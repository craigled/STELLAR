#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/walk_gen.py - RUNNING's frames -> walkman.inc. A jointed stick man: thighs, shins, upper arms and forearms swing on
a sine, the body bobs; each frame is drawn on a grid of blocks. What RUNNING sends is only what changes from the frame
before (at 19200 baud the bytes are the speed): for each run of blocks, ESC[row;colH and spaces, the ones going off
first, then the ones coming on in reverse video.      python3 LTOS/walk_gen.py [-v]
"""
import math, os, sys
W, H, N = 15, 16, 6                     # blocks across, down; frames in a step (the legs swap, so a step is the whole loop)
TOP, LEFT = 5, 26                       # screen row of the first block row, column of the first block (2 columns each)
THIGH, SHIN, FOOT, UARM, FARM, BODY = 3.9, 4.3, 1.6, 2.9, 2.7, 4.2


def line(g, a, b):
    n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 2) + 1
    for i in range(n + 1):
        x = a[0] + (b[0] - a[0]) * i / n; y = a[1] + (b[1] - a[1]) * i / n
        cx, cy = int(round(x)), int(round(y))
        if 0 <= cx < W and 0 <= cy < H: g[cy][cx] = 1


def at(p, ang, l):                      # ang from straight down, + forward (right)
    return p[0] + l * math.sin(ang), p[1] + l * math.cos(ang)


def leg(g, hip, ph):
    t = math.radians(36) * math.sin(ph) + math.radians(3)
    k = math.radians(75) * max(0.0, math.sin(ph + 2.2)) ** 1.5 + math.radians(4)    # the knee bends as the leg comes through
    knee = at(hip, t, THIGH); ankle = at(knee, t - k, SHIN)
    toe = at(ankle, t - k + math.radians(85), FOOT)                                  # the foot: square to the shin
    line(g, hip, knee); line(g, knee, ankle); line(g, ankle, toe)


def arm(g, sh, ph):
    u = math.radians(48) * math.sin(ph)
    e = math.radians(30) + math.radians(50) * max(0.0, math.sin(ph))                 # the elbow bends more going forward
    el = at(sh, u, UARM); line(g, sh, el); line(g, el, at(el, u + e, FARM))


def frame(i):
    g = [[0] * W for _ in range(H)]
    ph = math.pi * i / N                                                             # half a cycle: then the legs have swapped
    bob = 0.5 * math.cos(2 * ph)
    hip = (6.6, 7.6 + bob); sh = (7.0, hip[1] - BODY)
    leg(g, hip, ph); leg(g, hip, ph + math.pi)
    arm(g, sh, ph + math.pi); arm(g, sh, ph)
    line(g, hip, sh)
    hx, hy = int(round(sh[0] + 0.3)), int(round(sh[1] - 1.9))
    for y in range(hy - 1, hy + 1):
        for x in range(hx - 1, hx + 2):
            if 0 <= y < H: g[y][x] = 1
    return g


def runs(old, new):
    """(row, first, length, on) for each run of blocks that change."""
    out = []
    for y in range(H):
        x = 0
        while x < W:
            if old[y][x] != new[y][x]:
                s = x
                while x < W and old[y][x] != new[y][x] and new[y][x] == new[y][s]: x += 1
                out.append((y, s, x - s, new[y][s]))
            else: x += 1
    return out


def go(r, c, y, x):
    """The fewest bytes from the cursor (r, c) to (y, x): ESC[y;xH, or relative moves."""
    full = b'\x1b[%d;%dH' % (y, x)
    if r is None: return full
    rel = b''
    if y > r: rel += b'\x1b[B' if y == r + 1 else b'\x1b[%dB' % (y - r)
    if y < r: rel += b'\x1b[A' if y == r - 1 else b'\x1b[%dA' % (r - y)
    if x > c: rel += b'\x1b[C' if x == c + 1 else b'\x1b[%dC' % (x - c)
    if x < c: rel += b'\x08' * (c - x) if c - x <= 3 else b'\x1b[%dD' % (c - x)
    return rel if len(rel) < len(full) else full


def delta(old, new):
    """Row by row, the video switched only when it has to."""
    b = bytearray(); r = c = None; rev = False
    for y, s, n, on in runs(old, new):
        if bool(on) != rev:
            b.extend(b'\x1b[7m' if on else b'\x1b[0m'); rev = bool(on)
        b.extend(go(r, c, TOP + y, LEFT + 2 * s)); b.extend(b' ' * (2 * n))
        r, c = TOP + y, LEFT + 2 * s + 2 * n
    if rev: b.extend(b'\x1b[0m')
    return bytes(b)


def main():
    F = [frame(i) for i in range(N)]
    blank = [[0] * W for _ in range(H)]
    first = delta(blank, F[0])
    steps = [delta(F[i], F[(i + 1) % N]) for i in range(N)]
    if '-v' in sys.argv:
        for k in range(0, N, 4):
            for y in range(H): print('   '.join(''.join('##' if F[j][y][x] else '  ' for x in range(W)) for j in range(k, min(k + 4, N))))
            print('-' * 130)
    print('frames %d, bytes each: %s; average %d = %.1f frames a second at 19200 baud; all %d bytes' % (
        N, [len(s) for s in steps], sum(map(len, steps)) // N, 1920 * N / sum(map(len, steps)), sum(map(len, steps)) + len(first)))
    def db(name, data):
        o = ['%s:' % name] if name else []
        for i in range(0, len(data), 16): o.append('        DB      ' + ','.join('%03XH' % c for c in data[i:i + 16]))
        return o
    t = ['; Copyright (C) 2026 Craig Ledbetter', '; SPDX-License-Identifier: GPL-3.0-or-later', '; walkman.inc - made by walk_gen.py: regenerate, do not edit.'] + db('FIRST', first + b'\0') + ['LOOP:']
    for s in steps: t += db('', s + b'\0')
    t.append('        DB      0')
    open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'walkman.inc'), 'w').write('\n'.join(t) + '\n')


def sc_string(b):
    return ''.join('\\e' if c == 27 else '\\b' if c == 8 else chr(c) for c in b)


def stellar_c():
    """The same man as a Stellar C program (SC/examples/walk.sc), for the home page's VMs. No wait: sharing the chip
    four ways is pace enough."""
    F = [frame(i) for i in range(N)]
    blank = [[0] * W for _ in range(H)]
    o = ['// walk.sc - made by LTOS/walk_gen.py: the man RUNNING draws, as a STELLAR app. Esc stops him.',
         'u8 clear[] = "\\e[0m\\e[2J\\e[?25l\\e[23;36HEsc stops";',
         'u8 leave[] = "\\e[0m\\e[?25h\\e[2J\\e[H";',
         'u8 first[] = "%s";' % sc_string(delta(blank, F[0]))]
    for i in range(N): o.append('u8 f%d[] = "%s";' % (i, sc_string(delta(F[i], F[(i + 1) % N]))))
    o += ['', 'u16 stop() {', '    u16 k;', '    if (!keyready()) return 0;', '    k = getc();',
          '    if (k != 27) return 0;', '    delay(3);                        // more straight after it: an arrow key',
          '    if (!keyready()) return 1;', '    while (keyready()) { k = getc(); }', '    return 0;', '}', '',
          'void main() {',
          '    print(clear);', '    print(first);', '    while (1) {']
    for i in range(N): o += ['        print(f%d);' % i, '        if (stop()) break;']
    o += ['    }', '    print(leave);', '}', '']
    open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'SC', 'examples', 'walk.sc'), 'w').write('\n'.join(o))


if __name__ == '__main__':
    main()
    stellar_c()
