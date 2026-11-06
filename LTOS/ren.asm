; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; ren.asm - REN.PRG: REN old new - a new name in the same folder (MV moves). (In the kernel until
; 2026-10-20: moved out for the line editor.)
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
; ---- REN / MV old new
        SEP     R4
        DW      KS_MNTCHK
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_WDIR        ; its folder, kept
        LOAD    RC, MKPAR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, KS_NNAME
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_PPSL        ; the new name: just a name (MV to another folder: not yet)
        LDN     RD
        LBZ     RN0
        SEP     R4
        DW      K_PIN
        DB      'The new name is a name, not a path.',0DH,0AH,0
        LBR     K_MAIN
RN0:    LOAD    RD, MKPAR
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, KS_NNAME       ; the new name must be free
        SEP     R4
        DW      KS_FINDN
        LBDF    RN1
        SEP     R4
        DW      K_PIN
        DB      'There is already a ',0
        LOAD    RD, KS_NNAME
        SEP     R4
        DW      KS_PFNAMD
        SEP     R4
        DW      K_PCRLF
        LBR     K_MAIN
RN1:    LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_NOFILE
        LOAD    RD, KS_ENTP        ; its long name goes; the new short name in its place
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      KS_KILLLFN
        LBDF    KS_CARDF
        LOAD    RD, KS_ENTP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, KS_NNAME
        LDI     11
        PLO     RB
RN2:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    RN2
        LOAD    RD, KS_DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    KS_CARDF
        SEP     R4
        DW      K_PIN
        DB      'Renamed.',0DH,0AH,0
        LBR     K_MAIN

OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
MKPAR:  DS      2               ; the old name's folder
        END
