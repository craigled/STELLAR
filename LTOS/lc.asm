; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lc.asm - LC.PRG: LC - the LTOS Commander, a two-pane file manager (plan: PLANS/LTOS-Commander-LC.md).
;   Phase 1: the two panes (left: this folder, right: the root), the cursor, scrolling, into a folder and up,
;   tags, the line about the file under the cursor, Help, the clock. Esc quits.
;
;   +- /BIN ------------------------------++- / ----------------------------------+
;   | ..                     <UP>          || BIN             <DIR> 26-11-16 10:02 |
;   | GAMES                 <DIR> 26-11-20 || ...
;   |>APPS.PRG               2304 26-11-17 ||
;   +- 9 files, 4 folders ----------------++--------------------------------------+
;
; Each pane's folder is read whole into records (RECSZ bytes: the name 11, attribute 1 - bit 7 = tagged, and the
; kernel's DTIME DDATE DCLUS DSIZE 10, all as DNEXT leaves them), and an index of them kept sorted as they come
; (a binary search, then the index bytes moved up): folders first, then by name. A pane not at the root has a
; ".." record first (index 0). Keys come through a ring (the UART holds one byte): every byte sent polls it.
;
; Memory (lc.inc): this core $3000-$45FF; a part of LC.OVL $4600-$57FF; the indexes $5800 / $5900; both panes'
; records in one pool $5A00-$69FF; keys, a path, a line $6A00; View's page starts $7700.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        INCL    "lc.inc"

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        DB      'VER:0.2',0
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        GLO     RF              ; (the arguments: kept on the stack while the variables are cleared)
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      KS_MNTCHK
        LOAD    RD, VARS        ; every variable 0
        LOAD    RC, VEND - VARS
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST1
        GHI     RC
        LBNZ    ST1
        LOAD    RD, LASTM       ; the clock: drawn the first time
        LDI     0FFH
        STR     RD
; ---- the panes: the left at this folder, the right at the root
        LOAD    RD, OVCUR       ; no part of LC.OVL loaded yet
        LDI     0FFH
        STR     RD
        LOAD    RD, PANE0 + P_IDXH
        LDI     HIGH(IDX0)
        STR     RD
        INC     RD
        INC     RD
        LDI     1
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RD, PANE1 + P_IDXH
        LDI     HIGH(IDX1)
        STR     RD
        INC     RD
        INC     RD
        LDI     41
        STR     RD
        INC     RD
        LDI     1
        STR     RD
        LOAD    RD, PANE1 + P_PATH
        LDI     '/'
        STR     RD
        LOAD    RD, KS_CWD      ; the left: CWD, its path from WHERE ("" for the root)
        LOAD    RF, PANE0 + P_CLUS
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        SEP     R4
        DW      KS_WHERE
        LOAD    RA, PANE0 + P_PATH
        LDN     RF
        LBNZ    ST2
        LDI     '/'
        STR     RA
        LBR     STARG
ST2:    LDA     RF
        STR     RA
        INC     RA
        LBNZ    ST2
STARG:  IRX                     ; LC -r / LC -k: back from a program LC ran - where it was (LC4.OVL)
        LDXA
        PHI     RF
        LDX
        PLO     RF
        SEP     R4
        DW      K_SKIPSP
        LDA     RF
        XRI     '-'
        LBNZ    ST3
        LDN     RF
        ANI     0DFH
        PLO     R7
        XRI     'R'
        LBZ     ST2R
        GLO     R7
        XRI     'K'
        LBZ     ST2R
        GLO     R7
        XRI     'E'             ; LC -e: back from NANO (Edit)
        LBNZ    ST3
ST2R:   LOAD    RD, RESMODE
        GLO     R7
        STR     RD
        LDI     4
        SEP     R4
        DW      OVLD
        LBDF    ST3
        SEP     R4
        DW      OVLA + 6
        LBNF    ST6
ST3:    LDI     0               ; the left read, then the right
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      LOADP
        LDI     1
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      LOADP
ST6:    SEP     R4
        DW      DRAWALL
; ---- the keys
LOOP:   SEP     R4
        DW      KEY
        PLO     R7
        LOAD    RD, KEYV
        GLO     R7
        STR     RD
        LOAD    RD, MSGF        ; a message showing: the file's line again
        LDN     RD
        LBZ     LP1
        LDI     0
        STR     RD
        SEP     R4
        DW      INFO
LP1:    SEP     R4              ; the active pane
        DW      ACTCP
        LOAD    RD, KEYV
        LDN     RD
        LBZ     LOOP
        LOAD    RF, KTAB        ; KTAB: key, routine (2) ... 0
LP2:    LDA     RF
        LBZ     LOOP            ; (not a key LC knows)
        STR     R2
        LDN     RD
        XOR
        LBZ     LP3
        INC     RF
        INC     RF
        LBR     LP2
LP3:    LOAD    RD, JMPV        ; the routine: called through an LBR in RAM, then the next key
        LDI     0C0H
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        SEP     R4
        DW      JMPV
        LBR     LOOP
KTAB:   DB      KUP
        DW      DOUP
        DB      KDN
        DW      DODN
        DB      KPU
        DW      DOPU
        DB      KPD
        DW      DOPD
        DB      KHM
        DW      DOHM
        DB      KEN
        DW      DOEN
        DB      09H
        DW      DOTAB
        DB      KLT
        DW      DOTAB
        DB      KRT
        DW      DOTAB
        DB      0DH
        DW      DOENT
        DB      08H
        DW      GOUP
        DB      7FH
        DW      GOUP
        DB      ' '
        DW      DOTAG
        DB      KINS
        DW      DOTAG
        DB      '*'
        DW      TAGALL
        DB      '-'
        DW      UNTAG
        DB      '+'
        DW      TAGALL
        DB      12H
        DW      DORELD
        DB      '1'
        DW      HELP
        DB      '2'
        DW      FINFO
        DB      '3'
        DW      VIEW
        DB      '4'
        DW      RENAME
        DB      '5'
        DW      COPY
        DB      '6'
        DW      MOVE
        DB      '7'
        DW      MKDIR
        DB      '8'
        DW      DELETE
        DB      KDEL
        DW      DELETE
        DB      '9'
        DW      RUN
        DB      'E'
        DW      EDIT
        DB      'e'
        DW      EDIT
        DB      ESC
        DW      QUIT
        DB      0

; ==== the actions: the active pane in CP; each one returns to LOOP
RET0:   SEP     R5
DOUP:   LDI     P_CUR
        SEP     R4
        DW      GETF
        LBZ     RET0
        SMI     1
        LBR     SETCUR
DODN:   LDI     P_CUR
        SEP     R4
        DW      GETF
        ADI     1
        PLO     R7
        LDI     P_N
        SEP     R4
        DW      GETF
        STR     R2
        GLO     R7
        SM
        LBDF    RET0
        GLO     R7
        LBR     SETCUR
DOPU:   LDI     P_CUR
        SEP     R4
        DW      GETF
        SMI     ROWS
        LBDF    SETCUR
        LDI     0
        LBR     SETCUR
DOPD:   LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        SMI     1
        PLO     R7              ; the last
        LDI     P_CUR
        SEP     R4
        DW      GETF
        ADI     ROWS
        PHI     R7
        STR     R2
        GLO     R7
        SM                      ; last - (cur + ROWS)
        LBNF    DOEN
        GHI     R7
        LBR     SETCUR
DOHM:   LDI     0
        LBR     SETCUR
