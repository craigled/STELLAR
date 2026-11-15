# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""DEROFF.PRG against deroff() below - the same rules in Python (there is no deroff on the Mac to ask). Each file
run with > to a file on the card, read back and compared byte for byte, plain and with -w: the EROFF manual
(examples/EROFF.RF), a file of every escape and request, a table and an equation, CR LF lines, a line of 2500
characters, no LF at the end, an empty file. Then usage, and a file that is not there.

    python3 LTOS/verify_deroff.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

LMAX, WMAX = 1000, 63
WCH = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789&'")
LET = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz')


def unescape(t):
    r, i = [], 0
    while i < len(t):
        c = t[i]; i += 1
        if c != '\\': r.append(c); continue
        if i >= len(t): break
        d = t[i]; i += 1
        if d in 'f*n': i += 3 if t[i:i + 1] == '(' else 1
        elif d == 's':
            if t[i:i + 1] in ('+', '-'): i += 1
            if t[i:i + 1] == '(': i += 3
            elif t[i:i + 1].isdigit(): i += 1
        elif d == '(': i += 2
        elif d == '"': break
        elif d in 'e\\': r.append('\\')
        elif d in ' 0': r.append(' ')
        elif d in '&%c|^': pass
        else: r.append(d)
    return ''.join(r)


def text_of(line):
    """A line's text as DEROFF prints it, or None (a request with nothing to print)."""
    if line[:1] not in ('.', "'"): return line
    name = re.match(r'[^ \t]*', line[1:]).group()
    rest = line[1 + len(name):].lstrip(' \t')
    if name in ('B', 'I', 'R', 'sh'): t = rest
    elif name == 'nh':
        m = re.match(r'[^ \t]*[ \t]', rest)
        t = rest[m.end():].lstrip(' \t') if m else ''
    elif name == 'ip':
        t = rest[1:].split('"')[0] if rest.startswith('"') else re.match(r'[^ \t]*', rest).group()
    else: return None
    return t or None


def deroff(data, words=False):
    text = data.replace(b'\r', b'').decode('latin-1')
    lines = text.split('\n')
    if lines[-1] == '': lines.pop()
    out, skip = [], None
    for whole in lines:
        for k in range(0, max(len(whole), 1), LMAX):
            line = whole[k:k + LMAX]
            if skip:
                if line.startswith(skip): skip = None
                continue
            if line[:1] in ('.', "'"):
                name = re.match(r'[^ \t]*', line[1:]).group()
                if name in ('TS', 'EQ'): skip = {'TS': '.TE', 'EQ': '.EN'}[name]; continue
            t = text_of(line)
            if t is None: continue
            u = unescape(t)
            if not words: out.append(u + '\n'); continue
            for w in re.findall(r"[A-Za-z0-9&']+", u):
                w = w[:WMAX].strip("'")
                if sum(ch in LET for ch in w) >= 2: out.append(w + '\n')
    return ''.join(out).encode('latin-1')


ESC = (b'.\\" a comment line\n'
       b'.sh A \\fBbold\\fR heading\n'
       b'.nh 2 Numbered \\fIone\\fP\n'
       b'.nh 3\n'
       b'.ip "two words" 5\n'
       b'Tagged \\(em paragraph text.\n'
       b'.ip TAG\n'
       b'.ip ""\n'
       b'.ip "open\n'
       b'.B bold words\n'
       b'.I\n'
       b'.R roman\n'
       b'.pp\n'
       b'.ll 60\n'
       b'.sp 2\n'
       b"'br\n"
       b'.shx not a request we know\n'
       b'.\n'
       b'Fonts \\f(CWcode\\fP and \\fB\\fIboth\\fR; sizes \\s+2big\\s-2 \\s(12x\\s0 \\s3y \\s z.\n'
       b'Strings \\*x \\*(ab, numbers \\nA \\n(PN; specials \\(bu\\(co.\n'
       b'A\\-dash, a \\e backslash, \\\\ too, \\&.dot, hy\\%phen, \\|thin\\^ \\cjoined, a\\ space, \\0digit.\n'
       b'Other: \\q \\{ \\} \\. \\x.\n'
       b'Comment after text \\" this goes\n'
       b'\\" only a comment\n'
       b'Trailing backslash \\\n'
       b'.TS\n'
       b'tab(:);\n'
       b'l l.\n'
       b'A:B\n'
       b'.TE\n'
       b'After the table.\n'
       b'.EQ\n'
       b'x sup 2\n'
       b'.TE\n'
       b'still in the equation\n'
       b'.EN\n'
       b'After the equation.\n'
       b"Words: don't 'quoted' rock'n'roll AT&T x1 a b2 99 ab 3D R2D2 'tis '' &&\n"
       b'\n'
       b'\tA TAB line and \\fBend\\fR')
