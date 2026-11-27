#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/atman_gen.py - AT-MAN's maze: 21 rows of 37 cells, the left 19 written here and mirrored, then checked
(every dot reachable, no open 2 x 2 block, the pen and its door, the tunnel) and written to out/atmanmaze.inc.

  #  wall          .  a dot          o  a power cell          (space)  an empty corridor
  -  the pen's door (Glitches only)   G  a Glitch starts here (in the pen)   P  AT-MAN starts here

    python3 LTOS/atman_gen.py            (build.py runs it)
"""
import os
HERE = os.path.dirname(os.path.abspath(__file__))

LEFT = [                          # 19 characters: the last is the middle column
    "###################",
    "#........#........",
    "#o##.###.#.######.#",
    "#.................",
    "#.##.#.#######.##.#",
    "#....#....#....#..",
    "####.####.#.###.###",
    "   #.#.........    ",
    "####.#.#####.#.###-",           # the pen's top: its door in the middle
    "    ...#.....#.#GGG",           # the tunnel (row 9's ends), the pen (5 wide)
    "####.#.#####.#.####",
    "   #.#.............",
    "####.#.###.####.###",
    "#........#........",
    "#.##.###.#.#####.#",
    "#o.#...........#..",
    "##.#.#.#######.#.##",
    "#....#....#....#..",
    "#.#######.#.####.##",
    "#.................P",
    "###################",
]


def maze():
    rows = []
    for k, l in enumerate(LEFT):
        l = l.ljust(19, '.')
        rows.append(l + l[:18][::-1])
    rows = [r.replace('P', ' ') if k != 19 else r[:18] + 'P' + r[19:].replace('P', '.') for k, r in enumerate(rows)]
    return rows


def check(m):
    H, W = len(m), len(m[0])
    probs = []
    if H != 21 or any(len(r) != W for r in m) or W != 37: probs.append('size %d x %d' % (W, H))
    start = [(r, c) for r in range(H) for c in range(W) if m[r][c] == 'P']
    if len(start) != 1: probs.append('P: %d' % len(start)); return probs
    seen, todo = set(start), list(start)
    while todo:                                   # AT-MAN's moves: not walls, not the door; the tunnel wraps
        r, c = todo.pop()
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rr, cc = r + dr, (c + dc) % W
            if 0 <= rr < H and (rr, cc) not in seen and m[rr][cc] not in '#-G':
                seen.add((rr, cc)); todo.append((rr, cc))
    lost = [(r, c) for r in range(H) for c in range(W) if m[r][c] in '.o' and (r, c) not in seen]
    if lost: probs.append('dots out of reach: %s' % lost[:6])
    for r in range(H - 1):
        for c in range(W - 1):
            if all(m[r + a][c + b] not in '#-G' for a in (0, 1) for b in (0, 1)):
                probs.append('an open 2 x 2 at row %d col %d' % (r, c))
    for r in range(H):                            # the edges: walls, but for the tunnel row
        for c in (0, W - 1):
            if m[r][c] not in '#' and r != 9 and m[r][c] != ' ': probs.append('edge open at row %d col %d' % (r, c))
    if m[9][0] == '#' or m[9][W - 1] == '#': probs.append('no tunnel on row 9')
    if sum(row.count('G') for row in m) < 4: probs.append('room for 4 Glitches in the pen')
    return probs


def write(path=os.path.join(HERE, 'out', 'atmanmaze.inc')):
    m = maze()
    p = check(m)
    if p: raise SystemExit('AT-MAN maze: ' + '; '.join(p))
    lines = ['; out/atmanmaze.inc - made by atman_gen.py: AT-MAN\'s maze, 21 rows x 37 cells (# wall, . dot, o power,',
             ';   - the pen door, G the pen, P AT-MAN\'s start)', 'MAZEW   EQU     37', 'MAZEH   EQU     21', 'MAZE0:']
    for r in m: lines.append("        DB      '%s'" % r.replace("'", "''"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write('\n'.join(lines) + '\n')
    return m


if __name__ == '__main__':
    m = maze()
    print('\n'.join(m))
    p = check(m)
    print('dots %d, power %d' % (sum(r.count('.') for r in m), sum(r.count('o') for r in m)))
    print('OK' if not p else '\n'.join(p))
