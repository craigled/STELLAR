; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; walk.inc - WALK: every entry of every folder below a start folder (FIND, TREE). INCL'd after the program.
; The program defines the hooks, CALLed (SEP R4) with the walk's state in memory:
;   W_ENTRY  an entry: KS_DATTR, KS_DSIZE, WCL (its first cluster); WENT -> its 32 bytes in DIRBUF; PATH holds
;            the folder's path ("/", "/DOCS/" ...), 0-ended, PLENG long; WDEPTH = how deep
;   W_INTO   a folder is about to be walked: KS_WDIR = it, PATH its path (with the / at the end)
;   W_OUT    a folder has been walked (its PATH, WDEPTH still as at W_INTO)
; Hooks may print and use every register. W_ENTRY must not walk a directory itself (DOPEN / DNEXT / FINDN);
; W_INTO may (the walk opens the folder again after it). Folders deeper than WMAX are not gone into.
; The program defines WMAX, the start (KS_WDIR, PATH and PLENG set before WALK), and the variables WDEPTH (1),
; WIDX (2), WCL (2), WENT (2), PLENG (1), PATH (PMAXL + 13), WSTK (WMAX x 5).
; Re-entering a folder after a deeper one: it is opened again and the entries already seen are skipped.

WALK:   LOAD    RD, WDEPTH      ; WDEPTH, WIDX: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      W_INTO
WOPEN:  LOAD    RD, KS_PAT      ; every name
        LDI     11
        PLO     RB
WO1:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    WO1
        SEP     R4
        DW      KS_DOPEN
        LOAD    RD, WIDX        ; past the WIDX entries seen already
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
WO2:    GHI     RC
        LBNZ    WO3
        GLO     RC
        LBZ     WNXT
WO3:    DEC     RC
        GHI     RC
        STXD
        GLO     RC
        STXD
        SEP     R4
        DW      KS_DNEXT
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        LBDF    WEND
        LBR     WO2
WNXT:   SEP     R4
        DW      KS_DNEXT
        LBDF    WEND
        LOAD    RD, WENT        ; WENT -> it; WCL = its first cluster; WIDX + 1
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, KS_DCLUS
        LOAD    RF, WCL
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, WIDX
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        INC     RC
        GLO     RC
        STR     RD
        DEC     RD
        GHI     RC
        STR     RD
        SEP     R4
        DW      W_ENTRY
        LOAD    RD, KS_DATTR    ; a folder: in, if not too deep and the path has room
        LDN     RD
        ANI     10H
        LBZ     WNXT
        LOAD    RD, WDEPTH
        LDN     RD
        XRI     WMAX
        LBZ     WNXT
        LOAD    RD, PLENG
        LDN     RD
        SMI     PMAXL
        LBDF    WNXT
; ---- in: WSTK[WDEPTH] = WDIR, WIDX, PLENG; the name and a / onto PATH; WDIR = it, WIDX = 0
        LOAD    RD, WDEPTH
        LDN     RD
        PLO     RB              ; RF -> WSTK + 5 x depth
        LOAD    RF, WSTK
WI1:    GLO     RB
        LBZ     WI2
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        DEC     RB
        LBR     WI1
WI2:    LOAD    RD, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LOAD    RD, WIDX
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LOAD    RD, PLENG
        LDN     RD
        STR     RF
        LOAD    RD, WDEPTH
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, WENT        ; the name onto PATH, then a /
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      PATHADD
        LOAD    RD, PLENG
        LDN     RD
        ADI     LOW(PATH)
        PLO     RF
        LDI     HIGH(PATH)
        ADCI    0
        PHI     RF
        LDI     '/'
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, WCL         ; WDIR = it, WIDX = 0
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, WIDX
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      W_INTO
        LBR     WOPEN
; ---- a folder's end: out, back to where its parent was
WEND:   SEP     R4
        DW      W_OUT
        LOAD    RD, WDEPTH
        LDN     RD
        LBZ     WDONE
        SMI     1
        STR     RD
        PLO     RB              ; RF -> WSTK + 5 x depth
        LOAD    RF, WSTK
WE1:    GLO     RB
        LBZ     WE2
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        DEC     RB
        LBR     WE1
WE2:    LOAD    RD, KS_WDIR
        LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        LOAD    RD, WIDX
        LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        LOAD    RD, PLENG
        LDN     RF
        STR     RD
        ADI     LOW(PATH)       ; PATH ends there again
        PLO     RF
        LDI     HIGH(PATH)
        ADCI    0
        PHI     RF
        LDI     0
        STR     RF
        LBR     WOPEN
WDONE:  SEP     R5

; PATHADD: the 11-byte name at RC onto PATH as NAME.EXT (PLENG grows; a 0 after it)
PATHADD: LOAD   RD, PLENG
        LDN     RD
        ADI     LOW(PATH)
        PLO     RF
        LDI     HIGH(PATH)
        ADCI    0
        PHI     RF
        SEP     R4
        DW      NM2TX
        LOAD    RD, PLENG       ; PLENG = RF - PATH
        GLO     RF
        SMI     LOW(PATH)
        STR     RD
        SEP     R5
