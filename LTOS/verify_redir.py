# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 1 in the simulator: output redirection and the new programs, against what the Mac reads.

  * > NAME, >> NAME, > NUL: any command's output into a file (LF line ends), added on, or nowhere - the file
    as the screen would have shown it; > replacing a file gives the old one's clusters back; into a folder;
    many sectors and clusters; >> across a sector's end; a > in quotes is text; paging off in a file
  * questions (Y/N) and errors still on the screen; mistakes in the name said, nothing run
  * the card full partway: the file as it was, every cluster given back
  * ECHO, CAT, HEAD, TAIL, TOUCH against Python's answers; fsck clean and FREE = fsck after each session

    python3 LTOS/verify_redir.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

NUMS = b''.join(b'line %d\r\n' % i for i in range(1, 31))                   # PC line ends
BIG = b''.join(b'%05d the quick brown fox jumps over the lazy dog\n' % i for i in range(400))   # ~22 KB
TEXTS = {'N.TXT': NUMS, 'BIG.TXT': BIG, 'OLD.TXT': b'x' * 3000, 'A.ZZZ': b'a', 'B.ZZZ': b'b',
         'DOCS/IN.TXT': b'in a folder\n'}


def card(mem, extra=None):
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        for n, d in TEXTS.items():
            p = os.path.join(m, *n.split('/'))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, 'wb').write(d)
        if extra: extra(m)
    img, _ = P2.mac(V.image(cf, 16384), put)
    P1.load_image(cf, img)
    return cf


def files(cf):
    def walk(m):
        r = {}
        for d, ds, fs in os.walk(m):
            ds[:] = [x for x in ds if not x.startswith('.')]
            for f in fs:
                if f.startswith('.'): continue
                p = os.path.join(d, f); r[os.path.relpath(p, m)] = open(p, 'rb').read()
        return r
    return P2.mac(V.image(cf, 16384), walk)[1]


def out(t, cmd):
    return P2.session_out(t, cmd + '\r').lstrip('\r\n')


