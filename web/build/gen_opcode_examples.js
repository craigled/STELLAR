#!/usr/bin/env node
// Build web/js/opcode-examples.js from web/build/opcode-examples.txt.
//
//     node web/build/gen_opcode_examples.js [--check]
//
// Every example is assembled, RUN ON THE REAL FIRMWARE (js/firmware-0061-37.js in the same
// emulator the Simulator uses), and its `expect:` values are compared with what the machine
// did. One mismatch and nothing is written, so a program on the Opcodes page is one that
// has been seen to work. The ASSEMBLY column comes from the disassembler, not from the
// text file, so it can never disagree with the bytes.
//
// The text file, one example after another:
//   ## 04 05 | Title                    the opcodes it shows, first = the one it belongs to
//   src: T3                             the table in the TEST PROGRAMS document, or new
//   fix: what was wrong in the document (the page shows it, and so does the report)
//   note: what the example shows
//   run: sw=05 stop=40 ef4=1 serial=HI\r  input switches, opcodes to run, EF4 held, keys
//   expect: A=1234 R1=0034 MA=00001234 MAR=0002 DA=.. DAR=.. OUT=AA,BB Q=1 T=1 C=0 E=00
//           M4100=AA,BB SER=text VM2.R1=0005 (a ~ before = : shown on the page, not checked)
//   CD                                  one instruction a line: its bytes
//   10 AA BB ; a comment                the comment, or one is made from the bytes
//   loop:                               a label; {loop} = its address in the program block
//   B0 {loop}
//   @4100                               the next bytes go here
//   db 48 49 00 ; text                  data, not an instruction
//   ## - | Title                        a whole program: it goes at the end of the page
const fs = require('fs'), path = require('path');
const WEB = path.dirname(__dirname);
global.window = global;
require(path.join(WEB, 'js/opcodes.js'));
require(path.join(WEB, 'js/firmware-0061-37.js'));
const L = require(path.join(WEB, 'js/stellar-vm.js'));
const D = require(path.join(WEB, 'js/disasm.js'));
const OPS = window.STELLAR_OPCODES, BYOP = {};
OPS.forEach(o => { BYOP[o.op] = o; });
const hx = (v, n) => v.toString(16).toUpperCase().padStart(n, '0');
const ACC = ['the Accumulator', 'the Math Accumulator', 'the Decimal Accumulator'];
const R = n => 'R' + n.toString(16).toUpperCase();
const lo = b => b & 15, hi = b => b >> 4;

