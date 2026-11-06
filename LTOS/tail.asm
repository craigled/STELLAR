; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; tail.asm - TAIL.PRG: TAIL [-n N] name - the file's last N lines (10 if not said; -N works too). It reads the
; file twice: the lines counted, then all but the last N passed over.
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
; ---- 1. its lines: NTOT = the LFs, + 1 if the last byte is not an LF
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, NTOT        ; NTOT, NOTNL: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
T1:     SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    T5
        LOAD    RF, KS_DATBUF
T2:     GHI     RC
        LBNZ    T3
        GLO     RC
        LBZ     T1
T3:     DEC     RC
        LDA     RF
        XRI     0AH
        LBZ     T4
        LOAD    RD, NOTNL       ; (NOTNL here: the last byte was not an LF)
        LDI     1
        STR     RD
        LBR     T2
T4:     LOAD    RD, NOTNL
        LDI     0
        STR     RD
        LOAD    RD, NTOT
        SEP     R4
        DW      INC16
        LBR     T2
T5:     LOAD    RD, NOTNL       ; a last line with no LF
        LDN     RD
        LBZ     T6
        LOAD    RD, NTOT
        SEP     R4
        DW      INC16
; ---- 2. NSKIP = NTOT - N (0 if N is more), then read again: NSKIP LFs passed over, the rest out
T6:     LOAD    RD, NLEFT+1
        LDN     RD
        STR     R2
        LOAD    RD, NTOT+1
        LDN     RD
        SM
        PLO     RA
        LOAD    RD, NLEFT
        LDN     RD
        STR     R2
        LOAD    RD, NTOT
        LDN     RD
        SMB
        PHI     RA              ; RA = NTOT - N
        LBDF    T7
        LOAD    RA, 0
T7:     LOAD    RD, NSKIP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, NOTNL
        LDI     0
        STR     RD
        SEP     R4
        DW      KS_FOPEN
T8:     SEP     R4
        DW      KS_FREAD
        LBDF    T13
        LOAD    RF, KS_DATBUF
T9:     GHI     RC
        LBNZ    T10
        GLO     RC
        LBZ     T8
T10:    DEC     RC
        LOAD    RD, NSKIP       ; still passing over?
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     T12
        LDA     RF
        XRI     0AH
        LBNZ    T9
        LOAD    RD, NSKIP       ; an LF: one fewer to pass
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
        LBR     T9
T12:    SEP     R4
        DW      PUTCH
        LBR     T9
T13:    LBR     ENDNL
; INC16: the 2 bytes at RD (big-endian) + 1
INC16:  INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
USAGE:  DB      'TAIL [-n N] name - the last N lines (10)',0DH,0AH,0
        INCL    "lines.inc"
        INCL    "numarg.inc"
PEND:
NLEFT:  DS      2
NTOT:   DS      2               ; NTOT, NOTNL: in this order
NOTNL:  DS      1
NSKIP:  DS      2
        END
