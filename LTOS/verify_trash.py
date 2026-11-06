# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""DELETE and EMPTY in the simulator: files to /TRASH (made the first time), wildcards and several names, the older
one going on a clash, folders left alone, a file got back with MV, EMPTY's question, the space back, the card clean.

    python3 LTOS/verify_trash.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed_full(mem, n)
    def put(m):
        os.makedirs(os.path.join(m, 'SUB'), exist_ok=True)
        os.makedirs(os.path.join(m, 'DOCS'), exist_ok=True)
        open(os.path.join(m, 'A.TXT'), 'wb').write(b'first\r\n')
        open(os.path.join(m, 'B.BAK'), 'wb').write(b'b' * 3000)
        open(os.path.join(m, 'C.BAK'), 'wb').write(b'c' * 3000)
        open(os.path.join(m, 'NOEXT'), 'wb').write(b'n' * 600)
        open(os.path.join(m, 'DOCS', 'D.TXT'), 'wb').write(b'keep me\r\n')
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)
    cmds = ['EMPTY', 'FREE', 'DELETE', 'DELETE A.TXT', 'DIR /TRASH', 'TYPE A.TXT', 'ECHO second > A.TXT', 'DELETE A.TXT',
            'TYPE /TRASH/A.TXT', 'DELETE NOPE.TXT', 'DELETE *.BAK DOCS/D.TXT NOEXT', 'DELETE SUB', 'DIR SUB', 'CD /TRASH',
            'DELETE A.TXT #', 'CD /', 'MV /TRASH/D.TXT DOCS', 'TYPE DOCS/D.TXT']
    later = [('LTOS /TRASH> ' if c in ('DELETE A.TXT #', 'CD /') else 'LTOS> ', c.replace(' #', '').encode() + b'\r') for c in cmds]
    later += [('LTOS> ', b'EMPTY\r'), ('(Y/N) ', b'N'), ('LTOS> ', b'DIR /TRASH\r'), ('LTOS> ', b'EMPTY\r'), ('(Y/N) ', b'Y'),
              ('LTOS> ', b'DIR /TRASH\r'), ('LTOS> ', b'EMPTY\r'), ('LTOS> ', b'FREE\r'), ('LTOS> ', b'FSCK\r'), ('LTOS> ', b'MON\r')]
    b = V.Elf2K(cf, keys=b'', later=later); b.rtc = P3.clock()
    st = b.boot_rom(3_000_000_000)
    t = b.text().replace('\r', '')
    if '-v' in sys.argv: print(t[t.find('LTOS> EMPTY'):])
    parts = re.split(r'(?m)^LTOS(?: /TRASH)?> ', t)
    def out(c, k=0):
        m = [p[len(c):] for p in parts if p.startswith(c + '\n') or p == c]
        return m[k] if k < len(m) else '(no %s)' % c

    e = []
    if st != 'stop': e.append('the end: %s' % st)
    if 'The trash is empty.' not in out('EMPTY'): e.append('EMPTY with no /TRASH: %r' % out('EMPTY'))
    if 'DELETE names' not in out('DELETE'): e.append('no usage: %r' % out('DELETE'))
    if '1 moved to /TRASH.' not in out('DELETE A.TXT'): e.append('DELETE A.TXT: %r' % out('DELETE A.TXT'))
    if 'A        TXT' not in out('DIR /TRASH'): e.append('not in /TRASH: %r' % out('DIR /TRASH'))
    if 'first' in out('TYPE A.TXT'): e.append('still here: %r' % out('TYPE A.TXT'))
    report('DELETE: /TRASH made the first time, the file moved; EMPTY with no trash; the usage', e)

    e = []
    if 'second' not in out('TYPE /TRASH/A.TXT'): e.append('the newer one should be there: %r' % out('TYPE /TRASH/A.TXT'))
    if 'No file matches.' not in out('DELETE NOPE.TXT'): e.append(repr(out('DELETE NOPE.TXT')))
    o = out('DELETE *.BAK DOCS/D.TXT NOEXT')
    if '4 moved to /TRASH.' not in o: e.append(repr(o))
    if 'No file matches.' not in out('DELETE SUB'): e.append('a folder: %r' % out('DELETE SUB'))
    if 'in the trash already' not in out('DELETE A.TXT', 2): e.append('in /TRASH: %r' % out('DELETE A.TXT', 2))
    if 'keep me' not in out('TYPE DOCS/D.TXT'): e.append('MV back: %r' % out('TYPE DOCS/D.TXT'))
    report('DELETE: the older one goes on a clash; wildcards and several names; folders left alone; from /TRASH refused; MV gets one back', e)

    e = []
    if 'delete for good' not in t: e.append('no question')
    d = [p for p in parts if p.startswith('DIR /TRASH')]
    if len(d) < 3 or 'B        BAK' not in d[1]: e.append('N kept nothing: %r' % d[1:2])
    if 'The trash is empty now.' not in t: e.append('Y: no message')
    if len(d) >= 3 and 'BAK' in d[2]: e.append('after Y: %r' % d[2])
    if 'The trash is empty.' not in out('EMPTY', 3): e.append('a second EMPTY: %r' % out('EMPTY', 3))
    f = re.findall(r'(\d+) KB free', t)
    if len(f) < 2 or int(f[1]) < int(f[0]) - 1: e.append('the space: %r' % f)
    if 'No problems found.' not in out('FSCK'): e.append('FSCK: %r' % out('FSCK')[-300:])
    img = V.image(cf, n); rc, _ = P2.fsck_free(img)
    if rc: e.append('fsck_msdos: %d' % rc)
    report('EMPTY: asks; N keeps them, Y deletes them; the space back; FSCK and the Mac\'s fsck clean', e)
    print('\nTRASH: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
