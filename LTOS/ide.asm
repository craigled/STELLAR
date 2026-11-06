; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; ide.asm - LTOS's CompactFlash / IDE driver for the Elf2K Disk/UART/RTC card (INCL'd).
;
; The same protocol as CF-Test / CF-Scan (HW-verified): OUT 2 selects a register, INP / OUT 3 reads or
; writes it, 8-bit mode, LBA, master. Every access selects its register first - the console UART shares
; the select register.
;
; Calls (BIOS SCRT): DF = 0 worked; DF = 1 failed with D = the card's error register, or $FF (no answer
; in ~4 s) or $FE (the card never asked for the data). Sector number: R8.1 = LBA 24-27, R8.0 = LBA
; 16-23, R7 = LBA 0-15. Buffer: RF (kept). Uses RC (kept) and RE.0. X = R2 on entry and exit.
;
;   IDERST   soft reset, interrupts off, 8-bit mode (checked: IDE8CHK), 3 tries
;   IDEID    IDENTIFY DEVICE -> 512 bytes at RF
;   IDERD    read the sector R8:R7 -> 512 bytes at RF
;   IDEWR    write 512 bytes at RF -> the sector R8:R7

; ---- IDERST: soft reset, then (ATA) ~16 ms before the status means anything - a card can still show ready from
;      before the reset, and took SET FEATURES then as nothing (the 32 MB SDCFB-32s, 2026-10-26) - then ready,
;      8-bit mode, and IDE8CHK that it took. Not: the whole again, 3 times at most. RD kept.
IDERST: GLO     RC
        STXD
        GHI     RC
        STXD
        GHI     RD
        STXD
        LDI     3
        PHI     RD              ; RD.1 = tries
IRS0:   LDI     IDE_DEV
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0E0H
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     IDE_CTL
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     06H             ; soft reset, interrupts off (LTOS has no interrupt handler)
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     0
        PLO     RC
IRS1:   DEC     RC              ; hold it a while (ATA: 5 us)
        GLO     RC
        LBNZ    IRS1
        LDI     02H             ; reset off, interrupts still off
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     2
        PHI     RC              ; (RC.0 = 0) 512 x 3 steps: ~16 ms
IRS2:   DEC     RC
        GHI     RC
        LBNZ    IRS2
        SEP     R4
        DW      IDEWAIT
        LBDF    IRSX
        LDI     IDE_DEV
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0E0H
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     IDE_ERR         ; feature $01 = 8-bit data, then SET FEATURES
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     01H
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0EFH
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R4
        DW      IDEDONE
        LBDF    IRSX
        SEP     R4
        DW      IDE8CHK
        LBNF    IDEX2
IRSX:   PLO     RE              ; again? (D: why)
        GHI     RD
        SMI     1
        PHI     RD
        LBNZ    IRS0
        GLO     RE
        SMI     0               ; DF = 1, D kept
IDEX2:  PLO     RE              ; (D and DF survive the pops)
        IRX
        LDXA
        PHI     RD
        LDXA
        PHI     RC
        LDX
        PLO     RC
        GLO     RE
        SEP     R5
; IDE8CHK: is the card in 8-bit mode? IDENTIFY, read 256 bytes (thrown away): the card must still want more (DRQ) -
;   in 16-bit mode it has given all 256 words by then; 256 more: now it must be done. DF = 1 + D $FD: not 8-bit.
IDE8CHK: SEP    R4
        DW      IDEWAIT
        LBDF    I8X
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0ECH
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R4
        DW      IDEDRQ
        LBDF    I8X
        SEP     R4              ; 256, then DRQ still set
        DW      I8RD
        LBZ     I8BAD
        SEP     R4              ; 256 more, then DRQ clear
        DW      I8RD
        LBNZ    I8BAD
        LDI     0
        SHR
        SEP     R5
I8BAD:  LDI     0FDH
        SMI     0
I8X:    SEP     R5
; I8RD: 256 data bytes into M(R2) (the free slot, over and over), then D = the status's DRQ bit
I8RD:   LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0
        PLO     RC
I8R1:   INP     DATPORT
        DEC     RC
        GLO     RC
        LBNZ    I8R1
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     08H
        SEP     R5

; ---- IDEID / IDERD / IDEWR
IDEID:  GLO     RC
        STXD
        GHI     RC
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      IDEWAIT
        LBDF    IDEX4
        LDI     IDE_DEV
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0E0H
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     0ECH
        LBR     IDRC

