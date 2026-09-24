// Scheduler view: boots 2–4 real VMs and renders the CIDP page, the per-core
// state, and the cooperative round-robin hand-off.
(function () {
  var SCENARIOS = [
    { name: '3 tickers — round-robin', blurb: 'Each VM prints its own digit in a loop. The interleaved output (1 2 3 1 2 3 …) is the scheduler cycling the CPU between VMs.',
      programs: ['sched-tick1.lst', 'sched-tick2.lst', 'sched-tick3.lst'] },
    { name: '2 tickers', blurb: 'Two VMs alternating on the single 1802.',
      programs: ['sched-tick1.lst', 'sched-tick2.lst'] },
    { name: '4 tickers — all cores', blurb: 'All four VMs active — the CPU cycles 1→2→3→4.',
      programs: ['sched-tick1.lst', 'sched-tick2.lst', 'sched-tick3.lst', 'sched-tick4.lst'] },
    { name: '3 counters (CVT2DEC + OUTDEC)', blurb: 'Each VM counts by a different step and prints via CVT2DEC + OUTDEC — watch the registers change per core.',
      programs: ['sched-count1.lst', 'sched-count2.lst', 'sched-count3.lst'] },
    { name: 'Typing — one VM waits, the other runs', blurb: 'Click the shared terminal and type. VM1 prints a dot 48 times; VM2 sits in SERIN waiting for a key and echoes the 4 characters you type. Because SERIN yields to the scheduler instead of blocking, the dots keep coming while VM2 waits — your characters appear inline wherever you typed them.',
      programs: ['sched-echo-tick.lst', 'sched-echo-read.lst'] },
    { name: 'Front panel — two VMs, one latch', blurb: 'Nothing goes to the terminal here — watch the front panel. VM1 holds Q on and writes $11 to the output latch; VM2 holds Q off and writes $22. There is only one Q line and one latch for the whole machine, so the display flips 11/22 and the Q lamp blinks as the scheduler hands the CPU between them.',
      programs: ['sched-panel1.lst', 'sched-panel2.lst'] }
  ];
  var SPEEDS = [
    { label: '1×', slices: 1, ms: 320 },
    { label: '4×', slices: 1, ms: 90 },
    { label: '16×', slices: 4, ms: 40 },
    { label: 'turbo', slices: 120, ms: 0 }
  ];
  var STATE = { 0x00: 'done', 0x01: 'active', 0x02: 'cycle', 0x03: 'idle', 0x04: 'paused', 0x05: 'killed', 0x06: 'error', 0x0F: 'unknown' };
  function byId(id) { return document.getElementById(id); }
  var panel = new window.FrontPanel(byId('frontpanel'));
  // Live typing into the shared terminal. One UART for the whole machine, so a
  // keystroke goes to whichever VM reads it first — the input side of the same
  // sharing the output already shows.
  window.attachTerminalInput(byId('term'), function () { return mv && mv.cpu; });
  function hx(v, n) { return v.toString(16).toUpperCase().padStart(n, '0'); }
  function opName(op) {
    var t = window.STELLAR_OPCODES || [];
    for (var i = 0; i < t.length; i++) if (t[i].op === op) return t[i].name;
    return '';
  }

  var mv = null, running = false, timer = null, opsPerTick = 1, tickMs = 320;
  var serialLen = 0, prevRegs = {}, built = 0, vt = null;
  var expandedVM = null, coreView = null;

  function loadScenario(i) {
    var s = SCENARIOS[i];
    byId('blurb').textContent = s.blurb;
    byId('status').textContent = 'loading ' + s.name + '…';
    Promise.all(s.programs.map(function (f) {
      return fetch('samples/' + f + '?v=36').then(function (r) { return r.text(); });
    })).then(function (texts) {
      mv = new window.StellarMultiVM({ firmware: window.STELLAR_FIRMWARE, programs: texts });
      mv.bootUntilReady();      // run CREATE_CIDP + scheduler so VMs are active
      stop(); serialLen = 0; prevRegs = {}; built = 0; expandedVM = null;
      if (vt) vt.reset(); else byId('term').textContent = '';
      byId('cores').innerHTML = '';
      render();
      byId('status').textContent = 'ready — ' + mv.cidp().totalVMs + ' VMs booted';
    }).catch(function (e) { byId('status').textContent = 'load failed: ' + e; });
  }

  function stateBadge(st) {
    return '<span class="st s' + hx(st, 2) + '">' + (STATE[st] || ('$' + hx(st, 2))) + '</span>';
  }

  // Decoders for the CIDP system bytes, per STELLAR COMMANDS v0061.23.
  var SYSINT = { 0x00: 'Single', 0x01: 'Hardware Int', 0x02: 'Counter Int', 0x03: 'Dual', 0x0E: 'Error' };
  var VMERR = { 0x00: 'None', 0x01: 'No VMs', 0x02: 'Abort', 0x0F: 'Unknown' };
  var STATUS = { 0x00: 'busy', 0x01: 'ready', 0x02: 'error' };
  function statusBadge(st) {
    return '<span class="st st-' + (STATUS[st] || 'unk') + '">' + (STATUS[st] || ('$' + hx(st, 2))) + '</span>';
  }
  function dec(map, v) { return map[v] !== undefined ? map[v] : '?'; }

  // The nine machine-wide bytes at $2F50-$2F5F, shown with their addresses so the
  // panel doubles as a map of the interchange page.
  function renderSys(cd) {
    var items = [
      ['System Interrupt State', 0x2F50, cd.sysIntState, dec(SYSINT, cd.sysIntState)],
      ['VM Error Register',      0x2F51, cd.vmError,     dec(VMERR, cd.vmError)],
      ['Current VM Number',      0x2F52, cd.currentVM,   cd.currentVM ? 'VM' + cd.currentVM : 'none'],
      ['MAX VMs',                0x2F53, cd.maxVMs,      String(cd.maxVMs)],
      ['Total VMs Present',      0x2F54, cd.totalVMs,    String(cd.totalVMs)],
      ['Multitasking Allowed',   0x2F55, cd.multitasking, cd.multitasking ? 'Yes' : 'No'],
      // spec: 00 = Simultaneous, 01 = Sequential
      ['VM Operation',           0x2F56, cd.operation,   cd.operation ? 'Sequential' : 'Simultaneous'],
      ['VM Repeat',              0x2F57, cd.repeat,      cd.repeat ? 'Repeat at End' : 'Continuous to End'],
      ['Hardware Interrupt FF',  0x2F5F, cd.hwIntFF,     cd.hwIntFF ? 'set' : 'clear']
    ];
    byId('sysreg').innerHTML = items.map(function (it) {
      return '<div class="sr-cell">' +
        '<span class="sr-lab">' + it[0] + '</span>' +
        '<span class="sr-addr mono">$' + hx(it[1], 4) + '</span>' +
        '<span class="sr-val mono">$' + hx(it[2], 2) + '</span>' +
        '<span class="sr-dec">' + it[3] + '</span>' +
        '</div>';
    }).join('');
  }

  function renderCIDP(cd) {
    var rows = '';
    cd.vms.forEach(function (v, i) {
      if (v.num === 0 || v.num > cd.totalVMs) return;
      var active = cd.currentVM === v.num;
      var base = 0x2F00 + (v.num - 1) * 0x10;
      rows += '<tr class="' + (active ? 'vm-active' : '') + '">' +
        '<td class="mono">VM' + v.num + (active ? ' ◀ CPU' : '') + '</td>' +
        '<td>' + stateBadge(v.state) +
          '<span class="cidp-raw mono">$' + hx(v.state, 2) + ' @$' + hx(base + 0x05, 4) + '</span></td>' +
        '<td>' + statusBadge(v.status) +
          '<span class="cidp-raw mono">$' + hx(v.status, 2) + ' @$' + hx(base + 0x0B, 4) + '</span></td>' +
        '<td class="mono">$' + hx(v.corePage, 2) + '00</td>' +
        '<td class="mono">$' + hx(v.progPage, 2) + '00</td>' +
        '<td class="mono">' + v.cmds.toLocaleString() + '</td>' +
        '<td class="mono">' + (v.mode === 2 ? 'RW' : v.mode === 1 ? 'RO' : '—') + '</td>' +
        '</tr>';
    });
    byId('cidp').innerHTML =
      '<div class="cidp-tblwrap"><table><thead><tr>' +
      '<th>VM</th><th>State</th><th>Status</th><th>Core</th><th>Prog</th><th>#Cmds</th><th>Access</th>' +
      '</tr></thead><tbody>' + rows + '</tbody></table></div>';
  }

  function renderCores(cd) {
    var host = byId('cores');
    var vms = cd.vms.filter(function (v) { return v.num !== 0 && v.num <= cd.totalVMs; });
    if (built !== vms.length) { host.innerHTML = ''; built = vms.length; }
    vms.forEach(function (v) {
      var s = mv.snapshotVM(v.num);
      var id = 'mini' + v.num;
      var el = document.getElementById(id);
      var active = cd.currentVM === v.num;
      var q = s.intMax ? Math.round(100 * s.intCounter / s.intMax) : 0;
      if (!el) {
        el = document.createElement('div');
        el.id = id; el.className = 'mini';
        host.appendChild(el);
      }
      el.classList.toggle('active', active);
      el.classList.toggle('expanded', expandedVM === v.num);
      var prev = prevRegs[v.num] || [];
      var regsHtml = '';
      for (var r = 0; r < 16; r++) {
        var chg = prev[r] !== undefined && prev[r] !== s.regs[r];
        regsHtml += '<span class="rc' + (chg ? ' chg' : '') + '"><span class="l">R' +
          r.toString(16).toUpperCase() + '</span> ' + hx(s.regs[r], 4) + '</span>';
      }
      prevRegs[v.num] = s.regs.slice();
      el.innerHTML =
        '<div class="mini-head"><span class="vmname">VM' + v.num + '</span>' +
        stateBadge(v.state) +
        '<button class="mini-expand" data-vm="' + v.num + '" title="Expand full core">⤢</button>' +
        '<span class="cpu-badge' + (active ? '' : ' idle') + '">' + (active ? 'RUNNING' : 'waiting') + '</span></div>' +
        '<div class="mini-body">' +
        '<div class="mini-op">$' + hx(s.cmd, 2) + ' ' + (opName(s.cmd) || '') + '</div>' +
        '<div class="mini-pl">PL $' + hx(s.pl, 4) + ' · cmd# ' + s.cmdCounter + '</div>' +
        '<div class="mini-pl">1802 ops: <b style="color:var(--accent)">' + s.steps.toLocaleString() + '</b></div>' +
        '<div class="mini-quantum"><span class="qlab">quantum ' + s.intCounter + ' / ' + s.intMax + '</span>' +
        '<span class="qbar"><i style="width:' + q + '%"></i></span></div>' +
        '<div class="mini-regs">' + regsHtml + '</div>' +
        '</div>';
    });
  }

  function appendSerial() {
    var out = mv.cpu.io_out[3] || [];
    if (out.length > serialLen) {
      var t = byId('term');
      if (!vt && window.VT100) vt = window.VT100(t);
      if (vt) { vt.write(out.slice(serialLen)); vt.render(); }
      else {
        var s = '';
        for (var i = serialLen; i < out.length; i++) { var b = out[i]; s += (b === 13) ? '' : String.fromCharCode(b); }
        t.textContent += s; t.scrollTop = t.scrollHeight;
      }
      serialLen = out.length;
    }
  }

  function updateDetail(cd) {
    var dp = byId('vmdetail');
    if (!expandedVM || !mv || expandedVM > cd.totalVMs) { dp.hidden = true; return; }
    dp.hidden = false;
    if (!coreView) coreView = new window.CoreView(byId('vd-core'));
    var active = cd.currentVM === expandedVM;
    byId('vd-title').textContent = 'VM' + expandedVM + ' — full core ($' +
      (0x3000 + (expandedVM - 1) * 0x400).toString(16).toUpperCase() + ')';
    var badge = byId('vd-badge');
    badge.textContent = active ? 'RUNNING' : 'waiting';
    badge.classList.toggle('idle', !active);
    coreView.render(mv.snapshotVM(expandedVM));
  }

  // The front panel is machine-wide, not per-VM: one 1802 means one Q line and
  // one output latch, so whichever VM drove them last is what shows — the same
  // sharing the serial terminal has. The port number is per-VM though (each core
  // has its own DEFOUT byte at +$39), so it is read from the VM holding the CPU.
  function panelState() {
    var cpu = mv.cpu, vm = mv.currentVM();
    var base = mv.coreBase(vm >= 1 && vm <= 4 ? vm : 1);
    var port = cpu.M[base + 0x39] || 4;
    var log = cpu.io_out[port];
    return {
      q: cpu.Q ? 1 : 0,
      outPort: port,
      outByte: (log && log.length) ? log[log.length - 1] : null
    };
  }

  function render() {
    if (!mv) return;
    var cd = mv.cidp();
    renderCIDP(cd);
    renderSys(cd);
    renderCores(cd);
    updateDetail(cd);
    appendSerial();
    panel.render(panelState());
    var anyActive = cd.vms.some(function (v) { return v.state === 0x01; });
    byId('run').disabled = running || !anyActive;
    byId('step').disabled = running || !anyActive;
    byId('pause').disabled = !running;
    return anyActive;
  }

  function step() {
    if (!mv) return;
    var r = mv.stepSlice();
    var active = render();
    if (r.halted || !active) { stop(); byId('status').textContent = 'all VMs done'; }
  }
  function run() {
    if (running || !mv) return;
    running = true; byId('status').textContent = 'running…';
    timer = setInterval(function () {
      for (var i = 0; i < opsPerTick; i++) {
        var r = mv.stepSlice();
        if (r.halted) { render(); stop(); byId('status').textContent = 'all VMs done'; return; }
      }
      var active = render();
      if (!active) { stop(); byId('status').textContent = 'all VMs done'; }
    }, tickMs);
  }
  function stop() { running = false; if (timer) { clearInterval(timer); timer = null; } render(); }

  // wire up
  var sel = byId('scenario');
  SCENARIOS.forEach(function (s, i) {
    var o = document.createElement('option'); o.value = i; o.textContent = s.name; sel.appendChild(o);
  });
  sel.addEventListener('change', function () { loadScenario(+this.value); });
  // expand a VM into the full core view (event-delegated; mini panels re-render)
  byId('cores').addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.mini-expand');
    if (!btn) return;
    var vm = +btn.dataset.vm;
    if (expandedVM === vm) { expandedVM = null; }
    else { expandedVM = vm; if (coreView) coreView.reset(); }
    render();
    if (expandedVM) byId('vmdetail').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  });
  byId('vd-close').addEventListener('click', function () { expandedVM = null; render(); });
  byId('step').addEventListener('click', step);
  byId('run').addEventListener('click', run);
  byId('pause').addEventListener('click', function () { stop(); byId('status').textContent = 'paused'; });
  byId('reset').addEventListener('click', function () { if (mv) { mv.reset(); mv.bootUntilReady(); serialLen = 0; prevRegs = {}; built = 0; if (vt) vt.reset(); else byId('term').textContent = ''; byId('cores').innerHTML = ''; render(); byId('status').textContent = 'reset'; } });
  var speed = byId('speed');
  function applySpeed() { var s = SPEEDS[+speed.value]; byId('speedLabel').textContent = s.label; opsPerTick = s.slices; tickMs = s.ms; if (running) { stop(); run(); } }
  speed.addEventListener('input', applySpeed);
  applySpeed();
  loadScenario(0);
})();
