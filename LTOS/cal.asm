; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cal.asm - CAL.PRG: a calendar, as Unix cal lays it out.
;   CAL              this month (from the clock), today in reverse video on the screen
;   CAL year         a whole year, three months across (1-9999)
;   CAL month year   one month
; The calendar is Unix cal's: Julian up to 1752 (a leap year every 4th), Gregorian after, and September 1752
; jumps from the 2nd to the 14th. Lines are built in LINE (80 columns) and printed without trailing spaces.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        DB      'VER:1.0',0
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        GHI     RF              ; (the line, kept: RTCGET uses RF)
        PHI     R8
        GLO     RF
        PLO     R8
        LOAD    RD, TMON        ; today: none unless the clock answers and the output is the screen
        LDI     0FFH
        STR     RD
        SEP     R4
        DW      RTCGET
        LBDF    S0
        LOAD    RD, TYEAR       ; TYEAR = 2000 + YY, TMON = MON - 1, TDAY = DAY
        LOAD    RF, YY
        LDN     RF
        ADI     LOW(2000)
        PLO     RC
        LDI     HIGH(2000)
        ADCI    0
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        LOAD    RF, MON
        LDN     RF
        SMI     1
        STR     RD
        INC     RD
        LOAD    RF, DAY
        LDN     RF
        STR     RD
        LOAD    RD, CLOCK
        LDI     1
        STR     RD
S0:     GHI     R8
        PHI     RF
        GLO     R8
        PLO     RF
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     NOARG
        SEP     R4
        DW      NUMARG
        LBDF    USE
        LOAD    RC, ARG1
        SEP     R4
        DW      PUTW
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     ONEARG
        SEP     R4
        DW      NUMARG
        LBDF    USE
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USE
        SEP     R4              ; CAL month year
        DW      CHKYR
        LBDF    USE
        LOAD    RC, YEAR
        SEP     R4
        DW      PUTW
        LOAD    RD, ARG1        ; the month: 1-12
        LDA     RD
        LBNZ    USE
        LDN     RD
        LBZ     USE
        SMI     13
        LBDF    USE
        LDN     RD
        SMI     1
        LBR     MONTHV
ONEARG: LOAD    RD, ARG1        ; CAL year
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R4
        DW      CHKYR
        LBDF    USE
        LOAD    RC, YEAR
        SEP     R4
        DW      PUTW
        LBR     YEARV
NOARG:  LOAD    RD, CLOCK       ; CAL: this month
        LDN     RD
        LBZ     NOCLK
        LOAD    RD, TYEAR
        LOAD    RF, YEAR
        LDA     RD
        STR     RF
        INC     RF
        LDA     RD
        STR     RF
        LDN     RD              ; TMON
        LBR     MONTHV
NOCLK:  SEP     R4
        DW      K_PIN
        DB      'There is no clock: CAL month year, or CAL year.',0DH,0AH,0
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'Usage: CAL [[month] year]   (month 1-12, year 1-9999)',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5

; ---- one month: D = it (0-11); the title "November 2026" centred in 20, the days' names, six weeks
MONTHV: STR     R2
        LOAD    RD, CMON
        LDN     R2
        STR     RD
        SEP     R4
        DW      SETUP
        SEP     R4
        DW      CLEAR
        LOAD    RD, CMON        ; TBUF = the month's name, a space, the year
        LDN     RD
        SEP     R4
        DW      MNAME           ; RF -> the name
        LOAD    RD, TBUF
MV1:    LDA     RF
        LBZ     MV2
        STR     RD
        INC     RD
        LBR     MV1
MV2:    LDI     ' '
        STR     RD
        INC     RD
        SEP     R4
        DW      YTEXT           ; the year at RD, 0-ended
        LDI     20
        PLO     RB
        LDI     0
        PHI     RB
        SEP     R4
        DW      CENTRE
        SEP     R4
        DW      PLINE
        SEP     R4
        DW      CLEAR
        LDI     0
        SEP     R4
        DW      WNAMES
        SEP     R4
        DW      PLINE
        LDI     0               ; the weeks
        PLO     R9
