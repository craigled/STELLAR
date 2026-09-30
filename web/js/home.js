// The home page: one StellarMachine running four programs, drawn four ways -
// four VT100 screens, the die, the scheduler timeline, and the descent panels.
(function () {
  'use strict';

  var V = '?v=68';
  var LINEUP = [
    { file: 'Mandelbrot.lst', name: 'Mandelbrot', input: '',       what: 'fixed-point maths' },
    { file: 'Starfield.lst',  name: 'Starfield',  input: ' 12\r',  what: 'VT100 animation' },
    { file: 'Invaders.lst',   name: 'Invaders',   input: '',       what: 'a game: click, press a key' },
    { file: 'Starship.lst',   name: 'Starship',   input: '',       what: 'a picture, run-length drawn' }
  ];
  var VMC = ['#9aa3b8', '#ffb547', '#5fe3d0', '#ff7a90', '#b8f36a'];

  var Machine = window.StellarMachine, Die = window.StellarDie, COS = window.Cosmac;
  var OPS = {};
  (window.STELLAR_OPCODES || []).forEach(function (o) { OPS[o.op] = o; });

  var $ = function (id) { return document.getElementById(id); };
  function h2(v) { return COS.h2(v); }
  function h4(v) { return COS.h4(v); }
  function fmt(n) {
    if (n >= 1e9) return (n / 1e9).toFixed(2) + 'B';
    if (n >= 1e6) return (n / 1e6).toFixed(2) + 'M';
    if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k';
    return String(Math.round(n));
  }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }

  var m = null, die = null, screens = [], texts = [];
  var speed = 40, paused = false, frozen = false, focusVM = 0;

  // ---------------------------------------------------------------- screens
  function buildQuad() {
    var q = $('quad');
    LINEUP.forEach(function (p, i) {
      var vm = i + 1;
      var el = document.createElement('div');
      el.className = 'crt';
      el.style.setProperty('--vm', VMC[vm]);
      el.innerHTML =
        '<div class="crt-h"><span class="dot"></span><b>VM' + vm + '</b>' +
        '<span class="crt-name">' + p.name + '</span>' +
        '<span class="crt-addr mono">$' + h4(0x4000 + i * 0x1000) + '</span>' +
        '<span class="grow"></span><span class="crt-ops mono" id="ops' + vm + '"></span></div>' +
        '<div class="crt-screen" tabindex="0" role="textbox" aria-label="VM' + vm + ' ' + p.name +
        ' screen. Click and type to send keys to this VM."><pre class="vt"></pre>' +
        '<div class="crt-hint">' + p.what + '</div></div>';
      q.appendChild(el);
      var scr = el.querySelector('.crt-screen');
      screens.push(window.VT100(el.querySelector('.vt')));
      scr.addEventListener('focus', function () { focusVM = vm; el.classList.add('focus'); });
      scr.addEventListener('blur', function () { if (focusVM === vm) focusVM = 0; el.classList.remove('focus'); });
      scr.addEventListener('keydown', function (e) {
        var b = keyBytes(e);
        if (!b) return;
        e.preventDefault();
        if (!m) return;
        if (prompted[vm]) runPromptKey(vm, b);
        else m.sendKeys(vm, b);
      });
    });
  }

  // ---------------------------------------------------------------- RUN prompt
  // When a VM's app finishes, its screen offers a prompt; RUN + Enter starts the app
  // again in that VM (Machine.rerun) while the others carry on. Typing here is echoed
  // locally - the VM itself is finished and reads nothing.
  var prompted = [false, false, false, false, false], runLine = ['', '', '', '', ''];
  function say(vm, text) {
    var b = [];
    for (var i = 0; i < text.length; i++) b.push(text.charCodeAt(i));
    screens[vm - 1].write(b);
  }
  function checkFinished() {
    for (var v = 1; v <= 4; v++) {
      if (prompted[v] || !m.vmFinished(v)) continue;
      var b = m.drain(v);
      if (b) screens[v - 1].write(b);
      prompted[v] = true; runLine[v] = '';
      say(v, '\x1b[0m\x1b[?25h\r\n' + LINEUP[v - 1].name + ' has finished. Type RUN to start it again.\r\n> ');
    }
  }
  function runPromptKey(vm, b) {
    var ch = b[0];
    if (b.length === 1 && ch === 0x0D) {
      if (runLine[vm].trim().toUpperCase() === 'RUN' && m.rerun(vm)) {
        prompted[vm] = false; runLine[vm] = '';
        screens[vm - 1].reset();
        markTabs();
      } else {
        say(vm, '\r\n?  only RUN is understood here\r\n> ');
        runLine[vm] = '';
      }
    } else if (b.length === 1 && (ch === 0x08 || ch === 0x7F)) {
      if (runLine[vm].length) { runLine[vm] = runLine[vm].slice(0, -1); say(vm, '\b \b'); }
    } else if (b.length === 1 && ch >= 0x20 && ch < 0x7F && runLine[vm].length < 40) {
      runLine[vm] += String.fromCharCode(ch); say(vm, String.fromCharCode(ch));
    }
    screens[vm - 1].render();
  }

  function keyBytes(e) {
    if (e.metaKey || e.altKey) return null;
    var arrows = { ArrowUp: 'A', ArrowDown: 'B', ArrowRight: 'C', ArrowLeft: 'D' };
    if (arrows[e.key]) return [0x1B, 0x5B, arrows[e.key].charCodeAt(0)];
    if (e.key === 'Enter') return [0x0D];
    if (e.key === 'Backspace') return [0x08];
    if (e.key === 'Escape') return [0x1B];
    if (e.ctrlKey && /^[a-zA-Z]$/.test(e.key)) return [e.key.toUpperCase().charCodeAt(0) - 64];
    if (!e.ctrlKey && e.key.length === 1) return [e.key.charCodeAt(0) & 0xFF];
    return null;
  }

  // ---------------------------------------------------------------- die labels
  function buildDieLabels() {
    var host = $('dieLabels');
    // rows are 128 bytes: address / 128 / 256 = fraction of the height
    var marks = [
      [0x0000, 0x0800, 'kernel', 0], [0x0800, 0x0A00, 'dispatch', 0], [0x0A00, 0x2F00, 'opcode handlers', 0],
      [0x2F00, 0x3000, 'CIDP', 0], [0x3000, 0x4000, 'cores', 0],
      [0x4000, 0x5000, 'VM1', 1], [0x5000, 0x6000, 'VM2', 2], [0x6000, 0x7000, 'VM3', 3], [0x7000, 0x8000, 'VM4', 4]
    ];
    marks.forEach(function (mk) {
      var d = document.createElement('div');
      d.className = 'dl' + (mk[3] ? ' vm' : '');
      d.style.top = (mk[0] / 0x8000 * 100) + '%';
      d.style.height = ((mk[1] - mk[0]) / 0x8000 * 100) + '%';
      if (mk[3]) d.style.setProperty('--vm', VMC[mk[3]]);
      d.innerHTML = '<span>' + mk[2] + '</span><i class="mono">$' + h4(mk[0]) + '</i>';
      host.appendChild(d);
    });
    var cv = $('die'), read = $('dieRead');
    cv.addEventListener('mousemove', function (e) {
      var r = cv.getBoundingClientRect();
      var x = Math.floor((e.clientX - r.left) / r.width * 128);
      var y = Math.floor((e.clientY - r.top) / r.height * 256);
      if (x < 0 || y < 0 || x > 127 || y > 255 || !m) return;
      var a = y * 128 + x;
      read.innerHTML = '<b>$' + h4(a) + '</b> = ' + h2(m.M[a]) + ' · ' + Die.region(a);
    });
    cv.addEventListener('mouseleave', function () { read.textContent = 'hover the die'; });
  }

  // ---------------------------------------------------------------- CIDP
  // The Common Interchange Data Page, $2F00: how the scheduler and the VMs keep
  // track of each other. Only the rows the firmware uses are shown: one 16-byte
  // entry per VM, the scheduler's own state at $2F50, and the top of the page,
  // where the 1802's hardware stack (R2) lives.
  var CIDP_ROWS = [0x00, 0x10, 0x20, 0x30, 'gap', 0x50, 'gap', 0xF0];
  var VM_FIELDS = ['VM number', 'core page', 'program page', 'max size (pages)', 'count', 'state',
    '#commands', '#commands', '#commands', '#commands', 'mode', 'status'];
  var SYS_FIELDS = { 0x50: 'system interrupt state', 0x51: 'VM error', 0x52: 'current VM — who has the CPU',
    0x53: 'max VMs', 0x54: 'total VMs', 0x55: 'multitasking allowed (C7 SETMULTI)', 0x56: 'VM operation',
    0x57: 'VM repeat', 0x5F: 'hardware interrupt flip-flop' };
  var STATES = ['done', 'active', 'completed this cycle', 'idle / waiting', 'paused', 'killed', 'stopped on error'];
  var cidpCells = [];

  function cidpField(o) {
    if (o < 0x40) {
      var f = o & 0xF, vm = (o >> 4) + 1;
      return 'VM' + vm + ' ' + (VM_FIELDS[f] || 'unused');
    }
    if (o >= 0x50 && o < 0x60) return SYS_FIELDS[o] || 'scheduler (unused)';
    if (o >= 0xF0) return '1802 hardware stack (R2 grows down from here)';
    return 'unused';
  }

  function buildCidp() {
    var g = $('cidpGrid'), html = '';
    CIDP_ROWS.forEach(function (r) {
      if (r === 'gap') { html += '<div class="gap">⋮</div>'; return; }
      html += '<span class="ra">$2F' + h2(r) + '</span>';
      for (var i = 0; i < 16; i++) {
        var o = r + i, cls = 'cb', style = '';
        if (o < 0x40) { cls += ' vmrow'; style = ' style="--vm:' + VMC[(o >> 4) + 1] + '"'; if ((o & 0xF) === 5) cls += ' state'; }
        else if (o < 0x60) cls += ' sys';
        html += '<span class="' + cls + '"' + style + ' data-o="' + o + '"></span>';
      }
    });
    g.innerHTML = html;
    cidpCells = Array.prototype.slice.call(g.querySelectorAll('.cb'));
    var read = $('dieRead');
    g.addEventListener('mouseover', function (e) {
      var c = e.target.closest ? e.target.closest('.cb') : null;
      if (!c || !m) return;
      var o = +c.dataset.o, v = m.M[0x2F00 + o], extra = '';
      if (o < 0x40 && (o & 0xF) === 5) extra = ' (' + (STATES[v] || '?') + ')';
      if (o === 0x55) extra = v ? ' (on)' : ' (off)';
      read.innerHTML = '<b>$' + h4(0x2F00 + o) + '</b> = ' + h2(v) + extra + ' · CIDP · ' + cidpField(o);
    });
    g.addEventListener('mouseleave', function () { read.textContent = 'hover the die'; });
  }

  function renderCidp() {
    if (!cidpCells.length) return;
    var M = m.M, wh = m.wheat, cur = M[0x2F52];
    for (var i = 0; i < cidpCells.length; i++) {
      var el = cidpCells[i], o = +el.dataset.o, a = 0x2F00 + o, v = M[a], t = h2(v);
      if (el.textContent !== t) el.textContent = t;
      var nz = v !== 0, hot = wh[a] > 40, isCur = o < 0x40 && (o >> 4) + 1 === cur;
      if (el._nz !== nz) { el._nz = nz; el.classList.toggle('nz', nz); }
      if (el._hot !== hot) { el._hot = hot; el.classList.toggle('hot', hot); }
      if (el._cur !== isCur) { el._cur = isCur; el.classList.toggle('cur', isCur); }
    }
    var st = [];
    st.push(cur >= 1 && cur <= 4 ? 'VM' + cur + ' running' : 'scheduler');
    st.push(M[0x2F54] + ' VMs');
    st.push('multitasking ' + (M[0x2F55] ? 'on' : 'off'));
    var sum = st.join(' · ');
    if ($('cidpSum').textContent !== sum) $('cidpSum').textContent = sum;
  }

  // ---------------------------------------------------------------- timeline
  function drawTimeline() {
    var cv = $('timeline'), dpr = window.devicePixelRatio || 1;
    var W = cv.clientWidth, H = 44;
    if (!W) return;
    if (cv.width !== Math.round(W * dpr)) { cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr); }
    var ctx = cv.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    var sl = m.recentSlices(400), span = 0;
    // show the most recent ~120k machine cycles (about a third of a second on the Elf2K)
    var WINDOW = 120000, x = W;
    for (var i = sl.length - 1; i >= 0 && x > 0; i--) {
      var w = sl[i][1] / WINDOW * W;
      x -= w;
      var vm = sl[i][0];
      ctx.fillStyle = VMC[vm] || VMC[0];
      ctx.globalAlpha = vm ? 0.92 : 0.35;
      ctx.fillRect(Math.max(0, x), vm ? 6 : 18, Math.max(0.6, w - 0.6), vm ? 32 : 8);
      span += sl[i][1];
    }
    ctx.globalAlpha = 1;
  }

  function drawShare() {
    var tot = 0, v, html = '';
    for (v = 1; v <= 4; v++) tot += m.vmCycles[v];
    for (v = 1; v <= 4; v++) {
      var pct = tot ? m.vmCycles[v] / tot * 100 : 0;
      html += '<div class="sh" style="--vm:' + VMC[v] + ';flex-grow:' + Math.max(pct, 0.5) + '">' +
        '<span>VM' + v + ' ' + pct.toFixed(0) + '%</span></div>';
    }
    $('share').innerHTML = html;
  }

  // ---------------------------------------------------------------- telemetry
  var lastTel = 0, lastInstr = 0, lastTelT = 0;
  function telemetry(now) {
    var secs = m.cycles / Machine.CYCLES_PER_SEC;
    var mm = Math.floor(secs / 60), ss = Math.floor(secs % 60);
    $('tmTime').textContent = (mm >= 60 ? Math.floor(mm / 60) + 'h ' + (mm % 60) + 'm' : mm + ':' + (ss < 10 ? '0' : '') + ss);
    $('tmInstr').textContent = fmt(m.instr);
    var ops = 0;
    for (var v = 1; v <= 4; v++) {
      var o = m.vmOps(v); ops += o;
      var st = m.vmState(v);
      $('ops' + v).textContent = fmt(o) + ' ops' + (st === 0 ? ' · done' : '');
    }
    $('tmOps').textContent = fmt(ops);
    $('tmRatio').textContent = ops ? Math.round(m.instr / ops) : '—';
    if (lastTelT) {
      var dt = (now - lastTelT) / 1000, di = m.instr - lastInstr;
      var rate = di / dt;   // 1802 instructions per real second
      var x = (m.cycles - lastCyc) / dt / Machine.CYCLES_PER_SEC;
      $('tmSpeed').textContent = speed < 0 ? stepMsg : paused || frozen ? 'paused' : (x < 1.5 ? '≈ Elf2K speed' : x.toFixed(0) + '× the Elf2K');
      $('tmSpeed').title = fmt(rate) + ' 1802 instructions per second';
    }
    lastTelT = now; lastInstr = m.instr; lastCyc = m.cycles;
    drawShare();
  }
  var lastCyc = 0;

  // ---------------------------------------------------------------- descent
  var PHASES = {
    fetch:   ['fetch & dispatch', 'Read the opcode byte at the VM\'s program counter and jump through the table at $0800.'],
    handler: ['handler', 'The firmware routine that carries out this opcode.'],
    scrt:    ['call / return', 'SCRT: the 1802 has no CALL instruction, so R4 and R5 point at small routines that do it.'],
    sched:   ['scheduler', 'Count the VM\'s quantum; hand the chip to the next VM when it runs out.']
  };
  function phaseOf(pc) {
    if (pc >= 0x0100 && pc <= 0x0167) return 'fetch';
    if (pc >= 0x0050 && pc < 0x0100) return 'sched';
    if (pc >= 0x0340 && pc < 0x0380) return 'scrt';
    return 'handler';
  }
  function opLen(op) { var o = OPS[op]; return o && o.length > 0 ? o.length : 0; }
  function opName(op) { var o = OPS[op]; return o ? o.name : '$' + h2(op); }

  function buildTabs() {
    var host = $('vmTabs');
    LINEUP.forEach(function (p, i) {
      var b = document.createElement('button');
      b.type = 'button'; b.setAttribute('role', 'tab');
      b.style.setProperty('--vm', VMC[i + 1]);
      b.innerHTML = '<span class="dot"></span>VM' + (i + 1) + ' <span class="t-n">' + p.name + '</span>';
      b.addEventListener('click', function () {
        m.setTraceVM(i + 1);
        markTabs();
        if (frozen) stepOne(); else renderDescent(true);
      });
      host.appendChild(b);
    });
    markTabs();
  }
  function markTabs() {
    var bs = $('vmTabs').children;
    for (var i = 0; i < bs.length; i++) bs[i].setAttribute('aria-selected', m && m.traceVM === i + 1 ? 'true' : 'false');
  }

  function buildCoreGrid() {
    var g = $('coregrid'), html = '';
    for (var i = 0; i < 256; i++) html += '<span data-o="' + i + '" class="' + coreClass(i) + '"></span>';
    g.innerHTML = html;
    texts = g.children;
    $('coreLegend').innerHTML = [
      ['reg', 'R0–RF virtual registers'], ['acc', 'accumulator'], ['da', 'decimal acc'],
      ['pl', 'command · program counter · counter'], ['flag', 'flags'], ['ma', 'math acc'], ['q', 'quantum']
    ].map(function (l) { return '<span class="lg ' + l[0] + '"><i></i>' + l[1] + '</span>'; }).join('');
  }
  function coreClass(o) {
    if (o < 0x20) return 'reg';
    if (o < 0x22) return 'acc';
    if (o >= 0x28 && o < 0x30) return 'da';
    if (o >= 0x30 && o < 0x37) return 'pl';
    if (o >= 0x45 && o < 0x50) return 'flag';
    if (o === 0x5E || o === 0x5F) return 'q';
    if (o >= 0x68 && o < 0x6F) return 'ma';
    return '';
  }

  var shownRec = null;
  function renderDescent(force) {
    if (!m || !m.ops.length) return;
    var rec = m.ops[m.ops.length - 1];
    if (rec === shownRec && !force) { renderCore(); return; }
    shownRec = rec;
    var M = m.M, vm = m.traceVM;

    // A - bytecode stream: the last few opcodes of this VM
    var recent = m.ops.slice(-9), bc = '';
    recent.forEach(function (r, i) {
      var n = opLen(r.op), bytes = [r.op];
      for (var k = 1; k <= n; k++) bytes.push(M[(r.pl + k) & 0xFFFF]);
      var cur = i === recent.length - 1;
      bc += '<div class="bc' + (cur ? ' cur' : '') + '"><span class="a">' + h4(r.pl) + '</span>' +
        '<span class="b">' + bytes.map(h2).join(' ') + '</span><span class="n">' + esc(opName(r.op)) + '</span>' +
        '<span class="c">' + (r.end - r.start) + '</span></div>';
    });
    $('bytecode').innerHTML = '<div class="bc hd"><span class="a">addr</span><span class="b">bytes</span><span class="n">opcode</span><span class="c">1802 instr</span></div>' + bc;

    // B - the opcode
    var o = OPS[rec.op] || {}, trace = m.opTrace(rec) || [], cyc = 0;
    trace.forEach(function (pc) { cyc += COS.cycles(M, pc); });
    var us = cyc * 8 / Machine.CLOCK_HZ * 1e6;
    var n = opLen(rec.op), ob = [rec.op];
    for (var k = 1; k <= n; k++) ob.push(M[(rec.pl + k) & 0xFFFF]);
    $('opcard').innerHTML =
      '<div class="op-top"><span class="op-hex mono">$' + h2(rec.op) + '</span>' +
      '<span class="op-name">' + esc(o.name || 'unknown') + '</span>' +
      '<span class="op-grp mono">' + esc(o.operands || '') + '</span></div>' +
      '<p class="op-desc">' + esc(o.desc || '') + '</p>' +
      '<div class="op-stats">' +
        '<div><b>' + ob.map(h2).join(' ') + '</b><span>bytes at $' + h4(rec.pl) + '</span></div>' +
        '<div><b>' + trace.length + '</b><span>1802 instructions</span></div>' +
        '<div><b>' + cyc + '</b><span>machine cycles</span></div>' +
        '<div><b>' + (us >= 1000 ? (us / 1000).toFixed(2) + ' ms' : us.toFixed(0) + ' µs') + '</b><span>on a 3 MHz Elf2K</span></div>' +
      '</div>' +
      '<p class="op-foot">VM' + vm + ' · opcode #' + fmt(m.vmOps(vm)) + ' · <a href="opcodes.html#op-' + h2(rec.op) + '">reference</a></p>';

    // C - the 1802 code, grouped by phase
    var groups = [], cur = null;
    trace.forEach(function (pc) {
      var ph = phaseOf(pc);
      if (!cur || cur.ph !== ph) { cur = { ph: ph, pcs: [] }; groups.push(cur); }
      cur.pcs.push(pc);
    });
    var counts = { fetch: 0, handler: 0, scrt: 0, sched: 0 };
    groups.forEach(function (g) { counts[g.ph] += g.pcs.length; });
    var tot = trace.length || 1;
    $('phaseBar').innerHTML = ['fetch', 'handler', 'scrt', 'sched'].map(function (ph) {
      if (!counts[ph]) return '';
      return '<span class="pb ' + ph + '" style="flex-grow:' + counts[ph] + '" title="' + PHASES[ph][1] + '">' +
        PHASES[ph][0] + ' ' + counts[ph] + '</span>';
    }).join('');
    var LIMIT = 500, shown = 0, html = '';
    for (var gi = 0; gi < groups.length && shown < LIMIT; gi++) {
      var g = groups[gi];
      html += '<div class="ph-h ' + g.ph + '">' + PHASES[g.ph][0] + '<span>' + g.pcs.length + '</span></div>';
      for (var j = 0; j < g.pcs.length && shown < LIMIT; j++, shown++) {
        var pc = g.pcs[j], d = COS.decode(M, pc), bs = [];
        for (var q = 0; q < d.len; q++) bs.push(h2(M[(pc + q) & 0xFFFF]));
        html += '<div class="mi ' + g.ph + '"><span class="a">' + h4(pc) + '</span><span class="b">' + bs.join(' ') +
          '</span><span class="t">' + d.text + '</span></div>';
      }
    }
    if (trace.length > LIMIT) html += '<div class="more">… and ' + fmt(trace.length - LIMIT) + ' more. This one opcode ran ' +
      fmt(trace.length) + ' 1802 instructions.</div>';
    if (!trace.length) html = '<div class="more">Trace overwritten. Freeze, then step.</div>';
    var box = $('m1802'); box.innerHTML = html; box.scrollTop = 0;

    $('coreSub').textContent = 'VM' + vm + '\'s 256-byte core at $' + h4(Machine.coreBase(vm));
    renderCore();
  }

  function renderCore() {
    if (!texts.length) return;
    var base = Machine.coreBase(m.traceVM), M = m.M, wh = m.wheat;
    for (var i = 0; i < 256; i++) {
      var el = texts[i], v = h2(M[base + i]);
      if (el.textContent !== v) el.textContent = v;
      var hot = wh[base + i] > 40;
      if (hot !== (el._hot || false)) { el._hot = hot; el.classList.toggle('hot', hot); }
    }
  }

  function stepOne() {
    // start from a cold picture so what lights up is exactly this opcode's writes
    m.sampleWrites(); m.wheat.fill(0);
    var want = m.opCount + 1, guard = 0;
    while (m.opCount < want && guard++ < 400 && !m.halted) m.run(4000);
    m.sampleWrites();
    renderDescent(true);
    renderCidp();
    paintScreens();
    die.render();
    drawTimeline();
  }

  // ---------------------------------------------------------------- loop
  function paintScreens() {
    for (var v = 1; v <= 4; v++) {
      var b = m.drain(v);
      if (b) screens[v - 1].write(b);
      screens[v - 1].render();
    }
  }

  var lastT = 0, frame = 0, lastDescent = 0, consoleVisible = true, descentVisible = false;
  function tick(t) {
    requestAnimationFrame(tick);
    if (!m) return;
    // allow long frames (a busy or backgrounded tab) so the chosen speed holds; cap stops a runaway after sleep
    var dt = lastT ? Math.min(t - lastT, 500) : 16;
    lastT = t;
    if (speed >= 0 && !paused && !frozen && !m.halted) {
      var budget = speed ? dt / 1000 * Machine.CYCLES_PER_SEC * speed : Infinity;
      // ~11 ms of work per frame at 60 fps; a throttled tab gets few, long frames, so it may
      // spend proportionally more per frame (up to 60 ms) to keep the chosen speed
      m.run(budget, performance.now() + Math.min(Math.max(11, dt * 0.6), 60));
    }
    frame++;
    m.sampleWrites();
    // frozen: nothing is moving, so keep the last step's heat on screen instead of fading it
    if (consoleVisible && !frozen) {
      renderCidp();
      die.render();
      paintScreens();
      checkFinished();
      drawTimeline();
    } else if (!frozen) {
      // keep the serial buffers from growing while nobody is looking
      for (var v = 1; v <= 4; v++) { var b = m.drain(v); if (b) screens[v - 1].write(b); }
    }
    if (frame % 15 === 0) telemetry(t);
    if (descentVisible && !frozen && t - lastDescent > 350) { lastDescent = t; renderDescent(false); }
    else if (descentVisible) renderCore();
  }

  // ---------------------------------------------------------------- controls
  // speed < 0 is the single-step clock: the machine runs only when step is clicked
  function setSpeed(s) {
    speed = s;
    var bs = document.querySelectorAll('.speed button[data-speed]');
    for (var i = 0; i < bs.length; i++) bs[i].setAttribute('aria-checked', +bs[i].dataset.speed === s ? 'true' : 'false');
    var st = document.querySelectorAll('.clock-step');
    for (var j = 0; j < st.length; j++) st[j].classList.toggle('on', s < 0);
  }
  var stepMsg = 'single step';
  function clockStep() {
    if (speed >= 0) setSpeed(-1);
    var vm = m.stepOpcode();
    stepMsg = vm ? 'single step · VM' + vm + ' ran one opcode' : 'single step · nothing to run';
    $('tmSpeed').textContent = stepMsg;
  }
  // The clock row is repeated above the CIDP panel and above the 1802 machine-code
  // layer, so it can be changed without scrolling back to the top. The copies are
  // clones of the first row; setSpeed keeps every row's highlight in step.
  function cloneClocks() {
    var main = document.querySelector('.console-top .speed');
    var slots = document.querySelectorAll('[data-clock-copy]');
    for (var i = 0; i < slots.length; i++) slots[i].innerHTML = main.innerHTML;
  }
  function bindControls() {
    cloneClocks();
    var bs = document.querySelectorAll('.speed button[data-speed]');
    for (var i = 0; i < bs.length; i++) bs[i].addEventListener('click', function () { setSpeed(+this.dataset.speed); });
    setSpeed(speed);
    var st = document.querySelectorAll('.clock-step');
    for (var j = 0; j < st.length; j++) st[j].addEventListener('click', clockStep);
    $('pauseBtn').addEventListener('click', function () {
      paused = !paused;
      this.textContent = paused ? '▶ run' : '❚❚ pause';
    });
    $('resetBtn').addEventListener('click', function () { boot(); });
    $('freezeBtn').addEventListener('click', function () {
      frozen = !frozen;
      this.textContent = frozen ? '▶ thaw' : '❄ freeze';
      this.classList.toggle('on', frozen);
      $('descent').classList.toggle('frozen', frozen);
      renderDescent(true);
    });
    $('stepBtn').addEventListener('click', function () {
      if (!frozen) $('freezeBtn').click();
      stepOne();
    });
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (es) { es.forEach(function (e) { consoleVisible = e.isIntersecting; }); })
        .observe($('console'));
      new IntersectionObserver(function (es) {
        es.forEach(function (e) { descentVisible = e.isIntersecting; if (descentVisible) renderDescent(true); });
      }).observe($('descent'));
    }
  }

  // ---------------------------------------------------------------- facts
  function buildFacts() {
    var fw = window.STELLAR_FIRMWARE, bytes = 0;
    fw.segments.forEach(function (s) { if (s[0] < 0x2F00) bytes += atob(s[1]).length; });
    var live = (window.STELLAR_OPCODES || []).length;
    $('facts').innerHTML = [
      // the image stores only the non-zero runs, so this undercounts: round down
      [(Math.floor(bytes / 1000) * 1000).toLocaleString('en-US') + '+', 'bytes of hand-written 1802 code and tables in the firmware'],
      [live, 'opcodes in the STELLAR instruction set'],
      ['4', 'virtual machines, 4 KB of program each'],
      ['0', 'assemblers, compilers or linkers involved']
    ].map(function (f) { return '<div class="fact"><b>' + f[0] + '</b><span>' + f[1] + '</span></div>'; }).join('');
  }

  // ---------------------------------------------------------------- boot
  var sources = null;
  function boot() {
    m = new Machine({
      firmware: window.STELLAR_FIRMWARE,
      programs: LINEUP.map(function (p, i) { return { text: sources[i], input: p.input }; }),
      traceVM: m ? m.traceVM : 3
    });
    if (die) die.setMachine(m); else die = new Die($('die'), m);
    screens.forEach(function (s) { s.reset(); });
    for (var v = 1; v <= 4; v++) { prompted[v] = false; runLine[v] = ''; }
    lastInstr = 0; lastTelT = 0; lastCyc = 0; shownRec = null;
    markTabs();
  }

  function start() {
    buildQuad();
    buildDieLabels();
    buildCidp();
    buildCoreGrid();
    buildFacts();
    Promise.all(LINEUP.map(function (p) {
      return fetch('samples/' + p.file + V).then(function (r) {
        if (!r.ok) throw new Error(p.file + ': HTTP ' + r.status);
        return r.text();
      });
    })).then(function (txt) {
      sources = txt;
      boot();
      buildTabs();
      bindControls();
      requestAnimationFrame(tick);
    }).catch(function (e) {
      $('quad').innerHTML = '<p class="boot-err">Could not load the sample programs (' + esc(e.message) +
        '). The site has to be served over http, not opened from a file. See web/README-running.md.</p>';
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
