# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""RUNNING in the simulator, on the real ROM: the screen cleared, the frames drawn in the middle (replayed through a small
VT100 model), an arrow key ignored, a lone Esc ending it with the cursor back and the screen clear.

    python3 LTOS/verify_running.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import build


def screens(t):
    """The picture so far: 25 x 80 of ' ' and '#' (reverse video)."""
    g = [[' '] * 81 for _ in range(26)]; r = c = 1; rev = False
    for m in re.finditer(r'\x1b\[([0-9;?]*)([A-Za-z])|(.)', t, re.S):
        if m.group(3) is not None:
            ch = m.group(3)
            if ch == '\x08': c -= 1
            elif ch not in '\r\n':
                if c <= 80: g[r][c] = '#' if rev else ch
                c += 1
        else:
            a, k = m.group(1), m.group(2); n = int(a) if a.isdigit() else 1
            if k == 'H':
                p = a.split(';') if a else ['1', '1']; r, c = int(p[0]), int(p[1] if len(p) > 1 else 1)
            elif k == 'A': r -= n
            elif k == 'B': r += n
            elif k == 'C': c += n
            elif k == 'D': c -= n
            elif k == 'm': rev = a == '7'
            elif k == 'J': g = [[' '] * 81 for _ in range(26)]
    return g


def main():
    m, _ = build.assemble('running')
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    class CF:
        present = True; disk = {}; log = []
        def sector(s, n): return bytes(512)
    gap = [('\x1b[0m', b'')] * 60                                        # a few frames between the keys
    later = [('Esc stops', b'\x1b[C')] + gap + [('\x1b[0m', b'x')] + gap + [('\x1b[0m', b'\x1b')]
    b = V.Elf2K(CF(), keys=b'', later=later)
    for a, v in m.items(): b.c.M[a] = v
    st = b.call(0x3000, cap=12_000_000)
    t = b.text()
    e = []
    if st not in ('idle', 'stop'): e.append('the end: %s' % st)
    if not t.startswith('\x1b[0m\x1b[2J\x1b[?25l'): e.append('not cleared first: %r' % t[:30])
    if not t.endswith('\x1b[0m\x1b[?25h\x1b[2J\x1b[H'): e.append('the end: %r' % t[-30:])
    n = t.count('\x1b[0m')
    if n < 16: e.append('the arrow or x stopped it: %d' % n)
    import walk_gen as G                                                # the picture on the screen is each frame, exactly
    F = [G.frame(i) for i in range(G.N)]
    body = t[t.index('Esc stops') + 9:]
    pre = t[:t.index('Esc stops') + 9]
    m = list(re.finditer(r'(?=\x1b\[)', body)); seen = set()
    for k in m:
        g = screens(pre + body[:k.start()])
        pic = tuple(tuple(1 if g[G.TOP + y][G.LEFT + 2 * x] == '#' and g[G.TOP + y][G.LEFT + 2 * x + 1] == '#' else 0 for x in range(G.W)) for y in range(G.H))
        for i, f in enumerate(F):
            if pic == tuple(tuple(r) for r in f): seen.add(i)
    if len(seen) < G.N: e.append('frames seen right: %s of %d' % (sorted(seen), G.N))
    report('RUNNING: cleared, the cursor hidden; every frame on the screen exactly; walks through an arrow key and an x; a lone Esc ends it, the cursor back, cleared', e)
    if '-v' in sys.argv:
        for i in range(G.N): print('\n'.join(''.join('##' if v else '  ' for v in r) for r in F[i])); print('-' * 30)
    print('steps %d, %d bytes sent' % (b.steps, len(t)))
    print('\nRUNNING: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
