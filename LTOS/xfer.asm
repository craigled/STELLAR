; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; xfer.asm - XFER.PRG: files of any size (up to ~32 MB) between the Mac and the card, a sector at a time.
;   XFER -R name   the Mac to the card (on the Mac: elfser.py put FILE NAME); "replace it?" if it is there
;   XFER -S name   the card to the Mac (on the Mac: elfser.py pull NAME FILE)
; The protocol (PLANS/LTOS-XFER-large-files.md): XFER waits for the Mac's 'G'. Then frames of 516 bytes - the
; block number (2, low byte first), 512 bytes, a CRC-16 (XMODEM's: $1021, from 0; high byte first) - each
; answered ACK ($06), NAK ($15, sent again) or CAN ($18, stopped). Block 0 holds the size (4, low byte first),
; blocks 1.. the file (the last one padded); block $FFFF from the Mac stops it. The same block again (its ACK
; was lost) is ACKed and not written twice; 10 bad ones in a row and it stops.
; Mac to card: each block is on the card before its ACK - the Mac waits, so the UART's one byte keeps up. The
; old file stays until the new one is all there; then one directory write switches the entry, and the old
; clusters are freed. Anything going wrong: the clusters taken are given back, nothing is saved.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
THI     EQU     6A00H           ; the CRC table: high bytes, low bytes (page-aligned; made at the start)
TLO     EQU     6B00H
FRLEN   EQU     516
ACK     EQU     06H
NAK     EQU     15H
CAN     EQU     18H

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        LBR     START           ; (RECV XFER.PRG starts a program at its lowest address)
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
        LOAD    RA, BUF
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
; CRCB: RC = the CRC with D. Keeps RA, RB, RF.
CRCB:   STR     R2
        GHI     RC
        XOR
        PLO     R9
        LDI     HIGH(THI)
        PHI     R9
        LDN     R9
        STR     R2
        GLO     RC
        XOR
        PHI     RC
        LDI     HIGH(TLO)
        PHI     R9
        LDN     R9
        PLO     RC
        SEP     R5
; TXC: D into the CRC and out
TXC:    PLO     RF
        SEP     R4
        DW      CRCB
        GLO     RF
        LBR     TXB
; TXFR: frame EXP out: its number, the 512 bytes at RA, the CRC
TXFR:   LOAD    RC, 0
        LOAD    RD, EXP+1
        LDN     RD
        SEP     R4
        DW      TXC
        LOAD    RD, EXP
        LDN     RD
        SEP     R4
        DW      TXC
        LOAD    RB, 512         ; the bytes: the CRC and the UART inline (no calls), so it keeps up
        LDI     HIGH(THI)
        PHI     R9
        LDI     HIGH(TLO)
        PHI     R8
TF1:    LDA     RA
        PLO     RF
        STR     R2              ; CRC = (CRC << 8) xor T[CRC.1 xor it]
        GHI     RC
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
        LDI     15H             ; the status: room for it?
        STR     R2
        OUT     SELPORT
        DEC     R2
TF2:    INP     DATPORT
        ANI     20H
        LBZ     TF2
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RF
        STR     R2
        OUT     DATPORT
        DEC     R2
        DEC     RB
        GLO     RB
        LBNZ    TF1
        GHI     RB
        LBNZ    TF1
        GHI     RC
        SEP     R4
        DW      TXB
        GLO     RC
        LBR     TXB

START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        LOAD    RD, MODE        ; MODE .. WSLEFT: 0
        LDI     VEND - MODE
        PLO     RB
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST1
        LDN     RF              ; -R or -S
        XRI     '-'
        LBNZ    USE
        INC     RF
        LOAD    RD, MODE
        LDA     RF
        ANI     0DFH
        STR     RD
        XRI     'R'
        LBZ     ST2
        XRI     'R' XOR 'S'
        LBNZ    USE
ST2:    LDN     RF
        XRI     ' '
        LBNZ    USE
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        SEP     R4
        DW      KS_MNTCHK
        GHI     RF              ; (GENT uses RF)
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      GENT
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LOAD    RD, MODE
        LDN     RD
        XRI     'R'
        LBZ     RMAIN
        LBR     SMAIN

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

; WAITG: "waiting", then the Mac's 'G' (up to ~2 minutes); Ctrl-C stops
WAITG:  SEP     R4
        DW      K_PIN
        DB      'Waiting for the PC/Mac/Linux (elfser.py) - Ctrl-C stops.',0DH,0AH,0
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
        SEP     R4
        DW      K_PIN
        DB      'Stopped.',0DH,0AH,0
        LBR     K_MAIN
WG9:    SEP     R5

; NBCALC: SIZE (big-endian) -> NBLK = its 512-byte blocks. DF = 1: too big (~32 MB: 65534 blocks at most)
NBCALC: LOAD    RD, SIZE
        SEP     R4
        DW      KS_LD32
        LOAD    RC, 511
        SEP     R4
        DW      KS_ADD16        ; R8:R7 = SIZE + 511 (it fits: R8.1 < 2)
        GHI     R8
        SMI     2
        LBDF    NB9
        LOAD    RD, NBLK
        GHI     R8              ; (SIZE + 511) >> 9
        SHR
        GLO     R8
        SHRC
        STR     RD
        INC     RD
        GHI     R7
        SHRC
        STR     RD
        DEC     RD              ; $FFFF: the stop block's number
        LDA     RD
        ANI     0FFH
        STR     R2
        LDN     RD
        AND
        XRI     0FFH
        LBZ     NB9
        LDI     0
        SHR
        SEP     R5
NB9:    LDI     1
        SHR
        SEP     R5
; ATEND: DF = 1 if EXP = NBLK
ATEND:  LOAD    RD, EXP
        LOAD    RF, NBLK
        LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    AE1
        LDN     RD
        STR     R2
        LDN     RF
        XOR
        LBNZ    AE1
        LDI     1
        LSKP
AE1:    LDI     0
        SHR
        SEP     R5
; EXPINC: EXP + 1
EXPINC: LOAD    RD, EXP+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5
; PSIZE: ", N bytes." and a new line
PSIZE:  SEP     R4
        DW      K_PIN
        DB      ', ',0
        LOAD    RD, SIZE
        SEP     R4
        DW      KS_LD32
        LDI     0               ; (no padding)
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      ' bytes.',0DH,0AH,0
        SEP     R5

; FAIL: (the text after the call) CAN to the Mac, the clusters taken given back, the text, back to the prompt
FAIL:   LOAD    RD, MSGP
        GHI     R6
        STR     RD
        INC     RD
        GLO     R6
        STR     RD
        LDI     CAN
        SEP     R4
        DW      TXB
        LOAD    RD, WFIRST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    FA1
        GLO     RC
        LBZ     FA2
FA1:    SEP     R4
        DW      KS_FREECH
FA2:    SEP     R4
        DW      K_PCRLF
        LOAD    RD, MSGP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      F_MSG
        LOAD    RD, MODE
        LDN     RD
        XRI     'R'
        LBNZ    FA3
        SEP     R4
        DW      K_PIN
        DB      ' Nothing was saved.',0
FA3:    SEP     R4
        DW      K_PCRLF
        LBR     K_MAIN

; ==== XFER -R name: the Mac to the card
RMAIN:  LOAD    RD, KS_FNAME    ; the name (a path: WDIR = its folder)
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_FNAME    ; there already?
        SEP     R4
        DW      KS_FINDN
        LBDF    RM2
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    KS_ISDIR
        LOAD    RD, ESEC        ; the entry to rewrite: its sector, where in DIRBUF; its clusters
        LOAD    RC, KS_DSEC
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        INC     RD
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, OLDCL
        LOAD    RC, KS_DCLUS
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        LOAD    RD, REPL
        LDI     1
        STR     RD
        SEP     R4              ; (the question on the screen, even with the output in a file)
        DW      K_TTYON
        SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ' is already on the card - replace it? (Y/N) ',0
        SEP     R4
        DW      K_YESNO
        LBNF    K_MAIN
        LBR     RM3
RM2:    SEP     R4              ; a new file: a free entry (a folder may grow by a cluster for it)
        DW      KS_DSLOT
        LBNF    RM2A
        SEP     R4
        DW      K_PIN
        DB      'The directory is full.',0DH,0AH,0
        LBR     K_MAIN
RM2A:   LOAD    RD, ESEC
        LOAD    RC, KS_WDSEC    ; WDSEC, WDPTR
        LDI     4
        PLO     RB
RM2B:   LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    RM2B
RM3:    SEP     R4
        DW      WAITG
        LDI     ACK
        SEP     R4
        DW      TXB
; each frame: its first byte within ~60 s (the Mac sends one again after 45 s of no answer)
RL1:    LDI     132
        SEP     R4
        DW      RXFR
        LBZ     RL3
        XRI     1
        LBNZ    RL2
        SEP     R4
        DW      FAIL
        DB      'The PC/Mac/Linux stopped sending.',0
RL2:    LOAD    RD, FAILS       ; bad: again, 10 in a row at most
        LDN     RD
        ADI     1
        STR     RD
        SMI     10
        LBNF    RL2A
        SEP     R4
        DW      FAIL
        DB      '10 bad blocks in a row.',0
RL2A:   SEP     R4
        DW      DRAIN
        LDI     NAK
        SEP     R4
        DW      TXB
        LBR     RL1
RL3:    LOAD    RD, FAILS       ; a good one
        LDI     0
        STR     RD
        LOAD    RD, BUF
        LDA     RD
        PLO     RC
        LDN     RD
        PHI     RC              ; RC = its number
        ANI     0FFH
        STR     R2
        GLO     RC
        AND
        XRI     0FFH
        LBNZ    RL4
        SEP     R4
        DW      FAIL
        DB      'Stopped on the PC/Mac/Linux.',0
RL4:    LOAD    RD, EXP+1       ; the one expected?
        GLO     RC
        STR     R2
        LDN     RD
        SM
        PLO     RF
        DEC     RD
        GHI     RC
        STR     R2
        LDN     RD
        SMB
        PHI     RF              ; RF = EXP - its number
        LBNZ    RL5
        GLO     RF
        LBZ     RL6
        XRI     1
        LBNZ    RL5
        LDI     ACK             ; the one before, again (its ACK was lost)
        SEP     R4
        DW      TXB
        LBR     RL1
RL5:    SEP     R4
        DW      FAIL
        DB      'Out of step with the PC/Mac/Linux.',0
RL6:    LOAD    RD, EXP         ; block 0: the size
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    RL7
        LOAD    RD, SIZE        ; (big-endian, from little-endian)
        LOAD    RC, BUF+5
        LDI     4
        PLO     RB
RL6A:   LDN     RC
        STR     RD
        INC     RD
        DEC     RC
        DEC     RB
        GLO     RB
        LBNZ    RL6A
        SEP     R4
        DW      NBCALC
        LBNF    RL8
        SEP     R4
        DW      FAIL
        DB      'Too big (32 MB at most).',0
RL7:    SEP     R4              ; a block of the file
        DW      WRBLK
        LBNF    RL8
        XRI     2
        LBNZ    RL7A
        SEP     R4
        DW      FAIL
        DB      'The card is full.',0
RL7A:   SEP     R4
        DW      FAIL
        DB      'The card did not answer.',0
RL8:    SEP     R4              ; the last? then the entry
        DW      ATEND
        LBDF    RFIN
        SEP     R4
        DW      EXPINC
        LDI     ACK
        SEP     R4
        DW      TXB
        LBR     RL1

; WRBLK: BUF+2's 512 bytes as the file's next sector (a new cluster when this one is full). DF = 1 + D:
;        2 the card is full, 3 the card failed
WRBLK:  LOAD    RD, WSLEFT
        LDN     RD
        LBNZ    WB4
        SEP     R4              ; a cluster for the next part
        DW      KS_FREECL
        LBDF    WBFULL
        LOAD    RD, NEWC
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    R9, 0FFFFH      ; it ends the chain ...
        SEP     R4
        DW      KS_FATPUT
        LBDF    WBERR
        LOAD    RD, WPREV       ; ... and the last one points at it (or it is the first)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, NEWC
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        GHI     RC
        LBNZ    WB2
        GLO     RC
        LBNZ    WB2
        LOAD    RD, WFIRST
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LBR     WB3
WB2:    SEP     R4
        DW      KS_FATPUT
        LBDF    WBERR
WB3:    LOAD    RD, NEWC        ; WPREV = it; WLBA = its first sector, WSLEFT = its sectors
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, WPREV
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      KS_CL2LBA
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_ST32
        LOAD    RD, KS_SPC
        LDN     RD
        PLO     RB
        LOAD    RD, WSLEFT
        GLO     RB
        STR     RD
WB4:    LOAD    RD, WLBA        ; the sector
        SEP     R4
        DW      KS_LD32
        LOAD    RF, BUF+2
        SEP     R4
        DW      KS_IDEWR
        LBDF    WBERR
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_LD32
        LOAD    RC, 1
        SEP     R4
        DW      KS_ADD16
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_ST32
        LOAD    RD, WSLEFT
        LDN     RD
        SMI     1
        STR     RD
        LDI     0
        SHR
        SEP     R5
WBFULL: LDI     2
        LSKP
WBERR:  LDI     3
        SMI     0               ; DF = 1, D kept
        SEP     R5

; RFIN: all of it on the card: the FAT, the entry (the switch), then the old file's clusters; ACK
RFIN:   SEP     R4
        DW      KS_FATFLUSH
        LBDF    RF9
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRRD
        LBDF    RF9
        SEP     R4
        DW      KS_STAMP
        LOAD    RD, EPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, KS_FNAME    ; 0-10 the name
        LDI     11
        PLO     RB
RF1:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    RF1
        LDI     20H             ; 11 archive; 12, 13
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 14-17 created
        DW      KS_PUTST
        LOAD    RD, KS_STD      ; 18-19 used
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LDI     0               ; 20-21
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 22-25 written
        DW      KS_PUTST
        LOAD    RD, WFIRST      ; 26-27 the first cluster, 28-31 the size (little-endian)
        LDA     RD
        PHI     RC
        LDN     RD
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        LOAD    RD, SIZE+3
        LDI     4
        PLO     RB
RF2:    LDN     RD
        STR     RF
        INC     RF
        DEC     RD
        DEC     RB
        GLO     RB
        LBNZ    RF2
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    RF9
        LOAD    RD, WFIRST      ; it is saved: nothing to give back now
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, REPL        ; the old file's clusters
        LDN     RD
        LBZ     RF3
        LOAD    RD, OLDCL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_FREECH
RF3:    LDI     ACK
        SEP     R4
        DW      TXB
        SEP     R4
        DW      K_PCRLF
        SEP     R4
        DW      K_PIN
        DB      'Saved ',0
        SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      PSIZE
        LBR     K_MAIN
RF9:    SEP     R4
        DW      FAIL
        DB      'The card did not answer.',0

; ==== XFER -S name: the card to the Mac
SMAIN:  SEP     R4              ; the file (or a message, and back to the prompt) - as TYPE: not NAMEARG, FINDN
        DW      KS_MNTCHK       ;  finds hidden files too (cardfiles.py backs them up)
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_NOFILE
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    KS_ISDIR
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, SIZE
        LOAD    RC, KS_DSIZE
        LDI     4
        PLO     RB
SM1:    LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    SM1
        SEP     R4
        DW      NBCALC
        LBNF    SM2
        SEP     R4
        DW      K_PIN
        DB      'Too big for XFER (32 MB at most).',0DH,0AH,0
        LBR     K_MAIN
SM2:    LOAD    RD, BUF+2       ; block 0: the size, little-endian, then 0s
        LOAD    RB, 512
SM3:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    SM3
        GHI     RB
        LBNZ    SM3
        LOAD    RD, BUF+2
        LOAD    RC, SIZE+3
        LDI     4
        PLO     RB
SM4:    LDN     RC
        STR     RD
        INC     RD
        DEC     RC
        DEC     RB
        GLO     RB
        LBNZ    SM4
        SEP     R4
        DW      WAITG
        LOAD    RA, BUF+2
; frame EXP out (from RA), until the Mac ACKs it
SL1:    LOAD    RD, SPTR
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
SL2:    LOAD    RD, SPTR
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      TXFR
        LDI     7               ; its answer: within ~3 s
        SEP     R4
        DW      WAITRX
        LBNF    SL4
        SEP     R4
        DW      GETRX
        XRI     ACK
        LBZ     SL5
        XRI     ACK XOR CAN
        LBNZ    SL4
        SEP     R4              ; (FAIL sends a CAN back)
        DW      FAIL
        DB      'Stopped on the PC/Mac/Linux.',0
SL4:    LOAD    RD, FAILS       ; NAK, nothing, or noise: again, 10 times at most
        LDN     RD
        ADI     1
        STR     RD
        SMI     10
        LBNF    SL2
        SEP     R4
        DW      FAIL
        DB      'No answer from the PC/Mac/Linux.',0
SL5:    LOAD    RD, FAILS
        LDI     0
        STR     RD
        SEP     R4              ; the last? done
        DW      ATEND
        LBDF    SL9
        SEP     R4
        DW      EXPINC
        SEP     R4              ; the next sector, its tail 0s
        DW      KS_FREAD
        LBNF    SL6
        SEP     R4
        DW      FAIL
        DB      'The card did not answer.',0
SL6:    LOAD    RF, KS_DATBUF
        GLO     RC
        STR     R2
        GLO     RF
        ADD
        PLO     RF
        GHI     RC
        STR     R2
        GHI     RF
        ADC
        PHI     RF              ; RF = DATBUF + its bytes
SL7:    GLO     RF
        LBNZ    SL8
        GHI     RF
        XRI     HIGH(KS_DATBUF + 512)
        LBZ     SL8A
SL8:    LDI     0
        STR     RF
        INC     RF
        LBR     SL7
SL8A:   LOAD    RA, KS_DATBUF
        LBR     SL1
SL9:    SEP     R4
        DW      K_PCRLF
        SEP     R4
        DW      K_PIN
        DB      'Sent ',0
        SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      PSIZE
        LBR     K_MAIN

USE:    SEP     R4
        DW      K_PIN
        DB      'XFER -R name  (the PC/Mac/Linux to the card: elfser.py put FILE NAME)',0DH,0AH
        DB      'XFER -S name  (the card to the PC/Mac/Linux: elfser.py pull NAME FILE)',0DH,0AH,0
        LBR     K_MAIN
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        LBR     K_MAIN
PEND:
MODE:   DS      1               ; MODE .. WSLEFT: 0 at the start
REPL:   DS      1               ; 1: replacing a file
FAILS:  DS      1               ; bad frames in a row
EXP:    DS      2               ; the block expected / being sent (big-endian)
NBLK:   DS      2               ; the file's blocks
SIZE:   DS      4               ; its bytes (big-endian)
ESEC:   DS      2               ; ESEC, EPTR: in this order - its directory entry's sector, where in DIRBUF
EPTR:   DS      2
OLDCL:  DS      2               ; the old file's first cluster
WFIRST: DS      2               ; the new chain: its first cluster (0: none, or saved), its last, a new one
WPREV:  DS      2
NEWC:   DS      2
WLBA:   DS      4               ; the next sector
WSLEFT: DS      1               ; sectors left in this cluster
VEND:
MSGP:   DS      2
SPTR:   DS      2
BUF:    DS      FRLEN
        END
