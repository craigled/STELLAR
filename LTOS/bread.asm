; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; bread.asm - a small sector read for the boot sector and MON's stub (INCL'd), so that neither depends on
; the BIOS's read after BOOT: BIOS 1.0.6's (Craig's) waits for the data with no timeout and without
; waiting for BUSY to clear first (1.0.9 fixed that "for CF compatibility"); LTOS phase 1 hung there.
;
;   BREAD   the sector R7 (LBA 0-65535) -> 512 bytes at RF; RF ends past them.
;           DF = 1: the card reported an error, or no data within ~4 s.  Uses RC, RD; X = R2.
; The task file goes out from BRTASK with OUT 2 / OUT 3 pairs (X = RD), the sector number patched in.
; The card is already in 8-bit mode (the BIOS's BOOT reset it, or LTOS did).

BREAD:  LOAD    RD, BRTASK+5
        GLO     R7
        STR     RD
        INC     RD
        INC     RD
        GHI     R7
        STR     RD
        LOAD    RD, BRTASK
        SEX     RD
        OUT     SELPORT         ; device control: interrupts off (after a reset the card has them on - an
        OUT     DATPORT         ;  interrupt mid-read sent the 1802 off at R1: HW 2026-10-26)
        OUT     SELPORT         ; count = 1
        OUT     DATPORT
        OUT     SELPORT         ; LBA 0-7
        OUT     DATPORT
        OUT     SELPORT         ; LBA 8-15
        OUT     DATPORT
        OUT     SELPORT         ; LBA 16-23 = 0
        OUT     DATPORT
        OUT     SELPORT         ; device: E0 (LBA, master)
        OUT     DATPORT
        OUT     SELPORT         ; command: READ SECTORS (the status is selected from now on)
        OUT     DATPORT
        SEX     R2
        LDI     0
        PLO     RC
        PHI     RC
BRW:    DEC     RC              ; ~65,000 looks: about 4 s
        GHI     RC
        LBZ     BRF
        INP     DATPORT         ; the status (also at M(R2))
        SHL
        LBDF    BRW             ; busy: nothing else means anything yet
        LDN     R2
        SHR
        LBDF    BRF             ; the error bit
        LDN     R2
        ANI     08H
        LBZ     BRW             ; no data yet
        LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RC, 512         ; 512 bytes, one at a time, straight into the buffer (X = RF) - the same pace as
        SEX     RF              ;  ide.asm's IDERD: two reads one instruction apart lost a byte on a 32 MB card
BRR:    INP     DATPORT         ;  (2026-10-26: the byte after a 00, read early, then all moved up one)
        INC     RF
        GHI     RF              ; $7F00 reached (an app's $7E00 block): the rest into M(R2) - $7F00-$7FFF is
        XRI     7FH             ;  the Elf2K BIOS's and is never written
        LBNZ    BRR1
        SEX     R2
BRR1:   DEC     RC
        GLO     RC
        LBNZ    BRR
        GHI     RC
        LBNZ    BRR
        SEX     R2
        LDI     0
        SHR                     ; DF = 0
        SEP     R5
BRF:    LDI     1
        SHR                     ; DF = 1
        SEP     R5
BRTASK: DB      IDE_CTL, 02H, IDE_CNT, 1, IDE_LBA0, 0, IDE_LBA1, 0, IDE_LBA2, 0, IDE_DEV, 0E0H, IDE_CMD, 20H
