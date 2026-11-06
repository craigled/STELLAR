; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cfdiag3.asm - CFDIAG3: why does byte 0 of a written sector sometimes come back $00 on Craig's SDCFB-8?
; Seen (installer, 2026-10-15): sectors $0108 / $0111 read back $00 at byte 0 - twice the same, so it is what the
; card holds - and writing the sector again fixed it. $00 is also the value OUT 2 sends to select the data
; register just before the first byte goes out. If that select is sometimes taken by the card as a data byte
; too, the sector holds $00 followed by the 512 bytes moved along one (the last falls off): "shifted right".
;
; Load CFDIAG3.HEX, CALL 3000. It saves the card's LAST sector, writes it 200 times in each of four ways, reads
; it back each time and sorts the result, then puts the sector back as it was. Nothing else on the card changes.
;   1  LTOS's write, the data straight from STELLAR's $1800 (as the installer wrote sector $0108)
;   2  the same 512 bytes from $6200 (the place, or the data?)
;   3  the data register selected with $40 instead of $00 (the same register to the card): if the stray byte
;      is the select, it now comes back $40
;   4  the data register selected twice (two chances for a stray byte)
; Each write is sorted: ok / only byte 0 wrong / shifted right by one (the first byte stored is printed) /
; shifted left by one / other (how many bytes differ, the first). The first 3 failures of each way are shown.

        CPU     1802
        INCL    "ltos.inc"

SAVEB   EQU     6000H           ; the last sector as it was
COPYB   EQU     6200H           ; $1800-$19FF copied
RBUF    EQU     6400H           ; read back
CHKB    EQU     6600H           ; the second read of the saved sector
NWR     EQU     200             ; writes per way

        ORG     3000H - 6
        DW      START, PEND - START, START

        ORG     3000H
START:  LOAD    RD, SAVR2
        GHI     R2
        STR     RD
        INC     RD
        GLO     R2
        STR     RD
        INC     RD
        GHI     R6
        STR     RD
        INC     RD
        GLO     R6
        STR     RD
        SEX     R2
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'CFDIAG3 - the first byte of a write',0DH,0AH,0
        SEP     R4
        DW      CARD
        LBDF    BYE
        SEP     R4              ; TSEC = the last sector
        DW      LDNSEC
        GLO     R7
        SMI     1
        PLO     R7
        GHI     R7
        SMBI    0
        PHI     R7
        GLO     R8
        SMBI    0
        PLO     R8
        GHI     R8
        SMBI    0
        PHI     R8
        LOAD    RD, TSEC
        SEP     R4
        DW      ST32LE
        LOAD    RF, 1800H       ; COPYB = $1800-$19FF
        LOAD    RD, COPYB
        LOAD    RC, 512
CP1:    LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    CP1
        GHI     RC
        LBNZ    CP1
        SEP     R4
        DW      PIN
        DB      'It writes only sector ',0
        SEP     R4
        DW      LDT
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      ' (the last), 800 times, and puts it back. Press Y to start: ',0
        SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      PCRLF
        GLO     RB
        ANI     0DFH
        XRI     'Y'
        LBNZ    BYE
        LDI     5               ; save it: two reads that agree
        PLO     RA
SV1:    SEP     R4
        DW      LDT
        LOAD    RF, SAVEB
        SEP     R4
        DW      IDERD
        LBDF    SVF
        SEP     R4
        DW      LDT
        LOAD    RF, CHKB
        SEP     R4
        DW      IDERD
        LBDF    SVF
        LOAD    RD, SAVEB
        LOAD    RF, CHKB
        LOAD    RC, 512
SV2:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    SV3
        DEC     RC
        GLO     RC
        LBNZ    SV2
        GHI     RC
        LBNZ    SV2
        LBR     WAYS
SV3:    DEC     RA
        GLO     RA
        LBNZ    SV1
SVF:    SEP     R4
        DW      PIN
        DB      'It cannot be read the same twice - nothing written.',0DH,0AH,0
        LBR     BYE

WAYS:   LOAD    R9, WAYTAB      ; the four ways: source, select value, select twice, name
WT1:    LDA     R9
        LBZ     DONE
        PLO     RB
        LOAD    RD, SRC
        GLO     RB
        STR     RD
        INC     RD
        LDA     R9
        STR     RD
        INC     RD
        LDA     R9              ; SELV
        STR     RD
        INC     RD
        LDA     R9              ; DBL
        STR     RD
        SEP     R4
        DW      PCRLF
        GHI     R9              ; the name
        PHI     RF
        GLO     R9
        PLO     RF
        SEP     R4
        DW      F_MSG
        SEP     R4
        DW      PCRLF
WT0:    LDA     R9              ; past the name, to its 0FFH marker
        XRI     0FFH
        LBNZ    WT0
        GHI     R9
        STXD
        GLO     R9
        STXD
        SEP     R4
        DW      WAY
        IRX
        LDXA
        PLO     R9
        LDX
        PHI     R9
        LBR     WT1

