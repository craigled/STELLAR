# Mandelbrot — ASCII fractal renderer

> **v09 (2026-09-24):** `Mandelbrot.lst` is now v09, rewritten for firmware V0061.33 -
> the same output byte for byte, about 2.5x faster (~4.4 min on the Elf2K instead of
> ~10.9). MULTXY + SHIFTMA + COPYAX MA make a multiply three opcodes instead of five,
> and the escape loop is inline (no SMUL/SADD calls, no LBL/GTL): ~37 opcodes an
> iteration instead of ~75. A four-VM version, each VM drawing a quarter at the same
> time, is on the website's Multitasking page.

Renders the Mandelbrot set as an ASCII density map to the terminal, computed
entirely on the RCA 1802 through the STELLAR virtual CPU. Loads at `$4000` (VM1),
terminal output only.

```
STELLAR MANDELBROT

                     ....
                  ..........
                .............
              ................. .
             ....................
        .......:::::::=+*:::........
      ......:::::::----=@@=----::::....
     .....::::----==+*@@@@@@@*+==----:::..
 ...:::::--=@@@@@@@@@@@@@@@@@@@@@@@=--:::..
     .....::::----==+*@@@@@@@*+==----:::..
      ......:::::::----=@@=----::::....
        .......:::::::=+*:::........
             ....................
              ................. .
                .............
                  ..........
                     ....
```
*(illustrative — actual output is 40 columns × 24 rows)*

## What it does

For each character cell, the program maps the cell to a point `c` in the complex
plane (real axis `-2.5 … +1.0`, imaginary `-1.2 … +1.2`) and runs the escape-time
iteration `z → z² + c` up to 15 times. The number of iterations survived before
`|z|² ≥ 4` selects a character from a 16-level density ramp (`' '` for points that
escape immediately, `'@'` for points inside the set). A title banner prints first.

## How it works — the interesting part

The 1802 has no multiply and no floating point, so everything is done in
**hand-rolled signed fixed-point**:

- **Q8.8 fixed-point** — each value is an integer scaled by 256.
- **Sign-magnitude arithmetic** — STELLAR's math returns a magnitude plus a
  separate sign byte, so every value is carried as `{magnitude, sign flag}`.
  Helper routines `SMUL` (signed multiply), `SADD`/`SSUB` (signed add/subtract)
  compose the iteration from STELLAR's `MULTXA`, `SHIFTMA`, `ADDXY`, and `SUBXY`
  primitives. Subtraction is always computed larger-minus-smaller (with the sign
  set by hand) so it never takes an unreliable code path.
- **24-bit Math Accumulator** — a `16×16` product can exceed 16 bits, so the
  `(a·b)>>8` scaling reads the high bytes of the 24-bit MA (`SHIFTMA` + `COPYMAA`)
  rather than truncating.

The render is a doubly-nested loop (rows × columns) wrapping the per-pixel escape
loop, which in turn calls the `SMUL`/`SADD` subroutines — all in hand-assembled
STELLAR bytecode.

## Running it

Download the `.lst` to VM1 (`$4000`) and start. It prints the banner, then draws
the fractal **row by row over several minutes** (≈960 pixels × up to 15 iterations,
each with several multiplies, under the VM on a ~MHz 1802). Watching it build is
part of the fun.

## Notes

Building this shook out several previously-undocumented STELLAR firmware behaviors
(the `SHIFTMA` byte-shift, the sign-magnitude number system, and a live bug in the
subtract negate path), which is a nice side benefit of a heavy fixed-point workout.
