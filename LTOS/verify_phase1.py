# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 1 in the simulator, against the real Elf2K ROM (v120) and the CF card model (verify_phase0.py's
harness): the kernel and its commands.

  * F: the installer formats the card and writes the kernel; BOOT (the ROM's own, $0106 with R3, and BIOS
    1.0.6's, $0100 with R0) loads it and the LTOS> prompt answers: HELP, ?, VER (kernel, card, size,
    STELLAR.BIN, which register booted it), CLS, DUMP a n and DUMP going on, an unknown word, Ctrl-C,
    lower case; MON puts STELLAR back byte for byte and reaches the monitor;
  * U: a file the Mac put on the card survives an update - the partition, the FATs and STELLAR.BIN are
    untouched, fsck_msdos is clean, the card boots; U on a card without LTOS writes nothing.

    python3 LTOS/verify_phase1.py
"""
import time, os, sys, re, subprocess, tempfile, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import cftest_verify as CV
import opcode_sweep as S
import build

PAGES = b' ' * (build.help_list().count('\n') // 22)   # a key for each pause: after every 22 lines, the last too
SESSION = (b'help\r' + PAGES + b'?\r' + PAGES + b'VER\r' b'DUMP 300 20\r' b'dump\r' b'foo bar\r' b'CLS\r' b'DUMP 7FX\x08 10\r'
           b'abc\x03' b'MON\r')


def installed(mem, n, keys=b'F', cf=None):
    cf = cf or CV.CF(sectors=n)
    e = V.Elf2K(cf, keys=keys)
    for a, b in mem.items(): e.c.M[a] = b
    st = e.call(0x3000, cap=300_000_000)
    if keys[:1] in (b'F', b'f') and 'CALL 3003' in e.text(): st = second_paste(e)
    return cf, e, st


def second_paste(e):
    """After F: INSTALL2.HEX loaded by the monitor, then CALL 3003 (RECV and the first programs onto the card)."""
    m2 = {}
    V.load_hex(os.path.join(build.OUT, 'INSTALL2.HEX'), m2)
    for a, b in m2.items(): e.c.M[a] = b
    e.c.halted = False
    return e.call(0x3003, cap=300_000_000)


def installed_full(mem, n, keys=b'F', cf=None, rtc=None):
    """F, then BOOT and RECV SYSTEM with LTOS-SYSTEM.HEX (every program), then MON - a card as Craig makes one."""
    cf, e, st = installed(mem, n, keys, cf)
    add_system(cf, rtc)
    return cf, e, st


def add_system(cf, rtc=None, ram=None):
    """BOOT, RECV SYSTEM with LTOS-SYSTEM.HEX (and again with LTOS-SYSTEM2.HEX), MON: every program on the card."""
    later = []
    for nm in build.sysparts():
        p = os.path.join(build.OUT, nm)
        if not os.path.exists(p): continue
        hx = open(p).read().replace('\n', '\r\n').encode()
        if later: later.append(('LTOS> ', b'RECV SYSTEM\r'))
        later.append(('Ctrl-C stops.', hx))
    later.append(('LTOS> ', b'MON\r'))
    b = V.Elf2K(cf, keys=b'RECV SYSTEM\r', later=later); b.rtc = rtc
    if ram: ram(b.c.M)
    st2 = b.boot_rom(cap=1_800_000_000)
    assert st2 == 'stop' and b.text().count(' saved') >= len(build.samples()), (st2, b.text().count(' saved'), len(build.samples()), b.text()[-600:])


def load_image(cf, data):
    cf.disk = {i: data[i * 512:(i + 1) * 512] for i in range(len(data) // 512)}


def mac_add_file(img, name, content):
    """Mount the image's partition read-write on the Mac and put a file on it. -> the new image bytes."""
    d = tempfile.mkdtemp(); p = os.path.join(d, 'card.img'); open(p, 'wb').write(img)
    r = subprocess.run(['hdiutil', 'attach', '-imagekey', 'diskimage-class=CRawDiskImage', '-nomount', p],
                       capture_output=True, text=True)
    disk = r.stdout.split()[0]; mnt = os.path.join(d, 'mnt'); os.mkdir(mnt)
    try:
        m = subprocess.run(['diskutil', 'mount', '-mountPoint', mnt, disk + 's1'], capture_output=True, text=True)
        assert os.path.ismount(mnt), m.stdout + m.stderr
        open(os.path.join(mnt, name), 'wb').write(content)
        subprocess.run(['sync'])
        for k in range(10):
            if subprocess.run(['diskutil', 'unmount', mnt], capture_output=True).returncode == 0: break
            time.sleep(1)
        else:
            subprocess.run(['diskutil', 'unmount', 'force', mnt], capture_output=True)
    finally:
        subprocess.run(['hdiutil', 'detach', disk, '-force'], capture_output=True)
    data = open(p, 'rb').read(); shutil.rmtree(d, ignore_errors=True)
    return data


