# Banner — big-letter ASCII banner printer

An interactive banner printer: type a word and it prints it back in large 5×5
block letters. Runs on the RCA 1802 via the STELLAR virtual CPU. Loads at `$4000`
(VM1), terminal input and output.

```
WORD: STELLAR

 ####  #####  #####  #      #      ####  ####
#        #    #      #      #     #    # #   #
 ###     #    ####   #      #     #####  ####
    #    #    #      #      #     #    # #  #
####     #    #####  #####  #####  #    # #   #
```
*(rendered in `*` characters; shown here approximately)*

## What it does

1. Prints `WORD: ` and reads a line from the terminal.
2. Echoes each keystroke; **Backspace** erases the last character; **Enter**
   finishes the word (up to 13 characters).
3. Prints the word in 5-row-tall block letters.

Supports **A–Z** and **0–9**. Any other character (symbols, spaces, lowercase)
prints as a blank cell rather than garbage.

## How it works

- **Pre-rendered font** — instead of storing letters as bitmaps and testing bits,
  each glyph is stored as literal 5×5 ASCII (ink + space), 25 bytes per glyph, at
  `$4A00` (A–Z, then 0–9, then a blank glyph). Rendering is therefore pure table
  lookup + output — no bit manipulation.
- **Row-major assembly** — a banner is printed one text-row at a time across all
  the letters: for each of the 5 rows, the program walks the input buffer,
  computes each glyph's byte offset (`slot·25 + row·5`), and streams five font
  cells plus a gap.
- **Character → glyph mapping** — `A–Z` map to slots 0–25, `0–9` to 26–35, and
  everything else to a blank glyph, chosen with a small range check.
- **Input handling** — reads via STELLAR's cooperative `SERIN`, detects Enter and
  Backspace, stores characters with the indexed-write op, and echoes a destructive
  `BS SP BS` on backspace.

Font cells are read through a full 16-bit pointer (`COPYIMXA`) because the glyph
table is larger than 256 bytes — the indexed-read op's index register is only
reliable below 256.

## Running it

Download the `.lst` to VM1 (`$4000`) and start. At the `WORD:` prompt, type a word
in **capitals** (A–Z, 0–9), correct with Backspace, and press **Enter** to see it
in lights. Fits an 80-column terminal (≈13 characters).
