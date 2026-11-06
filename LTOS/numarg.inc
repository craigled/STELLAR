; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; numarg.inc - NUMARG (HEAD, TAIL): INCL'd after a program's own code.

; NUMARG: RF -> digits (spaces before them skipped) -> RD (0-65535, more wraps); DF = 1: no digit there. RF ends
;         past them. Uses RC.
NUMARG: SEP     R4
        DW      K_SKIPSP
        LOAD    RD, 0
        LDN     RF
        SMI     '0'
        LBNF    NU9
        SMI     10
        LBDF    NU9
NU1:    LDN     RF
        SMI     '0'
        LBNF    NU8
        SMI     10
        LBDF    NU8
        GLO     RD              ; RD = RD x 10 + the digit: RC = 2 RD, RD = 8 RD, RD + RC
        SHL
        PLO     RC
        GHI     RD
        SHLC
        PHI     RC
        GLO     RC
        SHL
        PLO     RD
        GHI     RC
        SHLC
        PHI     RD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        GLO     RC
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RC
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        LDA     RF
        SMI     '0'
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LBR     NU1
NU8:    LDI     0
        SHR
        SEP     R5
NU9:    LDI     1
        SHR
        SEP     R5
