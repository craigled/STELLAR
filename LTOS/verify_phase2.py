# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 2 in the simulator (the real Elf2K ROM v120, the CF card model, the Mac's FAT code): reading files.

  * F on 8 MB and 32 MB cards: STELLAR.BIN, HELLO.PRG and README.TXT on the card - fsck_msdos clean, and
    the Mac reads all three back byte for byte;
  * at the LTOS> prompt: DIR (all, *.TXT, S*), TYPE README.TXT (paged), FREE (= the Mac's own count),
    RUN HELLO.PRG with and without arguments, LOAD HELLO.PRG, LOAD STELLAR.BIN (not a program), LOAD
    STELLAR.BIN 2000 (memory = the firmware), sizes that do not fit, missing files, bad names, wildcards
    where they do not belong; MON puts STELLAR back;
  * files the Mac wrote: a 20 KB text file over many clusters, a long name, a folder, a FRAGMENTED file -
    DIR lists them (and not the Mac's ._ / .fseventsd), TYPE prints every one exactly, FREE agrees;
  * F refuses when RAM holds LTOS instead of STELLAR; U still keeps the files.

    python3 LTOS/verify_phase2.py [-v]
"""
import os, sys, re, subprocess, tempfile, shutil, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import cftest_verify as CV
import opcode_sweep as S
import build


def mac(img, actions):
    """Mount the image's partition read-write on the Mac, run actions(mountpoint). -> the new image bytes."""
    d = tempfile.mkdtemp(); p = os.path.join(d, 'card.img'); open(p, 'wb').write(img)
    r = subprocess.run(['hdiutil', 'attach', '-imagekey', 'diskimage-class=CRawDiskImage', '-nomount', p],
                       capture_output=True, text=True)
    disk = r.stdout.split()[0]; mnt = os.path.join(d, 'mnt'); os.mkdir(mnt)
    try:
        subprocess.run(['diskutil', 'mount', '-mountPoint', mnt, disk + 's1'], capture_output=True, text=True)
        assert os.path.ismount(mnt)
        out = actions(mnt)
        subprocess.run(['sync'])
        for k in range(10):                                     # a busy volume (Spotlight) refuses at first;
            if subprocess.run(['diskutil', 'unmount', mnt], capture_output=True).returncode == 0: break
            time.sleep(1)                                       #  a forced detach would lose the writes
        else:
            subprocess.run(['diskutil', 'unmount', 'force', mnt], capture_output=True)
    finally:
        subprocess.run(['hdiutil', 'detach', disk, '-force'], capture_output=True)
    data = open(p, 'rb').read(); shutil.rmtree(d, ignore_errors=True)
    return data, out


def fsck_free(img):
    d = tempfile.mkdtemp(); p = os.path.join(d, 'card.img'); open(p, 'wb').write(img)
    r = subprocess.run(['hdiutil', 'attach', '-imagekey', 'diskimage-class=CRawDiskImage', '-nomount', p],
                       capture_output=True, text=True)
    disk = r.stdout.split()[0]
    try:
        f = subprocess.run(['fsck_msdos', '-n', disk + 's1'], capture_output=True, text=True, errors='replace')
        m = re.search(r'(\d+) files?, (\d+) KiB free \((\d+) clusters\)', f.stdout + f.stderr)
        return f.returncode, (int(m.group(2)), int(m.group(3))) if m else None
    finally:
        subprocess.run(['hdiutil', 'detach', disk, '-force'], capture_output=True)
        shutil.rmtree(d, ignore_errors=True)


def geometry(img):
    import struct
    vbr = img[64 * 512:65 * 512]
    spc, res, nf, ents, fsz = vbr[13], struct.unpack('<H', vbr[14:16])[0], vbr[16], struct.unpack('<H', vbr[17:19])[0], struct.unpack('<H', vbr[22:24])[0]
    fat = (64 + res) * 512; root = fat + nf * fsz * 512; data = root + ents * 32
    return spc, fat, fsz, nf, root, ents, data


def root_names(img):
    spc, fat, fsz, nf, root, ents, data = geometry(img)
    out = []
    for k in range(ents):
        e = img[root + 32 * k:root + 32 * k + 32]
        if e[0] == 0: break
        if e[0] == 0xE5 or e[11] == 0x0F or e[11] & 0x0E: continue
        n, x = e[:8].decode().strip(), e[8:11].decode().strip()
        out.append(n + ('.' + x if x else ''))
    return out


def fragment(img, name):
    """Move the second cluster of the file `name` (11 bytes) to the last free cluster, chain it there and
    back, in every FAT - a valid file in two (or more) pieces."""
    import struct
    img = bytearray(img)
    spc, fat, fsz, nf, root, ents, data = geometry(img)
    for k in range(ents):
        o = root + 32 * k
        if img[o:o + 11] == name: break
    c1 = struct.unpack('<H', img[o + 26:o + 28])[0]
    get = lambda c: struct.unpack('<H', img[fat + 2 * c:fat + 2 * c + 2])[0]
    def put(c, v):
        for f in range(nf): img[fat + f * fsz * 512 + 2 * c:fat + f * fsz * 512 + 2 * c + 2] = struct.pack('<H', v)
    c2 = get(c1); c3 = get(c2)
    ncl = (fsz * 512) // 2
    free = [c for c in range(ncl - 1, 2, -1) if get(c) == 0 and data + (c - 2) * spc * 512 + spc * 512 <= len(img)][0]
    src, dst = data + (c2 - 2) * spc * 512, data + (free - 2) * spc * 512
    img[dst:dst + spc * 512] = img[src:src + spc * 512]
    put(c1, free); put(free, c3); put(c2, 0)
    return bytes(img)


def typed(text):
    """What TYPE should print for these bytes: CR dropped, LF -> CRLF, other control characters '.', a pause
    every 22 lines (its prompt and the line that wipes it are left out of the comparison)."""
    out = []
    for ch in text:
        if ch == '\r': continue
        if ch == '\n': out.append('\r\n'); continue
        out.append(ch if ch >= ' ' or ch == '\t' else '.')
    return ''.join(out)


def session_out(t, cmd):
    """The output of one command in a session transcript, the pager's prompts taken out."""
    i = t.index('LTOS> ' + cmd)
    j = t.index('LTOS> ', i + 6)
    body = t[i + len('LTOS> ' + cmd):j]
    return re.sub(r'-- more: a key goes on, Q stops --.\r {35}\r', '', body, flags=re.S)


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    files = dict((n[:8].decode().strip() + '.' + n[8:].decode().strip(), d) for n, d in build.samples())
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    stl = S.image('37')[0:0x2F00]

    for mb in (8, 32):
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        t = e2k.text(); e = []
        inst = [n[:8].decode().strip() + '.' + n[8:].decode().strip() for n in build.build.installed_files]
        for w in ['STELLAR    BIN  12032 bytes', 'The card is ready. Type BOOT.'] + ['%s  %d bytes' % (f.split('.')[0], len(files[f])) for f in inst]:
            if w.replace('    ', ' ').split()[0] not in t: e.append('install: %r' % w)
        if 'The card is ready. Type BOOT.' not in t: e.append('install: %r' % t[-300:])
        img = V.image(cf, n)
        got, out = mac(img, lambda m: {f: open(os.path.join(m, f), 'rb').read() for f in os.listdir(m) if not f.startswith('.')})
        for f, d in list(files.items()) + [('STELLAR.BIN', stl)]:
            if out.get(f) != d: e.append('the Mac reads %s %s' % (f, 'differently' if f in out else ': missing'))
        rc, fr = fsck_free(img)
        if rc != 0: e.append('fsck_msdos %d' % rc)
        report('%d MB: F writes STELLAR.BIN and the files for the card - fsck clean, the Mac reads them all byte for byte' % mb, e)

        readme_lines = files['HELP.TXT'].count(b'\n')
        keys = (b'DIR\r' b'dir *.txt\r' b'DIR S*\r' b'TYPE HELP.TXT\r' + b' ' * (readme_lines // 22) +
                b'FREE\r' b'RUN HELLO.PRG\r' b'run hello.prg hi there\r' b'LOAD HELLO.PRG\r' b'LOAD STELLAR.BIN\r'
                b'LOAD STELLAR.BIN 3000\r' b'LOAD STELLAR.BIN 6000\r' b'TYPE NOPE.TXT\r' b'TYPE A:B\r'
                b'TYPE *.TXT\r' b'DIR Q*\r' b'MON\r')
        b = V.Elf2K(cf, keys=keys); st = b.boot_rom(cap=400_000_000); t = b.text(); e = []
        d_all = session_out(t, 'DIR\r')
        for f in (r'STELLAR  BIN +12032  \d{4}-\d\d-\d\d \d\d:\d\d', r'HELLO    PRG +%d ' % len(files['HELLO.PRG']),
                  r'HELP     TXT +%d ' % len(files['HELP.TXT']), r'RECV     PRG +%d ' % len(files['RECV.PRG'])):
            if not re.search(f, d_all): e.append('DIR: %r missing' % f)
        if '%4d files, %d bytes' % (len(files) + 1, 12032 + sum(len(x) for x in files.values())) not in d_all: e.append('DIR total: %r' % d_all[-60:])
        d_txt = session_out(t, 'dir *.txt\r')
        if 'HELP     TXT' not in d_txt or 'HELLO' in d_txt or '   1 files,' not in d_txt: e.append('DIR *.TXT: %r' % d_txt)
        d_s = session_out(t, 'DIR S*\r')
        if 'STELLAR' not in d_s or 'HELP' in d_s: e.append('DIR S*: %r' % d_s)
        ty = session_out(t, 'TYPE HELP.TXT\r')
        if ty.lstrip('\r\n') != typed(files['HELP.TXT'].decode()): e.append('TYPE HELP.TXT differs: %r' % ty[:120])
        fr_out = session_out(t, 'FREE\r')
        m = re.search(r'(\d+) KB free of (\d+) KB \((\d+) of (\d+) clusters of (\d+) bytes\)', fr_out)
        if not m or int(m.group(3)) != fr[1]: e.append('FREE: %r, fsck says %s free clusters' % (fr_out, fr))
        if 'Hello from HELLO.PRG' not in session_out(t, 'RUN HELLO.PRG\r') or 'Try: HELLO hi there' not in t: e.append('RUN HELLO.PRG')
        if 'You said: "hi there"' not in session_out(t, 'run hello.prg hi there\r'): e.append('RUN with arguments')
        lp = session_out(t, 'LOAD HELLO.PRG\r')
        if 'Loaded HELLO.PRG, %d bytes at $3000-$%04X' % (len(files['HELLO.PRG']) - 6, 0x3000 + len(files['HELLO.PRG']) - 7) not in lp or 'It starts at $3000' not in lp:
            e.append('LOAD HELLO.PRG: %r' % lp)
        if 'STELLAR.BIN is not a program' not in session_out(t, 'LOAD STELLAR.BIN\r'): e.append('LOAD STELLAR.BIN (no address)')
        if 'Loaded STELLAR.BIN, 12032 bytes at $3000-$5EFF' not in session_out(t, 'LOAD STELLAR.BIN 3000\r'): e.append('LOAD STELLAR.BIN 3000')
        if 'It does not fit in $3000-$6BFF.' not in session_out(t, 'LOAD STELLAR.BIN 6000\r'): e.append('LOAD STELLAR.BIN 6000')
        if 'There is no file NOPE.TXT' not in session_out(t, 'TYPE NOPE.TXT\r'): e.append('TYPE NOPE.TXT')
        if 'That is not a file name' not in session_out(t, 'TYPE A:B\r'): e.append('TYPE A:B')
        if 'That is not a file name' not in session_out(t, 'TYPE *.TXT\r'): e.append('TYPE *.TXT')
        if '   0 files, 0 bytes' not in session_out(t, 'DIR Q*\r'): e.append('DIR Q*')
        if 'STELLAR is as it was before LTOS.' not in t or st != 'stop': e.append('MON: %s' % st)
        if '-v' in sys.argv and mb == 8: print(t)
        report('%d MB: DIR (all, *.TXT, S*), TYPE (paged, exact), FREE = fsck, RUN (with arguments), LOAD (program, '
               'raw, too big, not a program), missing and bad names, MON' % mb, e)

    # the Mac's own files: many clusters, a long name, a folder, a fragmented file
    n = 32 * 2048
    cf, e2k, st = P1.installed_full(mem, n)
    big = ''.join('Line %04d of BIG.TXT, written on the Mac: the quick brown fox jumps over the lazy dog.\n' % i
                  for i in range(240)).encode()
    frag = ''.join('FRAG %03d - this file had to fill a gap and go on past it.\n' % i for i in range(140)).encode()
    def put(m):
        open(os.path.join(m, 'BIG.TXT'), 'wb').write(big)
        open(os.path.join(m, 'GAP1.TXT'), 'wb').write(b'g' * 3000)
        open(os.path.join(m, 'KEEP.TXT'), 'wb').write(b'k' * 3000)
        os.remove(os.path.join(m, 'GAP1.TXT'))
        open(os.path.join(m, 'FRAG.TXT'), 'wb').write(frag)
        open(os.path.join(m, 'A long file name.txt'), 'wb').write(b'long names show their short form\n')
        os.mkdir(os.path.join(m, 'Docs'))
        open(os.path.join(m, 'Docs', 'inside.txt'), 'wb').write(b'in a folder\n')
        return sorted(os.listdir(m))
    img, listing = mac(V.image(cf, n), put)
    img = fragment(img, b'FRAG    TXT')
    P1.load_image(cf, img)
    rc, fr = fsck_free(img)
    shorts = root_names(img)
    lname = ([x for x in shorts if x.startswith('ALONG')] or [print('short names:', shorts, listing)])[0]
    # is FRAG.TXT really in pieces?  follow its chain in the image
    import struct
    vbr = img[64 * 512:65 * 512]; spc = vbr[13]; res = struct.unpack('<H', vbr[14:16])[0]; fsz = struct.unpack('<H', vbr[22:24])[0]
    fat = img[(64 + res) * 512:(64 + res + fsz) * 512]; root = (64 + res + 2 * fsz) * 512
    pieces = None
    for k in range(512):
        ent = img[root + 32 * k:root + 32 * k + 32]
        if ent[:11] == b'FRAG    TXT':
            c = struct.unpack('<H', ent[26:28])[0]; chain = [c]
            while True:
                c = struct.unpack('<H', fat[2 * c:2 * c + 2])[0]
                if c >= 0xFFF8: break
                chain.append(c)
            pieces = sum(1 for a, b2 in zip(chain, chain[1:]) if b2 != a + 1) + 1
    lines = big.count(b'\n'); flines = frag.count(b'\n')
    keys = (b'DIR\r' b'TYPE BIG.TXT\r' + b' ' * (lines // 22) + b'TYPE FRAG.TXT\r' + b' ' * (flines // 22) +
            b'TYPE ' + lname.encode() + b'\r' b'FREE\r' b'TYPE DOCS\r' b'MON\r')
    b = V.Elf2K(cf, keys=keys); st = b.boot_rom(cap=900_000_000); t = b.text(); e = []
    if not pieces or pieces < 2: e.append('FRAG.TXT is not fragmented (%s pieces) - the test proves less' % pieces)
    d = session_out(t, 'DIR\r')
    for f in (r'BIG      TXT +%d ' % len(big), r'FRAG     TXT +%d ' % len(frag), r'KEEP     TXT +3000 ',
              re.escape(lname.replace('.', ' ')) + r' +\d+ ', r'DOCS {14}<DIR>'):
        if not re.search(f, d): e.append('DIR: %r missing' % f)
    if rc != 0: e.append('fsck_msdos says the hand-fragmented card is damaged')
    if 'GAP1' in d or 'FSEVEN' in d or '._' in d: e.append('DIR shows what it should not: %r' % d)
    if session_out(t, 'TYPE BIG.TXT\r').lstrip('\r\n') != typed(big.decode()): e.append('TYPE BIG.TXT differs')
    if session_out(t, 'TYPE FRAG.TXT\r').lstrip('\r\n') != typed(frag.decode()): e.append('TYPE FRAG.TXT (fragmented) differs')
    if 'long names show their short form' not in session_out(t, 'TYPE ' + lname + '\r'): e.append('TYPE ' + lname)
    m = re.search(r'\((\d+) of (\d+) clusters', session_out(t, 'FREE\r'))
    if not m or int(m.group(1)) != fr[1]: e.append('FREE %s, fsck %s' % (m and m.group(1), fr))
    if 'DOCS is a folder.' not in session_out(t, 'TYPE DOCS\r'): e.append('TYPE DOCS')
    if st != 'stop': e.append('MON: %s' % st)
    if '-v' in sys.argv: print(t[:3000])
    report('the Mac\'s files on a 32 MB card: DIR (long name, folder; not ._ / .fseventsd), TYPE of a 20 KB file '
           'and of a file in %s pieces exact, FREE = fsck (%s clusters)' % (pieces, fr and fr[1]), e)

    # without STELLAR in RAM: F installs without STELLAR.BIN; MON just leaves
    e = []
    for how, fill in (('RAM empty', lambda M: M.__setitem__(slice(0, 0x2F00), bytes(0x2F00))),
                      ('LTOS in RAM', lambda M: M.__setitem__(slice(0x0300, 0x0307), b'\xC0\x03\x09LTOS'))):
        cf = CV.CF(sectors=16384)
        e2k = V.Elf2K(cf, keys=b'F')
        for a, b_ in mem.items(): e2k.c.M[a] = b_
        fill(e2k.c.M)
        e2k.call(0x3000, cap=300_000_000); P1.second_paste(e2k); t = e2k.text()
        if 'STELLAR is not in RAM: no STELLAR.BIN' not in t or 'STELLAR BIN' in t or 'The card is ready.' not in t:
            e.append('%s: install %r' % (how, t[-300:]))
        img = V.image(cf, 16384)
        got, out = mac(img, lambda m: sorted(f for f in os.listdir(m) if not f.startswith('.')))
        inst = sorted(n[:8].decode().strip() + '.' + n[8:].decode().strip() for n in build.build.installed_files + build.build.install2_files)
        if out != inst or fsck_free(img)[0] != 0: e.append('%s: the Mac sees %s' % (how, out))
        P1.add_system(cf, ram=lambda M: M.__setitem__(slice(0, 0x2F00), bytes(0x2F00)))
        inst = sorted(n[:8].decode().strip() + '.' + n[8:].decode().strip() for n, d in build.samples())
        b = V.Elf2K(cf, keys=b'VER\rDIR\rMON\r')
        b.c.M[0:0x2F00] = bytes(0x2F00)
        st = b.boot_rom(cap=200_000_000); t = b.text()
        if 'no STELLAR.BIN on this card' not in t or '%4d files' % len(inst) not in t or 'Back to the monitor.' not in t or 'Putting STELLAR back' in t or st != 'stop':
            e.append('%s: boot %s %r' % (how, st, t[-300:]))
    report('no STELLAR in RAM (empty, or a booted LTOS): F installs without STELLAR.BIN, the Mac sees 2 files; VER says so; MON just leaves', e)

    # a card WITH STELLAR.BIN, booted when RAM did not hold STELLAR: MON leaves RAM alone
    e = []
    cf, e2k, st = P1.installed_full(mem, 16384)
    b = V.Elf2K(cf, keys=b'VER\rMON\r')
    b.c.M[0x2800:0x2F00] = bytes(0x700)
    st = b.boot_rom(cap=200_000_000); t = b.text()
    if 'not in RAM at boot: MON just leaves' not in t or 'Back to the monitor.' not in t or 'Putting STELLAR back' in t:
        e.append(repr(t[-300:]))
    b = V.Elf2K(cf, keys=b'VER\rMON\r'); st = b.boot_rom(cap=200_000_000); t = b.text()
    if ' - in RAM at boot: MON puts it back' not in t or 'STELLAR is as it was before LTOS.' not in t:
        e.append('with STELLAR: %r' % t[-300:])
    report('STELLAR.BIN on the card: VER/MON put STELLAR back only if it was in RAM when LTOS started', e)

    # a garbled paste: one byte of the kernel image wrong in RAM -> stopped before anything is written
    e = []
    cf = CV.CF(sectors=16384); cf.log.clear()
    e2k = V.Elf2K(cf, keys=b'F')
    for a, b_ in mem.items(): e2k.c.M[a] = b_
    e2k.c.M[syms['KERNIMG'] + 3000] ^= 0x04
    e2k.call(0x3000, cap=300_000_000); t = e2k.text()
    if 'INSTALL.HEX did not load right' not in t or any(k == 'write' for k, _ in cf.log): e.append('garbled paste: %r' % t[-200:])
    # a card that does not keep a kernel sector: the read-back says which
    cf = CV.CF(sectors=16384, corrupt=(70, 100))
    e2k = V.Elf2K(cf, keys=b'F')
    for a, b_ in mem.items(): e2k.c.M[a] = b_
    e2k.call(0x3000, cap=300_000_000); t = e2k.text()
    if 'VERIFY FAILED: the card did not keep what was written to sector $00000046' not in t: e.append('bad card: %r' % t[-250:])
    if t.count('- writing it again.') != 2: e.append('bad card: %d rewrites, not 2' % t.count('- writing it again.'))
    # one misread during the read-back: a read glitch, and the install goes on
    cf = CV.CF(sectors=16384); real = cf.command; once = [True]
    def glitch(v, cf=cf):
        r = real(v)
        if v == 0x20 and cf.lba() == 270 and once[0]:
            once[0] = False; buf = bytearray(cf.buf); buf[0xAF] ^= 0x10; cf.buf = bytes(buf)
        return r
    cf.command = glitch
    e2k = V.Elf2K(cf, keys=b'F')
    for a, b_ in mem.items(): e2k.c.M[a] = b_
    e2k.call(0x3000, cap=300_000_000); t = e2k.text()
    if 'sector $010E byte $00AF' not in t or 'read again: it is right (a read glitch).' not in t or 'read glitches: 1, sectors written again: 0' not in t \
       or 'The card is ready' not in t: e.append('read glitch: %r' % t[-400:])
    # one bad write: written again, and the install goes on
    cf = CV.CF(sectors=16384); realw = cf.write; once = [True]
    def wglitch(r, v, cf=cf):
        if r == 0 and cf.mode == 'in' and cf.wlba == 275 and len(cf.wbuf) == 10 and once[0]:
            once[0] = False; v ^= 0x80
        return realw(r, v)
    cf.write = wglitch
    e2k = V.Elf2K(cf, keys=b'F')
    for a, b_ in mem.items(): e2k.c.M[a] = b_
    e2k.call(0x3000, cap=300_000_000); t = e2k.text()
    if 'sector $0113 byte $000A' not in t or t.count('- writing it again.') != 1 or 'read glitches: 0, sectors written again: 1' not in t \
       or 'The card is ready' not in t: e.append('write glitch: %r' % t[-400:])
    report('a garbled paste is caught before anything is written; a card that never keeps a sector: 2 rewrites then '
           'VERIFY FAILED; one misread: a read glitch, install goes on; one bad write: written again, install goes on', e)

    # FW: the firmware into memory and the monitor, however LTOS started (RAM empty at the boot: MON leaves, FW loads)
    e = []
    stl = S.image('37')[0:0x2F00]
    cf, e2k, st = P1.installed_full(mem, 16384)
    for keys, ram, what in ((b'FW NOPE.BIN\rFW\r', True, 'RAM empty at the boot'), (b'FW STELLAR.BIN\r', False, 'STELLAR in RAM')):
        b = V.Elf2K(cf, keys=keys)
        if ram: b.c.M[0:0x2F00] = bytes(0x2F00)
        st = b.boot_rom(cap=200_000_000); t = b.text()
        if st != 'stop' or bytes(b.c.M[0:0x2F00]) != bytes(stl) or 'Loading STELLAR.BIN into memory ... done.' not in t \
           or 'Back to the monitor - STELLAR is in memory.' not in t: e.append('%s: %s %r' % (what, st, t[-250:]))
        if ram and 'NOPE.BIN is not on the card, or not a STELLAR firmware (12 KB at least).' not in t: e.append('FW NOPE.BIN: %r' % t[-300:])
    cf = CV.CF(sectors=16384)                                   # a card with no STELLAR.BIN: said, LTOS goes on
    e2k = V.Elf2K(cf, keys=b'F')
    for a, b_ in mem.items(): e2k.c.M[a] = b_
    e2k.c.M[0:0x2F00] = bytes(0x2F00)
    e2k.call(0x3000, cap=300_000_000)
    if 'CALL 3003' in e2k.text(): P1.second_paste(e2k)
    P1.add_system(cf, ram=lambda M: M.__setitem__(slice(0, 0x2F00), bytes(0x2F00)))
    b = V.Elf2K(cf, keys=b'FW\rMON\r'); b.c.M[0:0x2F00] = bytes(0x2F00)
    st = b.boot_rom(cap=200_000_000); t = b.text()
    if 'STELLAR.BIN is not on the card, or not a STELLAR firmware' not in t or st != 'stop': e.append('no STELLAR.BIN: %s %r' % (st, t[-250:]))
    report('FW: STELLAR.BIN into memory and the monitor with RAM empty at the boot, and again with STELLAR there '
           '(FW STELLAR.BIN); a name not there and a card without STELLAR.BIN said, LTOS goes on', e)

    print('\nLTOS phase 2:', 'ALL PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
