// Drive the real VM through the real VT100 and see what the screen holds.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const require = createRequire(import.meta.url);
const WEB = join(dirname(fileURLToPath(import.meta.url)), '..');
const firmware = require(join(WEB,'js','firmware-0061-35.js'));
const { StellarVM } = require(join(WEB,'js','stellar-vm.js'));
const VT100 = require(join(WEB,'js','vt100.js'));
const manifest = JSON.parse(readFileSync(join(WEB,'samples','manifest.json'),'utf8'));

function screen(vt) {
  // read the grid straight off the emulator: '#' for a reverse-video cell (that is
  // how the pictures are drawn), otherwise the character itself
  return vt.grid.map(row => row.map(c => c.rev ? '#' : c.ch).join('').replace(/\s+$/, ''));
}

for (const name of ['Starfield.lst','Starship.lst','Bouncing-Ball.lst','Invaders.lst']) {
  const s = manifest.find(m => m.file === name);
  const lst = readFileSync(join(WEB,'samples',name),'utf8');
  const vm = new StellarVM({ firmware, program: lst, input: s.input, coldBoot: true });
  vm.runToSerial(s.maxSteps);
  const out = vm.serialOut();
  const el = { textContent:'', innerHTML:'', scrollTop:0, scrollHeight:0 };
  const vt = VT100(el);
  vt.write(out); vt.render();
  const rows = screen(vt);
  const cells = rows.join('').replace(/ /g,'').length;
  console.log('--- ' + name + '  (' + out.length + ' bytes out, ' + cells + ' cells painted) ---');
  rows.forEach(r => { if (r.trim()) console.log('  |' + r); });
}
