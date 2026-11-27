# Stellar C (prototype)

A small C-like language that compiles straight to STELLAR bytecode, in the `.lst` house
format (each opcode with its source line, then the clean flashable block).

```
python3 scc.py examples/snake.sc          # -> examples/snake.lst  (+ snake.sym.json)
python3 scc.py prog.sc --vm 2 -o p2.lst   # the same, built to run in VM2 ($5000)
python3 scc.py examples/tasks.sc          # a program with tasks: one .lst for VM1-VM3
```

**Building for VM2-VM4** (`--vm N`): the program is placed at `$4000 + (N-1) x $1000` and its
native code uses VM N's registers (`$3000 + (N-1) x $400`): the D-lines, RUNMC targets, `&array`
and `{var}` addresses all move; the bytecode is relative anyway. Load the VM1 program first - its
.lst claims the other blocks - then the others. `pervm_verify.py` runs the native demo in VM2-VM4.

**Memory ends at `$7EFF`**: on the Elf2K the `$7F00-$7FFF` page is not available, so VM4's block
holds 3,840 bytes, not 4 KB. scc refuses a program (code, data and arrays) that would run past it.

## The language

```c
const W = 80;                        // compile-time constants
u16 score, best;                     // 16-bit unsigned variables -> registers
u8  next, lvl;                       // byte variables -> one byte of memory each
u8  grid[1680];                      // byte arrays (READIDX / WRITEIDX)
u8  rev[] = { 0, 2, 1, 4, 3 };       // initialised arrays; a string is one
patched u8 pos[] = "\e[rr;ccH";      // written before every read: not restored at start

u16 kwait() { ... return getc(); }   // functions, parameters, locals, return values
void main() { ... }
```

### Types

* `u16` - 16-bit unsigned (a register, or two bytes of memory). `u8` - one byte of memory.
* `i16` - 16-bit SIGNED (two's complement, -32768..32767). The same storage and the same `+ - * & | ^ <<`;
  where the sign matters it is used: `< <= > >=` compare signed (both sides + $8000, then unsigned),
  `/` rounds toward zero and `%` takes the dividend's sign (C's rules; a small library routine),
  `>>` is arithmetic (rounds down), and `printi(e)` prints a `-`. An expression is signed if any of
  its operands is (a mixed `i16`/`u16` comparison is a signed one); a constant expression with a minus
  sign in it is folded signed (`-7 / 2` is -3).
