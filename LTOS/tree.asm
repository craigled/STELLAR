; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; tree.asm - TREE.PRG: TREE [-f] [-h] [folder] - the folders below this one (or the folder given) as a tree,
;   each with its files and their size; the totals at the end. A screen at a time.
;   -f: every folder and file, in each folder its folders then its files by name, a file with its size, date and
;   time - the card tool's menu 7 layout (treef.inc); -h: hidden files too.
;
;       /                          9 files     37785 bytes
;         BIN/                    27 files     38435 bytes
;         DOCS/                    3 files      2301 bytes
;           OLD/                   1 file         66 bytes
;       4 folders, 40 files, 78587 bytes
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
WMAX    EQU     8
PMAXL   EQU     120

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
        LOAD    RD, LINES       ; LINES, TFOLD (2), TFILES (4), TBYTES (4), FFLAG, HIDF, TFULL, PGIVEN: 0
        LDI     15
        PLO     RB
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST1
; ---- the flags (-f, -h, together or apart) and a folder, in any order
OPT:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     OPT9
        XRI     '-'
        LBNZ    OPTP
        INC     RF
OPT1:   LDA     RF              ; the letters
        LBZ     OPT8
        XRI     ' '
        LBZ     OPT
        XRI     ' '
        ANI     0DFH
        XRI     'F'
        LBNZ    OPT2
        LOAD    RD, FFLAG
        LDI     1
        STR     RD
        LBR     OPT1
OPT2:   XRI     'F' XOR 'H'
        LBNZ    USE
        LOAD    RD, HIDF
        LDI     1
        STR     RD
        LBR     OPT1
OPT8:   DEC     RF
        LBR     OPT
OPTP:   LOAD    RD, PGIVEN      ; a folder: one only
        LDN     RD
        LBNZ    USE
        LDI     1
        STR     RD
        LOAD    RD, PBUF        ; the word, upper case, to PBUF
        LDI     PMAXL - 20
        PLO     RB
OPP1:   LDN     RF
        LBZ     OPP2
        XRI     ' '
        LBZ     OPP2
        LDA     RF              ; a-z made A-Z, the rest as it is
        PLO     R7
        SMI     'a'
        LBNF    OPP1B
        SMI     26
        LBDF    OPP1B
        GLO     R7
        SMI     20H
        PLO     R7
OPP1B:  GLO     R7
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBZ     USE
        LBR     OPP1
OPP2:   LDI     0
        STR     RD
        LBR     OPT
OPT9:   LOAD    RD, PGIVEN
        LDN     RD
        LBZ     NOPATH
; ---- a folder given: WDIR = it, PATH = its name and a /
        LOAD    RD, PBUF        ; "/" alone: the root
        LDA     RD
        XRI     '/'
        LBNZ    GP1
        LDN     RD
        LBNZ    GP1
        LOAD    RD, KS_WDIR
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LBR     GP3
GP1:    LOAD    RF, PBUF
        LOAD    RD, FN11
        SEP     R4
        DW      K_PARSE         ; WDIR = the folder it is in
        LBDF    NOFOLD
        LOAD    RD, FN11
        SEP     R4
        DW      KS_FINDN
        LBDF    NOFOLD
        LOAD    RD, KS_DATTR    ; a folder?
        LDN     RD
        ANI     10H
        LBZ     NOFOLD
        LOAD    RD, KS_DCLUS    ; WDIR = it
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
GP3:    LOAD    RA, PBUF        ; PATH = PBUF, and a / unless it ends with one
        LOAD    RD, PATH
        LDI     0
        PLO     RB
GP4:    LDA     RA
        LBZ     GP5
        STR     RD
        INC     RD
        INC     RB
        LBR     GP4
GP5:    DEC     RD
        LDA     RD
        XRI     '/'
        LBZ     GP6
        LDI     '/'
        STR     RD
        INC     RD
        INC     RB
GP6:    LDI     0
        STR     RD
        LOAD    RD, PLENG
        GLO     RB
        STR     RD
        LBR     GO
NOPATH: SEP     R4              ; from here: PATH = its path and a / (WHERE first: it moves WDIR) ...
        DW      KS_WHERE        ; RF -> "/GAMES" ("" for the root)
        LOAD    RD, PATH
        LDI     0
        PLO     RB
ST2:    LDA     RF
        LBZ     ST3
        STR     RD
        INC     RD
        INC     RB
        GLO     RB
        XRI     PMAXL - 20
        LBNZ    ST2
ST3:    LDI     '/'
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        INC     RB
        LOAD    RD, PLENG
        GLO     RB
        STR     RD
        LOAD    RD, KS_CWD      ; ... and WDIR = CWD
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
GO:     LOAD    RD, FFLAG       ; -f: every file, sorted, as a tree (treef.inc)
        LDN     RD
        LBNZ    TREEF
        SEP     R4
        DW      WALK
        LOAD    RD, TFOLD       ; the totals
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' folders, ',0
        LOAD    RD, TFILES
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      ' files, ',0
        LOAD    RD, TBYTES
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      ' bytes',0
        SEP     R4
        DW      NEWLN
        SEP     R5