MV3:    SEP     R4
        DW      CLEAR
        LOAD    RD, CMON
        LDN     RD
        PHI     R9              ; R9.1 = the month, R9.0 = the week
        LDI     0
        SEP     R4
        DW      WEEK
        SEP     R4
        DW      PLINE
        INC     R9
        GLO     R9
        XRI     6
        LBNZ    MV3
        SEP     R5

; ---- a whole year: the year centred over 60, then four rows of three months, a blank line between rows
YEARV:  SEP     R4
        DW      SETUP
        SEP     R4
        DW      CLEAR
        LOAD    RD, TBUF
        SEP     R4
        DW      YTEXT
        LDI     60
        PLO     RB
        LDI     0
        PHI     RB
        SEP     R4
        DW      CENTRE
        SEP     R4
        DW      PLINE
        LOAD    RD, CMON        ; CMON = the row's first month
        LDI     0
        STR     RD
YV1:    SEP     R4              ; the names, each centred in 20 at 0 / 22 / 44
        DW      CLEAR
        LDI     0
        PHI     RB              ; RB.1 = the column
YV2:    LOAD    RD, CMON
        LDN     RD
        STR     R2
        GHI     RB              ; + column / 22
        LBZ     YV3
        LDN     R2
        ADI     1
        STR     R2
        GHI     RB
        XRI     22
        LBZ     YV3
        LDN     R2
        ADI     1
        STR     R2
YV3:    LDN     R2
        SEP     R4
        DW      MNAME
        LOAD    RD, TBUF
YV4:    LDA     RF
        STR     RD
        INC     RD
        LBNZ    YV4
        LDI     20
        PLO     RB
        SEP     R4
        DW      CENTRE
        GHI     RB
        ADI     22
        PHI     RB
        XRI     66
        LBNZ    YV2
        SEP     R4
        DW      PLINE
        SEP     R4
        DW      CLEAR
        LDI     0
        SEP     R4
        DW      WNAMES
        LDI     22
        SEP     R4
        DW      WNAMES
        LDI     44
        SEP     R4
        DW      WNAMES
        SEP     R4
        DW      PLINE
        LDI     0               ; the weeks: R9.0 the week, R9.1 the month
        PLO     R9
YV5:    SEP     R4
        DW      CLEAR
        LOAD    RD, CMON
        LDN     RD
        PHI     R9
        LDI     0
        SEP     R4
        DW      WEEK
        GHI     R9
        ADI     1
        PHI     R9
        LDI     22
        SEP     R4
        DW      WEEK
        GHI     R9
        ADI     1
        PHI     R9
        LDI     44
        SEP     R4
        DW      WEEK
        SEP     R4
        DW      PLINE
        INC     R9
        GLO     R9
        XRI     6
        LBNZ    YV5
        LOAD    RD, CMON        ; the next row
        LDN     RD
        ADI     3
        STR     RD
        XRI     12
        LBZ     YV9
        SEP     R4
        DW      K_PCRLF
        LBR     YV1
YV9:    SEP     R5

; ---- SETUP: YEAR -> MSTART (each month's first weekday, 0 = Sunday), MCELLS (its days shown), HLM (the month
;      that holds today, $FF: none - and never when the output is not the screen)
SETUP:  LOAD    RD, HLM
        LDI     0FFH
        STR     RD
        LOAD    RD, K_RDIR
        LDN     RD
        LBNZ    SU1
        LOAD    RD, TYEAR       ; this year?
        LOAD    RF, YEAR
        LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    SU1
        LDA     RD
        STR     R2
        LDN     RF
        XOR
        LBNZ    SU1
        LDN     RD              ; TMON (LOAD sets D: kept at M(R2))
        STR     R2
        LOAD    RD, HLM
        LDN     R2
        STR     RD
