# LIFE LAB

Conway's Game of Life that you seed yourself: draw your own life forms, stamp classic
patterns, then run it and watch them evolve. Written in Stellar C (`LifeLab.sc`), with the
generation itself in raw 1802 code (`native { }`, run by RUNMC). VT100 terminal, VM1 at
`$4000`, `SETSIZE 02` (8 KB: VM1 + VM2's block).

Build: `python3 SC/scc.py APPLICATIONS/Life-Lab/LifeLab.sc`
Verify: `python3 Firmware-Math/lifelab_verify.py` (a Python Life on the same torus is the model).

## Playing

The help screen comes first; any key opens the board (78 x 20, empty).

**EDIT** (the cursor shows where you are)

| key | does |
|---|---|
| arrows, or W A S D | move the cursor (it wraps round the edges) |
| SPACE | turn the cell under the cursor on or off |
| 1-9 | stamp a pattern with its top-left corner at the cursor |
| C | clear the board (and the generation count) |
| R | fill the board at random, about one cell in four |
| T | one generation |
| ENTER | run |
| ? | the help screen again |
| Q | quit |

**RUN**: SPACE or ENTER stops and goes back to EDIT - the board and the generation count
are kept, so you can add to a running world and carry on. `+` / `-` change the speed (0-9).

**Patterns**: 1 glider, 2 spaceship (LWSS), 3 R-pentomino (chaos from five cells),
4 acorn (seven cells, thousands of generations), 5 Gosper glider gun (a glider every 30
generations), 6 pulsar (blinks forever), 7 diehard (vanishes after 130 generations),
8 ten in a row (becomes a pentadecathlon), 9 infinite growth (a one-row seed that never stops).

The board wraps round - a torus - so gliders that leave one edge come back on the other.

## How it works

* `A[]` is the board with a one-cell border, 80 bytes a row (`(H + 2) x 80`). Before each
  generation native code copies the opposite edges into the border, so every cell has eight
  neighbours and the wrap costs nothing in the inner loop.
* **The generation** (native): three row pointers walk the board with running column sums;
  each cell costs one new 3-cell column sum. With the 3 x 3 sum `s` (the cell included) the
  rule is `s = 3`: alive; `s = 4`: unchanged; anything else: dead. The new board goes to `B[]`.
* **The redraw** (native, row by row): compare `B` with `A`, copy it across, count the
  population, and build `ESC[row;colH` + the cells from the first to the last change in the
  row. Only rows that changed are sent; a quiet board costs a few bytes a generation.
* The random fill is a 16-bit Galois LFSR in native code, seeded from `rand()`.
* Editing writes `A[]` directly and draws the one cell with a patched escape string
  (`ESC[rr;ccHO` + backspace, so the terminal's cursor stays on the cell).

## Speed (simulator, V0061.35)

About 150,000 1802 instructions a generation (the native step ~100k, the row loop ~30k,
the status line ~10k) - roughly 0.8 s on the 3 MHz Elf2K, plus the terminal: a sparse
board (the glider gun) sends ~250 bytes, a busy random board ~1.7 KB (1.8 s at 9600 baud).
