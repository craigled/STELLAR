; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; ltcalc.asm - LTCALC.PRG: LTCALC [name] - a small spreadsheet in 1802 code: one page of 8 columns (A-H) by 20 rows.
;   A cell holds a number, text, or a formula: =A1+B1*2  =(A1-B2)/3  =SUM(A1:A10)  =AVG MIN MAX COUNT over ranges
;   (a list too: =SUM(A1:A3,C1:C3)). Numbers have two decimals: a 32-bit whole number of hundredths, up to
;   21,474,836.47 either way. Going past that, dividing by 0, a bad formula or a cell that needs itself shows ERR.
;
; The sheet in memory IS the file: a pool of lines, "A1 =B1*2" LF, in cell order (a line someone else put out of
; order still works; a line that names no cell stays in the file, unused). Saving writes the pool as it is, opening
; reads it as it is, and TYPE, GREP, RAWK and NANO can all use the file. A name with no extension gets .CLC.
;
; Memory, from the first page after the code, up to $6BFF:
;   seven pages, each indexed by the cell's number (0-159: row * 8 + column), so a cell's byte is one PLO away:
;   TYP  the kind (below) and its flags         tail: the variables
;   PH PL  where its line is in the pool (0: empty)   tail of PH: the typed line, the cell's text; of PL: the math
;   V0-V3  its value (V0 the top byte)          tail of V1: the value stack
;   then a page for the key ring, and the pool, to PTOP. LTOS's own buffers ($6C00 up) stay LTOS's: saving and opening are the kernel's.
;
; Recalculating: first the formulas that name a changed cell are found (a look through their text, far quicker than
; working them out), and those that name them, and so on. Those are marked waiting, then passes over them: a formula
; that meets a waiting cell stops and tries again next pass; one that finishes is done. So each is worked out once,
; in the order they need, and what still waits when a pass finishes nothing is a loop: ERR. Only cells that changed
; are sent to the screen.
;
; The terminal: the UART directly, as NANO: a key that comes while the screen is written is kept (a ring of 128).
; Registers: R7.0 the cell being worked on, R8 the text being read, R9 the value stack; RE.1 never touched.
; verify_ltcalc.py runs it on the simulated Elf2K.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

