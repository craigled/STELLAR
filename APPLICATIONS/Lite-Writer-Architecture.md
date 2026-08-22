# Lite-Writer — Architecture, Loops & Functions

A higher-level companion to `Lite-Writer-Disassembly.md`. This describes **how the
program is organised**, the **data structures**, and the **shape of each loop and
function** — without walking every byte.

Lite-Writer is a single-buffer, single-cursor text-entry terminal for the STELLAR
VM on the 1802/Elf2K. You type; it echoes and stores characters into a RAM buffer;
control keys manipulate that buffer (delete, kill line, clear, view, save/load, copy
to memory, exit). It's deliberately flat: **one big input loop with a key-dispatch
ladder**, plus a set of small handlers that each return to that loop.

---

## 1. The big picture — one event loop

```
        ┌──────────────── startup ───────────────┐
        │ C7 00 (multitasking off)               │
        │ init registers R1,R2,R3,R5,R9          │
        │ print banner                           │
        │ if buffer non-empty: print "Text is    │
        │ Present"                               │
        └────────────────┬───────────────────────┘
                         │
                         ▼
        ┌─────────────  L01: MAIN LOOP  ─────────────┐
        │ INCH  ← wait for one keystroke             │◄──────────┐
        │                                            │           │
        │ key-dispatch ladder:                       │           │
        │   ^X→exit  ^V→view  ^S→save  ^W→write       │           │
        │   ^L→load  ^K→kill  ^E→end   ^D→del          │           │
        │   DEL/BS→backspace  ^G→help                 │           │
        │   CR→newline  ^U→clear                       │           │
        │                                            │           │
        │ else (printable):                          │           │
        │   if buffer full → ignore                   │           │
        │   echo + store at R1, R1++                  │           │
        │   if R1==warn → print warning               │           │
        └────────────────────┬───────────────────────┘           │
                             │ every handler ends with GTL L01 ───┘
                             ▼
                     ^X only: write $00, HALT
```

Every command handler is a **leaf** that does its work and jumps back to `L01`
(`GTL L01`). Only `^X` breaks the cycle, with `HALT`. This is the classic
read-eval-loop of a line editor, flattened into label branches because STELLAR has
no structured control flow.

---

## 2. Data structures

### The text buffer — one flat byte array with a moving cursor
- **2048 bytes** at real `$5000-$57FF` (relative `$1000-$17FF`).
- **R1 is the cursor / write pointer.** Everything is defined relative to it:
  - bytes `[R2 .. R1)` are "the text so far";
  - the byte at `R1` is where the next character lands;
  - a `$00` at the cursor marks end-of-text for save/load/replay.
- **R2 / R3 / R5** are fixed fenceposts: start (`$1000`), end+1 (`$1800`),
  last (`$17FF`). They never move; they bound the loops.
- **R9 = `$17E0`** is a soft "nearly full" tripwire, 32 bytes before the hard end.

The buffer is **destructive and un-gapped**: there is no insert-in-the-middle.
Editing only ever happens at the tail by moving `R1` backward (delete/kill) or
forward (type). Old bytes aren't scrubbed on delete — they're simply overwritten by
the next keystroke or cut off by the next `$00` terminator. This is why the delete
handlers just decrement `R1` and the save/view handlers stop at the first `$00`.

### Newlines are two bytes
Pressing **Enter** stores a **CR ($0D) + LF ($0A) pair**. This choice ripples
through the whole design:
- **Delete/backspace/kill** peek the byte they land on; if it's `$0A` they step back
  **twice**, so a newline behaves as a single editable unit.
- **View/replay** send the stored CR+LF straight to the terminal, so the on-screen
  layout matches what was typed.

### Save banks
- **Bank 1**: real `$6000-$67FF` (rel `$2000-$27FF`), used by `^S`/`^L`.
- `$6800-$7EFF` is reserved for future banks / a file system (see the TODO).
- These live in the RAM that normally belongs to VM2/3/4. Lite-Writer can own them
  only because it turned **multitasking off** at startup (`C7 00`), pinning the
  scheduler to VM1.

### Strings
Seven null-terminated strings at `$4700+`. Nothing dynamic — every message is a
fixed literal printed by the shared print-string loop.

---

## 3. The two reusable code shapes

Almost the entire program is built from **two loop templates**. Recognising them is
the fastest way to read the disassembly.

### Template A — "print a null-terminated string"
Used for the banner, "Text is Present", the size warning, "File Saved", the help
screen, the "Where?" prompt, and "Copied". Appears as L80, L82, L84, L86, L88, L71,
L78 (seven copies).

