// Glue for simulator.html: sample picker, controls, and the SimApp wiring.
(function () {
  var SPEEDS = [
    { label: '1×', ops: 1, ms: 500 },
    { label: '4×', ops: 1, ms: 120 },
    { label: '16×', ops: 4, ms: 30 },
    { label: 'turbo', ops: 200, ms: 0 }
  ];

  var panel = new window.FrontPanel(document.getElementById('frontpanel'));

  var app = new window.SimApp({
    coreEl: document.getElementById('core'),
    disasmEl: document.getElementById('disasm'),
    terminalEl: document.getElementById('term'),
    statusEl: document.getElementById('status'),
    onState: function (s) {
      panel.render(s);
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

  // ---- opening a .lst from the user's machine (file picker or drag-and-drop) ----
  // Everything is client-side; the site is static, so nothing is uploaded anywhere.
  function loadUserProgram(name, text) {
    var pokes;
    try {
      pokes = window.StellarVMLib.parseLst(text);
    } catch (e) {
      btn('status').textContent = name + ': could not parse — ' + e;
      return;
    }
    if (!pokes.length) {
      btn('status').textContent = name + ': no "D <addr> <bytes>" lines found — is this a STELLAR .lst?';
      return;
    }
    var entry = pokes[0][0], first = pokes[0][1];
    var input = btn('input').value.replace(/\\r/g, '\r').replace(/\\n/g, '\n');
    app.load(text, input);
    btn('blurb').textContent = 'Loaded ' + name + ' — ' + pokes.length +
      ' bytes from $' + entry.toString(16).toUpperCase() + '.';
    if (first !== 0xCD) {
      // Every STELLAR program starts with CD START; anything else is most
      // likely native 1802 code (or a data-only file) and will not run here.
      btn('status').textContent = name + ': loaded, but the first byte is $' +
        first.toString(16).toUpperCase() + ', not $CD START — this may not be a STELLAR program.';
    }
  }

  function readFile(file) {
    if (!file) return;
    var fr = new FileReader();
    fr.onload = function () { loadUserProgram(file.name, String(fr.result)); };
    fr.onerror = function () { btn('status').textContent = 'could not read ' + file.name; };
    fr.readAsText(file);
  }

  btn('openFile').addEventListener('click', function () { btn('fileInput').click(); });
  btn('fileInput').addEventListener('change', function () {
    readFile(this.files && this.files[0]);
    this.value = '';               // let the same file be re-picked later
  });

  var bodyEl = document.getElementById('body');
  ['dragenter', 'dragover'].forEach(function (ev) {
    bodyEl.addEventListener(ev, function (e) {
      e.preventDefault(); bodyEl.classList.add('dropping');
    });
  });
  ['dragleave', 'drop'].forEach(function (ev) {
    bodyEl.addEventListener(ev, function (e) {
      e.preventDefault();
      if (ev === 'dragleave' && bodyEl.contains(e.relatedTarget)) return;
      bodyEl.classList.remove('dropping');
    });
  });
  bodyEl.addEventListener('drop', function (e) {
    readFile(e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0]);
  });

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
