#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The Elf2K's own hardware from Tiny Stellar C (SC/tsc.py, and so SC.PRG) and Stellar C (scc.py) alike, on the
firmware (V0061.37) with the DS12887 model (Firmware-Math/rtc_verify.py):

  * rtc(0) .. rtc(6): the BIOS's 2026-10-04 14:23:07 (a Sunday: weekday 0); rtc(7) 1 - and 0 with no clock chip
  * q(n): the Q line on for q(1), off for q(0); Tiny Stellar C takes a constant (if (x) q(1); else q(0);)
  * ef(n): 1 for each EF line that is on, 0 for the others
  * waitef(4): waits until EF4 has gone on and off again (one press of INPUT), then goes on

Each program runs from both compilers' code and must give the same.     python3 SC/hwio_verify.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, '..', 'Firmware-Math')]
import tsc, tsc_verify as TV
import rtc_verify as R
import opcode_sweep as S

BIOS = {0x00: 7, 0x02: 23, 0x04: 14, 0x06: 1, 0x07: 4, 0x08: 10, 0x09: 54,      # binary, 24 h, from 1972
        0x0A: 0x20, 0x0B: 0x06, 0x0C: 0x00, 0x0D: 0x80}


def run(pokes, present=True, ef=(0, 0, 0, 0), press=None, cap=20_000_000):
    """-> (what it printed, Q at the end, the step it finished at). press: (on at step, off at step) for EF4."""
    c = S.boot(bytes(S.image('37')), pokes, keys=b'')
    rtc = R.DS12887(c, present)
    for n, v in BIOS.items(): rtc.r[n] = v
    c.io_in[3] = R.Port3In(c.io_in[3], c.io_out[2], rtc)
    c.io_out[3] = R.Port3Out(c.io_out[2], rtc)
    c.EF = list(ef)
    k = 0
    for k in range(cap):
        if press:
            if k == press[0]: c.EF[3] = 1
            if k == press[1]: c.EF[3] = 0
        if not c.step() or c.R[c.P] == S.EXIT_IDL + 1: break
    return bytes(c.io_out[3]).decode('latin1'), c.Q, k


def both(src, **kw):
    return run(TV.pokes_tsc(tsc.compile_text(src)), **kw), run(TV.pokes_scc(src), **kw)


def main():
    ok = True
    def check(label, src, want, **kw):
        nonlocal ok
        a, b = both(src, **kw)
        e = []
        if a[0] != b[0] or a[1] != b[1]: e.append('tsc %r Q%d, scc %r Q%d' % (a[0], a[1], b[0], b[1]))
        if not want(a): e.append('got %r, Q %d (step %d)' % (a[0], a[1], a[2]))
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    CLOCK = '''void main() { printu(rtc(7)); putc(' '); printu(rtc(6)); putc('-'); printu(rtc(5)); putc('-');
        printu(rtc(4)); putc(' '); printu(rtc(2)); putc(':'); printu(rtc(1)); putc(':'); printu(rtc(0));
        putc(' '); printu(rtc(3)); }'''
    check('rtc(): 1 2026-10-4 14:23:7, weekday 0 (Sunday)', CLOCK, lambda r: r[0] in ('1 2026-10-4 14:23:7 0', '1 2026-10-4 14:23:8 0'))
    check('rtc(7) with no clock chip: 0', 'void main() { if (rtc(7)) print("a clock"); else print("none"); }',
          lambda r: r[0] == 'none', present=False)
    check('q(1): Q on', 'void main() { q(1); }', lambda r: r[1] == 1)
    check('q(0) after q(1): Q off', 'void main() { q(1); q(0); }', lambda r: r[1] == 0)
    check('if (x) q(1); else q(0); with x = 5: on',
          'u16 x = 5;\nvoid main() { if (x) q(1); else q(0); printu(x); }', lambda r: r[1] == 1 and r[0] == '5')
    EF = 'void main() { printu(ef(1)); printu(ef(2)); printu(ef(3)); printu(ef(4)); if (ef(2) && !ef(1)) print(" yes"); }'
    check('ef(n), EF2 and EF4 on: 0101 yes', EF, lambda r: r[0] == '0101 yes', ef=(0, 1, 0, 1))
    check('ef(n), EF1 on: 1000', EF, lambda r: r[0] == '1000', ef=(1, 0, 0, 0))
    check('waitef(4): goes on only after INPUT is pressed and let go (on at 300,000 steps, off at 600,000)',
          'void main() { print("a"); waitef(4); print("b"); }', lambda r: r[0] == 'ab' and r[2] > 600_000,
          press=(300_000, 600_000))
    print('ALL PASS' if ok else 'SOME FAILED')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
