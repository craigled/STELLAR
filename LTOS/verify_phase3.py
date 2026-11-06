# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 3 in the simulator (the real Elf2K ROM v120, the CF card model, the Mac's FAT code): writing files.

  * SAVE: a data file, a program (its 6-byte header), a 17 KB file over many clusters, replacing a file (Y) and
    keeping it (N), bad ranges; the Mac reads every file back byte for byte, fsck_msdos is clean, FREE agrees;
    the date and time come from the DS12887 (or the build date with no clock);
  * REN / MV: renamed; a name that is taken refused; a missing file; a long-named Mac file renamed - its long
    name goes, so the Mac shows the new short name and fsck sees no orphan pieces;
  * RM / DEL: one file; a wildcard that matches several (asked - Y and N); a long-named Mac file (its pieces
    go too); folders are left alone; the clusters are free again (FREE, fsck);
  * on 8 MB (1 sector a cluster) and 32 MB (2) cards.

    python3 LTOS/verify_phase3.py [-v]
"""
import os, sys, re, struct
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import opcode_sweep as S
import build


def clock(y=26, mo=10, d=16, h=14, mi=30, s=20, binary=False):
    """A DS12887: BCD, year from 2000 - or binary with the year from 1972, as the Elf2K BIOS keeps it."""
    if binary:
        regs = {0x0A: 0, 0x0B: 0x06, 0: s, 2: mi, 4: h, 7: d, 8: mo, 9: y + 28}
    else:
        bcd = lambda v: int('%d' % v, 16)
        regs = {0x0A: 0, 0x0B: 0x02, 0: bcd(s), 2: bcd(mi), 4: bcd(h), 7: bcd(d), 8: bcd(mo), 9: bcd(y)}
    return lambda r: regs.get(r, 0)


def entry(img, name11):
    spc, fat, fsz, nf, root, ents, data = P2.geometry(img)
    for k in range(ents):
        e = img[root + 32 * k:root + 32 * k + 32]
        if e[0] == 0: return None
        if e[:11] == name11: return e
    return None


def lfn_orphans(img):
    """Long-name pieces not followed by the short entry they belong to (what RM / REN must not leave)."""
    spc, fat, fsz, nf, root, ents, data = P2.geometry(img)
    bad, run = 0, 0
    for k in range(ents):
        e = img[root + 32 * k:root + 32 * k + 32]
        if e[0] == 0: break
        if e[0] == 0xE5: bad += run; run = 0; continue
        if e[11] == 0x0F: run += 1; continue
        run = 0
    return bad + run


def hexdump(data, name='HELLO.PRG'):
    """What HEX prints: 'NAME.EXT, n bytes', then 18 bytes a line - 'oooo  ' (6 digits + 1 space from 64 KB),
    'xx ' each (3 spaces for a missing one), a space (4-digit offsets only), the text (a dot for anything not printable)."""
    lines = ['%s, %d bytes' % (name, len(data))]
    for o in range(0, len(data), 18):
        c = data[o:o + 18]
        lines.append(('%06X ' % o if len(data) >= 65536 else '%04X  ' % o) + ''.join('%02X ' % x for x in c) +
                     '   ' * (18 - len(c)) + ('' if len(data) >= 65536 else ' ') + ''.join(chr(x) if 32 <= x < 127 else '.' for x in c))
    return lines


def session(cf, keys, rtc=None, cap=900_000_000, ram=None, later=()):
    b = V.Elf2K(cf, keys=keys, later=later); b.rtc = rtc
    if ram: ram(b.c.M)
    st = b.boot_rom(cap=cap)
    return b, st, b.text()


def out(t, cmd):
    return P2.session_out(t, cmd)


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    stl = S.image('37')

    for mb in (8, 32):
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        pat = bytes((i * 7 + 3) & 0xFF for i in range(0x4400))          # what $3000-$6BFF holds for BIG.BIN
        keys = (b'SAVE TEST.BIN 3000 30FF\r' b'SAVE PROG.PRG 3000 30FF 3010\r' b'SAVE BIG.BIN 3000 67FF\r'
                b'SAVE TEST.BIN 3000 300F\rY' b'SAVE TEST.BIN 3000 3001\rN' b'SAVE X.BIN 3000 2FFF\r'
                b'SAVE X.BIN 3000 6800\r' b'SAVE X.BIN 3000 30FF 3100\r' b'SAVE A*.BIN 3000 30FF\r'
                b'DIR\r' b'FREE\r' b'MON\r')
        def ram(M):
            M[0x3000:0x6C00] = pat[:0x3C00]
        b, st, t = session(cf, keys, rtc=clock(), ram=ram)
        img = V.image(cf, n); e = []
        got, files = P2.mac(img, lambda m: {f: open(os.path.join(m, f), 'rb').read() for f in os.listdir(m) if not f.startswith('.')})
        want = {'PROG.PRG': bytes([0x30, 0, 1, 0, 0x30, 0x10]) + pat[:256], 'BIG.BIN': pat[:0x3800], 'TEST.BIN': pat[:16]}
        for f, d in want.items():
            if files.get(f) != d: e.append('the Mac reads %s: %s' % (f, 'missing' if f not in files else '%d bytes, different' % len(files[f])))
        if 'X.BIN' in files: e.append('X.BIN was saved')
        rc, fr = P2.fsck_free(img)
        if rc != 0: e.append('fsck_msdos %d' % rc)
        m = re.search(r'\((\d+) of (\d+) clusters', out(t, 'FREE\r'))
        if not m or int(m.group(1)) != fr[1]: e.append('FREE %s, fsck %s' % (m and m.group(1), fr))
        for w, c in (('Saved TEST.BIN, 256 bytes.', 'SAVE TEST.BIN 3000 30FF\r'), ('Saved PROG.PRG, 262 bytes.', 'SAVE PROG.PRG 3000 30FF 3010\r'),
                     ('Saved BIG.BIN, 14336 bytes.', 'SAVE BIG.BIN 3000 67FF\r'), ('replace it? (Y/N) Y', 'SAVE TEST.BIN 3000 300F\r'),
                     ('replace it? (Y/N) N', 'SAVE TEST.BIN 3000 3001\r'), ('SAVE name start end [exec]', 'SAVE X.BIN 3000 2FFF\r'),
                     ('That reaches $6800-$7EFF', 'SAVE X.BIN 3000 6800\r'), ('SAVE name start end [exec]', 'SAVE X.BIN 3000 30FF 3100\r'),
                     ('That is not a file name', 'SAVE A*.BIN 3000 30FF\r')):
            if w not in out(t, c): e.append('%r: %r' % (c, out(t, c)[:120]))
        en = entry(img, b'TEST    BIN')
        tm, dt = struct.unpack('<HH', en[22:26]) if en else (0, 0)
        if (dt >> 9, (dt >> 5) & 15, dt & 31, tm >> 11, (tm >> 5) & 63, (tm & 31) * 2) != (46, 10, 16, 14, 30, 20):
            e.append('TEST.BIN date/time %04X %04X' % (dt, tm))
        if not re.search(r'TEST     BIN +16  2026-10-16 14:30', out(t, 'DIR\r')): e.append('DIR: %r' % out(t, 'DIR\r'))
        if st != 'stop': e.append('MON: %s' % st)
        if '-v' in sys.argv and mb == 8: print(t)
        report('%d MB: SAVE (data, program header, 17 KB over many clusters, replace Y / N, bad ranges and names); '
               'the Mac reads them exactly, fsck clean, FREE = fsck, the clock\'s date' % mb, e)

        # REN / RM, with the Mac's long names
        img, _ = P2.mac(img, lambda m: [open(os.path.join(m, 'Long name one.txt'), 'wb').write(b'one\n'),
                                        open(os.path.join(m, 'Long name two.txt'), 'wb').write(b'two\n' * 300),
                                        os.mkdir(os.path.join(m, 'Docs'))])
        P1.load_image(cf, img)
        shorts = P2.root_names(img)
        l1 = [x for x in shorts if x.startswith('LONGN') and x.endswith('TXT')]
        keys = (b'REN TEST.BIN T2.BIN\r' b'MV T2.BIN PROG.PRG\r' b'REN NOPE.BIN N2.BIN\r' b'REN ' + l1[0].encode() + b' ONE.TXT\r'
                b'RM BIG.BIN\r' b'RM *.TXT\rN' b'DEL ' + l1[1].encode() + b'\r' b'RM DOCS\r' b'RM NOPE.*\r' b'RM *.*\rY' b'DIR\r' b'MON\r')
        b, st, t = session(cf, keys, rtc=clock())
        img = V.image(cf, n); e = []
        got, names = P2.mac(img, lambda m: sorted(f for f in os.listdir(m) if not f.startswith('.')))
        if names != ['Docs']: e.append('the Mac sees %s' % names)
        rc, fr = P2.fsck_free(img)
        if rc != 0: e.append('fsck_msdos %d' % rc)
        if lfn_orphans(img): e.append('%d long-name pieces left without their file' % lfn_orphans(img))
        for w, c in (('Renamed.', 'REN TEST.BIN T2.BIN\r'), ('There is already a PROG.PRG', 'MV T2.BIN PROG.PRG\r'),
                     ('There is no file NOPE.BIN', 'REN NOPE.BIN N2.BIN\r'), ('Renamed.', 'REN ' + l1[0] + ' ONE.TXT\r'),
                     ('Deleted.', 'RM BIG.BIN\r'), ('3 files match - delete them all? (Y/N) N', 'RM *.TXT\r'),
                     ('Deleted.', 'DEL ' + l1[1] + '\r'), ('No file matches.', 'RM DOCS\r'), ('No file matches.', 'RM NOPE.*\r'),
                     ('%d files match - delete them all? (Y/N) Y' % (len(build.samples()) + 4), 'RM *.*\r')):
            if w not in out(t, c): e.append('%r: %r' % (c, out(t, c)[:150]))
        if '-v' in sys.argv and mb == 8: print(t)
        report('%d MB: REN / MV (taken name, missing file, a Mac long name), RM / DEL (one, wildcards asked Y / N, a '
               'long name, a folder left alone); the Mac sees only the folder, fsck clean, no orphan long-name '
               'pieces, DIR empty after RM *.* (FREE.PRG and the rest go too)' % mb, e)

    # 3b: the programs on the card - COPY, HEX, RECV; typing a name runs NAME.PRG
    for mb in (8, 32):
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        files = dict((nm[:8].decode().strip() + '.' + nm[8:].decode().strip(), d) for nm, d in build.samples())
        text = ''.join('Line %02d sent from the terminal by RECV - the quick brown fox.\r\n' % i for i in range(30))
        hx = build.intel_hex({0x3000 + i: b for i, b in enumerate(files['HELLO.PRG'][6:])})
        hl = hx.split('\n'); hl[1] = hl[1][:-2] + '%02X' % ((int(hl[1][-2:], 16) + 1) & 0xFF); bad = '\n'.join(hl)  # a checksum wrong
        hexd = hexdump(files['HELLO.PRG'])
        big = bytes((i * 13 + 5) & 0xFF for i in range(17000))
        keys = b'COPY HELP.TXT H2.TXT\r' b'HEX HELLO.PRG\r' + b' ' * (len(hexd) // 22) + b'RECV T.TXT\r'
        go = 'Ctrl-C stops.'                                  # RECV drops what comes after a file: send each
        later = [(go, text.encode() + b'.\r\n'),               #  file when it asks, the next line at the prompt
                 ('LTOS> ', b'RECV H2.PRG\r'), (go, hx.replace('\n', '\r\n').encode()),
                 ('LTOS> ', b'RECV H3.PRG\r'), (go, bad.replace('\n', '\r\n').encode()),
                 ('LTOS> ', b'RECV Z.TXT\r'), (go, b'abc\x03'),
                 ('LTOS> ', b'RECV TYPED.TXT\r'), (go, b'typed\rat the terminal\r.\r'),
                 ('LTOS> ', b'RUN H2.PRG hi\r' b'hello there\r' b'copy\r' b'FOO\r' b'RECV A*B\r'
                  b'SAVE BIG.BIN 3000 6E27\r' b'SAVE BIG.BIN 3000 66AF\r' b'COPY BIG.BIN BIG2.BIN\r' b'MON\r')]
        def ram(M): M[0x3000:0x3000 + 14000] = big[:14000]       # (COPY holds about 14.3 KB)
        b, st, t = session(cf, keys, rtc=clock(), ram=ram, cap=600_000_000, later=later)
        img = V.image(cf, n); e = []
        got, fl = P2.mac(img, lambda m: {f: open(os.path.join(m, f), 'rb').read() for f in os.listdir(m) if not f.startswith('.')})
        want = {'H2.TXT': files['HELP.TXT'], 'T.TXT': text.encode(), 'H2.PRG': files['HELLO.PRG'],
                'TYPED.TXT': b'typed\r\nat the terminal\r\n'}             # (Enter = CR: saved as CR LF)
        if fl.get('BIG2.BIN') != fl.get('BIG.BIN') or len(fl.get('BIG2.BIN', b'')) != 14000: e.append('BIG2.BIN is not BIG.BIN')
        for f, d in want.items():
            if fl.get(f) != d: e.append('the Mac reads %s: %s' % (f, 'missing' if f not in fl else '%d bytes, different' % len(fl[f])))
        for f in ('H3.PRG', 'Z.TXT', 'A*B'):
            if f in fl: e.append('%s was saved' % f)
        rc, fr = P2.fsck_free(img)
        if rc != 0: e.append('fsck_msdos %d' % rc)
        h = out(t, 'HEX HELLO.PRG\r')
        h = re.sub(r'-- more: a key goes on, Q stops --.\r {35}\r', '', h, flags=re.S).lstrip('\r\n')
        if h != ''.join(x + '\r\n' for x in hexd): e.append('HEX HELLO.PRG differs: %r' % h[:200])
        for w, c in (('Saved H2.TXT, %d bytes.' % len(files['HELP.TXT']), 'COPY HELP.TXT H2.TXT\r'),
                     ('Received %d bytes.' % len(text), 'RECV T.TXT\r'), ('Saved H2.PRG, %d bytes.' % len(files['HELLO.PRG']), 'RECV H2.PRG\r'),
                     ('1 bad checksums - nothing saved.', 'RECV H3.PRG\r'), ('Stopped - nothing saved.', 'RECV Z.TXT\r'),
                     ('You said: "hi"', 'RUN H2.PRG hi\r'), ('Hello from HELLO.PRG', 'hello there\r'),
                     ('COPY from to', 'copy\r'), ('Unknown command: FOO', 'FOO\r'), ('Not a file name - nothing saved.', 'RECV A*B\r'),
                     ('That reaches $6800-$7EFF', 'SAVE BIG.BIN 3000 6E27\r'), ('Saved BIG2.BIN, 14000 bytes.', 'COPY BIG.BIN BIG2.BIN\r')):
            if w not in out(t, c): e.append('%r: %r' % (c, out(t, c)[:160]))
        if st != 'stop': e.append('MON: %s' % st)
        if '-v' in sys.argv and mb == 8: print(t[:6000])
        report('%d MB: COPY (text, 14 KB), HEX (= a reference dump, paged), RECV (text to a "." line; Intel HEX to a '
               '.PRG = HELLO.PRG exactly; a bad checksum and Ctrl-C save nothing), NAME runs NAME.PRG, unknown '
               'words; the Mac reads them, fsck clean' % mb, e)

    # the Elf2K BIOS's clock: binary, the year from 1972 (Craig's: 54 = 2026)
    cf, e2k, st = P1.installed_full(mem, 16384)
    b, st, t = session(cf, b'SAVE B.BIN 2800 28FF\rDIR\rMON\r', rtc=clock(h=19, mi=16, binary=True))
    e = [] if re.search(r'B        BIN +256  2026-10-16 19:16', out(t, 'DIR\r')) else ['DIR: %r' % out(t, 'DIR\r')]
    report('a binary clock with the year from 1972 (as the Elf2K BIOS keeps it): the file is dated 2026', e)

    # no clock: the build's date
    cf, e2k, st = P1.installed_full(mem, 16384)
    b, st, t = session(cf, b'SAVE N.BIN 2800 28FF\rMON\r', rtc=lambda r: 0xFF)
    en = entry(V.image(cf, 16384), b'N       BIN'); e = []
    tm, dt = build.fat_now()
    if not en or struct.unpack('<H', en[24:26])[0] != dt: e.append('no clock: %r' % (en and en[22:26].hex()))
    report('no clock: a saved file gets the date LTOS was built', e)

    print('\nLTOS phase 3:', 'ALL PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
