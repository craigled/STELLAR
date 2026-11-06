# STELLAR, Stellar C and LTOS

Software for the RCA COSMAC 1802, a microprocessor from 1976, running on a COSMAC Elf 2000 (the "Elf2K") from Spare Time Gizmos. By Craig Ledbetter.

- **STELLAR** is a multitasking virtual machine: four programs at once on one 1802.
- **Stellar C** is a small C-like language that compiles to STELLAR.
- **LTOS** (LiteOS) is a disk operating system with a Unix-like shell, on a CompactFlash card.

You don't need any hardware to try them:

- In a browser: https://stellar-1802.dev
- In the Emma 02 emulator: see "Running on Emma 02" below.

Current versions: STELLAR firmware V0061.37, LTOS 0.5.

## STELLAR

"System for Time-shared Execution on Low-Level Architecture Resources"

STELLAR sits between the bare chip and your program. A STELLAR program is a list of commands, one byte each plus any operands, and STELLAR's firmware carries them out. The firmware is about 12 KB of 1802 machine code at the bottom of RAM, and it was written directly in hex, with no assembler.

The 1802 has sixteen 16-bit registers, but no stack instructions, no call or return, no multiply and no divide. STELLAR gives its programs all of those, as 198 commands.

What it can do:

- **Run four programs at once.** Each runs in its own virtual machine (VM), with its own registers, stacks, labels and 4 KB program block. A scheduler gives each VM a few commands in turn, and a VM waiting for a key gives up its turn.
- **Let VMs work together.** A shared page, the CIDP, lets VMs watch and signal each other. One VM can start, pause, stop or reach into another.
- **Do real arithmetic.** 16- and 32-bit add, subtract, multiply and divide, and 8-digit decimal conversion in both directions.
- **Handle text and screens.** Strings, a VT100 terminal, keys, and number printing.
- **Use the hardware.** The front panel switches and display, the Q output, EF inputs, I/O ports and the real-time clock.
- **Go fast when needed.** One command, RUNMC, runs raw 1802 code and comes back, about a hundred times faster than the same work in commands.
- **Help you debug.** Error codes for each VM and a trace mode.
- **Run bigger programs.** A program can take a second or third 4 KB block.

Dozens of programs have been written for it and run on the real machine: games (Freefall, Galaxia, Snake, Bounce, Breakout, Mazes), STELLAR Orbit (an Apollo 7 flight on three VMs), Lite-Writer (a word processor), calculators, Mandelbrot sets, Morse code sending and receiving, a Life race, and a job scheduler.

## Stellar C

Stellar C is a small C-like language that compiles straight to STELLAR commands. The compiler is written in Python, and it also runs in the browser on the Stellar C page.

    u16 n;
    void main() {
        for (n = 1; n <= 5; n++) {
            printu(n * n);
            putc(13); putc(10);
        }
    }

What it can do:

- **The usual language:** functions, parameters and local variables, `if`, `while`, `for`, `switch`, and expressions with C's operators.
- **Types:** `u8`, `u16` and signed `i16`, with arrays and strings.
- **Terminal and keyboard:** cursor positioning, formatted numbers, reading a key or a whole line.
- **The Elf2K itself:** the front panel, Q, EF lines, the clock, and random numbers.
- **Several tasks at once:** a program can run as tasks on STELLAR's VMs, each with a share of the chip.
- **Speed when you want it:** `asm { }` for inline STELLAR commands, and `native { }` for inline 1802 code.
- **Output for real hardware:** a `.lst` file of hex lines to load into an Elf2K. LTOS can take the same file with `RECV NAME.STL` and run it as an app.

The Stellar C guide on the website teaches the language from the first program upward, with a Try It link for each example.

## LTOS

LTOS is a disk operating system for the Elf2K. It boots from a CompactFlash card with a FAT16 file system, so a PC, Mac or Linux machine can read the same card. The kernel is about 10 KB of 1802 code.

What it can do:

- **Files and folders:** DIR, TYPE, COPY, MV, REN, RM, MKDIR, RMDIR, CD, PWD, TREE and FIND, with paths and wildcards.
- **A trash folder:** DELETE moves files to /TRASH, and EMPTY deletes them for good.
- **Text tools:** GREP, SORT, UNIQ, WC, HEAD, TAIL, CAT, and EROFF, a small nroff.
- **awk:** RAWK is an awk written in 1802 code.
- **Editors:** NANO, a small editor in the style of GNU nano, written from scratch in 1802 code and not part of the GNU project; Lite-Writer 2 (LW2) and Lite-Writer 3 (LW3) on STELLAR, for files up to 60 KB.
- **A shell:** line editing with the last command recalled, `>` and `>>` on any command, scripts with variables, `if`, loops, functions, `case` and `$(command)`, and /AUTOEXEC.SH at boot.
- **Moving files:** XFER sends files of any size to and from a PC/Mac/Linux with error checking. RECV and SEND use plain Intel HEX.
- **Looking after the card:** FSCK checks it, FREE shows the space, and DISKINFO reports everything about the card.
- **Running STELLAR:** type an app's name, such as GALAXIA, and LTOS loads the STELLAR firmware and the app. Esc comes back to LTOS.

