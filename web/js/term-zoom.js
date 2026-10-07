// Enlarge a serial terminal to fill the window (computers only - the button is hidden
// on phones and tablets by CSS).
//
// The terminal element itself is lifted into an overlay - not copied - so the program
// keeps running into it and its key handlers keep working: games play at full size.
// js/vt100.js sees the .tz-lifted class and fits the font to the overlay's width AND
// height instead of the page's column. A placeholder holds the terminal's place on the
// page so nothing jumps.
//
// Esc is NOT used to close it: Esc belongs to the program (Snake, Breakout and the
// others quit on it). The x button or a click outside the terminal closes the view.
(function () {
  'use strict';

  function refit() {                          // vt100.js refits on resize
    try { window.dispatchEvent(new Event('resize')); } catch (e) {}
  }

  // lift: the element moved into the overlay; host: where the button goes;
  // focusEl: what gets the keyboard afterwards.
  function attach(lift, host, focusEl) {
    if (!lift || !host || lift._tzAttached) return;
    lift._tzAttached = true;
    focusEl = focusEl || lift;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'tz-btn';
    btn.textContent = '⤢ Enlarge';
    btn.title = 'Enlarge this terminal to fill the window';
    btn.setAttribute('aria-label', 'Enlarge this terminal');
    host.appendChild(btn);

    var overlay = null, holder = null, hostParent = null;
    function open() {
      if (overlay) return;
      holder = document.createElement('div');
      holder.className = 'tz-holder';
      holder.style.height = lift.offsetHeight + 'px';
      lift.parentNode.insertBefore(holder, lift);
      overlay = document.createElement('div');
      overlay.className = 'tz-overlay';
      overlay.setAttribute('role', 'dialog');
      overlay.setAttribute('aria-modal', 'true');
      overlay.setAttribute('aria-label', 'Terminal, enlarged');
      var close = document.createElement('button');
      close.type = 'button';
      close.className = 'tz-close';
      close.textContent = '×';
      close.title = 'Back to the page (Esc goes to the program)';
      close.setAttribute('aria-label', 'Close the enlarged terminal');
      var panel = document.createElement('div');
      panel.className = 'tz-panel';
      if (overlay.requestFullscreen) {
        var fs = document.createElement('button');
        fs.type = 'button';
        fs.className = 'tz-full';
        fs.textContent = '⛶';
        fs.title = 'Full screen (Esc or this button leaves it)';
        fs.setAttribute('aria-label', 'Full screen');
        fs.addEventListener('click', function () {
          if (document.fullscreenElement) document.exitFullscreen();
          else overlay.requestFullscreen().then(refit, function () {});
          setTimeout(function () { focusEl.focus({ preventScroll: true }); }, 0);
        });
        overlay.appendChild(fs);
      }
      overlay.appendChild(close);
      overlay.appendChild(panel);
      panel.appendChild(lift);
      lift.classList.add('tz-lifted');
      document.body.appendChild(overlay);
      document.body.style.overflow = 'hidden';
      close.addEventListener('click', shut);
      overlay.addEventListener('mousedown', function (e) { if (e.target === overlay) shut(); });
      // a click anywhere on the lifted terminal hands it the keyboard
      panel.addEventListener('mousedown', function () { setTimeout(function () { focusEl.focus({ preventScroll: true }); }, 0); });
      refit();
      focusEl.focus({ preventScroll: true });
    }
    function shut() {
      if (!overlay) return;
      if (document.fullscreenElement === overlay) document.exitFullscreen();
      lift.classList.remove('tz-lifted');
      holder.parentNode.replaceChild(lift, holder);
      overlay.parentNode.removeChild(overlay);
      overlay = holder = null;
      document.body.style.overflow = '';
      refit();
      focusEl.focus({ preventScroll: true });
    }
    btn.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); open(); });
    lift._tz = { open: open, close: shut, button: btn };
    return lift._tz;
  }

  // Every page terminal (.term) gets a button in its heading (.term-wrap h4) - not inside
  // the terminal: vt100.js rewrites the terminal's contents on every frame.
  function auto() {
    var terms = document.querySelectorAll('.term');
    for (var i = 0; i < terms.length; i++) {
      var t = terms[i], wrap = t.parentNode;
      var h = wrap && wrap.querySelector('h4');
      if (h) attach(t, h, t);
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', auto);
  else auto();

  window.TermZoom = { attach: attach };
})();
