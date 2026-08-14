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
    var LEN = {}, NAME = {};
    ops.forEach(function (o) { LEN[o.op] = o.length; NAME[o.op] = o.name; });
    return { LEN: LEN, NAME: NAME };
  }

  // variable-length opcodes (return operand-byte count)
  function vlen(mem, a) {
    var op = mem[a], nxt = mem[a + 1] || 0;
    if (op === 0x12) return 1 + ((nxt >> 4) || 2);
    if (op === 0x63 || op === 0x64 || op === 0x65) return (nxt >> 4) === 1 ? 3 : 1;
    if (op === 0x9D) return 1 + (nxt >> 4);
    if (op === 0xC2) { var n = 1; while (mem[a + n] !== 0xD5 && mem[a + n] !== undefined) n++; return n; }
    return 0;
  }

  function hx2(b) { return b.toString(16).toUpperCase().padStart(2, '0'); }
  function hx4(w) { return w.toString(16).toUpperCase().padStart(4, '0'); }

  // Disassemble a memory image over [lo,hi]; stop code at F0 00 00 end marker.
  // Returns { lines:[{addr,len,bytes,op,name,ops,operandHex,isEnd}], byAddr:{addr:index} }.
  function disassemble(mem, lo, hi, opcodesArr) {
    var t = tables(getOpcodes(opcodesArr)), LEN = t.LEN, NAME = t.NAME;
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

  return { disassemble: disassemble, disassembleProgram: disassembleProgram, vlen: vlen, hx2: hx2, hx4: hx4 };
});
