// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// 🎤 Listen: the microphone as the Input switch (EF4). A tone heard by js/tone-detect.js
// (running as an AudioWorklet) holds the key down; each edge is passed on with the wall-
// clock moment it happened, so SimApp.keyEdge can replay the marks and gaps at the right
// machine cycles. Echo cancellation, noise suppression and automatic gain are turned
// OFF - browsers otherwise treat a steady tone as noise and remove it.
(function () {
  'use strict';

  function ToneListen(opts) {
    this.onEdge = opts.onEdge; this.onMeter = opts.onMeter || function () {};
    this.ctx = null; this.stream = null; this.node = null;
  }

  ToneListen.prototype.start = function (moduleUrl) {
    var self = this, AC = window.AudioContext || window.webkitAudioContext;
    if (!AC || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.AudioWorkletNode)
      return Promise.reject(new Error('this browser cannot listen (no microphone or AudioWorklet support)'));
    return navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false, channelCount: 1 }
    }).then(function (stream) {
      self.stream = stream;
      self.ctx = new AC();
      return self.ctx.audioWorklet.addModule(moduleUrl);
    }).then(function () {
      var ctx = self.ctx, src = ctx.createMediaStreamSource(self.stream);
      self.node = new AudioWorkletNode(ctx, 'tone-detect');
      var mute = ctx.createGain(); mute.gain.value = 0;    // keeps the worklet pulled, plays nothing
      src.connect(self.node); self.node.connect(mute); mute.connect(ctx.destination);
      self.node.port.onmessage = function (ev) {
        var m = ev.data, wall = Date.now() - (ctx.currentTime - m.time) * 1000;
        if (m.edge !== undefined) self.onEdge(m.edge, wall);
        else self.onMeter(m);
      };
      if (ctx.state === 'suspended') ctx.resume();
    });
  };

  ToneListen.prototype.stop = function () {
    if (this.stream) this.stream.getTracks().forEach(function (t) { t.stop(); });
    if (this.ctx) this.ctx.close();
    this.ctx = this.stream = this.node = null;
  };

  window.ToneListen = ToneListen;
})();
