# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""MORSE.PRG in a cycle-counting 1802 at a given clock (2 machine cycles an instruction, 3 for $Cx; MHz x 125,000 a
second), the kernel's calls played in Python.

Sending (-s, -t): every edge of Q timed, the tone's pitch measured, and the marks and gaps decoded by THIS file's own
Morse reader (Firmware-Math/morse_table.py) back into text - dot 1, dash 3, gaps 1 / 3 / 7 at the WPM asked, at 3.58
and 1.79 MHz, other tones. -t shows each letter and its dots and dashes, as MORSETX.STL.
Receiving (-r): a hand keyed onto EF4 (or EF3 with -e 3) - at a speed other than -w's, sloppy (each element and gap
off by up to 20%), the switch bouncing at every change - and Esc: the file saved must be the text keyed.
Then the usage for no mode, two modes, a bad speed, clock or EF line, and a name that is not one.

    python3 LTOS/verify_morse.py [-v]
"""
import math, os, random, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
from cpu1802 import CPU
import build, morse_table as MT

K = dict(K_LOADF=0x30C, K_SAVEF=0x30F, K_PIN=0x312, K_PDEC=0x315, K_PCRLF=0x31E, K_SKIPSP=0x321, K_PARSE=0x32A,
         K_OUT=0x332, F_TYPE=0xFF03, F_INPUTL=0xFF69)


class Run:
    """keyed: [(seconds, level)] - EF n set from then on; key_at: seconds, an Esc on the terminal; lines: for -t."""
    def __init__(s, prg, args, mhz=3.5795, files=None, keyed=(), ef=4, key_at=None, lines=(), max_s=60, keyval=0x1B):
        s.keyval = keyval
        s.clk = mhz * 1e6 / 8
        s.mem = bytearray(65536)
        lo = prg[0] << 8 | prg[1]; start = prg[4] << 8 | prg[5]
        s.mem[lo:lo + len(prg) - 6] = prg[6:]
        a = 0x7000; s.mem[a:a + len(args) + 1] = args.encode() + b'\0'
        c = s.c = CPU(s.mem); c.P = 3; c.X = 2; c.R[2] = 0x7DFF; c.R[3] = start; c.R[15] = a; c.Q = 0
        s.files, s.saved, s.out, s.edges, s.cyc, s.stack, s.sel = files or {}, {}, '', [], 0, [], 0
        s.lines = list(lines); s.key_at = key_at; s.end = None
        keyed = sorted(keyed); ki = 0
        q = 0
        while s.cyc < max_s * s.clk:
            while ki < len(keyed) and keyed[ki][0] * s.clk <= s.cyc:
                c.EF[ef - 1] = keyed[ki][1]; ki += 1
            if c.P == 4: s.call(); continue
            if c.P == 5:
                if not s.stack: s.end = 'returned'; break
                c.R[3] = s.stack.pop(); c.P = 3; continue
            op = s.mem[c.R[c.P]]
            if op == 0x62: s.sel = s.mem[c.R[c.X]]
            if op == 0x6B:
                ready = s.key_at is not None and s.cyc >= s.key_at * s.clk
                if s.sel == 0x15: c.io_in[3] = [0x60 | ready]
                elif s.sel == 0x10: c.io_in[3] = [s.keyval]; s.key_at = None
            c.step(); s.cyc += 3 if op >> 4 == 0xC else 2
            if c.Q != q: q = c.Q; s.edges.append((s.cyc, q))
        else: s.end = 'time'
        s.qend = c.Q

    def call(s):
        c = s.c; m = s.mem
        t = m[c.R[3]] << 8 | m[c.R[3] + 1]; c.R[3] += 2; c.P = 3
        if t >= 0x3000 and t < 0x8000: s.stack.append(c.R[3]); c.R[3] = t; return
        if t == K['K_PIN']:
            while m[c.R[3]]: s.out += chr(m[c.R[3]]); c.R[3] += 1
            c.R[3] += 1
        elif t in (K['K_OUT'], K['F_TYPE']): s.out += chr(c.D)
        elif t == K['K_PCRLF']: s.out += '\r\n'
        elif t == K['K_PDEC']: s.out += str(c.R[13])
        elif t == K['K_SKIPSP']:
            while m[c.R[15]] == 0x20: c.R[15] += 1
        elif t == K['K_PARSE']:
            n = s.name(c.R[15])
            c.DF = 0 if n and '*' not in n and len(n.split('/')[-1].split('.')[0]) <= 8 else 1
        elif t == K['K_LOADF']:
            n = s.name(c.R[15])
            if n not in s.files: s.out += '(no file %s)' % n; s.stack = []; c.P = 5; return
            d = s.files[n]; m[c.R[10]:c.R[10] + len(d)] = d; c.R[12] = len(d)
        elif t == K['K_SAVEF']:
            n = s.name(c.R[15]); s.saved[n] = bytes(m[c.R[10]:c.R[10] + c.R[12]])
            s.out += 'Saved %s, %d bytes.\r\n' % (n, c.R[12]); s.stack = []; c.P = 5
        elif t == K['F_INPUTL']:
            if not s.lines: c.DF = 1; return
            ln = s.lines.pop(0).encode(); m[c.R[15]:c.R[15] + len(ln) + 1] = ln + b'\0'; s.out += ln.decode(); c.DF = 0
        else: raise SystemExit('call to $%04X' % t)

    def name(s, a):
        n = b''
        while self_ok(s.mem[a]): n += bytes([s.mem[a]]); a += 1
        return n.decode()

    def morse(s):
        """Q's edges -> tone runs [(start s, length s, Hz)] - a run ends at a low over 3 half-periods."""
        e = s.edges; runs, i = [], 0
        if e and e[0][1] == 0: e = e[1:]
        iv = sorted(e[k + 1][0] - e[k][0] for k in range(len(e) - 1))
        h = iv[len(iv) // 4] if iv else 1                  # the tone's half-period (most intervals are one)
        while i + 1 < len(e):
            j = i
            while j + 3 < len(e) and e[j + 2][0] - e[j + 1][0] <= 3 * h: j += 2
            per = (e[j][0] - e[i][0]) / ((j - i) / 2) if j > i else 2 * (e[i + 1][0] - e[i][0])
            runs.append((e[i][0] / s.clk, (e[j + 1][0] - e[i][0]) / s.clk, s.clk / per))
            i = j + 2
        return runs


def self_ok(b): return b not in (0, 0x20)


REV = {p: ch for ch, p in MT.MORSE.items()}


def decode(runs, dot):
    """Tone runs -> text, by this file's own reading: a mark under 2 dots is a dot; a gap over 2 dots ends the
    letter, over 5 the word."""
    text, pat = '', ''
    for k, (t, d, hz) in enumerate(runs):
        pat += '.' if d < 2 * dot else '-'
        gap = runs[k + 1][0] - (t + d) if k + 1 < len(runs) else 99
        if gap > 2 * dot:
            text += REV.get(pat, '?'); pat = ''
            if gap > 5 * dot and k + 1 < len(runs): text += ' '
    return text


def timing(runs, dot):
    """Every mark and gap as a count of dots (rounded) and its error."""
    worst, kinds = 0.0, set()
    for k, (t, d, hz) in enumerate(runs):
        n = round(d / dot); worst = max(worst, abs(d - n * dot) / dot); kinds.add(('mark', n))
        if k + 1 < len(runs):
            g = runs[k + 1][0] - (t + d); n = round(g / dot); worst = max(worst, abs(g - n * dot) / dot); kinds.add(('gap', n))
    return worst, kinds


def keying(text, wpm, sloppy=0.2, bounce=True, start=0.3, seed=1):
    """A hand: [(seconds, level)] for EF; elements and gaps each off by up to `sloppy`; a bounce at each change."""
    rnd = random.Random(seed); dot = 1.2 / wpm; t = start; ev = []
    def j(n): return n * dot * (1 + rnd.uniform(-sloppy, sloppy))
    words = text.split(' ')
    for wi, w in enumerate(words):
        for li, ch in enumerate(w):
            pat = MT.MORSE[ch]
            for ei, el in enumerate(pat):
                if bounce: ev += [(t, 1), (t + 0.0015, 0), (t + 0.0025, 1)]
                else: ev.append((t, 1))
                t += j(1 if el == '.' else 3)
                if bounce: ev += [(t, 0), (t + 0.001, 1), (t + 0.002, 0)]
                else: ev.append((t, 0))
                if ei + 1 < len(pat): t += j(1)
            if li + 1 < len(w): t += j(3)
        if wi + 1 < len(words): t += j(7)
    return ev, t


def main():
    v = '-v' in sys.argv
    import morse_gen; morse_gen.main()
    prg = build.prg('morse')
    global SYMS; SYMS = build.assemble('morse')[1]
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e

    # ---- sending a file
    e = []
    for mhz, c, wpm, hz, text in [(3.5795, '', 12, 700, 'SOS PARIS'), (1.7898, '-c 1.79', 25, 600, 'CQ DE ELF2K'),
                                  (3.5795, '', 5, 700, 'E T'), (1.7898, '-c 1.79', 20, 1000, 'THE QUICK, BROWN FOX? 73')]:
        args = '%s -w %d -f %d -s MSG.TXT' % (c, wpm, hz)
        r = Run(prg, args, mhz, {'MSG.TXT': text.lower().encode()}, max_s=120)
        runs = r.morse(); dot = 1.2 / wpm
        got = decode(runs, dot)
        rw = Run(prg, args, mhz, {'MSG.TXT': ('  ' + text.lower().replace(' ', '  \r\n\t ') + ' \r\n\r\n').encode()}, max_s=120)
        if decode(rw.morse(), dot) != text: e.append('%s: runs of spaces / new lines: %r' % (args, decode(rw.morse(), dot)))
        if rw.edges and r.edges and abs((rw.edges[-1][0] - rw.edges[0][0]) - (r.edges[-1][0] - r.edges[0][0])) > 0.01 * r.clk * (text.count(' ') + 1):
            e.append('%s: runs of spaces cost more than 10 ms a gap' % args)
        if r.end != 'returned' or r.qend: e.append('%s: %s Q %d %r' % (args, r.end, r.qend, r.out[-60:]))
        if got != text: e.append('%s: sent %r, want %r' % (args, got, text))
        pitch = [hz2 for _, _, hz2 in runs]
        if any(abs(1200 * math.log2(p / hz)) > 10 for p in pitch): e.append('%s: pitch %.1f-%.1f Hz, want %d' % (args, min(pitch), max(pitch), hz))
        S = SYMS; w = lambda a: r.mem[a] << 8 | r.mem[a + 1]                # the dot as sent: UNIT half-periods
        dr = w(S['UNIT']) * (42 + 6 * (w(S['KB']) - 255) + 8 * r.mem[S['FRAC']] / 256) / r.clk
        if abs(dr - dot) / dot > 0.015: e.append('%s: a dot is %.2f ms, want %.2f' % (args, dr * 1000, dot * 1000))
        worst, kinds = timing(runs, dr)
        if worst > 0.03 or kinds - {('mark', 1), ('mark', 3), ('gap', 1), ('gap', 3), ('gap', 7)}:
            e.append('%s: timing off by up to %.1f%% of a dot; lengths %r' % (args, worst * 100, sorted(kinds)))
        if v: print(args, '->', got, '%.1f Hz' % (sum(pitch) / len(pitch)), 'worst %.1f%%' % (worst * 100), repr(r.out))
    report('MORSE -s: decoded back to the text (runs of spaces and new lines one word gap, none at the ends); tone in pitch; the dot within 1.5%; dash 3, gaps 1 / 3 / 7 within 3% of it (3.58 and '
           '1.79 MHz, 5-25 WPM, 600-1000 Hz)', e)

    # ---- -t
    e = []
    r = Run(prg, '-t -w 20', lines=['Hello, world', 'SOS'], max_s=60)
    runs = r.morse(); got = decode(runs, 1.2 / 20)
    if got != 'HELLO, WORLD SOS' and got != 'HELLO, WORLDSOS': e.append('sent %r' % got)
    if 'H .... E . L .-.. L .-.. O --- , --..-- W .-- O --- R .-. L .-.. D -..' not in r.out: e.append('shown: %r' % r.out)
    if r.end != 'returned': e.append('end %s' % r.end)
    r2 = Run(prg, '-t', lines=['PARIS PARIS'], key_at=1.5, max_s=30)
    if '(stopped)' not in r2.out or r2.qend: e.append('Esc: %r' % r2.out[-80:])
    r3 = Run(prg, '-t', lines=['PARIS PARIS'], key_at=1.5, keyval=0x41, max_s=30)
    if '(stopped)' in r3.out or decode(r3.morse(), 0.1) != 'PARIS PARIS': e.append('another key: %r %r' % (r3.out[-60:], decode(r3.morse(), 0.1)))
    report('MORSE -t: each line sent as typed, shown as MORSETX (letters and dots and dashes); Esc stops a line, another key does not', e)

    # ---- receiving
    e = []
    for mhz, args, wpm, ef, text, slop, seed in [
            (3.5795, '-w 12 -r RX.TXT', 15, 4, 'CQ CQ DE ELF2K', 0.15, 1),
            (1.7898, '-c 1.79 -w 16 -r RX.TXT', 13, 4, 'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG', 0.2, 2),
            (3.5795, '-e 3 -w 10 -r RX.TXT', 10, 3, 'SOS 73 PARIS', 0.1, 3),
            (3.5795, '-w 20 -r RX.TXT', 22, 4, 'NOW IS THE TIME', 0.2, 4)]:
        ev, end = keying(text, wpm, slop, True, 0.3, seed)
        r = Run(prg, args, mhz, keyed=ev, ef=ef, key_at=end + 2.0, max_s=end + 10)
        saved = r.saved.get('RX.TXT', b'').decode()
        if r.end != 'returned' or saved != text + '\n':
            e.append('%s keyed %d WPM +-%d%%: saved %r, want %r (%s)' % (args, wpm, slop * 100, saved, text, r.end))
        side = [hz for _, d, hz in r.morse() if d > 0.03]
        if side and abs(1200 * math.log2(sum(side) / len(side) / 700)) > 60:
            e.append('%s: sidetone %.0f Hz' % (args, sum(side) / len(side)))
        if v: print(args, '->', repr(saved), '%.0f Hz' % (sum(side) / len(side)) if side else '', repr(r.out[-120:]))
    ev, end = keying('SOS', 12, 0.0, False, 0.3, 5)
    r = Run(prg, '-v -w 12 -r V.TXT', keyed=ev, key_at=end + 2.0, max_s=end + 6)
    import re as _re
    shown = _re.findall(r'([._-])(\d+)', r.out.split('Esc saves.')[-1])
    if shown and shown[0][0] == '_': shown = shown[1:]        # (the wait before the first mark)
    marks = [(c, int(n)) for c, n in shown if c in '.-']; gaps = [int(n) for c, n in shown if c == '_']
    want = [('.', 140)] * 3 + [('-', 420)] * 3 + [('.', 140)] * 3
    if r.saved.get('V.TXT') != b'SOS\n' or len(marks) != 9 or any(c != wc or abs(n - wn) > 6 for (c, n), (wc, wn) in zip(marks, want)) \
            or len(gaps) != 8 or any(abs(g - (420 if k in (2, 5) else 140)) > 8 for k, g in enumerate(gaps)):
        e.append('-v: %r saved %r' % (shown, r.saved.get('V.TXT')))
    report('MORSE -r: a sloppy, bouncing hand at another speed than -w, decoded and saved on Esc (EF4, EF3, 1.79 MHz); '
           '-v shows each mark and gap in samples', e)
    e = []

    # -a: a sound module on the line - while a tone sounds its output pulses at the tone's pitch (here 25% of each
    # cycle), and between marks a noise blip now and then; -i: a module that goes the other way up
    def audio(text, wpm, fin, duty=0.25, sloppy=0.1, seed=6, invert=False, blips=True):
        ev, end = keying(text, wpm, sloppy, False, 0.3, seed)
        rnd = random.Random(seed); out = []; on, off = (1, 0) if not invert else (0, 1)
        out.append((0.0, off))
        for (t0, a), (t1, b) in zip(ev, ev[1:] + [(end + 0.5, 0)]):
            if a == 1:                                  # a mark: pulses at fin
                t = t0
                while t < t1:
                    out += [(t, on), (min(t + duty / fin, t1), off)]; t += 1 / fin
            elif blips:                                 # a gap: a blip of 0.1 ms every so often
                t = t0 + rnd.uniform(0.005, 0.03)
                while t < t1 - 0.005:
                    out += [(t, on), (t + 0.0001, off)]; t += rnd.uniform(0.02, 0.06)
        return out, end
    for mhz, args, wpm, fin, inv, text in [(3.5795, '-a -e 3 -w 15 -r RX.TXT', 15, 700, False, 'CQ CQ DE ELF2K'),
                                            (1.7898, '-c 1.79 -a -e 3 -w 12 -r RX.TXT', 13, 600, False, 'SOS 73'),
                                            (3.5795, '-a -i -e 3 -w 20 -r RX.TXT', 18, 1000, True, 'PARIS NOW'),
                                            (3.5795, '-a -h 12 -e 3 -w 10 -r RX.TXT', 10, 400, False, 'THE END')]:
        ev, end = audio(text, wpm, fin, invert=inv)
        r = Run(prg, args, mhz, keyed=ev, ef=3, key_at=end + 2.0, max_s=end + 8)
        saved = r.saved.get('RX.TXT', b'').decode()
        if r.end != 'returned' or saved != text + '\n':
            e.append('%s: a %d Hz tone at %d WPM: saved %r, want %r' % (args, fin, wpm, saved, text))
        if r.morse(): e.append('%s: Q sounded (no sidetone with -a)' % args)
        if '(-a: a sound module' not in r.out: e.append('%s: %r' % (args, r.out[:200]))
        if v: print(args, '->', repr(saved))
    report('MORSE -r -a: a sound module\'s pulses at the tone\'s pitch (400-1000 Hz, noise blips between) decoded, at '
           '3.58 and 1.79 MHz, -i the other way up, -h a longer hold; no sidetone', e)
    e = []
    r = Run(prg, '-r NONE.TXT', key_at=1.0, max_s=5)
    if 'Nothing received' not in r.out or r.saved: e.append('nothing keyed: %r' % r.out)
    report('MORSE -r: nothing keyed: nothing saved', e)

    e = []
    for bad in ('', '-w 12', '-s A -t', '-w 50 -t', '-w 4 -t', '-c 0.5 -t', '-c 12 -t', '-e 5 -t', '-f 100 -t', '-q -t', '-s', '-h 0 -t', '-h 60 -t', '-h -t'):
        r = Run(prg, bad, max_s=3)
        if 'MORSE -s name' not in r.out or r.mem[0x33F] != 1: e.append('%r: %r' % (bad, r.out[:60]))
    r = Run(prg, '-r BAD*NAME', max_s=3)
    if 'not a name' not in r.out: e.append('-r BAD*NAME: %r' % r.out)
    r = Run(prg, '-s NOPE.TXT', max_s=3)
    if 'no file NOPE.TXT' not in r.out: e.append('-s NOPE.TXT: %r' % r.out)
    report('the usage: no mode, two modes, a speed, clock, EF line or tone out of range, an unknown option; a bad name; '
           'no such file', e)
    print('\nMORSE: %s (%d bytes)' % ('ALL PASS' if ok else 'FAIL', len(prg)))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
