; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; spin.inc - DISKINFO.PRG's progress: one character turning in place, \ | / - , so a long job is seen to be
; working; when it is done the character is rubbed out and what follows is written where it stood.
;   SPIN     the next of \ | / - over the last one (a backspace first). Straight to the screen: never into a
;            > file. Changes RD.
;   SPINEND  rubs the turning character out (backspace, space, backspace), if there is one. Changes RD.
SPIN:   LOAD    RD, SPN
        LDN     RD
        LBZ     SPN1
        LDI     08H             ; over the last one
        SEP     R4
        DW      F_TYPE
SPN1:   LOAD    RD, SPN
        LDN     RD
        ANI     3
        ADI     1
        STR     RD              ; SPN = 1..4: the one now shown
        STR     R2
        LOAD    RD, SPCH-1      ; its character
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LDN     RD
        SEP     R4
        DW      F_TYPE
        SEP     R5
SPINEND: LOAD   RD, SPN
        LDN     RD
        LBZ     SPN9
        LDI     0
        STR     RD
        LDI     08H
        SEP     R4
        DW      F_TYPE
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     08H
        SEP     R4
        DW      F_TYPE
SPN9:   SEP     R5
SPN:    DB      0               ; 0: nothing shown
SPCH:   DB      5CH,'|/-'       ; \ | / -
