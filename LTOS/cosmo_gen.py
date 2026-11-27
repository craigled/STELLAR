#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/cosmo_gen.py - COSMO KID's worlds: each screen drawn here as 22 rows of 79 characters, then packed
(run-length: count, character) into out/cosmolvl.inc for cosmo.asm.

  #  brick (solid)        =  platform (solid)      $  a coin            ^  spikes (they hurt)
  (  )  the portal: the world's end                B  a Blorb starts here (1 tall, it walks)
  S  Cosmo starts here (his feet)                  .  *  stars (nothing)

Cosmo is 2 rows tall (feet at row r, head r - 1) and jumps 5 rows; the ground's top is row 20.

    python3 LTOS/cosmo_gen.py            (build.py runs it)
"""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 79, 22
SOLID = '#='


def blank(seed):
    g = [[' '] * W for _ in range(H)]
    x = seed * 7 + 3                                 # a sky of stars, the same every time
    for k in range(14):
        x = (x * 37 + 11) % 997
        g[x % 6][x % W] = '.' if k % 3 else '*'
    return g


def ground(g, c0, c1, top=20):
    for r in range(top, H):
        for c in range(c0, c1 + 1): g[r][c] = '#'


def plat(g, r, c0, c1, ch='='):
    for c in range(c0, c1 + 1): g[r][c] = ch


def coins(g, r, c0, c1, step=2):
    for c in range(c0, c1 + 1, step): g[r][c] = '$'


def put(g, r, c, ch): g[r][c] = ch


def portal(g, c):
    for r in (17, 18, 19): g[r][c] = '('; g[r][c + 1] = ')'


def world1():
    a = blank(1)
    ground(a, 0, W - 1)
    put(a, 19, 3, 'S')
    coins(a, 19, 12, 20)
    plat(a, 16, 26, 33); coins(a, 15, 27, 33)
    put(a, 19, 40, 'B')
    plat(a, 15, 46, 52); plat(a, 11, 55, 60); coins(a, 10, 56, 60)
    put(a, 19, 66, 'B')
    coins(a, 19, 70, 76, 3)
    b = blank(2)
    ground(b, 0, 22); ground(b, 27, 52); ground(b, 57, W - 1)       # two pits to jump
    coins(b, 16, 23, 26, 3); coins(b, 16, 53, 56, 3)
    plat(b, 15, 33, 40); put(b, 14, 36, 'B'); coins(b, 14, 34, 40, 3)
    put(b, 19, 45, 'B')
    for c in range(62, 67): plat(b, 19 - (c - 62), c, W - 1 if c == 66 else c, '#')   # a stair
    for r in range(15, 20):
        for c in range(62 + 19 - r, 67): b[r][c] = '#'
    coins(b, 14, 63, 67, 2)
    c = blank(3)
    ground(c, 0, W - 1)
    plat(c, 16, 10, 16); plat(c, 12, 20, 26); plat(c, 8, 30, 36); coins(c, 7, 31, 35)
    coins(c, 11, 21, 25)
    put(c, 19, 28, 'B'); put(c, 19, 44, 'B'); put(c, 19, 52, 'B')
    plat(c, 15, 40, 48); coins(c, 14, 41, 47, 3)
    coins(c, 19, 58, 66, 2)
    portal(c, 72)
    return [a, b, c]


def world2():
    a = blank(4)
    ground(a, 0, 18); ground(a, 24, 40); ground(a, 47, W - 1)
    put(a, 19, 3, 'S')
    plat(a, 15, 19, 23); coins(a, 14, 19, 23, 2)
    put(a, 19, 30, 'B'); put(a, 19, 36, 'B')
    plat(a, 15, 41, 46); coins(a, 14, 41, 46, 2)
    plat(a, 19, 55, 58, '^')                                           # spikes on the ground
    coins(a, 15, 54, 59, 2)
    put(a, 19, 66, 'B')
    b = blank(5)
    ground(b, 0, 10); ground(b, 70, W - 1)
    plat(b, 17, 14, 19); plat(b, 14, 24, 29); plat(b, 17, 34, 39); plat(b, 14, 44, 49); plat(b, 17, 54, 59)
    plat(b, 15, 63, 67)
    coins(b, 16, 15, 19, 2); coins(b, 13, 25, 29, 2); coins(b, 16, 35, 39, 2); coins(b, 13, 45, 49, 2)
    coins(b, 16, 55, 59, 2)
    put(b, 16, 36, 'B'); put(b, 13, 46, 'B')
    c = blank(6)
    ground(c, 0, W - 1)
    plat(c, 19, 12, 14, '^'); plat(c, 19, 30, 33, '^'); plat(c, 19, 50, 52, '^')
    coins(c, 16, 11, 15, 2); coins(c, 16, 29, 34, 2); coins(c, 16, 49, 53, 2)
    put(c, 19, 20, 'B'); put(c, 19, 24, 'B'); put(c, 19, 40, 'B'); put(c, 19, 44, 'B'); put(c, 19, 58, 'B')
    plat(c, 14, 36, 46); coins(c, 13, 37, 45, 2)
    portal(c, 72)
    return [a, b, c]


WORLDS = [world1(), world2()]


def pack(g):
    """Run-length: (count 1-255, character) pairs over the 22 x 79 grid, row by row; 0 at the end."""
    flat = ''.join(''.join(r) for r in g)
    out, i = [], 0
    while i < len(flat):
        j = i
        while j < len(flat) and flat[j] == flat[i] and j - i < 255: j += 1
        out += [j - i, ord(flat[i])]; i = j
    return out + [0]


def write(path=os.path.join(HERE, 'out', 'cosmolvl.inc')):
    rooms = [r for w in WORLDS for r in w]
    lines = ['; out/cosmolvl.inc - made by cosmo_gen.py: COSMO KID\'s screens, run-length packed (count, char), 0 ends',
             'NWORLD  EQU     %d' % len(WORLDS), 'NROOMS  EQU     %d' % len(WORLDS[0]),
             'ROOMS:'] + ['        DW      ROOM%d' % k for k in range(len(rooms))]
    for k, g in enumerate(rooms):
        p = pack(g)
        lines.append('ROOM%d:' % k)
        for i in range(0, len(p), 16): lines.append('        DB      ' + ','.join('%d' % v for v in p[i:i + 16]))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write('\n'.join(lines) + '\n')
    return sum(len(pack(g)) for g in rooms)


if __name__ == '__main__':
    n = write()
    for w, rooms in enumerate(WORLDS, 1):
        for k, g in enumerate(rooms, 1):
            print('--- world %d-%d' % (w, k)); print('\n'.join(''.join(r) for r in g))
    print('%d bytes packed' % n)
