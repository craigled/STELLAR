#!/usr/bin/env node
// Copyright (C) 2026 Joshua Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// An MCP server for the emulated Elf2K: an AI agent boots LTOS, types at the terminal, reads the screen,
// moves files on and off the card, starts STELLAR apps and looks at memory. JSON-RPC 2.0 on stdin/stdout,
// one message a line; nothing to install.
//     claude mcp add elf2k -- node /path/to/STELLAR/mcp/server.mjs
import { createInterface } from 'node:readline';
import { Elf2K, CYCLES_PER_SECOND, DEFAULT_CLOCK, keyBytes, textBytes, samples, sampleText, VM_STATES, h2, h4 } from './elf2k.mjs';

const PROTOCOLS = ['2025-06-18', '2025-03-26', '2024-11-05'];
const MAX_SECONDS = 600;                       // the most Elf2K time one call may run
const elf = new Elf2K();

const INSTRUCTIONS =
  'An RCA 1802 computer (a COSMAC Elf 2000 at 3 MHz) running Craig Ledbetter\'s real firmware: LTOS, a disk ' +
  'operating system with a Unix-like shell, and STELLAR, a multitasking virtual machine. Start with boot, then ' +
  'command("HELP") and command("DIR /BIN"). The terminal is a VT100, 24 rows of 80. Esc leaves every app. ' +
  'Time is the Elf2K\'s own, counted in machine cycles (375,000 a second), and every result says how much passed. ' +
  'A result ends "waiting for a key" when the machine has gone quiet and is asking the keyboard; "time ran out" ' +
  'means it was still busy or still drawing, so look at the screen and call run or press again.';

