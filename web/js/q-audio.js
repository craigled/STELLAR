// Q as sound: what a speaker wired to the 1802's Q line would play.
//
// The emulator logs every change of Q with the machine cycle it happened on
// (CPU.qLog). After each tick of the run loop this turns that log into audio
// samples on the HARDWARE's clock - 375,000 machine cycles a second, Craig's
// 3 MHz Elf2K - and queues them back to back through Web Audio. So the pitch is
// the program's own: Morse Sender v18's TONE loop comes out at its 700 Hz, and
// changing its pitch byte changes the note. A Q held steady (v17's key-down) is
// a click on and a click off, as a speaker gives - a DC blocker lets the level
// settle back to silence.
//
// Only at the Elf2K speed: faster clocks would raise the pitch, the stepping
// speeds have no timing at all, so they are muted. Browsers allow sound only
// after a click, so it starts switched off.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.QAudio = api;
})(this, function () {
  'use strict';

  var CPS = 375000;      // Elf2K machine cycles a second (3 MHz / 8)
  var LEAD = 0.08;       // seconds queued ahead of the audio clock when sound (re)starts
  var AMP = 0.25;
  var R = 0.995;         // DC blocker pole: a steady Q fades in a few ms

  function QAudio() {
    this.enabled = false;
    this.ctx = null;
    this.cpu = null;
    this.cursor = 0;     // audio-clock time the next samples play at; 0 = idle
    this.lastWall = 0;
  }

  // Must be called from a click: that is when a browser lets a page make sound.
  QAudio.prototype.setEnabled = function (on) {
    var AC = window.AudioContext || window.webkitAudioContext;
    if (on && !AC) return false;
    this.enabled = !!on;
    if (on) {
      if (!this.ctx) {
        this.ctx = new AC();
        this.gain = this.ctx.createGain();
        this.gain.gain.value = 1;
        this.gain.connect(this.ctx.destination);
      }
      if (this.ctx.state === 'suspended') this.ctx.resume();
    }
    this.cpu = null;     // re-sync on the next tick
    return this.enabled;
  };

  QAudio.prototype._sync = function (cpu) {
    if (this.cpu && this.cpu !== cpu) this.cpu.qLog = null;
    this.cpu = cpu;
    cpu.qLog = this.enabled ? [] : null;
    this.c0 = cpu.cycles;                 // cycle the next sample starts at
    this.frac = 0;                        // fractional sample carried between ticks
    this.level = cpu.Q;
    this.x = cpu.Q; this.y = 0;           // DC blocker state
    this.cursor = 0;
  };

  // After each run-loop tick. `audible` = the clock is at Elf2K speed.
  QAudio.prototype.tick = function (cpu, audible) {
    var wall = Date.now(), gap = wall - this.lastWall;
    this.lastWall = wall;
    if (!this.enabled || !this.ctx) { if (cpu.qLog) cpu.qLog = null; this.cpu = null; return; }
    // a new program, a different speed, or a pause (Step / Pause / a hidden tab):
    // what happened meanwhile is not real time, so start over from here
    if (cpu !== this.cpu || !audible || gap > 250) { this._sync(cpu); return; }

    var sr = this.ctx.sampleRate, spc = sr / CPS;
    var end = cpu.cycles, log = cpu.qLog;
    var exact = (end - this.c0) * spc + this.frac, n = Math.floor(exact);
    var quiet = !log.length && Math.abs(this.y) < 1e-4 && this.x === this.level;
    var now = this.ctx.currentTime, k = 0;
    if (this.cursor && this.cursor < now) this.cursor = 0;          // fell behind: idle
    if (n <= 0) return;
    if (quiet) {
      if (this.cursor) this.cursor += n / sr;
    } else {
      var buf = this.ctx.createBuffer(1, n, sr), out = buf.getChannelData(0);
      var cyc = this.c0 - this.frac / spc, step = 1 / spc;   // cycles per sample
      var level = this.level, x = this.x, y = this.y;
      for (var i = 0; i < n; i++) {
        var a = cyc + i * step, b = a + step, hi = 0, t = a;
        while (k < log.length && log[k] < b) {             // edges inside this sample
          if (level) hi += Math.max(0, log[k] - t);
          t = Math.max(t, log[k]); level = log[k + 1]; k += 2;
        }
        if (level) hi += b - t;
        var xs = hi / step;                                 // share of the sample Q was high
        y = xs - x + R * y; x = xs;
        out[i] = y * AMP;
      }
      this.level = level; this.x = x; this.y = y;
      if (!this.cursor) this.cursor = now + LEAD;
      if (this.cursor > now + 3) this.cursor = now + LEAD;          // never queue seconds of lag
      var src = this.ctx.createBufferSource();
      src.buffer = buf; src.connect(this.gain); src.start(this.cursor);
      this.cursor += n / sr;
    }
    if (k) log.splice(0, k);   // an edge in the last part-sample waits for the next tick
    this.frac = exact - n;
    this.c0 = end;
  };

  return QAudio;
});
