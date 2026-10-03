# Tic-Tac-Toe — terminal game vs. the computer

A playable game of Tic-Tac-Toe against a computer opponent, running on the RCA
1802 through the STELLAR virtual CPU. Loads at `$4000` (VM1), terminal input and
output. You are **X**; the computer is **O**.

```
 1 | 2 | 3
---+---+---
 4 | X | 6
---+---+---
 7 | 8 | O
```

## What it does

The board is redrawn after every move. Empty cells display their position number
`1–9`, so the board doubles as the input legend — just type the number of the cell
you want. The program validates the move, plays the computer's reply, redraws, and
checks for a win or a draw.

## The computer opponent

A fast heuristic (no search tree needed):

1. **Win** — if the computer can complete a line (two O + one empty), take it.
2. **Block** — otherwise, if the human threatens a line (two X + one empty), block it.
3. **Position** — otherwise take the center, then a corner, then a side.

This plays a solid game — it never misses a win or an obvious block.

## How it works

The game is organized as a set of hand-assembled STELLAR subroutines called with
`CALL`/`RETURN`:

- `DRAWBOARD` — renders the 3×3 grid with separators.
- `READMOVE` — prompts, reads a line, and validates the chosen cell.
- `SCANLINE` — scans the eight winning lines for a given side (used for both
  win-detection and the AI's win/block logic).
- `PICKEMPTY` — the center/corner/side fallback.
- `BOARDFULL` — draw detection.

Terminal I/O (character in/out, string printing, line input) reuses the same
routines proven in the other STELLAR apps on this firmware.

## Running it

Download the `.lst` to VM1 (`$4000`) and start. Type a cell number `1–9` and press
Enter on your turn; the computer replies immediately. Play until someone wins or
the board fills.