```
loop:  Acc ← M(RA)          ; read one byte via the string pointer
       if Acc == 0 → exit    ; null terminator ends the string
       OUTCH                 ; send it
       RA++                  ; next byte
       goto loop
```

### Template B — "walk the buffer between two pointers"
Used for view, end-scan, replay, and all three block copies (save, load, ^W). The
guard is either "pointer reached a fencepost" or "byte read was `$00`".

```
loop:  if iterator == limit → exit
       Acc ← M(iterator)
       (do something: OUTCH, or store to a dest pointer)
       iterator++
       goto loop
```

The **block-copy** variant (save / load / ^W) runs two pointers in lockstep
(`R6` source, `R7` dest) and stops on **either** the `$00` terminator **or** a
hard address limit (`TESTXI R6==$1800`/`$2800`) — belt-and-braces so a buffer with
no terminator still can't run off the end.

---

## 4. Function-by-function

### Startup (`$4000`)
Turns multitasking off, loads the fixed fenceposts into R2/R3/R5/R9, sets the cursor
R1 to the buffer start, prints the banner, and — if the buffer already holds text
from a prior session — prints "Text is Present". Then falls into the main loop.

### Main loop + dispatch — `L01`
1. `INCH` blocks (cooperatively) for a keystroke.
2. A flat ladder of `TESTAI/IFTRUEL` pairs compares the byte against each control
   code and branches to the matching handler on the first hit.
3. If nothing matched, the byte is a printable character: bounds-check against R3,
   echo it, store it at R1, advance, and trip the size warning once at R9.

The dispatch is O(n) in the number of control keys, which is fine — there are ~13,
and a keystroke is glacial next to the CPU.

### Character entry (fall-through of `L01`)
The "default case". Note it reuses the very `Acc` value that the ladder just tested —
no reload needed, since `TESTAI` is non-destructive.

### View — `^V` / `L10`
Template B over `[R2 .. R1)`, printing each byte. Reproduces the document exactly,
CR+LF pairs included.

### Backspace — DEL/BS / `L20`, and Delete char — `^D` / `L30`
Same core: bounds-check, `R1--`, peek; if the byte is `$0A`, step back once more so a
CR+LF vanishes as a unit. The only difference:
- **L20 (backspace)** emits `BS SP BS` to visually erase the glyph on screen.
- **L30 (^D)** does the same cursor math but emits **no** feedback.

### Kill line — `^K` / `L55` — the one genuinely branching function
Two behaviours depending on whether the current line has content:

- **Path A** (current line non-empty): walk backward erasing characters with
  `BS SP BS` feedback until the **previous** CR+LF is reached; keep that CR+LF; drop
  a `$00`. Returns to `L01`. This is a simple in-place erase, so screen and buffer
  stay in sync — no redraw needed.
- **Path B** (current line empty — you just hit Enter): step back over the trailing
  CR+LF, then walk backward through the **previous** line until the CR+LF before *it*
  (or buffer start); drop a `$00`; then **jump into the ^V view** (`L10`) to redraw,
  because a whole line disappeared from the middle of the screen and can't be fixed
  with local backspaces.

Repeated `^K` therefore walks backward one line per press and stops cleanly at the
buffer start. The peek uses R7 as a scratch "look one byte back without moving the
cursor" pointer.

### Newline — CR / `L40`
Stores CR then LF (each bounds-checked separately, so a buffer that fills mid-pair
still terminates cleanly), then echoes CR+LF. The two-byte newline is the linchpin
the delete/kill logic depends on.

### Clear — `^U` / `L50`
A single `FILLMEMXY R2..R5 = $00` wipes all 2048 bytes; reset cursor to start. The
one place the program uses a bulk-memory opcode instead of a hand-rolled loop.

### End — `^E` / `L60`
Two Template-B passes: **scan** forward for the first `$00` (the text end) and park
the cursor there, then **replay** everything from the start so the user can keep
appending at the tail. Also serves as the **shared tail for ^L load**.

### Save / Load — `^S` / `L65`, `^L` / `L66`
Mirror images. Save terminates the text with `$00`, then block-copies buffer→bank1
and prints "File Saved". Load block-copies bank1→buffer, then **falls into `L60`
(^E)** to position the cursor at the end and echo the restored text. Both copies
stop on the `$00` terminator or the respective hard limit.

