# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 2 in the simulator: SH.PRG runs scripts.

  * Craig's TEST.SH, by its name alone (TEST) and as SH TEST
  * scripts of built-ins only (echo, variables, quotes, ;, #, $0-$9 $# $?, if / elif / else / fi nested, test and
    [ ] of every kind, true / false / :, exit) - the same output as the Mac's own /bin/sh gives
  * outside commands in between: VER > file, CAT, RAWK (it loads over SH: SH.PRG comes back from the card and the
    script goes on), an unknown command ($? = 127); -x shows each command
  * a long script (lines across sectors and clusters); read (-p, Backspace, a key typed early); the file tests
  * errors with the script's name and line; SH NOPE; Ctrl-C between lines stops it

    python3 LTOS/verify_sh.py [-v]
"""
import os, re, sys, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_redir as R
import verify_phase3 as P3
import build

TEST = b'echo "Testing the batch feature"\necho "1"\necho "2"\necho "3"\nexit\n'
# built-ins only: the Mac's /bin/sh must print the same
PURE = {
    'VARS.SH': b'''#!/bin/sh
# variables and quotes
X=hello; Y="big   world"; EMPTY=
echo $X ${Y} '$X ${Y}' "$X and $Y" end
echo "[$EMPTY]" [${EMPTY}] a${X}b "$X"'$X'
Z=$X; X=changed
echo $Z $X
echo $ alone, 100$ and "$"
echo args $# : $1 / $2 / $3 / "$4"
true; echo t $?; false; echo f $?; :; echo c $?
echo semi; echo colons;   echo   spaced    words  # a comment
echo 'a # not a comment' "b ; not a split"
''',
    'IFS.SH': b'''N=7
if [ $N -gt 5 ]; then echo big; else echo small; fi
if [ $N -lt 5 ]
then
  echo small
elif [ $N -eq 7 ]
then
  echo seven
  if [ "$1" = one ]; then echo inner one; elif [ "$1" = two ]; then echo inner two; else echo inner other; fi
else
  echo other
fi
if false; then echo no; elif false; then echo no2; else echo else ran; fi
if true; then if false; then echo x; else echo nested else; fi; fi
if false; then
  if true; then echo never; else echo never2; fi
  echo never3
fi
echo after
for_ok=yes
if [ -z "" ]; then echo z empty; fi
if [ -n "" ]; then echo n wrong; else echo n empty; fi
if [ abc = abc ]; then echo s eq; fi
if [ abc != abd ]; then echo s ne; fi
if [ ! abc = abd ]; then echo not eq; fi
if [ -3 -lt 2 ]; then echo neg lt; fi
if [ 10 -ge 10 ] && true; then echo ge; fi
if test 32767 -gt -32768; then echo wide; fi
if [ 5 -ne 5 ]; then echo wrong; else echo ne false; fi
if [ 4 -le 3 ]; then echo wrong; else echo le false; fi
[ x ]; echo one word $?
[ ]; echo none $?
[ "" ]; echo empty word $?
test ! ""; echo not empty $?
exit 3
echo not reached
''',
}
PURE['IFS.SH'] = PURE['IFS.SH'].replace(b' && true', b'')
LONG = b''.join(b'echo line %d of the long script, padded out to make it longer than a sector or two\n' % i
                for i in range(1, 121))
MIXED = b'''X=1
VER > V.TXT
echo VER status $?
CAT V.TXT > NUL
RAWK 'BEGIN {print 6*7}'
echo after RAWK X=$X status $?
NOSUCH arg
echo unknown status $?
if [ -f V.TXT ]; then echo V.TXT here; fi
if [ -f NOPE.TXT ]; then echo wrong; else echo NOPE.TXT not here; fi
if [ -d DOCS ]; then echo DOCS a folder; fi
if [ -e DOCS/IN.TXT ]; then echo IN.TXT in DOCS; fi
if [ -s TOUCHED.TXT ]; then echo wrong; else echo TOUCHED.TXT empty; fi
TOUCH TOUCHED.TXT
if [ -f TOUCHED.TXT ]; then echo TOUCHED.TXT made; fi
set
unset X
echo X is now [$X]
echo the end > E.TXT
'''
MIXED = MIXED.replace(b'set\n', b'set\necho -n no newline; echo " - then this"\n')
ASK = b'read -p "Your name? " N\necho Hello, $N!\nread X\nif [ "$X" -gt 5 ]; then echo big; else echo small; fi\n'
BAD = {'NOFI.SH': b'echo a\nif true; then\necho b\n', 'NOIF.SH': b'echo a\n\nfi\necho b\n',
       'TESTBAD.SH': b'[ 1 -eq x ]; echo st $?\n[ 1 = 1\necho st $?\ntest a -zz b; echo st $?\nexit x\necho no\n'}
STOP = b''.join(b'echo stop %d\n' % i for i in range(1, 400))


def mac_sh(script, args):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'S.SH'); open(p, 'wb').write(script)
        r = subprocess.run(['/bin/sh', p] + args, capture_output=True, cwd=d)
        return r.stdout.decode(), r.returncode


def out(t, cmd):
    return R.out(t, cmd)


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    for n, d in [('TEST.SH', TEST), ('LONG.SH', LONG), ('MIXED.SH', MIXED), ('ASK.SH', ASK), ('STOP.SH', STOP)] + list(PURE.items()) + list(BAD.items()):
        R.TEXTS[n] = d

    # ---- 1. TEST.SH, the built-ins against /bin/sh, the long script
    cf = R.card(mem)
    runs = [('TEST', None), ('SH TEST.SH', None), ('VARS one "two words" 3', ['one', 'two words', '3']),
            ('SH VARS', []), ('IFS one', ['one']), ('IFS two', ['two']), ('IFS', []), ('LONG', None)]
    later = [('LTOS> ', (c + '\r').encode()) for c, _ in runs] + [('LTOS> ', b'MON\r')]
    b, st, t = P3.session(cf, b'', rtc=P3.clock(), later=later)
    if '-v' in sys.argv: print(t)
    e = []
    want = 'Testing the batch feature\r\n1\r\n2\r\n3\r\n'
    for c in ('TEST', 'SH TEST.SH'):
        if out(t, c) != want: e.append('%s: %r' % (c, out(t, c)))
    report("Craig's TEST.SH: by its name (TEST) and as SH TEST.SH", e)
    e = []
    for c, a in runs[2:7]:
        name = c.split()[0] if c.split()[0] != 'SH' else c.split()[1]
        w, rc = mac_sh(PURE[name + '.SH'], a)
        w = w.replace('S.SH', name)
        if out(t, c) != w.replace('\n', '\r\n'): e.append('%s:\n      got  %r\n      want %r' % (c, out(t, c), w.replace('\n', '\r\n')))
    report('built-ins only (variables, quotes, ;, #, $0-$9 $# $?, if/elif/else nested, test and [ ], exit): '
           'the same as the Mac\'s /bin/sh', e)
    e = []
    w = ''.join('line %d of the long script, padded out to make it longer than a sector or two\r\n' % i for i in range(1, 121))
    if out(t, 'LONG') != w: e.append('LONG: %d characters, want %d' % (len(out(t, 'LONG')), len(w)))
    report('a %d-byte script: lines across sectors and clusters' % len(LONG), e)

    # ---- 2. outside commands, RAWK over SH, -x, read, the file tests
    cf = R.card(mem)
    later = [('Your name? ', b'Craig\x08g\r'), ('Hello, Craig!\r\n', b'12\r'), ('LTOS> ', b'SH -x TEST\r'),
             ('LTOS> ', b'MON\r')]
    b, st, t = P3.session(cf, b'', rtc=P3.clock(), later=[('LTOS> ', b'MIXED\r'), ('LTOS> ', b'ASK\r')] + later)
    if '-v' in sys.argv: print(t)
    fl = R.files(cf); e = []
    ver = out(b.text(), 'MIXED')
    for w in ['VER status 0', 'after RAWK X=1 status 0\r\n', '42\r\n', 'Unknown command: NOSUCH', 'unknown status 127',
              'V.TXT here', 'NOPE.TXT not here', 'DOCS a folder', 'IN.TXT in DOCS', 'TOUCHED.TXT empty',
              'TOUCHED.TXT made', 'X=1\r\n', 'X is now []', 'no newline - then this\r\n']:
        if w not in ver: e.append('MIXED: no %r' % w)
    if not fl.get('V.TXT', b'').startswith(b'LTOS 0.5'): e.append('V.TXT: %r' % fl.get('V.TXT', b'')[:40])
    if fl.get('E.TXT') != b'the end\n': e.append('E.TXT: %r' % fl.get('E.TXT'))
    if fl.get('TOUCHED.TXT') != b'': e.append('TOUCHED.TXT: %r' % fl.get('TOUCHED.TXT'))
    report('outside commands: VER > V.TXT, CAT, RAWK (over SH: SH.PRG loaded again, the script goes on), an unknown '
           'one ($? 127), echo > E.TXT (ECHO.PRG), echo -n; the file tests -f -d -e -s; set, unset', e)
    e = []
    if out(t, 'ASK') != 'Your name? Craig\x08 \x08g\r\nHello, Craig!\r\n12\r\nbig\r\n': e.append('ASK: %r' % out(t, 'ASK'))
    want = '+ echo "Testing the batch feature"\r\nTesting the batch feature\r\n+ echo "1"\r\n1\r\n+ echo "2"\r\n2\r\n+ echo "3"\r\n3\r\n+ exit\r\n'
    if out(t, 'SH -x TEST') != want: e.append('-x: %r' % out(t, 'SH -x TEST'))
    report('read -p (Backspace), read with a key typed before it was asked; SH -x shows each command', e)

    # ---- 3. errors, SH NOPE, Ctrl-C
    cf = R.card(mem)
    cmds = ['NOFI', 'NOIF', 'TESTBAD', 'SH NOPE', 'SH', 'STOP']
    later = [('LTOS> ', (c + '\r').encode()) for c in cmds] + [('stop 3\r\n', b'\x03'), ('LTOS> ', b'MON\r')]
    b, st, t = P3.session(cf, b'', rtc=P3.clock(), later=later)
    if '-v' in sys.argv: print(t)
    e = []
    for c, w in (('NOFI', 'a\r\nb\r\nNOFI line 4: if without fi\r\n'),
                 ('NOIF', 'a\r\nNOIF line 3: then, elif, else or fi without if\r\n'),
                 ('TESTBAD', 'TESTBAD line 1: test: a number, please\r\nst 2\r\nTESTBAD line 2: [: no ] at the end\r\nst 2\r\n'
                             'TESTBAD line 4: test: not understood\r\nst 2\r\nTESTBAD line 5: exit: a number, please\r\n'),
                 ('SH NOPE', 'SH: NOPE is not on the card.\r\n'),
                 ('SH', 'SH [-x] NAME [words] - runs the script NAME.SH\r\n')):
        if out(t, c) != w: e.append('%s: %r, want %r' % (c, out(t, c), w))
    s = out(t, 'STOP')
    m = re.search(r'STOP stopped at line (\d+)\r\n$', s)
    if not m or 'stop 3\r\n' not in s or 'stop 399' in s: e.append('STOP: %r' % s[-120:])
    report('errors: the script\'s name and line (if without fi, fi without if, test, exit); SH NOPE; SH alone; '
           'Ctrl-C between lines', e)
    print('\nLTOS SH: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
