// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// Elf2K front panel for the simulator: the Q lamp and the two-digit hex
// display that shows the latched output byte.
//
// Both are driven straight from the emulator — `cpu.Q` and the last byte
// written to the configured output port (core $x039, Elf2K default 4) — so
// what you see here is what the real board's LEDs would be showing.
//
// The digits are inline SVG rather than a font: crisp at any size, themeable,
// and unlit segments are drawn faintly instead of hidden, which is what makes
// a real LED display readable when it is only partly lit.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.FrontPanel = api;
})(this, function () {
  'use strict';

  var NS = 'http://www.w3.org/2000/svg';

  // segment order: a b c d e f g
  var GLYPH = {
    0x0: 'abcdef', 0x1: 'bc',     0x2: 'abdeg',  0x3: 'abcdg',
    0x4: 'bcfg',   0x5: 'acdfg',  0x6: 'acdefg', 0x7: 'abc',
    0x8: 'abcdefg',0x9: 'abcdfg', 0xA: 'abcefg', 0xB: 'cdefg',
    0xC: 'adef',   0xD: 'bcdeg',  0xE: 'adefg',  0xF: 'aefg'
  };

  // Polygon points for each segment on a 100x180 grid (chamfered bar ends,
  // which is what gives it the classic LED look rather than plain rectangles).
  var SEG = {
    a: '18,8   82,8   72,20  28,20',
    b: '86,12  92,74  82,84  74,74  74,26',
    c: '86,96  92,158 82,168 74,158 74,110',
    d: '18,172 82,172 72,160 28,160',
    e: '14,96  20,110 20,158 12,168 6,158',
    f: '14,12  20,26  20,74  12,84  6,74',
    g: '20,90  28,80  72,80  80,90  72,100 28,100'
  };

  var LIT = '#ff4436';        // LED red
  var DIM = 0.07;             // unlit segments stay faintly visible, as on real hardware

  function digit(doc) {
    var svg = doc.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 100 180');
    svg.setAttribute('class', 'fp-digit');
    // Size and colour are also set as attributes, not left to CSS alone: an SVG
    // with no CSS width falls back to the browser default of 300x150 and unstyled
    // polygons fill black, so a stale stylesheet would render huge black digits
    // on white. These attributes keep it sane; the CSS still overrides them.
    svg.setAttribute('width', '38');
    svg.setAttribute('height', '68');
    var segs = {};
    Object.keys(SEG).forEach(function (k) {
      var p = doc.createElementNS(NS, 'polygon');
      p.setAttribute('points', SEG[k]);
      p.setAttribute('class', 'fp-seg');
      p.setAttribute('fill', LIT);
      p.setAttribute('fill-opacity', DIM);
      svg.appendChild(p);
      segs[k] = p;
    });
    return { svg: svg, segs: segs };
  }

  function FrontPanel(el) {
    var doc = el.ownerDocument;
    this.el = el;
    el.innerHTML = '';

    // --- Q lamp ---
    var qwrap = doc.createElement('div');
    qwrap.className = 'fp-qwrap';
    this.qLamp = doc.createElement('span');
    this.qLamp.className = 'fp-q';
    var qlab = doc.createElement('span');
    qlab.className = 'fp-qlab';
    qlab.textContent = 'Q';
    qwrap.appendChild(this.qLamp);
    qwrap.appendChild(qlab);

    // --- two hex digits ---
    var disp = doc.createElement('div');
    disp.className = 'fp-display';
    this.hi = digit(doc);
    this.lo = digit(doc);
    disp.appendChild(this.hi.svg);
    disp.appendChild(this.lo.svg);

    var caption = doc.createElement('div');
    caption.className = 'fp-cap mono';
    caption.textContent = 'OUTPUT —';
    this.caption = caption;

    el.appendChild(qwrap);
    el.appendChild(disp);
    el.appendChild(caption);
    this.render({ q: 0, outByte: null, outPort: 4 });
  }

  FrontPanel.prototype._setDigit = function (d, nib) {
    var on = nib === null ? '' : GLYPH[nib & 0xF];
    Object.keys(d.segs).forEach(function (k) {
      var lit = on.indexOf(k) >= 0;
      d.segs[k].classList.toggle('on', lit);          // CSS adds the glow
      d.segs[k].setAttribute('fill-opacity', lit ? 1 : DIM);  // works without CSS too
    });
  };

  FrontPanel.prototype.render = function (s) {
    var b = (s && s.outByte != null) ? s.outByte : null;
    this.qLamp.classList.toggle('on', !!(s && s.q));
    this._setDigit(this.hi, b === null ? null : (b >> 4) & 0xF);
    this._setDigit(this.lo, b === null ? null : b & 0xF);
    this.caption.textContent = b === null
      ? 'OUTPUT — · port ' + ((s && s.outPort) || 4)
      : 'OUTPUT $' + ('0' + b.toString(16).toUpperCase()).slice(-2) +
        ' · port ' + ((s && s.outPort) || 4);
  };

  return FrontPanel;
});
