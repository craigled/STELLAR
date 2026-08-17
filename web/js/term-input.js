// Live typing into an emulated serial terminal.
//
// Keys are appended to the emulated 16C550's receive buffer. That buffer already
// reports "byte waiting" whenever it is non-empty, and SERIN yields when it is
// empty, so typed characters are picked up exactly as they would be at the real
// terminal — at any speed, including turbo. Programs echo their own input, as on
// hardware, so nothing is drawn locally.
//
// The CPU is fetched through a callback rather than captured once, because the
// page replaces its VM whenever a program is loaded or reset. Reaching the buffer
// via cpu.io_in[3] (rather than a StellarVM method) also means a cached copy of
// stellar-vm.js cannot break input.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.attachTerminalInput = api;
})(this, function () {
  'use strict';

  function keyToByte(e) {
    if (e.key === 'Enter') return 0x0D;
    if (e.key === 'Backspace') return 0x08;
    if (e.key === 'Escape') return 0x1B;
    if (e.ctrlKey && /^[a-zA-Z]$/.test(e.key)) {
      return e.key.toUpperCase().charCodeAt(0) - 64;   // ^A..^Z -> $01..$1A
    }
    if (!e.ctrlKey && e.key.length === 1) return e.key.charCodeAt(0) & 0xFF;
    return null;
  }

  return function attachTerminalInput(termEl, getCpu) {
    if (!termEl) return;
    if (!termEl.hasAttribute('tabindex')) termEl.setAttribute('tabindex', '0');
    termEl.addEventListener('keydown', function (e) {
      var cpu = getCpu();
      var uart = cpu && cpu.io_in && cpu.io_in[3];
      if (!uart || !uart.buf) return;
      // leave browser shortcuts and focus movement alone
      if (e.altKey || e.metaKey || e.key === 'Tab') return;
      var code = keyToByte(e);
      if (code === null) return;
      e.preventDefault();
      uart.buf.push(code);
    });
  };
});
