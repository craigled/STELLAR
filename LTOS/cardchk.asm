; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cardchk.asm - CARDCHK.HEX: what is on the CF card, asked from the ROM monitor without booting it. The card tool
; (tools/elf2k_card.py) pastes it in and types CALL 3000; it reads sector 0 with LTOS's own IDE driver (8-bit
; mode, as the installer) and says one of:
;   CARD:LTOS    an LTOS boot sector ('LTS' at 3, the MBR's 55 AA) - BOOT will start it
;   CARD:BLANK   no MBR (55 AA not there): never formatted - BOOT would run zeros and stop the Elf2K
;   CARD:OTHER   an MBR, not LTOS's (formatted elsewhere)
;   CARD:NONE    no card answered
; then goes back to the monitor (SEP R5). Nothing is written.
        CPU     1802
        INCL    "ltos.inc"
SBUF    EQU     3400H           ; sector 0 read here

        ORG     3000H
START:  SEP     R4              ; 8-bit mode, interrupts off
        DW      IDERST
        LBDF    NONE
        LOAD    R7, 0
        LOAD    R8, 0
        LOAD    RF, SBUF
        SEP     R4
        DW      IDERD
        LBDF    NONE
        LOAD    RF, SBUF + 1FEH
        LDA     RF
        XRI     55H
        LBNZ    BLANK
        LDN     RF
        XRI     0AAH
        LBNZ    BLANK
        LOAD    RF, SBUF + 3
        LDA     RF
        XRI     'L'
        LBNZ    OTHER
        LDA     RF
        XRI     'T'
        LBNZ    OTHER
        LDN     RF
        XRI     'S'
        LBNZ    OTHER
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'CARD:LTOS',0DH,0AH,0
        SEP     R5
BLANK:  SEP     R4
        DW      PIN
        DB      0DH,0AH,'CARD:BLANK',0DH,0AH,0
        SEP     R5
OTHER:  SEP     R4
        DW      PIN
        DB      0DH,0AH,'CARD:OTHER',0DH,0AH,0
        SEP     R5
NONE:   SEP     R4
        DW      PIN
        DB      0DH,0AH,'CARD:NONE',0DH,0AH,0
        SEP     R5
        INCL    "ide.asm"
        INCL    "cons.asm"
CEND:
        END
