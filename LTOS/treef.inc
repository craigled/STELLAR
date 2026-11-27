; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; treef.inc - TREE -f (TREE.PRG): every folder and file below the start as a tree - in each folder its folders,
;   then its files, each by name (as the card has it: NAME    EXT); a file with its size, date and time; -h: the
;   hidden ones too. The same layout as the card tool's menu 7 (tools/elf2k_card.py):
;
;       /
;       |-- BIN/
;       |   |-- GAMES/
;       |   |   `-- BALL.STL         4096  2026-11-18 22:10
;       |   `-- DIR.PRG          3021  2026-11-19 18:33
;       `-- README.TXT        1234  2026-11-07 16:34
;       2 files in 2 folders, 8351 bytes
;
; Each folder's entries are read into records ([name 11, attr 1, time 2, date 2, cluster 2, size 4] - the kernel's
; DTIME..DSIZE as they lie at $2D60) from ESTK up to ETOPL, sorted there, then printed one by one; a folder is
; gone into as its line is printed (its records above its parent's). FRAMES: for each level [base 2, end 2,
; cursor 2, its WDIR 2]. PREF: the "|   " / "    " a line starts with, 4 a level.
RECSZ   EQU     22
ETOPL   EQU     6800H           ; the records end here ($6C00: the kernel's DIRBUF)

TREEF:  LOAD    RA, PATH        ; the start's path
        SEP     R4
        DW      PRSTR
        SEP     R4
        DW      NEWLN
        LOAD    RD, ETOP
        LDI     HIGH(ESTK)
        STR     RD
        INC     RD
        LDI     LOW(ESTK)
        STR     RD
        LOAD    RD, LEVEL
        LDI     0
        STR     RD
        SEP     R4
        DW      TFLOAD          ; the start's records
TFLOOP: SEP     R4              ; RF -> this level's frame
        DW      FRAMEP
        INC     RF              ; cursor (RF + 4) = end (RF + 2)? this folder is done
        INC     RF
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA              ; RA = end
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC              ; RC = cursor
        GHI     RA
        STR     R2
        GHI     RC
        XOR
        LBNZ    TFNXT
        GLO     RA
        STR     R2
        GLO     RC
        XOR
        LBNZ    TFNXT
        LOAD    RD, LEVEL       ; done: up a level (or the end)
        LDN     RD
        LBZ     TFEND
        SMI     1
        STR     RD
        SEP     R4              ; ETOP = this level's base (its records are let go); WDIR = the parent again
        DW      FRAMEP
        GLO     RF
        ADI     RFSZ
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF              ; RF -> the level just finished
        LOAD    RD, ETOP
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        SEP     R4
        DW      FRAMEP
        GLO     RF
        ADI     6
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, KS_WDIR
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        LBR     TFLOOP
TFNXT:  GLO     RC              ; RD = this record; cursor + RECSZ; LASTF = the cursor is at the end now
        PLO     RD
        GHI     RC
        PHI     RD
        GLO     RC
        ADI     RECSZ
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        GLO     RC              ; (RF -> the cursor's low byte) store it back
        STR     RF
        DEC     RF
        GHI     RC
        STR     RF
        LOAD    RF, CREC
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        LOAD    RF, LASTF
        GHI     RA
        STR     R2
        GHI     RC
        XOR
        LBNZ    TFN1
        GLO     RA
        STR     R2
        GLO     RC
        XOR
        LBNZ    TFN1
        LDI     1
        LSKP
TFN1:   LDI     0
        STR     RF
        SEP     R4              ; the line's start: PREF's first 4 x LEVEL, then |-- or `--
        DW      TPREF
        LOAD    RD, LASTF
        LDN     RD
        LBZ     TFN2
        SEP     R4
        DW      K_PIN
        DB      '`-- ',0
        LBR     TFN3
TFN2:   SEP     R4
        DW      K_PIN
        DB      '|-- ',0
