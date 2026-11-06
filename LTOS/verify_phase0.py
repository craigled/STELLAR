# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The LTOS simulator harness (Elf2K: the real ROM, the CF card model, the Mac's checks), used by
verify_phase1.py. Its own main() tested PHASE 0's boot sector, which phase 1 replaced - see git history.

LTOS phase 0 in the simulator: the installer, then booting the card, against the REAL Elf2K ROM.

  * the Elf2K ROM (Spare Time Gizmos, v120) at $8000-$FFFF - its BIOS does the console and the BOOT;
  * the Disk/UART/RTC card: OUT 2 selects - $00-$1F the CF card (the CF-Test model: strict 8-bit mode,
    busy, DRQ, IDNF, ERR held until the next command), $10 / $15 the UART's data / status;
  * STELLAR V0061.36 in RAM at $0000-$2EFF, as on Craig's Elf2K; INSTALL.HEX loaded as the monitor would.
Checks: the installer runs as the monitor's CALL 3000 would, on an 8 MB and a 32 MB card full of junk; the
card it leaves is checked by the Mac's own FAT code (hdiutil + fsck_msdos) and STELLAR.BIN read back from
it by the Mac must be the firmware byte for byte; then the card boots through the ROM's own BOOT code (the
new-BIOS way in, $0106 with R3) and the BIOS 1.0.6 way ($0100 with R0); N leaves the card untouched; no
card is reported and nothing hangs.

    python3 LTOS/verify_phase0.py
"""
import os, sys, subprocess, tempfile, re, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
from cpu1802 import CPU
import opcode_sweep as S
import cftest_verify as CV
import build

ROM = os.path.join(HERE, 'rom', 'Elf2K-v120.hex')
STUB = 0x7E80                       # the monitor's CALL, played by: SEP R4 / DW 3000 / IDL


def load_hex(path, mem, offset=0):
    for ln in open(path):
        ln = ln.strip()
        if not ln.startswith(':') or ln[7:9] != '00': continue
        n, a = int(ln[1:3], 16), int(ln[3:7], 16)
        for i in range(n): mem[(a + offset + i) & 0xFFFF] = int(ln[9 + 2 * i:11 + 2 * i], 16)


class UART:
    """keys: typed ahead. later: [(prompt, keys), ...] - each typed only once the prompt has been printed (after
    the previous one), for programs that look for a key while they work and would eat keys typed ahead."""
    PER = 58                                            # 19200 baud on the Elf2K: one character per ~58 instructions
    def __init__(s, keys, later=()):
        s.q = list(keys); s.out = []; s.later = list(later); s.seen = 0; s.timed = None; s.lost = 0; s.now = 0
    def feed(s):
        if s.q or s.timed or not s.later: return
        p, k = s.later[0][:2]
        i = bytes(s.out).find(p.encode('latin1'), s.seen)
        if i >= 0: s.seen = i + len(p); s.q = list(k); s.later.pop(0)
    # timed: [(prompt, keys, 'timed')] - the keys arrive one per PER instructions, as a terminal sends a file at
    # full speed; the UART holds ONE: a character not read before the next arrives is lost (the Elf2K's)
    def feed_timed(s):
        if s.q or s.timed or not s.later or len(s.later[0]) < 3: return False
        p, k, _ = s.later[0]
        i = bytes(s.out).find(p.encode('latin1'), s.seen)
        if i >= 0: s.seen = i + len(p); s.later.pop(0); s.timed = [s.now, bytes(k), 0]
        return True
    def ready(s):
        t0, k, d = s.timed
        n = min(len(k), (s.now - t0) // s.PER)
        if n >= len(k) and d >= len(k): s.timed = None; return False
        return n > d
    def read(s):
        t0, k, d = s.timed
        n = min(len(k), (s.now - t0) // s.PER)
        if n <= d: return 0
        s.lost += n - 1 - d; s.timed[2] = n
        return k[n - 1]


class P3In:
    def __init__(s, m): s.m = m
    def pop(s, i=0):
        sel = s.m.sel()
        if sel & 0x90 == 0: return s.m.cf.read(sel & 0x1F)
        u = s.m.u
        if sel in (0x10, 0x15):
            u.now = s.m.steps
            if not u.feed_timed(): u.feed()
        if u.timed is not None and sel in (0x10, 0x15):
            if sel == 0x10: return u.read()
            return 0x60 | (1 if u.ready() else 0)
        if sel == 0x10: return u.q.pop(0) if u.q else 0
        if sel == 0x15: return 0x60 | (1 if u.q else 0)          # THR empty, TX empty, data ready
        if sel & 0x80 and s.m.rtc: return s.m.rtc(sel & 0x7F)          # a DS12887, if the test gives one
        return 0
    def __bool__(s): return True

class P3Out(list):
    def __init__(s, m): super().__init__(); s.m = m
    def append(s, b):
        sel = s.m.sel()
        if sel & 0x90 == 0: s.m.cf.write(sel & 0x1F, b)
        elif sel == 0x10: s.m.u.out.append(b)
        elif sel & 0x80 and getattr(s.m, 'rtcw', None): s.m.rtcw(sel & 0x7F, b)      # a writable clock

class Const:
    def __init__(s, v): s.v = v
    def pop(s, i=0): return s.v
    def __bool__(s): return True


class Elf2K:
    def __init__(s, cf, keys=b'', later=()):
        mem = bytearray(0x10000)
        mem[0:0x3000] = S.image('37')[0:0x3000]                    # STELLAR, as on Craig's Elf2K
        load_hex(ROM, mem, 0x8000)
        s.c = CPU(mem); s.cf = cf; s.u = UART(keys, later); s.rtc = None
        s.c.io_out[2] = []
        s.c.io_out[3] = P3Out(s)
        s.c.io_in[3] = P3In(s)
        s.c.io_in[2] = Const(0x30 if cf.present else 0)
        for p in (1, 4, 5, 6, 7): s.c.io_in[p] = Const(0)
    def sel(s): return s.c.io_out[2][-1] if s.c.io_out[2] else 0x15
    def text(s): return bytes(s.u.out).decode('latin1')
    steps = 0
    STALL = 32                                          # x 2^20 steps with no keys left to give and nothing printed
    def run(s, cap, stop=None):
        c = s.c; u = s.u; quiet = 0; seen = -1
        for k in range(cap):
            if stop is not None and c.R[c.P] == stop: return 'stop'
            if not c.step(): return 'idle'
            s.steps += 1
            if k & 0xFFFFF == 0xFFFFF:                  # stuck at a prompt (or in a loop) with nothing to come: stop
                n = len(u.out)
                if n == seen and not u.q and not u.timed and getattr(u, 'gen', None) is None: quiet += 1
                else: quiet = 0
                seen = n
                if quiet >= s.STALL: return 'stuck'
        return 'cap'
    def call(s, addr, cap=60_000_000):
        """The monitor's CALL addr: SCRT from the BIOS (F_INITCALL), R2 a stack, RE.1 = 1 (the UART)."""
        c, m = s.c, s.c.M
        m[STUB:STUB + 4] = bytes([0xD4, addr >> 8, addr & 0xFF, 0x00])
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[6] = STUB
        c.R[3] = 0xFF3F; c.P = 3
        return s.run(cap)
    def boot_rom(s, cap=60_000_000):
        """The monitor's BOOT: the BIOS's own F_BOOT ($FF00) - reset, read LBA 0 to $0100, check, jump."""
        c = s.c
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        return s.run(cap, stop=0x8003)
    def boot_106(s, cap=60_000_000):
        """BIOS 1.0.6's ending, which v120 does not have: the sector at $0100, R0 = $0100, SEP R0."""
        c = s.c
        c.M[STUB] = 0x00                                                 # the BIOS's SCRT into R4 / R5, then IDL
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[6] = STUB; c.R[3] = 0xFF3F; c.P = 3
        s.run(10_000); c.halted = False
        c.M[0x100:0x300] = s.cf.sector(0)
        c.R[2] = 0x00F0; c.X = 2; c.R[0xE] = 0x0100; c.R[0] = 0x0100; c.P = 0
        return s.run(cap, stop=0x8003)


