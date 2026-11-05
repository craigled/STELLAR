// The LTOS page's machine (js/elf2k.js + the web BIOS + the baked card) against the Python Elf2K: the same
// commands, typed one at each prompt, must print exactly the same text (build/ltos-session.json, made by
// build/ltos_ref.py from the same card). Then: a STELLAR app (GALAXIA) starts and a lone Esc brings LTOS back, and a
// card written to and put back ("Restore the card") is the baked one again.
//     node web/build/test_ltos.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const WEB = join(HERE, '..');
const firmware = require(join(WEB, 'js', 'firmware-0061-37.js'));
const E = require(join(WEB, 'js', 'elf2k.js'));
const b64 = /LTOS_WEBBIOS = "([^"]+)"/.exec(readFileSync(join(WEB, 'js', 'webbios.js'), 'utf8'))[1];
const bios = Uint8Array.from(Buffer.from(b64, 'base64'));
const raw = readFileSync(join(WEB, 'ltos', 'ltos-card.bin'));
const ref = JSON.parse(readFileSync(join(HERE, 'ltos-session.json'), 'utf8'));
let ok = true;
const report = (label, errs) => { console.log(label + ': ' + (errs.length ? 'FAIL' : 'OK')); errs.forEach(e => console.log('    ' + e)); ok = ok && !errs.length; };

// the Python test clock (verify_phase3.clock): BCD, 2026-10-16 14:30:20
function clock([y, mo, d, h, mi, s]) {
  const bcd = v => parseInt(String(v), 16);
  const regs = { 0x0A: 0, 0x0B: 0x02, 0: bcd(s), 2: bcd(mi), 4: bcd(h), 7: bcd(d), 8: bcd(mo), 9: bcd(y) };
  return { read: r => regs[r] || 0, write: () => {} };
}

// a machine that types each [prompt, keys] once the prompt has been printed - as the Python UART's `later`
function machine(later, card) {
  E.setModel('SanDisk SDCFB-128');
  const out = [];
  const base = E.parseCard(raw);
  const m = new E.Machine({ bios, firmware, sectors: base.sectors, card: card || base.map, onOutput: b => out.push(b) });
  m.cpu.rtc = clock(ref.clock);
  let seen = 0;
  const pop = m.cpu.io_in[3].pop, sel = m.cpu.io_out[2];
  m.cpu.io_in[3].pop = function () {
    const s = sel[0];
    if ((s === 0x10 || s === 0x15) && !m.uart.buf.length && later.length) {
      const text = Buffer.from(out).toString('latin1'), i = text.indexOf(later[0][0], seen);
      if (i >= 0) { seen = i + later[0][0].length; m.keys(Buffer.from(later.shift()[1], 'latin1')); }
    }
    return pop.call(this);
  };
  m.text = () => Buffer.from(out).toString('latin1');
  return m;
}
function runTo(m, stop, cap, done) {
  const c = m.cpu;
  for (let i = 0; i < cap; i++) {
    if (c.R[c.P] === stop) return 'stop';
    if (!c.step()) return 'idle';
    if (done && (i & 0xFFFF) === 0 && done()) return 'done';
  }
  return 'cap';
}

// 1. the same session as the Python Elf2K
{
  const later = ref.commands.map(k => ['LTOS> ', k + '\r']).concat([['LTOS> ', 'MON\r']]);
  const m = machine(later);
  const st = runTo(m, 0x8003, 400_000_000), t = m.text(), e = [];
  if (st !== 'stop') e.push('ended: ' + st + ' ' + JSON.stringify(t.slice(-300)));
  if (t !== ref.text) {
    let i = 0; while (i < t.length && t[i] === ref.text[i]) i++;
    e.push('the text parts at ' + i + ': Python ' + JSON.stringify(ref.text.slice(Math.max(0, i - 60), i + 60)) +
           ', JS ' + JSON.stringify(t.slice(Math.max(0, i - 60), i + 60)));
  }
  report(ref.commands.length + ' commands on the baked card: exactly the Python Elf2K\'s text (' + ref.text.length + ' characters)', e);
}

// 2. a STELLAR app and back; 3. the card restored
{
  const m = machine([['LTOS> ', 'RM README.TXT\r'], ['LTOS> ', 'ECHO new > NEW.TXT\r'], ['LTOS> ', 'GALAXIA\r'],
                     ['any key to start', ' '], ['SPACE: fire', '\x1b'], ['LTOS> ', 'DIR\r']]);
  const st = runTo(m, 0xFFFF, 600_000_000, () => /DIR\r?\n[\s\S]*LTOS> $/.test(m.text())), t = m.text(), e = [];
  const dir = t.slice(t.lastIndexOf('LTOS> DIR'));
  if (!t.includes('G  A  L  A  X  I  A') || !t.includes('Thanks for playing STELLAR GALAXIA.')) e.push('Galaxia: ' + JSON.stringify(t.slice(-400)));
  if (t.split('LTOS 0.5 - LiteOS').length < 3) e.push('LTOS did not come back after Esc');
  if (!dir.includes('NEW') || dir.includes('README')) e.push('DIR after RM / ECHO: ' + JSON.stringify(dir.slice(0, 400)));
  report('RM README.TXT, ECHO > NEW.TXT, GALAXIA, Esc back to LTOS, DIR', e);
  const e2 = [];
  if (!m.cf.dirty.size) e2.push('nothing written');
  const fresh = machine([['LTOS> ', 'DIR\r'], ['LTOS> ', 'MON\r']]);       // what "Restore the card" boots: the baked map
  runTo(fresh, 0x8003, 200_000_000);
  const d2 = fresh.text().slice(fresh.text().lastIndexOf('LTOS> DIR'));
  if (!d2.includes('README') || d2.includes('NEW')) e2.push('restored DIR: ' + JSON.stringify(d2.slice(0, 400)));
  report('restored: README.TXT back, NEW.TXT gone (' + m.cf.dirty.size + ' sectors had been written)', e2);
}

console.log('\nLTOS WEB: ' + (ok ? 'ALL PASS' : 'FAILURES'));
process.exit(ok ? 0 : 1);
