# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""RAWK (rawk.asm) in the simulator, against the Mac's own awk (/usr/bin/awk) on the same files.

  Every program is run by RAWK on an LTOS card and by awk on the Mac; what they print must be the same, byte for
  byte - except where RAWK is meant to differ: whole numbers (7/2 is 3), and its own messages for what it cannot
  do yet (checked against the text RAWK should say). Also: a screen at a time (a key goes on, Q stops), names by
  DIR's rules (*.TXT, a folder), and the time a 500-line file takes (instructions / 93,000 a second: measured on the Elf2K, 2026-10-23).

    python3 LTOS/verify_rawk.py [-v]
"""
import os, sys, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

FILES = {
    'A.TXT': b'one two three\nfour five\n\nsix\n',
    'S.TXT': b'apples 3 10\npears 5 -2\nplums 12 7\n',
    'C.CSV': b'name,qty,price\r\nbolt,100,3\r\nnut,,2\r\n',
    'T.TXT': b'a\tb c\td\n  lead  trail  \nx\n',
    'N.TXT': b'10\n9\n010\n-3\n+4\n 7 \nabc\n12abc\n\n',
    'D.TXT': b'3.5\n1e2\n-0.5\n',
    'DOCS/NOTE.TXT': b'Lot went to Sodom\nAbraham stayed\nlot of words\n',
    'LONG.TXT': b''.join(b'line %d of %d\n' % (i, 30) for i in range(1, 31)),
    'BIG.TXT': b''.join(b'item%d %d %d some more words here\n' % (i, i % 37, i * 7 % 101) for i in range(500)),
    # phase 2: programs in files (-f)
    'P.AWK': b'# a program in a file\nBEGIN { n = 0 }\n{ n++\n  if ($2 > 4) print $1, "big"\n  else print $1, "small" }\nEND { printf "%d lines\\n", n }\n',
    'L.AWK': b'BEGIN {\n  for (i = 1; i <= 5; i++) {\n    s = s i\n    if (i == 3) continue\n    printf "%s;", s\n  }\n  print ""\n  while (1) { k++; if (k > 3) break }\n  print k\n  do { j++ } while (j < 4)\n  print j\n}\n',
    'I.AWK': b'BEGIN {\n  print index("hello", "ll"), index("hello", "z"), index("hello", ""), index("", "a")\n  print substr("hello", 0, 2) "|" substr("hello", -1, 3) "|" substr("hello", 2)\n  print substr("hello", 10) "|" substr("hello", 2, -1) "|" substr("hello", 1, 100)\n  print substr("hello", 2, 3), index("hello", "ll"), toupper("abc"), tolower("XyZ")\n}\n',
    'F.AWK': b'BEGIN {\n  printf "[%5s][%-5s][%.2s][%c][%c][%X][%%][%3d]\\n", "ab", "ab", "abc", 65, "hey", 3054, -7\n  printf "%05d|%-05d|%.3d|%+d|%+d\\n", -42, 7, 5, 3, -3\n  printf "%5.1s|%-3c|%x\\n", "xyz", "q", 0\n}\n',
    'R.AWK': b'/e+/ {print "1", $1}\n/l?u/ {print "2", $1}\n/[0-9][0-9]/ {print "3", $0}\n/^[a-o]*s /\n/p[a-z]+s/ {print "4", $1}\n$2 ~ "^1" {print "5", $2}\n',
    'W.AWK': b'{ for (i = 1; i <= NF; i++) { w = $i\r\n    if (length(w) > 3) printf "%-6s|", toupper(w) }\r\n  print "" }\r\n',
}

# programs RAWK and awk must print the same for
SAME = [
    "RAWK '{print $2}' A.TXT",
    "RAWK 'BEGIN {print 1+2}'",
    "RAWK '{s += $3} END {print s}' S.TXT",
    "RAWK '/p/' S.TXT",
    "RAWK '!/p/' S.TXT",
    "RAWK '{print NR \": \" $0}' A.TXT",
    "RAWK -F, '{print $1, $3}' C.CSV",
    "RAWK -F, 'NR > 1 {s += $2 * $3} END {print s}' C.CSV",
    "RAWK -F , '{print NF \":\" $2 \"|\"}' C.CSV",
    "RAWK 'NF > 0 {n++} END {print n}' A.TXT",
    "RAWK '$2 > 4 {print $1}' S.TXT",
    "RAWK '$1 ~ \"pl\"' S.TXT",
    "RAWK '$1 !~ /p/ {print $1}' S.TXT",
    "RAWK 'NR >= 2 && NR <= 3' S.TXT",
    "RAWK 'NR == 1 || NR == 3 {print NR, $1}' S.TXT",
    "RAWK '{print $NF, $(NF-1)}' S.TXT",
    "RAWK 'length($0) > 9' S.TXT",
    "RAWK '{print length, length()}' A.TXT",
    "RAWK 'END {print NR}' A.TXT",
    "RAWK 'END {print $0, NF}' S.TXT",
    "RAWK '{x = x $1} END {print x}' S.TXT",
    "RAWK '{print $2 * $3, $2 - $3, $3 % $2}' S.TXT",
    "RAWK 'BEGIN {print -7 % 3, 7 % -3, 2 * -3, 6 / 3, -8 / 2}'",
    "RAWK 'BEGIN {x = 5; print x++, x, ++x, x--, --x}'",
    "RAWK 'BEGIN {a = b = 3; print a, b; a += 2; b -= 1; print a * b}'",
    "RAWK 'BEGIN {a = 7; a *= 3; print a; a %= 4; print a; a /= 1; print a}'",
    "RAWK 'BEGIN {print 1 \" \" -1; print \"a\" 1 + 2 \"b\"}'",
    "RAWK 'BEGIN {print !0, !1, !\"\", !\"a\", !x, !\"0\"}'",
    "RAWK 'BEGIN {print 2147483647, -2147483647, 100000 * 1000}'",
    "RAWK '$2 == 5' S.TXT",
    "RAWK '$1 < \"q\"' S.TXT",
    "RAWK '$2 < $3' S.TXT",
    "RAWK '{print FILENAME, FNR, NR}' A.TXT S.TXT",
    "RAWK 'BEGIN {FS = \",\"} {print $2}' C.CSV",
    "RAWK 'BEGIN {OFS = \"-\"} {print $1, $2}' S.TXT",
    "RAWK '{print \"a\\tb\\\"c\\\\d\"}' S.TXT",
    "RAWK '{print $5 \"|\" ($5 == 0) ($5 == \"\")}' A.TXT",
    "RAWK 'BEGIN {print (x == 0), (x == \"\"), length(x)}'",
    "RAWK -F'\\t' '{print NF \":\" $2}' T.TXT",
    "RAWK -Ft '{print NF}' T.TXT",
    "RAWK '{print NF \"[\" $1 \"]\"}' T.TXT",
    "RAWK '{ n = n + 1 } ; END { print n }' A.TXT",
    "RAWK '$1 > 9' N.TXT",
    "RAWK '$1 == 7 {print \"seven\"} $1 {print \"t\", $1}' N.TXT",
    "RAWK '{print $1 + 0, -$1}' N.TXT",
    "RAWK '{print ($1 < \"9\")}' N.TXT",
    "RAWK '{s += $1} END {print s}' N.TXT",
    "RAWK 'BEGIN {s = 0} {s += $2} END {print s, NR}' BIG.TXT",
    "RAWK 'NR % 100 == 0 {print $1, $2 * $3}' BIG.TXT",
    # ---- phase 2: statements
    "RAWK '{if ($1) print}' A.TXT",
    "RAWK 'BEGIN {for (i = 1; i <= 5; i++) print i}'",
    "RAWK '{if ($2 > 4) print $1; else print \"no\"}' S.TXT",
    "RAWK '{for (i = NF; i > 0; i--) printf \"%s \", $i; print \"\"}' A.TXT",
    "RAWK 'BEGIN {while (i < 3) {i++; print i}}'",
    "RAWK 'BEGIN {do {k++} while (k < 5); print k}'",
    "RAWK 'BEGIN {for (;;) {n++; if (n > 4) break}; print n}'",
    "RAWK 'BEGIN {for (i = 0; i < 6; i++) {if (i % 2) continue; print i}}'",
    "RAWK 'NR == 2 {next} {print NR}' S.TXT",
    "RAWK '{print; if (NR == 2) exit} END {print \"end\", NR}' S.TXT",
    "RAWK 'BEGIN {print \"a\"; exit; print \"b\"} END {print \"c\"}' A.TXT",
    "RAWK 'BEGIN {if (1) if (0) print \"a\"; else print \"b\"}'",
    "RAWK 'BEGIN {x = 3; if (x > 2) {print \"big\"} else {print \"small\"}}'",
    "RAWK '{ if ($2 > 4) { n++ } } END { print n }' S.TXT",
    "RAWK 'BEGIN {for (i = 1; i <= 100; i++) s = s \"x\"; print length(s)}'",
    "RAWK 'BEGIN {for (i = 1; i <= 300; i++) t = t + length(i \"\"); print t}'",
    "RAWK '{print \"a\\nb\"}' S.TXT",
    # printf, functions
    "RAWK 'BEGIN {printf \"%d|%5d|%-5d|%05d|%s|%x\\n\", 42, 42, 42, 42, \"hi\", 255}'",
    "RAWK 'BEGIN {printf(\"%d-%d\\n\", 1, 2); printf \"%s\\n\", \"x\"}'",
    "RAWK '{printf \"%-8s%4d\\n\", $1, $2 * $3}' S.TXT",
    "RAWK 'BEGIN {print toupper(\"abc\"), tolower(\"XyZ\"), toupper(12) + 1}'",
    "RAWK '{print substr($1, 2, 3), index($0, \"s\")}' S.TXT",
    "RAWK -f I.AWK",
    "RAWK -f F.AWK",
    # patterns
    "RAWK '/^[ap]/' S.TXT",
    "RAWK '/s$/' S.TXT",
    "RAWK '$1 ~ /^p.*s$/ {print $1}' S.TXT",
    "RAWK '$2 ~ /^[^0-4]/' S.TXT",
    "RAWK '{print ($1 ~ \"p.u\")}' S.TXT",
    "RAWK '/a.b/' A.TXT",
    "RAWK '$1 ~ \"a*\"' A.TXT",
    "RAWK -f R.AWK S.TXT",
    # -f, -v
    "RAWK -f P.AWK S.TXT",
    "RAWK -f L.AWK",
    "RAWK -f W.AWK A.TXT",
    "RAWK -v x=5 'BEGIN {print x + 1}'",
    "RAWK -v 'msg=hi there' 'BEGIN {print msg}'",
    "RAWK -v n=3 -v s=ab 'BEGIN {for (i = 0; i < n; i++) printf \"%s\", s; print \"\"}'",
    "RAWK -F, -v OFS=: '{print $1, $2}' C.CSV",
    "RAWK -v FS=, '{print $2}' C.CSV",
    "RAWK -v 'x=a\\tb' 'BEGIN {print x}'",
]

# what RAWK says itself (awk differs, or has nothing like it)
OWN = [
    ("RAWK", "RAWK [-F c] [-v x=val] [-o file] 'program' (or -f file) names - HELP RAWK\n"),
    ("RAWK -q '{print}' A.TXT", "RAWK [-F c] [-v x=val] [-o file] 'program' (or -f file) names - HELP RAWK\n"),
    ("RAWK '{print}'", "RAWK: name the files to read\nRAWK [-F c] [-v x=val] [-o file] 'program' (or -f file) names - HELP RAWK\n"),
    ("RAWK '{print}' NOPE.TXT", "No file matches.\n"),
    ("RAWK '{print $1' A.TXT", "RAWK: the program ends too soon near: \n"),
    ("RAWK 'BEGIN {print 1' A.TXT", "RAWK: the program ends too soon near: \n"),
    ("RAWK 'BEGIN {print 1;' A.TXT", "RAWK: a } is missing near: \n"),
    ("RAWK '{print $1)}' A.TXT", "RAWK: this is not understood near: )}\n"),
    ("RAWK '{print (1}' A.TXT", "RAWK: a ) is missing near: }\n"),
    ("RAWK '{print 1 +}' A.TXT", "RAWK: this is not understood near: }\n"),
    ("RAWK '{print 3.5}' A.TXT", "RAWK: whole numbers only (SAWK does decimals) near: 3.5}\n"),
    ("RAWK '/a(b)/' A.TXT", "RAWK: ( ) | in a pattern come later\n"),
    ("RAWK '$1 ~ \"a|b\"' A.TXT", "RAWK: ( ) | in a pattern come later\n"),
    ("RAWK '{print $1 > \"x\"}' A.TXT", "RAWK: put a comparison after print in ( ) near: > \"x\"}\n"),
    ("RAWK '{NR = 1}' A.TXT", "RAWK: NR, NF, FNR, FILENAME cannot be changed yet near: = 1}\n"),
    ("RAWK '{$1 = \"x\"}' A.TXT", "RAWK: $n = value comes in a later version near: = \"x\"}\n"),
    ("RAWK '{3 = x}' A.TXT", "RAWK: only a variable can be given a value near: = x}\n"),
    ("RAWK '{print 1/0}' A.TXT", "RAWK: division by zero\n"),
    ("RAWK '{print $(-1)}' A.TXT", "RAWK: a field number below 0\n"),
    ("RAWK '{print \"x}' A.TXT", "RAWK: a \" is not closed near: \"x}\n"),
    ("RAWK '{print 1 # x}' A.TXT", "RAWK: the program ends too soon near: \n"),
    ("RAWK '{print 1 @ x}' A.TXT", "RAWK: RAWK cannot use this character near: @ x}\n"),
    ("RAWK '{print} A.TXT", "RAWK: the program's ' is not closed\n"),
    ("RAWK -f NONE.AWK A.TXT", "RAWK: cannot find the program file\n"),
    ("RAWK -v x 'BEGIN {print}'", "RAWK: -v takes name=value\n"),
    ("RAWK -v NR=3 'BEGIN {print}'", "RAWK: NR, NF, FNR, FILENAME cannot be changed yet near: \n"),
    ("RAWK 'BEGIN {break}'", "RAWK: break or continue outside a loop near: break}\n"),
    ("RAWK 'BEGIN {next}'", "RAWK: next is not for BEGIN or END near: next}\n"),
    ("RAWK 'BEGIN {print substr(1)}'", "RAWK: wrong number of values for a function near: )}\n"),
    ("RAWK 'BEGIN {print split(1)}'", "RAWK: split comes in a later version near: split(1)}\n"),
    ("RAWK 'BEGIN {do x++}'", "RAWK: a do needs its while near: }\n"),
    ("RAWK 'BEGIN {for (i = 1 i < 2; i++) x}'", "RAWK: a ; is missing near: ) x}\n"),
    ("RAWK 'BEGIN {if 1 print}'", "RAWK: a ( is missing near: 1 print}\n"),
    ("RAWK 'BEGIN {printf \"%d %s|%%|%q\\n\", 7}'", "7 |%|%q\n"),
    ("RAWK 'BEGIN {FS = \"ab\"} {print}' A.TXT", "RAWK: FS must be one character in RAWK\n"),
    # whole numbers: what awk would print as decimals
    ("RAWK '{print $3 / $2}' S.TXT", "3\n0\n0\n"),
    ("RAWK 'BEGIN {print 7 / 2, -7 / 2}'", "3 -3\n"),
    ("RAWK '{print $1 + 0, $1 * 2}' D.TXT", "3 6\n1 2\n0 0\n"),
    # names by DIR's rules: the card's order; a folder
    ("RAWK 'FNR == 1 {print FILENAME}' *.TXT", "A.TXT\nS.TXT\nT.TXT\nN.TXT\nD.TXT\nLONG.TXT\nBIG.TXT\n"),
    ("RAWK '/lot/ {print FILENAME \": \" $0}' DOCS", "NOTE.TXT: lot of words\n"),
]


def mac_awk(cmd, d):
    r = subprocess.run(['/bin/sh', '-c', 'awk ' + cmd.split(' ', 1)[1]], cwd=d, capture_output=True, text=True,
                       stdin=subprocess.DEVNULL)
    return r.stdout


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    rawk = dict(build.samples())[b'RAWK    PRG']
    cf, e2k, st = P1.installed(mem, 16384)
    def put(m):
        for n, dt in FILES.items():
            p = os.path.join(m, *n.split('/'))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, 'wb').write(dt)
        open(os.path.join(m, 'RAWK.PRG'), 'wb').write(rawk)
    img, _ = P2.mac(V.image(cf, 16384), put)
    P1.load_image(cf, img)
    d = tempfile.mkdtemp()
    for n, dt in FILES.items():
        p = os.path.join(d, *n.split('/'))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'wb').write(dt.replace(b'\r', b''))      # (RAWK drops a CR before an LF; awk keeps it)

    cmds = SAME + [c for c, w in OWN]
    assert all(len(c) <= 79 for c in cmds), [c for c in cmds if len(c) > 79]   # LTOS's command line
    b = V.Elf2K(cf, keys=b'', later=[('LTOS> ', (c + '\r').encode()) for c in cmds] + [('LTOS> ', b'MON\r')])
    marks, seen = [], 0
    b.boot_rom(cap=1)
    while True:                                         # the instructions each command took
        r = b.run(200_000, stop=0x8003)
        n = b.text().count('LTOS> ')
        if n > seen: marks.append(b.steps); seen = n
        if r != 'cap': break
        if b.steps - (marks[-1] if marks else 0) > 300_000_000:      # no prompt for ~30 minutes of the Elf2K's
            report('stuck after %r' % (cmds[len(marks) - 2] if len(marks) > 1 else 'the boot'), [repr(b.text()[-400:])])
            break
    t = b.text()
    if '-v' in sys.argv: print(t)
    def one(c):
        try: return P2.session_out(t, c + '\r').replace('\r\n', '\n').lstrip('\n')
        except ValueError: return '(not run - the session ended: %s, %r)' % (r, t[-300:])
    got = {c: one(c) for c in cmds}

    e = []
    for c in SAME:
        w = mac_awk(c, d)
        if got[c] != w:
            e.append('%s\n        RAWK: %r\n        awk:  %r' % (c, got[c][:300], w[:300]))
    report('RAWK and the Mac\'s awk print the same: %d programs' % len(SAME), e)
    e = []
    for c, w in OWN:
        if got[c] != w: e.append('%s\n        RAWK: %r\n        want: %r' % (c, got[c], w))
    report('RAWK\'s own answers (whole numbers; what it cannot do yet, said; mistakes in a program): %d' % len(OWN), e)
    if r != 'stop': report('MON at the end', ['%s: %r' % (r, t[-300:])])

    # a screen at a time: 30 lines, a key after 22; Q stops (END not run)
    b2, st2, t2 = P3.session(cf, b'', later=[('LTOS> ', b"RAWK '{print} END {print \"end\"}' LONG.TXT\r"),
                                               ('Q stops --', b' '), ('LTOS> ', b"RAWK '{print} END {print \"end\"}' LONG.TXT\r"),
                                               ('Q stops --', b'Q'), ('LTOS> ', b'MON\r')], cap=400_000_000)
    e = []
    parts = t2.split("RAWK '{print} END {print \"end\"}' LONG.TXT")
    if len(parts) != 3: e.append('%r' % t2[-500:])
    else:
        a, q = parts[1], parts[2]
        if a.count('line ') != 30 or 'end' not in a or a.count('-- more') != 1: e.append('a key goes on: %r' % a[:2000])
        if q.count('line ') != 22 or 'end\r' in q: e.append('Q stops: %r' % q[:2000])
    report('a screen at a time: a key after 22 lines goes on; Q stops (no END)', e)

    # ---- -o NAME: the output into a file (Y / N to replace; sectors and clusters; a folder; nothing on a failure)
    import verify_phase5 as P5
    awkbig = mac_awk("RAWK '{print}' BIG.TXT", d).encode()
    OC = [("RAWK -o OUT.TXT '{print $1, $3}' S.TXT", None),
          ("RAWK -o OUT.TXT '{print $2}' S.TXT", 'Y'),
          ("RAWK -o OUT.TXT '{print \"no\"}' S.TXT", 'N'),
          ("RAWK -o BIGOUT.TXT '{print}' BIG.TXT", None),
          ("RAWK -o DOCS/OUT2.TXT 'END {print NR}' A.TXT", None),
          ("RAWK -o EMPTY.TXT '/zzz/' A.TXT", None),
          ("RAWK -o C.CSV -F, '{print $1}' C.CSV", 'Y'),
          ("RAWK -o ERR.TXT '{print} NR == 400 {print 1 / 0}' BIG.TXT", None),
          ("RAWK -o DOCS '{print}' A.TXT", None),
          ("RAWK -o 'BEGIN {print 1}'", None)]
    rc0, fr0 = P2.fsck_free(V.image(cf, 16384))
    later = []
    for c, yn in OC:
        later.append(('LTOS> ', (c + '\r').encode()))
        if yn: later.append(('(Y/N) ', yn.encode()))
    b3, st3, t3 = P3.session(cf, b'', later=later + [('LTOS> ', b'MON\r')], rtc=P3.clock(), cap=900_000_000)
    if '-v' in sys.argv: print(t3)
    img = V.image(cf, 16384)
    _, fl = P2.mac(img, P5.walk)
    rc, fr = P2.fsck_free(img)
    o = {c: P2.session_out(t3, c + '\r').replace('\r\n', '\n').lstrip('\n') for c, yn in OC}
    e = []
    def want(c, w):
        if o[c] != w: e.append('%s\n        RAWK: %r\n        want: %r' % (c, o[c], w))
    out1, out2 = mac_awk("RAWK '{print $1, $3}' S.TXT", d), mac_awk("RAWK '{print $2}' S.TXT", d)
    want(OC[0][0], 'Saved OUT.TXT, %d bytes.\n' % len(out1))
    want(OC[1][0], 'OUT.TXT is already on the card - replace it? (Y/N) Y\nSaved OUT.TXT, %d bytes.\n' % len(out2))
    want(OC[2][0], 'OUT.TXT is already on the card - replace it? (Y/N) N\nNothing written.\n')
    want(OC[3][0], 'Saved BIGOUT.TXT, %d bytes.\n' % len(awkbig))
    want(OC[4][0], 'Saved OUT2.TXT, 2 bytes.\n')
    want(OC[5][0], 'Saved EMPTY.TXT, 0 bytes.\n')
    want(OC[6][0], 'C.CSV is already on the card - replace it? (Y/N) Y\nSaved C.CSV, 14 bytes.\n')
    want(OC[7][0], 'RAWK: division by zero\n')
    want(OC[8][0], 'DOCS is a folder.\n')
    want(OC[9][0], "RAWK [-F c] [-v x=val] [-o file] 'program' (or -f file) names - HELP RAWK\n")
    for n, w in (('OUT.TXT', out2.encode()), ('BIGOUT.TXT', awkbig), ('DOCS/OUT2.TXT', b'4\n'), ('EMPTY.TXT', b''),
                 ('C.CSV', b'name\nbolt\nnut\n')):
        if fl.get(n) != w: e.append('%s on the card: %r' % (n, (fl.get(n) or b'(missing)')[:80]))
    if 'ERR.TXT' in fl: e.append('ERR.TXT was saved')
    if rc != 0: e.append('fsck_msdos %d' % rc)
    used = sum((len(fl[n]) + 511) // 512 for n in ('OUT.TXT', 'BIGOUT.TXT', 'DOCS/OUT2.TXT')) + (len(fl['C.CSV']) + 511) // 512 \
        - (len(FILES['C.CSV']) + 511) // 512
    if fr0[1] - fr[1] != used: e.append('free clusters %d -> %d: %d taken, %d expected (clusters lost?)' % (fr0[1], fr[1], fr0[1] - fr[1], used))
    report('-o: a new file, replaced (Y), kept (N), 17 KB (many sectors), into a folder, empty, its own input; '
           'a failure saves nothing and gives its clusters back; fsck clean', e)

    big = [(c, (marks[i + 1] - marks[i]) / 93000) for i, c in enumerate(cmds) if 'BIG.TXT' in c and i + 1 < len(marks)]
    for c, s in big: print('    %-62s %5.1f s on the Elf2K' % (c, s))
    print('LTOS RAWK: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
