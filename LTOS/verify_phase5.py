# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 5 in the simulator: folders.

  * MKDIR / CD / RMDIR, paths with '/' (GAMES/A.BIN, /HELP.TXT, .., CD /), the prompt "LTOS /GAMES/OLD> ";
    files SAVEd into a folder; the Mac and fsck_msdos agree with what LTOS made (8 MB and 32 MB cards);
  * a folder grows past its first cluster (40 files in one);
  * folders the Mac made (long names in them too): TYPE DOCS/INSIDE.TXT, CD DOCS/SUB, DIR DOCS;
  * RMDIR refuses a folder with something in it and the current folder; an empty one goes, its cluster freed;
  * the auto-run finds a program in the root from inside a folder; errors: no such folder, '\\' in a path.

    python3 LTOS/verify_phase5.py [-v]
"""
import os, sys, re
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build
import verify_phase4 as P4

PROMPT = re.compile(r'LTOS(?: (/[^>\r\n]*))?> ')


def outs(t):
    """[(prompt path, the command typed, its output)] for every command in a transcript."""
    ms = list(PROMPT.finditer(t))
    res = []
    for a, b in zip(ms, ms[1:]):
        body = t[a.end():b.start()]
        cmd, _, rest = body.partition('\r\n'); cmd = cmd.rstrip('\r')
        res.append((a.group(1) or '', cmd, re.sub(r'-- more: a key goes on, Q stops --.\r {35}\r', '', rest, flags=re.S)))
    return res


def out_of(t, cmd, nth=0):
    hits = [(p, o) for p, c, o in outs(t) if c == cmd]
    return hits[nth] if len(hits) > nth else (None, None)


def walk(m):
    """Every file and folder under the mount point: {'GAMES/A.BIN': bytes or 'DIR'}."""
    res = {}
    for root, ds, fs in os.walk(m):
        ds[:] = [d for d in ds if not d.startswith('.')]
        rel = os.path.relpath(root, m)
        for d in ds: res[os.path.normpath(os.path.join(rel, d))] = 'DIR'
        for f in fs:
            if f.startswith('.'): continue
            res[os.path.normpath(os.path.join(rel, f))] = open(os.path.join(root, f), 'rb').read()
    return res


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    pat = bytes((i * 7 + 3) & 0xFF for i in range(256))
    ram = lambda M: M.__setitem__(slice(0x5000, 0x5100), pat)

    # ---- 1: MKDIR, CD, paths, the prompt; the Mac reads it all
    for mb in (8, 32):
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        keys = (b'MKDIR GAMES\rCD GAMES\rSAVE A.BIN 5000 50FF\rMKDIR OLD\rCD OLD\rCD\rSAVE B.BIN 5000 500F\r'
                b'CD ..\rCD\rCD /\rDIR GAMES\rDIR GAMES/OLD\rCD GAMES/OLD\rTYPE /HELP.TXT\r' + P1.PAGES + b'CD ../..\r'
                b'COPY GAMES/A.BIN /C.BIN\rCD /GAMES/\rFREE\rMON\r')
        b, st, t = P3.session(cf, keys, rtc=P3.clock(), ram=ram)
        e = []
        p, o = out_of(t, 'CD')
        if p != '/GAMES/OLD' or o.strip() != '/GAMES/OLD': e.append('CD in /GAMES/OLD: %r %r' % (p, o))
        p, o = out_of(t, 'CD', 1)
        if p != '/GAMES' or o.strip() != '/GAMES': e.append('CD after CD ..: %r %r' % (p, o))
        p, o = out_of(t, 'DIR GAMES')
        if p != '' or not o or 'A        BIN' not in o or 'OLD' not in o: e.append('DIR GAMES: %r' % o)
        p, o = out_of(t, 'DIR GAMES/OLD')
        if not o or 'B        BIN' not in o or 'A        BIN' in o: e.append('DIR GAMES/OLD: %r' % o)
        p, o = out_of(t, 'TYPE /HELP.TXT')
        if p != '/GAMES/OLD' or not o or 'MKDIR' not in o: e.append('TYPE /HELP.TXT from /GAMES/OLD: %r %r' % (p, (o or '')[:200]))
        p, o = out_of(t, 'COPY GAMES/A.BIN /C.BIN')
        if p != '': e.append('CD ../.. did not reach the root: %r' % p)
        p, o = out_of(t, 'FREE')
        if p != '/GAMES': e.append('CD /GAMES/: the prompt %r' % p)
        if st != 'stop': e.append('MON: %s' % st)
        img = V.image(cf, n)
        rc, _ = P2.fsck_free(img)
        if rc: e.append('fsck_msdos: %d' % rc)
        _, fl = P2.mac(img, walk)
        want = {'GAMES': 'DIR', 'GAMES/OLD': 'DIR', 'GAMES/A.BIN': pat, 'GAMES/OLD/B.BIN': pat[:16], 'C.BIN': pat}
        for k, v in want.items():
            if fl.get(k) != v: e.append('the Mac: %s = %r' % (k, fl.get(k) if not isinstance(fl.get(k), bytes) else fl.get(k)[:16]))
        if '-v' in sys.argv and mb == 8: print(t[-3000:])
        report('%d MB: MKDIR / CD / paths / the prompt; SAVE and COPY into and out of folders; TYPE /HELP.TXT from '
               'a folder; fsck and the Mac agree' % mb, e)

    # ---- 2: a folder grows: 40 files in one (8 MB: 16 entries a cluster)
    cf, e2k, st = P1.installed_full(mem, 16384)
    keys = b'MKDIR MANY\rCD MANY\r' + b''.join(b'SAVE F%02d.BIN 5000 5000\r' % i for i in range(40)) + b'CD /\rMON\r'
    b, st, t = P3.session(cf, keys, rtc=P3.clock(), ram=ram, cap=3_000_000_000)
    e = []
    if t.count('Saved F') < 40 or 'full' in t: e.append(repr(t[-400:]))
    img = V.image(cf, 16384)
    rc, _ = P2.fsck_free(img)
    if rc: e.append('fsck_msdos: %d' % rc)
    _, fl = P2.mac(img, walk)
    got = sorted(k for k in fl if k.startswith('MANY/'))
    if got != ['MANY/F%02d.BIN' % i for i in range(40)] or any(fl[k] != pat[:1] for k in got):
        e.append('the Mac sees %d files in MANY' % len(got))
    report('a folder grows past its first cluster: 40 files in MANY (fsck, the Mac)', e)

    # ---- 3: folders the Mac made
    cf, e2k, st = P1.installed_full(mem, 16384)
    img = V.image(cf, 16384)
    def mk(m):
        os.makedirs(os.path.join(m, 'DOCS', 'SUB'))
        open(os.path.join(m, 'DOCS', 'INSIDE.TXT'), 'wb').write(b'inside the folder\n')
        open(os.path.join(m, 'DOCS', 'A long name.txt'), 'wb').write(b'long\n')
        open(os.path.join(m, 'DOCS', 'SUB', 'DEEP.TXT'), 'wb').write(b'two down\n')
    img, _ = P2.mac(img, mk)
    P1.load_image(cf, img)
    keys = b'TYPE DOCS/INSIDE.TXT\rCD DOCS/SUB\rTYPE DEEP.TXT\rCD ../..\rDIR DOCS\rCD DOCS\rCD\rMON\r'
    b, st, t = P3.session(cf, keys, rtc=P3.clock())
    e = []
    p, o = out_of(t, 'TYPE DOCS/INSIDE.TXT')
    if not o or 'inside the folder' not in o: e.append('TYPE DOCS/INSIDE.TXT: %r' % o)
    p, o = out_of(t, 'TYPE DEEP.TXT')
    if p != '/DOCS/SUB' or not o or 'two down' not in o: e.append('TYPE DEEP.TXT in DOCS/SUB: %r %r' % (p, o))
    p, o = out_of(t, 'DIR DOCS')
    if p != '' or not o or 'INSIDE   TXT' not in o or 'SUB' not in o: e.append('DIR DOCS: %r %r' % (p, o))
    p, o = out_of(t, 'CD')
    if p != '/DOCS' or o.strip() != '/DOCS': e.append('CD: %r %r' % (p, o))
    report('folders the Mac made: TYPE DOCS/INSIDE.TXT, CD DOCS/SUB, CD ../.., DIR DOCS', e)

    # ---- 4: RMDIR; errors; the auto-run from a folder
    cf, e2k, st = P1.installed_full(mem, 16384)
    rc0, free0 = P2.fsck_free(V.image(cf, 16384))
    keys = (b'MKDIR X\rMKDIR X/Y\rRMDIR X\rCD X/Y\rRMDIR /X/Y\rHELLO\rCD NOPE\rTYPE NOPE/A.TXT\r'
            b'CD ' + bytes([0x5C]) + b'X\rMKDIR /X/Y\rCD /\rRMDIR X/Y\rRMDIR X\rRMDIR X\rMON\r')
    b, st, t = P3.session(cf, keys, rtc=P3.clock())
    e = []
    o = out_of(t, 'RMDIR X')[1]
    if not o or 'not empty' not in o: e.append('RMDIR X with Y in it: %r' % o)
    o = out_of(t, 'RMDIR /X/Y')[1]
    if not o or 'current folder' not in o: e.append('RMDIR of the current folder: %r' % o)
    p, o = out_of(t, 'HELLO')
    if p != '/X/Y' or not o or 'Unknown' in o: e.append('HELLO (HELLO.PRG in the root) from /X/Y: %r' % o)
    o = out_of(t, 'CD NOPE')[1]
    if not o or 'There is no folder NOPE' not in o: e.append('CD NOPE: %r' % o)
    o = out_of(t, 'TYPE NOPE/A.TXT')[1]
    if not o or 'There is no folder NOPE' not in o: e.append('TYPE NOPE/A.TXT: %r' % o)
    o = out_of(t, 'CD \\X')[1]
    if not o or 'not a file name' not in o: e.append('CD \\X: %r' % o)
    o = out_of(t, 'MKDIR /X/Y')[1]
    if not o or 'already' not in o: e.append('MKDIR /X/Y again: %r' % o)
    o = out_of(t, 'RMDIR X', 2)[1]
    if not o or 'There is no folder X' not in o: e.append('RMDIR X when it is gone: %r' % o)
    if st != 'stop': e.append('MON: %s' % st)
    img = V.image(cf, 16384)
    rc, free = P2.fsck_free(img)
    if rc or free != free0: e.append('fsck_msdos: %d, free %r (before: %r)' % (rc, free, free0))
    _, fl = P2.mac(img, walk)
    if 'X' in fl: e.append('the Mac still sees X')
    if '-v' in sys.argv: print(t[-2500:])
    report('RMDIR: a folder with something in it and the current folder refused, empty ones go (clusters back); '
           'HELLO from a folder runs the root\'s; no such folder; a backslash is not a name', e)

    # ---- deeper than 5: the prompt shows "/..." and the last five
    cf, e2k, st = P1.installed_full(mem, 16384)
    keys = b''.join(b'MKDIR LEVEL%d\rCD LEVEL%d\r' % (i, i) for i in range(1, 8)) + b'CD\rCD /\rMON\r'
    b, st, t = P3.session(cf, keys, rtc=P3.clock())
    p, o = out_of(t, 'CD')
    want = '/.../LEVEL3/LEVEL4/LEVEL5/LEVEL6/LEVEL7'
    e = [] if (p == want and o.strip() == want and st == 'stop') else ['%r %r %s' % (p, o, st)]
    report('7 folders deep: the prompt and CD show "/..." then the last five', e)

    # ---- 5 (5c): MV - into a folder, renamed, up a level, a folder moved (its '..' follows), refusals
    for mb in (8, 32):
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        keys = (b'SAVE A.BIN 5000 50FF\rMKDIR D\rMKDIR E\rMV A.BIN D\rMV D/A.BIN D/B.BIN\rCD D\rMV B.BIN ..\rCD /\r'
                b'MV E D\rCD D/E\rCD ..\rCD /\rMV D D/E\rMV NOPE.BIN D\rSAVE C.BIN 5000 500F\rMV B.BIN D/E/\r'
                b'MV C.BIN D/E/B.BIN\rMON\r')
        b, st, t = P3.session(cf, keys, rtc=P3.clock(), ram=ram)
        e = []
        p, o = out_of(t, 'CD /', 1)
        if p != '/D': e.append('CD .. from /D/E (the moved folder\'s ..): the prompt %r' % p)
        o = out_of(t, 'MV D D/E')[1]
        if not o or 'cannot go into itself' not in o: e.append('MV D D/E: %r' % o)
        o = out_of(t, 'MV NOPE.BIN D')[1]
        if not o or 'There is no file NOPE.BIN' not in o: e.append('MV NOPE.BIN D: %r' % o)
        o = out_of(t, 'MV C.BIN D/E/B.BIN')[1]
        if not o or 'There is already a B.BIN' not in o: e.append('MV onto a taken name: %r' % o)
        if st != 'stop': e.append('MON: %s' % st)
        img = V.image(cf, n)
        rc, _ = P2.fsck_free(img)
        if rc: e.append('fsck_msdos: %d' % rc)
        _, fl = P2.mac(img, walk)
        want = {'D': 'DIR', 'D/E': 'DIR', 'D/E/B.BIN': pat, 'C.BIN': pat[:16]}
        extra = sorted(k for k in fl if k.endswith('.BIN') and k not in want and k != 'STELLAR.BIN')
        if extra: e.append('left behind: %r' % extra)
        for k, v in want.items():
            if fl.get(k) != v: e.append('the Mac: %s = %r' % (k, fl.get(k) if not isinstance(fl.get(k), bytes) else fl.get(k)[:16]))
        if '-v' in sys.argv and mb == 8: print(t[-3000:])
        report('%d MB: MV into a folder, renamed in one, up with .., a folder into another (its .. follows), into '
               'itself / a missing file / a taken name refused; fsck and the Mac agree' % mb, e)

    # ---- wildcards: COPY *.DAT D, MV *.DAT E - into folders only, a name already there is left alone
    for mb in (8, 32):
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        keys = (b'SAVE A1.DAT 5000 50FF\rSAVE A2.DAT 5000 500F\rSAVE B.BAK 5000 5000\rMKDIR D\rMKDIR E\r'
                b'COPY *.DAT D\rCOPY A*.DAT D\rMV *.DAT E\rMV D/*.DAT E\rMV *.BAK D/\rMV *.DAT NOPE.DAT\r'
                b'COPY E/*.DAT E\rMON\r')
        b, st, t = P3.session(cf, keys, rtc=P3.clock(), ram=ram)
        e = []
        for cmd, want in (('COPY *.DAT D', ['A1.DAT', 'A2.DAT', '2 copied.']),
                          ('COPY A*.DAT D', ['has one already: not copied', '0 copied.']),
                          ('MV *.DAT E', ['A1.DAT', 'A2.DAT', '2 moved.']),
                          ('MV D/*.DAT E', ['left where it is', '0 moved.']),
                          ('MV *.BAK D/', ['B.BAK', '1 moved.']),
                          ('MV *.DAT NOPE.DAT', ['must be a folder']),
                          ('COPY E/*.DAT E', ['in that folder already'])):
            o = out_of(t, cmd)[1] or ''
            if any(w not in o for w in want): e.append('%s: %r' % (cmd, o))
        if st != 'stop': e.append('MON: %s' % st)
        img = V.image(cf, n)
        rc, _ = P2.fsck_free(img)
        if rc: e.append('fsck_msdos: %d' % rc)
        _, fl = P2.mac(img, walk)
        want = {'D/A1.DAT': pat, 'D/A2.DAT': pat[:16], 'E/A1.DAT': pat, 'E/A2.DAT': pat[:16], 'D/B.BAK': pat[:1]}
        for k, v in want.items():
            if fl.get(k) != v: e.append('the Mac: %s = %r' % (k, fl.get(k) if not isinstance(fl.get(k), bytes) else fl.get(k)[:16]))
        left = sorted(k for k in fl if k in ('A1.DAT', 'A2.DAT', 'B.BAK'))
        if left: e.append('still in the root: %r' % left)
        if '-v' in sys.argv and mb == 8: print(t[-2500:])
        report('%d MB: COPY *.DAT D, MV *.DAT E, MV *.BAK D/ - each named, "already there" left alone, counts; '
               'not a folder / the same folder refused; fsck and the Mac agree' % mb, e)

    # ---- 6 (5c): STELLAR finds the firmware and apps in this folder, else the root
    import opcode_sweep as S
    stl = bytes(S.image('37')[0:0x2F00])
    new = bytearray(stl); new[0x2EF0:0x2F00] = b'FIRMWARE IN FW/!'; new = bytes(new)
    lst = open(os.path.join(HERE, '..', 'APPLICATIONS', 'CLOCK', 'Time-Grab.lst')).read()
    stlapp = build.stl_of(lst)
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        os.makedirs(os.path.join(m, 'FW'))
        open(os.path.join(m, 'FW', 'S2.BIN'), 'wb').write(new)
        open(os.path.join(m, 'TG.STL'), 'wb').write(stlapp)
        open(os.path.join(m, 'FW', 'TG2.STL'), 'wb').write(stlapp)
    img, _ = P2.mac(V.image(cf, 16384), put)
    for how, keys, fw in (('CD FW, STELLAR S2.BIN (here)', b'CD FW\rSTELLAR S2.BIN\r', new),
                          ('CD FW, STELLAR (the root\'s STELLAR.BIN)', b'CD FW\rSTELLAR\r', stl),
                          ('STELLAR FW/S2.BIN TG FW/TG2 (a path; an app in the root)', b'STELLAR FW/S2.BIN TG FW/TG2\r', new),
                          ('CD FW, STELLAR S2.BIN TG (the app from the root)', b'CD FW\rSTELLAR S2.BIN TG\r', new)):
        P1.load_image(cf, img)
        b = V.Elf2K(cf, keys=keys); b.rtc = P3.clock(); c = b.c
        b.c.M[0:0x2F00] = bytes(0x2F00)
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        st = b.run(900_000_000, stop=0x0000)
        e = []
        if st != 'stop' or 'Starting STELLAR ... done.' not in b.text(): e.append('%s: %r' % (st, b.text()[-300:]))
        elif bytes(c.M[0:0x2F00]) != P4.with_back(fw): e.append('the wrong firmware in RAM')
        report('5c %s' % how, e)
    P1.load_image(cf, img)
    b, st, t = P3.session(cf, b'CD FW\rSTELLAR /S2.BIN\rSTELLAR /TG2\rMON\r', rtc=P3.clock())
    e = [] if ('S2.BIN is not on the card' in t and 'TG2.STL is not on the card.' in t) else [repr(t[-500:])]
    report('5c a path with / is looked for only there: STELLAR /S2.BIN, STELLAR /TG2 refused from FW', e)

    # ---- 7: /BIN - a program not here or in the root is looked for in /BIN; it still starts in this folder
    cf, e2k, st = P1.installed_full(mem, 16384)
    def tobin(m):
        os.makedirs(os.path.join(m, 'BIN'))
        os.makedirs(os.path.join(m, 'DOCS'))
        open(os.path.join(m, 'DOCS', 'NOTE.TXT'), 'wb').write(b'a note in DOCS\n')
        open(os.path.join(m, 'BIN', 'HI.PRG'), 'wb').write(open(os.path.join(m, 'HELLO.PRG'), 'rb').read())
        for n in ('TYPE.PRG', 'STELLAR.PRG', 'STELLAR.BIN'): os.rename(os.path.join(m, n), os.path.join(m, 'BIN', n))
        open(os.path.join(m, 'BIN', 'TG.STL'), 'wb').write(stlapp)
    img, _ = P2.mac(V.image(cf, 16384), tobin)
    P1.load_image(cf, img)
    hello = out_of(P3.session(cf, b'HELLO\rMON\r', rtc=P3.clock())[2], 'HELLO')[1]
    P1.load_image(cf, img)
    b, st, t = P3.session(cf, b'HI\rCD DOCS\rHI\rTYPE NOTE.TXT\rDOCS/HI\rCD /\rTYPE DOCS/NOTE.TXT\rMON\r',
                          rtc=P3.clock())
    e = []
    p, o = out_of(t, 'HI')
    if p != '' or not hello or o != hello: e.append('HI from the root: %r (HELLO gave %r)' % (o, hello))
    p, o = out_of(t, 'HI', 1)
    if p != '/DOCS' or o != hello: e.append('HI from /DOCS: %r %r' % (p, o))
    p, o = out_of(t, 'TYPE NOTE.TXT')
    if p != '/DOCS' or not o or 'a note in DOCS' not in o: e.append('TYPE (in /BIN) NOTE.TXT from /DOCS: %r %r' % (p, o))
    o = out_of(t, 'DOCS/HI')[1]
    if not o or 'Unknown command' not in o: e.append('DOCS/HI (a path: only there): %r' % o)
    o = out_of(t, 'TYPE DOCS/NOTE.TXT')[1]
    if not o or 'a note in DOCS' not in o: e.append('TYPE DOCS/NOTE.TXT from the root: %r' % o)
    if st != 'stop': e.append('MON (STELLAR.BIN in /BIN): %s' % st)
    if '-v' in sys.argv: print(t[-2500:])
    report('/BIN: HI (BIN/HI.PRG) from the root and from /DOCS; TYPE.PRG in /BIN types /DOCS\'s NOTE.TXT; '
           'DOCS/HI refused; MON finds BIN/STELLAR.BIN', e)
    P1.load_image(cf, img)
    b = V.Elf2K(cf, keys=b'CD DOCS\rSTELLAR TG\r'); b.rtc = P3.clock(); c = b.c
    b.c.M[0:0x2F00] = bytes(0x2F00)
    c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
    st = b.run(900_000_000, stop=0x0000)
    e = []
    if st != 'stop' or 'Starting STELLAR ... done.' not in b.text(): e.append('%s: %r' % (st, b.text()[-300:]))
    elif bytes(c.M[0:0x2F00]) != P4.with_back(stl): e.append('the wrong firmware in RAM')
    report('/BIN: CD DOCS, STELLAR TG - STELLAR.PRG, STELLAR.BIN and TG.STL all from /BIN', e)

    # ---- 8: RECV SYSTEM with a /BIN folder: every .PRG/.STL into /BIN, HELP.TXT into the root; without one,
    #      all of them into the current folder (as before)
    sysf = {n[:8].decode().strip() + '.' + n[8:].decode().strip(): d for n, d in build.samples()}
    progs = sorted(k for k in sysf if k.endswith(('.PRG', '.STL')))
    def recv_system(cf, folder):
        later = []
        for nm in build.sysparts():
            fp = os.path.join(build.OUT, nm)
            if not os.path.exists(fp): continue
            if later: later.append(('LTOS /%s> ' % folder, b'RECV SYSTEM\r'))
            later.append(('Ctrl-C stops.', open(fp).read().replace('\n', '\r\n').encode()))
        later.append(('LTOS /%s> ' % folder, b'MON\r'))
        return P3.session(cf, b'CD %s\rRECV SYSTEM\r' % folder.encode(), rtc=P3.clock(), cap=1_800_000_000, later=later)
    cf, e2k, st = P1.installed_full(mem, 16384)
    def binned(m):                                  # Craig's card: every program in /BIN, one of them stale
        os.makedirs(os.path.join(m, 'BIN')); os.makedirs(os.path.join(m, 'DOCS'))
        open(os.path.join(m, 'DOCS', 'NOTE.TXT'), 'wb').write(b'a note in DOCS\n')
        for n in progs: os.rename(os.path.join(m, n), os.path.join(m, 'BIN', n))
        open(os.path.join(m, 'BIN', 'HELLO.PRG'), 'wb').write(b'\x50\x00\x00\x01\x50\x00\x00')
        os.remove(os.path.join(m, 'HELP.TXT'))
    img, _ = P2.mac(V.image(cf, 16384), binned)
    P1.load_image(cf, img)
    b, st, t = recv_system(cf, 'DOCS')
    _, fl = P2.mac(V.image(cf, 16384), walk)
    e = []
    if st != 'stop' or t.count(' saved') < len(sysf): e.append('%s: %r' % (st, t[-400:]))
    for n in progs:
        if fl.get('BIN/' + n) != sysf[n]: e.append('BIN/%s: %s' % (n, 'missing' if 'BIN/' + n not in fl else 'not the new one'))
        if n in fl: e.append('%s also in the root' % n)
    if fl.get('HELP.TXT') != sysf['HELP.TXT']: e.append('HELP.TXT not in the root')
    if 'BIN/HELP.TXT' in fl: e.append('HELP.TXT in /BIN')
    if sorted(k for k in fl if k.startswith('DOCS/')) != ['DOCS/NOTE.TXT']: e.append('DOCS: %r' % sorted(k for k in fl if k.startswith('DOCS/')))
    if '-v' in sys.argv: print(t[-2500:])
    report('RECV SYSTEM (from /DOCS) with /BIN: every program into /BIN, replacing; HELP.TXT into the root', e)
    cf, e2k, st = P1.installed_full(mem, 16384)
    img, _ = P2.mac(V.image(cf, 16384), lambda m: os.makedirs(os.path.join(m, 'DOCS')))
    P1.load_image(cf, img)
    b, st, t = recv_system(cf, 'DOCS')
    _, fl = P2.mac(V.image(cf, 16384), walk)
    e = []
    if st != 'stop' or t.count(' saved') < len(sysf): e.append('%s: %r' % (st, t[-400:]))
    for n, d in sysf.items():
        if fl.get('DOCS/' + n) != d: e.append('DOCS/%s: %s' % (n, 'missing' if 'DOCS/' + n not in fl else 'different'))
    if any(k.startswith('BIN') for k in fl): e.append('a BIN appeared')
    report('RECV SYSTEM (from /DOCS) with no /BIN: every file into /DOCS, as before', e)

    print('LTOS phase 5: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
