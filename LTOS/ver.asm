; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; ver.asm - VER.PRG: LTOS's version, the kernel, how it booted, the card, where STELLAR.BIN is.
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
; ---- VER
        SEP     R4
        DW      KS_PIN
        DB      'LTOS 0.5 - LiteOS for the Elf2K',0DH,0AH
        DB      'Free software, GPL-3.0-or-later: HELP LICENSE',0DH,0AH
        DB      'Kernel:     $0300-$',0
        LOAD    RD, KS_KEND-1
        SEP     R4
        DW      KS_PHEX4
        SEP     R4
        DW      KS_PIN
        DB      ' (',0
        LOAD    RD, KS_KEND-KS_KSTART
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' bytes)',0DH,0AH
        DB      'Programs:   $3000-$6BFF',0DH,0AH
        DB      'Booted:     the boot sector started with R',0
        LOAD    RD, KS_BOOTR
        LDN     RD
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'Card:       ',0
        LOAD    RF, KS_SECBUF
        SEP     R4
        DW      KS_IDEID
        LBDF    VNOC
        LDI     0               ; the model: words 27-46, each word's two characters swapped
        PLO     RC
V1:     GLO     RC
        XRI     1
        ADI     LOW(KS_SECBUF+54)
        PLO     RF
        LDI     HIGH(KS_SECBUF+54)
        ADCI    0
        PHI     RF
        LDN     RF
        SEP     R4
        DW      F_TYPE
        INC     RC
        GLO     RC
        XRI     40
        LBNZ    V1
        LOAD    RF, KS_SECBUF+120  ; the size: sectors at bytes 120-123
        LDA     RF
        PLO     R7
        LDA     RF
        PHI     R7
        LDA     RF
        PLO     R8
        LDN     RF
        PHI     R8
        SEP     R4
        DW      KS_PCRLF
        SEP     R4
        DW      KS_PIN
        DB      'Size:       ',0
        SEP     R4
        DW      KS_PMB
        LBR     V2
VNOC:   SEP     R4
        DW      KS_PIN
        DB      'no answer',0
V2:     SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'STELLAR:    ',0
        SEP     R4              ; (as it is now: RECV may have replaced it)
        DW      KS_STLFIND
        LOAD    RF, KS_STLN
        LDN     RF
        LBNZ    V3
        SEP     R4
        DW      KS_PIN
        DB      'no STELLAR.BIN on this card',0DH,0AH,0
        SEP     R5     
V3:     SEP     R4
        DW      KS_PIN
        DB      'STELLAR.BIN at sector $',0
        LOAD    RF, KS_STLLST
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      KS_PHEX4
        LOAD    RD, KS_STLRAM
        LDN     RD
        LBZ     V4
        SEP     R4
        DW      KS_PIN
        DB      ' - in RAM at boot: MON puts it back',0DH,0AH,0
        SEP     R5     
V4:     SEP     R4
        DW      KS_PIN
        DB      ' - not in RAM at boot: MON just leaves',0DH,0AH,0
        SEP     R5     

OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
