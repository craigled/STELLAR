# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""COSMO KID (COSMO.PRG) in the simulator, on the real ROM's UART: keys given at chosen moments, the output replayed
through a small VT100 model (the screen as the terminal shows it), Q watched for the sounds.

  * the title; a key: world 1-1 drawn - the status line, the map, Cosmo (o over A) where S is
  * held right (D, and the arrow ESC [ C): he walks; the coins on his way taken - COINS and SCORE up, gone from the
    screen; Q sounds the blips
  * a jump (Space): he rises, then comes down again to the ground
  * stomp: dropped onto a Blorb, it is gone and 100 points; a Blorb at his side, a pit: a life each
  * off the right edge: world 1-2; at the portal: world 2-1
  * an arrow never quits; a lone Esc does - the screen cleared, the cursor back

    python3 LTOS/verify_cosmo.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import build, cosmo_gen


class ScriptUART(V.UART):
    """Keys given at chosen moments (in the 1802's instructions)."""
    def __init__(s):
        super().__init__(b'', []); s.keys = []
    def feed_timed(s): s.timed = 1; return True
    def ready(s): return bool(s.keys) and s.keys[0][0] <= s.now
    def read(s):
        if s.ready(): return s.keys.pop(0)[1]
        return 0
    def type(s, at, data, gap=4000):
        for k, ch in enumerate(data): s.keys.append((at + k * gap, ch))
        s.keys.sort()


def screen(t):
    """24 rows x 80 as the VT100 shows them (only what COSMO sends: CUP, ED 2, SGR, ?25)."""
    g = [[' '] * 81 for _ in range(25)]; r = c = 1
    for m in re.finditer(r'\x1b\[([0-9;?]*)([A-Za-z])|(.)', t, re.S):
        if m.group(3) is not None:
            ch = m.group(3)
            if ch not in '\r\n':
                if 1 <= r <= 24 and 1 <= c <= 80: g[r][c] = ch
                c += 1
        else:
            a, k = m.group(1), m.group(2)
            if k == 'H':
                p = a.split(';') if a else ['1', '1']; r, c = int(p[0]), int(p[1] if len(p) > 1 and p[1] else 1)
            elif k == 'J': g = [[' '] * 81 for _ in range(25)]
    return [''.join(row[1:]) for row in g[1:]]          # [0] = row 1


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    cosmo_gen.write()
    m, sy = build.assemble('cosmo')

    class CF:
        present = True; disk = {}; log = []
        def sector(s, n): return bytes(512)
    b = V.Elf2K(CF(), keys=b'', later=[])
    u = ScriptUART(); b.u = u
    for a, v in m.items(): b.c.M[a] = v
    c, M = b.c, b.c.M
    # the monitor's CALL 3000 (as Elf2K.call), run here in pieces
    STUB = V.STUB
    M[STUB:STUB + 4] = bytes([0xD4, 0x30, 0x00, 0x00])
    c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[6] = STUB; c.R[3] = 0xFF3F; c.P = 3
    qflips = [0]
    def run(n):
        """n instructions, Q's changes counted -> 'idle' if it ended"""
        q = c.Q
        for _ in range(n):
            if not c.step(): return 'idle'
            b.steps += 1
            if c.Q != q: qflips[0] += 1; q = c.Q
        return 'run'
    def scr(): return screen(b.text())
    def v(name, k=0): return M[sy[name] + k]
    def setv(name, val, k=0): M[sy[name] + k] = val & 0xFF
    def status(): return scr()[0]

    run(300_000)
    e = []
    s = scr()
    if 'C O S M O   K I D' not in '\n'.join(s): e.append('no title: %r' % s[5:8])
    report('the title', e)

    u.type(b.steps + 1000, b'x')
    run(1_500_000)
    s = scr(); e = []
    if 'COSMO KID' not in s[0] or 'SCORE 00000' not in s[0] or 'WORLD 1-1' not in s[0]: e.append('status: %r' % s[0])
    g = cosmo_gen.WORLDS[0][0]
    if s[20][3] != 'A' or s[19][3] != 'o': e.append('Cosmo not at S (row 21, col 4): %r %r' % (s[19][:8], s[20][:8]))
    if s[21][:79] != ''.join(g[20]): e.append('the ground: %r' % s[21][:40])
    if v('PR') != 19 or v('PC') != 4: e.append('PR, PC = %d, %d' % (v('PR'), v('PC')))
    report('a key: world 1-1 - the status line, the map, Cosmo (o over A) where S is', e)

    def no_blorbs():                                    # (the ones walking at him: for the checks not about them)
        for k in range(8): M[sy['ENS'] + 5 * k] = 0
    # ---- walk right (D held: a key every 3 frames or so), over the coins at row 19, cols 12-20
    no_blorbs(); run(100_000)
    q0 = qflips[0]; c0 = v('PC')
    for k in range(5): u.type(b.steps + 2000 + k * 60_000, b'd')                       # (short of the Blorb at col 41)
    for k in range(2): u.type(b.steps + 2000 + (5 + k) * 60_000, b'\x1b[C', gap=60)      # an arrow's 3 bytes together
    run(800_000)
    s = scr(); e = []
    if v('PC') < c0 + 10: e.append('he walked only to col %d' % v('PC'))
    if v('COINS') < 4: e.append('coins %d' % v('COINS'))
    if 'COINS %03d' % v('COINS') not in s[0]: e.append('the status: %r' % s[0])
    if '$' in s[20][11:v('PC') - 1]: e.append('a coin still there: %r' % s[20][10:24])
    if qflips[0] - q0 < 100: e.append('no sound: Q changed %d times' % (qflips[0] - q0))
    if v('ES') != 0: e.append('the arrow left ES = %d' % v('ES'))
    report('walking right (D, then the arrow): to col %d, %d coins taken and gone, COINS and SCORE shown, Q blips (%d changes)'
           % (v('PC'), v('COINS'), qflips[0] - q0), e)

    # ---- a jump: up, then down again
    no_blorbs(); run(100_000)
    row0 = v('PR'); low = row0
    u.type(b.steps + 1000, b' ')
    for _ in range(40):
        run(20_000); low = min(low, v('PR'))
    run(400_000)
    e = []
    if row0 - low < 4: e.append('rose only %d rows' % (row0 - low))
    if v('PR') != row0 or not v('ONG'): e.append('not back down: row %d, on the ground %d' % (v('PR'), v('ONG')))
    report('a jump (Space): up %d rows, then back down to the ground' % (row0 - low), e)

    # ---- a stomp: Cosmo above a Blorb, falling onto it
    base = sy['ENS']
    pc = v('PC')
    for k in range(5 * 8): M[base + k] = 0
    def cell(r, col): return sy['MAP'] + r * 79 + col - 1
    M[cell(19, pc - 1)] = M[cell(19, pc + 1)] = ord('#')     # (boxed in: it stays under him)
    M[base:base + 5] = bytes([1, 19, pc, 1, pc])            # a Blorb on the ground under him
    setv('PR', 15); setv('JT', 0); setv('ONG', 0); setv('RUNT', 0)
    sc0 = v('SCORE') * 256 + v('SCORE', 1); lives0 = v('LIVES')
    run(500_000)
    e = []
    sc = v('SCORE') * 256 + v('SCORE', 1)
    if M[base] != 0: e.append('the Blorb is alive')
    if sc - sc0 < 100: e.append('score %d -> %d' % (sc0, sc))
    if v('LIVES') != lives0: e.append('a life lost')
    if '&' in ''.join(scr()[1:23]): e.append('a Blorb still on the screen')
    no_blorbs()
    report('a stomp: dropped onto a Blorb - gone from the screen, +100, no life lost', e)

    # ---- a Blorb at his side: a life
    pr, pc = v('PR'), v('PC')
    M[cell(pr, pc - 1)] = M[cell(pr, pc + 1)] = ord('#')
    M[base:base + 5] = bytes([1, pr, pc, 0xFF, pc])          # right on his feet's cell, him not falling
    run(300_000)
    e = []
    if v('LIVES') != lives0 - 1: e.append('lives %d' % v('LIVES'))
    if 'LIVES %d' % (lives0 - 1) not in scr()[0]: e.append(scr()[0])
    report('a Blorb at his side: a life lost (LIVES %d), back where the screen was entered' % v('LIVES'), e)

    # ---- off the right edge: world 1-2
    run(300_000)
    no_blorbs()
    setv('PR', 19); setv('PC', 79); setv('JT', 0)
    for k in range(4): u.type(b.steps + 2000 + k * 50_000, b'd')
    run(1_500_000)
    e = []
    if v('ROOMN') != 1 or 'WORLD 1-2' not in scr()[0]: e.append('room %d, %r' % (v('ROOMN'), scr()[0]))
    g = cosmo_gen.WORLDS[0][1]
    if scr()[21][:79] != ''.join(g[20]): e.append('not 1-2\'s ground: %r' % scr()[21][:60])
    if e and '-v' in sys.argv: print('\n'.join(scr())); print(v('PR'), v('PC'), v('LIVES'))
    report('off the right edge: world 1-2 drawn', e)

    # ---- a pit (1-2 has one at cols 23-26): a life
    lives1 = v('LIVES'); no_blorbs()
    setv('PR', 15); setv('PC', 25); setv('JT', 0); setv('ONG', 0)
    run(800_000)
    e = []
    if v('LIVES') != lives1 - 1: e.append('lives %d (was %d)' % (v('LIVES'), lives1))
    report('into a pit: a life lost', e)

    # ---- the portal: 1-3's ( ) at cols 73-74; world 2
    setv('ROOMN', 2); setv('LIVES', 3)
    run(100_000)
    setv('PR', 19); setv('PC', 79); setv('JT', 0)
    setv('ROOMN', 1)
    for k in range(4): u.type(b.steps + 2000 + k * 50_000, b'd')
    run(1_500_000)                                                   # into 1-3 at col 1
    no_blorbs()
    setv('PR', 19); setv('PC', 72); setv('JT', 0)
    q0 = qflips[0]
    for k in range(3): u.type(b.steps + 2000 + k * 50_000, b'd')
    run(4_000_000)
    e = []
    if v('WORLD') != 1 or 'WORLD 2-1' not in scr()[0]: e.append('world %d, %r' % (v('WORLD'), scr()[0]))
    if qflips[0] - q0 < 200: e.append('no fanfare (Q changed %d times)' % (qflips[0] - q0))
    report('at the portal: a fanfare, world 2-1', e)

    # ---- Esc alone: quits
    u.type(b.steps + 2000, b'\x1b')
    st = run(3_000_000)
    t = b.text(); e = []
    if st != 'idle': e.append('did not end')
    if not t.endswith('\x1b[0m\x1b[?25h\x1b[2J\x1b[H'): e.append('the end: %r' % t[-30:])
    if c.Q: e.append('Q left on')
    report('a lone Esc: the game ends - the screen cleared, the cursor back, Q off', e)
    if '-v' in sys.argv: print('\n'.join(scr()))
    print('%d instructions, %d bytes sent, program $%04X-$%04X' % (b.steps, len(t), min(m), max(m)))
    print('\nCOSMO: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
