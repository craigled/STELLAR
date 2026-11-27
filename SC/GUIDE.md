# Programming in Stellar C

Stellar C is a small C-like language for the RCA 1802. A Stellar C program compiles to STELLAR
bytecode - the same `.lst` file a hand-written STELLAR program is - so it loads on an Elf2K
running the STELLAR firmware, or runs in the web Simulator. This guide teaches it from the first
line to a finished game. Every example in it is a complete program, and every one is compiled
and run by `SC/guide_check.py` with the output shown here - so what you read is what you get.

If you know C, most of Stellar C will look familiar; the differences are the ones the 1802 and
STELLAR impose, and section 12 explains them. If you do not know C, start at section 1.

## 0. Compiling and running your own programs

A Stellar C program is a plain text file, by convention named `something.sc`.

**On the website - nothing to install.** Open the Stellar C page on stellar-1802.dev.
1. Type or paste your program into the Source box (it replaces the example; your edits are kept
   in the browser if you leave and come back - Revert brings the example back).
2. Press **Compile** (Ctrl/Cmd+Enter compiles and runs). Errors show with their line number.
3. Press **Run**. A program that reads keys: click the terminal and type. The input box under
   the example menu types keys for you before the program starts.
4. **Download .lst** saves the compiled program for a real Elf2K.

Every example in this guide has a **Try it** link that opens it there.

**On your computer** - Python 3 and the work repository (`stellar-1802`):

```
python3 SC/scc.py myprog.sc          # writes myprog.lst beside it (and myprog.sym.json)
```

Then either load `myprog.lst` into the Elf2K - its D-lines go to the monitor like any STELLAR
app - and cold-boot STELLAR; or open it in the web Simulator (**Open .lst...**, or drag the file
onto the page) and press **Run**. The `.lst` header says how many STELLAR commands it compiled
to and how much memory it uses; below that is the compiled program, each command beside the
source line it came from.

**A version number.** A line `#version 1.2` (one word, up to 15 characters) puts
`; VERSION:  1.2` near the top of the `.lst`. On LTOS, `RECV NAME.STL` keeps it, and `APPS`
shows it beside the app's size and VMs.

---

## 1. Your first program

```c example=hello
void main() {
    print("Hello from the 1802!\r\n");
    print("2 + 3 = ");
    printu(2 + 3);
    print("\r\n");
}
```

```output
Hello from the 1802!
2 + 3 = 5
```

* Every program has a `main()`; the program starts there and ends when `main()` ends.
* `print("...")` sends text to the terminal; `printu(e)` prints a number.
* A statement ends with `;`. Comments are `// to the end of the line` or `/* ... */`.
* `\r\n` is a new line: carriage return (back to column 1) and line feed (down a row). A terminal
  needs both - `\n` alone moves down without going back to the left edge.
* Other escapes in strings and characters: `\t` tab, `\b` backspace, `\e` escape (for terminal
  codes), `\0`, `\\`, `\'`, `\"`.

---

## 2. Numbers and variables

```c example=numbers
const DOZEN = 12;
u16 eggs, boxes, left;

void main() {
    eggs = 100;
    boxes = eggs / DOZEN;
    left = eggs % DOZEN;
    printu(eggs); print(" eggs make "); printu(boxes);
    print(" boxes, with "); printu(left); print(" left over.\r\n");
    eggs = 65535;
    eggs = eggs + 1;
    print("65535 + 1 = "); printu(eggs); print("\r\n");
}
```

```output
100 eggs make 8 boxes, with 4 left over.
65535 + 1 = 0
```

* `u16` is a 16-bit unsigned number, 0 to 65535. It is the everyday type: most variables are
  `u16`, and the compiler keeps the busiest ones in the 1802's registers.
* Arithmetic is `+ - * / %`; `/` drops the remainder and `%` is the remainder. A result too big
  for 16 bits wraps round (65535 + 1 is 0).
