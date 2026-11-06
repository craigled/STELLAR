; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; nums.asm - LTOS number printing (INCL'd after cons.asm; not in the boot sector, which has no room).
;   PHEX2    D as two hex digits          PHEX4    RD as four
;   PDEC     RD as a decimal number (0-65535), no leading zeros

PHEX4:  GHI     RD
        SEP     R4
        DW      PHEX2
        GLO     RD
PHEX2:  STXD                    ; keep the byte
        SHR
        SHR
        SHR
        SHR
        SEP     R4
        DW      PNIB
        IRX
        LDX
        ANI     0FH
PNIB:   SMI     10              ; one hex digit
        LBNF    PNIB1
        ADI     'A'-'0'-10
PNIB1:  ADI     '0'+10
        SEP     R4
        DW      F_TYPE
        SEP     R5

; PDEC: RD in decimal, no leading zeros. Repeated subtraction of 10000, 1000, 100, 10 (no BIOS maths).
;       Keeps RD, RF, RC, R9.
PDEC:   GLO     RD
        STXD
        GHI     RD
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        GLO     RC
        STXD
        GHI     RC
        STXD
        GLO     R9
        STXD
        GHI     R9
        STXD
        LDI     0
        PHI     R9              ; R9.1 = 1 once a digit has been printed
        LDI     HIGH(DECTAB)
        PHI     RF
        LDI     LOW(DECTAB)
        PLO     RF
PD0:    LDA     RF              ; RC = the power of ten (0 = only the units are left)
        PHI     RC
        LDA     RF
        PLO     RC
        STR     R2
        GHI     RC
        OR
        LBZ     PDU
        LDI     '0'
        PLO     R9              ; R9.0 = the digit
PD1:    GLO     RC              ; RD - RC: does it go?
        STR     R2
        GLO     RD
        SM
        PLO     RE              ; (no calls in this loop: RE.0 is safe)
        GHI     RC
        STR     R2
        GHI     RD
        SMB
        LBNF    PD2             ; no
        PHI     RD
        GLO     RE
        PLO     RD
        INC     R9
        LBR     PD1
PD2:    GLO     R9
        SMI     '0'
        LBNZ    PD3             ; a digit other than 0
        GHI     R9
        LBZ     PD0             ; a leading 0: not printed
PD3:    LDI     1
        PHI     R9
        GLO     R9
        SEP     R4
        DW      F_TYPE
        LBR     PD0
PDU:    GLO     RD              ; the units, always printed
        ADI     '0'
        SEP     R4
        DW      F_TYPE
        IRX
        LDXA
        PHI     R9
        LDXA
        PLO     R9
        LDXA
        PHI     RC
        LDXA
        PLO     RC
        LDXA
        PHI     RF
        LDXA
        PLO     RF
        LDXA
        PHI     RD
        LDX
        PLO     RD
        SEP     R5
DECTAB: DW      10000, 1000, 100, 10, 0

; ---- PMB: R8:R7 sectors, printed as MB (sectors / 2048); keeps R7, R8
PMB:    GHI     R8
        PHI     RA
        GLO     R8
        PLO     RA
        GHI     R7
        PHI     RD
        GLO     R7
        PLO     RD
        LDI     11
        PLO     RC
PM1:    GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        GHI     RD
        SHRC
        PHI     RD
        GLO     RD
        SHRC
        PLO     RD
        DEC     RC
        GLO     RC
        LBNZ    PM1
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' MB',0
        SEP     R5


; ---- PDEC32: R8:R7 in decimal, right-aligned in D columns (0: no padding). Keeps R7, R8.
;      Uses RA RB RC RD RF R9. Repeated subtraction of 10^9 ... 10 (no BIOS maths).
PDEC32: PLO     RA              ; RA.0 = the width
        GLO     R7
        STXD
        GHI     R7
        STXD
        GLO     R8
        STXD
        GHI     R8
        STXD
        LOAD    RF, NUMBUF
        LOAD    RD, P10TAB
        LDI     0
        PHI     RB              ; RB.1 = 1 once a digit is kept
        LDI     9
        PHI     RA              ; RA.1 = powers to go
PQ1:    LDI     '0'
        PLO     RB              ; RB.0 = the digit
PQ2:    INC     RD              ; R9:RC = R8:R7 - the power (from its low byte)
        INC     RD
        INC     RD
        SEX     RD
        GLO     R7
        SM
        PLO     RC
        DEC     RD
        GHI     R7
        SMB
        PHI     RC
        DEC     RD
        GLO     R8
        SMB
        PLO     R9
        DEC     RD
        GHI     R8
        SMB
        PHI     R9
        SEX     R2
        LBNF    PQ3             ; it does not go
        GHI     R9
        PHI     R8
        GLO     R9
        PLO     R8
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        INC     RB
        LBR     PQ2
PQ3:    GLO     RB
        XRI     '0'
        LBNZ    PQ4
        GHI     RB
        LBZ     PQ5             ; a leading 0
PQ4:    GLO     RB
        STR     RF
        INC     RF
        LDI     1
        PHI     RB
PQ5:    INC     RD
        INC     RD
        INC     RD
        INC     RD
        GHI     RA
        SMI     1
        PHI     RA
        LBNZ    PQ1
        GLO     R7              ; the units
        ADI     '0'
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        GLO     RF              ; padding: width - length
        SMI     LOW(NUMBUF)
        STR     R2
        GLO     RA
        SM
        LBNF    PQ7
        LBZ     PQ7
        PLO     RA
PQ6:    LDI     ' '
        SEP     R4
        DW      F_TYPE
        DEC     RA
        GLO     RA
        LBNZ    PQ6
PQ7:    LOAD    RF, NUMBUF
        SEP     R4
        DW      F_MSG
        IRX
        LDXA
        PHI     R8
        LDXA
        PLO     R8
        LDXA
        PHI     R7
        LDX
        PLO     R7
        SEP     R5
P10TAB: DB      3BH,9AH,0CAH,00H, 05H,0F5H,0E1H,00H, 00H,98H,96H,80H, 00H,0FH,42H,40H
        DB      00H,01H,86H,0A0H, 00H,00H,27H,10H, 00H,00H,03H,0E8H, 00H,00H,00H,64H
        DB      00H,00H,00H,0AH

; ---- P2D: D (0-99) as two digits
P2D:    PLO     RA
        LDI     '0'
        PHI     RA
P2D1:   GLO     RA
        SMI     10
        LBNF    P2D2
        PLO     RA
        GHI     RA
        ADI     1
        PHI     RA
        LBR     P2D1
P2D2:   GHI     RA
        SEP     R4
        DW      F_TYPE
        GLO     RA
        ADI     '0'
        SEP     R4
        DW      F_TYPE
        SEP     R5
