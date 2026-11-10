#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/play_gen.py - PLAY's note table -> playtab.inc.     python3 LTOS/play_gen.py [-v]

PLAY sounds a note by toggling Q every half-period. TONE's half-period, in machine cycles (8 clocks; 447,443 a
second at 3.5795 MHz), is 42 + 6 x K, and 8 more when the fraction byte's running sum carries (FRAC / 256 of the
time), so the average pitch is right to a fraction of a cycle. For each of the 84 notes C1-B7 (and a silent
entry for rests, 2,000 half-periods a second) the table holds 8 bytes:
    K + $FF (2, high first: TONE's loop counts while the high byte is not 0), FRAC, P (3), OV (2)
P = half-periods in 240 seconds, so a note of length L (4 = a quarter) at tempo T lasts P / (T x L) half-periods;
OV = the half-periods in OVH cycles, PLAY's own time between notes, taken off so the tempo stays right.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
CLK = 3579545 / 8           # machine cycles a second: the Elf2K at 3.5795 MHz (Craig's choice 2026-11-10; Emma 02 is set
                            #  to it; his board measured 1.7898 MHz that day - there PLAY is an octave low, half speed)
BASE, STEP, CARRY = 42, 6, 8
OVH = 2430                  # machine cycles PLAY spends between notes (reading, dividing): taken off each note


def entry(h):
    """A half-period of h cycles -> (K, FRAC, the half-period TONE really makes)."""
    k = max(1, int((h - BASE) // STEP))
    r = h - BASE - STEP * k
    frac = min(255, max(0, int(round(r / CARRY * 256)))) if h >= BASE + STEP else 0
    return k, frac, BASE + STEP * k + CARRY * frac / 256


def table():
    rows = []
    for i in range(84):                                  # C1 = MIDI 24
        f = 440.0 * 2 ** ((24 + i - 69) / 12)
        k, frac, real = entry(CLK / (2 * f))
        rows.append((k, frac, real, f, CLK / (2 * real)))
    k, frac, real = entry(CLK / 2000)                    # a rest: 2,000 half-periods a second
    rows.append((k, frac, real, None, None))
    return rows


NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


def main():
    rows = table()
    out = ['; playtab.inc - made by play_gen.py: do not edit. 85 x 8 bytes: K+$FF (2), FRAC, P (3), OV (2)',
           '; (C1 ... B7, then the rest). Half-period = %d + %d K (+%d on a carry) machine cycles at %d a second.'
           % (BASE, STEP, CARRY, CLK), 'PTAB:']
    for i, (k, frac, real, f, got) in enumerate(rows):
        p = int(round(240 * CLK / real))
        assert k + 0xFF <= 0xFFFF and p < 1 << 24, (i, k, p)
        name = 'rest' if f is None else '%s%d %.2f Hz -> %.2f' % (NAMES[i % 12], i // 12 + 1, f, got)
        ov = int(round(OVH / real))
        b = [(k + 0xFF) >> 8, (k + 0xFF) & 255, frac, p >> 16, (p >> 8) & 255, p & 255, ov >> 8, ov & 255]
        out.append('        DB      ' + ', '.join('0%02XH' % x for x in b) + '    ; ' + name)
        if '-v' in sys.argv and f: print('%-4s %8.2f Hz  K %4d  frac %3d  -> %8.2f Hz  %+.1f cents' % (
            NAMES[i % 12] + str(i // 12 + 1), f, k, frac, got, 1200 * __import__('math').log2(got / f)))
    out.append('; FTAB: O7\'s 12 notes\' frequencies x 16, then the rest\'s (1,000 Hz: 2,000 half-periods a second). PLAY -s')
    out.append('; works K and FRAC out from these for another clock: half-period x 32 = 320,000 x (MHz x 100) / (Hz x 16),')
    out.append('; doubled for each octave down.')
    fs = [int(round(440.0 * 2 ** ((96 + i - 69) / 12) * 16)) for i in range(12)] + [1000 * 16]
    out.append('FTAB:   DW      ' + ', '.join('%d' % x for x in fs))
    open(os.path.join(HERE, 'playtab.inc'), 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
