; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; dots.inc - shared by FSCK.PRG and DISKINFO.PRG: progress dots, so a long job is seen to be working.
;   DOT     one '.', 64 to a line. Straight to the screen: never into a > file. Changes RD.
;   DOTEND  ends the line of dots, if there is one. Changes RD.
DOT:    LOAD    RD, DOTN
        LDN     RD
        ADI     1
        STR     RD
        XRI     64
        LBNZ    DT1
        STR     RD              ; (0: the line is full)
        LDI     '.'
        SEP     R4
        DW      F_TYPE
        LBR     DTNL
DT1:    LDI     '.'
        SEP     R4
        DW      F_TYPE
        SEP     R5
DOTEND: LOAD    RD, DOTN
        LDN     RD
        LBZ     DT9
        LDI     0
        STR     RD
DTNL:   LDI     0DH
        SEP     R4
        DW      F_TYPE
        LDI     0AH
        SEP     R4
        DW      F_TYPE
DT9:    SEP     R5
DOTN:   DB      0
