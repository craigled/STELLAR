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

  // Arrow keys arrive as a three-byte escape sequence, the same as a real VT100
  // sends. Invaders steers its gun with them, so without this the game cannot be
  // played in the browser at all.
  var ARROWS = { ArrowUp: 0x41, ArrowDown: 0x42, ArrowRight: 0x43, ArrowLeft: 0x44 };

  var SEQS = { Home: [0x1B, 0x5B, 0x48], End: [0x1B, 0x5B, 0x46], PageUp: [0x1B, 0x5B, 0x35, 0x7E],
              PageDown: [0x1B, 0x5B, 0x36, 0x7E], Delete: [0x1B, 0x5B, 0x33, 0x7E] };

  // The bytes a named key sends, or null. Arrow keys and Home/End/PgUp/PgDn/Delete
  // go as the escape sequences a VT100/VT220 sends (Invaders and Lite-Writer use them).
  function keyBytes(e) {
    if (ARROWS[e.key] !== undefined) return [0x1B, 0x5B, ARROWS[e.key]];
    if (SEQS[e.key]) return SEQS[e.key];
    var code = keyToByte(e);
    return code === null ? null : [code];
  }

  return function attachTerminalInput(termEl, getCpu) {
    if (!termEl) return;
    if (!termEl.hasAttribute('tabindex')) termEl.setAttribute('tabindex', '0');

    function send(bytes) {
      var cpu = getCpu();
      var uart = cpu && cpu.io_in && cpu.io_in[3];
      if (!uart || !uart.buf) return false;
      for (var i = 0; i < bytes.length; i++) uart.buf.push(bytes[i]);
      return true;
    }

    termEl.addEventListener('keydown', function (e) {
      // leave browser shortcuts and focus movement alone
      if (e.altKey || e.metaKey || e.key === 'Tab') return;
      var b = keyBytes(e);
      if (b && send(b)) e.preventDefault();
    });

    // ---- phones and tablets ----
    // A touch screen only offers its keyboard for a real text field, and the terminal
    // is a <div>. So on a touch device a hidden textarea sits with the terminal:
    // tapping the terminal focuses it, the keyboard comes up, and what is typed is
    // sent on. Soft keyboards often report every key as "Unidentified" (keyCode 229),
    // so text is read from the textarea itself: it always holds two spaces, and
    // anything beyond them is typed text, anything short of them is Backspace. A row
    // of keys a phone keyboard lacks - the arrows, Esc, Enter - goes underneath.
    if (!(window.matchMedia && window.matchMedia('(pointer: coarse)').matches)) return;

    var SENT = '  ';
    var bar = document.createElement('div');
    bar.className = 'term-keys';
    var ta = document.createElement('textarea');
    ta.className = 'term-kbd';
    ta.setAttribute('aria-label', 'Type to the terminal');
    ['autocapitalize', 'autocorrect', 'autocomplete'].forEach(function (k) { ta.setAttribute(k, 'off'); });
    ta.spellcheck = false;
    ta.value = SENT;
    bar.appendChild(ta);

    function reset() { ta.value = SENT; ta.setSelectionRange(SENT.length, SENT.length); }
    function openKeyboard() { ta.focus({ preventScroll: true }); reset(); fitTerminal = true; place(); }
    function takeText() {
      var v = ta.value;
      if (v.length < SENT.length) {
        var bs = []; for (var i = v.length; i < SENT.length; i++) bs.push(0x08);
        send(bs);
      } else {
        var t = v.slice(SENT.length), out = [];
        for (var k = 0; k < t.length; k++) {
          var c = t.charCodeAt(k);
          out.push(c === 10 ? 0x0D : c & 0xFF);             // the keyboard's return is CR
        }
        if (out.length) send(out);
      }
      reset();
    }
    ta.addEventListener('input', function (e) { if (!e.isComposing) takeText(); });
    ta.addEventListener('compositionend', takeText);
    ta.addEventListener('keydown', function (e) {
      if (e.isComposing || e.keyCode === 229 || e.altKey || e.metaKey || e.key === 'Tab') return;
      // named keys from a Bluetooth keyboard: send them here; printable keys come
      // through the input event instead, so nothing is sent twice
      if (e.key.length === 1 && !e.ctrlKey) return;
      var b = keyBytes(e);
      if (b && send(b)) e.preventDefault();
    });
    ta.addEventListener('focus', function () { termEl.classList.add('term-typing'); fitTerminal = true; place(); });
    ta.addEventListener('blur', function () { termEl.classList.remove('term-typing'); place(); });
    termEl.addEventListener('click', openKeyboard);

    [['\u2328', null, 'Show the keyboard'], ['\u2190', 'ArrowLeft'], ['\u2191', 'ArrowUp'],
     ['\u2193', 'ArrowDown'], ['\u2192', 'ArrowRight'], ['Esc', 'Escape'], ['Enter', 'Enter']]
      .forEach(function (k) {
        var btn = document.createElement('button');
        btn.type = 'button'; btn.textContent = k[0];
        btn.setAttribute('aria-label', k[2] || k[1]);
        // pointerdown + preventDefault: the tap must not take focus from the textarea,
        // or the keyboard would close every time an arrow is pressed
        btn.addEventListener('pointerdown', function (e) {
          e.preventDefault();
          if (!k[1]) { openKeyboard(); return; }
          send(keyBytes({ key: k[1] }));
        });
        btn.addEventListener('click', function (e) { e.preventDefault(); });
        bar.appendChild(btn);
      });
    // The row sits in a slot under the terminal. While the keyboard is up it would be
    // hidden behind it, so it floats instead: pinned to the bottom of the VISUAL
    // viewport (the part of the page the keyboard leaves showing), with the slot
    // keeping its place so the page does not jump. When the keyboard first opens the
    // page scrolls so the terminal ends just above the row.
    var slot = document.createElement('div');
    slot.className = 'term-keys-slot';
    slot.appendChild(bar);
    termEl.insertAdjacentElement('afterend', slot);
    var fitTerminal = false;
    function place() {
      var vv = window.visualViewport;
      if (document.activeElement !== ta || !vv) {
        bar.classList.remove('term-keys-float');
        bar.style.top = bar.style.left = bar.style.width = '';
        slot.style.height = '';
        return;
      }
      if (!bar.classList.contains('term-keys-float')) {
        slot.style.height = slot.offsetHeight + 'px';
        bar.classList.add('term-keys-float');
      }
      var h = bar.offsetHeight;
      bar.style.left = vv.offsetLeft + 'px';
      bar.style.width = vv.width + 'px';
      bar.style.top = (vv.offsetTop + vv.height - h) + 'px';
      if (fitTerminal && vv.height < window.innerHeight * 0.85) {   // the keyboard is up now
        fitTerminal = false;
        var r = termEl.getBoundingClientRect();
        var room = vv.height - h - 8;                                 // visible height above the row
        var want = r.height <= room ? r.bottom - vv.offsetTop - room  // terminal's bottom at the row
                                    : r.top - vv.offsetTop - 8;       // too tall: show its top
        if (Math.abs(want) > 4) window.scrollBy(0, want);
      }
    }
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', place);
      window.visualViewport.addEventListener('scroll', place);
    }
    window.addEventListener('scroll', place, { passive: true });
  };
});