SU1:    SEP     R4              ; RD = YEAR
        DW      GETY
        SEP     R4              ; LEAP
        DW      ISLEAP
        STR     R2
        LOAD    RD, LEAP
        LDN     R2
        STR     RD
        SEP     R4
        DW      GETY
        SEP     R4              ; RA.0 = the weekday of January 1
        DW      JAN1
        PLO     RA
        LDI     0
        PLO     RB              ; RB.0 = the month
SU2:    GLO     RB              ; MSTART[m] = RA.0
        ADI     LOW(MSTART)
        PLO     RD
        LDI     HIGH(MSTART)
        ADCI    0
        PHI     RD
        GLO     RA
        STR     RD
        GLO     RB              ; the days: DIM[m], + 1 for a leap February, 19 for September 1752
        ADI     LOW(DIM)
        PLO     RD
        LDI     HIGH(DIM)
        ADCI    0
        PHI     RD
        LDN     RD
        PLO     RC
        GLO     RB
        XRI     1
        LBNZ    SU3
        LOAD    RD, LEAP
        LDN     RD
        LBZ     SU3
        INC     RC
SU3:    GLO     RB
        XRI     8
        LBNZ    SU4
        SEP     R4
        DW      GETY
        GHI     RD
        XRI     HIGH(1752)
        LBNZ    SU4
        GLO     RD
        XRI     LOW(1752)
        LBNZ    SU4
        LDI     19
        PLO     RC
SU4:    GLO     RB              ; MCELLS[m] = it
        ADI     LOW(MCELLS)
        PLO     RD
        LDI     HIGH(MCELLS)
        ADCI    0
        PHI     RD
        GLO     RC
        STR     RD
        GLO     RA              ; the next month starts (start + days) mod 7 on
        STR     R2
        GLO     RC
        ADD
SU5:    SMI     7
        LBDF    SU5
        ADI     7
        PLO     RA
        INC     RB
        GLO     RB
        XRI     12
        LBNZ    SU2
        SEP     R5

; GETY: RD = YEAR
GETY:   LOAD    RF, YEAR
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R5

; ISLEAP: RD = a year -> D = 1 if it is a leap year (to 1752 every 4th; after, not the 100ths unless 400ths)
ISLEAP: GLO     RD
        ANI     03H
        LBNZ    IL0
        GHI     RD              ; to 1752: yes
        SMI     HIGH(1753)
        LBNF    IL1
        LBNZ    IL2
        GLO     RD
        SMI     LOW(1753)
        LBNF    IL1
IL2:    LOAD    RC, 100         ; not a 100th: yes
        SEP     R4
        DW      MODW
        GHI     RC
        LBNZ    IL1
        GLO     RC
        LBNZ    IL1
        LOAD    RC, 400         ; a 400th: yes
        SEP     R4
        DW      MODW
        GHI     RC
        LBNZ    IL0
        GLO     RC
        LBNZ    IL0
IL1:    LDI     1
        SEP     R5
IL0:    LDI     0
        SEP     R5

; JAN1: RD = a year -> D = the weekday of its January 1 (0 = Sunday). R = year - 1;
;       to 1752 (Julian): (6 + R + R/4) mod 7; after: (1 + 5 (R mod 4) + 4 (R mod 100) + 6 (R mod 400)) mod 7
JAN1:   DEC     RD              ; RD = R
        GHI     RD
        SMI     HIGH(1752)
        LBNF    JJ
        LBNZ    JG
        GLO     RD
        SMI     LOW(1752)
        LBDF    JG
