# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""DOTBOT in Stellar C (examples/dotbot.lst) on the STELLAR firmware V0061.37, as the Elf2K runs it: a UART that holds
ONE byte (an arrow's three bytes back to back), the output replayed through the native DOTBOT test's VT100 model
(reverse video shown as #), Q watched. The same checks as LTOS/verify_atman.py, and its speed:

  * the title; a key: the maze drawn exactly, DOTBOT (@) at his start, the status line
  * steered left (A, then the arrow): dots eaten - gone from the screen, 10 each, Q ticks
  * the Glitches leave the pen one by one and never stand in a wall; every cell on the screen as the maze after
    it (the redraw follows the cursor: a space, BS + ESC [ A / B, or ESC [ r ; c H); a tick's time
  * a Glitch meets him: a life; a power cell: scared (x), 50; a scared one caught: 200, home; the tunnel; the last
    dot: level 2, every dot back
  * a lone Esc: the program ends, the screen cleared, the cursor back, Q off

    python3 SC/dotbot_sc_verify.py [-v]
"""
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math')); sys.path.insert(0, os.path.join(HERE, '..', 'LTOS'))
import opcode_sweep as S
from litewriter2_verify import Clock, TX, UART, BYTE_T
import dotbot_gen
from verify_atman import screen

LST = os.path.join(HERE, 'examples', 'dotbot.lst')
IPS = 170_000                                     # STELLAR's 1802 instructions a second on the Elf2K (3 MHz)


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    sym = json.load(open(LST.replace('.lst', '.sym.json')))
    maze = dotbot_gen.maze()
    clock = Clock()
    c = S.boot(S.image('37'), S.parse_dlines([l for l in open(LST) if l.startswith('D ')]), keys=b'')
    tx = TX(clock); c.io_out[3] = tx
    u = UART(clock, c.io_out[2], tx); c.io_in[3] = u
    M = c.M
    qf = [0]; walls = []; halted = [False]; most_out = [0]
    def run(n, watch=False):
        q = c.Q
        for k in range(n):
            if not c.step() or c.R[c.P] == S.EXIT_IDL + 1: halted[0] = True; return False
            clock.now += 1
            if c.Q != q: qf[0] += 1; q = c.Q
            if watch and k % 20000 == 0:
                most_out[0] = max(most_out[0], sum(1 for i in range(4) if arr('gm', i) == 2))
                for i in range(4):
                    if arr('gm', i) == 2 and maze[arr('gy', i)][arr('gx', i)] == '#': walls.append((i, arr('gx', i), arr('gy', i)))
        return True
    def send(data, gap=None):
        t = clock.now + 50
        for b in data: u.sched.append((t, b)); t += BYTE_T
        u.sched.sort(key=lambda x: x[0])
    def var(n):
        v = sym['vars'][n]
        a = 0x3000 + 2 * v['reg'] if 'reg' in v else v['mem']
        return (M[a] << 8) | M[a + 1]
    def setvar(n, x):
        v = sym['vars'][n]
        a = 0x3000 + 2 * v['reg'] if 'reg' in v else v['mem']
        M[a] = (x >> 8) & 0xFF; M[a + 1] = x & 0xFF
    def arr(n, i=0): return M[sym['arrays'][n] + i]
    def setarr(n, i, x): M[sym['arrays'][n] + i] = x & 0xFF
    def scr(): return screen(bytes(tx).decode('latin1'))
    def text(k): return scr()[k].replace('#', ' ')
    def at(x, y): return scr()[y + 1][2 * x + 3]
    def glitch(k, x, y, d, mode=2, wait=0, scared=0):
        for n, v in (('gx', x), ('gy', y), ('gd', d), ('gm', mode), ('gw', wait), ('gox', x), ('goy', y), ('gs', scared)):
            setarr(n, k, v)
    def all_home():
        for k in range(4): glitch(k, 16 + k if k < 2 else 17 + k, 9, 0, 0, 250)

    run(3_000_000)
    e = []
    if 'D O T B O T' not in ''.join(text(k) for k in range(24)): e.append('no title')
    report('the title', e)

    send(b'x'); run(9_000_000)
    s = scr(); e = []
    bad = [(x, y) for y in range(21) for x in range(37) if (maze[y][x] == '#') != (s[y + 1][2 * x + 3] == '#')]
    if bad: e.append('walls not as the maze at %s' % bad[:5])
    if at(18, 19) != '@': e.append('DOTBOT not at his start: %r' % s[20][30:50])
    if 'SCORE 0' not in text(0) or 'LIVES 3' not in text(0) or 'LEVEL 1' not in text(0): e.append(text(0))
    report('a key: the maze drawn as it is (walls in reverse video), DOTBOT at his start, the status', e)

    # ---- steered left; the time a tick takes
    all_home(); run(200_000)
    sc0, d0, q0, t0, n0 = var('score'), var('dots'), qf[0], var('tnum'), clock.now
    send(b'a'); run(4_000_000)
    send(b'\x1b[D'); run(4_000_000)
    e = []
    ticks = var('tnum') - t0
    per = (clock.now - n0) / max(1, ticks)
    eaten = d0 - var('dots')
    if var('px') > 12: e.append('he is at x %d' % var('px'))
    if eaten < 6 or var('score') - sc0 != 10 * eaten: e.append('%d dots, score %d -> %d' % (eaten, sc0, var('score')))
    if any(at(x, 19) == '.' for x in range(var('px') + 1, 18)): e.append('a dot left behind him: %r' % scr()[20][:60])
    if qf[0] - q0 < 20: e.append('no ticks on Q (%d)' % (qf[0] - q0))
    report('steered left (A, then the arrow): %d dots eaten and gone, 10 each, Q ticks; a tick: %d instructions = %.2f s'
           % (eaten, per, per / IPS), e)

    # ---- the Glitches out, never in a wall
    for k in range(4): glitch(k, 16 + k if k < 2 else 17 + k, 9, 0, 0, 2 + 4 * k)
    setvar('px', 1); setvar('py', 19); setvar('pd', 255); setvar('nd', 255)
    t0, n0 = var('tnum'), clock.now
    run(12_000_000, watch=True)
    e = []
    out = range(most_out[0])                        # (the most seen out: one may catch him at the end, and all go home)
    if most_out[0] < 4: e.append('at most %d out of the pen' % most_out[0])
    if walls: e.append('a Glitch in a wall: %s' % walls[:4])
    per = (clock.now - n0) / max(1, var('tnum') - t0)
    g0 = sym['arrays']['grid']; pieces = {(var('px'), var('py'))} | {(arr('gx', k), arr('gy', k)) for k in range(4)}
    wrong = [(x, y) for y in range(21) for x in range(37) if (x, y) not in pieces
             and at(x, y) != chr(M[g0 + 37 * y + x])]
    if wrong: e.append('the screen not as the maze (the short cursor moves): %s' % wrong[:5])
    report('the Glitches leave the pen (%d out), never in a wall; with all four out a tick is %d instructions = %.2f s'
           % (len(out), per, per / IPS), e)

    # ---- caught
    all_home(); run(300_000)
    lives0 = var('lives')
    setvar('px', 6); setvar('py', 19); setvar('pd', 255); setvar('nd', 255)
    glitch(0, 8, 19, 1)
    run(4_000_000)
    e = []
    if var('lives') != lives0 - 1: e.append('lives %d' % var('lives'))
    report('a Glitch comes to him: a life lost (%d left)' % var('lives'), e)

    # ---- a power cell; a scared one caught
    run(8_000_000); all_home(); run(300_000)
    setvar('px', 1); setvar('py', 3); setvar('pd', 0); setvar('nd', 0)
    glitch(0, 9, 1, 1)
    sc0 = var('score')
    run(1_000_000)
    e = []
    if not var('scaret'): e.append('not scared')
    if arr('gs', 0) != 1: e.append('Glitch 0 not scared')
    if var('score') - sc0 < 50: e.append('score %d -> %d' % (sc0, var('score')))
    seen = False                                    # (its next move: drawn as x - looked for as it runs: he may
    for _ in range(16):                             #  catch it soon after)
        run(50_000)
        if 'x' in ''.join(scr()[1:22]): seen = True; break
    if not seen: e.append('no x on the screen')
    report('a power cell: the Glitches out turn scared (x), 50 points', e)
    all_home()
    setvar('px', 10); setvar('py', 3); setvar('pd', 3); setvar('nd', 3)
    glitch(0, 12, 3, 1, scared=1); setvar('scaret', 40)
    sc0, lives0 = var('score'), var('lives')
    run(1_000_000)                                  # (before its wait in the pen is over)
    e = []
    if arr('gm', 0) != 0: e.append('Glitch 0 not home')
    if var('score') - sc0 < 200: e.append('score %d -> %d' % (sc0, var('score')))
    if var('lives') != lives0: e.append('a life lost')
    report('a scared Glitch caught: 200 points, home to the pen', e)

    # ---- the tunnel
    all_home(); setvar('scaret', 0)
    setvar('px', 1); setvar('py', 9); setvar('pd', 1); setvar('nd', 1)
    run(3_000_000)
    e = []
    if var('px') < 30: e.append('x %d' % var('px'))
    report('the tunnel: out at the left, in at the right (x %d)' % var('px'), e)

    # ---- the last dot: level 2
    all_home()
    g0 = sym['arrays']['grid']
    for i in range(777):
        if M[g0 + i] in (ord('.'), ord('o')): M[g0 + i] = ord(' ')
    M[g0 + 3 * 37 + 5] = ord('.')
    setvar('dots', 1)
    setvar('px', 3); setvar('py', 3); setvar('pd', 3); setvar('nd', 3)
    run(25_000_000)
    e = []
    if var('level') != 2: e.append('level %d' % var('level'))
    if var('dots') < 360: e.append('the dots not back: %d' % var('dots'))
    report('the last dot: a fanfare, level 2, every dot back (%d)' % var('dots'), e)

    # ---- Esc alone
    send(b'\x1b'); run(4_000_000)
    t = bytes(tx).decode('latin1'); e = []
    if not halted[0]: e.append('did not end')
    if not t.endswith('\x1b[0m\x1b[?25h\x1b[2J\x1b[H'): e.append('the end: %r' % t[-30:])
    if c.Q: e.append('Q left on')
    report('a lone Esc: the program ends, the screen cleared, the cursor back, Q off', e)
    if '-v' in sys.argv: print('\n'.join(scr()))
    print('\nDOTBOT (Stellar C): %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
