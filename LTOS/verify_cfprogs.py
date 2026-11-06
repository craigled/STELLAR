# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The native CF programs (CFTEST, CFSCAN) in the simulator: the real Elf2K ROM v120, the CF card model, the DS12887
clock; started as the monitor's CALL 3000 would, with STELLAR in RAM (it must not be touched).

    python3 LTOS/verify_cfprogs.py [-v]
"""
import os, sys, re
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import cftest_verify as CV
import opcode_sweep as S
import build


def prog(name):
    mem, syms = build.native_prog(name)
    return {a: b for a, b in mem.items() if a >= 0x3000}


class GlitchCF(CV.CF):
    """A card that sometimes misreads: byte 0 of the reads numbered in `rg` comes back $00 (as Craig's SDCFB-8 did);
    the writes numbered in `wb` store byte 7 wrong."""
    def __init__(s, rg=(), wb=(), **k):
        super().__init__(**k); s.rg, s.wb, s.nr, s.nw, s.g = set(rg), set(wb), 0, 0, False
    def command(s, v):
        if v == 0x20: s.nr += 1; s.g = s.nr in s.rg
        if v == 0x30: s.nw += 1
        return super().command(v)
    def read(s, r):
        if r == 0 and s.mode == 'out' and s.pos == 0 and s.g and s.status & 0x08:
            s.g = False; super().read(r); return 0
        return super().read(r)
    def write(s, r, v):
        if r == 0 and s.mode == 'in' and len(s.wbuf) == 7 and s.nw in s.wb: v ^= 1
        return super().write(r, v)


def clock(cf, start=23 * 60 + 58, per=150, bcd=True, jitter=0):
    """A DS12887 whose time moves on with the card's work: a minute every `per` sectors read or written. jitter:
    every jitter-th reading of the minutes is a minute early (a misread)."""
    n = [0]
    def r(reg):
        m = (start + len(cf.log) // per) % 1440
        if reg == 2 and jitter:
            n[0] += 1
            if n[0] % jitter == 0: m = (m - 1) % 1440
        v = {0x0A: 0, 0x0B: 0x02 if bcd else 0x06, 0x02: m % 60, 0x04: m // 60}.get(reg, 0)
        return int('%d' % v, 16) if bcd and reg in (2, 4) else v
    return r


def run(mem, cf, keys, cap=900_000_000, rtc=None, later=()):
    e = V.Elf2K(cf, keys=keys, later=later); e.rtc = rtc
    for a, b in mem.items(): e.c.M[a] = b
    stl = bytes(e.c.M[0:0x3000])
    st = e.call(0x3000, cap=cap)
    return e, st, e.text(), bytes(e.c.M[0:0x3000]) == stl


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    m = prog('cftest')
    n = 16384
    cf = CV.CF(sectors=n)
    before = {l: cf.sector(l) for l in (0, n - 1, 0x1234)}
    e, st, t, same = run(m, cf, b'\rY' + b'R' + b'0\r' + b'40000\r' + b'1234\rY' + b'x')
    E = []
    if st != 'idle' or 'CFTEST finished.' not in t: E.append('did not finish: %s %r' % (st, t[-200:]))
    if t.count('ALL PASSED') != 2: E.append('ALL PASSED %d times' % t.count('ALL PASSED'))
    for w in ('SanDisk SDCFB-128', 'Size: 8 MB ($0004000 sectors)', 'the last one, $0003FFF',
              'not sector 0', 'the card has only $0004000 sectors', 'Pattern 5: pseudo-random', '6 writes, 8 reads of sector $0001234'):
        if w not in t: E.append('missing %r' % w)
    writes = sorted(set(l for k, l in cf.log if k == 'write'))
    if writes != [0x1234, n - 1]: E.append('wrote %s' % writes)
    for l, b in before.items():
        if cf.sector(l) != b: E.append('sector $%X changed' % l)
    if not same: E.append('STELLAR in RAM changed')
    if '-v' in sys.argv: print(t)
    report('CFTEST, a good card: the last sector and $1234 - 5 patterns each, put back exactly; sector 0 and $40000 '
           'refused; STELLAR in RAM untouched; back to the monitor', E)

    cf = CV.CF(sectors=n, corrupt=(n - 1, 300)); orig = cf.sector(n - 1)
    e, st, t, same = run(m, cf, b'\rYx'); E = []
    if t.count('MISMATCH at byte 300') != 6 or '6 FAILED' not in t: E.append(repr(t[-500:]))
    cf = CV.CF(present=False)
    e, st, t, same = run(m, cf, b'')
    if 'no answer. Is a card in the socket?' not in t or st != 'idle': E.append('no card: %s %r' % (st, t[-150:]))
    cf = CV.CF(sectors=n)
    e, st, t, same = run(m, cf, b'Q\r')
    if 'CFTEST finished.' not in t or any(k == 'write' for k, _ in cf.log): E.append('Q: %r' % t[-150:])
    report('CFTEST: a card that flips a bit - every pattern and the restore "MISMATCH at byte 300", 6 FAILED; no card; '
           'Q writes nothing', E)

    m = prog('cfscan')
    n = 2048
    cf = CV.CF(sectors=n)
    e, st, t, same = run(m, cf, b'R\r\rY', rtc=clock(cf, jitter=5), later=[('S = scan again', b'x')])
    E = []
    if st != 'idle' or 'CFSCAN finished.' not in t: E.append('did not finish: %s %r' % (st, t[-300:]))
    for w in ('Scanning $0000000 to $00007FF', 'Scan complete.', 'Scanned $0000000 up to $0000800 (1 MB) in 0:1',
              'each read once: NO BAD SECTORS.', '100%', ' gone ', ' left '):
        if w not in t: E.append('missing %r' % w)
    reads = [l for k, l in cf.log if k == 'read']
    if any(k == 'write' for k, _ in cf.log): E.append('it wrote')
    if sorted(set(reads)) != list(range(n)): E.append('read %d sectors' % len(set(reads)))
    if not same: E.append('STELLAR in RAM changed')
    if '-v' in sys.argv: print(t)
    report('CFSCAN read scan, the whole 1 MB card: every sector read, nothing written, 100%, the clock past '
           'midnight; STELLAR untouched', E)

    cf = CV.CF(sectors=n, corrupt=(0x120, 300))
    before = {l: cf.sector(l) for l in range(0xF0, 0x150)}
    e, st, t, same = run(m, cf, b'W100\r13F\rY', rtc=clock(cf, 600), later=[('S = scan again', b'x')])
    E = []
    if st != 'idle' or 'CFSCAN finished.' not in t: E.append('did not finish: %s %r' % (st, t[-300:]))
    for w in ('BAD sector $0000120: reading pattern 1 back - read back different at byte 300: $',
              '; COULD NOT BE PUT BACK', 'Scan complete.', 'each written 3 times and read 5 times: 1 BAD: $0000120'):
        if w not in t: E.append('missing %r' % w)
    if t.count('BAD sector') != 1: E.append('%d BAD lines' % t.count('BAD sector'))
    w = sorted(set(l for k, l in cf.log if k == 'write'))
    if w != list(range(0x100, 0x140)): E.append('wrote %s..%s (%d)' % (hex(w[0]), hex(w[-1]), len(w)))
    for l, b in before.items():
        x = bytearray(b)
        if l == 0x120: x[300] ^= 0x10
        if cf.sector(l) != bytes(x): E.append('sector $%X is not as it was' % l)
    if not same: E.append('STELLAR in RAM changed')
    if '-v' in sys.argv: print(t)
    report('CFSCAN write test $100-$13F, a card that corrupts byte 300 of $120: 1 BAD (pattern 1, byte 300, not put '
           'back); every other sector exactly as it was; nothing outside the range written', E)

    cf = GlitchCF(sectors=n, rg=(3, 9, 30, 45, 60, 75, 90, 105, 120, 135, 150), wb=(21,))
    before = {l: cf.sector(l) for l in range(0xF0, 0x150)}
    e, st, t, same = run(m, cf, b'W100\r13F\rY', rtc=clock(cf, 600), later=[('S = scan again', b'x')])
    E = []
    for w in ('read glitch, sector $00001', '(more read glitches are counted, not shown)',
              'NO BAD SECTORS.', ' read glitch(es)', '1 sector(s) had to be written back more than once',
              'Clock: started at 10:00, last read at 10:'):
        if w not in t: E.append('missing %r' % w)
    if t.count('read glitch, sector') != 8: E.append('%d glitch lines' % t.count('read glitch, sector'))
    if any(cf.sector(l) != b for l, b in before.items()): E.append('a sector is not as it was')
    if '-v' in sys.argv: print(t)
    report('CFSCAN write test on a card that misreads byte 0 now and then (the saving read too) and spoils one put-back write: read '
           'glitches (8 shown), the put-back written again, NO BAD SECTORS, every sector as it was', E)

    E = []
    cf = CV.CF(sectors=n)
    e, st, t, same = run(m, cf, b'R10\r\rYQ', rtc=lambda r: 0xFF, later=[('S = scan again', b'x')])
    if 'Stopped. To go on later, start at sector $0000011.' not in t or ' gone' in t: E.append('Q: %r' % t[-400:])
    cf = CV.CF(sectors=n)
    e, st, t, same = run(m, cf, b'R800\r10\r\rQ', later=[('S = scan again', b'x')])
    if t.count('not a sector on this card') != 1 or 'CFSCAN finished.' not in t or cf.log.count(('read', 0)) :
        E.append('bad first: %r' % t[-400:])
    cf = CV.CF(sectors=n)
    e, st, t, same = run(m, cf, b'R20\r10\r\rN', rtc=clock(cf, bcd=False), later=[('S = scan again', b'x')])
    if 'it is before the first' not in t or any(k != 'identify' for k, _ in cf.log): E.append('before/N: %r' % t[-400:])
    cf = CV.CF(present=False)
    e, st, t, same = run(m, cf, b'', cap=50_000_000)
    if 'no answer. Is a card in the socket?' not in t or st != 'idle': E.append('no card: %s %r' % (st, t[-150:]))
    report('CFSCAN: Q stops after a sector and says where to go on (no clock: no times); $800 refused; last < first '
           'refused; N writes nothing; no card', E)

    print('\nnative CF programs:', 'ALL PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