DONE:   SEP     R4              ; put it back: up to 5 writes
        DW      PIN
        DB      0DH,0AH,'Putting the sector back ... ',0
        LDI     5
        PLO     RA
PB1:    SEP     R4
        DW      LDT
        LOAD    RF, SAVEB
        SEP     R4
        DW      IDEWR
        LBDF    PB3
        SEP     R4
        DW      LDT
        LOAD    RF, RBUF
        SEP     R4
        DW      IDERD
        LBDF    PB3
        LOAD    RD, SAVEB
        LOAD    RF, RBUF
        LOAD    RC, 512
PB2:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    PB3
        DEC     RC
        GLO     RC
        LBNZ    PB2
        GHI     RC
        LBNZ    PB2
        SEP     R4
        DW      PIN
        DB      'done.',0DH,0AH,'CFDIAG3 finished.',0DH,0AH,0
        LBR     BYE
PB3:    DEC     RA
        GLO     RA
        LBNZ    PB1
        SEP     R4
        DW      PIN
        DB      'IT DID NOT READ BACK RIGHT - the last sector is not as it was.',0DH,0AH,0
        LBR     BYE

; ---- WAY: NWR writes the way SRC / SELV / DBL say; sort each; print the counts
WAY:    LOAD    RD, CNTS        ; the counts and FAILS: 0
        LDI     14
        PLO     RA
WA0:    LDI     0
        STR     RD
        INC     RD
        DEC     RA
        GLO     RA
        LBNZ    WA0
        LOAD    RD, NLEFT
        LDI     HIGH(NWR)
        STR     RD
        INC     RD
        LDI     LOW(NWR)
        STR     RD
WA1:    SEP     R4
        DW      DWR
        LBDF    WAE
        SEP     R4
        DW      LDT
        LOAD    RF, RBUF
        SEP     R4
        DW      IDERD
        LBDF    WAE
        SEP     R4
        DW      SORT            ; D = the class (0 ok, 1 byte 0, 2 right, 3 left, 4 other)
        LBR     WA2
WAE:    LDI     5               ; the driver failed
WA2:    SHL                     ; count it
        ADI     LOW(CNTS)
        PLO     RD
        LDI     HIGH(CNTS)
        ADCI    0
        PHI     RD
        INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, KEY         ; a key stops it
        SEP     R4
        DW      KEYHIT
        LBDF    WA4
        LOAD    RD, NLEFT+1
        LDN     RD
        SMI     1
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        INC     RD
        SEX     RD
        OR
        SEX     R2
        LBNZ    WA1
WA4:    SEP     R4              ; the counts
        DW      PIN
        DB      '  ok ',0
        LDI     0
        SEP     R4
        DW      PCNT
        SEP     R4
        DW      PIN
        DB      ', only byte 0 wrong ',0
        LDI     1
        SEP     R4
        DW      PCNT
        SEP     R4
        DW      PIN
        DB      ', shifted right ',0
        LDI     2
        SEP     R4
        DW      PCNT
        SEP     R4
        DW      PIN
        DB      ', shifted left ',0
        LDI     3
        SEP     R4
        DW      PCNT
        SEP     R4
        DW      PIN
        DB      ', other ',0
        LDI     4
        SEP     R4
        DW      PCNT
        SEP     R4
        DW      PIN
        DB      ', card errors ',0
        LDI     5
        SEP     R4
        DW      PCNT
        SEP     R4
        DW      PCRLF
        SEP     R5
PCNT:   SHL                     ; count D
        ADI     LOW(CNTS)
        PLO     RF
        LDI     HIGH(CNTS)
        ADCI    0
        PHI     RF
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      PDEC
        SEP     R5

; ---- DWR: write SRC's 512 bytes to TSEC, LTOS's way except the data select (SELV, twice if DBL). DF = 1: failed.
DWR:    SEP     R4
        DW      LDT
        SEP     R4
        DW      IDEWAIT
        LBDF    DWX
        SEP     R4
        DW      IDELBA
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     30H
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R4
        DW      IDEDRQ
        LBDF    DWX
        LOAD    RD, SELV
        LDN     RD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RD, DBL
        LDN     RD
        LBZ     DW1
        LOAD    RD, SELV
        LDN     RD
        STR     R2
        OUT     SELPORT
        DEC     R2
DW1:    LOAD    RD, SRC
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RC, 512
DW2:    LDI     CFDLY
DW3:    SMI     1
        LBNZ    DW3
        LDA     RF
        STR     R2
        OUT     DATPORT
        DEC     R2
        DEC     RC
        GLO     RC
        LBNZ    DW2
        GHI     RC
        LBNZ    DW2
        SEP     R4
        DW      IDEDONE
