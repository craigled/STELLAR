; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; sysrx.asm - SYSRX.PRG: every LTOS program from the PC/Mac/Linux in one go (there: elfser.py system).
;   The one file out/LTOS-ALL.PAK comes in XFER's frames: block 0 says how many parts and how many blocks in each;
;   each part (an LPAK bundle, as RECV SYSTEM's) is gathered in memory, and its files saved before the ACK of its
;   last block, so the sender waits for the card. Each .PRG and .STL goes in /BIN if there is one, the rest in the
;   root. RECV SYSTEM stays for a plain terminal program, which has no way to wait.
;   Only the fixed K_ calls and no kernel addresses: it still works right after U has put a new kernel on the card.
; The receive code is XFER's. Nothing is printed until the end: the sender is listening for ACKs.
; verify_sysrx.py runs it on the simulated Elf2K.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
THI     EQU     7700H           ; the CRC table: high bytes, low bytes (page-aligned; made at the start)
TLO     EQU     7800H           ;  (above LTOS's buffers, so a part has all of memory up to PTOP)
FRB     EQU     7900H           ; a frame, as it comes
FRLEN   EQU     516
ACK     EQU     06H
NAK     EQU     15H
CAN     EQU     18H

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        LBR     START           ; (RECV SYSRX.PRG starts a program at its lowest address)
; ---- the receive loop: first, so it sits in one page and its branches are the short kind. At 19200 baud a
;      character takes ~58 instructions' time; this takes ~30. RA = where it goes, RB = bytes to come,
;      RC = the CRC (so far), R9.1 / R8.1 = THI / TLO, R7 = the wait (~0.45 s for each byte). The status
;      register stays selected between characters.
RXL:    LDI     20H
        PHI     R7
RXW:    INP     DATPORT         ; the line status: a character?
        SHR
        BDF     RXC
        DEC     R7
        GHI     R7
        BNZ     RXW
        BR      RXTO            ; none: the frame stopped short
RXC:    LDI     10H             ; the character
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT         ; (D and M(R2))
        STR     RA
        INC     RA
        GHI     RC              ; CRC = (CRC << 8) xor T[CRC.1 xor it]
        XOR
        PLO     R9
        PLO     R8
        LDN     R9
        STR     R2
        GLO     RC
        XOR
        PHI     RC
        LDN     R8
        PLO     RC
        LDI     15H             ; the status again, ready for the next
        STR     R2
        OUT     SELPORT
        DEC     R2
        DEC     RB
        GLO     RB
        BNZ     RXL
        GHI     RB
        BNZ     RXL
        GHI     RC              ; all of it: the CRC over it all (its own CRC too) is 0 if it is good
        BNZ     RXBAD
        GLO     RC
        BNZ     RXBAD
        LDI     0
        SEP     R5
RXBAD:  LDI     2
        SEP     R5
RXTO:   LDI     3
        SEP     R5
RXPEND:
; RXFR: a frame into BUF, waiting up to D x ~0.45 s for its first byte. D = 0 good, 1 nothing came,
;       2 a bad CRC, 3 it stopped short
RXFR:   PLO     RE              ; (the setup first, so the first byte is read soon after it comes)
        LOAD    RA, FRB
        LOAD    RB, FRLEN
        LOAD    RC, 0
        LDI     HIGH(THI)
        PHI     R9
        LDI     HIGH(TLO)
        PHI     R8
        LDI     15H             ; the wait, here and not WAITRX's: a byte seen goes straight to RXC (a call and a
        STR     R2              ; return took most of a character's time)
        OUT     SELPORT
        DEC     R2
RXF1:   LDI     0
        PLO     R7
        LDI     20H
        PHI     R7
RXF2:   INP     DATPORT
        SHR
        LBDF    RXC
        DEC     R7
        GHI     R7
        LBNZ    RXF2
        DEC     RE
        GLO     RE
        LBNZ    RXF1
        LDI     1
        SEP     R5
; WAITRX: up to D x ~0.45 s for a character (not taken): DF = 1 one is there. The status left selected.
WAITRX: PLO     RE
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
WR1:    LDI     0
        PLO     R7
        LDI     20H
        PHI     R7
WR2:    INP     DATPORT
        SHR
        LBDF    WR9
        DEC     R7
        GHI     R7
        LBNZ    WR2
        DEC     RE
        GLO     RE
        LBNZ    WR1
        LDI     0
        SHR
WR9:    SEP     R5
; GETRX: the character waiting -> D
GETRX:  LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RE
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RE
        SEP     R5
; DRAIN: whatever is still coming, thrown away, until ~0.45 s of quiet
DRAIN:  LDI     1
        SEP     R4
        DW      WAITRX
        LBNF    DR9
        SEP     R4
        DW      GETRX
        LBR     DRAIN
DR9:    SEP     R5
; TXB: D out of the UART (straight to it: every byte as it is). Keeps everything but RE.0.
TXB:    PLO     RE
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
TXW:    INP     DATPORT         ; room for it?
        ANI     20H
        LBZ     TXW
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RE
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        SEP     R5
; GENT: the CRC tables (CRC-16 $1021 of each high byte)
GENT:   LDI     0
        PLO     R9
GT1:    GLO     R9
        PHI     RC
        LDI     0
        PLO     RC
        LDI     8
        PLO     RB
GT2:    GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        LBNF    GT3
        GHI     RC
        XRI     10H
        PHI     RC
        GLO     RC
        XRI     21H
        PLO     RC
GT3:    DEC     RB
        GLO     RB
        LBNZ    GT2
        GLO     R9
        PLO     RA
        LDI     HIGH(THI)
        PHI     RA
        GHI     RC
        STR     RA
        LDI     HIGH(TLO)
        PHI     RA
        GLO     RC
        STR     RA
        INC     R9
        GLO     R9
        LBNZ    GT1
        SEP     R5

START:  LOAD    RD, VBEG        ; the variables: 0
        LDI     VEND - VBEG
        PLO     RB
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST1
        SEP     R4
        DW      GENT
        SEP     R4
        DW      K_PIN
        DB      'Waiting for the PC/Mac/Linux (elfser.py system) - Ctrl-C stops.',0DH,0AH,0
        LDI     4
        PLO     RF              ; RF.0: the ~30 s waits left
WG1:    LDI     66              ; ~30 s
        SEP     R4
        DW      WAITRX
        LBDF    WG2
        DEC     RF
        GLO     RF
        LBNZ    WG1
        SEP     R4
        DW      K_PIN
        DB      'Nothing came from the PC/Mac/Linux.',0DH,0AH,0
        LBR     K_MAIN
WG2:    SEP     R4
        DW      GETRX
        XRI     'G'
        LBZ     WG9
        XRI     'G' XOR 03H
        LBNZ    WG1
        LBR     K_MAIN
WG9:    LDI     ACK
        SEP     R4
        DW      TXB
; ---- the frames
FR1:    LDI     200             ; ~90 s
        SEP     R4
        DW      RXFR
        PLO     RB
        LBZ     FR3
        XRI     1
        LBZ     FR2             ; nothing came
        SEP     R4              ; damaged: the rest of it goes
        DW      DRAIN
FR2:    LOAD    RD, BADS
        LDN     RD
        ADI     1
        STR     RD
        XRI     10
        LBZ     STOP
        LDI     NAK
        SEP     R4
        DW      TXB
        LBR     FR1
FR3:    LOAD    RD, BADS
        LDI     0
        STR     RD
        LOAD    RD, FRB         ; the block's number: the one expected?
        LDA     RD
        PLO     RC
        LDN     RD
        PHI     RC
        LOAD    RD, EXP
        LDA     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    FR4
        LDN     RD
        STR     R2
        GLO     RC
        XOR
        LBZ     FR5
FR4:    INC     RC              ; the one before, again: its ACK was lost
        GHI     RC
        STR     R2
        LOAD    RD, EXP
        LDA     RD
        XOR
        LBNZ    FR41
        GLO     RC
        STR     R2
        LDN     RD
        XOR
        LBNZ    FR41
        LDI     ACK
        SEP     R4
        DW      TXB
        LBR     FR1
FR41:   LDI     NAK
        SEP     R4
        DW      TXB
        LBR     FR1
FR5:    LOAD    RD, EXP + 1     ; the next
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, NPART       ; block 0 not seen yet?
        LDN     RD
        LBNZ    FR6
        LOAD    RF, FRB + 6     ; the plan: parts, then each one's blocks
        LDA     RF
        LBZ     STOP
        STR     RD
        PLO     RB
        LOAD    RD, PLAN
FR51:   LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    FR51
        SEP     R4
        DW      NEWPART
        LBR     FR9
FR6:    LOAD    RF, FRB + 2     ; a block of a part
        LOAD    RD, WP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RC, 512
FR61:   LDA     RF
        STR     RA
        INC     RA
        DEC     RC
        GLO     RC
        LBNZ    FR61
        GHI     RC
        LBNZ    FR61
        LOAD    RD, WP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, LEFT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    FR9
        SEP     R4              ; the part is here: its files, then the ACK
        DW      UNPAK
        LOAD    RD, NDONE
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, NPART
        LDN     RD
        XOR
        LBZ     FINI
        SEP     R4
        DW      NEWPART
FR9:    LDI     ACK
        SEP     R4
        DW      TXB
        LBR     FR1
FINI:   LDI     ACK
        SEP     R4
        DW      TXB
        LOAD    RF, SAVED
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' files saved.',0DH,0AH,0
        LOAD    RD, FAILS
        LDN     RD
        LBZ     K_MAIN
        SEP     R4
        DW      K_PIN
        DB      'Some files were NOT saved: the card is full, or failed.',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
STOP:   LDI     CAN
        SEP     R4
        DW      TXB
        SEP     R4
        DW      K_PIN
        DB      'Stopped.',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
; NEWPART: the next part: WP = BUF, LEFT = its blocks (too many for memory: STOP)
NEWPART: LOAD   RD, NDONE
        LDN     RD
        ADI     LOW(PLAN)
        PLO     RD
        LDI     HIGH(PLAN)
        ADCI    0
        PHI     RD
        LDN     RD
        PLO     RB
        SMI     ((PTOP - BUF) / 512) + 1
        LBDF    STOP
        LOAD    RD, LEFT
        GLO     RB
        STR     RD
        LOAD    RD, WP
        LDI     HIGH(BUF)
        STR     RD
        INC     RD
        LDI     LOW(BUF)
        STR     RD
        SEP     R5
; UNPAK: every file of the bundle at BUF saved, replacing. With a /BIN folder, .PRG and .STL go there, the rest in
;        the root; without one, all in the root. (As RECV's, without the names on the screen.)
UNPAK:  LOAD    RD, PKB
        LDI     0
        STR     RD
        LOAD    RF, PBIN        ; a /BIN? (D = 3: "/BIN/" is a folder)
        SEP     R4
        DW      UPAT
        XRI     3
        LBNZ    UP0
        LOAD    RD, PKB
        LDI     1
        STR     RD
UP0:    LOAD    RD, BUF + 4
        LDA     RD
        PLO     RB
        LOAD    RF, PKN         ; PKN, PKP: in this order
        GLO     RB
        STR     RF
        INC     RF
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
UP1:    LOAD    RF, PKN
        LDN     RF
        LBZ     UP9
        SMI     1
        STR     RF
        SEP     R4              ; the folder it goes in
        DW      UPDIR
        LOAD    RF, PKP         ; RD -> the entry
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        GLO     RD              ; past its name
        ADI     11
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LDA     RD              ; RA = BUF + offset, RC = length; PKP = the next entry
        STR     R2
        LDA     RD
        ADI     LOW(BUF)
        PLO     RA
        LDN     R2
        ADCI    HIGH(BUF)
        PHI     RA
        LDA     RD
        PHI     RC
        LDA     RD
        PLO     RC
        LOAD    RF, PKP
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        GLO     RD              ; RD back to the name for K_SAVER
        SMI     15
        PLO     RD
        GHI     RD
        SMBI    0
        PHI     RD
        SEP     R4
        DW      K_SAVER
        LBDF    UP3
        LOAD    RD, SAVED + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     UP1
UP3:    LOAD    RD, FAILS
        LDI     1
        STR     RD
        LBR     UP1
UP9:    SEP     R5
; UPDIR: with /BIN, the file at PKP goes in /BIN if it is a .PRG or .STL, else in the root
UPDIR:  LOAD    RF, PKB
        LDN     RF
        LBZ     UPRT
        LOAD    RF, PKP         ; RF -> its extension
        LDA     RF
        PHI     RD
        LDN     RF
        ADI     8
        PLO     RF
        GHI     RD
        ADCI    0
        PHI     RF
        LDA     RF
        XRI     'P'
        LBNZ    UPX1
        LDA     RF
        XRI     'R'
        LBNZ    UPRT
        LDN     RF
        XRI     'G'
        LBR     UPX2
UPX1:   XRI     'P' XOR 'S'
        LBNZ    UPRT
        LDA     RF
        XRI     'T'
        LBNZ    UPRT
        LDN     RF
        XRI     'L'
UPX2:   LBNZ    UPRT
        LOAD    RF, PBIN        ; a program: /BIN
        LBR     UPAT
UPRT:   LOAD    RF, PROOT       ; the rest: the root
UPAT:   LOAD    RD, NBUF        ; K_PARSE of the path at RF: WDIR = its folder
        SEP     R4
        DW      K_PARSE
        SEP     R5
PBIN:   DB      '/BIN/',0
PROOT:  DB      '/',0
PEND:
VBEG:
EXP:    DS      2
BADS:   DS      1
NPART:  DS      1
NDONE:  DS      1
LEFT:   DS      1
WP:     DS      2
PKB:    DS      1
PKN:    DS      1               ; (PKP follows it)
PKP:    DS      2
SAVED:  DS      2
FAILS:  DS      1
VEND:
PLAN:   DS      32
NBUF:   DS      11
BUF:    DS      1               ; a part, up to PTOP
        END
