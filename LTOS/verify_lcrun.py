# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LC's Run (LC4.OVL) and the way back, in the simulator: the real ROM, the kernel built now (its WARM runs "LC -r"
when LC left its mark), a card with programs, a script, a tune, a Stellar C source and a STELLAR app:

  * Enter on HELLO.PRG: it runs (LTOS's folder is the pane's), "LC: a key goes back to it", a key: LC as it was -
    the same folders, the cursor on HELLO.PRG; three times running (the script /_LC.SH does not nest)
  * Enter on TEST.SH (a script), ODE.MUS (PLAY), and 9 on /DOCS/FIRST.SC in the right pane (SC compiles it):
    each comes back, the right pane still /DOCS and active, FIRST.STL there now
  * Enter on BOUNCE.STL: STELLAR runs it; Esc ends it; LTOS starts again and the kernel runs LC -r - LC as it was,
    no key needed; the mark gone after
  * E on NOTE.TXT: NANO edits it (X typed, ^O, ^X) and LC is back as it was, no key; e on a .PRG: what E edits
  * Enter on a .TXT: View; 9 on it: what Run runs; /_LC.DAT and /_LC.SH hidden; fsck_msdos: nothing wrong

    python3 LTOS/verify_lcrun.py [-v]
"""
import os, re, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_cardfiles as VC
import cardsync as CS
import cardfiles as CFm
import build
from verify_lc import vt100, settle, UARTS

VERB = '-v' in sys.argv
ROOT = os.path.join(HERE, '..')


def make_card():
    kimg, _ = build.kernel(); mem, _, _ = build.build(kimg)
    cf, e, st = P1.installed(mem, 16384)
    path = os.path.join(tempfile.mkdtemp(), 'c.img'); open(path, 'wb').write(V.image(cf, 16384))
    im = CS.Image(path, check=False); CS.run(im.open(lambda *a: None)); CS.run(im.walk(lambda *a: None))
    sysf = dict(build.system_files())
    files = [('/LC.PRG', build.prg('lc'))] + [('/LC%d.OVL' % k, p) for k, p in enumerate(build.lc_ovl())]
    for n in ('SH', 'ECHO', 'HELLO', 'STELLAR', 'PLAY', 'SC', 'CD', 'NANO', 'ATTACH'):
        files.append(('/%s.PRG' % n, sysf[n.ljust(8).encode() + b'PRG']))
    files.append(('/NANO.OVL', sysf[b'NANO    OVL']))
    files += [('/ODE.MUS', sysf[b'ODE     MUS']), ('/TEST.SH', b'ECHO a script ran\r\n'), ('/NOTE.TXT', b'just text\r\n'),
              ('/BOUNCE.STL', build.stl_of(open(os.path.join(ROOT, 'APPLICATIONS', 'Bounce.lst')).read())),
              ('/DOCS/FIRST.SC', open(os.path.join(HERE, 'src', 'FIRST.SC'), 'rb').read())]
    CS.run(im.write(['/DOCS'], files, lambda *a: None))
    P1.load_image(cf, open(path, 'rb').read())
    return cf


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    cf = make_card()
    st = {'acc': '', 'b': None}
    errs = []
    def scr(): return vt100(st['acc'])[0]
    def r22(): return scr()[21].strip()
    def recv(quiet, pats=()):
        if pats: o = yield from CFm.until([p.encode() for p in pats], quiet)
        else: o = yield from settle(quiet)
        st['acc'] += o.decode('latin1'); return o
    def key(b, quiet=1.5, pats=()):
        l0 = UARTS[-1].lost if UARTS else 0
        yield ('send', b); o = yield from recv(quiet, pats)
        if UARTS and UARTS[-1].lost != l0 and VERB: print('  lost %d at %r (screen row 1 %r)' % (UARTS[-1].lost - l0, b, scr()[0][:40]), flush=True)
        return o
    def goto(name):
        if VERB: print('  goto', name, 'waiting:', __import__('verify_lc').lc_waiting(), flush=True)
        yield from key(b'\x1b[H')
        for _ in range(40):
            if VERB: print('  goto %s: row 22 %r' % (name, r22()[:30]), flush=True)
            if r22().split(' ')[:1] in ([name], [name + '/']): return
            yield from key(b'\x1b[B')
        errs.append('%s: not in the pane' % name)
    def lc_back(label, name, left='/', right='/', act=0, waitkey=True):
        """After a Run: (the key asked for, then) LC's screen as it was."""
        if waitkey:
            if 'a key goes back to it' not in st['acc'][-400:]: errs.append('%s: no "a key goes back" (%r)' % (label, st['acc'][-160:]))
            yield from key(b' ', 12.0, ['Esc quit'])
        yield from recv(3.0)
        g = scr()
        want_top = '+- %s ' % left
        if not g[0].startswith(' LTOS Commander'): errs.append('%s: not LC again: %r' % (label, g[0])); return
        if not g[1].startswith('+- ' + left + ' ') or g[1][40:43] + g[1][43:43 + len(right) + 1] != '+- ' + right + ' ':
            errs.append('%s: the panes %r' % (label, g[1]))
        if not r22().startswith(name): errs.append('%s: the cursor %r, want %s' % (label, r22(), name))
    def gen():
        yield from CFm.start(cr=False, say=lambda *a: None)
        yield from CFm.typed('LC')
        yield from recv(8.0)
        if os.environ.get('SHORT') == '2':
            yield from goto('HELLO.PRG'); n0 = len(st['acc'])
            yield from key(b'\r', 25.0, ['a key goes back to it']); yield from recv(8.0)
            m, sy = build.assemble('lc'); M = st['b'].c.M
            print({k: M[sy[k]] for k in ('RESMODE', 'OVCUR', 'OVFND', 'OVSEG')}, 'LINE:', bytes(M[0x7000:0x7020]), flush=True)
            print('_LC.SH?', bytes(M[0x6B00:0x6B30]), flush=True)
            yield from key(b' ', 12.0); yield from key(b'\x1b', 3.0); yield from key(b'\x1b', 3.0, ['LTOS> ']); return
        if os.environ.get('SHORT'): yield from goto('HELLO.PRG'); yield from key(b'\x1b', 3.0); yield from key(b'\x1b', 3.0, ['LTOS> ']); return
        for k in range(3):                                      # HELLO.PRG, three times
            yield from goto('HELLO.PRG')
            yield from key(b'\r', 20.0, ['a key goes back to it'])
            if k == 0 and 'Hello' not in st['acc'][-600:] and 'HELLO' not in st['acc'][-600:].upper(): errs.append('HELLO: its output %r' % st['acc'][-300:])
            yield from lc_back('HELLO.PRG (%d)' % (k + 1), 'HELLO.PRG')
        yield from goto('TEST.SH')
        yield from key(b'\r', 20.0, ['a key goes back to it'])
        if 'a script ran' not in st['acc'][-500:]: errs.append('TEST.SH: its output %r' % st['acc'][-300:])
        yield from lc_back('TEST.SH', 'TEST.SH')
        yield from goto('ODE.MUS')
        yield from key(b'\r', 60.0, ['a key goes back to it'])
        yield from lc_back('ODE.MUS', 'ODE.MUS')
        yield from key(b'\t'); yield from goto('DOCS'); yield from key(b'\r', 6.0); yield from goto('FIRST.SC')
        yield from key(b'9', 60.0, ['a key goes back to it'])
        yield from lc_back('SC FIRST (9, in /DOCS)', 'FIRST.SC', right='/DOCS', act=1)
        if 'FIRST.STL' not in '\n'.join(g[40:] for g in scr()[2:20]): errs.append('SC: no FIRST.STL in /DOCS')
        yield from key(b'\t')
        yield from goto('BOUNCE.STL')
        yield from key(b'\r', 15.0)                             # STELLAR runs it; Esc ends it; LTOS again, LC -r
        yield from key(b'\x1b', 90.0, ['Esc quit'])
        yield from recv(4.0)
        if 'LTOS 0.5' not in st['acc'][-6000:]: errs.append('BOUNCE: LTOS did not start again (%r)' % st['acc'][-200:])
        yield from lc_back('BOUNCE.STL (back through the kernel)', 'BOUNCE.STL', right='/DOCS', waitkey=False)
        mark = bytes(st['b'].c.M[0x7EF8:0x7EFA])
        if mark[:2] == b'LC': errs.append('the mark still there: %r' % mark)
        yield from goto('NOTE.TXT')                             # E: NANO edits it, ^X: LC again, no key
        yield from key(b'E', 25.0, ['NANO 1.1'])
        if 'NANO 1.1' not in st['acc'][-3000:]: errs.append('E on NOTE.TXT: no NANO (%r)' % st['acc'][-200:])
        yield from key(b'X\x0f', 15.0, ['bytes to'])
        yield from key(b'\x18', 25.0, ['Esc quit'])
        yield from lc_back('E on NOTE.TXT (NANO, ^O, ^X)', 'NOTE.TXT', right='/DOCS', waitkey=False)
        if 'a key goes back' in st['acc'][-3000:]: errs.append('Edit: a key was asked for')
        yield from key(b'E', 25.0, ['NANO 1.1'])                # again, from the LC that LC -e started: ^X, no change
        yield from key(b'\x18', 25.0, ['Esc quit'])
        yield from lc_back('E again (from LC -e)', 'NOTE.TXT', right='/DOCS', waitkey=False)
        yield from goto('HELLO.PRG')
        yield from key(b'e')
        if not r22().startswith('Edit (NANO): .SC .TXT'): errs.append('e on a .PRG: %r' % r22())
        yield from goto('NOTE.TXT')
        yield from key(b'9')
        if not r22().startswith('Run: .PRG .SH .STL'): errs.append('9 on a .TXT: %r' % r22())
        yield from key(b'\r', 4.0)
        if not scr()[0].startswith(' /NOTE.TXT'): errs.append('Enter on a .TXT: not View (%r)' % scr()[0])
        yield from key(b'\x1b', 4.0); yield from key(b'\x1b', 4.0, ['LTOS> '])
    def g2():
        while not UARTS or getattr(UARTS[-1], 'board', None) is None: yield ('recv', 1, 0.01)
        st['b'] = UARTS[-1].board
        yield from gen()
    u, s2, text = VC.session(cf, g2(), cap=900_000_000)
    if VERB: print('\n'.join(scr()))
    report('Run: HELLO.PRG x3, a script, PLAY, SC in the other pane, a STELLAR app back through the kernel; Edit '
           '(E: NANO, no key after); View; what 9 runs, what e edits - LC as it was after each', errs)
    img = V.image(cf, 16384); pth = os.path.join(tempfile.mkdtemp(), 'c.img'); open(pth, 'wb').write(img)
    im = CS.Image(pth, check=False); CS.run(im.open(lambda *a: None))
    ents = {n: at for n, at, sz, d, fc in im.entries(0)}
    e = ['%s: %s' % (n, 'not there' if n not in ents else 'not hidden') for n in ('_LC.DAT', '_LC.SH') if not ents.get(n, 0) & 2]
    CS.run(im.walk(lambda *a: None))
    got = CS.run(im.get('/NOTE.TXT', lambda *a: None)) if '/NOTE.TXT' in im.where else None
    if got != b'Xjust text\n': e.append('NOTE.TXT after Edit: %r (want X typed at its top, LF ends)' % got)
    rc, _ = P2.fsck_free(img)
    if rc != 0: e.append('fsck_msdos: %r' % rc)
    if u.lost: e.append('%d bytes lost at the UART' % u.lost)
    report('/_LC.DAT and /_LC.SH hidden; NOTE.TXT as NANO saved it; fsck_msdos finds nothing wrong; no byte lost', e)
    print('ALL PASS' if ok else 'SOME FAILED')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
