// Simulator controller: loads a program, drives it opcode-by-opcode, and keeps
// the disassembly side panel, the live core view, and the serial terminal in
// sync. Shared by simulator.html and core.html.
(function (root, factory) {
  var api = factory();
  if (typeof window !== 'undefined') window.SimApp = api;
})(this, function () {
  'use strict';

  var ENTRY = 0x4000;
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
    this.onState = opts.onState || function () {};
  }

  SimApp.prototype.load = function (programText, input) {
    this.stop();
    this.programText = programText;
    this.input = input || '';
    this.vm = new window.StellarVM({
      firmware: window.STELLAR_FIRMWARE, program: programText, input: this.input
    });
    // run the label pre-pass so stepping starts at the first real instruction
    this.vm.prime();
    this._buildDisasm();
    if (this.coreView) this.coreView.reset();
    this.serialLen = 0;
    if (this.opts.terminalEl) this.opts.terminalEl.textContent = '';
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
        '<span class="dis-ops">' + (ln.operandHex || '') + '</span>';
      frag.appendChild(row);
      this.rows[ln.addr] = row;
    }, this);
    host.appendChild(frag);
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

  SimApp.prototype._appendSerial = function () {
    var term = this.opts.terminalEl;
    if (!term) return;
    var out = this.vm.cpu.io_out[3] || [];
    if (out.length > this.serialLen) {
      var s = '';
      for (var i = this.serialLen; i < out.length; i++) {
        var b = out[i];
        s += (b === 13) ? '' : String.fromCharCode(b);   // swallow lone CR, keep LF
      }
      term.textContent += s;
      this.serialLen = out.length;
      term.scrollTop = term.scrollHeight;
    }
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
    this._setStatus('running…');
    var self = this;
    this.timer = setInterval(function () {
      for (var i = 0; i < self.opsPerTick; i++) {
        var r = self.vm.stepOpcode();
        if (r.halted) { self._render(); self.stop(); self._setStatus('halted — program ended'); return; }
      }
      self._render();
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
    if (this.opts.terminalEl) this.opts.terminalEl.textContent = '';
    this._render();
    this._setStatus('reset — label pre-pass complete');
  };

  SimApp.prototype.setSpeed = function (opsPerTick, tickMs) {
    this.opsPerTick = opsPerTick; this.tickMs = tickMs;
    if (this.running) { this.stop(); this.run(); }
  };

  SimApp.prototype._setStatus = function (msg) {
    if (this.opts.statusEl) this.opts.statusEl.textContent = msg;
  };

  return SimApp;
});