JJ:     GHI     RD              ; Julian: R7 = R / 4
        SHR
        PHI     R7
        GLO     RD
        SHRC
        PLO     R7
        GHI     R7
        SHR
        PHI     R7
        GLO     R7
        SHRC
        PLO     R7
        GLO     RD              ; RD = R + R/4 + 6
        STR     R2
        GLO     R7
        ADD
        PLO     RD
        GHI     R7
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        GLO     RD
        ADI     6
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LBR     MOD7
JG:     GLO     RD              ; Gregorian: R7 = 1 + 5 (R mod 4)
        ANI     03H
        PLO     R7
        SHL
        SHL
        STR     R2
        GLO     R7
        ADD
        ADI     1
        PLO     R7
        LDI     0
        PHI     R7
        LOAD    RC, 400         ; R mod 400 -> RD (R mod 100 = it mod 100)
        SEP     R4
        DW      MODW
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        LDI     6               ; R7 += 6 x it
        PLO     RB
JG1:    GLO     RD
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     RD
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        DEC     RB
        GLO     RB
        LBNZ    JG1
        LOAD    RC, 100         ; R7 += 4 x (it mod 100)
        SEP     R4
        DW      MODW
        GLO     RC
        SHL
        SHL
        STR     R2              ; (< 400: its high bit from the carry)
        GLO     R7
        ADD
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        GLO     RC
        ANI     0C0H
        LBZ     JG2
        SHR
        SHR
        SHR
        SHR
        SHR
        SHR
        STR     R2
        GHI     R7
        ADD
        PHI     R7
JG2:    GHI     R7
        PHI     RD
        GLO     R7
        PLO     RD
; MOD7: D = RD mod 7 (RD < 64 K)
MOD7:   LOAD    RC, 1792
        SEP     R4
        DW      MODW
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        LOAD    RC, 112
        SEP     R4
        DW      MODW
        GLO     RC
M71:    SMI     7
        LBDF    M71
        ADI     7
        SEP     R5

; MODW: RC = RD mod RC (repeated subtraction; RD kept). Uses RF.
MODW:   GHI     RC
        PHI     RF
        GLO     RC
        PLO     RF              ; RF = the divisor
        GHI     RD
        PHI     RC
        GLO     RD
        PLO     RC
MW1:    GLO     RF
        STR     R2
        GLO     RC
        SM
        PLO     RE
        GHI     RF
        STR     R2
        GHI     RC
        SMB
        LBNF    MW9
        PHI     RC
        GLO     RE
        PLO     RC
        LBR     MW1
MW9:    SEP     R5

; ---- CHKYR: RD = a year: 1-9999? (DF = 1: not)
CHKYR:  GHI     RD
        LBNZ    CY1
        GLO     RD
        LBZ     CYBAD
CY1:    GLO     RD
        SMI     LOW(10000)
        GHI     RD
        SMBI    HIGH(10000)
        LBDF    CYBAD
        LDI     0
        SHR
        SEP     R5
CYBAD:  LDI     1
        SHR
        SEP     R5

; PUTW: RD -> the 2 bytes at RC (high first)
PUTW:   GHI     RD
        STR     RC
        INC     RC
        GLO     RD
        STR     RC
        SEP     R5

; NUMARG: RF -> 1-4 digits, then a space or the end -> RD. DF = 1: not that.
NUMARG: LOAD    RD, 0
        LDI     0
        PLO     RB              ; RB.0 = the digits
NA1:    LDN     RF
        SMI     '0'
        LBNF    NA2
        SMI     10
        LBDF    NA2
        GLO     RB
        XRI     4
        LBZ     NABAD
        INC     RB
        GLO     RD              ; RD = 10 RD + the digit
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
        LBR     NA1
NA2:    GLO     RB
        LBZ     NABAD
        LDN     RF
        LBZ     NAOK
        XRI     ' '
        LBNZ    NABAD
NAOK:   LDI     0
        SHR
        SEP     R5
NABAD:  LDI     1
        SHR
        SEP     R5

; ---- MNAME: D = a month (0-11) -> RF = its name (0-ended)
MNAME:  PLO     RC
        LOAD    RF, MNAMES
MN1:    GLO     RC
        LBZ     MN9
