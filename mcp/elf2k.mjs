// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// The website's Elf2K with no page around it: the same modules (web/js, unchanged), a VT100 that is only
// a grid, keys by name, and a clock that counts the 1802's machine cycles. Two machines:
//
//   * 'ltos'    - elf2k.js with the web BIOS and the baked card: LTOS at its prompt, and STELLAR apps
//                 started from it.
//   * 'stellar' - the bare firmware cold-booted with up to four .lst programs, one in each VM
//                 (stellar-vm.js's MultiVM, loaded as machine.js loads the Multitasking page).
//
// Nothing here reads this computer's clock: time is cpu.cycles, 375,000 a second on a 3 MHz Elf2K, and
// the DS12887 starts at a fixed date and runs on the same count.
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const WEB = join(dirname(fileURLToPath(import.meta.url)), '..', 'web');
const firmware = require(join(WEB, 'js', 'firmware-0061-37.js'));
const LIB = require(join(WEB, 'js', 'stellar-vm.js'));
const E = require(join(WEB, 'js', 'elf2k.js'));
const VT100 = require(join(WEB, 'js', 'vt100.js'));
const COS = require(join(WEB, 'js', 'cosmac.js'));
// webbios.js only sets a window global, so its bytes are read out of the text (as test_ltos.mjs does)
const bios = Uint8Array.from(Buffer.from(
  /LTOS_WEBBIOS = "([^"]+)"/.exec(readFileSync(join(WEB, 'js', 'webbios.js'), 'utf8'))[1], 'base64'));
const baked = E.parseCard(readFileSync(join(WEB, 'ltos', 'ltos-card.bin')));
const SAMPLES = join(WEB, 'samples');

export const CYCLES_PER_SECOND = 375000;      // 3 MHz / 8 clocks a machine cycle
export const DEFAULT_CLOCK = '2026-11-09T12:00:00';
const CHUNK = 32;                             // 1802 instructions between looks at the stop conditions
const QUIET = CYCLES_PER_SECOND / 4;          // waiting = this long with nothing printed ...
const MIN_POLLS = 50;                         // ... while the UART was asked for a key at least this often
const POLL_GAP = 5000;                        // ... the last time no longer ago than this (cycles)
const RECV_MAX = 16000;                       // RECV holds the file in memory: "up to about 16 KB"

// ---- keys ----
// What a VT100 sends, as js/term-input.js has it (its table is not exported, so it is repeated here).
const NAMED = {
  enter: [0x0D], return: [0x0D], esc: [0x1B], escape: [0x1B], tab: [0x09], space: [0x20],
  backspace: [0x08], bksp: [0x08], delete: [0x1B, 0x5B, 0x33, 0x7E], del: [0x1B, 0x5B, 0x33, 0x7E],
  up: [0x1B, 0x5B, 0x41], down: [0x1B, 0x5B, 0x42], right: [0x1B, 0x5B, 0x43], left: [0x1B, 0x5B, 0x44],
  home: [0x1B, 0x5B, 0x48], end: [0x1B, 0x5B, 0x46],
  pageup: [0x1B, 0x5B, 0x35, 0x7E], pgup: [0x1B, 0x5B, 0x35, 0x7E],
  pagedown: [0x1B, 0x5B, 0x36, 0x7E], pgdn: [0x1B, 0x5B, 0x36, 0x7E]
};
export function keyBytes(name) {
  const k = String(name).trim();
  const ctrl = /^(?:ctrl|control|\^)[-+ ]?(.)$/i.exec(k);
  if (ctrl) {
    const c = ctrl[1].toUpperCase().charCodeAt(0);
    if (c >= 0x40 && c <= 0x5F) return [c - 0x40];             // ^@ ^A..^Z ^[ ^\ ^] ^^ ^_
    throw new Error('no such control key: ' + name);
  }
  const named = NAMED[k.toLowerCase().replace(/^arrow/, '').replace(/[ _-]/g, '')];
  if (named) return named;
  if (k.length === 1 && k.charCodeAt(0) < 0x100) return [k.charCodeAt(0)];
  throw new Error('no such key: ' + name + ' (Enter Esc Tab Space Backspace Delete Up Down Left Right Home End ' +
                  'PageUp PageDown Ctrl-A..Ctrl-Z, or one character)');
}
export function textBytes(text) {
  const out = [];
  for (const ch of String(text)) {
    const c = ch.codePointAt(0);
    if (c === 0x0A) out.push(0x0D);                            // the terminal's Enter is CR
    else if (c < 0x100) out.push(c);
    else throw new Error('the terminal is 8-bit: cannot type ' + JSON.stringify(ch));
  }
  return out;
}

