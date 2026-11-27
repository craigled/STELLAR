; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; atman.asm - AT-MAN.PRG: AT-MAN, a maze game in 1802 code on the VT100 alone (characters, positioning, reverse
;   video), with Q for sound. The game: atman_main.inc; the maze: atman_gen.py -> out/atmanmaze.inc; the screen,
;   UART, key queue and sound routines below are COSMO KID's (cosmo.asm), as they are. Only the UART and Q: any
;   kernel. Keys: arrows or W A S D steer, Esc quits.
        CPU     1802
        INCL    "ltos.inc"

ESC     EQU     1BH
WAITB   EQU     420             ; a tick's rest at level 1 (POLL rounds), 12 fewer a level
WAITM   EQU     200             ; ... at least

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
        INCL    "atman_main.inc"

; ==== COSMO KID's routines (cosmo.asm)
; PDEC5 / PDEC3: R7 as 5 / 3 digits (leading zeros)
PDEC5:  LOAD    RA, D10K
        LDI     5
        LBR     PDN
PDEC3:  LOAD    RA, D100
        LDI     3
PDN:    PLO     RB
PD1:    LDA     RA              ; RC = the power of ten
        PHI     RC
        LDA     RA
        PLO     RC
        LDI     '0'
        PHI     RB
PD2:    GLO     RC              ; R7 - RC: no borrow: one more
        STR     R2
        GLO     R7
        SM
        PLO     RD
        GHI     RC
        STR     R2
        GHI     R7
        SMB
        LBNF    PD3
        PHI     R7
        GLO     RD
        PLO     R7
        GHI     RB
        ADI     1
        PHI     RB
        LBR     PD2
PD3:    GHI     RB
        SEP     R4
        DW      PUTC
        DEC     RB
        GLO     RB
        LBNZ    PD1
        SEP     R5
D10K:   DW      10000, 1000
D100:   DW      100, 10, 1

