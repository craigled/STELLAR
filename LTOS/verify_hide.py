# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""HIDE, and a hidden /AUTOEXEC.SH: DIR leaves it out, DIR -h shows it, TYPE and NANO reach it, it still runs at boot,
and it stays hidden through NANO's save and >>. HIDE -U brings it back; not there, a folder, no name: said so.

    python3 LTOS/verify_hide.py [-v]
"""
import os, re, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build


def attr(img, name):
    ps = struct.unpack_from('<I', img, 0x1C6)[0]; v = ps * 512
    res, nf, fsz, nroot = struct.unpack_from('<H', img, v + 14)[0], img[v + 16], struct.unpack_from('<H', img, v + 22)[0], struct.unpack_from('<H', img, v + 17)[0]
    root = (ps + res + nf * fsz) * 512
    for o in range(root, root + nroot * 32, 32):
        if bytes(img[o:o + 11]) == name: return img[o + 11]
    return None


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
        os.makedirs(os.path.join(m, 'DOCS'), exist_ok=True)
        open(os.path.join(m, 'AUTOEXEC.SH'), 'wb').write(b'ECHO startup ran\r\n')
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)
    def go(steps):
        b = V.Elf2K(cf, keys=b'', later=steps); b.rtc = P3.clock()
        s = b.boot_rom(3_000_000_000)
        t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
        return s, t
    A = b'AUTOEXECSH '
    c = lambda x: ('LTOS> ', x.encode() + b'\r')
    s, t = go([c('HIDE'), c('HIDE NOPE.TXT'), c('HIDE DOCS'), c('HIDE AUTOEXEC.SH'), c('DIR AUTO*'), c('DIR -h AUTO*'), c('TYPE AUTOEXEC.SH'), c('MON')])
    if '-v' in sys.argv: print(t[-900:])
    e = []
    parts = dict((p.split('\n', 1)[0], p.split('\n', 1)[1] if '\n' in p else '') for p in re.split(r'(?m)^LTOS> ', t))
    if s != 'stop': e.append('the end: %s' % s)
    if 'HIDE name' not in parts.get('HIDE', ''): e.append('usage: %r' % parts.get('HIDE'))
    if 'no file' not in parts.get('HIDE NOPE.TXT', ''): e.append('no file: %r' % parts.get('HIDE NOPE.TXT'))
    if 'hidden' in parts.get('HIDE DOCS', 'hidden'): e.append('a folder: %r' % parts.get('HIDE DOCS'))
    if 'is hidden' not in parts.get('HIDE AUTOEXEC.SH', ''): e.append('%r' % parts.get('HIDE AUTOEXEC.SH'))
    if 'AUTOEXEC' in parts.get('DIR AUTO*', 'AUTOEXEC'): e.append('DIR shows it: %r' % parts.get('DIR AUTO*'))
    if 'AUTOEXEC' not in parts.get('DIR -h AUTO*', ''): e.append('DIR -h: %r' % parts.get('DIR -h AUTO*'))
    if 'ECHO startup ran' not in parts.get('TYPE AUTOEXEC.SH', ''): e.append('TYPE: %r' % parts.get('TYPE AUTOEXEC.SH'))
    img2 = V.image(cf, n)
    if attr(img2, A) is None or not attr(img2, A) & 2: e.append('attribute: %r' % attr(img2, A))
    report('HIDE: usage, no such file, a folder refused; hidden: DIR leaves it out, DIR -h shows it, TYPE reads it', e)

    e = []
    s, t = go([('Type HELP', b''), c('MON')])
    if 'startup ran' not in t: e.append('not run at boot: %r' % t[-200:])
    report('Hidden, it still runs at boot', e)

    e = []
    s, t = go([c('ECHO ECHO appended >> /AUTOEXEC.SH'), c('MON')])
    a = attr(V.image(cf, n), A)
    if a is None or not a & 2: e.append('>> lost it: %r' % a)
    report('>> /AUTOEXEC.SH: stays hidden', e)

    e = []
    s, t = go([c('NANO /AUTOEXEC.SH'), ('NANO 1.1', b'ECHO edited\r\x0f'), ('Wrote ', b'\x18'), c('TYPE /AUTOEXEC.SH'), c('MON')])
    im = V.image(cf, n); a = attr(im, A)
    if '-v' in sys.argv: print(t[-500:])
    if s != 'stop': e.append('the end: %s: %r' % (s, t[-260:]))
    if a is None or not a & 2: e.append('the save lost it: attr %r' % a)
    if 'ECHO edited' not in t.split('LTOS> TYPE')[-1]: e.append('not saved: %r' % t[-260:])
    report('NANO: a change saved, and the file stays hidden', e)

    e = []
    s, t = go([c('HIDE -U AUTOEXEC.SH'), c('DIR AUTO*'), c('MON')])
    if 'AUTOEXEC' not in t.split('LTOS> DIR AUTO*')[-1]: e.append('still hidden: %r' % t[-200:])
    a = attr(V.image(cf, n), A)
    if a is None or a & 2: e.append('attribute: %r' % a)
    rc, _ = P2.fsck_free(V.image(cf, n))
    if rc: e.append('fsck_msdos: %d' % rc)
    report('HIDE -U: back in DIR; fsck clean', e)
    print('\nHIDE: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
