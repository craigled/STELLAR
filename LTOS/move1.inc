; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; move1.inc - shared by MV.PRG and DELETE.PRG: MOVE1, one directory entry to another folder.
; MOVE1: the entry SNM1 (one name) in SDIR -> DNM in DDIR. DF = 0 moved; DF = 1: D = 1 DDIR has DNM already,
;        2 a folder into itself, 3 no such file, 4 the folder is full, 5 the card failed.
MOVE1:  LOAD    RD, SDIR
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, SNM1
        SEP     R4
        DW      KS_FINDN
        LDI     3
        LBDF    MFAIL
        LOAD    RC, ENT         ; its entry, kept
        LDI     32
        PLO     RB
M2:     LDA     RF
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    M2
        LOAD    RD, KS_DCLUS
        LOAD    RC, MCL
        SEP     R4
        DW      CP2
        LOAD    RD, ENT+11      ; a folder: not into itself, or into one inside it
        LDN     RD
        ANI     10H
        LBZ     M7
        LOAD    RD, DDIR        ; (up from DDIR to the root: MCL must not be on the way)
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LDI     64
        PLO     R9
M6:     LOAD    RD, KS_WDIR
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     M7
        LOAD    RC, MCL
        LDN     RD
        STR     R2
        INC     RC
        LDN     RC
        XOR
        LBNZ    M6A
        DEC     RD
        DEC     RC
        LDN     RD
        STR     R2
        LDN     RC
        XOR
        LBNZ    M6A
        LDI     2
        LBR     MFAIL
M6A:    GLO     R9
        STXD
        LOAD    RD, DOTDOT
        SEP     R4
        DW      KS_FOLDIN
        IRX
        LDX
        PLO     R9
        LDI     5
        LBDF    MFAIL
        DEC     R9
        GLO     R9
        LBNZ    M6
        LDI     2
        LBR     MFAIL
M7:     LOAD    RD, DDIR        ; WDIR = DDIR: the new name must be free
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, DNM
        SEP     R4
        DW      KS_FINDN
        LDI     1
        LBNF    MFAIL
        LOAD    RD, DDIR
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        SEP     R4
        DW      KS_DSLOT        ; a slot in DDIR (it may grow)
        LDI     4
        LBDF    MFAIL
        LOAD    RD, KS_WDPTR    ; the entry there: ENT, with the new name
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, ENT
        LDI     32
        PLO     RB
M9:     LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    M9
        LOAD    RD, KS_WDPTR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, DNM
        SEP     R4
        DW      CP11
        LOAD    RD, KS_WDSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LDI     5
        LBDF    MFAIL
        LOAD    RD, SDIR        ; the old entry goes (its long name too) - not its clusters
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, SNM1
        SEP     R4
        DW      KS_FINDN
        LDI     5
        LBDF    MFAIL
        LOAD    RD, KS_ENTP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      KS_KILLLFN
        LDI     5
        LBDF    MFAIL
        LOAD    RD, KS_ENTP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDI     0E5H
        STR     RF
        LOAD    RD, KS_DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LDI     5
        LBDF    MFAIL
        LOAD    RD, ENT+11      ; a folder: its '..' = DDIR (0: the root)
        LDN     RD
        ANI     10H
        LBZ     MOK
        LOAD    RD, MCL
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RC, 0
        SEP     R4
        DW      KS_DIRRD
        LDI     5
        LBDF    MFAIL
        LOAD    RF, KS_DIRBUF+32
        LDA     RF
        XRI     '.'
        LBNZ    MOK
        LDN     RF
        XRI     '.'
        LBNZ    MOK
        LOAD    RF, KS_DIRBUF+32+26
        LOAD    RD, DDIR+1
        LDN     RD
        STR     RF
        INC     RF
        DEC     RD
        LDN     RD
        STR     RF
        LOAD    RC, 0
        SEP     R4
        DW      KS_DIRWR
        LDI     5
        LBDF    MFAIL
MOK:    LDI     0
        SHR
        SEP     R5
MFAIL:  SMI     0               ; DF = 1, D kept
        SEP     R5

