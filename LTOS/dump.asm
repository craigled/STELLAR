; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; dump.asm - DUMP.PRG: DUMP [a [n]] - memory in hex and text from a, n bytes (hex; 80 if left out); DUMP
; alone goes on from where the last one ended (the kernel keeps that, KS_DUMPA).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     6800H - 6
        DW      START, PEND - START, START
        ORG     6800H           ; (high: $2C00-$67FF stays free for what it works on)
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
; ---- DUMP [addr [len]]: 16 bytes a line, hex then text
        LOAD    RC, 80H         ; how many: 80 unless given
        SEP     R4
        DW      KS_HEXARG
        LBDF    D0              ; no address: go on from the last
        LOAD    RA, KS_DUMPA
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        SEP     R4
        DW      KS_HEXARG
        LBDF    D0
        GHI     RD
        PHI     RC
        GLO     RD
        PLO     RC
D0:     LOAD    RA, KS_DUMPA
        LDA     RA
        PHI     RF
        LDN     RA
        PLO     RF              ; RF = the address
DL:     GHI     RC              ; RC = bytes left (whole lines of 16)
        LBNZ    D1
        GLO     RC
        LBZ     DEND
D1:     GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        SEP     R4
        DW      KS_PHEX4
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     16
        PLO     RB
DH:     LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDA     RF
        SEP     R4
        DW      KS_PHEX2
        DEC     RB
        GLO     RB
        LBNZ    DH
        SEP     R4
        DW      KS_PIN
        DB      '  ',0
        GLO     RF              ; back 16 for the text
        SMI     16
        PLO     RF
        GHI     RF
        SMBI    0
        PHI     RF
        LDI     16
        PLO     RB
DT:     LDA     RF
        PLO     RA              ; (RA.0: the byte; no calls in between)
        SMI     ' '
        LBNF    DDOT
        GLO     RA
        SMI     7FH
        LBDF    DDOT
        GLO     RA
        LSKP
DDOT:   LDI     '.'
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    DT
        SEP     R4
        DW      KS_PCRLF
        GLO     RC              ; 16 fewer to go (or none, if fewer than 16 were left)
        SMI     16
        PLO     RC
        GHI     RC
        SMBI    0
        PHI     RC
        LBDF    DL
DEND:   LOAD    RA, KS_DUMPA       ; DUMP alone goes on from here
        GHI     RF
        STR     RA
        INC     RA
        GLO     RF
        STR     RA
        SEP     R5     

OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