TFN3:   LOAD    RD, CREC        ; RC -> the record
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        ADI     11
        PLO     RD
        GHI     RC
        ADCI    0
        PHI     RD
        LDN     RD              ; its attr
        ANI     10H
        LBZ     TFFILE
; ---- a folder: NAME/, then into it (its PREF part: |    or 4 spaces, as it is last or not)
        LOAD    RF, NBUF
        SEP     R4
        DW      NM2TX
        LOAD    RA, NBUF
        SEP     R4
        DW      PRSTR
        LDI     '/'
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      NEWLN
        LOAD    RD, TFOLD       ; folders + 1
        INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, LEVEL       ; PREF + 4 x LEVEL: this level's part
        LDN     RD
        SHL
        SHL
        ADI     LOW(PREF)
        PLO     RF
        LDI     HIGH(PREF)
        ADCI    0
        PHI     RF
        LOAD    RD, LASTF
        LDN     RD
        LBZ     TFF1
        LDI     ' '
        LSKP
TFF1:   LDI     '|'
        STR     RF
        INC     RF
        LDI     ' '
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        LOAD    RD, LEVEL       ; too deep: not gone into
        LDN     RD
        ADI     1
        SMI     WMAX
        LBDF    TFLOOP
        LOAD    RD, CREC        ; WDIR = its first cluster
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        ADI     16
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LOAD    RD, KS_WDIR
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        LOAD    RD, LEVEL
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      TFLOAD
        LBR     TFLOOP
; ---- a file: NAME.EXT to 12 columns, its size (8), its date and time, (hidden)
TFFILE: LOAD    RF, NBUF
        SEP     R4
        DW      NM2TX
        LOAD    RA, NBUF
        LDI     12
        PLO     R9
TFL1:   LDA     RA
        LBZ     TFL2
        SEP     R4
        DW      F_TYPE
        DEC     R9
        LBR     TFL1
TFL2:   GLO     R9              ; (an 8.3 name is 12 at most)
        LBZ     TFL3
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        DEC     R9
        LBR     TFL2
TFL3:   LOAD    RD, CREC        ; its time, date, cluster, size back where the kernel keeps them (PDATE reads them)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        ADI     12
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LOAD    RA, KS_DTIME
        LDI     10
        PLO     RB
TFL4:   LDA     RC
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    TFL4
        LOAD    RD, KS_DSIZE
        SEP     R4
        DW      KS_LD32
        LDI     8
        SEP     R4
        DW      KS_PDEC32
        LOAD    RD, KS_DSIZE    ; bytes + its size
        SEP     R4
        DW      KS_LD32
        LOAD    RD, TBYTES
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        LOAD    RD, TFILES
        SEP     R4
        DW      INC32
        SEP     R4
        DW      PDATE
        LOAD    RD, CREC        ; hidden?
        LDA     RD
        PHI     RC
        LDN     RD
        ADI     11
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LDN     RC
        ANI     02H
        LBZ     TFL5
        SEP     R4
        DW      K_PIN
        DB      '  (hidden)',0
TFL5:   SEP     R4
        DW      NEWLN
        LBR     TFLOOP
; ---- the totals: n files in m folders, b bytes
TFEND:  LOAD    RD, TFILES
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      ' files in ',0
        LOAD    RD, TFOLD
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
        LOAD    RD, TFULL       ; some left out: no room
        LDN     RD
        LBZ     TFE9
        SEP     R4
        DW      K_PIN
        DB      '(a folder had more entries than there is room for: some are not shown)',0
        SEP     R4
        DW      NEWLN
TFE9:   SEP     R5

; FRAMEP: RF -> FRAMES + 8 x LEVEL
RFSZ    EQU     8
FRAMEP: LOAD    RF, LEVEL
        LDN     RF
        SHL
        SHL
        SHL
        ADI     LOW(FRAMES)
        PLO     RF
        LDI     HIGH(FRAMES)
        ADCI    0
        PHI     RF
        SEP     R5