Type HELP at the prompt for every command, or HELP NAME for one. RUNNING shows a man in white blocks, in 1802 code, and WALK is the same man as a STELLAR app. Esc stops either.

## The website: stellar-1802.dev

Everything on the site runs the real firmware on an emulated 1802 in your browser. Nothing to install.

- **Home:** four STELLAR programs running at once, with the chip's memory lit up beside them.
- **The machine:** what STELLAR is, how it works and what it runs on.
- **Architecture:** the memory map, registers, calls and how multitasking is built.
- **VM Core:** one VM's 256 bytes of state, live, as a program runs.
- **Simulator:** load a program and run it, or step one command at a time and watch every bit change on an LED console. Also has the firmware and programs to download for a real Elf2K.
- **Multitasking:** watch the scheduler hand the chip from VM to VM.
- **Opcodes:** every command, with worked examples that were all run on the firmware. Click a description to see them.
- **Apps:** the programs, with pictures. Click one to run it in the Simulator, then click the terminal to use the keyboard.
- **Stellar C:** write, compile and run a program. The guide is linked from there.
- **LTOS:** the real LTOS booting from a simulated card, with a list of things to try. Changes you make are kept in your browser, Restore puts the card back, and you can download the whole card as an image.

Tip: the LTOS page runs at 10 times the Elf2K's speed. Choose Elf2K to feel the real machine.

## Running on Emma 02

