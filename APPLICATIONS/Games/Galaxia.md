# STELLAR GALAXIA

A Galaxian-style shooter for STELLAR, written in Stellar C (`SC/scc.py`) with a native 1802 frame engine.
VT100 terminal, 80 x 24, VM1 at `$4000`, `SETSIZE 02` (8 KB: VM1 + VM2's block). Verified on the Elf2K
(2026-10-11).

## Playing

* **Left / Right arrows** (or A / D) move your ship `/^\` along the bottom; **SPACE** fires (one shot at a time).
* The swarm of 36 hangs at the top and sways from side to side: flagships `=W=` 60, reds `}@{` 50,
  purples `<O>` 40, blues `/V\` 30.
* Aliens peel off and dive: they swoop out, home in on your ship and drop bombs `!`. A diver that misses loops
  round to the top and flies back into its place. **A diver shot in flight scores double.**
* Three ships. A bomb or a diver that reaches you costs one. Clear the swarm and the next wave comes, diving
  more often.
* **P** pauses, **R** restarts, **Q** quits.

## How it works

* Stellar C runs the game: the keys, the swarm's sway, launching divers, scoring, waves, the title and the
  status line. Each swarm row is one string, `ESC [ rr ; cc H` and its 51 characters, in `FORM`; a sway patches
  the column digits and prints the five rows.
* Each frame's moving parts - the shot, the divers, the bombs and all their drawing - are one `native` block
  (`tick()`), which writes every escape sequence into one buffer, `OB`, that Stellar C then prints once. In
  Stellar C alone that work ran about 5 frames a second; native, about 10.
* `build_galaxia.py` generates that native block and compiles the program: run it, not `scc.py` alone.
* Every erase asks **OCC** what should show in that cell - the shot, a bomb, a diver, else the swarm's own
  byte - and each object hides itself while it erases, so things crossing leave no holes or stray marks.
* `Firmware-Math/galaxia_verify.py` (work repo) rebuilds the screen from the game's state at every frame and
  compares it with a VT100 model: a 1,500-frame robot game into dirty RAM, scoring, lost ships, GAME OVER,
  the next wave, R, Q and a rerun without reloading.
