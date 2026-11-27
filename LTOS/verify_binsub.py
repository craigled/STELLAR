# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Programs in folders under /BIN: a typed NAME is looked for here, in the root, in /BIN, then in each folder in /BIN
(one level down, in the order DIR /BIN lists them; the first found wins). A card as Craig makes one (every program in
/BIN), then the Mac sorts some into /BIN/SYS and /BIN/GAMES:

  * NAME.PRG (ECHO) and NAME.SH (HI) in a folder run; SH.PRG itself in /BIN/SYS; SH HI finds the script too;
  * HELP.PRG and HELP.HLP in /BIN/SYS: HELP ECHO; NANO.PRG in /BIN/GAMES with NANO.OVL and ATTACH.PRG in /BIN/SYS;
  * a STELLAR app: LW2.STL in /BIN/GAMES, STELLAR.PRG and ATTACH.PRG in /BIN/SYS - LW2 starts Lite-Writer;
  * two of one name: /BIN's own wins, then the first folder's; a folder two levels down is not searched;
    a name nowhere: still "Unknown command";
  * how long it takes at 1.79 MHz: a program in /BIN, in the first folder, in the second, and an unknown name.

    python3 LTOS/verify_binsub.py [-v]
"""
import os, re, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_phase4 as P4
import build

N = 16384
SYS = ('SH.PRG', 'STELLAR.PRG', 'ATTACH.PRG', 'HELP.PRG', 'HELP.HLP', 'ECHO.PRG', 'NANO.OVL')


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    cf, e2k, st = P1.installed_full(mem, N)
    lw2 = build.stl_of(open(os.path.join(HERE, '..', 'APPLICATIONS', 'Lite-Writer-2', 'Lite-Writer-2.lst')).read())

    def put(m):
        b = os.path.join(m, 'BIN'); s = os.path.join(b, 'SYS'); g = os.path.join(b, 'GAMES')
        os.makedirs(b, exist_ok=True)                                # (a card made without /BIN: RECV SYSTEM put
        for f in os.listdir(m):                                      #  everything in the root - the programs to
            if f.endswith(('.PRG', '.STL')) and os.path.isfile(os.path.join(m, f)):   #  /BIN, as SYSRX does)
                os.rename(os.path.join(m, f), os.path.join(b, f))
        os.makedirs(s); os.makedirs(g); os.makedirs(os.path.join(g, 'OLD'))
        where = lambda f: next((p for p in (os.path.join(b, f), os.path.join(m, f)) if os.path.exists(p)), None)
        missing = [f for f in SYS + ('NANO.PRG', 'PWD.PRG') if not where(f)]
        if missing: return missing
        for f in SYS: os.rename(where(f), os.path.join(s, f))
        os.rename(os.path.join(b, 'NANO.PRG'), os.path.join(g, 'NANO.PRG'))
        pwd, echo = open(os.path.join(b, 'PWD.PRG'), 'rb').read(), open(os.path.join(s, 'ECHO.PRG'), 'rb').read()
        w = lambda p, d: open(os.path.join(b, p), 'wb').write(d)
        w('GAMES/LW2.STL', lw2)
        w('GAMES/HI.SH', b'ECHO hi from games\r\n')
        w('DUP.PRG', pwd); w('SYS/DUP.PRG', echo)                 # /BIN's own first
        w('SYS/TWO.PRG', pwd); w('GAMES/TWO.PRG', echo)           # then the first folder's
        w('GAMES/OLD/DEEP.PRG', pwd)                              # two levels down: not looked in
        w('T0.PRG', pwd); w('SYS/T1.PRG', pwd); w('GAMES/T2.PRG', pwd)
        return missing
    img, missing = P2.mac(V.image(cf, N), put)
    P1.load_image(cf, img)
    base = img
    c = lambda x: ('LTOS> ', x.encode() + b'\r')
    clean = lambda t: re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', t.replace('\r', ''))

    def go(steps, cap=3_000_000_000):
        """A fresh boot of the sorted card, each prompt's keys in turn -> (end, text, steps at each prompt answered)"""
        P1.load_image(cf, base)
        b = V.Elf2K(cf, keys=b'', later=steps); b.rtc = P3.clock()
        marks = []
        feed0 = b.u.feed
        def feed():
            n = len(b.u.later); feed0()
            if len(b.u.later) < n: marks.append(b.steps)
        b.u.feed = feed
        s = b.boot_rom(cap)
        return s, clean(b.text()), marks

    def outs(t):
        return dict((p.split('\n', 1)[0], p.split('\n', 1)[1] if '\n' in p else '') for p in re.split(r'(?m)^LTOS> ', t))

    cmds = ['DIR /BIN', 'ECHO hello', 'HI', 'SH HI', 'DUP x', 'TWO x', 'DEEP', 'HELP ECHO', 'NOPE']
    s, t, _ = go([c(x) for x in cmds] + [c('MON')])
    o = outs(t)
    if v: print(t[-3000:])
    e = ['not on the card made: %s' % ', '.join(missing)] if missing else []
    if s != 'stop': e.append('the end: %s %r' % (s, t[-300:]))
    d = o.get('DIR /BIN', '')
    if not ('SYS' in d and 'GAMES' in d and d.index('SYS') < d.index('GAMES')): e.append('DIR /BIN: SYS then GAMES? %r' % d[-400:])
    want = {'ECHO hello': 'hello', 'HI': 'hi from games', 'SH HI': 'hi from games', 'DUP x': '/', 'TWO x': '/'}
    for k, w in want.items():
        if o.get(k, '').strip() != w: e.append('%s: %r (want %r)' % (k, o.get(k), w))
    if 'Unknown command: DEEP' not in o.get('DEEP', ''): e.append('DEEP (two levels down): %r' % o.get('DEEP'))
    if 'Unknown command: NOPE' not in o.get('NOPE', ''): e.append('NOPE: %r' % o.get('NOPE'))
    if 'ECHO' not in o.get('HELP ECHO', '') or len(o.get('HELP ECHO', '')) < 40: e.append('HELP ECHO: %r' % o.get('HELP ECHO'))
    report('/BIN/SYS and /BIN/GAMES: ECHO.PRG and HI.SH (SH.PRG in SYS) run, SH HI too, HELP ECHO (HELP.PRG, HELP.HLP in '
           'SYS); DUP: /BIN\'s own wins, TWO: SYS\'s (listed first); DEEP (GAMES/OLD) and NOPE: Unknown command', e)

    e = []
    s, t, _ = go([c('NANO NOTE.TXT'), ('NANO 1.1', b'\x18'), c('MON')])
    if s != 'stop' or 'NANO 1.1' not in t or 'missing' in t: e.append('the end %s: %r' % (s, t[-400:]))
    report('NANO (NANO.PRG in GAMES): NANO.OVL and ATTACH.PRG found in SYS, NANO opens and ^X leaves', e)

    e = []
    P1.load_image(cf, base)
    b = V.Elf2K(cf, keys=b'LW2\r', later=[('press any key', b' '), ('^W asks for a name', b'\x18')]); b.rtc = P3.clock()
    b.c.R[2] = 0x7EF0; b.c.X = 2; b.c.R[0xE] = 0x0100; b.c.R[3] = 0xFF00; b.c.P = 3
    s = P4.run_to_back(b, 2_500_000_000)
    t = clean(b.text())
    if s != 'stop' or '^W asks for a name' not in t: e.append('the end %s: %r' % (s, t[-400:]))
    report('LW2: STELLAR.PRG (SYS) runs LW2.STL (GAMES), ATTACH.PRG from SYS - Lite-Writer starts, ^X leaves', e)

    e = []                                                       # RECV SYSTEM: a sorted /BIN stays sorted
    news = b'ECHO NEW\r\n'
    hx = build.intel_hex({i: x for i, x in enumerate(build.pak([(b'ECHO    PRG', build.prg('echo') + b'\0'),
                                                               (b'ZNEW    PRG', build.prg('pwd')), (b'ZNOTE   TXT', news)]))})
    hx = hx.replace('\n', '\r\n').encode()
    s, t, _ = go([c('RECV SYSTEM'), ('Ctrl-C stops.', hx), c('ECHO in place'), c('MON')])
    if v: print(t[-800:])
    _, fl = P2.mac(V.image(cf, N), lambda m: {p: open(os.path.join(m, p), 'rb').read() for p in
                                                ('BIN/SYS/ECHO.PRG', 'BIN/ECHO.PRG', 'BIN/ZNEW.PRG', 'ZNOTE.TXT', 'BIN/ZNOTE.TXT')
                                                if os.path.exists(os.path.join(m, p))})
    if s != 'stop': e.append('the end: %s %r' % (s, t[-300:]))
    if fl.get('BIN/SYS/ECHO.PRG') != build.prg('echo') + b'\0': e.append('BIN/SYS/ECHO.PRG not replaced')
    if 'BIN/ECHO.PRG' in fl: e.append('a second ECHO.PRG in /BIN')
    if fl.get('BIN/ZNEW.PRG') != build.prg('pwd'): e.append('ZNEW.PRG not in /BIN: %r' % sorted(fl))
    if fl.get('ZNOTE.TXT') != news or 'BIN/ZNOTE.TXT' in fl: e.append('ZNOTE.TXT not in the root: %r' % sorted(fl))
    if outs(t).get('ECHO in place', '').strip() != 'in place': e.append('ECHO after: %r' % outs(t).get('ECHO in place'))
    rc, _ = P2.fsck_free(V.image(cf, N))
    if rc: e.append('fsck_msdos: %d' % rc)
    report('RECV SYSTEM: ECHO.PRG replaced in /BIN/SYS where it is (no copy in /BIN), a new ZNEW.PRG into /BIN, '
           'ZNOTE.TXT into the root; fsck clean', e)

    e = []
    tc = ['T0 a', 'T1 a', 'T2 a', 'NOPE', 'T0 b']
    s, t, mk = go([c(x) for x in tc] + [c('MON')])
    o = outs(t)
    for x in tc[:3] + tc[4:]:
        if o.get(x, '').strip() != '/': e.append('%s: %r' % (x, o.get(x)))
    sec = [(mk[i + 1] - mk[i]) / 112000 for i in range(len(tc))]       # (1.79 MHz: 16 clocks an instruction)
    print('    at 1.79 MHz: in /BIN %.2f s, in SYS (folder 1) %.2f s, in GAMES (folder 2) %.2f s, unknown %.2f s'
          % (sec[0], sec[1], sec[2], sec[3]))
    if not sec[0] <= sec[1] <= sec[2] or sec[2] - sec[0] > 3: e.append('times %r' % sec)
    report('timing: /BIN read once for its folders, then each folder looked through', e)
    print('\nBIN folders: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
