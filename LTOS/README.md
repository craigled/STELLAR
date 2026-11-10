## Building this source

This is the source of LTOS, under GPL-3.0-or-later (see `COPYING` at the top of this repository).

- It assembles with the A18 cross-assembler. `build.py` looks for it at `../Firmware-Math/scratchpad/a18`; change `A18` there to where yours is.
- The tests (`verify_*.py`, `run_tests.py`) also use a Python 1802 simulator and firmware tools that are not in this folder, and the Elf2K ROM, which is not included (see `rom/README.txt`).

> **LTOS 0.5** (2026-10-28): what was the LTOS-SH fork (`PLANS/LTOS-SH-shell-plan.md`) is LTOS now; the 0.4 system
> it was copied from is `../LTOS-0.4/`. New since 0.4: `>`, `>>`, `> NUL` for every command (`redir.asm`); scripts -
> SH.PRG (`sh.asm`: variables, if, loops, functions, case, `$(command)` ...; `HELP SH`, `HELP SCRIPTS`, `HELP LOOPS`,
> `HELP FUNCS`), and /AUTOEXEC.SH at every boot; ECHO, CAT, HEAD, TAIL, TOUCH; MON and LOAD are programs. Programs
> start at **$3000**; F takes two pastes (INSTALL.HEX + CALL 3000, then INSTALL2.HEX + CALL 3003); RECV SYSTEM is
> 7 parts. Tests: `python3 LTOS/run_tests.py` (all at once, ~23 min) or `run_tests.py sh redir` (just those).

# LTOS - LiteOS for the Elf2K

A small disk operating system in native 1802 code, on a bootable FAT16 CompactFlash card. The plan:
[`PLANS/Elf2K-DOS-plan.md`](../PLANS/Elf2K-DOS-plan.md). Built for Craig's Elf2K: Monitor V87, BIOS 1.0.6.

