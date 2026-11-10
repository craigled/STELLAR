# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""PLAY.PRG in a cycle-counting 1802 (2 machine cycles an instruction, 3 for $Cx; play_gen.CLK a second - 3.5795 MHz): the kernel's
calls played in Python, Q's every edge timed. Checks the pitch of every note C1-A#7 against equal temperament
(A4 = 440), the lengths (tempo, L, dots, triplets, rests, MN ML MS), sharps / flats / octaves, comments printed,
a bad character reported with its line, a key stopping it with Q off, .MUS added, -n.

    python3 LTOS/verify_play.py [-v]
"""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
from cpu1802 import CPU
import build

import play_gen
CLK = play_gen.CLK
K = dict(K_MAIN=0x309, K_LOADF=0x30C, K_PIN=0x312, K_PDEC=0x315, K_PCRLF=0x31E, K_SKIPSP=0x321, K_OUT=0x332)
NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


class Run:
    def __init__(s, prg, args, files=None, key_at=None, max_s=60, mhz=None):
        s.clk = mhz * 1e6 / 8 if mhz else CLK
        s.mem = bytearray(65536)
        lo = prg[0] << 8 | prg[1]; start = prg[4] << 8 | prg[5]
        s.mem[lo:lo + len(prg) - 6] = prg[6:]
        a = 0x7000; s.mem[a:a + len(args) + 1] = args.encode() + b'\0'
        c = s.c = CPU(s.mem); c.P = 3; c.X = 2; c.R[2] = 0x7DFF; c.R[3] = start; c.R[15] = a; c.Q = 0
        s.files = files or {}; s.out = ''; s.edges = []; s.cyc = 0; s.stack = []; s.sel = 0
        s.key_at = key_at; s.end = None; s.loaded = None
        q, port = c.Q, None
        while s.cyc < max_s * s.clk:
            if c.P == 4: s.call(); continue
            if c.P == 5:
                if not s.stack: s.end = 'returned'; break
                c.R[3] = s.stack.pop(); c.P = 3; continue
            op = s.mem[c.R[c.P]]
            if op == 0x62: s.sel = s.mem[c.R[c.X]]
            if op == 0x6B:                                      # INP 3
                ready = s.key_at is not None and s.cyc >= s.key_at * s.clk
                if s.sel == 0x15: c.io_in[3] = [0x60 | ready]
                elif s.sel == 0x10: c.io_in[3] = [0x41]; s.key_at = None; s.keyread = s.cyc
            c.step(); s.cyc += 3 if op >> 4 == 0xC else 2
            if c.Q != q: q = c.Q; s.edges.append((s.cyc, q))
        else: s.end = 'time'
        s.qend = c.Q

    def call(s):
        c = s.c; m = s.mem
        t = m[c.R[3]] << 8 | m[c.R[3] + 1]; c.R[3] += 2; c.P = 3
        if t >= 0x3000: s.stack.append(c.R[3]); c.R[3] = t; return
        if t == K['K_PIN']:
            while m[c.R[3]]: s.out += chr(m[c.R[3]]); c.R[3] += 1
            c.R[3] += 1
        elif t == K['K_OUT']: s.out += chr(c.D)
        elif t == K['K_PCRLF']: s.out += '\r\n'
        elif t == K['K_PDEC']: s.out += str(c.R[13])
        elif t == K['K_SKIPSP']:
            while m[c.R[15]] == 0x20: c.R[15] += 1
        elif t == K['K_LOADF']:
            n = b''
            while m[c.R[15]] not in (0, 0x20): n += bytes([m[c.R[15]]]); c.R[15] += 1
            s.loaded = n.decode()
            if s.loaded not in s.files: s.out += '(no file %s)' % s.loaded; c.P = 5; s.stack = []; return
            d = s.files[s.loaded]; assert len(d) <= c.R[12]
            m[c.R[10]:c.R[10] + len(d)] = d; c.R[12] = len(d)
        else: raise SystemExit('call to $%04X' % t)

    def notes(s):
        """Q's edges -> [(start s, sound s, Hz)]: a note ends where Q stays low for more than 1.6 x its last high."""
        out, e, i = [], [e for e in s.edges], 0
        if e and e[0][1] == 0: e = e[1:]
        while i + 1 < len(e):
            j = i                                       # e[j] rises, e[j + 1] falls
            while j + 3 < len(e) and e[j + 2][0] - e[j + 1][0] <= 1.6 * (e[j + 1][0] - e[j][0]): j += 2
            per = (e[j][0] - e[i][0]) / ((j - i) / 2) if j > i else 2 * (e[i + 1][0] - e[i][0])
            out.append((e[i][0] / s.clk, (e[j + 1][0] - e[i][0]) / s.clk, s.clk / per))
            i = j + 2
        return out


