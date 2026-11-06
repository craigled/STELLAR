; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cfread2.asm - CFREAD2 (from cfread.asm): sector 73 written again from the installer's kernel image ($5900), read
; back at once ($6000), the card reset, read again ($6200): does the card keep what it took?
; cfread.asm - CFREAD: what is really on the card? (2026-10-26, the 32 MB SDCFB-32: the boot sector's read gave the
; same two kernel sectors wrong every time - a byte moved early - though the installer's read-back said right.)
; Load CFREAD.HEX, CALL 3000. It resets the card as LTOS does (8-bit, interrupts off), then reads sectors 73 and 75
; (LBA) with the kernel's IDERD and with the boot sector's BREAD:  73 -> $6000 (IDERD), $6200 (BREAD)
;                                                                  75 -> $6400 (IDERD), $6600 (BREAD)
; and goes back to the monitor. Nothing is written to the card. Then E 6000 67FF shows them.
        CPU     1802
        INCL    "ltos.inc"

        ORG     3000H - 6
        DW      START, PEND - START, START
        ORG     3000H
START:  SEX     R2
        SEP     R4
        DW      IDERST          ; 8-bit mode, interrupts off
        LBDF    BAD
        LOAD    R7, 73          ; write it (IDEWR: R8:R7, RF -> 512 bytes)
        LOAD    R8, 0
        LOAD    RF, 5900H
        SEP     R4
        DW      IDEWR
        LBDF    BAD
        LOAD    R7, 73          ; read it straight back
        LOAD    R8, 0
        LOAD    RF, 6000H
        SEP     R4
        DW      IDERD
        LBDF    BAD
        SEP     R4              ; the card reset (as at a boot), then read again
        DW      IDERST
        LBDF    BAD
        LOAD    R7, 73
        LOAD    R8, 0
        LOAD    RF, 6200H
        SEP     R4
        DW      IDERD
        LBDF    BAD
        SEP     R4
        DW      PIN
        DB      'CFREAD2: 73 written, read, reset, read - E 6000 63FF',0DH,0AH,0
        SEP     R5
BAD:    SEP     R4
        DW      PIN
        DB      'CFREAD2: the card did not answer',0DH,0AH,0
        SEP     R5
        INCL    "bread.asm"
        INCL    "ide.asm"
        INCL    "cons.asm"
PEND:
        END