; W_INTO: its line - indented 2 a level, its name (the start: its path), then its files and their bytes
W_INTO: LOAD    RD, TFOLD
        INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, WDEPTH
        LDN     RD
        LBNZ    TI1
        LOAD    RA, PATH        ; the start: its path
        SEP     R4
        DW      PRSTR
        LOAD    RD, PLENG
        LDN     RD
        PLO     R9              ; R9.0 = the columns used
        LBR     TI4
TI1:    SHL                     ; 2 spaces a level
        PLO     R9
        PLO     RB
TI2:    LDI     ' '
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    TI2
        LOAD    RD, WENT        ; its name (the entry just gone into), and a /
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RF, NBUF
        SEP     R4
        DW      NM2TX
        LOAD    RA, NBUF
TI3:    LDA     RA
        LBZ     TI3D
        SEP     R4
        DW      F_TYPE
        INC     R9
        LBR     TI3
TI3D:   LDI     '/'
        SEP     R4
        DW      F_TYPE
        INC     R9
TI4:    GLO     R9              ; to column 26
        SMI     26
        LBDF    TI5
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        INC     R9
        LBR     TI4
TI5:    LOAD    RD, CF          ; CF (4), CB (4): 0 - then its files counted
        LDI     8
        PLO     RB
TI6:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    TI6
        LOAD    RD, KS_PAT
        LDI     11
        PLO     RB
TI7:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    TI7
        SEP     R4
        DW      KS_DOPEN
TI8:    SEP     R4
        DW      KS_DNEXT
        LBDF    TI9
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    TI8             ; a folder: its own line
        LOAD    RD, CF
        SEP     R4
        DW      INC32
        LOAD    RD, KS_DSIZE
        SEP     R4
        DW      KS_LD32
        LOAD    RD, CB
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        LBR     TI8
TI9:    LOAD    RD, CF          ; n files (1 file)
        SEP     R4
        DW      KS_LD32
        LDI     5
        SEP     R4
        DW      KS_PDEC32
        LOAD    RD, TFILES
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        LOAD    RD, CF+3
        LDN     RD
        XRI     1
        DEC     RD
        SEX     RD
        OR
        DEC     RD
        OR
        DEC     RD
        OR
        SEX     R2
        LBNZ    TIA
        SEP     R4
        DW      K_PIN
        DB      ' file ',0
        LBR     TIB
TIA:    SEP     R4
        DW      K_PIN
        DB      ' files',0
TIB:    LOAD    RD, CB
        SEP     R4
        DW      KS_LD32
        LDI     11
        SEP     R4
        DW      KS_PDEC32
        LOAD    RD, TBYTES
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        SEP     R4
        DW      K_PIN
        DB      ' bytes',0
        SEP     R4
        DW      NEWLN
        SEP     R5
W_ENTRY: SEP    R5
W_OUT:  SEP     R5

USE:    SEP     R4
        DW      K_PIN
        DB      'Usage: TREE [-f] [-h] [folder]   (-f every file, by name, with its size and date; -h hidden ones too)',0DH,0AH,0
        LBR     FAIL
NOFOLD: SEP     R4
        DW      K_PIN
        DB      'There is no folder ',0
        LOAD    RA, PBUF
        SEP     R4
        DW      PRSTR
        SEP     R4
        DW      K_PIN
        DB      0DH,0AH,0
FAIL:   LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "tools.inc"
        INCL    "walk.inc"
        INCL    "treef.inc"
PEND:
LINES:  DS      1               ; LINES, TFOLD, TFILES, TBYTES: in this order
TFOLD:  DS      2
TFILES: DS      4
TBYTES: DS      4
FFLAG:  DS      1               ; (cleared with LINES ... TBYTES: in this order after them)
HIDF:   DS      1
TFULL:  DS      1
PGIVEN: DS      1
CF:     DS      4               ; CF, CB: in this order
CB:     DS      4
NBUF:   DS      14
WDEPTH: DS      1               ; WDEPTH, WIDX: in this order
WIDX:   DS      2
WCL:    DS      2
WENT:   DS      2
PLENG:  DS      1
PATH:   DS      PMAXL + 14
WSTK:   DS      WMAX * 5
PBUF:   DS      PMAXL
FN11:   DS      11
ETOP:   DS      2               ; TREE -f (treef.inc)
LEVEL:  DS      1
CREC:   DS      2
LASTF:  DS      1
FRAMES: DS      WMAX * 8
PREF:   DS      WMAX * 4
ESTK:                           ; its records, from here to ETOPL
        END