IDERD:  GLO     RC
        STXD
        GHI     RC
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      IDEWAIT
        LBDF    IDEX4
        SEP     R4
        DW      IDELBA
        LDI     20H
IDRC:   PLO     RC              ; the command
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RC
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R4
        DW      IDEDRQ
        LBDF    IDEX4
        LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RC, 512
        SEX     RF              ; INP straight into the buffer (X = RF), at full speed - the pause and the
IRD1:   INP     DATPORT         ;  stack slot of LTOS 0.2 were for a failing 74HC245 on Craig's card, since
        INC     RF              ;  replaced (CFSCAN at full speed: 8 MB written and read, no errors)
        DEC     RC
        GLO     RC
        LBNZ    IRD1
        GHI     RC
        LBNZ    IRD1
        SEX     R2
        LDI     0
        SHR                     ; DF = 0
        LBR     IDEX4

IDEWR:  GLO     RC
        STXD
        GHI     RC
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      IDEWAIT
        LBDF    IDEX4
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
        LBDF    IDEX4
        LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RC, 512
IWR1:   LDA     RF              ; each byte goes out from the stack slot (X = R2), not straight from the
        STR     R2              ;  buffer: on Craig's Elf2K an OUT straight from some addresses ($67BE, in
        OUT     DATPORT         ;  LTOS 0.4's installer) sends the byte before it again - even after the
        DEC     R2              ;  74HC245 was replaced. (Reads straight into the buffer are fine.)
        DEC     RC
        GLO     RC
        LBNZ    IWR1
        GHI     RC
        LBNZ    IWR1
        SEP     R4
        DW      IDEDONE         ; busy until it is written; its error, if any
IDEX4:  PLO     RE
        IRX
        LDXA
        PHI     RF
        LDXA
        PLO     RF
        LDXA
        PHI     RC
        LDX
        PLO     RC
        GLO     RE
        SEP     R5

; ---- IDELBA: one sector at R8:R7, LBA mode, master
IDELBA: LDI     IDE_CNT
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     1
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     IDE_LBA0
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     R7
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     IDE_LBA1
        STR     R2
        OUT     SELPORT
        DEC     R2
        GHI     R7
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     IDE_LBA2
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     R8
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     IDE_DEV
        STR     R2
        OUT     SELPORT
        DEC     R2
        GHI     R8
        ANI     0FH
        ORI     0E0H
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R5

; ---- the waits. RC is the timeout (65,536 tries, ~4 s at 3 MHz) - callers keep RC; RD is kept here.
; IDEWAIT, before a command: not busy and ready. The error bit is ignored: it stays set from the LAST
;   command until the next is written (after one failure every later wait would fail too).
; IDEDRQ, after a command: not busy, then an error, or a data request.
; IDEDONE, after a command with no data to come: not busy, then an error, or ready.
IDEWAIT: LDI    40H             ; wait for RDY, errors not counted
        LSKP
IDEDONE: LDI    41H             ; RDY, errors counted
        LSKP
IDEDRQ: LDI     09H             ; DRQ, errors counted
        PLO     RE              ; (RE.0 only: RE.1 is the BIOS's baud byte - never DEC / INC RE)
        GLO     RD
        STXD                    ; RD.0 = what to wait for (+ bit 0: count errors); kept for the caller
        GLO     RE
        PLO     RD
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0
        PLO     RC
        PHI     RC              ; 65,536 tries
IW1:    DEC     RC
        GLO     RC
        LBNZ     IW2
        GHI     RC
        LBNZ     IW2
        LDI     0FFH            ; no answer
        LBR     IWFAIL
IW2:    INP     DATPORT         ; the status, also at M(R2)
        ANI     80H
        LBNZ     IW1             ; busy: the other bits mean nothing yet
        GLO     RD
        ANI     01H
        LBZ      IW3
        LDN     R2
        ANI     01H
        LBZ      IW3
        LDI     IDE_ERR         ; an error: its error register
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        LBR     IWFAIL
IW3:    GLO     RD
        ANI     0FEH            ; the bit wanted (RDY or DRQ) ...
        AND                     ; ... of the status still at M(R2)
        LBZ      IW1
        LDI     0
        SHR                     ; DF = 0
        LSKP
IWFAIL: SMI     0               ; DF = 1, D kept
        PLO     RE
        IRX
        LDX
        PLO     RD
        GLO     RE
        SEP     R5
