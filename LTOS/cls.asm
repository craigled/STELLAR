; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cls.asm - CLS.PRG: clear the screen. (In the kernel until 2026-10-20: moved out for the line editor.)
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  SEP     R4
        DW      K_PIN
        DB      1BH,'[2J',1BH,'[H',0
        SEP     R5
PEND:
        END
