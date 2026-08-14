// Disassembler parity: disasm.js must produce the same instruction stream
// (address + mnemonic, up to the end marker) as tools/stellar_disasm.py for
// every app in the work repo. Run:  node web/build/test_disasm.mjs
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';
import { homedir, tmpdir } from 'node:os';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const WEB = join(HERE, '..');
const opcodes = require(join(WEB, 'js', 'opcodes.js')).opcodes;
const { disassemble } = require(join(WEB, 'js', 'disasm.js'));
const { parseLst } = require(join(WEB, 'js', 'stellar-vm.js'));

const PYTOOL = join(homedir(), 'Projects', 'stellar-1802', 'tools', 'stellar_disasm.py');
const APPDIR = join(homedir(), 'Projects', 'stellar-1802', 'APPLICATIONS');
const TMP = join(tmpdir(), 'parity.dis');

// build a 64K image from an .lst and return {mem, lo, hi} of the first run.
// Runs are grouped by WRITTEN-ADDRESS contiguity (like the Python tool) — a $00
// operand byte is written and must not be treated as a gap.
function image(lstText) {
  const mem = new Uint8Array(0x10000);
  const written = [];
  parseLst(lstText).forEach(([a, b]) => { mem[a] = b; written.push(a); });
  const addrs = Array.from(new Set(written)).sort((x, y) => x - y);
  const lo = addrs[0];
  let hi = lo;
  for (let i = 1; i < addrs.length && addrs[i] === hi + 1; i++) hi = addrs[i];
  return { mem, lo, hi };
}

// parse the Python .dis: code lines are "AAAA  bytes...  MNEMONIC ..." before data/label sections
function parsePy(dis) {
  const out = [];
  for (const ln of dis.split('\n')) {
    if (ln.startsWith('; ---') || ln.startsWith('; label index')) break;
    const m = /^([0-9A-Fa-f]{4})  (?:[0-9A-Fa-f]{2}(?: [0-9A-Fa-f]{2})*)\s+(\S+)/.exec(ln);
    if (m) out.push([parseInt(m[1], 16), m[2]]);
  }
  return out;
}

const apps = readdirSync(APPDIR).filter(f => f.endsWith('.lst'));
let pass = 0, fail = 0;
for (const app of apps) {
  const path = join(APPDIR, app);
  execFileSync('python3', [PYTOOL, path, TMP]);
  const py = parsePy(readFileSync(TMP, 'utf8'));
  const { mem, lo, hi } = image(readFileSync(path, 'utf8'));
  const js = disassemble(mem, lo, hi, opcodes).lines.map(l => [l.addr, l.name]);

  let ok = js.length === py.length;
  let where = -1;
  if (ok) for (let i = 0; i < py.length; i++) {
    if (js[i][0] !== py[i][0] || js[i][1] !== py[i][1]) { ok = false; where = i; break; }
  }
  if (ok) { pass++; }
  else {
    fail++;
    console.log(`FAIL ${app}: js=${js.length} py=${py.length} lines` +
      (where >= 0 ? `, first diff @${where}: js=${js[where]} py=${py[where]}` : ''));
  }
}
console.log(`\n${pass} passed, ${fail} failed  (of ${apps.length} apps)`);
process.exit(fail ? 1 : 0);
