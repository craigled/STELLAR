#!/usr/bin/env python3
"""Build web/apps/apps.json - the Apps page's catalogue: every showcase app with a screenshot.

Each "screenshot" is the app's real terminal screen: the program is run in the work repo's
Python simulator (Firmware-Math) over the SAME firmware image the browser gets
(extract_firmware.build_image), keys are typed at it on a schedule (SCRIPT below), and the
VT100 screen it has drawn is captured - 24 rows of 80 columns plus where reverse video is.
The page draws it as a terminal, so it is sharp at any size and costs a few KB.

    python3 web/build/gen_apps.py              # all apps (in parallel), writes web/apps/apps.json
    python3 web/build/gen_apps.py --show Snake # one app: print its screen, write nothing

Run it after adding a Simulator sample (add it to APPS too), then bump ?v=.
"""
import os, sys, json, re
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.dirname(HERE)
FMATH = os.path.expanduser('~/Projects/stellar-1802/Firmware-Math')
sys.path.insert(0, FMATH); sys.path.insert(0, HERE)

UP, DOWN, LEFT, RIGHT = b'\x1b[A', b'\x1b[B', b'\x1b[D', b'\x1b[C'
M = 1_000_000

# (file, group, name, description, script[, href]). A script is a list of: an int = run that
# many 1802 instructions; bytes = type them (queued: the program reads them as it gets to them).
# The Simulator sample's own pre-typed input (manifest.json "input") is typed first.
# A multi-VM app (the Multitasking page's demos): file = its Elf2K download (every program at its
# own VM block, as the Multitasking page places them) and href = its link there,
# scheduler.html#app=<the scenario's id>.
APPS = [
 # ---------------------------------------------------------------- games
 ('CanonBall.lst', 'Games', 'CanonBall',
  'Your castle and great cannon against the computer\'s. Raise the barrel, mind the wind, fire - '
  'then the computer fires back, correcting its aim from where its last ball landed. Three levels. Written in Stellar C.',
  [b'2', 3 * M, DOWN * 21, 3 * M, b' ', 14 * M]),
 ('CanonBall-Solo.lst', 'Games', 'CanonBall Solo',
  'Target practice: aim the cannon and knock down the castle across the field in as few shots '
  'as you can. Each shot leaves a trail of dots to aim by. Written in Stellar C.',
  [b' ', 2 * M, DOWN * 20, 3 * M, b' ', 9 * M]),
 ('Battleship.lst', 'Games', 'Battleship',
  'You against the computer on two 10 x 10 seas. Aim with the arrow keys or type a square; '
  'the computer hunts on a checkerboard and works round every hit.',
  [b' ', 3 * M, b' ', 4 * M, b'E5 ', 5 * M, b'C3 ', 5 * M, b'G7 ', 5 * M, b'B8 ', 5 * M, b'H2 ', 6 * M]),
 ('Tetris.lst', 'Games', 'Tetris',
  'Steer the falling pieces, turn them, and clear the rows. Every ten rows the level goes up and the pieces fall faster.',
  [b' ', 1 * M, LEFT * 3 + b' ', 1 * M, RIGHT * 2 + b' ', 1 * M, UP + LEFT + b' ', 1 * M, RIGHT * 4 + b' ', 1 * M,
   UP + RIGHT * 2 + b' ', 1 * M, b' ', 1 * M, LEFT * 4 + b' ', 1 * M, UP + b' ', 1_500_000]),
 ('Breakout.lst', 'Games', 'Breakout',
  'Knock out the wall of bricks with the paddle: three balls, and every wall comes faster.',
  [b' ', 1_200_000, RIGHT * 4, 300_000]),
 ('Snake.lst', 'Games', 'Snake',
  'Steer the snake to the food; it grows with every bite. Do not hit the wall or yourself. Ten speed levels.',
  [b' ', 700_000, UP, 300_000, RIGHT, 400_000]),
 ('Lunar-Lander.lst', 'Games', 'Lunar Lander',
  'Fire the thrusters to set the lander down gently on the pad before the fuel runs out. Easy and Hard.',
  [b'E', 800_000, UP * 3, 400_000, RIGHT, 300_000]),
 ('Racer.lst', 'Games', 'Racer',
  'Keep the car on a scrolling, winding road with the arrow keys. The road narrows as you go.',
  [b' ', 900_000, LEFT, 200_000]),
 ('Pong.lst', 'Games', 'Pong',
  'The classic: you on the right against the computer\'s paddle on the left.',
  [b' ', 4 * M]),
 ('Invaders.lst', 'Games', 'Invaders',
  'Two rows of invaders march down the screen; move your gun with the arrow keys and shoot them first.',
  [b' ', 4 * M, LEFT * 3, 1 * M, b' ', 300_000]),
 ('Tic-Tac-Toe.lst', 'Games', 'Tic-Tac-Toe',
  'You are X against the computer\'s O. Type a square to play.',
  [b'5\r', 3 * M, b'9\r', 3 * M, b'2\r', 3 * M]),
 ('downloads/Maze.lst', 'Games', 'Maze',
  'Two VMs at work: VM1 carves a random maze as you watch, copies it into VM2, and VM2 finds the way '
  'through with its right hand on the wall. Runs on the Multitasking page.',
  [b' ', 30 * M], 'scheduler.html#app=maze'),
 ('downloads/MazeRace.lst', 'Games', 'Maze Race',
  'Three VMs: VM1 carves a maze and draws it twice; VM2 (right hand on the wall) and VM3 (left hand) '
  'race through it at the same time on the one 1802. Runs on the Multitasking page.',
  [b' ', 40 * M], 'scheduler.html#app=mazerace'),
 ('Moonbase.lst', 'Games', 'MOONBASE',
  'A text adventure: escape the damaged moon base. Two-word commands, ten rooms, and every game is shuffled.',
  [b'\r', 4 * M, b'LOOK\r', 6 * M, b'INVENTORY\r', 6 * M]),
 ('Getting-Warmer.lst', 'Games', 'Getting Warmer',
  'Guess the number from 1 to 1000 in ten tries: higher or lower, warmer or colder.',
  [b'\r', 3 * M, b'500\r', 3 * M, b'250\r', 3 * M, b'375\r', 3 * M, b'300\r', 3 * M]),
 # ---------------------------------------------------------------- graphics
 ('Mandelbrot.lst', 'Graphics', 'Mandelbrot',
  'The Mandelbrot set in ASCII, 40 x 24, worked out in fixed-point arithmetic on an 8-bit chip.',
  [60 * M]),
 ('Starfield.lst', 'Graphics', 'Starfield',
  'Stars stream out from the centre of the screen as if you were flying through space. You choose how many.',
  [14 * M]),
 ('Bouncing-Ball.lst', 'Graphics', 'Bouncing Ball',
  'Balls bounce round the screen, off the walls and each other.',
  [14 * M]),
 ('Starship.lst', 'Graphics', 'Starship',
  'The COSMAC ELF logo starship, drawn in text on the terminal.',
  [9 * M]),
 ('Game-of-Life.lst', 'Graphics', 'Game of Life',
  'Conway\'s Game of Life, animated: a blinker and a glider on a 20 x 10 world.',
  [10 * M]),
 ('Sort-Visualiser.lst', 'Graphics', 'Sort Visualiser',
  'Watch a bubble sort put a row of bars in order, one pass per STELLAR command.',
  [b' ', 1_300_000]),
 # ---------------------------------------------------------------- text
 ('ELIZA.lst', 'Text', 'ELIZA',
  'The famous 1966 chatbot therapist, running on the 1802. Tell it your troubles.',
  [8 * M, b'I am worried about my computer\r', 10 * M, b'It is very old\r', 10 * M]),
 ('Lite-Writer-2.lst', 'Text', 'Lite-Writer 2',
  'A full-screen word processor: type, move the cursor, insert and delete, and keep documents in memory slots.',
  [4 * M, b'Welcome to Lite-Writer 2, a word processor for the RCA 1802.\r\r', 6 * M,      # (its key queue holds 127)
   b'It runs on a 1976 CPU at 3 MHz, inside a\rmultitasking virtual machine.\r', 8 * M]),
 ('Banner.lst', 'Text', 'Banner',
  'Type a word and it prints in big block letters.',
  [4 * M]),
 # ---------------------------------------------------------------- math
 ('Pi-Spigot.lst', 'Math', 'Pi digits',
  'Pi to as many as 1,526 digits, worked out by the spigot method.',
  [b'500\r', 45 * M]),
 ('Prime-Gen-v07.lst', 'Math', 'Prime-Gen',
  'Give it a range and it prints every prime number in it.',
  [40 * M]),
 ('Simple-Calc-8.lst', 'Math', 'Simple-Calc',
  'A pocket calculator on the terminal: 8-digit add, subtract, multiply and divide, with the answer carried on.',
  [3 * M, b'355/113\r', 4 * M, b'*2\r', 4 * M]),
 # ---------------------------------------------------------------- morse + clock
 ('Morse-Sender-v18.lst', 'Morse', 'Morse Sender',
  'Type a message and it is sent in Morse code on the Q line - turn the Sound on and listen to it at 700 Hz.',
  [14 * M]),
 ('Big-Clock-v3.lst', 'Clock', 'Big Clock',
  'A big seven-segment clock from the Elf2K\'s real-time clock chip, with a timer, a chime and an alarm.',
  [6 * M]),
]


