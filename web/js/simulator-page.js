// Glue for simulator.html: sample picker, controls, and the SimApp wiring.
// Sample fetches carry the same ?v= cache-buster the <script> tags do. Without it a
// browser that has visited before serves the OLD manifest from cache and newly added
// samples never appear in the dropdown - which is exactly what happened when the five
// VT100 programs were added.
(function () {

  var panel = new window.FrontPanel(document.getElementById('frontpanel'));
  var memView = null;   // built after the app exists, so it can read the live memory

  function showBreaks(n) {
    var el = document.getElementById('bpCount');
    if (el) el.textContent = n ? (n + ' breakpoint' + (n === 1 ? '' : 's')) : '';
  }

  // Front-panel inputs are read straight off the live CPU rather than trusted to
  // come back in the snapshot. StellarVM.snapshot does supply q/outPort/outByte,
  // but only in builds from 2026-08-17 on — deriving them here as well means a
  // cached copy of stellar-vm.js leaves the panel working instead of blank.
  function panelState(s) {
    var cpu = app.vm && app.vm.cpu;
    if (!cpu) return s;
    var CORE = (window.StellarVMLib && window.StellarVMLib.CORE) || 0x3000;
    var port = cpu.M[CORE + 0x39] || 4;          // DEFOUT target; Elf2K default 4
    var log = cpu.io_out[port];
    s.q = cpu.Q ? 1 : 0;
    s.outPort = port;
    s.outByte = (log && log.length) ? log[log.length - 1] : null;
    return s;
  }

  var app = new window.SimApp({
    coreEl: document.getElementById('core'),
    disasmEl: document.getElementById('disasm'),
    terminalEl: document.getElementById('term'),
    coldBoot: true,
    statusEl: document.getElementById('status'),
    onBreaksChanged: function (n) { showBreaks(n); },
    onState: function (s) {
      panel.render(panelState(s));
      if (memView) memView.render();
      btn('pause').disabled = !app.running;
      btn('run').disabled = app.running || s.halted;
      btn('step').disabled = app.running || s.halted;
    }
  });

  function btn(id) { return document.getElementById(id); }
  var samples = [];

  fetch('samples/manifest.json?v=53')
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
    .catch(function (e) {
    // Opened as a file:// URL the sample fetches are blocked as cross-origin, so the
    // dropdown stays empty and nothing can be loaded - which looks like the page is
    // simply broken. Say what to do instead of reporting a bare TypeError.
    btn('status').textContent = (location.protocol === 'file:')
      ? 'This page has to be SERVED over http, not opened as a file. '
        + 'Run:  python3 -m http.server 8787 --directory web   from the repo root, '
        + 'then open http://localhost:8787/' + location.pathname.split('/').pop()
      : 'could not load samples: ' + e;
  });

  function selectSample(i) {
    var s = samples[i];
    btn('input').value = (s.input || '').replace(/\r/g, '\\r');
    btn('blurb').textContent = s.blurb || '';
    // A sample can ask for a speed by its label ("flat out", "Elf2K", ...). ELIZA
    // wants flat out (slower, its start-up outlasts a visitor's first keystrokes);
    // Pong wants Elf2K, the hardware's real pace - flat out a game is over in seconds.
    if (s.speed && clock) clock.set(s.speed);
    loadSample(s);
  }

  function loadSample(s) {
    btn('status').textContent = 'loading ' + s.name + '…';
    fetch('samples/' + s.file + '?v=53')
      .then(function (r) { return r.text(); })
      .then(function (text) {
        var input = btn('input').value.replace(/\\r/g, '\r').replace(/\\n/g, '\n');
        app.load(text, input);
      })
      .catch(function (e) { btn('status').textContent = 'load failed: ' + e; });
  }

  memView = new window.MemView(document.getElementById('memview'),
    function () { return app.vm && app.vm.cpu && app.vm.cpu.M; });

  document.getElementById('clearBreaks').addEventListener('click', function () {
    app.clearBreaks(); showBreaks(0);
  });

  // Live typing into the serial terminal (shared with the multitasking page).
  window.attachTerminalInput(document.getElementById('term'),
    function () { return app.vm && app.vm.cpu; });

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

  var clock = window.ClockRow(btn('clockBtns'), btn('speedLabel'), function (sp) {
    app.setSpeed(sp.ops || 0, sp.ms, sp.ips);
  });
})();
