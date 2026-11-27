; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; atman_main.inc - AT-MAN's game (atman.asm puts it before the screen, UART and sound routines it shares with
;   COSMO KID). A maze of 21 x 37 cells (atman_gen.py), each cell two columns on the screen (rows 2-22, cols 4-77),
;   the walls reverse-video blocks. AT-MAN (@) eats the dots (.); a power cell (o) scares the Glitches (X -> x) for
;   a while, and a scared one is caught for points; caught by one that is not, a life is lost. The maze cleared:
;   the next level, faster. Every tick: AT-MAN a cell, the Glitches a cell (scared ones every other tick), then only
;   the cells that changed sent.
;
; Directions: 0 up, 1 left, 2 down, 3 right (the order ties are broken in); the reverse of d is d XOR 2.
; A Glitch: [x, y, direction, mode, wait, drawn x, drawn y, scared] - mode 0 in the pen (wait ticks to go),
;   2 out in the maze. Glitch 0 hunts AT-MAN, 1 the cell 4 ahead of him, 2 wanders, 3 hunts him but slowly.

MW      EQU     37
MH      EQU     21
NG      EQU     4
GSZ     EQU     8
DOORX   EQU     18              ; the pen's door; a Glitch leaving appears just above it
OUTY    EQU     7
PENY    EQU     9

START:  LOAD    RD, KQH         ; the key queue empty; Q off; the generator seeded
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, RND
        LDI     0ACH
        STR     RD
        INC     RD
        LDI     0E1H
        STR     RD
        REQ
TITLE:  LOAD    RA, TITLES
        SEP     R4
        DW      PUTS
TI1:    SEP     R4              ; a key: Esc alone leaves, anything else plays (and stirs the generator)
        DW      RANDOM
        SEP     R4
        DW      GETK
        LBNF    TI1
        GLO     RC
        XRI     ESC
        LBNZ    NEWGAME
        SEP     R4
        DW      ESCALONE
        LBDF    QUIT
NEWGAME: LOAD   RD, LIVES
        LDI     3
        STR     RD
        LOAD    RD, SCORE
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, LEVEL
        LDI     1
        STR     RD
NEWLVL: SEP     R4              ; a fresh maze (every dot back)
        DW      SETUP
RESTART: SEP    R4              ; AT-MAN and the Glitches at their starts; the screen
        DW      STARTS
        SEP     R4
        DW      DRAWALL
        LOAD    RA, READYS      ; "READY" for a moment
        SEP     R4
        DW      PUTS
        LDI     6               ; (R9.0: WAIT uses R7)
        PLO     R9
RD1:    SEP     R4
        DW      WAIT
        DEC     R9
        GLO     R9
        LBNZ    RD1
        LOAD    RA, UNREADYS
        SEP     R4
        DW      PUTS

; ---- one tick
TICK:   LOAD    RD, TNUM
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      KEYS
        LBDF    QUIT
        SEP     R4              ; where everyone was drawn, kept (to erase)
        DW      KEEPOLD
; ---- AT-MAN: the turn asked for, if that way is open; then on, if the way ahead is open
        LOAD    RD, ND
        LDN     RD
        XRI     0FFH
        LBZ     DB2
        LDN     RD
        PLO     R9              ; R9.0 = a direction
        LOAD    RD, PX
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        SEP     R4
        DW      STEP            ; R8 one cell that way (the tunnel wraps)
        SEP     R4
        DW      PASSP
        LBNF    DB2
        LOAD    RD, ND
        LDN     RD
        PLO     R7
        LOAD    RD, PD
        GLO     R7
        STR     RD
DB2:    LOAD    RD, PD
        LDN     RD
        XRI     0FFH
        LBZ     GLITCH
        LDN     RD
        PLO     R9
        LOAD    RD, PX
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        SEP     R4
        DW      STEP
        SEP     R4
        DW      PASSP
        LBNF    GLITCH          ; a wall: he waits there
        LOAD    RD, PX
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        SEP     R4              ; what he is on now
        DW      CELL
        XRI     '.'
        LBZ     EATDOT
        XRI     '.' XOR 'o'
        LBNZ    GLITCH
        LDI     ' '             ; a power cell: 50 points; the Glitches out in the maze scared, turned round
        STR     RF
        LDI     50
        SEP     R4
        DW      ADDSC
        SEP     R4
        DW      DOTGONE
        SEP     R4
        DW      SCARE
        SEP     R4
        DW      SNDPOWER
        LBR     GLITCH