MN2:    LDA     RF
        LBNZ    MN2
        DEC     RC
        LBR     MN1
MN9:    SEP     R5

; YTEXT: YEAR in decimal at RD (no leading zeros), then a 0
YTEXT:  LOAD    RF, YEAR
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC              ; RC = the year
        LDI     0
        PHI     RB              ; RB.1 = 1 once a digit is written
        LOAD    RF, 1000
        SEP     R4
        DW      YDIG
        LOAD    RF, 100
        SEP     R4
        DW      YDIG
        LOAD    RF, 10
        SEP     R4
        DW      YDIG
        GLO     RC
        ADI     '0'
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        SEP     R5
; YDIG: the digit of RC for the power RF (RC -= it); written at RD unless it is a leading 0
YDIG:   LDI     0
        PLO     RB
YD1:    GLO     RF
        STR     R2
        GLO     RC
        SM
        PLO     RE
        GHI     RF
        STR     R2
        GHI     RC
        SMB
        LBNF    YD2
        PHI     RC
        GLO     RE
        PLO     RC
        INC     RB
        LBR     YD1
YD2:    GLO     RB
        LBNZ    YD3
        GHI     RB
        LBZ     YD9
YD3:    GLO     RB
        ADI     '0'
        STR     RD
        INC     RD
        LDI     1
        PHI     RB
YD9:    SEP     R5

; ---- CENTRE: TBUF (0-ended) centred in RB.0 columns from column RB.1 of LINE: (width - length) / 2 before it
CENTRE: LOAD    RF, TBUF
        LDI     0
        PLO     RC
CE1:    LDA     RF
        LBZ     CE2
        INC     RC
        LBR     CE1
CE2:    GLO     RC              ; D = (width - length) / 2 + the column
        STR     R2
        GLO     RB
        SM
        SHR
        STR     R2
        GHI     RB
        ADD
        ADI     LOW(LINE)
        PLO     RD
        LDI     HIGH(LINE)
        ADCI    0
        PHI     RD
        LOAD    RF, TBUF
CE3:    LDA     RF
        LBZ     CE9
        STR     RD
        INC     RD
        LBR     CE3
CE9:    SEP     R5

; WNAMES: "Su Mo Tu We Th Fr Sa" at column D of LINE
WNAMES: ADI     LOW(LINE)
        PLO     RD
        LDI     HIGH(LINE)
        ADCI    0
        PHI     RD
        LOAD    RF, WDN
WN1:    LDA     RF
        LBZ     WN9
        STR     RD
        INC     RD
        LBR     WN1
WN9:    SEP     R5

; WEEK: week R9.0 (0-5) of month R9.1, at column D of LINE: 7 cells of 3 ("%2d "); today's: HLCOL
WEEK:   PHI     RA              ; RA.1 = the column
        GHI     R9              ; RA.0 = the cell's index in the month: 7 x week - MSTART[m] (from -6)
        ADI     LOW(MSTART)
        PLO     RD
        LDI     HIGH(MSTART)
        ADCI    0
        PHI     RD
        LDN     RD
        STR     R2
        GLO     R9
        SHL
        SHL
        SHL
        SM                      ; 8 week - start
        STR     R2
        GLO     R9
        SD                      ; - week
        PLO     RA
        GHI     R9              ; RB.1 = MCELLS[m]
        ADI     LOW(MCELLS)
        PLO     RD
        LDI     HIGH(MCELLS)
        ADCI    0
        PHI     RD
        LDN     RD
        PHI     RB
        LDI     7
        PLO     RB              ; RB.0 = the cells left
WK1:    GLO     RA              ; an index 0 .. MCELLS - 1? (a negative one is >= $80)
        ANI     80H
        LBNZ    WK8
        GHI     RB
        STR     R2
        GLO     RA
        SM
        LBDF    WK8
        GLO     RA              ; the day: index + 1, past the 2nd of September 1752 + 12
        ADI     1
        PLO     RC
        GHI     R9
        XRI     8
        LBNZ    WK2
        GHI     RB
        XRI     19
        LBNZ    WK2
        GLO     RC
        SMI     3
        LBNF    WK2
        GLO     RC
        ADI     11
        PLO     RC
