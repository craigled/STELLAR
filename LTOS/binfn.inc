; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; binfn.inc - BINFN, shared by SH, STELLAR, HELP, ENANO (INCL'd among a program's own routines).
;
;   BINFN   RD -> an 11-byte name: looked for in /BIN, then in each folder in /BIN (the kernel's BINWALK: one
;           level down, the folders in the order DIR /BIN lists them, hidden ones not; the first found wins).
;           DF = 0: found, as KS_FINDN finds it (KS_WDIR = its folder); DF = 1: nowhere, or no /BIN.
;           Uses RB RC RD (and all the kernel's card routines use).
BINFN:  LOAD    RC, KS_FNAME
        LDI     11
        PLO     RB
BFN1:   LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    BFN1
        LOAD    RD, KS_UKM      ; (UKM = 1: the name itself, not NAME.SH / NAME.PRG)
        LDI     1
        STR     RD
        LBR     KS_BINWALK
