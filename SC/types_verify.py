# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check 16-bit arrays, signed (i16) arithmetic and switch (examples/types.sc) on V0061.37 (as flashed): the
compiled program's output must be, character for character, what Python works out for the same
operations (C semantics: / rounds toward zero, % takes the dividend's sign, >> is arithmetic).
Then from dirty memory, and a rerun without reloading.

    python3 types_verify.py
"""
import sys, os, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import scc
import opcode_sweep as S

V = [-32768, -1000, -1, 0, 1, 999, 32767]


def cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q
def cmod(a, b): return a - b * cdiv(a, b)
def kind(k):
    if chr(k) in 'aeiou': return 1
    if k == 32: return 2
    if chr(k) in '012': return 13
    if k == ord('9'): return 10
    return 9


def expected():
    big = [1000, 2000, 65535, 0, 12345]
    sq = [(i * i * 300) & 0xFFFF for i in range(10)]
    l1 = '%d %d %d %d %d %d %d %d' % (sum(x // 10 for x in big), big[2], big[4], sq[9], (sq[3] + sq[4]) & 0xFFFF, -5, -32000, 6)
    l2 = ''.join(chr(48 + (a < b) + 2 * (a <= b) + 4 * (a > b) + 8 * (a >= b)) for a in V for b in V)
    def w(x): return ((x + 0x8000) & 0xFFFF) - 0x8000                # back to 16 bits, signed
    l3 = ''.join('%d,%d,%d,%d,%d,%d ' % (w(cdiv(a, 7)), w(cmod(a, 7)), w(cdiv(a, -3)), w(cmod(a, -3)), a >> 1, a >> 3) for a in V)
    l5 = ''.join('%d ' % w(cmod(a, b) + cdiv(w(cdiv(a, b)), 2)) for a in V for b in [-7, 3, -1, 32767])
    txt = b'ai 09xu2b!e\0'
    l4 = ''
    for c in txt:
        if c == ord('x'): continue
        l4 += chr(48 + kind(c))
    return '\r\n'.join([l1, l2, l3, l5, l4]) + '\r\n'


def run(pokes, mem=None, dirty=False):
    img = bytearray(S.image('37'))
    if dirty:
        rnd = random.Random(7)
        for a in range(0x4000, 0x5000): img[a] = rnd.randrange(256)
    c = S.boot(bytes(mem), [], keys=b'') if mem else S.boot(bytes(img), pokes, keys=b'')
    for _ in range(40_000_000):
        if not c.step() or c.R[c.P] == S.EXIT_IDL + 1: break
    return c, bytes(c.io_out.get(3, [])).decode('latin1')


def main():
    c0, em, labels, data = scc.compile_source(open(os.path.join(HERE, 'examples', 'types.sc')).read(), 'types')
    pokes = [(a + i, b) for a, bs, _, _ in em for i, b in enumerate(bs)] + \
            [(0x4000 + a + i, b) for a, d in data.items() for i, b in enumerate(d)]
    want = expected()
    ok = True
    names = ['16-bit arrays (read, sum, write, &a[i], i16 elements)', 'signed < <= > >= over 7 x 7 values',
             'signed / % (by 7 and -3) and >> 1, >> 3', 'signed / % inside an expression, variable divisors', 'switch: cases, fall-through, default, break, continue']
    c, out = run(pokes)
    for k, (g, w) in enumerate(zip(out.split('\r\n'), want.split('\r\n'))):
        if k >= len(names): break
        good = g == w
        print('%-56s %s' % (names[k], 'OK' if good else 'FAIL\n   got  %r\n   want %r' % (g[:150], w[:150])))
        ok &= good
    err = c.M[0x304F]
    if err: print('VM error $%02X' % err); ok = False
    c2, out2 = run(pokes, dirty=True)
    c3, out3 = run(None, mem=c2.M)
    good = out2 == want and out3 == want
    print('%-56s %s' % ('from dirty memory, and a rerun without reloading', 'OK' if good else 'FAIL'))
    ok &= good
    print('PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