// ---- the tools ----
const seconds = (dflt, what) => ({ type: 'number', description: (what || 'The most Elf2K time to run, in seconds') + ' (default ' + dflt + ', at most ' + MAX_SECONDS + ').' });
const TOOLS = [
  { name: 'boot',
    description: 'Power on and boot LTOS from the card to its LTOS> prompt. Call it first, and again for a reset. Files written to the card are kept across boots until restore_card.',
    props: { restore_card: { type: 'boolean', description: 'Put every file on the card back as it was baked.' },
             clock: { type: 'string', description: 'What the real-time clock says at power-on (default ' + DEFAULT_CLOCK + '). It then runs on machine cycles.' },
             authentic_uart: { type: 'boolean', description: 'The Elf2K\'s own UART: it holds ONE byte at 19200 baud, so keys sent faster than a program reads them are lost. Default: off, keys queue.' } } },
  { name: 'command',
    description: 'Type a line at the LTOS> prompt, press Enter, and run until the machine waits for a key again. Returns what was printed (lines that scrolled off the top too) and the screen. For LTOS commands: HELP, DIR /BIN, TYPE README.TXT, SORT -r DOCS/SALES.TXT, ECHO hello > HI.TXT.',
    props: { line: { type: 'string', description: 'The command, without the Enter.' }, max_seconds: seconds(60) },
    required: ['line'] },
  { name: 'type',
    description: 'Type text at the terminal as it is, then run until the machine waits for a key. A newline in the text is Enter. For text typed into an editor or a program\'s own prompt.',
    props: { text: { type: 'string' }, enter: { type: 'boolean', description: 'Press Enter after the text.' }, max_seconds: seconds(30) },
    required: ['text'] },
  { name: 'press',
    description: 'Press named keys, in order, then run until the machine waits for a key. Keys: Enter, Esc, Tab, Space, Backspace, Delete, Up, Down, Left, Right, Home, End, PageUp, PageDown, Ctrl-A to Ctrl-Z, or one character such as "y". Esc leaves every app. In a game, give a small max_seconds (0.2) to move a step at a time.',
    props: { keys: { type: 'array', items: { type: 'string' }, description: 'For example ["Ctrl-O", "Enter", "Ctrl-X"].' }, max_seconds: seconds(5) },
    required: ['keys'] },
  { name: 'run',
    description: 'Let the machine run with no keys: for a program that is still working (FSCK, PI) or to watch a game or a clock move.',
    props: { seconds: seconds(10, 'How long to run, in seconds of Elf2K time'),
             stop_when_waiting: { type: 'boolean', description: 'Stop early once the machine waits for a key (default true). False runs the whole time, for programs that animate while they wait.' } } },
  { name: 'screen',
    description: 'The terminal now: 24 rows of 80 as text, and where the cursor is. Runs nothing. A reverse-video blank shows as a block (the apps draw pictures with them).',
    props: {} },
  { name: 'list_apps',
    description: 'The STELLAR apps: the .STL files in /BIN on the card (start one with launch_app) and the sample .lst programs for stellar_load.',
    props: {} },
  { name: 'launch_app',
    description: 'Start a STELLAR app from the LTOS> prompt by its name (GALAXIA, SNAKE, WALK, LW2 ...). LTOS loads the STELLAR firmware and the app. Esc comes back to LTOS.',
    props: { name: { type: 'string', description: 'An app from list_apps, with or without .STL.' }, max_seconds: seconds(30) },
    required: ['name'] },
  { name: 'stellar_load',
    description: 'The bare STELLAR firmware with no LTOS: cold-boot it with one to four .lst programs, the first in VM1, as the website\'s Simulator and Multitasking pages do, and run. All four VMs share the one terminal, as on the Elf2K. This replaces the LTOS machine until the next boot.',
    props: { programs: { type: 'array', minItems: 1, maxItems: 4, description: 'VM1 first.',
                         items: { type: 'object', properties: {
                           sample: { type: 'string', description: 'A file from web/samples, such as Mandelbrot.lst.' },
                           lst: { type: 'string', description: 'Or the text of a .lst: "D 4000 bb bb ..." lines, assembled for VM1 ($4000).' },
                           blocks: { type: 'integer', description: 'How many 4 KB blocks it takes (SETSIZE): 1 unless the app says otherwise.' } } } },
             clock: { type: 'string', description: 'The real-time clock at power-on (default ' + DEFAULT_CLOCK + ').' },
             max_seconds: seconds(5) },
    required: ['programs'] },
  { name: 'peek',
    description: 'Memory as hex and text. $0000-$2EFF the STELLAR firmware, $2F00 the CIDP, $3000 + (vm-1) x $400 a VM\'s core, $4000 $5000 $6000 $7000 the VMs\' program blocks, $8000-$FFFF the BIOS. (Under LTOS, programs load at $3000.)',
    props: { address: { type: 'string', description: 'Hex: "4000", "$4000" or "0x4000".' }, length: { type: 'integer', description: 'Bytes (default 64, at most 1024).' } },
    required: ['address'] },
  { name: 'vm_core',
    description: 'One STELLAR VM\'s state while STELLAR runs: its 16 registers, accumulator, math accumulator, flags, program location and command count, and its line in the CIDP.',
    props: { vm: { type: 'integer', description: '1 to 4 (default 1).' } } },
  { name: 'status',
    description: 'Which machine is on, the Elf2K time since power-on, the 1802\'s registers and next instruction, keys not yet read, sectors written to the card, and the STELLAR VMs if any.',
    props: {} },
  { name: 'list_files',
    description: 'A folder on the card, read straight from the card image as a PC would read it. Takes no Elf2K time. Paths start at the root: "/", "/BIN", "/DOCS".',
    props: { path: { type: 'string', description: 'Default "/".' } } },
  { name: 'read_file',
    description: 'A file from the card image, as text. Takes no Elf2K time. To have the 1802 do it, use command("TYPE name").',
    props: { path: { type: 'string', description: 'From the root, such as /DOCS/SALES.TXT.' }, hex: { type: 'boolean', description: 'Show it in hex, for a file that is not text.' } },
    required: ['path'] },
  { name: 'write_file',
    description: 'Put a file on the card, up to about 16 KB, the way a terminal program does: RECV at the LTOS> prompt, then the bytes as Intel HEX. LTOS itself writes the card. The path is as LTOS sees it from the current folder. Lines end as you give them (LTOS\'s own files use LF, or CR LF).',
    props: { path: { type: 'string', description: 'An 8.3 name, such as NOTES.TXT or DOCS/NOTES.TXT.' }, text: { type: 'string', description: 'The file\'s text.' },
             hex: { type: 'string', description: 'Or its bytes in hex, for a file that is not text.' },
             replace: { type: 'boolean', description: 'Answer Y when LTOS asks to replace a file already there (default: N, nothing saved).' } },
    required: ['path'] }
];

// ---- results ----
const secs = cycles => (cycles / CYCLES_PER_SECOND).toFixed(3);
const STOPS = { waiting: 'waiting for a key', time: 'time ran out (still busy or still drawing)', halted: 'the 1802 stopped (IDL)', until: 'done' };