[Emma 02](https://www.emma02.hobby-site.com) is Marcel van Tongeren's emulator for 1802 computers, and it includes the Elf 2000. LTOS runs on Emma 02 V2.00, including STELLAR and its apps.

**Get the kit:** download `LTOS-for-Emma02.zip` from the LTOS page of the website. It holds:

| File | What it is |
|---|---|
| `ltos-card.ide` | The card image |
| `ltos.xml` | The Elf 2000 setup: ROM, card, terminal, clock and sound |
| `rtcdump.bin` | A starting clock file |
| `README.txt` | Short install notes |

**Install:** find your Emma 02 data folder, the one holding the `Elf2K` and `Xml` folders. On a Mac it is usually `Emma 02` in your home folder. Then copy:

- `ltos-card.ide` into `Elf2K/`
- `ltos.xml` into `Xml/Elf2K/`
- `rtcdump.bin` into `Elf2K/`, unless your Elf 2000 already starts and shows its banner. See "If it doesn't work".

**Run:**

1. Start Emma 02 and choose COSMAC Elf 2000.
2. Set XML to `ltos.xml`.
3. Check that IDE 0 says `ltos-card.ide` and that the ROM is `Elf2Kv112.bin`.
4. Press Start.
5. Click in the VT 100 window and press Enter. The ROM's banner and `>>>` appear.
6. Type `BOOT` and press Enter. You are at the `LTOS>` prompt.

Try `HELP`, `DIR /BIN`, `RUNNING`, `WALK`, `GALAXIA` or `DISKINFO`.

**Sound:** `ltos.xml` turns on Q as a 700 Hz tone, using Emma's Q sound setting. Emma's own Elf 2000 UART setup has no sound, so Q is silent there. To add it to another setup, put this in the XML file:

    <sound type="q">
        <hw>700</hw>
    </sound>

**Moving files on and off the card:** close Emma 02 first, because LTOS keeps part of the disk in memory. `ltos-card.ide` is a raw card image with a FAT16 partition 32,768 bytes (64 sectors) in. Names must be 8.3.

- Mac: `hdiutil attach -imagekey diskimage-class=CRawDiskImage ltos-card.ide`
- Linux: `sudo mount -o loop,offset=32768 ltos-card.ide /mnt`
- Windows: use a tool that mounts raw images, such as OSFMount.

Delete any hidden files your computer adds before you unmount it. Keep a copy of the image, because Emma 02 writes to it.

**If it doesn't work:**

| What you see | What to do |
|---|---|
| Blank terminal, panel stuck showing 74 | The clock file is missing or empty. Copy `rtcdump.bin` into `Elf2K/`, or tick Clear non-volatile RTC, then start again. |
| Keys do nothing | Click in the VT 100 window. It must be the front window. |
| `?DRIVE ERROR` at BOOT | Press Reset and type `BOOT` first. `SHOW IDE` before `BOOT` caused this here. |
| No `IDE Master` line in the banner | IDE 0 isn't finding the file. Check that `ltos-card.ide` is in `Elf2K/`. |
| No sound | Check that the Volume slider isn't at zero, and that you are using `ltos.xml`. |

DISKINFO shows the file name as the card's model and 26 MB as its size. That comes from Emma's disk settings, and the card image itself is about 8 MB.

## How it got here

The git history starts in February 2026. Before that, the firmware was already written by hand in hex.

- **February 2026:** Audits of the firmware, command group by command group, fixed the math, tests, jumps and conversions.
- **July:** Work moved into one project. Indexed arrays (READIDX and WRITEIDX) were designed, and Morse code, the Mandelbrot set and Banner appeared.
- **August:** Lite-Writer grew into a real word processor. SETSIZE let a program take more than one block. The website began.
- **September:** The firmware was put in strict order and every command was swept for faults. V0061.27 to V0061.33 were verified on the real Elf2K. Freefall ran, and on 29 September Stellar C compiled its first programs.
- **Early October:** V0061.35 added the real-time clock command. Cron, a job scheduler, and the Lunar Mission (later STELLAR Orbit) arrived.
- **12 October:** LTOS began as a CompactFlash driver, boot sector and serial installer.
- **Later in October:** LTOS gained folders, the line editor, its tools, FSCK and XFER, then RAWK, the shell with scripts, EROFF, Lite-Writer 3 and NANO. V0061.36 added one-shot absolute addressing and register-based array access, and LTOS 0.5 became the main line. Stellar C gained multitasking, and LTOS joined the website.
- **November:** Every command got worked examples on the Opcodes page. A review of the test programs led to V0061.37, which uses all 32 bits of the Math Accumulator everywhere, converts 8 digits both ways, and fixes indirect jumps. LTOS gained DELETE, EMPTY, RUNNING and progress dots, and now runs on Emma 02.

## Ideas for the future

**STELLAR**

- Convert the DA remainder in CVT2HEX, the one known gap in the 8-digit work.
- Write up the rules for decimal mode and the Overflow flag.
- Add floating point as firmware commands, building on the work in Calc and SAWK.
- A debugger that runs from the terminal: breakpoints, single step and watching a VM's registers.
- Use more of the 1802's successors, such as the 1805's extra instructions, for speed.

**Stellar C**

- A standard library for strings and file access.
- Structs, and long (32-bit) numbers using the Math Accumulator.
- File access under LTOS, so that a Stellar C program can read and write the card.
- A compiler that runs on LTOS itself, which would need a much smaller design.
- Better error messages that point at the line and show what was expected.

**LTOS**

- Long file names, read at least, for files from other computers.
- A full-screen file browser, and an UNDELETE that restores from /TRASH.
- Pipes between commands, such as `SORT FILE | UNIQ`.
- More awk: decimals in RAWK, as SAWK has on STELLAR.
- Networking or remote access to the Elf2K over its serial port, perhaps through a Wi-Fi bridge.
- Run LTOS programs and STELLAR apps side by side.

**The website and Emma 02**

- Pace the web terminal at the real baud rate, so that programs like RUNNING look as they do on hardware.
- Finish the History section on the site.
- Offer the kit to the Emma 02 project, and report the clock start-up problem.
- A short video of each program on the real Elf2K.

## License

Copyright (C) 2026 Craig Ledbetter.

LTOS, the STELLAR firmware, the Stellar C compiler and the programs here are free software: you can use, change and share them under the GNU General Public License, version 3 or any later version (GPL-3.0-or-later). They come with no warranty. The full text is in `COPYING`, and on the card as `COPYING.TXT`.

**Programs you compile are yours.** The Stellar C compiler copies some of its library routines into your program, so an exception (`COPYING.EXCEPTION`) lets you use what it produces on any terms you like.

The source of LTOS is in the `LTOS` folder, the Stellar C compiler in `web/sc`, and the programs in `APPLICATIONS` and `web/samples`.

The documentation, including this README and the Stellar C guide, is under the Creative Commons Attribution-ShareAlike 4.0 licence (CC BY-SA 4.0).

Some things here belong to others and have their own terms: the Elf2K ROM (Spare Time Gizmos, not included), Emma 02 (Marcel van Tongeren) and Pyodide, which the website loads to run the compiler in the browser.

## Thanks

To Spare Time Gizmos for the Elf 2000, Mike Riley for the ElfOS BIOS, Marcel van Tongeren for Emma 02, and everyone keeping the 1802 alive. The Elf2K ROM belongs to Spare Time Gizmos and is not included here.