* Arrays: `u8 a[n]`, and `u16 a[n]` / `i16 a[n]` - two bytes an element, high byte first (the order
  the firmware's 16-bit copies use). `a[i]`, `a[i] = e`, `&a[i]` (= base + 2i), initialisers
  (`i16 t[] = { -5, 300 };`). `fill`, `copy`, `getline` and `rtcget` work in bytes on `u8` arrays.

Statements: `if/else`, `while`, `for`, `switch`, `break`, `continue`, `return`, `x = e`, `x += e`
(and `-= *= /= %= &= |= ^=`), `x++`, `x--`, `a[i] = e`, calls.
Conditions: `== != < <= > >= && || !` (unsigned). Expressions: `+ - * / % & | ^`,
`<< >>` by a constant, unary `-`, `a[i]`, `&a[i]`, calls.
`switch (e) { case k: ... break; default: ... }` is C's: constant cases (characters too), fall-through,
`break` leaves the switch, `continue` goes to the enclosing loop; it compiles to one `TESTXI` + branch
per case at the top.

Builtins: `putc(e) print("text"|array) printu(e) printi(e) getc() keyready() rand() rand(n) delay(k) halt()
fill(&a[i], value, count) copy(&dst, &src, count)` - and the terminal, number, input, clock and
memory built-ins below.

### The terminal, numbers, a line of input, the clock, absolute memory

| call | does |
|---|---|
| `cls()` | clear the screen, cursor home, normal video |
| `eol()` | erase from the cursor to the end of the line |
| `rev(on)` | reverse video on (`rev(1)`) or off (`rev(0)`) |
| `cursor(on)` | show (`cursor(1)`) or hide (`cursor(0)`) the cursor |
| `at(row, col)` | move the cursor (1-based). Constants are one `PRINTSTR` of a fixed string; variables call a small routine |
| `printz(e, n)` | `e` as exactly `n` digits, zero-padded: `printz(7, 2)` is `07` (n 1-5; a bigger `e` shows its low `n` digits) |
| `printw(e, n)` | `e` right-aligned in `n` columns, space-padded |
| `printh(e)`, `printh(e, n)` | `e` in hex, 4 digits or `n` (1-4) |
| `n = getline(buf)`, `getline(buf, max)` | a line typed into the u8 array `buf`, NUL-terminated, echoed, Backspace works, Enter echoes CR LF; at most `max` characters (default: the array's size - 1) - extra keys are ignored, unlike `$C2 GETSTR`, which has no limit. Returns the length |
| `rtcget(t)` | the date and time into the 8-byte u8 array `t`: sec, min, hour, weekday (0 = Sunday), day, month, year high byte, year low byte - in whatever mode the chip keeps (`$07 RTCGET`, firmware V0061.35) |
| `rtc(n)` | one field of the clock as a number, `n` a constant: 0 second, 1 minute, 2 hour, 3 weekday (0 = Sunday), 4 day, 5 month, 6 the year; 7: 1 if there is a clock chip, else 0 (also in Tiny Stellar C) |
| `ok = rtcset(t)` | set the clock from `t` (same layout; the weekday is worked out). Returns 1 if written, 0 if the firmware refused it (31 February, 25:00, ...) - nothing is written then |
| `peek(a)`, `poke(a, v)` | a byte at the ABSOLUTE address `a` (not the program's own block) |
| `peekw(a)`, `pokew(a, v)` | a 16-bit word, high byte first |

`at()` with variables, `printz`, `printw` and `printh` call small library routines that the
program gets only if it uses them (the arguments go in RF/RE; R0 is borrowed through the VM
stack and given back). They must be statements of their own, not inside an expression.
`peek`/`poke` switch to absolute addressing (`MEMMODE 00`) for one or two opcodes and back,
with no branch in between. `builtins_verify.py` runs `examples/builtins.sc`, which uses every
one, on the clock-chip model and a strict VT100 screen.

### Elf2K I/O (the $01-$0F group)

| call | opcode | does |
|---|---|---|
| `out(e)` | $04 OUTI / $06 OUTX / $05 OUTA | a byte to the output port: the front panel's hex display on port 4. A constant is OUTI, a register variable OUTX (and `out(x >> 8)` its high byte), anything else goes through the Acc |
| `outmem(a)` | $08 OUTMX | the byte at address `a` (`&buf[i]`) to the output port |
| `outport(p)` | $01 DEFOUT | choose the output port, 1-7 (default 4). 2 and 3 are the serial chip: refused |
| `q(e)` | $0A SETQ | the Q lamp: `q(0)` off, `q(1)` on, `q(2)` one blink, `q(3)` two; any non-constant is on if non-zero |
| `scanin()` | $0C SIPA | read the input port now |
| `getin()` | $0E GIPX / $0D GIPA | wait for the EF line (the INPUT button) to go high then low, then read the input port |
| `inport(p)` | $02 DEFIN | choose the input port, 1-7 (default 4; 2 and 3 refused) |
| `efsource(n)`, `efsource(n, 1)` | $03 DEFEF | the EF line `getin()` and `waitef()` wait on, 1-4 (default 4); a second argument of 1 makes it inverted (active low) |
| `ef()`, `ef(n)` | $09 GETEFA | all four EF lines as a mask (bit 0 = EF1 ... bit 3 = EF4); `ef(n)` is 1 if line `n` is on, else 0 (`if (ef(4))` is one test and one branch) |
| `waitef()`, `waitef(n)` | $0F WIP | wait for the `efsource()` line to go active then inactive; or for EF line `n` (1-4, normal) whatever `efsource()` says. The other VMs keep running meanwhile |

Ports and EF lines must be constants, and are checked when the program compiles.
`efsource()` and `waitef()` need two firmware patches, both HW-verified 2026-09-30: DEFEF DZ
(Firmware-Math/DEFEF-DZ-fix.dlines.txt - V0061.34 read the EF line from DEFEF's low nibble, so
the documented `DEFEF 40` stopped the next GIPA/GIPX with error $0E and "inverted" did nothing)
and WIP (WIP-DEFEF-fix.dlines.txt - WIP took its EF line from the OUTPUT port's number). One row
still differs from COMMANDS: GETEFA returns one EF number rather than a set of flags. `waitef(n)`
needs a third patch, WIP Z (WIP-Z-fix.dlines.txt, HW-verified 2026-09-30), which makes WIP 0Z use
EF line Z as the COMMANDS row says. `io_verify.py` checks every call.

## Inline STELLAR: `asm { }`

When you want a particular opcode, or a loop written exactly your way, write it inline.
It is emitted exactly as written, and the compiler's caches are thrown away afterwards.

```c
u16 countkeys() {
    u16 k = 0;
    asm {
    poll:
        SERST                  // a key waiting?
        IFFALSEI @done
        SERIN
        INCX 0{k}              // {k} = the register k lives in, as one hex digit
        GAL @poll
    done:
    }
    return k;
}
```

One command per line: the mnemonic (or its opcode byte in hex), then its operand bytes in
hex, just as the COMMANDS table lays them out. Inside an operand:

| write | means |
|---|---|
| `{x}` | the register holding variable `x`, as one hex digit: `MULTXY {n}{i}`, `COPYAX 1{n}` |
| `{f.x}` | function `f`'s variable `x`, to set up a hand-written `CALL @f` |
| `#e` | two bytes: a constant, `&array` or `&array+k`: `LOADXI 0{p} #&msg` |
| `%e` | one byte, from a constant: `SEROUTI %'*'` |
| `'c'` | one byte, a character |
| `@name` | an address: a label in this function's asm, a function, or `@break` `@continue` `@return` |
| `name:` | defines a label (labels are local to the function) |

Comments start with `//` or `;`. Each command's length is checked against the opcode table,
so a missing or extra byte is reported, not assembled. Variables an asm block names get
registers ahead of the rest, and the block counts as reading them, so they stay live.
The asm may use RD, RE and RF freely (a function's result comes back in RD), but it must
leave RC alone: RC holds 0 for the compiled code. `examples/asmdemo.sc` uses every form,
and `asm_verify.py` runs it.

## Native 1802: `native { }`

For the inner loop that has to be fast, write raw 1802. The compiler assembles it (its
own assembler, `asm1802.py` - no a18 needed), puts it after the program's data where the
STELLAR pre-pass never looks, and emits `RUNMC <its address>` where the block stands.
Summing 200 bytes: 180,149 1802 instructions as a compiled loop, 2,520 native (71x).

```c
native {                        // total = data[0] + ... + data[199]
    LDI hi(&data)
    PHI R7
    LDI lo(&data)
    PLO R7                      ; R7 -> data
    LDI 200
    PLO R8
    LDI 0
    PHI RD
    PLO RD
    SEX R2
loop:
    LDA R7
    STR R2
    GLO RD
    ADD
    PLO RD
    GHI RD
    ADCI 0
    PHI RD
    DEC R8
    GLO R8
    BNZ loop
    LDI hi({total})             ; {total} = where total's VM register lives
    PHI R9
    LDI lo({total})
    PLO R9
    GHI RD
    STR R9                      ; high byte first
    INC R9
    GLO RD
    STR R9
}
```

The whole 1802 instruction set, plus `DB` / `DW` data, `CALL addr` (the firmware's SCRT
call, D4) and `RETN` (D5). Operands are expressions:

| write | means |
|---|---|
| `{x}` | the absolute address of variable `x`'s VM register, high byte (`{x}+1` = low byte) |
| `&a`, `a`, `&a[k]` | the absolute address of array `a` |
| `hi(e)`, `lo(e)` | the two bytes of an address |
| `$41` `0x41` `65` `'A'` | numbers; const names and labels (local to the block) work too |

The compiler takes care of the RUNMC rules:

* The block ends with `exit: SEX R2 / RETN`, so falling off the end, or `BR exit`, goes home.
* Free registers are R7 R8 R9 RB RD RE RF, which the RUNMC handler saves, plus R2 as the
  stack (M(R2) is a scratch byte). Writing R3 (the PC), R6 (the way home), RA (its low
  byte is not restored on V0061.34) or any other register is refused, and so is a bare `SEP`.
* A short branch must land in the page of its operand byte. A block with short branches is
  placed so it does not straddle a page; one too big for a page is refused with "use the
  long form".
* Variables a block names get registers and stay live.

Things the compiler cannot check for you:

* X is unknown on entry. `SEX` before any `STR`, `OUT` or ALU-with-memory instruction.
* RUNMC does not yield: while a block runs, the other VMs wait.
* The addresses are the VM's own: VM1's registers at `$3000` and program at `$4000` (`--vm N`: VM N's).

`examples/nativedemo.sc` sums an array, formats hex, and copies a `DB` string.
`native_verify.py` runs it from clean and dirty memory, and again without reloading.

## Multitasking: `task`, `shared`, `chan`

One program can run as up to four tasks, one per STELLAR VM. Plan and design notes:
`PLANS/Stellar-C-multitasking.md`; the guide's section 16 teaches it.
`examples/tasks.sc` (three tasks: keyboard, counter, main) runs on the Elf2K (HW-verified 2026-10-22,
sent with `RECV TASKS.STL` and run under LTOS): keys typed 150 ms apart all arrive; much faster than that,
some are lost while main prints inside `atomic`, because the UART holds one byte.

```c
shared u16 total;              // one copy for every task (memory, at an address they all agree on)
chan keys[8];                  // a queue of bytes
task keyboard() { while (1) send(keys, getc()); }     // VM2
task counter()  { while (1) total++; }                // VM3: the update is made one step
void main() { u16 k; k = recv(keys); printu(total); } // VM1
```

| write | does |
|---|---|
| `task f() { }`, `task(N) f() { }` | `f` runs in a VM of its own (the next free one, or VM N). No parameters; at most 3 |
| `shared` declarations | one copy, placed after `main()`'s data; every part reaches it by absolute address |
| `chan c[n]` | a ring of n bytes (2-255) plus three shared counters |
| `send(c, v)` / `x = recv(c);` / `ready(c)` | put / take a byte, sleeping while full / empty; how many wait |
| `wait(cond)` | sleep until `cond` (on shared data) is true |
| `atomic { }` | `SETMULTI 00` ... `SETMULTI 01`: no other VM runs meanwhile |
| `turns(n)` | `$C8 SETCIN n`: commands this VM runs a turn (default 3) |
| `stop(t)` / `start(t)` | hold task `t` still (CIDP state 3) / let a stopped one carry on (state 1) |

How it compiles:

* **One `.lst`, every part.** Each part is compiled for its VM's block and registers (the `--vm N`
  machinery), the header lists them, and the D-lines of all of them are one block. A program without
  `task` compiles exactly as before.
* **Start.** `main()`'s first command is `SETMULTI 00`; it marks VM2-VM4 paused (CIDP state `$2Fx5` = 4),
  sets up every shared variable and queue (so a rerun without reloading starts clean), marks them
  running (1), and turns multitasking back on. No task sees half-set-up data.
* **Shared data costs no `MEMMODE`.** STELLAR adds the block's page to an address with no clamp, so VM2
  reaches absolute `$4130` as `$F130` - an ordinary memory variable, one opcode.
* **Updates of shared data are made atomic**: a statement that writes shared data and also reads some
  (`total++`, `a[i] = a[i] + 1`) gets `SETMULTI 00` before it and `SETMULTI 01` after.
* **`wait(c)`**: multitasking off, test `c`; if false, set my own state to 4, multitasking on, and spin
  until the state is 1 again (the scheduler gives a paused VM no turns), then test again. Testing and
  pausing with nothing else running means a wake-up cannot be lost between them.
* **Wake-ups are automatic**: after any statement that writes a shared variable another part's `wait`
  looks at, `TESTMXI` that part's state, and if it is 4 make it 1.
* **`stop(t)`** sets `t`'s CIDP state to 3 (the firmware's "idle"): the scheduler gives it no turns, and
  wake-ups, which only wake a state of 4, pass it by - so a stopped task stays stopped whatever it was
  waiting for. **`start(t)`**, with multitasking off, makes a 3 into a 1; a task stopped while asleep in
  `wait()` then looks at its condition again. `stop()` of the task itself spins until it is started.
  Wake-ups of a task that `stop()` can reach are made with multitasking off, so a `stop()` cannot fall
  between a wake-up's look and its write and be undone (a program without `stop` compiles as before).
* **End.** When `main()` returns it marks every task paused and halts; with no VM left running the
  program ends. A task that returns parks itself (paused, in a loop that pauses it again), so a stray
  wake-up cannot restart it.

Refused at compile time: a plain global used by two parts, `wait` / `getc` / `getline` / `getin` /
`waitef` (or a function that does one) inside `atomic { }`, `break` / `return` out of `atomic { }`, a
`wait` that reads no shared variable or calls a function, `recv` / `send` inside an expression, calling
a task, `stop` / `start` of something that is not a task (or of `main`), `stop()` of itself inside
`atomic { }`, more than 3 tasks or more than 4 blocks. Warned: two parts reading the keyboard, `native { }`
(RUNMC freezes every VM), a busy-wait loop on shared data.

Measured in the simulator (V0061.35): splitting one loop over two VMs takes 1.51x as long (1.19x with
`turns(32)`); the firmware does not count commands run with multitasking off towards a turn, so a task
that spends most of its time in `atomic` gets more than its share. `tasks_verify.py` runs a pipeline
through a queue, three VMs racing on one total (exactly 3,000 - and 1,000 with the update split by
hand, which shows the race is real), a 4-deep queue under load, a two-block `main()` with a task pinned to
VM4, shared arrays, a native block reading shared data, dirty memory and reruns.

## The model

STELLAR has 16 fast registers and no stack frames, so Stellar C works like PL/M or Atari
Action!: **no recursion** (refused at compile time), and every variable has a fixed home.
The compiler decides the homes:

* Most-used variables get registers (R0-RB; RC holds 0 when the program needs a zero,
  RD-RF are expression temporaries and RD carries return values).
* Two variables share a register unless both can hold a live value at once - worked out
  from the call graph and a liveness analysis (a variable only has to survive the calls
  it is actually live across).
* Anything that does not fit gets two bytes of memory.

Every STELLAR rule learned the hard way is in the compiler: address branches only (the
label machinery is not used), relative addressing, `$89 TESTLXY` is strictly `<`, the
`F0 00 00` end marker, arrays the program writes are re-initialised in code at start
(rerun without reloading), `SETSIZE` and the VM claims when a program outgrows 4 KB.
Code generation uses the one-opcode forms: `ADDXI`/`INCX` for `x += k`, `ADDXYZ` for
`x = y + z`, constant offsets folded into `READIDX` bases (`grid[hi - 240]` is one opcode),
`n % d == 0` is `DIVXY` + `TESTREMZ` and shares its divide with a nearby `n / d`,
`if (c) break;` is one branch, and a value already in a register or the Acc is not loaded
again.

## How it compares (simulator, V0061.34)

| program | commands | code bytes | speed |
|---|---|---|---|
| Prime-Gen v07 (hand) | - | 389 | 1.00 |
| `examples/primes.sc` | 95 | 254 | 1.07-1.14x faster, output byte-identical |
| Snake (hand, `build_snake.py`) | 387 | 1171 | step 12,309 instr, poll loop 857 |
| `examples/snake.sc` | 411 | 1262 | step 12,685 instr (+3%), poll loop 855 |

`snake_sc_verify.py` runs the hand-written Snake's own verifier, unchanged, against the
compiled one - and the compiled Snake runs on the Elf2K (HW-verified 2026-10-04).
`types_verify.py` checks 16-bit arrays, signed arithmetic and `switch` against Python.
`shortcut_verify.py` checks that `&&` and `||` stop early: a call on the right runs only when needed.

**A guide** - `GUIDE.md`: the language taught step by step, every example a complete program that
`guide_check.py` compiles, runs and compares with the output the guide shows.

## Not yet

Shifts by a variable amount, structs, longer expressions (three temporaries: split a very long one);
smaller code (shared library routines). The web page (stellarc.html on
stellar-1802.dev) runs this compiler in the browser - re-bake it after a change.
