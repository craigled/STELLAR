; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; csv2clc.asm - CSV2CLC.PRG: CSV2CLC NAME.CSV - a CSV file (from a spreadsheet on a PC or Mac) made into an LTCALC
;   sheet, NAME.CLC beside it (never over one already there). Row n of the CSV is row n of the sheet, its fields
;   A-H: Excel's ways handled (the mark at the start, CR LF, "quoted, with commas", "" for a quote, spaces before a
;   field, no last line end); a number written with commas (1,234.50) comes in as a number; a field past H or row 32,
;   or past 60 characters, is left out. Moved out of LTCALC itself (Craig, 2026-11-24: room for the sheet).
; CSV2CLC -L NAME.CSV (how LTCALC opens a CSV: LTCALC NAME.CSV, or ^O): the sheet into /_CSV.CLC (hidden), then
;   LTCALC -C, which opens it as a sheet with no name yet.
; Memory: the CSV at IBUF ($3600-$4FFF, 6,000 bytes at most), the sheet's lines at OBUF ($5000-$6BFF).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
NROW    EQU     32
INMAX   EQU     60
CSVMAX  EQU     6000
IBUF    EQU     3600H
OBUF    EQU     5000H

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
        LOAD    RD, LMODE
        LDI     0
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF              ; -L: from LTCALC
        XRI     '-'
        LBNZ    ST1
        INC     RF
        LDA     RF
        ANI     0DFH
        XRI     'L'
        LBNZ    USAGE
        LOAD    RD, LMODE
        LDI     1
        STR     RD
        SEP     R4
        DW      K_SKIPSP
ST1:    LDN     RF
        LBZ     USAGE
        LOAD    RD, NAME11      ; the CSV (WDIR: its folder)
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, NAME11
        SEP     R4
        DW      KS_FINDN
        LBNF    ST2
        SEP     R4
        DW      K_PIN
        DB      'There is no such file.',0DH,0AH,0
        LBR     K_MAIN
ST2:    LOAD    RD, KS_DSIZE    ; 6,000 bytes at most
        LDA     RD
        LBNZ    BIG
        LDA     RD
        LBNZ    BIG
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        SMI     LOW(CSVMAX + 1)
        GHI     RC
        SMBI    HIGH(CSVMAX + 1)
        LBDF    BIG
        LOAD    RD, KS_LDDST
        LDI     HIGH(IBUF)
        STR     RD
        INC     RD
        LDI     LOW(IBUF)
        STR     RD
        LOAD    RD, KS_LDSKIP
        LDI     0
        STR     RD
        SEP     R4
        DW      KS_LOADF
        LBNF    CSVIN
        SEP     R4
        DW      K_PIN
        DB      'It could not be read.',0DH,0AH,0
        LBR     K_MAIN
BIG:    SEP     R4
        DW      K_PIN
        DB      'Too big: a CSV of 6,000 bytes at most.',0DH,0AH,0
        LBR     K_MAIN
USAGE:  SEP     R4
        DW      K_PIN
        DB      'Usage: CSV2CLC NAME.CSV   (makes NAME.CLC, a sheet for LTCALC)',0DH,0AH,0
        LBR     K_MAIN
OLD:    SEP     R4
        DW      K_PIN
        DB      'CSV2CLC does not match this LTOS: RECV SYSTEM again.',0DH,0AH,0
        LBR     K_MAIN

; CVEND: the lines made, OBUF .. RA. -L: into /_CSV.CLC (hidden), then LTCALC -C; else NAME.CLC beside the CSV.
CVEND:  SEP     R4              ; (the spinner rubbed out)
        DW      SPINEND
        GLO     RA              ; RC = their length
        SMI     LOW(OBUF)
        PLO     RC
        GHI     RA
        SMBI    HIGH(OBUF)
        PHI     RC
        LOAD    RD, LMODE
        LDN     RD
        LBNZ    CV5
        LOAD    RD, NAME11 + 8  ; NAME.CLC, in the CSV's folder (WDIR still)
        LDI     'C'
        STR     RD
        INC     RD
        LDI     'L'
        STR     RD
        INC     RD
        LDI     'C'
        STR     RD
        GHI     RC
        STXD
        GLO     RC
        STXD
        LOAD    RD, NAME11
        SEP     R4
        DW      KS_FINDN
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        LBDF    CV2
        SEP     R4
        DW      K_PIN
        DB      'That .CLC is there already: not written (LTCALC opens the CSV too).',0DH,0AH,0
        LBR     K_MAIN
CV2:    LOAD    RD, NAME11
        LOAD    RA, OBUF
        SEP     R4
        DW      K_SAVER
        LBDF    NOSAVE
        SEP     R4
        DW      K_PIN
        DB      'Saved the sheet: LTCALC opens it.',0DH,0AH,0
        LBR     K_MAIN
