# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 3 in the simulator: SH's loops and the rest.

  * while / until / for (words, $1 .. $#), break, continue, nested; && || !; $((...)) (16-bit: + - * / % ( ),
    comparisons, NAME and $NAME); ${NAME:-x} ${NAME:=x}; shift [n]; fi sets $? as sh does - the same output as
    the Mac's own /bin/sh
  * loops round outside commands (ECHO > file, CAT, RAWK - over SH: loaded again each round, the loop goes on);
    for over wildcards (*.ZZZ, DOCS/*.TXT, R?.TXT; none matching: the word itself)
  * sleep (a clock that ticks as the Elf2K's would), pause (with and without text), set -e (not after || or in an
    if's condition), Ctrl-C in an endless loop; errors: done without while, break outside a loop, / 0, a bad $((...))

    python3 LTOS/verify_sh3.py [-v]
"""
import os, sys, difflib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase3 as P3
import verify_redir as R
import verify_sh as T
import build

PURE = b'''i=1
while [ $i -le 5 ]; do
  echo while $i
  i=$((i + 1))
done
echo after while i=$i
n=3
until [ $n -eq 0 ]; do echo until $n; n=$((n-1)); done
for w in apple "big pear" fig; do echo for $w; done
for a; do echo arg $a; done
for x in 1 2 3 4 5 6; do
  if [ $x -eq 2 ]; then continue; fi
  if [ $x -eq 5 ]; then break; fi
  echo x $x
done
echo x after $x
true && echo and1
false && echo and2
false || echo or1
true || echo or2
true && false || echo chain
! false; echo not $?
! true; echo not2 $?
echo $((2+3*4)) $(( (2+3)*4 )) $((17/5)) $((17%5)) $((-17/5)) $((-17%5)) $((7-10))
echo $((3<4)) $((3>4)) $((4<=4)) $((5>=6)) $((2==2)) $((2!=2)) $((!0)) $((-(3)))
V=5; echo $((V*2)) $(($V+1)) $(( $1 + 1 ))
echo ${UNSET:-def} ${V:-def} [${EMPTY:-e}]
echo ${NEW:=made} $NEW
for i in 1 2; do for j in a b; do echo $i$j; done; done
i=0; while true; do i=$((i+1)); if [ $i -ge 3 ]; then break; fi; done; echo broke at $i
shift
echo after shift $1 $#
shift 2
echo after shift 2 [$1] $#
if false; then echo no; fi; echo fi status $?
'''
MIXED = b'''i=0
while [ $i -lt 3 ]; do
  i=$((i+1))
  ECHO round $i > R$i.TXT
  RAWK 'BEGIN {print "rawk", 40+2}'
  echo loop $i status $?
done
for f in *.ZZZ; do echo found $f; done
for f in DOCS/*.TXT NOMATCH*.Q; do echo item $f; done
for f in R?.TXT; do CAT $f; done
echo before sleep; sleep 2; echo after sleep
set -e
true
false || echo or kept going
if false; then echo no; fi
echo still going
false
echo not reached
'''
BAD = {'E.SH': b'echo a\ndone\n', 'E2.SH': b'break\n', 'E3.SH': b'echo $((1/0))\n', 'E4.SH': b'echo $((2+))\n',
       'P.SH': b'pause\npause Ready?\necho paused ok\nwhile true; do echo forever; done\n'}


def session(cf, later):
    """the Elf2K with a DS12887 whose seconds tick as the Elf2K's would (about 93,000 instructions a second)"""
    b = V.Elf2K(cf, keys=b'', later=later)
    base = P3.clock()
    b.rtc = lambda r: int('%d' % ((20 + b.steps // 93000) % 60), 16) if r == 0 else base(r)
    st = b.boot_rom(cap=1_500_000_000)
    return b, st, b.text()


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    R.TEXTS.update({'L.SH': PURE, 'M.SH': MIXED}); R.TEXTS.update(BAD)
    cf = R.card(mem)
    later = [('LTOS> ', (c + '\r').encode()) for c in ('L 7 b c', 'M', 'E', 'E2', 'E3', 'E4', 'P')]
    later += [('go on ... ', b'x'), ('Ready?', b'y'), ('forever\r\nforever\r\nforever', b'\x03'), ('LTOS> ', b'MON\r')]
    b, st, t = session(cf, later)
    if '-v' in sys.argv: print(t)
    e = []
    w = T.mac_sh(PURE, ['7', 'b', 'c'])[0].replace('\n', '\r\n')
    g = T.out(t, 'L 7 b c')
    if g != w: e += ['L: ' + l for l in difflib.unified_diff(w.split('\r\n'), g.split('\r\n'), 'mac', 'ltos', lineterm='')]
    report("loops (while until for, break continue, nested), && || !, $((...)), ${X:-y} ${X:=y}, shift: the same as "
           "the Mac's /bin/sh", e)
    e = []
    want = ('rawk 42\r\nloop 1 status 0\r\nrawk 42\r\nloop 2 status 0\r\nrawk 42\r\nloop 3 status 0\r\n'
            'found A.ZZZ\r\nfound B.ZZZ\r\nitem DOCS/IN.TXT\r\nitem NOMATCH*.Q\r\nround 1\r\nround 2\r\nround 3\r\n'
            'before sleep\r\nafter sleep\r\nor kept going\r\nstill going\r\n')
    if T.out(t, 'M') != want: e.append('M: %r' % T.out(t, 'M'))
    report('a loop round ECHO > file and RAWK (SH loaded again each round); for over wildcards; sleep 2; set -e', e)
    e = []
    for c, w in (('E', 'a\r\nE line 2: do or done without while, until or for\r\n'),
                 ('E2', 'E2 line 1: break or continue outside a loop\r\n'), ('E3', 'E3 line 1: divided by 0\r\n'),
                 ('E4', 'E4 line 1: $((...)) not understood\r\n'),
                 ('P', 'Press a key to go on ... \r\nReady?\r\npaused ok\r\nforever\r\nforever\r\nforever\r\nP stopped at line 4\r\n')):
        if T.out(t, c) != w: e.append('%s: %r, want %r' % (c, T.out(t, c), w))
    report('errors (done without while, break outside a loop, / 0, a bad $((...))); pause; Ctrl-C in an endless loop', e)
    print('\nLTOS SH phase 3: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
