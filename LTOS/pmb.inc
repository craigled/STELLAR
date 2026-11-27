; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; pmb.inc - PMB for VER, DISKINFO and the installer (the kernel's until 2026-11-16: room for BINWALK's folder list).
;   The includer sets PMBDEC and PMBPIN: K_PDEC and K_PIN in a program, PDEC and PIN in the installer.
; ---- PMB: R8:R7 sectors, printed as MB (sectors / 2048); keeps R7, R8
PMB:    GHI     R8
        PHI     RA
        GLO     R8
        PLO     RA
        GHI     R7
        PHI     RD
        GLO     R7
        PLO     RD
        LDI     11
        PLO     RC
PM1:    GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        GHI     RD
        SHRC
        PHI     RD
        GLO     RD
        SHRC
        PLO     RD
        DEC     RC
        GLO     RC
        LBNZ    PM1
        SEP     R4
        DW      PMBDEC
        SEP     R4
        DW      PMBPIN
        DB      ' MB',0
        SEP     R5
