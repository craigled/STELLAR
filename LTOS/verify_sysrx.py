# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""SYSRX and elfser.py system on the simulated Elf2K: a card fresh from the installer (F and INSTALL2), MKDIR /BIN,
then LTOS-ALL.PAK: every program in /BIN, the rest in the root, byte for byte; fsck clean; programs run. Over a card
that has them already. Damaged frames, a lost ACK, and a sender that stops.

    python3 LTOS/verify_sysrx.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_xfer as X
import elfser as E
import build


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + str(x)[:180]) for x in e[:10]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed(mem, n, b'F')
    fresh = V.image(cf, n)
    data = open(os.path.join(build.OUT, 'LTOS-ALL.PAK'), 'rb').read()
    want = {}
    for name, d in build.samples():
        f = name[:8].decode().strip() + '.' + name[8:].decode().strip()
        want[('BIN/' if name[8:] in (b'PRG', b'STL') else '') + f] = d
    quiet = lambda *a: None
    E.xsys.t0 = 0
    E.time = type('T', (), {'time': staticmethod(lambda: 0), 'sleep': staticmethod(lambda x: None)})

    def go(img, later_after=(), first=b'MKDIR /BIN\r', **kw):
        P1.load_image(cf, img)
        later = [('LTOS> ', b'SYSRX\r')] + list(later_after) + [('LTOS> ', b'MON\r')]
        u, st, t = X.run(cf, first, E.xsys(data, quiet), later=later, cap=3_000_000_000, **kw)
        return u, st, t, V.image(cf, n)

    def check(img, e):
        got = X.files(img)
        for k, d in want.items():
            if got.get(k) != d: e.append('%s: %s' % (k, 'not there' if k not in got else 'differs'))
        code = P2.fsck_free(img)
        if code[0]: e.append('fsck %r' % (code,))

    e = []
    u, st, t, img = go(fresh, [('LTOS> ', b'VER\r'), ('LTOS> ', b"SED -n '1p' /HELP.TXT\r")])
    print('    the whole system: about %d s on the Elf2K (%d bytes)' % (u.board.steps / 85000, len(data)))
    if st != 'stop' or u.result is not True: e.append('%s %r %r' % (st, u.result, t[-200:]))
    if ' files saved.' not in t or 'NOT saved' in t: e.append(t[-200:])
    if 'LTOS 0.5' not in t.split('files saved.')[-1]: e.append('VER after it: %r' % t[-200:])
    check(img, e)
    report('A fresh card: %d files from one LTOS-ALL.PAK' % len(want), e)

    e = []
    u, st, t, img2 = go(img, first=b'\r')
    if u.result is not True or 'NOT saved' in t: e.append('%r %r' % (u.result, t[-200:]))
    check(img2, e)
    report('Again over the same card: every file replaced', e)

    e = []
    def sendf(k, d): return bytes([d[0] ^ 0x40]) + d[1:] if k in (5, 40) and len(d) > 100 else (d[:300] if k == 70 and len(d) > 100 else d)
    lost = [False]
    def recvf(k, b):
        if k == 30 and not lost[0]: lost[0] = True; return None
        return b
    u, st, t, img3 = go(fresh, sendf=sendf, recvf=recvf)
    if u.result is not True: e.append('%r %r' % (u.result, t[-200:]))
    check(img3, e)
    report('Damaged frames, one cut short, a lost ACK: sent again, every file right', e)

    e = []
    def stop():
        yield from E.xstart(quiet)
        yield ('send', E.xframe(0, data[:512]))
        yield ('recv', 1, 5.0)
        return True
    P1.load_image(cf, fresh)
    u, st, t = X.run(cf, b'SYSRX\r', stop(), later=[('Stopped.', b''), ('LTOS> ', b'MON\r')], cap=3_000_000_000)
    if st != 'stop' or 'Stopped.' not in t: e.append('%s %r' % (st, t[-160:]))
    report('A sender that stops: SYSRX gives up and is back at the prompt', e)
    print('SYSRX: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