DOEN:   LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        SMI     1
; SETCUR: the cursor to entry D (one there): its line and the one it left drawn again, or the pane scrolled
SETCUR: PLO     R7
        LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        LDI     P_CUR
        SEP     R4
        DW      PFLD
        LDN     RD
        PLO     R8              ; the old
        GLO     R7
        STR     RD
        LOAD    RD, OLDCV
        GLO     R8
        STR     RD
        LDI     P_TOP
        SEP     R4
        DW      GETF
        STR     R2
        GLO     R7
        SM                      ; new - top
        LBNF    SC1
        SMI     ROWS
        LBDF    SC2
        LDI     P_TOP           ; on the screen: the old line, the new
        SEP     R4
        DW      GETF
        STR     R2
        LOAD    RD, OLDCV
        LDN     RD
        SM
        SEP     R4
        DW      ROWDRAW
        LDI     P_CUR
        SEP     R4
        DW      GETF
        PLO     R7
        LDI     P_TOP
        SEP     R4
        DW      GETF
        STR     R2
        GLO     R7
        SM
        SEP     R4
        DW      ROWDRAW
        LBR     INFO
SC1:    LDI     P_TOP           ; above: it is the first line
        SEP     R4
        DW      PFLD
        GLO     R7
        STR     RD
        LBR     SC3
SC2:    GLO     R7              ; below: it is the last line
        SMI     ROWS - 1
        PLO     R8
        LDI     P_TOP
        SEP     R4
        DW      PFLD
        GLO     R8
        STR     RD
SC3:    SEP     R4
        DW      ROWSALL
        LBR     INFO

; Tab (or an arrow across): the other pane is the active one
DOTAB:  LOAD    RD, ACT
        LDN     RD
        XRI     1
        STR     RD
        LDI     0
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      PANEHL
        LDI     1
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      PANEHL
        LBR     INFO
PANEHL: LDI     P_CUR           ; a pane's cursor line and its top (the path shown reversed when active)
        SEP     R4
        DW      GETF
        PLO     R7
        LDI     P_TOP
        SEP     R4
        DW      GETF
        STR     R2
        GLO     R7
        SM
        SEP     R4
        DW      ROWDRAW
        LBR     FRAMETOP

; Enter: a folder - into it ('..': up); a file - later (Run, View)
DOENT:  LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        LDI     P_CUR
        SEP     R4
        DW      GETF
        PLO     R7
        LDI     P_UP
        SEP     R4
        DW      GETF
        LBZ     DE1
        GLO     R7
        LBZ     GOUP
DE1:    GLO     R7
        SEP     R4
        DW      ENTP
        LOAD    RD, RECP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     10H
        LBZ     RUNENT          ; a file: Run it (if it is a kind LC runs), else View it
        LDI     P_PATH          ; room in the path for /NAME.EXT?
        SEP     R4
        DW      PFLD
        LDI     0
        PLO     R8
DE2:    LDA     RD
        LBZ     DE3
        INC     R8
        LBR     DE2
DE3:    GLO     R8
        SMI     PATHL - 14
        LBDF    TOODEEP
        DEC     RD              ; at its 0: "/" alone gets the name, any other a / first
        GLO     R8
        XRI     1
        LBZ     DE4
        LDI     '/'
        STR     RD
        INC     RD
DE4:    GHI     RD
        PHI     RA
        GLO     RD
        PLO     RA
        LOAD    RD, RECP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      NAMEFMT
        LDI     0
        STR     RA
        LOAD    RD, RECP        ; its cluster: the pane's folder
        LDA     RD
        PHI     RF
        LDN     RD
        ADI     16
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDI     P_CLUS
        SEP     R4
        DW      PFLD
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        SEP     R4
        DW      LOADP
        LBR     NEWPANE
TOODEEP: SEP    R4
        DW      MSGI
        DB      'Too deep a folder for LC.',0
        SEP     R5
NOTYET: SEP     R4
        DW      MSGI
        DB      'Not in this LC yet.',0
        SEP     R5

; Backspace / '..': up a folder, the cursor on the folder just left
GOUP:   LDI     P_UP
        SEP     R4
        DW      GETF
        LBZ     RET0
        LDI     P_CLUS          ; WDIR and OLDCL = this folder
        SEP     R4
        DW      PFLD
        LOAD    RF, KS_WDIR
        LOAD    RC, OLDCL
        LDA     RD
        STR     RF
        STR     RC
        INC     RF
        INC     RC
        LDN     RD
        STR     RF
        STR     RC
        LOAD    RD, DOTDOT
        SEP     R4
        DW      KS_FOLDIN
        LBDF    RET0
        LDI     P_CLUS          ; the pane's folder = its parent
        SEP     R4
        DW      PFLD
        LOAD    RF, KS_WDIR
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        LDI     P_PATH          ; the path: its last /NAME gone ("/" stays)
        SEP     R4
        DW      PFLD
        GHI     RD
        PHI     RA
        PHI     RC
        GLO     RD
        PLO     RA
        PLO     RC
GU1:    LDN     RD
        LBZ     GU3
        XRI     '/'
        LBNZ    GU2
        GHI     RD
        PHI     RA
        GLO     RD
        PLO     RA
GU2:    INC     RD
        LBR     GU1
GU3:    GLO     RA
        STR     R2
        GLO     RC
        XOR
        LBNZ    GU4
        GHI     RA
        STR     R2
        GHI     RC
        XOR
        LBNZ    GU4
        INC     RA
GU4:    LDI     0
        STR     RA
        SEP     R4
        DW      LOADP
        LDI     P_N             ; the folder left (its cluster OLDCL): the cursor on it
        SEP     R4
        DW      GETF
        PHI     R8
        LDI     0
        PLO     R8
GU5:    GLO     R8
        STR     R2
        GHI     R8
        XOR
        LBZ     NEWPANE
        GLO     R8
        SEP     R4
        DW      ENTP
        GLO     RF
        ADI     16
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LOAD    RC, OLDCL
        LDA     RC
        STR     R2
        LDA     RD
        XOR
        LBNZ    GU6
        LDN     RC
        STR     R2
        LDN     RD
        XOR
        LBZ     GU7
GU6:    INC     R8
        LBR     GU5
GU7:    LDI     P_CUR
        SEP     R4
        DW      PFLD
        GLO     R8
        STR     RD
        GLO     R8
        SMI     ROWS
        LBNF    NEWPANE
        GLO     R8
        SMI     ROWS / 2
        PLO     R8
        LDI     P_TOP
        SEP     R4
        DW      PFLD
        GLO     R8
        STR     RD
; ==== LC.OVL's parts: VIEW and FINFO (part 0); RENAME MOVE MKDIR DELETE (part 1); HELP (part 2); COPY (part 3)
VIEW:   LDI     0
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 3
FINFO:  LDI     0
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 6
HELP:   LDI     2               ; part 2: Help
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 3
RUNENT: LDI     1               ; Enter on a file: Run (part 4) - not a kind it runs: View
        LSKP
RUN:    LDI     0               ; 9 / F9: Run (not a kind it runs: said)
        STXD
        LDI     4
        SEP     R4
        DW      OVLD
        IRX
        LDX
        LBDF    RET0
        SEP     R4
        DW      OVLA + 3
        LBDF    VIEW
        SEP     R5
EDIT:   LDI     4               ; E: Edit with NANO (part 4, beside Run)
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 9
COPY:   LDI     3               ; part 3: Copy
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 3
RENAME: LDI     1               ; part 1: the jobs that change the card
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 3
MOVE:   LDI     1
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 6
MKDIR:  LDI     1
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 9
DELETE: LDI     1
        SEP     R4
        DW      OVLD
        LBDF    RET0
        LBR     OVLA + 12
