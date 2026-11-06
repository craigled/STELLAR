; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; send.asm - SEND.PRG: SEND [-T] name - a file out to the terminal, for the Mac to keep (the opposite of RECV).
;   SEND name      Intel HEX from address 0: 16 bytes a record, an extended address record (04) every 64 KB,
;                  the end record. Any file, byte for byte; RECV name puts it back (not a .PRG: RECV gives
;                  those the program header from the HEX addresses). On the Mac: elfser.py get NAME file.
;   SEND -T name   the text as it is (a lone LF sent as CR LF), for a terminal's capture.
;   Nothing else is printed (no paging), so a capture holds the file and only the file.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        SEP     R4
        DW      KS_MNTCHK
        LOAD    RD, TEXT        ; TEXT, LASTCR, ADDR (4), SREM (2): 0
        LDI     8
        PLO     RB
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST1
        LDN     RF
        LBZ     USE
        XRI     '-'
        LBNZ    ST2
        INC     RF
        LDA     RF
        ORI     20H
        XRI     't'
        LBNZ    USE
        LOAD    RD, TEXT
        LDI     1
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
ST2:    SEP     R4              ; the file (or a message, and back to the prompt)
        DW      KS_NAMEARG
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, TEXT
        LDN     RD
        LBNZ    TX1
; ---- Intel HEX: a record of up to 16 bytes at a time
HX1:    LOAD    RA, REC         ; RB.0 = the bytes in this record
        LDI     0
        PLO     RB
HX2:    GLO     RB              ; (GETB keeps RA, RB)
        XRI     16
        LBZ     HX3
        SEP     R4
        DW      GETBK
        LBDF    HX3
        STR     RA
        INC     RA
        INC     RB
        LBR     HX2
HX3:    GLO     RB
        LBZ     HXEND
        SEP     R4
        DW      RECORD
        LBR     HX1
HXEND:  SEP     R4
        DW      K_PIN
        DB      ':00000001FF',0DH,0AH,0
        SEP     R5
; RECORD: ':' count address 00 data checksum, CR LF - for RB.0 bytes at REC; ADDR += them. A new 64 KB: the 04
;         record first.
RECORD: LOAD    RD, ADDR+2      ; the low 16 bits 0 and not the first 64 KB: an extended address record
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    RC1
        LOAD    RD, ADDR
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     RC1
        GLO     RB
        STXD
        LDI     ':'
        SEP     R4
        DW      F_TYPE
        LDI     0
        PLO     R9              ; R9.0 = the checksum
        LDI     2
        SEP     R4
        DW      HEXB
        LDI     0
        SEP     R4
        DW      HEXB
        LDI     0
        SEP     R4
        DW      HEXB
        LDI     4
        SEP     R4
        DW      HEXB
        LOAD    RD, ADDR
        LDA     RD
        SEP     R4
        DW      HEXB
        LOAD    RD, ADDR+1
        LDN     RD
        SEP     R4
        DW      HEXB
        SEP     R4
        DW      CKEND
        IRX
        LDX
        PLO     RB
RC1:    LDI     ':'
        SEP     R4
        DW      F_TYPE
        LDI     0
        PLO     R9
        GLO     RB
        SEP     R4
        DW      HEXB
        LOAD    RD, ADDR+2
        LDA     RD
        SEP     R4
        DW      HEXB
        LOAD    RD, ADDR+3
        LDN     RD
        SEP     R4
        DW      HEXB
        LDI     0
        SEP     R4
        DW      HEXB
        GLO     RB
        PLO     RC
        LOAD    RA, REC
RC2:    LDA     RA
        SEP     R4
        DW      HEXB
        DEC     RC
        GLO     RC
        LBNZ    RC2
        SEP     R4
        DW      CKEND
        LOAD    RD, ADDR+3      ; ADDR += the count
        GLO     RB
        STR     R2
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5
; GETBK: GETB, keeping RA and RB (a new sector's read may use them)
GETBK:  GHI     RA
        STXD
        GLO     RA
        STXD
        GHI     RB
        STXD
        GLO     RB
        STXD
        SEP     R4
        DW      GETB
        PLO     R7
        IRX
        LDXA
        PLO     RB
        LDXA
        PHI     RB
        LDXA
        PLO     RA
        LDX
        PHI     RA
        GLO     R7
        SEP     R5
; CKEND: the checksum (minus the sum), CR LF
CKEND:  GLO     R9
        SDI     0
        SEP     R4
        DW      HEXB
        LDI     0DH
        SEP     R4
        DW      F_TYPE
        LDI     0AH
        SEP     R4
        DW      F_TYPE
        SEP     R5
; HEXB: D as two hex digits, and into the checksum (R9.0). Keeps RA, RB, RC.
HEXB:   PLO     R8
        STR     R2
        GLO     R9
        ADD
        PLO     R9
        GLO     R8
        SHR
        SHR
        SHR
        SHR
        SEP     R4
        DW      NIB
        GLO     R8
        ANI     0FH
NIB:    ADI     '0'
        PLO     RE
        SMI     '9'+1
        LBNF    NB1
        ADI     'A'
        PLO     RE
NB1:    GLO     RE
        SEP     R4
        DW      F_TYPE
        SEP     R5
; ---- text: as it is, a lone LF as CR LF
TX1:    SEP     R4
        DW      GETB
        LBDF    TX9
        PLO     RA
        XRI     0AH
        LBNZ    TX2
        LOAD    RD, LASTCR
        LDN     RD
        LBNZ    TX2
        LDI     0DH
        SEP     R4
        DW      F_TYPE
TX2:    LOAD    RD, LASTCR
        GLO     RA
        XRI     0DH
        LBZ     TX3
        LDI     1               ; (not a CR: LASTCR = 0)
TX3:    XRI     1
        STR     RD
        GLO     RA
        SEP     R4
        DW      F_TYPE
        LBR     TX1
TX9:    SEP     R5

USE:    SEP     R4
        DW      K_PIN
        DB      'SEND [-T] name - a file out as Intel HEX (RECV puts it back), or as text',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "getb.inc"
PEND:
TEXT:   DS      1               ; TEXT, LASTCR, ADDR, SREM: in this order
LASTCR: DS      1
ADDR:   DS      4
SREM:   DS      2
SPTR:   DS      2
REC:    DS      16
        END