WK2:    GHI     RA              ; RD -> its cell
        ADI     LOW(LINE)
        PLO     RD
        LDI     HIGH(LINE)
        ADCI    0
        PHI     RD
        LOAD    RF, HLM         ; today? HLCOL = the cell's column
        LDN     RF
        STR     R2
        GHI     R9
        XOR
        LBNZ    WK3
        LOAD    RF, TDAY
        LDN     RF
        STR     R2
        GLO     RC
        XOR
        LBNZ    WK3
        LOAD    RF, HLCOL
        GHI     RA
        STR     RF
WK3:    GLO     RC              ; "%2d"
        PLO     RE
        LDI     0
        PLO     RF
WK4:    GLO     RE
        SMI     10
        LBNF    WK5
        PLO     RE
        INC     RF
        LBR     WK4
WK5:    GLO     RF
        LBZ     WK6
        ADI     '0'
        STR     RD
WK6:    INC     RD
        GLO     RE
        ADI     '0'
        STR     RD
WK8:    GLO     RA              ; (RA.0 alone: INC RA would carry into the column)
        ADI     1
        PLO     RA
        GHI     RA
        ADI     3
        PHI     RA
        DEC     RB
        GLO     RB
        LBNZ    WK1
        SEP     R5

; ---- CLEAR: LINE = 80 spaces, HLCOL = $F0 (no highlight)
CLEAR:  LOAD    RD, LINE
        LDI     80
        PLO     RC
CL1:    LDI     ' '
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    CL1
        LOAD    RD, HLCOL
        LDI     0F0H            ; (past the line: HLCOL + 1 is never a column either)
        STR     RD
        SEP     R5

; PLINE: LINE without its trailing spaces, then a new line; the 2 columns from HLCOL in reverse video
PLINE:  LOAD    RD, LINE+80     ; RC.0 = the length
        LDI     80
        PLO     RC
PL1:    DEC     RD
        LDN     RD
        XRI     ' '
        LBNZ    PL2
        DEC     RC
        GLO     RC
        LBNZ    PL1
PL2:    LOAD    RD, LINE
        LDI     0
        PLO     RB              ; RB.0 = the column
PL3:    GLO     RC
        LBZ     PL9
        LOAD    RF, HLCOL
        LDN     RF
        STR     R2
        GLO     RB
        XOR
        LBNZ    PL4
        SEP     R4
        DW      K_PIN
        DB      1BH,'[7m',0
PL4:    LDA     RD
        SEP     R4
        DW      F_TYPE
        LOAD    RF, HLCOL
        LDN     RF
        ADI     1
        STR     R2
        GLO     RB
        XOR
        LBNZ    PL5
        SEP     R4
        DW      K_PIN
        DB      1BH,'[0m',0
PL5:    INC     RB
        DEC     RC
        LBR     PL3
PL9:    SEP     R4
        DW      K_PCRLF
        SEP     R5

MNAMES: DB      'January',0,'February',0,'March',0,'April',0,'May',0,'June',0,'July',0,'August',0
        DB      'September',0,'October',0,'November',0,'December',0
WDN:    DB      'Su Mo Tu We Th Fr Sa',0
        INCL    "rtc.inc"
CLOCK:  DB      0               ; 1: the clock answered
TYEAR:  DS      2               ; TYEAR TMON TDAY: today, in this order
TMON:   DS      1
TDAY:   DS      1
ARG1:   DS      2
YEAR:   DS      2
CMON:   DS      1
LEAP:   DS      1
HLM:    DS      1
HLCOL:  DS      1
MSTART: DS      12
MCELLS: DS      12
TBUF:   DS      24
LINE:   DS      80
PEND:
        END
