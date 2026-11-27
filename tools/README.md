# The Elf2K card tool

<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

`elf2k_card.py` looks after the CompactFlash card in an Elf 2000 over its serial port (19200 baud, 8N1), from a Mac,
a Windows PC or Linux, as a menu: format a card and install LTOS + STELLAR, update them (only what differs), back the
card up and restore it, check it (FSCK, space, bad clusters), name it, arrange its programs into the card layout
template, list it, get and put files, delete, and run raw 1802 programs.

**To use it, download the ready-made kit** from the [LTOS page](https://stellar-1802.dev/ltos#cardtool):
`Elf2K-Card-Tool.zip` holds these scripts together with a built LTOS, the STELLAR firmware and the starter files
for a new card, and launchers for each computer. Its `README.txt` says how to set it up.

## The files here

| File | What it is |
|---|---|
| `elf2k_card.py` | the tool: the menu and every job |
| `cardsync.py` | the serial port (termios on a Mac or Linux, pyserial on Windows), the card image reader, and a card mirror (`CARDSYNC.md`) |
| `card_layout.py` | the card layout template (`LTOS/layout.txt`): where each program goes |
| `make_card_kit.py` | builds `Elf2K-Card-Tool.zip` |
| `../Elf2K Card.command`, `../Elf2K Card.bat`, `../elf2k-card.sh` | double-click launchers: Mac, Windows, Linux |

It also uses `LTOS/elfser.py` (XFER, SYSRX, the port) and `LTOS/cardfiles.py` (backups).

## Running it from this source

The tool sends a built LTOS, so before it starts it needs:

- `LTOS/out/` built: `python3 LTOS/build.py` (it needs the A18 assembler: see `LTOS/README.md`);
- the STELLAR firmware as Intel HEX, `stellar v6137.hex`, at the top of this repository (it is in the kit);
- optionally `EMMA02/card-share.img`, the starter files a new card is given (without it they are left out).

Then `python3 tools/elf2k_card.py` (add `--port COM4` or `--port /dev/ttyUSB0` if there is more than one USB serial
port). On Windows install pyserial first: `py -m pip install pyserial`.
