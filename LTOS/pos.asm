; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; pos.asm - POS.PRG: POS x y - the cursor to column x, row y (1 1: the top left), as ESC [ y ; x H.
;   To the output, as CLS's codes (into a file with >). The kernel's fixed calls only (kapi.inc).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  SEP     R4              ; x
        DW      NUMARG
        LBDF    USE
        SEP     R4
        DW      ONETO
        LBDF    USE
        LOAD    RC, XCOL
        GHI     RD
        STR     RC
        INC     RC
        GLO     RD
        STR     RC
        SEP     R4              ; y
        DW      NUMARG
        LBDF    USE
        SEP     R4
        DW      ONETO
        LBDF    USE
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USE
        SEP     R4              ; ESC [ y ; x H
        DW      K_PIN
        DB      1BH,'[',0
        SEP     R4
        DW      K_PDEC
        LDI     ';'
        SEP     R4
        DW      K_OUT
        LOAD    RC, XCOL
        LDA     RC
        PHI     RD
        LDN     RC
        PLO     RD
        SEP     R4
        DW      K_PDEC
        LDI     'H'
        SEP     R4
        DW      K_OUT
        LOAD    RD, K_STAT
        LDI     0
        STR     RD
        SEP     R5
; ONETO: RD 1 - 255? DF = 1: no
ONETO:  GHI     RD
        LBNZ    OT9
        GLO     RD
        LBZ     OT9
        LDI     0
        SHR
        SEP     R5
OT9:    LDI     1
        SHR
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'POS x y - the cursor to column x, row y (1 1: the top left)',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5

        INCL    "numarg.inc"
XCOL:   DS      2
PEND:
        END