CV5:    GHI     RC              ; -L: /_CSV.CLC
        STXD
        GLO     RC
        STXD
        LOAD    RF, TMPN
        LOAD    RD, NAME11
        SEP     R4
        DW      K_PARSE
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        LOAD    RD, NAME11
        LOAD    RA, OBUF
        SEP     R4
        DW      K_SAVER
        LBDF    NOSAVE
        LOAD    RD, NAME11      ; hidden (DIR -h shows it)
        SEP     R4
        DW      KS_FINDN
        LBDF    CV7
        GLO     RF
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDN     RF
        ORI     02H
        STR     RF
        LOAD    RD, KS_DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
CV7:    LOAD    RF, LTCMD       ; then LTCALC -C
        LOAD    RD, KS_LINE
CV8:    LDA     RF
        STR     RD
        INC     RD
        LBNZ    CV8
        LBR     K_EXEC
NOSAVE: SEP     R4
        DW      K_PIN
        DB      'Not saved: the card or the folder may be full.',0DH,0AH,0
        LBR     K_MAIN
TMPN:   DB      '/_CSV.CLC',0
SPK:    DB      0
        INCL    "spin.inc"
LTCMD:  DB      'LTCALC -C',0

CSVIN:  LOAD    RD, KS_LDDST
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LOAD    RD, KS_LDEND
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LOAD    RA, OBUF
        LOAD    RD, CROW
        LDI     1
        STR     RD
        INC     RD              ; CCOL
        LDI     0
        STR     RD
        SEP     R4
        DW      ATEND
        LBDF    CIDONE
        LDN     R8              ; Excel's mark (EF BB BF) at the start
        XRI     0EFH
        LBNZ    CI0
        INC     R8
        INC     R8
        INC     R8
CI0:    LOAD    RD, SPK         ; the spinner, every 16th field
        LDN     RD
        ADI     1
        STR     RD
        ANI     0FH
        LBNZ    CI0S
        SEP     R4
        DW      SPIN
CI0S:   LOAD    RD, FSTART      ; a field: its line's start kept (dropped if it makes none)
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, FLEN
        LDI     0
        STR     RD
        LOAD    RD, CCOL        ; its name: the column, the row, a space
        LDN     RD
        ADI     'A'
        STR     RA
        INC     RA
        LOAD    RD, CROW
        LDN     RD
        PLO     RC
        LDI     0
        PHI     RC
CI1:    GLO     RC
        SMI     10
        LBNF    CI2
        PLO     RC
        GHI     RC
        ADI     1
        PHI     RC
        LBR     CI1
CI2:    GHI     RC
        LBZ     CI3
        ADI     '0'
        STR     RA
        INC     RA
CI3:    GLO     RC
        ADI     '0'
        STR     RA
        INC     RA
        LDI     ' '
        STR     RA
        INC     RA
        GHI     RA              ; RB = where the field's own characters start
        PHI     RB
        GLO     RA
        PLO     RB
CI4:    SEP     R4              ; spaces before it
        DW      ATEND
        LBDF    CIEND
        LDN     R8
        XRI     ' '
        LBNZ    CI5
        INC     R8
        LBR     CI4
CI5:    LDN     R8
        XRI     '"'
        LBZ     CIQ
CIU:    SEP     R4              ; to a comma or the line's end
        DW      ATEND
        LBDF    CIEND
        SEP     R4
        DW      CIENDQ
        LBDF    CIEND
        LDA     R8
        SEP     R4
        DW      PUTF
        LBR     CIU
CIQ:    INC     R8              ; "quoted"
CIQ1:   SEP     R4
        DW      ATEND
        LBDF    CIEND
        LDA     R8
        PLO     RC
        XRI     '"'
        LBZ     CIQQ
        GLO     RC
        XRI     0AH
        LBZ     CIQS
        GLO     RC
        XRI     0DH
        LBZ     CIQS
        GLO     RC
        LBR     CIQP
CIQS:   LDI     ' '
CIQP:   SEP     R4
        DW      PUTF
        LBR     CIQ1
CIQQ:   SEP     R4              ; "" is one "; a lone " ends it
        DW      ATEND
        LBDF    CIEND
        LDN     R8
        XRI     '"'
        LBNZ    CISK
        INC     R8
        LDI     '"'
        LBR     CIQP
CISK:   SEP     R4              ; after it: on to the comma or the line's end
        DW      ATEND
        LBDF    CIEND
        SEP     R4
        DW      CIENDQ
        LBDF    CIEND
        INC     R8
        LBR     CISK
CIEND:  LOAD    RD, FLEN        ; a line for it? something in it, within H and row 32
        LDN     RD
        LBZ     CIDROP
        LOAD    RD, CCOL
        LDN     RD
        SMI     8
        LBDF    CIDROP
        LOAD    RD, CROW
        LDN     RD
        SMI     NROW + 1
        LBDF    CIDROP
        SEP     R4              ; 1,234.50: the commas out, a number
        DW      CINUM
        LDI     0AH
        STR     RA
        INC     RA
        LBR     CINX