; TPREF: PREF's first 4 x LEVEL characters
TPREF:  LOAD    RD, LEVEL
        LDN     RD
        SHL
        SHL
        PLO     RB
        LOAD    RA, PREF
TPR1:   GLO     RB
        LBZ     TPR9
        LDA     RA
        SEP     R4
        DW      F_TYPE
        DEC     RB
        LBR     TPR1
TPR9:   SEP     R5

; TFLOAD: this level's frame [base = ETOP, end, cursor = base, WDIR] - the folder at WDIR read into records from
;   ETOP (each [name 11, attr 1, DTIME..DSIZE 10]), ETOP past them, sorted: folders first, then by name
TFLOAD: SEP     R4
        DW      FRAMEP
        LOAD    RD, ETOP
        LDA     RD              ; base, cursor = ETOP
        STR     RF
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        STR     RF
        DEC     RF
        DEC     RF
        DEC     RF
        LDN     RD
        STR     RF
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        STR     RF
        INC     RF              ; WDIR
        LOAD    RD, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, KS_PAT      ; every name
        LDI     11
        PLO     RB
TFD1:   LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    TFD1
        SEP     R4
        DW      KS_DOPEN
        LOAD    RD, HIDF        ; -h: hidden ones too (DNALL: set after DOPEN)
        LDN     RD
        PLO     R7
        LOAD    RD, KS_DNALL
        GLO     R7
        STR     RD
TFD2:   SEP     R4
        DW      KS_DNEXT
        LBDF    TFD9
        LOAD    RD, ETOP        ; room for one more?
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA              ; RA = where it goes
        GLO     RA
        ADI     RECSZ
        GHI     RA
        ADCI    0
        SMI     HIGH(ETOPL)
        LBNF    TFD3
        LOAD    RD, TFULL
        LDI     1
        STR     RD
        LBR     TFD2
TFD3:   LDI     11              ; its name (RF -> it in DIRBUF)
        PLO     RB
TFD4:   LDA     RF
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    TFD4
        LOAD    RD, KS_DATTR
        LDN     RD
        STR     RA
        INC     RA
        LOAD    RD, KS_DTIME    ; DTIME DDATE DCLUS DSIZE: 10 bytes
        LDI     10
        PLO     RB
TFD5:   LDA     RD
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    TFD5
        LOAD    RD, ETOP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LBR     TFD2
TFD9:   SEP     R4              ; end = ETOP
        DW      FRAMEP
        INC     RF
        INC     RF
        LOAD    RD, ETOP
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
; ---- sorted, as an insertion sort over the records base..end: each one moved back past the larger ones
        SEP     R4
        DW      FRAMEP
        LDA     RF
        PHI     R9
        LDA     RF
        PLO     R9              ; R9 = base
        LDA     RF
        PHI     R8
        LDN     RF
        PLO     R8              ; R8 = end
        GHI     R9              ; none (an empty folder): nothing to sort
        STR     R2
        GHI     R8
        XOR
        LBNZ    TS0
        GLO     R9
        STR     R2
        GLO     R8
        XOR
        LBZ     TS9
TS0:    GLO     R9              ; RC = base + RECSZ: the first to place
        ADI     RECSZ
        PLO     RC
        GHI     R9
        ADCI    0
        PHI     RC
TS1:    GHI     RC              ; RC = end: sorted
        STR     R2
        GHI     R8
        XOR
        LBNZ    TS2
        GLO     RC
        STR     R2
        GLO     R8
        XOR
        LBZ     TS9
TS2:    GHI     RC              ; RB = RC; while RB > base and the one before it is larger: swap, RB back one
        PHI     RB
        GLO     RC
        PLO     RB
TS3:    GHI     RB
        STR     R2
        GHI     R9
        XOR
        LBNZ    TS4
        GLO     RB
        STR     R2
        GLO     R9
        XOR
        LBZ     TS8
