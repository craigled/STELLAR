; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cons.asm - LTOS console helpers (INCL'd). Characters go out through the BIOS (F_TYPE / F_MSG), which
; knows the UART and its baud rate; the number formatting is LTOS's own.
;
;   PSTR     the zero-ended string at RF (RF ends past it)
;   PIN      the zero-ended string that follows the call:  SEP R4 / DW PIN / DB 'text',0
;   PCRLF    a new line
; All keep RD and RF unless they say otherwise; D is lost; RC is kept.

PSTR:   SEP     R4
        DW      F_MSG
        SEP     R5

PIN:    LDA     R6              ; R6 = the caller's return: the text is there
        LBZ     PIN9
        SEP     R4
        DW      F_TYPE
        LBR     PIN
PIN9:   SEP     R5              ; returns past the 0

PCRLF:  LDI     0DH
        SEP     R4
        DW      F_TYPE
        LDI     0AH
        SEP     R4
        DW      F_TYPE
        SEP     R5

