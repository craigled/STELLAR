; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; mkdir.asm - MKDIR.PRG: MKDIR path - a new folder (moved out of the kernel in phase 5b).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
; ---- MKDIR path: a new folder - a zeroed cluster with its '.' and '..' entries, then its entry ($10)
        SEP    R4
        DW      KS_MNTCHK
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_FNAME       ; ('.' and '..' are there already)
        LDN     RD
        XRI     '.'
        LBZ     KS_BADNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    MK1
        SEP     R4
        DW      KS_PIN
        DB      'There is already a ',0
        SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      KS_PCRLF
        SEP     R5     
        INCL    "mkfold.inc"
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
