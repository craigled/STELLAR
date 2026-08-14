// Glue for simulator.html: sample picker, controls, and the SimApp wiring.
(function () {
  var SPEEDS = [
    { label: '1×', ops: 1, ms: 160 },
    { label: '4×', ops: 1, ms: 40 },
    { label: '16×', ops: 4, ms: 30 },
    { label: 'turbo', ops: 200, ms: 0 }
  ];

  var app = new window.SimApp({
    coreEl: document.getElementById('core'),
    disasmEl: document.getElementById('disasm'),
    terminalEl: document.getElementById('term'),
    statusEl: document.getElementById('status'),
    onState: function (s) {
      btn('pause').disabled = !app.running;
      btn('run').disabled = app.running || s.halted;
      btn('step').disabled = app.running || s.halted;
    }
  });

  function btn(id) { return document.getElementById(id); }
  var samples = [];

  fetch('samples/manifest.json')
    .then(function (r) { return r.json(); })
    .then(function (list) {
      samples = list;
      var sel = btn('sample');
      list.forEach(function (s, i) {
        var o = document.createElement('option');
        o.value = i; o.textContent = s.name;
        sel.appendChild(o);
      });
      selectSample(0);
    })
    .catch(function (e) { btn('status').textContent = 'could not load samples: ' + e; });

  function selectSample(i) {
    var s = samples[i];
    btn('input').value = (s.input || '').replace(/\r/g, '\\r');
    btn('blurb').textContent = s.blurb || '';
    loadSample(s);
  }

  function loadSample(s) {
    btn('status').textContent = 'loading ' + s.name + '…';
    fetch('samples/' + s.file)
      .then(function (r) { return r.text(); })
      .then(function (text) {
        var input = btn('input').value.replace(/\\r/g, '\r').replace(/\\n/g, '\n');
        app.load(text, input);
      })
      .catch(function (e) { btn('status').textContent = 'load failed: ' + e; });
  }

  btn('sample').addEventListener('change', function () { selectSample(+this.value); });
  btn('load').addEventListener('click', function () {
    var s = samples[+btn('sample').value];
    loadSample(s);
  });
  btn('step').addEventListener('click', function () { app.step(); });
  btn('run').addEventListener('click', function () { app.run(); });
  btn('pause').addEventListener('click', function () { app.stop(); app._setStatus('paused'); btn('run').disabled = false; btn('step').disabled = false; btn('pause').disabled = true; });
  btn('reset').addEventListener('click', function () { app.reset(); });
  btn('toggleSide').addEventListener('click', function () {
    document.getElementById('body').classList.toggle('side-open');
  });

  var speed = btn('speed');
  function applySpeed() {
    var s = SPEEDS[+speed.value];
    btn('speedLabel').textContent = s.label;
    app.setSpeed(s.ops, s.ms);
  }
  speed.addEventListener('input', applySpeed);
  applySpeed();
})();
