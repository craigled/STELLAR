#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/morse_gen.py - MORSE.PRG's tables -> morsetab.inc, from Firmware-Math/morse_table.py (the table the STELLAR
Morse Sender v18 and Receiver v11 use, so they all agree).     python3 LTOS/morse_gen.py

STBL: 64 bytes, ASCII $20-$5F: each character's LEADING-1 code (start at 1; for each element x 2, + 1 for a dash:
A .- = %101), 0 = no Morse for it.  RTBL: 128 bytes indexed by that code: the character, 0 = none.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import morse_table as MT


def main():
    stbl = bytearray(64)
    for ch, pat in MT.MORSE.items():
        stbl[ord(ch) - 0x20] = MT.code(pat)
    rtbl = MT.recv_table()
    out = ['; morsetab.inc - made by morse_gen.py from Firmware-Math/morse_table.py: do not edit.', 'STBL:']
    for i in range(0, 64, 16):
        out.append('        DB      ' + ', '.join('0%02XH' % b for b in stbl[i:i + 16]) + '    ; ' +
                   ''.join(chr(0x20 + i + k) for k in range(16)))
    out.append('RTBL:')
    for i in range(0, 128, 16):
        out.append('        DB      ' + ', '.join('0%02XH' % b for b in rtbl[i:i + 16]))
    open(os.path.join(HERE, 'morsetab.inc'), 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
