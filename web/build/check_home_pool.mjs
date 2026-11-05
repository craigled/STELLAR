// Check every app in web/samples/home-pool.json in every home-page slot (VM1-VM4), beside three
// other pool apps (a two-block app: in VM1+VM2, three times, beside two others), in the real home-page machine (js/machine.js): its screen gets output, no VM
// reports an error, all four keep running, and a RUN after it finishes restarts it without
// disturbing the others.      node web/build/check_home_pool.mjs
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const WEB = join(dirname(fileURLToPath(import.meta.url)), '..');
const FW = require(join(WEB, 'js', 'firmware-0061-37.js'));
const Machine = require(join(WEB, 'js', 'machine.js'));
const pool = JSON.parse(readFileSync(join(WEB, 'samples', 'home-pool.json'), 'utf8'));
const text = {};
for (const p of pool) text[p.file] = readFileSync(join(WEB, 'samples', p.file), 'latin1');
// A two-block app (SETSIZE 2, "blocks": 2 - Life Lab) always runs in VM1 with VM2's slot empty, as
// js/home.js places it: it is tried three times, each with two different companions in VM3 / VM4.
const LENT = { name: '(lent)', file: null, input: '', lent: true };
const small = pool.filter(p => (p.blocks || 1) === 1);
const CPS = 375000, SECS = +(process.argv[2] || 8);
const ccount = (M, vm) => { const b = 0x3000 + (vm - 1) * 0x400 + 0x33; return M[b] * 16777216 + (M[b + 1] << 16) + (M[b + 2] << 8) + M[b + 3]; };
let fails = 0, n = 0, seed = 1802;
const rnd = k => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % k; };
for (const app of pool) {
  const row = [];
  const big = app.blocks === 2;
  for (let trial = 1; trial <= 4; trial++) {
    if (big && trial === 4) break;
    const slot = big ? 1 : trial;
    const others = small.filter(p => p !== app && !(big && p.heavy));   // home.js: one heavy app, the rest light
    const four = [];
    while (four.length < (big ? 2 : 3)) { const o = others[rnd(others.length)]; if (!four.includes(o)) four.push(o); }
    if (big) four.unshift(app, LENT); else four.splice(slot - 1, 0, app);
    const m = new Machine({ firmware: FW, programs: four.map(p => ({ text: p.lent ? '' : text[p.file], input: p.input, blocks: p.blocks || 1 })) });
    const outs = [0, 0, 0, 0, 0], c0 = [1, 2, 3, 4].map(v => ccount(m.M, v));
    for (let t = 0; t < SECS * 4; t++) {
      m.run(CPS / 4);
      for (let v = 1; v <= 4; v++) { const b = m.drain(v); if (b) outs[v] += b.length; }
    }
    const problems = [];
    for (let v = 1; v <= 4; v++) {
      if (four[v - 1].lent) { if (outs[v]) problems.push(`VM${v} is lent but printed`); continue; }
      const err = m.M[0x3000 + (v - 1) * 0x400 + 0x4F];
      if (err) problems.push(`VM${v} (${four[v - 1].name}) error $${err.toString(16)}`);
      if (!outs[v]) problems.push(`VM${v} (${four[v - 1].name}) printed nothing`);
      if (ccount(m.M, v) === c0[v - 1] && !m.vmFinished(v)) problems.push(`VM${v} (${four[v - 1].name}) stuck`);
    }
    if (m.halted && ![1, 2, 3, 4].every(v => four[v - 1].lent || m.vmFinished(v))) problems.push('machine halted');
    // RUN after finishing: restart it, the others carry on
    if (m.vmFinished(slot)) {
      const before = [1, 2, 3, 4].map(v => ccount(m.M, v));
      if (!m.rerun(slot)) problems.push('RUN refused');
      m.run(CPS);
      for (let v = 1; v <= 4; v++) if (v !== slot && !four[v - 1].lent && !m.vmFinished(v) && ccount(m.M, v) === before[v - 1]) problems.push(`RUN stopped VM${v}`);
      if (!m.drain(slot)) problems.push('RUN printed nothing');
    }
    n++;
    const where = big ? `VM1+2 with ${four[2].name}, ${four[3].name}` : `VM${slot}`;
    if (problems.length) { fails++; row.push(`${where}: ` + problems.join('; ')); }
    else row.push(`${where} ok${m.vmFinished(slot) ? ' (finished, RUN ok)' : ''}`);
  }
  console.log(`${app.name.padEnd(16)} ${row.join(' | ')}`);
}
console.log(`${n - fails}/${n} slot runs OK`);
process.exit(fails ? 1 : 0);
