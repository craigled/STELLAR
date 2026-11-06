; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; date.asm - DATE.PRG: DATE shows the date (and its weekday); DATE yyyy-mm-dd sets it (2000-2099), in the
; clock's own form (rtc.inc), with the weekday register to match.
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
        GHI     RF              ; (the rest of the line, kept)
        PHI     R8
        GLO     RF
        PLO     R8
        SEP     R4
        DW      RTCGET
        LBNF    S1
        SEP     R4
        DW      K_PIN
        DB      'There is no clock (a DS12887 on the Disk/UART/RTC card).',0DH,0AH,0
        SEP     R5
S1:     GHI     R8
        PHI     RF
        GLO     R8
        PLO     RF
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     SHOW            ; nothing after it: show
        SEP     R4              ; yyyy-mm-dd
        DW      DECARG
        LBDF    USE
        GLO     RD              ; 2000-2099 -> YY
        SMI     LOW(2000)
        PLO     RC
        GHI     RD
        SMBI    HIGH(2000)
        LBNZ    USE
        GLO     RC
        SMI     100
        LBDF    USE
        LOAD    RD, NYY
        GLO     RC
        STR     RD
        SEP     R4
        DW      DECARG          ; the month: 1-12
        LBDF    USE
        GHI     RD
        LBNZ    USE
        GLO     RD
        LBZ     USE
        SMI     13
        LBDF    USE
        GLO     RD
        PLO     RC
        LOAD    RD, NMON
        GLO     RC
        STR     RD
        SEP     R4
        DW      DECARG          ; the day: 1 - the days in that month (29 in a leap year's February)
        LBDF    USE
        GHI     RD
        LBNZ    USE
        GLO     RD
        LBZ     USE
        PLO     RC
        LOAD    RD, NMON
        LDN     RD
        ADI     LOW(DIM - 1)
        PLO     RA
        LDI     HIGH(DIM - 1)
        ADCI    0
        PHI     RA
        LDN     RA
        PLO     RA              ; RA.0 = the days in it
        LDN     RD
        XRI     2
        LBNZ    D1
        LOAD    RD, NYY
        LDN     RD
        ANI     03H
        LBNZ    D1
        INC     RA              ; a leap February
D1:     GLO     RA
        STR     R2
        GLO     RC
        SD                      ; days - day: a borrow = too big
        LBNF    USE
        LDN     R2              ; (anything left on the line: not a date)
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USE
        LOAD    RD, DAY         ; DAY MON YY = the new date (WDAY reads them)
        GLO     RC
        STR     RD
        INC     RD
        LOAD    RF, NMON
        LDN     RF
        STR     RD
        INC     RD
        LOAD    RF, NYY
        LDN     RF
        STR     RD
        SEP     R4
        DW      WDAY            ; the weekday: Monday = 1 .. Sunday = 7 (Sunday is 0 here) - before
        LBNZ    D2              ;  RTCSET0 (WDAY uses RB; RB.0 is the clock's form from RTCSET0 on)
        LDI     7
D2:     PLO     RC
        LOAD    RD, NWD
        GLO     RC
        STR     RD
        SEP     R4
        DW      RTCSET0         ; written with the clock stopped
        LDI     86H
        PLO     RD
        LOAD    RF, NWD
        LDN     RF
        SEP     R4
        DW      RTCW
        LOAD    RF, DAY
        LDI     87H
        PLO     RD
        LDA     RF
        SEP     R4
        DW      RTCW
        LDI     88H
        PLO     RD
        LDA     RF
        SEP     R4
        DW      RTCW
        LDI     89H
        PLO     RD
        LDN     RF              ; the year: binary from 1972, BCD from 2000
        PLO     RA
        GLO     RB
        ANI     04H
        LBZ     D3
        GLO     RA
        ADI     28
        LBR     D3B
D3:     GLO     RA
D3B:    SEP     R4
        DW      RTCW
        SEP     R4
        DW      RTCSET1
        SEP     R4
        DW      RTCGET
SHOW:   SEP     R4
        DW      PDATE
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'DATE shows it; DATE yyyy-mm-dd sets it (2000-2099).',0DH,0AH,0
        SEP     R5
NYY:    DS      1               ; NYY, NMON (and DAY): the date given
NMON:   DS      1
NWD:    DS      1
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "rtc.inc"
PEND:
        END
