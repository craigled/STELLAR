# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""DISKINFO in the simulator: the card's IDENTIFY answer, the partition, the volume, the space and the contents
agree with the card image and with FSCK and FREE; a cluster marked bad in the FAT is counted (and not as free or
used); DISKINFO -Q gives the card and volume alone; DISKINFO -S starts reading every sector and a key stops it;
DISKINFO -X: the usage.

    python3 LTOS/verify_diskinfo.py [-v]
"""
import os, re, struct, sys
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
        os.makedirs(os.path.join(m, 'A', 'B'), exist_ok=True)
        open(os.path.join(m, 'A', 'ONE.TXT'), 'wb').write(b'x' * 1000)
        open(os.path.join(m, 'A', 'B', 'TWO.TXT'), 'wb').write(b'y' * 3000)
    img, _ = P2.mac(V.image(cf, n), put)
    img = bytearray(img)
    ps = struct.unpack_from('<I', img, 0x1C6)[0]                      # the last cluster marked bad, in both FATs
    v = ps * 512
    spc, res, nf, nroot, tot16, fsz = img[v + 13], struct.unpack_from('<H', img, v + 14)[0], img[v + 16], \
        struct.unpack_from('<H', img, v + 17)[0], struct.unpack_from('<H', img, v + 19)[0], struct.unpack_from('<H', img, v + 22)[0]
    tot = tot16 or struct.unpack_from('<I', img, v + 32)[0]
    ncl = (tot - res - nf * fsz - nroot * 32 // 512) // spc
    last = ncl + 1
    for k in range(nf):
        a = v + (res + k * fsz) * 512 + 2 * last
        assert img[a:a + 2] == b'\0\0', 'the last cluster is in use'
        img[a:a + 2] = b'\xf7\xff'
    P1.load_image(cf, bytes(img))
    later = [('LTOS> ', b'DISKINFO\r'), ('LTOS> ', b'FSCK\r'), ('LTOS> ', b'FREE\r'), ('LTOS> ', b'DISKINFO -Q\r'),
             ('LTOS> ', b'DISKINFO -S\r'), ('a key stops it) ', b'x'), ('LTOS> ', b'DISKINFO -X\r'), ('LTOS> ', b'MON\r')]
    b = V.Elf2K(cf, keys=b'', later=later); b.rtc = P3.clock()
    st = b.boot_rom(3_000_000_000)
    t = b.text().replace('\r', '')
    dots = re.findall(r'\n\.{5,}\n', t)                                # the progress dots: seen, then out of the way
    t = re.sub(r'(?<=\n)\.+\n', '', t)
    if '-v' in sys.argv: print(t[t.find('DISKINFO'):])
    d = t[t.find('LTOS> DISKINFO\n'):t.find('LTOS> FSCK')]
    def num(label):
        m = re.search(r'\n  ' + label + r':\s+(.*)', d)
        return m.group(1).strip() if m else ''

    e = []
    if st != 'stop': e.append('the end: %s' % st)
    if num('Model') != 'SanDisk SDCFB-128': e.append('Model %r' % num('Model'))
    if num('Kind') != 'CompactFlash, LBA addressing': e.append('Kind %r' % num('Kind'))
    if num('Size') != '8 MB = 16384 sectors of 512 bytes': e.append('Size %r' % num('Size'))
    if 'Geometry' in d: e.append('a Geometry line with none given')
    if num('Table') != "MBR; the first partition's type is $%02X (FAT16)" % img[0x1C2]: e.append('Table %r' % num('Table'))
    if num('Starts at') != 'sector %d' % ps: e.append('Starts at %r' % num('Starts at'))
    report('DISKINFO: the card (model, kind, size; no geometry line when it gives none) and the partition', e)

    e = []
    oem = img[v + 3:v + 11].decode().rstrip()
    if num('Format') != 'FAT16, formatted by "%s"' % oem: e.append('Format %r' % num('Format'))
    if num('Label') != 'LTOS': e.append('Label %r' % num('Label'))
    ser = struct.unpack_from('<I', img, v + 39)[0]
    if num('Serial number').count('-') and num('Serial number') != '%04X-%04X' % (ser >> 16, ser & 0xFFFF):
        e.append('volume serial %r' % num('Serial number'))
    if num('Sectors') != '%d in the volume (%d reserved), media byte $%02X' % (tot, res, img[v + 21]): e.append('Sectors %r' % num('Sectors'))
    if num('Cluster size') != '%d sectors = %d bytes' % (spc, spc * 512): e.append('Cluster size %r' % num('Cluster size'))
    if num('FATs') != '%d copies of %d sectors' % (nf, fsz): e.append('FATs %r' % num('FATs'))
    if num('Root folder') != 'room for %d entries' % nroot: e.append('Root folder %r' % num('Root folder'))
    report('DISKINFO: the volume (format, who formatted it, label, serial, sectors, cluster size, FATs, root)', e)

    e = []
    fr = re.search(r'\((\d+) of (\d+) clusters', t)
    fs = re.search(r'Checked: (\d+) files, (\d+) folders', t)
    free, allc = (int(fr.group(1)), int(fr.group(2))) if fr else (-1, -1)
    if allc != ncl: e.append('FREE says %d clusters, the image %d' % (allc, ncl))
    want = '%d in all, %d free, %d used, 1 marked bad' % (ncl, free, ncl - free - 1)
    if num('Clusters') != want: e.append('Clusters %r, not %r' % (num('Clusters'), want))
    cb = spc * 512
    want = '%d in all, %d free, %d used' % (ncl * cb, free * cb, (ncl - free - 1) * cb)
    if num('Bytes') != want: e.append('Bytes %r, not %r' % (num('Bytes'), want))
    if not fs or not num('Files').startswith(fs.group(1) + ', holding '): e.append('Files %r (FSCK: %s)' % (num('Files'), fs and fs.group(1)))
    if not fs or num('Folders') != '%s (and the root)' % fs.group(2): e.append('Folders %r' % num('Folders'))
    if num('In the FAT') != '1 clusters marked bad': e.append('In the FAT %r' % num('In the FAT'))
    report('DISKINFO: the space (clusters and bytes, a cluster marked bad in the FAT counted apart) and the '
           'files and folders in every folder agree with FREE and FSCK', e)

    e = []
    s = t[t.find('LTOS> DISKINFO -S'):t.find('LTOS> DISKINFO -X')]
    if 'Stopped at sector ' not in s or 'Unreadable:    0 sectors' not in s: e.append('-S: %r' % s[-300:])
    if 'Usage: DISKINFO [-Q | -S]' not in t: e.append('no usage for -X')
    q = t[t.find('LTOS> DISKINFO -Q'):t.find('LTOS> DISKINFO -S')]
    full = d[d.find('Card'):d.find('Space\n')]
    if q[q.find('Card'):].replace('LTOS> ', '') != full: e.append('-Q is not the full report up to Space: %r' % q[-300:])
    if not dots: e.append('no progress dots')
    report('DISKINFO -Q: the card, partition and volume exactly as in the full report, nothing after; '
           'DISKINFO -S reads every sector until a key; -X: the usage', e)
    print('\nDISKINFO: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