def mac_read(img, name):
    d = tempfile.mkdtemp(); p = os.path.join(d, 'card.img'); open(p, 'wb').write(img)
    r = subprocess.run(['hdiutil', 'attach', '-imagekey', 'diskimage-class=CRawDiskImage', '-nomount', p],
                       capture_output=True, text=True)
    disk = r.stdout.split()[0]; mnt = os.path.join(d, 'mnt'); os.mkdir(mnt); out = None
    try:
        f = subprocess.run(['fsck_msdos', '-n', disk + 's1'], capture_output=True, text=True, errors='replace')
        subprocess.run(['diskutil', 'mount', 'readOnly', '-mountPoint', mnt, disk + 's1'], capture_output=True)
        if os.path.exists(os.path.join(mnt, name)): out = open(os.path.join(mnt, name), 'rb').read()
        subprocess.run(['diskutil', 'unmount', mnt], capture_output=True)
        return f.returncode, out
    finally:
        subprocess.run(['hdiutil', 'detach', disk, '-force'], capture_output=True)
        shutil.rmtree(d, ignore_errors=True)


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    kend = ksyms['KEND'] - 1

    for mb in (8, 32):
        n = mb * 2048
        cf, e2k, st = installed(mem, n)
        t = e2k.text(); e = []
        if 'The card is ready. Type BOOT.' not in t or ('%d sectors' % ((len(kimg) + 511) // 512) not in t): e.append('install: %r' % t[-300:])
        s0 = cf.sector(0)
        if s0[0x32] != len(kimg) // 512 + (1 if len(kimg) % 512 else 0): e.append('KSECT = %d' % s0[0x32])
        for k in range(s0[0x32]):
            if cf.sector(65 + k) != kimg[k * 512:(k + 1) * 512].ljust(512, b'\0'): e.append('kernel sector %d differs' % k)
        stl = (s0[0x30] << 8) | s0[0x31]
        add_system(cf)                                          # VER.PRG and the rest
        for how, fn, reg in (('ROM BOOT', 'boot_rom', '3'), ('BIOS 1.0.6', 'boot_106', '0')):
            b = V.Elf2K(cf, keys=SESSION); st = getattr(b, fn)(cap=200_000_000); t = b.text()
            want = ['LTOS: loading the kernel %sdone.\r\n' % ('.' * s0[0x32]), 'LTOS 0.5 - LiteOS for the Elf2K.  Type HELP',
                    '  MON         Back to the monitor', 'Kernel:     $0300-$%04X' % kend,
                    'the boot sector started with R%s' % reg, 'Card:       SanDisk SDCFB-128',
                    'Size:       %d MB' % mb, 'STELLAR.BIN at sector $%04X' % stl,
                    '0300  ' + ' '.join('%02X' % x for x in kimg[:7]), '0310 ', '0320 ', '0330 ', '007F ',
                    'Unknown command: foo  (see HELP)', '\x1b[2J\x1b[H', '^C',
                    'Putting STELLAR back from STELLAR.BIN ... done.', 'STELLAR is as it was before LTOS.']
            miss = [w for w in want if w not in t]
            if t.count('LTOS 0.5 - LiteOS for the Elf2K\r\n') != 1: miss.append('VER once')
            if t.count('  DIR         List the files in a folder') != 2: miss.append('HELP and ? both')
            if '0390 ' not in t or '03A0 ' in t or '008F ' in t: miss.append('DUMP: DUMP alone should go on $80 bytes from $0320')
            if miss: e.append('%s: missing %s' % (how, miss))
            if st != 'stop': e.append('%s: did not reach the monitor (%s)' % (how, st))
            if bytes(b.c.M[0:0x2F00]) != S.image('37')[0:0x2F00]: e.append('%s: STELLAR in RAM not as it was' % how)
            if '-v' in sys.argv: print(t)
        report('%d MB: F installs a %d-sector kernel; both boot paths reach LTOS>; HELP ? VER CLS DUMP, unknown words, '
               'Ctrl-C, Backspace; MON puts STELLAR back byte for byte' % (mb, s0[0x32]), e)

    # a damaged kernel sector: the checksum says so; a card that stops answering after BOOT's own read: no hang
    cf, e2k, st = installed(mem, 16384); e = []
    k2 = bytearray(cf.sector(67)); k2[100] ^= 0x40; cf.disk[67] = bytes(k2)
    b = V.Elf2K(cf, keys=b''); st = b.boot_rom(cap=100_000_000); t = b.text()
    if t.count('?') != 2 or ' FAILED (read/sum).' not in t or st != 'stop': e.append('damaged: %s %r' % (st, t[-120:]))
    cf, e2k, st = installed(mem, 16384)
    real = cf.command
    def mute(v, cf=cf):
        if v == 0x20 and cf.lba() == 65: cf.present = False
        return real(v)
    cf.command = mute
    b = V.Elf2K(cf, keys=b''); st = b.boot_rom(cap=100_000_000); t = b.text()
    if ' FAILED (read/sum).' not in t or st != 'stop': e.append('silent card: %s %r' % (st, t[-120:]))
    # a card that misreads one kernel sector ONCE: the boot loads it all again and goes on
    cf, e2k, st = installed(mem, 16384)
    real2 = cf.command; once = [True]
    def glitch(v, cf=cf):
        r = real2(v)
        if v == 0x20 and cf.lba() == 68 and once[0]:
            once[0] = False; buf = bytearray(cf.buf); buf[200] ^= 0x01; cf.buf = bytes(buf)
        return r
    cf.command = glitch
    b = V.Elf2K(cf, keys=b'MON\r'); st = b.boot_rom(cap=200_000_000); t = b.text()
    if '?' not in t or 'LTOS 0.5 - LiteOS' not in t: e.append('one misread: %r' % t[-200:])
    report('a damaged kernel sector: three tries, then "FAILED (read/sum)"; a silent card: the same, no hang; '
           'ONE misread: "?", loaded again, LTOS starts', e)

    # U keeps the files
    n = 16384
    cf, e2k, st = installed(mem, n)
    img = V.image(cf, n)
    hello = b'Hello from the Mac - a file LTOS must keep.\r\n' * 40
    img2 = mac_add_file(img, 'HELLO.TXT', hello)
    load_image(cf, img2)
    before = {l: cf.sector(l) for l in range(n) if not (l == 0 or 65 <= l < 96)}
    cf.log.clear()
    e2k = V.Elf2K(cf, keys=b'U')
    for a, b in mem.items(): e2k.c.M[a] = b
    st = e2k.call(0x3000, cap=300_000_000); t = e2k.text(); e = []
    if 'an LTOS card.' not in t or 'LTOS is updated; the files on the card are as they were.' not in t: e.append(repr(t[-300:]))
    writes = sorted(set(l for k, l in cf.log if k == 'write'))
    if any(not (l == 0 or 65 <= l < 96) for l in writes): e.append('wrote outside the boot sector and the kernel: %s' % writes)
    if any(cf.sector(l) != b for l, b in before.items()): e.append('a sector outside them changed')
    if cf.sector(0)[0x1BE:0x1FE] != img2[0x1BE:0x1FE] or cf.sector(0)[0x30:0x32] != img2[0x30:0x32]:
        e.append('the partition table or STELLAR.BIN\'s sector changed')
    rc, got = mac_read(V.image(cf, n), 'HELLO.TXT')
    if rc != 0 or got != hello: e.append('the Mac: fsck %d, HELLO.TXT %s' % (rc, 'kept' if got == hello else 'LOST'))
    b = V.Elf2K(cf, keys=b'VER\rMON\r'); st = b.boot_rom(cap=200_000_000)
    if 'LTOS 0.5 - LiteOS' not in b.text() or st != 'stop': e.append('after U: %r' % b.text()[-200:])
    cf3 = CV.CF(sectors=n); cf3.log.clear()
    e3 = V.Elf2K(cf3, keys=b'U')
    for a, b_ in mem.items(): e3.c.M[a] = b_
    e3.call(0x3000, cap=300_000_000)
    if 'this card has no LTOS on it' not in e3.text() or any(k == 'write' for k, _ in cf3.log): e.append('U on a blank card: %r' % e3.text()[-200:])
    report('U: a file the Mac put on the card survives (only LBA 0 and the kernel sectors written; fsck clean); '
           'the card boots; U on a card without LTOS writes nothing', e)

    print('\nLTOS phase 1:', 'ALL PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
