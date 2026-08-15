// Glue for core.html — a focused single-core view. Reuses SimApp; the sample's
// input comes from the manifest (no manual input field here).
(function () {
  var SPEEDS = [
    { label: '1×', ops: 1, ms: 500 },
    { label: '4×', ops: 1, ms: 120 },
    { label: '16×', ops: 4, ms: 30 },
    { label: 'turbo', ops: 200, ms: 0 }
  ];
  function byId(id) { return document.getElementById(id); }

  var app = new window.SimApp({
    coreEl: byId('core'),
    disasmEl: byId('disasm'),
    terminalEl: byId('term'),
    statusEl: byId('status'),
    onState: function (s) {
      byId('pause').disabled = !app.running;
      byId('run').disabled = app.running || s.halted;
      byId('step').disabled = app.running || s.halted;
    }
  });

  var samples = [];
  fetch('samples/manifest.json').then(function (r) { return r.json(); }).then(function (list) {
    samples = list;
    var sel = byId('sample');
    list.forEach(function (s, i) {
      var o = document.createElement('option');
      o.value = i; o.textContent = s.name; sel.appendChild(o);
    });
    load(0);
  }).catch(function (e) { byId('status').textContent = 'could not load samples: ' + e; });

  function load(i) {
    var s = samples[i];
    byId('status').textContent = 'loading ' + s.name + '…';
    fetch('samples/' + s.file).then(function (r) { return r.text(); }).then(function (text) {
      var input = (s.input || '').replace(/\\r/g, '\r').replace(/\\n/g, '\n');
      app.load(text, input);
    });
  }

  byId('sample').addEventListener('change', function () { load(+this.value); });
  byId('step').addEventListener('click', function () { app.step(); });
  byId('run').addEventListener('click', function () { app.run(); });
  byId('pause').addEventListener('click', function () {
    app.stop(); app._setStatus('paused');
    byId('run').disabled = false; byId('step').disabled = false; byId('pause').disabled = true;
  });
  byId('reset').addEventListener('click', function () { app.reset(); });
  byId('toggleSide').addEventListener('click', function () {
    byId('body').classList.toggle('side-open');
  });

  var speed = byId('speed');
  function applySpeed() {
    var s = SPEEDS[+speed.value];
    byId('speedLabel').textContent = s.label;
    app.setSpeed(s.ops, s.ms);
  }
  speed.addEventListener('input', applySpeed);
  applySpeed();
})();
