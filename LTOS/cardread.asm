; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cardread.asm - CARDREAD: the card's sectors to the Mac, for EMMA02/card_copy.py. Reads only: nothing is written.
; Loaded into RAM at the monitor (it uses the BIOS alone, so LTOS need not be running), CALL 3000. The Mac sends
; the sector number (2 bytes, low first); back come a status (ACK, or NAK if the read failed), the 512 bytes and
; a Fletcher sum (2 bytes: running sum of the sums, sum). Sector $FFFF: back to the monitor.
        CPU     1802
        INCL    "ltos.inc"
BUF     EQU     3200H
ACK     EQU     06H
NAK     EQU     15H

        ORG     3000H
START:  SEX     R2
MAIN:   LDI     15H             ; the line status
        STR     R2
        OUT     SELPORT
        DEC     R2
RX1:    INP     DATPORT
        SHR
        BNF     RX1
        LDI     10H             ; the character: the low byte
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     R7
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
RX2:    INP     DATPORT
        SHR
        BNF     RX2
        LDI     10H             ; the high byte
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PHI     R7
        XRI     0FFH
        BNZ     GO
        GLO     R7
        XRI     0FFH
        BNZ     GO
        SEP     R5              ; $FFFF: done
GO:     LOAD    R8, 0E000H
        LOAD    RF, BUF
        SEP     R4
        DW      F_IDEREAD
        SEX     R2
        LDI     ACK
        BNF     SAY
        LDI     NAK
SAY:    SEP     R4
        DW      TXB
        LOAD    RA, BUF
        LOAD    RB, 512
        LDI     0
        PLO     RC
        PHI     RC
NEXT:   LDA     RA
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        STR     R2
        GHI     RC
        ADD
        PHI     RC
        DEC     RA
        LDA     RA
        SEP     R4
        DW      TXB
        DEC     RB
        GHI     RB
        BNZ     NEXT
        GLO     RB
        BNZ     NEXT
        GHI     RC
        SEP     R4
        DW      TXB
        GLO     RC
        SEP     R4
        DW      TXB
        LBR     MAIN
; TXB: D out of the UART, as XFER does it.
TXB:    PLO     RE
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
TXW:    INP     DATPORT
        ANI     20H
        BZ      TXW
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RE
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R5
PEND:
        END
