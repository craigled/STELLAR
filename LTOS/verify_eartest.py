# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""EARTEST.PRG in a cycle-counting 1802 (2 machine cycles an instruction, 3 for $Cx; MHz x 125,000 a second), with
LTOS's SCRT (R4 / R5 / R6) and a 16C450 UART that takes a character every ~1 ms (9600 baud).

A sound detector on EF3 is played in Python: as sound at given times (the meter), or as a detector that hears Q's
tone - after an attack, staying on for a release - only at the pitches it likes (the tone test and the sweep).
Checked: every meter-loop path the same length; 1,000 samples a second; sound lengths and counts; the bar; the
tone test's attack / release; the sweep's best pitches; -i; Esc; the usage. At 1.79 and 3.58 MHz.

    python3 LTOS/verify_eartest.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
from cpu1802 import CPU
import build

K_PIN, K_PDEC, K_PCRLF, K_SKIPSP, K_OUT = 0x312, 0x315, 0x31E, 0x321, 0x332
VERB = '-v' in sys.argv


class Run:
    """sound(t, run) -> True while the detector hears sound (t in seconds); keys: [(seconds, byte)]."""
    def __init__(s, prg, args, mhz=1.79, sound=None, keys=(), max_s=30, ef=3, low=True, baud=9600):
        s.clk = mhz * 1e6 / 8
        s.mem = bytearray(65536)
        lo = prg[0] << 8 | prg[1]; start = prg[4] << 8 | prg[5]
        s.mem[lo:lo + len(prg) - 6] = prg[6:]
        a = 0x7000; s.mem[a:a + len(args) + 1] = args.encode() + b'\0'
        c = s.c = CPU(s.mem); c.P = 3; c.X = 2; c.R[2] = 0x7DFF; c.R[3] = start; c.R[15] = a; c.Q = 0
        s.out, s.cyc, s.stack, s.sel, s.end = '', 0, [], 0, None
        s.qedges = []                                   # (cycle, q)
        s.mlk = []                                      # cycles at each meter sample
        syms = build.assemble('eartest')[1]; s.syms = syms
        keys = sorted(keys); ki = 0
        thre_at, tsr_free, chcyc = 0, 0, s.clk * 10 / baud      # the 16C450: a holding register + the shifter
        sound = sound or (lambda t, run: False)
        q = 0
        while s.cyc < max_s * s.clk:
            t = s.cyc / s.clk
            on = bool(sound(t, s))
            c.EF[ef - 1] = 1 if on == low else 0        # EF[] = 1: the line pulled low (B branches)
            if c.P == 4: s.call(); continue
            if c.P == 5:
                if not s.stack: s.end = 'returned'; break
                c.R[3] = c.R[6]; c.R[6] = s.stack.pop(); c.P = 3; continue
            pc = c.R[c.P]; op = s.mem[pc]
            if pc == syms['MLK']: s.mlk.append(s.cyc)
            if op == 0x62: s.sel = s.mem[c.R[c.X]]
            if op == 0x63 and s.sel == 0x10:
                s.out += chr(s.mem[c.R[c.X]])
                if s.cyc >= tsr_free: thre_at, tsr_free = s.cyc, s.cyc + chcyc
                else: thre_at, tsr_free = tsr_free, tsr_free + chcyc
            if op == 0x6B:
                ready = ki < len(keys) and keys[ki][0] <= t
                if s.sel == 0x15: c.io_in[3] = [(0x20 if s.cyc >= thre_at else 0) | ready]
                elif s.sel == 0x10:
                    c.io_in[3] = [keys[ki][1] if ready else 0]
                    if ready: ki += 1
            c.step(); s.cyc += 3 if op >> 4 == 0xC else 2
            if c.Q != q: q = c.Q; s.qedges.append((s.cyc, q))
        else: s.end = 'time'

    def call(s):
        c = s.c; m = s.mem
        t = m[c.R[3]] << 8 | m[c.R[3] + 1]; c.R[3] += 2; c.P = 3
        if 0x3000 <= t < 0x8000:                         # SCRT: R6 = the return (inline data), the old R6 stacked
            s.stack.append(c.R[6]); c.R[6] = c.R[3]; c.R[3] = t; return
        if t == K_PIN:
            while m[c.R[3]]: s.out += chr(m[c.R[3]]); c.R[3] += 1
            c.R[3] += 1
        elif t == K_OUT: s.out += chr(c.D)
        elif t == K_PCRLF: s.out += '\r\n'
        elif t == K_PDEC: s.out += str(c.R[13])
        elif t == K_SKIPSP:
            while m[c.R[15]] == 0x20: c.R[15] += 1
        else: raise SystemExit('call to $%04X' % t)
        s.cyc += 200                                    # (the kernel's own time, about)

    def detector(s, t, attack, release):
        """a detector on Q's tone: on once the tone has sounded `attack` s, off `release` s after it stops."""
        cy = t * s.clk; e = s.qedges; gap = 0.005 * s.clk
        if not e: return False
        if cy - e[-1][0] > gap:                                  # the tone has stopped: at e[-1]
            return cy - e[-1][0] < release * s.clk and s.run_len(len(e) - 1) >= attack * s.clk
        return s.run_len(len(e) - 1) + (cy - e[-1][0]) >= attack * s.clk

    def run_len(s, i):
        """the cycles from the start of the tone that edge i belongs to, to edge i"""
        e = s.qedges; gap = 0.005 * s.clk; j = i
        while j > 0 and e[j][0] - e[j - 1][0] < gap: j -= 1
        return e[i][0] - e[j][0]


