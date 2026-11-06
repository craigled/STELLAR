; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cfdiag.asm - CFDIAG: find out why the LTOS installer's read-back fails on Craig's SanDisk SDCFB-8.
; Load CFDIAG.HEX, CALL 3000. It writes ONE sector at a time and reads it back three ways - it changes only
; sectors $0109 and $0130 (the card is not bootable after the failed install anyway).
;
; Seen on the Elf2K: STELLAR.BIN's 14th sector ($1A00-$1BFF of the firmware) written to sector $0109 reads back
; with two bytes repeated at offset $AF (and once at $BD): the data slides 2 bytes - every time, at the same
; place. Is it the write or the read? The data or the place?
;
; Each test: write (fast = LTOS's 8-to-a-turn OUT loop, or slow = a pause after every byte), then read back
; three ways (fast = LTOS's INP loop, slow = a pause after every byte, BIOS = the ROM's own read) and print the
; first difference for each - or "ok". Three rounds of each.

        CPU     1802
        INCL    "ltos.inc"

VBUF    EQU     7400H           ; where a sector is read back

        ORG     3000H
START:  LOAD    RD, SAVR2       ; back to the monitor from anywhere
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
        DB      0DH,0AH,'CFDIAG - which part of the CF transfer slips?',0DH,0AH,0
        SEP     R4
        DW      IDERST
        LBDF    BYE
        LOAD    R9, TESTS       ; each: data address (2), sector (2), write kind (1); a 0 word ends them
T1:     LDA     R9
        PHI     RF
        LDA     R9
        PLO     RF
        GHI     RF
        STR     R2
        GLO     RF
        OR
        LBZ     BYE
        LOAD    RD, DATA
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDA     R9
        PHI     R7
        LDA     R9
        PLO     R7
        LOAD    R8, 0
        LOAD    RD, WKIND
        LDA     R9
        STR     RD
        LDI     3
        PLO     RA              ; RA.0 = rounds
T2:     SEP     R4              ; "data $1A00 -> sector $0109, fast write: "
        DW      PIN
        DB      'data $',0
        SEP     R4
        DW      PDATA
        SEP     R4
        DW      PIN
        DB      ' -> sector $',0
        GHI     R7
        SEP     R4
        DW      PHEX2
        GLO     R7
        SEP     R4
        DW      PHEX2
        LOAD    RD, WKIND
        LDN     RD
        LBNZ    T3
        SEP     R4
        DW      PIN
        DB      ', fast write: ',0
        SEP     R4
        DW      LDATA
        SEP     R4
        DW      IDEWR
        LBR     T4
T3:     SEP     R4
        DW      PIN
        DB      ', slow write: ',0
        SEP     R4
        DW      LDATA
        SEP     R4
        DW      SLOWWR
T4:     LBDF    WERR
        SEP     R4              ; read it back three ways
        DW      PIN
        DB      'fast read ',0
        LOAD    RF, VBUF
        SEP     R4
        DW      IDERD
        SEP     R4
        DW      CMPR
        SEP     R4
        DW      PIN
        DB      ', slow read ',0
        LOAD    RF, VBUF
        SEP     R4
        DW      SLOWRD
        SEP     R4
        DW      CMPR
        SEP     R4
        DW      PIN
        DB      ', BIOS read ',0
        LOAD    RF, VBUF
        LDI     0E0H            ; BIOS: R8.1 = E0 + LBA 24-27
        PHI     R8
        SEP     R4
        DW      F_IDEREAD
        LDI     0
        PHI     R8
        SEP     R4
        DW      CMPR
        SEP     R4
        DW      PCRLF
        DEC     RA
        GLO     RA
        LBNZ    T2
        LBR     T1
WERR:   SEP     R4
        DW      PIN
        DB      'WRITE FAILED',0DH,0AH,0
        LBR     T1
BYE:    SEP     R4
        DW      PIN
        DB      'Done.',0DH,0AH,0
        LOAD    RD, SAVR2
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

; PDATA: print DATA (4 hex digits).  LDATA: RF = DATA.
PDATA:  LOAD    RD, DATA
        LDA     RD
        SEP     R4
        DW      PHEX2
        LDN     RD
        SEP     R4
        DW      PHEX2
        SEP     R5
LDATA:  LOAD    RD, DATA
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5

; CMPR: VBUF against DATA (DF = 1 from the read: "read failed"). Prints "ok" or "@ofs wrote/read +N"
; where N says how far back in the data the byte read really came from (1-4), if it did.
CMPR:   LBNF    CM0
        SEP     R4
        DW      PIN
        DB      'FAILED',0
        SEP     R5
CM0:    SEP     R4
        DW      LDATA           ; RF = the data, RD = VBUF
        LOAD    RD, VBUF
        LDI     0
        PHI     RC
        PLO     RC              ; RC = the offset
CM1:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    CM2
        INC     RC
        GHI     RC
        XRI     2
        LBNZ    CM1
        SEP     R4
        DW      PIN
        DB      'ok',0
        SEP     R5
CM2:    DEC     RD
        DEC     RF
        LDI     '@'
        SEP     R4
        DW      F_TYPE
        GHI     RC
        SEP     R4
        DW      PHEX1
        GLO     RC
        SEP     R4
        DW      PHEX2
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDN     RF
        SEP     R4
        DW      PHEX2
        LDI     '/'
        SEP     R4
        DW      F_TYPE
        LDN     RD
        SEP     R4
        DW      PHEX2
        LDI     1               ; is it the data from 1-4 bytes back?
        PLO     RB
CM3:    GLO     RB
        STR     R2
        GLO     RF
        SM
        PLO     RC
        GHI     RF
        SMBI    0
        PHI     RC
        LDN     RC
        STR     R2
        LDN     RD
        XOR
        LBZ     CM4
        INC     RB
        GLO     RB
        XRI     5
        LBNZ    CM3
        SEP     R5
CM4:    SEP     R4
        DW      PIN
        DB      ' (-',0
        GLO     RB
        ADI     '0'
        SEP     R4
        DW      F_TYPE
        LDI     ')'
        SEP     R4
        DW      F_TYPE
        SEP     R5
PHEX1:  ANI     0FH             ; one hex digit
        SMI     10
        LBNF    PH1
        ADI     'A'-'0'-10
PH1:    ADI     '0'+10
        SEP     R4
        DW      F_TYPE
        SEP     R5

; SLOWWR / SLOWRD: as IDEWR / IDERD, but one byte at a time with a pause after each (~60 us)
SLOWWR: SEP     R4
        DW      IDEWAIT
        LBDF    SLX
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
        LBDF    SLX
        LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RC, 512
        SEX     RF
SW1:    OUT     DATPORT
        LDI     10
SW2:    SMI     1
        LBNZ    SW2
        DEC     RC
        GLO     RC
        LBNZ    SW1
        GHI     RC
        LBNZ    SW1
        SEX     R2
        SEP     R4
        DW      IDEDONE
SLX:    SEP     R5
SLOWRD: SEP     R4
        DW      IDEWAIT
        LBDF    SLX
        SEP     R4
        DW      IDELBA
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     20H
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R4
        DW      IDEDRQ
        LBDF    SLX
        LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RC, 512
        SEX     RF
SR1:    INP     DATPORT
        INC     RF
        LDI     10
SR2:    SMI     1
        LBNZ    SR2
        DEC     RC
        GLO     RC
        LBNZ    SR1
        GHI     RC
        LBNZ    SR1
        SEX     R2
        LDI     0
        SHR
        SEP     R5

        INCL    "ide.asm"
        INCL    "cons.asm"
        INCL    "nums.asm"

; the tests: data, sector, 0 = fast write / 1 = slow write
TESTS:  DW      1A00H, 0109H
        DB      0               ; what failed, as it failed
        DW      1A00H, 0130H
        DB      0               ; the same data at another sector: the place, or the data?
        DW      1800H, 0109H
        DB      0               ; other data at the same sector
        DW      1A00H, 0109H
        DB      1               ; the failing case, written slowly
        DW      0
SAVR2:  DS      4
DATA:   DS      2
WKIND:  DS      1
NUMBUF  EQU     7200H
        END