// What every tool that touches the machine returns: the time that passed, why it stopped, the lines that
// scrolled off the top since the last result, and the screen.
function report(ran, note) {
  const s = elf.screen(), scrolled = elf.takeScrolled();
  let last = s.rows.length;
  while (last > 0 && !s.rows[last - 1]) last--;
  const head = '[' + (ran ? '+' + secs(ran.cycles) + ' s of Elf2K time (' + ran.cycles + ' cycles), ' : 'no time passed, ') +
    secs(elf.cpu.cycles) + ' s since power-on | ' + (ran ? STOPS[ran.stop] : (elf.cpu.halted ? STOPS.halted : elf.waiting ? STOPS.waiting : 'not waiting')) +
    ' | cursor row ' + s.cursor.row + ' col ' + s.cursor.col + (s.cursor.visible ? '' : ' (hidden)') + ']';
  const parts = [head];
  if (note) parts.push(note);
  if (scrolled.length) parts.push('---- scrolled off the top (' + scrolled.length + ' lines) ----', ...scrolled);
  parts.push('---- screen ----', ...s.rows.slice(0, last));
  return {
    text: parts.join('\n'),
    data: { elapsed_cycles: ran ? ran.cycles : 0, elapsed_seconds: ran ? +secs(ran.cycles) : 0, total_seconds: +secs(elf.cpu.cycles),
            stop: ran ? ran.stop : null, waiting: elf.waiting, cursor: s.cursor, scrolled, screen: s.rows }
  };
}
const plain = (text, data) => ({ text, data: data || {} });
const budget = (v, dflt) => Math.min(MAX_SECONDS, Math.max(0, typeof v === 'number' ? v : dflt));
function address(v) {
  const m = /^\s*(?:\$|0x)?([0-9a-f]{1,4})\s*$/i.exec(String(v));
  if (!m) throw new Error('address: want hex, such as 4000 or $2F00');
  return parseInt(m[1], 16);
}
function dump(bytes, at) {
  const lines = [];
  for (let o = 0; o < bytes.length; o += 16) {
    const row = Array.from(bytes.subarray(o, o + 16));
    lines.push(h4(at + o) + '  ' + row.map(h2).join(' ').padEnd(47) + '  ' + row.map(b => b >= 0x20 && b < 0x7F ? String.fromCharCode(b) : '.').join(''));
  }
  return lines.join('\n');
}
function stlApps() {
  return elf.cardList('/BIN').filter(e => !e.dir && e.name.endsWith('.STL')).map(e => e.name.replace(/\.STL$/, ''));
}
function vmLines() {
  const c = elf.cidp();
  const vms = c.vms.filter(v => v.num >= 1 && v.num <= 4 && v.corePage);
  return { cidp: c, lines: vms.map(v => 'VM' + v.num + ': ' + (VM_STATES[v.state] || 'state $' + h2(v.state)) + ', core $' + h2(v.corePage) + '00, program $' +
    h2(v.progPage) + '00, ' + v.cmds + ' commands run') };
}

