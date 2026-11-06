; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; pwd.asm - PWD.PRG: PWD - the current folder's path ("/" for the root, "/GAMES/OLD" ...), as the prompt shows it.
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
        SEP     R4
        DW      KS_MNTCHK
        SEP     R4
        DW      KS_WHERE        ; RF -> the path ("" for the root)
        LDN     RF
        LBNZ    P1
        LDI     '/'
        SEP     R4
        DW      F_TYPE
        LBR     P2
P1:     SEP     R4
        DW      F_MSG
P2:     SEP     R4
        DW      K_PCRLF
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
