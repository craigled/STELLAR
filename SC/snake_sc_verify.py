# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the hand-written Snake's verifier (Firmware-Math/snake_verify.py) against the
Stellar C build (examples/snake.lst) - the same 7 tests, unchanged.

The verifier reads the game's state by register number and memory offset; this shim
answers those from the compiler's symbol map instead (examples/snake.sym.json).

    python3 snake_sc_verify.py
"""
import os, sys, json, types
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import opcode_sweep as S
import build_snake as HAND
import snake_verify as V

LST = os.path.join(HERE, 'examples', 'snake.lst')
SYM = json.load(open(os.path.join(HERE, 'examples', 'snake.sym.json')))

B = types.ModuleType('snake_sc')
for k in ('UP', 'DOWN', 'LEFT', 'RIGHT', 'W', 'ROWS', 'COLS', 'FOOD', 'LEN0', 'GROW',
          'TOPW', 'BOTW', 'LEFTW', 'RIGHTW', 'ROW0', 'COL0', 'LVLSTEP'):
    setattr(B, k, getattr(HAND, k))
B.LST = LST
B.GB = SYM['arrays']['grid'] - 0x4000 - 240          # grid index = line x 80 + column - 240
B.NEXT = SYM['arrays']['next'] - 0x4000
B.LVL = SYM['arrays']['lvl'] - 0x4000
B.pokes = lambda: S.parse_dlines([l for l in open(LST) if l.startswith('D ')])
V.B = B

# the hand build's registers R1-R9, by name
NAMES = {1: 'hl', 2: 'hc', 3: 'hi', 4: 'tl', 5: 'tc', 6: 'ti', 7: 'dir', 8: 'grow', 9: 'score'}
def reg(g, i):
    v = SYM['vars'][NAMES[i]]
    if 'reg' in v: return (g.c.M[0x3000 + 2 * v['reg']] << 8) | g.c.M[0x3001 + 2 * v['reg']]
    return (g.c.M[v['mem']] << 8) | g.c.M[v['mem'] + 1]
V.Game.reg = reg

if __name__ == '__main__':
    sys.exit(0 if V.main() else 1)
