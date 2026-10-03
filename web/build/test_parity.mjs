// Parity test: the JS STELLAR engine must reproduce the Python firmware sim's
// serial output byte-for-byte for every sample. Run:
//     node web/build/test_parity.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const WEB = join(HERE, '..');

const firmware = require(join(WEB, 'js', 'firmware-0061-35.js'));
const { StellarVM } = require(join(WEB, 'js', 'stellar-vm.js'));

const manifest = JSON.parse(readFileSync(join(WEB, 'samples', 'manifest.json'), 'utf8'));
const fixtures = JSON.parse(readFileSync(join(HERE, 'fixtures.json'), 'utf8'));

function toHex(u8) {
  let s = '';
  for (const b of u8) s += b.toString(16).padStart(2, '0');
  return s;
}

let pass = 0, fail = 0;
for (const s of manifest) {
  const fx = fixtures[s.file];
  if (!fx) { console.log(`SKIP ${s.file} (no fixture — run gen_fixtures.py)`); continue; }
  const lst = readFileSync(join(WEB, 'samples', s.file), 'utf8');
  const vm = new StellarVM({ firmware, program: lst, input: s.input, coldBoot: true });
  vm.runToSerial(s.maxSteps);
  const got = toHex(vm.serialOut());
  if (got === fx.outHex) {
    console.log(`PASS ${s.file.padEnd(22)} ${fx.bytes} bytes`);
    pass++;
  } else {
    console.log(`FAIL ${s.file}`);
    console.log(`  expected (${fx.outHex.length / 2}b): ${fx.outHex.slice(0, 80)}…`);
    console.log(`  got      (${got.length / 2}b): ${got.slice(0, 80)}…`);
    // first diff
    const n = Math.min(got.length, fx.outHex.length);
    let i = 0; while (i < n && got[i] === fx.outHex[i]) i++;
    console.log(`  first diff at byte ${Math.floor(i / 2)}`);
    fail++;
  }
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
