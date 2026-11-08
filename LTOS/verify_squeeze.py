# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""SQUEEZE in the simulator: a root folder of 120 files made and 108 deleted (with a hidden /AUTOEXEC.SH and a
folder), then SQUEEZE: every file still there with the same bytes (the Mac reads them), the entries in the same
order, packed, with no deleted one before the end; the hidden one still hidden; fsck clean; LTOS still works.
N leaves the card as it was; a second SQUEEZE has nothing to do. Then a copy of Craig's card, if it is here.

    python3 LTOS/verify_squeeze.py [card image]
"""
import os, re, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_xfer as X
import build


def root_entries(img):
    ps = struct.unpack_from('<I', img, 0x1C6)[0]; v = ps * 512
    res, nf, fsz, nroot = struct.unpack_from('<H', img, v + 14)[0], img[v + 16], struct.unpack_from('<H', img, v + 22)[0], struct.unpack_from('<H', img, v + 17)[0]
    r = (ps + res + nf * fsz) * 512
    return [bytes(img[r + i * 32:r + i * 32 + 32]) for i in range(nroot)]


def summary(img):
    es = root_entries(img); live, dead, end = [], 0, len(es)
    for i, e in enumerate(es):
        if e[0] == 0: end = i; break
        if e[0] == 0xE5: dead += 1
        else: live.append(e)
    return live, dead, end, es


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + str(x)[:200]) for x in e[:10]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed_full(mem, n)
    prg = build.prg('squeeze')
    def make(m):
        open(os.path.join(m, 'SQUEEZE.PRG'), 'wb').write(prg)
        for i in range(120): open(os.path.join(m, 'X%03d.TXT' % i), 'wb').write(b'file %d\r\n' % i * (1 + i % 7))
        open(os.path.join(m, 'AUTOEXEC.SH'), 'wb').write(b'ECHO startup ran\r\n')
        os.makedirs(os.path.join(m, 'DOCS'), exist_ok=True)
        open(os.path.join(m, 'DOCS', 'A.TXT'), 'wb').write(b'in a folder\r\n')
    img, _ = P2.mac(V.image(cf, n), make)
    def rm(m):
        for i in range(120):
            if i % 10: os.remove(os.path.join(m, 'X%03d.TXT' % i))
    img, _ = P2.mac(img, rm)
    img = bytearray(img)                                   # /AUTOEXEC.SH hidden
    live0, dead0, end0, es = summary(img)
    ps = struct.unpack_from('<I', img, 0x1C6)[0]; v = ps * 512
    r = (ps + struct.unpack_from('<H', img, v + 14)[0] + img[v + 16] * struct.unpack_from('<H', img, v + 22)[0]) * 512
    for i, e in enumerate(es):
        if e[:11] == b'AUTOEXECSH ': img[r + i * 32 + 11] |= 2
    img = bytes(img)
    live0, dead0, end0, _ = summary(img)
    files0 = X.files(img)

    def go(keys_after, image):
        P1.load_image(cf, image)
        b = V.Elf2K(cf, keys=b'', later=[('LTOS> ', b'SQUEEZE\r')] + keys_after + [('LTOS> ', b'MON\r')]); b.rtc = P3.clock()
        s = b.boot_rom(3_000_000_000)
        return s, b.text().replace('\r', ''), V.image(cf, n), b

    e = []
    s, t, img_n, b = go([('(Y/N) ', b'N')], img)
    if img_n != img: e.append('N changed the card')
    m = re.search(r'The root folder: (\d+) entries and (\d+) deleted ones, in (\d+) sectors', t)
    if not m or (int(m.group(1)), int(m.group(2)), int(m.group(3))) != (len(live0), dead0, (end0 + 16) // 16):
        e.append('the count: %r, the card: %d live, %d deleted, end at %d' % (m and m.group(0), len(live0), dead0, end0))
    report('SQUEEZE counts right (%d entries, %d deleted, %d sectors); N leaves the card byte for byte' % (len(live0), dead0, (end0 + 16) // 16), e)

    e = []
    s, t, img1, b = go([('(Y/N) ', b'Y'), ('LTOS> ', b'DIR X01*\r'), ('LTOS> ', b'TYPE X010.TXT\r'), ('LTOS> ', b'HELLO\r'),
                        ('LTOS> ', b'SQUEEZE\r'), ('LTOS> ', b'SQUEEZE X\r')], img)
    live1, dead1, end1, es1 = summary(img1)
    if s != 'stop': e.append('%s %r' % (s, t[-200:]))
    if live1 != live0: e.append('the entries kept are not the same, in the same order')
    if dead1 or end1 != len(live0): e.append('not packed: %d deleted, the end at %d' % (dead1, end1))
    if any(x != bytes(32) for x in es1[end1:]): e.append('something after the end')
    if 'Squeezed: %d entries, now in %d sectors' % (len(live0), (len(live0) + 15) // 16) not in t: e.append(t[-300:])
    if X.files(img1) != files0: e.append('the Mac reads different files')
    if P2.fsck_free(img1)[0]: e.append('fsck: %r' % (P2.fsck_free(img1),))
    if 'X010     TXT' not in t or 'file 10' not in t or 'Hello from HELLO' not in t: e.append('after it: %r' % t[-500:])
    if 'Nothing to squeeze.' not in t or 'HELP SQUEEZE' not in t: e.append('again / with a word: %r' % t[-300:])
    hid = [x for x in es1 if x[:11] == b'AUTOEXECSH ']
    if not hid or not hid[0][11] & 2: e.append('AUTOEXEC.SH not hidden now')
    if 'startup ran' not in t: e.append('AUTOEXEC.SH did not run at boot')
    report('Y: the same entries in the same order, packed into %d sectors, nothing after them; the Mac reads every file '
           'the same; hidden stays hidden; fsck clean; DIR, TYPE, programs work; again: nothing to do' % ((len(live0) + 15) // 16), e)

    real = sys.argv[1] if len(sys.argv) > 1 else None
    if real and os.path.exists(real):
        e = []
        im = open(real, 'rb').read(); nn = len(im) // 512
        cf2 = P1.CV.CF(sectors=nn); P1.load_image(cf2, im)
        _, e2, _ = P1.installed(mem, nn, b'U', cf=cf2)                     # (this kernel, for SQUEEZE.PRG)
        im = V.image(cf2, nn)
        im, _ = P2.mac(im, lambda m: open(os.path.join(m, 'SQUEEZE.PRG'), 'wb').write(prg))
        f0, (l0, d0, en0, _) = X.files(im), summary(im)
        P1.load_image(cf2, im)
        b = V.Elf2K(cf2, keys=b'', later=[('LTOS> ', b'SQUEEZE\r'), ('(Y/N) ', b'Y'), ('LTOS> ', b'MON\r')]); b.rtc = P3.clock()
        s = b.boot_rom(3_000_000_000)
        im2 = V.image(cf2, nn); l1, d1, en1, _ = summary(im2)
        if X.files(im2) != f0: e.append('files differ')
        if l1 != l0 or d1: e.append('entries')
        if P2.fsck_free(im2)[0]: e.append('fsck')
        report('A copy of the real card: %d entries and %d deleted ones in %d sectors -> %d sectors; every file the same; '
               'fsck clean' % (len(l0), d0, (en0 + 16) // 16, (en1 + 15) // 16), e)
    print('SQUEEZE: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
