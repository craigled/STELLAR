# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""FILE.PRG against what_is() below - the same rules in Python. A card of files of every kind (programs with and
without a version, apps, a bundle, Intel HEX, a STELLAR .lst, an LTCALC sheet, EROFF, ASCII / UTF-8 / 8-bit text,
CR LF, the binary signatures and near misses, data, empty, a folder): FILE * > a file, read back and compared line
for line; then a folder's contents (FILE SUB/), a path, two names, a name not there, and usage.

    python3 LTOS/verify_file.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

HEXD = set(b'0123456789ABCDEFabcdef')
MAGIC = [(0, b'\x89PNG', 'PNG image'), (0, b'GIF8', 'GIF image'), (0, b'\xff\xd8\xff', 'JPEG image'), (0, b'%PDF-', 'PDF document'),
         (0, b'PK\x03\x04', 'ZIP archive'), (0, b'\x1f\x8b', 'gzip data'), (0, b'MThd', 'MIDI music'), (8, b'WAVE', 'WAV sound'),
         (0, b'\x7fELF', 'ELF program')]


def pver(b):
    out = ''
    for c in b[:15]:
        if not 32 <= c < 127: break
        out += chr(c)
    return out


def listing(l):
    return re.match(rb'(; ?)?D [0-9A-F]{4}( |$)|;[0-9A-F]{4}  [0-9A-F]{2}( |$)', l[:12]) is not None


def what_is(d, folder=False):
    if folder: return 'folder'
    n = len(d)
    if n == 0: return 'empty'
    if d[:4] == b'STL1' and n >= 512:
        v = pver(d[128:144])
        return 'STELLAR app, %d blocks' % d[4] + (', version ' + v if d[128] else '')
    if d[:4] == b'LPAK' and n >= 5: return 'LTOS bundle (RECV), %d files' % d[4]
    t = d[:512]
    data = any((c < 32 and c not in (9, 10, 12, 13, 26)) or c == 127 for c in t)
    if data and 7 <= n < 65536:                         # a program: only what would be data; its length may pass the file
        load, ln, ex = d[0] << 8 | d[1], d[2] << 8 | d[3], d[4] << 8 | d[5]
        if ln >= n - 6 and load + ln <= 0x10000 and load <= ex <= load + ln - 1:
            s = 'LTOS program, $%04X-$%04X' % (load, load + ln - 1)
            if ex != load and d[6:10] == b'VER:': s += ', version ' + pver(d[10:26])
            return s
    for off, m, name in MAGIC:
        if d[off:off + len(m)] == m: return name
    if data: return 'data'
    hi = any(c >= 0x80 for c in t)
    bad, due = False, 0
    for c in t:
        if due:
            if 0x80 <= c <= 0xBF: due -= 1
            else: bad, due = True, 0
        elif c >= 0x80:
            if c < 0xC2: bad = True
            elif c < 0xE0: due = 1
            elif c < 0xF0: due = 2
            elif c < 0xF5: due = 3
            else: bad = True
    lines = [l for l in t.replace(b'\r', b'').split(b'\n') if l]
    hexok = all(l[0:1] == b':' and len(l) >= 11 and all(c in HEXD for c in l[1:]) for l in lines)
    dany = any(listing(l) for l in lines)
    clc = all(re.match(rb'[A-H]([1-9]|1[0-9]|20) ', l[:12]) for l in lines)
    roff = any(re.match(rb'\.([a-z]{2}|[A-Z]{1,2})([ \t]|$)|\.\\"', l[:12]) for l in lines)
    if not (lines and hexok) and not dany and not roff and not (lines and clc) and n > 512:
        dany = any(listing(l) for l in d[512:8192].replace(b'\r', b'').split(b'\n'))     # further on: a listing's lines
    if lines and hexok: k = 'Intel HEX'
    elif dany: k = 'STELLAR listing (.lst)'
    elif lines and clc: k = 'LTCALC sheet'
    elif roff: k = 'EROFF / nroff text'
    else: k = 'UTF-8 text' if hi and not bad else '8-bit text' if hi else 'ASCII text'
    return k + (', CR LF line ends' if b'\r\n' in t else '')


def show(name, what):
    return (name + ':').ljust(14) + what


