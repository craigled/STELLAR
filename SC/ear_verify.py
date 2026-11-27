# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check examples/eartest.sc (the EF3 ear test) in the simulator: V0061.37 as flashed (the docx),
a VT100 screen, and EF3 driven the way an ear would drive it.

  1. quiet; a 700 Hz square wave on EF3 for 300 ms (a raw comparator ear hearing a tone); quiet
     500 ms; a 100 ms burst: Sounds 2, quiet at the end, the EF row back to '.'.
  2. a "clap" from a raw sound module: three 20 ms pulses 40 ms apart - ONE sound (hold 2).
  3. EF3 held on (JP6 still fitted, or a tone detector hearing a steady tone): SOUND, the EF row
     shows 3 '*', the level bar full, Sounds 1.
  4. 'i' flips the polarity: the held line reads quiet, the EF row still shows the line itself,
     the bar is empty; 'c' clears the count; 'q' quits (halts, no VM error).

    python3 ear_verify.py [--show]
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import guide_check as G
import opcode_sweep as S
import rtc_verify as V
import scc

SEC = V.SEC                                 # emulated 1802 instructions a second
SRC = open(os.path.join(HERE, 'examples', 'eartest.sc')).read()


class Ear:
    """EF3 over time: [(until_second, mode)], mode 'quiet' | 'tone' (700 Hz) | 'on'."""
    def __init__(s, plan): s.plan = plan
    def at(s, steps):
        t = steps / SEC
        for until, mode in s.plan:
            if t < until:
                if mode == 'tone': return int(t * 1400) & 1
                return 1 if mode == 'on' else 0
        return 0


def run(plan, keys_at=(), seconds=4.0):
    c0, em, labels, data = scc.compile_source(SRC, 'eartest')
    pokes = [(a + i, b) for a, bs, _, _ in em for i, b in enumerate(bs)] + \
            [(0x4000 + a + i, b) for a, d in data.items() for i, b in enumerate(d)]
    img = bytearray(S.image('37'))
    c = S.boot(bytes(img), pokes, keys=b'')
    rtc = V.DS12887(c)
    c.io_in[3] = V.Port3In(c.io_in[3], c.io_out[2], rtc)
    c.io_out[3] = V.Port3Out(c.io_out[2], rtc)
    ear, keys, halted = Ear(plan), sorted(keys_at), False
    for k in range(int(seconds * SEC)):
        if k % 16 == 0:
            c.EF = [0, 0, ear.at(k), 0]
            while keys and k >= keys[0][0] * SEC: c.io_in[3].u.q.extend(keys.pop(0)[1])
        if not c.step() or c.R[c.P] == S.EXIT_IDL + 1: halted = True; break
    vt = G.VT(); vt.feed(bytes(c.io_out[3]).decode('latin1'))
    return [vt.row(i) for i in range(24)], halted, c.M[0x304F], vt.bad


def num(row):
    w = row[11:].split()
    return int(w[0]) if w and w[0].isdigit() else None


def main():
    show = '--show' in sys.argv
    ok = True
    def check(name, good, detail=''):
        nonlocal ok
        print('%-62s %s' % (name, 'OK' if good else 'FAIL ' + detail)); ok &= bool(good)
    def shown(rows):
        if show: print('\n'.join(rows).rstrip('\n') + '\n')

    rows, halted, err, bad = run([(1.5, 'quiet'), (1.8, 'tone'), (2.3, 'quiet'), (2.4, 'tone')], seconds=3.0)
    shown(rows)
    check('1 runs, no VM error, clean VT100 output', not halted and not err and not bad, 'halted=%s err=%02X bad=%s' % (halted, err, bad))
    check('1 title, EF row all quiet', rows[0].startswith('STELLAR EAR TEST') and rows[2].startswith('EF lines   1 .  2 .  3 .  4 .'), rows[2])
    check('1 two tone bursts: Sounds 2', num(rows[8]) == 2, rows[8])
    check('1 quiet again at the end, bar empty', 'quiet' in rows[4] and rows[6] == 'Level      [' + '.' * 20 + ']', rows[4] + ' | ' + rows[6])

    clap = [(1.0, 'quiet'), (1.02, 'on'), (1.06, 'quiet'), (1.08, 'on'), (1.12, 'quiet'), (1.14, 'on')]
    rows, halted, err, bad = run(clap, seconds=2.0)
    shown(rows)
    check('2 a chattering clap counts once (hold 2)', num(rows[8]) == 1 and 'quiet' in rows[4], rows[8] + ' | ' + rows[4])

    rows, halted, err, bad = run([(1.0, 'quiet'), (9, 'on')], seconds=2.0)
    shown(rows)
    check('3 held on: SOUND lit', 'SOUND' in rows[4], rows[4])
    check('3 held on: EF row shows 3 *', rows[2].startswith('EF lines   1 .  2 .  3 *  4 .'), rows[2])
    check('3 held on: level bar full', rows[6] == 'Level      [' + '#' * 20 + ']', rows[6])
    check('3 held on: Sounds 1', num(rows[8]) == 1, rows[8])

    rows, halted, err, bad = run([(9, 'on')], keys_at=[(1.0, b'i')], seconds=2.0)
    shown(rows)
    check('4 inverted: the held line reads quiet, Polarity inverted', 'quiet' in rows[4] and 'inverted' in rows[10], rows[4] + ' | ' + rows[10])
    check('4 inverted: the EF row still shows the line itself (3 *)', rows[2].startswith('EF lines   1 .  2 .  3 *  4 .'), rows[2])
    check('4 inverted: level bar empty, Sounds 0', rows[6] == 'Level      [' + '.' * 20 + ']' and num(rows[8]) == 0, rows[6] + ' | ' + rows[8])
    rows, halted, err, bad = run([(0.5, 'quiet'), (0.8, 'on'), (9, 'quiet')], keys_at=[(1.2, b'c')], seconds=1.8)
    check('4 c clears the count', num(rows[8]) == 0 and 'normal' in rows[10], rows[8])
    rows, halted, err, bad = run([(9, 'on')], keys_at=[(1.0, b'i'), (1.5, b'q')], seconds=2.5)
    check('4 q quits: halts with no VM error', halted and not err, 'halted=%s err=%02X' % (halted, err))

    print('ear test: %s' % ('ALL OK' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
