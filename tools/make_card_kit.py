#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/make_card_kit.py - the Elf2K card tool as a zip anyone can use, on a Mac, a PC or Linux.

    python3 tools/make_card_kit.py [out.zip]     -> Elf2K-Card-Tool.zip (default: in the project's top folder)

The zip holds one folder, Elf2K-Card-Tool/, laid out as this project is (tools/, LTOS/, LTOS/out/, EMMA02/), so
tools/elf2k_card.py finds everything by the same paths: the scripts, this build of LTOS (LTOS-ALL.PAK, INSTALL.HEX,
INSTALL2.HEX, CARDCHK.HEX, ksyms.inc), the STELLAR firmware, the card layout template, the starter card (the Emma 02
kit's card-share.img), the launchers for each computer, README.txt and the licence. Build LTOS first
(python3 LTOS/build.py) and the starter card (EMMA02/clean_card.py) - the zip takes what is there now.
"""
import os, sys, time, zipfile
HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(TOP, 'LTOS'))
import elf2k_card as T

DIR = 'Elf2K-Card-Tool'
FILES = [  # (path in the project, executable)
    ('tools/elf2k_card.py', False), ('tools/cardsync.py', False), ('tools/card_layout.py', False),
    ('LTOS/elfser.py', False), ('LTOS/cardfiles.py', False), ('LTOS/layout.txt', False),
    ('LTOS/out/LTOS-ALL.PAK', False), ('LTOS/out/INSTALL.HEX', False), ('LTOS/out/INSTALL2.HEX', False),
    ('LTOS/out/CARDCHK.HEX', False), ('LTOS/out/ksyms.inc', False),
    (os.path.relpath(T.FIRMWARE, TOP), False), ('EMMA02/card-share.img', False),
    ('Elf2K Card.command', True), ('Elf2K Card.bat', False), ('elf2k-card.sh', True),
    ('COPYING', False), ('COPYING.EXCEPTION', False),
]

README = """THE ELF2K CARD TOOL
===================

Looks after the CompactFlash card in an Elf 2000 (Elf2K) with the Disk/UART/RTC card, over its serial port:

   1  Format a card and install LTOS + STELLAR          7  List every file on the card
   2  Update LTOS + STELLAR (only what differs)          8  Get a file from the card
   3  Back up the card to this computer                  9  Put a file on the card
   4  Check the card (FSCK, space, bad clusters)        10  Restore a backup onto a card
   5  Name this card                                    11  Delete a file or folder
   6  Arrange the programs into /BIN, /BIN/GAMES ...    12  Run a raw 1802 program

This copy holds LTOS {ltos} (kernel built {built}) and STELLAR V00{fw}.
Backups go to the folder Elf2K-backups in your home folder; files got from the card go to Downloads.


WHAT YOU NEED
-------------
  * An Elf2K with the STELLAR ROM and a CF card, on a USB serial cable at 19200 baud, 8N1.
  * Python 3 (3.8 or newer).
  * Nothing else may be using the serial port: close any terminal program first.


ON A MAC
--------
  1. Unzip, and keep the Elf2K-Card-Tool folder where you like (Documents, the Desktop ...).
  2. Python 3: type  python3 --version  in Terminal. If it is missing, macOS offers to install the
     command line tools - say yes - or get Python from python.org.
  3. Double-click "Elf2K Card.command". The first time macOS may refuse a downloaded script:
     right-click it, choose Open, then Open again. (Or in Terminal:  xattr -dr com.apple.quarantine
     followed by the folder.)
  The USB serial port is found by itself. With more than one plugged in, run it from Terminal with
     ./elf2k-card.sh --port /dev/cu.usbserial-XXXX


ON WINDOWS
----------
  1. Unzip (right-click, Extract All), and keep the Elf2K-Card-Tool folder where you like.
  2. Install Python 3 from python.org - tick "Add python.exe to PATH" - or from the Microsoft Store.
  3. Double-click "Elf2K Card.bat". The first time it installs pyserial (the serial port library).
     If Windows SmartScreen warns about the file: More info, then Run anyway.
  The one USB serial port is found by itself. With more than one: open a Command Prompt in the folder
  and type   "Elf2K Card.bat" --port COM4   (Device Manager, Ports, shows which COM it is).


ON LINUX
--------
  ./elf2k-card.sh   (the port is found by itself, or --port /dev/ttyUSB0)
  Your user needs to be allowed the serial port: on most systems  sudo usermod -aG dialout $USER
  then log out and in again.


GOOD TO KNOW
------------
  * A card that already holds LTOS is never formatted without asking - twice - and a backup is offered.
  * Update sends only what differs from this copy: the kernel, system files and STELLAR.BIN.
  * Your own files are never moved or replaced unless you say so.
  * Esc leaves every LTOS program; if the Elf2K stops answering, press its Reset and pick R (read again).

LTOS and STELLAR are by Craig Ledbetter. Free software: GPL-3.0-or-later (COPYING).
Source, a version that runs in a web browser, and one for the Emma 02 emulator:
github.com/craigled/STELLAR
"""


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(TOP, 'Elf2K-Card-Tool.zip')
    for p, _ in FILES:
        if not os.path.exists(os.path.join(TOP, p)): raise SystemExit('Missing %s - build it first.' % p)
    b = T.Build()
    built = time.strftime('%Y-%m-%d %H:%M', time.localtime(os.path.getmtime(T.INSTALL)))
    readme = README.format(ltos='0.5', built=built, fw=b.fw_version).replace('\n', '\r\n')
    stamp = time.localtime()[:6]
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        def add(name, data, exe=False):
            i = zipfile.ZipInfo(DIR + '/' + name, stamp)
            i.compress_type = zipfile.ZIP_DEFLATED
            i.external_attr = ((0o100755 if exe else 0o100644) << 16)
            i.create_system = 3                                   # Unix: the permissions above are kept on a Mac
            z.writestr(i, data)
        add('README.txt', readme.encode('ascii'))
        for p, exe in FILES:
            add(p, open(os.path.join(TOP, p), 'rb').read(), exe)
    print('%s: %d files, %d KB  (LTOS kernel stamp $%04X, %d system files, STELLAR V00%s)'
          % (out, len(FILES) + 1, os.path.getsize(out) // 1024, b.stamp, len(b.files), b.fw_version))


if __name__ == '__main__':
    main()
