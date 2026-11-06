; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; memverse.asm - MEMVERSE.PRG: one line of /BIBLE/MEMVERSE.TXT, picked at random, wrapped at the words.
; A line is a verse: blank lines do not count, the spaces before it go, and UTF-8 dashes and quotes become plain
; ones. The clock's date and time, stirred with a 16-bit xorshift, pick the line; two passes over the file (count,
; then keep the one picked), so the file can be any length. With no clock it is always the same line.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
WIDTH   EQU     76              ; columns of text

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
        LOAD    RD, TARGET      ; first: count them (no line is number $FFFF)
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      SCAN
        LOAD    RD, IDX
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     NONE
        SEP     R4              ; DF = 1: no clock (the numbers stay 0)
        DW      RTCGET
        LOAD    RA, 1802H
        LOAD    RF, SEC         ; SEC MIN HOUR DAY MON YY: each stirred in
        LDI     6
        PLO     R8
ST1:    LDA     RF
        STR     R2
        GLO     RA
        XOR
        PLO     RA
        SEP     R4
        DW      STIR
        DEC     R8
        GLO     R8
        LBNZ    ST1
        SEP     R4
        DW      STIR
        SEP     R4
        DW      STIR
        SEP     R4              ; TARGET = RA mod the lines
        DW      MODN
        LOAD    RD, TARGET
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        SEP     R4
        DW      SCAN
        SEP     R4
        DW      K_PCRLF
        SEP     R4
        DW      SHOW
        SEP     R4
        DW      K_PCRLF
        SEP     R5
NONE:   SEP     R4
        DW      K_PIN
        DB      'There are no verses in /BIBLE/MEMVERSE.TXT.',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
; STIR: RA through a 16-bit xorshift: x ^= x << 7, x ^= x >> 9, x ^= x << 8
STIR:   GHI     RA
        SHR
        GLO     RA
        SHRC
        STR     R2
        GHI     RA
        XOR
        PHI     RA
        LDI     0
        SHRC
        STR     R2
        GLO     RA
        XOR
        PLO     RA
        GHI     RA
        SHR
        STR     R2
        GLO     RA
        XOR
        PLO     RA
        GLO     RA
        STR     R2
        GHI     RA
        XOR
        PHI     RA
        SEP     R5
; MODN: RB = RA mod IDX
MODN:   LDI     0
        PHI     RB
        PLO     RB
        LDI     16
        PLO     R8
MD1:    GLO     RA
        SHL
        PLO     RA
        GHI     RA
        SHLC
        PHI     RA
        GLO     RB
        SHLC
        PLO     RB
        GHI     RB
        SHLC
        PHI     RB
        LOAD    RD, IDX+1
        SEX     RD
        GLO     RB
        SM
        PLO     R9
        DEC     RD
        GHI     RB
        SMB
        SEX     R2
        LBNF    MD2
        PHI     RB
        GLO     R9
        PLO     RB
MD2:    DEC     R8
        GLO     R8
        LBNZ    MD1
        SEP     R5
; SCAN: through the file: IDX = the lines with something on them; line TARGET in LBUF (0-ended), and it stops there
SCAN:   LOAD    RF, FNAME
        SEP     R4
        DW      KS_NAMEARG      ; (not there: the kernel says so, back to the prompt)
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, IDX
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, HAS
        LDI     0
        STR     RD
        LOAD    RD, MB
        LDI     0
        STR     RD
        SEP     R4
        DW      LPHOME
SC1:    SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    SC9
        LOAD    RF, KS_DATBUF
SC2:    GHI     RC
        LBNZ    SC3
        GLO     RC
        LBZ     SC1
SC3:    DEC     RC
        LDA     RF
        PLO     R9
        XRI     0DH
        LBZ     EOL
        GLO     R9
        XRI     0AH
        LBZ     EOL
        GLO     R9
        ANI     80H
        LBNZ    HIGHB
        GLO     R9              ; a space or less before the verse: left out
        SMI     21H
        LBDF    PUT
        LOAD    RD, HAS
        LDN     RD
        LBZ     SC2
PUT:    LOAD    RD, HAS
        LDI     1
        STR     RD
        LOAD    RD, LP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GHI     RA              ; full: the rest of the line is left out
        XRI     HIGH(LEND)
        LBZ     SC2
        GLO     R9
        STR     RA
        INC     RA
        LOAD    RD, LP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LBR     SC2
