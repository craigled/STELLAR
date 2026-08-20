// Reusable VM-core panel: renders a snapshot() from stellar-vm.js as registers,
// accumulators, math units, and flags, highlighting the cells the last opcode
// changed. A "⊕ all fields" toggle expands to the full decoded core block
// (Program Command/Location, config, every flag, scratch + the MA window).
// Used by core.html, simulator.html, and (per-core) scheduler.html.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.CoreView = api;
})(this, function () {
  'use strict';

  function opName(op) {
    var t = (typeof window !== 'undefined' && window.STELLAR_OPCODES) || [];
    for (var i = 0; i < t.length; i++) if (t[i].op === op) return t[i].name;
    return '';
  }
  function hx(v, n) { return v.toString(16).toUpperCase().padStart(n, '0'); }
  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }

  // Full core map: [offset, byteLen, label, format]. Covers the named fields of
  // the 256-byte core (VM1 $3000). Values are read from snapshot.raw.
  var FIELDS = [
    ['exec', 'Execution'],
    [0x30, 1, 'Program Command', 'op'],
    [0x31, 2, 'Program Location', 'word'],
    [0x33, 4, 'Command Counter', 'u32'],
    ['io', 'I/O & memory'],
    [0x37, 1, 'EF config', 'hex1'],
    [0x38, 1, 'Input port', 'hex1'],
    [0x39, 1, 'Output port', 'hex1'],
    [0x3A, 1, 'I/O byte', 'hex1'],
    [0x3B, 1, 'MEMMODE (addressing)', 'memmode'],
    [0x3C, 1, 'Prog stack loc', 'hex1'],
    [0x40, 1, 'Address modifier', 'hex1'],
    [0x41, 1, 'Mem direction', 'hex1'],
    [0x42, 2, 'Random', 'word'],
    [0x44, 1, 'Delay counter', 'hex1'],
    ['flags', 'Flags & status'],
    [0x45, 1, 'Test flag', 'flag'],
    [0x46, 1, 'Debug flag', 'hex1'],
    [0x47, 1, 'System status', 'hex1'],
    [0x48, 1, 'Carry flag', 'flag'],
    [0x49, 1, 'Overflow flag', 'flag'],
    [0x4A, 1, 'Hex/Dec', 'hexdec'],
    [0x4C, 1, 'Interrupt flag', 'flag'],
    [0x4D, 1, 'Delay remaining', 'hex1'],
    [0x4E, 1, 'ExitCode', 'hex1'],
    [0x4F, 1, 'Error register', 'hex1'],
    ['vm', 'VM config'],
    [0x56, 1, 'Q state', 'flag'],
    [0x57, 1, 'Hardware ID', 'hex1'],
    [0x58, 1, 'C/R stack loc', 'hex1'],
    [0x59, 1, 'VM number', 'hex1'],
    [0x5A, 1, 'Core page', 'hex1'],
    [0x5B, 1, 'Program page', 'hex1'],
    [0x5C, 1, 'CIDP page', 'hex1'],
    [0x5D, 1, 'Data block size', 'hex1'],
    [0x5E, 1, 'Int counter', 'hex1'],
    [0x5F, 1, 'Int counter max', 'hex1'],
    ['scratch', 'Scratch & Math window'],
    [0x60, 3, 'Scratch A', 'bytes'],
    [0x63, 3, 'Scratch B', 'bytes'],
    [0x66, 2, 'Scratch C', 'word'],
    [0x68, 4, 'MA integer', 'bytes'],
    [0x6C, 2, 'MA remainder', 'word'],
    [0x6E, 1, 'MA sign', 'hex1']
  ];

  function fmt(kind, raw, off, len) {
    var b0 = raw[off];
    switch (kind) {
      case 'op': return '$' + hx(b0, 2) + (opName(b0) ? '  ' + opName(b0) : '');
      case 'word': return '$' + hx((raw[off] << 8) | raw[off + 1], 4);
      case 'u32': return (raw[off] * 0x1000000 + (raw[off + 1] << 16) + (raw[off + 2] << 8) + raw[off + 3]).toLocaleString();
      case 'flag': return b0 ? '● 1' : '○ 0';
      case 'hex1': return '$' + hx(b0, 2);
      case 'memmode': return b0 ? 'RELATIVE' : 'ABSOLUTE';
      case 'hexdec': return b0 ? 'DEC' : 'HEX';
      case 'bytes': {
        var s = [];
        for (var i = 0; i < len; i++) s.push(hx(raw[off + i], 2));
        return s.join(' ');
      }
    }
    return '$' + hx(b0, 2);
  }
  function changed(raw, prev, off, len) {
    if (!prev) return false;
    for (var i = 0; i < len; i++) if (raw[off + i] !== prev[off + i]) return true;
    return false;
  }

  function CoreView(container, opts) {
    this.root = container;
    this.opts = opts || {};
    this.prev = null;
    this.cells = {};
    this.fullCells = [];
    this.showFull = false;
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
    var r = this.root, self = this;
    r.classList.add('coreview');
    r.innerHTML = '';

    // Two rows: the instruction being executed on top, and the counters that
    // describe it (command number, and the 1802 instructions it cost) beneath —
    // so the opcode reads on its own line instead of trailing off into numbers.
    var status = el('div', 'cv-status');
    var top = el('div', 'cv-s-row');
    top.appendChild(el('span', 'cv-s-op mono', '—'));
    top.appendChild(el('span', 'cv-s-pl mono', ''));
    var spacer = el('span', 'cv-s-spacer'); top.appendChild(spacer);
    var toggle = el('button', 'cv-toggle', '⊕ all fields');
    toggle.type = 'button';
    toggle.addEventListener('click', function () {
      self.showFull = !self.showFull;
      self.root.classList.toggle('cv-showfull', self.showFull);
      toggle.textContent = self.showFull ? '⊖ compact' : '⊕ all fields';
      if (self.prev) self.render(self.prev, true);
    });
    top.appendChild(toggle);

    var counters = el('div', 'cv-s-row cv-s-counters');
    counters.appendChild(el('span', 'cv-s-cc mono', ''));
    counters.appendChild(el('span', 'cv-s-steps mono', ''));

    status.appendChild(top);
    status.appendChild(counters);
    r.appendChild(status);
    this.sOp = status.querySelector('.cv-s-op');
    this.sPl = status.querySelector('.cv-s-pl');
    this.sCc = status.querySelector('.cv-s-cc');
    this.sSteps = status.querySelector('.cv-s-steps');

    var grid = el('div', 'cv-grid');
    r.appendChild(grid);

    var regs = el('section', 'cv-sec cv-regs');
    regs.appendChild(el('h4', null, 'Registers'));
    var rgrid = el('div', 'cv-reggrid');
    for (var i = 0; i < 16; i++) this._cell(rgrid, 'R' + i, 'R' + i.toString(16).toUpperCase());
    regs.appendChild(rgrid);
    grid.appendChild(regs);

    var acc = el('section', 'cv-sec cv-accs');
    acc.appendChild(el('h4', null, 'Accumulators & Math'));
    var ag = el('div', 'cv-acclist');
    this._cell(ag, 'acc', 'Acc');
    this._cell(ag, 'ma', 'MA ($3068)');
    this._cell(ag, 'maRem', 'MA rem');
    this._cell(ag, 'maSign', 'MA sign');
    this._cell(ag, 'da', 'DA');
    this._cell(ag, 'daRem', 'DA rem');
    this._cell(ag, 'daSign', 'DA sign');
    acc.appendChild(ag);
    grid.appendChild(acc);

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

    // ---- full (detailed) section, hidden until toggled ----
    var full = el('section', 'cv-full');
    full.appendChild(el('h4', null, 'Full core block — VM1 $3000'));
    var ftbl = el('div', 'cv-fulltbl');
    FIELDS.forEach(function (f) {
      if (f.length === 2) { // group header
        var h = el('div', 'cv-fgroup', f[1]); ftbl.appendChild(h); return;
      }
      var row = el('div', 'cv-frow');
      row.appendChild(el('span', 'cv-foff mono', '$30' + hx(f[0], 2)));
      row.appendChild(el('span', 'cv-flab', f[2]));
      var v = el('span', 'cv-fval mono', '—');
      row.appendChild(v);
      ftbl.appendChild(row);
      self.fullCells.push({ row: row, val: v, off: f[0], len: f[1], kind: f[3] });
    });
    full.appendChild(ftbl);
    r.appendChild(full);
  };

  CoreView.prototype.render = function (s, force) {
    var p = this.prev, self = this;
    function set(key, val, ch) {
      var e = self.cells[key];
      e.textContent = val;
      e.parentNode.classList.toggle('chg', !!ch);
    }
    var i;
    for (i = 0; i < 16; i++) set('R' + i, '$' + hx(s.regs[i], 4), p && p.regs[i] !== s.regs[i]);
    set('acc', '$' + hx(s.acc, 4), p && p.acc !== s.acc);
    set('ma', s.maBytes.map(function (b) { return hx(b, 2); }).join(' '), p && p.maBytes.join() !== s.maBytes.join());
    set('maRem', '$' + hx(s.maRem, 4), p && p.maRem !== s.maRem);
    set('maSign', s.maSign ? '$' + hx(s.maSign, 2) : '+', p && p.maSign !== s.maSign);
    set('da', s.daBytes.map(function (b) { return hx(b, 2); }).join(' '), p && p.daBytes.join() !== s.daBytes.join());
    set('daRem', s.daRemBytes.map(function (b) { return hx(b, 2); }).join(' '), p && p.daRemBytes.join() !== s.daRemBytes.join());
    set('daSign', s.daSign ? '$' + hx(s.daSign, 2) : '+', p && p.daSign !== s.daSign);
    set('test', s.flags.test ? '● 1' : '○ 0', p && p.flags.test !== s.flags.test);
    set('carry', s.flags.carry ? '● 1' : '○ 0', p && p.flags.carry !== s.flags.carry);
    set('ovf', s.flags.overflow ? '● 1' : '○ 0', p && p.flags.overflow !== s.flags.overflow);
    set('hexdec', s.flags.hexdec ? 'DEC' : 'HEX', p && p.flags.hexdec !== s.flags.hexdec);
    set('quantum', s.intCounter + ' / ' + s.intMax, p && p.intCounter !== s.intCounter);
    set('memmode', s.memMode ? 'REL' : 'ABS', p && p.memMode !== s.memMode);

    this.sOp.textContent = s.halted ? 'HALTED' : '$' + hx(s.cmd, 2) + '  ' + (opName(s.cmd) || '');
    this.sPl.textContent = 'PL $' + hx(s.pl, 4);
    this.sCc.textContent = 'cmd# ' + s.cmdCounter;
    // raw 1802 instruction counts: this STELLAR opcode, then running total
    this.sSteps.innerHTML = '1802: <b>' + (s.lastOpCost || 0).toLocaleString() +
      '</b> this op · <b>' + s.steps.toLocaleString() + '</b> total';

    if ((this.showFull || force) && s.raw) {
      var praw = p && p.raw;
      this.fullCells.forEach(function (fc) {
        fc.val.textContent = fmt(fc.kind, s.raw, fc.off, fc.len);
        fc.row.classList.toggle('chg', changed(s.raw, praw, fc.off, fc.len));
      });
    }
    this.prev = s;
  };

  CoreView.prototype.reset = function () { this.prev = null; };

  return CoreView;
});
