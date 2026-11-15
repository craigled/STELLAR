; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; eartest.asm - EARTEST.PRG: is the sound detector on an EF line working, and how well does it hear?
;   EARTEST [-e 1-4] [-i] [-f Hz] [-c MHz]
;   The meter: 1,000 samples a second; each 0.1 s a bar shows how much of it heard sound, the peak, how many
;   sounds (a sound ends after 10 ms of quiet), and the last one's length in ms.
;   T  the tone test: a tone on Q (the Elf2K's speaker) 5 times, 0.3 s each: how soon it is heard, how much of
;      it, and how long the detector stays on after it stops (that matters for Morse).
;   S  a sweep: one tone at each of 10 pitches, 300-2000 Hz - which pitch it hears best (for MORSE -f).
;   I  the line the other way up   C  clear the counts   Esc  quit
;   -e N the EF line (3)  -i the other way up  -f Hz the test tone 200-2000 (700)  -c MHz the clock (3.58)
; Sound = the EF line LOW (B3), as the SparkFun detector through an NPN, or a module that pulls it low.
; Only the kernel's fixed calls: it works with any LTOS 0.5.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
ESC     EQU     1BH
MOVH    EQU     86              ; the meter loop's cycles a sample, outside its delay (+8 when MFR carries)
TOVH    EQU     36              ; the tone loop's cycles a half-period, outside its delay
HOLDN   EQU     10              ; samples (ms) of quiet that end a sound
FMTC    EQU     1512            ; the cycles a meter line takes to make, every time (the samples missed are added on)
FMTD    EQU     2301            ; and the more when it turns a length into digits

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
; ---- the tone loop, one sample a half-period. R7 = half-periods + $FF, RD = the delay (K + $FF); RC counts the
;      samples hearing sound, RA = R7 at the first (R8.0 = 1 once there is one), RB = R7 at the last.
;      TLS is SEQ (a tone) or REQ (quiet), TLK B1-B4 / BN1-BN4. 36 + 6 K cycles a half-period, every path.
TL:     BQ      TL1
TLS:    SEQ
        BR      TL2
TL1:    REQ
        SEX     R2
TL2:
TLK:    B3      TLA             ; (patched)
        SEX     R2              ; quiet: as long as the sound path
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        BR      TLD
TLA:    INC     RC
        GLO     R7
        PLO     RB
        GHI     R7
        PHI     RB
        GLO     R8
        BNZ     TLD
        INC     R8              ; the first (once)
        GLO     R7
        PLO     RA
        GHI     R7
        PHI     RA
TLD:    GLO     RD
        PLO     R9
        GHI     RD
        PHI     R9
TLD1:   DEC     R9
        GHI     R9
        BNZ     TLD1
        DEC     R7
        GHI     R7
        BNZ     TL
        REQ
        SEP     R5
TLEND:

; ---- the meter loop, one sample a millisecond: 74 + 6 K cycles every path. The UART's status selected ($15):
;      a key ends it; while there is room, the next character of the line at RA goes out (0: none).
;      RC.0 counts the window down (100), R7.0 the samples hearing sound in it, R8 the sound's length, RB.1 = 1
;      in a sound, RB.0 the quiet in a row in it. RD = the delay (K + $FF); RF.1 = its fraction (/256 of 8 cycles),
;      RF.0 sums it.
ML:     INP     DATPORT
        SHR
        LBDF    MKEY
        ANI     10H             ; room to send
        BZ      MLN1
        LDN     RA
        BZ      MLN2
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDA     RA
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        BR      MLS
MLN1:   SEX     R2
        SEX     R2
MLN2:   SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
MLS:    DEC     RC
MLK:    B3      MLA             ; (patched)
        GHI     RB              ; quiet: in a sound?
        BZ      MLQ0
        INC     R8
        INC     RB
        GLO     RB
        XRI     HOLDN
        LBZ     MEND
        BR      MLD
MLQ0:   NOP
        SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        BR      MLD
MLA:    INC     R7
        GHI     RB
        LBZ     MSTART
        INC     R8
        LDI     0
        PLO     RB
        SEX     R2
        SEX     R2
MLD:    GHI     RF
        STR     R2
        GLO     RF
        ADD
        PLO     RF
        GLO     RD
        PLO     R9
        GHI     RD
        PHI     R9
        BNF     MLD1
        INC     R9
MLD1:   DEC     R9
        GHI     R9
        BNZ     MLD1
        GLO     RC
        BNZ     ML
        LBR     MWIN
MLEND:
MSTART: LDI     1               ; a sound starts
        PHI     RB
        LDI     0
        PLO     RB
        LOAD    R8, 1
        LOAD    R9, CFR
        LDI     0
        STR     R9
        LOAD    R9, SNUM + 4        ; the count, in its digits
SI1:    LDN     R9
        XRI     ' '
        LBZ     SI3
        LDN     R9
        XRI     '9'
        LBNZ    SI2
        LDI     '0'
        STR     R9
        DEC     R9
        GLO     R9
        XRI     LOW(SNUM - 1)
        LBNZ    SI1
        LBR     MLD
SI2:    LDN     R9
        ADI     1
        STR     R9
        LBR     MLD
SI3:    LDI     '1'
        STR     R9
        LBR     MLD
MEND:   GLO     R8              ; a sound ends: its length = R8 - the quiet
        SMI     HOLDN
        PLO     R8
        GHI     R8
        SMBI    0
        PHI     R8
        LOAD    R9, LASTL
        GHI     R8
        STR     R9
        INC     R9
        GLO     R8
        STR     R9
        INC     R9              ; LFLAG: a new length to show
        LDI     1
        STR     R9
        LDI     0
        PHI     RB
        PLO     RB
        PHI     R8
        PLO     R8
        LBR     MLD

; =================================================================================================== the options
START:  SEX     R2
        REQ
        LOAD    RD, C100        ; the defaults: 3.58 MHz, 700 Hz, EF3, the right way up
        LDI     HIGH(358)
        STR     RD
        INC     RD
        LDI     LOW(358)
        STR     RD
        INC     RD              ; FREQ
        LDI     HIGH(700)
        STR     RD
        INC     RD
        LDI     LOW(700)
        STR     RD
        INC     RD              ; EFN
        LDI     3
        STR     RD
        INC     RD              ; INV
        LDI     0
        STR     RD
OPT:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     OPEND
        XRI     '-'
        LBNZ    USAGE
        INC     RF
        LDA     RF
        ANI     0DFH
        PLO     RB
        SEP     R4
        DW      K_SKIPSP
        GLO     RB
        XRI     'E'
        LBZ     OEF
        GLO     RB
        XRI     'I'
        LBZ     OINV
        GLO     RB
        XRI     'F'
        LBZ     OFREQ
        GLO     RB
        XRI     'C'
        LBZ     OCLK
        LBR     USAGE
OINV:   LOAD    RD, INV
        LDI     1
        STR     RD
        LBR     OPT
OEF:    LDA     RF              ; -e 1-4
        SMI     '1'
        LBNF    USAGE
        SMI     4
        LBDF    USAGE
        ADI     5
        PLO     RB
        LOAD    RD, EFN
        GLO     RB
        STR     RD
        LBR     OEND
OFREQ:  SEP     R4              ; -f 200-2000
        DW      NUMARG
        LBDF    USAGE
        GLO     RD
        SMI     LOW(200)
        GHI     RD
        SMBI    HIGH(200)
        LBNF    USAGE
        GLO     RD
        SMI     LOW(2001)
        GHI     RD
        SMBI    HIGH(2001)
        LBDF    USAGE
        GHI     RD
        PHI     RB
        GLO     RD
        PLO     RB
        LOAD    RD, FREQ
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LBR     OEND
OCLK:   SEP     R4              ; -c MHz: 1.00-9.99, two decimals kept -> C100
        DW      NUMARG
        LBDF    USAGE
        GHI     RD
        LBNZ    USAGE
        GLO     RD
        LBZ     USAGE
        SMI     10
        LBDF    USAGE
        LDI     0
        PHI     RA
        PLO     RA
OC1:    GLO     RD
        LBZ     OC2
        DEC     RD
        GLO     RA
        ADI     100
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     OC1
OC2:    LDN     RF
        XRI     '.'
        LBNZ    OC9
        INC     RF
        LDI     10
        PLO     RB
OC3:    LDN     RF
        SMI     '0'
        LBNF    OC9
        SMI     10
        LBDF    OC9
        LDA     RF
        SMI     '0'
        PLO     R9
OC4:    GLO     R9
        LBZ     OC5
        DEC     R9
        GLO     RB
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     OC4
OC5:    GLO     RB
        XRI     10
        LBNZ    OC6
        LDI     1
        PLO     RB
        LBR     OC3
OC6:    LDN     RF
        SMI     '0'
        LBNF    OC9
        SMI     10
        LBDF    OC9
        INC     RF
        LBR     OC6
OC9:    LOAD    RD, C100
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
OEND:   LDN     RF
        LBZ     OPT
        XRI     20H
        LBNZ    USAGE
        LBR     OPT

USAGE:  SEP     R4
        DW      K_PIN
        DB      'EARTEST [-e EF 1-4 (3)] [-i] [-f Hz 200-2000 (700)] [-c MHz clock (3.58)]',0DH,0AH
        DB      '  tests a sound detector on an EF line: a meter, a tone test and a sweep',0DH,0AH
        DB      '  (sound = the line pulled low; -i the other way up)',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        REQ
        SEP     R5

; =================================================================================================== the start
OPEND:  SEP     R4
        DW      SETUP
        SEP     R4
        DW      PATCH
        SEP     R4              ; the counts from 0
        DW      CLEAR
        SEP     R4
        DW      K_PIN
        DB      0DH,0AH,'EARTEST - listening on EF',0
        LOAD    RF, EFN
        LDN     RF
        ADI     '0'
        SEP     R4
        DW      K_OUT
        LOAD    RF, INV
        LDN     RF
        LBZ     ST1
        SEP     R4
        DW      K_PIN
        DB      ' (-i: high = sound)',0
ST1:    SEP     R4
        DW      K_PIN
        DB      '. Make a sound: the bar is how much of each 0.1 s it heard.',0DH,0AH
        DB      'T tone test   S sweep the pitches   I invert   C clear   Esc quits',0DH,0AH,0DH,0AH,0
; ---- the meter: start a window
METER:  LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RF, MKB
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LOAD    RA, ZERO        ; nothing to send
        LOAD    RF, MFR
        LDN     RF
        PHI     RF
        LDI     0
        PLO     RF
        PHI     RB
        PLO     RB
        PHI     R8
        PLO     R8
        PHI     R7
        PLO     R7
        LOAD    RC, 100
        LBR     ML

; MWIN: a window (0.1 s) is over: the line, if the last one has gone out. It takes FMTC cycles every time, and
;   FMTD more when it turns a new sound's length into digits (the samples missed meanwhile are added on: LOADL).
MWIN:   LDN     RA
        LBNZ    MW9             ; still sending: this window is not shown
        GLO     R7              ; the percentage = the samples hearing sound
        PLO     RC
        LOAD    RF, PEAK
        LDN     RF
        STR     R2
        GLO     RC
        SM
        LBNF    MW0
        GLO     RC
        STR     RF
        LBR     MW1
MW0:    SEX     R2
        NOP
MW1:    SEP     R4
        DW      SAVEL
        LOAD    RF, OBUF
        LDI     0DH
        STR     RF
        INC     RF
        LDI     '['
        STR     RF
        INC     RF
        GLO     RC              ; 20 steps of 5%: '#' or '-', the same time each
        PLO     R9
        LDI     20
        PHI     R9
MW2:    GLO     R9
        SMI     5
        LBNF    MW3
        PLO     R9
        LDI     '#'
        LBR     MW3A
MW3:    SEX     R2
        LDI     '-'
        NOP
MW3A:   STR     RF
        INC     RF
        GHI     R9
        SMI     1
        PHI     R9
        LBNZ    MW2
        LDI     ']'
        STR     RF
        INC     RF
        GLO     RC
        SEP     R4
        DW      PUT3
        SEP     R4
        DW      PUTS
        DB      '%  peak ',0
        LOAD    RD, PEAK
        LDN     RD
        SEP     R4
        DW      PUT3
        SEP     R4
        DW      PUTS
        DB      '%  sounds ',0
        LOAD    RD, SNUM
        SEP     R4
        DW      COPY5
        SEP     R4
        DW      PUTS
        DB      '  last ',0
        LOAD    RD, LFLAG       ; a new length: into digits (DCV = 1: FMTD more)
        LDN     RD
        LBZ     MW5
        LDI     0
        STR     RD
        INC     RD              ; DCV
        LDI     1
        STR     RD
        GHI     RF
        PHI     R8              ; (R8 is kept by SAVEL)
        GLO     RF
        PLO     R8
        LOAD    RD, LASTL
        SEP     R4
        DW      GETW
        SEP     R4
        DW      DEC5            ; -> NBUF
        LOAD    RD, NBUF        ; NBUF -> LNUM
        LOAD    RF, LNUM
        SEP     R4
        DW      COPY5
        GHI     R8
        PHI     RF
        GLO     R8
        PLO     RF
MW5:    LOAD    RD, LNUM
        SEP     R4
        DW      COPY5
        SEP     R4
        DW      PUTS
        DB      ' ms ',0
        LDI     0
        STR     RF
        SEP     R4
        DW      LOADL           ; the loop's registers back, the missed samples added on
        LOAD    RA, OBUF
MW9:    LDI     0
        PHI     R7
        PLO     R7
        LOAD    RC, 100
        LOAD    RF, MKB
        LDA     RF
        PHI     RD
        LDA     RF
        PLO     RD
        LDN     RF              ; MFR
        PHI     RF
        LBR     ML

; PUT3: D (0-100) as 3 characters at RF, from PTAB (the same time for any D). Uses R9, RD.
PUT3:   PLO     R9
        LOAD    RD, PTAB
        LDI     3
        PHI     R9
P3A:    GLO     R9              ; RD += D, 3 times
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        GHI     R9
        SMI     1
        PHI     R9
        LBNZ    P3A
        LDA     RD
        STR     RF
        INC     RF
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        SEP     R5
; COPY5: 5 bytes from RD to RF
COPY5:  LDA     RD
        STR     RF
        INC     RF
        LDA     RD
        STR     RF
        INC     RF
        LDA     RD
        STR     RF
        INC     RF
        LDA     RD
        STR     RF
        INC     RF
        LDA     RD
        STR     RF
        INC     RF
        SEP     R5

; SAVEL / LOADL: the meter's sound state (R8, RB) kept while a line is made; LOADL adds the samples it missed
SAVEL:  LOAD    R9, SVR8
        GHI     R8
        STR     R9
        INC     R9
        GLO     R8
        STR     R9
        INC     R9
        GHI     RB
        STR     R9
        INC     R9
        GLO     RB
        STR     R9
        SEP     R5
LOADL:  LOAD    RF, SVR8
        LDA     RF
        PHI     R8
        LDA     RF
        PLO     R8
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        GHI     RB
        LBZ     LL9
        LOAD    RF, CFR         ; in a sound: it went on while the line was made - R8:CFR += COMP (/256 samples)
        LDN     RF
        STR     R2
        LOAD    RC, COMP + 1
        LDN     RC
        ADD
        STR     RF
        DEC     RC
        LDN     RC
        STR     R2
        GLO     R8
        ADC
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        LOAD    RC, DCV         ; and the digits made: COMPD more
        LDN     RC
        LBZ     LL9
        LDN     RF
        STR     R2
        LOAD    RC, COMPD + 1
        LDN     RC
        ADD
        STR     RF
        DEC     RC
        LDN     RC
        STR     R2
        GLO     R8
        ADC
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
LL9:    LOAD    RC, DCV
        LDI     0
        STR     RC
        SEP     R5

; ---- a key
MKEY:   LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RB
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RB
        XRI     ESC
        LBZ     QUIT
        GLO     RB
        XRI     03H
        LBZ     QUIT
        GLO     RB
        ANI     0DFH
        PLO     RB
        XRI     'C'
        LBZ     KCLR
        GLO     RB
        XRI     'I'
        LBZ     KINV
        GLO     RB
        XRI     'T'
        LBZ     KTONE
        GLO     RB
        XRI     'S'
        LBZ     KSWEEP
        LBR     METER
KCLR:   SEP     R4
        DW      CLEAR
        LBR     METER
KINV:   LOAD    RF, INV
        LDN     RF
        XRI     1
        STR     RF
        SEP     R4
        DW      PATCH
        LBR     METER
QUIT:   REQ
        SEP     R4
        DW      K_PCRLF
        SEP     R5

; CLEAR: the count, the peak and the last length back to 0
CLEAR:  LOAD    RF, PEAK
        LDI     0
        STR     RF
        INC     RF              ; LASTL, LFLAG, DCV
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        LOAD    RF, SNUM
        SEP     R4
        DW      ZNUM
        LOAD    RF, LNUM
ZNUM:   LDI     ' '             ; RF -> '    0'
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        LDI     '0'
        STR     RF
        SEP     R5

; PATCH: MLK and TLK = B1-B4 for EFN, BN1-BN4 with -i
PATCH:  LOAD    RF, EFN
        LDN     RF
        ADI     33H
        PLO     RB
        LOAD    RF, INV
        LDN     RF
        LBZ     PA1
        GLO     RB
        ADI     8
        PLO     RB
PA1:    LOAD    RF, MLK
        GLO     RB
        STR     RF
        LOAD    RF, TLK
        GLO     RB
        STR     RF
        SEP     R5

; ---- T: the tone test, 5 times at FREQ
KTONE:  SEP     R4
        DW      K_PIN
        DB      0DH,0AH,0DH,0AH,'Tone test: ',0
        LOAD    RF, FREQ
        SEP     R4
        DW      GETWF
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' Hz on Q, 0.3 s, 5 times (put the microphone near the speaker)',0DH,0AH,0
        LOAD    RF, FREQ
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LOAD    RF, CF
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        LOAD    RF, NTRY
        LDI     '1'
        STR     RF
KT1:    SEP     R4
        DW      BURST
        LBDF    KTX             ; Esc
        SEP     R4
        DW      K_PIN
        DB      '  ',0
        LOAD    RF, NTRY
        LDN     RF
        SEP     R4
        DW      K_OUT
        SEP     R4
        DW      K_PIN
        DB      ': ',0
        LOAD    RF, TON
        SEP     R4
        DW      GETWF
        GHI     RD
        LBNZ    KT2
        GLO     RD
        LBNZ    KT2
        SEP     R4
        DW      K_PIN
        DB      'not heard',0
        LBR     KT5
KT2:    SEP     R4
        DW      K_PIN
        DB      'heard after ',0
        LOAD    RF, TATK
        SEP     R4
        DW      PMS
        SEP     R4
        DW      K_PIN
        DB      ' ms, on ',0
        SEP     R4
        DW      PPCT
        SEP     R4
        DW      K_PIN
        DB      '% of the tone, ',0
        LOAD    RF, TREL
        SEP     R4
        DW      GETWF
        GHI     RD
        LBNZ    KT3
        GLO     RD
        LBNZ    KT3
        SEP     R4
        DW      K_PIN
        DB      'off as it stopped',0
        LBR     KT5
KT3:    LOAD    RF, TREL
        SEP     R4
        DW      GETWF
        GLO     RD              ; still on at the end: 300 ms or more
        XRI     0FFH
        LBNZ    KT4
        GHI     RD
        XRI     0FFH
        LBNZ    KT4
        SEP     R4
        DW      K_PIN
        DB      'STILL ON 0.3 s after it',0
        LBR     KT5
KT4:    SEP     R4
        DW      K_PIN
        DB      'off ',0
        LOAD    RF, TREL
        SEP     R4
        DW      PMS
        SEP     R4
        DW      K_PIN
        DB      ' ms after it',0
KT5:    SEP     R4
        DW      PNOISE
        SEP     R4
        DW      K_PCRLF
        LOAD    RF, NTRY
        LDN     RF
        ADI     1
        STR     RF
        XRI     '6'
        LBNZ    KT1
KTX:    SEP     R4
        DW      K_PCRLF
        LBR     METER

; ---- S: the sweep, one tone at each pitch in FTAB
KSWEEP: SEP     R4
        DW      K_PIN
        DB      0DH,0AH,0DH,0AH,'Sweep: a 0.3 s tone at each pitch - how much of it was heard',0DH,0AH,0
        LOAD    RF, NTRY        ; NTRY = the index into FTAB
        LDI     0
        STR     RF
KS1:    LOAD    RF, NTRY
        LDN     RF
        SHL
        ADI     LOW(FTAB)
        PLO     RD
        LDI     HIGH(FTAB)
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    KS2
        GLO     RC
        LBZ     KTX             ; the end of the table
KS2:    LOAD    RF, CF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R4
        DW      BURST
        LBDF    KTX
        LOAD    RF, CF          ; "  700 Hz [####----] 52%  after 12 ms"
        SEP     R4
        DW      GETWF
        LDI     6
        SEP     R4
        DW      PDECW
        SEP     R4
        DW      K_PIN
        DB      ' Hz [',0
        SEP     R4
        DW      PCTV            ; RD = the percentage (K_OUT keeps RD)
        LDI     20
        PHI     RD
KS3:    GLO     RD
        SMI     5
        LBNF    KS4
        PLO     RD
        LDI     '#'
        SEP     R4
        DW      K_OUT
        GHI     RD
        SMI     1
        PHI     RD
        LBR     KS3
KS4:    GHI     RD
        LBZ     KS5
        LDI     '-'
        SEP     R4
        DW      K_OUT
        GHI     RD
        SMI     1
        PHI     RD
        LBR     KS4
KS5:    SEP     R4
        DW      K_PIN
        DB      '] ',0
        SEP     R4
        DW      PCTV
        LDI     3
        SEP     R4
        DW      PDECW
        LDI     '%'
        SEP     R4
        DW      K_OUT
        LOAD    RF, TON
        SEP     R4
        DW      GETWF
        GHI     RD
        LBNZ    KS6
        GLO     RD
        LBZ     KS7
KS6:    SEP     R4
        DW      K_PIN
        DB      '  after ',0
        LOAD    RF, TATK
        SEP     R4
        DW      PMS
        SEP     R4
        DW      K_PIN
        DB      ' ms',0
KS7:    SEP     R4
        DW      PNOISE
        SEP     R4
        DW      K_PCRLF
        LOAD    RF, NTRY
        LDN     RF
        ADI     1
        STR     RF
        LBR     KS1

FTAB:   DW      300, 400, 500, 600, 700, 800, 1000, 1200, 1500, 2000, 0

; PNOISE: " (heard N before)" if the quiet before the tone was not quiet
PNOISE: LOAD    RF, TNOI
        SEP     R4
        DW      GETWF
        GHI     RD
        LBNZ    PN1
        GLO     RD
        LBZ     PN9
PN1:    SEP     R4
        DW      K_PIN
        DB      '  (and sound in the quiet before it)',0
PN9:    SEP     R5

; PMS: the half-periods at RF in ms (x 500 / CF)
PMS:    SEP     R4
        DW      GETWF
        GHI     RD
        PHI     RA
        GLO     RD
        PLO     RA
        LOAD    RB, 500
        SEP     R4
        DW      MUL
        LOAD    RF, CF
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R4
        DW      K_PDEC
        SEP     R5
; PCTV: RD = TON x 100 / TN; PPCT prints it
PCTV:   LOAD    RF, TON
        SEP     R4
        DW      GETWF
        GHI     RD
        PHI     RA
        GLO     RD
        PLO     RA
        LOAD    RB, 100
        SEP     R4
        DW      MUL
        LOAD    RF, TN
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R5
PPCT:   SEP     R4
        DW      PCTV
        SEP     R4
        DW      K_PDEC
        SEP     R5

; ---- BURST: at CF Hz - 0.3 s quiet, 0.3 s tone, 0.3 s quiet, sampling each half-period. TNOI = sound heard in
;   the first quiet, TON = in the tone, TATK = half-periods until it was first heard, TREL = from the tone's end
;   to the last sound heard ($FFFF: still on at the end). DF = 1: Esc (or Ctrl-C) was pressed before it.
BURST:  LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBNF    BU1
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RB
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RB
        XRI     ESC
        LBZ     BUX
        GLO     RB
        XRI     03H
        LBZ     BUX
BU1:    LOAD    RF, CF          ; H = MCB / (2 CF); K = (H - TOVH) / 6, at least 1
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        GLO     RB
        SHL
        PLO     RB
        GHI     RB
        SHLC
        PHI     RB
        SEP     R4
        DW      SETDVS
        LOAD    RF, MCB
        LDA     RF
        PLO     RD
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        SEP     R4
        DW      DIV             ; RC = H
        GLO     RC
        SMI     TOVH + 6
        GHI     RC
        SMBI    0
        LBDF    BU2
        LOAD    RC, 1
        LBR     BU3
BU2:    GLO     RC
        SMI     TOVH
        PLO     RC
        GHI     RC
        SMBI    0
        PHI     RC
        LDI     0
        PLO     RD
        LOAD    RB, 6
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
BU3:    LOAD    RF, TKB
        GLO     RC
        ADI     0FFH
        PLO     RB
        GHI     RC
        ADCI    0
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        LOAD    RF, CF          ; TN = CF x 3 / 5 (0.3 s of half-periods)
        LDA     RF
        PHI     RA
        LDN     RF
        PLO     RA
        LOAD    RB, 3
        SEP     R4
        DW      MUL
        LOAD    RB, 5
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        LOAD    RF, TN
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LDI     7AH             ; quiet: REQ
        SEP     R4
        DW      PHASE
        LOAD    RF, TNOI
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LDI     7BH             ; the tone: SEQ
        SEP     R4
        DW      PHASE
        LOAD    RF, TON
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R4              ; TATK = TN + $FF - RA
        DW      FROMR
        DB      0
        LOAD    RF, TATK
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        LDI     7AH             ; after it: quiet
        SEP     R4
        DW      PHASE
        GLO     RC
        LBNZ    BU4
        GHI     RC
        LBNZ    BU4
        LOAD    RA, 0           ; nothing heard after it
        LBR     BU6
BU4:    GHI     RB              ; the last sound: RB
        PHI     RA
        GLO     RB
        PLO     RA
        SEP     R4
        DW      FROMR           ; RA = TN + $FF - RB + 1: half-periods to the end of the last sound
        DB      1
        LOAD    RF, TN          ; still on at the very end?
        LDA     RF
        STR     R2
        GHI     RA
        XOR
        LBNZ    BU6
        LDN     RF
        STR     R2
        GLO     RA
        XOR
        LBNZ    BU6
        LOAD    RA, 0FFFFH
BU6:    LOAD    RF, TREL
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        LDI     0
        SHR
        SEP     R5
BUX:    LDI     1
        SHR
        SEP     R5

; FROMR: RA = TN + $FF - RA + the byte after the call (the samples from the phase's start)
FROMR:  LDA     R6
        PLO     RB
        LOAD    RF, TN
        LDA     RF
        PHI     RC
        LDN     RF
        ADI     0FFH
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC              ; RC = TN + $FF
        GLO     RA
        STR     R2
        GLO     RC
        SM
        PLO     RC
        GHI     RA
        STR     R2
        GHI     RC
        SMB
        PHI     RC
        GLO     RB
        STR     R2
        GLO     RC
        ADD
        PLO     RA
        GHI     RC
        ADCI    0
        PHI     RA
        SEP     R5

; PHASE: D = SEQ / REQ at TLS; TN half-periods of the tone loop -> RC, RA, RB (as TL leaves them)
PHASE:  PLO     RC
        LOAD    RF, TLS
        GLO     RC
        STR     RF
        LOAD    RF, TN
        LDA     RF
        PHI     R7
        LDN     RF
        ADI     0FFH
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        LOAD    RF, TKB
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LDI     0
        PHI     RC
        PLO     RC
        PHI     RA
        PLO     RA
        PHI     RB
        PLO     RB
        PLO     R8
        SEP     R4
        DW      TL
        SEP     R5

; =================================================================================================== the timing
; SETUP: MCB = C100 x 1,250 (machine cycles a second); CYC = MCB / 1,000 (a sample); MKB = (CYC - MOVH) / 6 + $FF;
;   COMP = FMTC / CYC (the samples a line takes to make)
SETUP:  LOAD    RF, C100
        LDA     RF
        PHI     RA
        LDN     RF
        PLO     RA
        LOAD    RB, 1250
        SEP     R4
        DW      MUL
        LOAD    RF, MCB
        GLO     RD
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LOAD    RB, 125         ; C8 = MCB / 125: a sample's cycles x 8
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        LOAD    RF, C8
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        GLO     RC              ; K = (C8 - 8 MOVH) / 48 (at least 1), MFR = what is left x 4
        SMI     LOW(8 * MOVH + 48)
        GHI     RC
        SMBI    HIGH(8 * MOVH + 48)
        LBDF    SE1
        LOAD    RC, 1
        LDI     0
        PLO     R9
        LBR     SE2
SE1:    GLO     RC
        SMI     LOW(8 * MOVH)
        PLO     RC
        GHI     RC
        SMBI    HIGH(8 * MOVH)
        PHI     RC
        LDI     0
        PLO     RD
        LOAD    RB, 48
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        GLO     R9
        SHL
        SHL
        PLO     R9
SE2:    LOAD    RF, MKB         ; MKB = K + $FF, MFR
        GLO     RC
        ADI     0FFH
        PLO     RB
        GHI     RC
        ADCI    0
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        INC     RF
        GLO     R9
        STR     RF
        LOAD    RA, FMTC        ; COMP = FMTC x 2048 / C8: the samples a line takes, /256
        LOAD    RB, 2048
        SEP     R4
        DW      MUL
        LOAD    RF, C8
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        LOAD    RF, COMP
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LOAD    RA, FMTD        ; COMPD = FMTD x 2048 / C8
        LOAD    RB, 2048
        SEP     R4
        DW      MUL
        SEP     R4
        DW      DIV             ; (DVS is still C8)
        LOAD    RF, COMPD
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R5

; =================================================================================================== small helpers
; GETW: RD -> a word -> RD.  GETWF: RF -> a word -> RD
GETW:   LDA     RD
        PHI     R7
        LDN     RD
        PLO     RD
        GHI     R7
        PHI     RD
        SEP     R5
GETWF:  LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R5

; MUL: RA x RB -> RD.0:RC (24 bits). Uses R9.0.
MUL:    LDI     0
        PLO     RD
        PHI     RC
        PLO     RC
        PLO     R9
MU1:    GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        LBNF    MU2
        GLO     RB
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RB
        STR     R2
        GHI     RC
        ADC
        PHI     RC
        GLO     R9
        STR     R2
        GLO     RD
        ADC
        PLO     RD
MU2:    GLO     RB
        SHL
        PLO     RB
        GHI     RB
        SHLC
        PHI     RB
        GLO     R9
        SHLC
        PLO     R9
        GHI     RA
        LBNZ    MU1
        GLO     RA
        LBNZ    MU1
        SEP     R5

; DEC5: RD -> 5 digits at NBUF, the leading zeros as spaces (the last digit always shown)
DEC5:   LOAD    RF, NBUF
        LOAD    RC, PTEN
        LDI     0
        PHI     RB              ; RB.1 = 1 once a digit is shown
DE1:    LDA     RC
        PHI     R9
        LDA     RC
        PLO     R9
        GHI     R9
        LBNZ    DE2
        GLO     R9
        LBZ     DE9
DE2:    LDI     0               ; the digit: 9 tries every time, so a line takes the same time whatever it shows
        PLO     RB
        LDI     9
        PHI     R7
DE3:    GLO     R9
        STR     R2
        GLO     RD
        SM
        PLO     R7
        GHI     R9
        STR     R2
        GHI     RD
        SMB
        LBNF    DE3N
        PHI     RD
        GLO     R7
        PLO     RD
        INC     RB
        LBR     DE3E
DE3N:   SEX     R2
        SEX     R2
        SEX     R2
        SEX     R2
        NOP
DE3E:   GHI     R7
        SMI     1
        PHI     R7
        LBNZ    DE3
DE4:    GLO     RB
        LBNZ    DEA
        GHI     RB
        LBNZ    DEB
        GLO     R9              ; the ones: always
        XRI     1
        LBZ     DE5
        LDI     ' '
        NOP
        LBR     DE6
DEA:    NOP
        SEX     R2
DEB:    NOP
        SEX     R2
        SEX     R2
DE5:    LDI     1
        PHI     RB
        GLO     RB
        ADI     '0'
DE6:    STR     RF
        INC     RF
        LBR     DE1
DE9:    SEP     R5
PTEN:   DW      10000, 1000, 100, 10, 1, 0

; PUTN: RD right-aligned in D characters (up to 5 digits, wider: spaces first) at RF (the line); RF past it
PUTN:   PHI     R8              ; (R8 is kept by SAVEL)
        GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
        SEP     R4
        DW      DEC5
        GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        GHI     R8
        SMI     5
        LBNF    PU2
        PLO     R8
PU1:    GLO     R8
        LBZ     PU3
        LDI     ' '
        STR     RF
        INC     RF
        DEC     R8
        LBR     PU1
PU2:    SDI     0               ; fewer than 5: skip 5 - D
        PLO     R8
        LOAD    RC, NBUF
PU2A:   GLO     R8
        LBZ     PU4
        INC     RC
        DEC     R8
        LBR     PU2A
PU3:    LOAD    RC, NBUF
PU4:    GLO     RC
        XRI     LOW(NBUF + 5)
        LBZ     PU9
        LDA     RC
        STR     RF
        INC     RF
        LBR     PU4
PU9:    SEP     R5

; PDECW: RD printed right-aligned in D characters
PDECW:  PLO     RC
        LOAD    RF, PWID
        GLO     RC
        STR     RF
        LOAD    RF, LBUF
        LOAD    RC, PWID
        LDN     RC
        SEP     R4
        DW      PUTN
        LDI     0
        STR     RF
        LOAD    RF, LBUF
PD1:    LDA     RF
        LBZ     PD9
        SEP     R4
        DW      K_OUT
        LBR     PD1
PD9:    SEP     R5

; PUTS: the text after the call -> RF
PUTS:   LDA     R6
        LBZ     PS9
        STR     RF
        INC     RF
        LBR     PUTS
PS9:    SEP     R5

; SETDVS: DVS = RB
SETDVS: LOAD    RF, DVS
        GHI     RB
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        SEP     R5

; ---- DIV (PLAY's): RD.0:RC (24 bits) / DVS (16) -> RD.0:RC, the remainder in R9. Uses R7, RA, RB.0, RF.1.
DIV:    LOAD    R7, DVS+1
        LDI     0
        PHI     R9
        PLO     R9
        LDI     24
        PLO     RB
DV1:    GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     RD
        SHLC
        PLO     RD
        GLO     R9
        SHLC
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        LDI     0
        SHLC
        PHI     RA
        SEX     R7
        GLO     R9
        SM
        PLO     RA
        DEC     R7
        GHI     R9
        SMB
        INC     R7
        PHI     RF
        LBDF    DVC
        GHI     RA
        LBZ     DVN
DVC:    GHI     RF
        PHI     R9
        GLO     RA
        PLO     R9
        INC     RC
DVN:    SEX     R2
        DEC     RB
        GLO     RB
        LBNZ    DV1
        SEP     R5

        INCL    "numarg.inc"
ZERO:   DB      0
PTAB:
        DB      '  0'
        DB      '  1'
        DB      '  2'
        DB      '  3'
        DB      '  4'
        DB      '  5'
        DB      '  6'
        DB      '  7'
        DB      '  8'
        DB      '  9'
        DB      ' 10'
        DB      ' 11'
        DB      ' 12'
        DB      ' 13'
        DB      ' 14'
        DB      ' 15'
        DB      ' 16'
        DB      ' 17'
        DB      ' 18'
        DB      ' 19'
        DB      ' 20'
        DB      ' 21'
        DB      ' 22'
        DB      ' 23'
        DB      ' 24'
        DB      ' 25'
        DB      ' 26'
        DB      ' 27'
        DB      ' 28'
        DB      ' 29'
        DB      ' 30'
        DB      ' 31'
        DB      ' 32'
        DB      ' 33'
        DB      ' 34'
        DB      ' 35'
        DB      ' 36'
        DB      ' 37'
        DB      ' 38'
        DB      ' 39'
        DB      ' 40'
        DB      ' 41'
        DB      ' 42'
        DB      ' 43'
        DB      ' 44'
        DB      ' 45'
        DB      ' 46'
        DB      ' 47'
        DB      ' 48'
        DB      ' 49'
        DB      ' 50'
        DB      ' 51'
        DB      ' 52'
        DB      ' 53'
        DB      ' 54'
        DB      ' 55'
        DB      ' 56'
        DB      ' 57'
        DB      ' 58'
        DB      ' 59'
        DB      ' 60'
        DB      ' 61'
        DB      ' 62'
        DB      ' 63'
        DB      ' 64'
        DB      ' 65'
        DB      ' 66'
        DB      ' 67'
        DB      ' 68'
        DB      ' 69'
        DB      ' 70'
        DB      ' 71'
        DB      ' 72'
        DB      ' 73'
        DB      ' 74'
        DB      ' 75'
        DB      ' 76'
        DB      ' 77'
        DB      ' 78'
        DB      ' 79'
        DB      ' 80'
        DB      ' 81'
        DB      ' 82'
        DB      ' 83'
        DB      ' 84'
        DB      ' 85'
        DB      ' 86'
        DB      ' 87'
        DB      ' 88'
        DB      ' 89'
        DB      ' 90'
        DB      ' 91'
        DB      ' 92'
        DB      ' 93'
        DB      ' 94'
        DB      ' 95'
        DB      ' 96'
        DB      ' 97'
        DB      ' 98'
        DB      ' 99'
        DB      '100'
PEND:
C100:   DS      2               ; (START sets these four in order)
FREQ:   DS      2
EFN:    DS      1
INV:    DS      1
PEAK:   DS      1               ; (CLEAR: these four in order)
LASTL:  DS      2
LFLAG:  DS      1
DCV:    DS      1
SNUM:   DS      5               ; the count of sounds, in digits
LNUM:   DS      5               ; the last length, in digits
COMPD:  DS      2
DVS:    DS      2
MCB:    DS      3
C8:     DS      2
MKB:    DS      2               ; (MFR follows it)
MFR:    DS      1
CFR:    DS      1
COMP:   DS      2
TKB:    DS      2
CF:     DS      2
TN:     DS      2
TNOI:   DS      2
TON:    DS      2
TATK:   DS      2
TREL:   DS      2
NTRY:   DS      1
PWID:   DS      1
SVR8:   DS      4
NBUF:   DS      5
LBUF:   DS      12
OBUF:   DS      80
VEND:
        END
