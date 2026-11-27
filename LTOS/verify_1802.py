# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""1802.PRG in the simulator: a raw 1802 program (NAME.BIN, no header) run on the bare machine.

  * 1802 T1: the file at $0000, started as a reset leaves the 1802 - R0 the PC, X = P = 0, IE = 1, Q off;
    R1 = the ROM's breakpoint entry (v120: $8F53); the program runs to its IDL;
  * a file in pieces (its clusters apart): every sector where it belongs; 12 KB from $0000 (all of $0000-$2FFF);
    18.5 KB at $3400 started at $7DF5 (an LBR at $0000, P still 0); lower case, .BIN left off or typed;
  * -Z (before the name or after it, either case): $0000-$2FFF and $3400-$7EFF all 00 but the program (and
    the LBR) - MON's stub at $3000-$33FF left as it is;
  * R1.BIN in /BIN/RAW: run by its path (a name alone is looked for only here, as PLAY does);
  * refused, LTOS goes on: too big, outside $0000-$2FFF / $3400-$7EFF, empty, no such file, a start that
    is not $0000 with $0000-$0002 loaded, more on the line, nothing on the line.

    python3 LTOS/verify_1802.py [-v]
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

BRK = 0x8F53                    # the monitor's breakpoint entry in ROM v120 (stellar.asm; verify_phase4)
CAP = 900_000_000


