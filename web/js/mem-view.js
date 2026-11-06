// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// Memory page viewer: one 256-byte page at a time, hex + ASCII, live as the
// program runs.
//
// The range offered is $2F00-$7EFF — everything a STELLAR program can meaningfully
// look at: the CIDP interchange page ($2F00), the four VM core blocks
// ($3000/$3400/$3800/$3C00) and the four program blocks ($4000-$7EFF). Firmware
// below $2F00 is deliberately left out; it never changes.
//
// Rendering is cheap but not free, so the cell spans are built once and only
// their text is updated afterwards — that keeps it usable at turbo speed.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.MemView = api;
})(this, function () {
  'use strict';

  var LO = 0x2F00, HI = 0x7EFF;
  function hx(v, n) { return v.toString(16).toUpperCase().padStart(n, '0'); }

  // Labels for the pages worth naming, so the picker reads as a memory map.
  function pageLabel(p) {
    var a = p << 8;
    if (a === 0x2F00) return ' — CIDP interchange';
    if (a === 0x3000) return ' — VM1 core';
    if (a === 0x3400) return ' — VM2 core';
    if (a === 0x3800) return ' — VM3 core';
    if (a === 0x3C00) return ' — VM4 core';
    if (a === 0x4000) return ' — VM1 program';
    if (a === 0x5000) return ' — VM2 program';
    if (a === 0x6000) return ' — VM3 program';
    if (a === 0x7000) return ' — VM4 program';
    return '';
  }

  function MemView(host, getMem) {
    var doc = host.ownerDocument;
    this.host = host;
    this.getMem = getMem;
    this.page = 0x41;                  // $4100 — where the sample programs park data
    host.innerHTML = '';

    var bar = doc.createElement('div');
    bar.className = 'mv-bar';
    var sel = doc.createElement('select');
    sel.className = 'mv-page';
    for (var p = LO >> 8; p <= HI >> 8; p++) {
      var o = doc.createElement('option');
      o.value = p;
      o.textContent = '$' + hx(p << 8, 4) + pageLabel(p);
      sel.appendChild(o);
    }
    sel.value = this.page;
    var prev = doc.createElement('button'); prev.type = 'button'; prev.textContent = '◀';
    prev.title = 'previous page';
    var next = doc.createElement('button'); next.type = 'button'; next.textContent = '▶';
    next.title = 'next page';
    bar.appendChild(prev);
    bar.appendChild(sel);
    bar.appendChild(next);
    host.appendChild(bar);

    var grid = doc.createElement('div');
    grid.className = 'mv-grid mono';
    this.cells = [];
    this.asciis = [];
    this.addrs = [];
    for (var r = 0; r < 16; r++) {
      var row = doc.createElement('div');
      row.className = 'mv-row';
      var ad = doc.createElement('span'); ad.className = 'mv-addr';
      row.appendChild(ad); this.addrs.push(ad);
      var hexWrap = doc.createElement('span'); hexWrap.className = 'mv-hex';
      for (var c = 0; c < 16; c++) {
        var cell = doc.createElement('span');
        cell.className = 'mv-b';
        hexWrap.appendChild(cell);
        this.cells.push(cell);
      }
      row.appendChild(hexWrap);
      var asc = doc.createElement('span'); asc.className = 'mv-ascii';
      row.appendChild(asc); this.asciis.push(asc);
      grid.appendChild(row);
    }
    host.appendChild(grid);

    var self = this;
    sel.addEventListener('change', function () { self.page = +this.value; self.render(true); });
    prev.addEventListener('click', function () {
      if (self.page > (LO >> 8)) { self.page--; sel.value = self.page; self.render(true); }
    });
    next.addEventListener('click', function () {
      if (self.page < (HI >> 8)) { self.page++; sel.value = self.page; self.render(true); }
    });
    this.sel = sel;
    this.prevBytes = null;
    this.render(true);
  }

  // Jump the view to whatever page an address falls in.
  MemView.prototype.showAddress = function (addr) {
    var p = (addr >> 8) & 0xFF;
    if (p < (LO >> 8) || p > (HI >> 8)) return false;
    this.page = p; this.sel.value = p; this.render(true);
    return true;
  };

  MemView.prototype.render = function (force) {
    var M = this.getMem();
    if (!M) return;
    var base = this.page << 8;
    var prev = this.prevBytes;
    var cur = new Array(256);
    for (var i = 0; i < 256; i++) cur[i] = M[base + i];
    for (var r = 0; r < 16; r++) {
      if (force) this.addrs[r].textContent = '$' + hx(base + r * 16, 4);
      var s = '';
      for (var c = 0; c < 16; c++) {
        var i2 = r * 16 + c, v = cur[i2];
        if (force || !prev || prev[i2] !== v) {
          var cell = this.cells[i2];
          cell.textContent = hx(v, 2);
          cell.classList.toggle('zero', v === 0);
        }
        s += (v >= 32 && v < 127) ? String.fromCharCode(v) : '.';
      }
      this.asciis[r].textContent = s;
    }
    this.prevBytes = cur;
  };

  return MemView;
});
