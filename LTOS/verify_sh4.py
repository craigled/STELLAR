# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 4 in the simulator: functions, case, $(command), . files, scripts that run scripts.

  * functions (NAME() { ... }, one line or many; $1 .. $#, return [n], calling themselves), case (| * ? quotes,
    branches of many lines, one line, none matching) - the same output as the Mac's own /bin/sh
  * $(command): into a variable (not split), joined lines, in a for list, a condition, a case word, inside $((
    )); its file /_SHOUT.TMP deleted after; RAWK > file (RAWK's output through the kernel now)
  * a script running another (NAME and SH NAME): its own $0 $1 ..., exit n back to the first one, which has its own
    again; . LIB (functions and variables from a file); a function that runs RAWK (SH loaded again inside it)
  * errors: } or return outside a function, a function's } missing, two $( ) in one command, . of a missing file

    python3 LTOS/verify_sh4.py [-v]
"""
import os, sys, difflib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase3 as P3
import verify_redir as R
import verify_sh as T
import build

PURE = b'''greet() {
  echo hello $1 args $#
  return 3
}
greet world
echo greet status $?
add() { echo $(( $1 + $2 )); }
add 2 5
count() {
  n=0
  for x; do n=$((n+1)); done
  echo count $n
}
count a b c
echo args still $1 $#
for w in apple pear 42 x.txt Q; do
  case $w in
    apple|pear) echo $w is a fruit ;;
    *.txt) echo $w is text ;;
    ?) echo $w is one letter ;;
    *) echo $w is something else ;;
  esac
done
case abc in
  a*)
    echo starts with a
    echo second line
    ;;
  *) echo no ;;
esac
case "x y" in "x y") echo quoted match;; esac
case z in a) echo a;; esac; echo no match status $?
f2() { echo in f2; }
f2; f2
nest() { if [ $1 -gt 0 ]; then echo nest $1; nest $(( $1 - 1 )); fi; }
nest 3
echo end
'''
MIXED = b'''N=$(ECHO hello   world)
echo got [$N]
L=$(CAT LIST.TXT)
echo list [$L]
for w in $(CAT LIST.TXT) end; do echo item $w; done
if [ "$(ECHO yes)" = yes ]; then echo cond ok; fi
case $(ECHO beta) in b*) echo case on output;; esac
echo count $(RAWK 'END {print NR}' LIST.TXT) lines
if [ -f /_SHOUT.TMP ]; then echo temp left; else echo temp gone; fi
SUB a "b c"
echo back status $? args $1 $#
SH SUB x
echo back again $? args $1 $#
. LIB
libf hi
echo libvar $LIBV
rk() { RAWK 'BEGIN {print "rawk in a function"}'; echo after rawk $1; }
rk arg1
echo done
'''
FILES = {'LIST.TXT': b'alpha\nbeta\ngamma\n', 'F4.SH': PURE, 'C.SH': MIXED,
         'SUB.SH': b'echo in sub $0 [$1] [$2] $#\nexit 4\necho not reached\n',
         'LIB.SH': b'libf() { echo libf says $1; }\nLIBV=set\n',
         'B1.SH': b'echo a\n}\n', 'B2.SH': b'return\n', 'B3.SH': b'f() {\necho never closed\n',
         'B4.SH': b'echo $(ECHO a) $(ECHO b)\n', 'B5.SH': b'. NOPE\necho went on $?\n'}


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    R.TEXTS.update(FILES)
    cf = R.card(mem)
    cmds = ['F4 one two', 'C one two', 'B1', 'B2', 'B3', 'B4', 'B5', "RAWK 'END {print NR}' LIST.TXT > X.TXT", 'DIR *.TMP']
    b, st, t = P3.session(cf, b'', rtc=P3.clock(), later=[('LTOS> ', (c + '\r').encode()) for c in cmds] + [('LTOS> ', b'MON\r')])
    if '-v' in sys.argv: print(t)
    fl = R.files(cf)
    e = []
    w = T.mac_sh(PURE, ['one', 'two'])[0].replace('\n', '\r\n')
    g = T.out(t, 'F4 one two')
    if g != w: e += ['F4: ' + l for l in difflib.unified_diff(w.split('\r\n'), g.split('\r\n'), 'mac', 'ltos', lineterm='')]
    report("functions (one line and many, $1 .. $#, return n, calling itself) and case (| * ? quotes, many lines, "
           "none matching): the same as the Mac's /bin/sh", e)
    e = []
    want = ('got [hello world]\r\nlist [alpha beta gamma]\r\nitem alpha\r\nitem beta\r\nitem gamma\r\nitem end\r\n'
            'cond ok\r\ncase on output\r\ncount 3 lines\r\ntemp gone\r\nin sub SUB [a] [b c] 2\r\n'
            'back status 4 args one 2\r\nin sub SUB [x] [] 1\r\nback again 4 args one 2\r\nlibf says hi\r\n'
            'libvar set\r\nrawk in a function\r\nafter rawk arg1\r\ndone\r\n')
    if T.out(t, 'C one two') != want: e.append('C: %r' % T.out(t, 'C one two'))
    if fl.get('X.TXT') != b'3\n': e.append('RAWK > X.TXT: %r' % fl.get('X.TXT'))
    if '_SHOUT.TMP' in fl or T.out(t, 'DIR *.TMP') != '   0 files, 0 bytes\r\n': e.append('/_SHOUT.TMP left: %r' % T.out(t, 'DIR *.TMP'))
    report('$(command) (a variable, joined lines, a for list, a condition, a case word), its file '
           'deleted; RAWK > file; a script running another (NAME, SH NAME; exit 4 back); . LIB; RAWK in a function', e)
    e = []
    for c, w in (('B1', 'a\r\nB1 line 2: return or } outside a function\r\n'),
                 ('B2', 'B2 line 1: return or } outside a function\r\n'),
                 ('B3', "B3 line 3: a function's } is missing\r\n"),
                 ('B4', 'B4 line 1: $(...): one a command, with its )\r\n'),
                 ('B5', 'B5 line 1: NOPE is not on the card\r\nwent on 1\r\n')):
        if T.out(t, c) != w: e.append('%s: %r, want %r' % (c, T.out(t, c), w))
    report('errors: } and return outside a function, a function never closed, two $( ) in a command, . NOPE', e)
    # ---- a name alone: NAME.SH first, then NAME.PRG, then NAME.STL (in each folder: here, the root, /BIN). (The
    #      programs are all in the root on this card: HELLO.SH beside HELLO.PRG, after it; VER.PRG nearer than /BIN's VER.SH)
    e = []
    more = {'HELLO.SH': b'echo HELLO.SH, not HELLO.PRG: $1\n', 'BIN/VER.SH': b'echo BIN/VER.SH ran\n', 'LW2.SH': b'echo LW2.SH, not LW2.STL\n',
            'DOCS/T.SH': b'echo DOCS/T.SH $#\n'}
    R.TEXTS.update(more)
    cf2 = R.card(mem)
    for n in more: del R.TEXTS[n]
    cmds = ['HELLO hi', 'LW2', 'DOCS/T a b', 'VER > NUL', 'VER', 'NOPE', 'HELLO.PRG', 'HELLO.SH x']
    b, st, t = P3.session(cf2, b'', rtc=P3.clock(), later=[('LTOS> ', (c + '\r').encode()) for c in cmds] + [('LTOS> ', b'MON\r')])
    if '-v' in sys.argv: print(t)
    for c, w in (('HELLO hi', 'HELLO.SH, not HELLO.PRG: hi\r\n'), ('LW2', 'LW2.SH, not LW2.STL\r\n'),
                 ('DOCS/T a b', 'DOCS/T.SH 2\r\n'), ('VER > NUL', ''), ('VER', None),
                 ('NOPE', 'Unknown command: NOPE  (see HELP)\r\n'), ('HELLO.SH x', 'HELLO.SH, not HELLO.PRG: x\r\n')):
        if w is None: w = T.out(t, c) if T.out(t, c).startswith('LTOS 0.5') else 'LTOS 0.5 ...'
        if T.out(t, c) != w: e.append('%s: %r, want %r' % (c, T.out(t, c), w))
    if 'HELLO.SH' in T.out(t, 'HELLO.PRG') or not T.out(t, 'HELLO.PRG'): e.append('HELLO.PRG: %r' % T.out(t, 'HELLO.PRG'))
    report('a name alone: NAME.SH before NAME.PRG (in the same folder too) and before NAME.STL, the nearer folder first; a path; an extension typed; '
           'programs and unknown names as before', e)
    # ---- no start-up script (Craig, 2026-11-08): an AUTOEXEC.SH is not run, and the boot leaves RAM from $3000 alone
    e = []
    R.TEXTS['AUTOEXEC.SH'] = b'echo autoexec ran\nX=1\nCD DOCS\n'
    cf = R.card(mem)
    b, st, t = P3.session(cf, b'MON\r', rtc=P3.clock())
    if 'Type HELP for the commands.\r\nLTOS> ' not in t or 'autoexec ran' in t: e.append('with AUTOEXEC.SH: %r' % t[-200:])
    del R.TEXTS['AUTOEXEC.SH']
    cf = R.card(mem)
    pat = bytes((i * 7 + 3) & 0xFF for i in range(0x3C00))
    def ram(M): M[0x3000:0x6C00] = pat
    b, st, t = P3.session(cf, b'MON\r', rtc=P3.clock(), ram=ram)
    if 'Type HELP for the commands.\r\nLTOS> ' not in t: e.append('without: %r' % t[-200:])
    if bytes(b.c.M[0x4000:0x6800]) != pat[0x1000:0x3800]: e.append('without: RAM where SH would go ($4000-$67FF) changed by the boot')
    report('no start-up script: an AUTOEXEC.SH is not run; the boot goes to the prompt and leaves RAM alone (MON uses $3000-$3FFF)', e)
    print('\nLTOS SH phase 4: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
