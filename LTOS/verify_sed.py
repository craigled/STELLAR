# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""SED on the simulated Elf2K, each script's output held to the Mac's own sed (POSIX) or, for what only GNU's has
(\\+ \\? \\|, I, the n of an empty match), to the answer written here.

    python3 LTOS/verify_sed.py [-v]
"""
import os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import build

T = {'A.TXT': b'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n',
     'B.TXT': b'hello world\nHello World\nfoo bar foo bar\n  leading spaces\ntrailing  \n\na.b*c[d]\n2026-11-07 date\nJohn Smith\nabcabcabc\n',
     'C.TXT': b'no end of line\nlast one',
     'D.TXT': b'CR line\r\nsecond\r\n'}
# (the command after SED, what the Mac's sed runs if not the same: None = run it)
POSIX = [
 "'s/o/0/' A.TXT", "'s/o/0/g' B.TXT", "'s/foo/X/2' B.TXT", "'s/foo/X/2g' B.TXT" if False else "'s/l/L/3' B.TXT", "-n '2p' A.TXT", "-n '2,4p' A.TXT", "-n '$p' A.TXT", "-n '/t/p' A.TXT", "'2d' A.TXT",
 "'2,$d' A.TXT", "'/e/d' A.TXT", "'/e/!d' A.TXT", "'3!d' A.TXT", "-n '/two/,/four/p' A.TXT", "-n '/two/,+0p' A.TXT" if False else "-n '/six/,$p' A.TXT", "-n '3,1p' A.TXT", "-n '/one/,2p' A.TXT",
 "'s/[aeiou]/*/g' B.TXT", "'s/[^a-z]//g' B.TXT", "'s/^/> /' A.TXT", "'s/$/ </' A.TXT", "'s/^  *//' B.TXT", "'s/  *$//' B.TXT", "'s/.*/[&]/' A.TXT", "'s/\\(.*\\) \\(.*\\)/\\2 \\1/' B.TXT",
 "'s/\\([a-z]*\\) \\([a-z]*\\)/\\2 \\1/' B.TXT", "'s/a.b/X/' B.TXT", "'s/a\\.b/X/' B.TXT", "'s/\\*/S/' B.TXT", "'s/\\[d\\]/D/' B.TXT", "'s/[0-9]\\{4\\}-[0-9]\\{2\\}/YM/' B.TXT", "'s/\\(abc\\)\\1/two/' B.TXT",
 "'s/\\(abc\\)*/X/' B.TXT", "'s/\\(a\\)\\(b\\)\\(c\\)/\\3\\2\\1/g' B.TXT", "'s#/#|#g' B.TXT", "'s|o|0|g' B.TXT", "'s/o/\\&/' A.TXT", "'s/e/&&/g' A.TXT", "'y/abc/xyz/' B.TXT", "'y/lo/01/' B.TXT",
 "-n 's/foo/X/p' B.TXT", "-n 's/foo/X/gp' B.TXT", "'=' A.TXT", "-n '$=' A.TXT", "-n '/t/=' A.TXT", "'2q' A.TXT", "'$!N;s/\\n/ /' A.TXT", "'$!N;P;D' A.TXT",
 "'1!G;h;$!d' A.TXT", "-n '1!G;h;$p' A.TXT", "'G' A.TXT", "'x;$G' A.TXT", "-n 'H;${x;s/\\n/,/g;p;}' A.TXT", "'/two/{s/t/T/;s/o/O/;}' A.TXT", "'/t/{/w/d;}' A.TXT", "'2,4{s/e/E/;/F/d;}' A.TXT", "-n '/two/{n;p;}' A.TXT",
 "-e 's/o/0/' -e 's/e/E/' A.TXT", "-n -e '2p' -e '4p' A.TXT", "'s/one/1/;s/two/2/' A.TXT A.TXT",
 "-n '$p' A.TXT B.TXT", "-n '12p' A.TXT B.TXT", "'s/x*/-/g' A.TXT", "'s/b*/X/g' B.TXT", "-n '/^$/=' B.TXT", "'/^$/d' B.TXT", "'s/[[:upper:]]/U/g' B.TXT", "'s/[[:digit:]][[:digit:]]*/N/g' B.TXT", "'s/[[:space:]]/_/g' B.TXT", "'s/[]]/R/' B.TXT", "'s/[^]]/R/' B.TXT",
 "'s/\\(a*\\)*$/E/' B.TXT", "'s/\\(ab\\)*\\(c\\)/[\\1\\2]/g' B.TXT", "-E 's/(a|b)*c/<&>/g' B.TXT", "-E 's/(x*)+o/Q/' A.TXT", "-n 'l' B.TXT", "'s/e\\{2\\}/E/' A.TXT", "'s/o\\{1,\\}/O/' A.TXT", "'s/\\(foo\\) \\(bar\\) \\1 \\2/same/' B.TXT", "'//d' A.TXT" if False else "'/one/s//1/' A.TXT", "'s/t/&/2' A.TXT", "'$!d' C.TXT", "'s/$/!/' C.TXT", 
 "-E 's/(a|b)+/X/g' B.TXT", "-E 's/o+/0/' A.TXT", "-E 's/(hello|foo) (world|bar)/\\2 \\1/' B.TXT", "-E 's/[0-9]{4}/Y/' B.TXT", "-E 's/^(.)(.*)$/\\2\\1/' A.TXT", "-E 's/e?n/N/g' A.TXT", "-E 's/(ab)*c/Z/' B.TXT", "-E 's/a|e|i/V/g' A.TXT",
]
GNU = [  # the Mac's sed has not these: the answer here
 ("'s/l\\+/L/' A.TXT", None), ("'s/hello/X/I' B.TXT", ['X world', 'X World', 'foo bar foo bar', '  leading spaces', 'trailing  ', '', 'a.b*c[d]', '2026-11-07 date', 'John Smith', 'abcabcabc']),
 ("-n '/HELLO/Ip' B.TXT", ['hello world', 'Hello World']), ("'1a\\\nadded' C.TXT", None), ("'2i inserted' C.TXT", ['no end of line', 'inserted', 'last one']), ("'1a added' C.TXT", ['no end of line', 'added', 'last one']), ("'1c changed' C.TXT", ['changed', 'last one']),
 ("'2,4c many' A.TXT", ['one', 'many', 'five', 'six', 'seven', 'eight', 'nine', 'ten']), ("'$a end' C.TXT", ['no end of line', 'last one', 'end']), ("'1Q' A.TXT", []), ("'s/o\\|e/V/' A.TXT", ['Vne', 'twV', 'thrVe', 'fVur', 'fivV', 'six', 'sVven', 'Vight', 'ninV', 'tVn']),
 ("'s/o/0/;T;s/$/!/' C.TXT", ['n0 end of line!', 'last 0ne!']), ("'s/x\\?o/_/' A.TXT", ['_ne', 'tw_', 'three', 'f_ur', 'five', 'six', 'seven', 'eight', 'nine', 'ten']),
]
TEN = ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten']
GNU += [("'n;d' A.TXT", ['one', 'three', 'five', 'seven', 'nine']), ("'N;N;s/\\n/,/g' A.TXT", ['one,two,three', 'four,five,six', 'seven,eight,nine', 'ten']), ("'N;P;D' A.TXT", TEN),
        ("':a;s/^\\(x*\\)o/\\1x/;ta' A.TXT", ['xne'] + TEN[1:]), ("'s/o/0/;t;s/e/E/' A.TXT", ['0ne', 'tw0', 'thrEe', 'f0ur', 'fivE', 'six', 'sEven', 'Eight', 'ninE', 'tEn']),
        ("'s/o/0/;tz;s/e/E/;:z' A.TXT", ['0ne', 'tw0', 'thrEe', 'f0ur', 'fivE', 'six', 'sEven', 'Eight', 'ninE', 'tEn']), ("'bz;s/o/0/;:z' A.TXT", TEN),
        ("'s/$/!/' D.TXT", ['CR line!', 'second!']), ("'s/o/0/ # note' C.TXT", ['n0 end of line', 'last 0ne'])]
BAD = ["'s/a/b' A.TXT", "'k' A.TXT", "'{p' A.TXT", "'p}' A.TXT", "'b nolabel' A.TXT", "'y/abc/x/' A.TXT", "'s/\\(a/b/' A.TXT"]


def mac(cmd, d):
    r = subprocess.run('/usr/bin/sed ' + cmd.replace('-E ', '-E ', 1), shell=True, cwd=d, capture_output=True)
    return r.stdout.decode('latin1').split('\n')


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + str(x)[:200]) for x in e[:14]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed_full(mem, n)
    prg = build.prg('sed')
    sy = build.assemble('sed')[1]
    assert sy['DEND'] <= 0x6C00, 'SED runs to $%04X' % sy['DEND']
    def put(m):
        os.makedirs(os.path.join(m, 'BIN'), exist_ok=True)
        open(os.path.join(m, 'BIN', 'SED.PRG'), 'wb').write(prg)
        for k, v in T.items(): open(os.path.join(m, k), 'wb').write(v)
        open(os.path.join(m, 'S.SED'), 'wb').write(b'# a script\r\n/two/{\ns/t/T/\na\\\nline one\\\nline two\n}\n$i\\\nbefore the end\ny/e/E/\n')
    base, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, base)
    d = tempfile.mkdtemp()
    for k, v in T.items(): open(os.path.join(d, k), 'wb').write(v)

    def run(cmds, cap=3_000_000_000):
        later = [('LTOS> ', ('SED ' + c.replace('\n', '\r')).encode('latin1') + b'\r') for c in cmds] + [('LTOS> ', b'MON\r')]
        return later

    def session(cmds, cap=6_000_000_000):
        later = [('LTOS> ', c.encode('latin1') + b'\r') for c in cmds] + [('LTOS> ', b'MON\r')]
        b = V.Elf2K(cf, keys=b'', later=later)
        st = b.boot_rom(cap)
        t = b.text().replace('\r', '')
        parts = re.split(r'(?m)^LTOS> ', t)[1:]
        res = []
        for c, p in zip(cmds, parts):
            res.append(p[len(c) + 1:] if p.startswith(c) else '?? ' + p)
        return st, res, len(parts)

    if os.environ.get('SEDONLY'):
        st, res, np_ = session(['SED ' + c for c in os.environ['SEDONLY'].split('@@')])
        print(st, res); return True
    # 1. POSIX scripts against the Mac's sed
    e = []
    for part in range(0, len(POSIX), 25):
        cs = POSIX[part:part + 25]
        st, res, np_ = session(['SED ' + c for c in cs])
        if st != 'stop': e.append('%s: %r' % (st, res[-1][-200:] if res else ''))
        for c, r in zip(cs, res):
            w = mac(c, d)
            w = w[:-1] if w and w[-1] == '' else w
            g = r.split('\n')
            g = g[:-1] if g and g[-1] == '' else g
            if '-v' in sys.argv: print(c, g[:3])
            if g != w: e.append('%s\n      got  %r\n      want %r' % (c, g[:12], w[:12]))
    report('%d scripts against the Mac\'s sed' % len(POSIX), e)

    # 2. what only GNU's has
    e = []
    cs = [c for c, w in GNU]
    st, res, np_ = session(['SED ' + c.replace('\n', ' ') for c in cs if '\n' not in c])
    k = 0
    for c, w in GNU:
        if '\n' in c: continue
        g = res[k].split('\n'); k += 1
        g = g[:-1] if g and g[-1] == '' else g
        if w is None: w = [l for l in T['A.TXT'].decode().split('\n')[:-1]] if 'l\\+' in c else w
        if g != w: e.append('%s\n      got  %r\n      want %r' % (c, g[:12], w))
    report('%d scripts in GNU\'s manner' % len(cs), e)

    # 3. a script file, > a file, the same file, bad scripts, no file
    e = []
    st, res, np_ = session(['SED -f S.SED A.TXT', "SED 's/o/0/g' A.TXT > OUT.TXT", 'TYPE OUT.TXT', "SED 's/one/ONE/' A.TXT > A.TXT", 'TYPE A.TXT', "SED 's/a/b/' NOPE.TXT", 'SED'] + ['SED ' + c for c in BAD])
    w = ['onE', 'Two', 'line one', 'line two', 'thrEE', 'four', 'fivE', 'six', 'sEvEn', 'Eight', 'ninE', 'before the end', 'tEn']
    if res[0].split('\n')[:-1] != w: e.append('script file: %r' % res[0])
    if res[2].split('\n')[0] != 'One'.lower().replace('o', '0') : e.append('> : %r' % res[2][:30])
    if res[4].split('\n')[0] != 'ONE': e.append('> the same file: %r' % res[4][:40])
    if 'No file' not in res[5]: e.append('no file: %r' % res[5])
    for c, r in zip(BAD, res[7:]):
        if 'SED:' not in r: e.append('%s: %r' % (c, r[:80]))
    report('A script file; > a file, and the same file; no file; %d bad scripts say so' % len(BAD), e)
    # 4. the hard ones: lines too long, patterns that go round for ever, a big file
    e = []
    long = b'ab' * 900 + b'\nend\n'
    big = b''.join(b'Line %d of the file, with the words to change in it.\n' % i for i in range(1, 401))
    def put2(m):
        open(os.path.join(m, 'L.TXT'), 'wb').write(long); open(os.path.join(m, 'BIG.TXT'), 'wb').write(big)
    img, _ = P2.mac(V.image(cf, n), put2)
    P1.load_image(cf, img)
    st, res, np_ = session(["SED 's/a/XX/g' L.TXT", "SED 's/\\(a*\\)*$/E/' A.TXT", "SED 's/\\(a*\\)*b/X/' L.TXT", "SED -n '$p' L.TXT", "SED 's/.*/&&&/' L.TXT", "SED 'G;G;G;h' L.TXT"])
    if st != 'stop': e.append(st)
    if len(res) != 6: e.append('%d answers' % len(res))
    else:
        l0 = res[0].split('\n')[0]
        if len(l0) != 511 + 255 and not (0 < len(l0) <= 1023): e.append('long line: %d' % len(l0))
        if res[3] != 'end\n': e.append('$ after a long line: %r' % res[3][:40])
        if res[1].split('\n')[0] != 'ONEE': e.append('a loop that matches nothing: %r' % res[1][:30])
    b = V.Elf2K(cf, keys=b'', later=[('LTOS> ', b"SED -n 's/words/WORDS/gp' BIG.TXT > O.TXT\r"), ('LTOS> ', b'MON\r')])
    st = b.boot_rom(3_000_000_000)
    n1 = b.steps
    b = V.Elf2K(cf, keys=b'', later=[('LTOS> ', b"CAT BIG.TXT > P.TXT\r"), ('LTOS> ', b'MON\r')])
    st = b.boot_rom(3_000_000_000)
    print('    400 lines (21 KB) through s///gp > a file: about %.0f s on the Elf2K (CAT to a file takes %.0f s of that)' % ((n1 - 0) / 85000, b.steps / 85000))
    report('Lines too long are cut, a pattern that goes round ends, a bigger file', e)
    print('SED: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
