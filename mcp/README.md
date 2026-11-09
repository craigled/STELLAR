# An MCP server for the Elf2K

This lets an AI agent, such as Claude Code, use the emulated Elf2K the way a person uses the website: boot LTOS, type at the terminal, read the screen, edit a file, start a STELLAR app, look at memory.

It runs the same code as stellar-1802.dev. `server.mjs` imports the modules in `web/js` as they are (`stellar-vm.js`, `elf2k.js`, `vt100.js`, `cosmac.js`, the V0061.37 firmware, the web BIOS) and the baked card in `web/ltos`. Nothing under `web/`, `LTOS/` or `APPLICATIONS/` is changed.

It needs Node and nothing else. There is no `npm install` and no build step.

## Add it to Claude Code

    claude mcp add elf2k -- node ~/Projects/STELLAR/mcp/server.mjs

Change the path to where this repository is. Then start Claude Code and ask it to boot the Elf2K.

To check it first:

    node mcp/test_mcp.mjs

It should end with `ELF2K MCP: ALL PASS`.

## Three things to ask Claude

- "Boot LTOS, write a ten-line shopping list in NANO, sort it into a second file, and show me both."
- "Start GALAXIA and clear the bottom row. Tell me the score, then quit with Esc."
- "Load Prime-Gen-v07.lst on the bare firmware, give it 3 and 60, and tell me how many commands VM1 ran and how long that takes on the Elf2K."

`EXAMPLE-SESSION.md` is a whole session, written down as it happened.

## The tools

| Tool | What it does |
|---|---|
| `boot` | Power on and boot LTOS to its prompt. Again for a reset. `restore_card` puts the card back as baked. |
| `command` | Type a line at `LTOS>`, press Enter, run until the machine waits for a key. |
| `type` | Type text as it is, for an editor or a program's own prompt. |
| `press` | Press named keys: Enter, Esc, arrows, Ctrl-X and the rest. |
| `run` | Let the machine run with no keys, for a time. |
| `screen` | The 24 rows of 80 as text, and the cursor. Runs nothing. |
| `list_apps` | The `.STL` apps in `/BIN` on the card, and the `.lst` samples in `web/samples`. |
| `launch_app` | Start a STELLAR app from LTOS by name. |
| `stellar_load` | The bare firmware with one to four `.lst` programs, one in each VM, and no LTOS. |
| `peek` | Memory in hex and text. |
| `vm_core` | One VM's registers, accumulators, flags, program location and command count. |
| `status` | The time so far, the 1802's registers and next instruction, the VMs. |
| `list_files` | A folder on the card, read from the card image as a PC reads it. |
| `read_file` | A file from the card image. |
| `write_file` | A file onto the card, by `RECV` and Intel HEX at the prompt. Up to about 16 KB. |

Every tool that runs the machine says how much Elf2K time passed, in seconds and in machine cycles, and why it stopped.

## How it works

**Time is machine cycles.** The server never reads this computer's clock. Time is the count `stellar-vm.js` keeps (`cpu.cycles`: 2 a short instruction, 3 a long branch), at 375,000 a second for the 3 MHz Elf2K. The real-time clock starts at 2026-11-09 12:00:00, or the date you give `boot`, and runs on the same count. So a session run twice gives the same text and the same cycle counts. The test checks this with two servers.

**"Waiting for a key" is worked out.** Nothing in the machine says it is waiting. The server calls it waiting when nothing has been printed and no key read for a quarter of a second of Elf2K time, and the UART has been asked for a key at least 50 times since, the last time within 5,000 cycles. At the LTOS prompt the UART is asked about every 7 cycles. A game that draws all the time is never waiting, so `press` and `run` take a time limit and stop there.

**The card is kept in memory.** It starts as `web/ltos/ltos-card.bin`. Files you write stay across `boot` and are gone when the server stops.

**`write_file` goes through LTOS.** It types `RECV NAME` at the prompt and sends Intel HEX, as a terminal program does, so LTOS's own code writes the card. `list_files` and `read_file` read the card image directly and take no Elf2K time. LTOS writes a file to the card before the prompt comes back: the test does `ECHO > ECHO.TXT` and then reads the file from the image.

**`stellar_load` loads as the Multitasking page does.** Each `.lst` is a VM1 file. It is moved up into its own block, and bytes outside its block (the claim lines at the end) are left out. This is `machine.js`'s rule, on `stellar-vm.js`'s `MultiVM`. All VMs share the one terminal, as on the Elf2K.

## Where it is not the Elf2K

- The screen is the website's `vt100.js`. It scrolls when a line feed comes at row 24. Your terminal does not, so an app that passes here can still be wrong there.
- Keys queue and none is lost, unless you ask `boot` for `authentic_uart` (`elf2k.js`'s one-byte UART at 19200 baud).
- The BIOS is the web BIOS, not the Elf2K ROM.
- Reverse video is flattened. A run of reverse-video blanks is shown as `█` blocks, and reverse-video text is shown as plain text.
- There is no front panel, Q, sound or EF input. Morse Receiver has nothing to listen to.
- `write_file` stops at about 16 KB, because `RECV` does. XFER is not offered.

## What was checked, and what was not

Checked, on a Mac with Node 22.23.4:

- `node mcp/test_mcp.mjs` prints `ELF2K MCP: ALL PASS`. It talks to the server over stdin and stdout and does these: the handshake and the 15 tools; boot to `LTOS>`; `DIR /BIN`, whose count and bytes must equal the card image's (93 files, 301979 bytes); a file written, then read back from the image and by `TYPE`; three lines typed into NANO, saved, and sorted by `SORT`; GALAXIA started, VM1 active, and a lone Esc back to `LTOS>`; the card kept across a boot and restored; Prime-Gen v07 and three VMs on the bare firmware; then the whole session again in a second server, which must print the same text.
- `node mcp/example_session.mjs` wrote `EXAMPLE-SESSION.md`. Run twice, it wrote the same file (`cmp`).
- `node web/build/test_ltos.mjs` still prints `LTOS WEB: ALL PASS` with this folder added.
- Claude Code 2.1.321, run once with `claude --mcp-config ... -p`, booted the machine and ran `WC DOCS/SALES.TXT` through the server.

Not checked:

- `claude mcp add` itself, and the Claude desktop app.
- Windows and Linux.
- Anything against the real Elf2K. The cycle counts are the emulator's.
- `authentic_uart`, beyond one `ECHO` typed at the prompt.
- Whether Claude plays the games well.

## Small changes in `web/js` that would make this simpler

None is made here.

- `webbios.js` sets only `window.LTOS_WEBBIOS`. With the `module.exports` line the other modules have, Node could `require` it. For now its bytes are read out of the file's text, as `test_ltos.mjs` does.
- The `RTC` in `stellar-vm.js` reads `Date.now()` in `_load` and `_commit`. If it asked one `now()` method for the time, a caller could supply the clock. For now `elf2k.mjs` replaces those two methods.
- `term-input.js` keeps its table of key bytes to itself. If it exported `keyBytes`, the server would use it. For now the table is repeated in `elf2k.mjs`.

## Files

| File | |
|---|---|
| `server.mjs` | The MCP server: JSON-RPC 2.0 on stdin and stdout, one message a line, written by hand. The MCP SDK would be this folder's only dependency and would bring `npm install` with it. |
| `elf2k.mjs` | The machine with no page: power, keys, time, the screen as text, the card. |
| `client.mjs` | A very small MCP client, for the test and the example. |
| `test_mcp.mjs` | The test. |
| `example_session.mjs` | Makes `EXAMPLE-SESSION.md`. |
