// A small VT100 for the serial terminal.
//
// STELLAR's full-screen programs — Starfield, Bouncing-Ball, Invaders, Starship,
// Game of Life — drive the terminal with escape sequences. Appending the bytes to
// a <div> shows the escapes as literal rubbish, so those programs could not be run
// in the browser at all. This keeps a real 24x80 screen with a cursor, and renders
// it after each batch of output.
//
// It is a deliberate subset: exactly the sequences STELLAR programs emit (plus the
// VT102 insert/delete character pair Starship v02 uses, and the VT100 scrolling
// region - DECSTBM "ESC [ t ; b r" and reverse index "ESC M" - that the car racer
// scrolls its road with), which is
// the same set the Python screen-replay harness parses (scratchpad/starrun.py) and
// which was checked frame by frame against five programs there.
//
// Teletype programs are unaffected. Text with CR/LF scrolls the screen the way it
// always did, and lines pushed off the top are kept in a scrollback above the live
// screen so nothing that used to be readable is lost.
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.VT100 = api;
})(this, function () {
  'use strict';

  var COLS = 80, ROWS = 24, SCROLLBACK = 400;

  function blankRow() {
    var r = new Array(COLS);
    for (var i = 0; i < COLS; i++) r[i] = { ch: ' ', rev: false };
    return r;
  }

  function VT100(el, opts) {
    opts = opts || {};
    this.el = el;
    this.cols = opts.cols || COLS;
    this.rows = opts.rows || ROWS;
    this.reset();
  }

  VT100.prototype.reset = function () {
    this.grid = [];
    for (var r = 0; r < this.rows; r++) this.grid.push(blankRow());
    this.scroll = [];          // lines that have scrolled off the top
    this.cx = 0; this.cy = 0;  // zero-based
    this.top = 0; this.bot = this.rows - 1;   // the scrolling region (DECSTBM)
    this.rev = false;
    this.curVis = true;
    this.pending = '';         // a partial escape sequence split across batches
    this.dirty = true;
    if (this.el) this.el.textContent = '';
  };

  VT100.prototype._scrollUp = function () {
    var gone = this.grid.shift();
    var s = '';
    for (var i = 0; i < gone.length; i++) s += gone[i].ch;
    this.scroll.push(s.replace(/\s+$/, ''));
    if (this.scroll.length > SCROLLBACK) this.scroll.shift();
    this.grid.push(blankRow());
  };

  VT100.prototype._nl = function () {
    if (this.cy === this.bot) {
      // at the bottom margin: scroll the region up. A full-screen region keeps
      // the scrollback, as before; a partial one just loses its top line.
      if (this.top === 0 && this.bot === this.rows - 1) this._scrollUp();
      else { this.grid.splice(this.top, 1); this.grid.splice(this.bot, 0, blankRow()); }
    } else if (this.cy < this.rows - 1) this.cy++;
  };

  // ESC M - reverse index: up a line, or at the top margin scroll the region DOWN
  VT100.prototype._ri = function () {
    if (this.cy === this.top) { this.grid.splice(this.bot, 1); this.grid.splice(this.top, 0, blankRow()); }
    else if (this.cy > 0) this.cy--;
  };

  VT100.prototype._put = function (ch) {
    if (this.cx >= this.cols) { this.cx = 0; this._nl(); }
    var cell = this.grid[this.cy][this.cx];
    cell.ch = ch; cell.rev = this.rev;
    this.cx++;
  };

  VT100.prototype._erase = function (mode) {
    var r, c;
    if (mode === 2) {
      for (r = 0; r < this.rows; r++) this.grid[r] = blankRow();
      return;
    }
    // 0 = cursor to end of screen, 1 = start of screen to cursor
    var from = (mode === 1) ? 0 : this.cy * this.cols + this.cx;
    var to   = (mode === 1) ? this.cy * this.cols + this.cx : this.rows * this.cols - 1;
    for (var i = from; i <= to; i++) {
      r = Math.floor(i / this.cols); c = i % this.cols;
      this.grid[r][c] = { ch: ' ', rev: false };
    }
  };

  VT100.prototype._eraseLine = function (mode) {
    var from = (mode === 1) ? 0 : this.cx;
    var to   = (mode === 1) ? this.cx : this.cols - 1;
    for (var c = from; c <= to && c < this.cols; c++) this.grid[this.cy][c] = { ch: ' ', rev: false };
  };

  // Returns the number of characters consumed, or -1 if the sequence is
  // incomplete and should be held over until more bytes arrive.
  VT100.prototype._esc = function (s, i) {
    if (i + 1 >= s.length) return -1;
    var c1 = s.charAt(i + 1);
    if (c1 === 'M') { this._ri(); return 2; }    // reverse index
    if (c1 === 'D') { this._nl(); return 2; }    // index
    if (c1 !== '[') { return 2; }                 // other ESC x - not used by STELLAR, drop
    var j = i + 2, priv = '';
    if (j < s.length && s.charAt(j) === '?') { priv = '?'; j++; }
    var num = '';
    while (j < s.length && /[0-9;]/.test(s.charAt(j))) { num += s.charAt(j); j++; }
    // Intermediate bytes ($20-$2F) sit between the parameters and the final letter.
    // DECSCUSR - set cursor style - is "ESC [ 2 SP q", and Bouncing-Ball v01 emits
    // it. Without skipping the space the 'q' fell through and was PRINTED, leaving
    // a stray q on the screen.
    while (j < s.length && s.charCodeAt(j) >= 0x20 && s.charCodeAt(j) <= 0x2F) j++;
    if (j >= s.length) return -1;                 // still waiting for the final letter
    var fin = s.charAt(j);
    var parts = num.length ? num.split(';') : [];
    var p0 = parts.length ? parseInt(parts[0], 10) : 0;
    var p1 = parts.length > 1 ? parseInt(parts[1], 10) : 0;

    if (priv === '?' && (fin === 'l' || fin === 'h')) {
      if (p0 === 25) this.curVis = (fin === 'h');   // hide / show the cursor
    } else if (fin === 'H' || fin === 'f') {
      this.cy = Math.min(this.rows - 1, Math.max(0, (parts.length ? p0 : 1) - 1));
      this.cx = Math.min(this.cols - 1, Math.max(0, (parts.length > 1 ? p1 : 1) - 1));
    } else if (fin === 'r' && !priv) {
      // DECSTBM: set the scrolling region; the cursor goes home
      var t = (parts.length && p0) ? p0 : 1, bb = (parts.length > 1 && p1) ? p1 : this.rows;
      if (t < bb && bb <= this.rows) { this.top = t - 1; this.bot = bb - 1; }
      else { this.top = 0; this.bot = this.rows - 1; }
      this.cx = 0; this.cy = 0;
    } else if (fin === 'J') {
      this._erase(parts.length ? p0 : 0);
      if ((parts.length ? p0 : 0) === 2) { this.cx = 0; this.cy = 0; }
    } else if (fin === 'K') {
      this._eraseLine(parts.length ? p0 : 0);
    } else if (fin === 'm') {
      if (!parts.length) this.rev = false;
      for (var k = 0; k < parts.length; k++) {
        var v = parseInt(parts[k], 10);
        if (v === 0) this.rev = false;
        else if (v === 7) this.rev = true;
        else if (v === 27) this.rev = false;
      }
    } else if (fin === 'A') { this.cy = Math.max(0, this.cy - (p0 || 1)); }
    else if (fin === 'B') { this.cy = Math.min(this.rows - 1, this.cy + (p0 || 1)); }
    else if (fin === 'C') { this.cx = Math.min(this.cols - 1, this.cx + (p0 || 1)); }
    else if (fin === 'D') { this.cx = Math.max(0, this.cx - (p0 || 1)); }
    // VT102 insert / delete character - Starship v02 slides its picture with these.
    // The cells at and right of the cursor move; the cursor itself stays put.
    else if (fin === '@' || fin === 'P') {
      var n = Math.min(p0 || 1, this.cols - this.cx), row = this.grid[this.cy], b;
      if (this.cx < this.cols) {
        for (b = 0; b < n; b++) {
          if (fin === '@') { row.splice(this.cx, 0, { ch: ' ', rev: false }); row.pop(); }
          else { row.splice(this.cx, 1); row.push({ ch: ' ', rev: false }); }
        }
      }
    }
    return j - i + 1;
  };

  VT100.prototype.write = function (bytes) {
    var s = this.pending;
    this.pending = '';
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i] & 0xFF);
    var p = 0;
    while (p < s.length) {
      var ch = s.charAt(p), code = s.charCodeAt(p);
      if (code === 0x1B) {
        var used = this._esc(s, p);
        if (used < 0) { this.pending = s.slice(p); break; }  // finish it next batch
        p += used; continue;
      }
      if (code === 0x0D) { this.cx = 0; p++; continue; }
      if (code === 0x0A) { this._nl(); p++; continue; }
      if (code === 0x08) { this.cx = Math.max(0, this.cx - 1); p++; continue; }
      if (code === 0x09) { this.cx = Math.min(this.cols - 1, (this.cx + 8) & ~7); p++; continue; }
      if (code === 0x07 || code < 0x20 || code === 0x7F) { p++; continue; }
      this._put(ch); p++;
    }
    this.dirty = true;
  };

  function esc(t) {
    return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // An 80-column screen has to FIT, or the picture is cut in half - the terminal
  // sits in a fairly narrow column on these pages. Measure the element and pick the
  // largest font size up to the stylesheet's that shows all 80 columns.
  VT100.prototype.fit = function () {
    if (!this.el) return;
    var avail = this.el.clientWidth;
    if (!avail || avail === this._fitFor) return;
    this._fitFor = avail;
    if (!this._baseSize) {
      this.el.style.fontSize = '';
      this._baseSize = parseFloat(getComputedStyle(this.el).fontSize) || 13;
    }
    var probe = document.createElement('span');
    probe.style.cssText = 'position:absolute;visibility:hidden;white-space:pre;font-size:100px';
    probe.style.fontFamily = getComputedStyle(this.el).fontFamily;
    probe.textContent = new Array(this.cols + 1).join('X');
    document.body.appendChild(probe);
    var w100 = probe.getBoundingClientRect().width;
    probe.parentNode.removeChild(probe);
    if (!w100) return;
    var size = Math.floor(avail / w100 * 100 * 10) / 10;      // 0.1px steps
    this.el.style.fontSize = Math.max(6, Math.min(this._baseSize, size)) + 'px';
  };

  VT100.prototype.render = function () {
    if (!this.el) return;
    this.fit();
    if (!this.dirty) return;
    this.dirty = false;
    var html = '';
    if (this.scroll.length) html += esc(this.scroll.join('\n')) + '\n';
    for (var r = 0; r < this.rows; r++) {
      var row = this.grid[r], line = '', run = '', runRev = null;
      for (var c = 0; c < this.cols; c++) {
        var cell = row[c];
        // the cursor is drawn by inverting the cell it sits on, which is how
        // Bouncing-Ball v01 draws its ball - the program prints nothing at all
        var rev = cell.rev;
        if (this.curVis && r === this.cy && c === this.cx) rev = !rev;
        if (rev !== runRev) {
          if (runRev !== null) line += runRev ? '<span class="rev">' + esc(run) + '</span>' : esc(run);
          run = ''; runRev = rev;
        }
        run += cell.ch;
      }
      if (runRev !== null) line += runRev ? '<span class="rev">' + esc(run) + '</span>' : esc(run);
      html += line.replace(/\s+$/, '') + (r < this.rows - 1 ? '\n' : '');
    }
    this.el.innerHTML = html;
    this.el.scrollTop = this.el.scrollHeight;
  };

  return function (el, opts) {
    var vt = new VT100(el, opts);
    if (typeof window !== 'undefined' && window.addEventListener) {
      window.addEventListener('resize', function () { vt._fitFor = null; vt.dirty = true; vt.render(); });
    }
    return vt;
  };
});