def lf(s):
    """screen text -> what the file holds: CR LF -> LF"""
    return s.replace('\r\n', '\n').encode('latin1')


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    def clean(cf, t, e):
        img = V.image(cf, 16384)
        rc, fr = P2.fsck_free(img)
        if rc != 0: e.append('fsck_msdos %d' % rc)
        m = re.findall(r'\((\d+) of (\d+) clusters', t)
        if not m or not fr or int(m[-1][0]) != fr[1]: e.append('FREE %s, fsck %s' % (m and m[-1][0], fr))
        return fr

    # ---- 1. > >> NUL, quotes, paging, folders, replacing, the new programs
    cf = card(mem)
    fr0 = P2.fsck_free(V.image(cf, 16384))[1]
    cmds = ['VER', 'VER > V.TXT', 'VER >> V.TXT', 'CAT N.TXT > C.TXT', 'CAT BIG.TXT>B2.TXT', 'CAT C.TXT >> B2.TXT',
            'TYPE N.TXT > T.TXT', 'HELP > NUL', 'ECHO "a > b" \'c >> d\' > Q.TXT', 'ECHO into a folder > /DOCS/H.TXT',
            'ECHO hi > OLD.TXT', 'DIR DOCS > D.TXT', 'DIR DOCS', 'ECHO hello   world "x  y" -n', 'ECHO -n no newline',
            'HEAD N.TXT', 'HEAD -n 3 N.TXT > H3.TXT', 'HEAD -2 BIG.TXT', 'TAIL N.TXT', 'TAIL -n 2 BIG.TXT >> H3.TXT',
            'TAIL -50 N.TXT > T50.TXT', 'HEAD -n 0 N.TXT', 'TOUCH NEW.TXT N.TXT', 'CAT', 'HEAD', 'TAIL -n x N.TXT',
            'FREE']
    b, st, t = P3.session(cf, ''.join(c + '\r' for c in cmds).encode() + b'MON\r', rtc=P3.clock())
    if '-v' in sys.argv: print(t)
    fl = files(cf); e = []
    def want(f, d):
        if fl.get(f) != d: e.append('%s: %r, want %r' % (f, fl.get(f, b'(none)')[:120], d[:120]))
    ver = out(t, 'VER')
    want('V.TXT', lf(ver) * 2)
    for c in cmds[1:3] + ['HELP > NUL', 'CAT N.TXT > C.TXT', 'TYPE N.TXT > T.TXT']:
        if out(t, c).strip(): e.append('%s printed %r on the screen' % (c, out(t, c)[:80]))
    want('C.TXT', NUMS.replace(b'\r', b''))
    want('B2.TXT', BIG + NUMS.replace(b'\r', b''))
    want('T.TXT', NUMS.replace(b'\r', b''))
    want('Q.TXT', b'a > b c >> d\n')
    want('DOCS/H.TXT', b'into a folder\n')
    want('OLD.TXT', b'hi\n')
    want('D.TXT', lf(out(t, 'DIR DOCS')).replace(b'H        TXT         14', b'H        TXT         14'))
    if [f for f in fl if f.upper() in ('NUL', 'NUL.TXT')]: e.append('a NUL file was made')
    fr = clean(cf, t, e)
    report('> >> and > NUL: VER twice, CAT of a PC file (LF ends), 22 KB (many clusters) then >> more, TYPE '
           'with no pages, HELP nowhere, a > in quotes, into /DOCS, replacing OLD.TXT; fsck clean, FREE = fsck', e)
    e = []
    def scr(c, w):
        if out(t, c) != w: e.append('%s: %r, want %r' % (c, out(t, c)[:200], w[:200]))
    lines = NUMS.replace(b'\r', b'').decode().split('\n')[:-1]
    big = BIG.decode().split('\n')[:-1]
    scr('ECHO hello   world "x  y" -n', 'hello world x  y -n\r\n')
    if not t.count('no newlineLTOS> '): e.append('ECHO -n: %r' % out(t, 'ECHO -n no newline'))
    scr('HEAD N.TXT', '\r\n'.join(lines[:10]) + '\r\n')
    scr('HEAD -2 BIG.TXT', '\r\n'.join(big[:2]) + '\r\n')
    scr('TAIL N.TXT', '\r\n'.join(lines[-10:]) + '\r\n')
    scr('HEAD -n 0 N.TXT', '')
    want('H3.TXT', ('\n'.join(lines[:3] + big[-2:]) + '\n').encode())
    want('T50.TXT', NUMS.replace(b'\r', b''))
    want('NEW.TXT', b'')
    want('N.TXT', NUMS)
    scr('CAT', 'CAT names - the files, one after another\r\n')
    scr('HEAD', 'HEAD [-n N] name - the first N lines (10)\r\n')
    scr('TAIL -n x N.TXT', 'TAIL [-n N] name - the last N lines (10)\r\n')
    report('ECHO (spaces, quotes, -n), HEAD and TAIL (-n N, -N, 0, more than there are, into a file), TOUCH '
           '(a new file, one there kept), the usage lines', e)

    # ---- 2. questions and errors on the screen; mistakes in the name
    cf = card(mem)
    cmds = ['RM *.ZZZ > R.TXT', 'FOO > X.TXT', 'ZZZZ > Y.TXT', 'ECHO > ', 'ECHO hi > /NOPE/A.TXT', 'ECHO hi > *.TXT',
            'ECHO hi > DOCS', 'ECHO hi > A:B', 'DIR *.ZZZ', 'FREE']
    later = [('(Y/N) ', b'Y'), ('LTOS> ', ''.join(c + '\r' for c in cmds[1:]).encode() + b'MON\r')]
    b, st, t = P3.session(cf, cmds[0].encode() + b'\r', rtc=P3.clock(), later=later)
    if '-v' in sys.argv: print(t)
    fl = files(cf); e = []
    if '2 files match - delete them all? (Y/N) Y' not in out(t, 'RM *.ZZZ > R.TXT'): e.append('RM: %r' % out(t, 'RM *.ZZZ > R.TXT'))
    if b'Y/N' in fl.get('R.TXT', b'') or 'R.TXT' not in fl: e.append('R.TXT: %r' % fl.get('R.TXT'))
    for c in ('FOO > X.TXT', 'ZZZZ > Y.TXT'):
        if 'Unknown command: ' + c.split()[0] not in out(t, c): e.append('%s: %r' % (c, out(t, c)))
    for f in ('X.TXT', 'Y.TXT'):
        if fl.get(f) != b'': e.append('%s: %r, want empty' % (f, fl.get(f)))
    for c, w in (('ECHO > ', 'A file name must follow the >.'), ('ECHO hi > /NOPE/A.TXT', 'There is no such folder.'),
                 ('ECHO hi > *.TXT', 'That is not a file name.'), ('ECHO hi > DOCS', 'That is a folder.'),
                 ('ECHO hi > A:B', 'That is not a file name.')):
        if out(t, c) != w + '\r\n': e.append('%s: %r' % (c, out(t, c)))
    if 'A.ZZZ' in fl or 'B.ZZZ' in fl: e.append('RM did not delete them')
    clean(cf, t, e)
    report('the question (Y/N) and its answer on the screen, not in the file; Unknown command on the screen (an '
           'empty file); no name, no such folder, a wildcard, a folder, a bad name: said, nothing run', e)

    # ---- 3. the card full partway: >, a new file, and >>
    def fill(m):
        st = os.statvfs(m); room = st.f_bavail * st.f_frsize
        open(os.path.join(m, 'FILL.BIN'), 'wb').write(b'\xAA' * (room - 10 * 1024))
    cf = card(mem, fill)
    img0 = V.image(cf, 16384); frf = P2.fsck_free(img0)[1]
    cmds = ['CAT BIG.TXT > F.TXT', 'CAT BIG.TXT > OLD.TXT', 'CAT BIG.TXT >> N.TXT', 'ECHO still here > S.TXT', 'FREE']
    b, st, t = P3.session(cf, ''.join(c + '\r' for c in cmds).encode() + b'MON\r', rtc=P3.clock())
    if '-v' in sys.argv: print(t)
    fl = files(cf); e = []
    for c, f in (('CAT BIG.TXT > F.TXT', 'F.TXT'), ('CAT BIG.TXT > OLD.TXT', 'OLD.TXT'), ('CAT BIG.TXT >> N.TXT', 'N.TXT')):
        if 'The card is full - %s is as it was.' % f not in out(t, c): e.append('%s: %r' % (c, out(t, c)[-120:]))
    if fl.get('F.TXT') != b'': e.append('F.TXT: %r' % fl.get('F.TXT', b'(none)')[:40])
    if fl.get('OLD.TXT') != b'x' * 3000: e.append('OLD.TXT changed')
    if fl.get('N.TXT') != NUMS: e.append('N.TXT changed: %d bytes' % len(fl.get('N.TXT', b'')))
    if fl.get('S.TXT') != b'still here\n': e.append('S.TXT: %r' % fl.get('S.TXT'))
    fr = clean(cf, t, e)
    if fr and frf and fr[1] != frf[1] - 1: e.append('free clusters %d, before %d (S.TXT takes 1)' % (fr[1], frf[1]))
    report('the card full partway: a new file (left empty), >, >> - each as it was, every cluster given back; '
           'the next command goes on; fsck clean', e)
    print('\nLTOS redirection: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