def screen_of(app):
    file, group, name, desc, script = app[:5]
    href = app[5] if len(app) > 5 else None
    files = file if isinstance(file, list) else [file]
    import opcode_sweep as S
    import rtc_verify as V
    import litewriter2_verify as LW
    from extract_firmware import build_image
    LW.TROWS = 24

    class VT(LW.VT100):                       # the page's terminal: 24 rows, scrolls on LF
        def esc(s, e):
            if re.match(r'^\x1b\[\?\d+[hl]$', e): return
            if re.match(r'^\x1b\[\d*[ABCD]$', e):
                n = int(e[2:-1] or 1); d = e[-1]
                if d == 'A': s.r = max(0, s.r - n)
                elif d == 'B': s.r = min(23, s.r + n)
                elif d == 'C': s.c = min(79, s.c + n)
                else: s.c = max(0, s.c - n)
                return
            if e in ('\x1b[J', '\x1b[0J'):
                for c in range(s.c, 80): s.g[s.r][c] = ' '
                for r in range(s.r + 1, 24): s.g[r] = [' '] * 80
                return
            if e == '\x1b[H': s.r = s.c = 0; return
            super().esc(e)

    man = {m['file']: m for m in json.load(open(os.path.join(WEB, 'samples', 'manifest.json')))}
    pokes = []
    for f in files:
        text = open(os.path.join(WEB, f if '/' in f else os.path.join('samples', f))).read()
        pokes += S.parse_dlines([l for l in text.split('\n') if l.startswith('D ')])
    c = S.boot(bytes(build_image()), pokes, keys=b'')
    rtc = V.DS12887(c)                         # Big Clock: a clock chip set to a fixed time
    for n, v in {0x00: 7, 0x02: 10, 0x04: 10, 0x06: 3, 0x07: 7, 0x08: 10, 0x09: 54,
                 0x0A: 0x20, 0x0B: 0x07, 0x0C: 0x10, 0x0D: 0x80}.items(): rtc.r[n] = v
    c.io_in[3] = V.Port3In(c.io_in[3], c.io_out[2], rtc)
    c.io_out[3] = V.Port3Out(c.io_out[2], rtc)
    q = c.io_in[3].u.q
    if files[0] in man: q.extend(man[files[0]]['input'].encode('latin1'))
    for item in script:
        if isinstance(item, bytes): q.extend(item); continue
        for _ in range(item):
            if not c.step() or c.R[c.P] == S.EXIT_IDL + 1: break
    vt = VT(); vt.feed(bytes(c.io_out[3]).decode('latin1'))
    rows = [''.join(vt.g[r]).rstrip() for r in range(24)]
    rev = []
    for r in range(24):
        spans, start = [], None
        for col in range(81):
            on = col < 80 and vt.a[r][col]
            if on and start is None: start = col
            if not on and start is not None: spans.append([start, col]); start = None
        if spans: rev.append([r] + spans)
    while rows and not rows[-1]: rows.pop()
    out = {'file': files[0], 'group': group, 'name': name, 'desc': desc, 'rows': rows, 'rev': rev,
           'blank': not any(rows) and not rev}
    if href: out['href'] = href
    return out


