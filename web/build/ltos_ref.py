# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The reference LTOS session for test_ltos.mjs: the baked card (ltos/ltos-card.bin) booted in the Python Elf2K
with the web BIOS (LTOS/verify_webbios.py), these commands typed one at each prompt, and what it printed.

    python3 web/build/ltos_ref.py [path/to/stellar-1802]      -> web/build/ltos-session.json

The JS Elf2K (js/elf2k.js) must print exactly the same text from the same card: test_ltos.mjs.
"""
import os, sys, json, struct
WORK = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Projects/stellar-1802')
LTOS = os.path.join(WORK, 'LTOS')
WEB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, LTOS)
os.chdir(LTOS)
import verify_phase0 as V
import verify_phase3 as P3
import verify_webbios as W

COMMANDS = ['VER', 'DISKINFO', 'DIR', 'DIR /BIN', 'TYPE README.TXT', 'TEST', 'SH -x TEST', 'ECHO hello there > HI.TXT',
            'TYPE HI.TXT', 'TYPE DOCS/SALES.TXT', "RAWK '{ s += $2 } END { print s }' DOCS/SALES.TXT",
            'HELP SCRIPTS', 'ECHO abcd\b\b\bxyz', 'NOPE', 'VER']


def main():
    raw = open(os.path.join(WEB, 'ltos', 'ltos-card.bin'), 'rb').read()
    n, count = struct.unpack('<II', raw[4:12])
    cf = V.CV.CF(sectors=n)
    cf.disk = {}
    for i in range(count):
        p = 12 + i * 516
        cf.disk[struct.unpack('<I', raw[p:p + 4])[0]] = raw[p + 4:p + 516]
    for l in range(n): cf.disk.setdefault(l, bytes(512))                  # (a sector never written: zeros)
    W.WebElf2K.BIOS = W.webbios()
    later = [('LTOS> ', (c + '\r').encode('latin1')) for c in COMMANDS] + [('LTOS> ', b'MON\r')]
    b = W.WebElf2K(cf, later=later); b.rtc = P3.clock()
    c = b.c; c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
    st = b.run(900_000_000, stop=0x8003)
    assert st == 'stop', st
    json.dump({'commands': COMMANDS, 'clock': [26, 10, 16, 14, 30, 20], 'text': b.text()},
              open(os.path.join(WEB, 'build', 'ltos-session.json'), 'w'), indent=0)
    print('ltos-session.json: %d commands, %d characters' % (len(COMMANDS), len(b.text())))


if __name__ == '__main__':
    main()
