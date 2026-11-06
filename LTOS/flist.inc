; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; flist.inc - FLIST / FLGET (WC, GREP): INCL'd after tools.inc.

; FLIST: the words at RF (paths / patterns) -> the files that match each, at FLBUF: [WDIR (2), name (11)] each,
;        FLN of them (FLMAX at most; folders left out). The program defines FLBUF (FLMAX x 13), FLN (DS 1),
;        FLP (DS 2), NXARG (DS 2) and FLMAX.  FLGET: entry RC.0 -> KS_WDIR set, RD -> its 11-byte name.
FLIST:  LOAD    RD, FLN
        LDI     0
        STR     RD
        LOAD    RD, FLP
        LDI     HIGH(FLBUF)
        STR     RD
        INC     RD
        LDI     LOW(FLBUF)
        STR     RD
TFL1:   SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     TFL9
        SEP     R4
        DW      PATARG
        LOAD    RD, NXARG       ; (past this word)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      KS_DOPEN
TFL2:   SEP     R4
        DW      KS_DNEXT        ; RF -> the entry
        LBDF    TFL8
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    TFL2            ; a folder
        LOAD    RD, FLN
        LDN     RD
        XRI     FLMAX
        LBZ     TFL2            ; the list is full
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, FLP         ; RC -> its place
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        INC     RC
        LDI     11
        PLO     RB
TFL3:   LDA     RF
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    TFL3
        LOAD    RD, FLP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LBR     TFL2
TFL8:   LOAD    RD, NXARG
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LBR     TFL1
TFL9:   SEP     R5
FLGET:  LOAD    RD, FLBUF       ; RD = FLBUF + 13 x RC.0
        GLO     RC
        PLO     RB
TFG1:   GLO     RB
        LBZ     TFG2
        GLO     RD
        ADI     13
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        DEC     RB
        LBR     TFG1
TFG2:
        LOAD    RF, KS_WDIR     ; its folder
        LDA     RD
        STR     RF
        INC     RF
        LDA     RD
        STR     RF
        SEP     R5              ; RD -> the name
