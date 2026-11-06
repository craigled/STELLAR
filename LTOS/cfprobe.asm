; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cfprobe.asm - CFPROBE: CFCHECK four ways, to find how a slow card must be read (2026-10-27: the SDCFB-32 gave the
; first bytes of IDENTIFY, then $00s, then the rest late - it was not ready, and the Elf2K does not wait for it).
;   CALL 3000  as LTOS reads (INP after INP)      CALL 3006  the status before every byte: not busy, data ready
;   CALL 3003  ~20 ms after DRQ, then as LTOS     CALL 3009  a pause after every byte (~20 steps)
; READ ONLY, as CFCHECK.
; (from) cfcheck.asm - CFCHECK: is this card read reliably? READ ONLY - nothing is written to the card. (2026-10-27, for
; the 32 MB and 256 MB cards that gave bytes moved along on the Elf2K.) Load CFCHECK.HEX, CALL 3000:
;   1  reset with LTOS's driver (the ~16 ms wait, 8-bit mode checked: IDE8CHK) - said OK or why not
;   2  IDENTIFY three times: the three must be the same; the model and the size from it
;   3  sectors 0-127 and the last one, each read twice with another sector read between - every pair must agree
; Then back to the monitor. STELLAR, if it is in RAM, is not touched ($3000 up only; buffers $6000-$65FF).
        CPU     1802
        INCL    "ltos.inc"

        ORG     3000H - 6
        DW      3000H, PEND - 3000H, 3000H
        ORG     3000H
        LBR     M0
        LBR     M1
        LBR     M2
        LBR     M3
M0:     LDI     0
        LSKP
M1:     LDI     1
        LSKP
M2:     LDI     2
        LSKP
M3:     LDI     3
        PLO     RE
        LOAD    RD, MODE
        GLO     RE
        STR     RD
START:  SEX     R2
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'CFPROBE - reading only, nothing is written - way ',0
        LOAD    RD, MODE
        LDN     RD
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      '',0DH,0AH,'Reset, 8-bit mode:    ',0
        SEP     R4
        DW      IDERST
        LBNF    C1
        SEP     R4
        DW      PIN
        DB      'FAILED $',0
        LBR     CBAD
C1:     SEP     R4
        DW      PIN
        DB      'OK',0DH,0AH,'IDENTIFY x 3:         ',0
        LOAD    RF, 6000H
        SEP     R4
        DW      PID
        LBDF    CFAIL
        LOAD    RF, 6200H
        SEP     R4
        DW      PID
        LBDF    CFAIL
        LOAD    RF, 6400H
        SEP     R4
        DW      PID
        LBDF    CFAIL
        LOAD    RD, 6000H       ; the three the same?
        LOAD    RF, 6200H
        LOAD    RA, 6400H
        LOAD    RC, 512
C2:     LDA     RF
        STR     R2
        LDN     RD
        XOR
        LBNZ    C2BAD
        LDA     RA
        STR     R2
        LDA     RD
        XOR
        LBNZ    C2BAD
        DEC     RC
        GLO     RC
        LBNZ    C2
        GHI     RC
        LBNZ    C2
        SEP     R4
        DW      PIN
        DB      'the same',0DH,0AH,'Model:                ',0
        LOAD    RD, 6000H+54    ; words 27-46, each word's two characters swapped
        LDI     20
        PLO     RC
C3:     INC     RD
        LDN     RD
        SEP     R4
        DW      F_TYPE
        DEC     RD
        LDN     RD
        SEP     R4
        DW      F_TYPE
        INC     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    C3
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'Sectors:              $',0
        LOAD    RD, 6000H+120   ; words 60-61: the sectors (low word first, each low byte first)
        LDA     RD
        PLO     R7
        LDA     RD
        PHI     R7
        LDA     RD
        PLO     R8
        LDN     RD
        PHI     R8
        LOAD    RD, LAST        ; LAST = sectors - 1
        GLO     R7
        SMI     1
        STXD
        GHI     R7
        SMBI    0
        STXD
        GLO     R8
        SMBI    0
        STXD
        GHI     R8
        SMBI    0
        STR     RD
        INC     RD
        IRX
        LDXA
        STR     RD
        INC     RD
        LDXA
        STR     RD
        INC     RD
        LDX
        STR     RD
        GHI     R8
        SEP     R4
        DW      PHEX2
        GLO     R8
        SEP     R4
        DW      PHEX2
        GHI     R7
        SEP     R4
        DW      PHEX2
        GLO     R7
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'Sectors 0-127, last:  ',0
        LOAD    RD, NBAD
        LDI     0
        STR     RD
        LOAD    R9, 0           ; R9 = the sector (0-127)
C4:     GHI     R9
        PHI     R7
        GLO     R9
        PLO     R7
        LOAD    R8, 0
        SEP     R4
        DW      TWICE
        INC     R9
        GLO     R9
        XRI     128
        LBNZ    C4
        LOAD    RD, LAST        ; and the last
        LDA     RD
        PHI     R8
        LDA     RD
        PLO     R8
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      TWICE
        LOAD    RD, NBAD
        LDN     RD
        LBNZ    C5
        SEP     R4
        DW      PIN
        DB      'every pair agrees',0DH,0AH,0DH,0AH,'This card reads reliably.',0DH,0AH,0
        SEP     R5