// ---- the clock ----
// stellar-vm.js's DS12887 with its two readers of Date.now() replaced: the fields come from a start
// date plus the cycles run, and setting the clock (DATE, TIME, $07 RTCSET) moves the start date.
function cycleClock(cpu, start) {
  const rtc = new LIB.RTC();
  let base = Date.parse(start + 'Z');
  if (isNaN(base)) throw new Error('clock: want a date like ' + DEFAULT_CLOCK);
  rtc.now = () => new Date(base + cpu.cycles * 1000 / CYCLES_PER_SECOND);
  rtc._load = function () {
    const d = this.now(), r = this.r, binary = r[0x0B] & 0x04;
    r[0] = this._enc(d.getUTCSeconds()); r[2] = this._enc(d.getUTCMinutes()); r[4] = this._enc(d.getUTCHours());
    r[6] = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
    r[7] = this._enc(d.getUTCDate()); r[8] = this._enc(d.getUTCMonth() + 1);
    r[9] = binary ? (d.getUTCFullYear() - 1972) & 0xFF : this._enc(d.getUTCFullYear() % 100);
  };
  rtc._commit = function () {
    const r = this.r, y = (r[0x0B] & 0x04) ? 1972 + r[9] : 2000 + this._dec(r[9]);
    const t = Date.UTC(y, this._dec(r[8]) - 1, this._dec(r[7]), this._dec(r[4]), this._dec(r[2]), this._dec(r[0]));
    if (!isNaN(t)) base = t - cpu.cycles * 1000 / CYCLES_PER_SECOND;
  };
  return rtc;
}

// ---- the card, read from outside (as a PC reads it: FAT16, 8.3 names) ----
function fat(disk) {
  const sec = lba => disk.get(lba) || new Uint8Array(512);
  const u16 = (b, o) => b[o] | (b[o + 1] << 8), u32 = (b, o) => (u16(b, o) | (u16(b, o + 2) << 16)) >>> 0;
  const part = u32(sec(0), 0x1BE + 8), bpb = sec(part);
  const perCluster = bpb[13], fat0 = part + u16(bpb, 14), rootEntries = u16(bpb, 17);
  const root0 = fat0 + bpb[16] * u16(bpb, 22), data0 = root0 + Math.ceil(rootEntries * 32 / 512);
  const next = c => u16(sec(fat0 + (c >> 8)), (c & 0xFF) * 2);
  function chain(first, size) {
    const parts = [];
    for (let c = first, n = 0; c >= 2 && c < 0xFFF0 && n < 65536; c = next(c), n++) {
      for (let s = 0; s < perCluster; s++) parts.push(sec(data0 + (c - 2) * perCluster + s));
    }
    const all = Buffer.concat(parts);
    return size === undefined ? all : all.subarray(0, size);
  }
  function entries(bytes) {
    const out = [];
    for (let o = 0; o + 32 <= bytes.length; o += 32) {
      const e = bytes.subarray(o, o + 32), attr = e[11];
      if (e[0] === 0) break;
      if (e[0] === 0xE5 || attr === 0x0F || (attr & 0x08)) continue;
      const base = Buffer.from(e.subarray(0, 8)).toString('latin1').trimEnd();
      const ext = Buffer.from(e.subarray(8, 11)).toString('latin1').trimEnd();
      if (base === '.' || base === '..') continue;
      const d = u16(e, 24), t = u16(e, 22), p2 = v => String(v).padStart(2, '0');
      out.push({ name: ext ? base + '.' + ext : base, dir: !!(attr & 0x10), hidden: !!(attr & 0x02),
                 size: u32(e, 28), cluster: u16(e, 26),
                 date: (1980 + (d >> 9)) + '-' + p2((d >> 5) & 15) + '-' + p2(d & 31) + ' ' + p2(t >> 11) + ':' + p2((t >> 5) & 63) });
    }
    return out;
  }
  const rootBytes = () => Buffer.concat(Array.from({ length: data0 - root0 }, (_, i) => sec(root0 + i)));
  // the folder's entries, or the one file's entry, at a path from the root
  function find(path) {
    const names = String(path || '/').toUpperCase().split('/').filter(Boolean);
    let list = entries(rootBytes()), at = null;
    for (let i = 0; i < names.length; i++) {
      at = list.find(e => e.name === names[i]);
      if (!at) throw new Error('There is no ' + names.slice(0, i + 1).join('/') + ' on the card');
      if (at.dir) list = entries(chain(at.cluster));
      else if (i < names.length - 1) throw new Error(names[i] + ' is a file, not a folder');
    }
    return { entry: at, list: !at || at.dir ? list : null };
  }
  return {
    list(path) {
      const f = find(path);
      if (!f.list) return [f.entry];
      return f.list;
    },
    read(path) {
      const f = find(path);
      if (!f.entry || f.entry.dir) throw new Error((path || '/') + ' is a folder');
      return chain(f.entry.cluster, f.entry.size);
    }
  };
}