// The EXPLANATION column for a line with no comment of its own.
function explain(b) {
  const op = b[0], o = b.slice(1), w = (i) => hx(o[i], 2) + hx(o[i + 1], 2), x = o.length ? lo(o[0]) : 0, z = o.length ? hi(o[0]) : 0;
  const part = ['', ' (low byte only)', ' (high byte only)'];
  const shift = ['left', 'in a ring to the left', 'right', 'in a ring to the right'];
  const bytes = n => n + ' byte' + (n === 1 ? '' : 's');
  const T = {
    0x00: () => 'Halt: end the program', 0x01: () => 'Output goes to port ' + o[0], 0x02: () => 'Input comes from port ' + hx(o[0], 1),
    0x03: () => 'EF source = EF' + z + (x ? ', inverted' : ''), 0x04: () => 'Output ' + hx(o[0], 2),
    0x05: () => 'Output byte ' + x + ' of ' + ACC[z], 0x06: () => 'Output the ' + (z ? 'high' : 'low') + ' byte of ' + R(x),
    0x08: () => 'Output the byte at M(' + R(x) + ')', 0x09: () => 'Read the four EF lines into the Accumulator',
    0x0A: () => ['Q off', 'Q on', 'Q on, then off', 'Q on twice, then off twice'][x],
    0x0C: () => 'Read the input port now, into the Acc ' + (x ? 'high' : 'low') + ' byte',
    0x0D: () => 'Wait for the Input key, then read the input port into the Acc ' + (x ? 'high' : 'low') + ' byte',
    0x0E: () => 'Wait for the Input key, then read the input port into the ' + (z ? 'high' : 'low') + ' byte of ' + R(x),
    0x0F: () => x ? 'Wait until EF' + x + ' goes high and then low' : 'Wait for the Input key: EF goes high and then low',
    0x10: () => 'Load ' + w(0) + ' into the Accumulator',
    0x11: () => 'Load ' + (z === 1 ? hx(o[2], 2) + ' into the low byte of ' + R(x) : z === 2 ? hx(o[1], 2) + ' into the high byte of ' + R(x) : w(1) + ' into ' + R(x)),
    0x12: () => 'Load ' + bytes(z || 2) + ' into ' + ACC[x], 0x13: () => 'Copy the Acc low byte to its high byte', 0x14: () => 'Copy the low byte of ' + R(x) + ' to its high byte',
    0x15: () => 'Swap the Acc low and high bytes', 0x16: () => 'Swap the low and high bytes of ' + R(x), 0x17: () => 'Shift the MA one byte ' + shift[x],
    0x18: () => 'Set bit mask ' + hx(o[0], 2) + ' in the Acc low byte', 0x19: () => 'Reset bit mask ' + hx(o[0], 2) + ' in the Acc low byte', 0x1A: () => 'Test: are the bits in mask ' + hx(o[0], 2) + ' set in the Acc low byte?',
    0x20: () => 'Memory mode: ' + (x ? 'relative to this program block' : 'absolute'), 0x21: () => 'Copy ' + ACC[z] + ' to ' + R(x), 0x22: () => 'Copy ' + R(x) + ' to ' + ACC[z],
    0x23: () => 'Copy ' + R(hi(o[1])) + ' to ' + R(lo(o[1])) + part[x], 0x24: () => 'Copy the Accumulator to the low 2 bytes of the MA', 0x25: () => 'Copy the low 2 bytes of the MA to the Accumulator',
    0x27: () => 'Copy the MA Remainder to the Accumulator', 0x28: () => 'Copy the Command Counter to ' + ACC[x], 0x29: () => 'Copy the I/O byte to the Acc low byte', 0x2A: () => 'Copy the Acc low byte to the I/O byte', 0x2B: () => 'Copy the MA high word to the Accumulator',
    0x2E: () => 'Acc = M(' + w(1) + ' + ' + R(x) + ')', 0x2F: () => 'M(' + w(1) + ' + ' + R(x) + ') = the Acc low byte',
    0x31: () => 'Save ' + hx(o[1], 2) + ' at M(' + R(x) + ')', 0x32: () => 'Save ' + w(1) + ' at M(' + R(x) + ')', 0x33: () => 'Load ' + ACC[z] + ' from M(' + R(x) + ')', 0x34: () => 'Save ' + ACC[z] + ' at M(' + R(x) + ')',
    0x35: () => 'Load ' + bytes(lo(o[0])) + ' from M(' + R(lo(o[1])) + ') into ' + ACC[hi(o[1])], 0x36: () => 'Save ' + bytes(lo(o[0])) + ' of ' + ACC[hi(o[1])] + ' at M(' + R(lo(o[1])) + ')',
    0x37: () => 'Load ' + bytes(z) + ' from M(' + R(lo(o[1])) + ') into ' + ACC[hi(o[1])] + ', from its byte ' + x, 0x38: () => 'Save ' + bytes(z) + ' of ' + ACC[hi(o[1])] + ', from its byte ' + x + ', at M(' + R(lo(o[1])) + ')',
    0x39: () => 'Load ' + bytes(x) + ' from M(' + R(hi(o[1])) + ') into ' + R(lo(o[1])), 0x3A: () => 'Save ' + bytes(x) + ' of ' + R(hi(o[1])) + ' at M(' + R(lo(o[1])) + ')',
    0x3B: () => 'Copy ' + o[1] + ' bytes from M(' + R(z) + ') to M(' + R(x) + ')', 0x3C: () => 'Copy memory from M(' + R(z) + ') to M(' + R(x) + ') until ' + R(lo(o[1])) + ' is reached', 0x3D: () => 'Test: does ' + ACC[z] + ' match M(' + R(x) + ')?',
    0x40: () => 'Increment the Accumulator', 0x41: () => 'Decrement the Accumulator', 0x42: () => 'Increment ' + R(x) + (z ? ', in decimal' : ''), 0x43: () => 'Decrement ' + R(x) + (z ? ', in decimal' : ''),
    0x44: () => 'MA = ' + R(z) + ' + ' + R(x), 0x45: () => 'MA = ' + R(z) + ' - ' + R(x), 0x46: () => 'MA = Acc + ' + R(x), 0x47: () => 'MA = Acc - ' + R(x), 0x48: () => 'MA = ' + R(x) + ' - Acc', 0x49: () => 'MA = ' + R(x) + ' x Acc', 0x4A: () => 'MA = ' + R(z) + ' x ' + R(x),
    0x4B: () => 'MA = Acc / ' + R(x) + ', with the remainder', 0x4C: () => 'MA = ' + R(x) + ' / Acc, with the remainder', 0x4D: () => 'MA = ' + R(z) + ' / ' + R(x) + ', with the remainder', 0x4E: () => 'Add ' + w(0) + ' to the Accumulator', 0x4F: () => 'Subtract ' + w(0) + ' from the Accumulator',
    0x50: () => R(lo(o[1])) + ' = ' + R(z) + ' + ' + R(x), 0x51: () => R(lo(o[1])) + ' = ' + R(z) + ' - ' + R(x), 0x52: () => 'Add ' + w(1) + ' to ' + R(x), 0x53: () => 'Subtract ' + w(1) + ' from ' + R(x),
    0x54: () => 'MA ' + (x ? '+= ' : '= ') + bytes(z) + ' at M(' + R(hi(o[1])) + ') + M(' + R(lo(o[1])) + ')', 0x55: () => 'MA ' + (x ? '+= ' : '= ') + bytes(z) + ' at M(' + R(hi(o[1])) + ') - M(' + R(lo(o[1])) + ')',
    0x56: () => 'MA = Acc + ' + bytes(z) + ' at M(' + R(x) + ')', 0x57: () => 'MA = Acc - ' + bytes(z) + ' at M(' + R(x) + ')', 0x58: () => 'MA = Acc x the 2 bytes at M(' + R(x) + ')', 0x59: () => 'MA = Acc / the 2 bytes at M(' + R(x) + ')',
    0x5A: () => 'MA = M(' + R(z) + ') x M(' + R(x) + ')', 0x5B: () => 'MA = M(' + R(z) + ') / M(' + R(x) + ')', 0x5C: () => 'MA = MA / ' + R(x) + ', with the remainder',
    0x60: () => 'Shift the Acc ' + (z === 1 ? 'low byte ' : z === 2 ? 'high byte ' : '') + 'one bit ' + shift[x], 0x61: () => 'Shift ' + R(z) + ' one bit ' + shift[x], 0x62: () => 'Shift the MA one bit ' + shift[x],
    0x63: () => 'MA = ' + R(x) + ' OR ' + (z ? w(1) : 'Acc'), 0x64: () => 'MA = ' + R(x) + ' XOR ' + (z ? w(1) : 'Acc'), 0x65: () => 'MA = ' + R(x) + ' AND ' + (z ? w(1) : 'Acc'),
    0x6A: () => 'Clear ' + ACC[x], 0x6B: () => 'Convert ' + ['the Accumulator', 'the Math Accumulator', R(x)][z] + ' to decimal, into the DA', 0x6C: () => 'Convert the DA to hex, into the MA', 0x6D: () => x ? 'Math results also go to the DA in decimal' : 'Hex mode', 0x6E: () => 'Send the DA to the terminal as a decimal number',
    0x70: () => 'Push ' + ACC[x], 0x71: () => 'Pop ' + ACC[x], 0x72: () => 'Push ' + R(x), 0x73: () => 'Pop ' + R(x), 0x74: () => 'Push ' + bytes(z || 16) + ' from M(' + R(x) + '), walking down', 0x75: () => 'Pop ' + bytes(z || 16) + ' to M(' + R(x) + '), walking up',
    0x76: () => 'Push the ' + ['I/O byte', 'EF setting', 'memory mode', 'DATADIR', 'hex flag', '(unassigned)', 'Error register', '(unassigned)', 'ExitCode'][x], 0x77: () => 'Pop the ' + ['I/O byte', 'EF setting', 'memory mode', 'DATADIR', 'hex flag', '(unassigned)', 'Error register', '(unassigned)', 'ExitCode'][x], 0x78: () => 'Push the Q state', 0x79: () => 'Pop the Q state and set Q',
    0x80: () => 'Test: Acc = ' + R(x) + part[z] + '?', 0x81: () => 'Test: Acc = ' + w(0) + '?', 0x82: () => 'Test: Acc = the ' + (x ? 'high' : 'low') + ' 2 bytes of the MA?', 0x83: () => 'Test: I/O byte = the Acc low byte?', 0x84: () => 'Test: I/O byte = ' + hx(o[0], 2) + '?', 0x85: () => 'Test: Acc = the ' + (x ? 'high' : 'low') + ' 2 bytes of the DA?',
    0x86: () => 'Test: ' + R(x) + ' = ' + w(1) + part[z] + '?', 0x87: () => 'Test: ' + R(z) + ' = ' + R(x) + '?', 0x88: () => 'Test: ' + R(z) + ' >= ' + R(x) + '?', 0x89: () => 'Test: ' + R(z) + ' < ' + R(x) + '?', 0x8A: () => 'Test: DA > ' + R(x) + '?', 0x8B: () => 'Test: Command Counter > ' + R(x) + '?',
    0x8C: () => 'Test: ' + R(x) + ' = 0' + part[z] + '?', 0x8D: () => 'Test: ' + ACC[x] + ' = 0?', 0x8E: () => 'Test: MA Remainder = 0?', 0x8F: () => 'Test: DA Remainder = 0?', 0x90: () => 'Test: is the Acc from ' + R(z) + ' to ' + R(x) + '?', 0x91: () => 'Test: is the MA sign positive?', 0x92: () => 'Test: is Q on?', 0x93: () => 'Test: is Carry set?',
    0x94: () => 'Test: is the ' + ['Overflow', 'Interrupt', 'Decimal', 'Macro'][x] + ' flag set?', 0x96: () => 'Test: ExitCode = ' + hx(o[0], 2) + '?', 0x97: () => 'Test: Interrupt State = ' + hx(o[0], 2) + '?', 0x98: () => 'Test: is the Error register non-zero?', 0x99: () => 'Test: EF' + z + ' = ' + x + '?', 0x9A: () => 'Test: is the low byte of ' + ACC[x] + ' even?',
    0x9B: () => 'Test: is byte ' + z + ' of ' + ACC[x] + ' zero?', 0x9C: () => 'Test: do ' + bytes(o[0]) + ' at M(' + R(hi(o[1])) + ') and M(' + R(lo(o[1])) + ') match?', 0x9D: () => 'Test: do the ' + bytes(z) + ' at M(' + R(x) + ') match these?', 0x9E: () => 'Test: System Status = ' + hx(o[0], 2) + '?', 0x9F: () => 'Test: input port = ' + hx(o[1], 2) + '?',
    0xA0: () => 'If true, go to ' + w(0), 0xA1: () => 'If false, go to ' + w(0), 0xA2: () => 'If true, go to label ' + hx(o[0], 2), 0xA3: () => 'If false, go to label ' + hx(o[0], 2), 0xA4: () => 'If true, jump ' + (o[0] ? 'back ' : 'ahead ') + hx(o[1], 2) + ' bytes', 0xA5: () => 'If false, jump ' + (o[0] ? 'back ' : 'ahead ') + hx(o[1], 2) + ' bytes',
    0xA6: () => 'If true, go to the address ' + (z ? 'held at M(' + R(x) + ')' : 'in ' + R(x)), 0xA7: () => 'If false, go to the address ' + (z ? 'held at M(' + R(x) + ')' : 'in ' + R(x)),
    0xB0: () => 'Go to ' + w(0), 0xB1: () => 'Go to the address ' + (z ? 'held at M(' + R(x) + ')' : 'in ' + R(x)), 0xB2: () => 'Call label ' + hx(o[0], 2), 0xB3: () => 'Label this location ' + hx(o[0], 2), 0xB4: () => 'Go to label ' + hx(o[0], 2),
    0xB5: () => 'Loop to ' + w(1) + ' until ' + R(z) + ' >= ' + R(x), 0xB6: () => 'Loop to label ' + hx(o[1], 2) + ' until ' + R(z) + ' >= ' + R(x), 0xB7: () => 'Loop to ' + w(1) + ' until ' + R(x) + ' = 0000', 0xB8: () => 'Loop to label ' + hx(o[1], 2) + ' until ' + R(x) + ' = 0000', 0xB9: () => 'Jump ' + (o[0] ? 'back ' : 'ahead ') + hx(o[1], 2) + ' bytes',
    0xBA: () => 'Define subroutine ' + hx(o[0], 2) + ' at ' + w(1), 0xBB: () => 'Subroutine ' + hx(o[0], 2) + ' starts here', 0xBC: () => 'End of the subroutine', 0xBD: () => 'Call the subroutine at ' + w(0), 0xBE: () => 'Return from the subroutine', 0xBF: () => 'Return from the labelled call',
    0xC0: () => 'Delay ' + hx(o[0], 2), 0xC1: () => 'Print the string at M(' + R(x) + ')', 0xC2: () => 'Read a line into M(' + R(z) + ')', 0xC3: () => 'Random number into the Accumulator', 0xC4: () => 'No operation', 0xC5: () => 'Enable external interrupts', 0xC6: () => 'Disable external interrupts', 0xC7: () => 'Multitasking ' + (x ? 'on' : 'off'), 0xC8: () => 'Counter interrupt count = ' + hx(o[0], 2),
    0xC9: () => 'Send the Acc low byte to the terminal', 0xCA: () => 'Send ' + hx(o[0], 2) + ' to the terminal', 0xCB: () => 'Wait for a key, into the Acc low byte', 0xCC: () => 'Test: is a key waiting?', 0xCD: () => 'Start of the program',
    0xCE: () => (x ? 'Resume VM' : 'Pause VM') + z, 0xCF: () => 'Kill VM' + z, 0xD0: () => z ? 'Share this VM, ' + (x === 2 ? 'read and write' : 'read only') : 'Stop sharing this VM', 0xD1: () => 'Test: is VM' + z + ' open for ' + (x === 2 ? 'read and write' : 'reading') + '?', 0xD2: () => x ? 'Save our Acc to the Acc of VM' + z : 'Load the Acc of VM' + z + ' into our Acc',
    0xD3: () => x ? 'Save our ' + R(lo(o[1])) + ' to ' + R(hi(o[1])) + ' of VM' + z : 'Load ' + R(hi(o[1])) + ' of VM' + z + ' into our ' + R(lo(o[1])), 0xD4: () => 'Load 2 bytes from M(' + R(hi(o[1])) + ') of VM' + z + ' into our ' + R(lo(o[1])), 0xD5: () => 'Save our ' + R(hi(o[1])) + ' at M(' + R(lo(o[1])) + ') of VM' + z,
    0xD6: () => 'In VM' + z + ', copy a byte from M(' + R(x) + ') to M(' + R(lo(o[1])) + ')', 0xD7: () => 'In VM' + z + ', copy ' + R(x) + ' to ' + R(lo(o[1])), 0xD8: () => 'Increment the Acc of VM' + z, 0xD9: () => 'Decrement the Acc of VM' + z, 0xDA: () => 'Increment ' + R(x) + ' of VM' + z, 0xDB: () => 'Decrement ' + R(x) + ' of VM' + z,
    0xDC: () => 'Copy ' + o[2] + ' bytes from M(' + R(x) + ') of VM' + z + ' to M(' + R(lo(o[1])) + ') of VM' + hi(o[1]), 0xDD: () => 'Test VM' + z + "'s status", 0xDE: () => 'Test: ' + R(hi(o[1])) + ' of VM' + z + ' = our ' + R(lo(o[1])) + '?', 0xDF: () => 'Test a special register of VM' + z + ' = ' + hx(o[1], 2) + '?',
    0xF0: () => 'Break: back to the command line', 0xF1: () => 'Run the machine code at ' + w(0), 0xF2: () => 'Take ' + x + ' blocks for this VM', 0xF6: () => 'Add up the bytes from M(' + R(z) + ') to M(' + R(x) + '), into the MA', 0xFA: () => 'Reset flag ' + x, 0xFB: () => 'Fill M(' + R(z) + ') to M(' + R(x) + ') with ' + hx(o[1], 2), 0xFC: () => 'One sort pass over M(' + R(hi(o[1])) + ') to M(' + R(lo(o[1])) + ')', 0xFD: () => 'Clear program memory', 0xFF: () => 'Debug mode ' + hx(o[0], 2)
  };
  const f = T[op];
  return f ? f() : '';
}

