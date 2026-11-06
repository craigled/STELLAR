; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; head.asm - HEAD.PRG: HEAD [-n N] name - the file's first N lines (10 if not said; -N works too, as Linux's).
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
        DW      KS_MNTCHK
        SEP     R4
        DW      LNARG           ; NLEFT = the lines; RF -> the name
        SEP     R4
        DW      KS_NAMEARG      ; (not there, a folder ...: the kernel says so, back to the prompt)
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, NOTNL
        LDI     0
        STR     RD
        LOAD    RD, NLEFT       ; 0 lines: nothing
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     H9
H3:     SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    H9
        LOAD    RF, KS_DATBUF
H4:     GHI     RC
        LBNZ    H5
        GLO     RC
        LBZ     H3
H5:     DEC     RC
        SEP     R4              ; the byte out; DF = 1: it was an LF
        DW      PUTCH
        LBNF    H4
        LOAD    RD, NLEFT       ; a line: one fewer to go
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        DEC     RA
        GLO     RA
        STR     RD
        DEC     RD
        GHI     RA
        STR     RD
        LBNZ    H4
        GLO     RA
        LBNZ    H4
        SEP     R5
H9:     LBR     ENDNL
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
USAGE:  DB      'HEAD [-n N] name - the first N lines (10)',0DH,0AH,0
        INCL    "lines.inc"
        INCL    "numarg.inc"
PEND:
NLEFT:  DS      2
NOTNL:  DS      1
        END
