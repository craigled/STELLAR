# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""When the card was formatted, and when LTOS was built, in the simulator:
  * F with a DS12887 keeps 'FD' and the clock's registers (B year month day hour minute second) in the partition's
    boot record at $1F0; DISKINFO and DISKINFO -Q show "Formatted:     yyyy-mm-dd hh:mm" from them - BCD, binary
    (year from 1972, as the Elf2K BIOS keeps it), a 12-hour clock (AM, PM, 12 AM, 12 PM);
  * no clock at F, or a card another formatter made (no 'FD'): "not recorded";
  * VER: "Built:      yyyy-mm-dd hh:mm" = the kernel's DATEV (build.py: the build's time).

    python3 LTOS/verify_fmtdate.py [-v]
"""
import os, re, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase3 as P3
CV = P1.CV
import build


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    kimg, ksyms = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384

    def install(rtc):
        cf = CV.CF(sectors=n)
        e = V.Elf2K(cf, keys=b'F'); e.rtc = rtc
        for a, b in mem.items(): e.c.M[a] = b
        st = e.call(0x3000, cap=300_000_000)
        if 'CALL 3003' in e.text(): st = P1.second_paste(e)
        return cf, st

    def session(cf, keys):
        later = [('LTOS> ', k) for k in keys] + [('LTOS> ', b'MON\r')]
        b = V.Elf2K(cf, keys=b'', later=later)
        st = b.boot_rom(3_000_000_000)
        return st, b.text().replace('\r', '')

    def formatted(t):
        return re.findall(r'\n  Formatted:\s+(.*)', t)

    # F with a BCD 24-hour clock, then every program; DISKINFO and -Q; VER
    cf, st = install(P3.clock(26, 11, 16, 14, 30, 20))
    e = []
    vbr = 64 * 512
    img = bytearray(V.image(cf, n))
    want = b'FD' + bytes([0x02, 0x26, 0x11, 0x16, 0x14, 0x30, 0x20])
    if img[vbr + 0x1F0:vbr + 0x1F9] != want: e.append('boot record $1F0: %s' % img[vbr + 0x1F0:vbr + 0x1F9].hex())
    if img[vbr + 0x1FE:vbr + 0x200] != b'\x55\xaa': e.append('boot record signature %s' % img[vbr + 0x1FE:vbr + 0x200].hex())
    report('F with a clock: the clock\'s registers in the boot record at $1F0 (signature kept)', e)

    P1.add_system(cf)
    st, t = session(cf, [b'DISKINFO\r', b'DISKINFO -Q\r', b'VER\r'])
    if '-v' in sys.argv: print(t[t.find('DISKINFO'):])
    e = []
    if st != 'stop': e.append('the end: %s' % st)
    if formatted(t) != ['2026-11-16 14:30'] * 2: e.append('Formatted: %r' % formatted(t))
    tm, dt = struct.unpack_from('<HH', kimg, ksyms['DATEV'] - 0x300)
    built = '%04d-%02d-%02d %02d:%02d' % (1980 + (dt >> 9), dt >> 5 & 15, dt & 31, tm >> 11, tm >> 5 & 63)
    m = re.search(r'\nBuilt:      (.*)\n', t)
    if not m or m.group(1) != built: e.append('VER Built: %r, want %r' % (m and m.group(1), built))
    if not re.search(r'\nKernel:     \$0300-\$[0-9A-F]{4} \(\d+ bytes\)\nBuilt:      .*\nPrograms:   ', t): e.append('VER: the lines around Built:')
    report('DISKINFO and DISKINFO -Q: Formatted: 2026-11-16 14:30; VER: Built: %s (the kernel\'s DATEV)' % built, e)

    # other clocks' forms, other formatters: the same card, its boot record's bytes changed
    cases = [(bytes([0x06, 54, 11, 16, 9, 5, 0]), '2026-11-16 09:05', 'binary, year from 1972'),
             (bytes([0x00, 0x26, 0x11, 0x16, 0x82, 0x07, 0]), '2026-11-16 14:07', '12-hour, 2 PM'),
             (bytes([0x00, 0x26, 0x11, 0x16, 0x12, 0x45, 0]), '2026-11-16 00:45', '12-hour, 12 AM'),
             (bytes([0x00, 0x26, 0x11, 0x16, 0x92, 0x45, 0]), '2026-11-16 12:45', '12-hour, 12 PM'),
             (bytes([0x06, 54, 1, 2, 23, 59, 0]), '2026-01-02 23:59', 'binary, 24-hour, a single-digit month'),
             (bytes([0xFF] * 7), 'not recorded', 'no clock at F ($FF)'),
             (bytes(7), 'not recorded', 'no clock at F (zeros)')]
    e = []
    img = bytearray(V.image(cf, n))
    for regs, want, what in cases:
        img[vbr + 0x1F0:vbr + 0x1F9] = b'FD' + regs
        P1.load_image(cf, bytes(img))
        st, t = session(cf, [b'DISKINFO -Q\r'])
        if formatted(t) != [want]: e.append('%s: %r, want %r' % (what, formatted(t), want))
    img[vbr + 0x1F0:vbr + 0x1F9] = bytes(9)
    P1.load_image(cf, bytes(img))
    st, t = session(cf, [b'DISKINFO -Q\r'])
    if formatted(t) != ['not recorded']: e.append('no FD: %r' % formatted(t))
    report('Formatted: binary, 12-hour (AM, PM, 12 AM, 12 PM), no clock, another formatter', e)

    # F with no clock
    cf, st = install(None)
    img = V.image(cf, n)
    e = []
    if img[vbr + 0x1F0:vbr + 0x1F2] != b'FD' or img[vbr + 0x1F3] not in (0, 0xFF): e.append('no clock: %s' % img[vbr + 0x1F0:vbr + 0x1F9].hex())
    report('F with no clock: what the clock\'s place reads kept (DISKINFO: not recorded)', e)
    print('ALL PASS' if ok else 'FAILED')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