; OVLD: part D of LC (LCd.OVL) in OVLA, read unless it is there already. Each part's file is looked for once - in
;   /BIN and its folders, here, the root - and where it starts kept (OVDC: 6 bytes a part, its DCLUS and DSIZE;
;   OVFND: a bit a part). DF = 1: not found, or not this LC's (said on row 22).
OVLD:   PLO     R7
        LOAD    RD, OVCUR
        LDN     RD
        STR     R2
        GLO     R7
        XOR
        LBZ     GRNO
        LOAD    RD, OVSEG
        GLO     R7
        STR     RD
        ADI     '0'             ; its file's name: LC0 .. LC3
        PLO     R8
        LOAD    RD, OVLN + 2
        GLO     R8
        STR     RD
        SEP     R4              ; R9.0 = its bit, RA -> its OVDC
        DW      OVBIT
        LOAD    RD, OVFND
        LDN     RD
        STR     R2
        GLO     R9
        AND
        LBNZ    OL2
        LOAD    RD, OVLN        ; /BIN and its folders
        SEP     R4
        DW      BINFN
        LBNF    OL1
        LOAD    RD, KS_CWD      ; here
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, OVLN
        SEP     R4
        DW      KS_FINDN
        LBNF    OL1
        LOAD    RD, KS_WDIR     ; the root
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, OVLN
        SEP     R4
        DW      KS_FINDN
        LBDF    OLBAD
OL1:    SEP     R4
        DW      OVBIT
        LOAD    RF, KS_DCLUS    ; (DCLUS, then DSIZE)
        GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
        LOAD    RC, 6
        SEP     R4
        DW      MCOPY
        SEP     R4
        DW      OVBIT
        LOAD    RD, OVFND
        GLO     R9
        SEX     RD
        OR
        STR     RD
        SEX     R2
OL2:    LOAD    RD, OVCUR       ; (none there while it is read)
        LDI     0FFH
        STR     RD
        SEP     R4
        DW      OVBIT
        GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        LOAD    RD, KS_DCLUS
        LOAD    RC, 6
        SEP     R4
        DW      MCOPY
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, OLCNT       ; OVSECS sectors (or to its end) into OVLA
        LDI     OVSECS
        STR     RD
        LOAD    RD, OLDST
        LDI     HIGH(OVLA)
        STR     RD
        INC     RD
        LDI     LOW(OVLA)
        STR     RD
OL7:    SEP     R4
        DW      KS_FREAD
        LBDF    OL8
        LOAD    RD, OLDST
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LOAD    RF, KS_DATBUF
OL7A:   LDA     RF
        STR     R8
        INC     R8
        DEC     RC
        GLO     RC
        LBNZ    OL7A
        GHI     RC
        LBNZ    OL7A
        LOAD    RD, OLDST
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        LOAD    RD, OLCNT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    OL7
OL8:    LOAD    RD, OVLA        ; this LC's part, the one wanted?
        LDA     RD
        XRI     HIGH(PEND)
        LBNZ    OLBAD
        LDA     RD
        XRI     LOW(PEND)
        LBNZ    OLBAD
        LDN     RD
        STR     R2
        LOAD    RD, OVSEG
        LDN     RD
        XOR
        LBNZ    OLBAD
        LOAD    RD, OVCUR
        LDN     R2
        STR     RD
        LBR     GRNO
; OVBIT: R9.0 = OVSEG's bit in OVFND, RA -> its 6 bytes in OVDC
OVBIT:  LOAD    RD, OVSEG
        LDN     RD
        PLO     R8
        SHL
        STR     R2
        SHL
        ADD
        ADI     LOW(OVDC)
        PLO     RA
        LDI     HIGH(OVDC)
        ADCI    0
        PHI     RA
        LDI     1
        PLO     R9
OB1:    GLO     R8
        LBZ     RET0
        GLO     R9
        SHL
        PLO     R9
        DEC     R8
        LBR     OB1
OLBAD:  SEP     R4              ; (looked for again next time)
        DW      OVBIT
        LOAD    RD, OVFND
        GLO     R9
        XRI     0FFH
        SEX     RD
        AND
        STR     RD
        SEX     R2
        SEP     R4
        DW      MSGI
        DB      'A part of LC (LC0-LC4.OVL) is missing, or from another LC: RECV SYSTEM again.',0
        LBR     GRYES
OVLN:   DB      'LC0     OVL'
        INCL    "binfn.inc"

; NEWPANE: the pane drawn (top, lines, bottom), then the file's line
NEWPANE: SEP    R4
        DW      PANEDRAW
        LBR     INFO
PANEDRAW: SEP   R4
        DW      FRAMETOP
        SEP     R4
        DW      ROWSALL
        LBR     FRAMEBOT

; Space / Ins: the file tagged or not, then down; '*' '+': every file tagged; '-': none
DOTAG:  LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        LDI     P_CUR
        SEP     R4
        DW      GETF
        PLO     R7
        LDI     P_UP
        SEP     R4
        DW      GETF
        LBZ     DG1
        GLO     R7
        LBZ     DODN            ; ('..' is never tagged)
DG1:    GLO     R7
        SEP     R4
        DW      ENTP
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        XRI     80H
        STR     RD
        LDI     P_CUR
        SEP     R4
        DW      GETF
        PLO     R7
        LDI     P_TOP
        SEP     R4
        DW      GETF
        STR     R2
        GLO     R7
        SM
        SEP     R4
        DW      ROWDRAW
        SEP     R4
        DW      FRAMEBOT
        LDI     P_CUR           ; down (at the last: its line again)
        SEP     R4
        DW      GETF
        ADI     1
        PLO     R7
        LDI     P_N
        SEP     R4
        DW      GETF
        STR     R2
        GLO     R7
        SM
        LBDF    INFO
        GLO     R7
        LBR     SETCUR
TAGALL: LDI     80H
        LSKP
UNTAG:  LDI     0
        PLO     RB              ; RB.0 = the tag (folders: left as they are by '*', untagged by '-')
        LDI     P_N
        SEP     R4
        DW      GETF
        PHI     RC              ; RC.1 = N, RC.0 = i
        LDI     0
        PLO     RC
TG1:    GLO     RC
        STR     R2
        GHI     RC
        XOR
        LBZ     TG5
        GLO     RC
        SEP     R4
        DW      RECADR
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     10H
        LBZ     TG2
        GLO     RB
        LBNZ    TG3
        LDN     RD
        ANI     7FH
        STR     RD
        LBR     TG3
TG2:    GLO     RB
        STR     R2
        LDN     RD
        ANI     7FH
        OR
        STR     RD
TG3:    INC     RC
        LBR     TG1
TG5:    SEP     R4
        DW      ROWSALL
        LBR     FRAMEBOT

; ^R: both folders read again
DORELD: LDI     0
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      LOADP
        LDI     1
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      LOADP
        LBR     DRAWALL

; DRAWALL: the whole screen
DRAWALL: SEP    R4
        DW      INL
        DB      ESC,'[0m',ESC,'[?25l',ESC,'[2J',ESC,'[1;1H',ESC,'[7m',' LTOS Commander 0.2',0
        LDI     61
        PLO     R7
DA0:    SEP     R4
        DW      INL
        DB      ' ',0
        DEC     R7
        GLO     R7
        LBNZ    DA0
        SEP     R4
        DW      INL
        DB      ESC,'[0m',0
        LOAD    RD, LASTM
        LDI     0FFH
        STR     RD
        SEP     R4
        DW      CLOCK
        LDI     0
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      PANEDRAW
        LDI     1
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      PANEDRAW
        SEP     R4
        DW      INL
        DB      ESC,'[23;1H',' 1',ESC,'[7m','Help',ESC,'[0m',' 2',ESC,'[7m','Info',ESC,'[0m'
        DB      ' 3',ESC,'[7m','View',ESC,'[0m',' 4',ESC,'[7m','Ren',ESC,'[0m',' 5',ESC,'[7m','Copy',ESC,'[0m'
        DB      ' 6',ESC,'[7m','Move',ESC,'[0m',' 7',ESC,'[7m','MkDir',ESC,'[0m',' 8',ESC,'[7m','Del',ESC,'[0m'
        DB      ' 9',ESC,'[7m','Run',ESC,'[0m',' E',ESC,'[7m','Edit',ESC,'[0m','  Tab pane  Esc quit',0
        LBR     INFO

