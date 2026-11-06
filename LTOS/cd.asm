; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cd.asm - CD.PRG: CD [path] - into a folder (CD .., CD /, CD GAMES/OLD); no path: where you are.
; (In the kernel until 2026-10-20: moved out for the line editor.)
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
        LDN     RF
        LBNZ    CD1
        SEP     R4              ; no path: where you are
        DW      KS_WHERE
        LDN     RF
        LBNZ    CD0
        LDI     '/'
        SEP     R4
        DW      F_TYPE
CD0:    SEP     R4
        DW      KS_PSTR
        SEP     R4
        DW      K_PCRLF
        SEP     R5
CD1:    LOAD    RD, KS_NNAME
        SEP     R4
        DW      KS_PARSE
        LBNF    CD2
        XRI     3
        LBZ     CD3             ; it ends in '/': WDIR is the folder
        XRI     3
        LBR     KS_PPERR
CD2:    LOAD    RD, KS_NNAME    ; the last part: a folder in WDIR
        SEP     R4
        DW      KS_FOLDIN
        LBDF    KS_NOFOLD
CD3:    LOAD    RD, KS_WDIR     ; CWD = WDIR
        LOAD    RF, KS_CWD
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
