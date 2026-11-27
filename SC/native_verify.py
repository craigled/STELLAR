# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run examples/nativedemo.lst (the native { } demo) in the simulator on the V0061.37 image (as flashed),
from clean and from dirty memory, and check what it prints.

    python3 asm_verify.py
"""
import os, sys, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import opcode_sweep as S

LST = os.path.join(HERE, 'examples', 'nativedemo.lst')
KEYS = b''
WANT = '19900 = 19900\r\n4DBC\r\nnative!\r\n'

def main():
    img = bytearray(S.image('37'))
    pokes = S.parse_dlines(open(LST))
    ok = True
    for label, fill in (('clean memory', None), ('dirty memory', 1802)):
        m = bytearray(img)
        if fill is not None:
            rng = random.Random(fill)
            for a in range(0x4000, 0x5000): m[a] = rng.randrange(256)
        c = S.boot(bytes(m), pokes, keys=KEYS)
        r = S.run(c)
        good = r['halted'] and r['serial'] == WANT and not r['first_err']
        c2 = S.boot(bytes(c.M), [], keys=KEYS)            # rerun on what the first run left
        r2 = S.run(c2)
        good &= r2['halted'] and r2['serial'] == WANT and not r2['first_err']
        label += ' + rerun'
        ok &= good
        print('%s: %r  halted %s, errors %s: %s' % (label, r['serial'], r['halted'], r['first_err'] or 'none',
                                                   'OK' if good else 'FAIL'))
    return ok

if __name__ == '__main__':
    sys.exit(0 if main() else 1)
