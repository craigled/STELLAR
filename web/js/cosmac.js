// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// A small CDP1802/1805 disassembler, for showing the raw machine instructions
// that execute underneath a single STELLAR opcode. One instruction at a time:
// decode(M, addr) -> { len, text }. Browser + Node.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.Cosmac = api;
})(this, function () {
  'use strict';

  function h2(v) { return (v & 0xFF).toString(16).toUpperCase().padStart(2, '0'); }
  function h4(v) { return (v & 0xFFFF).toString(16).toUpperCase().padStart(4, '0'); }
  function r(n) { return 'R' + n.toString(16).toUpperCase(); }

  var SHORT = ['BR', 'BQ', 'BZ', 'BDF', 'B1', 'B2', 'B3', 'B4',
               'SKP', 'BNQ', 'BNZ', 'BNF', 'BN1', 'BN2', 'BN3', 'BN4'];
  var LONG = ['LBR', 'LBQ', 'LBZ', 'LBDF', 'NOP', 'LSNQ', 'LSNZ', 'LSNF',
              'LSKP', 'LBNQ', 'LBNZ', 'LBNF', 'LSIE', 'LSQ', 'LSZ', 'LSDF'];
  var SEVEN = ['RET', 'DIS', 'LDXA', 'STXD', 'ADC', 'SDB', 'SHRC', 'SMB',
               'SAV', 'MARK', 'REQ', 'SEQ', 'ADCI', 'SDBI', 'SHLC', 'SMBI'];
  var EFF = ['LDX', 'OR', 'AND', 'XOR', 'ADD', 'SD', 'SHR', 'SM',
             'LDI', 'ORI', 'ANI', 'XRI', 'ADI', 'SDI', 'SHL', 'SMI'];
  var EXT0 = ['STPC', 'DTC', 'SPM2', 'SCM2', 'SPM1', 'SCM1', 'LDC', 'STM',
              'GEC', 'ETQ', 'XIE', 'XID', 'CIE', 'CID'];

  function decodeExt(M, a) {
    var op = M[(a + 1) & 0xFFFF], hi = op >> 4, lo = op & 0xF;
    var b2 = M[(a + 2) & 0xFFFF], b3 = M[(a + 3) & 0xFFFF];
    if (hi === 0x0 && lo < EXT0.length) return { len: 2, text: EXT0[lo] };
    if (hi === 0x2) return { len: 4, text: 'DBNZ ' + r(lo) + ',' + h4((b2 << 8) | b3) };
    if (op === 0x3E) return { len: 3, text: 'BCI ' + h2(b2) };
    if (op === 0x3F) return { len: 3, text: 'BXI ' + h2(b2) };
    if (hi === 0x6) return { len: 2, text: 'RLXA ' + r(lo) };
    if (hi === 0x8) return { len: 4, text: 'SCAL ' + r(lo) + ',' + h4((b2 << 8) | b3) };
    if (hi === 0x9) return { len: 2, text: 'SRET ' + r(lo) };
    if (hi === 0xA) return { len: 2, text: 'RSXD ' + r(lo) };
    if (hi === 0xB) return { len: 2, text: 'RNX ' + r(lo) };
    if (hi === 0xC) return { len: 4, text: 'RLDI ' + r(lo) + ',' + h4((b2 << 8) | b3) };
    var dec = { 0x74: 'DADC', 0x76: 'DSAV', 0x77: 'DSMB', 0xF4: 'DADD', 0xF7: 'DSM' };
    if (dec[op]) return { len: 2, text: dec[op] };
    var deci = { 0x7C: 'DACI', 0x7F: 'DSBI', 0xFC: 'DADI', 0xFF: 'DSMI' };
    if (deci[op]) return { len: 3, text: deci[op] + ' ' + h2(b2) };
    return { len: 2, text: 'DB 68,' + h2(op) };
  }

  function decode(M, a) {
    var op = M[a & 0xFFFF], hi = op >> 4, lo = op & 0xF, b1 = M[(a + 1) & 0xFFFF];
    switch (hi) {
      case 0x0: return { len: 1, text: op === 0 ? 'IDL' : 'LDN ' + r(lo) };
      case 0x1: return { len: 1, text: 'INC ' + r(lo) };
      case 0x2: return { len: 1, text: 'DEC ' + r(lo) };
      case 0x3:
        if (op === 0x38) return { len: 1, text: 'SKP' };
        return { len: 2, text: SHORT[lo] + ' ' + h2(b1) };
      case 0x4: return { len: 1, text: 'LDA ' + r(lo) };
      case 0x5: return { len: 1, text: 'STR ' + r(lo) };
      case 0x6:
        if (op === 0x60) return { len: 1, text: 'IRX' };
        if (op === 0x68) return decodeExt(M, a);
        return { len: 1, text: (lo < 8 ? 'OUT ' + lo : 'INP ' + (lo - 8)) };
      case 0x7:
        if (op === 0x7C || op === 0x7D || op === 0x7F) return { len: 2, text: SEVEN[lo] + ' ' + h2(b1) };
        return { len: 1, text: SEVEN[lo] };
      case 0x8: return { len: 1, text: 'GLO ' + r(lo) };
      case 0x9: return { len: 1, text: 'GHI ' + r(lo) };
      case 0xA: return { len: 1, text: 'PLO ' + r(lo) };
      case 0xB: return { len: 1, text: 'PHI ' + r(lo) };
      case 0xC:
        if (lo === 4 || (lo >= 5 && lo <= 8) || lo >= 0xC) return { len: 1, text: LONG[lo] };
        return { len: 3, text: LONG[lo] + ' ' + h4((b1 << 8) | M[(a + 2) & 0xFFFF]) };
      case 0xD: return { len: 1, text: 'SEP ' + r(lo) };
      case 0xE: return { len: 1, text: 'SEX ' + r(lo) };
      default:
        if (op >= 0xF8 && op !== 0xFE) return { len: 2, text: EFF[lo] + ' ' + h2(b1) };
        return { len: 1, text: EFF[lo] };
    }
  }

  // Machine cycles an instruction takes (8 clocks each). Base 1802: 2, long
  // branches and skips 3. The 1805 extended ops vary (2-10); these are the
  // datasheet figures for the ones STELLAR's firmware uses, rounded where the
  // taken/not-taken count differs.
  function cycles(M, a) {
    var op = M[a & 0xFFFF];
    if ((op & 0xF0) === 0xC0) return 3;
    if (op !== 0x68) return 2;
    var x = M[(a + 1) & 0xFFFF], hi = x >> 4;
    if (hi === 0x8) return 10;      // SCAL
    if (hi === 0x9) return 8;       // SRET
    if (hi === 0xC) return 5;       // RLDI
    if (hi === 0x2) return 5;       // DBNZ
    if (hi === 0x6 || hi === 0xA) return 5;
    if (hi === 0xB) return 4;       // RNX
    return 4;
  }

  return { decode: decode, cycles: cycles, h2: h2, h4: h4 };
});
