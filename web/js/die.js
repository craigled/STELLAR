// The die: all 32 KB of the machine's RAM as a 128 x 256 picture, one pixel per
// byte, 128 bytes to a row (so a 256-byte page is two rows). The bytes themselves
// are the faint texture - firmware looks like firmware, empty RAM is black. On
// top of that, every instruction fetch lights its byte in the colour of the VM it
// was fetched for, and every write flashes white. Both fade over a few frames.
(function (root, factory) {
  var api = factory();
  if (typeof window !== 'undefined') window.StellarDie = api;
})(this, function () {
  'use strict';

  var W = 128, H = 256;
  // VM 0 = boot/scheduler (no VM running yet)
  var VMC = [[150, 160, 185], [255, 181, 71], [95, 227, 208], [255, 122, 144], [184, 243, 106]];

  function Die(canvas, machine) {
    this.cv = canvas;
    canvas.width = W; canvas.height = H;
    this.ctx = canvas.getContext('2d');
    this.img = this.ctx.createImageData(W, H);
    this.m = machine;
  }
  Die.prototype.setMachine = function (m) { this.m = m; };

  Die.prototype.render = function () {
    var m = this.m; if (!m) return;
    var M = m.M, heat = m.heat, hv = m.heatVM, wh = m.wheat, px = this.img.data;
    for (var a = 0, p = 0; a < 32768; a++, p += 4) {
      var v = M[a];
      // base texture: code bytes glint faintly by value
      var b = v ? 22 + (v >> 4) : 7;
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
    }
    this.ctx.putImageData(this.img, 0, 0);
  };

  // What lives at an address, for the hover readout.
  Die.region = function (a) {
    if (a < 0x0800) return 'firmware — kernel, scheduler, SCRT';
    if (a < 0x0A00) return 'firmware — opcode dispatch table';
    if (a < 0x2F00) return 'firmware — opcode handlers';
    if (a < 0x3000) return 'CIDP — the shared page';
    if (a < 0x4000) return 'VM' + (((a - 0x3000) >> 10) + 1) + ' core, stacks & labels';
    return 'VM' + (((a - 0x4000) >> 12) + 1) + ' program block';
  };
  Die.VMC = VMC;
  Die.W = W; Die.H = H;
  return Die;
});
