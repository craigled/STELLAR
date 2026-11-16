# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""MAKE.PRG on the simulated Elf2K, in a folder /MK of a card made on the Mac (the sources dated 1 January 2026,
the clock at 16 October 2026). First boot: MAKE -n, MAKE (everything made: variables = := += ?=, $@ $< ${<} $^,
.PHONY, @ and -, a CR LF line, spaces for a Tab), MAKE again (nothing to do), MAKE GUIDE.TXT (up to date), MAKE
SHOW Z=... (a command line's variable wins). Then HEAD.RF dated 2027 on the Mac. Second boot: only GUIDE.TXT is
made again; a command that fails stops MAKE ($? 1, the commands after it not run); MAKE inside a script comes
back to the script; and the mistakes: no MAKEFILE, a command before any rule, no rule for a name (needed by ...),
a circle, a second rule, $( with no ), a line not a rule, usage.

    python3 LTOS/verify_make.py [-v]
"""
import os, re, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

MAKEFILE = (b'# a test MAKEFILE\n'
            b'DOC = guide\n'
            b'OUT := $(DOC).txt   # a comment after\n'
            b'X = one\n'
            b'X += two\n'
            b'Y ?= kept\n'
            b'Y ?= not this\n'
            b'Z = typed\n'
            b'\n'
            b'.PHONY: all show\n'
            b'all: $(OUT) notes.txt\n'
            b'\n'
            b'$(OUT): $(DOC).rf head.rf\n'
            b'\tTYPE $< > $@\n'
            b'# a comment among the commands\n'
            b'\t@ECHO made $@ from $^\n'
            b'notes.txt: notes.src\r\n'
            b'  -TYPE nothere.txt\r\n'
            b'  TYPE ${<} > $@\r\n'
            b'show:\n'
            b'\tECHO $(X) $(Y) $(Z) $$HOME\n')
FAILS = b'T: \n\tTYPE nothere.txt\n\tECHO never\n'
GOOD = b'ok:\n\tECHO fine\n'
RUNMK = b'MAKE -f GOOD\necho after $?\n'
BAD = [('NORULE', b'\tECHO x\n', 'MAKE: line 1: a command with no rule before it.'),
       ('MISS', b'A: B\n\tECHO a\nB: C\n\tECHO b\n', 'MAKE: no rule to make C (needed by B).'),
       ('CIRC', b'A: B\nB: A\n', 'MAKE: A is made from itself (a circle of rules).'),
       ('TWICE', b'A:\nA:\n', 'MAKE: line 2: a second rule for A (one rule each).'),
       ('UNCL', b'A:\n\tECHO $(X\n', 'MAKE: line 2: a $( with no ) (or ${ with no }).'),
       ('NOTR', b'# x\nA\n', 'MAKE: line 2: not a rule (target: names) or NAME = value.'),
       ('NOPE', None, 'MAKE: no NOPE here.')]
GUIDE, HEAD, NOTES = b'The guide.\nTwo lines.\n', b'.sh Head\n', b'Notes, a line.\n'
OLD = time.mktime((2026, 1, 1, 12, 0, 0, 0, 0, -1))
NEW = time.mktime((2027, 1, 1, 12, 0, 0, 0, 0, -1))
PROGS = ('MAKE', 'SH', 'CD', 'TYPE', 'ECHO')


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    _, syms = build.assemble('make')
    e = []
    if syms['VEND'] > 0x4600: e.append('the code and its variables end at $%04X, past the MAKEFILE at $4600' % syms['VEND'])
    report('MAKE.PRG fits ($3000-$%04X; the MAKEFILE from $4600)' % syms['VEND'], e)

    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed(mem, n)
    def put(m):
        b = os.path.join(m, 'BIN')
        if not os.path.isdir(b): os.mkdir(b)
        for p in PROGS: open(os.path.join(b, p + '.PRG'), 'wb').write(build.prg(p.lower()))
        open(os.path.join(m, 'RUNMK.SH'), 'wb').write(RUNMK)
        d = os.path.join(m, 'MK'); os.mkdir(d)
        for name, data in [('MAKEFILE', MAKEFILE), ('GUIDE.RF', GUIDE), ('HEAD.RF', HEAD), ('NOTES.SRC', NOTES),
                           ('FAILS', FAILS), ('GOOD', GOOD)] + [(x, y) for x, y, _ in BAD if y is not None]:
            p = os.path.join(d, name); open(p, 'wb').write(data); os.utime(p, (OLD, OLD))
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)

    def session(cmds):
        """The commands typed one after another (in /MK) -> [(command, what it showed, $?)], the stop."""
        later = [('LTOS> ', b'CD MK\r')] + [('/MK> ', x.encode() + b'\r') for x in cmds + ['MON']]
        b = V.Elf2K(cf, keys=b'', later=later)
        b.rtc = P3.clock()
        stat = []
        f0 = b.u.feed
        def feed():                                     # $? as each prompt comes (the last command's)
            k = len(b.u.later)
            f0()
            if len(b.u.later) < k: stat.append(b.c.M[0x033F])
        b.u.feed = feed
        s = b.boot_rom(20_000_000_000)
        t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
        if v: print(t[-5000:])
        parts = re.split(r'(?m)^LTOS /MK> ', t)[1:]
        out = []
        for k, p in enumerate(parts[:len(cmds)]):
            c, _, body = p.partition('\n')
            out.append((c, body, stat[k + 2] if k + 2 < len(stat) else None))
        return out, s

    def files(names):
        got = {}
        def rd(m):
            for x in names:
                p = os.path.join(m, x)
                got[x] = (open(p, 'rb').read(), os.path.getmtime(p)) if os.path.exists(p) else None
        P2.mac(V.image(cf, n), rd)
        return got

    # ---- the first boot
    out, s = session(['MAKE -n', 'MAKE', 'MAKE', 'MAKE GUIDE.TXT', 'MAKE show Z=cmd'])
    res = dict((k, x) for k, x in enumerate(out))
    def chk(k, want, rc, label):
        c, body, got = res.get(k, ('', '', None))
        if body.rstrip('\n').split('\n') != want or got != rc:
            e.append('%s: %r, $? %r' % (label, body, got))
    e = []
    if s != 'stop': e.append('the end: %s' % s)
    chk(0, ['TYPE GUIDE.RF > GUIDE.TXT', 'ECHO made GUIDE.TXT from GUIDE.RF HEAD.RF', 'TYPE nothere.txt',
            'TYPE NOTES.SRC > NOTES.TXT'], 0, 'MAKE -n')
    report('MAKE -n: the commands in order ($(...) := += ?= $@ $< ${<} $^ put in, @ ones too), nothing run', e)
    e = []
    chk(1, ['TYPE GUIDE.RF > GUIDE.TXT', 'made GUIDE.TXT from GUIDE.RF HEAD.RF', 'TYPE nothere.txt',
            'There is no file NOTHERE.TXT', 'TYPE NOTES.SRC > NOTES.TXT'], 0, 'MAKE')
    got = files(['MK/GUIDE.TXT', 'MK/NOTES.TXT', '_MAKE.SH'])
    for f, want in (('MK/GUIDE.TXT', GUIDE), ('MK/NOTES.TXT', NOTES)):
        if not got[f] or got[f][0] != want: e.append('%s: %r' % (f, got[f]))
    sc = got['_MAKE.SH'][0] if got['_MAKE.SH'] else b''
    if sc != (b'# made by MAKE.PRG: what it runs\nMAKEFAIL() { echo "MAKE: $1 failed - stopped."; exit 1; }\n'
              b"echo 'ECHO one two kept cmd $HOME'\nECHO one two kept cmd $HOME\n[ $? -eq 0 ] || MAKEFAIL SHOW\n"):
        e.append('/_MAKE.SH: %r' % sc[:400])
    rt = P3.entry(V.image(cf, n), b'_MAKE   SH ')
    if not rt or not rt[11] & 0x02: e.append('/_MAKE.SH not hidden: %r' % (rt,))
    report('MAKE: each command shown (not the @ one) and run in order, - goes on past a failure; GUIDE.TXT and '
           'NOTES.TXT made; the script (the last: MAKE show) /_MAKE.SH, hidden', e)
    e = []
    chk(2, ['MAKE: nothing to do for ALL.'], 0, 'MAKE again')
    chk(3, ['MAKE: GUIDE.TXT is up to date.'], 0, 'MAKE GUIDE.TXT')
    chk(4, ['ECHO one two kept cmd $HOME', 'one two kept cmd'], 0, 'MAKE show Z=cmd')
    report('MAKE again: nothing to do; MAKE GUIDE.TXT: up to date; MAKE show Z=cmd: NAME=value typed wins', e)

    # ---- HEAD.RF newer; the second boot
    def newer(m): os.utime(os.path.join(m, 'MK', 'HEAD.RF'), (NEW, NEW))
    img, _ = P2.mac(V.image(cf, n), newer)
    P1.load_image(cf, img)
    cmds = ['MAKE', 'MAKE -f FAILS', 'SH /RUNMK'] + ['MAKE -f %s' % x for x, _, _ in BAD] + ['MAKE -f']
    out, s = session(cmds)
    res = dict((k, x) for k, x in enumerate(out))
    e = []
    if s != 'stop': e.append('the end: %s' % s)
    chk(0, ['TYPE GUIDE.RF > GUIDE.TXT', 'made GUIDE.TXT from GUIDE.RF HEAD.RF'], 0, 'MAKE (HEAD.RF newer)')
    report('HEAD.RF newer than GUIDE.TXT: only GUIDE.TXT made again', e)
    e = []
    chk(1, ['TYPE nothere.txt', 'There is no file NOTHERE.TXT', 'MAKE: T failed - stopped.'], 1, 'MAKE -f FAILS')
    chk(2, ['ECHO fine', 'fine', 'after 0'], 0, 'SH /RUNMK')
    report('a command that fails: MAKE stops there, $? 1; MAKE inside a script: back to the script after', e)
    e = []
    for k, (x, _, want) in enumerate(BAD):
        chk(3 + k, [want], 1, 'MAKE -f ' + x)
    chk(3 + len(BAD), ['Usage: MAKE [-n] [-f file] [NAME=value] [targets]'], 1, 'MAKE -f')
    report('mistakes: no MAKEFILE, a command before any rule, no rule (needed by), a circle, a second rule, $( with '
           'no ), not a rule, usage - each said, $? 1', e)
    rc, _ = P2.fsck_free(V.image(cf, n))
    report('fsck_msdos: the card clean', ['fsck_msdos: %d' % rc] if rc else [])
    print('\nMAKE: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
