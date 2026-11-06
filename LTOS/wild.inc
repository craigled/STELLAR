; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; wild.inc - shared by MV.PRG and COPY.PRG (INCL'd at their end): the "from" name, the "to" folder, and the
; walk through the files a wildcard name matches.
;
;   SRCARG  RF -> the "from" path: SNM = its name (wildcards allowed), SDIR = its folder, WILD = 1 if it has
;           * or ?. RF past it. Not a path: the message, and back to LTOS.
;   DSTARG  RF -> the "to" path: DNM = its name, DDIR = its folder, ISDIR = 1 if it names a folder (then DDIR
;           = that folder). No wildcards. Not a path: the message, and back to LTOS.
;   MATCHN  the NSKIP-th file (not folder; from 0) in SDIR that SNM matches: DF = 0, RF -> its entry (and
;           DCLUS, DSIZE ... as DNEXT leaves them); DF = 1: no more.
;   CP2     the 2 bytes at RD -> RC.          CP11  the 11 bytes at RD -> RC.

SRCARG: LOAD    RD, SNM
        SEP     R4
        DW      KS_PARSE
        LBDF    PERR
        LOAD    RD, KS_WDIR     ; SDIR = its folder
        LOAD    RC, SDIR
        SEP     R4
        DW      CP2
        LOAD    RD, SNM         ; WILD = a '?' in it
        LOAD    RC, WILD
        LDI     0
        STR     RC
        LDI     11
        PLO     RB
SA1:    LDA     RD
        XRI     '?'
        LBNZ    SA2
        LDI     1
        STR     RC
SA2:    DEC     RB
        GLO     RB
        LBNZ    SA1
        SEP     R5
PERR:   XRI     3               ; KS_PARSE's DF = 1: D = 3 a folder ("DOCS/"), not a name in it
        LBZ     KS_BADNAME
        XRI     3
        LBR     KS_PPERR

DSTARG: LOAD    RD, ISDIR
        LDI     0
        STR     RD
        LOAD    RD, DNM
        SEP     R4
        DW      KS_PARSE
        LBNF    DS1
        XRI     3
        LBNZ    DS0
        LOAD    RD, ISDIR       ; "DOCS/", "/", "..": a folder - WDIR is it
        LDI     1
        STR     RD
        LBR     DS3
DS0:    XRI     3
        LBR     KS_PPERR
DS1:    LOAD    RD, DNM         ; a name: no wildcards ...
        LDI     11
        PLO     RB
DS2:    LDA     RD
        XRI     '?'
        LBZ     KS_BADNAME
        DEC     RB
        GLO     RB
        LBNZ    DS2
        GHI     RF              ; (FOLDIN uses RF)
        STXD
        GLO     RF
        STXD
        LOAD    RD, DNM         ; ... and a folder by that name: into it
        SEP     R4
        DW      KS_FOLDIN
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LBDF    DS3
        LOAD    RD, ISDIR
        LDI     1
        STR     RD
DS3:    LOAD    RD, KS_WDIR     ; DDIR = the folder it goes in
        LOAD    RC, DDIR
        LBR     CP2

MATCHN: LOAD    RD, SDIR        ; WDIR = SDIR, PAT = SNM
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, SNM
        LOAD    RC, KS_PAT
        SEP     R4
        DW      CP11
        SEP     R4
        DW      KS_DOPEN
        LOAD    RD, NSKIP
        LDN     RD
        PLO     R9              ; (DNEXT leaves R9 alone)
MN1:    SEP     R4
        DW      KS_DNEXT
        LBDF    MN9
        LOAD    RD, KS_DATTR    ; folders: not counted
        LDN     RD
        ANI     10H
        LBNZ    MN1
        GLO     R9
        LBZ     MN8
        DEC     R9
        LBR     MN1
MN8:    LDI     0
        SHR
MN9:    SEP     R5

CP2:    LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R5
CP11:   LDI     11
        PLO     RB
C11:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    C11
        SEP     R5
; NOTDIR / SAMEDIR: the wildcard forms' two refusals
NOTDIR: SEP     R4
        DW      K_PIN
        DB      'With * or ? the second name must be a folder (DOCS, DOCS/, .., /).',0DH,0AH,0
        SEP     R5
SAMEDIR: SEP    R4
        DW      K_PIN
        DB      'They are in that folder already.',0DH,0AH,0
        SEP     R5
; SAMED: DF = 1 if SDIR = DDIR
SAMED:  LOAD    RD, SDIR
        LOAD    RC, DDIR
        LDA     RD
        STR     R2
        LDA     RC
        XOR
        LBNZ    SD9
        LDN     RD
        STR     R2
        LDN     RC
        XOR
        LBNZ    SD9
        LDI     1
        SHR
        SEP     R5
SD9:    LDI     0
        SHR
        SEP     R5
; PCUR: "  NAME.EXT" (CUR's 11 bytes)
PCUR:   SEP     R4
        DW      K_PIN
        DB      '  ',0
        LOAD    RD, CUR
        LBR     KS_PFNAMD

SNM:    DS      11
DNM:    DS      11
CUR:    DS      11
SDIR:   DS      2
DDIR:   DS      2
WILD:   DS      1
ISDIR:  DS      1
NSKIP:  DS      1
NDONE:  DS      2
