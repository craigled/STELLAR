# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""SC.PRG (Tiny Stellar C on LTOS) on the simulated Elf2K, against SC/tsc.py (its reference, itself checked against
scc on the firmware by SC/tsc_verify.py): each program of tsc_verify's TESTS compiled on the card - its .STL must be
tsc's byte for byte - then each of its mistakes refused with tsc's line, $? 1 and nothing saved. Also: a name with
no extension (.SC taken as read), a source spread over several sectors, usage, no such file, fsck clean.

    python3 LTOS/verify_sc.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'SC'))
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build
import tsc, tsc_verify as T

BIG = ('// a program over several sectors: long comments and many statements\n' +
       ''.join('// line %d of padding to push the code over sector boundaries, and a /* comment */ too\n' % i for i in range(40)) +
       'u16 total;\nvoid main() {\n    total = 0;\n' + ''.join('    total = total + %d;\n' % i for i in range(60)) +
       '    printu(total); print("\\r\\n");\n}\n')


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    _, syms = build.assemble('sc')
    e = []
    if syms['VEND'] > syms['HDR']: e.append('the code and its variables end at $%04X, past $%04X' % (syms['VEND'], syms['HDR']))
    report('SC.PRG fits ($3000-$%04X)' % syms['VEND'], e)

    progs = dict((k.upper()[:8], src) for k, (src, _, _) in T.TESTS.items())
    progs['BIG'] = BIG
    for name, d in build.srcfiles(): progs[name[:8].decode().strip()] = d.decode('latin1')   # the /SRC examples
    bad = [('E%d' % i, src, line, words) for i, (src, line, words) in enumerate(T.BAD)]
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed(mem, n)
    def put(m):
        b = os.path.join(m, 'BIN'); os.makedirs(b, exist_ok=True)
        for p in ('SC', 'CD'): open(os.path.join(b, p + '.PRG'), 'wb').write(build.prg(p.lower()))
        d = os.path.join(m, 'C'); os.mkdir(d)
        for k, src in progs.items(): open(os.path.join(d, k + '.SC'), 'wb').write(src.encode('latin1'))
        for k, src, _, _ in bad: open(os.path.join(d, k + '.SC'), 'w').write(src)
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)
    cmds = ['SC %s' % k for k in progs] + ['SC %s.SC' % k for k, _, _, _ in bad] + ['SC', 'SC NOSUCH']
    later = [('LTOS> ', b'CD C\r')] + [('/C> ', x.encode() + b'\r') for x in cmds + ['MON']]
    b = V.Elf2K(cf, keys=b'', later=later)
    b.rtc = P3.clock()
    stat = []
    f0 = b.u.feed
    def feed():
        k = len(b.u.later)
        f0()
        if len(b.u.later) < k: stat.append(b.c.M[0x033F])
    b.u.feed = feed
    s = b.boot_rom(400_000_000_000)
    t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
    if v: print(t[-4000:])
    parts = re.split(r'(?m)^LTOS /C> ', t)[1:]
    res = dict((c, (p.partition('\n')[2], stat[k + 2] if k + 2 < len(stat) else None)) for k, (c, p) in enumerate(zip(cmds, parts)))
    got = {}
    def rd(m):
        for k in list(progs) + [x[0] for x in bad]:
            p = os.path.join(m, 'C', k + '.STL')
            got[k] = open(p, 'rb').read() if os.path.exists(p) else None
    P2.mac(V.image(cf, n), rd)
    if v:
        dd = os.environ.get('SCDUMP')
        if dd:
            for k, g in got.items():
                if g: open(os.path.join(dd, k + '.STL'), 'wb').write(g)

    e = []
    if s != 'stop': e.append('the end: %s' % s)
    for k, src in progs.items():
        want = tsc.compile_text(src)
        g = got[k]
        body, rc = res.get('SC %s' % k, ('', None))
        if g != want or rc != 0:
            i = next((j for j in range(min(len(g or b''), len(want))) if g[j] != want[j]), None)
            e.append('%s: %s (first difference at %s: %s / %s) $? %r %r' % (k, 'not tsc\'s' if g else 'not saved', i,
                     g[i:i + 8].hex() if g and i is not None else '', want[i:i + 8].hex() if i is not None else '', rc, body[-160:]))
    report('SC makes tsc\'s .STL byte for byte: %s (BIG: a source over several sectors; and the /SRC examples)' % ', '.join(progs), e)

    e = []
    for k, src, line, words in bad:
        body, rc = res.get('SC %s.SC' % k, ('', None))
        if ('%s.SC line %d: ' % (k, line)) not in body or words not in body or rc != 1 or got[k] is not None:
            e.append('%s: %r $? %r (want line %d: %s)' % (k, body[-140:], rc, line, words))
    report('each mistake: tsc\'s line and words, $? 1, nothing saved', e)

    e = []
    if 'Usage: SC' not in res['SC'][0] or res['SC'][1] != 1: e.append('SC: %r' % (res['SC'],))
    if 'there is no NOSUCH.SC' not in res['SC NOSUCH'][0] or res['SC NOSUCH'][1] != 1: e.append('SC NOSUCH: %r' % (res['SC NOSUCH'],))
    rc, _ = P2.fsck_free(V.image(cf, n))
    if rc: e.append('fsck_msdos: %d' % rc)
    report('usage, no such file, fsck clean', e)
    print('(a 1.79 MHz Elf2K\'s time for all of it: %.0f s)' % (b.steps / 112000))
    print('\nSC: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
