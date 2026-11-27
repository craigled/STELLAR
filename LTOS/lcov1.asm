; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lcov1.asm - LC.OVL's part 1: the jobs that change the card: Rename, Move, MkDir, Delete. Loaded by LC.PRG (OVLD) into OVLA when wanted; it uses LC.PRG's
;   routines and variables by their names (out/lcsyms.inc, written by build.py from lc.asm's listing).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
        INCL    "lc.inc"
        INCL    "out/lcsyms.inc"

        ORG     OVLA
        DW      PEND            ; (this LC.PRG's: LC.PRG checks it)
        DB      1
        LBR     OREN
        LBR     OMOVE
        LBR     OMKDIR
        LBR     ODEL

; ---- 4 / F4: Rename the entry under the cursor (its name offered, to be edited)
OREN:   SEP     R4
        DW      CURREC
        LBDF    RET0
        GHI     RF              ; ONAME = its name; INBUF = it as NAME.EXT
        PHI     RD
        GLO     RF
        PLO     RD
        LOAD    RC, ONAME
        SEP     R4
        DW      CP11
        LOAD    RC, ONAME
        LOAD    RA, INBUF
        SEP     R4
        DW      NAMEFMT
        LDI     0
        STR     RA
        SEP     R4
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',' Rename to (Esc: no): ',0
        SEP     R4
        DW      LINEIN
        LBDF    INFO
        SEP     R4
        DW      MKNAME
        LBDF    JBADN
        LOAD    RF, NBUF        ; the same name: nothing to do
        LOAD    RD, ONAME
        LDI     11
        PLO     RB
RN1:    LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    RN2
        DEC     RB
        GLO     RB
        LBNZ    RN1
        LBR     INFO
RN2:    SEP     R4
        DW      TRAPON
        SEP     R4              ; the new name must be free there
        DW      SETWD
        LOAD    RD, NBUF
        SEP     R4
        DW      KS_FINDN
        LBNF    JTHERE
        SEP     R4
        DW      SETWD
        LOAD    RD, ONAME
        SEP     R4
        DW      KS_FINDN
        LBDF    JGONE
        LOAD    RD, KS_DATTR
        LDN     RD
        PLO     R7
        LOAD    RD, JATTR
        GLO     R7
        STR     RD
        LOAD    RD, KS_ENTP     ; (as REN: its long name goes, the new short name in its place)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      KS_KILLLFN
        LBDF    KS_CARDF
        LOAD    RD, KS_ENTP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, NBUF
        SEP     R4
        DW      CP11
        LOAD    RD, KS_DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    KS_CARDF
        SEP     R4
        DW      TRAPOFF
        LOAD    RD, JATTR       ; a folder: the other pane in it follows to this one's folder
        LDN     RD
        ANI     10H
        LBZ     RN3
        LOAD    RC, ONAME
        SEP     R4
        DW      PATHNM
        SEP     R4
        DW      OTHFIX
RN3:    LOAD    RD, FINDNM
        LDI     1
        STR     RD
        SEP     R4
        DW      JDONE
        DB      'Renamed.',0
        SEP     R5

; ---- 7 / F7: MkDir - a new folder in this pane's folder
OMKDIR: LOAD    RD, INBUF
        LDI     0
        STR     RD
        SEP     R4
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',' A new folder (Esc: none): ',0
        SEP     R4
        DW      LINEIN
        LBDF    INFO
        SEP     R4
        DW      MKNAME
        LBDF    JBADN
        SEP     R4
        DW      TRAPON
        SEP     R4
        DW      SETWD
        LOAD    RD, NBUF
        SEP     R4
        DW      KS_FINDN
        LBNF    JTHERE
        LOAD    RD, NBUF
        LOAD    RC, KS_FNAME
        SEP     R4
        DW      CP11
        SEP     R4
        DW      SETWD
        SEP     R4
        DW      MK1             ; (mkfold.inc, as MKDIR)
        SEP     R4
        DW      TRAPOFF
        LOAD    RD, FINDNM
        LDI     1
        STR     RD
        SEP     R4
        DW      JDONE
        DB      'Folder made.',0
        SEP     R5

; ---- 6 / F6: Move the tagged entries (or the one under the cursor) to the other pane's folder: each entry
;   moves, its data stays where it is (MOVE1, as MV). A name the folder has already, or a folder into itself: left.
OMOVE:  SEP     R4
        DW      SDDIRS          ; SDIR = this pane's folder, DDIR = the other's
        LOAD    RD, SDIR
        LOAD    RC, DDIR
        LDA     RD
        STR     R2
        LDA     RC
        XOR
        LBNZ    MV1
        LDN     RD
        STR     R2
        LDN     RC
        XOR
        LBNZ    MV1
        SEP     R4
        DW      MSGI
        DB      'Both panes show this folder: Move moves to the other pane',39,'s.',0
        SEP     R5
MV1:    SEP     R4
        DW      SELECT
        LBDF    RET0
        SEP     R4              ; " Move NAME (or 3) to /PATH? (Y/N) "
        DW      JASK
        DB      ' Move ',0
        LOAD    RF, STO
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      OTHPATH
        LOAD    RF, SQYN
        SEP     R4
        DW      ASKYN
        LBNF    JNO
        SEP     R4
        DW      TRAPON
        SEP     R4
        DW      JZERO
MV2:    SEP     R4
        DW      NEXTSEL
        LBDF    MV9
MV3:    SEP     R4
        DW      MOVE1
        LBNF    MV4
        SMI     3               ; 1 a name there, 2 a folder into itself: left
        LBDF    JFAIL
        LOAD    RD, JN2
        LBR     MV5
MV4:    LOAD    RD, JN1
MV5:    LDN     RD
        ADI     1
        STR     RD
        LBR     MV2
MV9:    SEP     R4
        DW      TRAPOFF
        LOAD    RD, OTHRL
        LDI     1
        STR     RD
        SEP     R4
        DW      JDONE
        DB      0
        LOAD    RD, JN1         ; "3 moved to /DOCS." "1 not: its name is there, or a folder into itself."
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SMOVED
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      OTHPATH
        LDI     '.'
        STR     RA
        INC     RA
        LOAD    RD, JN2
        LDN     RD
        LBZ     JSAY
        LDI     ' '
        STR     RA
        INC     RA
        LOAD    RD, JN2
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SNOTM
        SEP     R4
        DW      CPYS
        LBR     JSAY

; ---- 8 / F8 / Del: Delete the tagged entries (or the one under the cursor): files to /TRASH (made if it is not
;   there; one of the same name there already goes - as DELETE), an empty folder for good (as RMDIR); a folder
;   with something in it, or the current folder, is left.
ODEL:   SEP     R4
        DW      SELECT
        LBDF    RET0
        SEP     R4
        DW      JASK
        DB      ' Delete ',0
        LOAD    RF, SDELQ
        SEP     R4
        DW      ASKYN
        LBNF    JNO
        SEP     R4
        DW      TRAPON
        SEP     R4
        DW      SDDIRS
        SEP     R4
        DW      TRASHD          ; DDIR = /TRASH
        LBDF    JTFILE
        LOAD    RD, SDIR        ; in /TRASH itself: EMPTY's job
        LOAD    RC, DDIR
        LDA     RD
        STR     R2
        LDA     RC
        XOR
        LBNZ    DL1
        LDN     RD
        STR     R2
        LDN     RC
        XOR
        LBNZ    DL1
        SEP     R4
        DW      TRAPOFF
        SEP     R4
        DW      UNSEL
        SEP     R4
        DW      MSGI
        DB      'These are in /TRASH already: EMPTY deletes them for good.',0
        SEP     R5
DL1:    SEP     R4
        DW      JZERO
DL2:    SEP     R4
        DW      NEXTSEL
        LBDF    DL9
        LOAD    RD, JATTR
        LDN     RD
        ANI     10H
        LBNZ    DLDIR
DL3:    SEP     R4              ; a file: to /TRASH
        DW      MOVE1
        LBNF    DL4
        XRI     1
        LBNZ    JFAILX
        LOAD    RD, DDIR        ; the trash has that name: the older one goes, then again
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, DNM
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_CARDF
        SEP     R4
        DW      KS_DELENT
        LBDF    KS_CARDF
        LBR     DL3
DL4:    LOAD    RD, JN1
        LBR     DL6
DLDIR:  LOAD    RD, SDIR        ; a folder: found (its cluster in DCLUS) ...
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, SNM1
        SEP     R4
        DW      KS_FINDN
        LBDF    JGONE
        LOAD    RD, KS_DCLUS    ; ... not the current folder ...
        LOAD    RC, KS_CWD
        LDA     RD
        STR     R2
        LDA     RC
        XOR
        LBNZ    DL5
        LDN     RD
        STR     R2
        LDN     RC
        XOR
        LBZ     DL5N
DL5:    LOAD    RD, KS_DCLUS    ; ... and empty (anything in it, hidden or not: QNAME matches all)
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, KS_QNAME
        SEP     R4
        DW      KS_FINDN
        LBNF    DL5N
        LOAD    RD, SDIR        ; then found again in its folder, and deleted
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, SNM1
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_CARDF
        SEP     R4
        DW      KS_DELENT
        LBDF    KS_CARDF
        LOAD    RC, SNM1        ; the other pane in it: to this one's folder
        SEP     R4
        DW      PATHNM
        SEP     R4
        DW      OTHFIX
        LOAD    RD, JN2
        LBR     DL6
DL5N:   LOAD    RD, JN3
DL6:    LDN     RD
        ADI     1
        STR     RD
        LBR     DL2
DL9:    SEP     R4
        DW      TRAPOFF
        LOAD    RD, OTHRL       ; (the other pane read again: it may show /TRASH, new or with more in it)
        LDI     1
        STR     RD
        SEP     R4
        DW      JDONE
        DB      0
        LOAD    RD, JN1         ; "3 moved to /TRASH." " 1 folder deleted." " 1 folder left (not empty)."
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, STRASH
        SEP     R4
        DW      CPYS
        LOAD    RD, JN2
        LDN     RD
        LBZ     DL10
        SEP     R4
        DW      U8STR
        LOAD    RF, SFOLD
        SEP     R4
        DW      CPYS
        LOAD    RD, JN2
        LDN     RD
        SEP     R4
        DW      PLURAL
        LOAD    RF, SDELD
        SEP     R4
        DW      CPYS
DL10:   LOAD    RD, JN3
        LDN     RD
        LBZ     JSAY
        SEP     R4
        DW      U8STR
        LOAD    RF, SFOLD
        SEP     R4
        DW      CPYS
        LOAD    RD, JN3
        LDN     RD
        SEP     R4
        DW      PLURAL
        LOAD    RF, SLEFT
        SEP     R4
        DW      CPYS
        LBR     JSAY
JTFILE: SEP     R4
        DW      TRAPOFF
        SEP     R4
        DW      UNSEL
        SEP     R4
        DW      MSGI
        DB      'A file called TRASH is in the root: Delete needs that name for a folder.',0
        SEP     R5
; TRASHD: DDIR = /TRASH's first cluster (made in the root if it is not there); DF = 1: a file has that name
TRASHD: SEP     R4
        DW      TFIND
        LBNF    TD2
        LOAD    RD, STRN
        LOAD    RC, KS_FNAME
        SEP     R4
        DW      CP11
        SEP     R4
        DW      MK1
        SEP     R4
        DW      TFIND
        LBDF    KS_CARDF
TD2:    LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBZ     GRYES
        LOAD    RD, KS_DCLUS
        LOAD    RC, DDIR
        SEP     R4
        DW      CP2
        LBR     GRNO
TFIND:  LOAD    RD, KS_WDIR
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, STRN
        LBR     KS_FINDN

; LINEIN: INBUF (0-ended, up to 12) shown after the prompt and edited: letters (made capitals), digits and the other
;   characters a name may have; Backspace. Enter: DF = 0; Esc: DF = 1. The cursor shown meanwhile.
LINEIN: SEP     R4
        DW      INL
        DB      ESC,'[?25h',0
        LOAD    RF, INBUF
        SEP     R4
        DW      PUTS
LI1:    SEP     R4
        DW      KEY
        PLO     R7
        XRI     0DH
        LBZ     LIOK
        GLO     R7
        XRI     ESC
        LBZ     LIESC
        GLO     R7
        XRI     08H
        LBZ     LIBS
        GLO     R7
        XRI     7FH
        LBZ     LIBS
        GLO     R7              ; a-z: A-Z
        SMI     'a'
        LBNF    LI2
        SMI     26
        LBDF    LI2
        GLO     R7
        SMI     20H
        PLO     R7
LI2:    GLO     R7              ; A-Z and 0-9 at once; the others looked for (a key caught first: POLL)
        SMI     'A'
        LBNF    LI2A
        SMI     26
        LBNF    LI4
LI2A:   GLO     R7
        SMI     '0'
        LBNF    LI2B
        SMI     10
        LBNF    LI4
LI2B:   SEP     R4
        DW      POLL
        LOAD    RF, NCHARS
LI3:    LDA     RF
        LBZ     LI1
        STR     R2
        GLO     R7
        XOR
        LBNZ    LI3
LI4:    SEP     R4
        DW      INEND
        XRI     12
        LBZ     LI1
        GLO     R7
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        GLO     R7
        SEP     R4
        DW      PUTC
        LBR     LI1
LIBS:   SEP     R4
        DW      INEND
        LBZ     LI1
        DEC     RF
        LDI     0
        STR     RF
        SEP     R4
        DW      INL
        DB      8,' ',8,0
        LBR     LI1
LIOK:   SEP     R4
        DW      INL
        DB      ESC,'[?25l',0
        LBR     GRNO
LIESC:  SEP     R4
        DW      INL
        DB      ESC,'[?25l',0
        LBR     GRYES
INEND:  LOAD    RF, INBUF       ; RF -> INBUF's 0, D = its length
        LDI     0
        PLO     R8
IE1:    LDN     RF
        LBZ     IE2
        INC     RF
        INC     R8
        LBR     IE1
IE2:    GLO     R8
        SEP     R5
; MKNAME: INBUF as an 11-byte name in NBUF (NAME    EXT); DF = 1: not a name (empty, '.' first, too long, two dots)
MKNAME: LOAD    RD, NBUF
        LDI     11
        PLO     RB
NM1:    LDI     ' '
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    NM1
        LOAD    RF, INBUF
        LOAD    RD, NBUF
        LDI     8
        PLO     RB
        LDN     RF
        LBZ     GRYES
        XRI     '.'
        LBZ     GRYES
NM2:    LDA     RF
        LBZ     GRNO
        PLO     R7
        XRI     '.'
        LBZ     NM3
        GLO     RB
        LBZ     GRYES
        GLO     R7
        STR     RD
        INC     RD
        DEC     RB
        LBR     NM2
NM3:    LOAD    RD, NBUF + 8
        LDI     3
        PLO     RB
NM4:    LDA     RF
        LBZ     GRNO
        PLO     R7
        XRI     '.'
        LBZ     GRYES
        GLO     RB
        LBZ     GRYES
        GLO     R7
        STR     RD
        INC     RD
        DEC     RB
        LBR     NM4
        INCL    "move1.inc"
        INCL    "mkfold.inc"

        INCL    "lcjobs.inc"
NCHARS: DB      '.-_!#$%&()@^{}~',39,96,0
STRN:   DB      'TRASH      '
SDELQ:  DB      '? Files go to /TRASH, an empty folder for good. (Y/N) ',0
SMOVED: DB      ' moved to ',0
SNOTM:  DB      ' not: its name is there, or a folder into itself.',0
STRASH: DB      ' moved to /TRASH. ',0
SDELD:  DB      ' deleted. ',0
SLEFT:  DB      ' left (not empty, or the current one).',0
ONAME:  DS      11              ; Rename: the old name
INBUF:  DS      14              ; a name being typed
OVEND:
        END
