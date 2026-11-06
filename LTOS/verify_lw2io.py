# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS + Lite-Writer 2 in the simulator: documents to and from LW2's slots.

  * LW2 alone: a new document in the current folder - its first ^W asks for a name, checked against the folder's;
    no slots under LTOS (^S, ^L say so);
  * STELLAR LW2 DOC.TXT: ATTACH.PRG puts the file where Lite-Writer can rewrite it alone; Lite-Writer opens it
    (any line ends), ^W writes it back - the Mac reads it, fsck is clean (8 and 32 MB, a new file, a folder).

    python3 LTOS/verify_lw2io.py [-v]
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import opcode_sweep as S
import build
import verify_phase4 as P4
import verify_phase5 as P5


# the ^W save's FAT stamp, 2026-10-16 14:30, as the Mac shows it: its msdos driver reads FAT times with TODAY's
# offset from UTC, then shows them in the zone of that date - so after a summer-time change it is an hour off
import calendar, time
MAC1430 = time.localtime(calendar.timegm((2026, 10, 16, 14, 30, 0)) - time.localtime().tm_gmtoff)[:5]

def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    # ---- STELLAR LW2 DOC.TXT: the file attached - Lite-Writer opens it, ^W writes it back, the Mac reads it
    lst = open(os.path.join(HERE, '..', 'APPLICATIONS', 'Lite-Writer-2', 'Lite-Writer-2.lst')).read()
    lw2 = build.stl_of(lst)
    import re
    import time
    OLD = time.mktime((2021, 3, 4, 5, 6, 8, 0, 0, -1))         # the Mac's files: dated 2021-03-04 05:06:08
    def lw2_session(mb, files, folders, cmd, typed, kept=None, cap=2_500_000_000, inbin=False, quit_only=False):
        """A card with LW2.STL (+ files, made by the Mac); STELLAR <cmd>; type at the top, ^W, ^X. -> (text, cf)"""
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        def put(m):
            for d in folders: os.makedirs(os.path.join(m, d), exist_ok=True)
            open(os.path.join(m, 'LW2.STL'), 'wb').write(lw2)
            for nm, d in files.items(): open(os.path.join(m, nm), 'wb').write(d); os.utime(os.path.join(m, nm), (OLD, OLD))
            if inbin:                                         # the programs in /BIN, the document here
                os.makedirs(os.path.join(m, 'BIN'))
                for n in ('LW2.STL', 'STELLAR.PRG', 'STELLAR.BIN', 'ATTACH.PRG'):
                    os.rename(os.path.join(m, n), os.path.join(m, 'BIN', n))
        img, _ = P2.mac(V.image(cf, n), put)
        P1.load_image(cf, img)
        later = [('press any key to start', b' '), ('^W writes it back', typed + b'\x17'),
                 ('bytes to ', b'\x18')] if not quit_only else [('press any key to start', b' '), ('^W writes it back', b'\x18')]
        b = V.Elf2K(cf, keys=cmd, later=later); b.rtc = P3.clock(); c = b.c
        if kept: c.M[0x7000:0x7000 + len(kept)] = kept
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        st = P4.run_to_back(b, cap)                           # STELLAR's end: BACK (it boots LTOS)
        return st, b, cf
    def clean(t): return re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', ' ', t)
    BIG = b''.join(b'Line %03d of a longer document.\n' % i for i in range(170))[:5000]

    # ---- LW2 alone (no document): a new one in the current folder; its first ^W asks for a name ("Save as"),
    #      checked against the folder's names; no slots under LTOS
    def alone(later, folders=('DOCS',), cmd=b'CD DOCS\rLW2\r', cap=2_500_000_000):
        cf, e2k, st = P1.installed_full(mem, 16384)
        def put(m):
            os.makedirs(os.path.join(m, 'BIN'), exist_ok=True)
            open(os.path.join(m, 'BIN', 'LW2.STL'), 'wb').write(lw2)
            for d in folders: os.makedirs(os.path.join(m, d), exist_ok=True)
            if folders: open(os.path.join(m, 'DOCS', 'OTHER.TXT'), 'wb').write(b'other\n')
        img, _ = P2.mac(V.image(cf, 16384), put); P1.load_image(cf, img)
        b = V.Elf2K(cf, keys=cmd, later=later); b.rtc = P3.clock(); c = b.c
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        n0 = len(V.writes(cf))
        st = P4.run_to_back(b, cap)
        img = V.image(cf, 16384)
        rc, _ = P2.fsck_free(img)
        _, fl = P2.mac(img, P5.walk)
        return st, clean(b.text()), rc, fl, V.writes(cf)[n0:]
    st, t, rc, fl, w = alone([('press any key', b' '), ('^W asks for a name', b'Hello there\x01\x17'),
                              ('Save as', b'other\r'), ('in use here', b'\x17'), ('Save as', b'BAD..N\r'),
                              ('Not a file name', b'\x17'), ('Save as', b'\x1b'), ('LITE-WRITER', b'\x17'),
                              ('Save as', b'note\r'), ('bytes to NOTE.TXT', b'X\x17'), ('bytes to NOTE.TXT', b'\x18')])
    e = []
    if st != 'stop': e.append('the end: %s %r' % (st, t[-300:]))
    if rc: e.append('fsck %d' % rc)
    if fl.get('DOCS/NOTE.TXT') != b'XHello there': e.append('DOCS/NOTE.TXT %r' % fl.get('DOCS/NOTE.TXT'))
    if fl.get('DOCS/OTHER.TXT') != b'other\n': e.append('DOCS/OTHER.TXT %r' % fl.get('DOCS/OTHER.TXT'))
    if 'Save as' in t.split('bytes to NOTE.TXT')[1] if 'bytes to NOTE.TXT' in t else True:
        e.append('the second ^W asked for a name again (or none was written): %r' % t[-400:])
    if sorted(k for k in fl if k.startswith('DOCS/')) != ['DOCS/NOTE.TXT', 'DOCS/OTHER.TXT']: e.append('files %r' % sorted(fl))
    if '-v' in sys.argv: print(t[-2500:])
    report('CD DOCS, LW2 alone, ^A (the text after the cursor moves up when it is named): ^W asks "Save as": OTHER (in use) refused, BAD..N refused, Esc cancels, NOTE -> '
           'NOTE.TXT .TXT added; the next ^W just writes it; fsck clean, the Mac reads it', e)
    st, t, rc, fl, w = alone([('press any key', b' '), ('^W asks for a name', b'Bye now\x18'),
                              ('before leaving?', b'Y'), ('Save as', b'x.doc\r')], folders=(), cmd=b'LW2\r')
    e = []
    if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
    if fl.get('X.DOC') != b'Bye now': e.append('X.DOC %r (files %r)' % (fl.get('X.DOC'), sorted(fl)))
    report('LW2 alone in the root, ^X: "Save your changes before leaving?" Y, Save as x.doc: X.DOC written', e)
    st, t, rc, fl, w = alone([('press any key', b' '), ('^W asks for a name', b'\x13'), ('No slots here', b'\x0c'),
                              ('No slots here', b'\x18')])
    e = []
    if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
    if sorted(k for k in fl if k.startswith('DOCS/')) != ['DOCS/OTHER.TXT']: e.append('files %r' % sorted(fl))
    if 'Save your changes' in t: e.append('nothing typed, yet it asked to save')
    report('LW2 alone: ^S and ^L say "No slots here"; ^X with nothing typed: no file made, fsck clean', e)
    for mb, files, folders, cmd, typed, path, want, label, *inbin in (
            (8, {'DOC.TXT': b'Line one\nLine two\n'}, [], b'STELLAR LW2 DOC.TXT\r', b'Top. ', 'DOC.TXT',
             b'Top. Line one\nLine two\n', 'DOC.TXT (LF line ends) opened, typed at the top, ^W'),
            (32, {'DOC.TXT': b'Line one\r\nLine two\r\n'}, [], b'STELLAR LW2 DOC.TXT\r', b'Top. ', 'DOC.TXT',
             b'Top. Line one\nLine two\n', '32 MB card, CR LF line ends'),
            (8, {'LOTSLOSS.TXT': 'It\u2019s \u201cfine\u201d \u2014 ok\u2026 caf\u00e9\u00a0x \u2013 \u2018y\u2019\r\n'.encode()}, [],
             b'STELLAR LW2 LOTSLOSS.TXT\r', b'Top. ', 'LOTSLOSS.TXT', b'Top. It\'s "fine" - ok... caf? x - \'y\'\n',
             'the Mac\'s UTF-8 quotes, dashes, ... and no-break space become ASCII; anything else ?'),
            (8, {'DOCS/BIG.TXT': BIG}, ['DOCS'], b'CD DOCS\rlw2 big.txt\r', b'Top. ', 'DOCS/BIG.TXT',
             b'Top. ' + BIG, '5,000 bytes (2026-10-30: under LTOS the text holds 5,204), rewritten: ATTACH holds it at $5500, '
             'clear of STELLAR.PRG ($4000) and its variables ($6B00)', True),
            (8, {'DOC.TXT': b'Line one\nLine two\n'}, [], b'LW2 DOC.TXT\r', b'Top. ', 'DOC.TXT',
             b'Top. Line one\nLine two\n', 'just LW2 DOC.TXT (no LW2.PRG: the kernel runs STELLAR LW2 DOC.TXT)'),
            (8, {}, [], b'STELLAR LW2 NEW.TXT\r', b'Hello there\rSecond line', 'NEW.TXT',
             b'Hello there\nSecond line', 'NEW.TXT not on the card: opened empty, ^W makes it'),
            (8, {'DOCS/NOTE.TXT': b'In a folder\n'}, ['DOCS'], b'STELLAR LW2 DOCS/NOTE.TXT\r', b'Edited. ', 'DOCS/NOTE.TXT',
             b'Edited. In a folder\n', 'DOCS/NOTE.TXT (the Mac\'s folder: it grows a sector)'),
            (8, {'DOCS/NOTE.TXT': b'In a folder\n'}, ['DOCS'], b'CD DOCS\rSTELLAR LW2 NOTE.TXT\r', b'Edited. ', 'DOCS/NOTE.TXT',
             b'Edited. In a folder\n', 'CD DOCS, LW2 NOTE.TXT: STELLAR, LW2, ATTACH all in /BIN', True),
            (8, {'DOCS/NOTE.TXT': b'In a folder\n'}, ['DOCS'], b'CD DOCS\rSTELLAR NOTE.TXT\r', b'Edited. ', 'DOCS/NOTE.TXT',
             b'Edited. In a folder\n', 'CD DOCS, STELLAR NOTE.TXT (no app named: Lite-Writer 2 from /BIN)', True)):
        st, b, cf = lw2_session(mb, files, folders, cmd, typed, inbin=bool(inbin))
        t = clean(b.text()); e = []
        nm = path.split('/')[-1]
        if 'Opened %s' % nm not in t: e.append('no "Opened %s": %r' % (nm, t[-400:]))
        if 'bytes to %s' % nm not in t: e.append('no "Wrote ... to %s": %r' % (nm, t[-300:]))
        if st != 'stop': e.append('STELLAR\'s end did not boot LTOS: %s' % st)
        img = V.image(cf, mb * 2048)
        rc, _ = P2.fsck_free(img)
        if rc: e.append('fsck_msdos: %d' % rc)
        _, (got, mt) = P2.mac(img, lambda m: (open(os.path.join(m, *path.split('/')), 'rb').read(),
                                              time.localtime(os.stat(os.path.join(m, *path.split('/'))).st_mtime)[:5])
                              if os.path.exists(os.path.join(m, *path.split('/'))) else (None, None))
        if got != want: e.append('the Mac reads %s: %r (want %r)' % (path, got, want))
        if mt != MAC1430: e.append('the Mac dates %s %r: not the ^W save (2026-10-16 14:30)' % (path, mt))
        if '-v' in sys.argv: print(t[-1500:])
        report('STELLAR LW2 %s - %s; fsck clean, the Mac reads it' % (path, label), e)
    for mb, path, folders in ((8, 'DOC.TXT', []), (8, 'DOCS/NOTE.TXT', ['DOCS'])):
        body = b'Leave me be\r\nas I am\r\n'
        st, b, cf = lw2_session(mb, {path: body}, folders, b'STELLAR LW2 %s\r' % path.encode(), b'', quit_only=True)
        t = clean(b.text()); e = []
        nm = path.split('/')[-1]
        if 'Opened %s' % nm not in t: e.append('no "Opened %s": %r' % (nm, t[-400:]))
        if 'bytes to' in t: e.append('it was written: %r' % t[-300:])
        if st != 'stop': e.append('STELLAR\'s end did not boot LTOS: %s' % st)
        img = V.image(cf, mb * 2048)
        rc, _ = P2.fsck_free(img)
        if rc: e.append('fsck_msdos: %d' % rc)
        _, (got, mt) = P2.mac(img, lambda m: (open(os.path.join(m, *path.split('/')), 'rb').read(),
                                              os.stat(os.path.join(m, *path.split('/'))).st_mtime))
        if got != body: e.append('the Mac reads %s: %r (want %r)' % (path, got, body))
        if mt != OLD: e.append('the Mac dates %s %s (want %s)' % (path, time.ctime(mt), time.ctime(OLD)))
        if '-v' in sys.argv: print(t[-1500:])
        report('STELLAR LW2 %s, then ^X with no edit: the Mac sees the same text and the same date' % path, e)
    cf, e2k, st = P1.installed_full(mem, 16384)
    img, _ = P2.mac(V.image(cf, 16384), lambda m: [open(os.path.join(m, n), 'wb').write(d) for n, d in
                                                   (('LW2.STL', lw2), ('BIG.TXT', b'z' * 61000))])
    P1.load_image(cf, img)
    b, st, t = P3.session(cf, b'STELLAR LW2 BIG.TXT\rMON\r', rtc=P3.clock())
    e = [] if ('over 60,000 bytes' in t and st == 'stop') else [repr(t[-500:])]
    report('STELLAR LW2 BIG.TXT (61,000 bytes) refused by ATTACH (60,000 at most: Lite-Writer 3\'s); LTOS goes on', e)

    # opening a document in a folder again and again: the folder must not grow (it gained a sector every time
    # before 2026-10-21 - on Craig's card the opens slowed to 22 s). The other files in it stay.
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        os.makedirs(os.path.join(m, 'DOCS'))
        open(os.path.join(m, 'LW2.STL'), 'wb').write(lw2)
        for n, d in (('A.TXT', b'first\n'), ('NOTE.TXT', b'the note\n' * 50), ('B.TXT', b'last\n')):
            open(os.path.join(m, 'DOCS', n), 'wb').write(d)
    img, _ = P2.mac(V.image(cf, 16384), put); P1.load_image(cf, img)
    e, frees, steps = [], [], []
    for k in range(8):
        b = V.Elf2K(cf, keys=b'CD DOCS\rLW2 NOTE.TXT\r', later=[('press any key', b' '), ('writes it back', b'\x18')])
        b.rtc = P3.clock(); c = b.c
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        n0 = 0
        st = P4.run_to_back(b, 900_000_000)
        if st != 'stop' or 'Opened NOTE.TXT' not in clean(b.text()): e.append('open %d: %s %r' % (k, st, clean(b.text())[-200:]))
        rc, free = P2.fsck_free(V.image(cf, 16384)); frees.append(free[1])
        if rc: e.append('open %d: fsck %d' % (k, rc))
    if len(set(frees[1:])) != 1: e.append('the free clusters went %s' % frees)
    _, fl = P2.mac(V.image(cf, 16384), P5.walk)
    for n, d in (('DOCS/A.TXT', b'first\n'), ('DOCS/NOTE.TXT', b'the note\n' * 50), ('DOCS/B.TXT', b'last\n')):
        if fl.get(n) != d: e.append('%s: %r' % (n, (fl.get(n) or b'')[:40]))
    report('LW2 NOTE.TXT in /DOCS 8 times (A.TXT and B.TXT with it): the folder does not grow (free clusters %s), '
           'the files stay, fsck clean' % frees[-1], e)
    # a folder already swollen (Craig's DOCS: sectors of deleted entries after the document's): one open takes
    # the folder's end back - the next opens are as quick as in a short folder; the files stay
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        os.makedirs(os.path.join(m, 'DOCS'))
        open(os.path.join(m, 'LW2.STL'), 'wb').write(lw2)
        open(os.path.join(m, 'DOCS', 'KEEP.TXT'), 'wb').write(b'keep me\n')
        open(os.path.join(m, 'DOCS', 'NOTE.TXT'), 'wb').write(b'the note\n')
        for k in range(60): open(os.path.join(m, 'DOCS', 'JUNK%02d.TXT' % k), 'wb').write(b'x')
    img, _ = P2.mac(V.image(cf, 16384), put)
    img, _ = P2.mac(img, lambda m: [os.remove(os.path.join(m, 'DOCS', 'JUNK%02d.TXT' % k)) for k in range(60)])
    P1.load_image(cf, img)
    e, cost = [], []
    for k in range(3):
        b = V.Elf2K(cf, keys=b'CD DOCS\rLW2 NOTE.TXT\r', later=[('press any key', b' '), ('writes it back', b'\x18')])
        b.rtc = P3.clock(); c = b.c
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        st = P4.run_to_back(b, 900_000_000); cost.append(b.c.steps if hasattr(b.c, 'steps') else 0)
        if st != 'stop' or 'Opened NOTE.TXT' not in clean(b.text()): e.append('open %d: %s' % (k, st))
    rc, _ = P2.fsck_free(V.image(cf, 16384))
    _, fl = P2.mac(V.image(cf, 16384), P5.walk)
    if rc: e.append('fsck %d' % rc)
    if fl.get('DOCS/KEEP.TXT') != b'keep me\n' or fl.get('DOCS/NOTE.TXT') != b'the note\n': e.append('files: %r' % sorted(fl))
    if any(n.startswith('DOCS/JUNK') for n in fl): e.append('a deleted file came back')
    report('a swollen folder (60 deleted entries after the document): opened 3 times - the files stay, fsck clean', e)
    # a second open of a file the first open laid out: ATTACH sees it and writes nothing (on Craig's 8 MB card an
    # open took 8 s, most of it the rewrite). ^X then: nothing changed - the text, the date; ^W: only Lite-Writer's
    # own writes (the text's sectors, the FAT sector in both copies, the directory sector); after it, still none.
    for path, folders in (('DOC.TXT', []), ('DOCS/NOTE.TXT', ['DOCS'])):
        cf, e2k, st = P1.installed_full(mem, 16384)
        body = b'Leave me be\r\nas I am\r\n'
        def put(m):
            for d in folders: os.makedirs(os.path.join(m, d))
            open(os.path.join(m, 'LW2.STL'), 'wb').write(lw2)
            if folders: open(os.path.join(m, 'DOCS', 'OTHER.TXT'), 'wb').write(b'other\n')
            open(os.path.join(m, *path.split('/')), 'wb').write(body); os.utime(os.path.join(m, *path.split('/')), (OLD, OLD))
        img, _ = P2.mac(V.image(cf, 16384), put); P1.load_image(cf, img)
        nm = path.split('/')[-1]
        cmd = (b'CD DOCS\rLW2 NOTE.TXT\r' if folders else b'LW2 DOC.TXT\r')
        e = []
        for k, typed, want, when in ((0, None, body, OLD), (1, None, body, OLD),
                                     (2, b'Top. ', b'Top. Leave me be\nas I am\n', 'save'), (3, None, None, 'save')):
            later = ([('press any key', b' '), ('writes it back', b'\x18')] if typed is None else
                     [('press any key', b' '), ('writes it back', typed + b'\x17'), ('bytes to ', b'\x18')])
            b = V.Elf2K(cf, keys=cmd, later=later); b.rtc = P3.clock(); c = b.c
            c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
            n0 = len(V.writes(cf))
            st = P4.run_to_back(b, 900_000_000)
            w = V.writes(cf)[n0:]
            t = clean(b.text())
            if st != 'stop' or 'Opened %s' % nm not in t: e.append('open %d: %s %r' % (k, st, t[-200:]))
            if k == 0 and not w: e.append('open 0 (the Mac\'s file): nothing written - it was not laid out')
            if k in (1, 3) and w: e.append('open %d: %d sectors written %s' % (k, len(w), w[:12]))
            if k == 2 and len(w) != (len(want) + 511) // 512 + 3:
                e.append('open 2, ^W: %d sectors written %s (want the text\'s, 2 FAT, 1 directory)' % (len(w), w))
            img = V.image(cf, 16384)
            rc, _ = P2.fsck_free(img)
            if rc: e.append('open %d: fsck_msdos %d' % (k, rc))
            _, (got, mt) = P2.mac(img, lambda m: (open(os.path.join(m, *path.split('/')), 'rb').read(),
                                                  os.stat(os.path.join(m, *path.split('/'))).st_mtime))
            if want is None: want = last
            if got != want: e.append('open %d: the Mac reads %r (want %r)' % (k, got, want))
            if when == OLD and mt != OLD: e.append('open %d: the Mac dates it %s (want %s)' % (k, time.ctime(mt), time.ctime(OLD)))
            if when == 'save' and time.localtime(mt)[:5] != MAC1430:
                e.append('open %d: the Mac dates it %s (want the ^W save, 2026-10-16 14:30)' % (k, time.ctime(mt)))
            last = got
            if folders:
                _, fl = P2.mac(img, P5.walk)
                if fl.get('DOCS/OTHER.TXT') != b'other\n': e.append('open %d: DOCS/OTHER.TXT %r' % (k, fl.get('DOCS/OTHER.TXT')))
        report('LW2 %s 4 times (^X, ^X, ^W, ^X): the 2nd and 4th open write nothing, ^W only its own sectors; '
               'the text and date stay, fsck clean' % path, e)
    # no NAME.PRG and no NAME.STL: still an unknown command (STELLAR.PRG says it, as the kernel would); a missing
    # second app is named as before
    cf, e2k, st = P1.installed_full(mem, 16384)
    img, _ = P2.mac(V.image(cf, 16384), lambda m: open(os.path.join(m, 'LW2.STL'), 'wb').write(lw2))
    P1.load_image(cf, img)
    b, st, t = P3.session(cf, b'DIRR\rLW2 NOPE\rMON\r', rtc=P3.clock())
    e = []
    if 'Unknown command: DIRR  (see HELP)' not in P2.session_out(t, 'DIRR\r'): e.append('DIRR: %r' % P2.session_out(t, 'DIRR\r'))
    if 'NOPE.STL is not on the card.' not in P2.session_out(t, 'LW2 NOPE\r'): e.append('LW2 NOPE: %r' % P2.session_out(t, 'LW2 NOPE\r'))
    if st != 'stop': e.append('MON: %s' % st)
    report('DIRR (no DIRR.PRG, no DIRR.STL): "Unknown command: DIRR"; LW2 NOPE: "NOPE.STL is not on the card."', e)
    print('LTOS + Lite-Writer 2: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