fails = 0
def check(name, ok, got=''):
    global fails
    print('  %-58s %s' % (name, 'ok' if ok else 'FAIL  ' + str(got)))
    if not ok: fails += 1


def lines(out):
    """the meter's lines (each starts with a CR) -> [(pct, peak, sounds, last)]"""
    return [tuple(map(int, m)) for m in re.findall(r'\r\[[#-]{20}\]\s*(\d+)%  peak\s*(\d+)%  sounds\s*(\d+)  last\s*(\d+) ms', out)]


def main():
    prg = build.prg('eartest')
    syms = build.assemble('eartest')[1]
    print('EARTEST.PRG %d bytes' % len(prg))
    check('the loops in one page each', syms['TL'] >> 8 == (syms['TLEND'] - 1) >> 8 and syms['ML'] >> 8 == (syms['MLEND'] - 1) >> 8)
    check('its variables below $6C00', syms['VEND'] <= 0x6C00)

    for mhz in (1.79, 3.58):
        cl = '-c %.2f' % mhz
        print('-- meter, %s MHz' % mhz)
        # sounds: 200 ms at 0.5 s, 50 ms at 1.0 s, 1000 ms at 1.5 s, then a sound that flickers (on 3 ms / off 2 ms) 300 ms
        def snd(t, r):
            if 0.5 <= t < 0.7 or 1.0 <= t < 1.05 or 1.5 <= t < 2.5: return True
            if 3.0 <= t < 3.3: return (t - 3.0) % 0.005 < 0.003
            return False
        r = Run(prg, cl, mhz, snd, keys=[(3.8, 0x1B)], max_s=6)
        check('Esc quits', r.end == 'returned', r.end)
        d = [b - a for a, b in zip(r.mlk, r.mlk[1:])]
        same = [x for x in d if x == d[0]]
        # (a window's line is made between some samples; every other gap is the loop)
        common = max(set(d), key=d.count)
        odd = [x for x in d if abs(x - common) > 8 and x < common * 3]      # (MFR's carry: 8 more)
        check('the meter loop: every sample the same cycles (%d, +-8)' % common,
              len(odd) <= 12 and all(abs(x - common) <= 8 or x in odd or x > common * 3 for x in d), sorted(set(odd)))
        rate = r.clk / common
        check('1,000 samples a second (%.1f)' % rate, 990 <= rate <= 1010, rate)
        fmt = sorted(x - common for x in d if x > common * 3)
        if fmt: print('    (a line takes %d-%d cycles to make)' % (fmt[0], fmt[-1]))
        L = lines(r.out)
        if VERB: print(L)
        check('a line every 0.1 s (%d in 3.8 s)' % len(L), 33 <= len(L) <= 38, len(L))
        lasts = []
        for x in L:
            if not lasts or x[3] != lasts[-1]: lasts.append(x[3])
        lasts = [x for x in lasts if x]
        check('the sounds\' lengths: 200, 50, 1000, 300 ms (%s)' % lasts,
              len(lasts) == 4 and all(abs(a - b) <= max(4, b * 0.03) for a, b in zip(lasts, (200, 50, 1000, 300))), lasts)
        check('4 sounds counted', L[-1][2] == 4, L[-1])
        check('100% while the long sound plays', any(x[0] == 100 for x in L), [x[0] for x in L])
        check('the peak 100%', L[-1][1] == 100, L[-1])
        mid = [x[0] for x in L[5:7]]
        bar = re.findall(r'\r\[([#-]{20})\]\s*100%', r.out)
        check('the bar full at 100%', bar and bar[0] == '#' * 20, bar[:1])

    print('-- -i (the line high = sound), and C clears')
    r = Run(prg, '-c 1.79 -i', 1.79, lambda t, r: 0.3 <= t < 0.5, keys=[(0.9, ord('c')), (1.3, 0x1B)], max_s=3, low=False)
    L = lines(r.out)
    check('-i: a 200 ms sound heard', any(x[3] in range(196, 205) for x in L), L)
    check('C clears the counts', L[-1][2] == 0 and L[-1][3] == 0, L[-1])
    check('-i shown', '(-i: high = sound)' in r.out)

    print('-- the tone test (a detector: on 12 ms after the tone starts, off 40 ms after it stops)')
    for mhz in (1.79, 3.58):
        def det(t, r): return r.detector(t, 0.012, 0.040)
        r = Run(prg, '-c %.2f' % mhz, mhz, det, keys=[(0.3, ord('t')), (6.5, 0x1B)], max_s=9)
        tl = re.findall(r'  (\d): heard after (\d+) ms, on (\d+)% of the tone, off (\d+) ms after it', r.out)
        if VERB: print(r.out)
        check('%s MHz: 5 tries reported' % mhz, len(tl) == 5, r.out[-400:])
        if tl:
            a = [int(x[1]) for x in tl]; p = [int(x[2]) for x in tl]; f = [int(x[3]) for x in tl]
            check('  heard after ~12 ms (%s)' % a, all(10 <= x <= 15 for x in a), a)
            check('  on ~96%% of the tone (%s)' % p, all(94 <= x <= 97 for x in p), p)
            check('  off ~40 ms after (%s)' % f, all(37 <= x <= 44 for x in f), f)
        # the pitch of the tone
        e = [b[0] - a[0] for a, b in zip(r.qedges, r.qedges[1:]) if b[0] - a[0] < r.clk * 0.01]
        hz = r.clk / (2 * sorted(e)[len(e) // 2])
        check('  the tone %.0f Hz (700)' % hz, abs(hz - 700) / 700 < 0.03, hz)

    print('-- not heard; still on')
    r = Run(prg, '-c 1.79', 1.79, lambda t, r: False, keys=[(0.3, ord('T')), (5.5, 0x1B)], max_s=8)
    check('nothing on EF3: "not heard" 5 times', r.out.count('not heard') == 5, r.out[-300:])
    r = Run(prg, '-c 1.79', 1.79, lambda t, r: t > 0.5, keys=[(0.3, ord('T')), (5.5, 0x1B)], max_s=8)
    check('always on: "STILL ON" and "sound in the quiet before"', 'STILL ON' in r.out and 'sound in the quiet before' in r.out, r.out[-300:])

    print('-- the sweep (a detector that hears 500-1000 Hz only)')
    def pitchdet(t, r):
        e = r.qedges
        if len(e) < 3 or (t * r.clk - e[-1][0]) > r.clk * 0.01: return False
        hz = r.clk / (2 * (e[-1][0] - e[-2][0]))
        return 480 <= hz <= 1050
    r = Run(prg, '-c 1.79', 1.79, pitchdet, keys=[(0.3, ord('s')), (11.5, 0x1B)], max_s=14)
    sw = re.findall(r'\s+(\d+) Hz \[([#-]{20})\]\s+(\d+)%', r.out)
    if VERB: print(r.out)
    got = {int(f): int(p) for f, b, p in sw}
    check('10 pitches', len(sw) == 10, sw)
    check('heard at 500-1000 Hz, not 300, 400, 1200-2000 (%s)' % got,
          all(got.get(f, 0) >= 90 for f in (500, 600, 700, 800, 1000)) and all(got.get(f, 100) == 0 for f in (300, 400, 1200, 1500, 2000)), got)

    print('-- the usage')
    for a in ('-x', '-e 5', '-f 100', '-c 12'):
        r = Run(prg, a, 1.79, max_s=1)
        check('%-8s -> the usage' % a, 'EARTEST [-e' in r.out and r.end == 'returned' and r.mem[0x33F] == 1, r.out[:80])

    print('ALL PASS' if not fails else '%d FAILED' % fails)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
