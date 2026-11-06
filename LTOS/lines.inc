; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lines.inc - LNARG / PUTCH / ENDNL (HEAD, TAIL): INCL'd after a program's own code. The program defines
; NLEFT (DS 2), NOTNL (DS 1) and USAGE (its usage line, 0-ended), and INCLs numarg.inc.

; LNARG: RF -> [-n N | -N] name: NLEFT = N (10 if not said), RF -> the name. Nothing there or not a number:
;        the usage, KSTAT 1, back to the prompt.
LNARG:  LOAD    RD, NLEFT
        LDI     0
        STR     RD
        INC     RD
        LDI     10
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        XRI     '-'
        LBNZ    LA2
        INC     RF
        LDN     RF
        ANI     0DFH
        XRI     'N'
        LBNZ    LA1
        INC     RF
LA1:    SEP     R4
        DW      NUMARG
        LBDF    LAUSE
        GHI     RD
        PHI     RA
        GLO     RD
        PLO     RA
        LOAD    RD, NLEFT
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
LA2:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     LAUSE
        SEP     R5
LAUSE:  LOAD    RF, USAGE
        SEP     R4
        DW      F_MSG
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     KS_MAIN

; PUTCH: the byte at RF (RF + 1) out: CR dropped, LF a new line (DF = 1), else as it is (DF = 0). NOTNL = 1
;        if the last thing out was not a new line. Keeps RA, RC.
PUTCH:  LDA     RF
        XRI     0DH
        LBZ     PU8             ; CR: dropped
        XRI     07H             ; (CR xor LF)
        LBZ     PULF
        XRI     0AH
        SEP     R4
        DW      F_TYPE
        LOAD    RD, NOTNL
        LDI     1
        STR     RD
PU8:    LDI     0
        SHR
        SEP     R5
PULF:   SEP     R4
        DW      K_PCRLF
        LOAD    RD, NOTNL
        LDI     0
        STR     RD
        LDI     1
        SHR
        SEP     R5

; ENDNL: a new line if the last thing out was not one; back to the prompt (SEP R5)
ENDNL:  LOAD    RD, NOTNL
        LDN     RD
        LBZ     EN9
        SEP     R4
        DW      K_PCRLF
EN9:    SEP     R5
