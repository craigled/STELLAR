; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; grep.asm - GREP.PRG: GREP [-i] [-n] text names - the lines of the files that contain the text (as Linux's grep).
;   -i any case; -n line numbers. Text with spaces in quotes: GREP "two words" *.TXT. Names: paths or patterns by
;   DIR's rules. With several files each line starts with the file's name. Lines are LF-ended (CR dropped);
;   past 250 characters a line is cut. A screen at a time.
;
;       GREP -n lot DOCS        NOTE.TXT:12:Abraham had a nephew named Lot   (-i)
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
FLMAX   EQU     100
LMAX    EQU     250
PMAX    EQU     60

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
        LOAD    RD, LINES       ; LINES, FCASE, FNUM: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
; ---- the flags
AR1:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        XRI     '-'
        LBNZ    AR5
        INC     RF
AR2:    LDN     RF
        LBZ     USE
        XRI     ' '
        LBZ     AR1
        LDA     RF
        ORI     20H
        XRI     'i'
        LBNZ    AR3
        LOAD    RD, FCASE
        LBR     AR4
AR3:    XRI     'i' XOR 'n'
        LBNZ    USE
        LOAD    RD, FNUM
AR4:    LDI     1
        STR     RD
        LBR     AR2
; ---- the text (in quotes, it may hold spaces) -> PATT, PLEN; upper case with -i
AR5:    LDN     RF
        LBZ     USE
        LOAD    RD, PATT
        LDI     0
        PLO     RB              ; RB.0 = its length
        PHI     RB              ; RB.1 = the quote that ends it (0: a space)
        LDN     RF
        XRI     '"'
        LBNZ    AR6
        INC     RF
        LDI     '"'
        PHI     RB
AR6:    LDN     RF
        LBZ     AR8
        STR     R2
        GHI     RB
        LBNZ    AR6Q
        LDN     R2
        XRI     ' '
        LBZ     AR8
        LBR     AR6C
AR6Q:   LDN     R2
        XRI     '"'
        LBNZ    AR6C
        INC     RF              ; (past the closing quote)
        LBR     AR8
AR6C:   LDA     RF
        SEP     R4
        DW      FOLD
        STR     RD
        GLO     RB
        XRI     PMAX
        LBZ     AR6
        INC     RD
        INC     RB
        LBR     AR6
AR8:    GLO     RB
        LBZ     USE
        LOAD    RD, PLEN
        GLO     RB
        STR     RD
        LDN     RF              ; then the names
        LBZ     USE
        SEP     R4
        DW      FLIST
        LOAD    RD, FLN
        LDN     RD
        LBNZ    GF0
        SEP     R4
        DW      K_PIN
        DB      'No file matches.',0DH,0AH,0
        LBR     ST2
GF0:    LOAD    RD, K_STAT      ; the exit status (as grep's): 1 until a line has the text
        LDI     1
        STR     RD
        LOAD    RD, FI
        LDI     0
        STR     RD
; ---- each file, a line at a time: LBUF (LLEN), LNO
GF1:    LOAD    RD, FI
        LDN     RD
        PLO     RC
        SEP     R4
        DW      FLGET
        LOAD    RF, NAMEP
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        SEP     R4
        DW      KS_FINDN
        LBDF    GFN
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, LNO         ; LNO (2), LLEN: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, SREM        ; nothing read yet
        LDI     0
        STR     RD
        INC     RD
        STR     RD
GL1:    SEP     R4              ; the next byte: D, DF = 1 at the end
        DW      GETB
        LBDF    GLE
        PLO     RA
        XRI     0DH
        LBZ     GL1             ; CR: dropped
        XRI     0DH XOR 0AH
        LBZ     GLL
        LOAD    RD, LLEN        ; into the line, if there is room
        LDN     RD
        XRI     LMAX
        LBZ     GL1
        XRI     LMAX
        ADI     LOW(LBUF)
        PLO     RF
        LDI     HIGH(LBUF)
        ADCI    0
        PHI     RF
        GLO     RA
        STR     RF
        LDN     RD
        ADI     1
        STR     RD
        LBR     GL1
GLL:    SEP     R4              ; an LF: the line ends
        DW      LINE
        LBR     GL1
GLE:    LOAD    RD, LLEN        ; the end: a last line with no LF
        LDN     RD
        LBZ     GFN
        SEP     R4
        DW      LINE
GFN:    LOAD    RD, FI          ; the next file
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, FLN
        LDN     RD
        SM
        LBNZ    GF1
        SEP     R5

; LINE: a line has ended - LNO + 1; printed if it has the text; LLEN = 0
LINE:   LOAD    RD, LNO
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
        LOAD    RD, LLEN        ; RB.0 = places the text could start: LLEN - PLEN + 1
        LDN     RD
        STR     R2
        LOAD    RD, PLEN
        LDN     RD
        SD                      ; LLEN - PLEN
        LBNF    LN9             ; shorter than the text
        ADI     1
        PLO     RB
        LOAD    RF, LBUF
LN1:    GHI     RF              ; RA -> here in the line, RC -> the text
        PHI     RA
        GLO     RF
        PLO     RA
        LOAD    RC, PATT
        LOAD    RD, PLEN
        LDN     RD
        PHI     RB              ; RB.1 = characters left to compare
LN2:    LDA     RA
        SEP     R4
        DW      FOLD
        STR     R2
        LDA     RC
        XOR
        LBNZ    LN3
        GHI     RB
        SMI     1
        PHI     RB
        LBNZ    LN2
        LBR     LNP             ; all of it: a match
LN3:    INC     RF
        DEC     RB
        GLO     RB
        LBNZ    LN1
        LBR     LN9
LNP:    LOAD    RD, K_STAT      ; a line has it: status 0
        LDI     0
        STR     RD
        LOAD    RD, FLN         ; print it: [name:][n:]line
        LDN     RD
        SMI     2
        LBNF    LP1
        LOAD    RF, NAMEP
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      KS_PFNAMD
        LDI     ':'
        SEP     R4
        DW      F_TYPE
LP1:    LOAD    RD, FNUM
        LDN     RD
        LBZ     LP2
        LOAD    RF, LNO
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      K_PDEC
        LDI     ':'
        SEP     R4
        DW      F_TYPE
LP2:    LOAD    RD, LLEN
        LDN     RD
        PLO     RB
        LOAD    RF, LBUF
LP3:    GLO     RB
        LBZ     LP4
        LDA     RF
        SEP     R4
        DW      F_TYPE
        DEC     RB
        LBR     LP3
LP4:    SEP     R4
        DW      NEWLN
LN9:    LOAD    RD, LLEN
        LDI     0
        STR     RD
        SEP     R5

; FOLD: D in upper case if -i (else as it is). Uses R8, R9 only.
FOLD:   PLO     R9
        LOAD    R8, FCASE
        LDN     R8
        LBZ     FD9
        GLO     R9
        SMI     'a'
        LBNF    FD9
        SMI     26
        LBDF    FD9
        GLO     R9
        SMI     20H
        SEP     R5
FD9:    GLO     R9
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'GREP [-i] [-n] text names - the lines with the text (-i any case, -n numbers)',0DH,0AH,0
ST2:    LOAD    RD, K_STAT      ; trouble: status 2
        LDI     2
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "tools.inc"
        INCL    "flist.inc"
        INCL    "getb.inc"
PEND:
LINES:  DS      1               ; LINES, FCASE, FNUM: in this order
FCASE:  DS      1
FNUM:   DS      1
PLEN:   DS      1
PATT:   DS      PMAX + 1
LNO:    DS      2               ; LNO, LLEN: in this order
LLEN:   DS      1
SREM:   DS      2
SPTR:   DS      2
FI:     DS      1
FLN:    DS      1
FLP:    DS      2
NXARG:  DS      2
NAMEP:  DS      2
LBUF:   DS      LMAX + 1
FLBUF:  DS      FLMAX * 13
        END
