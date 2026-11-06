# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The Linux-like tools in the simulator, against Python's own answers: WC, GREP, FIND, TREE, SEND, FSCK.

    python3 LTOS/verify_tools.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

TEXTS = {
    'A.TXT': b'one two three\nfour five\n',
    'B.TXT': b'Hello, World!\r\nhello again\r\n  spaced   out  words  \r\n',
    'DOCS/NOTE.TXT': b'In a folder\nsecond line\n\nfourth after a blank\n',
    'DOCS/OLD/DEEP.TXT': b'deep down\n',
    'GAMES/X.STL': bytes(range(256)) * 3,
}


def card(mem, extra=None):
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        for n, d in TEXTS.items():
            p = os.path.join(m, *n.split('/'))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, 'wb').write(d)
        if extra: extra(m)
    img, _ = P2.mac(V.image(cf, 16384), put)
    P1.load_image(cf, img)
    return cf


def out(t, cmd):
    return P2.session_out(t, cmd + '\r').lstrip('\r\n')


def wc(d):
    return d.count(b'\n'), len(d.split()), len(d)


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    # ---- WC
    HELPTXT = build.help_list().encode()                  # (HELP.TXT is in the root too)
    cf = card(mem)
    cmds = ['WC A.TXT', 'WC *.TXT', 'WC DOCS', 'WC NOPE.TXT', 'WC']
    b, st, t = P3.session(cf, ''.join(c + '\r' for c in cmds).encode() + b'MON\r', rtc=P3.clock())
    if '-v' in sys.argv: print(t)
    e = []
    def line(n, d): return '%8d%9d%11d  %s' % (wc(d) + (n,))
    want = {'WC A.TXT': [line('A.TXT', TEXTS['A.TXT'])],
            'WC *.TXT': [line('HELP.TXT', HELPTXT), line('A.TXT', TEXTS['A.TXT']), line('B.TXT', TEXTS['B.TXT'])],
            'WC DOCS': [line('NOTE.TXT', TEXTS['DOCS/NOTE.TXT'])]}
    tot = [sum(x) for x in zip(wc(HELPTXT), wc(TEXTS['A.TXT']), wc(TEXTS['B.TXT']))]
    want['WC *.TXT'].append('%8d%9d%11d  total' % tuple(tot))
    for c, w in want.items():
        got = [l for l in out(t, c).split('\r\n') if l.strip()][1:]
        if got != w: e.append('%s: %r (want %r)' % (c, got, w))
    if 'No file matches.' not in out(t, 'WC NOPE.TXT'): e.append('WC NOPE.TXT: %r' % out(t, 'WC NOPE.TXT'))
    if 'WC names' not in out(t, 'WC'): e.append('WC alone: %r' % out(t, 'WC'))
    if st != 'stop': e.append('MON: %s' % st)
    report('WC: one file, *.TXT (a total), a folder, no match, no names', e)

    # ---- GREP
    def grep(pat, names, ci=False, num=False):
        res = []
        for n in names:
            for k, l in enumerate(TEXTS[n].replace(b'\r', b'').split(b'\n'), 1):
                if not l and k == len(TEXTS[n].replace(b'\r', b'').split(b'\n')): continue
                if (pat.lower() in l.decode().lower()) if ci else (pat in l.decode()):
                    res.append(('%s:' % n.split('/')[-1] if len(names) > 1 else '') + ('%d:' % k if num else '') + l.decode())
        return res
    cmds = ['GREP o A.TXT', 'GREP -i hello B.TXT', 'GREP -n -i HELLO A.TXT B.TXT', 'GREP "two thr" *.TXT',
            'GREP -n line DOCS', 'GREP zzz A.TXT', 'GREP x NOPE.TXT', 'GREP', 'GREP -q x A.TXT']
    b, st, t = P3.session(cf, ''.join(c + '\r' for c in cmds).encode() + b'MON\r', rtc=P3.clock())
    if '-v' in sys.argv: print(t)
    e = []
    for c, w in (('GREP o A.TXT', grep('o', ['A.TXT'])), ('GREP -i hello B.TXT', grep('hello', ['B.TXT'], ci=True)),
                 ('GREP -n -i HELLO A.TXT B.TXT', grep('HELLO', ['A.TXT', 'B.TXT'], True, True)),
                 ('GREP "two thr" *.TXT', ['A.TXT:one two three']), ('GREP -n line DOCS', grep('line', ['DOCS/NOTE.TXT'], num=True)),
                 ('GREP zzz A.TXT', [])):
        got = [l for l in out(t, c).split('\r\n') if l]
        if got != w: e.append('%s: %r (want %r)' % (c, got, w))
    if 'No file matches.' not in out(t, 'GREP x NOPE.TXT'): e.append('GREP x NOPE.TXT: %r' % out(t, 'GREP x NOPE.TXT'))
    for c in ('GREP', 'GREP -q x A.TXT'):
        if 'GREP [-i] [-n] text names' not in out(t, c): e.append('%s: %r' % (c, out(t, c)))
    if st != 'stop': e.append('MON: %s' % st)
    report('GREP: one file, -i, -n with two files (names), "quoted words", a folder, no line, no file, bad flags', e)

    # ---- FIND, TREE (the card: HELP.TXT, A.TXT, B.TXT in the root; DOCS/NOTE.TXT, DOCS/OLD/DEEP.TXT, GAMES/X.STL;
    #      the programs, as installed_full puts them, in the root)
    cmds = ['FIND NOTE.TXT', 'FIND *.STL', 'FIND DEEP', 'FIND OLD', 'FIND NOPE.TXT', 'FIND', 'CD DOCS', 'TREE', 'CD /', 'TREE']
    b, st, t = P3.session(cf, ''.join(c + '\r' for c in cmds).encode() + b'  MON\r', rtc=P3.clock())
    if '-v' in sys.argv: print(t)
    e = []
    for c, w in (('FIND NOTE.TXT', ['/DOCS/NOTE.TXT']), ('FIND *.STL', ['/GAMES/X.STL']),
                 ('FIND DEEP', ['/DOCS/OLD/DEEP.TXT']), ('FIND OLD', ['/DOCS/OLD/'])):
        got = [l for l in out(t, c).split('\r\n') if l]
        if got != w: e.append('%s: %r (want %r)' % (c, got, w))
    if 'Nothing by that name.' not in out(t, 'FIND NOPE.TXT'): e.append('FIND NOPE.TXT: %r' % out(t, 'FIND NOPE.TXT'))
    if 'FIND name' not in out(t, 'FIND'): e.append('FIND alone: %r' % out(t, 'FIND'))
    m = re.search(r'LTOS /DOCS> TREE\r\r\n(.*?)LTOS', t, re.S)
    sub = [l for l in (m.group(1) if m else '').split('\r\n') if l]
    want = ['%-26s%5d file %11d bytes' % ('/DOCS/', 1, len(TEXTS['DOCS/NOTE.TXT'])),
            '%-26s%5d file %11d bytes' % ('  OLD/', 1, len(TEXTS['DOCS/OLD/DEEP.TXT'])),
            '2 folders, 2 files, %d bytes' % (len(TEXTS['DOCS/NOTE.TXT']) + len(TEXTS['DOCS/OLD/DEEP.TXT']))]
    if sub != want: e.append('TREE in /DOCS: %r (want %r)' % (sub, want))
    m = re.search(r'LTOS> TREE\r\r\n(.*?)LTOS', t, re.S)
    whole = re.sub(r'-- more: a key goes on, Q stops --.\r {34}\r', '', m.group(1) if m else '', flags=re.S)
    names = [l.split()[0] for l in whole.split('\r\n') if l.strip() and not l.startswith(('4 folders', '5 folders'))]
    if names != ['/', 'DOCS/', 'OLD/', 'GAMES/'] or not re.search(r'4 folders, \d+ files, \d+ bytes', whole):
        e.append('TREE from the root: %r' % whole[-400:])
    if st != 'stop': e.append('MON: %s' % st)
    report('FIND: a name, *.STL, no dot (any extension), a folder, nothing, no name; TREE from /DOCS (exact) and the root', e)

    # ---- SEND: its Intel HEX decoded here must be the file; -T: the text with CR LF line ends
    def unhex(text):
        data, base, ended = {}, 0, False
        for ln in text.split('\r\n'):
            if not ln.startswith(':'): continue
            r = bytes.fromhex(ln[1:])
            if sum(r) & 0xFF: return 'a bad checksum in %r' % ln
            n, a, ty = r[0], (r[1] << 8) | r[2], r[3]
            if ty == 0:
                for i, x in enumerate(r[4:4 + n]): data[base + a + i] = x
            elif ty == 4: base = ((r[4] << 8) | r[5]) << 16
            elif ty == 1: ended = True
        if not ended: return 'no end record'
        return bytes(data.get(i, 0) for i in range(max(data) + 1)) if data else b''
    big = bytes((i * 31 + (i >> 9)) & 0xFF for i in range(70000))
    cf2 = card(mem, lambda m: open(os.path.join(m, 'BIG.BIN'), 'wb').write(big))
    cmds = ['SEND A.TXT', 'SEND GAMES/X.STL', 'SEND BIG.BIN', 'SEND -T A.TXT', 'SEND -T B.TXT', 'SEND NOPE.TXT', 'SEND']
    b, st, t = P3.session(cf2, ''.join(c + '\r' for c in cmds).encode() + b'MON\r', rtc=P3.clock(), cap=3_000_000_000)
    e = []
    for c, want in (('SEND A.TXT', TEXTS['A.TXT']), ('SEND GAMES/X.STL', TEXTS['GAMES/X.STL']), ('SEND BIG.BIN', big)):
        got = unhex(out(t, c))
        if got != want: e.append('%s: %r' % (c, got if isinstance(got, str) else '%d bytes, differ' % len(got)))
    if out(t, 'SEND -T A.TXT') != TEXTS['A.TXT'].decode().replace('\n', '\r\n'): e.append('SEND -T A.TXT: %r' % out(t, 'SEND -T A.TXT'))
    if out(t, 'SEND -T B.TXT') != TEXTS['B.TXT'].decode(): e.append('SEND -T B.TXT: %r' % out(t, 'SEND -T B.TXT'))
    if 'There is no file' not in out(t, 'SEND NOPE.TXT'): e.append('SEND NOPE.TXT: %r' % out(t, 'SEND NOPE.TXT'))
    if 'SEND [-T] name' not in out(t, 'SEND'): e.append('SEND alone: %r' % out(t, 'SEND'))
    if st != 'stop': e.append('MON: %s' % st)
    report('SEND: Intel HEX = the file (text, binary, 70,000 bytes with 64 KB records); -T text (LF -> CR LF)', e)

    # ---- FSCK: a clean card; then one damaged in Python - a lost cluster, a cross-link, a wrong size, a FAT 2
    #      byte; then -F (Y) on a card with only lost clusters: the Mac's fsck_msdos calls it clean after
    class Fat:
        def __init__(s, img):
            s.img = bytearray(img)
            s.p = int.from_bytes(s.img[454:458], 'little') * 512          # the partition (MBR entry 1)
            b = s.img[s.p:s.p + 512]
            s.spc, s.res, s.nf = b[13], int.from_bytes(b[14:16], 'little'), b[16]
            s.nroot, s.fsz = int.from_bytes(b[17:19], 'little'), int.from_bytes(b[22:24], 'little')
            s.fat = s.p + s.res * 512
            s.root = s.fat + s.nf * s.fsz * 512
        def get(s, c): return int.from_bytes(s.img[s.fat + 2 * c:s.fat + 2 * c + 2], 'little')
        def put(s, c, v, both=True):
            for k in range(s.nf if both else 1):
                a = s.fat + k * s.fsz * 512 + 2 * c; s.img[a:a + 2] = v.to_bytes(2, 'little')
        def entry(s, name):
            for i in range(s.nroot):
                a = s.root + 32 * i
                if s.img[a:a + 11] == name: return a
        def free(s):
            return next(c for c in range(100, 1000) if s.get(c) == 0)
    cmds = ['FSCK', 'FSCK -X']
    cf3 = card(mem)
    b, st, t = P3.session(cf3, ''.join(c + '\r' for c in cmds).encode() + b'MON\r', rtc=P3.clock(), cap=3_000_000_000)
    if '-v' in sys.argv: print(t)
    e = []
    if 'No problems found.' not in out(t, 'FSCK') or not re.search(r'Checked: \d+ files, 4 folders', out(t, 'FSCK')):
        e.append('a clean card: %r' % out(t, 'FSCK')[-300:])
    if 'FSCK [-F]' not in out(t, 'FSCK -X'): e.append('FSCK -X: %r' % out(t, 'FSCK -X'))
    rc, _ = P2.fsck_free(V.image(cf3, 16384))
    if rc: e.append('the Mac: fsck %d after a check' % rc)
    report('FSCK: a clean card (the Mac\'s own files too): "No problems found."; a bad flag', e)
    f = Fat(V.image(cf3, 16384))
    lost = f.free(); f.put(lost, 0xFFFF)                                       # a lost cluster
    ea, eb = f.entry(b'A       TXT'), f.entry(b'B       TXT')
    f.img[eb + 26:eb + 28] = f.img[ea + 26:ea + 28]                             # B shares A's cluster
    f.img[ea + 28:ea + 32] = (5000).to_bytes(4, 'little')                       # A's size wrong
    f.img[f.fat + f.fsz * 512 + 2 * 3] ^= 0x01                                  # FAT 2 differs (one sector)
    cf4 = type(cf3)(sectors=16384); P1.load_image(cf4, bytes(f.img))
    b, st, t = P3.session(cf4, b'FSCK\rMON\r', rtc=P3.clock(), cap=3_000_000_000)
    o = out(t, 'FSCK'); e = []
    for w in ('/A.TXT: its size does not match its clusters', '/B.TXT: cross-linked',
              'lost clusters (in use, but in no file) - FSCK -F frees them', "The FAT's two copies differ in 1 sectors."):
        if w not in o: e.append('missing %r in %r' % (w, o[-500:]))
    if 'No problems found.' in o: e.append('it said no problems')
    report('FSCK on a damaged card: the wrong size, the cross-link, lost clusters, the FAT copies - each found', e)
    f = Fat(V.image(cf3, 16384))
    for k in range(3): f.put(f.free(), 0xFFFF)                                  # 3 lost clusters, nothing else
    cf5 = type(cf3)(sectors=16384); P1.load_image(cf5, bytes(f.img))
    rc0, _ = P2.fsck_free(bytes(f.img))
    b, st, t = P3.session(cf5, b'FSCK -F\rYFSCK\rMON\r', rtc=P3.clock(), cap=3_000_000_000)
    e = []
    if not re.search(r'3 lost clusters', t) or 'Freed.' not in t: e.append('FSCK -F: %r' % t[-500:])
    if 'No problems found.' not in out(t, 'FSCK'): e.append('FSCK after: %r' % out(t, 'FSCK')[-300:])
    rc, _ = P2.fsck_free(V.image(cf5, 16384))
    if rc or not rc0: e.append('the Mac: fsck %d before, %d after (want not 0, then 0)' % (rc0, rc))
    report('FSCK -F, Y: 3 lost clusters freed - FSCK and the Mac\'s fsck_msdos both call the card clean after', e)

    print('Tools: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
