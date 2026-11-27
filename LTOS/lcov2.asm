; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lcov2.asm - LC.OVL's part 2: Help. Loaded by LC.PRG (OVLD) into OVLA when wanted; it uses LC.PRG's
;   routines and variables by their names (out/lcsyms.inc, written by build.py from lc.asm's listing).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
        INCL    "lc.inc"
        INCL    "out/lcsyms.inc"

        ORG     OVLA
        DW      PEND            ; (this LC.PRG's: LC.PRG checks it)
        DB      2
        LBR     OHELP

; 1 / F1: the keys
OHELP:  SEP     R4
        DW      INL
        DB      ESC,'[0m',ESC,'[2J',ESC,'[1;1H'
        DB      ' LTOS Commander - the keys',0DH,0AH,0AH
        DB      '  Up Down PgUp PgDn Home End   move the cursor',0DH,0AH
        DB      '  Tab (or Left / Right)        the other pane',0DH,0AH
        DB      '  Enter                        into a folder (.. : up); a file: Run, or View',0DH,0AH
        DB      '  Backspace                    up a folder',0DH,0AH
        DB      '  Space or Ins                 tag a file (or untag it), then down',0DH,0AH
        DB      '  * or +   -                   tag every file;  untag all',0DH,0AH
        DB      '  Ctrl-R                       read both folders again',0DH,0AH
        DB      '  1 or F1                      this help',0DH,0AH
        DB      '  2 or F2                      Info: a box about the file or folder',0DH,0AH
        DB      '  3 or F3                      View a file (text or hex): Space b Home End H',0DH,0AH
        DB      '  4 or F4                      Rename (the name offered to edit; Esc: no)',0DH,0AH
        DB      '  5 or F5                      Copy the tagged (or this one) to the other pane',0DH,0AH
        DB      '  6 or F6                      Move the tagged (or this one) to the other pane',0DH,0AH
        DB      '  7 or F7                      MkDir: a new folder here',0DH,0AH
        DB      '  8, F8 or Del                 Delete: files to /TRASH, empty folders go',0DH,0AH
        DB      '  9 or F9                      Run: .PRG .SH .STL .MUS .SC, then back to LC',0DH,0AH
        DB      '  E                            Edit with NANO: .SC .TXT .SH .RF .LOG .TAB',0DH,0AH
        DB      '  Esc                          back to LTOS',0DH,0AH,0AH
        DB      ' A key goes back to the panes.',0
        SEP     R4
        DW      KEY
        LBR     DRAWALL
OVEND:
        END