EATDOT: LDI     ' '
        STR     RF
        LDI     10
        SEP     R4
        DW      ADDSC
        SEP     R4
        DW      DOTGONE
        SEP     R4
        DW      SNDDOT
; ---- the Glitches
GLITCH: LOAD    RD, SCARET      ; the fright wears off
        LDN     RD
        LBZ     GL0
        SMI     1
        STR     RD
        LBNZ    GL0
        LOAD    R9, GS          ; (over: none scared now)
        LDI     NG
        PLO     RB
GLU:    GLO     R9
        ADI     7
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDI     0
        STR     RF
        GLO     R9
        ADI     GSZ
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        DEC     RB
        GLO     RB
        LBNZ    GLU
GL0:    LOAD    R9, GS
        LDI     0
        PLO     RB              ; RB.0 = which one
GL1:    GLO     RB              ; RA -> it
        SHL
        SHL
        SHL
        ADI     LOW(GS)
        PLO     RA
        LDI     HIGH(GS)
        ADCI    0
        PHI     RA
        SEP     R4
        DW      GMOVE
        GLO     RB
        ADI     1
        PLO     RB
        XRI     NG
        LBNZ    GL1
; ---- met: a scared one caught (200 points, home to the pen), or AT-MAN caught
        SEP     R4
        DW      MEET
        LBDF    CAUGHT
        SEP     R4              ; drawn: what changed
        DW      DRAWMOV
        SEP     R4
        DW      STATUS
        LOAD    RD, DOTS        ; every dot eaten: the next level
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     CLEARED
        SEP     R4
        DW      TWAIT
        LBR     TICK

CAUGHT: SEP     R4              ; a life lost
        DW      DRAWMOV
        SEP     R4
        DW      SNDDIE
        LOAD    RD, LIVES
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    RESTART
        SEP     R4
        DW      STATUS
        LOAD    RA, OVERS
        SEP     R4
        DW      PUTS
        LBR     ANYKEY
CLEARED: SEP    R4              ; a fanfare, the next level (faster)
        DW      SNDWIN
        LOAD    RD, LEVEL
        LDN     RD
        ADI     1
        STR     RD
        LBR     NEWLVL
ANYKEY: SEP     R4              ; (a moment first: keys still coming are not taken)
        DW      TWAIT
        SEP     R4
        DW      TWAIT
        SEP     R4
        DW      TWAIT
        LOAD    RD, KQH
        LDI     0
        STR     RD
        INC     RD
        STR     RD
AK1:    SEP     R4
        DW      GETK
        LBNF    AK1
        GLO     RC
        XRI     ESC
        LBNZ    TITLE
        SEP     R4
        DW      ESCALONE
        LBNF    TITLE
QUIT:   REQ
        LOAD    RA, BYES
        SEP     R4
        DW      PUTS
        SEP     R5

; ==== the maze
; SETUP: GRID = the maze afresh (G and P as corridors), DOTS counted
SETUP:  LOAD    RA, MAZE0
        LOAD    RF, GRID
        LOAD    RC, MW * MH
        LDI     0
        PLO     R7
        PHI     R7              ; R7 = dots
SU1:    LDA     RA
        XRI     'G'
        LBZ     SU2
        XRI     'G' XOR 'P'
        LBZ     SU2
        XRI     'P' XOR '.'
        LBZ     SU3
        XRI     '.' XOR 'o'
        LBNZ    SU4
SU3:    INC     R7
SU4:    DEC     RA
        LDA     RA
        LSKP