LONG = (b'.sh Long\n' + (b'word ' * 500).rstrip() + b'\n' + b'x' * 999 + b'\n' + b'y' * 1000 + b'\n' + b'z' * 1001 + b'\n'
        + b'.' + b'q' * 1500 + b'\n')
CRLF = b'.sh CR LF\r\nLine one\r\n.pp\r\nLine \\fBtwo\\fR\r\n'
FILES = [('EROFF.RF', open(os.path.join(HERE, 'examples', 'EROFF.RF'), 'rb').read()), ('ESC.RF', ESC), ('LONG.RF', LONG),
         ('CRLF.RF', CRLF), ('EMPTY.RF', b'')]


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed(mem, n)
    def put(m):
        open(os.path.join(m, 'DEROFF.PRG'), 'wb').write(build.prg('deroff'))
        for name, data in FILES: open(os.path.join(m, name), 'wb').write(data)
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)
    c = lambda x: ('LTOS> ', x.encode() + b'\r')
    runs = [(f, w) for f, _ in FILES for w in (False, True)]
    cmds = ['DEROFF %s%s > D%02d.TXT' % ('-w ' if w else '', f, k) for k, (f, w) in enumerate(runs)]
    bad = ['DEROFF', 'DEROFF -w', 'DEROFF -x ESC.RF', 'DEROFF -wESC.RF', 'DEROFF NOPE.RF']
    b = V.Elf2K(cf, keys=b'', later=[c(x) for x in cmds] + [c('DEROFF CRLF.RF')] + [c(x) for x in bad] + [c('MON')])
    b.rtc = P3.clock()
    s = b.boot_rom(12_000_000_000)
    t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
    if v: print(t[-2000:])
    got = {}
    def read(m):
        for k in range(len(cmds)):
            p = os.path.join(m, 'D%02d.TXT' % k)
            got[k] = open(p, 'rb').read() if os.path.exists(p) else None
    P2.mac(V.image(cf, n), read)
    e = []
    if s != 'stop': e.append('the end: %s %r' % (s, t[-300:]))
    data = dict(FILES)
    for k, (f, w) in enumerate(runs):
        want = deroff(data[f], w)
        g = got[k]
        if g != want:
            g = g or b''
            i = next((j for j in range(min(len(g), len(want))) if g[j] != want[j]), min(len(g), len(want)))
            e.append('DEROFF %s%s: differs at byte %d: %r / want %r' % ('-w ' if w else '', f, i, g[max(0, i - 30):i + 30], want[max(0, i - 30):i + 30]))
    if b'Fonts code and both; sizes big x y  z.\n' not in deroff(ESC): e.append('the model itself: %r' % deroff(ESC)[:400])
    report('DEROFF against the rules (in Python): %d files, plain and -w - EROFF.RF, every escape and request, a table '
           'and an equation, CR LF, 1000-character pieces, no last LF, an empty file' % len(FILES), e)

    e = []
    parts = dict((p.split('\n', 1)[0], p.split('\n', 1)[1] if '\n' in p else '') for p in re.split(r'(?m)^LTOS> ', t))
    if parts.get('DEROFF CRLF.RF') != deroff(CRLF).decode(): e.append('on the screen: %r' % parts.get('DEROFF CRLF.RF'))
    for x in bad[:4]:
        if 'Usage: DEROFF' not in parts.get(x, ''): e.append('%s: %r' % (x, parts.get(x)))
    if 'NOPE' not in parts.get('DEROFF NOPE.RF', '') and 'not' not in parts.get('DEROFF NOPE.RF', '').lower():
        e.append('DEROFF NOPE.RF: %r' % parts.get('DEROFF NOPE.RF'))
    rc, _ = P2.fsck_free(V.image(cf, n))
    if rc: e.append('fsck_msdos: %d' % rc)
    report('on the screen; usage; a file not there; fsck clean', e)
    print('\nDEROFF: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