* Bit operations are `& | ^ ~` and shifts `<<` `>>` by a constant number of places.
* `const NAME = value;` gives a value a name; it costs nothing at run time.
* Variables declared outside a function are global (every function sees them); variables
  declared inside a function are local to it.
* Short forms: `x += 5;` `x -= e;` `x *= e;` (and `/= %= &= |= ^=`), `x++;` `x--;`.

---

## 3. Decisions and loops

```c example=fizzbuzz
u16 n;

void main() {
    for (n = 1; n <= 15; n++) {
        if (n % 15 == 0) print("FizzBuzz");
        else if (n % 3 == 0) print("Fizz");
        else if (n % 5 == 0) print("Buzz");
        else printu(n);
        print(" ");
    }
    print("\r\n");
}
```

```output
1 2 Fizz 4 Buzz Fizz 7 8 Fizz Buzz 11 Fizz 13 14 FizzBuzz 
```

* `if (condition) statement else statement` - braces `{ }` group several statements.
* Comparisons: `== != < <= > >=`. Combine them with `&&` (and), `||` (or), `!` (not); `&&` and
  `||` stop as soon as the answer is known.
* Any number can be a condition: 0 is false, anything else is true.
* `while (condition) statement` repeats while the condition is true.
* `for (start; condition; step) statement` is the counting loop.
* `break;` leaves the loop at once; `continue;` skips to its next turn.

```c example=loops
u16 i, total;

void main() {
    total = 0;
    i = 0;
    while (1) {
        i++;
        if (i > 20) break;
        if (i % 2 == 1) continue;
        total += i;
    }
    print("2 + 4 + ... + 20 = "); printu(total); print("\r\n");
}
```

```output
2 + 4 + ... + 20 = 110
```

---

## 4. Functions

```c example=functions
u16 gcd(u16 a, u16 b) {
    u16 t;
    while (b != 0) {
        t = a % b;
        a = b;
        b = t;
    }
    return a;
}

u16 isprime(u16 n) {
    u16 d;
    if (n < 2) return 0;
    for (d = 2; d * d <= n; d++)
        if (n % d == 0) return 0;
    return 1;
}

void main() {
    u16 n;
    print("gcd(1071, 462) = "); printu(gcd(1071, 462)); print("\r\n");
    print("primes below 40:");
    for (n = 1; n < 40; n++)
        if (isprime(n)) { print(" "); printu(n); }
    print("\r\n");
}
```

```output
gcd(1071, 462) = 21
primes below 40: 2 3 5 7 11 13 17 19 23 29 31 37
```

* A function names its result type (`u16`, `i16`, or `void` for none), then its parameters.
* `return e;` hands back a value; `return;` (or the end of the function) leaves a `void` one.
* Functions can call other functions, and calls can be used inside expressions.
* **No recursion**: a function may not call itself, directly or through another. STELLAR has no
  stack frames, so every variable has one fixed home; the compiler refuses a recursive call
  (section 14). Loops do the same work.

---

## 5. Characters, strings and reading the keyboard

```c example=echo input="Hello\r"
u16 k, count;

void main() {
    print("Type, and press Enter: ");
    count = 0;
    while (1) {
        k = getc();
        if (k == '\r') break;
        if (k >= 'a' && k <= 'z') k = k - 'a' + 'A';
        putc(k);
        count++;
    }
    print("\r\n"); printu(count); print(" characters\r\n");
}
```

```output
Type, and press Enter: HELLO
5 characters
```

* A character in single quotes, `'A'`, is its number (65). `putc(e)` prints one character.
* `getc()` waits for a key and returns it. While it waits, the other VMs keep running.
* `keyready()` is true if a key is waiting - for a loop that must keep going (a game) - and
  `getc()` then takes it without waiting.

A string is an array of `u8` (bytes) ending with a 0. `getline` reads a whole line into one,
with Backspace working, and stops at the array's size so a long line cannot overrun it:

```c example=names input="Ada Lovelace\r"
u8 name[16];
u16 n, i;

void main() {
    print("Your name? ");
    n = getline(name);
    print("Hello, "); print(name); print(" - backwards: ");
    i = n;
    while (i > 0) { i--; putc(name[i]); }
    print("\r\n");
}
```

```output
Your name? Ada Lovelace
Hello, Ada Lovelace - backwards: ecalevoL adA
```

* `print(name)` prints a string array up to its 0.
* `getline(buf)` takes at most `size - 1` characters (here 15) and adds the 0; `getline(buf, max)`
  takes fewer. It returns the length. Enter ends the line.

---

## 6. Arrays

```c example=arrays
u8  counts[6];
u16 scores[] = { 300, 1200, 50, 700, 950 };
u16 i, j, t;

void main() {
    // a histogram of 600 dice rolls
    for (i = 0; i < 600; i++) counts[rand() % 6]++;
    t = 0;
    for (i = 0; i < 6; i++) t += counts[i];
    print("rolls counted: "); printu(t); print("\r\n");
    // sort the scores, smallest first (a bubble sort)
    for (i = 0; i < 5; i++)
        for (j = 0; j + 1 < 5 - i; j++)
            if (scores[j] > scores[j + 1]) {
                t = scores[j]; scores[j] = scores[j + 1]; scores[j + 1] = t;
            }
    for (i = 0; i < 5; i++) { printu(scores[i]); print(" "); }
    print("\r\n");
}
```

```output
rolls counted: 600
50 300 700 950 1200 
```

* `u8 a[n]` is n bytes (0-255 each); `u16 a[n]` is n 16-bit numbers; `i16 a[n]` n signed ones
  (section 7). Indexes start at 0. `a[] = { ... }` sets starting values (and the size).
* `rand()` is a pseudo-random 16-bit number (STELLAR's RAND, $C3: about 3,600 1802 steps, some
  16 ms on the Elf2K); `rand(n)` is 0 to n - 1, the same as `rand() % n` - so `rand(6) + 1` is a
  die. `examples/dice.sc` rolls two, and 600 to show the spread.
* `&a[i]` is the address of an element; `fill(&a[0], value, count)` and
  `copy(&dst[0], &src[0], count)` set or copy bytes in one STELLAR command each.
* **Arrays the program changes are set back to their starting values when it starts** - so
  running a program again without reloading it (the Elf2K way) starts it clean.
  (`patched u8 a[] = ...` turns that off for an array whose bytes are always written before
  they are read: a template string, say.)
* There are no bounds checks: `a[10]` of a 10-element array is the next thing in memory.

---

## 7. Signed numbers

```c example=signed
i16 t[] = { -12, 5, -3, 20, -8, 0, 15 };
i16 low, high, sum, x;
u16 i;

void main() {
    low = t[0]; high = t[0]; sum = 0;
    for (i = 0; i < 7; i++) {
        if (t[i] < low) low = t[i];
        if (t[i] > high) high = t[i];
        sum += t[i];
    }
    print("lowest "); printi(low); print(", highest "); printi(high);
    print(", average "); printi(sum / 7); print(" remainder "); printi(sum % 7); print("\r\n");
    x = -7;
    print("x / 2 = "); printi(x / 2); print(", x % 2 = "); printi(x % 2);
    print(", x >> 1 = "); printi(x >> 1); print(", -7 / 2 = "); printi(-7 / 2); print("\r\n");
}
```

```output
lowest -12, highest 20, average 2 remainder 3
x / 2 = -3, x % 2 = -1, x >> 1 = -4, -7 / 2 = -3
```

