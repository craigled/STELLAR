# CANONBALL

A cannon-and-castle artillery game for STELLAR, written in Stellar C (`SC/scc.py`).
VT100 terminal, 80 x 24, VM1 at `$4000`.

| file | what |
|---|---|
| `CanonBall-Solo.sc` / `.lst` | **Solo**: your cannon on the left, a castle somewhere in columns 48-77. Knock it down in as few shots as you can. One 4 KB block. |
| `CanonBall.sc` / `.lst` | **You against the computer**: a castle and a cannon at each end of the field, turns, wind, three levels. `SETSIZE 02` (8 KB: VM1 + VM2's block). |

Both are verified on the Elf2K (2026-10-06). Build from source with the Stellar C compiler
(the [download](https://stellar-1802.dev/stellarc.html)): `python3 scc.py CanonBall.sc` writes `CanonBall.lst`.
In the work repo these are `CanonBall-v01` (solo) and `CanonBall-v02`, with simulator verifiers.

## Playing

* **Up / Down arrows** (or W / S) raise and lower the barrel, one degree a press, 0-90.
  The angle in the status line follows the key at once; the barrel is redrawn when you stop
  (redrawing it costs about a quarter of a second of 1802 time).
* **SPACE** fires. The ball leaves a trail of dots, kept until the next shot, to aim by.
* **Q** quits.
* A hit knocks bricks off five columns round it (3 at the centre, 2, 1). A castle has 58
  bricks; it **falls when 15 or fewer stand**. The status line shows its strength in %.
* CanonBall (vs the computer): choose **1 Easy, 2 Normal, 3 Hard** on the title screen. You fire first. The wind
  (`<<<` / `>>>`, up to 3 marks, or calm) is fixed for a game and pushes every ball, yours
  and the computer's, the same way. A ball can come down on its own castle.

## How it works

* **Fixed point, all unsigned shifts.** `x` is in 1/256 of a column and `yy` in 1/256 of a row
  counting down, both with 128 added, so `col = x >> 8` and `row = yy >> 8` round to the
  nearest cell. A terminal row is about two columns tall, so the speed across is 2 x the sine
  table and the speed up 1 x; gravity is 6 per step. Each step: `x += vx; yy -= vy; vy -= 6`.
  Above the screen `yy` wraps (row >= 200: not drawn); off either side `x >> 8` is 0 or > 80.
  At 45 degrees the range is about 84 columns.
* **Sine table**, `sint[0..90]` = 255 sin, gives both components (cos a = `sint[90 - a]`).
* **Castle = column heights** `h[]`. The ball hits when `row + h[column] >= 24`; it moves up to
  2 columns a step, so the column it passed is tested too.
* **Drawing** uses patched escape strings and digit tables (`tens[]`, `ones[]`), not `at()`:
  one `PRINTSTR` both turns the old cell into a trail dot and draws the ball in the new one.
  `at()` with variables is ~2,900 instructions; this is ~10 commands.
* **The computer's aim (CanonBall vs the computer).** It starts at a random 15-44 degrees and after each shot moves
  by (where its ball came down - the middle of your castle) / 5, 3 or 2 degrees (Easy, Normal,
  Hard), clamped to +-12, plus a wobble of +-5, +-3 or +-1; kept within 5-45 (the low, fast
  trajectory). A ball off the left edge counts as landing at column 0. Tuned in a Python
  model against a decent human (who corrects by half a degree a column, +-2 sloppy): the
  computer wins about 35% / 54% / 72% of games.
* **Rerun without reload**: the castles, trail and angles are set in code at every game start.

## Speed (V0061.35, measured in the simulator)

About 1 ms per STELLAR command. A step of the ball is ~40 commands plus a 19-byte print:
a full-width 45-degree lob takes roughly 3-4 s, a typical 25-degree hit 2 s. Profiling found
the first draft 3x slower: `at()`, and the ball's variables spilled to memory because too
many globals held registers (fixed by locals, `u8` for rarely-used globals, and returning the
hit column in the result instead of a global).
