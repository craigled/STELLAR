; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; sleep.asm - SLEEP.PRG: SLEEP n[.dd] waits n seconds (0-65535, two decimals at most), as Unix sleep. Ctrl-C or
; Esc stops it early (exit status 1).
; It is timed by the DS12887 itself, whatever the Elf2K's clock speed: register A's rate bits set to 64 Hz (RS =
; 1010; the divider bits, the time itself, untouched), its periodic flag (register C bit 6, cleared by reading C)
; counted: 64 a second, the decimals to the nearest 1/64. Register A is put back as it was. No interrupt is
; turned on (register B's PIE stays off).
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
        SEP     R4              ; n: the whole seconds -> SECS
        DW      K_SKIPSP
        SEP     R4
        DW      NUMW
        LBNF    A1
        GLO     RB              ; no digits: only if ".5" follows (RD = 0, RB.0 = 0 there)
        LBNZ    USE
        LDN     RF
        XRI     '.'
        LBNZ    USE
        INC     RF
        LDN     RF
        DEC     RF
        SMI     '0'
        LBNF    USE
        SMI     10
        LBDF    USE
A1:     LOAD    RC, SECS
        GHI     RD
        STR     RC
        INC     RC
        GLO     RD
        STR     RC
        LOAD    RC, HUND        ; .dd: hundredths (.5 = 50)
        LDI     0
        STR     RC
        LDN     RF
        XRI     '.'
        LBNZ    A3
        INC     RF
        LDN     RF              ; a digit after the point (or none: "1.")
        SMI     '0'
        LBNF    A3
        SMI     10
        LBDF    A3
        LDA     RF
        SMI     '0'
        STR     R2              ; x 10
        SHL
        SHL
        ADD
        SHL
        STR     RC
        LDN     RF              ; perhaps a second one
        SMI     '0'
        LBNF    A3
        SMI     10
        LBDF    A3
        LDA     RF
        SMI     '0'
        STR     R2
        LDN     RC
        ADD
        STR     RC
A3:     LDN     RF              ; then nothing but spaces
        LBZ     A4
        XRI     ' '
        LBNZ    USE
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USE
A4:     LOAD    RD, HUND        ; EXTRA = (hundredths x 64 + 50) / 100: the periods for the decimals
        LDN     RD
        PLO     RC
        LDI     0
        PHI     RC
        LDI     6               ; RC x 64
        PLO     RB
A5:     GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        DEC     RB
        GLO     RB
        LBNZ    A5
        GLO     RC
        ADI     50
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LDI     0
        PLO     RB              ; RB.0 = the quotient
A6:     GLO     RC
        SMI     100
        PLO     RE
        GHI     RC
        SMBI    0
        LBNF    A7
        PHI     RC
        GLO     RE
        PLO     RC
        INC     RB
        LBR     A6
A7:     LOAD    RD, EXTRA
        GLO     RB
        STR     RD
; ---- the clock: there? (register B = $FF: none) Then A's rate = 64 Hz, C read (its flag cleared)
        LDI     8BH
        SEP     R4
        DW      RTCR
        XRI     0FFH
        LBNZ    C1
        SEP     R4
        DW      K_PIN
        DB      'SLEEP needs the clock (a DS12887 on the Disk/UART/RTC card).',0DH,0AH,0
        LBR     FAIL
C1:     LDI     8AH
        SEP     R4
        DW      RTCR
        ANI     7FH             ; (UIP is read-only)
        STR     R2              ; (LOAD sets D)
        LOAD    RD, OLDA
        LDN     R2
        STR     RD
        ANI     0F0H
        ORI     0AH             ; RS = 1010: 15.625 ms
        SEP     R4
        DW      SETA
        LDI     8CH
        SEP     R4
        DW      RTCR
; ---- SECS x 64 periods, then EXTRA
        LOAD    RD, SECS
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9              ; R9 = the seconds left
W1:     GHI     R9
        LBNZ    W2
        GLO     R9
        LBZ     W4
W2:     LDI     64
        PLO     R8
W3:     SEP     R4
        DW      TICK
        LBDF    STOP
        DEC     R8
        GLO     R8
        LBNZ    W3
        DEC     R9
        LBR     W1
W4:     LOAD    RD, EXTRA
        LDN     RD
        PLO     R8
W5:     GLO     R8
        LBZ     DONE
        SEP     R4
        DW      TICK
        LBDF    STOP
        DEC     R8
        LBR     W5
DONE:   SEP     R4
        DW      PUTA
        SEP     R5
STOP:   SEP     R4              ; a key stopped it
        DW      PUTA
        GLO     R7              ; (DF = 1 and D = 1: the flag never came)
        LBZ     FAIL
        SEP     R4
        DW      K_PIN
        DB      'The clock',27H,'s periodic flag does not come: SLEEP cannot time itself.',0DH,0AH,0
FAIL:   LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'Usage: SLEEP seconds   (0-65535, two decimals at most: SLEEP 2.5)',0DH,0AH,0
        LBR     FAIL
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5

; TICK: wait for the next periodic flag (register C bit 6). DF = 1: stopped - R7.0 = 0 a key (Ctrl-C or Esc),
;       1 no flag in 65536 looks (far more than 15.625 ms at any clock)
TICK:   LOAD    R7, 0
TK1:    LDI     8CH
        SEP     R4
        DW      RTCR
        ANI     40H
        LBNZ    TK9
        LDI     15H             ; a key? (the UART's line status: bit 0)
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBNF    TK2
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     7FH
        XRI     03H
        LBZ     TKKEY
        XRI     18H             ; (03H XOR 1BH: Esc)
        LBZ     TKKEY
TK2:    DEC     R7
        GHI     R7
        LBNZ    TK1
        GLO     R7
        LBNZ    TK1
        LDI     1               ; 65536 looks and no flag
        PLO     R7
        SHR
        SEP     R5
TKKEY:  LDI     0
        PLO     R7
        LDI     1
        SHR
        SEP     R5
TK9:    LDI     0
        SHR
        SEP     R5

; RTCR: D = $80 + a register -> D = its value.  SETA: D -> register A.  PUTA: register A back as it was.
RTCR:   STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SEP     R5
PUTA:   LOAD    RD, OLDA
        LDN     RD
SETA:   PLO     RE
        LDI     8AH
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RE
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R5

; NUMW: RF -> 1-5 digits (up to 65535) -> RD; DF = 1: none, or too big
NUMW:   LOAD    RD, 0
        LDI     0
        PLO     RB
NW1:    LDN     RF
        SMI     '0'
        LBNF    NW2
        SMI     10
        LBDF    NW2
        GLO     RB
        XRI     5
        LBZ     NWBAD
        INC     RB
        GLO     RD              ; RD = 10 RD + the digit, with a carry out: too big
        SHL
        PLO     RC
        GHI     RD
        SHLC
        PHI     RC
        LBDF    NWBAD
        GLO     RC
        SHL
        PLO     RD
        GHI     RC
        SHLC
        PHI     RD
        LBDF    NWBAD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        LBDF    NWBAD
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
        LBDF    NWBAD
        LDA     RF
        SMI     '0'
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LBDF    NWBAD
        LBR     NW1
NW2:    GLO     RB
        LBZ     NWBAD
        LDI     0
        SHR
        SEP     R5
NWBAD:  LDI     1
        SHR
        SEP     R5

SECS:   DS      2
HUND:   DS      1
EXTRA:  DS      1
OLDA:   DS      1
PEND:
        END