* `i16` is a signed 16-bit number, -32768 to 32767. Use it wherever a value can go below zero.
* `printi(e)` prints it with its sign (`printu` would show -1 as 65535).
* Where the sign matters, Stellar C uses it: comparisons, `/`, `%` and `>>`. `/` rounds toward
  zero and `%` takes the sign of the number divided (C's rules); `>>` keeps the sign.
* `x >> 1` of -7 is -4, not -3: a shift rounds down, where `/` rounds toward zero.
* An expression is signed if any variable, array or function result in it is `i16`, or if it is
  made only of constants and has a minus sign in it (`-7 / 2` is -3). Comparing an `i16` with
  a `u16` is a signed comparison.

---

## 8. Choosing with `switch`

```c example=switch input="+-*/x"
u16 k, a, b;

void main() {
    a = 20; b = 4;
    while (1) {
        k = getc();
        switch (k) {
            case '+': printu(a + b); break;
            case '-': printu(a - b); break;
            case '*': printu(a * b); break;
            case '/': printu(a / b); break;
            case 'q': case 'x': print("bye"); return;
            default: print("?");
        }
        print(" ");
    }
}
```

```output
24 16 80 5 bye
```

* `switch (e)` jumps to the `case` with e's value, or to `default:` if none matches (and past
  the switch if there is no default).
* Cases are constants: numbers or characters. Several cases can share one body.
* `break;` leaves the switch. Without it, the next case's statements run too ("fall through").
* Inside a loop, `continue;` in a switch goes to the loop's next turn.

---

## 9. The terminal screen

The Elf2K's terminal is a VT100: text can be placed anywhere, shown in reverse video, erased.

```c example=screen
u16 r, n;

void main() {
    cls();
    at(1, 1); rev(1); print(" REPORT "); rev(0);
    at(3, 3); print("row   value   padded   hex");
    for (r = 0; r < 4; r++) {
        n = r * 1234 + 5;
        at(4 + r, 3); printu(r);
        at(4 + r, 9); printw(n, 5);
        at(4 + r, 17); printz(n, 5);
        at(4 + r, 26); printh(n);
    }
    at(9, 1);
}
```

```screen
 REPORT

  row   value   padded   hex
  0         5   00005    0005
  1      1239   01239    04D7
  2      2473   02473    09A9
  3      3707   03707    0E7B
```

| call | does |
|---|---|
| `cls()` | clear the screen, cursor to the top left |
| `at(row, col)` | move the cursor (rows 1-24, columns 1-80) |
| `rev(1)` / `rev(0)` | reverse video on / off |
| `eol()` | erase from the cursor to the end of the line |
| `cursor(0)` / `cursor(1)` | hide / show the cursor (hide it while a game draws) |
| `printw(e, n)` | e right-aligned in n columns |
| `printz(e, n)` | e as n digits with leading zeros: `printz(7, 2)` is `07` |
| `printh(e)` / `printh(e, n)` | e in hexadecimal, 4 or n digits |

The terminal does NOT scroll when something is written on the bottom row - draw a full-screen
program with `at()` rather than by printing new lines.

---

## 10. Keys, time and games

A game is a loop: look for a key without waiting, move things, draw, wait a little, repeat.

```c example=game input="\x1b[C\x1b[C\x1b[C\x1b[Bq" noexit steps=6000000
u16 x, y, k;

u16 key() {                     // a key: 'U' 'D' 'L' 'R' for the arrows, 0 if none
    if (!keyready()) return 0;
    k = getc();
    if (k != 27) return k;      // not ESC: an ordinary key
    k = getc();
    if (k == '[') k = getc();   // ESC [ A ... - the '[' may have been lost (see below)
    switch (k) {
        case 'A': return 'U';
        case 'B': return 'D';
        case 'C': return 'R';
        case 'D': return 'L';
    }
    return 0;
}

void main() {
    x = 10; y = 5;
    cls(); cursor(0);
    at(1, 1); print("Arrows move the star, q quits");
    while (1) {
        at(y, x); putc('*');
        delay(10);
        k = key();
        if (k == 'q') break;
        if (k == 0) continue;
        at(y, x); putc(' ');
        switch (k) {
            case 'U': if (y > 2) y--; break;
            case 'D': if (y < 23) y++; break;
            case 'L': if (x > 1) x--; break;
            case 'R': if (x < 79) x++; break;
        }
    }
    cursor(1); at(24, 1);
}
```