const HANDLERS = {
  boot(a) {
    elf.bootLtos({ restoreCard: a.restore_card, clock: a.clock, authenticUart: a.authentic_uart });
    return report(elf.run(30), a.restore_card ? 'The card is as it was baked.' : null);
  },
  command(a) {
    if (elf.mode !== 'ltos') throw new Error('command is for the LTOS> prompt. Call boot first.');
    if (!elf.atPrompt()) throw new Error('The machine is not at the LTOS> prompt (see screen). Use type or press, or Esc to leave the program.');
    elf.type(textBytes(a.line + '\r'));
    return report(elf.run(budget(a.max_seconds, 60)));
  },
  type(a) {
    elf.type(textBytes(a.text + (a.enter ? '\r' : '')));
    return report(elf.run(budget(a.max_seconds, 30)));
  },
  press(a) {
    elf.type([].concat(...a.keys.map(keyBytes)));
    return report(elf.run(budget(a.max_seconds, 5)));
  },
  run(a) {
    return report(elf.run(budget(a.seconds, 10), { stopWhenWaiting: a.stop_when_waiting !== false }));
  },
  screen() { return report(null); },
  list_apps() {
    const apps = stlApps(), lst = samples();
    return plain('On the card, in /BIN (launch_app, from the LTOS> prompt):\n  ' + apps.join(' ') +
      '\n\nSample programs in web/samples (stellar_load):\n' + lst.map(s => '  ' + s.file.padEnd(26) + (s.blurb ? s.blurb.split('. ')[0].slice(0, 100) : '')).join('\n'),
      { card: apps, samples: lst.map(s => s.file) });
  },
  launch_app(a) {
    if (elf.mode !== 'ltos') throw new Error('launch_app starts an app from LTOS. Call boot first.');
    const name = String(a.name).toUpperCase().replace(/\.STL$/, '');
    if (!stlApps().includes(name)) throw new Error('There is no ' + name + '.STL in /BIN. list_apps shows them.');
    if (!elf.atPrompt()) throw new Error('The machine is not at the LTOS> prompt (see screen). Esc leaves the program that is running.');
    elf.type(textBytes(name + '\r'));
    return report(elf.run(budget(a.max_seconds, 30)));
  },
  stellar_load(a) {
    const programs = a.programs.map(p => {
      if (p.lst) return { name: 'pasted .lst', text: p.lst, blocks: p.blocks };
      if (!p.sample) throw new Error('each program wants "sample" or "lst"');
      return { ...sampleText(p.sample), blocks: p.blocks };
    });
    elf.bootStellar(programs, { clock: a.clock });
    return report(elf.run(budget(a.max_seconds, 5)), programs.map((p, i) => 'VM' + (i + 1) + ': ' + p.name).join(', '));
  },
  peek(a) {
    const at = address(a.address), bytes = elf.peek(at, Math.min(1024, Math.max(1, a.length || 64)));
    return plain(dump(bytes, at), { address: at, hex: Buffer.from(bytes).toString('hex') });
  },
  vm_core(a) {
    const vm = a.vm || 1;
    if (!(vm >= 1 && vm <= 4)) throw new Error('vm: 1 to 4');
    const { cidp } = vmLines(), entry = cidp.vms[vm - 1], k = elf.vmCore(vm);
    if (entry.num !== vm) {
      return plain('There is no VM' + vm + ' in the CIDP at $2F00: STELLAR is not running, or it made no VM' + vm +
        '. (Under LTOS, $3000 holds the program that is running.)', { running: false });
    }
    const text = [
      'VM' + vm + ': ' + (VM_STATES[entry.state] || 'state $' + h2(entry.state)) + ', core at $' + h4(0x3000 + (vm - 1) * 0x400) + ', program block $' + h2(entry.progPage) + '00' +
        (cidp.currentVM === vm ? ' (the VM running now)' : ''),
      'registers  ' + k.regs.slice(0, 8).map((r, i) => 'R' + i.toString(16).toUpperCase() + '=' + h4(r)).join(' '),
      '           ' + k.regs.slice(8).map((r, i) => 'R' + (i + 8).toString(16).toUpperCase() + '=' + h4(r)).join(' '),
      'ACC=' + h4(k.acc) + '  MA=' + k.maBytes.map(h2).join('') + ' rem ' + h4(k.maRem) + ' sign ' + h2(k.maSign) + '  DA=' + k.daBytes.map(h2).join(''),
      'PL=' + h4(k.pl) + ' (the command at it: $' + h2(k.cmd) + ')  commands run: ' + k.cmdCounter,
      'flags  test=' + k.flags.test + ' carry=' + k.flags.carry + ' overflow=' + k.flags.overflow + ' hexdec=' + k.flags.hexdec + '  memmode=' + k.memMode
    ].join('\n');
    return plain(text, { running: true, vm, state: entry.state, regs: k.regs, acc: k.acc, pl: k.pl, commands: k.cmdCounter });
  },
  status() {
    if (elf.mode === 'off') return plain('The machine is off. Call boot (LTOS) or stellar_load.', { mode: 'off' });
    const c = elf.cpuState(), lines = [];
    lines.push(elf.mode === 'ltos' ? 'LTOS on the Elf2K (web BIOS, the baked card' + (elf.m.authentic ? ', one-byte UART' : '') + ')'
                                   : 'Bare STELLAR: ' + elf.programs.map((p, i) => 'VM' + (i + 1) + ' ' + p).join(', '));
    lines.push(secs(elf.cpu.cycles) + ' s of Elf2K time since power-on (' + elf.cpu.cycles + ' machine cycles); the clock says ' +
      elf.cpu.rtc.now().toISOString().slice(0, 19).replace('T', ' '));
    lines.push(c.halted ? 'The 1802 has stopped (IDL).' : elf.waiting ? 'Waiting for a key.' : 'Running.');
    lines.push('1802: P=' + c.P.toString(16).toUpperCase() + ' X=' + c.X.toString(16).toUpperCase() + ' D=' + h2(c.D) + ' DF=' + c.DF + ' Q=' + c.Q +
      '  next at ' + h4(c.pc) + ': ' + c.next);
    lines.push('      ' + c.R.slice(0, 8).map((r, i) => 'R' + i.toString(16).toUpperCase() + '=' + h4(r)).join(' '));
    lines.push('      ' + c.R.slice(8).map((r, i) => 'R' + (i + 8).toString(16).toUpperCase() + '=' + h4(r)).join(' '));
    lines.push('Keys typed and not yet read: ' + elf.pending());
    lines.push('Card: ' + elf.written.size + ' sectors written since it was baked.');
    const vms = vmLines();
    if (elf.mode === 'stellar' || vms.lines.length) lines.push('STELLAR VMs (CIDP at $2F00' + (elf.mode === 'ltos' ? '; only true while a STELLAR app runs' : '') + '):', ...vms.lines.map(l => '  ' + l));
    return plain(lines.join('\n'), { mode: elf.mode, total_cycles: elf.cpu.cycles, total_seconds: +secs(elf.cpu.cycles), waiting: elf.waiting, halted: c.halted,
                                     pc: c.pc, pending_keys: elf.pending(), sectors_written: elf.written.size });
  },
  list_files(a) {
    const list = elf.cardList(a.path || '/');
    const files = list.filter(e => !e.dir);
    return plain((a.path || '/') + '\n' + list.map(e => '  ' + e.name.padEnd(13) + (e.dir ? '   <DIR>' : String(e.size).padStart(8)) + '  ' + e.date + (e.hidden ? '  hidden' : '')).join('\n') +
      '\n  ' + files.length + ' files, ' + files.reduce((n, e) => n + e.size, 0) + ' bytes', { entries: list.map(({ cluster, ...e }) => e) });
  },
  read_file(a) {
    const bytes = elf.cardRead(a.path);
    if (a.hex) return plain(dump(bytes.subarray(0, 4096), 0) + (bytes.length > 4096 ? '\n(the first 4096 of ' + bytes.length + ' bytes)' : ''), { size: bytes.length });
    const text = bytes.toString('latin1').replace(/\r\n/g, '\n');
    return plain(text.length > 20000 ? text.slice(0, 20000) + '\n(the first 20000 of ' + bytes.length + ' bytes)' : text, { size: bytes.length });
  },
  write_file(a) {
    if ((a.text === undefined) === (a.hex === undefined)) throw new Error('give text or hex, one of them');
    const bytes = a.hex !== undefined ? Buffer.from(a.hex.replace(/[\s,$]/g, ''), 'hex') : Buffer.from(textBytesExact(a.text));
    const r = elf.cardWrite(String(a.path).toUpperCase(), bytes, a.replace);
    const note = r.saved ? 'Saved: ' + bytes.length + ' bytes.'
      : r.exists ? 'NOT saved: the file is already on the card. Call again with replace: true.' : 'NOT saved: see what LTOS said below.';
    const out = report({ stop: 'waiting', cycles: r.cycles }, note);
    out.data.saved = r.saved;
    out.isError = !r.saved;
    return out;
  }
};
function textBytesExact(text) {
  return Array.from(String(text), ch => {
    const c = ch.codePointAt(0);
    if (c > 0xFF) throw new Error('LTOS text is 8-bit: cannot store ' + JSON.stringify(ch));
    return c;
  });
}

