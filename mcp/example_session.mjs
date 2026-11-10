// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// Makes mcp/EXAMPLE-SESSION.md: a session with the MCP server, each tool call sent over stdin/stdout to a
// real server.mjs and each result written down as it came back. The calls and the notes are Claude's.
//     node mcp/example_session.mjs
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { connect } from './client.mjs';

const STEPS = [
  ['Power on.', 'boot', {}],
  ['What is this?', 'command', { line: 'VER' }],
  ['A file to work on. STELLAR has four VMs, each with a core and a program block; I will type them into NANO out of order.',
   'command', { line: 'NANO VMS.TXT' }],
  ['A newline in the text is the Enter key. NANO redraws as it goes, so 108 keys take a few seconds of the Elf2K\'s time.', 'type', { text: 'VM3 core 3800 program 6000\nVM1 core 3000 program 4000\nVM4 core 3C00 program 7000\nVM2 core 3400 program 5000\n' }],
  ['Ctrl-O writes the file, Ctrl-X leaves.', 'press', { keys: ['Ctrl-O', 'Ctrl-X'] }],
  ['The 1802 sorts it.', 'command', { line: 'SORT VMS.TXT' }],
  ['Which VM has the block at $6000?', 'command', { line: 'GREP -n 6000 VMS.TXT' }],
  ['awk, in 1802 code: the first and last word of each line.', 'command', { line: "RAWK '{ print $1, $5 }' VMS.TXT" }],
  ['Sorted the other way, into a new file.', 'command', { line: 'SORT -r VMS.TXT > DOWN.TXT' }],
  ['That file, read from the card image itself and not through LTOS. No Elf2K time passes.', 'read_file', { path: '/DOWN.TXT' }],
  ['A game. LTOS loads the STELLAR firmware and the app.', 'launch_app', { name: 'GALAXIA' }],
  ['Any key starts it. One second of the Elf2K\'s time, then stop and look.', 'press', { keys: ['Space'], max_seconds: 1 }],
  ['Three steps left, fire, and a second and a half for the shot to get there.', 'press', { keys: ['Left', 'Left', 'Left', 'Space'], max_seconds: 1.5 }],
  ['The game is a STELLAR program in VM1. Its core should be where VMS.TXT says: $3000, with the program at $4000.', 'vm_core', { vm: 1 }],
  ['The first bytes of that core, as they sit in memory.', 'peek', { address: '$3000', length: 32 }],
  ['Esc quits every app.', 'press', { keys: ['Esc'] }],
  ['Now the bare firmware with no LTOS, and one sample program in VM1.', 'stellar_load', { programs: [{ sample: 'Mandelbrot.lst' }], max_seconds: 60 }],
  ['It is still drawing. Let it finish.', 'run', { seconds: 600 }],
  ['Where everything stands.', 'status', {}]
];

const c = await connect();
const out = [
  '# An example session',
  '',
  'Claude using the Elf2K through `mcp/server.mjs`. Every block below is what the server sent back, unedited.',
  'Made by `node mcp/example_session.mjs`, which starts the server, sends these ' + STEPS.length + ' tool calls over stdin/stdout',
  'and writes down the results. The calls and the notes above them are Claude\'s. Run it again and you get the',
  'same file, to the machine cycle.',
  ''
];
let n = 0;
for (const [note, name, args] of STEPS) {
  const r = await c.call(name, args);
  if (r.isError) { console.error('step ' + (n + 1) + ' ' + name + ' failed: ' + r.text); process.exit(1); }
  out.push('## ' + (++n) + '. ' + name + ' ' + JSON.stringify(args), '', note, '', '```', r.text.replace(/\n+$/, ''), '```', '');
}
c.close();
const file = join(dirname(fileURLToPath(import.meta.url)), 'EXAMPLE-SESSION.md');
writeFileSync(file, out.join('\n'));
console.log(n + ' calls, written to ' + file);