### Write-to-address — `^W` / `L70` — the arithmetic-heavy function
The only function that does real computation. It prompts `Where?`, reads **four hex
digits**, and assembles them into a 16-bit relative destination address:

- Each ASCII digit → value via `-$30`, with an extra `-$07` if the result is `≥ 10`
  (i.e. it was a letter `A`–`F`). `R8 = 10` is the comparison constant.
- The four nibbles `d1 d2 d3 d4` become `HIGH=d1d2`, `LOW=d3d4`, combined using only
  **4-bit left shifts** (`SHIFTBA ×4`), `ADDAX` accumulation into MA, and a single
  `SWAPA` to promote the HIGH byte — deliberately avoiding any 16-bit shift.
- Then it terminates the text and block-copies buffer→destination, printing "Copied".

Because the VM adds `$4000` in relative mode, `2000`→real `$6000` (bank 1),
`1000`→real `$5000` (the buffer). This is effectively a manual, general-purpose
"save to any bank" primitive — the building block the future multi-file system in
`Lite-Writer-TODO.md` is meant to sit on top of.

> This handler zeroes the accumulator with `LOADAI $0000`, **not** `CLEARA ($6A)`,
> because this firmware build's `$6A` handler crashes the VM.

### Exit — `^X` / `LFE`
Writes a `$00` sentinel at the cursor and `HALT`s. The buffer persists in owned RAM,
so the next launch's "Text is Present" check finds it.

---

## 5. Control-flow / state notes worth knowing

- **Everything is one register file, no stack.** There are no subroutine calls; the
  print-string and copy templates are **inlined** at each use site rather than
  called. That's why the same little loop appears seven times — cheaper and safer on
  this VM than the shaky label-call machinery.
- **The cursor model keeps state trivial.** The entire editor state is *(R1, and the
  bytes below it)*. No separate length field, no line table, no gap buffer. Delete is
  "R1--"; end-of-text is "first `$00`". Simple, and it's why some operations
  (view/end/save) all re-derive the end by scanning rather than tracking it.
- **Dual pointers for peeking.** Where a handler needs to look at a byte *without*
  committing to moving the cursor (all the CR+LF unit handling), it copies R1 into
  R7, decrements R7, and reads through it — R1 only moves once the decision is made.
- **Two independent stop conditions on every copy** (terminator OR address limit)
  make the block copies robust against a missing `$00`.
- **Redraw only when necessary.** In-place edits (type, backspace, Path-A kill) use
  local terminal feedback; structural edits that desync the screen (Path-B kill,
  load) re-enter the view/replay path to repaint.

---

## 6. Boundary behaviour & edge cases (for future editing)

- **Backspace/delete guard is `R1 >= R2` (inclusive).** On a genuinely empty buffer
  (`R1 == R2`) that guard is *true*, so a stray backspace would decrement R1 below
  the start before the CR+LF peek. In normal use the buffer isn't empty when you
  backspace, but if the multi-file/edit work touches these handlers, tightening this
  to a strict "greater-than" (or an explicit empty check) would harden it.
- **The warning fires on exact equality** (`R1 == R9`), i.e. once as the cursor
  passes `$17E0`. Typing continues until `R1 > R3`, after which printable keys are
  silently dropped by the `TESTLXY R1<=R3` bounds check.
- **Save/load are single-bank.** `^S`/`^L` always use bank 1 (`$6000`). `^W` is the
  escape hatch for other addresses today; the TODO proposes numbered banks and a
  named-file directory built on the same copy primitive.

---

## 7. Quick reference — keys → handlers

| Key | Code | Handler | Effect |
|---|---|---|---|
| (printable) | — | L01 fall-through | echo + store at cursor |
| CR / Enter | $0D | L40 | store CR+LF, echo newline |
| Backspace | $7F / $08 | L20 | delete last char (2 for CR+LF), BS-SP-BS feedback |
| ^D | $04 | L30 | delete last char, no feedback |
| ^K | $0B | L55 | kill line (Path A / Path B) |
| ^U | $15 | L50 | clear whole buffer |
| ^V | $16 | L10 | view buffer |
| ^E | $05 | L60 | jump to end, replay, keep typing |
| ^S | $13 | L65 | save buffer → bank 1 |
| ^L | $0C | L66 | load bank 1 → buffer (then ^E) |
| ^W | $17 | L70 | write buffer to a typed 16-bit address |
| ^G | $07 | L67 | help screen |
| ^X | $18 | LFE | write $00 sentinel, HALT |
