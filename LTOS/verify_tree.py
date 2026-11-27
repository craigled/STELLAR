# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""TREE -f (and -h, a folder given) in the simulator, line for line against the card tool's tree (tools/elf2k_card.py
tree_lines) drawn from the very same card read by the Mac:

  * TREE -f from the root: every folder and file, folders first then files, each by name (A.TXT before A-B.TXT,
    as the card's NAME    EXT has them), sizes and dates, the |-- / `-- / |    lines; the totals
  * TREE -f -h: the hidden file too, marked (hidden); TREE -fh /DOCS: from that folder; TREE -f DOCS/OLD
  * plain TREE as it was (folder totals); TREE -x, TREE /NOPE, two folders: refused, LTOS goes on

    python3 LTOS/verify_tree.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_cardfiles as VC
import cardsync as CS
import elf2k_card as T
import build, tempfile


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    kimg, _ = build.kernel(); mem, _, _ = build.build(kimg)
    cf, e2k, st = P1.installed_full(mem, 16384)
    # the files written into the image in Python (cardsync's writer): a Mac mount would leave its own hidden ._ files
    path = os.path.join(tempfile.mkdtemp(), 'c.img'); open(path, 'wb').write(V.image(cf, 16384))
    im = CS.Image(path, check=False); CS.run(im.open(lambda *a: None)); CS.run(im.walk(lambda *a: None))
    CS.run(im.write(['/DOCS', '/DOCS/OLD', '/GAMES', '/EMPTY', '/BIN', '/BIN/RAW'],
                    [(p, bytes(n)) for p, n in (('/A.TXT', 10), ('/A-B.TXT', 20), ('/ZED', 3), ('/DOCS/NOTE.TXT', 700),
                     ('/DOCS/OLD/DEEP.TXT', 5), ('/GAMES/X.STL', 1024), ('/GAMES/B.STL', 512), ('/BIN/RAW/SINE.BIN', 288),
                     ('/SECRET.TXT', 42))], lambda *a: None))
    img = bytearray(open(path, 'rb').read()); VC.set_hidden(img, '/SECRET.TXT'); open(path, 'wb').write(img)
    P1.load_image(cf, bytes(img))
    im = CS.Image(path, check=False); CS.run(im.open(lambda *a: None)); files, dirs = CS.run(im.walk(lambda *a: None))
    shown = {p: v for p, v in files.items() if not v[2]}
    cmds = ['TREE -f', 'TREE -f -h', 'TREE -fh /DOCS', 'TREE -f docs/old', 'TREE', 'TREE -x', 'TREE /NOPE', 'TREE /DOCS /GAMES']
    outs = {}
    def gen():                                          # as a person types: a command, a key at each "-- more"
        yield from VC.CF.start(cr=False, say=lambda *a: None)
        for c in cmds:
            yield from VC.CF.typed(c)
            got = b''
            while True:
                got += yield from VC.CF.until([b'LTOS> ', b'Q stops --'], 30.0)
                if got.endswith(b'Q stops --'): yield ('send', b' '); continue
                break
            outs[c] = got.decode('latin1')
    u, st, t = VC.session(cf, gen())
    def out(cmd):
        o = outs.get(cmd, '')
        o = re.sub(r'-- more: a key goes on, Q stops --[^\r]*\r *\r', '', o).replace('\r', '')
        return [l for l in o.split('\n') if l.strip() and not l.startswith('LTOS>')]
    def want(fs, ds, top='/'):
        sub = {p: v for p, v in fs.items() if top == '/' or p.startswith(top + '/')}
        sd = {d for d in ds if top == '/' or d.startswith(top + '/')}
        if top != '/':                                  # (tree_lines draws from the root: re-rooted here)
            n = len(top)
            sub = {'/' + p[n + 1:]: v for p, v in sub.items()}; sd = {'/' + d[n + 1:] for d in sd}
        lines = T.tree_lines(sub, sd)
        lines[0] = top if top == '/' else top + '/'
        tot = '%d files in %d folders, %d bytes' % (len(sub), len(sd), sum(v[0] for v in sub.values()))
        return lines + [tot]
    for cmd, fs, top in (('TREE -f', shown, '/'), ('TREE -f -h', files, '/'), ('TREE -fh /DOCS', files, '/DOCS'),
                         ('TREE -f docs/old', files, '/DOCS/OLD')):
        got, w = out(cmd), want(fs, dirs, top)
        if top == '/DOCS/OLD': w[0] = 'DOCS/OLD/'                   # (the path as typed, upper case)
        e = []
        if got != w:
            k = next((i for i, (a, c) in enumerate(zip(got, w)) if a != c), min(len(got), len(w)))
            e.append('line %d: %r, want %r' % (k, got[k] if k < len(got) else None, w[k] if k < len(w) else None))
        if '-v' in sys.argv: print('\n'.join(got))
        report('%s: line for line the card tool\'s tree (%d lines)' % (cmd, len(w)), e)
    e = []
    o = '\n'.join(out('TREE'))
    if 'folders,' not in o or 'files' not in o or '|--' in o: e.append('plain TREE changed: %r' % o[-300:])
    if 'Usage: TREE [-f] [-h] [folder]' not in '\n'.join(out('TREE -x')): e.append('TREE -x: %r' % out('TREE -x'))
    if 'There is no folder /NOPE' not in '\n'.join(out('TREE /NOPE')): e.append('TREE /NOPE: %r' % out('TREE /NOPE'))
    if 'Usage' not in '\n'.join(out('TREE /DOCS /GAMES')): e.append('two folders: %r' % out('TREE /DOCS /GAMES'))
    if st != 'stop': e.append('MON: %s' % st)
    report('plain TREE as it was; TREE -x, a folder not there, two folders: refused, LTOS goes on', e)
    print('TREE: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