```screen
Arrows move the star, q quits




            *
```

* `keyready()` tests for a key without waiting; `getc()` takes it.
* An arrow key sends three characters: ESC, `[` and a letter (`A` up, `B` down, `C` right,
  `D` left). They arrive about 1 ms apart and the Elf2K's serial chip holds only one, so a busy
  program can find the `[` overwritten - which is why `key()` above accepts ESC followed
  straight by the letter too.
* `delay(k)` waits about 4 ms per unit at the Elf2K's 3 MHz. It holds the whole 1802 while it
  waits (other VMs stop), so keep delays short in a program that shares the machine.
* `rand()` gives a different sequence in each VM; call it while waiting for a key to stir it.

---

## 11. The Elf2K's hardware

**The front panel.** `out(e)` shows a byte on the two-digit hex display; `q(1)` / `q(0)` turns
the Q lamp (and anything wired to Q - a speaker) on and off.

**The INPUT switch** is EF line 4: `ef(4)` is 1 while it is held; `waitef(4)` waits for one press
and release (the other VMs keep running meanwhile).

**The clock.** `rtcget(t)` fills an 8-byte `u8` array with the date and time from the Elf2K's
DS12887 clock chip (firmware V0061.35 or later):

```c example=clock
u8 t[8];

void main() {
    rtcget(t);
    print("Today is ");
    printu(t[6] * 256 + t[7]); putc('-'); printz(t[5], 2); putc('-'); printz(t[4], 2);
    print(", the time is ");
    printz(t[2], 2); putc(':'); printz(t[1], 2); putc(':'); printz(t[0], 2);
    print("\r\n");
}
```

```output
Today is 2026-10-04, the time is 14:23:07
```

| `t[0]` | `t[1]` | `t[2]` | `t[3]` | `t[4]` | `t[5]` | `t[6]`, `t[7]` |
|---|---|---|---|---|---|---|
| second | minute | hour | weekday, 0 = Sunday | day | month | year, high and low byte |

`ok = rtcset(t)` sets the clock from the same layout and returns 1 - or 0 if the date is
impossible (31 February), in which case nothing is changed.

`rtc(n)` gives one field as a number, with no array: `rtc(0)` the second, `rtc(1)` the minute,
`rtc(2)` the hour, `rtc(3)` the weekday (0 = Sunday), `rtc(4)` the day, `rtc(5)` the month,
`rtc(6)` the whole year (2026), and `rtc(7)` is 1 if the Elf2K has a clock chip at all (0: the
others mean nothing). `n` must be a constant. Tiny Stellar C (`SC` on LTOS) has `rtc(n)`, `q(n)`,
`ef(n)` and `waitef(n)` too - there `q` takes a constant (`if (x) q(1); else q(0);`).

