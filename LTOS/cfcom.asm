; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cfcom.asm - what CFTEST and CFSCAN share (INCL'd): entry and exit, the card's IDENTIFY, a sector number typed
; in hex, 32-bit printing, 16 x 16 multiply and 32 / 16 divide, a key check that does not wait, and the clock.
; Native 1802, the BIOS's SCRT and console; LTOS's CF driver (ide.asm). Runs at $3000: CALL 3000 from the
; monitor (STELLAR, if in RAM, is left alone below $3000) - or RUN from LTOS.

LINE    EQU     6800H           ; a line typed in
NUMBUF  EQU     6880H           ; PDEC32's digits
IDBUF   EQU     6A00H           ; the card's IDENTIFY

; ---- the program's start does: LOAD RD, SAVR2 and stores R2 then R6 there (see CFTEST / CFSCAN), so
; BYE: back to whoever started the program (the monitor, or LTOS), with R6 as it was when it was started
BYE:    LOAD    RD, SAVR2
        LDA     RD
        PHI     R2
        LDA     RD
        PLO     R2
        LDA     RD
        PHI     R6
        LDN     RD
        PLO     R6
        SEX     R2
        SEP     R5

; ---- CARD: reset the card, IDENTIFY it (twice: the model, LBA flag and size must agree), print
;      "Card: model, n MB". N0-N3 = its sectors (little-endian). DF = 1: no card / no LBA / no agreement.
CARD:   SEP     R4
        DW      PIN
        DB      'Card: ',0
        SEP     R4
        DW      IDERST
        LBDF    CDNO
        LDI     3
        PLO     RA
CD0:    LOAD    RF, IDBUF
        SEP     R4
        DW      IDEID
        LBDF    CDNO
        LOAD    RF, IDBUF+200H
        SEP     R4
        DW      IDEID
        LBDF    CDNO
        LOAD    RD, IDBUF+54    ; the model (54-93), LBA flag (98-99) and size (120-123): the same both times?
        LDI     40
        SEP     R4
        DW      IDSAME
        LBNF    CD2
        LOAD    RD, IDBUF+98
        LDI     2
        SEP     R4
        DW      IDSAME
        LBNF    CD2
        LOAD    RD, IDBUF+120
        LDI     4
        SEP     R4
        DW      IDSAME
        LBDF    CD3
CD2:    DEC     RA
        GLO     RA
        LBNZ    CD0
        SEP     R4
        DW      PIN
        DB      'it answers differently each time it is asked.',0DH,0AH,0
        LBR     CDBAD
CD3:    LDI     0               ; the model: words 27-46, each word's two characters swapped
        PLO     RC
CD4:    GLO     RC
        XRI     1
        ADI     LOW(IDBUF+54)
        PLO     RF
        LDI     HIGH(IDBUF+54)
        ADCI    0
        PHI     RF
        LDN     RF
        SEP     R4
        DW      F_TYPE
        INC     RC
        GLO     RC
        XRI     40
        LBNZ    CD4
        LOAD    RD, IDBUF+120   ; the size
        LOAD    RF, NSEC
        LDI     4
        PLO     RC
CD5:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    CD5
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'Size: ',0
        SEP     R4
        DW      LDNSEC
        SEP     R4
        DW      PMB
        SEP     R4
        DW      PIN
        DB      ' (',0
        SEP     R4
        DW      LDNSEC
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      ' sectors)',0DH,0AH,0
        LOAD    RD, IDBUF+99    ; LBA addressing
        LDN     RD
        ANI     02H
        LBNZ    CDOK
        SEP     R4
        DW      PIN
        DB      'This card has no LBA addressing.',0DH,0AH,0
        LBR     CDBAD
CDOK:   LDI     0
        SHR
        SEP     R5
CDNO:   SEP     R4
        DW      PIN
        DB      'no answer. Is a card in the socket?',0DH,0AH,0
CDBAD:  LDI     1
        SHR
        SEP     R5
; IDSAME: D bytes at RD and at RD + $200: DF = 1 if the same
IDSAME: PLO     RC
        GLO     RD
        PLO     RF
        GHI     RD
        ADI     2
        PHI     RF
IS1:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    IS2
        DEC     RC
        GLO     RC
        LBNZ    IS1
        LDI     1
        SHR
        SEP     R5
IS2:    LDI     0
        SHR
        SEP     R5
; LDNSEC: R8:R7 = the card's sectors
LDNSEC: LOAD    RD, NSEC
        LDA     RD
        PLO     R7
        LDA     RD
        PHI     R7
        LDA     RD
        PLO     R8
        LDN     RD
        PHI     R8
        SEP     R5

; ---- PHEX7: R8:R7 as $nnnnnnn (7 hex digits: up to 2^28 sectors)
PHEX7:  LDI     '$'
        SEP     R4
        DW      F_TYPE
        GLO     R8              ; 4 bits of R8.1 then R8.0, R7
        STXD
        GHI     R8
        ANI     0FH
        SEP     R4
        DW      PNIB
        IRX
        LDX
        SEP     R4
        DW      PHEX2
        GHI     R7
        SEP     R4
        DW      PHEX2
        GLO     R7
        SEP     R4
        DW      PHEX2
        SEP     R5

; ---- GETHEX: a line typed in; RB.0 = 0 Enter alone, 1 a number in R8:R7 (up to 7 hex digits), 2 Q,
;      3 not a number
GETHEX: LOAD    RF, LINE
        LOAD    RC, 20
        SEP     R4
        DW      F_INPUTL
        SEP     R4
        DW      PCRLF
        LOAD    RF, LINE
        LOAD    R7, 0
        LOAD    R8, 0
        LDN     RF
        LBZ     GH0
        ANI     0DFH
        XRI     'Q'
        LBZ     GHQ
        LDI     0
        PLO     RB
GH1:    LDA     RF              ; the digits
        LBZ     GH9
        PLO     RA
        SMI     '0'
        LBNF    GHBAD
        SMI     10
        LBNF    GHD             ; 0-9
        GLO     RA
        ANI     0DFH
        SMI     'A'
        LBNF    GHBAD
        SMI     6
        LBDF    GHBAD
        GLO     RA
        ANI     0DFH
        SMI     'A'-10
        LBR     GHD2
GHD:    GLO     RA
        SMI     '0'
GHD2:   PLO     RA
        GLO     RB              ; at most 7 digits (28 bits)
        XRI     7
        LBZ     GHBAD
        LDI     4
        PLO     RC
GH2:    SEP     R4
        DW      SHL32
        DEC     RC
        GLO     RC
        LBNZ    GH2
        GLO     RA
        STR     R2
        GLO     R7
        OR
        PLO     R7
        INC     RB
        LBR     GH1
GH9:    GLO     RB
        LBZ     GHBAD
        LDI     1
        LSKP
GH0:    LDI     0
        PLO     RB
        SEP     R5
GHQ:    LDI     2
        PLO     RB
        SEP     R5
GHBAD:  LDI     3
        PLO     RB
        SEP     R5

; ---- CMP32: R8:R7 against the 4 little-endian bytes at RD: DF = 1 if R8:R7 >= them
CMP32:  SEX     RD
        GLO     R7
        SM
        IRX
        GHI     R7
        SMB
        IRX
        GLO     R8
        SMB
        IRX
        GHI     R8
        SMB
        SEX     R2
        SEP     R5

; ---- SHL32 / SHR32: R8:R7 one bit
SHL32:  GLO     R7
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        GLO     R8
        SHLC
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        SEP     R5
SHR32:  GHI     R8
        SHR
        PHI     R8
        GLO     R8
        SHRC
        PLO     R8
        GHI     R7
        SHRC
        PHI     R7
        GLO     R7
        SHRC
        PLO     R7
        SEP     R5

; ---- MUL16: R8:R7 = RC x RD (shift and add, from RC's top bit). Uses RA.0.
MUL16:  LOAD    R7, 0
        LOAD    R8, 0
        LDI     16
        PLO     RA
MU1:    SEP     R4
        DW      SHL32
        GLO     RC              ; RC <<= 1: its top bit -> DF
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        LBNF    MU2
        GLO     RD              ; that bit was 1: add RD
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     RD
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        GLO     R8
        ADCI    0
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
MU2:    DEC     RA
        GLO     RA
        LBNZ    MU1
        SEP     R5

; ---- DIV32: R8:R7 / RD -> R7 = the quotient (saturates at $FFFF), shift and subtract. RD = 0: $FFFF.
DIV32:  LDI     32
        PLO     RA
        LOAD    RC, 0           ; RC = the remainder (17 bits: RB.0 bit 0 holds the 17th)
        LDI     0
        PLO     RB
DV1:    SEP     R4
        DW      SHL32           ; the top bit of R8:R7 -> DF
        GLO     RC
        SHLC
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        LDI     0
        SHLC
        PLO     RB
        GLO     RD              ; remainder >= RD?
        STR     R2
        GLO     RC
        SM
        PLO     RF
        GHI     RD
        STR     R2
        GHI     RC
        SMB
        PHI     RF
        GLO     RB
        SMBI    0
        LBNF    DV2
        GHI     RF
        PHI     RC
        GLO     RF
        PLO     RC
        INC     R7              ; the quotient bit (R7 bit 0 is 0 after the shift)
DV2:    DEC     RA
        GLO     RA
        LBNZ    DV1
        GLO     R8              ; more than 16 bits: $FFFF
        STR     R2
        GHI     R8
        OR
        LBZ     DV3
        LOAD    R7, 0FFFFH
DV3:    SEP     R5

; ---- KEYHIT: DF = 1 and D = the key if one is waiting (the UART on the Disk/UART/RTC card), without waiting
KEYHIT: LDI     15H             ; the line status register
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        LBZ     KH0
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RE
        LDI     1
        SHR
        GLO     RE
        SEP     R5
KH0:    LDI     0
        SHR
        SEP     R5

; ---- MINDAY: RC = minutes since midnight from the DS12887 (BCD or binary, 12 or 24 hours); DF = 1: no clock.
;      Read until two readings agree (up to 4): one taken across a change of minute or a misread is not used.
MINDAY: LOAD    RD, MDT
        LDI     4
        STR     RD
MDA:    SEP     R4
        DW      MINRD
        LBDF    MDZ
        LOAD    RD, MDV         ; the same as the last reading?
        LDA     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    MDB
        LDN     RD
        STR     R2
        GLO     RC
        XOR
        LBZ     MDOK
MDB:    LOAD    RD, MDV
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, MDT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    MDA
MDOK:   LDI     0
        SHR
MDZ:    SEP     R5
MINRD:  LDI     8AH             ; register A: wait while it updates
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0
        PLO     RC
MD0:    INP     DATPORT
        ANI     80H
        LBZ     MD1
        DEC     RC
        GLO     RC
        LBNZ    MD0
MD1:    LDI     8BH             ; register B: bit 2 binary, bit 1 24-hour
        SEP     R4
        DW      RTCRD
        PLO     RB
        XRI     0FFH
        LBZ     MDNO            ; $FF: no clock
        LDI     82H             ; minutes
        SEP     R4
        DW      RTCRD
        SEP     R4
        DW      RTCBIN
        PLO     RC
        LDI     84H             ; hours
        SEP     R4
        DW      RTCRD
        PLO     RA
        ANI     7FH
        SEP     R4
        DW      RTCBIN
        PHI     RA              ; RA.1 = the hour, RA.0 bit 7 = PM (12-hour mode)
        GLO     RB
        ANI     02H
        LBNZ    MD2             ; 24-hour
        GHI     RA
        XRI     12
        LBNZ    MD3
        PHI     RA              ; 12 -> 0
MD3:    GLO     RA
        ANI     80H
        LBZ     MD2
        GHI     RA
        ADI     12
        PHI     RA
MD2:    GHI     RA              ; RC = hour x 60 + minutes
        PLO     RD
        LDI     0
        PHI     RD
        GLO     RC
        PLO     RF              ; (the minutes)
        LDI     60
        PLO     RC
        LDI     0
        PHI     RC
        SEP     R4
        DW      MUL16
        GLO     RF
        STR     R2
        GLO     R7
        ADD
        PLO     RC
        GHI     R7
        ADCI    0
        PHI     RC
        LDI     0
        SHR
        SEP     R5
MDNO:   LDI     1
        SHR
        SEP     R5
; RTCRD: D = an RTC register's select ($80 + n) -> D = its value
RTCRD:  STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SEP     R5
; RTCBIN: D -> binary (from BCD, unless register B's bit 2 - in RB.0 - says binary already)
RTCBIN: PLO     RE
        GLO     RB
        ANI     04H
        LBNZ    RB9
        GLO     RE              ; tens x 10 + units
        SHR
        SHR
        SHR
        SHR
        STR     R2
        SHL
        SHL
        ADD                     ; tens x 5
        SHL                     ; x 10
        STR     R2
        GLO     RE
        ANI     0FH
        ADD
        SEP     R5
RB9:    GLO     RE
        SEP     R5

; ---- R8:R7 <-> 4 little-endian bytes at RD
LD32LE: LDA     RD              ; R8:R7 <- 4 little-endian bytes at RD
        PLO     R7
        LDA     RD
        PHI     R7
        LDA     RD
        PLO     R8
        LDN     RD
        PHI     R8
        SEP     R5
ST32LE: GLO     R7              ; 4 little-endian bytes at RD <- R8:R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        INC     RD
        GHI     R8
        STR     RD
        SEP     R5

; ---- WHY: D (IDERD / IDEWR's failure) in words
WHY:    PLO     RB
        XRI     0FFH
        LBNZ    WY1
        SEP     R4
        DW      PIN
        DB      'no answer',0DH,0AH,0
        SEP     R5
WY1:    GLO     RB
        XRI     0FEH
        LBNZ    WY2
        SEP     R4
        DW      PIN
        DB      'the card never asked for the data',0DH,0AH,0
        SEP     R5
WY2:    SEP     R4
        DW      PIN
        DB      'the card reported an error, error register $',0
        GLO     RB
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PCRLF
        SEP     R5

; ---- CMPRB: RBUF against the 512 bytes at RD: DF = 0 the same; DF = 1, RC = where, RD / RF -> the bytes
CMPRB:  LOAD    RF, RBUF
        LOAD    RC, 0
CB1:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    CB2
        INC     RC
        GHI     RC
        XRI     2
        LBNZ    CB1
        LDI     0
        SHR
        SEP     R5
CB2:    DEC     RD
        DEC     RF
        LDI     1
        SHR
        SEP     R5
SAVR2:  DS      4
NSEC:   DS      4
MDT:    DS      1               ; MINDAY: tries left, the last reading
MDV:    DS      2