; Esc: the screen cleared, the cursor shown, back to LTOS
QUIT:   SEP     R4
        DW      INL
        DB      ESC,'[0m',ESC,'[2J',ESC,'[1;1H',ESC,'[?25h',0
        LBR     K_MAIN

; ==== a pane's folder: LOADP reads it (the pane in CP) - records, a ".." first if not the root, the index sorted
LOADP:  LDI     P_CLUS
        SEP     R4
        DW      PFLD
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, KS_PAT      ; every name
        LDI     11
        PLO     RB
LD1:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    LD1
        SEP     R4
        DW      KS_DOPEN
        LDI     P_N             ; N TOP CUR MORE UP: 0
        SEP     R4
        DW      PFLD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LDI     P_CLUS          ; not the root: ".." first
        SEP     R4
        DW      PFLD
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     LD3
        LDI     0
        SEP     R4
        DW      RECADR
        LOAD    RD, DOTDOT
        LDI     11
        PLO     RB
LD2:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    LD2
        LDI     10H
        STR     RF
        INC     RF
        LDI     10
        PLO     RB
LD2B:   LDI     0
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    LD2B
        LDI     0
        SEP     R4
        DW      IDXP
        LDI     0
        STR     RD
        LDI     P_N
        SEP     R4
        DW      PFLD
        LDI     1
        STR     RD
        LDI     P_UP
        SEP     R4
        DW      PFLD
        LDI     1
        STR     RD
LD3:    LDI     P_N             ; LNV = the records so far, LUP = UP
        SEP     R4
        DW      GETF
        PLO     R7
        LDI     P_UP
        SEP     R4
        DW      GETF
        PHI     R7
        LOAD    RD, LNV
        GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        LOAD    RF, CNUM        ; LMAXV = the pool less the other pane's records (PMAX at most)
        LDN     RF
        LBNZ    LD3A
        LOAD    RD, PANE1 + P_N
        LBR     LD3C
LD3A:   LOAD    RD, PANE0 + P_N
LD3C:   LDN     RD
        SDI     POOLN
        PLO     R8
        SMI     PMAX
        LBNF    LD3B
        LDI     PMAX
        PLO     R8
LD3B:   LOAD    RD, LMAXV
        GLO     R8
        STR     RD
LD4:    SEP     R4
        DW      KS_DNEXT
        LBDF    LD9
        GHI     RF              ; RC -> the entry
        PHI     RC
        GLO     RF
        PLO     RC
        LOAD    RD, LMAXV
        LDN     RD
        STR     R2
        LOAD    RD, LNV
        LDN     RD
        XOR
        LBNZ    LD5A
        LDI     P_MORE          ; no room: the rest not read
        SEP     R4
        DW      PFLD
        LDI     1
        STR     RD
        LBR     LD9
LD5A:   LOAD    RD, LNV
        LDN     RD
        SEP     R4
        DW      RECADR
        LDI     11
        PLO     RB
LD5:    LDA     RC
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    LD5
        LOAD    RD, KS_DATTR    ; the attribute (bit 7: not tagged), then DTIME DDATE DCLUS DSIZE after it
        LDA     RD
        ANI     7FH
        STR     RF
        INC     RF
        LDI     10
        PLO     RB
LD6:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    LD6
        GLO     RF              ; RC -> this record
        SMI     RECSZ
        PLO     RC
        GHI     RF
        SMBI    0
        PHI     RC
        LOAD    RD, LNV
        LDA     RD
        PLO     R8
        LDN     RD
        PLO     R7
        SEP     R4
        DW      INSERT
        LOAD    RD, LNV
        LDN     RD
        ADI     1
        STR     RD
        LBR     LD4
LD9:    LOAD    RD, LNV
        LDN     RD
        PLO     R7
        LDI     P_N
        SEP     R4
        DW      PFLD
        GLO     R7
        STR     RD
        SEP     R5
