# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""MEMVERSE in the simulator, on the real file: the line the clock picks, wrapped at the words: no word split, no
line over 76 columns, every word there and in order; UTF-8 dashes plain; leading spaces gone; blank lines not counted.
A file with no line end at the end, a word too long for a line, a file with nothing in it, no file at all, > a file.
And the pick itself, modelled here: how evenly it spreads over the lines through a day.

    python3 LTOS/verify_memverse.py [-v]
"""
import collections, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build
REAL = os.path.join(HERE, '..', 'BIBLE', 'MEMVERSE.txt')
WIDTH = 76


def stir(x):
    x ^= (x << 7) & 0xFFFF; x ^= x >> 9; x ^= (x << 8) & 0xFFFF
    return x


def pick(n, s, mi, h, d, mo, y):
    x = 0x1802
    for b in (s, mi, h, d, mo, y): x = stir(x ^ b)
    return stir(stir(x)) % n


def lines_of(b):
    t = b.replace(b'\r\n', b'\n').replace(b'\r', b'\n').decode('utf8').replace('–', '-').replace('—', '-')
    t = t.replace('‘', "'").replace('’', "'").replace('“', '"').replace('”', '"')
    return [l.strip(' \t') for l in t.split('\n') if l.strip()]


def run(cf, cmds, clock):
    later = [('LTOS> ', c.encode() + b'\r') for c in cmds] + [('LTOS> ', b'MON\r')]
    b = V.Elf2K(cf, keys=b'', later=later); b.rtc = clock
    st = b.boot_rom(3_000_000_000)
    return st, b.text().replace('\r', '')


def out(t, c, k=0):
    p = [x[len(c) + 1:] for x in re.split(r'(?m)^LTOS> ', t) if x.startswith(c + '\n')]
    return p[k] if k < len(p) else None


def card(mem, n, cf, files):
    def put(m):
        d = os.path.join(m, 'BIBLE'); os.makedirs(d, exist_ok=True)
        for k, v in files.items(): open(os.path.join(d, k), 'wb').write(v)
    img, _ = P2.mac(V.image(cf0(mem, n, cf), n), put)
    P1.load_image(cf, img)


def cf0(mem, n, cf): return cf


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed_full(mem, n)
    base = V.image(cf, n)
    real = open(REAL, 'rb').read(); want = lines_of(real)

    def check_wrap(shown, verse, e, tag):
        rows = [r for r in shown.split('\n') if r.strip()]
        if ' '.join(rows).split() != verse.split(): e.append('%s: not the verse, word for word: %r' % (tag, shown[:120]))
        for r in rows:
            if len(r) > WIDTH: e.append('%s: %d columns: %r' % (tag, len(r), r))
            if r != r.strip(): e.append('%s: spaces at a line end: %r' % (tag, r))
        for a, b in zip(rows, rows[1:]):                # greedy: the next word would not have fitted
            if len(a) + 1 + len(b.split()[0]) <= WIDTH: e.append('%s: wrapped too soon: %r' % (tag, a))

    # 1. the real file, at times that pick the longest verses and others
    longest = sorted(range(len(want)), key=lambda i: -len(want[i]))[:3]
    want_t = {}
    for s in range(60):
        for mi in range(60):
            i = pick(len(want), s, mi, 14, 16, 10, 26)
            want_t.setdefault(i, (s, mi))
    times = [want_t[i] for i in longest + [0, len(want) - 1] if i in want_t]
    e = []
    img, _ = P2.mac(base, lambda m: (os.makedirs(os.path.join(m, 'BIBLE'), exist_ok=True), open(os.path.join(m, 'BIBLE', 'MEMVERSE.TXT'), 'wb').write(real)))
    for s, mi in times:
        P1.load_image(cf, img)
        st, t = run(cf, ['MEMVERSE'], P3.clock(h=14, mi=mi, s=s))
        o = out(t, 'MEMVERSE'); i = pick(len(want), s, mi, 14, 16, 10, 26)
        if st != 'stop' or o is None: e.append('%d:%d: %s %r' % (mi, s, st, t[-200:])); continue
        check_wrap(o, want[i], e, 'verse %d' % i)
        if '-v' in sys.argv: print(o)
        if not o.startswith('\n') or not o.endswith('\n\n'): e.append('no blank line around it: %r' % o[:40])
    report('MEMVERSE on the real file: %d verses, %d times, the longest ones too: the verse the clock picks, every word in order, wrapped at the words, none over %d columns' % (len(want), len(times), WIDTH), e)

    # 2. every verse of the real file, in one session: the clock moved on before each MEMVERSE
    e = []
    P1.load_image(cf, img)
    order = [(i, want_t[i]) for i in range(len(want)) if i in want_t]
    if len(order) != len(want): e.append('no time picks %d verses' % (len(want) - len(order)))
    later = [('LTOS> ', b'MEMVERSE\r') for _ in order] + [('LTOS> ', b'MON\r')]
    bb = V.Elf2K(cf, keys=b'', later=later)
    def tick(r):
        k = min(max(bb.text().count('LTOS> MEMVERSE') - 1, 0), len(order) - 1)
        return P3.clock(h=14, mi=order[k][1][1], s=order[k][1][0])(r)
    bb.rtc = tick
    st = bb.boot_rom(3_000_000_000); t = bb.text().replace('\r', '')
    if st != 'stop': e.append('the end: %s' % st)
    for k, (i, _) in enumerate(order):
        o = out(t, 'MEMVERSE', k)
        if o is None: e.append('run %d: nothing' % k); continue
        check_wrap(o, want[i], e, 'verse %d' % i)
    rows = sum(len([r for r in (out(t, 'MEMVERSE', k) or '').split('\n') if r.strip()]) for k in range(len(order)))
    report('All %d verses shown, %d lines on the screen: each word for word, none over %d columns, every break at a word and none too soon' % (len(order), rows, WIDTH), e)
    dash = [i for i, l in enumerate(lines_of(real)) if ' - ' in l or '-' in l]
    report('The real file: %d lines have a dash from UTF-8; nothing over $7E reaches the screen' % len(dash),
           [] if all(ord(c) < 127 for l in want for c in l) else ['non-ASCII left'])

    # 3. made-up files
    long_word = 'x' * 100
    tests = {
        'blanks': (b'\r\n\r\n   \r\n  one two\r\n\r\nthree four\r\n\r\n', ['one two', 'three four']),
        'noend': (b'alpha beta\ngamma delta', ['alpha beta', 'gamma delta']),
        'exact': (('a' * 76 + ' next\n').encode(), ['a' * 76 + ' next']),
        'word': ((long_word + ' tail\n').encode(), [long_word + ' tail']),
        'quotes': ('“He said” ‘so’ — it–is\n'.encode(), ['"He said" \'so\' - it-is']),
    }
    e = []
    for k, (data, ls) in tests.items():
        def w(m, data=data):
            os.makedirs(os.path.join(m, 'BIBLE'), exist_ok=True); open(os.path.join(m, 'BIBLE', 'MEMVERSE.TXT'), 'wb').write(data)
        im, _ = P2.mac(base, w); P1.load_image(cf, im)
        st, t = run(cf, ['MEMVERSE'], P3.clock())
        o = out(t, 'MEMVERSE'); i = pick(len(ls), 20, 30, 14, 16, 10, 26)
        got = None if o is None else ''.join(o.split('\n')).replace(' ', '')
        if got != ls[i].replace(' ', ''): e.append('%s: %r, not line %d %r' % (k, o, i, ls[i]))
        if k == 'word' and o and max(map(len, o.split('\n'))) > WIDTH: e.append('word: over %d' % WIDTH)
    report('Blank lines and leading spaces skipped; no line end at the end; a line of exactly 76; a word longer than a line; UTF-8 dashes and quotes', e)

    e = []
    def w0(m):
        os.makedirs(os.path.join(m, 'BIBLE'), exist_ok=True); open(os.path.join(m, 'BIBLE', 'MEMVERSE.TXT'), 'wb').write(b'\r\n  \r\n')
    im, _ = P2.mac(base, w0); P1.load_image(cf, im)
    st, t = run(cf, ['MEMVERSE'], P3.clock())
    if 'There are no verses' not in (out(t, 'MEMVERSE') or ''): e.append('empty: %r' % t[-120:])
    P1.load_image(cf, base)
    st, t = run(cf, ['MEMVERSE'], P3.clock())
    if st != 'stop' or 'There is no' not in (out(t, 'MEMVERSE') or ''): e.append('no file: %r' % t[-160:])
    P1.load_image(cf, img)
    st, t = run(cf, ['MEMVERSE > V.TXT', 'TYPE V.TXT'], P3.clock())
    if (out(t, 'MEMVERSE > V.TXT') or '').strip(): e.append('> : on the screen too: %r' % out(t, 'MEMVERSE > V.TXT'))
    if len((out(t, 'TYPE V.TXT') or '').strip()) < 20: e.append('> : the file: %r' % out(t, 'TYPE V.TXT'))
    report('Nothing in the file: said so; no file: said so; > V.TXT: the verse in the file', e)

    e = []
    c = collections.Counter(pick(len(want), s, mi, h, 16, 10, 26) for h in range(24) for mi in range(60) for s in range(60))
    lo, hi = min(c.get(i, 0) for i in range(len(want))), max(c.values()); mean = 86400 / len(want)
    if len(c) != len(want) or lo < mean * 0.7 or hi > mean * 1.3: e.append('spread %d..%d, mean %d, %d lines seen' % (lo, hi, mean, len(c)))
    same = sum(pick(len(want), s, 30, 14, 16, 10, 26) == pick(len(want), s + 1, 30, 14, 16, 10, 26) for s in range(59))
    report('The pick: every verse comes up through a day, %d to %d times each (mean %d); the same verse twice in the next second %d times in 59' % (lo, hi, mean, same), e)
    print('\nMEMVERSE: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
