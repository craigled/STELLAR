; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; mkfold.inc - shared by MKDIR.PRG and DELETE.PRG. MK1: a new folder, named KS_FNAME, in the folder WDIR.
MK1:    LOAD    RD, KS_WDIR        ; MKPAR = the folder it goes in
        LOAD    RC, KS_MKPAR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R4
        DW      KS_FREECL          ; MKCL = its cluster
        LDI     2
        LBDF    KS_WERR
        LOAD    RD, KS_MKCL
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      KS_ZDIR
        LBDF    KS_CARDF
        LOAD    RD, KS_MKCL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    R9, 0FFFFH
        SEP     R4
        DW      KS_FATPUT
        LBDF    KS_CARDF
        SEP     R4
        DW      KS_STAMP
        LOAD    RF, KS_DIRBUF      ; '.': itself
        LOAD    RD, KS_MKCL
        SEP     R4
        DW      DOTENT
        LOAD    RF, KS_DIRBUF+32   ; '..': the folder it is in (0: the root)
        LOAD    RD, KS_MKPAR
        SEP     R4
        DW      DOTENT
        LOAD    RF, KS_DIRBUF+33
        LDI     '.'
        STR     RF
        LOAD    RD, KS_MKCL        ; written in the new folder: WDIR = it for a moment
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RC, 0
        SEP     R4
        DW      KS_DIRWR
        LOAD    RD, KS_MKPAR       ; (LOAD keeps DF)
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LBDF    KS_CARDF
        LOAD    RD, KS_WLEN        ; its entry: no data, WATTR $10, MKCL its first cluster (WFILE1)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, KS_PFXN
        LDI     0
        STR     RD
        LOAD    RD, KS_WATTR
        LDI     10H
        STR     RD
        SEP     R4
        DW      KS_WFILE1
        LBNF    DONE
        STXD                    ; failed: the cluster back
        LOAD    RD, KS_MKCL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    R9, 0
        SEP     R4
        DW      KS_FATPUT
        SEP     R4
        DW      KS_FATFLUSH
        IRX
        LDX
        LBR     KS_WERR
; DOTENT: RF -> a zeroed entry: '.', 10 spaces, $10, the time now (STAMP's), cluster = the 2 bytes at RD
DOTENT: LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LDI     '.'
        STR     RF
        INC     RF
        LDI     10
        PLO     RB
DO1:    LDI     ' '
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    DO1
        LDI     10H             ; 11
        STR     RF
        INC     RF
        INC     RF              ; 12, 13
        INC     RF
        SEP     R4              ; 14-17 created
        DW      KS_PUTST
        INC     RF              ; 18-21
        INC     RF
        INC     RF
        INC     RF
        SEP     R4              ; 22-25 written
        DW      KS_PUTST
        GLO     R9              ; 26-27 the cluster
        STR     RF
        INC     RF
        GHI     R9
        STR     RF
        SEP     R5
DONE:   SEP     R5
