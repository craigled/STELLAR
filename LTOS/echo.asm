; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; echo.asm - ECHO.PRG: ECHO [-n] words - the words, one space between them, then a new line (-n: none).
; Quotes ('...' or "...") keep what is in them as it is - spaces too - and are left out themselves, as sh's.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

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
        DW      K_SKIPSP
        LDI     0
        PLO     R9              ; R9.0 = 1: -n
        PHI     R9              ; R9.1 = the quote the words are in (0: none)
        PLO     RB              ; RB.0 = 1: a space is owed (words before, and a gap)
        LDN     RF              ; -n?
        XRI     '-'
        LBNZ    E2
        INC     RF
        LDN     RF
        ANI     0DFH
        XRI     'N'
        LBNZ    E0
        INC     RF
        LDN     RF
        LBZ     E1
        XRI     ' '
        LBZ     E1
        DEC     RF              ; ("-nx": words)
E0:     DEC     RF
        LBR     E2
E1:     LDI     1
        PLO     R9
        SEP     R4
        DW      K_SKIPSP
E2:     LDA     RF
        LBZ     E9
        PLO     RA
        GHI     R9
        LBZ     E3
        STR     R2              ; in quotes: the closing one?
        GLO     RA
        XOR
        LBNZ    EOUT
        PHI     R9              ; (0)
        LBR     E2
E3:     GLO     RA
        XRI     ' '
        LBNZ    E4
        LDI     1               ; a gap: one space, if a word follows
        PLO     RB
        LBR     E2
E4:     GLO     RA
        XRI     27H
        LBZ     EQO
        GLO     RA
        XRI     22H
        LBNZ    ESP
EQO:    GLO     RA              ; a quote opens
        PHI     R9
        GLO     RB
        LBZ     E2
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     0
        PLO     RB
        LBR     E2
ESP:    GLO     RB              ; the space owed first
        LBZ     EOUT
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     0
        PLO     RB
EOUT:   GLO     RA
        SEP     R4
        DW      F_TYPE
        LBR     E2
E9:     GLO     R9
        LBNZ    E10
        SEP     R4
        DW      K_PCRLF
E10:    SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