def prog(at, mark, n):
    """At `at`: R7 = $1000 + n, M(R7) = mark, SEQ, IDL."""
    return bytes([0xF8, 0x10, 0xB7, 0xF8, n, 0xA7, 0xF8, mark, 0x57, 0x7B, 0x00])


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    t1 = prog(0, 0xAA, 0)                                           # 11 bytes, at $0000
    t2 = bytearray(1600); t2[0:3] = b'\xC0\x05\xF0'; t2[0x5F0:0x5FB] = prog(0x5F0, 0xBB, 1)   # 4 sectors
    t3 = prog(0x5000, 0xCC, 2)                                      # for $5000
    t4 = bytearray(0x3000); t4[0:3] = b'\xC0\x2F\xF0'; t4[0x2FF0:0x2FFB] = prog(0x2FF0, 0xDD, 3)  # 12 KB
    t6 = bytearray(37 * 512); t6[-11:] = prog(0x7DF5, 0xEE, 4)      # 18.5 KB for $3400, its code at $7DF5
    files = {'T1.BIN': t1, 'T2.BIN': bytes(t2), 'T3.BIN': t3, 'T4.BIN': bytes(t4), 'T6.BIN': bytes(t6),
             'T5.BIN': bytes(0x3001), 'T7.BIN': bytes(37 * 512 + 1), 'EMPTY.BIN': b''}
    r1 = prog(0, 0x99, 5)                                           # in /BIN/RAW: found by its path
    def card():
        cf, e2k, st = P1.installed_full(mem, 16384)
        def put(m):
            for n, d in files.items(): open(os.path.join(m, n), 'wb').write(d)
            os.makedirs(os.path.join(m, 'BIN', 'RAW'), exist_ok=True)
            open(os.path.join(m, 'BIN', 'RAW', 'R1.BIN'), 'wb').write(r1)
        img, _ = P2.mac(V.image(cf, 16384), put)
        img = P2.fragment(img, b'T2      BIN')                     # T2's second cluster far from its first
        img = P2.fragment(img, b'T4      BIN')
        P1.load_image(cf, img)
        return cf

    # ---- each one runs to its IDL, started as a reset would start it
    for keys, n, mark, start, rng in ((b'1802 T1\r', 0, 0xAA, 0x0000, (0x0000, t1)),
                                      (b'1802 t2\r', 1, 0xBB, 0x0000, (0x0000, bytes(t2))),
                                      (b'1802 T3.bin 5000\r', 2, 0xCC, 0x5000, (0x5000, t3)),
                                      (b'1802 T4\r', 3, 0xDD, 0x0000, (0x0000, bytes(t4))),
                                      (b'1802 T6 3400 7DF5\r', 4, 0xEE, 0x7DF5, (0x3400, bytes(t6))),
                                      (b'1802 -Z T1\r', 0, 0xAA, 0x0000, (0x0000, t1)),
                                      (b'1802 T3 5000 -z\r', 2, 0xCC, 0x5000, (0x5000, t3)),
                                      (b'1802 -Z T6 3400 7DF5\r', 4, 0xEE, 0x7DF5, (0x3400, bytes(t6))),
                                      (b'1802 /BIN/RAW/R1.BIN\r', 5, 0x99, 0x0000, (0x0000, r1))):
        how = keys.decode().strip()
        cf = card()
        b = V.Elf2K(cf, keys=keys); b.rtc = P3.clock(); c = b.c
        c.M[0x1000:0x1008] = bytes(8)
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3     # the monitor's BOOT
        st = b.run(CAP, stop=0x0000)                                 # (BOOT's own code never runs at $0000)
        e = []
        if st != 'stop' or c.P != 0 or c.X != 0: e.append('not started as a reset (%s, P=%X X=%X)' % (st, c.P, c.X))
        if c.R[1] != BRK: e.append('R1 = %04X, not $%04X' % (c.R[1], BRK))
        if c.Q: e.append('Q is on')
        if getattr(c, 'IE', 1) != 1: e.append('IE = %r' % c.IE)
        a, d = rng
        if bytes(c.M[a:a + len(d)]) != d: e.append('$%04X-$%04X is not the file' % (a, a + len(d) - 1))
        if start and bytes(c.M[0:3]) != bytes([0xC0, start >> 8, start & 0xFF]): e.append('no LBR at $0000: %s' % bytes(c.M[0:3]).hex())
        if 'Starting ' not in b.text() or 'oading ... done.' not in b.text(): e.append(repr(b.text()[-300:]))
        if b'-' in keys:                                            # -Z: nothing else left but 00
            end = a + (len(d) + 511) // 512 * 512
            dirty = [x for x in list(range(0, 0x3000)) + list(range(0x3400, 0x7F00))
                     if c.M[x] and not (a <= x < end) and not (start and x < 3)]
            if dirty: e.append('-Z: not 00 at %s' % ' '.join('%04X' % x for x in dirty[:8]))
            if 'Clearing RAM, then loading ... done.' not in b.text(): e.append('-Z: %r' % b.text()[-200:])
        st = b.run(CAP)
        if st != 'idle' or c.M[0x1000 + n] != mark or not c.Q: e.append('it did not run to its IDL (%s, M=%02X)' % (st, c.M[0x1000 + n]))
        if '-v' in sys.argv: print(b.text()[-400:])
        report('%s: loaded through its FAT chain, started with R0 = $0000, X = P = 0, IE = 1, Q off, R1 = the '
               'breakpoint entry; it runs to its IDL' % how, e)

    # ---- refused: LTOS goes on
    cf = card()
    tries = ((b'1802 T5', 'It must go in $0000-$2FFF or $3400-$7EFF'),
             (b'1802 T7 3400', 'T7.BIN is too big'),
             (b'1802 T1 2F00', 'It must go in $0000-$2FFF or $3400-$7EFF'),
             (b'1802 T1 3300', 'It must go in $0000-$2FFF or $3400-$7EFF'),
             (b'1802 T1 7E00', 'It must go in $0000-$2FFF or $3400-$7EFF'),
             (b'1802 T1 0 100', 'needs $0000-$0002 free'),
             (b'1802 EMPTY', 'EMPTY.BIN is empty.'),
             (b'1802 NOSUCH', 'There is no file NOSUCH.BIN'),
             (b'1802 /BIN/R1', 'There is no file R1.BIN'),                # a path: only there (R1 is in /BIN/RAW)
             (b'1802 R1', 'There is no file R1.BIN'),                     # a name alone: only here (the root)
             (b'1802 T1 1 2 3', 'Usage: 1802 [-Z] name [load [start]]'),
             (b'1802', 'Usage: 1802 [-Z] name [load [start]]'),
             (b'1802 -Z', 'Usage: 1802 [-Z] name [load [start]]'),
             (b'1802 -X T1', 'Usage: 1802 [-Z] name [load [start]]'))
    b, st, t = P3.session(cf, b''.join(k + b'\r' for k, w in tries) + b'MON\r', rtc=P3.clock())
    e = []
    for k, w in tries:
        o = P2.session_out(t, k.decode() + '\r')
        if w not in o: e.append('%s: %r' % (k.decode(), o))
    if st != 'stop': e.append('MON: %s' % st)
    if '-v' in sys.argv: print(t[-1500:])
    report('refused, LTOS goes on: too big, outside the two areas, a start whose LBR would hit the program, empty, '
           'no such file, a path or a name alone looked for only there, more on the line, nothing on the line, -Z alone, another option', e)
    print('1802: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
