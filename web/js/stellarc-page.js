// Glue for stellarc.html: the Stellar C editor, the compiler, and a runner.
//
// The compiler is the real one (SC/scc.py in the work repo, baked into web/sc/ by
// web/build/bake_scc.py) running under Pyodide - Python compiled to WebAssembly - so
// the page can never compile differently from the tool the hardware programs are
// built with. Pyodide is about 10 MB the first time, cached after that; the rest of
// the site does not load it.
(function () {
  'use strict';

  var V = '?v=69';
  var PYODIDE = 'https://cdn.jsdelivr.net/pyodide/v0.29.3/full/';
  var DRAFT = 'stellarc-draft';

  function $(id) { return document.getElementById(id); }
  var src = $('src'), gutter = $('gutter'), out = $('out');
  var examples = [], current = 0;
  var lst = null, lstName = 'program', dirty = true, errLine = 0;

  // ---------------------------------------------------------------- the editor
  function renumber() {
    var n = src.value.split('\n').length, s = '';
    for (var i = 1; i <= n; i++) s += (i === errLine ? '<span class="sc-errline">' + i + '</span>' : i) + '\n';
    gutter.innerHTML = s;
    gutter.scrollTop = src.scrollTop;
  }
  src.addEventListener('scroll', function () { gutter.scrollTop = src.scrollTop; });
  var saveTimer = null;
  src.addEventListener('input', function () {
    dirty = true; errLine = 0; renumber();
    $('download').disabled = true;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      try { localStorage.setItem(DRAFT, JSON.stringify({ example: current, src: src.value })); } catch (e) {}
    }, 400);
  });
  src.addEventListener('keydown', function (e) {
    if (e.key === 'Tab' && !e.shiftKey) {                 // indent instead of leaving the editor
      e.preventDefault();
      var a = src.selectionStart, b = src.selectionEnd;
      src.setRangeText('    ', a, b, 'end');
      src.dispatchEvent(new Event('input'));
    } else if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault(); runProgram();
    }
  });

  function setSource(text) {
    src.value = text; src.scrollTop = 0;
    dirty = true; errLine = 0; lst = null; renumber();
    $('download').disabled = true;
    out.textContent = 'Compile to see the STELLAR bytecode here, each opcode next to the source line it came from.';
    $('outTitle').textContent = '';
  }

  function showExample(i, keepDraft) {
    var ex = examples[i];
    current = i;
    $('example').value = i;
    $('blurb').textContent = ex.blurb || '';
    $('input').value = (ex.input || '').replace(/\r/g, '\\r');
    if (ex.speed && clock) clock.set(ex.speed);
    lstName = ex.file.replace(/\.sc$/, '');
    if (keepDraft) return;
    try { localStorage.removeItem(DRAFT); } catch (e) {}
    return fetch('sc/examples/' + ex.file + V).then(function (r) { return r.text(); }).then(setSource);
  }

  // ---------------------------------------------------------------- the compiler
  function loadScript(url) {
    return new Promise(function (ok, fail) {
      var s = document.createElement('script');
      s.src = url; s.onload = ok;
      s.onerror = function () { fail(new Error('could not load ' + url)); };
      document.head.appendChild(s);
    });
  }

  var manifest = fetch('sc/manifest.json' + V).then(function (r) { return r.json(); });
  var t0 = Date.now();
  var python = Promise.all([manifest, loadScript(PYODIDE + 'pyodide.js')])
    .then(function (got) {
      $('ccStatus').textContent = 'starting Python in your browser (about 10 MB the first time, cached after that)…';
      return Promise.all([got[0], window.loadPyodide({ indexURL: PYODIDE })]);
    })
    .then(function (got) {
      var m = got[0], py = got[1];
      py.FS.mkdirTree('/sc');
      return Promise.all(m.files.map(function (f) {
        return fetch('sc/' + f + V).then(function (r) {
          if (!r.ok) throw new Error('sc/' + f + ': ' + r.status);
          return r.text();
        }).then(function (t) { py.FS.writeFile('/sc/' + f, t); });
      })).then(function () {
        py.runPython('import sys, json\nsys.path.insert(0, "/sc")\nimport scc');
        return py;
      });
    });
  python.then(function () {
    $('ccStatus').textContent = 'compiler ready (' + ((Date.now() - t0) / 1000).toFixed(1) + ' s to load) — Compile, or Run ▶ to compile and run';
  }, function (e) {
    $('ccStatus').textContent = 'the compiler could not load: ' + e.message +
      '. It needs cdn.jsdelivr.net (Pyodide) - check the connection or a content blocker, then reload.';
    $('compile').disabled = true;
  });

  function compile() {
    return python.then(function (py) {
      $('ccStatus').textContent = 'compiling…';
      py.globals.set('SRC', src.value);
      py.globals.set('NAME', lstName);
      var t = performance.now();
      var r = JSON.parse(py.runPython('json.dumps(scc.compile_text(SRC, NAME))'));
      var ms = Math.round(performance.now() - t);
      if (r.error) {
        lst = null; $('download').disabled = true;
        var m = r.error.match(/line (\d+)/);
        errLine = m ? +m[1] : 0; renumber();
        out.innerHTML = '';
        var e = document.createElement('span'); e.className = 'sc-err'; e.textContent = r.error;
        out.appendChild(e);
        $('outTitle').textContent = '— error';
        $('ccStatus').textContent = 'compile failed' + (errLine ? ' at line ' + errLine : '');
        if (errLine) goToLine(errLine);
        return false;
      }
      lst = r.lst; dirty = false; errLine = 0; renumber();
      out.textContent = r.lst;
      $('outTitle').textContent = '— ' + r.summary;
      $('download').disabled = false;
      $('ccStatus').textContent = 'compiled in ' + ms + ' ms: ' + r.summary;
      return true;
    });
  }

  function goToLine(n) {
    var lines = src.value.split('\n'), a = 0;
    for (var i = 0; i < n - 1 && i < lines.length; i++) a += lines[i].length + 1;
    src.focus();
    src.setSelectionRange(a, a + (lines[n - 1] || '').length);
    var lh = parseFloat(getComputedStyle(src).lineHeight) || 19;
    src.scrollTop = Math.max(0, (n - 5) * lh);
  }

  // ---------------------------------------------------------------- the runner
  // The Elf2K front panel: Q lamp and the two-digit display of the last byte sent to
  // the output port (core $x039, DEFOUT; the Elf2K's default is 4), read off the CPU
  // as the Simulator page does.
  var panel = new window.FrontPanel($('frontpanel'));
  function panelState(s) {
    var cpu = app.vm && app.vm.cpu;
    if (!cpu) return s;
    var CORE = (window.StellarVMLib && window.StellarVMLib.CORE) || 0x3000;
    var port = cpu.M[CORE + 0x39] || 4;
    var log = cpu.io_out[port];
    s.q = cpu.Q ? 1 : 0;
    s.outPort = port;
    s.outByte = (log && log.length) ? log[log.length - 1] : null;
    return s;
  }

  var app = new window.SimApp({
    terminalEl: $('term'),
    statusEl: $('status'),
    coldBoot: true,
    onState: function (s) {
      panel.render(panelState(s));
      $('pause').disabled = !app.running;
      $('reset').disabled = !app.vm;
      halted = !!s.halted;
    }
  });
  var halted = true, loaded = null;

  function loadIntoMachine() {
    app.load(lst, $('input').value.replace(/\\r/g, '\r').replace(/\\n/g, '\n'));
    loaded = lst;
  }

  function runProgram() {
    var go = function () {
      if (!lst) return;
      if (loaded !== lst || halted || !app.vm) loadIntoMachine();
      app.run();
      $('pause').disabled = false;
      $('term').focus({ preventScroll: true });
    };
    if (dirty || !lst) compile().then(function (ok) { if (ok) go(); });
    else go();
  }

  $('compile').addEventListener('click', function () {
    compile().then(function (ok) { if (ok) { loadIntoMachine(); } });
  });
  $('run').addEventListener('click', runProgram);
  $('pause').addEventListener('click', function () { app.stop(); app._setStatus('paused'); $('pause').disabled = true; });
  $('reset').addEventListener('click', function () { app.reset(); });
  $('download').addEventListener('click', function () {
    if (!lst) return;
    var url = URL.createObjectURL(new Blob([lst], { type: 'text/plain' }));
    var a = document.createElement('a');
    a.href = url; a.download = lstName + '.lst';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  });
  $('example').addEventListener('change', function () { showExample(+this.value); });
  $('revert').addEventListener('click', function () { showExample(current); });

  window.attachTerminalInput($('term'), function () { return app.vm && app.vm.cpu; });
  var clock = window.ClockRow($('clockBtns'), $('speedLabel'), function (sp) {
    app.setSpeed(sp.ops || 0, sp.ms, sp.ips);
  });

  // ---------------------------------------------------------------- start
  manifest.then(function (m) {
    examples = m.examples;
    examples.forEach(function (ex, i) {
      var o = document.createElement('option');
      o.value = i; o.textContent = ex.name; $('example').appendChild(o);
    });
    var draft = null;
    try { draft = JSON.parse(localStorage.getItem(DRAFT) || 'null'); } catch (e) {}
    if (draft && examples[draft.example] && typeof draft.src === 'string') {
      showExample(draft.example, true);
      setSource(draft.src);
      $('blurb').textContent = 'Your edits from last time are back. Revert reloads the example.';
    } else {
      showExample(0);
    }
  }).catch(function (e) {
    $('ccStatus').textContent = (location.protocol === 'file:')
      ? 'This page has to be SERVED over http, not opened as a file. See web/README-running.md.'
      : 'could not load the examples: ' + e;
  });
})();