SU2:    LDI     ' '
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    SU1
        GHI     RC
        LBNZ    SU1
        LOAD    RD, DOTS
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        SEP     R5
; STARTS: AT-MAN at P, still; the Glitches in the pen, leaving one by one; none scared
STARTS: LOAD    RD, PX
        LDI     18
        STR     RD
        INC     RD
        LDI     19
        STR     RD
        LOAD    RD, PD
        LDI     0FFH
        STR     RD
        LOAD    RD, ND
        LDI     0FFH
        STR     RD
        LOAD    RD, SCARET
        LDI     0
        STR     RD
        LOAD    RD, ES
        LDI     0
        STR     RD
        LOAD    RA, GINIT       ; [x, y, d, mode, wait, drawn x, drawn y, scared] x 4
        LOAD    RF, GS
        LDI     NG * GSZ
        PLO     RB
ST1:    LDA     RA
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    ST1
        LOAD    RD, OPX         ; (nothing drawn yet)
        LDI     0FFH
        STR     RD
        SEP     R5
GINIT:  DB      16, PENY, 0, 0, 2, 16, PENY, 0
        DB      17, PENY, 0, 0, 30, 17, PENY, 0
        DB      19, PENY, 0, 0, 60, 19, PENY, 0
        DB      20, PENY, 0, 0, 90, 20, PENY, 0

; CELL: R8 = (x in R8.1, y in R8.0) -> D = its character, RF -> it (x 0-36, y 0-20)
CELL:   GLO     R8              ; RF = GRID + y x 37 + x
        SHL
        ADI     LOW(ROWT)
        PLO     RF
        LDI     HIGH(ROWT)
        ADCI    0
        PHI     RF
        LDA     RF
        PLO     RD
        LDN     RF
        STR     R2
        GHI     R8
        ADD
        PLO     RF
        GLO     RD
        ADCI    0
        PHI     RF
        LDN     RF
        SEP     R5
; STEP: R8 one cell in direction R9.0 (the tunnel: x past an edge comes in at the other)
STEP:   GLO     R9
        LBZ     SPU
        XRI     1
        LBZ     SPL
        XRI     1 XOR 2
        LBZ     SPD
        GHI     R8              ; right
        ADI     1
        XRI     MW
        LBNZ    SPR1
        PHI     R8
        SEP     R5
SPR1:   XRI     MW
        PHI     R8
        SEP     R5
SPL:    GHI     R8
        LBNZ    SPL1
        LDI     MW
SPL1:   SMI     1
        PHI     R8
        SEP     R5
SPU:    DEC     R8
        SEP     R5
SPD:    INC     R8
        SEP     R5