function intelHex(bytes) {
  const lines = [];
  const rec = (addr, type, data) => {
    const b = [data.length, addr >> 8, addr & 0xFF, type, ...data];
    b.push((-b.reduce((a, v) => a + v, 0)) & 0xFF);
    lines.push(':' + b.map(v => v.toString(16).toUpperCase().padStart(2, '0')).join(''));
  };
  for (let a = 0; a < bytes.length; a += 16) rec(a, 0, Array.from(bytes.subarray(a, a + 16)));
  rec(0, 1, []);
  return lines.join('\r') + '\r';
}

const VM_STATES = { 0x00: 'finished', 0x01: 'active', 0x05: 'killed', 0x06: 'stopped on an error' };
const h2 = v => v.toString(16).toUpperCase().padStart(2, '0');
const h4 = v => v.toString(16).toUpperCase().padStart(4, '0');

export class Elf2K {
  constructor() {
    this.mode = 'off';
    this.card = new Map(baked.map);
    this.written = new Set();                 // sectors LTOS has written since the card was baked
  }

  // ---- power ----
  _attach(cpu, pending, clock) {
    const self = this;
    this.cpu = cpu; this.pending = pending;
    this.vt = VT100(null);
    this.scrolled = [];
    const up = this.vt._scrollUp;             // lines pushed off the top, kept for the next result
    this.vt._scrollUp = function () { up.call(this); self.scrolled.push(this.scroll[this.scroll.length - 1]); };
    this.out = [];
    this.lastActivity = 0; this.polls = 0; this.lastPoll = 0;
    cpu.rtc = cycleClock(cpu, clock || DEFAULT_CLOCK);
    if (cpu.io_in[3].rtc) cpu.io_in[3].rtc = cpu.rtc;
    // count the times the UART is asked for a key and has none
    const port = cpu.io_in[3], pop = port.pop, sel = cpu.io_out[2];
    port.pop = function (i) {
      const s = sel[sel.length - 1];
      if (s === 0x10 || s === 0x15) {
        if (!pending()) { self.polls++; self.lastPoll = cpu.cycles; }
        else if (s === 0x10) self._active();
      }
      return pop.call(this, i);
    };
  }
  _active() { this.lastActivity = this.cpu.cycles; this.polls = 0; }

