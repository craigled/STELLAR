# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""DESCEND (DESCEND.PRG) in the simulator, on the real ROM's UART: keys given at chosen moments, the output replayed
through the VT100 model of verify_atman.py, Q watched for the sounds.

  * the title; levels made from several seeds: nine rooms inside the map, apart; every room, the stairs and every
    monster reachable from him; monsters on open cells, none in his room, none on another; things on floors
  * a key: the status line, him (@), his room shown, the rest of the map blank until seen
  * a step (a key and an arrow), a wall (no turn), a fight to the death of a rat (XP, its letter gone), a monster
    that hits him, gold / a potion / a weapon / armour picked up, a potion drunk, a level up, the stairs down
  * many steps at random: every cell on the screen as he knows the map (seen cells, monsters he sees, him), the
    status line as the numbers are
  * killed: the end screen, a key: the title and a new game; the Star Crystal on depth 10: won; a lone Esc ends it

    python3 LTOS/verify_descend.py [-v]
"""
import os, re, sys, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import build
from verify_cosmo import ScriptUART
from verify_atman import screen

MW, MH, NR, NM, MSZ = 78, 21, 9, 10, 8
LETTERS = 'rbksgoZwTD'
WALK = lambda ch: ch not in ' |-'


class Game:
    def __init__(s, m, sy):
        class CF:
            present = True; disk = {}; log = []
            def sector(s, n): return bytes(512)
        s.b = V.Elf2K(CF(), keys=b'', later=[])
        s.u = ScriptUART(); s.b.u = s.u
        for a, v in m.items(): s.b.c.M[a] = v
        s.c, s.M, s.sy = s.b.c, s.b.c.M, sy
        s.M[V.STUB:V.STUB + 4] = bytes([0xD4, 0x30, 0x00, 0x00])
        s.c.R[2] = 0x7EF0; s.c.X = 2; s.c.R[0xE] = 0x0100; s.c.R[6] = V.STUB; s.c.R[3] = 0xFF3F; s.c.P = 3
        s.qflips = 0; s.idle = False

    def run(s, n):
        q = s.c.Q
        for _ in range(n):
            if not s.c.step(): s.idle = True; return
            s.b.steps += 1
            if s.c.Q != q: s.qflips += 1; q = s.c.Q

    def key(s, data, n=600_000, gap=60):
        s.u.type(s.b.steps + 500, data, gap=gap); s.run(n)

    def v(s, name, k=0): return s.M[s.sy[name] + k]
    def setv(s, name, val, k=0): s.M[s.sy[name] + k] = val & 0xFF
    def v16(s, name): return s.v(name) * 256 + s.v(name, 1)
    def grid(s, x, y): return s.M[s.sy['GRID'] + y * MW + x]
    def setgrid(s, x, y, ch): s.M[s.sy['GRID'] + y * MW + x] = (s.grid(x, y) & 0x80) | ord(ch)
    def ch(s, x, y): return chr(s.grid(x, y) & 0x7F)
    def rooms(s):
        a = s.sy['ROOMS']; return [tuple(s.M[a + 5 * i: a + 5 * i + 5]) for i in range(NR)]
    def mons(s):
        a = s.sy['MONS']; return [list(s.M[a + MSZ * k: a + MSZ * k + MSZ]) for k in range(NM)]
    def setmon(s, k, t, x, y, hp, awake=1):
        a = s.sy['MONS'] + MSZ * k; s.M[a: a + MSZ] = bytes([t + 1, x, y, hp, awake, 0, 0, 0])
    def clear_mons(s):
        a = s.sy['MONS']
        for k in range(NM):
            if s.M[a + MSZ * k] and s.M[a + MSZ * k + 5]: s.M[a + MSZ * k] = 0     # (drawn ones: erased next redraw)
            elif s.M[a + MSZ * k]: s.M[a + MSZ * k] = 0
    def pos(s): return s.v('PX'), s.v('PY')
    def text(s): return s.b.text()
    def scr(s): return screen(s.text())
    def at(s, x, y): return s.scr()[y + 1][x + 1]


def neighbours(x, y): return [(0, (x, y - 1)), (1, (x - 1, y)), (2, (x, y + 1)), (3, (x + 1, y))]
KEY = {0: b'w', 1: b'a', 2: b's', 3: b'd'}
ARROW = {0: b'\x1b[A', 1: b'\x1b[D', 2: b'\x1b[B', 3: b'\x1b[C'}


def check_level(g):
    """-> the problems with the level made"""
    e = []
    R = g.rooms()
    for i, (x0, y0, x1, y1, lit) in enumerate(R):
        sx, sy = 26 * (i % 3), 7 * (i // 3)
        if not (sx <= x0 < x1 <= sx + 25 and sy <= y0 < y1 <= sy + 6 and x1 - x0 >= 4 and y1 - y0 >= 3):
            e.append('room %d %s outside its sector' % (i, R[i][:4]))
    flat = [g.ch(x, y) for y in range(MH) for x in range(MW)]
    if flat.count('>') + flat.count('*') != 1: e.append('%d stairs' % (flat.count('>') + flat.count('*')))
    px, py = g.pos()
    if g.ch(px, py) not in '.': e.append('he stands on %r' % g.ch(px, py))
    seen, todo = {(px, py)}, [(px, py)]                     # every open cell reachable from him?
    while todo:
        x, y = todo.pop()
        for _, (a, b) in neighbours(x, y):
            if 0 <= a < MW and 0 <= b < MH and (a, b) not in seen and WALK(g.ch(a, b)):
                seen.add((a, b)); todo.append((a, b))
    opens = {(x, y) for y in range(MH) for x in range(MW) if WALK(g.ch(x, y))}
    if opens - seen: e.append('cells not reachable: %s' % sorted(opens - seen)[:4])
    pr = [i for i, r in enumerate(R) if r[0] <= px <= r[2] and r[1] <= py <= r[3]]
    ms = [m for m in g.mons() if m[0]]
    want = min(g.v('DEPTH') + 2, NM)
    if len(ms) != want: e.append('%d monsters, not %d' % (len(ms), want))
    if len({(m[1], m[2]) for m in ms}) != len(ms): e.append('two monsters on one cell')
    for m in ms:
        if g.ch(m[1], m[2]) == ' ' or not WALK(g.ch(m[1], m[2])): e.append('a monster on %r' % g.ch(m[1], m[2]))
        if pr and R[pr[0]][0] <= m[1] <= R[pr[0]][2] and R[pr[0]][1] <= m[2] <= R[pr[0]][3]: e.append('a monster in his room')
        t = m[0] - 1
        if not (g.v('DEPTH') - 3 <= t <= g.v('DEPTH') - 1): e.append('type %d on depth %d' % (t, g.v('DEPTH')))
    for y in range(MH):
        for x in range(MW):
            c = g.ch(x, y)
            if c in '$!)[>*':
                inroom = any(r[0] < x < r[2] and r[1] < y < r[3] for r in R)
                if not inroom: e.append('%r not on a floor at %d,%d' % (c, x, y))
    return e


def consistent(g):
    """-> the screen's map cells that are not as he knows the map"""
    s = g.scr(); bad = []
    drawn = {}
    for m in g.mons():
        if m[5]: drawn[(m[6], m[7])] = LETTERS[m[0] - 1] if m[0] else '?'
    for y in range(MH):
        for x in range(MW):
            if (x, y) == g.pos(): want = '@'
            elif (x, y) in drawn: want = drawn[(x, y)]
            elif g.grid(x, y) & 0x80: want = g.ch(x, y)
            else: want = ' '
            if s[y + 1][x + 1] != want: bad.append((x, y, s[y + 1][x + 1], want))
    for m in g.mons():                                      # a monster he can see is drawn
        if m[0] and not m[5]:
            x, y = m[1], m[2]; px, py = g.pos()
            near = abs(x - px) <= 1 and abs(y - py) <= 1
            cr = g.v('CURR'); R = g.rooms()
            inr = cr != 0xFF and R[cr][0] <= x <= R[cr][2] and R[cr][1] <= y <= R[cr][3]
            if near or inr: bad.append(('a monster he can see not drawn', x, y))
    return bad


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + str(x)) for x in e[:8]]; ok &= not e
    m, sy = build.assemble('descend')
    rng = random.Random(1802)

    # ---- the title; levels from several seeds
    g = Game(m, sy); g.run(200_000)
    e = [] if 'D E S C E N D' in ''.join(g.scr()).replace('#', ' ') else ['no title']
    report('the title', e)
    e = []; n = 0
    for k in range(8):
        h = Game(m, sy); h.run(150_000 + 37_000 * k)
        h.key(b'x', 1_500_000)
        e += ['seed %d: %s' % (k, x) for x in check_level(h)]; n += 1
        if k == 0:
            first = h
    report('%d levels made: rooms in their sectors, all of the map reachable from him, the stairs, monsters, things'
           % n, e)

    # ---- the first screen
    g = first; px, py = g.pos(); s = g.scr(); e = []
    top = s[0]
    for w in ('DESCEND', 'Depth 1', 'HP 20/20', 'Atk 3', 'Def 0', 'Lv 1', 'XP 0', 'Gold 0', 'Pot 1'):
        if w not in top: e.append('status: %r not in %r' % (w, top))
    if g.at(px, py) != '@': e.append('no @ at his place')
    cr = g.v('CURR'); R = g.rooms()
    if cr == 0xFF: e.append('not in a room')
    else:
        x0, y0, x1, y1, lit = R[cr]
        if not lit: e.append('his room not lit')
    far = [(x, y) for i, r in enumerate(R) if i != cr for y in range(r[1], r[3] + 1) for x in range(r[0], r[2] + 1)
           if s[y + 1][x + 1] != ' ']
    if far: e.append('other rooms shown: %s' % far[:4])
    e += consistent(g)
    if 'Arrows/WASD' not in s[23]: e.append('keys line: %r' % s[23])
    report('a key: the status line, @, his room shown, the rest blank until seen', e)

    # ---- a step, by key and by arrow; a wall
    def free_dirs(g):
        px, py = g.pos(); ms = {(mm[1], mm[2]) for mm in g.mons() if mm[0]}
        return [d for d, (x, y) in neighbours(px, py) if WALK(g.ch(x, y)) and (x, y) not in ms]
    e = []
    g.clear_mons(); g.key(b' ')
    for how in (KEY, ARROW):
        d = free_dirs(g)[0]; p0 = g.pos(); t0 = g.v('TURN')
        g.key(how[d])
        want = dict(neighbours(*p0))[d]
        if g.pos() != want: e.append('%s: at %s, not %s' % ('key' if how is KEY else 'arrow', g.pos(), want))
        if g.v('TURN') != (t0 + 1) & 0xFF: e.append('no turn used')
        if g.at(*g.pos()) != '@': e.append('@ not drawn')
    walls = [d for d, (x, y) in neighbours(*g.pos()) if not WALK(g.ch(x, y))]
    if walls:
        p0, t0 = g.pos(), g.v('TURN'); g.key(KEY[walls[0]])
        if g.pos() != p0 or g.v('TURN') != t0: e.append('walked into a wall (or a turn used)')
    else: e.append('no wall next to him to try')
    e += consistent(g)
    report('a step (W A S D, an arrow), a wall: no step, no turn; the screen as he knows the map', e)

    # ---- a fight: a rat next to him, until it is dead
    e = []
    d = free_dirs(g)[0]; (x, y) = dict(neighbours(*g.pos()))[d]
    g.setmon(0, 0, x, y, 3, awake=0); g.setv('HP', 20); g.setv('XPH', 0); g.setv('XPL', 0); g.setv('NXH', 0); g.setv('NXL', 10)
    t0 = len(g.text()); q0 = g.qflips
    g.key(b' ')                                             # (drawn first)
    if g.at(x, y) != 'r': e.append('the rat not drawn: %r' % g.at(x, y))
    for _ in range(30):
        if not g.mons()[0][0]: break
        g.key(KEY[d])
    out = g.text()[t0:]
    if g.mons()[0][0]: e.append('the rat still there after 30 blows')
    if g.v16('XPH') != 1: e.append('XP %d' % g.v16('XPH'))
    if 'You kill the rat!' not in out: e.append('no "You kill the rat!"')
    if g.at(x, y) == 'r': e.append('its letter still on the screen')
    if g.qflips - q0 < 10: e.append('no sound')
    e += consistent(g)
    report('a fight: the rat killed (XP 1, "You kill the rat!", its letter gone, a sound)', e)

    # ---- a monster that fights him
    e = []
    d = free_dirs(g)[0]; (x, y) = dict(neighbours(*g.pos()))[d]
    g.setmon(1, 5, x, y, 99, awake=1); g.setv('HP', 60); g.setv('MAXHP', 60); g.setv('DEF', 0)
    t0 = len(g.text())
    for _ in range(8): g.key(b' ')
    out = g.text()[t0:]
    if g.v('HP') >= 60: e.append('HP %d' % g.v('HP'))
    if 'The orc hits you.' not in out: e.append('no "The orc hits you."')
    if ('HP %d/60' % g.v('HP')) not in g.scr()[0]: e.append('status: %r' % g.scr()[0])
    e += consistent(g)
    g.setmon(1, 0, 0, 0, 0, 0); g.M[sy['MONS'] + MSZ] = 0
    report('an orc next to him: it fights him (HP %d, "The orc hits you.", the status line)' % g.v('HP'), e)
    g.key(b' ')

    # ---- things picked up; a potion drunk; a level up
    e = []
    def put_and_step(c):
        d = free_dirs(g)[0]; (x, y) = dict(neighbours(*g.pos()))[d]
        g.setgrid(x, y, c); g.key(b' '); g.key(KEY[d])
        if g.pos() != (x, y): e.append('did not step onto %r' % c)
        if g.ch(x, y) != '.': e.append('%r left on the floor' % c)
    g0, p0, a0, d0 = g.v16('GOLDH'), g.v('POTS'), g.v('ATK'), g.v('DEF'); t0 = len(g.text())
    put_and_step('$'); put_and_step('!'); put_and_step(')'); put_and_step('[')
    out = g.text()[t0:]
    if not 2 + 5 <= g.v16('GOLDH') - g0 <= 9 + 5: e.append('gold %d -> %d' % (g0, g.v16('GOLDH')))
    if g.v('POTS') != p0 + 1: e.append('potions %d' % g.v('POTS'))
    if g.v('ATK') != a0 + 1 or g.v('DEF') != d0 + 1: e.append('Atk %d Def %d' % (g.v('ATK'), g.v('DEF')))
    for w in ('gold.', 'A potion!', 'A better weapon!', 'Armour!'):
        if w not in out: e.append('no %r' % w)
    g.setv('HP', 30); p0 = g.v('POTS')
    g.key(b'p')
    if g.v('HP') != 40 or g.v('POTS') != p0 - 1: e.append('a potion: HP %d, potions %d' % (g.v('HP'), g.v('POTS')))
    g.setv('POTS', 0); g.key(b'p')
    if 'No potions left.' not in g.text()[-200:]: e.append('no "No potions left."')
    d = free_dirs(g)[0]; (x, y) = dict(neighbours(*g.pos()))[d]   # a level up
    g.setmon(0, 0, x, y, 1, awake=0); g.setv('XPH', 0); g.setv('XPL', 9); g.setv('NXH', 0); g.setv('NXL', 10)
    lv, mx, at0 = g.v('PLV'), g.v('MAXHP'), g.v('ATK')
    for _ in range(20):
        if not g.mons()[0][0]: break
        g.key(KEY[d])
    if (g.v('PLV'), g.v('MAXHP'), g.v('ATK'), g.v16('NXH')) != (lv + 1, mx + 5, at0 + 1, 20):
        e.append('after the level up: Lv %d, most HP %d, Atk %d, next %d' % (g.v('PLV'), g.v('MAXHP'), g.v('ATK'), g.v16('NXH')))
    if 'Level up!' not in g.text()[-400:]: e.append('no "Level up!"')
    e += consistent(g)
    report('gold, a potion, a weapon, armour picked up; a potion drunk (+10 HP), none left; a level up', e)

    # ---- the stairs
    e = []
    px, py = g.pos(); g.setgrid(px, py, '>'); g.key(b'>', 2_000_000)
    if g.v('DEPTH') != 2: e.append('depth %d' % g.v('DEPTH'))
    if 'Depth 2' not in g.scr()[0]: e.append(g.scr()[0])
    if 'You go down to depth 2.' not in g.scr()[22]: e.append('row 23: %r' % g.scr()[22])
    e += check_level(g) + consistent(g)
    report('the stairs (>): depth 2, a new level, "You go down to depth 2."', e)

    # ---- many steps at random: the screen as he knows the map
    e = []
    for k in range(80):
        dirs = [d for d, (x, y) in neighbours(*g.pos()) if WALK(g.ch(x, y))]
        g.setv('HP', 99); g.setv('MAXHP', 99)
        g.key((KEY if k % 3 else ARROW)[rng.choice(dirs)], 500_000)
        if k % 10 == 9:
            bad = consistent(g)
            if bad: e.append('after %d steps: %s' % (k + 1, bad[:4])); break
    s = g.scr()[0]
    want = ['Depth %d' % g.v('DEPTH'), 'HP %d/%d' % (g.v('HP'), g.v('MAXHP')), 'Gold %d' % g.v16('GOLDH')]
    e += ['status: %r not in %r' % (w, s) for w in want if w not in s]
    seen = sum(1 for y in range(MH) for x in range(MW) if g.grid(x, y) & 0x80)
    report('80 steps at random: every screen cell as he knows the map (%d cells seen), the status line' % seen, e)

    # ---- killed; a key: the title, a new game
    e = []
    g.clear_mons(); g.key(b' ')
    d = free_dirs(g)[0]; (x, y) = dict(neighbours(*g.pos()))[d]
    g.setmon(2, 9, x, y, 99, awake=1); g.setv('HP', 2); g.setv('MAXHP', 20); g.setv('DEF', 0)
    for _ in range(30):
        if g.v('HP') == 0: break
        g.key(b' ')
    g.run(3_000_000)
    s = '\n'.join(g.scr())
    if g.v('HP') != 0: e.append('HP %d' % g.v('HP'))
    if 'You were killed by a dragon on depth 2.' not in s: e.append('the end screen: %r' % s[:300])
    if 'Score' not in s: e.append('no score')
    g.key(b'x', 1_500_000)
    if 'D E S C E N D' not in '\n'.join(g.scr()).replace('#', ' ') or 'Press any key' not in '\n'.join(g.scr()): e.append('not the title')
    g.key(b'x', 1_500_000)
    if (g.v('DEPTH'), g.v('HP'), g.v('MAXHP'), g.v('ATK'), g.v16('GOLDH')) != (1, 20, 20, 3, 0): e.append('not a new game')
    report('killed by a dragon: the end screen; a key: the title; a key: a new game', e)

    # ---- the Star Crystal on depth 10
    e = []
    g.setv('DEPTH', 9); px, py = g.pos(); g.setgrid(px, py, '>'); g.key(b'>', 2_000_000)
    star = [(x, y) for y in range(MH) for x in range(MW) if g.ch(x, y) == '*']
    if g.v('DEPTH') != 10 or len(star) != 1: e.append('depth %d, %d crystals' % (g.v('DEPTH'), len(star)))
    else:
        sx, sy2 = star[0]
        nb = [(d, p) for d, p in neighbours(sx, sy2) if g.ch(*p) == '.']
        d, p = nb[0]
        g.clear_mons(); g.setv('PX', p[0]); g.setv('PY', p[1]); g.key(b' ')
        g.key(KEY[d ^ 2], 3_000_000)
        s = '\n'.join(g.scr())
        if 'You found the Star Crystal on depth 10!' not in s: e.append('the end: %r' % s[:300])
    report('depth 10: the Star Crystal (*) taken - won', e)

    # ---- Esc alone
    g.key(b'x', 1_500_000); g.key(b'\x1b', 2_000_000)
    t = g.text(); e = []
    if not g.idle: e.append('did not end')
    if not t.endswith('\x1b[0m\x1b[?25h\x1b[2J\x1b[H'): e.append('the end: %r' % t[-30:])
    if g.c.Q: e.append('Q left on')
    report('a lone Esc at the title: the program ends - the screen cleared, the cursor back, Q off', e)
    if '-v' in sys.argv: print('\n'.join(first.scr()))
    print('program $%04X-$%04X, its variables to $%04X' % (min(m), max(m), sy['GRID'] + MW * MH))
    print('\nDESCEND: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