TS4:    GLO     RB              ; RA = RB - RECSZ
        SMI     RECSZ
        PLO     RA
        GHI     RB
        SMBI    0
        PHI     RA
        SEP     R4              ; the one at RA after the one at RB? DF = 1
        DW      TCMP
        LBNF    TS8
        LDI     RECSZ           ; swap them
        PLO     R7
TS5:    LDN     RA
        PLO     RF
        LDN     RB
        STR     RA
        GLO     RF
        STR     RB
        INC     RA
        INC     RB
        DEC     R7
        GLO     R7
        LBNZ    TS5
        GLO     RB              ; RB back to where RA was: RB - 2 x RECSZ
        SMI     2 * RECSZ
        PLO     RB
        GHI     RB
        SMBI    0
        PHI     RB
        LBR     TS3
TS8:    GLO     RC              ; the next to place
        ADI     RECSZ
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LBR     TS1
TS9:    SEP     R5

; TCMP: the record at RA comes after the one at RB? DF = 1 yes, DF = 0 no. A folder before a file; then the
;   name's 11 bytes. RA, RB kept.
TCMP:   GLO     RA              ; their attrs: a folder's 10H
        ADI     11
        PLO     RF
        GHI     RA
        ADCI    0
        PHI     RF
        LDN     RF
        ANI     10H
        PLO     R7              ; R7.0 = RA's folder bit
        GLO     RB
        ADI     11
        PLO     RF
        GHI     RB
        ADCI    0
        PHI     RF
        LDN     RF
        ANI     10H
        STR     R2
        GLO     R7
        XOR
        LBZ     TC1             ; both folders or both files: by name
        GLO     R7              ; RA a folder (RB not): not after; RA a file: after
        LBZ     TCY
        LBR     TCN
TC1:    GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        GHI     RB
        PHI     RD
        GLO     RB
        PLO     RD
        LDI     11
        PLO     R7
TC2:    LDN     RD              ; RA's byte - RB's byte
        STR     R2
        LDN     RF
        SM
        LBNZ    TC3
        INC     RF
        INC     RD
        DEC     R7
        GLO     R7
        LBNZ    TC2
TCN:    LDI     0               ; the same, or before: no
        SHR
        SEP     R5
TC3:    LBNF    TCN             ; RA's smaller (a borrow): before
TCY:    LDI     1
        SHR
        SEP     R5

; PDATE: "  yyyy-mm-dd hh:mm" from KS_DDATE, KS_DTIME (as DIR prints them)
PDATE:  SEP     R4
        DW      K_PIN
        DB      '  ',0
        LOAD    RD, KS_DDATE
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC              ; year = 1980 + date >> 9
        SHR
        ADI     LOW(1980)
        PLO     RD
        LDI     HIGH(1980)
        ADCI    0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        LDI     '-'
        SEP     R4
        DW      F_TYPE
        GHI     RC              ; month = date >> 5 & 15
        SHR
        GLO     RC
        SHRC
        SHR
        SHR
        SHR
        SHR
        ANI     0FH
        SEP     R4
        DW      P2D
        LDI     '-'
        SEP     R4
        DW      F_TYPE
        GLO     RC              ; day = date & 31
        ANI     1FH
        SEP     R4
        DW      P2D
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LOAD    RD, KS_DTIME
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC              ; hour = time >> 11
        SHR
        SHR
        SHR
        SEP     R4
        DW      P2D
        LDI     ':'
        SEP     R4
        DW      F_TYPE
        GLO     RC              ; minute = time >> 5 & 63 = (hi & 7) << 3 | lo >> 5
        SHR
        SHR
        SHR
        SHR
        SHR
        STR     R2
        GHI     RC
        ANI     07H
        SHL
        SHL
        SHL
        OR
        SEP     R4
        DW      P2D
        SEP     R5
        INCL    "p2d.inc"
