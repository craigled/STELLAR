// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// STELLAR disassembler for the side panel. Ported from tools/stellar_disasm.py
// (shares its opcode length/name tables via opcodes.js, so instruction
// boundaries match the Python tool exactly). Browser + Node.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.StellarDisasm = api;
})(this, function () {
  'use strict';

  function getOpcodes(explicit) {
    if (explicit) return explicit;
    if (typeof window !== 'undefined' && window.STELLAR_OPCODES) return window.STELLAR_OPCODES;
    if (typeof require !== 'undefined') { try { return require('./opcodes.js').opcodes; } catch (e) {} }
    throw new Error('opcode table unavailable (load opcodes.js first)');
  }
  function tables(ops) {
    var LEN = {}, NAME = {}, PAT = {};
    ops.forEach(function (o) { LEN[o.op] = o.length; NAME[o.op] = o.name; PAT[o.op] = o.operands || ''; });
    return { LEN: LEN, NAME: NAME, PAT: PAT };
  }

  // Render operand bytes against the opcode's pattern ("XY", "ZX", "0X", "NN NN"...)
  // so register nibbles read as R1/RA rather than a bare hex digit. Bytes whose
  // pattern holds no register nibble stay as plain hex.
  function fmtOperands(pattern, bytes) {
    var toks = (pattern || '').trim().split(/\s+/).filter(Boolean);
    if (!toks.length || toks.length !== bytes.length) return bytes.map(hx2).join(' ');
    var out = [], run = '';
    for (var i = 0; i < bytes.length; i++) {
      var tk = toks[i], b = bytes[i];
      if (!/[XY]/.test(tk)) { run += hx2(b); continue; }   // plain bytes group together
      if (run) { out.push(run); run = ''; }
      var parts = [], nib = [(b >> 4) & 0xF, b & 0xF];
      for (var k = 0; k < 2; k++) {
        var c = tk.charAt(k), d = nib[k].toString(16).toUpperCase();
        if (c === 'X' || c === 'Y') parts.push('R' + d);
        else if (c === '0') continue;          // padding nibble in the pattern
        else if (nib[k] === 0) continue;       // zero selector alongside a register: noise
        else parts.push(d);
      }
      out.push(parts.join(' '));
    }
    if (run) out.push(run);
    return out.filter(Boolean).join(' ');
  }

  // variable-length opcodes (return operand-byte count)
  function vlen(mem, a) {
    var op = mem[a], nxt = mem[a + 1] || 0;
    if (op === 0x12) return 1 + ((nxt >> 4) || 2);
    if (op === 0x63 || op === 0x64 || op === 0x65) return (nxt >> 4) === 1 ? 3 : 1;
    if (op === 0x9D) return 1 + (nxt >> 4);
    return 0;
  }

  function hx2(b) { return b.toString(16).toUpperCase().padStart(2, '0'); }
  function hx4(w) { return w.toString(16).toUpperCase().padStart(4, '0'); }

  // Disassemble a memory image over [lo,hi]; stop code at F0 00 00 end marker.
  // Returns { lines:[{addr,len,bytes,op,name,operandHex,operandText,isEnd}], byAddr:{addr:index} }.
  function disassemble(mem, lo, hi, opcodesArr) {
    var t = tables(getOpcodes(opcodesArr)), LEN = t.LEN, NAME = t.NAME, PAT = t.PAT;
    var lines = [], byAddr = {};
    var a = lo;
    while (a <= hi) {
      var op = mem[a];
      var L = LEN[op];
      var nops;
      if (L === undefined) { nops = 0; }           // unknown: show opcode alone
      else if (L === -1) { nops = vlen(mem, a); }  // variable
      else { nops = L; }
      var end = (op === 0xF0 && mem[a + 1] === 0 && mem[a + 2] === 0);
      if (end) nops = 2;
      var bytes = [];
      for (var i = 0; i <= nops; i++) bytes.push(mem[a + i]);
      byAddr[a] = lines.length;
      lines.push({
        addr: a, len: nops + 1, bytes: bytes, op: op,
        name: end ? 'BRK' : (NAME[op] || ('op' + hx2(op))),
        operandHex: bytes.slice(1).map(hx2).join(' '),
        operandText: end ? '' : fmtOperands(PAT[op], bytes.slice(1)),
        isEnd: end, unknown: L === undefined
      });
      a += nops + 1;
      if (end) break;
    }
    return { lines: lines, byAddr: byAddr };
  }

  // Convenience for an app image: find its program block and disassemble it.
  function disassembleProgram(mem, base) {
    base = base || 0x4000;
    // walk to the end marker or the end of the 4K block
    return disassemble(mem, base, base + 0x0FFF);
  }

  return { disassemble: disassemble, disassembleProgram: disassembleProgram, vlen: vlen, fmtOperands: fmtOperands, hx2: hx2, hx4: hx4 };
});