function parse(text) {
  const ex = []; let e = null;
  text.split('\n').forEach((raw, n) => {
    const line = raw.replace(/\s+$/, '');
    if (!line || line.startsWith('#!') || line.startsWith('// ')) return;
    let m;
    if ((m = line.match(/^## ([0-9A-F -]+)\| (.*)$/))) {
      e = { line: n + 1, ops: m[1].trim() === '-' ? [] : m[1].trim().split(/\s+/).map(h => parseInt(h, 16)), title: m[2], src: '', fix: '', tidy: '', note: '', run: {}, expect: [], body: [] };
      ex.push(e); return;
    }
    if (!e) throw new Error('line ' + (n + 1) + ': text before the first ##');
    if ((m = line.match(/^(src|fix|tidy|note|run|expect): ?(.*)$/))) {
      if (m[1] === 'run') m[2].split(/\s+/).filter(Boolean).forEach(t => { const [k, v] = t.split('='); e.run[k] = v === undefined ? '1' : v; });
      else if (m[1] === 'expect') e.expect.push(...m[2].split(/\s+/).filter(Boolean));
      else e[m[1]] = (e[m[1]] ? e[m[1]] + ' ' : '') + m[2];
      return;
    }
    e.body.push({ text: line, n: n + 1 });
  });
  return ex;
}

function assemble(e) {
  let a = 0x4000; const labels = {}, items = [];
  e.body.forEach(({ text, n }) => {           // pass 1: addresses
    let m;
    if ((m = text.match(/^@([0-9A-F]{4})$/))) { a = parseInt(m[1], 16); return; }
    if ((m = text.match(/^([a-z][a-z0-9]*):$/))) { labels[m[1]] = a; return; }
    const i = text.indexOf(';'), code = (i < 0 ? text : text.slice(0, i)).trim(), comment = i < 0 ? '' : text.slice(i + 1).trim();
    const toks = code.split(/\s+/).filter(Boolean), data = toks[0] === 'db';
    if (data) toks.shift();
    const len = toks.reduce((s, t) => s + (t[0] === '{' ? 2 : 1), 0);
        items.push({ addr: a, toks, comment, n, data }); a += len;
  });
  const pokes = [];
  items.forEach(it => {                        // pass 2: bytes
    it.bytes = [];
    it.toks.forEach(t => {
      if (t[0] === '{') {
        const l = labels[t.slice(1, -1)];
        if (l === undefined) throw new Error(e.title + ': no label ' + t);
        it.bytes.push((l >> 8) & 0x0F, l & 0xFF);
      } else {
        if (!/^[0-9A-F]{2}$/.test(t)) throw new Error('line ' + it.n + ': bad byte ' + t);
        it.bytes.push(parseInt(t, 16));
      }
    });
    it.bytes.forEach((b, i) => pokes.push([it.addr + i, b]));
  });
  return { items, pokes };
}

function run(e, pokes) {
  const vm = new L.StellarVM({ firmware: window.STELLAR_FIRMWARE, program: pokes, coldBoot: true,
    input: (e.run.serial || '').replace(/\\r/g, '\r').replace(/_/g, ' ') });
  const c = vm.cpu, sw = parseInt(e.run.sw || '05', 16);
  for (let p = 0; p < 8; p++) c.io_in[p] = c.io_in[p] || { pop: () => sw };
  if (e.run.ef4) c.EF[3] = +e.run.ef4;
  const hold = e.run.ef4 !== undefined;
  let stop = +(e.run.stop || 0), halted = false;
  const LIMIT = +(e.run.limit || 30000000); let spent = 0, n = 0;
  const cc = () => { const M = c.M; return M[0x3033] * 0x1000000 + (M[0x3034] << 16) + (M[0x3035] << 8) + M[0x3036]; };
  const cc0 = cc();
  while (spent < LIMIT) {
    for (let k = 0; k < 3000; k++) { if (!c.step()) { halted = true; break; } }
    spent += 3000;
    if (halted) break;
    if (!hold) c.EF[3] = c.EF[3] ? 0 : 1;      // someone pressing the Input key
    if (stop && cc() - cc0 >= stop) break;
  }
  return { vm, c, halted };
}

// Read one `expect` name from the machine, as the text it should equal.
function reading(key, c, vm) {
  let base = 0x3000, k = key, m;
  if ((m = k.match(/^VM([1-4])\.(.*)$/))) { base = 0x3000 + (+m[1] - 1) * 0x400; k = m[2]; }
  const M = c.M, bs = (o, n) => Array.from(M.subarray(base + o, base + o + n)).map(x => hx(x, 2)).join('');
  if ((m = k.match(/^R([0-9A-F])$/))) return bs(parseInt(m[1], 16) * 2, 2);
  switch (k) {
    case 'A': return bs(0x20, 2); case 'MA': return bs(0x68, 4); case 'MAR': return bs(0x6C, 2); case 'MAS': return bs(0x6E, 1);
    case 'DA': return bs(0x28, 4); case 'DAR': return bs(0x2C, 3); case 'DAS': return bs(0x2F, 1); case 'IO': return bs(0x3A, 1);
    case 'T': return String(M[base + 0x45]); case 'C': return String(M[base + 0x48]); case 'V': return String(M[base + 0x49]); case 'E': return bs(0x4F, 1); case 'X': return bs(0x4E, 1);
    case 'SP': return bs(0x3C, 1); case 'CSP': return bs(0x58, 1); case 'PL': return bs(0x31, 2); case 'CC': return bs(0x33, 4); case 'HEX': return bs(0x4A, 1); case 'MODE': return bs(0x3B, 1); case 'OP': return bs(0x37, 3);
    case 'Q': return String(c.Q);
    case 'OUT': { const p = M[0x3039] || 4; return (c.io_out[p] || []).map(x => hx(x, 2)).join(','); }
    case 'SER': return Buffer.from(c.io_out[3] || []).toString('latin1').replace(/\r/g, '\\r').replace(/\n/g, '\\n').replace(/ /g, '_');
    case 'ST': return hx(M[0x2F05 + (base - 0x3000) / 0x400 * 0x10], 2);
  }
  if ((m = k.match(/^M([0-9A-F]{4})$/))) return null;
  throw new Error('no such reading: ' + key);
}

const NAMES = { A: 'Accumulator', MA: 'MA', MAR: 'MA remainder', MAS: 'MA sign', DA: 'DA', DAR: 'DA remainder', DAS: 'DA sign', T: 'Test flag', C: 'Carry', V: 'Overflow', E: 'Error register', X: 'ExitCode', Q: 'Q', OUT: 'Output port', SER: 'Terminal', SP: 'Stack position', CSP: 'Call stack position', PL: 'Stopped at', CC: 'Command Counter', IO: 'I/O byte', HEX: 'Hex flag', MODE: 'Memory mode', ST: 'VM state' };
function pretty(k, v) {
  let m, pre = '';
  if ((m = k.match(/^VM([1-4])\.(.*)$/))) { pre = 'VM' + m[1] + ' '; k = m[2]; }
  if ((m = k.match(/^M([0-9A-F]{4})$/))) return pre + 'M(' + m[1] + ') = ' + v.replace(/,/g, ' ');
  if (k === 'OUT') return pre + 'Output port: ' + v.replace(/,/g, ' ');
  if (k === 'SER') return pre + 'Terminal: ' + v.replace(/\\r\\n/g, ' / ').replace(/_/g, ' ');
  return pre + (NAMES[k] || k) + ' = ' + v;
}

function build() {
  const file = path.join(__dirname, 'opcode-examples.txt');
  const ex = parse(fs.readFileSync(file, 'utf8'));
  const only = process.argv.includes('--only') ? process.argv[process.argv.indexOf('--only') + 1] : null;
  const out = []; let bad = 0;
  ex.forEach((e, id) => {
    if (only && !e.ops.some(o => hx(o, 2) === only)) return;
    let asm, r;
    try { asm = assemble(e); r = run(e, asm.pokes); } catch (x) { console.log('FAIL', e.title, x.message); bad++; return; }
    const { items, pokes } = asm, { c, vm, halted } = r, M = c.M, fails = [];
    // the listing: each source line must be exactly one instruction
    const lines = items.map(it => {
      if (it.data) return { a: hx(it.addr, 4), b: it.bytes.map(x => hx(x, 2)).join(' '), m: 'DATA', c: it.comment };
      const d = D.disassemble(Uint8Array.from(it.bytes.concat([0, 0, 0, 0, 0, 0, 0, 0])), 0, 0).lines[0];
      if (d.unknown) fails.push('line ' + it.n + ': no such opcode $' + hx(it.bytes[0], 2));
      if (it.bytes[0] !== 0xF0 && it.bytes.length !== d.len) fails.push('line ' + it.n + ': ' + d.name + ' is ' + d.len + ' bytes, not ' + it.bytes.length);
      const brkEnd = it.bytes[0] === 0xF0 && it.bytes.length === 3;
      return { a: hx(it.addr, 4), b: it.bytes.map(x => hx(x, 2)).join(' '), m: (brkEnd ? 'BRK' : d.name + (d.operandText ? ' ' + d.operandText : '')), c: it.comment || (brkEnd ? 'Break: back to the command line' : explain(it.bytes)) };
    });
    if (!pokes.some(p => p[0] === 0x4000 && p[1] === 0xCD) ) fails.push('does not start with CD');
    if (!e.run.stop && !halted) fails.push('never ended');
    if (e.run.stop && halted && !e.run.ends) fails.push('ended, but run: stop= says it loops');
    const result = [];
    e.expect.forEach(t => {
      const soft = t.includes('~='), [k, v] = t.split(soft ? '~=' : '=');
      let got, m2;
      if ((m2 = k.match(/^(?:VM([1-4])\.)?M([0-9A-F]{4})$/))) { const a = parseInt(m2[2], 16), n = v.split(',').length; got = Array.from(M.subarray(a, a + n)).map(x => hx(x, 2)).join(','); }
      else got = reading(k, c, vm);
      if (!soft && got !== v) fails.push(k + ' = ' + got + ', not ' + v);
      result.push(pretty(k, soft ? got : v));
    });
    if (fails.length) { bad++; console.log('FAIL line ' + e.line + ' [' + e.title + ']\n   ' + fails.join('\n   ')); }
    out.push({ ops: e.ops.map(o => hx(o, 2)), title: e.title, src: e.src, fix: e.fix, tidy: e.tidy, note: e.note, loop: !!e.run.stop, needs: e.run.serial ? 'keys' : '', lines, result, steps: c.steps });
  });
  return { out, bad, count: ex.length };
}

const { out, bad, count } = build();
if (process.argv.includes('--show')) out.forEach(e => console.log('[' + e.title + '] ' + e.result.join(' | ') + '  (' + e.steps + ')'));
console.log(count + ' examples, ' + bad + ' failed');
if (bad) process.exit(1);
if (process.argv.includes('--only')) process.exit(0);
const covered = {}; out.forEach(e => e.ops.forEach(o => { covered[o] = (covered[o] || 0) + 1; }));
const missing = OPS.map(o => hx(o.op, 2)).filter(h => !covered[h]);
console.log('opcodes with no example: ' + (missing.length ? missing.join(' ') : 'none'));
if (process.argv.includes('--check')) process.exit(0);
const js = '// AUTO-GENERATED by web/build/gen_opcode_examples.js from opcode-examples.txt - do not edit by hand.\n' +
  '// Every program here was run on the V0061.37 firmware; the results are what the machine did.\n' +
  'window.STELLAR_OP_EXAMPLES = ' + JSON.stringify(out.map(({ steps, tidy, ...e }) => e)) + ';\n';
fs.writeFileSync(path.join(WEB, 'js/opcode-examples.js'), js);
console.log('js/opcode-examples.js: ' + js.length + ' bytes');

// The report for the document's author: what became of every table.
const REPORT = process.argv.indexOf('--report');
if (REPORT > 0) {
  const ex = parse(fs.readFileSync(path.join(__dirname, 'opcode-examples.txt'), 'utf8'));
  const used = {}; const rows = [];
  ex.forEach(e => {
    e.src.split(/\s+/).filter(t => /^T\d+$/.test(t)).forEach(t => { used[+t.slice(1)] = 1; });
    if (e.src !== 'new' && (e.fix || e.tidy)) rows.push('| ' + e.src + ' | ' + e.title + ' | ' + [e.fix, e.tidy].filter(Boolean).join(' ').replace(/\|/g, '/') + ' |');
  });
  const added = ex.filter(e => e.src === 'new').map(e => '- ' + (e.ops.length ? '$' + hx(e.ops[0], 2) + ' ' : '') + e.title + (e.fix ? ': ' + e.fix : ''));
  const notUsed = []; for (let t = 1; t <= 258; t++) if (!used[t]) notUsed.push('T' + t);
  const head = fs.readFileSync(path.join(__dirname, 'opcode-examples-findings.md'), 'utf8');
  fs.writeFileSync(process.argv[REPORT + 1], head.replace('%COUNT%', ex.length) +
    '\n## Every table that was changed\n\nT numbers count the tables from the start of the document, T1 being the first.\n\n| Table | Now called | What changed |\n|---|---|---|\n' + rows.join('\n') +
    '\n\n## Examples that are new\n\n' + added.join('\n') +
    '\n\n## Tables not on the page\n\n' + notUsed.join(' ') + '\n');
  console.log('report: ' + rows.length + ' changed, ' + added.length + ' new, not used: ' + notUsed.join(' '));
}
