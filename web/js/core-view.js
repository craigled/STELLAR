// Reusable VM-core panel: renders a snapshot() from stellar-vm.js as registers,
// accumulators, math units, and flags, highlighting the cells the last opcode
// changed. Used by core.html, simulator.html, and (per-core) scheduler.html.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.CoreView = api;
})(this, function () {
  'use strict';

  function opName(op) {
    var t = (typeof window !== 'undefined' && window.STELLAR_OPCODES) || [];
    for (var i = 0; i < t.length; i++) if (t[i].op === op) return t[i].name;
    return 'op' + hx(op, 2);
  }
  function hx(v, n) { return v.toString(16).toUpperCase().padStart(n, '0'); }
  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }

  function CoreView(container, opts) {
    this.root = container;
    this.opts = opts || {};
    this.prev = null;
    this.cells = {};
    this._build();
  }

  CoreView.prototype._cell = function (parent, key, label) {
    var wrap = el('div', 'cv-cell');
    wrap.appendChild(el('span', 'cv-lab', label));
    var v = el('span', 'cv-val mono', '—');
    wrap.appendChild(v);
    parent.appendChild(wrap);
    this.cells[key] = v;
    return v;
  };

  CoreView.prototype._build = function () {
    var r = this.root;
    r.classList.add('coreview');
    r.innerHTML = '';

    // status line
    var status = el('div', 'cv-status');
    status.appendChild(el('span', 'cv-s-op mono', '—'));
    status.appendChild(el('span', 'cv-s-pl mono', ''));
    status.appendChild(el('span', 'cv-s-cc mono', ''));
    status.appendChild(el('span', 'cv-s-steps mono', ''));
    r.appendChild(status);
    this.sOp = status.querySelector('.cv-s-op');
    this.sPl = status.querySelector('.cv-s-pl');
    this.sCc = status.querySelector('.cv-s-cc');
    this.sSteps = status.querySelector('.cv-s-steps');

    var grid = el('div', 'cv-grid');
    r.appendChild(grid);

    // registers
    var regs = el('section', 'cv-sec cv-regs');
    regs.appendChild(el('h4', null, 'Registers'));
    var rgrid = el('div', 'cv-reggrid');
    for (var i = 0; i < 16; i++) this._cell(rgrid, 'R' + i, 'R' + i.toString(16).toUpperCase());
    regs.appendChild(rgrid);
    grid.appendChild(regs);

    // accumulators / math
    var acc = el('section', 'cv-sec cv-accs');
    acc.appendChild(el('h4', null, 'Accumulators & Math'));
    var ag = el('div', 'cv-acclist');
    this._cell(ag, 'acc', 'Acc');
    this._cell(ag, 'ma', 'MA');
    this._cell(ag, 'maRem', 'MA rem');
    this._cell(ag, 'maSign', 'MA sign');
    this._cell(ag, 'da', 'DA');
    this._cell(ag, 'daRem', 'DA rem');
    this._cell(ag, 'daSign', 'DA sign');
    acc.appendChild(ag);
    grid.appendChild(acc);

    // flags / state
    var fl = el('section', 'cv-sec cv-flags');
    fl.appendChild(el('h4', null, 'Flags & State'));
    var fg = el('div', 'cv-acclist');
    this._cell(fg, 'test', 'Test');
    this._cell(fg, 'carry', 'Carry');
    this._cell(fg, 'ovf', 'Overflow');
    this._cell(fg, 'hexdec', 'Hex/Dec');
    this._cell(fg, 'quantum', 'Quantum');
    this._cell(fg, 'memmode', 'Mem mode');
    fl.appendChild(fg);
    grid.appendChild(fl);
  };

  CoreView.prototype.render = function (s) {
    var p = this.prev, self = this;
    function set(key, val, changed) {
      var e = self.cells[key];
      e.textContent = val;
      e.parentNode.classList.toggle('chg', !!changed);
    }
    var i;
    for (i = 0; i < 16; i++) {
      set('R' + i, '$' + hx(s.regs[i], 4), p && p.regs[i] !== s.regs[i]);
    }
    set('acc', '$' + hx(s.acc, 4), p && p.acc !== s.acc);
    var ma = s.maBytes.map(function (b) { return hx(b, 2); }).join(' ');
    set('ma', ma, p && p.maBytes.join() !== s.maBytes.join());
    set('maRem', '$' + hx(s.maRem, 4), p && p.maRem !== s.maRem);
    set('maSign', s.maSign ? '$' + hx(s.maSign, 2) : '+', p && p.maSign !== s.maSign);
    var da = s.daBytes.map(function (b) { return hx(b, 2); }).join(' ');
    set('da', da, p && p.daBytes.join() !== s.daBytes.join());
    set('daRem', s.daRemBytes.map(function (b) { return hx(b, 2); }).join(' '), p && p.daRemBytes.join() !== s.daRemBytes.join());
    set('daSign', s.daSign ? '$' + hx(s.daSign, 2) : '+', p && p.daSign !== s.daSign);

    set('test', s.flags.test ? '● 1' : '○ 0', p && p.flags.test !== s.flags.test);
    set('carry', s.flags.carry ? '● 1' : '○ 0', p && p.flags.carry !== s.flags.carry);
    set('ovf', s.flags.overflow ? '● 1' : '○ 0', p && p.flags.overflow !== s.flags.overflow);
    set('hexdec', s.flags.hexdec ? 'DEC' : 'HEX', p && p.flags.hexdec !== s.flags.hexdec);
    set('quantum', s.intCounter + ' / ' + s.intMax, p && p.intCounter !== s.intCounter);
    set('memmode', s.memMode ? 'REL' : 'ABS', p && p.memMode !== s.memMode);

    // status
    this.sOp.textContent = '$' + hx(s.cmd, 2) + '  ' + opName(s.cmd);
    this.sPl.textContent = 'PL $' + hx(s.pl, 4);
    this.sCc.textContent = 'cmd# ' + s.cmdCounter;
    this.sSteps.textContent = s.steps.toLocaleString() + ' cycles';
    if (s.halted) this.sOp.textContent = 'HALTED';

    this.prev = s;
  };

  CoreView.prototype.reset = function () { this.prev = null; };

  return CoreView;
});
