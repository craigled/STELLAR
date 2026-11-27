; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; descend.asm - DESCEND.PRG (was DELVE, renamed 2026-11-22): a dungeon crawl in 1802 code on the VT100 alone, with Q for sound. Turn-based: nothing
;   moves until a key is pressed, so only the few cells that change go down the serial line.
;
;   Each level: nine rooms in a 3 x 3 grid of sectors (26 x 7 cells), joined to their neighbours by corridors
;   (#), doors (+). A room is shown when you step into it; in a corridor, the cells next to you. Walk into a
;   monster to fight it; gold ($), potions (!), weapons ()) and armour ([) are picked up as you go; stairs (>)
;   lead down. On depth 10 the Star Crystal (*) waits. Keys: arrows or W A S D, P a potion, > or Enter the
;   stairs, Space rest, Esc quit. The screen, UART, key queue and sound routines are COSMO KID's / AT-MAN's.
;
;   The map: GRID, MW x MH cells, a cell's bit 7 = seen. Screen row = y + 2, column = x + 2.
;   A room: [x0, y0, x1, y1, lit] (walls inclusive). A monster: [type + 1 (0: none), x, y, hp, awake, drawn,
;   drawn x, drawn y]. Directions: 0 up, 1 left, 2 down, 3 right.
        CPU     1802
        INCL    "ltos.inc"

ESC     EQU     1BH
MW      EQU     78
MH      EQU     21
NR      EQU     9
RSZ     EQU     5
NM      EQU     10
MSZ     EQU     8
LASTD   EQU     10              ; the Star Crystal's depth

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG

START:  LOAD    RD, KQH         ; the key queue empty; Q off; the generator seeded
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, RND
        LDI     5AH
        STR     RD
        INC     RD
        LDI     0C3H
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
NEWGAME: LOAD   RA, INIT0       ; HP 20/20, Atk 3, Def 0, Lv 1, XP 0 (next 10), gold 0, a potion, depth 1
        LOAD    RB, HP
        LDI     13
        PLO     R9
NG1:    LDA     RA
        STR     RB
        INC     RB
        DEC     R9
        GLO     R9
        LBNZ    NG1
        LOAD    RD, TURN        ; TURN, WON
        LDI     0
        STR     RD
        INC     RD
        STR     RD
NEWLVL: SEP     R4
        DW      GENLVL
        SEP     R4
        DW      DRAWLVL
        LOAD    RD, DEPTH       ; below the first: where you are
        LDN     RD
        SMI     1
        LBZ     MAIN
        LOAD    RA, S_DOWN
        SEP     R4
        DW      MSG
        LOAD    RD, NMODE
        LDI     1
        STR     RD
        LOAD    RD, DEPTH
        LDN     RD
        SEP     R4
        DW      NUM8
        LOAD    RA, S_DOT
        SEP     R4
        DW      MSG
        LOAD    RD, DEPTH
        LDN     RD
        XRI     LASTD
        LBNZ    MAIN
        LOAD    RA, S_CRYS
        SEP     R4
        DW      MSG

; ---- a turn: the screen brought up to date, a key, what it does; then the monsters
MAIN:   SEP     R4
        DW      REDRAW
        LOAD    RD, WON
        LDN     RD
        LBNZ    WIN
        LOAD    RD, HP
        LDN     RD
        LBZ     DEATH
        SEP     R4
        DW      GETCMD
        PLO     R7
        LOAD    RD, CMD
        GLO     R7
        STR     RD
        SEP     R4              ; last turn's words cleared
        DW      MSGCLR
        LOAD    RD, CMD
        LDN     RD
        XRI     7
        LBZ     QUIT
        LDN     RD
        SMI     4
        LBNF    DOMV
        LDN     RD
        XRI     4
        LBZ     TURN1           ; rest
        LDN     RD
        XRI     5
        LBZ     DOPOT
        LOAD    RD, PX          ; the stairs: is he on them?
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        SEP     R4
        DW      CELLA
        ANI     7FH
        XRI     '>'
        LBZ     DESCEND
        LOAD    RA, S_NOST
        SEP     R4
        DW      MSG
        LBR     MAIN
DOMV:   LDN     RD
        SEP     R4
        DW      DOMOVE
        LBDF    TURN1
        LBR     MAIN
DOPOT:  SEP     R4
        DW      DRINK
        LBNF    MAIN
TURN1:  LOAD    RD, WON         ; (the crystal taken: no more turns)
        LDN     RD
        LBNZ    MAIN
        SEP     R4
        DW      MONSAI
        SEP     R4
        DW      REGEN
        LBR     MAIN
DESCEND: LOAD   RD, DEPTH
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      SNDDOWN
        LBR     NEWLVL

; ---- the end of a game
DEATH:  SEP     R4
        DW      SNDDIE
        LOAD    RA, DEADS
        SEP     R4
        DW      PUTS
        LOAD    RD, KILLER
        LDN     RD
        SEP     R4
        DW      NAMEP
        SEP     R4
        DW      PUTS
        LOAD    RA, S_ONDEP
        SEP     R4
        DW      PUTS
        LOAD    RD, NMODE
        LDI     0
        STR     RD
        LOAD    RD, DEPTH
        LDN     RD
        SEP     R4
        DW      NUM8
        LDI     '.'
        SEP     R4
        DW      PUTC
        LBR     ENDSC
WIN:    SEP     R4
        DW      SNDWIN
        LOAD    RA, WINS
        SEP     R4
        DW      PUTS
ENDSC:  LOAD    RD, NMODE
        LDI     0
        STR     RD
        LOAD    RA, S_EGOLD
        SEP     R4
        DW      PUTS
        LOAD    RD, GOLDH
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      NUMOUT
        LOAD    RA, S_ESCORE
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      SCORE
        SEP     R4
        DW      NUMOUT
        LOAD    RA, S_EKEY
        SEP     R4
        DW      PUTS
ANYKEY: SEP     R4              ; (a moment first: keys still coming are not taken)
        DW      DELAY
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

; SCORE: R7 = gold + XP + 50 a depth below the first (+ 1000 for the crystal)
SCORE:  LOAD    RD, GOLDH
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LOAD    RD, XPL
        LDN     RD
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        DEC     RD
        LDN     RD
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        LOAD    RD, DEPTH
        LDN     RD
        PLO     R9
SC1:    DEC     R9
        GLO     R9
        LBZ     SC2
        GLO     R7
        ADI     50
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        LBR     SC1
SC2:    LOAD    RD, WON
        LDN     RD
        LBZ     SC3
        GLO     R7
        ADI     LOW(1000)
        PLO     R7
        GHI     R7
        ADCI    HIGH(1000)
        PHI     R7
SC3:    SEP     R5

; ==== the keys
; GETCMD: wait for a key -> D: 0-3 a direction, 4 rest, 5 a potion, 6 the stairs, 7 quit (a lone Esc)
GETCMD: SEP     R4
        DW      GETK
        LBNF    GETCMD
GC0:    GLO     RC
        XRI     ESC
        LBNZ    GC2
        SEP     R4              ; Esc: and then?
        DW      WAITK
        LBNF    GCQ             ; nothing: quit
        GLO     RC
        XRI     '['
        LBZ     GC1
        GLO     RC
        XRI     'O'
        LBZ     GC1
        LBR     GC0             ; another key: taken as itself
GC1:    SEP     R4              ; ESC [ and its letter
        DW      WAITK
        LBNF    GETCMD
        GLO     RC
        XRI     'A'
        LBZ     GCU
        XRI     'A' XOR 'B'
        LBZ     GCD
        XRI     'B' XOR 'C'
        LBZ     GCR
        XRI     'C' XOR 'D'
        LBZ     GCL
        LBR     GETCMD
GC2:    GLO     RC              ; A B C D (capitals) are an arrow's letter whose Esc [ was lost (the UART holds
        XRI     'A'             ;  one byte); w a s d (and W S) are keys
        LBZ     GCU
        XRI     'A' XOR 'w'
        LBZ     GCU
        XRI     'w' XOR 'W'
        LBZ     GCU
        XRI     'W' XOR 'B'
        LBZ     GCD
        XRI     'B' XOR 's'
        LBZ     GCD
        XRI     's' XOR 'S'
        LBZ     GCD
        XRI     'S' XOR 'C'
        LBZ     GCR
        XRI     'C' XOR 'd'
        LBZ     GCR
        XRI     'd' XOR 'D'
        LBZ     GCL
        XRI     'D' XOR 'a'
        LBZ     GCL
        XRI     'a' XOR 'p'
        LBZ     GCP
        XRI     'p' XOR 'P'
        LBZ     GCP
        XRI     'P' XOR ' '
        LBZ     GCZ
        XRI     ' ' XOR '.'
        LBZ     GCZ
        XRI     '.' XOR '>'
        LBZ     GCS
        XRI     '>' XOR 0DH
        LBZ     GCS
        LBR     GETCMD
GCU:    LDI     0
        SEP     R5
GCL:    LDI     1
        SEP     R5
GCD:    LDI     2
        SEP     R5
GCR:    LDI     3
        SEP     R5
GCZ:    LDI     4
        SEP     R5
GCP:    LDI     5
        SEP     R5
GCS:    LDI     6
        SEP     R5
GCQ:    LDI     7
        SEP     R5
; WAITK: a key within ~60 ms? DF = 1 and RC.0 = it; DF = 0 none. Uses R7, RB
WAITK:  LDI     60
        PLO     R7
WK1:    SEP     R4
        DW      GETK
        LBDF    WK9
        LDI     40
        PLO     RB
WK2:    DEC     RB
        GLO     RB
        LBNZ    WK2
        DEC     R7
        GLO     R7
        LBNZ    WK1
        ADI     0
WK9:    SEP     R5
; DELAY: about half a second (keys still caught)
DELAY:  LOAD    R7, 2500
DL1:    SEP     R4
        DW      POLL
        DEC     R7
        GLO     R7
        LBNZ    DL1
        GHI     R7
        LBNZ    DL1
        SEP     R5

; ==== the player's actions
; DOMOVE: D = a direction. A monster that way: fought; open: he steps there (and picks up what is there).
;   DF = 1 if the turn was used
DOMOVE: PLO     R9
        LOAD    RD, PX
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        GLO     R9
        SEP     R4
        DW      DSTEP
        SEP     R4
        DW      MONAT
        LBDF    DMATK
        SEP     R4
        DW      CELLA
        ANI     7FH
        SEP     R4
        DW      WALKABLE
        LBNF    DMNO
        LOAD    RD, PX
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        SEP     R4
        DW      PICKUP
        SMI     0
        SEP     R5
DMATK:  SEP     R4
        DW      PATTACK
        SMI     0
        SEP     R5
DMNO:   ADI     0
        SEP     R5

; PICKUP: what is on R8 (his cell) taken
PICKUP: SEP     R4
        DW      CELLA
        ANI     7FH
        PLO     R9
        XRI     '$'
        LBZ     PKG
        GLO     R9
        XRI     '!'
        LBZ     PKP
        GLO     R9
        XRI     ')'
        LBZ     PKW
        GLO     R9
        XRI     '['
        LBZ     PKA
        GLO     R9
        XRI     '>'
        LBZ     PKS
        GLO     R9
        XRI     '*'
        LBZ     PKC
        SEP     R5
PKG:    LDN     RF              ; gold: 2-9, and 5 more a depth
        ANI     80H
        ORI     '.'
        STR     RF
        LDI     8
        SEP     R4
        DW      RANDN
        ADI     2
        PLO     R7
        LOAD    RD, DEPTH
        LDN     RD
        PLO     R9
PKG1:   GLO     R7
        ADI     5
        PLO     R7
        DEC     R9
        GLO     R9
        LBNZ    PKG1
        LOAD    RD, GOLDL
        GLO     R7
        STR     R2
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LDI     0
        PHI     R7
        LOAD    RA, S_FIND
        SEP     R4
        DW      MSG
        LOAD    RD, NMODE
        LDI     1
        STR     RD
        SEP     R4
        DW      NUMOUT
        LOAD    RA, S_GOLD
        SEP     R4
        DW      MSG
        LBR     SNDGOLD
PKP:    LDN     RF
        ANI     80H
        ORI     '.'
        STR     RF
        LOAD    RD, POTS
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RA, S_POT
        SEP     R4
        DW      MSG
        LBR     SNDGOLD
PKW:    LDN     RF
        ANI     80H
        ORI     '.'
        STR     RF
        LOAD    RD, ATK
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RA, S_WPN
        SEP     R4
        DW      MSG
        LBR     SNDPICK
PKA:    LDN     RF
        ANI     80H
        ORI     '.'
        STR     RF
        LOAD    RD, DEF
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RA, S_ARM
        SEP     R4
        DW      MSG
        LBR     SNDPICK
PKS:    LOAD    RA, S_STAIR
        LBR     MSG
PKC:    LDN     RF
        ANI     80H
        ORI     '.'
        STR     RF
        LOAD    RD, WON
        LDI     1
        STR     RD
        SEP     R5

; DRINK: a potion, if he has one: 10 HP (to his most). DF = 1 if the turn was used
DRINK:  LOAD    RD, POTS
        LDN     RD
        LBZ     DR9
        SMI     1
        STR     RD
        LOAD    RD, MAXHP
        LDN     RD
        PLO     R7
        DEC     RD              ; HP
        LDN     RD
        ADI     10
        STR     R2
        GLO     R7
        SM                      ; most - (HP + 10)
        LBDF    DR1
        GLO     R7              ; over: the most
        STR     R2
DR1:    LDN     R2
        STR     RD
        LOAD    RA, S_DRINK
        SEP     R4
        DW      MSG
        SEP     R4
        DW      SNDPOT
        SMI     0
        SEP     R5
DR9:    LOAD    RA, S_NOPOT
        SEP     R4
        DW      MSG
        ADI     0
        SEP     R5

; REGEN: a turn more; every 8th, 1 HP back (to his most)
REGEN:  LOAD    RD, TURN
        LDN     RD
        ADI     1
        STR     RD
        ANI     7
        LBNZ    RG9
        LOAD    RD, MAXHP
        LDN     RD
        STR     R2
        DEC     RD
        LDN     RD
        SD                      ; most - HP
        LBZ     RG9
        LDN     RD
        ADI     1
        STR     RD
RG9:    SEP     R5

; PATTACK: he fights the monster at RA: 3 times in 4 a hit of 1 + rand(Atk) less its Def (at least 1)
PATTACK: LOAD   RD, MSLOT
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LDN     RA
        SMI     1
        PLO     R7
        LOAD    RD, MT
        GLO     R7
        STR     RD
        LDI     4
        SEP     R4
        DW      RANDN
        LBZ     PAMISS
        LOAD    RD, ATK
        LDN     RD
        SEP     R4
        DW      RANDN
        ADI     1
        PLO     R7
        LOAD    RD, MT
        LDN     RD
        SEP     R4
        DW      MTP
        INC     RC
        INC     RC
        INC     RC
        LDN     RC              ; its Def
        STR     R2
        GLO     R7
        SM
        LBNF    PA1
        LBNZ    PA2
PA1:    LDI     1
PA2:    PLO     R7              ; the damage
        SEP     R4
        DW      LDSLOT
        INC     RA
        INC     RA
        INC     RA
        LDN     RA              ; its HP
        STR     R2
        GLO     R7
        SD                      ; HP - damage
        LBNF    PAKILL
        LBZ     PAKILL
        STR     RA
        LOAD    RA, S_YHIT
        SEP     R4
        DW      MSG
        SEP     R4
        DW      MSGMT
        LOAD    RA, S_DOT
        SEP     R4
        DW      MSG
        LBR     SNDHIT
PAKILL: SEP     R4
        DW      LDSLOT
        LDI     0
        STR     RA
        LOAD    RA, S_YKILL
        SEP     R4
        DW      MSG
        SEP     R4
        DW      MSGMT
        LOAD    RA, S_BANG
        SEP     R4
        DW      MSG
        LOAD    RD, MT          ; its XP
        LDN     RD
        SEP     R4
        DW      MTP
        GLO     RC
        ADI     4
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LDN     RC
        STR     R2
        LOAD    RD, XPL
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R4
        DW      SNDKILL
        LBR     CHKLVL
PAMISS: LOAD    RA, S_YMISS
        SEP     R4
        DW      MSG
        SEP     R4
        DW      MSGMT
        LOAD    RA, S_DOT
        LBR     MSG
LDSLOT: LOAD    RD, MSLOT
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R5
MSGMT:  LOAD    RD, MT          ; its name, in the words
        LDN     RD
        SEP     R4
        DW      NAMEP
        LBR     MSG

; CHKLVL: XP up to the next level: Lv + 1, 5 more HP (and most), Atk + 1, the next twice as far
CHKLVL: LOAD    RA, XPH
        LDA     RA
        PHI     R7
        LDA     RA
        PLO     R7
        LDA     RA
        PHI     R9
        LDN     RA
        PLO     R9
        GLO     R9
        STR     R2
        GLO     R7
        SM
        GHI     R9
        STR     R2
        GHI     R7
        SMB
        LBNF    CL9
        GLO     R9              ; the next: twice
        SHL
        STR     RA
        DEC     RA
        GHI     R9
        SHLC
        STR     RA
        LOAD    RD, HP
        LDN     RD
        ADI     5
        STR     RD
        INC     RD
        LDN     RD
        ADI     5
        STR     RD
        INC     RD
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, PLV
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RA, S_LEVEL
        SEP     R4
        DW      MSG
        LBR     SNDLVL
CL9:    SEP     R5

; ==== the monsters
; MONSAI: each monster in turn. One that he can see wakes (and stays awake); awake, it comes for him the
;   shorter way it can, and fights him when next to him. Slow ones (Z) move every other turn; erratic
;   ones (b) wander half the time.
MONSAI: LOAD    RD, MPTR
        LDI     HIGH(MONS)
        STR     RD
        INC     RD
        LDI     LOW(MONS)
        STR     RD
        LOAD    RD, MCNT
        LDI     NM
        STR     RD
AI1:    LOAD    RD, HP          ; he is dead: no more
        LDN     RD
        LBZ     AI9
        SEP     R4
        DW      LDMP
        LDN     RA
        LBZ     AINX
        SMI     1
        PLO     R7
        LOAD    RD, MT
        GLO     R7
        STR     RD
        INC     RA
        LDA     RA
        PHI     R8
        LDN     RA
        PLO     R8
        LOAD    RD, MX
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        SEP     R4
        DW      VISIBLE
        LBNF    AI2
        SEP     R4
        DW      LDMP
        GLO     RA
        ADI     4
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LDI     1
        STR     RA
AI2:    SEP     R4
        DW      LDMP
        GLO     RA
        ADI     4
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LDN     RA
        LBZ     AINX            ; asleep
        LOAD    RD, MT
        LDN     RD
        SEP     R4
        DW      MTP
        GLO     RC
        ADI     5
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LDN     RC
        PLO     R9              ; its flags
        ANI     1
        LBZ     AI3
        LOAD    RD, TURN
        LDN     RD
        ANI     1
        LBNZ    AINX
AI3:    GLO     R9
        ANI     2
        LBZ     AI4
        LDI     2
        SEP     R4
        DW      RANDN
        LBZ     AI4
        LDI     4
        SEP     R4
        DW      RANDN
        SEP     R4
        DW      MTRY
        LBR     AINX
AI4:    LOAD    RD, MX
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        SEP     R4
        DW      DIST
        LOAD    RD, ADX
        LDA     RD
        STR     R2
        LDN     RD
        ADD
        XRI     1
        LBNZ    AI5
        SEP     R4              ; next to him: it fights
        DW      LDMP
        SEP     R4
        DW      MATTACK
        LBR     AINX
AI5:    LOAD    RD, ADY         ; the longer way first
        LDN     RD
        STR     R2
        DEC     RD
        LDN     RD
        SM
        LBNF    AI6
        LOAD    RD, HD
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LBR     AI7
AI6:    LOAD    RD, HD
        LDA     RD
        PLO     R9
        LDN     RD
        PHI     R9
AI7:    LOAD    RD, TRY2
        GLO     R9
        STR     RD
        GHI     R9
        XRI     0FFH
        LBZ     AI8
        GHI     R9
        SEP     R4
        DW      MTRY
        LBDF    AINX
AI8:    LOAD    RD, TRY2
        LDN     RD
        XRI     0FFH
        LBZ     AINX
        LDN     RD
        SEP     R4
        DW      MTRY
AINX:   LOAD    RD, MPTR + 1
        LDN     RD
        ADI     MSZ
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, MCNT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    AI1
AI9:    SEP     R5
LDMP:   LOAD    RD, MPTR
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R5

; DIST: from R8 (a monster) to him: ADX, ADY = |dx|, |dy|; HD = 3 right / 1 left / FF none, VD = 2 down / 0 up / FF
DIST:   LOAD    RD, PX
        LDN     RD
        STR     R2
        GHI     R8
        SD                      ; px - x
        LBZ     DX0
        LBNF    DXN
        PLO     R7
        LDI     3
        PHI     R7
        LBR     DXS
DXN:    SDI     0
        PLO     R7
        LDI     1
        PHI     R7
        LBR     DXS
DX0:    PLO     R7
        LDI     0FFH
        PHI     R7
DXS:    LOAD    RD, ADX
        GLO     R7
        STR     RD
        LOAD    RD, HD
        GHI     R7
        STR     RD
        LOAD    RD, PY
        LDN     RD
        STR     R2
        GLO     R8
        SD                      ; py - y
        LBZ     DY0
        LBNF    DYN
        PLO     R7
        LDI     2
        PHI     R7
        LBR     DYS
DYN:    SDI     0
        PLO     R7
        LDI     0
        PHI     R7
        LBR     DYS
DY0:    PLO     R7
        LDI     0FFH
        PHI     R7
DYS:    LOAD    RD, ADY
        GLO     R7
        STR     RD
        LOAD    RD, VD
        GHI     R7
        STR     RD
        SEP     R5

; MTRY: the monster at MPTR (at MX, MY) one step in direction D, if that cell is open (not him, not another).
;   DF = 1 if it moved
MTRY:   PLO     R9
        LOAD    RD, MX
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        GLO     R9
        SEP     R4
        DW      DSTEP
        LOAD    RD, PX
        LDA     RD
        STR     R2
        GHI     R8
        XOR
        LBNZ    MY1
        LDN     RD
        STR     R2
        GLO     R8
        XOR
        LBZ     MYNO
MY1:    SEP     R4
        DW      CELLA
        ANI     7FH
        SEP     R4
        DW      WALKABLE
        LBNF    MYNO
        SEP     R4
        DW      MONAT
        LBDF    MYNO
        SEP     R4
        DW      LDMP
        INC     RA
        GHI     R8
        STR     RA
        INC     RA
        GLO     R8
        STR     RA
        SMI     0
        SEP     R5
MYNO:   ADI     0
        SEP     R5

; MATTACK: the monster (type MT) fights him: 3 times in 4 a hit of 1 + rand(its Atk) less his Def (at least 1)
MATTACK: LDI    4
        SEP     R4
        DW      RANDN
        LBZ     MKMISS
        LOAD    RD, MT
        LDN     RD
        SEP     R4
        DW      MTP
        INC     RC
        INC     RC
        LDN     RC              ; its Atk
        SEP     R4
        DW      RANDN
        ADI     1
        PLO     R7
        LOAD    RD, DEF
        LDN     RD
        STR     R2
        GLO     R7
        SM
        LBNF    MK1
        LBNZ    MK2
MK1:    LDI     1
MK2:    PLO     R7
        LOAD    RD, HP
        LDN     RD
        STR     R2
        GLO     R7
        SD                      ; HP - damage
        LBNF    MK3
        LBZ     MK3
        STR     RD
        LBR     MK4
MK3:    LDI     0               ; dead: who did it, kept
        STR     RD
        LOAD    RD, MT
        LDN     RD
        PLO     R7
        LOAD    RD, KILLER
        GLO     R7
        STR     RD
MK4:    LOAD    RA, S_THE
        SEP     R4
        DW      MSG
        SEP     R4
        DW      MSGMT
        LOAD    RA, S_HITS
        SEP     R4
        DW      MSG
        LBR     SNDHURT
MKMISS: LOAD    RA, S_THE
        SEP     R4
        DW      MSG
        SEP     R4
        DW      MSGMT
        LOAD    RA, S_MISSES
        LBR     MSG

; MONAT: a monster at R8? DF = 1 and RA -> it. Uses RA RB RC
MONAT:  LOAD    RA, MONS
        LDI     NM
        PLO     RB
MA1:    LDN     RA
        LBZ     MA3
        GLO     RA
        PLO     RC
        GHI     RA
        PHI     RC
        INC     RC
        LDA     RC
        STR     R2
        GHI     R8
        XOR
        LBNZ    MA3
        LDN     RC
        STR     R2
        GLO     R8
        XOR
        LBNZ    MA3
        SMI     0
        SEP     R5
MA3:    GLO     RA
        ADI     MSZ
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        DEC     RB
        GLO     RB
        LBNZ    MA1
        ADI     0
        SEP     R5

; MTP: D = a monster type -> RC -> its row of MTAB: letter, HP, Atk, Def, XP, flags (1 slow, 2 erratic)
MTP:    PLO     RC
        SHL
        STR     R2
        GLO     RC
        SHL
        SHL
        ADD
        ADI     LOW(MTAB)
        PLO     RC
        LDI     HIGH(MTAB)
        ADCI    0
        PHI     RC
        SEP     R5
; NAMEP: D = a monster type -> RA -> its name
NAMEP:  SHL
        ADI     LOW(NAMET)
        PLO     RA
        LDI     HIGH(NAMET)
        ADCI    0
        PHI     RA
        LDA     RA
        PHI     RC
        LDN     RA
        PLO     RA
        GHI     RC
        PHI     RA
        SEP     R5

; ==== the map
; CELLA: R8 = (x in R8.1, y in R8.0) -> RF -> its cell, D = it (bit 7: seen)
CELLA:  GLO     R8
        SHL
        ADI     LOW(ROWT)
        PLO     RF
        LDI     HIGH(ROWT)
        ADCI    0
        PHI     RF
        LDA     RF
        STXD
        LDN     RF
        STR     R2
        GHI     R8
        ADD
        PLO     RF
        IRX
        LDX
        ADCI    0
        PHI     RF
        LDN     RF
        SEP     R5
; DSTEP: R8 one cell in direction D
DSTEP:  LBZ     DSU
        SMI     1
        LBZ     DSL
        SMI     1
        LBZ     DSD
        GHI     R8
        ADI     1
        PHI     R8
        SEP     R5
DSU:    GLO     R8
        SMI     1
        PLO     R8
        SEP     R5
DSL:    GHI     R8
        SMI     1
        PHI     R8
        SEP     R5
DSD:    GLO     R8
        ADI     1
        PLO     R8
        SEP     R5
; WALKABLE: D = a cell's character: DF = 1 if it can be walked on (not rock, not a wall)
WALKABLE: XRI   ' '
        LBZ     WA0
        XRI     ' ' XOR '|'
        LBZ     WA0
        XRI     '|' XOR '-'
        LBZ     WA0
        SMI     0
        SEP     R5
WA0:    ADI     0
        SEP     R5
; RMP: D = a room -> RC -> its record
RMP:    PLO     RC
        SHL
        SHL
        STR     R2
        GLO     RC
        ADD
        ADI     LOW(ROOMS)
        PLO     RC
        LDI     HIGH(ROOMS)
        ADCI    0
        PHI     RC
        SEP     R5
; INROOM: DF = 1 if R8 is in the room at RC (walls included). RC moves
INROOM: LDA     RC
        STR     R2
        GHI     R8
        SM
        LBNF    IRN
        LDA     RC
        STR     R2
        GLO     R8
        SM
        LBNF    IRN
        LDA     RC
        STR     R2
        GHI     R8
        SD
        LBNF    IRN
        LDN     RC
        STR     R2
        GLO     R8
        SD
        LBNF    IRN
        SMI     0
        SEP     R5
IRN:    ADI     0
        SEP     R5
; VISIBLE: DF = 1 if he can see R8: next to him, or in the room he is in. Uses RD RC
VISIBLE: LOAD   RD, PX
        LDA     RD
        STR     R2
        GHI     R8
        SM
        ADI     1
        SMI     3
        LBDF    VI2
        LDN     RD
        STR     R2
        GLO     R8
        SM
        ADI     1
        SMI     3
        LBDF    VI2
        SMI     0
        SEP     R5
VI2:    LOAD    RD, CURR
        LDN     RD
        XRI     0FFH
        LBZ     VNO
        LDN     RD
        SEP     R4
        DW      RMP
        LBR     INROOM
VNO:    ADI     0
        SEP     R5

; RANDOM: the next of a 16-bit shift register -> D (its low byte). Uses RD
RANDOM: LOAD    RD, RND
        LDN     RD
        SHR
        STR     RD
        INC     RD
        LDN     RD
        SHRC
        STR     RD
        LBNF    RN1
        DEC     RD
        LDN     RD
        XRI     0B4H
        STR     RD
        INC     RD
RN1:    LDN     RD
        SEP     R5
; RANDN: D = n (1-255) -> D = 0 .. n - 1. Uses RD RF
RANDN:  PHI     RF
        SEP     R4
        DW      RANDOM
RNL:    PLO     RF
        GHI     RF
        STR     R2
        GLO     RF
        SM
        LBDF    RNL
        GLO     RF
        SEP     R5

; ==== a new level
GENLVL: LOAD    RF, GRID        ; all rock
        LOAD    R7, MW * MH
GN1:    LDI     ' '
        STR     RF
        INC     RF
        DEC     R7
        GLO     R7
        LBNZ    GN1
        GHI     R7
        LBNZ    GN1
        LOAD    RF, MONS        ; no monsters
        LDI     NM * MSZ
        PLO     R7
GN2:    LDI     0
        STR     RF
        INC     RF
        DEC     R7
        GLO     R7
        LBNZ    GN2
        LOAD    RD, RI          ; the rooms
        LDI     0
        STR     RD
GN3:    SEP     R4
        DW      MKROOM
        LOAD    RD, RI
        LDN     RD
        ADI     1
        STR     RD
        XRI     NR
        LBNZ    GN3
        LOAD    RD, CI          ; the corridors
        LDI     0
        STR     RD
GN4:    LOAD    RD, CI
        LDN     RD
        SHL
        ADI     LOW(CONNT)
        PLO     RA
        LDI     HIGH(CONNT)
        ADCI    0
        PHI     RA
        LDA     RA
        PLO     R9              ; a
        LDN     RA
        PHI     R9              ; b
        GLO     R9
        SEP     R4
        DW      RMP
        GLO     RC
        PLO     RA
        GHI     RC
        PHI     RA
        GHI     R9
        SEP     R4
        DW      RMP
        GLO     RC
        PLO     RB
        GHI     RC
        PHI     RB
        GLO     R9
        STR     R2
        GHI     R9
        SM                      ; b - a: 1 side by side, 3 one above the other
        XRI     1
        LBNZ    GN5
        SEP     R4
        DW      HCONN
        LBR     GN6
GN5:    SEP     R4
        DW      VCONN
GN6:    LOAD    RD, CI
        LDN     RD
        ADI     1
        STR     RD
        XRI     12
        LBNZ    GN4
        LDI     NR              ; him: in a room
        SEP     R4
        DW      RANDN
        PLO     R7
        LOAD    RD, PROOM
        GLO     R7
        STR     RD
        GLO     R7
        SEP     R4
        DW      RANDFL
        LOAD    RD, PX
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
GN7:    LDI     NR              ; the stairs (the crystal on the last depth): another room
        SEP     R4
        DW      RANDN
        PLO     R7
        LOAD    RD, PROOM
        LDN     RD
        STR     R2
        GLO     R7
        XOR
        LBZ     GN7
        GLO     R7
        SEP     R4
        DW      RANDFL
        SEP     R4
        DW      CELLA
        LOAD    RD, DEPTH
        LDN     RD
        XRI     LASTD
        LBZ     GN8
        LDI     '>'
        STR     RF
        LBR     GN9
GN8:    LDI     '*'
        STR     RF
GN9:    LDI     4               ; 4-7 things
        SEP     R4
        DW      RANDN
        ADI     4
        PLO     R7
        LOAD    RD, GCNT
        GLO     R7
        STR     RD
GN10:   LDI     16              ; which
        SEP     R4
        DW      RANDN
        ADI     LOW(ITEMT)
        PLO     RA
        LDI     HIGH(ITEMT)
        ADCI    0
        PHI     RA
        LDN     RA
        PHI     RB              ; (RB.1: RANDFL uses RC, RANDN RD RF)
        LDI     NR
        SEP     R4
        DW      RANDN
        SEP     R4
        DW      RANDFL
        LOAD    RD, PX          ; not where he stands
        LDA     RD
        STR     R2
        GHI     R8
        XOR
        LBNZ    GN10A
        LDN     RD
        STR     R2
        GLO     R8
        XOR
        LBZ     GN11
GN10A:  SEP     R4
        DW      CELLA
        XRI     '.'
        LBNZ    GN11
        GHI     RB
        STR     RF
GN11:   LOAD    RD, GCNT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    GN10
        LOAD    RD, DEPTH       ; the monsters: 2 + depth (at most NM), none in his room
        LDN     RD
        ADI     2
        SMI     NM + 1
        LBNF    GN12
        LDI     NM
        LBR     GN13
GN12:   ADI     NM + 1
GN13:   PLO     R7
        LOAD    RD, GCNT
        GLO     R7
        STR     RD
        LOAD    RD, MPTR
        LDI     HIGH(MONS)
        STR     RD
        INC     RD
        LDI     LOW(MONS)
        STR     RD
GN14:   LDI     NR
        SEP     R4
        DW      RANDN
        PLO     R7
        LOAD    RD, PROOM
        LDN     RD
        STR     R2
        GLO     R7
        XOR
        LBZ     GN14
        GLO     R7
        SEP     R4
        DW      RANDFL
        SEP     R4
        DW      MONAT
        LBDF    GN14
        LOAD    RD, DEPTH       ; its type: depth - 1, or up to 2 less
        LDN     RD
        SMI     3
        LBNF    GN15
        LDI     3
        LBR     GN16
GN15:   ADI     3
GN16:   SEP     R4
        DW      RANDN
        STR     R2
        LOAD    RD, DEPTH
        LDN     RD
        SMI     1
        SM
        PLO     R9              ; R9.0 = its type
        SEP     R4
        DW      LDMP
        GLO     R9
        ADI     1
        STR     RA
        INC     RA
        GHI     R8
        STR     RA
        INC     RA
        GLO     R8
        STR     RA
        INC     RA
        GLO     R9
        SEP     R4
        DW      MTP
        INC     RC
        LDN     RC              ; its HP
        STR     RA
        LOAD    RD, MPTR + 1
        LDN     RD
        ADI     MSZ
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, GCNT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    GN14
        SEP     R5

; MKROOM: room RI in its sector: floor 3-16 wide, 2-4 high, placed at random; drawn into GRID
MKROOM: LOAD    RD, RI
        LDN     RD
        SHL
        ADI     LOW(SECT)
        PLO     RA
        LDI     HIGH(SECT)
        ADCI    0
        PHI     RA
        LDA     RA
        PHI     R9              ; sx
        LDN     RA
        PLO     R9              ; sy
        LDI     14              ; its width with the walls: 5-18
        SEP     R4
        DW      RANDN
        ADI     5
        PHI     R7
        LDI     3               ; its height: 4-6
        SEP     R4
        DW      RANDN
        ADI     4
        PLO     R7
        GHI     R7              ; x0 = sx + 1 + rand(25 - width)
        SDI     25
        SEP     R4
        DW      RANDN
        STR     R2
        GHI     R9
        ADD
        ADI     1
        PHI     R8
        GLO     R7              ; y0 = sy + rand(7 - height)
        SDI     7
        SEP     R4
        DW      RANDN
        STR     R2
        GLO     R9
        ADD
        PLO     R8
        LOAD    RD, RI
        LDN     RD
        SEP     R4
        DW      RMP
        GHI     R8
        STR     RC
        INC     RC
        GLO     R8
        STR     RC
        INC     RC
        GHI     R8
        STR     R2
        GHI     R7
        ADD
        SMI     1
        STR     RC
        INC     RC
        GLO     R8
        STR     R2
        GLO     R7
        ADD
        SMI     1
        STR     RC
        INC     RC
        LDI     0
        STR     RC
        LOAD    RD, RI          ; drawn: - top and bottom, | the sides, . the floor
        LDN     RD
        SEP     R4
        DW      RMP
        LDA     RC
        PHI     R9              ; x0
        LDA     RC
        PHI     RB              ; y0
        LDA     RC
        PLO     R9              ; x1
        LDN     RC
        PLO     RB              ; y1
        GHI     RB
        PLO     R8
MKR1:    GHI     R9
        PHI     R8
MR2:    GLO     R8
        STR     R2
        GHI     RB
        XOR
        LBZ     MRH
        GLO     R8
        STR     R2
        GLO     RB
        XOR
        LBZ     MRH
        GHI     R8
        STR     R2
        GHI     R9
        XOR
        LBZ     MRV
        GHI     R8
        STR     R2
        GLO     R9
        XOR
        LBZ     MRV
        LDI     '.'
        LBR     MRS
MRH:    LDI     '-'
        LBR     MRS
MRV:    LDI     '|'
MRS:    PLO     R7
        SEP     R4
        DW      CELLA
        GLO     R7
        STR     RF
        GHI     R8
        STR     R2
        GLO     R9
        XOR
        LBZ     MR3
        GHI     R8
        ADI     1
        PHI     R8
        LBR     MR2
MR3:    GLO     R8
        STR     R2
        GLO     RB
        XOR
        LBZ     MR4
        GLO     R8
        ADI     1
        PLO     R8
        LBR     MKR1
MR4:    SEP     R5

; RANDFL: D = a room -> R8 = a floor cell of it, at random. Uses RC RD RF
RANDFL: SEP     R4
        DW      RMP
        LDA     RC
        PHI     R8              ; x0
        LDA     RC
        PLO     R8              ; y0
        LDA     RC              ; x = x0 + 1 + rand(x1 - x0 - 1)
        STR     R2
        GHI     R8
        SD
        SMI     1
        SEP     R4
        DW      RANDN
        STR     R2
        GHI     R8
        ADD
        ADI     1
        PHI     R8
        LDN     RC              ; y = y0 + 1 + rand(y1 - y0 - 1)
        STR     R2
        GLO     R8
        SD
        SMI     1
        SEP     R4
        DW      RANDN
        STR     R2
        GLO     R8
        ADD
        ADI     1
        PLO     R8
        SEP     R5

; HCONN: rooms RA (left) and RB (right) joined: a door in each side wall, a corridor right, down or up, right
HCONN:  GLO     RA
        PLO     RC
        GHI     RA
        PHI     RC
        SEP     R4
        DW      SIDEY           ; ya
        PLO     R9
        LOAD    RD, CA
        GLO     R9
        STR     RD
        GLO     RB
        PLO     RC
        GHI     RB
        PHI     RC
        SEP     R4
        DW      SIDEY           ; yb
        PLO     R9
        LOAD    RD, CB
        GLO     R9
        STR     RD
        INC     RA              ; doors: (x1a, ya), (x0b, yb)
        INC     RA
        LDN     RA
        DEC     RA
        DEC     RA
        PHI     R8
        LOAD    RD, CA
        LDN     RD
        PLO     R8
        SEP     R4
        DW      DOOR
        LDN     RB
        PHI     R8
        LOAD    RD, CB
        LDN     RD
        PLO     R8
        SEP     R4
        DW      DOOR
        INC     RA              ; xs = x1a + 1, xe = x0b - 1, mx = xs + rand(xe - xs + 1)
        INC     RA
        LDN     RA
        ADI     1
        PLO     R9              ; R9.0 = xs
        LDN     RB
        SMI     1
        PHI     R9              ; R9.1 = xe
        GLO     R9
        STR     R2
        GHI     R9
        SM
        ADI     1
        SEP     R4
        DW      RANDN
        STR     R2
        GLO     R9
        ADD
        PLO     RB              ; RB.0 = mx (RB no longer needed)
        LOAD    RD, CA          ; along ya from xs to mx
        LDN     RD
        PLO     R8
        GLO     R9
        PHI     R8
        GLO     RB
        PLO     R7
        SEP     R4
        DW      CARVEH
        GLO     RB              ; mx, from ya to yb
        PHI     R8
        LOAD    RD, CA
        LDN     RD
        PLO     R8
        LOAD    RD, CB
        LDN     RD
        PLO     R7
        SEP     R4
        DW      CARVEV
        LOAD    RD, CB          ; along yb from mx to xe
        LDN     RD
        PLO     R8
        GLO     RB
        PHI     R8
        GHI     R9
        PLO     R7
        LBR     CARVEH
; SIDEY: RC -> a room: D = a row of its floor, at random (y0 + 1 + rand(y1 - y0 - 1))
SIDEY:  INC     RC
        LDA     RC
        PLO     R7
        INC     RC
        LDN     RC
        STR     R2
        GLO     R7
        SD
        SMI     1
        SEP     R4
        DW      RANDN
        STR     R2
        GLO     R7
        ADD
        ADI     1
        SEP     R5
; SIDEX: RC -> a room: D = a column of its floor, at random
SIDEX:  LDA     RC
        PLO     R7
        INC     RC
        LDN     RC
        STR     R2
        GLO     R7
        SD
        SMI     1
        SEP     R4
        DW      RANDN
        STR     R2
        GLO     R7
        ADD
        ADI     1
        SEP     R5

; VCONN: rooms RA (above) and RB (below) joined: a door in the bottom / top wall, a corridor down, across, down
VCONN:  GLO     RA
        PLO     RC
        GHI     RA
        PHI     RC
        SEP     R4
        DW      SIDEX           ; xa
        PLO     R9
        LOAD    RD, CA
        GLO     R9
        STR     RD
        GLO     RB
        PLO     RC
        GHI     RB
        PHI     RC
        SEP     R4
        DW      SIDEX           ; xb
        PLO     R9
        LOAD    RD, CB
        GLO     R9
        STR     RD
        LOAD    RD, CA          ; doors: (xa, y1a), (xb, y0b)
        LDN     RD
        PHI     R8
        INC     RA
        INC     RA
        INC     RA
        LDN     RA
        PLO     R8
        SEP     R4
        DW      DOOR
        LOAD    RD, CB
        LDN     RD
        PHI     R8
        INC     RB
        LDN     RB
        PLO     R8
        SEP     R4
        DW      DOOR
        LDN     RA              ; ys = y1a + 1, ye = y0b - 1, my = ys + rand(ye - ys + 1)
        ADI     1
        PLO     R9              ; R9.0 = ys
        LDN     RB
        SMI     1
        PHI     R9              ; R9.1 = ye
        GLO     R9
        STR     R2
        GHI     R9
        SM
        ADI     1
        SEP     R4
        DW      RANDN
        STR     R2
        GLO     R9
        ADD
        PLO     RB              ; RB.0 = my
        LOAD    RD, CA          ; down xa from ys to my
        LDN     RD
        PHI     R8
        GLO     R9
        PLO     R8
        GLO     RB
        PLO     R7
        SEP     R4
        DW      CARVEV
        GLO     RB              ; across my from xa to xb
        PLO     R8
        LOAD    RD, CA
        LDN     RD
        PHI     R8
        LOAD    RD, CB
        LDN     RD
        PLO     R7
        SEP     R4
        DW      CARVEH
        LOAD    RD, CB          ; down xb from my to ye
        LDN     RD
        PHI     R8
        GLO     RB
        PLO     R8
        GHI     R9
        PLO     R7
        LBR     CARVEV

; DOOR: R8 a door (+)
DOOR:   SEP     R4
        DW      CELLA
        LDI     '+'
        STR     RF
        SEP     R5
; CARVEH: row R8.0, from column R8.1 to R7.0 (either way round): rock made corridor (#)
CARVEH: GHI     R8
        STR     R2
        GLO     R7
        SM
        LBDF    CH1
        GHI     R8              ; the other way round: swapped
        PHI     R7
        GLO     R7
        PHI     R8
        GHI     R7
        PLO     R7
CH1:    SEP     R4
        DW      CARVE1
        GHI     R8
        STR     R2
        GLO     R7
        XOR
        LBZ     CH9
        GHI     R8
        ADI     1
        PHI     R8
        LBR     CH1
CH9:    SEP     R5
; CARVEV: column R8.1, from row R8.0 to R7.0 (either way round)
CARVEV: GLO     R8
        STR     R2
        GLO     R7
        SM
        LBDF    CV1
        GLO     R8
        PHI     R7
        GLO     R7
        PLO     R8
        GHI     R7
        PLO     R7
CV1:    SEP     R4
        DW      CARVE1
        GLO     R8
        STR     R2
        GLO     R7
        XOR
        LBZ     CV9
        GLO     R8
        ADI     1
        PLO     R8
        LBR     CV1
CV9:    SEP     R5
CARVE1: SEP     R4
        DW      CELLA
        XRI     ' '
        LBNZ    CR9
        LDI     '#'
        STR     RF
CR9:    SEP     R5

; ==== the screen
; DRAWLVL: a clear screen, the keys line; everything to be drawn afresh
DRAWLVL: LOAD   RA, CLEARS
        SEP     R4
        DW      PUTS
        LOAD    RA, KEYSS
        SEP     R4
        DW      PUTS
        LOAD    RA, SHOWN
        LDI     13
        PLO     R9
DW1:    LDI     0FFH
        STR     RA
        INC     RA
        DEC     R9
        GLO     R9
        LBNZ    DW1
        LOAD    RD, PDRAWN
        LDI     0
        STR     RD
        LOAD    RD, MCOL
        LDI     0
        STR     RD
        LOAD    RD, CURR
        LDI     0FFH
        STR     RD
        SEP     R5

; REDRAW: his old cell (if he moved); the room he is in, the first time; the cells next to him; the monsters
;   he can see; him (@); the status line, if it changed
REDRAW: LOAD    RD, CURY
        LDI     0FFH
        STR     RD
        LOAD    RD, PDRAWN
        LDN     RD
        LBZ     RW1
        LOAD    RD, OPX
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LOAD    RD, PX
        LDA     RD
        STR     R2
        GHI     R8
        XOR
        LBNZ    RW0
        LDN     RD
        STR     R2
        GLO     R8
        XOR
        LBZ     RW1
RW0:    SEP     R4
        DW      DRAWCELL
        LOAD    RD, PDRAWN
        LDI     0
        STR     RD
RW1:    LOAD    RD, PX          ; which room is he in?
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LDI     0
        PLO     R9
RW2:    GLO     R9
        SEP     R4
        DW      RMP
        SEP     R4
        DW      INROOM
        LBDF    RW3
        GLO     R9
        ADI     1
        PLO     R9
        XRI     NR
        LBNZ    RW2
        LDI     0FFH
        PLO     R9
RW3:    LOAD    RD, CURR
        GLO     R9
        STR     RD
        XRI     0FFH
        LBZ     RW4
        GLO     R9              ; lit yet?
        SEP     R4
        DW      RMP
        GLO     RC
        ADI     4
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LDN     RC
        LBNZ    RW4
        LDI     1
        STR     RC
        GLO     R9
        SEP     R4
        DW      LIGHT
        LOAD    RD, PDRAWN
        LDI     0
        STR     RD
RW4:    SEP     R4
        DW      ADJREV
        SEP     R4
        DW      DRAWMONS
        LOAD    RD, PDRAWN
        LDN     RD
        LBNZ    RW5
        LOAD    RD, PX
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LDI     '@'
        SEP     R4
        DW      DRAWAT
        LOAD    RD, OPX
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        LOAD    RD, PDRAWN
        LDI     1
        STR     RD
RW5:    LBR     STATUS

; LIGHT: room D shown, every cell of it seen; a monster drawn inside it is drawn again (its cell was overwritten)
LIGHT:  PLO     RB
        SEP     R4
        DW      RMP
        LDA     RC
        PHI     R9              ; x0
        LDA     RC
        PLO     R8              ; y0
        LDA     RC
        PLO     R9              ; x1
        LDN     RC
        PLO     R7              ; y1
LT1:    GHI     R9
        PHI     R8
        SEP     R4
        DW      GOTO
LT2:    SEP     R4
        DW      CELLA
        ORI     80H
        STR     RF
        ANI     7FH
        SEP     R4
        DW      PUTC
        GHI     R8
        STR     R2
        GLO     R9
        XOR
        LBZ     LT3
        GHI     R8
        ADI     1
        PHI     R8
        LBR     LT2
LT3:    GLO     R8
        STR     R2
        GLO     R7
        XOR
        LBZ     LT4
        GLO     R8
        ADI     1
        PLO     R8
        LBR     LT1
LT4:    LOAD    RD, CURY
        LDI     0FFH
        STR     RD
        LOAD    RA, MONS        ; monsters drawn in it: not any more
        LDI     NM
        PLO     R9
LT5:    GLO     RA
        ADI     5
        PLO     RD
        GHI     RA
        ADCI    0
        PHI     RD
        LDA     RD
        LBZ     LT6
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        GLO     RB
        SEP     R4
        DW      RMP
        SEP     R4
        DW      INROOM
        LBNF    LT6
        GLO     RA
        ADI     5
        PLO     RD
        GHI     RA
        ADCI    0
        PHI     RD
        LDI     0
        STR     RD
LT6:    GLO     RA
        ADI     MSZ
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        DEC     R9
        GLO     R9
        LBNZ    LT5
        SEP     R5

; ADJREV: the cells next to him (and his own) seen; drawn the first time (rock stays blank)
ADJREV: LDI     0
        PHI     R9
AR1:    LDI     0
        PLO     R9
AR2:    LOAD    RD, PX
        LDA     RD
        STR     R2
        GLO     R9
        ADD
        SMI     1
        PHI     R8
        LDN     RD
        STR     R2
        GHI     R9
        ADD
        SMI     1
        PLO     R8
        SEP     R4
        DW      CELLA
        ANI     80H
        LBNZ    AR3
        LDN     RF
        ORI     80H
        STR     RF
        ANI     7FH
        XRI     ' '
        LBZ     AR3
        LDN     RF
        ANI     7FH
        SEP     R4
        DW      DRAWAT
AR3:    GLO     R9
        ADI     1
        PLO     R9
        XRI     3
        LBNZ    AR2
        GHI     R9
        ADI     1
        PHI     R9
        XRI     3
        LBNZ    AR1
        SEP     R5

; DRAWMONS: first each monster drawn that is gone, has moved or is out of sight: its cell drawn again; then
;   each one he can see that is not drawn: its letter
DRAWMONS: LOAD  RA, MONS
        LDI     NM
        PLO     RB
DM1:    GLO     RA
        ADI     5
        PLO     RC
        GHI     RA
        ADCI    0
        PHI     RC
        LDN     RC
        LBZ     DM3             ; not drawn
        LDN     RA
        LBZ     DM2             ; gone
        GLO     RA
        PLO     RC
        GHI     RA
        PHI     RC
        INC     RC
        LDA     RC
        PHI     R8
        LDA     RC
        PLO     R8
        INC     RC
        INC     RC
        INC     RC
        LDA     RC
        STR     R2
        GHI     R8
        XOR
        LBNZ    DM2
        LDN     RC
        STR     R2
        GLO     R8
        XOR
        LBNZ    DM2
        SEP     R4
        DW      VISIBLE
        LBDF    DM3             ; still there, still seen: as it is
DM2:    GLO     RA
        ADI     5
        PLO     RC
        GHI     RA
        ADCI    0
        PHI     RC
        LDI     0
        STR     RC
        INC     RC
        LDA     RC
        PHI     R8
        LDN     RC
        PLO     R8
        SEP     R4
        DW      DRAWCELL
DM3:    GLO     RA
        ADI     MSZ
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        DEC     RB
        GLO     RB
        LBNZ    DM1
        LOAD    RA, MONS
        LDI     NM
        PLO     RB
DM4:    LDN     RA
        LBZ     DM6
        GLO     RA
        ADI     5
        PLO     RC
        GHI     RA
        ADCI    0
        PHI     RC
        LDN     RC
        LBNZ    DM6
        GLO     RA
        PLO     RC
        GHI     RA
        PHI     RC
        INC     RC
        LDA     RC
        PHI     R8
        LDN     RC
        PLO     R8
        SEP     R4
        DW      VISIBLE
        LBNF    DM6
        GLO     RA
        ADI     5
        PLO     RC
        GHI     RA
        ADCI    0
        PHI     RC
        LDI     1
        STR     RC
        INC     RC
        GHI     R8
        STR     RC
        INC     RC
        GLO     R8
        STR     RC
        LDN     RA
        SMI     1
        SEP     R4
        DW      MTP
        LDN     RC
        SEP     R4
        DW      DRAWAT
DM6:    GLO     RA
        ADI     MSZ
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        DEC     RB
        GLO     RB
        LBNZ    DM4
        SEP     R5

; DRAWCELL: R8's cell as he knows it (blank if never seen)
DRAWCELL: SEP   R4
        DW      CELLA
        SHL
        LBNF    DC1
        LDN     RF
        ANI     7FH
        LBR     DRAWAT
DC1:    LDI     ' '
; DRAWAT: D at R8's place (the cursor moved there only if it is not there already). Uses RD (GOTO: RF)
DRAWAT: STXD
        LOAD    RD, CURX
        LDA     RD
        STR     R2
        GHI     R8
        XOR
        LBNZ    DA1
        LDN     RD
        STR     R2
        GLO     R8
        XOR
        LBZ     DA2
DA1:    SEP     R4
        DW      GOTO
DA2:    LOAD    RD, CURX
        GHI     R8
        ADI     1
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        IRX
        LDX
        LBR     PUTC
; GOTO: the cursor to R8's place: ESC [ y + 2 ; x + 2 H (R8 kept)
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
        ADI     2
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

; STATUS: the top line, when anything on it changed
STATUS: LOAD    RA, HP
        LOAD    RB, SHOWN
        LDI     13
        PLO     R9
SS1:    LDA     RB
        STR     R2
        LDA     RA
        XOR
        LBNZ    SS2
        DEC     R9
        GLO     R9
        LBNZ    SS1
        SEP     R5
SS2:    LOAD    RA, HP
        LOAD    RB, SHOWN
        LDI     13
        PLO     R9
SS3:    LDA     RA
        STR     RB
        INC     RB
        DEC     R9
        GLO     R9
        LBNZ    SS3
        LOAD    RD, NMODE
        LDI     0
        STR     RD
        LOAD    RA, STS1
        SEP     R4
        DW      PUTS
        LOAD    RD, DEPTH
        LDN     RD
        SEP     R4
        DW      NUM8
        LOAD    RA, STS2
        SEP     R4
        DW      PUTS
        LOAD    RD, HP
        LDN     RD
        SEP     R4
        DW      NUM8
        LDI     '/'
        SEP     R4
        DW      PUTC
        LOAD    RD, MAXHP
        LDN     RD
        SEP     R4
        DW      NUM8
        LOAD    RA, STS3
        SEP     R4
        DW      PUTS
        LOAD    RD, ATK
        LDN     RD
        SEP     R4
        DW      NUM8
        LOAD    RA, STS4
        SEP     R4
        DW      PUTS
        LOAD    RD, DEF
        LDN     RD
        SEP     R4
        DW      NUM8
        LOAD    RA, STS5
        SEP     R4
        DW      PUTS
        LOAD    RD, PLV
        LDN     RD
        SEP     R4
        DW      NUM8
        LOAD    RA, STS6
        SEP     R4
        DW      PUTS
        LOAD    RD, XPH
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      NUMOUT
        LOAD    RA, STS7
        SEP     R4
        DW      PUTS
        LOAD    RD, GOLDH
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      NUMOUT
        LOAD    RA, STS8
        SEP     R4
        DW      PUTS
        LOAD    RD, POTS
        LDN     RD
        SEP     R4
        DW      NUM8
        LOAD    RA, STSE
        SEP     R4
        DW      PUTS
        LOAD    RD, CURY
        LDI     0FFH
        STR     RD
        SEP     R5

; ==== the words on row 23
; MSGCLR: last turn's words cleared (if there were any)
MSGCLR: LOAD    RD, MCOL
        LDN     RD
        LBZ     MC9
        LDI     0
        STR     RD
        LOAD    RA, CLRMSG
        LBR     PUTS
MC9:    SEP     R5
; MSG: the words at RA added (up to the line's end). MPUTC: D added. Uses RD only
MSG:    LDA     RA
        LBZ     MS9
        SEP     R4
        DW      MPUTC
        LBR     MSG
MS9:    SEP     R5
MPUTC:  STXD
        LOAD    RD, MCOL
        LDN     RD
        LBNZ    MP1
        LDI     ESC             ; the first: the cursor to row 23
        SEP     R4
        DW      PUTC
        LDI     '['
        SEP     R4
        DW      PUTC
        LDI     '2'
        SEP     R4
        DW      PUTC
        LDI     '3'
        SEP     R4
        DW      PUTC
        LDI     ';'
        SEP     R4
        DW      PUTC
        LDI     '1'
        SEP     R4
        DW      PUTC
        LDI     'H'
        SEP     R4
        DW      PUTC
        LOAD    RD, CURY
        LDI     0FFH
        STR     RD
        LOAD    RD, MCOL
MP1:    LDN     RD
        SMI     78
        LBDF    MP9
        LDN     RD
        ADI     1
        STR     RD
        IRX
        LDX
        LBR     PUTC
MP9:    IRX
        SEP     R5

; NUM8: D in decimal. NUMOUT: R7 in decimal, no leading zeros - to the screen (NMODE 0) or the words (1).
;   Uses R7 R9 RA RB RC RD
NUM8:   PLO     R7
        LDI     0
        PHI     R7
NUMOUT: LOAD    RA, P10
        LDI     5
        PLO     RB
        LDI     0
        PHI     RB
NO1:    LDA     RA
        PHI     RC
        LDA     RA
        PLO     RC
        LDI     0
        PLO     R9
NO2:    GLO     RC
        STR     R2
        GLO     R7
        SM
        PLO     RD
        GHI     RC
        STR     R2
        GHI     R7
        SMB
        LBNF    NO3
        PHI     R7
        GLO     RD
        PLO     R7
        GLO     R9
        ADI     1
        PLO     R9
        LBR     NO2
NO3:    GLO     R9
        LBNZ    NO4
        GHI     RB
        LBNZ    NO4
        GLO     RB
        XRI     1
        LBZ     NO4
        LBR     NO5
NO4:    LDI     1
        PHI     RB
        GLO     R9
        ADI     '0'
        SEP     R4
        DW      OUTC
NO5:    DEC     RB
        GLO     RB
        LBNZ    NO1
        SEP     R5
OUTC:   STXD
        LOAD    RD, NMODE
        LDN     RD
        LBNZ    OC1
        IRX
        LDX
        LBR     PUTC
OC1:    IRX
        LDX
        LBR     MPUTC
P10:    DW      10000, 1000, 100, 10, 1

; ==== COSMO KID's / AT-MAN's routines
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

; ==== sound on Q: TONE R7 = half-periods, R8.0 = K (each half-period ~ 20 + 3 K instructions). Keys are caught
;   while it plays. SWEEP: from K = R8.0 by R8.1 (signed) a step, RB.0 steps, R9.1 half-periods each.
;   The sounds use R7 R8 R9 RB.
TONE:   LBQ     TN1
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
SWEEP:  GHI     R9
        PLO     R7
        LDI     0
        PHI     R7
        GLO     R8
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
SNDHIT: LDI     22              ; a high tick
        PLO     R8
        LOAD    R7, 24
        LBR     TONE
SNDHURT: LDI    120             ; a low buzz
        PLO     R8
        LOAD    R7, 20
        LBR     TONE
SNDGOLD: LDI    18
        PLO     R8
        LOAD    R7, 14
        LBR     TONE
SNDPICK: LDI    60              ; up: 60 to 20
        PLO     R8
        LDI     0F8H
        PHI     R8
        LDI     6
        PLO     RB
        LDI     8
        PHI     R9
        LBR     SWEEP
SNDKILL: LDI    40              ; up: 40 to 16
        PLO     R8
        LDI     0FCH
        PHI     R8
        LDI     7
        PLO     RB
        LDI     10
        PHI     R9
        LBR     SWEEP
SNDPOT: LDI     90              ; down and up
        PLO     R8
        LDI     0F6H
        PHI     R8
        LDI     6
        PLO     RB
        LDI     8
        PHI     R9
        LBR     SWEEP
SNDDOWN: LDI    20              ; down the stairs: 20 to 140
        PLO     R8
        LDI     12
        PHI     R8
        LDI     11
        PLO     RB
        LDI     8
        PHI     R9
        LBR     SWEEP
SNDDIE: LDI     30              ; a fall: 30 to 210
        PLO     R8
        LDI     15
        PHI     R8
        LDI     12
        PLO     RB
        LDI     14
        PHI     R9
        LBR     SWEEP
SNDLVL: LOAD    RA, FANL
        LBR     PLAYT
SNDWIN: LOAD    RA, FANF
; PLAYT: the tune at RA: K, half-periods (x 4) ... 0
PLAYT:  LDA     RA
        LBZ     PL9
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
        LBR     PLAYT
PL9:    SEP     R5
FANF:   DB      48, 40, 40, 48, 30, 64, 40, 48, 30, 64, 24, 160, 0
FANL:   DB      40, 30, 30, 40, 24, 70, 0

; ==== tables
INIT0:  DB      20, 20, 3, 0, 1, 0, 0, 0, 10, 0, 0, 1, 1        ; HP .. DEPTH, as they start
SECT:   DB      0, 0, 26, 0, 52, 0, 0, 7, 26, 7, 52, 7, 0, 14, 26, 14, 52, 14
CONNT:  DB      0, 1, 1, 2, 3, 4, 4, 5, 6, 7, 7, 8, 0, 3, 1, 4, 2, 5, 3, 6, 4, 7, 5, 8
ITEMT:  DB      '$', '$', '$', '$', '$', '$', '$', '!', '!', '!', ')', ')', '[', '[', '$', '!'
;               letter HP Atk Def XP flags
MTAB:   DB      'r',  3,  2,  0,  1, 0         ; rat
        DB      'b',  4,  2,  0,  2, 2         ; bat (erratic)
        DB      'k',  6,  3,  0,  3, 0         ; kobold
        DB      's',  8,  4,  1,  5, 0         ; snake
        DB      'g', 10,  4,  1,  6, 0         ; goblin
        DB      'o', 14,  5,  2,  9, 0         ; orc
        DB      'Z', 20,  6,  2, 12, 1         ; zombie (slow)
        DB      'w', 16,  7,  1, 12, 0         ; wolf
        DB      'T', 26,  8,  3, 20, 0         ; troll
        DB      'D', 40, 10,  4, 40, 0         ; dragon
NAMET:  DW      NM0, NM1, NM2, NM3, NM4, NM5, NM6, NM7, NM8, NM9
NM0:    DB      'rat',0
NM1:    DB      'bat',0
NM2:    DB      'kobold',0
NM3:    DB      'snake',0
NM4:    DB      'goblin',0
NM5:    DB      'orc',0
NM6:    DB      'zombie',0
NM7:    DB      'wolf',0
NM8:    DB      'troll',0
NM9:    DB      'dragon',0

; ==== words
TITLES: DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l'
        DB      ESC,'[4;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[5;29H',ESC,'[7m','     D E S C E N D     ',ESC,'[0m'
        DB      ESC,'[6;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[8;18H','Down into the dungeon under the COSMAC 1802.'
        DB      ESC,'[10;8H','Find the Star Crystal (*) on depth 10. Walk into a monster to fight it.'
        DB      ESC,'[11;8H','Gold ($), potions (!), weapons ()) and armour ([) are picked up as you go;'
        DB      ESC,'[12;8H','stairs (>) lead down. Each new level of experience makes you stronger.'
        DB      ESC,'[14;24H','@   Arrows or W A S D   move, fight'
        DB      ESC,'[15;24H','P                   drink a potion'
        DB      ESC,'[16;24H','> or Enter          go down the stairs'
        DB      ESC,'[17;24H','Space               rest a turn'
        DB      ESC,'[18;24H','Esc                 quit'
        DB      ESC,'[21;29H','Press any key to play',0
CLEARS: DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l',0
KEYSS:  DB      ESC,'[24;1H',' Arrows/WASD move, fight   P potion   > stairs   Space rest   Esc quit',0
STS1:   DB      ESC,'[1;1H',ESC,'[7m',' DESCEND ',ESC,'[0m','  Depth ',0
STS2:   DB      '  HP ',0
STS3:   DB      '  Atk ',0
STS4:   DB      '  Def ',0
STS5:   DB      '  Lv ',0
STS6:   DB      '  XP ',0
STS7:   DB      '  Gold ',0
STS8:   DB      '  Pot ',0
STSE:   DB      ESC,'[K',0
CLRMSG: DB      ESC,'[23;1H',ESC,'[K',0
S_DOWN: DB      'You go down to depth ',0
S_DOT:  DB      '. ',0
S_BANG: DB      '! ',0
S_CRYS: DB      'The Star Crystal is here somewhere. ',0
S_NOST: DB      'No stairs here. ',0
S_FIND: DB      'You find ',0
S_GOLD: DB      ' gold. ',0
S_POT:  DB      'A potion! ',0
S_WPN:  DB      'A better weapon! ',0
S_ARM:  DB      'Armour! ',0
S_STAIR: DB     'Stairs down: press > ',0
S_DRINK: DB     'You drink a potion. ',0
S_NOPOT: DB     'No potions left. ',0
S_YHIT: DB      'You hit the ',0
S_YKILL: DB     'You kill the ',0
S_YMISS: DB     'You miss the ',0
S_THE:  DB      'The ',0
S_HITS: DB      ' hits you. ',0
S_MISSES: DB    ' misses. ',0
S_LEVEL: DB     'Level up! ',0
DEADS:  DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l'
        DB      ESC,'[6;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[7;29H',ESC,'[7m','     D E S C E N D     ',ESC,'[0m'
        DB      ESC,'[8;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[11;20H','You were killed by a ',0
S_ONDEP: DB     ' on depth ',0
WINS:   DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l'
        DB      ESC,'[6;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[7;29H',ESC,'[7m','     D E S C E N D     ',ESC,'[0m'
        DB      ESC,'[8;29H',ESC,'[7m','                       ',ESC,'[0m'
        DB      ESC,'[11;20H','You found the Star Crystal on depth 10!',0
S_EGOLD: DB     ESC,'[13;20H','Gold ',0
S_ESCORE: DB    '     Score ',0
S_EKEY: DB      ESC,'[16;20H','Press a key for the title',0
BYES:   DB      ESC,'[0m',ESC,'[?25h',ESC,'[2J',ESC,'[H',0

ROWT:   DW      GRID + 0 * MW, GRID + 1 * MW, GRID + 2 * MW, GRID + 3 * MW, GRID + 4 * MW
        DW      GRID + 5 * MW, GRID + 6 * MW, GRID + 7 * MW, GRID + 8 * MW, GRID + 9 * MW
        DW      GRID + 10 * MW, GRID + 11 * MW, GRID + 12 * MW, GRID + 13 * MW, GRID + 14 * MW
        DW      GRID + 15 * MW, GRID + 16 * MW, GRID + 17 * MW, GRID + 18 * MW, GRID + 19 * MW
        DW      GRID + 20 * MW
PEND:
; ---- the variables (each set before it is used)
KQH:    DS      1               ; KQH, KQT: in this order
KQT:    DS      1
KQ:     DS      16
RND:    DS      2
HP:     DS      1               ; HP .. DEPTH: in this order (INIT0, the status line)
MAXHP:  DS      1
ATK:    DS      1
DEF:    DS      1
PLV:    DS      1
XPH:    DS      1
XPL:    DS      1
NXH:    DS      1
NXL:    DS      1
GOLDH:  DS      1
GOLDL:  DS      1
POTS:   DS      1
DEPTH:  DS      1
SHOWN:  DS      13              ; the status line as shown
TURN:   DS      1               ; TURN, WON: in this order
WON:    DS      1
KILLER: DS      1
PX:     DS      1               ; PX, PY: in this order
PY:     DS      1
OPX:    DS      1               ; OPX, OPY: in this order (where @ is drawn)
OPY:    DS      1
PDRAWN: DS      1
CURR:   DS      1               ; the room he is in (FF: none)
PROOM:  DS      1
CURX:   DS      1               ; CURX, CURY: in this order (the cursor; CURY FF: not known)
CURY:   DS      1
MCOL:   DS      1
NMODE:  DS      1
CMD:    DS      1
MT:     DS      1
MSLOT:  DS      2
MPTR:   DS      2
MCNT:   DS      1
MX:     DS      1               ; MX, MY: in this order
MY:     DS      1
ADX:    DS      1               ; ADX, ADY: in this order
ADY:    DS      1
HD:     DS      1               ; HD, VD: in this order
VD:     DS      1
TRY2:   DS      1
RI:     DS      1
CI:     DS      1
GCNT:   DS      1
CA:     DS      1
CB:     DS      1
ROOMS:  DS      NR * RSZ
MONS:   DS      NM * MSZ
GRID:   DS      MW * MH
        END
