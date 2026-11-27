# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""A card as big as Craig's 512 MB Transcend (996,912 sectors, 62,268 clusters of 8 KB): ATTACH must put a document
where Lite-Writer's 16-bit sector numbers reach (below sector 65,536) - its search for a free FAT sector starts at
the FAT's end, which on this card is near sector 1,000,000. NANO NEW.TXT: written, read back by TYPE; its first
sector is below 65,536 (read from the card); LTOS's FSCK finds no problems.

    python3 LTOS/verify_bigcard.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase3 as P3
import build

N = 996912


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    cf, e2k, st = P1.installed_full(mem, N)
    clean = lambda t: re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', ' ', t.replace('\r', ''))
    c = lambda x: ('LTOS> ', x.encode() + b'\r')
    b = V.Elf2K(cf, keys=b'', later=[c('NANO NEW.TXT'), ('NANO 1.1', b'Hello from a big card\r\x0f'), ('Wrote ', b'\x18'),
                                     c('TYPE NEW.TXT'), c('FSCK'), c('MON')]); b.rtc = P3.clock()
    s = b.boot_rom(12_000_000_000)
    t = clean(b.text())
    if v: print(t[-1500:])
    e = []
    if s != 'stop': e.append('the end: %s %r' % (s, t[-400:]))
    if 'too far' in t or 'past sector' in t: e.append('ATTACH refused: %r' % t[-300:])
    if 'Hello from a big card' not in t.split('LTOS> TYPE NEW.TXT')[-1]: e.append('TYPE NEW.TXT: %r' % t[-500:])
    def sec(i): return bytes(cf.disk.get(i, bytes(512)))
    le = lambda x, o, n: int.from_bytes(x[o:o + n], 'little')
    ps = le(sec(0), 0x1C6, 4); bs = sec(ps)
    spc, res, nf, nroot, fsz = bs[13], le(bs, 14, 2), bs[16], le(bs, 17, 2), le(bs, 22, 2)
    root = ps + res + nf * fsz; data = root + nroot * 32 // 512
    d0 = None
    for k in range(nroot * 32 // 512):
        x = sec(root + k)
        for o in range(0, 512, 32):
            if x[o:o + 11] == b'NEW     TXT': d0 = data + (le(x, o + 26, 2) - 2) * spc
    if d0 is None: e.append('NEW.TXT not in the root')
    elif d0 + 128 > 65536: e.append('NEW.TXT at sector %d: past Lite-Writer\'s reach' % d0)
    print('    (%d sectors a cluster, the FAT %d sectors; NEW.TXT at sector %s)' % (spc, fsz, d0))
    if 'No problems found' not in t.split('LTOS> FSCK')[-1]: e.append('FSCK: %r' % t.split('LTOS> FSCK')[-1][-300:])
    report('486 MB card: NANO NEW.TXT written below sector 65,536 and read back; FSCK clean', e)
    print('\nBig card: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
