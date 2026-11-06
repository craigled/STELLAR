; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; time.asm - TIME.PRG: TIME shows the time; TIME hh:mm[:ss] sets it (24-hour), in the clock's own form (rtc.inc).
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
        SEP     R4              ; hh:mm[:ss]
        DW      DECARG
        LBDF    USE
        GHI     RD
        LBNZ    USE
        GLO     RD
        SMI     24
        LBDF    USE
        LOAD    RC, NH
        GLO     RD
        STR     RC
        SEP     R4
        DW      DECARG
        LBDF    USE
        GHI     RD
        LBNZ    USE
        GLO     RD
        SMI     60
        LBDF    USE
        LOAD    RC, NM
        GLO     RD
        STR     RC
        LOAD    RC, NS          ; the seconds: 0 if not given
        LDI     0
        STR     RC
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     T1
        SEP     R4
        DW      DECARG
        LBDF    USE
        GHI     RD
        LBNZ    USE
        GLO     RD
        SMI     60
        LBDF    USE
        LOAD    RC, NS
        GLO     RD
        STR     RC
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USE
T1:     SEP     R4
        DW      RTCSET0
        LDI     80H
        PLO     RD
        LOAD    RF, NS
        LDN     RF
        SEP     R4
        DW      RTCW
        LDI     82H
        PLO     RD
        LOAD    RF, NM
        LDN     RF
        SEP     R4
        DW      RTCW
        LOAD    RF, NH          ; the hour: 12-hour (B bit 1 = 0): 1-12, + $80 for PM
        LDN     RF
        PLO     RA
        GLO     RB
        ANI     02H
        LBNZ    T3
        LDI     0
        PHI     RA              ; RA.1 = the PM bit
        GLO     RA
        SMI     12
        LBNF    T2
        PLO     RA
        LDI     80H
        PHI     RA
T2:     GLO     RA
        LBNZ    T2A
        LDI     12
        PLO     RA
T2A:    GLO     RA
        SEP     R4
        DW      TOFORM
        STR     R2
        GHI     RA
        OR
        LBR     T4
T3:     GLO     RA
        SEP     R4
        DW      TOFORM
T4:     PLO     RC
        LDI     84H
        PLO     RD
        GLO     RC
        SEP     R4
        DW      RTCW0
        SEP     R4
        DW      RTCSET1
        SEP     R4
        DW      RTCGET
SHOW:   SEP     R4
        DW      PTIME
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'TIME shows it; TIME hh:mm[:ss] sets it (24-hour).',0DH,0AH,0
        SEP     R5
NH:     DS      1
NM:     DS      1
NS:     DS      1
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "rtc.inc"
PEND:
        END
