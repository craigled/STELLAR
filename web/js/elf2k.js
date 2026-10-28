// Elf2K: the whole machine LTOS runs on, for the LTOS page.
//
// The same 1802 core as the rest of the site (StellarVMLib.CPU), with what LTOS needs around it - a port of
// the Python simulator every LTOS test boots (LTOS/verify_phase0.py's Elf2K, and cftest_verify.py's CF card):
//
//   * port 2 picks a register: $10 / $15 the UART's data / line status, $80 + n the DS12887 clock's register
//     n, and anything with bits $90 clear one of the CF card's IDE registers (0-7). Port 3 reads / writes it.
//     INP 2 says a card is there ($30).
//   * the UART: keys go into a queue (`uart.buf`, which term-input.js fills), so none is lost - unless the
//     page asks for the Elf2K's own: ONE byte, at 19200 baud, a byte that comes before the last was read
//     overwrites it (`authentic`).
//   * the CF card: the IDE registers, 8-bit transfers, READ / WRITE SECTOR, on an image held as a Map of
//     sectors (a sector never written reads as zeros). Writes are noted in `dirty` for the page to save.
//   * the clock: the site's DS12887 (this computer's time).
//   * $0000-$2EFF: the STELLAR firmware, as on Craig's Elf2K at power-on; $8000-$FFFF: the web BIOS
//     (LTOS/webbios.asm - our own stand-in for the Elf2K ROM; webbios.js carries its bytes).
//
// Browser + Node.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.Elf2K = api;
})(this, function () {
  'use strict';

  var LIB = (typeof window !== 'undefined' && window.StellarVMLib) || require('./stellar-vm.js');

  // ---- the CF card (cftest_verify.CF) ----
  function CF(sectors, image) {
    this.n = sectors;
    this.disk = image || new Map();       // lba -> Uint8Array(512)
    this.reg = new Uint8Array(16); this.status = 0x50; this.err = 0; this.bit8 = false;
    this.busy = 0; this.buf = null; this.pos = 0; this.mode = null; this.wbuf = []; this.wlba = 0;
    this.dirty = new Set();
  }
  var ZERO = new Uint8Array(512);
  CF.prototype.sector = function (lba) { return this.disk.get(lba) || ZERO; };
  CF.prototype.lba = function () {
    var r = this.reg;
    if (!(r[6] & 0x40)) return null;
    return (r[3] | (r[4] << 8) | (r[5] << 16) | ((r[6] & 0x0F) << 24)) >>> 0;
  };
  CF.prototype.read = function (r) {
    if (r === 7 || r === 14) {
      if (this.busy) { this.busy--; return 0x80; }
      return this.status;
    }
    if (r === 1) return this.err;
    if (r === 0) {
      if (this.mode !== 'out' || !(this.status & 0x08)) return 0xFF;
      var b = this.buf[this.pos]; this.pos += this.bit8 ? 1 : 2;
      if (this.pos >= 512) { this.status &= ~0x08; this.mode = null; }
      return b;
    }
    return this.reg[r];
  };
  CF.prototype.write = function (r, v) {
    if (r === 14) {
      if (v & 0x04) { this.bit8 = false; this.status = 0x50; this.busy = 5; this.mode = null; }
      return;
    }
    if (r === 0) {
      if (this.mode === 'in' && (this.status & 0x08)) {
        this.wbuf.push(v);
        if (!this.bit8) this.wbuf.push(0);
        if (this.wbuf.length >= 512) {
          this.disk.set(this.wlba, Uint8Array.from(this.wbuf.slice(0, 512))); this.dirty.add(this.wlba);
          this.status = 0x50; this.busy = 4; this.mode = null;
        }
      }
      return;
    }
    if (r === 7) return this.command(v);
    this.reg[r] = v;
  };
  CF.prototype.command = function (v) {
    this.err = 0; this.busy = 3; this.status = 0x50;
    if (v === 0xEF) {
      if (this.reg[1] === 0x01) this.bit8 = true; else this.fail(0x04);
    } else if (v === 0xEC) {
      this.buf = identify(this.n); this.pos = 0; this.mode = 'out'; this.status = 0x58;
    } else if (v === 0x20 || v === 0x30) {
      var lba = this.lba();
      if (lba === null || lba >= this.n || this.reg[2] !== 1) return this.fail(0x10);
      if (v === 0x20) { this.buf = this.sector(lba); this.pos = 0; this.mode = 'out'; this.status = 0x58; }
      else { this.wbuf = []; this.wlba = lba; this.mode = 'in'; this.status = 0x58; }
    } else this.fail(0x04);
  };
  CF.prototype.fail = function (e) { this.err = e; this.status = 0x51; this.mode = null; };

  // IDENTIFY DEVICE (cftest_verify.identify): the serial number, firmware, model name, LBA and the size
  var MODEL = 'LTOS web card';
  function identify(n) {
    var w = new Uint16Array(256);
    function s(at, k, txt) {
      txt = txt.padEnd(2 * k, ' ');
      for (var i = 0; i < k; i++) w[at + i] = (txt.charCodeAt(2 * i) << 8) | txt.charCodeAt(2 * i + 1);
    }
    w[0] = 0x848A; s(10, 10, 'X1234 56789'); s(23, 4, 'HDX 4.04'); s(27, 20, MODEL);
    w[49] = 0x0200; w[60] = n & 0xFFFF; w[61] = n >>> 16;
    var b = new Uint8Array(512);
    for (var k = 0; k < 256; k++) { b[2 * k] = w[k] & 0xFF; b[2 * k + 1] = w[k] >> 8; }
    return b;
  }

  // ---- the machine ----
  var BAUD_T = 48;          // 1802 instructions a byte takes at 19200 baud (authentic UART)

  function Machine(opts) {
    this.bios = opts.bios;                 // 32 KB, $8000-$FFFF
    this.firmware = opts.firmware;         // STELLAR, at $0000
    this.cf = new CF(opts.sectors || 16384, opts.card);
    this.onOutput = opts.onOutput || function () {};
    this.authentic = false;
    this.reset();
  }

  Machine.prototype.reset = function () {
    var self = this, M = new Uint8Array(0x10000);
    if (this.firmware) {                   // ($0000-$2FFF, as the Python Elf2K has it)
      var fw = new Uint8Array(0x10000); LIB.loadFirmwareImage(fw, this.firmware); M.set(fw.subarray(0, 0x3000), 0);
    }
    M.set(this.bios, 0x8000);
    var c = this.cpu = new LIB.CPU(M);
    this.M = M;
    var sel = { 0: 0x15, length: 1, push: function (v) { this[0] = v; } };   // port 2: only the last matters
    var cf = this.cf, uart = this.uart = { buf: [], rbr: -1, lost: 0, next: 0 };
    c.rtc = new LIB.RTC();                  // (a test may put its own clock here)
    c.io_out[2] = sel;
    c.io_out[3] = { push: function (v) {
      var s = sel[0];
      if ((s & 0x90) === 0) cf.write(s & 0x1F, v);
      else if (s === 0x10) self.onOutput(v);
    } };
    c.io_in[3] = { buf: uart.buf, pop: function () {
      var s = sel[0];
      if ((s & 0x90) === 0) return cf.read(s & 0x1F);
      if (s === 0x10 || s === 0x15) {
        if (self.authentic) self._arrive();
        if (s === 0x10) {
          if (self.authentic) { var b = uart.rbr; uart.rbr = -1; return b < 0 ? 0 : b; }
          return uart.buf.length ? uart.buf.shift() : 0;
        }
        return 0x60 | ((self.authentic ? uart.rbr >= 0 : uart.buf.length) ? 1 : 0);
      }
      if (s & 0x80) return c.rtc.read(s & 0x7F);
      return 0;
    } };
    c.io_in[2] = { pop: function () { return 0x30; } };
    for (var p = 1; p <= 7; p++) if (!c.io_in[p]) c.io_in[p] = { pop: function () { return 0; } };
    // power on as the BIOS's BOOT: R2 a stack, RE.1 = 1 (the UART, echo), P = R3 at F_BOOT
    c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3;
    this.instr = 0;
  };

  // authentic UART: the queued keys arrive one per BAUD_T instructions; one not read before the next is lost
  Machine.prototype._arrive = function () {
    var u = this.uart;
    while (u.buf.length && this.instr >= u.next) {
      if (u.rbr >= 0) u.lost++;
      u.rbr = u.buf.shift(); u.next = this.instr + BAUD_T;
    }
    if (!u.buf.length && u.next < this.instr) u.next = this.instr;
  };

  // run up to n instructions; false if the 1802 stopped (IDL)
  Machine.prototype.run = function (n) {
    var c = this.cpu;
    for (var i = 0; i < n; i++) {
      if (!c.step()) { this.instr += i; return false; }
    }
    this.instr += n;
    return true;
  };

  // type bytes at the terminal
  Machine.prototype.keys = function (bytes) {
    for (var i = 0; i < bytes.length; i++) this.uart.buf.push(bytes[i] & 0xFF);
  };

  // ---- the card image: a list of used sectors ----
  // format (ltos-card.bin): 'LTCD', sectors (u32 LE), count (u32 LE), then count x (lba u32 LE, 512 bytes)
  function parseCard(buf) {
    var b = new Uint8Array(buf), dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    if (String.fromCharCode(b[0], b[1], b[2], b[3]) !== 'LTCD') throw new Error('not an LTOS card image');
    var n = dv.getUint32(4, true), count = dv.getUint32(8, true), map = new Map(), p = 12;
    for (var i = 0; i < count; i++) {
      map.set(dv.getUint32(p, true), b.slice(p + 4, p + 516)); p += 516;
    }
    return { sectors: n, map: map };
  }
  function packCard(sectors, map) {
    var keys = Array.from(map.keys()).filter(function (k) {
      var s = map.get(k); for (var i = 0; i < 512; i++) if (s[i]) return true; return false;
    }).sort(function (a, b) { return a - b; });
    var out = new Uint8Array(12 + keys.length * 516), dv = new DataView(out.buffer);
    out.set([0x4C, 0x54, 0x43, 0x44]); dv.setUint32(4, sectors, true); dv.setUint32(8, keys.length, true);
    var p = 12;
    keys.forEach(function (k) { dv.setUint32(p, k, true); out.set(map.get(k), p + 4); p += 516; });
    return out;
  }

  return { Machine: Machine, CF: CF, parseCard: parseCard, packCard: packCard,
           setModel: function (m) { MODEL = m; } };
});
