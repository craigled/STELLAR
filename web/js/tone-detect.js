// Tone detector: is a Morse tone sounding? The web Simulator's stand-in for a tone-
// decoder chip (an NE567 on the Elf2K's EF4): microphone samples in, key down / up out.
//
// Every hop (HOP samples, ~2.7 ms) it looks at the last ~10.7 ms through a bank of
// Goertzel filters 400-1000 Hz, 25 Hz apart, and takes the strongest. KEY DOWN needs
// that filter 10 dB over its own background (learned while the key is up) AND a fair
// share of all the sound in it - a tone sits in one filter (a square wave from Q puts
// ~81% of its energy in its fundamental); noise and speech spread over all of them. Hysteresis and two
// hops of agreement stop it chattering at the edges. Both edges are delayed by the same
// amount, so marks and gaps keep their lengths.
//
// Loaded twice: as an AudioWorklet module (registerProcessor below) and, in tests, by
// Node (module.exports).
(function () {
  'use strict';

  function ToneDetector(sampleRate) {
    this.sr = sampleRate;
    this.N = Math.round(sampleRate * 0.0107);          // the window: ~94 Hz wide filters
    this.HOP = 128;
    this.buf = new Float32Array(this.N); this.pos = 0; this.fill = 0;
    this.freqs = []; this.coef = [];
    for (var f = 400; f <= 1000; f += 25) { this.freqs.push(f); this.coef.push(2 * Math.cos(2 * Math.PI * f / sampleRate)); }
    this.hpx = 0; this.hpy = 0;                          // a high-pass: no DC, little hum
    this.floor = 1e-6;                                   // the room's mean square while the key is up
    this.down = false; this.agree = 0;
    this.n = 0;                                          // samples seen
    this.level = 0; this.purity = 0; this.hz = 0;        // for a meter
  }

  // Feed samples; returns [{at: sample index of the edge, v}] for any edges.
  ToneDetector.prototype.feed = function (x) {
    var out = [], N = this.N, buf = this.buf;
    for (var i = 0; i < x.length; i++) {
      var y = x[i] - this.hpx + 0.995 * this.hpy; this.hpx = x[i]; this.hpy = y;
      buf[this.pos] = y; this.pos = (this.pos + 1) % N; if (this.fill < N) this.fill++;
      this.n++;
      if (this.n % this.HOP === 0 && this.fill === N) {
        var e = this._hop();
        if (e !== null) out.push({ at: this.n, v: e });
      }
    }
    return out;
  };

  ToneDetector.prototype._hop = function () {
    var N = this.N, buf = this.buf, p0 = this.pos, E = 0, k, i;
    for (i = 0; i < N; i++) { var s = buf[i]; E += s * s; }
    var best = 0, bestF = 0;
    for (k = 0; k < this.coef.length; k++) {
      var c = this.coef[k], s1 = 0, s2 = 0;
      for (i = 0; i < N; i++) { var s0 = buf[(p0 + i) % N] + c * s1 - s2; s2 = s1; s1 = s0; }
      var pw = s1 * s1 + s2 * s2 - c * s1 * s2;
      if (pw > best) { best = pw; bestF = this.freqs[k]; }
    }
    var ms = E / N, purity = E > 0 ? best / (E * N / 2) : 0;
    var band = best / (N * N);                           // the strongest filter's power, per sample
    this.level = band; this.purity = purity; this.hz = bestF;
    var want;
    // DOWN: the tone's band is 10x (10 dB) its own background AND carries a fair share of
    // the sound (broadband noise spreads over every filter; a tone sits in one). UP: the
    // band falls to 3x its background, or the sound stops being a tone.
    if (!this.down) want = band > this.floor * 10 && purity > 0.2 && band > 1e-7;
    else want = !(band < this.floor * 3 || purity < 0.1);
    if (!this.down) {                                     // learn the band's background while up
      if (band < this.floor) this.floor = Math.max(band, 1e-9);
      else this.floor += (band - this.floor) * 0.002;
    }
    if (want !== this.down) {
      if (++this.agree >= 2) { this.down = want; this.agree = 0; return want ? 1 : 0; }
    } else this.agree = 0;
    return null;
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = ToneDetector;
  if (typeof registerProcessor === 'function') {
    registerProcessor('tone-detect', class extends AudioWorkletProcessor {
      constructor() { super(); this.d = new ToneDetector(sampleRate); this.meter = 0; }
      process(inputs) {
        var ch = inputs[0] && inputs[0][0];
        if (ch) {
          var base = this.d.n, ev = this.d.feed(ch);
          for (var j = 0; j < ev.length; j++)       // the edge's moment on the audio clock
            this.port.postMessage({ edge: ev[j].v, time: currentTime + (ev[j].at - base - ch.length) / sampleRate });
          if (++this.meter % 12 === 0)
            this.port.postMessage({ level: this.d.level, purity: this.d.purity, hz: this.d.hz, down: this.d.down, time: currentTime });
        }
        return true;
      }
    });
  }
  if (typeof window !== 'undefined') window.ToneDetector = ToneDetector;
})();
