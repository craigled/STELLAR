; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cfident.asm - CFIDENT: the card's IDENTIFY, raw, to $6000-$61FF - READ ONLY. CALL 3000 from the monitor, then
; EXAMINE 6000 61FF. (2026-11-09: a 256 MB card whose model and size LTOS reads wrong.)
        CPU     1802
        INCL    "ltos.inc"

        ORG     3000H - 6
        DW      START, PEND - START, START
        ORG     3000H
START:  SEX     R2
        SEP     R4
        DW      IDERST
        LOAD    RF, 6000H
        SEP     R4
        DW      IDEID
        SEP     R5
        INCL    "ide.asm"
        INCL    "cons.asm"
NUMBUF  EQU     6600H           ; (nums.asm's digits)
        INCL    "nums.asm"
PEND:
        END
