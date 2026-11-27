; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; p2d.inc - P2D for DIR and rtc.inc (the kernel's until 2026-11-16: room for BINWALK's folder list).
; ---- P2D: D (0-99) as two digits
P2D:    PLO     RA
        LDI     '0'
        PHI     RA
P2DA:   GLO     RA
        SMI     10
        LBNF    P2DB
        PLO     RA
        GHI     RA
        ADI     1
        PHI     RA
        LBR     P2DA
P2DB:   GHI     RA
        SEP     R4
        DW      F_TYPE
        GLO     RA
        ADI     '0'
        SEP     R4
        DW      F_TYPE
        SEP     R5
