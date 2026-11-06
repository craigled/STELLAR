; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; rtc.inc - the DS12887 clock for DATE.PRG and TIME.PRG (INCL'd; needs ltos.inc, kapi.inc, out/ksyms.inc).
; Registers: 0 seconds, 2 minutes, 4 hours, 6 weekday, 7 day, 8 month, 9 year, A / B status (select $80 + it).
; It is read and written in the clock's own form, as register B says: binary or BCD (bit 2), 24- or 12-hour
; (bit 1; then the hour's bit 7 = PM). The year: binary = 1972 + it (as the Elf2K BIOS keeps it), BCD = 2000 + it.
; The weekday register: Monday = 1 .. Sunday = 7 (the Elf2K BIOS's). Years 2000-2099.
;
;   RTCGET   SEC MIN HOUR DAY MON YY (2000 + YY) from the clock; DF = 1: no clock
;   PDATE    "Saturday 2026-10-17"      PTIME   "14:30:20"
;   DECARG   RF -> a decimal number -> RD (DF = 1: none); RF past it and one separator (- / : .)
;   WDAY     D = the weekday of DAY MON YY: 0 = Sunday
;   RTCSET0  freeze the clock (B's SET bit) for writing; RTCSET1 let it run again (A = $20: running)
;   RTCW     D = a value -> register RD.0 (its select, $80 + it), in the clock's form (TOFORM first)
;   TOFORM   D (binary) -> the clock's form (BCD unless B says binary)

RTCGET: LDI     8BH             ; register B: $FF = no clock
        SEP     R4
        DW      KS_RTCRD
        PLO     RB              ; RB.0 = B (KS_RTCBIN reads it there)
        XRI     0FFH
        LBNZ    RG1
        LDI     1
        SHR
        SEP     R5
RG1:    LDI     4               ; up to 4 tries: a reading the seconds did not change under
        PLO     R9
RG2:    LDI     0               ; wait while it updates (register A's bit 7)
        PLO     RA
RG3:    LDI     8AH
        SEP     R4
        DW      KS_RTCRD
        ANI     80H
        LBZ     RG4
        DEC     RA
        GLO     RA
        LBNZ    RG3
RG4:    LOAD    RF, RTCTAB      ; the registers, in SEC MIN HOUR DAY MON YY's order
        LOAD    RD, SEC
        LDI     6
        PLO     RC
RG5:    LDA     RF
        SEP     R4
        DW      KS_RTCRD
        PLO     RE
        GLO     RC              ; (the hour: 12-hour's PM bit kept apart)
        XRI     4
        LBNZ    RG6
        GLO     RE
        ANI     80H
        PHI     R9              ; R9.1 = PM
        GLO     RE
        ANI     7FH
        PLO     RE
RG6:    GLO     RE
        SEP     R4
        DW      KS_RTCBIN
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    RG5
        LDI     80H             ; the seconds again: the same?
        SEP     R4
        DW      KS_RTCRD
        SEP     R4
        DW      KS_RTCBIN
        STR     R2
        LOAD    RD, SEC
        LDN     RD
        XOR
        LBZ     RG7
        DEC     R9
        GLO     R9
        LBNZ    RG2
RG7:    GLO     RB              ; 12-hour: 12 -> 0, then PM + 12
        ANI     02H
        LBNZ    RG8
        LOAD    RD, HOUR
        LDN     RD
        XRI     12
        LBNZ    RG7A
        STR     RD
RG7A:   GHI     R9
        LBZ     RG8
        LDN     RD
        ADI     12
        STR     RD
RG8:    GLO     RB              ; the year: binary - 28 (from 1972 to from 2000)
        ANI     04H
        LBZ     RG9
        LOAD    RD, YY
        LDN     RD
        SMI     28
        STR     RD
RG9:    LDI     0
        SHR
        SEP     R5
RTCTAB: DB      80H, 82H, 84H, 87H, 88H, 89H

; PDATE / PTIME
PDATE:  SEP     R4
        DW      WDAY
        PLO     RC              ; the weekday's name: the RC.0-th in WDNAME
        LOAD    RF, WDNAME
PD1:    GLO     RC
        LBZ     PD3
PD2:    LDA     RF
        LBNZ    PD2
        DEC     RC
        LBR     PD1
PD3:    SEP     R4
        DW      KS_PSTR
        SEP     R4
        DW      K_PIN
        DB      ' 20',0
        LOAD    RD, YY
        LDN     RD
        SEP     R4
        DW      KS_P2D
        LDI     '-'
        SEP     R4
        DW      F_TYPE
        LOAD    RD, MON
        LDN     RD
        SEP     R4
        DW      KS_P2D
        LDI     '-'
        SEP     R4
        DW      F_TYPE
        LOAD    RD, DAY
        LDN     RD
        SEP     R4
        DW      KS_P2D
        LBR     K_PCRLF
PTIME:  LOAD    RD, HOUR
        LDN     RD
        SEP     R4
        DW      KS_P2D
        LDI     ':'
        SEP     R4
        DW      F_TYPE
        LOAD    RD, MIN
        LDN     RD
        SEP     R4
        DW      KS_P2D
        LDI     ':'
        SEP     R4
        DW      F_TYPE
        LOAD    RD, SEC
        LDN     RD
        SEP     R4
        DW      KS_P2D
        LBR     K_PCRLF
WDNAME: DB      'Sunday',0,'Monday',0,'Tuesday',0,'Wednesday',0,'Thursday',0,'Friday',0,'Saturday',0

; WDAY: (6 + Y + (Y + 3) / 4 + CUM7[month] + day - 1 + (a leap year, after February)) mod 7; Y = years
;       since 2000 (every 4th from 2000 a leap year, to 2099). 365 = 1 mod 7, so each year moves it on 1.
WDAY:   LOAD    RD, YY
        LDN     RD
        PLO     RC              ; RC.0 = Y
        ADI     3
        SHR
        SHR
        STR     R2
        GLO     RC
        ADD
        ADI     6 - 1
        PLO     RA              ; RA.0 = 6 + Y + (Y + 3) / 4 - 1
        LOAD    RD, MON
        LDN     RD
        PLO     RB              ; RB.0 = the month
        ADI     LOW(CUM7 - 1)
        PLO     RF
        LDI     HIGH(CUM7 - 1)
        ADCI    0
        PHI     RF
        LDN     RF
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        LOAD    RD, DAY
        LDN     RD
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GLO     RC              ; a leap year (Y mod 4 = 0), March on: + 1
        ANI     03H
        LBNZ    WD1
        GLO     RB
        SMI     3
        LBNF    WD1
        INC     RA
WD1:    GLO     RA              ; mod 7
WD2:    SMI     7
        LBDF    WD2
        ADI     7
        SEP     R5
CUM7:   DB      0, 3, 3, 6, 1, 4, 6, 2, 5, 0, 3, 5      ; the days before each month, mod 7
DIM:    DB      31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

; DECARG: RF -> digits -> RD; one separator after them is skipped
DECARG: SEP     R4
        DW      K_SKIPSP
        LOAD    RD, 0
        LDN     RF
        SMI     '0'
        LBNF    DA9
        SMI     10
        LBDF    DA9
DA1:    LDN     RF
        SMI     '0'
        LBNF    DA2
        SMI     10
        LBDF    DA2
        GLO     RD              ; RD = RD x 10 + the digit
        SHL
        PLO     RC
        GHI     RD
        SHLC
        PHI     RC              ; RC = 2 RD
        GLO     RC
        SHL
        PLO     RD
        GHI     RC
        SHLC
        PHI     RD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD              ; RD = 8 RD
        GLO     RC
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RC
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        LDA     RF
        SMI     '0'
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LBR     DA1
DA2:    LDN     RF              ; a separator: - / : .
        XRI     '-'
        LBZ     DA3
        LDN     RF
        XRI     '/'
        LBZ     DA3
        LDN     RF
        XRI     ':'
        LBZ     DA3
        LDN     RF
        XRI     '.'
        LBNZ    DA4
DA3:    INC     RF
DA4:    LDI     0
        SHR
        SEP     R5
DA9:    LDI     1
        SHR
        SEP     R5

; RTCSET0 / RTCSET1 / RTCW / TOFORM
RTCSET0: LDI    8BH             ; RB.0 = B; SET it (updates stop, the registers can be written)
        SEP     R4
        DW      KS_RTCRD
        PLO     RB
        LOAD    RD, 8BH
        GLO     RB
        ORI     80H
        LBR     RTCW0
RTCSET1: LDI    8AH             ; A = $20: the oscillator running, then B as it was (SET off)
        PLO     RD
        LDI     20H
        SEP     R4
        DW      RTCW0
        LDI     8BH
        PLO     RD
        GLO     RB
        ANI     7FH
        LBR     RTCW0
RTCW:   SEP     R4              ; (the value in the clock's form)
        DW      TOFORM
RTCW0:  PLO     RE              ; select RD.0, then the value - each from the stack slot
        GLO     RD
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RE
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R5
TOFORM: PLO     RE              ; BCD unless register B (RB.0) says binary
        GLO     RB
        ANI     04H
        LBNZ    TF9
        LDI     0
        PLO     RA
        GLO     RE
TF1:    SMI     10
        LBNF    TF2
        PLO     RE
        INC     RA
        GLO     RE
        LBR     TF1
TF2:    GLO     RA
        SHL
        SHL
        SHL
        SHL
        STR     R2
        GLO     RE
        OR
        SEP     R5
TF9:    GLO     RE
        SEP     R5

SEC:    DS      1               ; SEC MIN HOUR DAY MON YY: in this order
MIN:    DS      1
HOUR:   DS      1
DAY:    DS      1
MON:    DS      1
YY:     DS      1
