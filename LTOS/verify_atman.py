# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""AT-MAN (AT-MAN.PRG) in the simulator, on the real ROM's UART: keys given at chosen moments, the output replayed
through a small VT100 model (reverse video shown as #), Q watched for the sounds.

  * the title; a key: the maze drawn exactly (walls, dots, power cells), AT-MAN (@) at his start
  * steered (A, then the arrow ESC [ D): he eats the dots - gone from the screen, 10 each, Q ticks
  * the Glitches leave the pen one by one, and never stand in a wall
  * a Glitch meets him: a life lost; a power cell: the Glitches out turn scared (x), 50; a scared one caught: 200,
    home to the pen; the tunnel takes him across; the last dot: a fanfare, level 2 with every dot back
  * an arrow never quits; a lone Esc does - the screen cleared, the cursor back, Q off

    python3 LTOS/verify_atman.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import build, atman_gen
from verify_cosmo import ScriptUART


def screen(t):
    """24 rows x 80 as the VT100 shows them; a reverse-video space as #."""
    g = [[' '] * 81 for _ in range(25)]; r = c = 1; rev = False
    for m in re.finditer(r'\x1b\[([0-9;?]*)([A-Za-z])|(.)', t, re.S):
        if m.group(3) is not None:
            ch = m.group(3)
            if ch == '\b': c = max(1, c - 1)
            elif ch not in '\r\n':
                if 1 <= r <= 24 and 1 <= c <= 80: g[r][c] = '#' if rev and ch == ' ' else ch
                c += 1
        else:
            a, k = m.group(1), m.group(2)
            if k == 'H':
                p = a.split(';') if a else ['1', '1']; r, c = int(p[0]), int(p[1] if len(p) > 1 and p[1] else 1)
            elif k in 'ABCD':                                  # (the cursor up, down, right, left)
                n = int(a) if a else 1
                if k == 'A': r = max(1, r - n)
                elif k == 'B': r = min(24, r + n)
                elif k == 'C': c = min(80, c + n)
                else: c = max(1, c - n)
            elif k == 'J': g = [[' '] * 81 for _ in range(25)]
            elif k == 'K':                                     # (the line erased from the cursor on)
                for x in range(c, 81): g[r][x] = ' '
            elif k == 'm': rev = a == '7'
    return [''.join(row[1:]) for row in g[1:]]          # [0] = row 1


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    maze = atman_gen.write()
    m, sy = build.assemble('atman')

    class CF:
        present = True; disk = {}; log = []
        def sector(s, n): return bytes(512)
    b = V.Elf2K(CF(), keys=b'', later=[])
    u = ScriptUART(); b.u = u
    for a, v in m.items(): b.c.M[a] = v
    c, M = b.c, b.c.M
    STUB = V.STUB
    M[STUB:STUB + 4] = bytes([0xD4, 0x30, 0x00, 0x00])
    c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[6] = STUB; c.R[3] = 0xFF3F; c.P = 3
    qflips = [0]; walls_hit = []
    def g(k): return M[sy['GS'] + 8 * k: sy['GS'] + 8 * k + 8]
    def run(n, watch=False):
        q = c.Q
        for i in range(n):
            if not c.step(): return 'idle'
            b.steps += 1
            if c.Q != q: qflips[0] += 1; q = c.Q
            if watch and i % 20000 == 0:
                for k in range(4):
                    x, y, d, mode = g(k)[:4]
                    if mode == 2 and maze[y][x] == '#': walls_hit.append((k, x, y))
        return 'run'
    def scr(): return screen(b.text())
    def text(k): return scr()[k].replace('#', ' ')         # (reverse-video text: its spaces read as spaces)
    def v(name, k=0): return M[sy[name] + k]
    def setv(name, val, k=0): M[sy[name] + k] = val & 0xFF
    def score(): return v('SCORE') * 256 + v('SCORE', 1)
    def dots(): return v('DOTS') * 256 + v('DOTS', 1)
    def at(x, y): return scr()[y + 1][2 * x + 3]           # (the screen's character at cell x, y)
    def glitch(k, x, y, d, mode=2, wait=0, scared=0):
        M[sy['GS'] + 8 * k: sy['GS'] + 8 * k + 8] = bytes([x, y, d, mode, wait, x, y, scared])
    def all_home():                                         # (every Glitch in the pen, waiting long)
        for k in range(4): glitch(k, 16 + k, 9, 0, 0, 250)

    run(300_000)
    e = []
    if 'A T - M A N' not in ''.join(text(k) for k in range(24)): e.append('no title')
    report('the title', e)

    u.type(b.steps + 1000, b'x')
    run(2_500_000)
    s = scr(); e = []
    bad = [(x, y) for y in range(21) for x in range(37) if (maze[y][x] == '#') != (s[y + 1][2 * x + 3] == '#')]
    if bad: e.append('walls not as the maze at %s' % bad[:5])
    dotsbad = [(x, y) for y in range(21) for x in range(37) if maze[y][x] in '.o' and s[y + 1][2 * x + 3] != maze[y][x]
               and (x, y) != (v('PX'), v('PY'))]
    if len(dotsbad) > 6: e.append('dots not drawn: %s' % dotsbad[:5])
    if at(18, 19) != '@': e.append('AT-MAN not at his start: %r' % s[20][30:50])
    if 'SCORE 00000' not in text(0) or 'LIVES 3' not in text(0) or 'LEVEL 001' not in text(0): e.append(text(0))
    report('a key: the maze drawn as it is (walls in reverse video, dots, power cells), AT-MAN at his start, the status', e)

    # ---- steered left along the bottom: dots eaten
    all_home()
    sc0, d0, q0 = score(), dots(), qflips[0]
    u.type(b.steps + 1000, b'a')
    run(1_500_000)
    u.type(b.steps + 1000, b'\x1b[D', gap=60)
    run(1_500_000)
    e = []
    eaten = (d0 - dots())
    if v('PX') > 12: e.append('he is at x %d' % v('PX'))
    if eaten < 6 or score() - sc0 != 10 * eaten: e.append('%d dots, score %d -> %d' % (eaten, sc0, score()))
    if any(at(x, 19) == '.' for x in range(v('PX') + 1, 18)): e.append('a dot left behind him: %r' % scr()[20][:60])
    if qflips[0] - q0 < 20: e.append('no ticks on Q (%d)' % (qflips[0] - q0))
    if v('ES'): e.append('the arrow left ES = %d' % v('ES'))
    report('steered left (A, then the arrow): %d dots eaten and gone, 10 each, Q ticks' % eaten, e)

    # ---- the Glitches leave the pen, and stay out of the walls
    for k in range(4): glitch(k, 16 + k, 9, 0, 0, 2 + 6 * k)
    setv('PX', 1); setv('PY', 19); setv('PD', 0xFF); setv('ND', 0xFF)
    run(3_000_000, watch=True)
    e = []
    out = [k for k in range(4) if g(k)[3] == 2]
    if len(out) < 4: e.append('out of the pen: %s' % out)
    if walls_hit: e.append('a Glitch in a wall: %s' % walls_hit[:4])
    report('the Glitches leave the pen one by one (%d out), and never stand in a wall' % len(out), e)

    # ---- caught: a Glitch on him
    all_home(); run(200_000)
    lives0 = v('LIVES')
    setv('PX', 6); setv('PY', 19); setv('PD', 0xFF); setv('ND', 0xFF)
    glitch(0, 8, 19, 1)                                     # two cells right of him, coming left
    run(800_000)
    e = []
    if v('LIVES') != lives0 - 1: e.append('lives %d' % v('LIVES'))
    if 'LIVES %d' % (lives0 - 1) not in text(0): e.append(text(0))
    report('a Glitch comes to him: a life lost (LIVES %d), back at the starts' % v('LIVES'), e)

    # ---- a power cell: scared; a scared one caught
    run(1_500_000); all_home(); run(200_000)
    setv('PX', 1); setv('PY', 3); setv('PD', 0); setv('ND', 0)  # going up to the power cell at (1, 2)
    glitch(0, 9, 1, 1)                                      # out in the maze, top left
    sc0 = score()
    run(300_000)
    e = []
    if not v('SCARET'): e.append('not scared')
    if g(0)[7] != 1: e.append('Glitch 0 not scared')
    if score() - sc0 < 50: e.append('score %d -> %d' % (sc0, score()))
    run(300_000)
    if 'x' not in ''.join(scr()[1:22]): e.append('no x on the screen')
    report('a power cell: the Glitches out turn scared (x), 50 points', e)
    all_home()
    setv('PX', 10); setv('PY', 3); setv('PD', 3); setv('ND', 3)
    glitch(0, 12, 3, 1, scared=1); setv('SCARET', 40)
    sc0 = score(); lives0 = v('LIVES')
    run(600_000)
    e = []
    if g(0)[3] != 0: e.append('Glitch 0 not home (mode %d)' % g(0)[3])
    if score() - sc0 < 200: e.append('score %d -> %d' % (sc0, score()))
    if v('LIVES') != lives0: e.append('a life lost')
    report('a scared Glitch caught: 200 points, home to the pen', e)

    # ---- the tunnel
    all_home(); setv('SCARET', 0)
    setv('PX', 1); setv('PY', 9); setv('PD', 1); setv('ND', 1)
    run(500_000)
    e = []
    if v('PX') < 30: e.append('x %d' % v('PX'))
    report('the tunnel: out at the left, in at the right (x %d)' % v('PX'), e)

    # ---- the last dot: level 2
    all_home()
    for y in range(21):
        for x in range(37):
            a = sy['GRID'] + y * 37 + x
            if M[a] in (ord('.'), ord('o')): M[a] = ord(' ')
    M[sy['GRID'] + 3 * 37 + 5] = ord('.')
    setv('DOTS', 0); setv('DOTS', 1, 1)
    setv('PX', 3); setv('PY', 3); setv('PD', 3); setv('ND', 3)
    q0 = qflips[0]
    run(6_000_000)
    e = []
    if v('LEVEL') != 2 or 'LEVEL 002' not in text(0): e.append('level %d, %r' % (v('LEVEL'), text(0)))
    if dots() < 360: e.append('the dots not back: %d' % dots())
    if qflips[0] - q0 < 300: e.append('no fanfare (%d)' % (qflips[0] - q0))
    report('the last dot: a fanfare, level 2, every dot back (%d)' % dots(), e)

    # ---- Esc alone
    u.type(b.steps + 2000, b'\x1b')
    st = run(3_000_000)
    t = b.text(); e = []
    if st != 'idle': e.append('did not end')
    if not t.endswith('\x1b[0m\x1b[?25h\x1b[2J\x1b[H'): e.append('the end: %r' % t[-30:])
    if c.Q: e.append('Q left on')
    report('a lone Esc: the game ends - the screen cleared, the cursor back, Q off', e)
    if '-v' in sys.argv: print('\n'.join(scr()))
    print('%d instructions, %d bytes sent, program $%04X-$%04X' % (b.steps, len(t), min(m), max(m)))
    print('\nAT-MAN: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