def image(cf, n):
    return b''.join(cf.disk.get(l, bytes(512)) if l in cf.disk else bytes(512) for l in range(n))


def writes(cf):
    """The sectors the 1802 has written to the CF card model so far (its log), in order."""
    return [l for k, l in cf.log if k == 'write']


def mac_check(img_bytes):
    """Attach the image as a disk, fsck_msdos its partition, mount it, read STELLAR.BIN. -> (ok, notes, data)"""
    d = tempfile.mkdtemp(); p = os.path.join(d, 'card.img'); open(p, 'wb').write(img_bytes)
    notes, data, ok = [], None, False
    r = subprocess.run(['hdiutil', 'attach', '-imagekey', 'diskimage-class=CRawDiskImage', '-nomount', p],
                       capture_output=True, text=True)
    if r.returncode: return False, ['hdiutil attach: ' + r.stderr.strip()], None
    devs = re.findall(r'(/dev/disk\d+(?:s\d+)?)\s+(\S+)?', r.stdout)
    disk = devs[0][0]; part = [x for x, t in devs if re.search(r's\d+$', x)]
    try:
        notes.append('partitions: ' + ', '.join('%s %s' % (x, t) for x, t in devs))
        if not part: notes.append('no partition seen'); return False, notes, None
        f = subprocess.run(['fsck_msdos', '-n', part[0]], capture_output=True, text=True)
        notes.append('fsck_msdos: ' + ' | '.join(l.strip() for l in (f.stdout + f.stderr).split('\n') if l.strip()))
        mnt = os.path.join(d, 'mnt'); os.mkdir(mnt)
        m = subprocess.run(['mount', '-t', 'msdos', '-o', 'rdonly', part[0], mnt], capture_output=True, text=True)
        if m.returncode:
            m = subprocess.run(['diskutil', 'mount', '-mountPoint', mnt, 'readOnly', part[0]], capture_output=True, text=True)
        files = os.listdir(mnt) if os.path.ismount(mnt) else []
        notes.append('files: %s' % sorted(files))
        if 'STELLAR.BIN' in files: data = open(os.path.join(mnt, 'STELLAR.BIN'), 'rb').read()
        ok = f.returncode == 0 and data is not None
        if os.path.ismount(mnt): subprocess.run(['umount', mnt], capture_output=True)
        return ok, notes, data
    finally:
        subprocess.run(['hdiutil', 'detach', disk, '-force'], capture_output=True)
        shutil.rmtree(d, ignore_errors=True)