APPS = os.path.join(HERE, '..', 'APPLICATIONS')
TG = open(os.path.join(APPS, 'CLOCK', 'Time-Grab.lst')).read()
FILES = [
    ('HELLO.TXT', b'Hello there\nsecond line\n'),
    ('CRLF.TXT', b'one\r\ntwo\r\n'),
    ('UTF8.TXT', 'café — naïve \U0001F600\n'.encode('utf-8')),
    ('LATIN.TXT', 'café\n'.encode('latin-1')),
    ('BADU8.TXT', b'ok \xe2\x82 cut short then more\n'),
    ('CUT.TXT', b'x' * 511 + b'\xe2\x82'),
    ('LATE.LST', b'; header\n' * 300 + b'D 4000 CD\n'),
    ('LATE2.LST', b'x' * 600 + b'\n;4000  CD          START\n'),
    ('TOOLATE.LST', b'; header\n' * 1000 + b'D 4000 CD\n'),
    ('SPLIT.LST', b'a' * 509 + b'\nD 40' + b'00 CD\n' + b'b' * 100),
    ('SEMI.LST', b'; D 4000 CD             START\n'), ('SEMI2.LST', b';D 4000\n'), ('NOTL.TXT', b';DEAD  C\n; D 40\nD 4000x\n'),
    ('BIG.TXT', b'0123456789\n' * 7000),
    ('PRGDS.PRG', b'\x30\x00\x10\x00\x30\x00' + b'\x00\x01\x02'),
    ('DATA.BIN', bytes(range(256))),
    ('CTRLZ.TXT', b'old CP/M text\r\n\x1a\x1a'),
    ('FF.TXT', b'page one\n\x0cpage two\n'),
    ('EMPTY.TXT', b''),
    ('FILE.PRG', build.prg('file')),
    ('ECHO.PRG', build.prg('echo')),
    ('SHORT.PRG', b'\x30\x00\x00\x01\x30\x00'),
    ('BADLEN.PRG', b'\x30\x00\x00\x05\x30\x00abcd'),
    ('BADST.PRG', b'\x30\x00\x00\x04\x31\x00abcd'),
    ('WRAP.PRG', b'\xff\xfe\x00\x02\xff\xfeab'),
    ('TOP.PRG', b'\xff\xfe\x00\x02\xff\xffab'),
    ('TG.STL', build.stl_of(TG)),
    ('TGV.STL', build.stl_of('; VERSION:  3.1b\n' + TG)),
    ('SHORT.STL', b'STL1\x01' + b'\0' * 100),
    ('B.PAK', build.pak([(b'A       TXT', b'hi'), (b'B       TXT', b'there')])),
    ('LPAK.TXT', b'LPAK'),
    ('T.HEX', b':10300000F8FF1B5E3C0101D300D400F8FFAABB01\r\n:00000001FF\r\n'),
    ('HALF.HEX', b':103000\n'),
    ('TG.LST', TG.encode()),
    ('MINI.LST', b'; a listing\nD 4000 CD 01\nD 4002 00\n'),
    ('S.CLC', b'A1 5\nA2 7\nA3 =A1+A2\nH20 total\nB10 x\n'),
    ('NOT.CLC', b'A1 5\nI1 6\n'),
    ('EROFF.RF', open(os.path.join(HERE, 'examples', 'EROFF.RF'), 'rb').read()),
    ('MS.RF', b'Some text first\n.PP\nmore\n'),
    ('CMT.RF', b'.\\" just a comment\n'),
    ('DOTS.TXT', b'...and so on\n.5 is a half\n'),
    ('P.PNG', b'\x89PNG\r\n\x1a\n' + bytes(20)), ('G.GIF', b'GIF89a' + bytes(10)), ('J.JPG', b'\xff\xd8\xff\xe0' + bytes(10)),
    ('D.PDF', b'%PDF-1.4\n%...'), ('Z.ZIP', b'PK\x03\x04' + bytes(26)), ('G.GZ', b'\x1f\x8b\x08\x00' + bytes(6)),
    ('M.MID', b'MThd\x00\x00\x00\x06' + bytes(6)), ('W.WAV', b'RIFF\x24\x00\x00\x00WAVEfmt '), ('E.ELF', b'\x7fELF\x02\x01\x01' + bytes(9)),
    ('PK.TXT', b'PK'), ('WAVE.TXT', b'12345678WAV'),
    ('DIS.LST', open(os.path.join(APPS, 'Prime-Gen-v08.lst'), 'rb').read()),
    ('SC.LST', open(os.path.join(HERE, '..', 'SC', 'examples', 'dice.lst'), 'rb').read()),
]
SUB = [('INNER.TXT', b'inside\n'), ('INNER.PRG', build.prg('echo'))]


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:14]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed(mem, n)
    def put(m):
        os.makedirs(os.path.join(m, 'T'))
        for name, data in FILES: open(os.path.join(m, 'T', name), 'wb').write(data)
        os.makedirs(os.path.join(m, 'T', 'SUB'))
        for name, data in SUB: open(os.path.join(m, 'T', 'SUB', name), 'wb').write(data)
        open(os.path.join(m, 'FILE.PRG'), 'wb').write(build.prg('file'))
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)
    c = lambda x: ('LTOS> ', x.encode() + b'\r')
    cmds = ['FILE T/* > /ALL.OUT', 'FILE T/SUB/', 'FILE T/HELLO.TXT T/*.PNG', 'FILE T/NOPE.X T/HELLO.TXT', 'FILE', 'FILE /FILE.PRG']
    b = V.Elf2K(cf, keys=b'', later=[c(x) for x in cmds] + [c('MON')])
    b.rtc = P3.clock()
    s = b.boot_rom(8_000_000_000)
    t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
    if v: print(t[-3000:])
    got = {}
    P2.mac(V.image(cf, n), lambda m: got.update(all=open(os.path.join(m, 'ALL.OUT'), 'rb').read().decode('latin-1')
                                                 if os.path.exists(os.path.join(m, 'ALL.OUT')) else None))
    e = []
    if s != 'stop': e.append('the end: %s %r' % (s, t[-300:]))
    want = [show(nm, what_is(d)) for nm, d in FILES] + [show('SUB', 'folder')]
    gl = (got['all'] or '').split('\n')
    if gl and gl[-1] == '': gl.pop()
    if sorted(gl) != sorted(want):
        gs, ws = set(gl), set(want)
        for x in sorted(ws - gs): e.append('want %r' % x)
        for x in sorted(gs - ws): e.append(' got %r' % x)
    checks = {'FILE.PRG': 'LTOS program, $', 'ECHO.PRG': 'LTOS program', 'TGV.STL': 'version 3.1b', 'T.HEX': 'Intel HEX',
              'TG.LST': 'STELLAR listing', 'DIS.LST': 'STELLAR listing', 'SC.LST': 'STELLAR listing', 'LATE.LST': 'listing',
              'TOOLATE.LST': 'ASCII', 'PRGDS.PRG': 'LTOS program, $3000-$3FFF', 'LATE2.LST': 'listing', 'SEMI.LST': 'listing', 'SEMI2.LST': 'listing', 'NOTL.TXT': 'ASCII', 'S.CLC': 'LTCALC sheet', 'EROFF.RF': 'EROFF', 'UTF8.TXT': 'UTF-8 text',
              'LATIN.TXT': '8-bit text', 'CRLF.TXT': 'CR LF', 'DATA.BIN': 'data', 'W.WAV': 'WAV sound', 'B.PAK': '2 files'}
    for nm, d in FILES:
        if nm in checks and checks[nm] not in what_is(d): e.append('the model: %s is %r' % (nm, what_is(d)))
    if 'version 1.0' not in what_is(build.prg('file')): e.append('the model: FILE.PRG %r' % what_is(build.prg('file')))
    report('FILE T/* against the rules (in Python): %d files of every kind, and a folder' % len(FILES), e)

    e = []
    parts = dict((p.split('\n', 1)[0], p.split('\n', 1)[1] if '\n' in p else '') for p in re.split(r'(?m)^LTOS> ', t))
    def lines(cmd): return [l for l in parts.get(cmd, '').split('\n') if l]
    if sorted(lines('FILE T/SUB/')) != sorted(show(nm, what_is(d)) for nm, d in SUB): e.append('SUB/: %r' % lines('FILE T/SUB/'))
    if lines('FILE T/HELLO.TXT T/*.PNG') != [show('HELLO.TXT', 'ASCII text'), show('P.PNG', 'PNG image')]:
        e.append('two names: %r' % lines('FILE T/HELLO.TXT T/*.PNG'))
    if lines('FILE T/NOPE.X T/HELLO.TXT') != ['T/NOPE.X: not found', show('HELLO.TXT', 'ASCII text')]:
        e.append('not found: %r' % lines('FILE T/NOPE.X T/HELLO.TXT'))
    if 'Usage: FILE' not in parts.get('FILE', ''): e.append('usage: %r' % parts.get('FILE'))
    if lines('FILE /FILE.PRG') != [show('FILE.PRG', what_is(build.prg('file')))]: e.append('a path: %r' % lines('FILE /FILE.PRG'))
    rc, _ = P2.fsck_free(V.image(cf, n))
    if rc: e.append('fsck_msdos: %d' % rc)
    report('a folder\'s contents (SUB/), two names, a name not there, a path, usage; fsck clean', e)
    print('\nFILE: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
