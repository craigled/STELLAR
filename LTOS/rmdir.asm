; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; rmdir.asm - RMDIR.PRG: RMDIR path - an empty folder goes (moved out of the kernel in phase 5b).
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
; ---- RMDIR path: an empty folder (not the current one) goes
        SEP    R4
        DW      KS_MNTCHK
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_WDIR
        LOAD    RC, KS_MKPAR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    RDNO
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBZ     RDNO
        LOAD    RD, KS_DCLUS       ; the current folder?
        LOAD    RC, KS_CWD
        LDA     RD
        STR     R2
        LDA     RC
        XOR
        LBNZ    RD1
        LDN     RD
        STR     R2
        LDN     RC
        XOR
        LBNZ    RD1
        SEP     R4
        DW      KS_PIN
        DB      'That is the current folder - CD out of it first.',0DH,0AH,0
        SEP     R5     
RD1:    LOAD    RD, KS_DCLUS       ; empty? (anything in it at all, hidden or not)
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, KS_QNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    RD2
        SEP     R4
        DW      KS_PIN
        DB      'That folder is not empty.',0DH,0AH,0
        SEP     R5     
RD2:    LOAD    RD, KS_MKPAR       ; found again in its folder, then deleted
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_CARDF
        SEP     R4
        DW      KS_DELENT
        LBDF    KS_CARDF
        SEP     R5     
RDNO:   LBR     KS_NOFOLD          ; (the name at PPRD = FNAME)
DONE:   SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