C5:     SEP     R4
        DW      PIN
        DB      0DH,0AH,'Pairs that differ: ',0
        LOAD    RD, NBAD
        LDN     RD
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      0DH,0AH,0DH,0AH,'This card does NOT read reliably.',0DH,0AH,0
        SEP     R5
C2BAD:  SEP     R4
        DW      PIN
        DB      'DIFFERENT (this card does NOT read reliably)',0DH,0AH,0
        SEP     R5
CFAIL:  STXD
        SEP     R4
        DW      PIN
        DB      'the card did not answer $',0
        IRX
        LDX
CBAD:   SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      0DH,0AH,0
        SEP     R5
; TWICE: the sector R8:R7 into $6000, LBA 1 into $6400 (the card's buffer moved on), it again into $6200: the two
;        must agree. Not: "$sssss " said, NBAD + 1. R8, R7 kept.
TWICE:  LOAD    RF, 6000H
        SEP     R4
        DW      PRD
        LBDF    TWX
        GLO     R7
        STXD
        GHI     R7
        STXD
        GLO     R8
        STXD
        GHI     R8
        STXD
        LOAD    R7, 1
        LOAD    R8, 0
        LOAD    RF, 6400H
        SEP     R4
        DW      PRD
        IRX
        LDXA
        PHI     R8
        LDXA
        PLO     R8
        LDXA
        PHI     R7
        LDX
        PLO     R7
        LBDF    TWX
        LOAD    RF, 6200H
        SEP     R4
        DW      PRD
        LBDF    TWX
        LOAD    RD, 6000H
        LOAD    RF, 6200H
        LOAD    RC, 512
TW1:    LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    TWX
        DEC     RC
        GLO     RC
        LBNZ    TW1
        GHI     RC
        LBNZ    TW1
        SEP     R5
TWX:    LOAD    RD, NBAD        ; (a read that failed counts too)
        LDN     RD
        ADI     1
        STR     RD
        LDI     '$'
        SEP     R4
        DW      F_TYPE
        GLO     R8
        SEP     R4
        DW      PHEX2
        GHI     R7
        SEP     R4
        DW      PHEX2
        GLO     R7
        SEP     R4
        DW      PHEX2
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        SEP     R5

; ---- PID / PRD: IDENTIFY / the sector R8:R7 -> 512 bytes at RF (RF kept), the data read the MODE way. DF = 1: failed.
PID:    LDI     0ECH
        LSKP
PRD:    LDI     20H
        PLO     RE              ; the command -> PCMD
        LOAD    RD, PCMD
        GLO     RE
        STR     RD
        GLO     RF
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      IDEWAIT
        LBDF    PX3
        LOAD    RD, PCMD
        LDN     RD
        XRI     20H
        LBNZ    PR1
        SEP     R4
        DW      IDELBA
        LBR     PR2
PR1:    LDI     IDE_DEV
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0E0H
        STR     R2
        OUT     DATPORT
        DEC     R2
PR2:    LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RD, PCMD
        LDN     RD              ; the command
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R4
        DW      IDEDRQ
        LBDF    PX3
        LOAD    RD, MODE
        LDN     RD
        XRI     1
        LBNZ    PR3
        LDI     8               ; way 1: ~20 ms before the data
        PHI     RC
        LDI     0
        PLO     RC
PW1:    DEC     RC
        GHI     RC
        LBNZ    PW1
PR3:    LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RC, 512
PR4:    LOAD    RD, MODE
        LDN     RD
        XRI     2
        LBNZ    PR6
        LDI     IDE_CMD         ; way 2: the status first - not busy, data ready (8x)
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0
        PLO     RD
PR5:    DEC     RD
        GLO     RD
        LBZ     PR5X
        INP     DATPORT
        ANI     88H
        XRI     08H
        LBNZ    PR5
PR5X:   LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
PR6:    SEX     RF
        INP     DATPORT
        INC     RF
        SEX     R2
        LOAD    RD, MODE
        LDN     RD
        XRI     3
        LBNZ    PR8
        LDI     7               ; way 3: a pause after the byte
        PLO     RD
PR7:    DEC     RD
        GLO     RD
        LBNZ    PR7
PR8:    DEC     RC
        GLO     RC
        LBNZ    PR4
        GHI     RC
        LBNZ    PR4
        IRX
        LDXA
        PHI     RF
        LDX
        PLO     RF
        LDI     0
        SHR
        SEP     R5
PX3:    PLO     RE
        IRX
        LDXA
        PHI     RF
        LDX
        PLO     RF
        GLO     RE
        SMI     0
        SEP     R5
MODE:   DB      0
PCMD:   DB      0
        INCL    "ide.asm"
        INCL    "cons.asm"
NUMBUF  EQU     6600H           ; (nums.asm's digits)
        INCL    "nums.asm"
LAST:   DB      0, 0, 0, 0
NBAD:   DB      0
PEND:
        END