**Memory outside the program.** `peek(a)` and `poke(a, v)` read and write a byte at an absolute
address; `peekw` / `pokew` a 16-bit word. Programs normally never need them - they are for
sharing data with other programs (Time Grab Store's log at `$4B00`, say). Never write at `$8000`
or above: that is the Elf2K's own firmware.

---

## 12. How STELLAR shapes the language

Stellar C is small because the machine is small. Knowing why saves surprises.

* **No recursion, fixed homes.** Every variable lives in one place for the whole run - one of
  the VM's 16 registers, or two bytes of memory. The compiler gives registers to the busiest
  variables and lets two variables share a register when they are never in use at the same time.
* **Three scratch registers.** An expression is worked out in at most three temporary registers.
  A very long expression is refused ("expression too deep") - split it into two statements:
  `t = a * b + c; x = t / (d + e);`
* **`u8` variables cost more than `u16`.** A `u8` lives in memory and goes through the
  accumulator; use `u8` for arrays and for saving space, `u16` for the variables you work with.
* **Program size.** A VM's program block is 4 KB. A bigger program automatically takes two or
  three blocks (`SETSIZE`), leaving fewer VMs free - the `.lst` header says how much it uses.
* **Rerun without reloading.** The Elf2K runs a program again from memory as the last run left
  it; Stellar C resets the arrays a program changes and sets variables in code, so a rerun
  starts clean.
* **Sharing the machine.** `getc()`, `getline()` and `waitef()` let the other VMs run while they
  wait; `delay()`, a `native { }` block and long `rtcget` waits do not. Section 16 shows one
  program running as several tasks.

---

## 13. Faster code: `asm { }` and `native { }`

Most programs never need these. When one inner loop must be faster, you can write it in STELLAR
commands (`asm`) or in raw 1802 machine code (`native`, about 70 times faster than compiled code).

```c example=asmdemo
u16 n, total;

void main() {
    n = 10; total = 0;
    asm {
    loop:
        ADDXYZ {total}{n} 0{total}     // total = total + n
        DECX 0{n}
        TESTXZ 0{n}
        IFFALSEI @loop
    }
    print("10 + 9 + ... + 1 = "); printu(total); print("\r\n");
}
```

```output
10 + 9 + ... + 1 = 55
```

* In `asm { }`, one STELLAR command a line: the mnemonic, then its operand bytes in hex as the
  COMMANDS table lays them out. `{x}` is the register variable `x` lives in (one hex digit),
  `@label` an address, `#e` a two-byte constant or `&array`, `%e` a one-byte constant.
* `native { }` is raw 1802 assembly, run with `RUNMC`. Free registers: R7 R8 R9 RB RD RE RF; set
  X with `SEX` before using memory; a native block holds the whole CPU while it runs. See
  `SC/README.md` and `examples/nativedemo.sc`.
* The compiler checks each command's length and refuses registers that are not safe to use.

---

## 14. When the compiler says no

Compile errors name the line and say what is wrong. The common ones:

```c error=recursion
u16 fact(u16 n) {
    if (n < 2) return 1;
    return n * fact(n - 1);
}
void main() { printu(fact(5)); }
```

```error
fact() is recursive
```

A function that calls itself - write it as a loop instead.

```c error=toodeep
u16 a, b, c, d, e, f, x;
void main() { x = (a * b + c) / (d * e + f * (a + b)); }
```

```error
expression too deep
```

More than three temporary results at once - split the expression with a helper variable.

```c error=badcase
u16 k;
void main() {
    k = 1;
    switch (k) { case 1: k = 2; case 1: k = 3; }
}
```

```error
case 1 twice
```

| message | means |
|---|---|
| `expected ;, found ...` | a missing `;`, `)` or `}` just before that point |
| `unknown variable 'x'` | not declared (or declared in another function) |
| `no function f()` | a call to a function that does not exist |
| `f() takes 2 arguments` | the wrong number of arguments |
| `... can only be a statement of its own` | `at()`, `printz()`, `printw()`, `printh()` inside an expression |
| `getline(buf): buf must be a u8 array` | `getline` and `rtcget` need a byte array |
| `break outside a loop` | `break` / `continue` with no loop (or `continue` in a switch with no loop) |
| `the program needs 16 KB` | the program is bigger than three 4 KB blocks |
| `x is used by main() and t(): make it shared` | two tasks use a plain variable |
| `getc() inside atomic { }` | a wait inside `atomic`: every other task would stop |
| `recv() must be a statement of its own` | write `x = recv(c);`, then use `x` |
| `stop(x): x is not a task` | `stop` / `start` take a task's name (not `main`, not a function) |

---

## 15. A complete program: Hi-Lo

Everything together: a function, a loop, `getline`, a `switch`, the terminal.

```c example=hilo input="50\r25\rabc\r12\r18\r21\r23\rn\r"
u8  line[6];
u16 secret, guess, tries, n, i, ok;

u16 number() {                  // the digits typed, as a number (65535 if there are none)
    n = 0; ok = 0;
    for (i = 0; line[i] != 0; i++)
        if (line[i] >= '0' && line[i] <= '9') { n = n * 10 + line[i] - '0'; ok = 1; }
    if (!ok) return 65535;
    return n;
}

void main() {
    while (1) {
        secret = rand() % 100 + 1;
        tries = 0;
        print("\r\nI have a number from 1 to 100.\r\n");
        while (1) {
            print("Your guess? ");
            getline(line);
            guess = number();
            if (guess == 65535) continue;
            tries++;
            if (guess < secret) print("  higher\r\n");
            else if (guess > secret) print("  lower\r\n");
            else break;
        }
        print("Yes! "); printu(secret); print(" in "); printu(tries); print(" tries.\r\n");
        print("Again (y/n)? ");
        getline(line);
        switch (line[0]) {
            case 'y': case 'Y': continue;
        }
        print("Bye.\r\n");
        return;
    }
}
```

```output

I have a number from 1 to 100.
Your guess? 50
  lower
Your guess? 25
  lower
Your guess? abc
Your guess? 12
  higher
Your guess? 18
  higher
Your guess? 21
  higher
Your guess? 23
Yes! 23 in 6 tries.
Again (y/n)? n
Bye.
```

That game was played by the guide's checker, typing the guesses in. `rand()` decides the secret,
so a game on your machine will be a different one. Notice that `abc` was simply asked again:
`number()` returns 65535 when no digit was typed, and `continue` goes round for another guess
without counting it as a try.

---

## 16. Several tasks at once

STELLAR runs up to four virtual machines (VMs) on the one 1802, taking turns a few commands at a time.
A Stellar C program can use them: mark a function `task`, and it runs in a VM of its own beside
`main()`. The compiler places every part, gives them shared variables, and puts it all in one `.lst`.

```c example=pipeline input="hello\r" gap=100000
chan raw[8];                // keys, from keyboard() to upper()
chan done[8];               // capital letters, from upper() to main()
shared u16 letters;         // how many letters upper() changed

task keyboard() {           // VM2: owns the keyboard
    u16 k;
    while (1) {
        k = getc();
        send(raw, k);
        if (k == '\r') return;
    }
}

task upper() {              // VM3: does the work
    u16 k;
    while (1) {
        k = recv(raw);
        if (k >= 'a' && k <= 'z') { k = k - 32; letters++; }
        send(done, k);
        if (k == '\r') return;
    }
}

void main() {               // VM1: shows the result
    u16 k;
    print("type a line: ");
    while (1) {
        k = recv(done);
        if (k == '\r') break;
        putc(k);
    }
    print("\r\n"); printu(letters); print(" letters changed\r\n");
}
```

```output
type a line: HELLO
5 letters changed
```

* **`task name() { ... }`** runs in its own VM: `main()` is VM1, the tasks take VM2-VM4 in the order
  they are written (`task(4) name()` asks for a particular VM). At most three tasks, fewer if a part
  needs more than 4 KB. A task has no parameters; when it returns, it simply stops.
* **`shared u16 x;`** (and `shared u8 a[n];`, `i16`, initialisers) is one copy that every task reads
  and writes. Anything else is private to one task: a plain variable used by two tasks is an error.
  Each VM has its own registers, so a function called by two tasks works in both (it is copied).
* **`chan name[n];`** is a queue of up to `n` bytes. `send(c, v)` puts one in (and waits while the
  queue is full); `x = recv(c);` takes one out (and waits while it is empty); `ready(c)` says how many
  are waiting. A task that waits costs nothing: it gets no turns until there is something to do.
* **`wait(condition)`** sleeps until the condition (on shared variables) is true. The compiler wakes
  the task when another task changes one of those variables.
* **`atomic { ... }`** lets no other task run until the block ends - for steps that must not be cut,
  like moving the cursor and printing, or changing two shared variables together. Waiting for a key
  inside one is refused: everyone would stop.
* **`stop(name)` / `start(name)`** hold a task still and let it carry on.
* When `main()` ends, the whole program ends.

STELLAR switches VMs between commands, never in the middle of one. `total++` on a shared variable is
four commands, so another task could change `total` between the read and the write, and its update
would be lost. The compiler makes every update of shared data one step for you:

```c example=together
shared u16 total;
shared u8 finished;

task helper() {
    u16 i;
    for (i = 0; i < 500; i++) total++;
    finished = 1;
}

void main() {
    u16 i;
    for (i = 0; i < 500; i++) total++;
    wait(finished == 1);
    printu(total); print("\r\n");
}
```

```output
1000
```

One task can hold another still and let it go again: **`stop(name)`** gives task `name` no more turns,
**`start(name)`** lets it carry on from where it was. A stopped task is not woken by the variables its
`wait()` looks at; once started, it looks again. A task can stop itself - `stop(me)` inside `me()` -
and then waits there until another task starts it.

```c example=pausing
shared u16 ticks;

task clock() { while (1) ticks++; }       // counts in the background

void a_while() { u16 i; i = 0; while (i < 300) i++; }

void main() {
    u16 t;
    a_while();
    stop(clock);
    t = ticks; a_while();
    if (ticks == t) print("clock stopped\r\n");
    start(clock); a_while();
    if (ticks != t) print("clock running again\r\n");
}
```

```output
clock stopped
clock running again
```

`main()` cannot be stopped: when it ends, the program ends.

```c error=stopmain
task helper() { }
void main() { stop(main); }
```

```error
main() cannot be stopped or started
```

```c error=notshared
u16 count;
task helper() { count = 1; }
void main() { count = 2; }
```

```error
count is used by main() and helper(): make it shared
```

Good to know:

* **Tasks make a program more responsive, not faster.** There is still one 1802: splitting a loop in
  two tasks makes it about 1.5 times *slower* (the switching costs time). Use tasks so one part can
  wait - for a key, a line, another task - while the others carry on.
* **Turns.** A VM runs 3 commands, then the next one gets a turn. `turns(n)` changes that for the
  task that runs it (1-255): longer turns waste less time switching, shorter ones answer sooner.
  Time inside `atomic { }` does not count towards a turn.
* **One keyboard.** If two tasks read keys, whichever asks first gets each one - the compiler warns.
  Give the keyboard to one task, as `keyboard()` does above.
* **Printing.** One `print("...")` comes out whole; two prints from two tasks can mix. Put them in
  `atomic { }`.
* `native { }` stops every VM while it runs (the compiler warns).

---

## Quick reference

* Types: `u16`, `i16`, `u8` (and arrays of each); `const`; `patched` arrays.
* Statements: `if`/`else`, `while`, `for`, `switch`/`case`/`default`, `break`, `continue`,
  `return`; assignment `= += -= *= /= %= &= |= ^=`, `++`, `--`.
* Operators: `+ - * / %  & | ^ ~  << >>` (by a constant)  `== != < <= > >=  && || !`, unary `-`.
* Output: `putc print printu printi printw printz printh`; screen: `cls at rev eol cursor`.
* Input: `getc keyready getline`. Other: `rand delay halt fill copy`.
* `#version 1.2`: the app's version, in the `.lst` for LTOS's `APPS`.
* Tasks: `task f()`, `task(N) f()`, `shared`, `chan c[n]`, `send recv ready wait turns`, `stop(t) start(t)`, `atomic { }`.
* Hardware: `out q ef waitef getin scanin outport inport efsource rtcget rtcset peek poke
  peekw pokew`.
* Full details, the inline `asm` / `native` rules and how the compiler works: `SC/README.md`.