// ---- JSON-RPC over stdio ----
function handle(msg) {
  const { id, method, params } = msg;
  const result = r => ({ jsonrpc: '2.0', id, result: r });
  if (method === 'initialize') {
    const want = params && params.protocolVersion;
    return result({ protocolVersion: PROTOCOLS.includes(want) ? want : PROTOCOLS[0], capabilities: { tools: {} },
                    serverInfo: { name: 'elf2k', version: '0.1.0' }, instructions: INSTRUCTIONS });
  }
  if (method === 'ping') return result({});
  if (method === 'tools/list') {
    return result({ tools: TOOLS.map(t => ({ name: t.name, description: t.description,
                                             inputSchema: { type: 'object', properties: t.props, required: t.required || [] } })) });
  }
  if (method === 'tools/call') {
    const fn = HANDLERS[params && params.name], args = (params && params.arguments) || {};
    if (!fn) return { jsonrpc: '2.0', id, error: { code: -32602, message: 'Unknown tool: ' + (params && params.name) } };
    try {
      const missing = (TOOLS.find(t => t.name === params.name).required || []).filter(k => args[k] === undefined);
      if (missing.length) throw new Error(params.name + ' needs: ' + missing.join(', '));
      const r = fn(args);
      return result({ content: [{ type: 'text', text: r.text }], structuredContent: r.data, isError: !!r.isError });
    } catch (e) {
      return result({ content: [{ type: 'text', text: e.message }], isError: true });
    }
  }
  if (id === undefined) return null;             // a notification
  return { jsonrpc: '2.0', id, error: { code: -32601, message: 'Method not found: ' + method } };
}

createInterface({ input: process.stdin }).on('line', line => {
  if (!line.trim()) return;
  let reply;
  try { reply = handle(JSON.parse(line)); }
  catch (e) { reply = { jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error: ' + e.message } }; }
  if (reply) process.stdout.write(JSON.stringify(reply) + '\n');
});
