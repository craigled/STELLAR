; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; free.asm - FREE.PRG: the space left on the card (the FAT's free clusters counted), and the space used.
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
; ---- FREE: count the FAT's free entries for clusters 2 .. NCLUS + 1
        LOAD    RD, KS_MOUNTED
        LDN     RD
        LBZ     KS_NOMNT
        LOAD    RD, KS_NCLUS       ; RB = the last entry + 1 = NCLUS + 2
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        INC     RB
        INC     RB
        LDI     0
        PHI     RA              ; RA = the entry
        PLO     RA
        PHI     R9              ; R9 = free entries
        PLO     R9
FR0:    GLO     RA              ; a new FAT sector every 256 entries
        LBNZ    FR4
        GHI     RA
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    RD, KS_FATLBA
        SEP     R4
        DW      KS_LD32
        SEP     R4
        DW      KS_ADD16
        LOAD    RF, KS_FATBUF
        SEP     R4
        DW      KS_IDERD
        LBDF    FRERR
        LOAD    RF, KS_FATBUF
FR4:    LDA     RF
        STR     R2
        LDA     RF
        OR
        LBNZ    FR5             ; in use
        GHI     RA              ; free - and is it a cluster (2 or more)?
        LBNZ    FR6
        GLO     RA
        SMI     2
        LBNF    FR5
FR6:    INC     R9
FR5:    INC     RA
        GLO     RA
        STR     R2
        GLO     RB
        XOR
        LBNZ    FR0
        GHI     RA
        STR     R2
        GHI     RB
        XOR
        LBNZ    FR0
        LOAD    RD, KS_FATCUR   ; FATBUF no longer holds FATCUR's sector
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, FREEC       ; (PDEC32 uses R9: keep the count)
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        GHI     R9              ; free KB = free x clusters' sectors / 2
        PHI     R7
        GLO     R9
        PLO     R7
        SEP     R4
        DW      CLKB
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' KB free of ',0
        LOAD    RD, KS_NCLUS
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      CLKB
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' KB (',0
        LOAD    RF, FREEC
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' of ',0
        LOAD    RD, KS_NCLUS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' clusters of ',0
        LOAD    RD, KS_SPC
        LDN     RD
        PLO     R7
        LDI     0
        PHI     R7
        PHI     R8
        PLO     R8
        LDI     9
        PLO     RB
FR7:    SEP     R4              ; x 512
        DW      KS_SHL32
        DEC     RB
        GLO     RB
        LBNZ    FR7
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' bytes)',0DH,0AH,0
        LOAD    RF, FREEC       ; used: the clusters not free
        LOAD    RD, KS_NCLUS
        INC     RF
        INC     RD
        LDN     RF
        STR     R2
        LDN     RD
        SM
        PLO     R7
        DEC     RF
        DEC     RD
        LDN     RF
        STR     R2
        LDN     RD
        SMB
        PHI     R7
        LOAD    RD, FREEC       ; (FREEC = them now)
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        SEP     R4
        DW      CLKB
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' KB used (',0
        LOAD    RF, FREEC
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' clusters)',0DH,0AH,0
        SEP     R5     
FRERR:  SEP     R4
        DW      KS_PIN
        DB      'The FAT could not be read.',0DH,0AH,0
        SEP     R5     
; CLKB: R7 clusters -> R8:R7 = KB (clusters << SHIFT >> 1)
CLKB:   LDI     0
        PHI     R8
        PLO     R8
        LOAD    RD, KS_SHIFT
        LDN     RD
        PLO     RB
CK1:    GLO     RB
        LBZ     CK2
        SEP     R4
        DW      KS_SHL32
        DEC     RB
        LBR     CK1
CK2:    SEP     R4
        DW      KS_SHR32
        SEP     R5

OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
FREEC:  DS      2
PEND:
        END