; PASSP: DF = 1 if AT-MAN may be at R8 (not a wall, not the pen's door). PASSG: a Glitch (not a wall)
PASSP:  SEP     R4
        DW      CELL
        XRI     '#'
        LBZ     PA0
        XRI     '#' XOR '-'
        LBZ     PA0
PA1:    SMI     0
        SEP     R5
PA0:    ADI     0
        SEP     R5
PASSG:  SEP     R4
        DW      CELL
        XRI     '#'
        LBZ     PA0
        XRI     '#' XOR '-'     ; (the door only on the way out: they are put outside it)
        LBZ     PA0
        LBR     PA1

; ADDSC: SCORE + D
ADDSC:  STR     R2
        LOAD    RD, SCORE + 1
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5
; DOTGONE: DOTS - 1
DOTGONE: LOAD   RD, DOTS + 1
        LDN     RD
        SMI     1
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        SEP     R5
; SCARE: every Glitch out in the maze scared, turned round; SCARET = the fright's length (shorter each level)
SCARE:  LOAD    RD, LEVEL
        LDN     RD
        SHL
        SHL
        STR     R2
        LDI     60
        SM
        LBDF    SC0
        LDI     16
SC0:    SMI     16
        LBDF    SC1
        LDI     0
SC1:    ADI     16
        PLO     R7              ; (LOAD changes D)
        LOAD    RD, SCARET
        GLO     R7
        STR     RD
        LOAD    R9, GS
        LDI     NG
        PLO     RB
SC2:    GLO     R9              ; out in the maze?
        ADI     3
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDN     RF
        XRI     2
        LBNZ    SC3
        DEC     RF              ; its direction reversed
        LDN     RF
        XRI     2
        STR     RF
        GLO     R9              ; scared
        ADI     7
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDI     1
        STR     RF
SC3:    GLO     R9
        ADI     GSZ
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        DEC     RB
        GLO     RB
        LBNZ    SC2
        SEP     R5

; GMOVE: the Glitch at RA (RA, RB.0 kept). In the pen: its wait counted down, then out above the door.
;   Out: a cell a tick (scared: every other tick; Glitch 3 skips every fourth), the way to its target - the open
;   ways, not back the way it came, the one nearest the target (scared, or Glitch 2: one at random)
GMOVE:  GLO     RA              ; RA kept on the stack (the routines below use it)
        STXD
        GHI     RA
        STXD
        GLO     RB
        STXD
        INC     RA
        INC     RA
        INC     RA
        LDN     RA              ; mode
        LBNZ    GM2
        INC     RA              ; in the pen: wait
        LDN     RA
        LBZ     GM1
        SMI     1
        STR     RA
        LBR     GM9
GM1:    DEC     RA              ; out: just above the door, going left
        LDI     2
        STR     RA
        DEC     RA
        LDI     1
        STR     RA
        DEC     RA
        LDI     OUTY
        STR     RA
        DEC     RA
        LDI     DOORX
        STR     RA
        LBR     GM9
GM2:    DEC     RA              ; out in the maze: this tick?
        DEC     RA
        DEC     RA
        GLO     RA
        ADI     7
        PLO     RF
        GHI     RA
        ADCI    0
        PHI     RF
        LDN     RF              ; scared: every other tick
        LBZ     GM3
        LOAD    RD, TNUM
        LDN     RD
        ANI     1
        LBZ     GM9
GM3:    GLO     RB              ; Glitch 3: every fourth tick skipped
        XRI     3
        LBNZ    GM4
        LOAD    RD, TNUM
        LDN     RD
        ANI     3
        LBZ     GM9
GM4:    SEP     R4              ; the target: TX, TY (and RANDF: choose at random)
        DW      TARGET
        LDA     RA              ; R8 = where it is; R7.1 = the way it came (reversed: not allowed)
        PHI     R8
        LDA     RA
        PLO     R8
        LDN     RA
        XRI     2
        PHI     R7
        DEC     RA
        DEC     RA
        LDI     0FFH            ; the best so far: none (R7.0 = its direction, BEST = its distance)
        PLO     R7
        LOAD    RD, BEST
        LDI     0FFH
        STR     RD
        LDI     0
        PLO     R9              ; R9.0 = the direction tried
GM5:    GLO     R9              ; not back the way it came
        STR     R2
        GHI     R7
        XOR
        LBZ     GM8
        GHI     R8              ; that cell: open?
        PHI     RC
        GLO     R8
        PLO     RC
        SEP     R4
        DW      STEP
        SEP     R4
        DW      PASSG
        LBNF    GM7
        SEP     R4              ; its distance to the target (random: a random one)
        DW      DIST
        STR     R2
        LOAD    RD, BEST
        LDN     RD
        SM                      ; BEST - this: no borrow and not 0: this one is nearer
        LBNF    GM7
        LBZ     GM7
        LDN     R2
        STR     RD
        GLO     R9
        PLO     R7
GM7:    GHI     RC              ; R8 back
        PHI     R8
        GLO     RC
        PLO     R8
GM8:    INC     R9
        GLO     R9
        XRI     4
        LBNZ    GM5
        GLO     R7              ; none (a dead end): back the way it came
        XRI     0FFH
        LBNZ    GM6
        GHI     R7
        PLO     R7
GM6:    GLO     R7              ; that way: its direction and its new cell
        PLO     R9
        SEP     R4
        DW      STEP
        INC     RA
        INC     RA
        GLO     R9
        STR     RA
        DEC     RA
        GLO     R8
        STR     RA
        DEC     RA
        GHI     R8
        STR     RA
GM9:    IRX                     ; RB.0, RA back
        LDXA
        PLO     RB
        LDXA
        PHI     RA
        LDX
        PLO     RA
        SEP     R5
; TARGET: TX, TY for the Glitch at RA (RB.0 its number); RANDF = 1: it chooses at random (scared, or Glitch 2)
TARGET: LOAD    RD, RANDF
        LDI     0
        STR     RD
        GLO     RA              ; scared?
        ADI     7
        PLO     RF
        GHI     RA
        ADCI    0
        PHI     RF
        LDN     RF
        LBNZ    TG8
        GLO     RB
        XRI     2
        LBZ     TG8
        LOAD    RD, PX          ; AT-MAN (Glitch 1: 4 cells ahead of him, the way he goes)
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        GLO     RB
        XRI     1
        LBNZ    TG5
        LOAD    RD, PD
        LDN     RD
        XRI     0FFH
        LBZ     TG5
        LDN     RD
        PLO     R9
        LDI     4
        PLO     RC
TG4:    SEP     R4
        DW      STEP
        DEC     RC
        GLO     RC
        LBNZ    TG4
TG5:    LOAD    RD, TX
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        SEP     R5
TG8:    LOAD    RD, RANDF
        LDI     1
        STR     RD
        SEP     R5
; DIST: |x - TX| + |y - TY| for R8 (random: a random 0-127) -> D
DIST:   LOAD    RD, RANDF
        LDN     RD
        LBZ     DI1
        SEP     R4
        DW      RANDOM
        ANI     7FH
        SEP     R5
DI1:    LOAD    RD, TX
        SEX     RD              ; (SM: M(RD) - TX, then TY)
        GHI     R8
        SM
        LBDF    DI2
        SDI     0
DI2:    PLO     RE              ; (RE.0: not across a call)
        INC     RD
        GLO     R8
        SM
        LBDF    DI3
        SDI     0
DI3:    SEX     R2
        STR     R2
        GLO     RE
        ADD
        SEP     R5
; RANDOM: the next of a 16-bit shift register -> D (its low byte)
RANDOM: LOAD    RD, RND
        LDN     RD
        SHR
        STR     RD
        INC     RD
        LDN     RD
        SHRC
        STR     RD
        LBNF    RN1
        DEC     RD              ; the bit out was 1: XOR $B4 into the high byte
        LDN     RD
        XRI     0B4H
        STR     RD
        INC     RD
RN1:    LDN     RD
        SEP     R5

; MEET: DF = 1 if a Glitch (not scared) caught AT-MAN; a scared one he meets is caught: 200, home to the pen
;   (on his cell, or the two just passed each other)
MEET:   LOAD    R9, GS
        LDI     NG
        PLO     RB
ME1:    GLO     R9              ; out in the maze?
        ADI     3
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDN     RF
        XRI     2
        LBNZ    ME8
        LDN     R9              ; on his cell?
        STR     R2
        LOAD    RD, PX
        LDA     RD
        XOR
        LBNZ    ME3
        INC     R9
        LDN     R9
        DEC     R9
        STR     R2
        LDN     RD
        XOR
        LBZ     ME5
ME3:    GLO     R9              ; passed each other: it where he was, he where it was
        ADI     5
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDA     RF              ; its drawn x, y = his now?
        STR     R2
        LOAD    RD, PX
        LDA     RD
        XOR
        LBNZ    ME8
        LDN     RF
        STR     R2
        LDN     RD
        XOR
        LBNZ    ME8
        LDN     R9              ; and it now where he was?
        STR     R2
        LOAD    RD, OPX
        LDA     RD
        XOR
        LBNZ    ME8
        INC     R9
        LDN     R9
        DEC     R9
        STR     R2
        LDN     RD
        XOR
        LBNZ    ME8
ME5:    GLO     R9              ; met: scared?
        ADI     7
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDN     RF
        LBNZ    ME6
        SMI     0               ; no: AT-MAN caught
        SEP     R5
ME6:    LDI     0               ; caught: not scared, in the pen, a wait
        STR     RF
        GLO     R9
        ADI     3
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDI     0
        STR     RF
        INC     RF
        LDI     25
        STR     RF
        LDI     DOORX           ; its place in the pen
        STR     R9
        INC     R9
        LDI     PENY
        STR     R9
        DEC     R9
        LDI     200
        SEP     R4
        DW      ADDSC
        GLO     R9              ; (the sound uses R7 R8 R9: kept)
        STXD
        GHI     R9
        STXD
        GLO     RB
        STXD
        SEP     R4
        DW      SNDEAT
        IRX
        LDXA
        PLO     RB
        LDXA
        PHI     R9
        LDX
        PLO     R9
ME8:    GLO     R9
        ADI     GSZ
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        DEC     RB
        GLO     RB
        LBNZ    ME1
        ADI     0
        SEP     R5

; ==== the screen
; KEEPOLD: where AT-MAN and each Glitch are drawn now (OPX OPY; a Glitch's drawn x y), for DRAWMOV to erase
KEEPOLD: LOAD   RD, PX
        LOAD    RF, OPX
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        SEP     R5
; DRAWMOV: the cells left erased (the maze's character there), then the Glitches (X, scared x) and AT-MAN (@)
DRAWMOV: LOAD   RD, OPX         ; AT-MAN's old cell, if he moved
        LDA     RD
        PHI     R8
        XRI     0FFH
        LBZ     DV1
        LDN     RD
        PLO     R8
        LOAD    RD, PX
        LDA     RD
        STR     R2
        GHI     R8
        XOR
        LBNZ    DV0
        LDN     RD
        STR     R2
        GLO     R8
        XOR
        LBZ     DV1
DV0:    SEP     R4
        DW      DRAWAT
DV1:    LOAD    R9, GS          ; each Glitch: its old cell (if it moved, or its look changed), its new
        LDI     NG
        PHI     RB
DV2:    GLO     R9
        ADI     5
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDA     RF              ; drawn x, y
        PHI     R8
        LDN     RF
        PLO     R8
        SEP     R4
        DW      DRAWAT          ; erased (it is drawn again below)
        GLO     R9              ; drawn x, y = now
        ADI     5
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDA     R9
        STR     RF
        PHI     R8
        INC     RF
        LDN     R9
        STR     RF
        PLO     R8
        DEC     R9
        SEP     R4
        DW      GOTOC
        GLO     R9              ; X, or x scared
        ADI     7
        PLO     RF
        GHI     R9
        ADCI    0
        PHI     RF
        LDN     RF
        LBZ     DV3
        LDI     'x'
        LBR     DV4
DV3:    LDI     'X'
DV4:    SEP     R4
        DW      PUTC
        GLO     R9
        ADI     GSZ
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        GHI     RB
        SMI     1
        PHI     RB
        LBNZ    DV2
        LOAD    RD, PX          ; AT-MAN on top
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        SEP     R4
        DW      GOTOC
        LDI     '@'
        LBR     PUTC
; DRAWAT: the maze's character at R8 sent there (R8 kept)
DRAWAT: SEP     R4
        DW      GOTOC
        SEP     R4
        DW      CELL
        LBR     PUTC
; GOTOC: the cursor to the cell at R8 (x R8.1, y R8.0): row y + 2, col 2 x + 4 (R8 kept)
GOTOC:  GHI     R8
        STXD
        SHL
        ADI     4
        PHI     R8
        SEP     R4
        DW      GOTO
        IRX
        LDX
        PHI     R8
        SEP     R5
; DRAWALL: the screen cleared, the status line, the maze (walls in reverse video, a cell 2 columns), the keys
DRAWALL: LOAD   RA, CLEARS
        SEP     R4
        DW      PUTS
        LDI     0
        PLO     R8              ; R8.0 = y
DA1:    LDI     0
        PHI     R8
        SEP     R4
        DW      GOTOC
        LOAD    RD, INREV
        LDI     0
        STR     RD
DA2:    SEP     R4
        DW      CELL
        XRI     '#'
        LBNZ    DA4
        LOAD    RD, INREV       ; a wall: reverse video on (if it is not)
        LDN     RD
        LBNZ    DA3
        LDI     1
        STR     RD
        LOAD    RA, REVS
        SEP     R4
        DW      PUTS
DA3:    LDI     ' '
        SEP     R4
        DW      PUTC
        LDI     ' '
        SEP     R4
        DW      PUTC
        LBR     DA6
DA4:    LOAD    RD, INREV       ; not a wall: reverse video off
        LDN     RD
        LBZ     DA5
        LDI     0
        STR     RD
        LOAD    RA, NORMS
        SEP     R4
        DW      PUTS
DA5:    SEP     R4
        DW      CELL
        SEP     R4
        DW      PUTC
        LDI     ' '
        SEP     R4
        DW      PUTC
DA6:    GHI     R8
        ADI     1
        PHI     R8
        XRI     MW
        LBNZ    DA2
        LOAD    RA, NORMS
        SEP     R4
        DW      PUTS
        INC     R8
        GLO     R8
        XRI     MH
        LBNZ    DA1
        LOAD    RA, KEYSS
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      STATUS
        SEP     R4              ; the Glitches and AT-MAN
        DW      DRAWMOV
        SEP     R5

; STATUS: row 1 in reverse video: AT-MAN, the score, the lives, the level
STATUS: LOAD    RA, ST1S
        SEP     R4
        DW      PUTS
        LOAD    RD, SCORE
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      PDEC5
        LOAD    RA, ST2S
        SEP     R4
        DW      PUTS
        LOAD    RD, LIVES
        LDN     RD
        ADI     '0'
        SEP     R4
        DW      PUTC
        LOAD    RA, ST3S
        SEP     R4
        DW      PUTS
        LOAD    RD, LEVEL
        LDN     RD
        PLO     R7
        LDI     0
        PHI     R7
        SEP     R4
        DW      PDEC3
        LOAD    RA, ST4S
        SEP     R4
        DW      PUTS
        SEP     R5

; KEYS: the queued keys: arrows or W A S D -> ND (the turn wanted); DF = 1 Esc alone (quit)
KEYS:   LOAD    RD, ES          ; an Esc from the last tick, and still nothing after it: quit
        LDN     RD
        XRI     1
        LBNZ    KY1
        LOAD    RD, KQH
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        LBNZ    KY1
        SMI     0
        SEP     R5
KY1:    SEP     R4
        DW      GETK
        LBNF    KY9
        LOAD    RD, ES
        LDN     RD
        LBZ     KY4
        XRI     1
        LBZ     KY3
        LDI     0               ; ES = 2: the arrow's letter
        STR     RD
        GLO     RC
        XRI     'A'
        LBZ     KUP
        XRI     'A' XOR 'B'
        LBZ     KDOWN
        XRI     'B' XOR 'C'
        LBZ     KRIGHT
        XRI     'C' XOR 'D'
        LBZ     KLEFT
        LBR     KY1
KY3:    GLO     RC              ; ES = 1: [ ?
        XRI     '['
        LBNZ    KY3B
        LDI     2
        STR     RD
        LBR     KY1
KY3B:   LDI     0
        STR     RD
        LBR     KY1
KY4:    GLO     RC
        XRI     ESC
        LBNZ    KY5
        LDI     1
        STR     RD
        LBR     KY1
KY5:    GLO     RC
        ANI     0DFH            ; (upper case)
        XRI     'W'
        LBZ     KUP
        XRI     'W' XOR 'A'
        LBZ     KLEFT
        XRI     'A' XOR 'S'
        LBZ     KDOWN
        XRI     'S' XOR 'D'
        LBZ     KRIGHT
        LBR     KY1
KUP:    LDI     0
        LBR     KSET
KLEFT:  LDI     1
        LBR     KSET
KDOWN:  LDI     2
        LBR     KSET
KRIGHT: LDI     3
KSET:   PLO     R7              ; (LOAD changes D)
        LOAD    RD, ND
        GLO     R7
        STR     RD
        LBR     KY1
KY9:    ADI     0
        SEP     R5
; TWAIT: a tick's rest - shorter each level (WAITB - 12 x level, at least WAITM rounds); WAIT: a short one
TWAIT:  LOAD    RD, LEVEL
        LDN     RD
        PLO     R7
        LDI     0
        PHI     R7
        LOAD    RC, WAITB
TW1:    GLO     R7              ; - 12 a level
        LBZ     TW2
        GLO     RC
        SMI     12
        PLO     RC
        GHI     RC
        SMBI    0
        PHI     RC
        DEC     R7
        LBR     TW1
TW2:    GLO     RC              ; at least WAITM
        SMI     LOW(WAITM)
        GHI     RC
        SMBI    HIGH(WAITM)
        LBDF    TW3
        LOAD    RC, WAITM
TW3:    GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        LBR     WA1
WAIT:   LOAD    R7, 120
WA1:    SEP     R4
        DW      POLL
        LDI     8
        PLO     RB
WA2:    DEC     RB
        GLO     RB
        LBNZ    WA2
        DEC     R7
        GLO     R7
        LBNZ    WA1
        GHI     R7
        LBNZ    WA1
        SEP     R5

; ==== the sounds (TONE / SWEEP below): a tick a dot, a siren for a power cell, a chirp for a Glitch caught,
;   a fall when AT-MAN is caught, a fanfare for a cleared maze
SNDDOT: LDI     30
        PLO     R8
        LOAD    R7, 6
        LBR     TONE
SNDPOWER: LDI   70              ; up and down: 70 to 30, 30 to 70
        PLO     R8
        LDI     0F8H
        PHI     R8
        LDI     5
        PLO     RB
        LDI     8
        PHI     R9
        SEP     R4
        DW      SWEEP
        LDI     30
        PLO     R8
        LDI     8
        PHI     R8
        LDI     5
        PLO     RB
        LDI     8
        PHI     R9
        LBR     SWEEP
SNDEAT: LDI     50              ; up: 50 to 15
        PLO     R8
        LDI     0F9H
        PHI     R8
        LDI     5
        PLO     RB
        LDI     12
        PHI     R9
        LBR     SWEEP
SNDDIE: LDI     30              ; down: 30 to 210
        PLO     R8
        LDI     15
        PHI     R8
        LDI     12
        PLO     RB
        LDI     12
        PHI     R9
        LBR     SWEEP
SNDWIN: LOAD    RA, FANF        ; a fanfare: K, half-periods (x 4)
SW1:    LDA     RA
        LBZ     SW9
        PLO     R8
        LDA     RA
        PLO     R7
        LDI     0
        PHI     R7
        GLO     R7
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        GLO     R7
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        SEP     R4
        DW      TONE
        LBR     SW1
SW9:    SEP     R5
FANF:   DB      48, 40, 40, 48, 30, 64, 40, 48, 30, 64, 24, 160, 0

; ==== words
TITLES: DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l'
        DB      ESC,'[5;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[6;29H',ESC,'[7m','     A T - M A N       ',ESC,'[0m'
        DB      ESC,'[7;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[9;20H','A little robot in a maze, on the COSMAC 1802.'
        DB      ESC,'[11;14H','Eat every dot (.) to clear the maze. Four Glitches (X) hunt you;'
        DB      ESC,'[12;14H','a power cell (o) scares them (x) for a while - catch one then'
        DB      ESC,'[13;14H','for 200 points. The tunnel at the sides takes you across.'
        DB      ESC,'[15;27H','@    Arrows or W A S D   steer'
        DB      ESC,'[16;32H','Esc                 quit'
        DB      ESC,'[19;29H','Press any key to play',0
CLEARS: DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l',0
REVS:   DB      ESC,'[7m',0
NORMS:  DB      ESC,'[0m',0
KEYSS:  DB      ESC,'[24;1H',ESC,'[0m','   Arrows / W A S D steer     a power cell (o) scares the Glitches     Esc quits',0
READYS: DB      ESC,'[9;38H',ESC,'[7m','READY!',ESC,'[0m',0       ; (row 7's empty corridor above the pen)
UNREADYS: DB    ESC,'[9;38H','      ',0
ST1S:   DB      ESC,'[1;1H',ESC,'[7m',' AT-MAN          SCORE ',0
ST2S:   DB      '          LIVES ',0
ST3S:   DB      '          LEVEL ',0
ST4S:   DB      '                     ',ESC,'[0m',0
OVERS:  DB      ESC,'[11;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[12;29H',ESC,'[7m','      GAME  OVER       ',ESC,'[0m'
        DB      ESC,'[13;29H',ESC,'[7m','  a key: the title     ',ESC,'[0m'
        DB      ESC,'[14;29H',ESC,'[7m','                       ',ESC,'[0m',0
BYES:   DB      ESC,'[0m',ESC,'[?25h',ESC,'[2J',ESC,'[H',0
