; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; boot.asm - LTOS boot sector = LBA 0 of the card, an MBR (the partition table at $1BE is filled in by
; the installer). The Elf2K BIOS reads it to $0100-$02FF, checks the sum-and-shift of $0100-$0140
; (= $60; only $0139-$0140 count, and $0140 decides it), and then:
;   BIOS 1.0.6 (Craig's: Monitor V87):  R0 = $0100, SEP R0        -> $0100 runs, with P = R0
;   BIOS 1.0.12 and later:              LBR $0106 (P = R3)        -> $0106 runs, with P = R3
; Both land in GO with R3 as the PC, whichever way they came in.
;
; It loads the kernel - KSECT sectors from LBA 65 (the partition's reserved sectors) - to $0300 with its
; own read (bread.asm: BIOS 1.0.6's hung here, phase 1 on the Elf2K), a dot a sector, checks their sum
; against KSUM, and starts it.
; Boot path HW-verified (phase 0, 2026-10-12): BIOS 1.0.6 enters at $0100 with R0.

        CPU     1802
        INCL    "ltos.inc"

KLBA    EQU     65              ; the kernel: the partition (LBA 64) + its boot record

        ORG     0100H
        LBR     E0              ; $0100: BIOS 1.0.6 starts here, P = R0
        DB      'LTS'           ; $0103: the LTOS signature (the installer's U checks it)
        LBR     E3              ; $0106: newer BIOSes start here, P = R3
        DB      'LTOS boot - LiteOS for the Elf2K',0     ; $0109
        ORG     0130H
STLLBA: DW      0               ; $0130: where STELLAR.BIN starts on the card (the installer sets it;
                                ;        the kernel reads it from here)
KSECT:  DB      0               ; $0132: the kernel's sectors (the installer sets it)
KSUM:   DW      0               ; $0133: the 16-bit sum of the kernel's bytes, all KSECT sectors (installer)
        ORG     0140H
CKSUM:  DB      0               ; $0140: build.py sets it so the BIOS's check comes out $60

E0:     LDI     '0'             ; which register was the PC (R9.0, handed to the kernel in D)
        LSKP
E3:     LDI     '3'
        PLO     R9
        LDI     HIGH(GO)
        PHI     R3              ; (same page: if R3 is already the PC, nothing moves)
        LDI     LOW(GO)
        PLO     R3              ; P = R3: we are at GO now
        SEP     R3              ; P = R0: now R3 is the PC, at GO
GO:     SEX     R3              ; interrupts off: X = 2, P = 3 (LTOS has no interrupt handler)
        DIS
        DB      23H
        LOAD    R2, STACK
        SEX     R2
        LOAD    R6, GO2         ; the BIOS sets R4 / R5 to its SCRT and goes on at R6
        LBR     F_INITCALL
GO2:    SEP     R4
        DW      PIN
        DB      0DH,0AH,'LTOS: loading the kernel ',0
        LDI     3
        PHI     RA              ; RA.1 = tries: a bad read or sum loads it all again
KL0:    LOAD    RD, KSECT
        LDN     RD
        PLO     RA              ; RA.0 = sectors to go
        LBZ     NOKERN
        LOAD    R7, KLBA
        LOAD    RF, 0300H
KL:     SEP     R4
        DW      BREAD           ; LTOS's own read (bread.asm), not the BIOS's
        LBDF    KFAIL
        LDI     '.'             ; one dot a sector
        SEP     R4
        DW      F_TYPE
        INC     R7
        DEC     RA
        GLO     RA
        LBNZ    KL
        LOAD    RD, KSECT       ; the sum of KSECT x 512 bytes from $0300 must be KSUM
        LDN     RD
        SHL
        PHI     RC
        LDI     0
        PLO     RC
        PLO     RB
        PHI     RB
        LOAD    RF, 0300H
KS:     LDA     RF
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        DEC     RC
        GLO     RC
        LBNZ    KS
        GHI     RC
        LBNZ    KS
        LOAD    RD, KSUM
        LDA     RD
        STR     R2
        GHI     RB
        XOR
        LBNZ    BADK
        LDN     RD
        STR     R2
        GLO     RB
        XOR
        LBNZ    BADK
        GLO     R9              ; the kernel is told which way the BIOS came in (D)
        LBR     0300H
BADK:                           ; (the same as a failed read)
KFAIL:  GHI     RA
        SMI     1
        PHI     RA
        LBZ     KBAD
        LDI     '?'             ; again
        SEP     R4
        DW      F_TYPE
        LBR     KL0
KBAD:   SEP     R4
        DW      PIN
        DB      ' FAILED (read/sum).',0DH,0AH,0
        LBR     MONWARM
NOKERN: SEP     R4
        DW      PIN
        DB      '- no kernel.',0DH,0AH,0
        LBR     MONWARM

        INCL    "cons.asm"
        INCL    "bread.asm"

BOOTEND:                        ; build.py checks this is at or below $02BE (the partition table)
        ORG     02FEH
        DB      55H, 0AAH       ; the MBR signature
        END
