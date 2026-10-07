// STELLAR virtual machine for the browser (and Node).
//
// A faithful port of Firmware-Math/cpu1802.py (CDP1802/1805 base ISA + the
// 68-prefix extended ops STELLAR uses) plus the VM boot recipe from
// calc_interactive.run_calc. It runs the REAL flashed firmware image
// (firmware-0061-35.js), so behavior matches the hardware — the visualizers
// just read the emulated $3000 core RAM the firmware maintains.
//
// Works in the browser (window.StellarVM) and in Node (module.exports).
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') {
    window.StellarVM = api.StellarVM;     // the single-VM constructor
    window.StellarMultiVM = api.MultiVM;  // the multi-VM constructor
    window.StellarVMLib = api;            // CPU, UART, parseLst, constants
  }
})(this, function () {
  'use strict';

  var CORE = 0x3000;            // VM1 core page
  // R1 is the monitor's exit vector: when every VM has finished, the firmware
  // does SEP R1. On the Elf2K the monitor sets it; here it must point at an IDL
  // so the machine halts cleanly. This used to be $0033, which is not an
  // instruction at all - it is the low byte of `CALL $0C00` at $0031 and merely
  // happened to be $00. V0061.27 moved CREATE_CIDP, that byte became $98, and a
  // finished program ran on into the boot code. $FFF0 is never written.
  var EXIT_IDL = 0xFFF0;
  var ENTRY = 0x4000;          // VM1 program block

  // ---- base-1802 CPU (port of cpu1802.py) ----
  function CPU(mem) {
    this.M = mem;              // Uint8Array(0x10000)
    this.R = new Uint16Array(16);
    this.D = 0; this.DF = 0; this.X = 0; this.P = 0; this.T = 0;
    this.Q = 0; this.IE = 1;
    this.EF = [0, 0, 0, 0];
    this.io_out = {};          // port -> array of bytes written
    this.io_in = {};           // port -> object with pop(i)
    this.halted = false;
    this.steps = 0;
    this.cycles = 0;           // machine cycles (8 clocks each) - the clock Q audio is timed by
    this.qLog = null;          // set to [] to record [cycle, level] at every change of Q
  }
  CPU.prototype._fetch = function () {
    var b = this.M[this.R[this.P]];
    this.R[this.P] = (this.R[this.P] + 1) & 0xFFFF;
    return b;
  };
  CPU.prototype.step = function () {
    var op = this._fetch(), hi = op >> 4, lo = op & 0xF, R = this.R;
    if (hi === 0x0) {
      if (lo === 0) { this.halted = true; return false; }   // IDL
      this.D = this.M[R[lo]];                                 // LDN
    } else if (hi === 0x1) { R[lo] = (R[lo] + 1) & 0xFFFF; }  // INC
    else if (hi === 0x2) { R[lo] = (R[lo] - 1) & 0xFFFF; }    // DEC
    else if (hi === 0x3) { this._branch(op); }
    else if (hi === 0x4) { this.D = this.M[R[lo]]; R[lo] = (R[lo] + 1) & 0xFFFF; } // LDA
    else if (hi === 0x5) { this.M[R[lo]] = this.D; }          // STR
    else if (hi === 0x6) { this._io(op, lo); }
    else if (hi === 0x7) { this._misc7(op); }
    else if (hi === 0x8) { this.D = R[lo] & 0xFF; }           // GLO
    else if (hi === 0x9) { this.D = (R[lo] >> 8) & 0xFF; }    // GHI
    else if (hi === 0xA) { R[lo] = (R[lo] & 0xFF00) | this.D; }        // PLO
    else if (hi === 0xB) { R[lo] = (R[lo] & 0x00FF) | (this.D << 8); } // PHI
    else if (hi === 0xC) { this._longbranch(op); }
    else if (hi === 0xD) { this.P = lo; }                     // SEP
    else if (hi === 0xE) { this.X = lo; }                     // SEX
    else if (hi === 0xF) { this._miscF(op); }
    this.cycles += hi === 0xC ? 3 : 2;      // long branches and skips 3, the rest 2 (68 xx adds its own)
    this.steps++;
    return !this.halted;
  };
  CPU.prototype._branch = function (op) {
    // A taken short branch replaces the low byte of R(P) while R(P) is still ON
    // the operand, so the target is in the OPERAND byte's page - not the page
    // after it, which is what reading the PC after the fetch gives when the
    // operand is the last byte of a page. (Same fix as cpu1802.py, 9db7059.)
    var page = this.R[this.P] & 0xFF00;
    var a = this._fetch(), t;
    switch (op) {
      case 0x30: t = true; break;
      case 0x31: t = this.Q === 1; break;
      case 0x32: t = this.D === 0; break;
      case 0x33: t = this.DF === 1; break;
      case 0x34: t = this.EF[0] === 1; break;
      case 0x35: t = this.EF[1] === 1; break;
      case 0x36: t = this.EF[2] === 1; break;
      case 0x37: t = this.EF[3] === 1; break;
      case 0x38: t = false; break;
      case 0x39: t = this.Q === 0; break;
      case 0x3A: t = this.D !== 0; break;
      case 0x3B: t = this.DF === 0; break;
      case 0x3C: t = this.EF[0] === 0; break;
      case 0x3D: t = this.EF[1] === 0; break;
      case 0x3E: t = this.EF[2] === 0; break;
      case 0x3F: t = this.EF[3] === 0; break;
    }
    if (t) this.R[this.P] = page | a;
  };
  CPU.prototype._longbranch = function (op) {
    var self = this;
    function lbr(c) { var h = self._fetch(), l = self._fetch(); if (c) self.R[self.P] = (h << 8) | l; }
    function skip(c) { if (c) self.R[self.P] = (self.R[self.P] + 2) & 0xFFFF; }
    switch (op) {
      case 0xC0: lbr(true); break;
      case 0xC1: lbr(this.Q === 1); break;
      case 0xC2: lbr(this.D === 0); break;
      case 0xC3: lbr(this.DF === 1); break;
      case 0xC4: break;                       // NOP
      case 0xC5: skip(this.Q === 0); break;
      case 0xC6: skip(this.D !== 0); break;
      case 0xC7: skip(this.DF === 0); break;
      case 0xC8: skip(true); break;
      case 0xC9: lbr(this.Q === 0); break;
      case 0xCA: lbr(this.D !== 0); break;
      case 0xCB: lbr(this.DF === 0); break;
      case 0xCC: skip(this.IE === 1); break;
      case 0xCD: skip(this.Q === 1); break;
      case 0xCE: skip(this.D === 0); break;
      case 0xCF: skip(this.DF === 1); break;
    }
  };
  CPU.prototype._io = function (op, lo) {
    var R = this.R;
    if (op === 0x60) { R[this.X] = (R[this.X] + 1) & 0xFFFF; }        // IRX
    else if (op === 0x68) { this._extended(); }                       // 1805 prefix
    else if (op >= 0x61 && op <= 0x67) {                              // OUT
      if (lo === 3 && this.rtc) {                                     // port 3 = the RTC when port 2 selected one
        var s2 = this.io_out[2], sel = s2 && s2.length ? s2[s2.length - 1] : 0x15;
        if (sel & 0x80) { this.rtc.write(sel & 0x7F, this.M[R[this.X]]); R[this.X] = (R[this.X] + 1) & 0xFFFF; return; }
      }
      (this.io_out[lo] || (this.io_out[lo] = [])).push(this.M[R[this.X]]);
      R[this.X] = (R[this.X] + 1) & 0xFFFF;
    } else if (op >= 0x69 && op <= 0x6F) {                            // INP
      var port = lo & 0x7, q = this.io_in[port];
      var val = (q && q.pop) ? q.pop(0) : 0;
      this.M[R[this.X]] = val; this.D = val;
    }
  };
  CPU.prototype._misc7 = function (op) {
    var R = this.R, m, t, nb, b;
    if (op === 0x70) { b = this.M[R[this.X]]; R[this.X] = (R[this.X] + 1) & 0xFFFF; this.X = b >> 4; this.P = b & 0xF; this.IE = 1; }
    else if (op === 0x71) { b = this.M[R[this.X]]; R[this.X] = (R[this.X] + 1) & 0xFFFF; this.X = b >> 4; this.P = b & 0xF; this.IE = 0; }
    else if (op === 0x72) { this.D = this.M[R[this.X]]; R[this.X] = (R[this.X] + 1) & 0xFFFF; }   // LDXA
    else if (op === 0x73) { this.M[R[this.X]] = this.D; R[this.X] = (R[this.X] - 1) & 0xFFFF; }   // STXD
    else if (op === 0x74) { m = this.M[R[this.X]]; t = this.D + m + this.DF; this.DF = t > 255 ? 1 : 0; this.D = t & 0xFF; } // ADC
    else if (op === 0x75) { m = this.M[R[this.X]]; t = m - this.D - (1 - this.DF); this.DF = t >= 0 ? 1 : 0; this.D = t & 0xFF; } // SDB
    else if (op === 0x76) { nb = this.D & 1; this.D = (this.D >> 1) | (this.DF << 7); this.DF = nb; } // SHRC
    else if (op === 0x77) { m = this.M[R[this.X]]; t = this.D - m - (1 - this.DF); this.DF = t >= 0 ? 1 : 0; this.D = t & 0xFF; } // SMB
    else if (op === 0x78) { this.M[R[this.X]] = this.T; }             // SAV
    else if (op === 0x79) { this.T = (this.X << 4) | this.P; this.M[R[2]] = this.T; this.X = this.P; R[2] = (R[2] - 1) & 0xFFFF; } // MARK
    else if (op === 0x7A) { this._setQ(0); }                          // REQ
    else if (op === 0x7B) { this._setQ(1); }                          // SEQ
    else if (op === 0x7C) { m = this._fetch(); t = this.D + m + this.DF; this.DF = t > 255 ? 1 : 0; this.D = t & 0xFF; } // ADCI
    else if (op === 0x7D) { m = this._fetch(); t = m - this.D - (1 - this.DF); this.DF = t >= 0 ? 1 : 0; this.D = t & 0xFF; } // SDBI
    else if (op === 0x7E) { nb = (this.D >> 7) & 1; this.D = ((this.D << 1) | this.DF) & 0xFF; this.DF = nb; } // SHLC
    else if (op === 0x7F) { m = this._fetch(); t = this.D - m - (1 - this.DF); this.DF = t >= 0 ? 1 : 0; this.D = t & 0xFF; } // SMBI
  };
  CPU.prototype._setQ = function (v) {
    if (this.qLog && this.Q !== v) this.qLog.push(this.cycles, v);
    this.Q = v;
  };
  CPU.prototype._miscF = function (op) {
    var X = this.R[this.X], t;
    if (op === 0xF0) { this.D = this.M[X]; }
    else if (op === 0xF1) { this.D = this.D | this.M[X]; }
    else if (op === 0xF2) { this.D = this.D & this.M[X]; }
    else if (op === 0xF3) { this.D = this.D ^ this.M[X]; }
    else if (op === 0xF4) { t = this.D + this.M[X]; this.DF = t > 255 ? 1 : 0; this.D = t & 0xFF; }
    else if (op === 0xF5) { t = this.M[X] - this.D; this.DF = t >= 0 ? 1 : 0; this.D = t & 0xFF; }
    else if (op === 0xF6) { this.DF = this.D & 1; this.D = this.D >> 1; }
    else if (op === 0xF7) { t = this.D - this.M[X]; this.DF = t >= 0 ? 1 : 0; this.D = t & 0xFF; }
    else if (op === 0xF8) { this.D = this._fetch(); }
    else if (op === 0xF9) { this.D = this.D | this._fetch(); }
    else if (op === 0xFA) { this.D = this.D & this._fetch(); }
    else if (op === 0xFB) { this.D = this.D ^ this._fetch(); }
    else if (op === 0xFC) { t = this.D + this._fetch(); this.DF = t > 255 ? 1 : 0; this.D = t & 0xFF; }
    else if (op === 0xFD) { t = this._fetch() - this.D; this.DF = t >= 0 ? 1 : 0; this.D = t & 0xFF; }
    else if (op === 0xFE) { this.DF = (this.D >> 7) & 1; this.D = (this.D << 1) & 0xFF; }
    else if (op === 0xFF) { t = this.D - this._fetch(); this.DF = t >= 0 ? 1 : 0; this.D = t & 0xFF; }
  };
  CPU.prototype._extended = function () {
    var op2 = this._fetch(), hi = op2 >> 4, lo = op2 & 0xF, R = this.R, h, l;
    this.cycles += (hi === 0xC || hi === 0x2 || hi === 0x6 || hi === 0xA) ? 3 : 2;   // 1805 datasheet, as cosmac.js
    if (hi === 0xC) { h = this._fetch(); l = this._fetch(); R[lo] = (h << 8) | l; }            // RLDI
    else if (hi === 0x6) { h = this.M[R[this.X]]; R[this.X] = (R[this.X] + 1) & 0xFFFF; l = this.M[R[this.X]]; R[this.X] = (R[this.X] + 1) & 0xFFFF; R[lo] = (h << 8) | l; } // RLXA
    else if (hi === 0xA) { this.M[R[this.X]] = R[lo] & 0xFF; R[this.X] = (R[this.X] - 1) & 0xFFFF; this.M[R[this.X]] = (R[lo] >> 8) & 0xFF; R[this.X] = (R[this.X] - 1) & 0xFFFF; } // RSXD
    else if (hi === 0x2) { R[lo] = (R[lo] - 1) & 0xFFFF; h = this._fetch(); l = this._fetch(); if (R[lo] !== 0) this.R[this.P] = (h << 8) | l; } // DBNZ
    else if (op2 === 0xF4) { this.D = this._bcdAdd(this.D, this.M[R[this.X]], 0); }
    else if (op2 === 0x74) { this.D = this._bcdAdd(this.D, this.M[R[this.X]], this.DF); }
    else if (op2 === 0xF7) { this.D = this._bcdSub(this.D, this.M[R[this.X]], 1); }
    else if (op2 === 0x77) { this.D = this._bcdSub(this.D, this.M[R[this.X]], this.DF); }
    else { throw new Error('unimpl extended op 68 ' + op2.toString(16)); }
  };
  CPU.prototype._bcdAdd = function (a, b, cin) {
    var t = (a & 0xF) + (b & 0xF) + cin, c = t > 9 ? 1 : 0, lo = t > 9 ? t - 10 : t;
    var t2 = ((a >> 4) & 0xF) + ((b >> 4) & 0xF) + c, c2 = t2 > 9 ? 1 : 0, hi = t2 > 9 ? t2 - 10 : t2;
    this.DF = c2; return (hi << 4) | lo;
  };
  CPU.prototype._bcdSub = function (a, b, borrowIn) {
    var bin = borrowIn ? 0 : 1;
    var t = (a & 0xF) - (b & 0xF) - bin, c = t < 0 ? 0 : 1, lo = t < 0 ? t + 10 : t;
    var t2 = ((a >> 4) & 0xF) - ((b >> 4) & 0xF) - (c ? 0 : 1), c2 = t2 < 0 ? 0 : 1, hi = t2 < 0 ? t2 + 10 : t2;
    this.DF = c2; return (hi << 4) | lo;
  };

  // ---- UART model (mirrors calc_interactive.UART) ----
  // OUT 2 selects a register ($15 status / $10 data); INP 3 reads it.
  function UART(text, io_out) {
    this.buf = [];
    for (var i = 0; i < text.length; i++) this.buf.push(text.charCodeAt(i) & 0xFF);
    this.io_out = io_out;
  }
  UART.prototype.pop = function () {
    var sel2 = this.io_out[2];
    var sel = sel2 && sel2.length ? sel2[sel2.length - 1] : null;
    if (sel !== null && (sel & 0x80)) return this.rtc ? this.rtc.read(sel & 0x7F) : 0xFF;   // an RTC register
    if (sel === 0x15) return 0x20 | (this.buf.length ? 0x01 : 0x00); // status
    if (sel === 0x10) return this.buf.length ? this.buf.shift() : 0;  // data
    return 0;
  };

  // ---- the Elf2K's DS12887 real-time clock (ports 2/3, shared with the UART) ----
  // Port 2 selects: $80 | register = the RTC, $10 / $15 = the UART's data / status. The time
  // is THIS COMPUTER'S local clock, presented as Craig's Elf2K BIOS keeps the chip: binary,
  // 24-hour, year = 1972 + value, Monday = 1 (regB $07). Setting it (regB SET, the fields, SET
  // off) stores an offset from the computer's clock, shared by every load on the page, so a
  // time set with $07 RTCSET keeps running. Only what STELLAR's $07 handler uses is modelled:
  // UIP never shows (no update cycles), periodic/alarm interrupts are absent.
  var RTC_OFFSET = 0;
  function RTC() {
    this.r = new Uint8Array(128);
    this.r[0x0A] = 0x20; this.r[0x0B] = 0x07; this.r[0x0D] = 0x80;
    this.setting = false;
  }
  RTC.prototype._enc = function (v) { return (this.r[0x0B] & 0x04) ? v : (((v / 10) | 0) << 4) | (v % 10); };
  RTC.prototype._dec = function (v) { return (this.r[0x0B] & 0x04) ? v : (v >> 4) * 10 + (v & 15); };
  RTC.prototype._load = function () {               // the clock's fields, now
    var d = new Date(Date.now() + RTC_OFFSET), r = this.r, binary = r[0x0B] & 0x04;
    r[0] = this._enc(d.getSeconds()); r[2] = this._enc(d.getMinutes()); r[4] = this._enc(d.getHours());
    r[6] = d.getDay() === 0 ? 7 : d.getDay();
    r[7] = this._enc(d.getDate()); r[8] = this._enc(d.getMonth() + 1);
    r[9] = binary ? (d.getFullYear() - 1972) & 0xFF : this._enc(d.getFullYear() % 100);
  };
  RTC.prototype._commit = function () {             // the fields -> the offset
    var r = this.r, binary = r[0x0B] & 0x04;
    var y = binary ? 1972 + r[9] : 2000 + this._dec(r[9]);
    var t = new Date(y, this._dec(r[8]) - 1, this._dec(r[7]), this._dec(r[4]), this._dec(r[2]), this._dec(r[0]));
    if (!isNaN(t.getTime())) RTC_OFFSET = t.getTime() - Date.now();
  };
  RTC.prototype.read = function (n) {
    if (n <= 9 && !this.setting) this._load();
    return n === 0x0A ? this.r[n] & 0x7F : this.r[n];
  };
  RTC.prototype.write = function (n, v) {
    if (n === 0x0B) {
      if ((v & 0x80) && !this.setting) { this._load(); this.setting = true; }
      this.r[0x0B] = v;
      if (!(v & 0x80) && this.setting) { this.setting = false; this._commit(); }
      return;
    }
    if (n <= 9 && !this.setting) { this._load(); this.r[n] = v; this._commit(); return; }
    this.r[n] = n === 0x0A ? v & 0x7F : v;
  };

  // ---- helpers ----
  function b64ToBytes(s) {
    if (typeof Buffer !== 'undefined') return Buffer.from(s, 'base64');
    var bin = atob(s), out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function loadFirmwareImage(mem, fw) {
    fw.segments.forEach(function (seg) {
      var addr = seg[0], bytes = b64ToBytes(seg[1]);
      for (var i = 0; i < bytes.length; i++) mem[addr + i] = bytes[i];
    });
  }
  // Parse an Elf2K ".lst": D <addr> <hex bytes...>; ignore ';' comment lines.
  function parseLst(text) {
    var pokes = [];   // [addr, byte]
    text.split(/\r?\n/).forEach(function (ln) {
      var s = ln.trim();
      if (s[0] === ';') return;
      var m = /^D\s+([0-9A-Fa-f]{4})\s+(.+)/.exec(s);
      if (!m) return;
      var a = parseInt(m[1], 16);
      m[2].split(/\s+/).forEach(function (tok) {
        if (/^[0-9A-Fa-f]{2}$/.test(tok)) { pokes.push([a, parseInt(tok, 16)]); a++; }
        else return;
      });
    });
    return pokes;
  }

  // ---- the STELLAR VM ----
  // opts: { firmware, program (lst text or pokes array), input (string) }
  function StellarVM(opts) {
    this.firmware = opts.firmware || (typeof window !== 'undefined' && window.STELLAR_FIRMWARE);
    if (!this.firmware) throw new Error('firmware image not provided');
    this.programPokes = typeof opts.program === 'string' ? parseLst(opts.program)
      : (opts.program || []);
    this.input = opts.input || '';
    // Cold boot through CIDP instead of the hand-built register state. Programs
    // that WAIT (Starfield at its prompt, Invaders for a key) reach the firmware's
    // "all VMs done" path, and the hand-built state has no VM registered there, so
    // they restarted from the top for ever. ON by default since V0061.27: the
    // hand-built path only ever worked because the firmware then did SEP R1 with
    // R1=0 and cold-booted anyway, and its exit relied on $0033 happening to be $00.
    // The golden fixtures are taken on the cold boot too. Pass coldBoot:false for
    // the old hand-built state.
    this.coldBoot = opts.coldBoot !== false;
    this.keepRam = opts.keepRam || null;
    this.reset();
  }
  StellarVM.prototype.reset = function () {
    var mem = new Uint8Array(0x10000);
    loadFirmwareImage(mem, this.firmware);
    // RAM that outlives a load, as on the Elf2K (opts.keepRam = {addr, bytes}): the
    // Simulator carries Lite-Writer 2's slot pool over, so text Morse Receiver v11 left
    // in a slot opens in Lite-Writer. The program's own bytes still win.
    if (this.keepRam) mem.set(this.keepRam.bytes, this.keepRam.addr);
    this.programPokes.forEach(function (p) { mem[p[0]] = p[1]; });
    // core setup (calc_interactive.run_calc)
    mem[CORE + 0x3B] = 1;      // relative addressing mode
    mem[CORE + 0x5B] = 0x40;   // program-block page
    mem[CORE + 0x5C] = 0x00;
    var c = new CPU(mem);
    c.io_out[2] = [];
    c.io_in[3] = new UART(this.input, c.io_out);
    c.rtc = c.io_in[3].rtc = new RTC();
    if (this.coldBoot) {
      c.R[0] = 0x0000; c.P = 0; c.X = 0;
      c.R[1] = EXIT_IDL;               // return-to-monitor vector: an address that is always $00 (IDL)
      this.cpu = c;
      this.serialLen = 0; this.lastOpCost = 0;
      this._bootUntilReady();
      return;
    }
    c.R[4] = 0x0340; c.R[5] = 0x0360; c.R[2] = 0x2FF0; c.R[6] = 0;
    c.R[12] = 0x3000; c.R[8] = ENTRY; c.R[3] = 0x0100; c.P = 3; c.X = 2;
    this.cpu = c;
    this.serialLen = 0;
    this.lastOpCost = 0;   // raw 1802 instructions the last STELLAR opcode took
  };
  // Step the firmware's own start-up until VM1 exists and is active.
  StellarVM.prototype._bootUntilReady = function (cap) {
    cap = cap || 800000;
    var c = this.cpu, M = c.M, g = 0;
    while (g++ < cap) {
      if (!c.step()) return false;
      if (M[0x2F54] >= 1) {
        for (var v = 0; v < 4; v++) if (M[0x2F00 + v * 0x10 + 5] === 0x01) return true;
      }
    }
    return false;
  };
  // Run to completion (halt), returning captured serial output bytes.
  StellarVM.prototype.runToSerial = function (maxSteps) {
    maxSteps = maxSteps || 80000000;
    var c = this.cpu;
    for (var i = 0; i < maxSteps; i++) { if (!c.step()) break; }
    return this.serialOut();
  };
  StellarVM.prototype.serialOut = function () {
    return Uint8Array.from(this.cpu.io_out[3] || []);
  };
  StellarVM.prototype.serialText = function () {
    var b = this.serialOut(), s = '';
    for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
    return s;
  };
  // Read a byte / 16-bit word from the running core (for the visualizers).
  StellarVM.prototype.mem = function (a) { return this.cpu.M[a]; };
  StellarVM.prototype.coreByte = function (off, vmCore) { return this.cpu.M[(vmCore || CORE) + off]; };
  StellarVM.prototype.coreWord = function (off, vmCore) {
    var base = (vmCore || CORE) + off; return (this.cpu.M[base] << 8) | this.cpu.M[base + 1];
  };

  // Structured snapshot of any VM core block ($3000/$3400/$3800/$3C00).
  function readCore(M, base) {
    function b(o) { return M[base + o]; }
    function w(o) { return (M[base + o] << 8) | M[base + o + 1]; }
    var regs = [];
    for (var i = 0; i < 16; i++) regs.push((M[base + i * 2] << 8) | M[base + i * 2 + 1]);
    return {
      regs: regs,
      acc: w(0x20),
      // MA was relocated + widened: 4 int bytes +$68-$6B, remainder +$6C-$6D, sign +$6E.
      maBytes: [b(0x68), b(0x69), b(0x6A), b(0x6B)], maRem: w(0x6C), maSign: b(0x6E),
      daBytes: [b(0x28), b(0x29), b(0x2A), b(0x2B)],
      daRemBytes: [b(0x2C), b(0x2D), b(0x2E)], daSign: b(0x2F),
      cmd: b(0x30), pl: w(0x31),
      cmdCounter: b(0x33) * 0x1000000 + (b(0x34) << 16) + (b(0x35) << 8) + b(0x36),
      flags: { test: b(0x45), carry: b(0x48), overflow: b(0x49), hexdec: b(0x4A) },
      intCounter: b(0x5E), intMax: b(0x5F), memMode: b(0x3B),
      raw: Array.from(M.subarray(base, base + 256))
    };
  }

  // Structured snapshot of a VM core (default VM1) for the visualizers.
  StellarVM.prototype.snapshot = function (vmCore) {
    var base = vmCore || CORE;
    var s = readCore(this.cpu.M, base);
    s.steps = this.cpu.steps; s.lastOpCost = this.lastOpCost || 0;
    s.halted = this.cpu.halted; s.pc1802 = this.cpu.R[this.cpu.P];
    // ---- Elf2K front panel: Q lamp + the latched output byte ----
    // The output port is whatever DEFOUT ($01 0Z) last set at core $x039; the
    // Elf2K default is port 4. io_out[port] is the write log, so the last entry
    // is what the hardware latch would be showing.
    s.q = this.cpu.Q ? 1 : 0;
    var port = this.cpu.M[base + 0x39] || 4;
    var log = this.cpu.io_out[port];
    s.outPort = port;
    s.outByte = (log && log.length) ? log[log.length - 1] : null;
    return s;
  };

  // Command counter (VM1) — increments once per real STELLAR opcode.
  StellarVM.prototype._cc = function () {
    var M = this.cpu.M;
    return M[CORE + 0x33] * 0x1000000 + (M[CORE + 0x34] << 16) + (M[CORE + 0x35] << 8) + M[CORE + 0x36];
  };
  // Run past the CD label pre-pass so interactive stepping starts at the first
  // real instruction. The pre-pass walks PL through the program, then real
  // execution restarts at the program base — so we stop the 2nd time PL == base.
  StellarVM.prototype.prime = function (cap) {
    // A cold boot has already run the firmware's start-up, which includes the
    // label pre-pass, so there is nothing to prime.
    if (this.coldBoot) { this.primed = true; return true; }
    cap = cap || 3000000;
    var c = this.cpu, prevAtBase = false, hits = 0, g = 0;
    while (g++ < cap) {
      if (!c.step()) return false;
      var atBase = ((c.M[CORE + 0x31] << 8) | c.M[CORE + 0x32]) === ENTRY;
      if (atBase && !prevAtBase && ++hits === 2) { this.primed = true; return true; }
      prevAtBase = atBase;
    }
    return false;
  };
  // Advance exactly one real STELLAR opcode (until the command counter ticks).
  StellarVM.prototype.stepOpcode = function (cap) {
    cap = cap || 2000000;
    var c = this.cpu, s = this._cc(), start = c.steps, g = 0;
    while (g++ < cap) {
      if (!c.step()) { this.lastOpCost = c.steps - start; return { halted: true, cost: this.lastOpCost }; }
      if (this._cc() !== s) { this.lastOpCost = c.steps - start; return { halted: false, cost: this.lastOpCost }; }
    }
    this.lastOpCost = c.steps - start;
    return { halted: false, capped: true, cost: this.lastOpCost };
  };

  // ---- multi-VM engine (for the scheduler view) ----
  // Boots via STELLAR's real cold-boot ($0000): CREATE_CIDP scans the program
  // blocks and creates one VM per program, then the scheduler round-robins them.
  // opts: { firmware, programs: [lstText|pokes, ...] (up to 4), input }
  function MultiVM(opts) {
    this.firmware = opts.firmware || (typeof window !== 'undefined' && window.STELLAR_FIRMWARE);
    if (!this.firmware) throw new Error('firmware image not provided');
    this.programs = (opts.programs || []).map(function (p) {
      return typeof p === 'string' ? parseLst(p) : p;
    });
    this.input = opts.input || '';
    this.reset();
  }
  MultiVM.prototype.reset = function () {
    var mem = new Uint8Array(0x10000);
    loadFirmwareImage(mem, this.firmware);
    // load program i into block $4000 + i*$1000 (relocate from its $4000 base)
    this.programs.forEach(function (pokes, i) {
      var off = i * 0x1000;
      pokes.forEach(function (p) { mem[(p[0] + off) & 0xFFFF] = p[1]; });
    });
    var c = new CPU(mem);
    c.io_out[2] = [];
    c.io_in[3] = new UART(this.input, c.io_out);
    c.rtc = c.io_in[3].rtc = new RTC();
    c.R[0] = 0x0000; c.P = 0; c.X = 0;   // cold boot from the reset vector
    // R1 = interrupt/exit handler PC. On the Elf2K the monitor sets this so that
    // "all VMs done" (SEP R1 at $02E2) returns to the monitor. Point it at an IDL
    // (EXIT_IDL, always $00) so the sim halts cleanly instead of looping back to the reset
    // vector and re-running every program (which double-ran the whole boot).
    c.R[1] = EXIT_IDL;
    this.cpu = c;
    this.serialLen = 0;
    // per-VM raw-1802 accounting (index by VM number 1..4)
    this.vmSteps = [0, 0, 0, 0, 0];    // total 1802 instructions each VM has run
    this.vmLastOp = [0, 0, 0, 0, 0];   // 1802 instructions the VM's last opcode took
  };
  MultiVM.prototype.coreBase = function (vm) { return 0x3000 + (vm - 1) * 0x400; };
  MultiVM.prototype.currentVM = function () { return this.cpu.M[0x2F52]; };
  MultiVM.prototype._cc = function (vm) {
    if (vm < 1 || vm > 4) return -1;
    var M = this.cpu.M, base = this.coreBase(vm) + 0x33;
    return M[base] * 0x1000000 + (M[base + 1] << 16) + (M[base + 2] << 8) + M[base + 3];
  };
  MultiVM.prototype.snapshotVM = function (vm) {
    var s = readCore(this.cpu.M, this.coreBase(vm));
    s.vm = vm;
    s.steps = this.vmSteps[vm] || 0;      // this VM's own 1802 total (not the global)
    s.lastOpCost = this.vmLastOp[vm] || 0; // this VM's last-opcode 1802 cost
    return s;
  };
  MultiVM.prototype.cidp = function () {
    var M = this.cpu.M, vms = [];
    for (var v = 0; v < 4; v++) {
      var b = 0x2F00 + v * 0x10;
      vms.push({
        num: M[b], corePage: M[b + 1], progPage: M[b + 2], maxSize: M[b + 3],
        count: M[b + 4], state: M[b + 5],
        cmds: M[b + 6] * 0x1000000 + (M[b + 7] << 16) + (M[b + 8] << 8) + M[b + 9],
        mode: M[b + 0x0A], status: M[b + 0x0B]
      });
    }
    return {
      vms: vms, sysIntState: M[0x2F50], vmError: M[0x2F51], currentVM: M[0x2F52],
      maxVMs: M[0x2F53], totalVMs: M[0x2F54], multitasking: M[0x2F55],
      operation: M[0x2F56], repeat: M[0x2F57], hwIntFF: M[0x2F5F]
    };
  };
  // Advance until the current VM retires one opcode OR the scheduler switches VMs.
  MultiVM.prototype.stepSlice = function (cap) {
    cap = cap || 3000000;
    var c = this.cpu, vm0 = this.currentVM(), cc0 = this._cc(vm0), g = 0;
    var start = (vm0 >= 1 && vm0 <= 4) ? this.vmSteps[vm0] : 0;
    while (g++ < cap) {
      var cur = this.currentVM();               // attribute this instruction to the running VM
      if (!c.step()) return { halted: true };
      if (cur >= 1 && cur <= 4) this.vmSteps[cur]++;
      var vm = this.currentVM();
      if (vm !== vm0) return { switched: true, from: vm0, to: vm };
      if (this._cc(vm) !== cc0) {
        if (vm >= 1 && vm <= 4) this.vmLastOp[vm] = this.vmSteps[vm] - start;
        return { opcode: true, vm: vm };
      }
    }
    return { capped: true };
  };
  // Run the cold boot (CREATE_CIDP + scheduler) until a VM is active, so the
  // caller can start stepping at "VMs ready" (analogous to the pre-pass prime).
  MultiVM.prototype.bootUntilReady = function (cap) {
    cap = cap || 800000;
    // how many VMs the scan should find: the programs that have code (an empty slot - the
    // block a two-block app borrows on the home page - makes no VM)
    var c = this.cpu, g = 0, want = this.programs.filter(function (p) { return p.length; }).length;
    while (g++ < cap) {
      if (!c.step()) return false;
      if (this.cpu.M[0x2F54] >= want && this.currentVM() >= 1 && this.anyActive()) {
        this.booted = true; return true;
      }
    }
    return false;
  };
  MultiVM.prototype.serialOut = function () { return Uint8Array.from(this.cpu.io_out[3] || []); };
  MultiVM.prototype.anyActive = function () {
    var M = this.cpu.M;
    for (var v = 0; v < 4; v++) if (M[0x2F00 + v * 0x10 + 5] === 0x01) return true;
    return false;
  };

  return {
    CPU: CPU, UART: UART, RTC: RTC, StellarVM: StellarVM, MultiVM: MultiVM,
    parseLst: parseLst, loadFirmwareImage: loadFirmwareImage, readCore: readCore,
    CORE: CORE, ENTRY: ENTRY
  };
});
