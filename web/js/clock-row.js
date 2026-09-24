// The clock row shared by the Simulator and Multitasking pages: one button per
// speed, like the home page's clock.
//
// The first two are teaching speeds counted in STELLAR opcodes (or scheduler
// slices), so a single step can be followed on screen. The rest are REAL TIME,
// paced by 1802 instructions per wall-clock second: Craig's 3 MHz Elf2K runs
// 375,000 machine cycles a second at about 2.2 cycles an instruction, which is
// ~170,000 instructions - roughly a thousand STELLAR opcodes a second.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.ClockRow = api;
})(this, function () {
  'use strict';

  var ELF2K = 170000;
  var SPEEDS = [
    { label: '1 op/s',   ops: 1, ms: 1000, title: 'One STELLAR opcode a second - follow every step' },
    { label: '10 op/s',  ops: 1, ms: 100,  title: 'Ten STELLAR opcodes a second' },
    { label: 'Elf2K',    ms: 16, ips: ELF2K,      title: 'Real time: the speed of a 3 MHz Elf2K' },
    { label: '2×',       ms: 16, ips: ELF2K * 2,  title: 'Twice the Elf2K' },
    { label: '5×',       ms: 16, ips: ELF2K * 5,  title: 'Five times the Elf2K' },
    { label: '10×',      ms: 16, ips: ELF2K * 10, title: 'Ten times the Elf2K' },
    { label: 'flat out', ops: 200, ms: 0,         title: 'As fast as this browser can go' }
  ];
  var ALIAS = { turbo: 'flat out', 'Elf2K 1×': 'Elf2K' };   // older manifest names

  function describe(sp) {
    return sp.ips ? '≈ ' + Math.round(sp.ips / 1000) + 'k 1802 instructions a second'
      : sp.ms ? sp.label + ', to watch it step' : 'no pacing';
  }

  // Build the buttons into `host`; `onChange(speed)` gets the chosen entry.
  // Returns { set(labelOrIndex), current() }.
  function ClockRow(host, labelEl, onChange, initial) {
    var idx = -1;
    SPEEDS.forEach(function (sp, i) {
      var b = document.createElement('button');
      b.type = 'button'; b.textContent = sp.label; b.title = sp.title;
      b.setAttribute('role', 'radio');
      b.addEventListener('click', function () { set(i); });
      host.appendChild(b);
    });
    function set(which) {
      var i = typeof which === 'number' ? which
        : SPEEDS.map(function (s) { return s.label; }).indexOf(ALIAS[which] || which);
      if (i < 0 || i >= SPEEDS.length) return false;
      idx = i;
      [].forEach.call(host.children, function (b, k) { b.setAttribute('aria-checked', k === i ? 'true' : 'false'); });
      if (labelEl) labelEl.textContent = describe(SPEEDS[i]);
      onChange(SPEEDS[i]);
      return true;
    }
    set(initial === undefined ? 'Elf2K' : initial);
    return { set: set, current: function () { return SPEEDS[idx]; } };
  }
  ClockRow.SPEEDS = SPEEDS;
  ClockRow.ELF2K = ELF2K;
  return ClockRow;
});
