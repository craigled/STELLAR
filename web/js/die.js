// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// The die: all 32 KB of the machine's RAM as a 128 x 256 picture, one pixel per
// byte, 128 bytes to a row (so a 256-byte page is two rows). The bytes themselves
// are the faint texture - firmware looks like firmware, empty RAM is black. On
// top of that, every instruction fetch lights its byte in the colour of the VM it
// was fetched for, and every write flashes white. Both fade over a few frames.
// The CIDP and the cores stand apart: a gap above the CIDP, one between it and the cores and
// one between the cores and VM1's block. The CIDP is only two rows (256 bytes), so its rows
// are drawn CIDP_X times as tall - one byte is still one pixel across.
(function (root, factory) {
  var api = factory();
  if (typeof window !== 'undefined') window.StellarDie = api;
})(this, function () {
  'use strict';

  var W = 128, GAP = 4, CIDP_X = 4;
  // picture row of each 128-byte memory row, and how many picture rows it takes
  var ROWY = new Int16Array(256), ROWH = new Uint8Array(256), GAPS = [];
  (function () {
    var y = 0;
    for (var r = 0; r < 256; r++) {
      if (r === 94 || r === 96 || r === 128) { GAPS.push(y); y += GAP; }   // $2F00, $3000, $4000
      ROWY[r] = y; ROWH[r] = (r === 94 || r === 95) ? CIDP_X : 1; y += ROWH[r];
    }
    H = y;
  })();
  var H;
  // memory row under a picture row, -1 in a gap
  var YROW = new Int16Array(H).fill(-1);
  for (var r = 0; r < 256; r++) for (var k = 0; k < ROWH[r]; k++) YROW[ROWY[r] + k] = r;
  // VM 0 = boot/scheduler (no VM running yet)
  var VMC = [[150, 160, 185], [255, 181, 71], [95, 227, 208], [255, 122, 144], [184, 243, 106]];

  function Die(canvas, machine) {
    this.cv = canvas;
    canvas.width = W; canvas.height = H;
    this.ctx = canvas.getContext('2d');
    this.img = this.ctx.createImageData(W, H);
    this.m = machine;
    // the gaps: panel colour, edged top and bottom like the frame
    var px = this.img.data;
    GAPS.forEach(function (y0) {
      for (var g = 0; g < GAP; g++) {
        var edge = g === 0 || g === GAP - 1, c = edge ? [38, 44, 57] : [13, 15, 20];
        for (var x = 0, p = (y0 + g) * W * 4; x < W; x++, p += 4) {
          px[p] = c[0]; px[p + 1] = c[1]; px[p + 2] = c[2]; px[p + 3] = 255;
        }
      }
    });
  }
  Die.prototype.setMachine = function (m) { this.m = m; };
  // A second canvas that gets every frame too - the enlarged die. null stops it.
  Die.prototype.mirrorTo = function (canvas) {
    this.mirror = canvas ? canvas.getContext('2d') : null;
    if (canvas) { canvas.width = W; canvas.height = H; this.mirror.putImageData(this.img, 0, 0); }
  };

  Die.prototype.render = function () {
    var m = this.m; if (!m) return;
    var M = m.M, heat = m.heat, hv = m.heatVM, wh = m.wheat, px = this.img.data;
    for (var a = 0, p = 0; a < 32768; a++, p += 4) {
      if (!(a & 127)) p = ROWY[a >> 7] * W * 4;
      var v = M[a];
      // base texture: code bytes glint faintly by value
      var b = v ? 46 + (v >> 3) : 7;
      var r = b, g = b + 2, bl = b + 6;
      var h = heat[a];
      if (h) {
        var c = VMC[hv[a]] || VMC[0], k = h / 255;
        r += c[0] * k; g += c[1] * k; bl += c[2] * k;
        heat[a] = (h * 214) >> 8;
      }
      var w = wh[a];
      if (w) {
        var kw = w / 255;
        r += 255 * kw; g += 236 * kw; bl += 210 * kw;
        wh[a] = (w * 200) >> 8;
      }
      px[p] = r > 255 ? 255 : r; px[p + 1] = g > 255 ? 255 : g;
      px[p + 2] = bl > 255 ? 255 : bl; px[p + 3] = 255;
      if (a >= 0x2F00 && a < 0x3000)                  // the CIDP: the same pixel down its taller row
        for (var k = 1, q = p + W * 4; k < CIDP_X; k++, q += W * 4) {
          px[q] = px[p]; px[q + 1] = px[p + 1]; px[q + 2] = px[p + 2]; px[q + 3] = 255;
        }
    }
    this.ctx.putImageData(this.img, 0, 0);
    if (this.mirror) this.mirror.putImageData(this.img, 0, 0);
  };

  // What lives at an address, for the hover readout.
  Die.region = function (a) {
    if (a < 0x0800) return 'firmware — kernel, scheduler, SCRT';
    if (a < 0x0A00) return 'firmware — opcode dispatch table';
    if (a < 0x2F00) return 'firmware — opcode handlers';
    if (a < 0x3000) return 'CIDP — the shared page (drawn 4× tall)';
    if (a < 0x4000) return 'VM' + (((a - 0x3000) >> 10) + 1) + ' core, stacks & labels';
    return 'VM' + (((a - 0x4000) >> 12) + 1) + ' program block';
  };
  // address at a point of the picture (fractions 0-1 across and down), -1 in a gap
  Die.addrAt = function (fx, fy) {
    var x = Math.floor(fx * W), y = Math.floor(fy * H);
    if (x < 0 || x >= W || y < 0 || y >= H || YROW[y] < 0) return -1;
    return YROW[y] * 128 + x;
  };
  // where an address range starts and ends down the picture, as fractions of its height
  Die.span = function (a0, a1) {
    var r0 = a0 >> 7, r1 = (a1 >> 7) - 1;
    return [ROWY[r0] / H, (ROWY[r1] + ROWH[r1]) / H];
  };
  Die.VMC = VMC;
  Die.W = W; Die.H = H; Die.CIDP_X = CIDP_X;
  return Die;
});
