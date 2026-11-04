// The Simulator's LED console. LedCore shows ONE VM core as rows of lamps, a lamp for
// every bit; LedMem shows the program block a byte to the row, beside its command.
//
// Everything is read straight out of the machine's memory, so the lamps show what is
// really in the core. A bit that keeps changing while the program runs glows at the
// share of the time it was on, as a real lamp seems to: the run loop calls sample()
// after each opcode, and render() turns the counts into brightness.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.LedPanel = api;
})(this, function () {
  'use strict';

  var LEVELS = 12;            // brightness steps
  var GLOW_MS = 90;           // how long a lamp takes to settle at a new brightness
  var FRAME_MS = 28;          // the lamps are redrawn at most this often while running
  var SAMPLES = 16;           // samples wanted between two redraws
  var CIDP = 0x2F00;
  var STATE = { 0: 'done', 1: 'active', 2: 'finished this cycle', 3: 'idle', 4: 'paused', 5: 'killed', 6: 'error', 15: 'unknown' };

  // [name, core offset, bytes, colour (a = address, d = data), can a click flip it?, help]
  var LEFT = [
    ['Execution'],
    ['PL', 0x31, 2, 'a', 0, 'Program Location: the opcode being run'],
    ['OP', 0x30, 1, 'd', 0, 'The opcode being run'],
    ['COUNT', 0x33, 4, 'd', 0, 'Command Counter: opcodes run so far'],
    ['Accumulators'],
    ['ACC', 0x20, 2, 'd', 1, 'Accumulator'],
    ['MA', 0x68, 4, 'd', 1, 'Math Accumulator'],
    ['MA REM', 0x6C, 2, 'd', 1, 'Math remainder'],
    ['MA SIGN', 0x6E, 1, 'd', 1, 'Math sign'],
    ['DA', 0x28, 4, 'd', 1, 'Decimal Accumulator'],
    ['DA REM', 0x2C, 3, 'd', 1, 'Decimal remainder'],
    ['DA SIGN', 0x2F, 1, 'd', 1, 'Decimal sign'],
    ['Stacks and I/O'],
    ['PROG SP', 0x3C, 1, 'a', 0, 'Program stack position'],
    ['CALL SP', 0x58, 1, 'a', 0, 'Call/return stack position'],
    ['I/O', 0x3A, 1, 'd', 0, 'The last byte in or out']
  ];
  // [name, core offset (-1: the 1802's Q line), can a click flip it?, help]
  var FLAGS = [
    ['TEST', 0x45, 1, 'Test flag'], ['CARRY', 0x48, 1, 'Carry flag'], ['OVERFLOW', 0x49, 1, 'Overflow flag'],
    ['DECIMAL', 0x4A, 1, 'Hex/Decimal flag'], ['INT', 0x4C, 0, 'Interrupt flag'],
    ['ERROR', 0x4F, 0, 'Error register is not zero'], ['Q', -1, 0, 'The 1802 Q line, shared by every VM']
  ];
  var QUIET = { PL: 1, OP: 1, COUNT: 1 };        // these change on every step: no highlight

  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }
  function hx(v, n) { return v.toString(16).toUpperCase().padStart(n, '0'); }
  function opName(op) {
    var t = (typeof window !== 'undefined' && window.STELLAR_OPCODES) || [];
    for (var i = 0; i < t.length; i++) if (t[i].op === op) return t[i].name;
    return '';
  }
  function vmThere(M, v) {
    var c = 0x3000 + (v - 1) * 0x400 + 0x33;
    return !!(M[CIDP + (v - 1) * 0x10 + 5] || M[c] || M[c + 1] || M[c + 2] || M[c + 3]);
  }
  function lamp(colour) {
    var i = el('i', 'led led-' + colour), b = el('b');
    i.appendChild(b);
    return { host: i, lit: b };
  }

  // opts: { cpu(): the live CPU or null, running(): bool, stats(): {op, total}, onFlip(text), onRefused() }
  function LedCore(host, opts) {
    this.host = host;
    this.opts = opts;
    this.vmNum = 1;
    this.visible = true;
    this.decimal = false;
    this.rows = [];            // {name, off, len, row, val, note}
    this.offs = []; this.masks = []; this.els = [];   // one entry a lamp
    this._build();
    var n = this.offs.length;
    this.offs = Int32Array.from(this.offs);
    this.masks = Int32Array.from(this.masks);
    this.cnt = new Uint32Array(n);
    this.bright = new Float32Array(n);
    this.level = new Int8Array(n).fill(-1);
    this.samples = 0; this.ops = 0; this.skip = 0; this.stride = 1;
    this.prev = null; this.seen = null; this.t = 0; this.wasOn = true;
  }

  LedCore.prototype._addLamps = function (holder, f, off, len, colour, editable) {
    for (var k = 0; k < len; k++) {
      for (var bit = 7; bit >= 0; bit--) {
        var l = lamp(colour);
        if (editable) { l.host.classList.add('led-ed'); }
        l.host.dataset.i = this.offs.length;
        holder.appendChild(l.host);
        this.offs.push(off + k); this.masks.push(1 << bit); this.els.push(l.lit);
        if (bit === 4 || (bit === 0 && k < len - 1)) holder.appendChild(el('span', 'led-gap'));
      }
    }
  };

  LedCore.prototype._row = function (parent, f) {
    var row = el('div', 'lc-row');
    row.title = f[5] + ' (core +$' + hx(f[1], 2) + ')';
    var name = el('span', 'lc-name lc-' + f[3], f[0]);
    var note = el('span', 'lc-note');
    var holder = el('span', 'lc-leds');
    var val = el('span', 'lc-val', '');
    row.appendChild(name); row.appendChild(note); row.appendChild(holder); row.appendChild(val);
    parent.appendChild(row);
    var first = this.offs.length;
    this._addLamps(holder, f, f[1], f[2], f[3], f[4]);
    this.rows.push({ name: f[0], off: f[1], len: f[2], row: row, val: val, note: note, first: first, text: null, chg: false });
  };

  LedCore.prototype._build = function () {
    var self = this, h = this.host;
    h.classList.add('lc');
    h.innerHTML = '';
    this.lineEl = el('div', 'lc-line');
    h.appendChild(this.lineEl);
    var cols = el('div', 'lc-cols'), left = el('div', 'lc-col'), right = el('div', 'lc-col');
    LEFT.forEach(function (f) {
      if (f.length === 1) left.appendChild(el('div', 'lc-head', f[0]));
      else self._row(left, f);
    });
    right.appendChild(el('div', 'lc-head', 'Registers'));
    for (var r = 0; r < 16; r++) {
      var nm = 'R' + r.toString(16).toUpperCase();
      this._row(right, [nm, r * 2, 2, 'd', 1, 'Register ' + nm]);
    }
    cols.appendChild(left); cols.appendChild(right);
    h.appendChild(cols);
    var flags = el('div', 'lc-flags');
    this.flagInfo = [];
    FLAGS.forEach(function (f) {
      var w = el('span', 'lc-flag'), l = lamp('f');
      w.title = f[3];
      if (f[2]) l.host.classList.add('led-ed');
      l.host.dataset.i = self.offs.length;
      w.appendChild(l.host); w.appendChild(el('span', null, f[0]));
      flags.appendChild(w);
      self.offs.push(f[1]); self.masks.push(0); self.els.push(l.lit);
    });
    h.appendChild(flags);
    this.costEl = el('div', 'lc-cost');
    h.appendChild(this.costEl);
    h.addEventListener('click', function (e) {
      var t = e.target.closest ? e.target.closest('.led-ed') : null;
      if (t) self._flip(+t.dataset.i);
    });
  };

  LedCore.prototype.base = function () { return 0x3000 + (this.vmNum - 1) * 0x400; };
  // The firmware fills in all four rows of the VM table, so a VM is known by its state,
  // or, once it has ended (state 0), by the opcodes it ran.
  LedCore.prototype.vmExists = function (M, v) { return vmThere(M, v); };

  LedCore.prototype.setVM = function (v) {
    this.vmNum = v;
    this.prev = null;
    this.cnt.fill(0); this.samples = 0;
    this.render(true);
  };
  LedCore.prototype.setDecimal = function (d) {
    this.decimal = d;
    this.rows.forEach(function (r) { r.text = null; });
    this.render(true);
  };
  LedCore.prototype.setVisible = function (v) {
    this.visible = v;
    if (v) { this.prev = null; this.render(true); }
  };

  // After every opcode while running. The stride keeps the work to about SAMPLES
  // looks a frame, however many opcodes the speed fits in.
  LedCore.prototype.sample = function () {
    if (!this.visible) return;
    this.ops++;
    if (--this.skip > 0) return;
    this.skip = this.stride;
    var cpu = this.opts.cpu();
    if (!cpu) return;
    var M = cpu.M, b = this.base(), offs = this.offs, masks = this.masks, c = this.cnt;
    for (var i = 0; i < offs.length; i++) {
      var o = offs[i], m = masks[i], v = o < 0 ? cpu.Q : M[b + o];
      if (m ? v & m : v) c[i]++;
    }
    this.samples++;
  };

  // exact: the machine is stopped, so every lamp is simply on or off.
  LedCore.prototype.render = function (exact) {
    if (!this.visible) return;
    var cpu = this.opts.cpu();
    if (!cpu) return;
    var now = Date.now(), dt = now - this.t;
    if (!exact && dt < FRAME_MS) return;
    this.t = now;
    var M = cpu.M, b = this.base(), there = this.vmExists(M, this.vmNum);
    if (this.seen !== cpu) { this.seen = cpu; this.prev = null; }   // a new load or a reset
    var offs = this.offs, masks = this.masks, n = offs.length, a = 1 - Math.exp(-dt / GLOW_MS);
    for (var i = 0; i < n; i++) {
      var o = offs[i], m = masks[i], v = o < 0 ? cpu.Q : M[b + o];
      var on = (o < 0 || there) && (m ? v & m : v) ? 1 : 0, br;
      if (exact || !this.samples) br = this.bright[i] = exact ? on : this.bright[i] + (on - this.bright[i]) * a;
      else br = this.bright[i] += (this.cnt[i] / this.samples - this.bright[i]) * a;
      var lv = Math.round(br * LEVELS);
      if (lv !== this.level[i]) { this.level[i] = lv; this.els[i].style.opacity = lv / LEVELS; }
    }
    this.stride = Math.max(1, Math.floor(this.ops / SAMPLES));
    this.ops = 0; this.samples = 0; this.cnt.fill(0);
    this._readouts(M, b, there, !this.opts.running());
    this._line(M, b, there);
  };

  LedCore.prototype._readouts = function (M, b, there, stopped) {
    var prev = this.prev, dec = this.decimal;
    this.rows.forEach(function (r) {
      var v = 0, ch = false;
      for (var k = 0; k < r.len; k++) {
        v = v * 256 + M[b + r.off + k];
        if (prev && prev[r.off + k] !== M[b + r.off + k]) ch = true;
      }
      var t = !there ? '—' : dec ? String(v) : '$' + hx(v, r.len * 2);
      if (t !== r.text) {
        r.text = t; r.val.textContent = t;
        if (r.name === 'OP') r.note.textContent = there ? opName(v) : '';
      }
      ch = ch && stopped && !QUIET[r.name];
      if (ch !== r.chg) { r.chg = ch; r.row.classList.toggle('chg', ch); }
    });
    this.prev = M.slice(b, b + 256);
  };

  LedCore.prototype._line = function (M, b, there) {
    var v = this.vmNum, s = M[CIDP + (v - 1) * 0x10 + 5];
    var t = there ? 'VM' + v + ' · ' + (STATE[s] || '$' + hx(s, 2)) + ' · core $' + hx(b, 4) + ' · program $' + hx(M[b + 0x5B] << 8, 4)
      : 'VM' + v + ' · not in use: the program has no code in this block';
    if (t !== this.lineText) { this.lineText = t; this.lineEl.textContent = t; }
    this.host.classList.toggle('lc-off', !there);
    var st = this.opts.stats();
    var c = '1802: ' + st.op.toLocaleString() + ' this op · ' + st.total.toLocaleString() + ' total';
    if (c !== this.costText) { this.costText = c; this.costEl.textContent = c; }
  };

  LedCore.prototype._flip = function (i) {
    var cpu = this.opts.cpu();
    if (!cpu || !this.vmExists(cpu.M, this.vmNum)) return;
    if (this.opts.running()) { this.opts.onRefused(); return; }
    var a = this.base() + this.offs[i], m = this.masks[i];
    if (m) cpu.M[a] ^= m; else cpu.M[a] = cpu.M[a] ? 0 : 1;
    this.opts.onFlip('flipped a bit at $' + hx(a, 4) + ': it is now $' + hx(cpu.M[a], 2));
  };

  // ---- the program block, a byte to the row ----
  var ROW = 24;
  // opts: { mem(): the memory or null, isBreak(addr), onToggle(addr) }
  function LedMem(host, opts) {
    var self = this;
    this.host = host;
    this.opts = opts;
    this.items = [];
    this.index = {};
    this.pool = [];
    this.pl = -1;
    this.visible = false;
    host.classList.add('lm');
    this.tall = el('div', 'lm-tall');
    host.appendChild(this.tall);
    host.addEventListener('scroll', function () { self.draw(); });
    host.addEventListener('click', function (e) {
      var r = e.target.closest ? e.target.closest('.lm-row') : null;
      if (r && r._item) { opts.onToggle(r._item.line.addr); self.draw(); }
    });
  }

  LedMem.prototype.setLines = function (lines) {
    var items = [], index = {};
    lines.forEach(function (ln) {
      ln.bytes.forEach(function (x, k) {
        index[ln.addr + k] = items.length;
        items.push({ addr: ln.addr + k, line: ln, first: k === 0 });
      });
    });
    this.items = items; this.index = index; this.pl = -1;
    this.tall.style.height = items.length * ROW + 'px';
    this.pool.forEach(function (p) { p.item = null; });
    this.draw();
  };

  LedMem.prototype.setVisible = function (v) { this.visible = v; if (v) { this.pl = -1; } };

  LedMem.prototype._rowFor = function (k) {
    if (this.pool[k]) return this.pool[k];
    var r = el('div', 'lm-row'), leds = el('span', 'lm-leds'), lit = [];
    var addr = el('span', 'lm-addr'), val = el('span', 'lm-val'), cmd = el('span', 'lm-cmd');
    for (var b = 7; b >= 0; b--) {
      var l = lamp('d');
      leds.appendChild(l.host); lit.push(l.lit);
      if (b === 4) leds.appendChild(el('span', 'led-gap'));
    }
    r.appendChild(addr); r.appendChild(leds); r.appendChild(val); r.appendChild(cmd);
    this.tall.appendChild(r);
    return (this.pool[k] = { r: r, addr: addr, val: val, cmd: cmd, lit: lit, item: null, byte: -1 });
  };

  LedMem.prototype.draw = function () {
    if (!this.visible) return;
    var M = this.opts.mem();
    if (!M) return;
    var h = this.host, first = Math.floor(h.scrollTop / ROW);
    var count = Math.min(Math.ceil(h.clientHeight / ROW) + 1, this.items.length - first);
    for (var k = 0; k < this.pool.length; k++) if (k >= count) this.pool[k].r.style.display = 'none';
    for (k = 0; k < count; k++) {
      var p = this._rowFor(k), it = this.items[first + k], b = M[it.addr];
      if (p.item !== it) {
        p.item = it; p.r._item = it; p.byte = -1;
        p.r.style.display = '';
        p.r.style.transform = 'translateY(' + (first + k) * ROW + 'px)';
        p.addr.textContent = hx(it.addr, 4);
        p.cmd.textContent = it.first ? it.line.name + ' ' + (it.line.operandText || it.line.operandHex || '') : '';
        p.r.classList.toggle('lm-end', !!it.line.isEnd);
      }
      if (p.byte !== b) {
        p.byte = b;
        p.val.textContent = hx(b, 2);
        for (var i = 0; i < 8; i++) p.lit[i].style.opacity = b & (128 >> i) ? 1 : 0;
      }
      p.r.classList.toggle('lm-cur', it.line.addr === this.pl);
      p.r.classList.toggle('lm-bp', !!this.opts.isBreak(it.line.addr));
    }
  };

  LedMem.prototype.render = function (pl) {
    if (!this.visible) return;
    if (pl !== this.pl) {
      this.pl = pl;
      var at = this.index[pl];
      if (at !== undefined) this.host.scrollTop = Math.max(0, at * ROW - this.host.clientHeight / 2);
    }
    this.draw();
  };

  return { LedCore: LedCore, LedMem: LedMem, vmThere: vmThere };
});