def main():
    ok = True
    mem, syms, boot = build.build()
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    for mb in (8, 32):
        n = mb * 2048
        cf = CV.CF(sectors=n)
        e2k = Elf2K(cf, keys=b'Y')
        for a, b in mem.items(): e2k.c.M[a] = b
        stl = bytes(e2k.c.M[0:0x2F00])
        st = e2k.call(0x3000, cap=200_000_000); t = e2k.text(); e = []
        if st != 'idle' or e2k.c.R[3] != STUB + 4: e.append('did not return to the monitor (%s, PC $%04X)' % (st, e2k.c.R[e2k.c.P]))
        if 'The card is ready. Type BOOT.' not in t: e.append('installer said: %r' % t[-300:])
        if 'SanDisk' not in t or ('%d MB' % mb) not in t: e.append('identify / size: %r' % t[:300])
        if e2k.c.M[0:0x2F00] != stl: e.append('the installer changed STELLAR in RAM')
        s0 = cf.sector(0)
        if s0[:0x30] + s0[0x32:0x1BE] != boot[:0x30] + boot[0x32:0x1BE] or s0[0x1FE:] != b'\x55\xAA': e.append('LBA 0 is not the boot sector')
        vbr = cf.sector(64); data = 64 + 32 + 2 * (vbr[22] | vbr[23] << 8) + 32
        if (s0[0x30] << 8 | s0[0x31]) != data: e.append('the boot sector points at $%04X for STELLAR.BIN, not $%04X' % (s0[0x30] << 8 | s0[0x31], data))
        if build.btcheck(cf.sector(0)) != 0x60: e.append('the BIOS would refuse LBA 0')
        good, notes, data = mac_check(image(cf, n))
        if not good: e.append('the Mac: ' + ' / '.join(notes))
        elif data != stl: e.append('STELLAR.BIN read by the Mac is not the firmware (%d bytes)' % len(data))
        report('%d MB card: the installer (%s) - the Mac\'s fsck_msdos and mount accept it, STELLAR.BIN is the '
               'firmware byte for byte' % (mb, re.search(r'FAT16: +([^\r]*)', t).group(1) if 'FAT16:' in t else '?'), e)
        if '-v' in sys.argv: print(t); print('\n'.join('    ' + x for x in notes))

        # boot it, the ROM's own way (new BIOS: $0106, R3) and BIOS 1.0.6's ($0100, R0)
        e = []
        for how, fn, reg in (('ROM BOOT', 'boot_rom', '3'), ('BIOS 1.0.6', 'boot_106', '0')):
            b = Elf2K(cf); st = getattr(b, fn)(); t = b.text()
            want = 'started it with R%s as the PC' % reg
            if st != 'stop' or want not in t or 'The boot path works' not in t:
                e.append('%s: %s, %r' % (how, st, t[-200:]))
            if 'STELLAR in RAM put back' not in t or bytes(b.c.M[0:0x2F00]) != S.image('37')[0:0x2F00]:
                e.append('%s: STELLAR in RAM is not as it was after the boot' % how)
        report('%d MB card boots: through the ROM\'s own BOOT ($0106 with R3) and as BIOS 1.0.6 does ($0100 with R0); '
               'STELLAR in RAM put back byte for byte; back to the monitor' % mb, e)

    # N: nothing written.  No card: said, and nothing hangs.
    cf = CV.CF(sectors=16384); before = dict((l, cf.sector(l)) for l in range(0, 200))
    e2k = Elf2K(cf, keys=b'n')
    for a, b in mem.items(): e2k.c.M[a] = b
    st = e2k.call(0x3000, cap=100_000_000); t = e2k.text(); e = []
    if 'Nothing written.' not in t or any(k == 'write' for k, _ in cf.log): e.append(repr(t[-200:]))
    cf = CV.CF(present=False); e2k = Elf2K(cf)
    for a, b in mem.items(): e2k.c.M[a] = b
    st = e2k.call(0x3000, cap=400_000_000); t = e2k.text()
    if st != 'idle' or 'no answer. Is a card in the socket?' not in t: e.append('no card: %s %r' % (st, t[-200:]))
    report('N at the question: nothing written; no card: "no answer. Is a card in the socket?", back to the monitor', e)

    print('\nLTOS phase 0:', 'ALL PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit('phase 0 is superseded: run verify_phase1.py')