  bootLtos(opts = {}) {
    if (opts.restoreCard) { this.card = new Map(baked.map); this.written = new Set(); }
    const self = this;
    const m = this.m = new E.Machine({ bios, firmware, sectors: baked.sectors, card: this.card,
                                       onOutput: b => { self.out.push(b); self._active(); } });
    m.cf.dirty = this.written;
    m.authentic = !!opts.authenticUart;
    this.mode = 'ltos'; this.mvm = null; this.programs = null;
    this._attach(m.cpu, () => m.uart.buf.length + (m.authentic && m.uart.rbr >= 0 ? 1 : 0), opts.clock);
    this._step = () => m.run(CHUNK);
    this._keys = bytes => m.keys(bytes);
  }

  // programs: [{ name, text, blocks }] - VM1 first. Each is a VM1 .lst; MultiVM moves it up into its own
  // block, and only the bytes inside its block(s) are kept (machine.js: the claim lines at a .lst's end
  // would land on the VMs above).
  bootStellar(programs, opts = {}) {
    if (!programs.length || programs.length > 4) throw new Error('one to four programs, VM1 first');
    const mvm = this.mvm = new LIB.MultiVM({
      firmware,
      programs: programs.map(p => {
        const end = 0x4000 + (p.blocks || 1) * 0x1000;
        return p.text ? LIB.parseLst(p.text).filter(q => q[0] >= 0x4000 && q[0] < end) : [];
      })
    });
    const c = mvm.cpu, self = this;
    this.mode = 'stellar'; this.m = null; this.programs = programs.map(p => p.name);
    this._attach(c, () => c.io_in[3].buf.length, opts.clock);
    const o3 = c.io_out[3] || (c.io_out[3] = []);
    this._step = () => {
      let ok = true;
      for (let i = 0; i < CHUNK && ok; i++) ok = c.step();
      if (o3.length) { for (const b of o3) self.out.push(b); o3.length = 0; self._active(); }
      for (const p in c.io_out) if (p !== '3' && c.io_out[p].length > 256) c.io_out[p].splice(0, c.io_out[p].length - 16);
      return ok;
    };
    this._keys = bytes => { for (const b of bytes) c.io_in[3].buf.push(b & 0xFF); };
  }

  _on() { if (this.mode === 'off') throw new Error('The machine is off. Call boot (LTOS) or stellar_load first.'); }

  // ---- time ----
  get waiting() {
    const c = this.cpu;
    return !this.pending() && this.polls >= MIN_POLLS && c.cycles - this.lastPoll < POLL_GAP &&
           c.cycles - this.lastActivity >= QUIET;
  }
  // Run for up to `seconds` of the Elf2K's time. Stops early when the machine waits for a key (unless
  // stopWhenWaiting is false), when `until()` says so, or when the 1802 stops (IDL).
  run(seconds, opts = {}) {
    this._on();
    const c = this.cpu, start = c.cycles, budget = Math.round(seconds * CYCLES_PER_SECOND);
    const early = opts.stopWhenWaiting !== false;
    const row0 = this.vt.cy, kept = this.scrolled.length;
    let stop = 'time';
    if (c.halted) stop = 'halted';
    else while (c.cycles - start < budget) {
      if (!this._step()) { stop = 'halted'; break; }
      if (early && this.waiting) { stop = 'waiting'; break; }
      if (opts.until && this.out.length && (this._flush(), opts.until())) { stop = 'until'; break; }
    }
    this._flush();
    // of the lines pushed off the top, the rows that were above the cursor when this began are old
    const gone = this.scrolled.splice(kept);
    this.scrolled.push(...gone.slice(Math.min(row0, gone.length)));
    return { stop, cycles: c.cycles - start };
  }
  _flush() { if (this.out.length) { this.vt.write(this.out); this.out = []; } }

  type(bytes) {
    this._on();
    this._keys(bytes);
    this._active();
  }