; GOTO: the cursor to screen row R8.0 + 2, col R8.1: ESC [ r ; c H (R8 kept)
GOTO:   LDI     ESC
        SEP     R4
        DW      PUTC
        LDI     '['
        SEP     R4
        DW      PUTC
        GLO     R8
        ADI     2
        SEP     R4
        DW      PNUM
        LDI     ';'
        SEP     R4
        DW      PUTC
        GHI     R8
        SEP     R4
        DW      PNUM
        LDI     'H'
        LBR     PUTC
; PNUM: D (1-99) in decimal, no leading zero. Uses RF (not RE: the BIOS's SCRT keeps D in it on every call)
PNUM:   PLO     RF
        LDI     '0'
        PHI     RF
PN1:    GLO     RF
        SMI     10
        LBNF    PN2
        PLO     RF
        GHI     RF
        ADI     1
        PHI     RF
        LBR     PN1
PN2:    GHI     RF
        XRI     '0'
        LBZ     PN3
        GHI     RF
        SEP     R4
        DW      PUTC
PN3:    GLO     RF
        ADI     '0'
        LBR     PUTC

; ==== the UART: out, in, and the key queue
; PUTS: the bytes at RA to a 0. PUTC: D. While the UART is busy, POLL keeps catching keys.
PUTS:   LDA     RA
        LBZ     PS9
        SEP     R4
        DW      PUTC
        LBR     PUTS
PS9:    SEP     R5
PUTC:   STXD                    ; (the byte kept on the stack: RE is the BIOS's on every call)
PU1:    LDI     15H             ; room for it?
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     20H
        LBNZ    PU2
        SEP     R4
        DW      POLL
        LBR     PU1
PU2:    SEP     R4              ; (a key may be there too)
        DW      POLL
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        IRX                     ; the byte, from the stack, out
        OUT     DATPORT
        DEC     R2
        SEP     R5
; POLL: a byte from the UART, if one has come, put in the queue (16; full: dropped). Uses RD.0 only, and D.
POLL:   LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBNF    PO9
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        STXD                    ; (kept on the stack)
        GHI     RD
        STXD
        GLO     RD
        STXD
        LDI     HIGH(KQT)       ; the tail: room?
        PHI     RD
        LDI     LOW(KQT)
        PLO     RD
        LDN     RD
        ADI     1
        ANI     0FH
        DEC     RD              ; KQH
        SEX     RD
        XOR
        SEX     R2
        LBZ     PO8             ; full
        INC     RD
        LDN     RD              ; KQ + tail = the byte
        ADI     LOW(KQ)
        PLO     RD
        LDI     HIGH(KQ)
        ADCI    0
        PHI     RD
        IRX
        IRX
        IRX
        LDN     R2              ; the byte
        STR     RD
        DEC     R2
        DEC     R2
        DEC     R2
        LDI     HIGH(KQT)
        PHI     RD
        LDI     LOW(KQT)
        PLO     RD
        LDN     RD
        ADI     1
        ANI     0FH
        STR     RD
PO8:    IRX                     ; RD back
        LDXA
        PLO     RD
        LDXA
        PHI     RD
        LDX
PO9:    SEP     R5
; GETK: DF = 1 and RC.0 = the next key (POLL first); DF = 0 none
GETK:   SEP     R4
        DW      POLL
        LOAD    RD, KQH
        LDA     RD              ; head = tail: none
        STR     R2
        LDN     RD
        XOR
        LBZ     GK9
        DEC     RD
        LDN     RD
        ADI     LOW(KQ)
        PLO     RC
        LDI     HIGH(KQ)
        ADCI    0
        PHI     RC
        LDN     RC
        PLO     RC
        LDN     RD
        ADI     1
        ANI     0FH
        STR     RD
        SMI     0
        SEP     R5
GK9:    ADI     0
        SEP     R5
; ESCALONE: after an Esc: DF = 1 if nothing follows it soon (a lone Esc); else the rest of the sequence read
ESCALONE: LDI   60
        PLO     R7
EA1:    SEP     R4
        DW      GETK
        LBDF    EA5
        LDI     40
        PLO     RB
EA2:    DEC     RB
        GLO     RB
        LBNZ    EA2
        DEC     R7
        GLO     R7
        LBNZ    EA1
        SMI     0
        SEP     R5
EA5:    SEP     R4              ; [ and its letter: read and dropped
        DW      GETK
        ADI     0
        SEP     R5
; ==== sound on Q: TONE R7 = half-periods, R8.0 = K (each half-period ~ 20 + 3 K instructions: 187,500 a second
;   at 3 MHz, so K = 20 ~ 1,170 Hz, 60 ~ 470 Hz, 120 ~ 245 Hz). Keys are caught while it plays.
TONE:   BQ      TN1
        SEQ
        LBR     TN2
TN1:    REQ
TN2:    SEP     R4
        DW      POLL
        GLO     R8
        PLO     R9
TN3:    DEC     R9
        GLO     R9
        LBNZ    TN3
        DEC     R7
        GLO     R7
        LBNZ    TONE
        GHI     R7
        LBNZ    TONE
        REQ
        SEP     R5
; SWEEP: from K = R8.0 by R8.1 (signed) a step, RB.0 steps, R9.1 half-periods each
SWEEP:  GHI     R9
        PLO     R7
        LDI     0
        PHI     R7
        GLO     R8              ; (TONE uses R9.0 only)
        STXD
        GHI     R8
        STXD
        SEP     R4
        DW      TONE
        IRX
        LDXA
        PHI     R8
        LDX
        STR     R2
        GHI     R8
        ADD
        PLO     R8
        DEC     RB
        GLO     RB
        LBNZ    SWEEP
        SEP     R5

ROWT:
        DW      GRID + 0 * MW
        DW      GRID + 1 * MW
        DW      GRID + 2 * MW
        DW      GRID + 3 * MW
        DW      GRID + 4 * MW
        DW      GRID + 5 * MW
        DW      GRID + 6 * MW
        DW      GRID + 7 * MW
        DW      GRID + 8 * MW
        DW      GRID + 9 * MW
        DW      GRID + 10 * MW
        DW      GRID + 11 * MW
        DW      GRID + 12 * MW
        DW      GRID + 13 * MW
        DW      GRID + 14 * MW
        DW      GRID + 15 * MW
        DW      GRID + 16 * MW
        DW      GRID + 17 * MW
        DW      GRID + 18 * MW
        DW      GRID + 19 * MW
        DW      GRID + 20 * MW
        INCL    "out/atmanmaze.inc"
PEND:
; ---- the variables (each set before it is used)
KQH:    DS      1               ; KQH, KQT: in this order
KQT:    DS      1
KQ:     DS      16
RND:    DS      2
PX:     DS      1               ; PX, PY: in this order
PY:     DS      1
PD:     DS      1
ND:     DS      1
OPX:    DS      1               ; OPX, OPY: in this order
OPY:    DS      1
SCARET: DS      1
ES:     DS      1
TNUM:   DS      1
LIVES:  DS      1
SCORE:  DS      2
LEVEL:  DS      1
DOTS:   DS      2
TX:     DS      1               ; TX, TY: in this order
TY:     DS      1
RANDF:  DS      1
BEST:   DS      1
INREV:  DS      1
GS:     DS      NG * GSZ
GRID:   DS      MW * MH
        END