; a byte over $7F: a UTF-8 character, taken as one plain one when its last byte comes
HIGHB:  GLO     R9
        SMI     0C0H
        LBNF    CONT
        LOAD    RD, LEAD        ; the first byte: LEAD; MB = how many follow
        GLO     R9
        STR     RD
        LOAD    RD, MB
        LDI     1
        STR     RD
        GLO     R9
        SMI     0E0H
        LBNF    SC2
        LDI     2
        STR     RD
        GLO     R9
        SMI     0F0H
        LBNF    SC2
        LDI     3
        STR     RD
        LBR     SC2
CONT:   LOAD    RD, MB
        LDN     RD
        LBZ     QM              ; none expected: not UTF-8
        SMI     1
        STR     RD
        LBNZ    SC2
        LOAD    RD, LEAD
        LDN     RD
        XRI     0E2H
        LBNZ    QM
        GLO     R9              ; U+2018, U+2019: '   U+201C, U+201D: "   the others: -
        ANI     0FEH
        XRI     98H
        LBZ     SQ
        GLO     R9
        ANI     0FEH
        XRI     9CH
        LBZ     DQ
        LDI     '-'
        PLO     R9
        LBR     PUT
SQ:     LDI     27H
        PLO     R9
        LBR     PUT
DQ:     LDI     '"'
        PLO     R9
        LBR     PUT
QM:     LDI     '?'
        PLO     R9
        LBR     PUT
EOL:    LOAD    RD, HAS
        LDN     RD
        LBZ     SC2
        SEP     R4
        DW      LINE
        LBNF    SC2
        SEP     R5
SC9:    LOAD    RD, HAS         ; a last line with no line end
        LDN     RD
        LBZ     SC95
        SEP     R4
        DW      LINE
SC95:   SEP     R5
; LINE: a verse has ended. It is the one wanted: 0-ended, DF = 1. Else IDX + 1, LBUF empty, DF = 0.
LINE:   LOAD    RD, TARGET
        LOAD    RA, IDX
        LDA     RD
        STR     R2
        LDA     RA
        XOR
        LBNZ    LI1
        LDN     RD
        STR     R2
        LDN     RA
        XOR
        LBNZ    LI1
        LOAD    RD, LP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDI     0
        STR     RA
        LDI     1
        SHR
        SEP     R5
LI1:    LOAD    RD, IDX+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, HAS
        LDI     0
        STR     RD
        SEP     R4
        DW      LPHOME
        LDI     0
        SHR
        SEP     R5
LPHOME: LOAD    RD, LP
        LDI     HIGH(LBUF)
        STR     RD
        INC     RD
        LDI     LOW(LBUF)
        STR     RD
        SEP     R5
; SHOW: LBUF in lines of at most WIDTH, broken at the spaces; a word longer than a line is broken where it must be
SHOW:   LOAD    RF, LBUF
SH1:    GHI     RF              ; RA looks ahead; R8 = the last space it passed (0: none)
        PHI     RA
        GLO     RF
        PLO     RA
        LDI     0
        PHI     R8
        PLO     R8
        LDI     WIDTH
        PLO     RB
SH2:    LDN     RA
        LBZ     SHEND           ; the rest fits
        XRI     ' '
        LBNZ    SH3
        GHI     RA
        PHI     R8
        GLO     RA
        PLO     R8
SH3:    INC     RA
        DEC     RB
        GLO     RB
        LBNZ    SH2
        LDN     RA              ; a full line, and a space or the end just after it: all of it goes
        LBZ     SHEND
        XRI     ' '
        LBZ     SH4
        GHI     R8              ; else back to the last space, if there was one
        LBZ     SH4
        PHI     RA
        GLO     R8
        PLO     RA
SH4:    SEP     R4
        DW      PRTO
        SEP     R4
        DW      K_PCRLF
SH5:    LDN     RF              ; the spaces at the break go
        XRI     ' '
        LBNZ    SH1
        INC     RF
        LBR     SH5
SHEND:  SEP     R4
        DW      PRTO
        LBR     K_PCRLF
; PRTO: RF up to RA, out
PRTO:   GLO     RF
        STR     R2
        GLO     RA
        XOR
        LBNZ    PR1
        GHI     RF
        STR     R2
        GHI     RA
        XOR
        LBZ     PR9
PR1:    LDA     RF
        SEP     R4
        DW      F_TYPE
        LBR     PRTO
PR9:    SEP     R5
FNAME:  DB      '/BIBLE/MEMVERSE.TXT',0
        INCL    "rtc.inc"
PEND:
TARGET: DS      2
IDX:    DS      2
LP:     DS      2
HAS:    DS      1
MB:     DS      1
LEAD:   DS      1
        ORG     (($ + 255) / 256) * 256
LBUF:   DS      4096
LEND:   DS      256             ; (its high byte ends a line that long; never written)
        END
