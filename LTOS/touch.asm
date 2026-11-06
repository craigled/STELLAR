; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; touch.asm - TOUCH.PRG: TOUCH names - each file's time set to now; a name not on the card: a new, empty file.
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
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
TO1:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     TO9
        LOAD    RD, TNAME
        SEP     R4
        DW      K_PARSE         ; WDIR = its folder
        LBDF    KS_PPERR        ; (the kernel says why, back to the prompt)
        LOAD    RD, NXARG       ; (past this word)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, TNAME       ; a wildcard is not a name
        LDI     11
        PLO     RB
TO2:    LDA     RD
        XRI     '?'
        LBZ     NOTN
        DEC     RB
        GLO     RB
        LBNZ    TO2
        LOAD    RD, TNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    TONEW
        LOAD    RD, KS_DATTR    ; a folder: left as it is
        LDN     RD
        ANI     10H
        LBNZ    TONX
        LOAD    RD, ENTP        ; there: its time (22-25 written, 18-19 used) - the entry is in DIRBUF
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      KS_STAMP
        LOAD    RD, ENTP
        LDA     RD
        PHI     RF
        LDN     RD
        ADI     18
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, KS_STD
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        INC     RF              ; 20-21
        INC     RF
        SEP     R4
        DW      KS_PUTST
        LOAD    RD, KS_DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    TOERR
        LBR     TONX
TONEW:  LOAD    RD, TNAME       ; not there: an empty file
        LOAD    RA, TNAME
        LOAD    RC, 0
        SEP     R4
        DW      K_SAVER
        LBDF    TOSV
TONX:   LOAD    RD, NXARG       ; the next name
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LBR     TO1
TO9:    SEP     R5
TOSV:   XRI     1               ; K_SAVER's D: 1 the directory is full, 2 the card is full, 3 it failed
        LBNZ    TOS2
        SEP     R4
        DW      K_PIN
        DB      'The directory is full.',0DH,0AH,0
        LBR     ST1
TOS2:   XRI     1 XOR 2
        LBNZ    TOERR
        SEP     R4
        DW      K_PIN
        DB      'The card is full.',0DH,0AH,0
        LBR     ST1
TOERR:  SEP     R4
        DW      K_PIN
        DB      'The card did not answer.',0DH,0AH,0
        LBR     ST1
NOTN:   SEP     R4
        DW      K_PIN
        DB      'That is not a file name.',0DH,0AH,0
        LBR     ST1
USE:    SEP     R4
        DW      K_PIN
        DB      'TOUCH names - the time of each set to now (a name not there: a new, empty file)',0DH,0AH,0
ST1:    LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
TNAME:  DS      11
NXARG:  DS      2
ENTP:   DS      2
        END
