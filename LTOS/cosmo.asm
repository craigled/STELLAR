; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cosmo.asm - COSMO.PRG: COSMO KID, a platform game in 1802 code, on the VT100 alone (characters, positioning,
;   reverse video) with Q for sound. Cosmo (o over A: 2 rows) walks, jumps 5 rows, lands on bricks (#) and
;   platforms (=), collects coins ($), stomps Blorbs (&) from above - touching one from the side, falling in a
;   pit or onto spikes (^) costs a life - and reaches the portal ( ) at the end of each world. Two worlds of
;   three screens (cosmo_gen.py -> out/cosmolvl.inc); a screen is changed when Cosmo walks off its right edge.
;   Keys: arrows or A / D move, Up, W or Space jump, Esc quits. Only the UART and Q: any kernel.
;
; Each frame: the keys queued while it waited (POLL: the UART holds one byte, so it is read all the time - while
; waiting, while a sound plays, while a byte waits to go out), Cosmo moved, the Blorbs every other frame, then
; only the cells that changed sent. A screen is 22 rows x 79 (rows 2-23; row 1 the score, row 24 the keys).
        CPU     1802
        INCL    "ltos.inc"

ESC     EQU     1BH
ROWS    EQU     22
COLS    EQU     79
MAXEN   EQU     8               ; Blorbs on a screen at most
ENSZ    EQU     5               ; each: alive, row, col, direction (1 / FF), the column it was drawn at
WAITN   EQU     220             ; the wait a frame (POLL rounds): about 40 ms
JTOP    EQU     5               ; rows a jump rises

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  LOAD    RD, KQH         ; the key queue empty
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        REQ
TITLE:  LOAD    RA, TITLES
        SEP     R4
        DW      PUTS
TI1:    SEP     R4              ; a key: Esc alone leaves, anything else plays
        DW      GETK
        LBNF    TI1
        GLO     RC
        XRI     ESC
        LBNZ    NEWGAME
        SEP     R4              ; Esc: more straight after it is an arrow (play)
        DW      ESCALONE
        LBDF    QUIT
NEWGAME: LOAD   RD, LIVES       ; 3 lives, nothing scored, world 1
        LDI     3
        STR     RD
        LOAD    RD, SCORE
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, COINS
        LDI     0
        STR     RD
        LOAD    RD, WORLD
        LDI     0
        STR     RD
NEWWLD: LOAD    RD, ROOMN       ; a world from its first screen: Cosmo where S is
        LDI     0
        STR     RD
        SEP     R4
        DW      DECODE
        LOAD    RD, SPR
        LDA     RD
        PLO     R7
        LDN     RD
        PHI     R7
        LOAD    RD, PR
        GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
ENTER:  LOAD    RD, PR          ; where this screen was entered: where a life starts again
        LDA     RD
        PLO     R7
        LDN     RD
        PHI     R7
        LOAD    RD, ENTR
        GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
FRESH:  LOAD    RD, JT          ; standing still, falling if nothing is under him
        LDI     0
        STR     RD
        LOAD    RD, RUNT
        LDI     0
        STR     RD
        LOAD    RD, ES
        LDI     0
        STR     RD
        LOAD    RD, ONG
        LDI     0
        STR     RD
        LOAD    RD, PF
        LDI     'A'
        STR     RD
        SEP     R4
        DW      DRAWALL
        LBR     FRAME

; ---- one frame
FRAME:  LOAD    RD, PR          ; where Cosmo and the Blorbs are drawn now (to erase them after)
        LDA     RD
        PLO     R7
        LDA     RD
        PHI     R7
        LDN     RD              ; PF
        PLO     R8
        LOAD    RD, OPR
        GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        LOAD    RD, MOVED
        LDI     0
        STR     RD
        LOAD    RD, FNUM
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4              ; the keys
        DW      KEYS
        LBDF    QUIT
; ---- across: one column a frame while RUNT lasts
        LOAD    RD, RUNT
        LDN     RD
        LBZ     VERT
        SMI     1
        STR     RD
        LOAD    RD, PR
        LDA     RD
        PLO     R8              ; R8.0 = row
        LDN     RD
        STR     R2
        LOAD    RD, DIR
        LDN     RD
        ADD
        PHI     R8              ; R8.1 = the new column
        LBZ     VERT            ; (0: the left wall)
        XRI     COLS + 1
        LBNZ    AC1
        LOAD    RD, ROOMN       ; off the right edge: the next screen, if there is one
        LDN     RD
        XRI     NROOMS - 1
        LBZ     VERT
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      DECODE
        LOAD    RD, PC          ; in at the left, on the same row - up until there is room for him
        LDI     1
        STR     RD
ENT1:   LOAD    RD, PR
        LDN     RD
        PLO     R8
        LDI     1
        PHI     R8
        SEP     R4
        DW      FREE2
        LBDF    ENTER
        LOAD    RD, PR
        LDN     RD
        SMI     1
        STR     RD
        LBR     ENT1
AC1:    SEP     R4              ; room for his head and his feet there?
        DW      FREE2
        LBNF    VERT
        LOAD    RD, PC
        GHI     R8
        STR     RD
        LOAD    RD, MOVED
        LDI     1
        STR     RD
        LOAD    RD, WALK        ; his legs: A and H in turn
        LDN     RD
        XRI     1
        STR     RD
; ---- up and down: a jump rises JTOP rows (JT counts them), hangs a frame, then he falls a row a frame
VERT:   LOAD    RD, DOWN
        LDI     0
        STR     RD
        LOAD    RD, JT
        LDN     RD
        LBZ     FALL
        ADI     1               ; JT 2 .. JTOP + 1: rising; JTOP + 2: the hanging frame; then falling
        STR     RD
        SMI     JTOP + 2
        LBNF    RISE
        LBZ     SIDES
        LBR     JEND
RISE:   LOAD    RD, PR          ; up a row: the head's new row (row - 2) free? and not off the top
        LDN     RD
        SMI     2
        LBNF    JEND
        PLO     R8
        LOAD    RD, PC
        LDN     RD
        PHI     R8
        SEP     R4
        DW      SOLIDAT
        LBDF    JBONK
        LOAD    RD, PR
        LDN     RD
        SMI     1
        STR     RD
        LOAD    RD, MOVED
        LDI     1
        STR     RD
        LBR     SIDES
JBONK:  SEP     R4              ; his head on a brick: a knock, and down
        DW      SNDBONK
JEND:   LOAD    RD, JT
        LDI     0
        STR     RD
        LBR     SIDES
FALL:   LOAD    RD, PR          ; something under his feet? standing: else down a row
        LDN     RD
        ADI     1
        PLO     R8
        LOAD    RD, PC
        LDN     RD
        PHI     R8
        SEP     R4
        DW      SOLIDAT
        LBDF    STAND
        LOAD    RD, ONG
        LDI     0
        STR     RD
        LOAD    RD, PR
        LDN     RD
        ADI     1
        STR     RD
        SMI     ROWS            ; below the screen: a pit
        LBDF    DIE
        LOAD    RD, DOWN
        LDI     1
        STR     RD
        LBR     SIDES
STAND:  LOAD    RD, ONG
        LDI     1
        STR     RD
; ---- what his head and feet are in: a coin, spikes, the portal
SIDES:  LOAD    RD, PR
        LDN     RD
        PLO     R8
        LOAD    RD, PC
        LDN     RD
        PHI     R8
        SEP     R4
        DW      TOUCH           ; his feet
        LBDF    EVENT
        LOAD    RD, PR          ; his head (R8 again: a coin's sound uses it)
        LDN     RD
        SMI     1
        PLO     R8
        LOAD    RD, PC
        LDN     RD
        PHI     R8
        SEP     R4
        DW      TOUCH
        LBDF    EVENT
        LBR     BLORBS
EVENT:  XRI     1               ; D: 1 spikes, 2 the portal
        LBZ     DIE
        LBR     WINW
; ---- the Blorbs: each a column every other frame, turning at a wall, the edge of a ledge or the screen's edge
BLORBS: LOAD    RD, FNUM
        LDN     RD
        SHR
        LBNF    MEET
        LOAD    R9, ENS
        LDI     MAXEN
        PLO     RB
BL1:    LDN     R9              ; alive?
        LBZ     BL9
        INC     R9
        LDA     R9
        PLO     R8              ; row
        LDA     R9              ; col
        STR     R2
        LDN     R9              ; direction
        ADD
        PHI     R8              ; the column it would go to
        LBZ     BLTURN
        XRI     COLS + 1
        LBZ     BLTURN
        SEP     R4
        DW      SOLIDAT         ; a wall?
        LBDF    BLTURN
        INC     R8              ; the edge? (nothing under it there)
        SEP     R4
        DW      SOLIDAT
        LBNF    BLT1
        DEC     R8
        DEC     R9              ; on: its column
        GHI     R8
        STR     R9
        INC     R9
        LBR     BL8
BLT1:   DEC     R8
BLTURN: LDN     R9              ; turn round
        SDI     0
        STR     R9
BL8:    DEC     R9
        DEC     R9
        DEC     R9
BL9:    GLO     R9              ; the next
        ADI     ENSZ
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        DEC     RB
        GLO     RB
        LBNZ    BL1
; ---- Cosmo and the Blorbs: from above (he came down onto it) a stomp; else it hurts
MEET:   LOAD    R9, ENS
        LDI     MAXEN
        PLO     RB
ME1:    LDN     R9
        LBZ     ME9
        INC     R9
        INC     R9
        LDN     R9              ; its column = his? (or where it was drawn: they may have just passed each other)
        STR     R2
        LOAD    RD, PC
        LDN     RD
        XOR
        LBZ     ME1A
        INC     R9
        INC     R9
        LDN     R9
        DEC     R9
        DEC     R9
        STR     R2
        LDN     RD
        XOR
ME1A:   DEC     R9
        LBNZ    ME8
        LDN     R9              ; its row: his feet's, or his head's?
        STR     R2
        LOAD    RD, PR
        LDN     RD
        XOR
        LBZ     ME2
        LDN     RD
        SMI     1
        XOR
        LBNZ    ME8
        DEC     R9              ; his head: hurt
        LBR     DIE
ME2:    LOAD    RD, DOWN        ; his feet: a stomp if he came down onto it
        LDN     RD
        DEC     R9
        LBZ     DIE
        LDI     0               ; squashed
        STR     R9
        INC     R9
        LDN     R9
        PLO     R8
        INC     R9
        LDN     R9
        PHI     R8
        DEC     R9
        DEC     R9
        SEP     R4
        DW      DRAWAT          ; the map where it was
        LOAD    RD, SCORE       ; 100 points
        INC     RD
        LDN     RD
        ADI     100
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, JT          ; a bounce
        LDI     JTOP - 2
        STR     RD
        SEP     R4              ; (one stomp a frame: the sound and STATUS use this loop's registers)
        DW      SNDSTOMP
        SEP     R4
        DW      STATUS
        LBR     MEETX
ME8:    DEC     R9
ME9:    GLO     R9
        ADI     ENSZ
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        DEC     RB
        GLO     RB
        LBNZ    ME1
; ---- what changed, drawn: the Blorbs, then Cosmo (on top)
MEETX:  SEP     R4
        DW      DRAWEN
        LOAD    RD, PF          ; his legs: Y in the air, else A / H as he walks
        LOAD    RF, ONG
        LDN     RF
        LBNZ    DR1
        LDI     'Y'
        LBR     DR3
DR1:    LOAD    RF, WALK
        LDN     RF
        LBZ     DR2
        LDI     'H'
        LBR     DR3
DR2:    LDI     'A'
DR3:    STR     RD
        SEP     R4
        DW      DRAWME
        SEP     R4              ; the rest of the frame: waiting (and catching keys)
        DW      WAIT
        LBR     FRAME

; ---- a life lost: a falling tone; again from where this screen was entered (its Blorbs back), or game over
DIE:    SEP     R4
        DW      SNDDIE
        LOAD    RD, LIVES
        LDN     RD
        SMI     1
        STR     RD
        LBZ     OVER
        SEP     R4
        DW      DECODE
        LOAD    RD, ENTR
        LDA     RD
        PLO     R7
        LDN     RD
        PHI     R7
        LOAD    RD, PR
        GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        LBR     FRESH
OVER:   SEP     R4
        DW      STATUS
        LOAD    RA, OVERS
        SEP     R4
        DW      PUTS
        LBR     ANYKEY
; ---- the portal: a fanfare; the next world, or the end
WINW:   SEP     R4
        DW      SNDWIN
        LOAD    RD, SCORE       ; 500 points
        INC     RD
        LDN     RD
        ADI     LOW(500)
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    HIGH(500)
        STR     RD
        LOAD    RD, WORLD
        LDN     RD
        ADI     1
        STR     RD
        XRI     NWORLD
        LBNZ    NEWWLD
        SEP     R4
        DW      STATUS
        LOAD    RA, WONS
        SEP     R4
        DW      PUTS
ANYKEY: SEP     R4              ; (a second first: keys still coming are not taken)
        DW      WAIT
        SEP     R4
        DW      WAIT
        SEP     R4
        DW      WAIT
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

; ==== the screen
; DECODE: this world's screen ROOMN unpacked into MAP; B: a Blorb (in ENS), S: where Cosmo starts (SPR)
DECODE: LOAD    RD, ENS         ; no Blorbs
        LDI     MAXEN * ENSZ
        PLO     RB
DC0:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    DC0
        LOAD    RD, NEN
        LDI     0
        STR     RD
        LOAD    RD, WORLD       ; RA -> its data: ROOMS[world x NROOMS + room]
        LDN     RD
        PLO     RB
        LDI     0
        PLO     RC
DC1:    GLO     RB
        LBZ     DC2
        GLO     RC
        ADI     NROOMS
        PLO     RC
        DEC     RB
        LBR     DC1
DC2:    LOAD    RD, ROOMN
        LDN     RD
        STR     R2
        GLO     RC
        ADD
        SHL
        ADI     LOW(ROOMS)
        PLO     RD
        LDI     HIGH(ROOMS)
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RF, MAP
        LDI     0               ; R9.0 = row, R9.1 = col (1-79)
        PLO     R9
        LDI     1
        PHI     R9
DC3:    LDA     RA              ; count (0: the end)
        LBZ     DC9
        PLO     RB
        LDA     RA
        PLO     RC              ; RC.0 = the character
DC4:    GLO     RC
        XRI     'B'
        LBZ     DCB
        XRI     'B' XOR 'S'
        LBZ     DCS
        GLO     RC
        LBR     DC5
DCS:    LOAD    RD, SPR         ; Cosmo's start
        GLO     R9
        STR     RD
        INC     RD
        GHI     R9
        STR     RD
        LDI     ' '
        LBR     DC5
DCB:    LOAD    RD, NEN         ; a Blorb: [1, row, col, 1, col]
        LDN     RD
        SMI     MAXEN
        LBDF    DCB9
        LDN     RD
        ADI     1
        STR     RD
        SMI     1
        PLO     R7              ; its number x ENSZ
        SHL
        SHL
        STR     R2
        GLO     R7
        ADD
        ADI     LOW(ENS)
        PLO     RD
        LDI     HIGH(ENS)
        ADCI    0
        PHI     RD
        LDI     1
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        INC     RD
        GHI     R9
        STR     RD
        INC     RD
        LDI     0FFH            ; (it starts walking left)
        STR     RD
        INC     RD
        GHI     R9
        STR     RD
DCB9:   LDI     ' '
DC5:    STR     RF
        INC     RF
        GHI     R9              ; the next column (and row)
        ADI     1
        PHI     R9
        XRI     COLS + 1
        LBNZ    DC6
        LDI     1
        PHI     R9
        INC     R9
DC6:    DEC     RB
        GLO     RB
        LBNZ    DC4
        LBR     DC3
DC9:    SEP     R5

; CELL: the character at row R8.0 (0-21), col R8.1 (1-79) -> D; off the screen: above it nothing (' '), below it
;   nothing (a pit), left of col 1 or right of 79 a wall ('#'). RF -> it (on the screen). R8 kept.
CELL:   GLO     R8
        SMI     ROWS
        LBDF    CE8
        GHI     R8
        LBZ     CE7
        SMI     COLS + 1
        LBDF    CE7
        GLO     R8              ; RF = MAP + row x 79 + col - 1 (ROWTAB)
        SHL
        ADI     LOW(ROWTAB)
        PLO     RF
        LDI     HIGH(ROWTAB)
        ADCI    0
        PHI     RF
        LDA     RF
        PLO     RD
        LDN     RF
        STR     R2
        GHI     R8
        SMI     1
        ADD
        PLO     RF
        GLO     RD
        ADCI    0
        PHI     RF
        LDN     RF
        SEP     R5
CE7:    LDI     '#'
        SEP     R5
CE8:    LDI     ' '
        SEP     R5
; SOLIDAT: DF = 1 if the cell at R8 is solid (# or =)
SOLIDAT: SEP    R4
        DW      CELL
        XRI     '#'
        LBZ     SO1
        XRI     '#' XOR '='
        LBZ     SO1
        ADI     0               ; DF = 0
        SEP     R5
SO1:    SMI     0               ; DF = 1
        SEP     R5
; FREE2: DF = 1 if Cosmo fits at row R8.0 (his feet), col R8.1: neither cell solid
FREE2:  SEP     R4
        DW      SOLIDAT
        LBDF    FR8
        DEC     R8
        SEP     R4
        DW      SOLIDAT
        INC     R8
        LBDF    FR8
        SMI     0
        SEP     R5
FR8:    ADI     0
        SEP     R5
; TOUCH: what is at R8: a coin is taken (10 points, a blip, gone from the map and the screen); DF = 1 and D = 1
;   spikes, D = 2 the portal; else DF = 0
TOUCH:  SEP     R4
        DW      CELL
        XRI     '$'
        LBZ     TO1
        XRI     '$' XOR '^'
        LBZ     TO2
        XRI     '^' XOR '('
        LBZ     TO3
        XRI     '(' XOR ')'
        LBZ     TO3
        ADI     0
        SEP     R5
TO1:    GLO     R8              ; (on the screen: RF -> it)
        SMI     ROWS
        LBDF    TO9
        LDI     ' '
        STR     RF
        LOAD    RD, COINS
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, SCORE
        INC     RD
        LDN     RD
        ADI     10
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R4
        DW      SNDCOIN
        SEP     R4
        DW      STATUS
TO9:    ADI     0
        SEP     R5
TO2:    LDI     1
        LSKP
TO3:    LDI     2
        PLO     RC
        SMI     0
        GLO     RC
        SEP     R5

; DRAWALL: the whole screen - cleared, the status line, the map (each row to its last character), the keys
DRAWALL: LOAD   RA, CLEARS
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      STATUS
        LDI     0
        PLO     R8
DA1:    LDI     COLS            ; this row's last character that is not a space
        PHI     R8
DA2:    SEP     R4
        DW      CELL
        XRI     ' '
        LBNZ    DA3
        GHI     R8
        SMI     1
        PHI     R8
        LBNZ    DA2
        LBR     DA6             ; (all spaces)
DA3:    GHI     R8
        PLO     R7              ; R7.0 = how many to send
        LDI     1
        PHI     R8
        SEP     R4
        DW      GOTO
DA4:    SEP     R4
        DW      CELL
        SEP     R4
        DW      PUTC
        GHI     R8
        ADI     1
        PHI     R8
        DEC     R7
        GLO     R7
        LBNZ    DA4
DA6:    INC     R8
        GLO     R8
        XRI     ROWS
        LBNZ    DA1
        LOAD    RA, KEYSS
        SEP     R4
        DW      PUTS
        SEP     R4              ; the Blorbs and Cosmo (as not drawn yet)
        DW      DRAWEN0
        LOAD    RD, OPR
        LDI     0FFH            ; (nothing to erase)
        STR     RD
        SEP     R4
        DW      DRAWME
        SEP     R5

; DRAWAT: the map's character at R8 sent there (R8 kept)
DRAWAT: GLO     R8
        SMI     ROWS
        LBDF    DT9
        SEP     R4
        DW      GOTO
        SEP     R4
        DW      CELL
        SEP     R4
        DW      PUTC
DT9:    SEP     R5
; DRAWME: Cosmo erased where he was (OPR, OPC) if he moved, then drawn: o over his legs (PF)
DRAWME: LOAD    RD, OPR
        LDA     RD
        PLO     R8
        XRI     0FFH
        LBZ     DM2
        LDA     RD
        PHI     R8
        LDN     RD              ; OPF
        PLO     R7
        LOAD    RD, PR          ; the same place and legs: nothing to send
        LDA     RD
        STR     R2
        GLO     R8
        XOR
        LBNZ    DM1
        LDA     RD
        STR     R2
        GHI     R8
        XOR
        LBNZ    DM1
        LDN     RD
        STR     R2
        GLO     R7
        XOR
        LBZ     DM9
DM1:    SEP     R4              ; erased: his feet's cell, his head's
        DW      DRAWAT
        DEC     R8
        SEP     R4
        DW      DRAWAT
DM2:    LOAD    RD, PR          ; drawn
        LDA     RD
        PLO     R8
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R7
        SEP     R4
        DW      GOTO
        GLO     R7
        SEP     R4
        DW      PUTC
        DEC     R8
        GLO     R8
        SMI     ROWS
        LBDF    DM9
        SEP     R4
        DW      GOTO
        LDI     'o'
        SEP     R4
        DW      PUTC
DM9:    SEP     R5
; DRAWEN: each Blorb that moved or was squashed: erased where it was drawn, drawn where it is (&).
;   DRAWEN0: every live one drawn (the whole screen just sent)
DRAWEN0: LDI    1
        LSKP
DRAWEN: LDI     0
        PLO     RB              ; RB.0 = 1: all of them
        LOAD    R9, ENS
        LDI     MAXEN
        PHI     RB
DE1:    INC     R9              ; R8 = where it was drawn
        LDA     R9
        PLO     R8
        LDN     R9              ; col now
        PHI     R7
        INC     R9
        INC     R9
        LDN     R9              ; col drawn
        PHI     R8
        DEC     R9
        DEC     R9
        DEC     R9
        DEC     R9
        LDN     R9              ; alive?
        LBNZ    DE3
        GHI     R8              ; dead (or none): its old place, if it was ever drawn
        LBZ     DE9
        INC     R9              ; (marked: not drawn now)
        INC     R9
        INC     R9
        INC     R9
        LDI     0
        STR     R9
        DEC     R9
        DEC     R9
        DEC     R9
        DEC     R9
        SEP     R4
        DW      DRAWAT
        LBR     DE9
DE3:    GLO     RB              ; alive: moved (or all of them)?
        LBNZ    DE4
        GHI     R8
        STR     R2
        GHI     R7
        XOR
        LBZ     DE9
        SEP     R4              ; erased where it was
        DW      DRAWAT
DE4:    GHI     R7              ; drawn where it is
        PHI     R8
        SEP     R4
        DW      GOTO
        LDI     '&'
        SEP     R4
        DW      PUTC
        INC     R9              ; its drawn column = now
        INC     R9
        INC     R9
        INC     R9
        GHI     R7
        STR     R9
        DEC     R9
        DEC     R9
        DEC     R9
        DEC     R9
DE9:    GLO     R9
        ADI     ENSZ
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        GHI     RB
        SMI     1
        PHI     RB
        LBNZ    DE1
        SEP     R5

; STATUS: row 1 in reverse video: COSMO KID, the score, the coins, the lives, the world
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
        LOAD    RD, COINS
        LDN     RD
        PLO     R7
        LDI     0
        PHI     R7
        SEP     R4
        DW      PDEC3
        LOAD    RA, ST3S
        SEP     R4
        DW      PUTS
        LOAD    RD, LIVES
        LDN     RD
        ADI     '0'
        SEP     R4
        DW      PUTC
        LOAD    RA, ST4S
        SEP     R4
        DW      PUTS
        LOAD    RD, WORLD
        LDN     RD
        ADI     '1'
        SEP     R4
        DW      PUTC
        LDI     '-'
        SEP     R4
        DW      PUTC
        LOAD    RD, ROOMN
        LDN     RD
        ADI     '1'
        SEP     R4
        DW      PUTC
        LOAD    RA, ST5S
        SEP     R4
        DW      PUTS
        SEP     R5
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
; KEYS: the queued keys: arrows / A D move (RUNT 3 frames: a held key keeps him going), Up / W / Space jump;
;   DF = 1 Esc alone (quit). An Esc at the end with nothing after it waits a frame for the rest of its arrow.
KEYS:   LOAD    RD, ES          ; an Esc from the last frame, and still nothing after it: quit
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
        LBZ     KJUMP
        XRI     'A' XOR 'C'
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
        XRI     'A'
        LBZ     KLEFT
        XRI     'A' XOR 'D'
        LBZ     KRIGHT
        XRI     'D' XOR 'W'
        LBZ     KJUMP
        GLO     RC
        XRI     ' '
        LBZ     KJUMP
        LBR     KY1
KLEFT:  LDI     0FFH
        LBR     KMOVE
KRIGHT: LDI     1
KMOVE:  PLO     R7              ; (LOAD changes D)
        LOAD    RD, DIR
        GLO     R7
        STR     RD
        LOAD    RD, RUNT
        LDI     3
        STR     RD
        LBR     KY1
KJUMP:  LOAD    RD, ONG         ; only from the ground
        LDN     RD
        LBZ     KY1
        LOAD    RD, JT
        LDN     RD
        LBNZ    KY1
        LDI     1
        STR     RD
        LOAD    RD, ONG
        LDI     0
        STR     RD
        SEP     R4
        DW      SNDJUMP
        LBR     KY1
KY9:    ADI     0
        SEP     R5
; WAIT: the frame's rest, catching keys
WAIT:   LOAD    R7, WAITN
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
SNDJUMP: LDI    60              ; up: 60 to 25
        PLO     R8
        LDI     0F9H            ; -7
        PHI     R8
        LDI     6
        PLO     RB
        LDI     6
        PHI     R9
        LBR     SWEEP
SNDCOIN: LDI    18              ; two high blips
        PLO     R8
        LOAD    R7, 40
        SEP     R4
        DW      TONE
        LDI     12
        PLO     R8
        LOAD    R7, 90
        LBR     TONE
SNDSTOMP: LDI   120             ; a low thump
        PLO     R8
        LOAD    R7, 24
        LBR     TONE
SNDBONK: LDI    90
        PLO     R8
        LOAD    R7, 10
        LBR     TONE
SNDDIE: LDI     40              ; down: 40 to 200
        PLO     R8
        LDI     16
        PHI     R8
        LDI     11
        PLO     RB
        LDI     14
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
        GLO     R7              ; x 4
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
FANF:   DB      60, 30, 48, 38, 40, 45, 30, 60, 40, 30, 30, 120, 0

; ==== words
TITLES: DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l'
        DB      ESC,'[5;28H',ESC,'[7m','                         ',ESC,'[0m'
        DB      ESC,'[6;28H',ESC,'[7m','     C O S M O   K I D   ',ESC,'[0m'
        DB      ESC,'[7;28H',ESC,'[7m','                         ',ESC,'[0m'
        DB      ESC,'[9;22H','A little space kid on the COSMAC 1802.'
        DB      ESC,'[11;16H','Run, jump, collect the coins ($) and stomp the Blorbs (&)'
        DB      ESC,'[12;16H','from above. Mind the pits and the spikes (^). Reach the'
        DB      ESC,'[13;16H','portal ( ) at the end of each world.'
        DB      ESC,'[15;24H','o    Arrows or A / D   move'
        DB      ESC,'[16;24H','A    Up, W or Space   jump'
        DB      ESC,'[17;29H','Esc              quit'
        DB      ESC,'[20;29H','Press any key to play',0
CLEARS: DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l',0
KEYSS:  DB      ESC,'[24;1H',ESC,'[0m','  Arrows / A D move   Up / W / Space jump   Esc quits',0
ST1S:   DB      ESC,'[1;1H',ESC,'[7m',' COSMO KID     SCORE ',0
ST2S:   DB      '     COINS ',0
ST3S:   DB      '     LIVES ',0
ST4S:   DB      '     WORLD ',0
ST5S:   DB      '                          ',ESC,'[0m',0
OVERS:  DB      ESC,'[11;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[12;29H',ESC,'[7m','      GAME  OVER       ',ESC,'[0m'
        DB      ESC,'[13;29H',ESC,'[7m','  a key: the title     ',ESC,'[0m'
        DB      ESC,'[14;29H',ESC,'[7m','                       ',ESC,'[0m',0
WONS:   DB      ESC,'[10;24H',ESC,'[7m','                                 ',ESC,'[0m'
        DB      ESC,'[11;24H',ESC,'[7m','  YOU MADE IT, COSMO! Well done.  ',ESC,'[0m'
        DB      ESC,'[12;24H',ESC,'[7m','  Every world is yours.           ',ESC,'[0m'
        DB      ESC,'[13;24H',ESC,'[7m','  a key: the title                ',ESC,'[0m'
        DB      ESC,'[14;24H',ESC,'[7m','                                 ',ESC,'[0m',0
BYES:   DB      ESC,'[0m',ESC,'[?25h',ESC,'[2J',ESC,'[H',0

ROWTAB: DW      MAP + 0 * COLS, MAP + 1 * COLS, MAP + 2 * COLS, MAP + 3 * COLS, MAP + 4 * COLS, MAP + 5 * COLS
        DW      MAP + 6 * COLS, MAP + 7 * COLS, MAP + 8 * COLS, MAP + 9 * COLS, MAP + 10 * COLS, MAP + 11 * COLS
        DW      MAP + 12 * COLS, MAP + 13 * COLS, MAP + 14 * COLS, MAP + 15 * COLS, MAP + 16 * COLS
        DW      MAP + 17 * COLS, MAP + 18 * COLS, MAP + 19 * COLS, MAP + 20 * COLS, MAP + 21 * COLS
        INCL    "out/cosmolvl.inc"
PEND:
; ---- the variables (each set before it is used)
KQH:    DS      1               ; KQH, KQT: in this order
KQT:    DS      1
KQ:     DS      16
PR:     DS      1               ; PR, PC, PF: in this order (his feet's row, his column, his legs)
PC:     DS      1
PF:     DS      1
OPR:    DS      1               ; OPR, OPC, OPF: where he was drawn (OPR = FF: not drawn)
OPC:    DS      1
OPF:    DS      1
SPR:    DS      2               ; where S is (row, col)
ENTR:   DS      2               ; where this screen was entered (row, col)
JT:     DS      1
ONG:    DS      1
DOWN:   DS      1
MOVED:  DS      1
RUNT:   DS      1
DIR:    DS      1
WALK:   DS      1
ES:     DS      1
FNUM:   DS      1
LIVES:  DS      1
SCORE:  DS      2
COINS:  DS      1
WORLD:  DS      1
ROOMN:  DS      1
NEN:    DS      1
ENS:    DS      MAXEN * ENSZ
MAP:    DS      ROWS * COLS
        END