  // ---- the screen ----
  // 24 rows of 80. A run of reverse-video blanks is shown as blocks, because that is how the apps draw
  // pictures; reverse-video text (a title bar) is shown as the text.
  screen() {
    this._on();
    const rows = this.vt.grid.map(r => {
      let line = '';
      for (let i = 0; i < r.length;) {
        let j = i;
        while (j < r.length && r[j].rev === r[i].rev) j++;
        const run = r.slice(i, j).map(x => x.ch).join('');
        line += r[i].rev && !run.trim() ? '\u2588'.repeat(run.length) : run;
        i = j;
      }
      return line.replace(/\s+$/, '');
    });
    return { rows, cursor: { row: this.vt.cy + 1, col: Math.min(this.vt.cx, 79) + 1, visible: this.vt.curVis } };
  }
  takeScrolled() { const s = this.scrolled; this.scrolled = []; return s; }
  _cursorLine() {
    const s = this.screen();
    return { text: s.rows[s.cursor.row - 1], above: s.rows[s.cursor.row - 2] || '', col: s.cursor.col };
  }
  _barePrompt() {
    const l = this._cursorLine();
    return /^LTOS( \/\S*)?>$/.test(l.text) && l.col === l.text.length + 2;
  }
  atPrompt() { return this.mode === 'ltos' && this.waiting && this._barePrompt(); }

  // ---- memory ----
  peek(addr, len) { this._on(); return this.cpu.M.slice(addr & 0xFFFF, Math.min(0x10000, (addr & 0xFFFF) + len)); }
  cpuState() {
    this._on();
    const c = this.cpu, pc = c.R[c.P];
    return { R: Array.from(c.R), P: c.P, X: c.X, D: c.D, DF: c.DF, Q: c.Q, IE: c.IE, halted: c.halted,
             pc, next: COS.decode(c.M, pc).text };
  }
  cidp() { this._on(); return LIB.MultiVM.prototype.cidp.call({ cpu: this.cpu }); }
  vmCore(vm) { this._on(); return LIB.readCore(this.cpu.M, 0x3000 + (vm - 1) * 0x400); }

  // ---- the card ----
  cardList(path) { return fat(this.card).list(path); }
  cardRead(path) { return fat(this.card).read(path); }
  // A file onto the card the way a terminal program does it: RECV at the prompt, then Intel HEX. LTOS's
  // own code writes the card, so what it keeps in memory and the card agree.
  cardWrite(path, bytes, replace) {
    if (!this.atPrompt()) throw new Error('write_file types RECV at the LTOS> prompt: boot first, or leave the program that is running');
    if (bytes.length > RECV_MAX) throw new Error('RECV takes up to about 16 KB; this is ' + bytes.length + ' bytes');
    if (!bytes.length) throw new Error('nothing to write (TOUCH makes an empty file)');
    let cycles = 0;
    const go = (keys, seconds, until) => {
      this.type(textBytes(keys));
      cycles += this.run(seconds, { stopWhenWaiting: false, until }).cycles;
    };
    const asked = () => { const l = this._cursorLine(); return l.col === 1 && l.above.startsWith('Send it:'); };
    go('RECV ' + path + '\r', 30, () => asked() || this._barePrompt());
    const replaceQ = () => /replace it\? \(Y\/N\)$/.test(this._cursorLine().text);
    let exists = false;
    if (asked()) go(intelHex(bytes), 120, () => this._barePrompt() || replaceQ());
    if (replaceQ()) { exists = true; go(replace ? 'Y' : 'N', 30, () => this._barePrompt()); }
    cycles += this.run(5).cycles;
    return { saved: /^Saved \S+, \d+ bytes\.$/.test(this._cursorLine().above), exists, cycles };
  }
}

export function samples() {
  const manifest = JSON.parse(readFileSync(join(SAMPLES, 'manifest.json'), 'utf8'));
  const known = new Map(manifest.map(s => [s.file, s]));
  return readdirSync(SAMPLES).filter(f => f.endsWith('.lst')).sort().map(f => {
    const s = known.get(f);
    return { file: f, name: s ? s.name : f.replace(/\.lst$/, ''), blurb: s ? s.blurb : '' };
  });
}
export function sampleText(file) {
  const want = String(file).toLowerCase().replace(/\.lst$/, '');
  const hit = readdirSync(SAMPLES).find(f => f.toLowerCase() === want + '.lst');
  if (!hit) throw new Error('no sample ' + file + ' (list_apps shows them)');
  return { name: hit, text: readFileSync(join(SAMPLES, hit), 'utf8') };
}
export { VM_STATES, h2, h4 };
