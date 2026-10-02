// Simulator controller: loads a program, drives it opcode-by-opcode, and keeps
// the disassembly side panel, the live core view, and the serial terminal in
// sync. Shared by simulator.html and core.html.
(function (root, factory) {
  var api = factory();
  if (typeof window !== 'undefined') window.SimApp = api;
})(this, function () {
  'use strict';

  var ENTRY = 0x4000;
  var CPI = 375000 / 170000;   // Elf2K machine cycles a second / ClockRow's instructions a second
  function hx(v, n) { return v.toString(16).toUpperCase().padStart(n, '0'); }

  // opts: { coreEl, disasmEl, terminalEl, statusEl } (any subset)
  function SimApp(opts) {
    this.opts = opts;
    this.vm = null;
    this.coreView = opts.coreEl ? new window.CoreView(opts.coreEl) : null;
    this.rows = {};          // addr -> disasm row element
    this.curRow = null;
    this.serialLen = 0;
    this.running = false;
    this.timer = null;
    this.opsPerTick = 1;
    this.tickMs = 120;
    this.breaks = {};        // absolute address -> true
    this._skipBreak = false; // don't re-trigger on the address we just resumed from
    this.onState = opts.onState || function () {};
  }

  // Program Location, as the firmware maintains it at core+$31/$32 — the same
  // value the disassembly highlights. Read directly rather than via snapshot()
  // so the run loop can check it after every opcode without the extra work.
  SimApp.prototype._pl = function () {
    var M = this.vm.cpu.M, b = 0x3000;
    return (M[b + 0x31] << 8) | M[b + 0x32];
  };

  SimApp.prototype.toggleBreak = function (addr) {
    if (this.breaks[addr]) delete this.breaks[addr]; else this.breaks[addr] = true;
    var row = this.rows[addr];
    if (row) row.classList.toggle('dis-bp', !!this.breaks[addr]);
    return !!this.breaks[addr];
  };

  SimApp.prototype.clearBreaks = function () {
    var self = this;
    Object.keys(this.breaks).forEach(function (a) {
      var row = self.rows[a];
      if (row) row.classList.remove('dis-bp');
    });
    this.breaks = {};
  };

  SimApp.prototype.breakCount = function () { return Object.keys(this.breaks).length; };

  SimApp.prototype.load = function (programText, input) {
    this.stop();
    this.programText = programText;
    this.input = input || '';
    this.vm = new window.StellarVM({
      firmware: window.STELLAR_FIRMWARE, program: programText, input: this.input,
      coldBoot: !!this.opts.coldBoot
    });
    // run the label pre-pass so stepping starts at the first real instruction
    this.vm.prime();
    this._buildDisasm();
    if (this.coreView) this.coreView.reset();
    this.serialLen = 0;
    if (this._vtObj) this._vtObj.reset();
    else if (this.opts.terminalEl) this.opts.terminalEl.textContent = '';
    this._render();
    this._setStatus('ready — label pre-pass complete');
  };

  SimApp.prototype._buildDisasm = function () {
    var host = this.opts.disasmEl;
    if (!host) return;
    host.innerHTML = '';
    this.rows = {};
    var d = window.StellarDisasm.disassemble(this.vm.cpu.M, ENTRY, ENTRY + 0x0FFF);
    var frag = document.createDocumentFragment();
    d.lines.forEach(function (ln) {
      var row = document.createElement('div');
      row.className = 'dis-row' + (ln.isEnd ? ' dis-end' : '');
      row.innerHTML =
        '<span class="dis-addr">' + hx(ln.addr, 4) + '</span>' +
        '<span class="dis-bytes">' + ln.bytes.map(function (b) { return hx(b, 2); }).join(' ') + '</span>' +
        '<span class="dis-name">' + ln.name + '</span>' +
        '<span class="dis-ops">' + (ln.operandText || ln.operandHex || '') + '</span>';
      row.dataset.addr = ln.addr;
      if (this.breaks[ln.addr]) row.classList.add('dis-bp');
      frag.appendChild(row);
      this.rows[ln.addr] = row;
    }, this);
    host.appendChild(frag);
    // Click a line to toggle a breakpoint on it. Bound once on the container so
    // it survives the panel being rebuilt for each newly loaded program.
    if (!host._bpBound) {
      host._bpBound = true;
      var self = this;
      host.addEventListener('click', function (e) {
        var row = e.target.closest ? e.target.closest('.dis-row') : null;
        if (!row || row.dataset.addr === undefined) return;
        self.toggleBreak(+row.dataset.addr);
        if (self.opts.onBreaksChanged) self.opts.onBreaksChanged(self.breakCount());
      });
    }
  };

  SimApp.prototype._highlight = function (pl) {
    if (this.curRow) this.curRow.classList.remove('dis-cur');
    var row = this.rows[pl];
    if (row) {
      row.classList.add('dis-cur');
      this.curRow = row;
      var host = this.opts.disasmEl;
      var top = row.offsetTop - host.clientHeight / 2;
      host.scrollTop = Math.max(0, top);
    }
  };

  // The terminal is a VT100, so the full-screen programs (Starfield, Invaders,
  // Bouncing-Ball, Starship, Game of Life) draw properly instead of spraying
  // escape sequences as text. Teletype programs are unchanged: CR/LF scrolls, and
  // lines pushed off the top are kept in the scrollback.
  SimApp.prototype._vt = function () {
    var term = this.opts.terminalEl;
    if (!term) return null;
    if (!this._vtObj && window.VT100) this._vtObj = window.VT100(term);
    return this._vtObj || null;
  };

  SimApp.prototype._appendSerial = function () {
    var term = this.opts.terminalEl;
    if (!term) return;
    var out = this.vm.cpu.io_out[3] || [];
    if (out.length <= this.serialLen) return;
    var vt = this._vt();
    if (vt) {
      vt.write(out.slice(this.serialLen));
      vt.render();
    } else {                                   // vt100.js missing - old behaviour
      var s = '';
      for (var i = this.serialLen; i < out.length; i++) {
        var b = out[i];
        s += (b === 13) ? '' : String.fromCharCode(b);
      }
      term.textContent += s;
      term.scrollTop = term.scrollHeight;
    }
    this.serialLen = out.length;
  };

  SimApp.prototype._render = function () {
    var snap = this.vm.snapshot();
    if (this.coreView) this.coreView.render(snap);
    this._highlight(snap.pl);
    this._appendSerial();
    this.onState(snap);
    return snap;
  };

  SimApp.prototype.step = function () {
    if (!this.vm) return;
    var r = this.vm.stepOpcode();
    var snap = this._render();
    if (r.halted || snap.halted) { this.stop(); this._setStatus('halted — program ended'); }
    else if (r.capped) { this.stop(); this._setStatus('paused — long opcode (cycle cap hit)'); }
    return r;
  };

  SimApp.prototype.run = function () {
    if (this.running || !this.vm) return;
    this.running = true;
    // Resuming while stopped ON a breakpoint would otherwise hit it again at once.
    this._skipBreak = !!this.breaks[this._pl()];
    this._setStatus('running…');
    var self = this;
    var last = Date.now(), credit = 0;
    this.timer = setInterval(function () {
      var now = Date.now(), budget = Infinity, c = self.vm.cpu, c0 = c.cycles;
      if (self.instrPerSec) {
        // Real time is paced in 1802 MACHINE CYCLES, the hardware's own clock (an
        // Elf2K runs 375,000 a second; ClockRow quotes it as ~170,000 instructions).
        // The budget is a running credit: one opcode can outlast a tick - a RUNMC
        // tone holds the machine for a whole dash - and the debt is paid back by
        // waiting, so the machine never drifts ahead of the wall clock. A long gap
        // (a backgrounded tab) is capped so it does not race to catch up.
        credit = Math.min(credit + Math.min(now - last, 60) / 1000 * self.instrPerSec * CPI, 0.06 * self.instrPerSec * CPI);
        budget = credit;
      }
      last = now;
      for (var i = 0; self.instrPerSec ? c.cycles - c0 < budget : i < self.opsPerTick; i++) {
        var r = self.vm.stepOpcode();
        // stop() before _render(): the render fires onState, and the page decides
        // the Run/Step/Pause button states from this.running — rendering first
        // would leave them disabled after we have already stopped.
        if (r.halted) { self.stop(); self._render(); self._setStatus('halted — program ended'); return; }
        if (self.breakCount()) {
          var pl = self._pl();
          if (self._skipBreak) { self._skipBreak = false; }
          else if (self.breaks[pl]) {
            self.stop(); self._render();
            self._setStatus('breakpoint — stopped at $' + hx(pl, 4) + ' (Step ▸ to continue)');
            return;
          }
        }
      }
      if (self.instrPerSec) credit -= c.cycles - c0;
      self._render();
      if (self.opts.onTick) self.opts.onTick(self.vm, self.instrPerSec);
    }, this.tickMs);
  };

  SimApp.prototype.stop = function () {
    this.running = false;
    if (this.timer) { clearInterval(this.timer); this.timer = null; }
  };

  SimApp.prototype.reset = function () {
    if (!this.vm) return;
    this.stop();
    this.vm.reset();
    this.vm.prime();
    if (this.coreView) this.coreView.reset();
    this.serialLen = 0;
    if (this._vtObj) this._vtObj.reset();
    else if (this.opts.terminalEl) this.opts.terminalEl.textContent = '';
    this._render();
    this._setStatus('reset — label pre-pass complete');
  };

  // instrPerSec, when given, paces the machine by REAL TIME instead of by opcodes:
  // each tick spends the 1802 instructions that much wall-clock time buys, so
  // games and delay loops run as they do on the hardware.
  SimApp.prototype.setSpeed = function (opsPerTick, tickMs, instrPerSec) {
    this.opsPerTick = opsPerTick; this.tickMs = tickMs; this.instrPerSec = instrPerSec || 0;
    if (this.running) { this.stop(); this.run(); }
  };

  SimApp.prototype._setStatus = function (msg) {
    if (this.opts.statusEl) this.opts.statusEl.textContent = msg;
  };

  return SimApp;
});
