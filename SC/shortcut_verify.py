# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check that && and || stop early (examples/shortcut.sc) on V0061.37 (as flashed): the right side
- a call to a function - must run only when it is needed. Each test prints its result and how many
times f() ran. Then from dirty memory, and a rerun without reloading.

    python3 shortcut_verify.py
"""
import sys, os, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import scc
import opcode_sweep as S

# (what, result, calls to f())
TESTS = [('if (z && f(1))', 0, 0), ('if (o && f(1))', 1, 1), ('if (o || f(1))', 1, 0), ('if (z || f(0))', 0, 1),
         ('r = z && f(1)', 0, 0), ('r = o || f(0)', 1, 0), ('r = o && f(5)', 1, 1),
         ('if ((z && f(1)) || f(1))', 1, 1), ('if (!(z && f(1)))', 1, 0), ('while (i < 3 && f(1))', 3, 3),
         ('if (f(0) && f(1))', 0, 1), ('if (o || f(1)) break;', 0, 0), ('if (o || f(1)) return;', 0, 0),
         ('return z && f(1)', 0, 0), ('r = (z && f(1)) + 2', 2, 0), ('r = f(o && f(7))', 1, 2),
         ('if (pat[0] && !f(pat[0]))', 0, 0), ('if (pat[1] && !f(pat[1]))', 0, 1),
         ('if (z && f(1) || o && f(1))', 1, 1), ('if (o && (z || f(0)) && f(1))', 0, 1), ('q(z && f(1))', 0, 0)]


def run(pokes, mem=None, dirty=False):
    img = bytearray(S.image('37'))
    if dirty:
        rnd = random.Random(7)
        for a in range(0x4000, 0x5000): img[a] = rnd.randrange(256)
    c = S.boot(bytes(mem), [], keys=b'') if mem else S.boot(bytes(img), pokes, keys=b'')
    for _ in range(20_000_000):
        if not c.step() or c.R[c.P] == S.EXIT_IDL + 1: break
    return c, bytes(c.io_out.get(3, [])).decode('latin1')


def main():
    c0, em, labels, data = scc.compile_source(open(os.path.join(HERE, 'examples', 'shortcut.sc')).read(), 'shortcut')
    pokes = [(a + i, b) for a, bs, _, _ in em for i, b in enumerate(bs)] + \
            [(0x4000 + a + i, b) for a, d in data.items() for i, b in enumerate(d)]
    want = ''.join('%d,%d ' % (r, n) for _, r, n in TESTS) + '\r\n'
    ok = True
    c, out = run(pokes)
    got = out.split()
    for k, (what, r, n) in enumerate(TESTS):
        g = got[k] if k < len(got) else '?'
        good = g == '%d,%d' % (r, n)
        print('%-36s %s' % (what, 'OK' if good else 'FAIL: got %s (result,calls), want %d,%d' % (g, r, n)))
        ok &= good
    err = c.M[0x304F]
    if err: print('VM error $%02X' % err); ok = False
    c2, out2 = run(pokes, dirty=True)
    c3, out3 = run(None, mem=c2.M)
    good = out2 == want and out3 == want
    print('%-36s %s' % ('from dirty memory, and a rerun', 'OK' if good else 'FAIL'))
    ok &= good
    print('PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
