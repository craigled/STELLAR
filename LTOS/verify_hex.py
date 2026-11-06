# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""HEX.PRG in the simulator: 18 bytes a line in 80 columns, any size (6-digit offsets from 64 KB), a screen at
a time - space: the next screen, Enter: one more line, Q: stop; a short last line; a file that is empty.

    python3 LTOS/verify_hex.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

PROMPT = '-- space: more, Enter: a line, Q: stop --%s\r' + ' ' * 41 + '\r'      # (the BIOS echoes the key)


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    big = bytes((i * 7 + (i >> 8)) & 0xFF for i in range(70000))
    small = b'Hello, world!\r\n\x00\x01\x7f\xff' + bytes(range(32, 60))      # 47 bytes: 2 full lines + 11
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        open(os.path.join(m, 'BIG.BIN'), 'wb').write(big)
        open(os.path.join(m, 'SMALL.DAT'), 'wb').write(small)
        open(os.path.join(m, 'EMPTY.TXT'), 'wb').write(b'')
    img, _ = P2.mac(V.image(cf, 16384), put)
    P1.load_image(cf, img)
    keys = b'HEX SMALL.DAT\rHEX EMPTY.TXT\rHEX BIG.BIN\r \r\rQHEX\rMON\r'
    b, st, t = P3.session(cf, keys, rtc=P3.clock())
    if '-v' in sys.argv: print(t)
    e = []
    want = ''.join(l + '\r\n' for l in P3.hexdump(small, 'SMALL.DAT'))
    so = lambda c: P2.session_out(t, c).lstrip('\r\n')
    if so('HEX SMALL.DAT\r') != want: e.append('SMALL.DAT: %r' % so('HEX SMALL.DAT\r'))
    if any(len(l) > 79 for l in P3.hexdump(big, 'BIG.BIN')): e.append('a line is wider than 79')
    if so('HEX EMPTY.TXT\r') != 'EMPTY.TXT, 0 bytes\r\n': e.append('EMPTY: %r' % so('HEX EMPTY.TXT\r'))
    o = so('HEX BIG.BIN\r')
    lines = P3.hexdump(big, 'BIG.BIN')
    # the first screen (the name + 21 lines), space: 22 more, Enter: 1 more, Enter: 1 more, Q: stop
    want = ''.join(l + '\r\n' for l in lines[:22]) + PROMPT % ' ' + ''.join(l + '\r\n' for l in lines[22:44]) + \
        PROMPT % '\r' + lines[44] + '\r\n' + PROMPT % '\r' + lines[45] + '\r\n' + PROMPT % 'Q'
    if o != want: e.append('BIG.BIN: %r ... (want %r)' % (o[-300:], want[-300:]))
    if 'HEX name - any file in hex' not in t: e.append('HEX alone: no usage line')
    if st != 'stop': e.append('MON: %s' % st)
    report('HEX: 18 bytes a line (79 columns), a short last line, dots, an empty file; 70,000 bytes: 6-digit '
           'offsets, space - a screen, Enter - a line, Q stops; HEX alone tells how', e)
    print('HEX: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
