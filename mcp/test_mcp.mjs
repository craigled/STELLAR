// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// The MCP server (mcp/server.mjs) driven as an agent drives it: over stdin/stdout, one tool call at a time.
// A session that boots LTOS, lists /BIN, writes a file and reads it back three ways, edits one in NANO and
// sorts it, starts GALAXIA and leaves it with Esc, and runs a .lst on the bare firmware. Then the same
// session in a second server: every result must be the same text, to the machine cycle.
//     node mcp/test_mcp.mjs
import { connect } from './client.mjs';

let ok = true;
const report = (label, errs) => { console.log(label + ': ' + (errs.length ? 'FAIL' : 'OK')); errs.forEach(e => console.log('    ' + e)); ok = ok && !errs.length; };
const tail = r => JSON.stringify(r.text.slice(-300));
const NOTES = 'pear\napple\nfig\n';

async function session(check) {
  const c = await connect(), log = [];
  const call = async (name, args) => { const r = await c.call(name, args); log.push(name + ' ' + JSON.stringify(args || {}) + '\n' + r.text); return r; };
  const cursorLine = r => r.data.screen[r.data.cursor.row - 1];
  let r, e;

  e = [];
  const tools = await c.tools();
  if (c.init.serverInfo.name !== 'elf2k') e.push('initialize: ' + JSON.stringify(c.init));
  if (tools.length !== 15 || tools.some(t => !t.description || t.inputSchema.type !== 'object')) e.push('tools/list: ' + tools.map(t => t.name).join(' '));
  r = await call('status');
  if (!r.text.includes('The machine is off')) e.push('status before boot: ' + tail(r));
  r = await call('command', { line: 'DIR' });
  if (!r.isError) e.push('command before boot was not an error');
  check('the handshake, 15 tools, and the machine off until boot', e);

  e = [];
  r = await call('boot');
  if (r.data.stop !== 'waiting' || cursorLine(r) !== 'LTOS>') e.push('ended: ' + r.data.stop + ' ' + tail(r));
  if (!r.text.includes('LTOS 0.5 - LiteOS for the Elf2K')) e.push('no banner: ' + tail(r));
  if (!(r.data.elapsed_cycles > 0) || r.data.elapsed_seconds !== +(r.data.elapsed_cycles / 375000).toFixed(3)) e.push('time: ' + JSON.stringify(r.data));
  check('boot: LTOS 0.5 at its prompt, waiting for a key, the time counted in cycles', e);

  e = [];
  r = await call('command', { line: 'DIR /BIN' });
  const all = r.data.scrolled.concat(r.data.screen).join('\n');
  const files = /(\d+) files, (\d+) bytes/.exec(all);
  if (r.data.stop !== 'waiting' || cursorLine(r) !== 'LTOS>') e.push('ended: ' + r.data.stop + ' ' + tail(r));
  for (const name of ['SORT     PRG', 'NANO     PRG', 'GALAXIA  STL', 'WALK     STL']) if (!all.includes(name)) e.push('DIR /BIN has no ' + name);
  if (!r.data.scrolled.length) e.push('nothing kept from above the screen');
  const bin = (await call('list_files', { path: '/BIN' })).data.entries;
  if (!files || +files[1] !== bin.length || +files[2] !== bin.reduce((n, f) => n + f.size, 0)) e.push('DIR says ' + (files && files[0]) + ', the card image holds ' + bin.length + ' files');
  check('DIR /BIN: every line kept, and its count and bytes are the card image\'s (' + (files && files[0]) + ')', e);

  e = [];
  r = await call('write_file', { path: 'NOTES.TXT', text: NOTES });
  if (r.isError || !r.data.saved || cursorLine(r) !== 'LTOS>') e.push('write_file: ' + tail(r));
  r = await call('read_file', { path: '/NOTES.TXT' });
  if (r.text !== NOTES) e.push('read_file: ' + JSON.stringify(r.text));
  r = await call('command', { line: 'TYPE NOTES.TXT' });
  if (!r.data.screen.join('\n').includes('LTOS> TYPE NOTES.TXT\npear\napple\nfig\nLTOS>')) e.push('TYPE: ' + tail(r));
  r = await call('write_file', { path: 'NOTES.TXT', text: 'other\n' });
  if (!r.isError || !r.text.includes('replace: true')) e.push('a second write_file was not refused: ' + tail(r));
  r = await call('command', { line: 'ECHO made by ECHO > ECHO.TXT' });
  r = await call('read_file', { path: '/ECHO.TXT' });
  if (r.text.trim() !== 'made by ECHO') e.push('ECHO > ECHO.TXT then read_file: ' + JSON.stringify(r.text));
  check('write_file (RECV, Intel HEX) read back from the card image and by TYPE; no replace unasked; ECHO > seen in the image', e);

  e = [];
  r = await call('command', { line: 'NANO LIST.TXT' });
  if (!/NANO 1\.1\s+LIST\.TXT/.test(r.data.screen[23])) e.push('NANO did not start: ' + tail(r));
  r = await call('type', { text: NOTES });
  if (r.data.screen.slice(0, 3).join(',') !== 'pear,apple,fig' || !r.data.screen[23].includes('Modified')) e.push('typed: ' + tail(r));
  r = await call('press', { keys: ['Ctrl-O'] });
  if (!r.data.screen[23].includes('Wrote 15 bytes to LIST.TXT')) e.push('Ctrl-O: ' + tail(r));
  r = await call('press', { keys: ['Ctrl-X'] });
  if (cursorLine(r) !== 'LTOS>') e.push('Ctrl-X: ' + tail(r));
  r = await call('command', { line: 'SORT LIST.TXT' });
  if (!r.data.screen.join('\n').includes('LTOS> SORT LIST.TXT\napple\nfig\npear\nLTOS>')) e.push('SORT: ' + tail(r));
  check('NANO: three lines typed, Ctrl-O, Ctrl-X; SORT puts them in order', e);

  e = [];
  r = await call('launch_app', { name: 'GALAXIA' });
  if (!r.text.includes('G  A  L  A  X  I  A') || !r.text.includes('Press any key to start')) e.push('the title: ' + tail(r));
  r = await call('vm_core', { vm: 1 });
  if (!r.text.startsWith('VM1: active') || !(r.data.commands > 0)) e.push('vm_core: ' + tail(r));
  r = await call('command', { line: 'DIR' });
  if (!r.isError) e.push('command inside an app was not an error');
  r = await call('press', { keys: ['Space'], max_seconds: 1 });
  if (!r.data.screen[0].includes('STELLAR GALAXIA') || !r.data.screen[0].includes('SCORE 00000') || !r.text.includes('/^\\')) e.push('the game: ' + tail(r));
  r = await call('press', { keys: ['Esc'] });
  if (!r.text.includes('Thanks for playing STELLAR GALAXIA.') || r.data.stop !== 'waiting' || cursorLine(r) !== 'LTOS>') e.push('Esc: ' + r.data.stop + ' ' + tail(r));
  check('GALAXIA from LTOS: the title, VM1 active, the game drawn, a lone Esc back to LTOS>', e);

  e = [];
  r = await call('boot');
  r = await call('list_files', { path: '/' });
  if (!r.text.includes('NOTES.TXT') || !r.text.includes('LIST.TXT')) e.push('after boot the card lost its files: ' + tail(r));
  r = await call('boot', { restore_card: true });
  r = await call('list_files', { path: '/' });
  if (r.text.includes('NOTES.TXT') || !r.text.includes('README.TXT')) e.push('restore_card: ' + tail(r));
  r = await call('command', { line: 'TIME' });
  if (!/LTOS> TIME\n12:00:0\d\n/.test(r.data.screen.join('\n'))) e.push('TIME after boot: ' + tail(r));
  check('boot keeps the card, restore_card puts it back; the clock starts at 12:00:00 and runs on cycles', e);

  e = [];
  r = await call('stellar_load', { programs: [{ sample: 'Prime-Gen-v07.lst' }] });
  if (r.data.stop !== 'waiting' || !r.text.includes('Low limit:')) e.push('ended: ' + r.data.stop + ' ' + tail(r));
  r = await call('type', { text: '3\n60\n', max_seconds: 60 });
  if (r.data.stop !== 'halted' || !r.text.includes('3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59')) e.push('primes: ' + r.data.stop + ' ' + tail(r));
  r = await call('stellar_load', { programs: [{ sample: 'sched-count1' }, { sample: 'sched-count2' }, { sample: 'sched-count3' }] });
  if (!r.text.includes('1 2 3 2 4 6 3 6 9 4 8 12 5 10 15 6 12 18')) e.push('three VMs: ' + tail(r));
  r = await call('peek', { address: '$5000', length: 16 });
  if (!/^5000  ([0-9A-F]{2} ){15}[0-9A-F]{2}  /.test(r.text) || /^5000  (00 ){15}00/.test(r.text)) e.push('peek $5000: ' + tail(r));
  check('bare STELLAR: Prime-Gen v07 prints its primes and the 1802 stops; three VMs take turns; peek', e);

  c.close();
  return log.join('\n\n');
}

const first = await session(report);
const second = await session(() => {});
{
  const e = [];
  if (first !== second) {
    let i = 0; while (i < first.length && first[i] === second[i]) i++;
    e.push('the sessions part at ' + i + ': ' + JSON.stringify(first.slice(Math.max(0, i - 80), i + 80)) + ' / ' + JSON.stringify(second.slice(Math.max(0, i - 80), i + 80)));
  }
  report('the same session in a second server: the same ' + first.length + ' characters, every cycle count with them', e);
}

console.log('\nELF2K MCP: ' + (ok ? 'ALL PASS' : 'FAILURES'));
process.exit(ok ? 0 : 1);
