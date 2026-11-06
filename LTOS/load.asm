; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; load.asm - LOAD.PRG: LOAD name [address] - a file into memory: at the address given, or a program (an LTOS header)
; where its header says ("RUN would start it"). Out of the kernel 2026-10-28 (LTOS 0.5: room for AUTOEXEC.SH).
; It runs at $7700 (the high area), so all of $3000-$6BFF can be loaded; the high area itself cannot.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     7700H - 6
        DW      START, PEND - START, START
        ORG     7700H
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        SEP     R4
        DW      KS_NAMEARG
        SEP     R4
        DW      KS_HEXARG
        LBDF    LDPROG          ; no address: it must be a program
        LOAD    RA, KS_LDDST    ; as it is, at RD
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        LOAD    RA, KS_LDSKIP
        LDI     0
        STR     RA
        LOAD    RD, KS_DSIZE    ; it must fit in $3000-$6BFF
        SEP     R4
        DW      KS_LD32
        GHI     R8
        LBNZ    KS_TOOBIG
        GLO     R8
        LBNZ    KS_TOOBIG
        SEP     R4
        DW      LFITS
        SEP     R4
        DW      KS_LOADF
        LBDF    KS_LDFAIL
        SEP     R4
        DW      K_PIN
        DB      'Loaded ',0
        SEP     R4
        DW      PDONE
        LBR     K_MAIN
LDPROG: SEP     R4
        DW      KS_PROGHDR
        LBDF    KS_NOTPROG
        SEP     R4
        DW      LFITS
        SEP     R4
        DW      KS_LOADF
        LBDF    KS_LDFAIL
        SEP     R4
        DW      K_PIN
        DB      'Loaded ',0
        SEP     R4
        DW      PDONE
        SEP     R4
        DW      K_PIN
        DB      'It starts at $',0
        LOAD    RD, KS_LDEXEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        SEP     R4
        DW      K_PHEX4
        SEP     R4
        DW      K_PIN
        DB      ' - RUN would start it.',0DH,0AH,0
        LBR     K_MAIN
; LFITS: the kernel's FITS (R7 = the length; a program's: PROGHDR checked it), and not in the high area - LOAD is
;        there itself
LFITS:  SEP     R4
        DW      KS_FITS
        LBDF    KS_TOOBIG
        LOAD    RD, KS_LDDST
        LDN     RD
        SMI     HIGH(PROGHI)
        LBDF    KS_TOOBIG
        SEP     R5
PROGHI  EQU     6C00H
; PDONE: "NAME.EXT, n bytes at $aaaa-$bbbb"
PDONE:  SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ', ',0
        LOAD    RD, KS_LDEND    ; bytes = LDEND - LDDST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, KS_LDDST+1
        SEX     RD
        GLO     RC
        SM
        PLO     R7
        DEC     RD
        GHI     RC
        SMB
        PHI     R7
        SEX     R2
        LDI     0
        PHI     R8
        PLO     R8
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      ' bytes at $',0
        LOAD    RD, KS_LDDST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        SEP     R4
        DW      K_PHEX4
        SEP     R4
        DW      K_PIN
        DB      '-$',0
        LOAD    RD, KS_LDEND
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        DEC     RD
        SEP     R4
        DW      K_PHEX4
        SEP     R4
        DW      K_PCRLF
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
