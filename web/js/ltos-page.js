// Glue for ltos.html: the Elf2K (elf2k.js) with the web BIOS and the demo card, the VT100, the clock, the
// card kept in this browser (IndexedDB: only the sectors LTOS has written), and the "Things to try" list.
(function () {
  'use strict';

  var V = '144';                                    // the ?v= the card is fetched with
  var KEY = null;                                   // what saved changes are kept under: this card's fingerprint
  var ELF2K = 170000;                               // 1802 instructions a second on Craig's 3 MHz Elf2K
  var SPEEDS = [
    { label: 'Elf2K', ips: ELF2K, title: 'Real time: a 3 MHz Elf2K' },
    { label: '2×', ips: ELF2K * 2 },
    { label: '10×', ips: ELF2K * 10 },
    { label: '50×', ips: ELF2K * 50 },
    { label: 'flat out', ips: 0, title: 'As fast as this browser can go' }
  ];
  var TRY = [
    ['HELP', 'every command'],
    ['TYPE README.TXT', 'what is on this card'],
    ['DIR /BIN', 'the programs, and the STELLAR apps (.STL)'],
    ['TEST', 'a script: a name alone finds TEST.SH'],
    ['DEMO you', 'DEMO.SH: functions, loops, case, $( )'],
    ['SH -x TEST', 'each line shown as it runs'],
    ['LW2 DOCS/LETTER.TXT', 'Lite-Writer 2 (Ctrl-X: the menu)'],
    ['LW3 DOCS/BOOK.TXT', 'Lite-Writer 3: a 20 KB file, a part at a time (Ctrl-N, Ctrl-P)'],
    ['ENANO DOCS/BOOK.TXT', 'ENANO: a small nano in 1802 code - long lines wrapped, Shift+arrow selects (Ctrl-G: every key)'],
    ['GALAXIA', 'a game: arrows, SPACE; Esc back to LTOS'],
    ['ORBIT', 'STELLAR ORBIT: Apollo 7 on three VMs (SPACE: the count, ?: help)'],
    ['TETRIS', 'more games: SNAKE, PONG, INVADERS, BREAKOUT, MAZE'],
    ['EROFF EROFF.RF', 'a small nroff: plain text made into pages, headings, lists'],
    ['DISKINFO', 'all about the card: model, format, label, space, files and folders'],
    ['DICE', 'a Stellar C app: rand(6) + 1, two dice (S: 600 rolls, Q quits)'],
    ['SORT -r DOCS/SALES.TXT', 'SORT, UNIQ, PWD and more tools'],
    ["RAWK '{ s += $2 } END { print s }' DOCS/SALES.TXT", 'awk on the 1802'],
    ['ECHO hello > HI.TXT', 'a file written to the card'],
    ['FSCK', 'check the card (slow at Elf2K speed)'],
    ['VER', 'the kernel and the card']
  ];

  var termEl = document.getElementById('term');
  var statusEl = document.getElementById('status');
  var vt = window.VT100(termEl);
  var bios = Uint8Array.from(atob(window.LTOS_WEBBIOS), function (c) { return c.charCodeAt(0); });
  var base = null, m = null, speed = SPEEDS[2], halted = false, lastSave = 0, out = [];

  function status(t) { statusEl.textContent = t; }

  // ---- the card in this browser: the sectors written since it was baked ----
  var db = null;
  // A browser can leave IndexedDB unanswered (Safari, coming back to the page): then LTOS boots without
  // the saved changes after 2 s, rather than never.
  function timed(p, v) { return Promise.race([p, new Promise(function (ok) { setTimeout(function () { ok(v); }, 2000); })]); }
  function openDb() {
    return timed(new Promise(function (ok) {
      try {
        var r = indexedDB.open('ltos-card', 1);
        r.onupgradeneeded = function () { r.result.createObjectStore('sectors'); };
        r.onsuccess = function () { db = r.result; db.onversionchange = function () { db.close(); db = null; }; ok(); };
        r.onerror = r.onblocked = function () { ok(); };
      } catch (e) { ok(); }
    }));
  }
  function loadSaved() {
    return timed(new Promise(function (ok) {
      if (!db) return ok(null);
      try {
        var g = db.transaction('sectors').objectStore('sectors').get(KEY);
        g.onsuccess = function () { ok(g.result || null); };
        g.onerror = function () { ok(null); };
      } catch (e) { ok(null); }
    }), null);
  }
  function save() {
    if (!db || !KEY || !m || !m.cf.dirty.size) return;
    var keep = {};
    m.cf.dirty.forEach(function (l) { keep[l] = m.cf.disk.get(l); });
    try { db.transaction('sectors', 'readwrite').objectStore('sectors').put(keep, KEY); } catch (e) {}
  }
  function forget() {
    try { if (db) db.transaction('sectors', 'readwrite').objectStore('sectors').delete(KEY); } catch (e) {}
  }

  // ---- the machine ----
  function power(saved) {
    var map = new Map(base.map);
    var dirty = [];
    if (saved) Object.keys(saved).forEach(function (k) { map.set(+k, saved[k]); dirty.push(+k); });
    m = new window.Elf2K.Machine({ bios: bios, firmware: window.STELLAR_FIRMWARE, sectors: base.sectors, card: map,
                                   onOutput: function (b) { out.push(b); } });
    dirty.forEach(function (l) { m.cf.dirty.add(l); });
    m.authentic = document.getElementById('authentic').checked;
    vt.reset(); vt.dirty = true; halted = false;
    status(saved ? 'Booting LTOS from your card (' + dirty.length + ' sectors changed in this browser)…' : 'Booting LTOS…');
    termEl.focus({ preventScroll: true });
  }

  var last = performance.now(), shown = 0;
  function frame(now) {
    requestAnimationFrame(frame);                   // first: an error below must not stop the machine for good
    var dt = Math.min(now - last, 100); last = now;
    if (m && !halted) try {
      var t0 = performance.now();
      if (speed.ips) {
        if (!m.run(Math.round(speed.ips * dt / 1000))) halted = true;
      } else {
        while (performance.now() - t0 < 14) if (!m.run(20000)) { halted = true; break; }
      }
      if (halted) status('The 1802 stopped (IDL). Press Boot to start again.');
      if (out.length) { vt.write(out); out = []; }
      vt.render();
      if (now - lastSave > 2000) { lastSave = now; save(); }
      if (now - shown > 1000) {
        shown = now;
        if (!halted && /Booting/.test(statusEl.textContent) && m.instr > 200000) status('Running LTOS 0.5 at ' + speed.label + '.');
      }
    } catch (e) { halted = true; status('The emulator stopped (' + e.message + '). Press Boot to start again.'); }
  }
  requestAnimationFrame(frame);                     // running from the start: Boot and Restore work whatever the card load does

  // ---- the controls ----
  var sp = document.getElementById('speeds');
  SPEEDS.forEach(function (s) {
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'clock-btn'; b.textContent = s.label; b.title = s.title || ('×' + (s.ips / ELF2K) + ' the Elf2K');
    b.setAttribute('role', 'radio');
    b.addEventListener('click', function () { pick(s); });
    s.btn = b; sp.appendChild(b);
  });
  function pick(s) {
    speed = s;
    SPEEDS.forEach(function (x) { x.btn.classList.toggle('active', x === s); x.btn.setAttribute('aria-checked', x === s); });
    document.getElementById('speedLabel').textContent = s.ips ? '≈ ' + Math.round(s.ips / 1000) + 'k 1802 instructions a second' : 'no pacing';
    try { localStorage.setItem('ltos-speed', s.label); } catch (e) {}
  }
  var want = null; try { want = localStorage.getItem('ltos-speed'); } catch (e) {}
  pick(SPEEDS.filter(function (s) { return s.label === want; })[0] || SPEEDS[2]);

  document.getElementById('boot').addEventListener('click', function () {
    if (!base) return status('The card image is still loading…');
    save(); loadSaved().then(power);
  });
  document.getElementById('fresh').addEventListener('click', function () {
    if (!confirm('Put every file on the card back as it was, and start LTOS again? Anything you changed or saved on it will be gone.')) return;
    if (!base) return status('The card image is still loading…');
    forget(); power(null); status('The card is as it was baked. Booting LTOS…');
  });
  document.getElementById('authentic').addEventListener('change', function (e) { if (m) m.authentic = e.target.checked; });
  document.getElementById('saveImg').addEventListener('click', function () {
    if (!m) return;
    var img = new Uint8Array(base.sectors * 512);
    m.cf.disk.forEach(function (s, l) { img.set(s, l * 512); });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([img], { type: 'application/octet-stream' }));
    a.download = 'ltos-card.img'; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 5000);
  });
  var tryEl = document.getElementById('try');
  TRY.forEach(function (t) {
    var b = document.createElement('button');
    b.type = 'button'; b.innerHTML = '';
    b.appendChild(document.createTextNode(t[0]));
    var s = document.createElement('small'); s.textContent = t[1]; b.appendChild(s);
    b.addEventListener('click', function () {
      if (!m) return;
      var k = []; for (var i = 0; i < t[0].length; i++) k.push(t[0].charCodeAt(i));
      k.push(13); m.keys(k); termEl.focus({ preventScroll: true });
    });
    tryEl.appendChild(b);
  });
  window.attachTerminalInput(termEl, function () { return m && m.cpu; });
  window.LTOSPage = {                               // for checking the page by hand (the console)
    machine: function () { return m; },
    type: function (s) { if (m) m.keys(Array.from(s, function (ch) { return ch.charCodeAt(0); })); }
  };
  window.addEventListener('pagehide', save);

  // ---- start ----
  fetch('ltos/ltos-card.bin?v=' + V).then(function (r) {
    if (!r.ok) throw new Error('the card image: ' + r.status);
    return r.arrayBuffer();
  }).then(function (buf) {
    base = window.Elf2K.parseCard(buf);
    var h = 0x811C9DC5, b = new Uint8Array(buf);             // FNV-1a: changes saved for an older card are not
    for (var i = 0; i < b.length; i++) h = Math.imul(h ^ b[i], 16777619) >>> 0;   //  laid over a new one
    KEY = 'card-' + h.toString(16) + '-' + b.length;
    return openDb();
  }).then(loadSaved).then(function (saved) {
    power(saved);
  }).catch(function (e) { status('Could not start: ' + e.message); });
})();
