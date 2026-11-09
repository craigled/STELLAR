; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cfwtest.asm - CFWTEST: does this card keep what is written? (2026-11-09: a 256 MB Toshiba whose IDENTIFY loses
; bytes on the Elf2K.) CALL 3000 from the monitor. Sector $1000 is read and kept, then three patterns are written
; to it in turn and each read back - with sector 0 read in between, so a card cannot answer from its own buffer -
; and the bytes that differ counted. Then the sector it held is written back. Buffers: $6000 the pattern, $6200
; the read-back (the last one stays there: EXAMINE 6200 63FF), $6400 the sector as it was, $6600 sector 0.
        CPU     1802
        INCL    "ltos.inc"
TSEC    EQU     1000H

        ORG     3000H - 6
        DW      START, PEND - START, START
        ORG     3000H
START:  SEX     R2
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'CFWTEST - sector $1000, three patterns, then put back',0DH,0AH,'Reset: ',0
        SEP     R4
        DW      IDERST
        LBDF    FAIL
        SEP     R4
        DW      PIN
        DB      'OK',0DH,0AH,0
        SEP     R4              ; the sector as it was
        DW      SETLBA
        LOAD    RF, 6400H
        SEP     R4
        DW      IDERD
        LBDF    FAIL
        LDI     0
        PLO     R9              ; R9.0 = the pattern
T1:     SEP     R4
        DW      MAKE
        SEP     R4
        DW      PIN
        DB      'Pattern ',0
        GLO     R9
        ADI     '1'
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      SETLBA
        LOAD    RF, 6000H
        SEP     R4
        DW      IDEWR
        LBDF    FAIL
        LOAD    R7, 0           ; another sector first
        LOAD    R8, 0
        LOAD    RF, 6600H
        SEP     R4
        DW      IDERD
        LBDF    FAIL
        SEP     R4
        DW      SETLBA
        LOAD    RF, 6200H
        SEP     R4
        DW      IDERD
        LBDF    FAIL
        SEP     R4
        DW      COMP
        INC     R9
        GLO     R9
        XRI     3
        LBNZ    T1
        SEP     R4              ; put it back
        DW      SETLBA
        LOAD    RF, 6400H
        SEP     R4
        DW      IDEWR
        LBDF    FAIL
        SEP     R4
        DW      PIN
        DB      'Sector $1000 written back as it was.',0DH,0AH,0
        SEP     R5
FAIL:   PLO     RB
        SEP     R4
        DW      PIN
        DB      ' the card failed: $',0
        GLO     RB
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      0DH,0AH,0
        SEP     R5
; SETLBA: R8:R7 = TSEC
SETLBA: LOAD    R7, TSEC
        LOAD    R8, 0
        SEP     R5
; MAKE: pattern R9.0 at $6000: 0 the bytes 0-255 twice, 1 $55 $AA ..., 2 every byte of STELLAR's first sector
;       (from $0000) with $7C $00 $A8 at 100 and 506
MAKE:   LOAD    RF, 6000H
        LOAD    RC, 0
MK1:    GLO     R9
        LBNZ    MK2
        GLO     RC
        LBR     MK4
MK2:    XRI     1
        LBNZ    MK3
        GLO     RC
        ANI     1
        LBZ     MK21
        LDI     0AAH
        LBR     MK4
MK21:   LDI     55H
        LBR     MK4
MK3:    GLO     RC              ; RD = $0000 + RC
        PLO     RD
        GHI     RC
        PHI     RD
        LDN     RD
MK4:    STR     RF
        INC     RF
        INC     RC
        GHI     RC
        XRI     2
        LBNZ    MK1
        GLO     R9
        XRI     2
        LBNZ    MK9
        LOAD    RF, 6000H + 100
        SEP     R4
        DW      PUT3
        LOAD    RF, 6000H + 506
        LBR     PUT3
MK9:    SEP     R5
PUT3:   LDI     7CH
        STR     RF
        INC     RF
        LDI     00H
        STR     RF
        INC     RF
        LDI     0A8H
        STR     RF
        SEP     R5
; COMP: $6000 against $6200: the bytes that differ, and where the first is
COMP:   LOAD    RD, 6000H
        LOAD    RF, 6200H
        LOAD    RC, 0           ; the count
        LOAD    RA, 0FFFFH      ; the first (none)
CP1:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBZ     CP2
        INC     RC
        GHI     RA
        XRI     0FFH
        LBNZ    CP2
        GLO     RD              ; RA = its offset
        SMI     1
        PLO     RA
        GHI     RD
        SMBI    60H
        PHI     RA
CP2:    GHI     RD
        XRI     62H
        LBNZ    CP1
        SEP     R4
        DW      PIN
        DB      ': ',0
        GHI     RC
        SEP     R4
        DW      PHEX2
        GLO     RC
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ' bytes differ',0
        GHI     RA
        XRI     0FFH
        LBZ     CP9
        SEP     R4
        DW      PIN
        DB      ', the first at $',0
        GHI     RA
        SEP     R4
        DW      PHEX2
        GLO     RA
        SEP     R4
        DW      PHEX2
CP9:    SEP     R4
        DW      PIN
        DB      0DH,0AH,0
        SEP     R5
        INCL    "ide.asm"
        INCL    "cons.asm"
NUMBUF  EQU     6800H
        INCL    "nums.asm"
PEND:
        END
