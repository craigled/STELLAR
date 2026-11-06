; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; hide.asm - HIDE.PRG: HIDE name sets a file's hidden bit, HIDE -U name clears it. DIR leaves hidden files out
; (DIR -h shows them); FINDN, so TYPE, NANO and SH, still finds them. Only the entry's attribute byte is written.
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
        LOAD    RD, UNH
        LDI     0
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        XRI     '-'
        LBNZ    NM
        INC     RF              ; -U
        LDA     RF
        ANI     0DFH
        XRI     'U'
        LBNZ    USE
        LOAD    RD, UNH
        LDI     1
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
NM:     LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_NOFILE
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    KS_ISDIR
        GLO     RF              ; its attribute byte
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, UNH
        LDN     RD
        LBNZ    CLR
        LDN     RF
        ORI     02H
        STR     RF
        LBR     WR
CLR:    LDN     RF
        ANI     0FDH
        STR     RF
WR:     LOAD    RD, KS_DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    KS_CARDF
        SEP     R4
        DW      KS_PFNAME
        LOAD    RD, UNH
        LDN     RD
        LBNZ    SAYS
        SEP     R4
        DW      K_PIN
        DB      ' is hidden: DIR -h shows it.',0DH,0AH,0
        SEP     R5
SAYS:   SEP     R4
        DW      K_PIN
        DB      ' is not hidden now.',0DH,0AH,0
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'HIDE name  (hide a file from DIR);  HIDE -U name  (show it again)',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
UNH:    DB      0
PEND:
        END
