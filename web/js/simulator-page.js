// Glue for simulator.html: sample picker, controls, and the SimApp wiring.
// Sample fetches carry the same ?v= cache-buster the <script> tags do. Without it a
// browser that has visited before serves the OLD manifest from cache and newly added
// samples never appear in the dropdown - which is exactly what happened when the five
// VT100 programs were added.
(function () {

  var panel = new window.FrontPanel(document.getElementById('frontpanel'));
  var qAudio = window.QAudio ? new window.QAudio() : null;
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
    onTick: function (vm, ips) {
      if (qAudio) qAudio.tick(vm.cpu, ips === window.ClockRow.ELF2K);
    },
    onState: function (s) {
      panel.render(panelState(s));
      var k = btn('inKey'), down = !!(app.vm && app.vm.cpu.EF[3]);
      if (k && k.classList.contains('on') !== down) k.classList.toggle('on', down);
      if (memView) memView.render();
      btn('pause').disabled = !app.running;
      btn('run').disabled = app.running || s.halted;
      btn('step').disabled = app.running || s.halted;
    }
  });

  function btn(id) { return document.getElementById(id); }
  var samples = [];
  var autoRun = false;          // set by a #app= link: run the app once it is loaded

  function runEnlarged() {
    app.run();
    var t = document.getElementById('term');
    // enlarge where the Enlarge button is offered (not on phones: there the page's own
    // keyboard row is the way to play); otherwise just bring the terminal into view
    if (t._tz && t._tz.button && t._tz.button.offsetParent !== null) t._tz.open();
    else { t.scrollIntoView({ block: 'center' }); t.focus({ preventScroll: true }); }
  }

  fetch('samples/manifest.json?v=118')
    .then(function (r) { return r.json(); })
    .then(function (list) {
      samples = list;
      var sel = btn('sample');
      list.forEach(function (s, i) {
        var o = document.createElement('option');
        o.value = i; o.textContent = s.name;
        sel.appendChild(o);
      });
      // simulator.html#app=Snake.lst (the Apps page): that app, running, terminal enlarged
      var m = /(?:^#|&)app=([^&]+)/.exec(location.hash), want = m ? decodeURIComponent(m[1]) : null;
      var at = -1;
      list.forEach(function (s, i) { if (want && s.file.toLowerCase() === want.toLowerCase()) at = i; });
      if (at >= 0) {
        sel.value = at;
        autoRun = true;
      }
      selectSample(at >= 0 ? at : 0);
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
    fetch('samples/' + s.file + '?v=118')
      .then(function (r) { return r.text(); })
      .then(function (text) {
        var input = btn('input').value.replace(/\\r/g, '\r').replace(/\\n/g, '\n');
        app.load(text, input);
        if (autoRun) { autoRun = false; runEnlarged(); }
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

  // ---- downloads for the real machine ----
  // The firmware goes out as Intel HEX: 16-byte data records covering the whole
  // image $0000 up to the end of the firmware, gaps included as $00, so it loads the
  // same over RAM that is not clean. Built here from the baked image, so it is always
  // exactly what the simulator runs.
  function hex2(n) { return (n < 16 ? '0' : '') + n.toString(16).toUpperCase(); }
  function firmwareHex() {
    var fw = window.STELLAR_FIRMWARE, end = 0, mem = new Uint8Array(0x10000);
    fw.segments.forEach(function (sg) {
      var b = atob(sg[1]);
      for (var i = 0; i < b.length; i++) mem[sg[0] + i] = b.charCodeAt(i);
      end = Math.max(end, sg[0] + b.length);
    });
    end = (end + 15) & ~15;
    var out = [];
    for (var a = 0; a < end; a += 16) {
      var n = Math.min(16, end - a), rec = [n, a >> 8, a & 0xFF, 0], line = ':';
      for (var i = 0; i < n; i++) rec.push(mem[a + i]);
      var sum = 0;
      rec.forEach(function (x) { sum += x; line += hex2(x); });
      out.push(line + hex2((-sum) & 0xFF));
    }
    out.push(':00000001FF');
    return { text: out.join('\r\n') + '\r\n', end: end };
  }
  function saveFile(name, text) {
    var url = URL.createObjectURL(new Blob([text], { type: 'text/plain' }));
    var a = document.createElement('a');
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }
  if (window.STELLAR_FIRMWARE && window.STELLAR_FIRMWARE.version && btn('dlFwVer'))
    btn('dlFwVer').textContent = 'V' + window.STELLAR_FIRMWARE.version;
  btn('dlFw').addEventListener('click', function () {
    var h = firmwareHex(), v = window.STELLAR_FIRMWARE.version;
    saveFile('STELLAR-V' + v + '.hex', h.text);
    btn('dlNote').textContent = 'STELLAR-V' + v + '.hex: $0000-$' +
      (h.end - 1).toString(16).toUpperCase() + ', Intel HEX. Send it to the monitor as a text upload.';
  });

  // The full catalogue (web/build/gen_downloads.py): every finished app, grouped.
  var catalog = [];
  fetch('downloads/catalog.json?v=118')
    .then(function (r) { return r.json(); })
    .then(function (list) {
      catalog = list;
      var sel = btn('dlPick'), groups = {};
      sel.innerHTML = '';
      list.forEach(function (a, i) {
        if (!groups[a.group]) {
          groups[a.group] = document.createElement('optgroup');
          groups[a.group].label = a.group; sel.appendChild(groups[a.group]);
        }
        var o = document.createElement('option');
        o.value = i; o.textContent = a.name + (a.note ? ' (not yet on hardware)' : '');
        groups[a.group].appendChild(o);
      });
      describePick();
    })
    .catch(function () { btn('dlPick').innerHTML = '<option>app list unavailable</option>'; btn('dlGo').disabled = true; });
  function describePick() {
    var a = catalog[+btn('dlPick').value];
    if (a) btn('dlNote').textContent = a.href.split('/').pop() + ' \u2014 ' + a.what + (a.note ? ' (' + a.note + ')' : '');
  }
  btn('dlPick').addEventListener('change', describePick);
  btn('dlGo').addEventListener('click', function () {
    var a = catalog[+btn('dlPick').value];
    if (!a) return;
    var fn = a.href.split('/').pop();
    fetch(a.href + '?v=118')
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (text) {
        saveFile(fn, text);
        btn('dlNote').textContent = fn + ' saved: load its D-lines into the Elf2K monitor, then run STELLAR.';
      })
      .catch(function (e) { btn('dlNote').textContent = 'could not fetch ' + fn + ': ' + e; });
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
    soundNote();
  });

  // ---- Q as sound (js/q-audio.js) ----
  function soundNote() {
    var el = btn('soundNote');
    if (!el || !qAudio) return;
    var sp = clock && clock.current();
    el.textContent = !qAudio.enabled ? 'Q through a speaker: the program\u2019s own pitch, at the Elf2K clock only.'
      : (sp && sp.ips === window.ClockRow.ELF2K) ? 'Playing Q as a speaker would, at the Elf2K\u2019s 3 MHz.'
      : 'Muted: sound plays only at the Elf2K speed (other clocks would change the pitch).';
  }
  if (qAudio) {
    btn('sound').addEventListener('click', function () {
      var on = qAudio.setEnabled(!qAudio.enabled);
      this.textContent = on ? '🔊 Sound on' : '🔈 Sound off';
      this.setAttribute('aria-pressed', on ? 'true' : 'false');
      soundNote();
    });
  } else btn('sound').disabled = true;
  soundNote();

  // ---- the INPUT switch (EF4): held with the mouse, a finger, or Space ----
  (function () {
    var k = btn('inKey'), held = false;
    function set(v) { if (v !== held) { held = v; app.keyEdge(v ? 1 : 0); k.classList.toggle('on', v); } }
    k.addEventListener('pointerdown', function (e) { e.preventDefault(); k.setPointerCapture(e.pointerId); set(true); });
    ['pointerup', 'pointercancel', 'lostpointercapture'].forEach(function (ev) { k.addEventListener(ev, function () { set(false); }); });
    k.addEventListener('keydown', function (e) { if (e.key === ' ') { e.preventDefault(); if (!e.repeat) set(true); } });
    k.addEventListener('keyup', function (e) { if (e.key === ' ') { e.preventDefault(); set(false); } });
    k.addEventListener('blur', function () { set(false); });
  })();

  // ---- 🎤 Listen: a tone from the microphone keys EF4 (js/tone-listen.js) ----
  var listener = null;
  btn('listen').addEventListener('click', function () {
    var b = this, note = btn('listenNote');
    if (listener) {
      listener.stop(); listener = null; app.keyEdge(0);
      b.textContent = '🎤 Listen'; b.setAttribute('aria-pressed', 'false');
      note.textContent = 'Stopped listening.';
      return;
    }
    listener = new window.ToneListen({
      onEdge: function (v, wall) { app.keyEdge(v, wall); },
      onMeter: function (m) {
        var db = m.level > 0 ? Math.round(10 * Math.log10(m.level)) : -99;
        note.textContent = (m.down ? '● TONE  ' : '○ quiet  ') + m.hz + ' Hz  ' + db + ' dB' +
          (clock.current().ips === window.ClockRow.ELF2K ? '' : '  - set the clock to Elf2K for Morse timing');
      }
    });
    b.textContent = '🎤 Listening…'; b.setAttribute('aria-pressed', 'true');
    note.textContent = 'Allow the microphone, then send a tone (another laptop, Sound on, Morse Sender v18).';
    listener.start('js/tone-detect.js?v=118').catch(function (e) {
      listener = null; b.textContent = '🎤 Listen'; b.setAttribute('aria-pressed', 'false');
      note.textContent = 'Could not listen: ' + (e && e.message || e);
    });
  });
})();