| File | |
|---|---|
| `ltos.inc` | registers, the BIOS's vectors, the Disk/UART/RTC card's ports |
| `ide.asm` | the CF driver (the CF-Test / CF-Scan protocol, HW-verified) |
| `cons.asm`, `nums.asm` | console text; hex and decimal printing |
| `boot.asm` | LBA 0: the MBR boot sector - loads the kernel |
| `kernel.asm` | the kernel at $0300: the `LTOS>` prompt and the commands |
| `monstub.asm` | MON's last step, run at $3000: STELLAR back from `STELLAR.BIN` |
| `fat.asm` | the FAT16 layer: mount, clusters, the FAT, the root directory, reading a file, names |
| `bread.asm` | the boot sector's and MON's own sector read (not the BIOS's: BIOS 1.0.6 hung) |
| `hello.asm` | `HELLO.PRG`, the sample program the installer puts on the card |
| `install.asm` | the installer, run from the monitor |
| `build.py` | a18 -> `out/boot.bin`, `out/INSTALL.HEX` |
| `verify_phase0.py` | the simulator harness: the real Elf2K ROM v120 (`rom/`), the CF card model, the Mac's `fsck_msdos` |
| `verify_phase1.py` | boot (both BIOS entries), the prompt, MON, U, a damaged kernel, a silent card |
| `verify_tools.py` | WC, GREP, FIND, TREE, SEND (decoded: = the file), FSCK (a card damaged in Python: each problem found; -F, then the Mac's fsck clean) |
| `verify_rawk.py` | RAWK against the Mac's own awk on the same files (every program must print the same), its own messages, whole numbers, a screen at a time, the time a 500-line file takes |
| `verify_xfer.py` | XFER against `elfser.py`'s own put / pull code at 19200 baud (the UART holds one byte): 120 KB onto the card and back byte-identical, none lost; 0 / 1 / 512 / 513 bytes into a folder; a lost byte, a changed byte, a lost ACK both ways; a block always bad; replace Y / N / failed; the card full; a stop from the Mac - each time the Mac reads the card, fsck clean, FREE = fsck |
| `verify_recv.py` | RECV refuses Intel HEX with a record cut short (a lost digit: "bad checksums - nothing saved"); the same file whole is saved |
| `verify_edit.py` | the command line: arrows, Home / End, Backspace / Delete in the middle, the up arrow, Ctrl-C, a pasted line at full speed |
| `verify_hex.py` | HEX: the layout, a short last line, an empty file, 70,000 bytes, space / Enter / Q |
| `verify_help.py` | HELP: the list, ?, one command's page, a command's other name, an unknown one |
| `verify_dir.py` | DIR's flags: each sort, -r, -w, -p, -h, a bad flag |
| `verify_diskinfo.py` | DISKINFO against the card image, FREE and FSCK; a cluster marked bad counted apart; -S stopped by a key |
| `verify_phase2.py` | the files: DIR TYPE FREE LOAD RUN against what the Mac's own FAT code wrote and reads |
| `verify_update.py` | `RECV SYSTEM` right after U, run by the card's RECV.PRG made for the old kernel: every program into /BIN |

Build: `python3 LTOS/build.py` (needs `sh tools/a18/build.sh` once).  Test: `python3 LTOS/verify_phase1.py` ... `verify_phase5.py`.

## Phase 5 - folders (sim ALL PASS 2026-10-17, awaiting HW)

Paths use `/` (never `\`): `GAMES/SNAKE.PRG`, `/HELP.TXT` (from the root), `..` (up), `.`.

| Command | |
|---|---|
| `CD [path]` | go into a folder (`CD ..`, `CD /`, `CD GAMES/OLD`); no path: print where you are |
| `MKDIR path` | a new folder (its `.` and `..` entries, a zeroed cluster) - `MKDIR.PRG` |
| `RMDIR path` | an empty folder goes (not the one you are in) - `RMDIR.PRG` |
| `MV from to` | to a folder (`MV A.TXT DOCS`, `MV B.TXT ..`), a new name, or both (`MV A.TXT DOCS/B.TXT`); a folder moved: its `..` follows; not into itself - `MV.PRG` |
| `REN old new` | a new name in the same folder |
| `DIR [path]` | `DIR GAMES` lists the folder; `DIR GAMES/*.BIN` |
| `DIR -flags [path]` | flags before or after the path, together (`-at`) or apart: `-a` by name, `-e` by extension, `-s` by size (largest first), `-t` by date (newest first) - folders first; `-r` the other way round; `-w` wide (names only, five across); `-p` a screen at a time; `-h` hidden files too; any other letter lists them. DIR gathers the entries first (about 440 at once; more are counted, and it says how many were left out) - `verify_dir.py` |

* The prompt shows the folder: `LTOS /GAMES/OLD> ` (rebuilt from the `..` entries each time; deeper than 5:
  `/...` in front). Every other command takes paths too (TYPE, RUN, LOAD, SAVE, COPY, RM, RECV, HEX).
* Typing `NAME` runs `NAME.PRG` from this folder, else from the root, else from `/BIN` (if there is one);
  `STELLAR` looks for its firmware, apps and ATTACH.PRG the same way (a name with a `/` is looked for only
  where it says). A program found in the root or /BIN still starts in the current folder, so the files it is
  given are found here. A document named to STELLAR is looked for here, else in the root - never in /BIN.
  `MON` and the boot use STELLAR.BIN from the root, else from /BIN.
* Folders grow a cluster at a time when full; the root stays at 512 entries.
* The kernel is now 18 sectors (full): MKDIR, RMDIR, MV, DIR, TYPE, DUMP, SAVE are programs; `RECV SYSTEM` after
  an install puts them on the card (the installer itself carries RECV and TYPE).
* `RECV SYSTEM` puts each .PRG and .STL into /BIN (HELP.TXT into the root) through the kernel's fixed calls only
  (K_PARSE of "/BIN/" or "/", then K_SAVER - `kapi.inc`), never its KS_ addresses, so the RECV.PRG already on the
  card still does it right after U has put a different kernel there. (Before 2026-10-19 it used KS_WDIR / KS_TOBIN;
  with a new kernel's stamp it gave up on /BIN and saved them all in the current folder.)
* `verify_phase5.py`: folders LTOS made and the Mac made, 40 files in one folder, MV, RMDIR refusals,
  STELLAR from a folder - every card checked by `fsck_msdos` and read back by the Mac.

### Lite-Writer 2 documents: files, not slots (2026-10-21)

| Command | |
|---|---|
| `LW2 DOC.TXT` | edit DOC.TXT from the card; `^W` writes it back (= `STELLAR LW2 DOC.TXT`) |
| `LW2` | a new document in the current folder: its first `^W` asks for a name ("Save as"; no extension: .TXT) |

* ATTACH.PRG lays the file out so Lite-Writer (no FAT code) can write it whole, and leaves it a note at $7EA0.
* `LW2` alone: ATTACH makes a place ready but writes no entry; it lists the folder's names at $3400 (NAMESB),
  which MON's stub copies to $7001 (LWNAMES) for Lite-Writer to refuse a name already there (150 at most).
* Under LTOS Lite-Writer has no slots: `^S` / `^L` say so. On its own (no LTOS) it keeps them, in a 1,982-byte
  pool. The kernel no longer keeps the slots at the boot, and TAKE is gone.
* Any argument to STELLAR that is not .BIN or .STL (or has no extension, = .STL) is the document. A document with no app
  named starts Lite-Writer 2: `STELLAR DOC.TXT` = `STELLAR LW2 DOC.TXT`.

## Phase 4 - STELLAR from the card, apps, the clock (LTOS 0.4; HW-VERIFIED 2026-10-16/17)

| Command | |
|---|---|
| `NAME [args]` | the kernel looks in this folder, the root, then /BIN for NAME.SH or NAME.PRG - in each folder NAME.SH wins (one pass over the folder: NAME.???); NAME.SH runs as `SH NAME [args]` (0.5, 2026-10-28). An extension typed (`HELLO.PRG`) is looked for as it is |
| `NAME [args]` with no NAME.SH or NAME.PRG | the kernel runs STELLAR.PRG (the root, else /BIN) with the whole line: `LW2 DOC.TXT` = `STELLAR LW2 DOC.TXT`. No NAME.STL either: STELLAR.PRG says "Unknown command: NAME (see HELP)", as the kernel would (2026-10-21) |
| `STELLAR [-M] [fw.BIN] [app ...]` | load a firmware (STELLAR.BIN if none named) and apps from the card, start STELLAR as the monitor's RUN does. R1 = BACK, 14 bytes STELLAR.PRG puts at $0180 (the firmware's free $0175-$019F, checked to be 0 in the firmware loaded): when the program ends it turns interrupts off and runs the BIOS's F_BOOT, so LTOS starts again. With `-M`, or a firmware whose $0180 is used, R1 = the monitor's breakpoint entry found in the ROM (the register dump, as before). STELLAR started from the monitor is not touched. |
| `RECV NAME.STL` | a STELLAR app: send its `.lst` as it is - only the D-lines count; it ends when the line goes quiet (or Ctrl-Z) |
| `APPS` | the apps on the card, their blocks and the VMs they run in: a VM whose block ($4000, $5000, $6000, $7000) starts with START ($CD), as the firmware decides - not every block a .lst touches (its claim lines clear the others) |
| `RECV STELLAR.BIN` | a new firmware (Intel HEX from $0000); MON and STELLAR find it by name wherever it lands |
| `RECV SYSTEM` | `LTOS-SYSTEM.HEX` (then `RECV SYSTEM` again for `LTOS-SYSTEM2.HEX` .. `5.HEX`): every program on the card, added or replaced (after a fresh install, or a `U`) |
| `DATE [yyyy-mm-dd]`, `TIME [hh:mm[:ss]]` | show or set the DS12887, in the form the BIOS keeps it (binary, year from 1972) |

* Install: paste `INSTALL.HEX`, `CALL 3000`, F (or U), `BOOT`, then `RECV SYSTEM` and send `LTOS-SYSTEM.HEX`.
* An app file (NAME.STL): sector 0 = `STL1`, the block count, each block's address; then 512-byte blocks.
* VER, FREE, STELLAR, APPS, DATE, TIME use the kernel's routines directly (`out/ksyms.inc`, written by the
  build) and check the kernel's stamp at $032D (a CRC of the kernel) first.
* Writes to the card go out through the stack slot (an OUT straight from some RAM addresses repeats the byte
  before it on Craig's Elf2K); reads are full speed.

## Phase 3 - writing files (LTOS 0.3; sim ALL PASS 2026-10-16, awaiting HW)

| Command | |
|---|---|
| `SAVE name a b [x]` | memory a-b (hex) to a file; with x, a program (the 6-byte header) starting at x; asks before replacing |
| `RM names` / `DEL` | delete; wildcards; asks first when several match; folders left alone |
| `REN old new` | rename (MV: phase 5) |
| `COPY from to` | (COPY.PRG on the card) a file up to ~17 KB |
| `HEX name` | (HEX.PRG) any file, any size (a sector at a time): 18 bytes a line - offset, hex, text - in 79 columns (6-digit offsets from 64 KB); space: a screen, Enter: a line, Q: stop - `verify_hex.py` |
| `WC names` | (WC.PRG) lines, words and bytes of each file (paths, patterns, a folder); several: a total |
| `GREP [-i] [-n] text names` | (GREP.PRG) the lines with the text; -i any case, -n line numbers; "quoted text"; several files: the name first |
| `RAWK [-F c] [-v x=val] [-o file] 'program' (or -f PROG.AWK) names` | (RAWK.PRG, `rawk.asm`) awk, whole numbers (`PLANS/LTOS-AWK.md`). Phase 1: `pattern { action }`, BEGIN / END, `$0`..`$NF`, NR NF FNR FILENAME FS OFS, variables, `+ - * / %`, comparisons, `&& \|\| !`, joining, `print`, `length`; `-o file` (written a sector at a time like XFER's; replace? Y/N; a failure saves nothing). Phase 2 (2026-11-02): `{ }` blocks, `if`/`else`, `while`, `do`, `for`, `break`, `continue`, `next`, `exit`; `printf` (`%d %i %u %s %c %x %X %%`, `- 0 +`, width, precision); `substr index toupper tolower`; patterns in `/.../` and `~`: `^ $ . * + ? [..] [^..] \c` (not `( ) \|`); `-f file` (lines, `#` comments, 623 characters); `-v x=val`. The program is compiled once into steps for a small value-stack machine, then run for each line; the run's buffers sit on top of the compiler once it is done. On the Elf2K a 500-line, 17 KB file takes 12-28 s (GREP: 28 s) |
| `FIND name` | (FIND.PRG) every file / folder on the card by that name, as a full path; wildcards; no dot = any extension |
| `TREE` | (TREE.PRG) the folders below this one, indented, with their files and bytes; the totals |
| `SEND [-T] name` | (SEND.PRG) a file out as Intel HEX (RECV puts it back; on the Mac `elfser.py get NAME file`), or -T as text |
| `XFER -R name` / `XFER -S name` | (XFER.PRG) a file of any size (to 32 MB, ~1.5 KB/s) from / to the Mac: `elfser.py put FILE NAME` / `elfser.py pull NAME FILE` type the command and run the other end. 516-byte frames (block number, a sector, XMODEM's CRC-16), each ACKed once on the card; NAK / lost ACK: sent again; 10 bad in a row, the card full, or a stop: the clusters given back, nothing saved. Replacing (asks Y/N): the old file stays until the new one is all there, then one directory write switches it. `PLANS/LTOS-XFER-large-files.md` |
| `elfprint NAME` (on the Mac) | a text file from the card into `~/Documents/Elf2K/` by `elfser.py pull`, its line ends made the Mac's, opened in TextEdit (Cmd-P prints); `-p` sends it to the default printer, `-k` only fetches it. `LTOS/elfprint`, linked into `~/.local/bin` |
| `FSCK [-F]` | (FSCK.PRG) every folder (raw: the Mac's hidden files too) and chain: cross-links, broken chains, sizes against chains, lost clusters, FAT 1 = FAT 2; -F frees lost clusters after a Y |
| `RECV name` | (RECV.PRG) a file sent from the terminal: Intel HEX (NAME.PRG gets the program header), or text up to a line holding just `.` (or Ctrl-Z); checksums checked; UART read directly, no echo |
| `NAME [..]` | any NAME.PRG on the card runs when its name is typed |

* `fatw.asm`: both FATs kept in step; a new file's data, then the FAT, then its directory entry; deleting: the
  entry first, then the clusters - a power cut can lose only the file being written. The Mac's long-name
  pieces are deleted with their file (fsck sees no orphans). Dates from the DS12887 (the build's date with no clock).
* Programs now load at **$2800** (the kernel may use $0300-$27FF, 18 sectors); MON's check for "was STELLAR in
  RAM" compares $2800-$2DFF. (Since 2026-10-21: programs at **$2C00** (`PRGORG` in ltos.inc), the kernel up to
  20 sectors ($0300-$2BFF), STELLAR.PRG at $4000 - clear of $3000-$3FFF; the check compares $2C00-$2DFF.) HELP is now `HELP.TXT` on the card. The kernel's calls for programs: a jump table
  at $0309 (`kapi.inc`).
* The CF driver and the boot sector's read are full speed again (no pause, no stack slot): those were for a
  failing 74HC245 on Craig's Disk/UART/RTC card, since replaced.
* `verify_phase3.py`: every file checked by the Mac's own FAT driver and `fsck_msdos`, on 8 MB and 32 MB cards.

## Phase 2 - reading files (install + BOOT HW-VERIFIED 2026-10-14 on the 8 MB SanDisk)

Getting here on the Elf2K took two hardware findings, now built into the CF driver, the boot sector and MON:
* **OUT 3 straight from some RAM addresses slips** (two bytes repeated): every byte now goes through the stack
  slot (LDA / STR R2 / OUT 3; INP 3 with X = R2 / STR RF) - CFDIAG2 proved it.
* **Some cards misread at full speed** (the Elf2K cannot honour IORDY): a ~130 us pause after every byte (CFDLY).
* The installer verifies every sector it writes, re-reads or rewrites (3 tries), and checks its own bytes and
  the card's IDENTIFY (model, LBA, size read twice) before it formats. The 32 MB SanDisk SDCFB-32 still gives a
  different IDENTIFY each time; the 8 MB SDCFB-8 works.

F now also puts `HELLO.PRG` and `README.TXT` on the card (and refuses if RAM holds LTOS rather than STELLAR).

| Command | |
|---|---|
| `DIR [names]` | name, size, date and time; `DIR *.TXT`, `DIR S*` (= `S*.*`); folders show `<DIR>`; the Mac's `._` files and `.fseventsd` are hidden |
| `TYPE name` | a text file, a screen (22 lines) at a time - a key goes on, Q stops; Mac (LF) and PC (CR LF) line ends both work |
| `FREE` | KB free and in all, and clusters; then the space used (the size less what is free, 2026-11-02) |
| `DISKINFO [-Q \| -S]` | all about the card: model, serial, size, partition, FAT16 volume (formatter, label, serial, clusters, FATs), space free / used / marked bad, files and folders in every folder; -Q is quick (no FAT or folders read, so no space or file counts); -S reads every sector looking for bad ones (2026-11-03) |
| `LOAD name` | a program (6-byte header: load address, length, start) to where it says |
| `LOAD name a` | any file, as it is, at address a (hex) - it must fit in $2C00-$6BFF |
| `RUN name [...]` | load a program and call it, RF pointing at the rest of the line |

The root directory only, for now; any FAT16 card up to 2 GB (32-bit sector numbers throughout).

## Phase 1 - the kernel and the LTOS> prompt (HW-VERIFIED 2026-10-13: boots, VER on the Elf2K)

1. With STELLAR in RAM, paste `out/INSTALL.HEX` at the monitor prompt (400 lines) and `CALL 3000`.
   **F** formats the card (erases it) and installs; **U** puts the new LTOS on a card that already has
   one and leaves its files alone; anything else stops.
2. `BOOT`: "LTOS: loading the kernel ... done", then the `LTOS>` prompt:

| Command | |
|---|---|
| (the prompt) | LTOS's own line editor (GETLN, 2026-10-20): left / right arrows, Home / End, Backspace / Delete anywhere, the up arrow = the last line (HIST at $7600), Ctrl-C. Keys come from the UART itself (the BIOS's line input echoed an arrow's ESC [ D into the line); typing at the end is done inline, so a line pasted at full speed arrives whole. RM / DEL, REN, CLS and CD became programs (RM.PRG, DEL.PRG, REN.PRG, CLS.PRG, CD.PRG) to make the room - `verify_edit.py` |
| `HELP [command]` or `?` | `HELP.PRG`: every command, a line each, by group (paged); `HELP DIR` shows just DIR's page. The text is `help.txt` (build.py makes `out/helptext.inc`, and `HELP.TXT` = the list) - `verify_help.py` |
| `VER` | LTOS's version, the kernel's size, how the BIOS booted it, the card's name and size, where `STELLAR.BIN` is |
| `CLS` | clears the screen |
| `POS x y` | (POS.PRG, `pos.asm`) the cursor to column x, row y (`POS 1 1` the top left): ESC [ y ; x H to the output (2026-11-02) |
| `GETSTR [-p "prompt"] [file]` | (GETSTR.PRG, `getstr.asm`) a line typed (the BIOS's F_INPUTL: Backspace) into the file, or as the output: `NAME=$(GETSTR)` in a script. The typing shows on the screen only (K_TTY), so only the line goes into the file or variable; Ctrl-C: status 1. Takes over the word GETSTR from the STELLAR demo GETSTR.STL (`STELLAR GETSTR` still runs it) - `verify_input.py` |
| `FETCH [-p "prompt"] [file]` | (FETCH.PRG, `fetch.asm`) one key, no Enter, the same way: `K=$(FETCH)`; Enter gives "" |
| `DUMP [a [n]]` | memory in hex and text from `a`, `n` bytes (both hex; $80 if left out); `DUMP` alone goes on |
| `MON` | puts STELLAR back from `STELLAR.BIN` (the kernel sat on top of it) and goes to the monitor |

Lower case works; Backspace edits the line; Ctrl-C drops it.

## Phase 0 - the install and the boot path

**HW-VERIFIED 2026-10-12** on Craig's Elf2K (Monitor V87, BIOS 1.0.6): the installer, then BOOT -
"running at $0100 (the BIOS started it with R0 as the PC) ... STELLAR in RAM put back as it was".

On the Elf2K, with STELLAR in RAM as usual:

1. Paste `out/INSTALL.HEX` at the monitor prompt (the monitor takes Intel HEX records as they come; if
   your terminal drops characters, give it a short delay after each line). It loads at $3000-$4000 and
   does not touch STELLAR at $0000-$2EFF.
2. `CALL 3000`. The installer resets the card, shows its name and size and the FAT16 layout it will
   make, and asks. **Y erases the card** and writes it; anything else writes nothing.
3. `BOOT`. The boot sector says which register the BIOS started it with (R0 on BIOS 1.0.6), puts back
   the 768 bytes of STELLAR that BOOT overwrote (from `STELLAR.BIN` on the card) and returns to the
   monitor. STELLAR is ready to run as before.

The card: LBA 0 the boot sector (MBR, one FAT16 partition); LBA 64 the partition - its boot record, 31
sectors for the kernel, two FATs, a 512-entry root directory, then `STELLAR.BIN` (the firmware,
$0000-$2EFF) in the first clusters. 512-byte clusters up to 32 MB, then larger.

## Native CF tools - CFTEST and CFSCAN (sim ALL PASS 2026-10-14, awaiting HW)

Standalone 1802 versions of the STELLAR CF-Test / CF-Scan apps: paste `out/CFTEST.HEX` or `out/CFSCAN.HEX`
at the monitor and `CALL 3000` (STELLAR below $3000 is left alone; quitting returns to the monitor). The
`.PRG` files carry the 6-byte LTOS header for RUN once files can be copied onto the card (phase 3).
Shared code in `cfcom.asm`; LTOS's `ide.asm` driver (stack slot + CFDLY pause).

* **CFTEST** - one chosen sector: 5 patterns written and read back, then the sector restored exactly.
* **CFSCAN** - R (read every sector) or W (save, pattern, inverse, put back - every bit as 0 and 1) over a
  hex range (Enter = whole card); status line with %, time gone / left from the DS12887; Q/ESC stops and
  says where to resume; BAD lines say the phase, byte, wrote/read; first 16 bad sectors listed.
  On HW ~70 ms per sector transfer: 8 MB read scan ~18 min, write test ~2 h.

`verify_cfprogs.py` checks both (the harness UART can now hold keys back until a prompt appears, and
can model the RTC).

## Things learned

* **The BIOS's boot check only looks at $0139-$0140.** It shifts its sum left after each byte, so
  anything earlier falls off the top; the byte at $0140 decides it.
* **BIOS 1.0.6 starts the boot sector at $0100 with R0 as the PC**; later BIOSes jump to $0106 with R3.
  The boot sector has a long branch at both and ends up on R3 either way.
* **RE.1 is the BIOS's console selector** (0 = the video card, 1 = the UART). Never `DEC`/`INC`/`PHI` RE:
  a timeout counted down in RE once borrowed into RE.1 and silenced the console.
* The BIOS's SCRT keeps D and DF across CALL and RETURN (in RE.0, which is lost).

## PLAY - tunes on Q (2026-11-10)

`PLAY name` plays a text file of notes (`.MUS`) as a square wave on Q; `PLAY -n notes` plays the notes on the command
line; `PLAY -s MHz` is for an Elf2K at another clock (1.00-9.99; 3.58 if not given - Craig's Elf2K runs at 1.79).
`HELP PLAY` has the notes. `play.asm`, the note table from `play_gen.py` (`playtab.inc`), `verify_play.py` (every
edge of Q timed in a cycle-counting 1802: C1-B7 within 2 cents, lengths, `-s` at 1-8 MHz). Songs in `music/`, for
`/MUSIC` on the card.

### Songs from the internet: tomus.py

`tomus.py` makes `.MUS` files on a PC/Mac/Linux from music in four common forms:

    python3 LTOS/tomus.py TUNE.abc                 ABC - the first tune (--tune N for X:N)
    python3 LTOS/tomus.py HYMN.mid                 a MIDI file: the melody (--list, then --track N to choose)
    python3 LTOS/tomus.py RING.txt                 an RTTTL ringtone line
    python3 LTOS/tomus.py OLD.BAS                  a BASIC program's PLAY strings (GW-BASIC, QBasic)
    options: -o NAME.MUS, --transpose N, --tempo N, --grid N (MIDI), --title TEXT

Where to find music (choose tunes old enough to be free to share - traditional, classical, older hymns):

| | |
|---|---|
| ABC | abcnotation.com (a search over most collections), thesession.org (Irish), the Nottingham Music Database (English folk) |
| MIDI | Mutopia Project (classical), Hymnary.org and hymntime.com (hymns) |
| RTTTL | ringtone collections in Arduino and PICAXE tune libraries |
| BASIC | QBasic / GW-BASIC music programs (archive.org) - this notation is PLAY's own, almost letter for letter |

ABC: notes, the key, lengths, `>` `<`, triplets, ties, chords (the top note), accidentals for the bar, repeats and
1st/2nd endings; grace notes, decorations, chord names and words are left out; the first voice only. MIDI: the
highest-pitched of the busier tracks (drums left out), the top note where notes overlap, snapped to a 16th (`--grid
24` keeps triplets), tempo changes kept. Notes outside PLAY's C1-B7 move by octaves. A note longer than PLAY can
write as one is played in pieces, legato. Then onto the card: `python3 LTOS/elfser.py put HYMN.MUS /MUSIC/HYMN.MUS`,
or `RECV /MUSIC/HYMN.MUS` and send the text from a terminal program. `verify_tomus.py`: each format read as worked
out by hand, then played by PLAY in the simulator; all 46 tunes of the Nottingham file ashover.abc convert, and the
six tried play note for note.