CIDROP: LOAD    RD, FSTART
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
CINX:   SEP     R4              ; what ended it: a comma (the next column), a line end (the next row), the end
        DW      ATEND
        LBDF    CIDONE
        LDA     R8
        PLO     RC
        XRI     ','
        LBNZ    CIN1
        LOAD    RD, CCOL
        LDN     RD
        XRI     0FFH
        LBZ     CI0
        LDN     RD
        ADI     1
        STR     RD
        LBR     CI0
CIN1:   GLO     RC              ; CR: and an LF after it
        XRI     0DH
        LBNZ    CIN3
        SEP     R4
        DW      ATEND
        LBDF    CIN3
        LDN     R8
        XRI     0AH
        LBNZ    CIN3
        INC     R8
CIN3:   LOAD    RD, CCOL
        LDI     0
        STR     RD
        LOAD    RD, CROW
        LDN     RD
        XRI     0FFH
        LBZ     CIN4
        LDN     RD
        ADI     1
        STR     RD
CIN4:   SEP     R4
        DW      ATEND
        LBDF    CIDONE
        LBR     CI0
CIDONE: LBR     CVEND           ; RA: the lines' top
; CINUM: the field at RB .. RA: if it is a number written with commas ([+-] digits and commas, then .digits - a
;   digit and a comma in it), the commas taken out and RA moved back (Craig, 2026-11-24). RC RD RF used.
CINUM:  GHI     RB
        PHI     RF
        GLO     RB
        PLO     RF
        LDI     0               ; RC.0: 1 a digit, 2 a comma, 4 the point
        PLO     RC
        SEP     R4
        DW      RFRA
        LBDF    CN9
        LDN     RF              ; a sign first
        XRI     '-'
        LBZ     CNS
        LDN     RF
        XRI     '+'
        LBNZ    CN1
CNS:    INC     RF
CN1:    SEP     R4
        DW      RFRA
        LBDF    CNEND
        LDA     RF
        PLO     RD
        SMI     '0'
        LBNF    CN2
        SMI     10
        LBDF    CN2
        GLO     RC              ; a digit
        ORI     1
        PLO     RC
        LBR     CN1
CN2:    GLO     RD              ; a comma: before the point only
        XRI     ','
        LBNZ    CN3
        GLO     RC
        ANI     4
        LBNZ    CN9
        GLO     RC
        ORI     2
        PLO     RC
        LBR     CN1
CN3:    GLO     RD              ; the point: once
        XRI     '.'
        LBNZ    CN9
        GLO     RC
        ANI     4
        LBNZ    CN9
        GLO     RC
        ORI     4
        PLO     RC
        LBR     CN1
CNEND:  GLO     RC              ; a digit and a comma: the commas out
        ANI     3
        XRI     3
        LBNZ    CN9
        GHI     RB
        PHI     RF
        PHI     RD
        GLO     RB
        PLO     RF
        PLO     RD
CN4:    SEP     R4
        DW      RFRA
        LBDF    CN5
        LDA     RF
        XRI     ','
        LBZ     CN4
        XRI     ','
        STR     RD
        INC     RD
        LBR     CN4
CN5:    GHI     RD
        PHI     RA
        GLO     RD
        PLO     RA
CN9:    SEP     R5
; RFRA: DF = 1 if RF = RA
RFRA:   GLO     RF
        STR     R2
        GLO     RA
        XOR
        LBNZ    RR0
        GHI     RF
        STR     R2
        GHI     RA
        XOR
        LBNZ    RR0
        LDI     1
        SHR
        SEP     R5
RR0:    LDI     0
        SHR
        SEP     R5
; CIENDQ: DF = 1 if R8 is at a comma, a CR or an LF
CIENDQ: LDN     R8
        XRI     ','
        LBZ     CQ1
        LDN     R8
        XRI     0DH
        LBZ     CQ1
        LDN     R8
        XRI     0AH
        LBZ     CQ1
        LDI     0
        SHR
        SEP     R5
CQ1:    LDI     1
        SHR
        SEP     R5
; ATEND: DF = 1 if R8 = R9 (the CSV's end)
ATEND:  GLO     R8
        STR     R2
        GLO     R9
        XOR
        LBNZ    AE0
        GHI     R8
        STR     R2
        GHI     R9
        XOR
        LBNZ    AE0
        LDI     1
        SHR
        SEP     R5
AE0:    LDI     0
        SHR
        SEP     R5
; PUTF: D to the field's line at RA, if it has fewer than 60 characters yet (RD used)
PUTF:   STXD
        LOAD    RD, FLEN
        LDN     RD
        XRI     INMAX
        LBZ     PF9
        LDN     RD
        ADI     1
        STR     RD
        IRX
        LDX
        STR     RA
        INC     RA
        SEP     R5
PF9:    IRX
        SEP     R5

PEND:
LMODE:  DS      1               ; 1: -L (from LTCALC)
NAME11: DS      11
CROW:   DS      1
CCOL:   DS      1
FSTART: DS      2
FLEN:   DS      1
        END