; INSERT: record N into the index, in order: a binary search over UP..N-1 (one call in it, RECADR - it runs ~8
;   times a record), then the index entries after it moved up. Each compare: a file after a folder, else the 11-byte names.
;   Called with R8.0 = the new record, R7.0 = UP, RC -> its record. R7.0 lo, R7.1 hi, R8.1 mid, RB.1 the index
;   page, RB.0 the new one's folder bit, RF -> index[mid]'s record (RECADR).
INSERT: GLO     R8              ; (R8.0 the new record, R7.0 lo, RC -> the new record: the caller's)
        PHI     R7
        LOAD    RD, CIDX
        LDN     RD
        PHI     RB
        GLO     RC              ; RB.0 = the new one's folder bit
        ADI     11
        PLO     RD
        GHI     RC
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     10H
        PLO     RB
IS1:    GLO     R7
        STR     R2
        GHI     R7
        XOR
        LBZ     IS5
        GLO     R7              ; mid = (lo + hi) / 2
        STR     R2
        GHI     R7
        ADD
        SHRC
        PHI     R8
        PLO     RD              ; RF -> index[mid]'s record
        GHI     RB
        PHI     RD
        LDN     RD
        SEP     R4
        DW      RECADR
        GLO     RF              ; its folder bit against the new one's
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     10H
        STR     R2
        GLO     RB
        XOR
        LBZ     IS3
        GLO     RB              ; differ: index[mid] is after the new one if the new one is the folder
        LBNZ    ISHI
        LBR     ISLO
IS3:    GHI     RC              ; the same kind: the names (RA walks the new one's)
        PHI     RA
        GLO     RC
        PLO     RA
        LDI     11
        PLO     R9
IS4:    LDA     RA
        STR     R2
        LDA     RF
        SM                      ; mid's - new's: DF = 1 (and not 0) if mid's is after
        LBNZ    IS4B
        DEC     R9
        GLO     R9
        LBNZ    IS4
        LBR     ISLO
IS4B:   LBNF    ISLO
ISHI:   GHI     R8              ; index[mid] after the new one: hi = mid
        PHI     R7
        LBR     IS1
ISLO:   GHI     R8              ; else lo = mid + 1
        ADI     1
        PLO     R7
        LBR     IS1
IS5:    GLO     R8              ; index[lo + 1 .. N] = index[lo .. N - 1]; index[lo] = the new
        PLO     RD
        GHI     RB
        PHI     RD
IS6:    GLO     RD
        STR     R2
        GLO     R7
        XOR
        LBZ     IS7
        DEC     RD
        LDN     RD
        INC     RD
        STR     RD
        DEC     RD
        LBR     IS6
IS7:    GLO     R8
        STR     RD
        SEP     R5
GRNO:   LDI     0
        SHR
        SEP     R5
GRYES:  LDI     1
        SHR
        SEP     R5

; ==== a pane's fields: SETCP (D = 0 / 1) and ACTCP (the active one) set CP; PFLD: RD -> field D; GETF: D = it
ACTCP:  LOAD    RD, ACT
        LDN     RD
SETCP:  LBNZ    SP1
        LOAD    RF, PANE0
        LBR     SP2
SP1:    LOAD    RF, PANE1
SP2:    LOAD    RD, CP          ; CP, and CIDX CNUM for IDXP and RECADR
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GLO     RF
        ADI     P_IDXH
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, CIDX        ; CIDX = its index page, CNUM = which pane
        LDN     RF
        STR     RD
        INC     RD
        INC     RF
        INC     RF
        INC     RF
        LDN     RF
        STR     RD
        SEP     R5
PFLD:   STXD
        LOAD    RD, CP + 1
        IRX
        LDN     RD
        ADD
        STR     R2
        DEC     RD
        LDN     RD
        ADCI    0
        PHI     RD
        LDN     R2
        PLO     RD
        SEP     R5
GETF:   SEP     R4
        DW      PFLD
        LDN     RD
        SEP     R5
ISACT:  LDI     P_NUM           ; DF = 1: CP is the active pane
        SEP     R4
        DW      GETF
        STR     R2
        LOAD    RD, ACT
        LDN     RD
        XOR
        LBZ     GRYES
        LBR     GRNO
; IDXP: RD -> index entry D.  RECADR: RF -> record D (in the pool: the pane's end of it; RD R9 used).
; ENTP: RF -> entry D's record
IDXP:   STXD
        LOAD    RD, CIDX
        LDN     RD
        PHI     RD
        IRX
        LDX
        PLO     RD
        SEP     R5
ENTP:   SEP     R4
        DW      IDXP
        LDN     RD
RECADR: PLO     RF              ; RF = 22i: 2i, + 4i, + 16i
        LDI     0
        PHI     RF
        GLO     RF
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF
        GLO     RF
        PLO     R9
        GHI     RF
        PHI     R9              ; R9 = 2i
        GLO     RF
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF              ; 4i
        GLO     RF
        STR     R2
        GLO     R9
        ADD
        PLO     R9
        GHI     RF
        STR     R2
        GHI     R9
        ADC
        PHI     R9              ; R9 = 6i
        GLO     RF
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF
        GLO     RF
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF              ; 16i
        GLO     R9
        STR     R2
        GLO     RF
        ADD
        PLO     RF
        GHI     R9
        STR     R2
        GHI     RF
        ADC
        PHI     RF              ; 22i
        LOAD    RD, CNUM
        LDN     RD
        LBNZ    RQ2
        GLO     RF              ; the left: POOL + 22i
        ADI     LOW(POOL)
        PLO     RF
        GHI     RF
        ADCI    HIGH(POOL)
        PHI     RF
        SEP     R5
RQ2:    GLO     RF              ; the right: POOLE - 22 - 22i
        SDI     LOW(POOLE - RECSZ)
        PLO     RF
        GHI     RF
        SDBI    HIGH(POOLE - RECSZ)
        PHI     RF
        SEP     R5

; ==== drawing
; FRAMETOP: row 2 of a pane: +- PATH -----+ (the active pane's path reversed; a long one: ... and its end)
FRAMETOP: LDI   P_COL
        SEP     R4
        DW      GETF
        PLO     RB
        LDI     2
        PHI     RB
        SEP     R4
        DW      CUP
        SEP     R4
        DW      INL
        DB      '+- ',0
        SEP     R4
        DW      ISACT
        LBNF    FT1
        SEP     R4
        DW      INL
        DB      ESC,'[7m',0
FT1:    LDI     P_PATH
        SEP     R4
        DW      PFLD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        LDI     0
        PLO     R8
FT2:    LDA     RF
        LBZ     FT3
        INC     R8
        LBR     FT2
FT3:    GLO     R8
        SMI     35
        LBNF    FT4
        SEP     R4
        DW      INL
        DB      '...',0
        GLO     R8
        SMI     31
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LDI     34
        PLO     R8
FT4:    GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      INL
        DB      ESC,'[0m',' ',0
        GLO     R8
        SDI     35
        PLO     R8
FT5:    GLO     R8
        LBZ     FT6
        SEP     R4
        DW      INL
        DB      '-',0
        DEC     R8
        LBR     FT5
FT6:    SEP     R4
        DW      INL
        DB      '+',0
        SEP     R5
; ROWSALL: every line of the pane.  ROWDRAW: line D (|, the entry or blanks, |; the cursor's reversed if active)
ROWSALL: LOAD   RD, RRC
        LDI     0
        STR     RD
RS1:    LOAD    RD, RRC
        LDN     RD
        SEP     R4
        DW      ROWDRAW
        LOAD    RD, RRC
        LDN     RD
        ADI     1
        STR     RD
        XRI     ROWS
        LBNZ    RS1
        SEP     R5
ROWDRAW: PLO    R7
        LOAD    RD, RRV
        GLO     R7
        STR     RD
        LDI     P_COL
        SEP     R4
        DW      GETF
        PLO     RB
        GLO     R7
        ADI     3
        PHI     RB
        SEP     R4
        DW      CUP
        SEP     R4
        DW      INL
        DB      '|',0
        LDI     P_TOP
        SEP     R4
        DW      GETF
        STR     R2
        LOAD    RD, RRV
        LDN     RD
        ADD
        PLO     R7              ; the entry
        LOAD    RD, EV
        GLO     R7
        STR     RD
        LDI     P_N
        SEP     R4
        DW      GETF
        STR     R2
        GLO     R7
        SM
        LBDF    RW8
        LOAD    RD, REVF
        LDI     0
        STR     RD
        SEP     R4
        DW      ISACT
        LBNF    RW1
        LDI     P_CUR
        SEP     R4
        DW      GETF
        STR     R2
        LOAD    RD, EV
        LDN     RD
        XOR
        LBNZ    RW1
        LOAD    RD, REVF
        LDI     1
        STR     RD
        SEP     R4
        DW      INL
        DB      ESC,'[7m',0
RW1:    LOAD    RD, EV
        LDN     RD
        SEP     R4
        DW      ENTP
        SEP     R4
        DW      FMTENT
        LOAD    RF, LBUF
        SEP     R4
        DW      PUTS
        LOAD    RD, REVF
        LDN     RD
        LBZ     RW9
        SEP     R4
        DW      INL
        DB      ESC,'[0m',0
        LBR     RW9
RW8:    LOAD    RF, SP38
        SEP     R4
        DW      PUTS
RW9:    SEP     R4
        DW      INL
        DB      '|',0
        SEP     R5
; FMTENT: the record at RF as a pane line in LBUF (38): tag, NAME.EXT (12), size or <DIR> (10), ' ', yy-mm-dd hh:mm
FMTENT: LOAD    RD, RECP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RA, LBUF
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     80H
        LBZ     FE1
        LDI     '>'
        LSKP
FE1:    LDI     ' '
        STR     RA
        INC     RA
        GHI     RF
        PHI     RC
        GLO     RF
        PLO     RC
        SEP     R4
        DW      NAMEFMT
FE2:    GLO     RA
        XRI     LOW(LBUF + 13)
        LBZ     FE3
        LDI     ' '
        STR     RA
        INC     RA
        LBR     FE2
FE3:    SEP     R4
        DW      GETREC          ; RF -> the record again
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     10H
        LBZ     FE5
        LDN     RF
        XRI     '.'
        LBNZ    FE4
        LOAD    RF, SUP
        LBR     FE4A
FE4:    LOAD    RF, SDIRT
FE4A:   SEP     R4
        DW      CPYS
        LBR     FE6
FE5:    SEP     R4
        DW      SIZE87          ; R8:R7 = its size
        LDI     10
        SEP     R4
        DW      U32PAD
FE6:    LDI     ' '
        STR     RA
        INC     RA
        SEP     R4
        DW      GETREC
        LDN     RF
        XRI     '.'
        LBZ     FE7
        SEP     R4
        DW      DATE14
        LBR     FE8
FE7:    LOAD    RF, SP38 + 24
        SEP     R4
        DW      CPYS
FE8:    LDI     0
        STR     RA
        SEP     R5
GETREC: LOAD    RF, RECP
        LDA     RF
        STR     R2
        LDN     RF
        PLO     RF
        LDN     R2
        PHI     RF
        SEP     R5
SIZE87: SEP     R4              ; R8:R7 = the size of the record RECP
        DW      GETREC
        GLO     RF
        ADI     18
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     R8
        LDA     RD
        PLO     R8
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R5
; NAMEFMT: the 11-byte name at RC as NAME.EXT at RA (RA past it; RB used)
NAMEFMT: LDI    8
        PLO     RB
NF1:    LDA     RC
        STR     R2
        XRI     ' '
        LBZ     NF2
        LDN     R2
        STR     RA
        INC     RA
NF2:    DEC     RB
        GLO     RB
        LBNZ    NF1
        LDN     RC
        XRI     ' '
        LBZ     NF9
        LDI     '.'
        STR     RA
        INC     RA
        LDI     3
        PLO     RB
NF3:    LDA     RC
        STR     R2
        XRI     ' '
        LBZ     NF4
        LDN     R2
        STR     RA
        INC     RA
NF4:    DEC     RB
        GLO     RB
        LBNZ    NF3
NF9:    SEP     R5
; DATE14: the record RF's date and time at RA: yy-mm-dd hh:mm (FULLY: yyyy-mm-dd hh:mm); none: blanks
DATE14: GLO     RF
        ADI     12
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     RC
        LDA     RD
        PLO     RC              ; RC = the time
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB              ; RB = the date
        GHI     RB
        STR     R2
        GLO     RB
        OR
        LBNZ    DA1
        LOAD    RF, SP38 + 24
        LBR     CPYS
DA1:    GHI     RB              ; the year: date >> 9 from 1980
        SHR
        PLO     R8
        LOAD    RD, FULLY
        LDN     RD
        LBZ     DA4
        GLO     R8
        SMI     20
        LBNF    DA2
        PLO     R8
        LDI     '2'
        STR     RA
        INC     RA
        LDI     '0'
        LBR     DA3
DA2:    GLO     R8
        ADI     80
        PLO     R8
        LDI     '1'
        STR     RA
        INC     RA
        LDI     '9'
DA3:    STR     RA
        INC     RA
        LBR     DA5
DA4:    GLO     R8
        ADI     80
        PLO     R8
        SMI     100
        LBNF    DA5
        PLO     R8
DA5:    GLO     R8
        SEP     R4
        DW      P2B
        LDI     '-'
        STR     RA
        INC     RA
        GHI     RB              ; the month: date >> 5 & 15
        SHR
        GLO     RB
        SHRC
        SHR
        SHR
        SHR
        SHR
        ANI     0FH
        SEP     R4
        DW      P2B
        LDI     '-'
        STR     RA
        INC     RA
        GLO     RB              ; the day
        ANI     1FH
        SEP     R4
        DW      P2B
        LDI     ' '
        STR     RA
        INC     RA
        GHI     RC              ; the hour: time >> 11
        SHR
        SHR
        SHR
        SEP     R4
        DW      P2B
        LDI     ':'
        STR     RA
        INC     RA
        GHI     RC              ; the minute: (hi & 7) << 3 | lo >> 5
        ANI     07H
        SHL
        SHL
        SHL
        STR     R2
        GLO     RC
        SHR
        SHR
        SHR
        SHR
        SHR
        OR
; P2B: D (0-99) as two digits at RA (R9 used)
P2B:    PLO     R9
        LDI     '0'
        PHI     R9
P2B1:   GLO     R9
        SMI     10
        LBNF    P2B2
        PLO     R9
        GHI     R9
        ADI     1
        PHI     R9
        LBR     P2B1
P2B2:   GHI     R9
        STR     RA
        INC     RA
        GLO     R9
        ADI     '0'
        STR     RA
        INC     RA
        SEP     R5
; FRAMEBOT: row 21 of a pane: +- 9 files, 4 folders ----+ (tagged ones: +- 2 tagged, 2944 bytes --+)
FRAMEBOT: LDI   P_COL
        SEP     R4
        DW      GETF
        PLO     RB
        LDI     21
        PHI     RB
        SEP     R4
        DW      CUP
        LDI     0
        PLO     RA
        PHI     RA
        PLO     RB
        PLO     R7
        PHI     R7
        PLO     R8
        PHI     R8
        LDI     P_N             ; RC.1 = N, RC.0 = i (from 1 past a "..")
        SEP     R4
        DW      GETF
        PHI     RC
        LDI     P_UP
        SEP     R4
        DW      GETF
        PLO     RC
FB1:    GLO     RC
        STR     R2
        GHI     RC
        XOR
        LBZ     FB5
        GLO     RC
        SEP     R4
        DW      RECADR
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     10H
        LBZ     FB2
        GHI     RA              ; a folder
        ADI     1
        PHI     RA
        LBR     FB3
FB2:    INC     RA              ; a file
FB3:    LDN     RD
        ANI     80H
        LBZ     FB4
        INC     RB              ; tagged: its size added
        GLO     RF
        ADI     21
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        SEX     RD
        GLO     R7
        ADD
        PLO     R7
        DEC     RD
        GHI     R7
        ADC
        PHI     R7
        DEC     RD
        GLO     R8
        ADC
        PLO     R8
        DEC     RD
        GHI     R8
        ADC
        PHI     R8
        SEX     R2
FB4:    INC     RC
        LBR     FB1
FB5:    LOAD    RD, NFIL        ; NFIL NFOL NTAG SUM
        GLO     RA
        STR     RD
        INC     RD
        GHI     RA
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        INC     RD
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        LOAD    RA, LBUF
        LOAD    RF, SFB
        SEP     R4
        DW      CPYS
        LOAD    RD, NTAG
        LDN     RD
        LBZ     FB7
        SEP     R4
        DW      U8STR
        LOAD    RF, STAGD
        SEP     R4
        DW      CPYS
        LOAD    RD, SUM
        LDA     RD
        PHI     R8
        LDA     RD
        PLO     R8
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LOAD    RF, SBYTES
        SEP     R4
        DW      CPYS
        LBR     FB8
FB7:    LOAD    RD, NFIL
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SFILE
        SEP     R4
        DW      CPYS
        LOAD    RD, NFIL
        LDN     RD
        SEP     R4
        DW      PLURAL
        LDI     ','
        STR     RA
        INC     RA
        LDI     ' '
        STR     RA
        INC     RA
        LOAD    RD, NFOL
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SFOLD
        SEP     R4
        DW      CPYS
        LOAD    RD, NFOL
        LDN     RD
        SEP     R4
        DW      PLURAL
FB8:    LDI     P_MORE
        SEP     R4
        DW      GETF
        LBZ     FB9
        LOAD    RF, SMORE
        SEP     R4
        DW      CPYS
FB9:    LDI     ' '
        STR     RA
        INC     RA
FB10:   GLO     RA
        XRI     LOW(LBUF + 39)
        LBZ     FB11
        LDI     '-'
        STR     RA
        INC     RA
        LBR     FB10
FB11:   LDI     '+'
        STR     RA
        INC     RA
        LDI     0
        STR     RA
        LOAD    RF, LBUF
        LBR     PUTS
PLURAL: XRI     1               ; D <> 1: an 's' at RA
        LBZ     PL9
        LDI     's'
        STR     RA
        INC     RA
PL9:    SEP     R5
; INFO: row 22 - the active pane's entry under the cursor: NAME.EXT, its size, date and time, attributes
INFO:   SEP     R4
        DW      ACTCP
        SEP     R4
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',0
        LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        LDI     P_CUR
        SEP     R4
        DW      GETF
        SEP     R4
        DW      ENTP
        LOAD    RD, RECP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RA, LBUF
        LDI     ' '
        STR     RA
        INC     RA
        GHI     RF
        PHI     RC
        GLO     RF
        PLO     RC
        SEP     R4
        DW      NAMEFMT
        SEP     R4
        DW      GETREC
        LDN     RF
        XRI     '.'
        LBNZ    IF1
        LOAD    RF, SUPF
        SEP     R4
        DW      CPYS
        LBR     IF8
IF1:    GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        PLO     R7
        LOAD    RD, ATTRV
        GLO     R7
        STR     RD
        ANI     10H
        LBZ     IF2
        LOAD    RF, SFOLDR
        SEP     R4
        DW      CPYS
        LBR     IF3
IF2:    GLO     RA
        XRI     LOW(LBUF + 14)
        LBZ     IF2A
        LDI     ' '
        STR     RA
        INC     RA
        LBR     IF2
IF2A:   SEP     R4
        DW      SIZE87
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LOAD    RF, SBYTES
        SEP     R4
        DW      CPYS
        LDI     ' '
        STR     RA
        INC     RA
IF3:    LDI     ' '
        STR     RA
        INC     RA
        LOAD    RD, FULLY
        LDI     1
        STR     RD
        SEP     R4
        DW      GETREC
        SEP     R4
        DW      DATE14
        LOAD    RD, FULLY
        LDI     0
        STR     RD
        LOAD    RD, ATTRV       ; read-only, hidden, system
        LDN     RD
        ANI     01H
        LBZ     IF4
        LOAD    RF, SRO
        SEP     R4
        DW      CPYS
IF4:    LOAD    RD, ATTRV
        LDN     RD
        ANI     02H
        LBZ     IF5
        LOAD    RF, SHID
        SEP     R4
        DW      CPYS
IF5:    LOAD    RD, ATTRV
        LDN     RD
        ANI     04H
        LBZ     IF8
        LOAD    RF, SSYS
        SEP     R4
        DW      CPYS
IF8:    LDI     0
        STR     RA
        LOAD    RF, LBUF
        LBR     PUTS
; MSGI: the text after the call on row 22 (until the next key)
MSGI:   SEP     R4
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',' ',0
MI1:    LDA     R6
        LBZ     MI2
        SEP     R4
        DW      PUTC
        LBR     MI1
MI2:    LOAD    RD, MSGF
        LDI     1
        STR     RD
        SEP     R5
; CLOCK: hh:mm at the top right, when the minute has changed (LASTM)
CLOCK:  LOAD    RD, CLKOFF      ; (not while LC -k waits under a program's output)
        LDN     RD
        LBNZ    RET0
        LDI     8BH
        SEP     R4
        DW      KS_RTCRD
        PLO     RB
        XRI     0FFH
        LBZ     RET0
        LDI     82H
        SEP     R4
        DW      KS_RTCBIN2
        PLO     R7
        LOAD    RD, LASTM
        LDN     RD
        STR     R2
        GLO     R7
        XOR
        LBZ     RET0
        GLO     R7
        STR     RD
        LDI     84H
        SEP     R4
        DW      KS_RTCRD
        ANI     7FH
        SEP     R4
        DW      KS_RTCBIN
        PHI     R7
        LOAD    RA, NUMB
        GHI     R7
        SEP     R4
        DW      P2B
        LDI     ':'
        STR     RA
        INC     RA
        GLO     R7
        SEP     R4
        DW      P2B
        LDI     0
        STR     RA
        SEP     R4
        DW      INL
        DB      ESC,'[1;75H',ESC,'[7m',0
        LOAD    RF, NUMB
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      INL
        DB      ESC,'[0m',0
        SEP     R5

; MCOPY: RC bytes from RF to RD
MCOPY:  LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    MCOPY
        GHI     RC
        LBNZ    MCOPY
        SEP     R5

; ==== numbers
; U8STR: D in decimal at RA.  U32PAD: R8:R7 at RA right-aligned in D columns.  U32STR: R8:R7 -> NUMB, D = its length
U8STR:  PLO     R7
        LDI     0
        PHI     R7
        PLO     R8
        PHI     R8
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        LBR     CPYS
U32PAD: STXD
        SEP     R4
        DW      U32STR
        PLO     R9
        IRX
        LDX
        STR     R2
        GLO     R9
        SD                      ; width - length
        LBNF    UP2
        LBZ     UP2
        PLO     R9
UP1:    LDI     ' '
        STR     RA
        INC     RA
        DEC     R9
        GLO     R9
        LBNZ    UP1
UP2:    LOAD    RF, NUMB
        LBR     CPYS
U32STR: LOAD    RF, NUMB        ; (as the kernel's PDEC32: 10^9 .. 10 taken away in turn)
        LOAD    RD, KS_P10TAB
        LDI     0
        PHI     RB
        LOAD    R9, PCNT
        LDI     9
        STR     R9
UQ1:    LDI     '0'
        PLO     RB
UQ2:    INC     RD
        INC     RD
        INC     RD
        SEX     RD
        GLO     R7
        SM
        PLO     RC
        DEC     RD
        GHI     R7
        SMB
        PHI     RC
        DEC     RD
        GLO     R8
        SMB
        PLO     R9
        DEC     RD
        GHI     R8
        SMB
        PHI     R9
        SEX     R2
        LBNF    UQ3
        GHI     R9
        PHI     R8
        GLO     R9
        PLO     R8
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        INC     RB
        LBR     UQ2
UQ3:    GLO     RB
        XRI     '0'
        LBNZ    UQ4
        GHI     RB
        LBZ     UQ5
UQ4:    GLO     RB
        STR     RF
        INC     RF
        LDI     1
        PHI     RB
UQ5:    INC     RD
        INC     RD
        INC     RD
        INC     RD
        LOAD    R9, PCNT
        LDN     R9
        SMI     1
        STR     R9
        LBNZ    UQ1
        GLO     R7
        ADI     '0'
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        GLO     RF
        SMI     LOW(NUMB)
        SEP     R5

; ==== the terminal
; CUP: the cursor to row RB.1, column RB.0 (R9 used)
CUP:    SEP     R4
        DW      INL
        DB      ESC,'[',0
        GHI     RB
        SEP     R4
        DW      PNUM8
        SEP     R4
        DW      INL
        DB      ';',0
        GLO     RB
        SEP     R4
        DW      PNUM8
        SEP     R4
        DW      INL
        DB      'H',0
        SEP     R5
PNUM8:  PLO     R9              ; D (0-99), no leading 0
        LDI     '0'
        PHI     R9
PN1:    GLO     R9
        SMI     10
        LBNF    PN2
        PLO     R9
        GHI     R9
        ADI     1
        PHI     R9
        LBR     PN1
PN2:    GHI     R9
        XRI     '0'
        LBZ     PN3
        GHI     R9
        SEP     R4
        DW      PUTC
PN3:    GLO     R9
        ADI     '0'
        LBR     PUTC
; CPYS: RF's text to RA (RA past it, no 0).  PUTS: RF's text out.  INL: the text after the call out.
CPYS:   LDA     RF
        LBZ     RET0
        STR     RA
        INC     RA
        LBR     CPYS
PUTS:   LDA     RF
        LBZ     RET0
        SEP     R4
        DW      PUTC
        LBR     PUTS
INL:    LDA     R6
        LBZ     RET0
        SEP     R4
        DW      PUTC
        LBR     INL
; PUTC: D out to the UART. One read of its status says both: a key come (caught into the ring, POLL) and room
;       to send. Every register kept (D aside).
PUTC:   STXD
PU1:    LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBDF    PU3
        ANI     10H             ; (bit 5, shifted)
        LBZ     PU1
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        IRX
        OUT     DATPORT
        DEC     R2
        SEP     R5
PU3:    SEP     R4
        DW      POLL
        LBR     PU1
; POLL: a byte from the UART, if one has come, into the ring (32; full: dropped). Every register kept (D aside).
POLL:   LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBNF    RET0
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        STXD
        GLO     RD
        STXD
        GHI     RD
        STXD
        LOAD    RD, KQT
        LDN     RD
        ADI     1
        ANI     1FH
        DEC     RD
        SEX     RD
        XOR
        SEX     R2
        LBZ     PO8             ; full
        INC     RD
        LDN     RD
        PLO     RD
        LDI     HIGH(RING)
        PHI     RD
        IRX
        IRX
        IRX
        LDN     R2
        STR     RD
        DEC     R2
        DEC     R2
        DEC     R2
        LOAD    RD, KQT
        LDN     RD
        ADI     1
        ANI     1FH
        STR     RD
PO8:    IRX
        LDXA
        PHI     RD
        LDXA
        PLO     RD
        LDX
        SEP     R5
; GETK: DF = 1 and D = the next key from the ring (POLL first); DF = 0: none. RD used.
GETK:   SEP     R4
        DW      POLL
        LOAD    RD, KQH
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        LBZ     GRNO
        LDN     R2
        PLO     RD
        LDI     HIGH(RING)
        PHI     RD
        LDN     RD
        STXD
        LOAD    RD, KQH
        LDN     RD
        ADI     1
        ANI     1FH
        STR     RD
        IRX
        LDX
        SMI     0
        SEP     R5
; KEY: the next key: arrows and the like as KUP .. KDEL, F1-F9 as '1'-'9', a lone Esc. The keys caught while
;   drawing (the ring) first; else the UART watched inline (a byte every ~58 instructions at 19200 baud: no
;   calls in the loop), the clock every few seconds. After an Esc, all that follows within ~30 ms is caught inline
;   into SEQB, then put in the ring after what it holds, and read from there. An Esc from the ring with nothing after it is dropped (the rest of
;   an arrow lost while LC was busy must not end it); a lone Esc typed while LC waits is Esc.
KEY:    SEP     R4
        DW      GETK
        LBNF    KW0
        PLO     R7
        XRI     ESC
        LBNZ    KYR
        LDI     1
        PHI     R7
        LBR     KESC
KYR:    GLO     R7
        SEP     R5
KW0:    LDI     0
        PLO     R8
        PHI     R8
KW1:    LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBDF    KW3
        DEC     R8
        GLO     R8
        LBNZ    KW1
        GHI     R8
        LBNZ    KW1
        SEP     R4
        DW      CLOCK
        LBR     KEY
KW3:    LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     R7
        XRI     ESC
        LBNZ    KYR
        PHI     R7              ; (R7.1 = 0: typed while LC waited)
KESC:   LOAD    RA, SEQB
        LOAD    R8, 700
KS1:    LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBDF    KS3
        DEC     R8
        GLO     R8
        LBNZ    KS1
        GHI     R8
        LBNZ    KS1
        LBR     KS5
KS3:    LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        STR     RA
        INC     RA
        GLO     RA
        XRI     LOW(SEQB + 15)
        LBNZ    KS1
KS5:    LDI     0               ; all of it into the ring after what is there (a second key in it kept)
        STR     RA
        LOAD    RA, SEQB
KS6:    LDA     RA
        LBZ     KS7
        SEP     R4
        DW      PUSHR
        LBR     KS6
KS7:    SEP     R4
        DW      GETK
        LBDF    KY3
        GHI     R7              ; nothing after it
        LBNZ    KEY
        LDI     ESC
        SEP     R5
KY3:    XRI     '['
        LBZ     KCSI
        XRI     '[' XOR 'O'
        LBNZ    KEY
        SEP     R4              ; Esc O x: F1-F4 (P-S), or an arrow / Home / End
        DW      GETK
        LBNF    KEY
        PLO     R7
        SMI     'P'
        LBNF    KFIN
        SMI     4
        LBDF    KFIN
        GLO     R7
        SMI     'P' - '1'
        SEP     R5
KCSI:   LDI     0               ; Esc [ n ~ or Esc [ x
        PHI     R7
KC1:    SEP     R4
        DW      GETK
        LBNF    KEY
        PLO     R7
        SMI     '0'
        LBNF    KC2
        SMI     10
        LBDF    KC2
        GHI     R7              ; n = n x 10 + the digit
        SHL
        STR     R2
        SHL
        SHL
        ADD
        STR     R2
        GLO     R7
        SMI     '0'
        ADD
        PHI     R7
        LBR     KC1
KC2:    GLO     R7
        XRI     '~'
        LBZ     KTIL
        GLO     R7
        XRI     ';'
        LBZ     KC1
KFIN:   LOAD    RF, KLTAB
KF1:    LDA     RF
        LBZ     KEY
        STR     R2
        GLO     R7
        XOR
        LBZ     KF2
        INC     RF
        LBR     KF1
KF2:    LDN     RF
        SEP     R5
KTIL:   GHI     R7
        SMI     22
        LBDF    KEY
        GHI     R7
        ADI     LOW(TILTAB)
        PLO     RF
        LDI     HIGH(TILTAB)
        ADCI    0
        PHI     RF
        LDN     RF
        LBZ     KEY
        SEP     R5
; PUSHR: D into the ring (full: dropped). RD used.
PUSHR:  STXD
        LOAD    RD, KQT
        LDN     RD
        ADI     1
        ANI     1FH
        DEC     RD
        SEX     RD
        XOR
        SEX     R2
        LBZ     PR8
        INC     RD
        LDN     RD
        PLO     RD
        LDI     HIGH(RING)
        PHI     RD
        IRX
        LDX
        STR     RD
        DEC     R2
        LOAD    RD, KQT
        LDN     RD
        ADI     1
        ANI     1FH
        STR     RD
PR8:    IRX
        SEP     R5
KLTAB:  DB      'A',KUP,'B',KDN,'C',KRT,'D',KLT,'H',KHM,'F',KEN,0
TILTAB: DB      0,KHM,KINS,KDEL,KEN,KPU,KPD,KHM,KEN,0,0,'1','2','3','4','5',0,'6','7','8','9',0

OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5

DOTDOT: DB      '..         '
SP38:   DB      '                                      ',0
SUP:    DB      '      <UP>',0
SDIRT:  DB      '     <DIR>',0
SUPF:   DB      '   up a folder',0
SFOLDR: DB      '/   folder',0
SBYTES: DB      ' bytes',0
SFB:    DB      '+- ',0
STAGD:  DB      ' tagged, ',0
SFILE:  DB      ' file',0
SFOLD:  DB      ' folder',0
SMORE:  DB      ' (more)',0
SRO:    DB      '  read-only',0
SHID:   DB      '  hidden',0
SSYS:   DB      '  system',0
PEND:
; ==== the variables (all 0 at the start)
VARS:
PANE0:  DS      PSZ
PANE1:  DS      PSZ
ACT:    DS      1
CP:     DS      2
LNV:    DS      1               ; LNV, LUP: in this order (LOADP)
LUP:    DS      1
CIDX:   DS      1               ; CIDX, CNUM: CP's index page, and 0 / 1 (which pane), in this order
CNUM:   DS      1
OVCUR:  DS      1               ; the part of LC.OVL in OVLA ($FF: none)
OVSEG:  DS      1
OVFND:  DS      1               ; a bit a part: its file found (OVDC)
OVDC:   DS      6 * 8           ; where each part's file starts (its DCLUS, DSIZE): 8 parts at most
OLCNT:  DS      1
OLDST:  DS      2
CLKOFF: DS      1               ; 1: the clock not drawn
RESMODE: DS     1               ; 'R' or 'K': LC -r / LC -k (back from a program)
LMAXV:  DS      1               ; LOADP: the most records this pane may have
KQH:    DS      1               ; KQH, KQT: in this order
KQT:    DS      1
KEYV:   DS      1
MSGF:   DS      1
JMPV:   DS      3
LASTM:  DS      1
RRV:    DS      1
RRC:    DS      1
EV:     DS      1
REVF:   DS      1
OLDCV:  DS      1
RECP:   DS      2
OLDCL:  DS      2
PCNT:   DS      1
NFIL:   DS      1               ; NFIL NFOL NTAG SUM: in this order
NFOL:   DS      1
NTAG:   DS      1
SUM:    DS      4
FULLY:  DS      1
ATTRV:  DS      1
VMODE:  DS      1               ; View: 0 text, 1 hex
VPG:    DS      1               ; the page shown
VEOFP:  DS      1               ; 1: this page reached the end
NODRAW: DS      1               ; 1: pages read, not drawn (End)
VFLAG:  DS      1               ; VTROW's: 1 a CR ended the last line, 2 the last row was full
VROW:   DS      1
VHN:    DS      1
VLEFT:  DS      2               ; the bytes left in DATBUF
VPTR:   DS      2               ; the next of them
VSNAP:  DS      7               ; FREAD's place (FCLUS FSEC FREM) before DATBUF's sector
VOFS:   DS      3               ; the hex offset
BROW:   DS      1               ; Info: the box's next row
VEND:
        END