def main():
    os.chdir(FMATH)
    if '--show' in sys.argv:
        want = sys.argv[sys.argv.index('--show') + 1]
        for a in APPS:
            if want.lower() in (str(a[0]).lower(), a[2].lower()):
                s = screen_of(a)
                print('+' + '-' * 80 + '+')
                for r in range(24):
                    print('|' + (s['rows'][r] if r < len(s['rows']) else '').ljust(80) + '|')
                print('+' + '-' * 80 + '+', 'reverse:', s['rev'][:4])
                return
        raise SystemExit('no app %r' % want)
    with Pool(min(8, os.cpu_count() or 4)) as p:
        out = p.map(screen_of, APPS)
    for s in out:
        print('%-22s %-9s %s' % (s['name'], s['group'], 'BLANK SCREEN' if s['blank'] else '%d rows' % len(s['rows'])))
    os.makedirs(os.path.join(WEB, 'apps'), exist_ok=True)
    path = os.path.join(WEB, 'apps', 'apps.json')
    json.dump(out, open(path, 'w'), separators=(',', ':'))
    print('wrote %s: %d apps, %d bytes' % (path, len(out), os.path.getsize(path)))
    if any(s['blank'] for s in out): raise SystemExit('some screens are blank')


if __name__ == '__main__':
    main()