NCELL   EQU     160
GROW    EQU     4               ; the screen row of the sheet's row 1
GCOL    EQU     5               ; the screen column of column A
INMAX   EQU     60              ; the most characters typed into a cell
K_TEXT  EQU     1               ; the kinds (TYP's low 3 bits; 0: empty)
K_NUM   EQU     2
K_FORM  EQU     3               ; a formula with a value
K_FERR  EQU     4               ; a formula that failed
K_NERR  EQU     5               ; a number too big
F_WAIT  EQU     80H             ; TYP: a formula not worked out yet
F_DIRTY EQU     40H             ; TYP: to be sent to the screen
F_CHG   EQU     20H             ; TYP: changed, so what needs it must be worked out again
KUP     EQU     80H             ; RKEY's codes for the arrows
KDOWN   EQU     81H
KRIGHT  EQU     82H
KLEFT   EQU     83H

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        SEP     R4
        DW      KS_MNTCHK
        LOAD    RD, RHEAD       ; the key ring is empty
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, CHG
        LDI     0
        STR     RD
        INC     RD              ; NAMED
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     ST5             ; no name
        LOAD    RD, TMP11
        SEP     R4
        DW      KS_NAMEP
        SEP     R4
        DW      DEFEXT
        SEP     R4
        DW      KEEPNM
        SEP     R4
        DW      LOADFILE
        LOAD    RD, LRC
        LDN     RD
        LBZ     ST6             ; opened
        XRI     1
        LBZ     ST5             ; not there yet: a new sheet of that name
        SEP     R4
        DW      K_PIN
        DB      'That file cannot be opened as a sheet.',0DH,0AH,0
        LBR     K_MAIN
ST5:    SEP     R4
        DW      CLEAR
ST6:    SEP     R4
        DW      REDRAW
; ---- the main loop: the line above the sheet only when no key is waiting
MAINL:  SEP     R4
        DW      RXPOLL
        LOAD    RD, RHEAD
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        LBNZ    ML1
        LOAD    RD, SHOWP
        LDN     RD
        LBZ     ML1
        SEP     R4
        DW      SHOWCUR
ML1:    SEP     R4
        DW      RKEY
        LOAD    RD, KEY
        LDN     RD
        PLO     RC
        XRI     KUP
        LBZ     MVUP
        GLO     RC
        XRI     KDOWN
        LBZ     MVDOWN
        GLO     RC
        XRI     KRIGHT
        LBZ     MVRIGHT
        GLO     RC
        XRI     KLEFT
        LBZ     MVLEFT
        GLO     RC
        XRI     0DH
        LBZ     MVDOWN
        GLO     RC
        XRI     0AH
        LBZ     MVDOWN
        GLO     RC
        XRI     09H
        LBZ     MVRIGHT
        GLO     RC
        XRI     1BH
        LBZ     QUIT
        GLO     RC
        XRI     08H
        LBZ     WIPE
        GLO     RC
        XRI     7FH
        LBZ     WIPE
        GLO     RC
        XRI     05H             ; ^E
        LBZ     EDITC
        GLO     RC
        XRI     13H             ; ^S
        LBZ     SAVEK
        GLO     RC
        XRI     01H             ; ^A
        LBZ     SAVEAS
        GLO     RC
        XRI     0FH             ; ^O
        LBZ     OPENK
        GLO     RC              ; a printable key starts an entry
        SMI     20H
        LBNF    MAINL
        GLO     RC
        SHL
        LBDF    MAINL
        LOAD    RD, INB
        GLO     RC
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RD, INLEN
        LDI     1
        STR     RD
; ---- an entry: the line under the cell's, typed until Enter, Tab or an arrow takes it, or Esc drops it
EDGO:   LOAD    RD, ARROK
        LDI     1
        STR     RD
        LOAD    RC, 0201H
        SEP     R4
        DW      GOTO
        SEP     R4
        DW      TPIN
        DB      '> ',0
        LOAD    R8, INB
        SEP     R4
        DW      TSTR
        SEP     R4
        DW      EOL
        SEP     R4
        DW      EDLINE
        LOAD    RD, KEY
        LDN     RD
        XRI     1BH
        LBZ     EDCAN
        SEP     R4
        DW      SETCELL
        LBDF    MAINL           ; the sheet is full: it said so
        LOAD    RD, KEY
        LDN     RD
        PLO     RC
        XRI     KUP
        LBZ     MVUP
        GLO     RC
        XRI     KRIGHT
        LBZ     MVRIGHT
        GLO     RC
        XRI     09H
        LBZ     MVRIGHT
        GLO     RC
        XRI     KLEFT
        LBZ     MVLEFT
        LBR     MVDOWN          ; Enter, or the down arrow
EDCAN:  SEP     R4
        DW      SHOWCUR
        LBR     MAINL
; ^E: the cell's text to the entry line
EDITC:  SEP     R4
        DW      CURR7
        LOAD    RD, INB
        LDI     0
        PLO     RB
        GLO     R7
        PLO     RF
        LDI     HIGH(TYP)
        PHI     RF
        LDN     RF
        ANI     7
        LBZ     EC9             ; empty: nothing to fetch
        SEP     R4
        DW      SRCP
        LOAD    RD, INB
        LDI     0
        PLO     RB
EC1:    LDA     R8
        PLO     RC
        SMI     20H
        LBNF    EC9
        GLO     RC
        STR     RD
        INC     RD
        INC     RB
        GLO     RB
        XRI     INMAX
        LBNZ    EC1
EC9:    LDI     0
        STR     RD
        LOAD    RD, INLEN
        GLO     RB
        STR     RD
        LBR     EDGO
; Backspace or Delete on the sheet: the cell is emptied
WIPE:   LOAD    RD, INLEN
        LDI     0
        STR     RD
        LOAD    RD, INB
        LDI     0
        STR     RD
        SEP     R4
        DW      SETCELL
        LOAD    RD, SHOWP
        LDI     1
        STR     RD
        LBR     MAINL
; ---- moving: the old cell plain, the new one marked
MVUP:   SEP     R4
        DW      CURR7
        GLO     R7
        SMI     8
        LBNF    MVSTAY
        LBR     MVTO
MVDOWN: SEP     R4
        DW      CURR7
        GLO     R7
        ADI     8
        PLO     RC
        SMI     NCELL
        LBDF    MVSTAY
        GLO     RC
        LBR     MVTO
MVRIGHT: SEP    R4
        DW      CURR7
        GLO     R7
        ANI     7
        XRI     7
        LBZ     MVSTAY
        GLO     R7
        ADI     1
        LBR     MVTO
MVLEFT: SEP     R4
        DW      CURR7
        GLO     R7
        ANI     7
        LBZ     MVSTAY
        GLO     R7
        SMI     1
MVTO:   PLO     RC
        LOAD    RD, CUR
        GLO     RC
        STR     RD
        SEP     R4              ; R7 = the old cell: now plain
        DW      PUTCELL
        SEP     R4
        DW      CURR7
        SEP     R4
        DW      PUTCELL
MVSTAY: LOAD    RD, SHOWP
        LDI     1
        STR     RD
        LBR     MAINL
; ---- Esc: leave, asking first if there is something unsaved
QUIT:   LOAD    RD, CHG
        LDN     RD
        LBZ     QT5
        LOAD    R8, QQUIT
        SEP     R4
        DW      ASKYN
        LBDF    QT5
        SEP     R4
        DW      SHOWCUR
        LBR     MAINL
QT5:    SEP     R4
        DW      CLS
        LBR     K_MAIN
; ---- ^S: saved under its name (none yet: ^A's question). ^A: saved under a new name
SAVEK:  LOAD    RD, NAMED
        LDN     RD
        LBNZ    SV5
SAVEAS: LOAD    R8, QSAVE
        SEP     R4
        DW      ASKNAME
        LBDF    KCANCEL
        LOAD    RD, TMP11       ; there already?
        SEP     R4
        DW      KS_FINDN
        LBDF    SV3
        LOAD    R8, QREPL
        SEP     R4
        DW      ASKYN
        LBNF    KCANCEL
SV3:    SEP     R4
        DW      KEEPNM
SV5:    LOAD    RD, MYDIR       ; WDIR = the sheet's folder
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    R8, TOPV        ; RC = the pool's bytes
        LDA     R8
        PHI     RC
        LDN     R8
        PLO     RC
        GLO     RC
        SMI     LOW(POOL)
        PLO     RC
        GHI     RC
        SMBI    HIGH(POOL)
        PHI     RC
        LOAD    RD, NAME11
        LOAD    RA, POOL
        SEP     R4
        DW      K_SAVER
        LBDF    SV8
        LOAD    RD, CHG
        LDI     0
        STR     RD
        SEP     R4
        DW      STATUS
        LOAD    R8, MSAVED
        LBR     KMSG
SV8:    LOAD    R8, MNOSAVE
        LBR     KMSG
KCANCEL: SEP    R4
        DW      SHOWCUR
        LBR     MAINL
KMSG:   SEP     R4
        DW      MESSAGE
        LBR     MAINL
; ---- ^O: another sheet (the one here is kept if that one cannot be opened)
OPENK:  LOAD    RD, CHG
        LDN     RD
        LBZ     OK2
        LOAD    R8, QLOSE
        SEP     R4
        DW      ASKYN
        LBNF    KCANCEL
OK2:    LOAD    R8, QOPEN
        SEP     R4
        DW      ASKNAME
        LBDF    KCANCEL
        SEP     R4
        DW      LOADFILE
        LOAD    RD, LRC
        LDN     RD
        LBZ     OK5
        XRI     1
        LBNZ    OK3
        LOAD    R8, MNOFILE
        LBR     KMSG
OK3:    LOAD    R8, MBAD
        LBR     KMSG
OK5:    SEP     R4
        DW      KEEPNM
        SEP     R4
        DW      REDRAW
        LBR     MAINL
OLD:    SEP     R4
        DW      K_PIN
        DB      'LTCALC does not match this LTOS: RECV SYSTEM again.',0DH,0AH,0
        LBR     K_MAIN
QQUIT:  DB      'Quit without saving? Y/N ',0
QSAVE:  DB      'Save as: ',0
QOPEN:  DB      'Open: ',0
QREPL:  DB      'Replace that file? Y/N ',0
QLOSE:  DB      'Lose your changes? Y/N ',0
MSAVED: DB      'Saved.',0
MNOSAVE: DB     'Not saved: the card or the folder may be full.',0
MNOFILE: DB     'There is no such file.',0
MBAD:   DB      'That file cannot be opened as a sheet.',0
MFULL:  DB      'The sheet is full.',0
MNAME:  DB      'That is not a file name.',0
; ==== the terminal: TXB sends D; while it waits it reads the UART, so a key that comes is kept (RD RF used)
TXB:    PLO     RF
TX1:    LDI     15H             ; the status: a key in?
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        LBZ      TX2
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SEP     R4
        DW      PUSHK
        LBR      TX1
TX2:    LDN     R2              ; free to send?
        ANI     20H
        LBZ      TX1
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RF
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R5
; RXPOLL: a key that came -> the ring (RD RF used)
RXPOLL: LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        LBZ      RXP9
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        LBR     PUSHK
RXP9:   SEP     R5
; POLLS: RXPOLL with RD and RF kept
POLLS:  GLO     RD
        STXD
        GHI     RD
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      RXPOLL
        IRX
        LDXA
        PHI     RF
        LDXA
        PLO     RF
        LDXA
        PHI     RD
        LDX
        PLO     RD
        SEP     R5
; PUSHK: D -> the ring (dropped when it is full). RD RF.1 used.
PUSHK:  PHI     RF
        LOAD    RD, RTAIL
        LDN     RD
        ADI     1
        ANI     7FH
        STR     R2
        DEC     RD
        LDN     RD              ; = RHEAD: full
        XOR
        LBZ     PK9
        INC     RD
        LDN     RD
        PLO     RD
        LDI     HIGH(RING)
        PHI     RD
        GHI     RF
        STR     RD
        LOAD    RD, RTAIL
        LDN     R2
        STR     RD
PK9:    SEP     R5
; POPK: DF = 1 and D = the oldest key in the ring; DF = 0: none
POPK:   LOAD    RD, RHEAD
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        LBZ     PP9
        LDN     R2
        PLO     RD
        LDI     HIGH(RING)
        PHI     RD
        LDN     RD
        PHI     RF
        LOAD    RD, RHEAD
        LDN     RD
        ADI     1
        ANI     7FH
        STR     RD
        GHI     RF
        SMI     0               ; DF = 1
        GHI     RF
        SEP     R5
PP9:    ADI     0               ; DF = 0
        SEP     R5
; GETK: D = the next key (waits)
GETK:   SEP     R4
        DW      POPK
        LBDF     GK9
        SEP     R4
        DW      RXPOLL
        LBR     GETK
GK9:    SEP     R5
; ESCW: the next key if it comes soon (a sequence's next byte): DF = 1, D. DF = 0: none (~70 ms). R9 used.
ESCW:   LOAD    R9, 150
EW1:    SEP     R4
        DW      POPK
        LBDF     EW9
        SEP     R4
        DW      RXPOLL
        DEC     R9
        GLO     R9
        LBNZ     EW1
        GHI     R9
        LBNZ     EW1
        LDI     0
        SHR
EW9:    SEP     R5
; RKEY: KEY = the next key: an arrow is KUP-KLEFT, Delete 7FH, a lone Esc 1BH, any other sequence 0.
RKEY:   SEP     R4
        DW      GETK
        PLO     RC
        XRI     1BH
        LBNZ    RK8
        SEP     R4
        DW      ESCW
        LBNF    RK8             ; alone: Esc
        PLO     RB
        XRI     '['
        LBZ     RK2
        GLO     RB
        XRI     'O'
        LBZ     RK2
RK0:    LDI     0
        PLO     RC
        LBR     RK8
RK2:    SEP     R4
        DW      ESCW
        LBNF    RK0
        PLO     RB
        LDI     KUP
        PLO     RC
        GLO     RB
        XRI     'A'
        LBZ     RK8
        INC     RC
        GLO     RB
        XRI     'B'
        LBZ     RK8
        INC     RC
        GLO     RB
        XRI     'C'
        LBZ     RK8
        INC     RC
        GLO     RB
        XRI     'D'
        LBZ     RK8
        GLO     RB              ; ESC [ number ~ : Delete is 3
        XRI     '3'
        LBNZ    RK4
        LDI     7FH
        PLO     RC
        LSKP
RK4:    LDI     0
        PLO     RC
RK5:    GLO     RB              ; to the end of the sequence
        SMI     40H
        LBDF    RK8
        SEP     R4
        DW      ESCW
        LBNF    RK8
        PLO     RB
        LBR     RK5
RK8:    LOAD    RD, KEY
        GLO     RC
        STR     RD
        SEP     R5
; ---- printing. TPIN: the text after the call. TSTR: the text at R8. EOL: to the line's end. CLS: the whole screen
TPIN:   LDA     R6
        LBZ     TP9
        SEP     R4
        DW      TXB
        LBR     TPIN
TP9:    SEP     R5
TSTR:   LDA     R8
        LBZ     TP9
        SEP     R4
        DW      TXB
        LBR     TSTR
EOL:    SEP     R4
        DW      TPIN
        DB      1BH,'[K',0
        SEP     R5
CLS:    SEP     R4
        DW      TPIN
        DB      1BH,'[2J',1BH,'[H',0
        SEP     R5
; GOTO: the cursor to row RC.1, column RC.0 (RB used)
GOTO:   LDI     1BH
        SEP     R4
        DW      TXB
        LDI     '['
        SEP     R4
        DW      TXB
        GHI     RC
        SEP     R4
        DW      PNUM
        LDI     ';'
        SEP     R4
        DW      TXB
        GLO     RC
        SEP     R4
        DW      PNUM
        LDI     'H'
        LBR     TXB
; PNUM: D (0-99) in decimal (RB used)
PNUM:   PLO     RB
        LDI     0
        PHI     RB
PN1:    GLO     RB
        SMI     10
        LBNF    PN2
        PLO     RB
        GHI     RB
        ADI     1
        PHI     RB
        LBR     PN1
PN2:    GHI     RB
        LBZ     PN3
        ADI     '0'
        SEP     R4
        DW      TXB
PN3:    GLO     RB
        ADI     '0'
        LBR     TXB
; MESSAGE: the text at R8 on row 2
MESSAGE: LOAD   RC, 0201H
        SEP     R4
        DW      GOTO
        SEP     R4
        DW      TSTR
        LBR     EOL
; ASKYN: the question at R8 on row 2, a key: DF = 1 if Y
ASKYN:  SEP     R4
        DW      MESSAGE
        SEP     R4
        DW      RKEY
        LOAD    RD, KEY
        LDN     RD
        ANI     0DFH
        XRI     'Y'
        LBZ     AY1
        LDI     0
        SHR
        SEP     R5
AY1:    SMI     0               ; (D = 0) DF = 1
        SEP     R5
; ASKNAME: the question at R8 on row 2, a name typed -> TMP11, WDIR its folder. DF = 1: Esc, nothing typed, or not
; a name (it said so)
ASKNAME: LOAD   RD, ARROK
        LDI     0
        STR     RD
        LOAD    RD, INLEN
        LDI     0
        STR     RD
        LOAD    RD, INB
        LDI     0
        STR     RD
        SEP     R4
        DW      MESSAGE
        SEP     R4
        DW      EDLINE
        LOAD    RD, KEY
        LDN     RD
        XRI     1BH
        LBZ     AN8
        LOAD    RD, INLEN
        LDN     RD
        LBZ     AN8
        LOAD    RF, INB
        LOAD    RD, TMP11
        SEP     R4
        DW      KS_PARSE
        LBDF    AN7
        LOAD    RD, TMP11       ; (PARSE takes * and ?: not here)
        LDI     11
        PLO     RC
AN2:    LDA     RD
        XRI     '?'
        LBZ     AN7
        DEC     RC
        GLO     RC
        LBNZ    AN2
        SEP     R4
        DW      DEFEXT
        LDI     0
        SHR
        SEP     R5
AN7:    LOAD    R8, MNAME
        SEP     R4
        DW      MESSAGE
        SEP     R4              ; (seen until a key)
        DW      RKEY
AN8:    LDI     0
        SMI     0
        SEP     R5
; DEFEXT: a name with no extension gets .CLC
DEFEXT: LOAD    RD, TMP11 + 8
        LDA     RD
        XRI     ' '
        LBNZ    DE9
        LDA     RD
        XRI     ' '
        LBNZ    DE9
        LDN     RD
        XRI     ' '
        LBNZ    DE9
        LOAD    RD, TMP11 + 8
        LDI     'C'
        STR     RD
        INC     RD
        LDI     'L'
        STR     RD
        INC     RD
        LDI     'C'
        STR     RD
DE9:    SEP     R5
; KEEPNM: the sheet's name = TMP11, its folder = WDIR
KEEPNM: LOAD    RD, TMP11
        LOAD    RF, NAME11
        LDI     11
        PLO     RC
KN1:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    KN1
        LOAD    RD, KS_WDIR
        LOAD    RF, MYDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, NAMED
        LDI     1
        STR     RD
        SEP     R5
; EDLINE: a line typed into INB after what INLEN says is there (on the screen already). KEY = the key that ended it:
; Enter or Esc, and with ARROK Tab or an arrow too.
EDLINE: SEP     R4
        DW      RKEY
        LOAD    RD, KEY
        LDN     RD
        PLO     RC
        XRI     0DH
        LBZ     EDX
        GLO     RC
        XRI     0AH
        LBZ     EDX
        GLO     RC
        XRI     1BH
        LBZ     EDX
        GLO     RC
        XRI     08H
        LBZ     EDB
        GLO     RC
        XRI     7FH
        LBZ     EDB
        LOAD    RD, ARROK
        LDN     RD
        LBZ     ED2
        GLO     RC
        XRI     09H
        LBZ     EDX
        GLO     RC
        ANI     0FCH
        XRI     80H
        LBZ     EDX
ED2:    GLO     RC              ; a printable key
        SMI     20H
        LBNF    EDLINE
        GLO     RC
        SHL
        LBDF    EDLINE
        LOAD    RD, INLEN
        LDN     RD
        XRI     INMAX
        LBZ     EDLINE
        LDN     RD
        ADI     LOW(INB)
        PLO     RF
        LDI     HIGH(INB)
        PHI     RF
        GLO     RC
        STR     RF
        LDN     RD
        ADI     1
        STR     RD
        GLO     RC
        SEP     R4
        DW      TXB
        LBR     EDLINE
EDB:    LOAD    RD, INLEN
        LDN     RD
        LBZ     EDLINE
        SMI     1
        STR     RD
        SEP     R4
        DW      TPIN
        DB      8,' ',8,0
        LBR     EDLINE
EDX:    LOAD    RD, INLEN       ; its end
        LDN     RD
        ADI     LOW(INB)
        PLO     RF
        LDI     HIGH(INB)
        PHI     RF
        LDI     0
        STR     RF
        SEP     R5
; ==== the screen
; REDRAW: everything: the headings, every cell with something in it, the lines above and below
REDRAW: SEP     R4
        DW      CLS
        LOAD    RC, 0300H + GCOL
        SEP     R4
        DW      GOTO
        SEP     R4
        DW      TPIN
        DB      '    A        B        C        D        E        F        G        H',0
        LDI     1
        PLO     RA
RD1:    GLO     RA              ; the row numbers
        ADI     GROW - 1
        PHI     RC
        LDI     1
        PLO     RC
        GLO     RA
        SMI     10
        LBDF    RD2
        INC     RC              ; (one digit: under the other's units)
RD2:    SEP     R4
        DW      GOTO
        GLO     RA
        SEP     R4
        DW      PNUM
        INC     RA
        GLO     RA
        XRI     21
        LBNZ    RD1
        LOAD    RD, TYP         ; the cells with something in them
RD3:    LDN     RD
        ANI     7
        LBZ     RD4
        LDN     RD
        ORI     F_DIRTY
        STR     RD
RD4:    INC     RD
        GLO     RD
        XRI     NCELL
        LBNZ    RD3
        SEP     R4
        DW      CURR7           ; and the mark
        GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ORI     F_DIRTY
        STR     RD
        SEP     R4
        DW      DRAWD
        SEP     R4
        DW      STATUS
        LBR     SHOWCUR
; DRAWD: the cells marked dirty
DRAWD:  LDI     0
        PLO     R7
DW1:    GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     F_DIRTY
        LBZ     DW2
        LDN     RD
        ANI     0FFH - F_DIRTY
        STR     RD
        SEP     R4
        DW      PUTCELL
DW2:    INC     R7
        GLO     R7
        XRI     NCELL
        LBNZ    DW1
        SEP     R5
; CURR7: R7 = the current cell
CURR7:  LOAD    RD, CUR
        LDN     RD
        PLO     R7
        SEP     R5
; PUTCELL: cell R7.0 on the screen (the current one marked)
PUTCELL: GLO    R7
        SHR
        SHR
        SHR
        ADI     GROW
        PHI     RC
        GLO     R7              ; the column: 9 * c + GCOL
        ANI     7
        PLO     RC
        SHL
        SHL
        SHL
        STR     R2
        GLO     RC
        ADD
        ADI     GCOL
        PLO     RC
        SEP     R4
        DW      GOTO
        SEP     R4
        DW      ISCUR
        LBNF    PC1
        SEP     R4
        DW      TPIN
        DB      1BH,'[7m',0
PC1:    SEP     R4
        DW      CELLTXT
        LOAD    R8, CBUF
        SEP     R4
        DW      TSTR
        SEP     R4
        DW      ISCUR
        LBNF    PC9
        SEP     R4
        DW      TPIN
        DB      1BH,'[0m',0
PC9:    SEP     R5
; ISCUR: DF = 1: R7.0 is the current cell
ISCUR:  LOAD    RD, CUR
        LDN     RD
        STR     R2
        GLO     R7
        XOR
        LBZ     IC1
        LDI     0
        SHR
        SEP     R5
IC1:    SMI     0
        SEP     R5
; CELLTXT: cell R7.0's nine characters -> CBUF (0-ended)
CELLTXT: LOAD   RD, CBUF
        LDI     9
        PLO     RC
CT1:    LDI     ' '
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    CT1
        LDI     0
        STR     RD
        GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     7
        LBZ     CT9             ; empty
        PLO     RB
        XRI     K_TEXT
        LBZ     CTT
        GLO     RB
        SMI     K_FERR
        LBDF    CTE
        SEP     R4              ; a value
        DW      GETV
        SEP     R4
        DW      FMT
        LOAD    RD, FMTL
        LDN     RD
        PLO     RC
        SDI     9               ; 9 - its length: where it starts
        LBNF    CTH             ; too long
        ADI     LOW(CBUF)
        PLO     RD
        LDI     HIGH(CBUF)
        PHI     RD
        LOAD    RF, FMTB
CT2:    LDA     RF
        LBZ     CT9
        STR     RD
        INC     RD
        LBR     CT2
CTH:    LOAD    RD, CBUF
        LDI     9
        PLO     RC
CT3:    LDI     '#'
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    CT3
CT9:    SEP     R5
CTE:    LOAD    RD, CBUF + 6
        LDI     'E'
        STR     RD
        INC     RD
        LDI     'R'
        STR     RD
        INC     RD
        STR     RD
        SEP     R5
CTT:    SEP     R4              ; text: its first nine characters
        DW      SRCP
        LOAD    RD, CBUF
        LDI     9
        PLO     RC
CT4:    LDA     R8
        PLO     RB
        SMI     20H
        LBNF    CT9
        GLO     RB
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    CT4
        SEP     R5
; SHOWCUR: row 1: the current cell's name and what is in it. Row 2: its value
SHOWCUR: LOAD   RD, SHOWP
        LDI     0
        STR     RD
        SEP     R4
        DW      CURR7
        LOAD    RC, 0101H
        SEP     R4
        DW      GOTO
        SEP     R4
        DW      NAMEIT
        LOAD    R8, NBUF
        SEP     R4
        DW      TSTR
        SEP     R4
        DW      KINDR7
        LBZ     SC3
        SEP     R4
        DW      SRCP
        LDI     72
        PLO     RC
SC1:    LDA     R8
        PLO     RB
        SMI     20H
        LBNF    SC3
        GLO     RB
        SEP     R4
        DW      TXB
        DEC     RC
        GLO     RC
        LBNZ    SC1
SC3:    SEP     R4
        DW      EOL
        LOAD    RC, 0201H
        SEP     R4
        DW      GOTO
        SEP     R4
        DW      KINDR7
        PLO     RB
        SMI     K_NUM
        LBNF    SC8             ; empty or text: nothing
        GLO     RB
        SMI     K_FERR
        LBDF    SC6
        SEP     R4
        DW      GETV
        SEP     R4
        DW      FMT
        LOAD    R8, FMTB
        SEP     R4
        DW      TSTR
        LBR     SC8
SC6:    SEP     R4
        DW      TPIN
        DB      'ERR',0
SC8:    LBR     EOL
; KINDR7: D = cell R7.0's kind (the D is kept through the return: see NANO's POPK)
KINDR7: GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     7
        SEP     R5
; STATUS: row 24: the sheet's name, * if it changed, the keys
STATUS: LOAD    RC, 1801H
        SEP     R4
        DW      GOTO
        LOAD    RD, NAMED
        LDN     RD
        LBNZ    SA1
        SEP     R4
        DW      TPIN
        DB      '(no name)',0
        LBR     SA5
SA1:    LOAD    R8, NAME11
        LDI     8
        PLO     RC
SA2:    LDA     R8
        PLO     RB
        XRI     ' '
        LBZ     SA3
        GLO     RB
        SEP     R4
        DW      TXB
SA3:    DEC     RC
        GLO     RC
        LBNZ    SA2
        LDN     R8              ; the extension
        XRI     ' '
        LBZ     SA5
        LDI     '.'
        SEP     R4
        DW      TXB
        LDI     3
        PLO     RC
SA4:    LDA     R8
        PLO     RB
        XRI     ' '
        LBZ     SA41
        GLO     RB
        SEP     R4
        DW      TXB
SA41:   DEC     RC
        GLO     RC
        LBNZ    SA4
SA5:    LOAD    RD, CHG
        LDN     RD
        LBZ     SA6
        LDI     '*'
        SEP     R4
        DW      TXB
SA6:    SEP     R4
        DW      TPIN
        DB      '   ^S save  ^A save as  ^O open  ^E edit  Esc quit',0
        LBR     EOL
; NAMEIT: cell R7.0's name and a space -> NBUF, NLEN its length
NAMEIT: LOAD    RF, NBUF
        GLO     R7
        ANI     7
        ADI     'A'
        STR     RF
        INC     RF
        GLO     R7
        SHR
        SHR
        SHR
        ADI     1
        PLO     RC
        LDI     '0'
        PHI     RC
NI1:    GLO     RC
        SMI     10
        LBNF    NI2
        PLO     RC
        GHI     RC
        ADI     1
        PHI     RC
        LBR     NI1
NI2:    GHI     RC
        XRI     '0'
        LBZ     NI3
        GHI     RC
        STR     RF
        INC     RF
NI3:    GLO     RC
        ADI     '0'
        STR     RF
        INC     RF
        LDI     ' '
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        GLO     RF
        SMI     LOW(NBUF)
        PLO     RC
        LOAD    RD, NLEN
        GLO     RC
        STR     RD
        SEP     R5
; ==== the sheet
; CLEAR: nothing in it, the first cell current
CLEAR:  LOAD    RD, TYP
        LOAD    RF, PH
        LOAD    RB, PL
CR1:    LDI     0
        STR     RD
        STR     RF
        STR     RB
        INC     RD
        INC     RF
        INC     RB
        GLO     RD
        XRI     NCELL
        LBNZ    CR1
        LOAD    RD, CUR
        LDI     0
        STR     RD
        LOAD    RD, CHG
        LDI     0
        STR     RD
        LOAD    RD, TOPV
        LDI     HIGH(POOL)
        STR     RD
        INC     RD
        LDI     LOW(POOL)
        STR     RD
        SEP     R5
; GETP: RA = where cell R7.0's line is (0: empty). SETP: RA to it.
GETP:   GLO     R7
        PLO     RD
        LDI     HIGH(PH)
        PHI     RD
        LDN     RD
        PHI     RA
        LDI     HIGH(PL)
        PHI     RD
        LDN     RD
        PLO     RA
        SEP     R5
SETP:   GLO     R7
        PLO     RD
        LDI     HIGH(PH)
        PHI     RD
        GHI     RA
        STR     RD
        LDI     HIGH(PL)
        PHI     RD
        GLO     RA
        STR     RD
        SEP     R5
; SRCP: R8 -> what cell R7.0 holds: past its name in its line
SRCP:   GLO     R7
        PLO     RD
        LDI     HIGH(PH)
        PHI     RD
        LDN     RD
        PHI     R8
        LDI     HIGH(PL)
        PHI     RD
        LDN     RD
        PLO     R8
SP1:    LDA     R8
        XRI     ' '
        LBNZ    SP1
        SEP     R5
; GETV: ACC = cell R7.0's value. STV: ACC to it; RB.0 <> 0 if that changed it.
GETV:   LOAD    RF, ACC
        GLO     R7
        PLO     RD
        LDI     HIGH(V0)
        PHI     RD
        LDI     4
        PLO     RC
GV1:    LDN     RD
        STR     RF
        INC     RF
        GHI     RD
        ADI     1
        PHI     RD
        DEC     RC
        GLO     RC
        LBNZ    GV1
        SEP     R5
STV:    LOAD    RF, ACC
        GLO     R7
        PLO     RD
        LDI     HIGH(V0)
        PHI     RD
        LDI     0
        PLO     RB
        LDI     4
        PLO     RC
SV1:    LDA     RF
        STR     R2
        LDN     RD
        XOR
        PHI     RB              ; what differs
        LDN     R2
        STR     RD
        GHI     RB
        STR     R2
        GLO     RB
        OR
        PLO     RB
        GHI     RD
        ADI     1
        PHI     RD
        DEC     RC
        GLO     RC
        LBNZ    SV1
        SEP     R5
; SETCELL: cell CUR = INB (INLEN bytes; 0: emptied), all that follows from it worked out and shown.
; DF = 1: no room (it said so, nothing changed).
SETCELL: SEP    R4
        DW      CURR7
        LOAD    RD, INLEN
        LDN     RD
        LBZ     SE2
        PLO     RC              ; room for the line, its name and LF?
        ADI     5
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    RD, TOPV
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        GLO     RB              ; RB = the top + what it needs
        STR     R2
        GLO     RC
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        GLO     RB              ; past POOLE?
        SDI     LOW(POOLE)
        GHI     RB
        SDBI    HIGH(POOLE)
        LBDF    SE2
        LOAD    R8, MFULL
        SEP     R4
        DW      MESSAGE
        LDI     0
        SMI     0
        SEP     R5
SE2:    SEP     R4
        DW      GETP
        GHI     RA
        LBNZ    SE3
        LOAD    RD, INLEN       ; nothing there, and nothing to put there
        LDN     RD
        LBZ     SE9
SE3:    SEP     R4
        DW      REMOVE
        SEP     R4
        DW      RXPOLL
        GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDI     F_DIRTY + F_CHG
        STR     RD
        LOAD    RD, INLEN
        LDN     RD
        LBZ     SE5
        SEP     R4
        DW      INSERT
        SEP     R4
        DW      CLASS
SE5:    LOAD    RD, CHG         ; (the star, the first time)
        LDN     RD
        LBNZ    SE6
        LDI     1
        STR     RD
        SEP     R4
        DW      STATUS
SE6:    SEP     R4
        DW      RECALC
        SEP     R4
        DW      DRAWD
SE9:    LDI     0
        SHR
        SEP     R5
; REMOVE: cell R7.0's line out of the pool
REMOVE: SEP     R4
        DW      GETP
        GHI     RA
        LBZ     RM9
        GHI     RA              ; RB = its end, past the LF
        PHI     RB
        GLO     RA
        PLO     RB
RM1:    LDA     RB
        XRI     0AH
        LBNZ    RM1
        GLO     RA              ; RC = minus its length
        STR     R2
        GLO     RB
        SD
        PLO     RC
        GHI     RA
        STR     R2
        GHI     RB
        SDB
        PHI     RC
        GHI     RB              ; R8 = its end, for ADJ
        PHI     R8
        GLO     RB
        PLO     R8
        LOAD    RD, TOPV
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
RM2:    GHI     RB              ; the rest down over it
        STR     R2
        GHI     RF
        XOR
        LBNZ    RM3
        GLO     RB
        STR     R2
        GLO     RF
        XOR
        LBZ     RM4
RM3:    LDA     RB
        STR     RD
        INC     RD
        GLO     RD              ; (now and then, a key typed meanwhile is kept)
        ANI     3FH
        LBNZ    RM2
        SEP     R4
        DW      POLLS
        LBR     RM2
RM4:    GHI     RD              ; (RD = the new top)
        PHI     RB
        GLO     RD
        PLO     RB
        LOAD    RD, TOPV
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        GHI     R8
        PHI     RA
        GLO     R8
        PLO     RA
        SEP     R4
        DW      ADJ
        LOAD    RA, 0
        SEP     R4
        DW      SETP
RM9:    SEP     R5
; ADJ: every line at RA or above moves by RC
ADJ:    LOAD    RD, PH
        LOAD    RF, PL
        LDI     NCELL
        PLO     RB
AJ1:    LDN     RD              ; (empty)
        LBZ     AJ2
        LDN     RF              ; DF = 1: its address >= RA
        STR     R2
        GLO     RA
        SD
        LDN     RD
        STR     R2
        GHI     RA
        SDB
        LBNF    AJ2
        LDN     RF
        STR     R2
        GLO     RC
        ADD
        STR     RF
        LDN     RD
        STR     R2
        GHI     RC
        ADC
        STR     RD
AJ2:    INC     RD
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    AJ1
        SEP     R5
; INSERT: the line for cell R7.0 (its name, INB, LF) into the pool, before the next cell's
INSERT: SEP     R4
        DW      NAMEIT
        LOAD    RD, NLEN        ; RC = the line's length
        LDN     RD
        STR     R2
        LOAD    RD, INLEN
        LDN     RD
        ADD
        ADI     1
        PLO     RC
        LDI     0
        PHI     RC
        GLO     R7              ; RA = where: the next cell's line, or the top
        PLO     RD
RI1:    INC     RD
        GLO     RD
        XRI     NCELL
        LBZ     RI3
        LDI     HIGH(PH)
        PHI     RD
        LDN     RD
        LBZ     RI1
        PHI     RA
        LDI     HIGH(PL)
        PHI     RD
        LDN     RD
        PLO     RA
        LBR     RI4
RI3:    LOAD    RD, TOPV
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
RI4:    LOAD    RD, TOPV        ; RF = the top; RD = the new top
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     RF
        STR     R2
        GLO     RC
        ADD
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LOAD    R8, TOPV
        GHI     RD
        STR     R8
        INC     R8
        GLO     RD
        STR     R8
RI5:    GHI     RF              ; what is above it moves up, from the top down
        STR     R2
        GHI     RA
        XOR
        LBNZ    RI6
        GLO     RF
        STR     R2
        GLO     RA
        XOR
        LBZ     RI7
RI6:    DEC     RF
        DEC     RD
        LDN     RF
        STR     RD
        GLO     RD              ; (now and then, a key typed meanwhile is kept)
        ANI     3FH
        LBNZ    RI5
        SEP     R4
        DW      POLLS
        LBR     RI5
RI7:    SEP     R4
        DW      ADJ
        SEP     R4
        DW      SETP
        LOAD    R8, NBUF        ; the line
        GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
RI8:    LDA     R8
        LBZ     RI85
        STR     RD
        INC     RD
        LBR     RI8
RI85:   LOAD    R8, INB
RI9:    LDA     R8
        LBZ     RI95
        STR     RD
        INC     RD
        LBR     RI9
RI95:   LDI     0AH
        STR     RD
        SEP     R5
; CLASS: what cell R7.0 holds, from its text: TYP (dirty), and a number's value
CLASS:  SEP     R4
        DW      SRCP
        LDN     R8
        XRI     '='
        LBNZ    CL1
        LDI     K_FORM + F_WAIT + F_DIRTY + F_CHG
        LBR     CLK
CL1:    LOAD    RD, MSIGN       ; a number? [+-] digits [. digits], and nothing after
        LDI     0
        STR     RD
        LDN     R8
        XRI     '-'
        LBNZ    CL2
        LDI     80H
        STR     RD
        INC     R8
        LBR     CL3
CL2:    LDN     R8
        XRI     '+'
        LBNZ    CL3
        INC     R8
CL3:    LDN     R8              ; a digit, or a point and a digit
        XRI     '.'
        LBNZ    CL4
        INC     R8
        LDN     R8
        DEC     R8
        LBR     CL5
CL4:    LDN     R8
CL5:    SMI     '0'
        LBNF    CLT
        SMI     10
        LBDF    CLT
        SEP     R4
        DW      PNUMB
        LBDF    CLO
        LDN     R8
        SMI     20H
        LBDF    CLT
        SEP     R4
        DW      SGNF
        SEP     R4
        DW      STV
        LDI     K_NUM + F_DIRTY + F_CHG
        LBR     CLK
CLO:    LDI     K_NERR + F_DIRTY + F_CHG
        LBR     CLK
CLT:    LDI     K_TEXT + F_DIRTY + F_CHG
CLK:    PLO     RC
        GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        GLO     RC
        STR     RD
        SEP     R5
; LOADFILE: the file TMP11 (in WDIR) into the pool. LRC = 0: done, worked out; 1 no such file; 2 not one that fits
; (both leave the sheet as it was); 3 it could not be read (the sheet is empty).
LOADFILE: LOAD  RD, TMP11
        SEP     R4
        DW      KS_FINDN
        LBNF    LO1
        LDI     1
        LBR     LO9
LO1:    LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    LO8             ; a folder
        LOAD    RD, KS_DSIZE    ; fits?
        LDA     RD
        LBNZ    LO8
        LDA     RD
        LBNZ    LO8
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC              ; RC + POOL > POOLE?
        ADI     LOW(POOL)
        PLO     RC
        GHI     RC
        ADCI    HIGH(POOL)
        PHI     RC
        LBDF    LO8
        GLO     RC
        SDI     LOW(POOLE)
        GHI     RC
        SDBI    HIGH(POOLE)
        LBDF    LO2
LO8:    LDI     2
LO9:    PLO     RC
        LOAD    RD, LRC
        GLO     RC
        STR     RD
        SEP     R5
LO2:    SEP     R4
        DW      CLEAR
        LOAD    RD, KS_LDDST
        LDI     HIGH(POOL)
        STR     RD
        INC     RD
        LDI     LOW(POOL)
        STR     RD
        LOAD    RD, KS_LDSKIP
        LDI     0
        STR     RD
        SEP     R4
        DW      KS_LOADF
        LBNF    LO3
        LDI     3
        LBR     LO9
LO3:    LOAD    RD, KS_LDEND    ; the top
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GLO     RA              ; empty?
        XRI     LOW(POOL)
        LBNZ    LO4
        GHI     RA
        XRI     HIGH(POOL)
        LBZ     LO5
LO4:    DEC     RA              ; a last line with no LF gets one
        LDA     RA
        XRI     0AH
        LBZ     LO5
        LDI     0AH
        STR     RA
        INC     RA
LO5:    LOAD    RD, TOPV
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, LNP         ; the lines
        LDI     HIGH(POOL)
        STR     RD
        INC     RD
        LDI     LOW(POOL)
        STR     RD
LO6:    LOAD    RD, LNP
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LOAD    RD, TOPV        ; at the top: done
        LDA     RD
        STR     R2
        GHI     R8
        XOR
        LBNZ    LO61
        LDN     RD
        STR     R2
        GLO     R8
        XOR
        LBZ     LO7
LO61:   LDN     R8              ; (a line starting with a space is no cell's)
        XRI     ' '
        LBZ     LO65
        SEP     R4
        DW      PREF
        LBDF    LO65
        LDN     R8
        XRI     ' '
        LBNZ    LO65
        GHI     RA              ; R7.0 = the cell
        SHL
        SHL
        SHL
        STR     R2
        GLO     RA
        OR
        PLO     R7
        LOAD    RD, LNP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      SETP
        SEP     R4
        DW      CLASS
LO65:   LOAD    RD, LNP         ; the next line
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
LO66:   LDA     R8
        XRI     0AH
        LBNZ    LO66
        LOAD    RD, LNP
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        LBR     LO6
LO7:    SEP     R4
        DW      RECALC
        LDI     0
        LBR     LO9
; ==== working it out
; RECALC: every formula, in the order they need each other. A cell whose kind or value changes is marked dirty.
RECALC: LOAD    RD, PROG        ; a look: which formulas name a changed cell?
        LDI     0
        STR     RD
        PLO     R7
RP1:    GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD              ; a formula, not known yet?
        ANI     F_CHG + 7
        XRI     K_FORM
        LBZ     RP2
        XRI     K_FORM XOR K_FERR
        LBNZ    RP4
RP2:    SEP     R4              ; (a key typed meanwhile is kept)
        DW      RXPOLL
        SEP     R4
        DW      DEPS
        LBNF    RP4
        GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ORI     F_CHG
        STR     RD
        LOAD    RD, PROG
        LDI     1
        STR     RD
RP4:    INC     R7
        GLO     R7
        XRI     NCELL
        LBNZ    RP1
        LOAD    RD, PROG
        LDN     RD
        LBNZ    RECALC
        LOAD    RD, TYP         ; those formulas wait
RC1:    LDN     RD
        ANI     F_CHG
        LBZ     RC3
        LDN     RD
        ANI     7
        XRI     K_FORM
        LBZ     RC2
        LDN     RD
        ANI     7
        XRI     K_FERR
        LBNZ    RC3
RC2:    LDN     RD
        ORI     F_WAIT
        STR     RD
RC3:    INC     RD
        GLO     RD
        XRI     NCELL
        LBNZ    RC1
RC4:    LOAD    RD, PROG        ; a pass
        LDI     0
        STR     RD
        PLO     R7
RC5:    GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        SHL
        LBNF    RC8             ; not waiting
        SEP     R4              ; (a key typed meanwhile is kept)
        DW      RXPOLL
        SEP     R4
        DW      EVAL
        LOAD    RD, ECODE
        LDN     RD
        XRI     2
        LBZ     RC8             ; it needs one still waiting
        LOAD    RD, PROG
        LDI     1
        STR     RD
        LOAD    RD, ECODE
        LDN     RD
        LBNZ    RC6
        SEP     R4              ; a value
        DW      STV
        LDI     K_FORM
        LBR     RC7
RC6:    LDI     0
        PLO     RB
        LDI     K_FERR
RC7:    PLO     RC
        SEP     R4
        DW      SETK
RC8:    INC     R7
        GLO     R7
        XRI     NCELL
        LBNZ    RC5
        LOAD    RD, PROG
        LDN     RD
        LBNZ    RC4
        LDI     0               ; what still waits is a loop
        PLO     R7
RC9:    GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     0FFH - F_CHG
        STR     RD
        SHL
        LBNF    RC95
        LDI     0
        PLO     RB
        LDI     K_FERR
        PLO     RC
        SEP     R4
        DW      SETK
RC95:   INC     R7
        GLO     R7
        XRI     NCELL
        LBNZ    RC9
        SEP     R5
; SETK: cell R7.0 is done: kind RC.0; dirty if that differs from before, or RB.0 <> 0 (STV's word)
SETK:   GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     7
        STR     R2
        GLO     RC
        XOR
        STR     R2
        GLO     RB
        OR
        LBZ     SK1
        GLO     RC
        ORI     F_DIRTY
        STR     RD
        SEP     R5
SK1:    LDN     RD
        ANI     F_DIRTY
        STR     R2
        GLO     RC
        OR
        STR     RD
        SEP     R5
; EVAL: cell R7.0's formula -> ACC. ECODE = 0 done, 1 it failed, 2 it met a waiting cell. A failure anywhere inside
; comes straight back here: EVERR / EVWAIT put the stack and the link back as they were.
EVAL:   LOAD    RD, EVR2
        GHI     R2
        STR     RD
        INC     RD
        GLO     R2
        STR     RD
        INC     RD
        GHI     R6
        STR     RD
        INC     RD
        GLO     R6
        STR     RD
        SEP     R4
        DW      SRCP
        INC     R8              ; past the =
        LOAD    R9, V1 + 0A0H
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      PEEK
        GLO     RF
        SMI     20H
        LBDF    EVERR           ; something left over
        LDI     0
        LBR     EVEND
EVWAIT: LDI     2
        LBR     EVEND
EVERR:  LDI     1
EVEND:  PLO     RC
        LOAD    RD, ECODE
        GLO     RC
        STR     RD
        LOAD    RD, EVR2
        LDA     RD
        PHI     R2
        LDA     RD
        PLO     R2
        LDA     RD
        PHI     R6
        LDN     RD
        PLO     R6
        SEP     R5
; PEEK: RF.0 = the next character past any spaces, a letter in capitals; R8 at it
PEEK:   LDN     R8
        XRI     ' '
        LBNZ    PE1
        INC     R8
        LBR     PEEK
PE1:    LDN     R8
        PLO     RF
        SMI     'a'
        LBNF    PE9
        SMI     26
        LBDF    PE9
        GLO     RF
        ANI     0DFH
        PLO     RF
PE9:    SEP     R5
; EXPR: terms joined by + and -. TERM: factors joined by * and /. The left side waits on the value stack.
EXPR:   SEP     R4
        DW      TERM
EX1:    SEP     R4
        DW      PEEK
        GLO     RF
        XRI     '+'
        LBZ     EXA
        GLO     RF
        XRI     '-'
        LBZ     EXS
        SEP     R5
EXA:    INC     R8
        SEP     R4
        DW      PUSHA
        SEP     R4
        DW      TERM
        SEP     R4
        DW      POPB
        SEP     R4
        DW      ADDBA
        LBR     EX1
EXS:    INC     R8
        SEP     R4
        DW      PUSHA
        SEP     R4
        DW      TERM
        SEP     R4
        DW      POPB
        LOAD    RD, ACC + 3
        SEP     R4
        DW      NEGP
        SEP     R4
        DW      ADDBA
        LBR     EX1
TERM:   SEP     R4
        DW      UNARY
TM1:    SEP     R4
        DW      PEEK
        GLO     RF
        XRI     '*'
        LBZ     TMM
        GLO     RF
        XRI     '/'
        LBZ     TMD
        SEP     R5
TMM:    INC     R8
        SEP     R4
        DW      PUSHA
        SEP     R4
        DW      UNARY
        SEP     R4
        DW      POPB
        SEP     R4
        DW      MULBA
        LBR     TM1
TMD:    INC     R8
        SEP     R4
        DW      PUSHA
        SEP     R4
        DW      UNARY
        SEP     R4
        DW      POPB
        SEP     R4
        DW      DIVBA
        LBR     TM1
UNARY:  SEP     R4
        DW      PEEK
        GLO     RF
        XRI     '-'
        LBNZ    UN1
        INC     R8
        SEP     R4
        DW      UNARY
        LOAD    RD, ACC + 3
        LBR     NEGP
UN1:    GLO     RF
        XRI     '+'
        LBNZ    UN2
        INC     R8
        LBR     UNARY
UN2:    GLO     RF              ; ( expression )
        XRI     '('
        LBNZ    UN3
        INC     R8
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      PEEK
        GLO     RF
        XRI     ')'
        LBNZ    EVERR
        INC     R8
        SEP     R5
UN3:    GLO     RF              ; a number
        XRI     '.'
        LBZ     UN4
        GLO     RF
        SMI     '0'
        LBNF    UN5
        SMI     10
        LBDF    UN5
UN4:    SEP     R4
        DW      PNUMB
        LBDF    EVERR
        SEP     R5
UN5:    GLO     RF              ; a letter: a cell, or a function's name
        SMI     'A'
        LBNF    EVERR
        SMI     26
        LBDF    EVERR
        INC     R8
        LDN     R8
        DEC     R8
        SMI     '0'
        LBNF    FUNC
        SMI     10
        LBDF    FUNC
        SEP     R4
        DW      PREF
        LBDF    EVERR
        GHI     RA
        SHL
        SHL
        SHL
        STR     R2
        GLO     RA
        OR
        PLO     RC
        LBR     CELLV
; PREF: a cell's name at R8 -> RA.1 its row (0-19), RA.0 its column; R8 past it. DF = 1: not a cell.
PREF:   SEP     R4
        DW      PEEK
        GLO     RF
        SMI     'A'
        LBNF    PRX
        PLO     RA
        SMI     8
        LBDF    PRX
        INC     R8
        LDN     R8
        SMI     '0'
        LBNF    PRX
        SMI     10
        LBDF    PRX
        LDA     R8
        SMI     '0'
        PHI     RA
        LDN     R8
        SMI     '0'
        LBNF    PR2
        SMI     10
        LBDF    PR2
        LDA     R8
        SMI     '0'
        PLO     RB
        GHI     RA              ; * 10
        SHL
        STR     R2
        SHL
        SHL
        ADD
        STR     R2
        GLO     RB
        ADD
        PHI     RA
PR2:    GHI     RA
        LBZ     PRX
        SMI     21
        LBDF    PRX
        GHI     RA
        SMI     1
        PHI     RA
        LDI     0
        SHR
        SEP     R5
PRX:    LDI     0
        SMI     0
        SEP     R5
; CELLV: ACC = cell RC.0's value; DF = 1: it has one (0 for an empty cell or text, DF = 0)
CELLV:  GLO     RC
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        SHL
        LBDF    EVWAIT
        LDN     RD
        ANI     7
        PLO     RB
        SMI     K_NUM
        LBNF    CV0
        GLO     RB
        SMI     K_FERR
        LBDF    EVERR
        LOAD    RF, ACC
        LDI     HIGH(V0)
        PHI     RD
        LDN     RD
        STR     RF
        INC     RF
        LDI     HIGH(V1)
        PHI     RD
        LDN     RD
        STR     RF
        INC     RF
        LDI     HIGH(V2)
        PHI     RD
        LDN     RD
        STR     RF
        INC     RF
        LDI     HIGH(V3)
        PHI     RD
        LDN     RD
        STR     RF
        LDI     0
        SMI     0
        SEP     R5
CV0:    LOAD    RF, ACC
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        SHR
        SEP     R5
; FUNC: SUM AVG MIN MAX COUNT ( a list of cells and ranges )
FUNC:   LOAD    RB, FTAB
FN1:    LDN     RB
        LBZ     EVERR
        GHI     R8
        PHI     RF
        GLO     R8
        PLO     RF
        LDI     3
        PLO     RC
FN2:    LDA     RF
        ANI     0DFH
        STR     R2
        LDA     RB
        XOR
        LBNZ    FN3
        DEC     RC
        GLO     RC
        LBNZ    FN2
        LDN     RB              ; found
        PLO     RC
        LOAD    RD, FK
        GLO     RC
        STR     RD
        INC     R8
        INC     R8
        INC     R8
        GLO     RC
        XRI     5
        LBNZ    FN5
        LDA     R8              ; COUNT's last two
        ANI     0DFH
        XRI     'N'
        LBNZ    EVERR
        LDA     R8
        ANI     0DFH
        XRI     'T'
        LBNZ    EVERR
        LBR     FN5
FN3:    INC     RB              ; the next one's name
        DEC     RC
        GLO     RC
        LBNZ    FN3
        LBR     FN1
FN5:    SEP     R4
        DW      PEEK
        GLO     RF
        XRI     '('
        LBNZ    EVERR
        INC     R8
        LOAD    RD, FSUM        ; FSUM FMIN FMAX FCNT = 0
        LDI     14
        PLO     RC
FN51:   LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    FN51
FN6:    SEP     R4
        DW      PREF
        LBDF    EVERR
        LOAD    RD, R1V
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R4
        DW      PEEK
        GLO     RF
        XRI     ':'
        LBNZ    FN7
        INC     R8
        SEP     R4
        DW      PREF
        LBDF    EVERR
        LOAD    RD, R2V
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
FN7:    SEP     R4
        DW      FRANGE
        SEP     R4
        DW      PEEK
        GLO     RF
        XRI     ','
        LBNZ    FN8
        INC     R8
        LBR     FN6
FN8:    GLO     RF
        XRI     ')'
        LBNZ    EVERR
        INC     R8
        LOAD    RD, FK          ; the answer
        LDN     RD
        PLO     RC
        XRI     1
        LBNZ    FN81
        LOAD    RF, FSUM
        LBR     FNCP
FN81:   GLO     RC
        XRI     3
        LBNZ    FN82
        LOAD    RF, FMIN
        LBR     FNCP
FN82:   GLO     RC
        XRI     4
        LBNZ    FN83
        LOAD    RF, FMAX
FNCP:   LOAD    RD, ACC
        LBR     COPY4
FN83:   GLO     RC
        XRI     5
        LBNZ    FN84
        LOAD    RD, FCNT        ; COUNT: the number of them, as hundredths
        LDI     0
        PHI     RA
        PLO     RA
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LDI     0
        PLO     RF
        SEP     R4
        DW      M10
        LDI     0
        PLO     RF
        SEP     R4
        DW      M10
        LBR     STACC
FN84:   LOAD    RD, FCNT        ; AVG: the sum over how many
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     EVERR
        LOAD    RF, FSUM
        LOAD    RD, ACC
        SEP     R4
        DW      COPY4
        LOAD    RD, ACC
        LDN     RD
        PLO     RC
        LOAD    RD, MSIGN
        GLO     RC
        STR     RD
        ANI     80H
        LBZ     FN85
        LOAD    RD, ACC + 3
        SEP     R4
        DW      NEGP
FN85:   LOAD    RD, MP
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        LOAD    RF, ACC
        SEP     R4
        DW      COPY4
        LOAD    RD, MD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        LOAD    RF, FCNT
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        SEP     R4
        DW      DIVRND
        LBR     SGNF
FTAB:   DB      'SUM',1,'AVG',2,'MIN',3,'MAX',4,'COU',5,0
; DEPS: DF = 1: cell R7.0's formula names a changed cell. (Anything that looks like a cell's name counts: at worst a
; formula is worked out when it need not be.)
DEPS:   SEP     R4
        DW      SRCP
DP1:    LDN     R8
        SMI     20H
        LBNF    DPNO
        LDN     R8
        ANI     0DFH
        SMI     'A'
        LBNF    DPN
        SMI     8
        LBDF    DPN
        INC     R8
        LDN     R8
        DEC     R8
        SMI     '0'
        LBNF    DPN
        SMI     10
        LBDF    DPN
        SEP     R4
        DW      PREF
        LBDF    DP1
        LOAD    RD, R1V
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R4
        DW      PEEK
        GLO     RF
        XRI     ':'
        LBNZ    DP3
        INC     R8
        SEP     R4
        DW      PREF
        LBDF    DP1
        LOAD    RD, R2V
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
DP3:    SEP     R4
        DW      FRNORM
DP4:    LOAD    RD, C1V         ; a row of the range
        LDN     RD
        PLO     RA
DP5:    GHI     RA
        SHL
        SHL
        SHL
        STR     R2
        GLO     RA
        OR
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     F_CHG
        LBNZ    DPYES
        LOAD    RD, C2V
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBZ     DP6
        INC     RA
        LBR     DP5
DP6:    LOAD    RD, R2V
        LDN     RD
        STR     R2
        GHI     RA
        XOR
        LBZ     DP1
        GHI     RA
        ADI     1
        PHI     RA
        LBR     DP4
DPN:    INC     R8
        LBR     DP1
DPNO:   LDI     0
        SHR
        SEP     R5
DPYES:  LDI     0
        SMI     0
        SEP     R5
; FRANGE: every cell from R1V,C1V to R2V,C2V (either way round) into the function's sums
FRANGE: SEP     R4
        DW      FRNORM
        LBR     FG3
; FRNORM: the range's corners in order; RA.1 = its first row
FRNORM: LOAD    RD, R1V
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        GHI     RB              ; rows in order
        STR     R2
        GHI     RA
        SM
        LBNF    FG1
        GHI     RA
        PLO     RC
        GHI     RB
        PHI     RA
        GLO     RC
        PHI     RB
FG1:    GLO     RB              ; columns in order
        STR     R2
        GLO     RA
        SM
        LBNF    FG2
        GLO     RA
        PLO     RC
        GLO     RB
        PLO     RA
        GLO     RC
        PLO     RB
FG2:    LOAD    RD, R1V
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        SEP     R5
FG3:    LOAD    RD, C1V         ; a row
        LDN     RD
        PLO     RA
FG4:    GHI     RA
        SHL
        SHL
        SHL
        STR     R2
        GLO     RA
        OR
        PLO     RC
        SEP     R4
        DW      CELLV
        LBNF    FG5
        SEP     R4
        DW      FACC
FG5:    SEP     R4              ; (a long range: a key typed meanwhile is kept)
        DW      RXPOLL
        LOAD    RD, C2V
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBZ     FG6
        INC     RA
        LBR     FG4
FG6:    LOAD    RD, R2V
        LDN     RD
        STR     R2
        GHI     RA
        XOR
        LBZ     FG9
        GHI     RA
        ADI     1
        PHI     RA
        LBR     FG3
FG9:    SEP     R5
; FACC: ACC into the function's sum, count, least and most
FACC:   LOAD    RD, FCNT
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     FA1             ; the first: least and most
        LOAD    RF, ACC + 3
        LOAD    RD, FMIN + 3
        SEP     R4
        DW      CMPV
        LBDF    FA2
        LOAD    RF, ACC
        LOAD    RD, FMIN
        SEP     R4
        DW      COPY4
FA2:    LOAD    RF, FMAX + 3
        LOAD    RD, ACC + 3
        SEP     R4
        DW      CMPV
        LBDF    FA3
        LOAD    RF, ACC
        LOAD    RD, FMAX
        SEP     R4
        DW      COPY4
        LBR     FA3
FA1:    LOAD    RF, ACC
        LOAD    RD, FMIN
        SEP     R4
        DW      COPY4
        LOAD    RF, ACC
        LOAD    RD, FMAX
        SEP     R4
        DW      COPY4
FA3:    LOAD    RF, FSUM
        LOAD    RD, BV
        SEP     R4
        DW      COPY4
        SEP     R4
        DW      ADDBA
        LOAD    RF, ACC
        LOAD    RD, FSUM
        SEP     R4
        DW      COPY4
        LOAD    RD, FCNT + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5
; COPY4: 4 bytes from RF to RD (both end past them)
COPY4:  LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        INC     RD
        SEP     R5
; CMPV: the values ending at RF (X) and RD (Y), signed: DF = 1: X >= Y
CMPV:   SEX     RD
        LDN     RF
        SM
        DEC     RF
        DEC     RD
        LDN     RF
        SMB
        DEC     RF
        DEC     RD
        LDN     RF
        SMB
        DEC     RF
        DEC     RD
        SEX     R2
        LDN     RD
        XRI     80H
        STR     R2
        LDN     RF
        XRI     80H
        SMB
        SEP     R5
; ==== the numbers: 32 bits, big-endian, in hundredths
; PUSHA: ACC on the value stack. POPB: the value stack's top to BV.
PUSHA:  GLO     R9
        LBZ     EVERR           ; too deep
        LOAD    RD, ACC
        LDI     4
        PLO     RC
PA1:    LDA     RD
        STR     R9
        INC     R9
        DEC     RC
        GLO     RC
        LBNZ    PA1
        SEP     R5
POPB:   LOAD    RD, BV + 3
        LDI     4
        PLO     RC
PO1:    DEC     R9
        LDN     R9
        STR     RD
        DEC     RD
        DEC     RC
        GLO     RC
        LBNZ    PO1
        SEP     R5
; NEGP: the value ending at RD negated (the one value with no opposite: EVERR). RB used.
NEGP:   LDN     RD
        SDI     0
        STR     RD
        DEC     RD
        LDN     RD
        SDBI    0
        STR     RD
        DEC     RD
        LDN     RD
        SDBI    0
        STR     RD
        DEC     RD
        LDN     RD
        PLO     RB
        SDBI    0
        STR     RD
        STR     R2
        GLO     RB
        AND
        ANI     80H
        LBNZ    EVERR
        SEP     R5
; ADDBA: ACC = BV + ACC
ADDBA:  LOAD    RD, ACC
        LDN     RD
        PHI     RC              ; the signs
        LOAD    RF, BV
        LDN     RF
        PLO     RC
        LOAD    RD, ACC + 3
        LOAD    RF, BV + 3
        SEX     RF
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        ADC
        STR     RD
        SEX     R2
        GHI     RC              ; both differ in sign from the answer: too big
        STR     R2
        LDN     RD
        XOR
        PHI     RB
        GLO     RC
        STR     R2
        LDN     RD
        XOR
        STR     R2
        GHI     RB
        AND
        ANI     80H
        LBNZ    EVERR
        LOAD    RD, ACC         ; the one value with no opposite is out of range too
        LDA     RD
        XRI     80H
        LBNZ    AD9
        LDA     RD
        LBNZ    AD9
        LDA     RD
        LBNZ    AD9
        LDN     RD
        LBZ     EVERR
AD9:    SEP     R5
; SGN: MSIGN = the answer's sign; ACC and BV made positive
SGN:    LOAD    RD, ACC
        LDN     RD
        STR     R2
        LOAD    RD, BV
        LDN     RD
        XOR
        PLO     RC
        LOAD    RD, MSIGN
        GLO     RC
        STR     RD
        LOAD    RD, ACC
        LDN     RD
        ANI     80H
        LBZ     SG1
        LOAD    RD, ACC + 3
        SEP     R4
        DW      NEGP
SG1:    LOAD    RD, BV
        LDN     RD
        ANI     80H
        LBZ     SG2
        LOAD    RD, BV + 3
        SEP     R4
        DW      NEGP
SG2:    SEP     R5
; SGNF: ACC given the sign MSIGN says
SGNF:   LOAD    RD, MSIGN
        LDN     RD
        ANI     80H
        LBZ     SG2
        LOAD    RD, ACC + 3
        LBR     NEGP
; MULBA: ACC = BV * ACC / 100. DIVBA: ACC = BV * 100 / ACC. Both to the nearest hundredth.
MULBA:  SEP     R4
        DW      SGN
        LOAD    RF, ACC
        LOAD    RD, MY
        SEP     R4
        DW      COPY4
        LOAD    RD, MD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        LDI     100
        STR     RD
        LBR     MD1
DIVBA:  LOAD    RD, ACC
        LDA     RD
        STR     R2
        LDA     RD
        OR
        STR     R2
        LDA     RD
        OR
        STR     R2
        LDN     RD
        OR
        LBZ     EVERR           ; by 0
        SEP     R4
        DW      SGN
        LOAD    RF, ACC
        LOAD    RD, MD
        SEP     R4
        DW      COPY4
        LOAD    RD, MY
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        LDI     100
        STR     RD
MD1:    SEP     R4
        DW      MCORE
        SEP     R4
        DW      DIVRND
        LBR     SGNF
; MCORE: MP (8 bytes) = BV * MY
MCORE:  LOAD    RD, MX
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        LOAD    RF, BV
        SEP     R4
        DW      COPY4
        LOAD    RD, MP
        LDI     8
        PLO     RC
MC0:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    MC0
MC1:    LOAD    RD, MY          ; nothing left in MY: done
        LDA     RD
        STR     R2
        LDA     RD
        OR
        STR     R2
        LDA     RD
        OR
        STR     R2
        LDN     RD
        OR
        LBZ     MC9
        ADI     0
        LOAD    RD, MY          ; its low bit
        LDN     RD
        SHRC
        STR     RD
        INC     RD
        LDN     RD
        SHRC
        STR     RD
        INC     RD
        LDN     RD
        SHRC
        STR     RD
        INC     RD
        LDN     RD
        SHRC
        STR     RD
        LBNF    MC3
        LOAD    RD, MP + 7      ; set: MP += MX
        LOAD    RF, MX + 7
        LDI     8
        PLO     RC
        SEX     RF
        ADI     0
MC2:    LDN     RD
        ADC
        STR     RD
        DEC     RD
        DEC     RF
        DEC     RC
        GLO     RC
        LBNZ     MC2
        SEX     R2
MC3:    LOAD    RD, MX + 7      ; MX * 2
        LDI     8
        PLO     RC
        ADI     0
MC4:    LDN     RD
        SHLC
        STR     RD
        DEC     RD
        DEC     RC
        GLO     RC
        LBNZ     MC4
        LBR     MC1
MC9:    SEP     R5
; DIVRND: ACC = MP / MD (MD not 0), to the nearest. Too big: EVERR.
DIVRND: LOAD    RD, MD
        LDA     RD
        LBNZ    DVL
        LDA     RD
        LBNZ    DVL
        LDA     RD
        LBNZ    DVL
        LDN     RD              ; a one-byte divisor: a byte at a time, all in registers
        STR     R2
        LDI     0
        PLO     RA              ; the remainder
        LOAD    RD, MP
        LDI     8
        PHI     RC
DV1:    LDN     RD
        PLO     RB
        LBNZ    DV2
        GLO     RA
        LBZ     DV7             ; nothing to carry through a 0
DV2:    LDI     8
        PLO     RC
DV3:    GLO     RB
        SHL
        PLO     RB
        GLO     RA
        SHLC
        PLO     RA
        LBDF     DV4             ; 9 bits: it goes
        SM
        LBNF     DV6
        LBR      DV5
DV4:    SM
DV5:    PLO     RA
        GLO     RB
        ORI     1
        PLO     RB
DV6:    DEC     RC
        GLO     RC
        LBNZ     DV3
        GLO     RB
        STR     RD
DV7:    INC     RD
        GHI     RC
        SMI     1
        PHI     RC
        LBNZ    DV1
        GLO     RA              ; twice the remainder >= the divisor: up
        SHL
        LBDF    DVUP
        SM
        LBDF    DVUP
        LBR     DVF
DVL:    LOAD    RD, MR          ; the long way
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LDI     64
        PLO     RC
DL1:    LOAD    RD, MP          ; a top byte of 0: eight steps saved
        LDN     RD
        LBNZ    DL3
        LOAD    RF, MP + 1
        LDI     7
        PHI     RC
DL2:    LDA     RF
        STR     RD
        INC     RD
        GHI     RC
        SMI     1
        PHI     RC
        LBNZ    DL2
        LDI     0
        STR     RD
        GLO     RC
        SMI     8
        PLO     RC
        LBNZ    DL1
        LBR     DVF             ; it was 0
DL3:    ADI     0
        LOAD    RD, MP + 7      ; MP's top bit into MR (unrolled: a counter would lose DF)
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LOAD    RD, MR + 3
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LOAD    RF, MD + 3
        LOAD    RD, MR + 3
        SEX     RF
        LDN     RD
        SM
        PLO     RA
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        PHI     RA
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        PLO     RB
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        PHI     RB
        SEX     R2
        LBNF    DL5
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        INC     RD
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, MP + 7
        LDN     RD
        ORI     1
        STR     RD
DL5:    DEC     RC
        GLO     RC
        LBNZ    DL3
        ADI     0
        LOAD    RD, MR + 3      ; twice the remainder >= the divisor: up
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LBDF    DVUP
        LOAD    RF, MD + 3
        LOAD    RD, MR + 3
        SEX     RF
        LDN     RD
        SM
        PLO     RA
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        PHI     RA
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        PLO     RB
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        PHI     RB
        SEX     R2
        LBDF    DVUP
        LBR     DVF
DVUP:   LOAD    RD, MP + 7
        LDI     8
        PLO     RC
        SMI     0               ; DF = 1
DU1:    LDN     RD
        ADCI    0
        STR     RD
        DEC     RD
        DEC     RC
        GLO     RC
        LBNZ    DU1
DVF:    LOAD    RD, MP          ; it must fit in 31 bits
        LDA     RD
        LBNZ    EVERR
        LDA     RD
        LBNZ    EVERR
        LDA     RD
        LBNZ    EVERR
        LDA     RD
        LBNZ    EVERR
        LDN     RD
        ANI     80H
        LBNZ    EVERR
        LOAD    RF, MP + 4
        LOAD    RD, ACC
        LBR     COPY4
; STACC: ACC = RA:RB
STACC:  LOAD    RD, ACC
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        SEP     R5
; PNUMB: the number at R8 (digits, a point, digits; the third decimal rounds) -> ACC, in hundredths; R8 past it.
; DF = 1: too big. Works in RA:RB; RC RD RF used.
PNUMB:  LDI     0
        PHI     RA
        PLO     RA
        PHI     RB
        PLO     RB
PB1:    LDN     R8
        SMI     '0'
        LBNF    PB2
        SMI     10
        LBDF    PB2
        LDA     R8
        SMI     '0'
        PLO     RF
        SEP     R4
        DW      M10
        LBDF    PB9
        LBR     PB1
PB2:    LDN     R8
        XRI     '.'
        LBNZ    PB3
        INC     R8
PB3:    SEP     R4              ; tenths
        DW      FDIG
        SEP     R4
        DW      M10
        LBDF    PB9
        SEP     R4              ; hundredths
        DW      FDIG
        SEP     R4
        DW      M10
        LBDF    PB9
        SEP     R4              ; the next one rounds
        DW      FDIG
        GLO     RF
        SMI     5
        LBNF    PB5
        GLO     RB
        ADI     1
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        GLO     RA
        ADCI    0
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        SHL
        LBDF    PB9
PB5:    SEP     R4              ; the rest do not count
        DW      FDIG
        LDN     R8
        SMI     '0'
        LBNF    PB6
        SMI     10
        LBNF    PB5
PB6:    SEP     R4
        DW      STACC
        LDI     0
        SHR
PB9:    SEP     R5
; FDIG: RF.0 = the digit at R8, R8 past it; not a digit: 0, R8 stays
FDIG:   LDI     0
        PLO     RF
        LDN     R8
        SMI     '0'
        LBNF    FD9
        SMI     10
        LBDF    FD9
        LDA     R8
        SMI     '0'
        PLO     RF
FD9:    SEP     R5
; M10: RA:RB = RA:RB * 10 + RF.0. DF = 1: past 31 bits.
M10:    GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        GHI     RB
        PHI     RD
        GLO     RB
        PLO     RD
        SEP     R4
        DW      SH1
        LBDF    M19
        SEP     R4
        DW      SH1
        LBDF    M19
        GLO     RD
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RD
        STR     R2
        GHI     RB
        ADC
        PHI     RB
        GLO     RC
        STR     R2
        GLO     RA
        ADC
        PLO     RA
        GHI     RC
        STR     R2
        GHI     RA
        ADC
        PHI     RA
        SHL
        LBDF    M19
        SEP     R4
        DW      SH1
        LBDF    M19
        GLO     RF
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        GLO     RA
        ADCI    0
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        SHL
M19:    SEP     R5
; SH1: RA:RB * 2. DF = 1: bit 31 set.
SH1:    GLO     RB
        SHL
        PLO     RB
        GHI     RB
        SHLC
        PHI     RB
        GLO     RA
        SHLC
        PLO     RA
        GHI     RA
        SHLC
        PHI     RA
        SHL
        SEP     R5
; FMT: ACC in decimal, two places -> FMTB (0-ended), FMTL its length. R7 kept.
FMT:    LOAD    RD, ACC
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    R8, FNEG
        GHI     RA
        ANI     80H
        STR     R8
        LBZ     FM1
        GLO     RB
        SDI     0
        PLO     RB
        GHI     RB
        SDBI    0
        PHI     RB
        GLO     RA
        SDBI    0
        PLO     RA
        GHI     RA
        SDBI    0
        PHI     RA
FM1:    LOAD    RF, POWT        ; ten digits, by taking away powers of ten
        LOAD    R8, DIGB
        LDI     10
        PLO     R9
FM2:    LDI     0
        PHI     R9
FM3:    SEX     RF
        GLO     RB
        SM
        PLO     RC
        INC     RF
        GHI     RB
        SMB
        PHI     RC
        INC     RF
        GLO     RA
        SMB
        PLO     RD
        INC     RF
        GHI     RA
        SMB
        PHI     RD
        DEC     RF
        DEC     RF
        DEC     RF
        SEX     R2
        LBNF    FM4
        GHI     RD
        PHI     RA
        GLO     RD
        PLO     RA
        GHI     RC
        PHI     RB
        GLO     RC
        PLO     RB
        GHI     R9
        ADI     1
        PHI     R9
        LBR     FM3
FM4:    GHI     R9
        STR     R8
        INC     R8
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        DEC     R9
        GLO     R9
        LBNZ    FM2
        LOAD    RF, FMTB
        LOAD    R8, FNEG
        LDN     R8
        LBZ     FM5
        LDI     '-'
        STR     RF
        INC     RF
FM5:    LOAD    R8, DIGB        ; no leading zeros, but always one digit before the point
        LDI     7
        PLO     R9
FM6:    LDN     R8
        LBNZ    FM7
        INC     R8
        DEC     R9
        GLO     R9
        LBNZ    FM6
FM7:    INC     R9
FM8:    LDA     R8
        ADI     '0'
        STR     RF
        INC     RF
        DEC     R9
        GLO     R9
        LBNZ    FM8
        LDI     '.'
        STR     RF
        INC     RF
        LDA     R8
        ADI     '0'
        STR     RF
        INC     RF
        LDN     R8
        ADI     '0'
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        GLO     RF
        SMI     LOW(FMTB)
        PLO     RC
        LOAD    RD, FMTL
        GLO     RC
        STR     RD
        SEP     R5
POWT:   DB      000H,0CAH,09AH,03BH     ; 1,000,000,000 and on down, the low byte first
        DB      000H,0E1H,0F5H,005H
        DB      080H,096H,098H,000H
        DB      040H,042H,00FH,000H
        DB      0A0H,086H,001H,000H
        DB      010H,027H,000H,000H
        DB      0E8H,003H,000H,000H
        DB      064H,000H,000H,000H
        DB      00AH,000H,000H,000H
        DB      001H,000H,000H,000H
PEND:
; ---- the data: not in the file (the program clears what it needs)
DATA    EQU     ((PEND + 255) / 256) * 256
TYP     EQU     DATA
PH      EQU     DATA + 100H
PL      EQU     DATA + 200H
V0      EQU     DATA + 300H
V1      EQU     DATA + 400H
V2      EQU     DATA + 500H
V3      EQU     DATA + 600H
RING    EQU     DATA + 700H     ; 128 keys
POOL    EQU     DATA + 800H
POOLE   EQU     PTOP - 2        ; (a last line with no LF gets one)
; the tail of TYP
CUR     EQU     TYP + 0A0H
TOPV    EQU     TYP + 0A1H      ; (2) the pool's top
CHG     EQU     TYP + 0A3H      ; changed since it was saved
NAMED   EQU     TYP + 0A4H      ; (follows CHG) it has a name
MYDIR   EQU     TYP + 0A5H      ; (2) its folder
RHEAD   EQU     TYP + 0A7H      ; the key ring (RTAIL follows RHEAD)
RTAIL   EQU     TYP + 0A8H
KEY     EQU     TYP + 0A9H
INLEN   EQU     TYP + 0AAH
ARROK   EQU     TYP + 0ABH
SHOWP   EQU     TYP + 0ACH      ; rows 1 and 2 are out of date
NLEN    EQU     TYP + 0ADH
ECODE   EQU     TYP + 0AEH
MSIGN   EQU     TYP + 0AFH
FK      EQU     TYP + 0B0H
R1V     EQU     TYP + 0B1H      ; a range: R1V C1V R2V C2V
C1V     EQU     TYP + 0B2H
R2V     EQU     TYP + 0B3H
C2V     EQU     TYP + 0B4H
FNEG    EQU     TYP + 0B5H
PROG    EQU     TYP + 0B6H
EVR2    EQU     TYP + 0B7H      ; (2) and EVR6 (2) after it
LNP     EQU     TYP + 0BBH      ; (2)
LRC     EQU     TYP + 0BDH
FMTL    EQU     TYP + 0BEH
NAME11  EQU     TYP + 0C0H      ; (11)
TMP11   EQU     TYP + 0CBH      ; (11)
ACC     EQU     TYP + 0D6H      ; (4)
BV      EQU     TYP + 0DAH      ; (4)
FSUM    EQU     TYP + 0DEH      ; (4) then FMIN FMAX FCNT, cleared together
FMIN    EQU     TYP + 0E2H
FMAX    EQU     TYP + 0E6H
FCNT    EQU     TYP + 0EAH      ; (2)
; the tail of PH
INB     EQU     PH + 0A0H       ; (61)
NBUF    EQU     PH + 0E0H       ; (5)
CBUF    EQU     PH + 0F0H       ; (10)
; the tail of PL
MX      EQU     PL + 0A0H       ; (8)
MP      EQU     PL + 0A8H       ; (8)
MY      EQU     PL + 0B0H       ; (4)
MD      EQU     PL + 0B4H       ; (4)
MR      EQU     PL + 0B8H       ; (4)
DIGB    EQU     PL + 0BCH       ; (10)
FMTB    EQU     PL + 0C6H       ; (14)
        END
