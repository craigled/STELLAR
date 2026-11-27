# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The Tiny Stellar C examples for /SRC (LTOS/src/*.SC, in the system bundle): each compiled by tsc (SC.PRG's
reference - LTOS/verify_sc.py checks SC.PRG makes the same .STL on the card), run on STELLAR V0061.37 in the
simulator with keys typed where it reads them, and what it prints checked. Each fits SC.PRG's 3 KB and the
template puts it in /SRC; no name is a program's or app's already in the system (typing it would run that).

    python3 LTOS/verify_scex.py [-v]
"""
import os, sys, re
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'SC')); sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import build, tsc, tsc_verify as T, card_layout
import hwio_verify as H


def guess_keys(name):
    """GUESS's secret for this name (its generator, as the program works it out), and keys that find it"""
    seed = 1802
    for c in name: seed = (seed * 31 + c) & 0xFFFF
    seed = (seed * 75 + 74) & 0xFFFF
    secret = seed % 100 + 1
    lo, hi = max(1, secret - 7), min(100, secret + 9)
    keys = name + b'\r' + b''.join(b'%d\r' % g for g in (lo, hi, secret) if g != secret) + b'%d\r' % secret
    return secret, keys


def main():
    ok = True
    v = '-v' in sys.argv
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + str(x)[:200]) for x in e[:8]]; ok &= not e
    files = dict((n[:8].decode().strip(), d.decode('latin1')) for n, d in build.srcfiles())
    secret, gk = guess_keys(b'Craig')
    tests = {
        'FIRST': (b'', ['Hello from Tiny Stellar C on the COSMAC 1802!', '2 + 3 * 4 = 14']),
        'COUNT': (b'', ['Up:   1 2 3 4 5 6 7 8 9 10', 'Down: 10 9 8 7 6 5 4 3 2 1', '  9 18 27 36 45 54 63 72 81']),
        'FIZZBUZZ': (b'', ['1 2 Fizz 4 Buzz Fizz 7 8 Fizz Buzz', '11 Fizz 13 14 FizzBuzz', '97 98 Fizz Buzz']),
        'FUNCS': (b'', ['gcd(1802, 1806) = 2', 'gcd(144, 60) = 12', '16384 32768', 'sqrt(1802) = 42, sqrt(65535) = 255']),
        'SIEVE': (b'', ['2 3 5 7 11 13', '599', '109 primes below 600.']),
        'TEMPS': (b'', ['  0    -17', ' 30    -1', ' 50    10', '210    98', 'Water boils at 212 F = 100 C.']),
        'GUESS': (gk, ['Type your name and press Enter: Craig', 'Too low.', 'Too high.',
                       'Right! It was %d - you took 3 tries.' % secret]),
        'PRIMEGEN': (b'3\r60\r', ['Low limit:  3', '3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59', 'Done.']),
        'BOXES': (b'x', ['\x1b[2;5H+----------------------------+', '\x1b[6;11HTiny Stellar C', '\x1b[10;50H***********',
                         'Press a key...\x1b[2J\x1b[H']),
        'OXO': (b'5139n', ['TIC-TAC-TOE: you are X', ' O | 2 | X', 'I win.  Again? (Y/N)']),
        'GLIDER': (b'    q', ['THE GAME OF LIFE', 'Generation 4, 8 alive']),
        'BUBBLE': (b'abc\rx', ['BUBBLE SORT', 'Sorted: ', ' swaps.']),
        'PIDIGITS': (b'20\r', ['how many digits (10-50)? 20', '3.1415926535897932384']),
        'MOONLAND': (b'0\r0\r0\r40\r40\r40\r40\r30\r20\r20\r20\r20\r18\r17\r17\r17\r17\r17\r17\r17\r17\r17\r17\r17\r17\rn',
                     ['LUNAR LANDER - you are 6000 m up', '   10    5320      76    400', 'Touch down at 240 s, 56 m/s: a new crater']),
        'TIMENOW': (None, ["THE ELF2K'S CLOCK - hold INPUT to stop", '2026-10-04  14:23:', 'Stopped.']),
    }
    e = []
    if sorted(files) != sorted(tests): e.append('examples %s, tests for %s' % (sorted(files), sorted(tests)))
    where, _ = card_layout.load()
    taken = {n.split('.')[0] for n in where if not n.endswith('.SC')} | {n[:8].decode().strip() for n, _ in build.samples()}
    for k in files:
        if where.get(k + '.SC') != '/SRC': e.append('%s.SC not in /SRC in the template' % k)
        if k in taken: e.append('%s: a program of that name is in the system already' % k)
    report('%d examples, each in the template\'s /SRC, no name a program\'s already' % len(files), e)

    for k in sorted(files):
        e = []
        try:
            stl = tsc.compile_text(files[k])
        except tsc.Error as x:
            report('%s.SC' % k, ['tsc: %s' % x]); continue
        keys, want = tests.get(k, (b'', []))
        if keys is None:                    # the hardware: a clock chip, INPUT held after a while (SC/hwio_verify)
            out = H.run(T.pokes_tsc(stl), press=(3_000_000, 9_000_000), cap=12_000_000)[0]
        else: out, _ = T.run(T.pokes_tsc(stl), keys)
        flat = out.replace('\r', '')
        for w in want:
            if w not in flat: e.append('%r not in what it printed' % w)
        if '\r\n' not in files[k]: e.append('not CR LF lines')
        if v: print(flat)
        lines = len(files[k].split('\n'))
        report('%s.SC (%d lines): compiled, run, prints %s' % (k, lines, want[-1][:50].replace('\x1b', 'ESC')), e)
    print('\nSTELLAR C EXAMPLES: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