DWX:    SEP     R5

; ---- SORT: RBUF against SRC -> D = 0 the same, 1 only byte 0, 2 shifted right by one, 3 left, 4 other.
;      Failures (the first 3 of each way): a line.
SORT:   LOAD    RD, SRC
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LOAD    RF, RBUF
        LOAD    RC, 0           ; RC = i
        LOAD    RD, NDIF
        LDI     0
        STR     RD
        INC     RD
        STR     RD
SO1:    LDA     R9
        STR     R2
        LDA     RF
        XOR
        LBZ     SO2
        LOAD    RD, NDIF        ; different: count; the first one kept
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    SO1A
        LOAD    RD, FPOS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        DEC     R9
        DEC     RF
        LDA     R9
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
SO1A:   LOAD    RD, NDIF+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
SO2:    INC     RC
        GHI     RC
        XRI     2
        LBNZ    SO1
        LOAD    RD, NDIF        ; none: ok
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    SO3
        LDI     0
        SEP     R5
SO3:    LOAD    RD, NDIF        ; exactly one, at byte 0?
        LDA     RD
        LBNZ    SO4
        LDN     RD
        XRI     1
        LBNZ    SO4
        LOAD    RD, FPOS
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    SO4
        LDI     1
        LBR     SOX
SO4:    LOAD    RD, SRC         ; shifted right: RBUF[i+1] = SRC[i] for i = 0..510
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LOAD    RF, RBUF+1
        SEP     R4
        DW      SAME511
        LBNF    SO5
        LDI     2
        LBR     SOX
SO5:    LOAD    RD, SRC         ; shifted left: RBUF[i] = SRC[i+1]
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        INC     R9
        LOAD    RF, RBUF
        SEP     R4
        DW      SAME511
        LBNF    SO6
        LDI     3
        LBR     SOX
SO6:    LDI     4
SOX:    PLO     RB              ; the class; a line for the first 3 failures
        LOAD    RD, FAILS
        LDN     RD
        SMI     3
        LBDF    SOY
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      PIN
        DB      '  write ',0
        LOAD    RD, NLEFT       ; (which: NWR + 1 - NLEFT)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        SDI     LOW(NWR+1)
        PLO     RD
        GHI     RC
        SDBI    HIGH(NWR+1)
        PHI     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ': ',0
        LOAD    RD, NDIF
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' byte(s) differ, the first at ',0
        LOAD    RF, FPOS
        LDA     RF
        PHI     RD
        LDA     RF
        PLO     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ': wrote $',0
        LDA     RF
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ' read $',0
        LDN     RF
        SEP     R4
        DW      PHEX2
        GLO     RB
        XRI     2
        LBNZ    SOZ1
        SEP     R4
        DW      PIN
        DB      ' - SHIFTED RIGHT BY ONE (a byte added in front)',0
SOZ1:   GLO     RB
        XRI     3
        LBNZ    SOZ2
        SEP     R4
        DW      PIN
        DB      ' - SHIFTED LEFT BY ONE (the first byte lost)',0
SOZ2:   SEP     R4
        DW      PCRLF
SOY:    GLO     RB
        SEP     R5
; SAME511: 511 bytes at R9 and RF: DF = 1 if all the same
SAME511: LOAD   RC, 511
SA1:    LDA     R9
        STR     R2
        LDA     RF
        XOR
        LBNZ    SA2
        DEC     RC
        GLO     RC
        LBNZ    SA1
        GHI     RC
        LBNZ    SA1
        LDI     1
        SHR
        SEP     R5
SA2:    LDI     0
        SHR
        SEP     R5

LDT:    LOAD    RD, TSEC
        LBR     LD32LE

WAYTAB: DB      18H,00H, 00H, 0         ; source (hi, lo), select value, twice
        DB      '1  the LTOS write, the data from $1800 (as the installer)',0,0FFH
        DB      62H,00H, 00H, 0
        DB      '2  the same 512 bytes, from $6200',0,0FFH
        DB      18H,00H, 40H, 0
        DB      '3  the data register selected with $40 instead of $00',0,0FFH
        DB      18H,00H, 00H, 1
        DB      '4  the data register selected twice',0,0FFH
        DB      0

        INCL    "cfcom.asm"
        INCL    "ide.asm"
        INCL    "cons.asm"
        INCL    "nums.asm"

TSEC:   DS      4
SRC:    DS      2
SELV:   DS      1
DBL:    DS      1
NLEFT:  DS      2
KEY:    DS      1
CNTS:   DS      12              ; ok, byte 0, right, left, other, card errors (2 bytes each, big-endian)
FAILS:  DS      1               ; (zeroed with CNTS: 14 bytes from CNTS - FAILS and the pad)
        DS      1
NDIF:   DS      2
FPOS:   DS      4               ; where, wrote, read
PEND:
        END
