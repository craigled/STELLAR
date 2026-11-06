; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; wc.asm - WC.PRG: WC names - for each file, its lines, words and bytes (as Linux's wc); several: a total.
;   Names are paths or patterns, by DIR's rules (WC *.TXT, WC DOCS, WC A.TXT B.TXT). A line is an LF (a Mac or
;   PC file); a word is a run of characters that are not spaces, tabs or line ends.
;
;       lines    words      bytes
;          12       85        512  NOTE.TXT
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
FLMAX   EQU     100

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
        LOAD    RD, LINES       ; LINES, TL (4), TW (4), TB (4): 0
        LDI     13
        PLO     RB
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST1
        LDN     RF
        LBZ     USE
        SEP     R4              ; the files
        DW      FLIST
        LOAD    RD, FLN
        LDN     RD
        LBNZ    WC0
        SEP     R4
        DW      K_PIN
        DB      'No file matches.',0DH,0AH,0
        SEP     R5
WC0:    SEP     R4
        DW      K_PIN
        DB      '   lines    words      bytes',0
        SEP     R4
        DW      NEWLN
        LOAD    RD, FI
        LDI     0
        STR     RD
; ---- each file: found again, read through
WC1:    LOAD    RD, FI
        LDN     RD
        PLO     RC
        SEP     R4
        DW      FLGET           ; WDIR set, RD -> the name
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        LOAD    RD, NAMEP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        SEP     R4
        DW      KS_FINDN
        LBDF    WCN             ; gone since (it cannot be)
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, CL          ; CL (4), CW (4), INW: 0
        LDI     9
        PLO     RB
WC2:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    WC2
WC3:    SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    WC9
        LOAD    RF, KS_DATBUF
WC4:    GHI     RC
        LBNZ    WC5
        GLO     RC
        LBZ     WC3
WC5:    DEC     RC
        LDA     RF
        PLO     RA
        XRI     0AH
        LBNZ    WC6
        LOAD    RD, CL          ; an LF: a line
        SEP     R4
        DW      INC32
WC6:    GLO     RA              ; a space, tab, CR, LF ... (anything up to ' '): between words
        SMI     21H
        LBDF    WC7
        LOAD    RD, INW
        LDI     0
        STR     RD
        LBR     WC4
WC7:    LOAD    RD, INW         ; else: a word starts here, unless one has
        LDN     RD
        LBNZ    WC4
        LDI     1
        STR     RD
        LOAD    RD, CW
        SEP     R4
        DW      INC32
        LBR     WC4
WC9:    LOAD    RD, CL
        SEP     R4
        DW      KS_LD32
        LDI     8
        SEP     R4
        DW      KS_PDEC32       ; (it keeps R7, R8)
        LOAD    RD, TL
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        LOAD    RD, CW
        SEP     R4
        DW      KS_LD32
        LDI     9
        SEP     R4
        DW      KS_PDEC32       ; (it keeps R7, R8)
        LOAD    RD, TW
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        LOAD    RD, KS_DSIZE
        SEP     R4
        DW      KS_LD32
        LDI     11
        SEP     R4
        DW      KS_PDEC32       ; (it keeps R7, R8)
        LOAD    RD, TB
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        SEP     R4
        DW      K_PIN
        DB      '  ',0
        LOAD    RF, NAMEP
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      KS_PFNAMD
        SEP     R4
        DW      NEWLN
WCN:    LOAD    RD, FI          ; the next file
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, FLN
        LDN     RD
        SM
        LBNZ    WC1
        LDN     RD              ; more than one: the totals
        SMI     2
        LBNF    WC99
        LOAD    RD, TL
        SEP     R4
        DW      KS_LD32
        LDI     8
        SEP     R4
        DW      KS_PDEC32
        LOAD    RD, TW
        SEP     R4
        DW      KS_LD32
        LDI     9
        SEP     R4
        DW      KS_PDEC32
        LOAD    RD, TB
        SEP     R4
        DW      KS_LD32
        LDI     11
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      '  total',0
        SEP     R4
        DW      NEWLN
WC99:   SEP     R5

USE:    SEP     R4
        DW      K_PIN
        DB      'WC names - lines, words and bytes (WC *.TXT, WC DOCS)',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "tools.inc"
        INCL    "flist.inc"
PEND:
LINES:  DS      1               ; LINES, TL, TW, TB: in this order
TL:     DS      4
TW:     DS      4
TB:     DS      4
CL:     DS      4               ; CL, CW, INW: in this order
CW:     DS      4
INW:    DS      1
FI:     DS      1
FLN:    DS      1
FLP:    DS      2
NXARG:  DS      2
NAMEP:  DS      2
FLBUF:  DS      FLMAX * 13
        END
