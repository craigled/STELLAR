# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""PWD, SORT and UNIQ in the simulator, against Python's answers: each run with > X.OUT, the file read back.

    python3 LTOS/verify_uniqsort.py [-v] [N]     # N random files as well (default 4)
"""
import os, re, sys, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build


def lines_of(d):
    """As UNIQ and SORT read a file: CR dropped, 255 characters a line kept, a last line with no LF counts."""
    ls = d.replace(b'\r', b'').split(b'\n')
    if ls[-1] == b'': ls.pop()
    return [l[:255] for l in ls]


def uniq(d, c=False, dd=False):
    out, prev, n = [], None, 0
    for l in lines_of(d) + [None]:
        if prev is not None and l == prev: n = min(n + 1, 65535); continue
        if prev is not None and (not dd or n > 1):
            out.append((b'%7d ' % n if c else b'') + prev)
        prev, n = l, 1
    return b''.join(x + b'\n' for x in out)


def numkey(l):
    m = re.match(rb'[ \t]*(-?)(\d*)', l)
    v = int(m.group(2) or b'0')
    return -v if m.group(1) and v else v


def sort(d, r=False, n=False, u=False):
    ls = sorted(lines_of(d), key=(lambda l: (numkey(l), l)) if n else None)
    if r: ls.reverse()
    out = []
    for l in ls:
        if u and out and out[-1] == l: continue
        out.append(l)
    return b''.join(x + b'\n' for x in out)


def rand_file(rng):
    pool = [b'apple', b'Apple', b'banana', b'cherry', b'  10 ten', b'9 nine', b'-3 minus', b'-0 zero', b'007 bond',
            b'100', b'99', b'', b'x', b'apple pie', b'\tindent', b'00', b'12345678901234567890 big', b'-12345678901234567890']
    ls = []
    for _ in range(rng.randint(5, 60)):
        l = rng.choice(pool)
        if rng.random() < 0.4 and ls: l = ls[-1]                 # repeats in a row, for UNIQ
        ls.append(l)
    return b'\r\n'.join(ls) + (b'\r\n' if rng.random() < 0.8 else b'')


def main():
    ok = True
    n = int(sys.argv[-1]) if sys.argv[-1].isdigit() else 4
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    rng = random.Random(1802)
    files = {'F%d' % i: rand_file(rng) for i in range(n)}
    files['EMPTY'] = b''
    files['LONG'] = b'b' * 300 + b'\n' + b'a' * 300 + b'\n' + b'b' * 300 + b'X\n'
    files['WORDS'] = b'\n'.join(sorted((b'w%03d' % rng.randrange(200)) for _ in range(400))[::-1]) + b'\n'
    big = b''.join(b'line number %05d of a file too big to sort in memory\n' % i for i in range(400))
    files['BIG'] = big
    runs = []                                         # (command, the .OUT name, want)
    for k, d in files.items():
        if k == 'BIG': continue
        for opts, f in (('', lambda d: uniq(d)), ('-c', lambda d: uniq(d, c=True)), ('-d', lambda d: uniq(d, dd=True)),
                        ('-cd', lambda d: uniq(d, True, True))):
            runs.append(('UNIQ %s %s.TXT' % (opts, k), f(d)))
        for opts, f in (('', lambda d: sort(d)), ('-r', lambda d: sort(d, r=True)), ('-n', lambda d: sort(d, n=True)),
                        ('-n -r', lambda d: sort(d, True, True)), ('-u', lambda d: sort(d, u=True)),
                        ('-rnu', lambda d: sort(d, True, True, True))):
            runs.append(('SORT %s %s.TXT' % (opts, k), f(d)))
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        for k, d in files.items(): open(os.path.join(m, k + '.TXT'), 'wb').write(d)
        os.makedirs(os.path.join(m, 'DOCS', 'OLD'))
    img, _ = P2.mac(V.image(cf, 16384), put)
    P1.load_image(cf, img)
    keys = ''.join('%s > O%d.OUT\r' % (c, i) for i, (c, _) in enumerate(runs))
    b, st, t = P3.session(cf, keys.encode() + b'MON\r', rtc=P3.clock(), cap=8_000_000_000)
    _, got = P2.mac(V.image(cf, 16384), lambda m: {f[:-4]: open(os.path.join(m, f), 'rb').read()
                                                   for f in os.listdir(m) if f.endswith('.OUT')})
    bad = 0
    for i, (c, want) in enumerate(runs):
        g = got.get('O%d' % i)
        if g != want:
            bad += 1
            if bad <= 8: print('  %s: got %r\n      want %r' % (c, g[:300] if g else g, want[:300]))
    print('UNIQ, SORT: %d runs on %d files - %s' % (len(runs), len(files) - 1, 'OK' if not bad else '%d FAIL' % bad))
    ok &= not bad
    # PWD, SORT of a file too big, the usage lines - a prompt at a time
    b, st, t = P3.session(cf, b'PWD\r', rtc=P3.clock(), later=[
        ('LTOS> ', b'CD DOCS/OLD\r'), ('LTOS /DOCS/OLD> ', b'PWD\r'), ('LTOS /DOCS/OLD> ', b'CD /\r'),
        ('LTOS> ', b'SORT BIG.TXT\r'), ('LTOS> ', b'SORT\r'), ('LTOS> ', b'UNIQ -x A.TXT\r'), ('LTOS> ', b'MON\r')])
    if '-v' in sys.argv: print(t[-2000:])
    e = []
    if P2.session_out(t, 'PWD\r').strip() != '/': e.append('PWD at the root: %r' % P2.session_out(t, 'PWD\r'))
    i = t.index('LTOS /DOCS/OLD> PWD')
    if '/DOCS/OLD' not in t[i + 19:i + 40]: e.append('PWD in /DOCS/OLD: %r' % t[i:i + 60])
    if 'Too big to sort' not in P2.session_out(t, 'SORT BIG.TXT\r'): e.append('SORT BIG.TXT: %r' % P2.session_out(t, 'SORT BIG.TXT\r'))
    if 'SORT [-r]' not in P2.session_out(t, 'SORT\r'): e.append('SORT alone: %r' % P2.session_out(t, 'SORT\r'))
    if 'UNIQ [-c]' not in P2.session_out(t, 'UNIQ -x A.TXT\r'): e.append('UNIQ -x: %r' % P2.session_out(t, 'UNIQ -x A.TXT\r'))
    print('PWD (root, /DOCS/OLD); SORT of a %d-byte file says it is too big; the usage lines: %s'
          % (len(big), 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]
    ok &= not e
    print('\nPWD, SORT, UNIQ: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
