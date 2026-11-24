// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
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
  var LEAD = 0.12;       // seconds queued ahead of the audio clock when sound (re)starts; 0.25 on Safari's
  var LEAD_EL = 0.25;    //  <audio> route, which buffers more of its own: a frame later than the lead let
                         //  the queue run dry - a gap and a click (Craig, DOTBOT (now AT-MAN) in Safari, 2026-11-24; was 0.08)
  var AMP = 0.25;
  var R = 0.995;         // DC blocker pole: a steady Q fades in a few ms

  function QAudio() {
    this.enabled = false;
    this.ctx = null;
    this.cpu = null;
    this.cursor = 0;     // audio-clock time the next samples play at; 0 = idle
    this.lastWall = 0;
    // counts for the ?sounddebug readout on the Simulator page
    this.stat = { ticks: 0, syncs: 0, late: 0, muted: 0, notRunning: 0, quiet: 0, played: 0, edges: 0, maxGap: 0 };
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
        // Safari on some Macs plays nothing from Web Audio sent straight to the speakers
        // (Craig's: running, buffers queued, silence - while YouTube plays), yet the same
        // sound handed to an <audio> element is heard. So in Safari it goes that way.
        this.route = QAudio.route();
        if (this.route === 'element' && this.ctx.createMediaStreamDestination) {
          var dest = this.ctx.createMediaStreamDestination();
          this.gain.connect(dest);
          this.el = new Audio();
          this.el.srcObject = dest.stream;
        } else {
          this.route = 'direct';
          this.gain.connect(this.ctx.destination);
        }
      }
      if (this.ctx.state !== 'running') this.ctx.resume();
      if (this.el) { var pr = this.el.play(); if (pr && pr.catch) pr.catch(function () {}); }   // (in the click)
      // Safari keeps Web Audio silent until a sound is STARTED inside the click itself
      // (making and resuming the context is not enough), so start a silent sample now
      try {
        var b = this.ctx.createBufferSource();
        b.buffer = this.ctx.createBuffer(1, 1, this.ctx.sampleRate);
        b.connect(this.gain); b.start(0);
      } catch (e) {}
    }
    else if (this.el) this.el.pause();
    this.cpu = null;     // re-sync on the next tick
    return this.enabled;
  };

  // 'element' (through an <audio> element) in Safari, else 'direct'; ?audio=direct or
  // ?audio=element in the page's address picks one by hand
  QAudio.route = function () {
    var m = /[?&#]audio=(direct|element)/.exec(location.search + location.hash);
    if (m) return m[1];
    var ua = navigator.userAgent;
    return /Safari\//.test(ua) && !/Chrome|Chromium|CriOS|FxiOS|Edg|OPR|Android/.test(ua) ? 'element' : 'direct';
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
    var wall = Date.now(), gap = wall - this.lastWall, st = this.stat;
    this.lastWall = wall;
    st.ticks++; if (gap < 5000 && gap > st.maxGap) st.maxGap = gap;
    if (!this.enabled || !this.ctx) { if (cpu.qLog) cpu.qLog = null; this.cpu = null; return; }
    // Safari can suspend (or 'interrupt') a context that was playing: ask it back,
    // at most once a second, and start over in time when it returns
    if (this.ctx.state !== 'running') {
      st.notRunning++;
      if (wall - (this.lastResume || 0) > 1000) { this.lastResume = wall; try { this.ctx.resume(); } catch (e) {} }
      this.cpu = null; return;
    }
    // a new program, a different speed, or a pause (Step / Pause / a hidden tab):
    // what happened meanwhile is not real time, so start over from here
    if (cpu !== this.cpu || !audible || gap > 250) {
      st.syncs++; if (!audible) st.muted++; if (gap > 250) st.late++;
      this._sync(cpu); return;
    }

    var sr = this.ctx.sampleRate, spc = sr / CPS;
    var end = cpu.cycles, log = cpu.qLog;
    var exact = (end - this.c0) * spc + this.frac, n = Math.floor(exact);
    var quiet = !log.length && Math.abs(this.y) < 1e-4 && this.x === this.level;
    var now = this.ctx.currentTime, k = 0;
    if (this.cursor && this.cursor < now) this.cursor = 0;          // fell behind: idle
    if (n <= 0) return;
    st.edges += log.length / 2;
    if (quiet) {
      st.quiet++;
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
      var lead = this.route === 'element' ? LEAD_EL : LEAD;
      if (!this.cursor) this.cursor = now + lead;
      if (this.cursor > now + 3) this.cursor = now + lead;          // never queue seconds of lag
      var src = this.ctx.createBufferSource();
      src.buffer = buf; src.connect(this.gain); src.start(this.cursor); st.played++;
      this.cursor += n / sr;
    }
    if (k) log.splice(0, k);   // an edge in the last part-sample waits for the next tick
    this.frac = exact - n;
    this.c0 = end;
  };

  // A plain 440 Hz beep for half a second, straight to the speakers: tells whether the
  // browser plays Web Audio at all (call it from a click).
  QAudio.prototype.beep = function () {
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    if (!this.ctx) { var was = this.enabled; this.setEnabled(true); this.enabled = was; }   // the context, on its route
    var ctx = this.ctx || new AC();
    if (ctx.state !== 'running') ctx.resume();
    if (this.el && this.el.paused) this.el.play();
    var o = ctx.createOscillator(), g = ctx.createGain();
    g.gain.value = 0.2; o.frequency.value = 440;
    o.connect(g); g.connect(this.gain && this.ctx === ctx ? this.gain : ctx.destination);   // the same way as the sound
    o.start(); o.stop(ctx.currentTime + 0.5);
  };

  return QAudio;
});