def main():
    v = '-v' in sys.argv
    import play_gen; play_gen.main()
    prg = build.prg('play')
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e

    # every note's pitch: each octave's 12 at L16, T255 (short), legato so each is one run
    e = []
    for o in range(1, 8):
        r = Run(prg, '-n MN T120 L4 O%d C C# D D# E F F# G G# A A# B' % o)
        ns = r.notes()
        if len(ns) != 12: e.append('O%d: %d notes heard' % (o, len(ns))); continue
        for i, (t0, d, hz) in enumerate(ns):
            m = 24 + (o - 1) * 12 + i
            f = 440 * 2 ** ((m - 69) / 12)
            cents = 1200 * math.log2(hz / f)
            lim = 2
            if v and i in (0, 9): print('   %s%d %.2f Hz (want %.2f, %+.1f cents)' % (NAMES[i], o, hz, f, cents))
            if abs(cents) > lim: e.append('%s%d: %.2f Hz, want %.2f (%+.1f cents)' % (NAMES[i], o, hz, f, cents))
    report('pitch: C1-B7 within 2 cents (3.5795 MHz)', e)

    # lengths: from one note's start to the next (a C after the last marks its end); T120 L4 = 0.5 s;
    # normal sounds 7/8 of it, staccato 3/4, legato all - PLAY's own time between notes taken off the note
    e = []
    def lens(args, want, frac=None):
        r = Run(prg, args + ' C'); ns = r.notes()
        st = [t for t, _, _ in ns]
        got = [round(b - a, 4) for a, b in zip(st, st[1:])]
        if len(got) != len(want) or any(abs(a - b) > 0.003 for a, b in zip(got, want)):
            e.append('%s: from note to note %r, want %r' % (args, got, want)); return
        if frac is not None:
            snd = [d for _, d, _ in ns[:-1]]
            if any(abs(s - frac * w) > 0.016 for s, w in zip(snd, want)): e.append('%s: sounded %r' % (args, snd))
    lens('-n T120 A', [0.5], 7 / 8)
    lens('-n T120 MS A', [0.5], 3 / 4)
    lens('-n T120 ML A', [0.5], 1)
    lens('-n T60 A2', [2.0], 7 / 8)
    lens('-n T120 A8 A16 A1', [0.25, 0.125, 2.0], 7 / 8)
    lens('-n T120 A4. A4..', [0.75, 0.875], 7 / 8)
    lens('-n T120 L8 A A12 A', [0.25, 1 / 6, 0.25], 7 / 8)
    lens('-n T120 ML A R A R2 A', [1.0, 1.5, 0.5])
    lens('-n T240 ML A A A A', [0.25] * 4, 1)
    lens('-n T200 L16 O6 C D E F', [0.075] * 4, 7 / 8)
    report('lengths: tempo, L, dots, triplets, rests, MN / MS / ML', e)

    e = []
    def pitches(args):
        return [round(12 * math.log2(hz / 440) + 69) for _, _, hz in Run(prg, args).notes()]
    for args, want in [('-n O4 C C# C+ D- B-', [60, 61, 61, 61, 70]), ('-n o4 c > c < < c', [60, 72, 48]),
                       ('-n O1 C- O7 B#', [24, 107]), ('-n O9 C O0 C', [96, 24]), ('-n O4 B > > > > C', [71, 108 - 12]),
                       ('-n o4 a|b,c', [69, 71, 60])]:
        got = pitches(args)
        if got != want: e.append('%s: notes %r, want %r' % (args, got, want))
    report('sharps, flats, octaves (O, > <, the ends clamped), lower case, | and ,', e)

    e = []
    song = b'; Twinkle\r\nT200 C C G G\n;  the words  \nA A G2\n'
    r = Run(prg, 'TWINKLE', {'TWINKLE.MUS': song})
    if r.loaded != 'TWINKLE.MUS': e.append('loaded %r' % r.loaded)
    if r.out != 'Twinkle\r\n the words  \r\n': e.append('printed %r' % r.out)
    if len(r.notes()) != 7: e.append('%d notes' % len(r.notes()))
    if r.end != 'returned' or r.qend: e.append('end %s, Q %d' % (r.end, r.qend))
    r = Run(prg, 'SONGS/A.TXT', {'SONGS/A.TXT': b'C'})
    if r.loaded != 'SONGS/A.TXT' or len(r.notes()) != 1: e.append('A.TXT: %r' % r.loaded)
    r = Run(prg, '../A', {'../A.MUS': b'C'})
    if r.loaded != '../A.MUS': e.append('../A: %r' % r.loaded)
    report('a file: .MUS added, an extension kept, comments printed as reached', e)

    e = []
    r = Run(prg, '-n C D\n E X F', {})
    if "line 2: what is 'X'?" not in r.out or len(r.notes()) != 3: e.append('%r, %d notes' % (r.out, len(r.notes())))
    if r.mem[0x33F] != 1: e.append('K_STAT %d' % r.mem[0x33F])
    r = Run(prg, '-n O C', {})
    if "what is 'O'" not in r.out: e.append('O alone: %r' % r.out)
    r = Run(prg, '', {})
    if 'PLAY name' not in r.out: e.append('usage: %r' % r.out)
    report('a bad character: its line said, the rest not played; O with no number; no arguments: usage', e)

    e = []
    r = Run(prg, '-n T60 C1 C1 C1', {}, key_at=1.3)
    ns = r.notes()
    if 'Stopped.' not in r.out or r.qend or len(ns) != 1 or r.end != 'returned': e.append('%r Q %d %d notes %s' % (r.out, r.qend, len(ns), r.end))
    elif r.keyread / CLK - 1.3 > 0.01: e.append('the key seen %.3f s late' % (r.keyread / CLK - 1.3))
    report('a key stops it at once (read, Q left off)', e)

    # -s: the table worked out again for another clock - in tune and in time on that clock
    e = []
    for mhz, arg, top in [(1.79, '1.79', 1), (1.7898, '1.7898', 1), (3.5795, '3.58', 11), (4.9152, '4.92', 11), (2.0, '2', 3), (8.0, '8.00', 11), (1.0, '1', -1)]:
        r = Run(prg, '-s %s -n MN T120 L4 O7 C C# D D# E F F# G G# A A# B' % arg, mhz=mhz)
        ns = r.notes()
        for o in (1, 4):
            r2 = Run(prg, '-s %s -n MN T120 L4 O%d C F# B' % (arg, o), mhz=mhz)
            for (t, d, hz), i in zip(r2.notes(), (0, 6, 11)):
                f = 440 * 2 ** ((24 + (o - 1) * 12 + i - 69) / 12) * mhz / (int(float(arg) * 100 + 1e-6) / 100)
                if abs(1200 * math.log2(hz / f)) > 2: e.append('-s %s O%d %s: %.2f Hz, want %.2f' % (arg, o, NAMES[i], hz, f))
        if len(ns) != 12: e.append('-s %s O7: %d notes' % (arg, len(ns))); continue
        for i, (t, d, hz) in enumerate(ns):
            if i > top: continue
            f = 440 * 2 ** ((96 + i - 69) / 12) * mhz / (int(float(arg) * 100 + 1e-6) / 100)
            if abs(1200 * math.log2(hz / f)) > 2: e.append('-s %s %s7: %.2f Hz, want %.2f' % (arg, NAMES[i], hz, f))
        st = [t for t, _, _ in ns]
        gaps = [b - a for a, b in zip(st, st[1:])]
        want = 0.5 * (int(float(arg) * 100 + 1e-6) / 100) / mhz       # (-s 1.78 on a 1.7898 clock: a little fast)
        if any(abs(g - want) > 0.004 for g in gaps): e.append('-s %s: from note to note %r' % (arg, [round(g, 4) for g in gaps]))
    r = Run(prg, '-s 1.79 -n T120 ML A R A', mhz=1.79); st = [t for t, _, _ in r.notes()]
    if len(st) != 2 or abs(st[1] - st[0] - 1.0) > 0.004: e.append('-s 1.79: a rest: %r' % st)
    if st and st[0] > 0.6: e.append('-s 1.79: the first note starts at %.2f s (working out the table)' % st[0])
    d1 = Run(prg, '-n T200 O5 C E G', max_s=5).notes(); d2 = Run(prg, '-s 3.58 -n T200 O5 C E G', max_s=5).notes()
    if len(d1) != len(d2) or any(abs(1200 * math.log2(a[2] / b[2])) > 1 or abs(a[1] - b[1]) > 0.002 for a, b in zip(d1, d2)):
        e.append('-s 3.58: %r, default %r' % (d2, d1))
    r = Run(prg, '-s 1.79 TWINKLE', {'TWINKLE.MUS': b'C D'}, mhz=1.79)
    if r.loaded != 'TWINKLE.MUS' or len(r.notes()) != 2: e.append('-s then a name: %r' % r.loaded)
    for bad in ('-s', '-s x', '-s 0.5 -n C', '-s 10 -n C', '-s 1.7x -n C', '-s 12.5 -n C'):
        r = Run(prg, bad)
        if "clock, 1.00 to 9.99" not in r.out or r.notes(): e.append('%r: %r' % (bad, r.out))
    report('-s MHz: in tune (2 cents) and in time at 1.79, 2, 3.58, 4.92, 8, 1 MHz; a rest; = the default at 3.58; bad values said', e)

    print('\nPLAY: %s (%d bytes)' % ('ALL PASS' if ok else 'FAIL', len(prg)))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
