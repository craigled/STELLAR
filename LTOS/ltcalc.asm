; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; ltcalc.asm - LTCALC.PRG: LTCALC [name] - a small spreadsheet in 1802 code: 8 columns (A-H) by 32 rows (256 cells),
;   20 rows on the screen at a time: the view moves as the cursor goes past its top or bottom.
;   A cell holds a number, text, or a formula: =A1+B1*2  =(A1-B2)/3  =SUM(A1:A10)  =AVG MIN MAX COUNT over ranges
;   (a list too: =SUM(A1:A3,C1:C3)). Numbers have two decimals: a 32-bit whole number of hundredths, up to
;   21,474,836.47 either way. Going past that, dividing by 0, a bad formula or a cell that needs itself shows ERR.
;
; The sheet in memory IS the file: a pool of lines, "A1 =B1*2" LF, in cell order (a line someone else put out of
; order still works; a line that names no cell stays in the file, unused). Saving writes the pool as it is, opening
; reads it as it is, and TYPE, GREP, RAWK and NANO can all use the file. A name with no extension gets .CLC.
; CSV (2026-11-24): opening NAME.CSV runs CSV2CLC -L NAME.CSV (csv2clc.asm: row n of the file is row n, its fields
;   A-H; quotes as Excel writes them), which makes /_CSV.CLC and runs LTCALC -C: the sheet, with no name yet; ^A with a name ending .CSV writes the values (numbers with two decimals,
;   formulas as what they give, ERR as ERR) - the sheet keeps its own name and its formulas.
;
; Memory, from the first page after the code, up to $6BFF:
;   seven pages, each indexed by the cell's number (0-255: row * 8 + column), so a cell's byte is one PLO away:
;   TYP  the kind (below) and its flags
;   PH PL  where its line is in the pool (0: empty)
;   V0-V3  its value (V0 the top byte)
;   a page for the variables, the math's work and (at its top) the value stack (2026-11-24: they were in the
;   pages' tails, after cell 159, when the sheet had 160 cells); a page for the key ring (its first half) and the
;   typed line and the cell's text (its top); then the pool, to PTOP. LTOS's own buffers ($6C00 up) stay LTOS's: saving and opening are the kernel's.
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

NROW    EQU     32              ; the sheet's rows (256 cells: a cell's number is a byte)
SROWS   EQU     20              ; the rows on the screen at a time
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
        LOAD    RD, VTOP        ; the view at row 1
        LDI     0
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LOAD    RD, CSVM
        LDI     0
        STR     RD
        LOAD    RD, SPON
        LDI     0
        STR     RD
        LDN     RF
        LBZ     ST5             ; no name
        XRI     '-'             ; -C: the sheet CSV2CLC made of a CSV
        BNZ     ST1
        INC     RF
        LDN     RF
        ANI     0DFH
        XRI     'C'
        BNZ     ST5
        LOAD    RD, CSVM
        LDI     1
        STR     RD
        LOAD    RF, TMPCSV
ST1:    GHI     RF              ; (the name as typed kept, for a CSV)
        STXD
        GLO     RF
        STXD
        LOAD    RD, TMP11
        SEP     R4
        DW      KS_NAMEP
        SEP     R4
        DW      DEFEXT
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        SEP     R4              ; NAME.CSV: CSV2CLC makes it a sheet
        DW      ISCSV
        BDF     ST2
        SEP     R4
        DW      XCSV
        SEP     R4
        DW      K_PIN
        DB      'There is no such file.',0DH,0AH,0
        LBR     K_MAIN
ST2:    LOAD    RD, CSVM
        LDN     RD
        BNZ     ST3
        SEP     R4
        DW      KEEPNM
ST3:    SEP     R4
        DW      LOADFILE
        LOAD    RD, LRC
        LDN     RD
        BZ      ST6             ; opened
        XRI     1
        BZ      ST5             ; not there yet: a new sheet of that name
        SEP     R4
        DW      K_PIN
        DB      'That file cannot be opened as a sheet.',0DH,0AH,0
        LBR     K_MAIN
ST5:    SEP     R4
        DW      CLEAR
ST6:    SEP     R4
        DW      REDRAW
        LOAD    RD, CSVM
        LDN     RD
        LBZ     MAINL
        LOAD    R8, MCSVIN
        SEP     R4
        DW      MESSAGE
; ---- the main loop: the line above the sheet only when no key is waiting
MAINL:  SEP     R4
        DW      RXPOLL
        LOAD    RD, RHEAD
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        BNZ     ML1
        LOAD    RD, SHOWP
        LDN     RD
        BZ      ML1
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
        GLO     RC
        XRI     12H             ; ^R: insert or delete a row
        LBZ     ROWK
        GLO     RC
        XRI     0CH             ; ^L: insert or delete a column
        LBZ     COLK
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
        BZ      EC9             ; empty: nothing to fetch
        SEP     R4
        DW      SRCP
        LOAD    RD, INB
        LDI     0
        PLO     RB
EC1:    LDA     R8
        PLO     RC
        SMI     20H
        BNF     EC9
        GLO     RC
        STR     RD
        INC     RD
        INC     RB
        GLO     RB
        XRI     INMAX
        BNZ     EC1
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
        BNF     MVSTAY
        BR      MVTO
MVDOWN: SEP     R4
        DW      CURR7
        GLO     R7
        ADI     8
        BDF     MVSTAY          ; (past row 32: the byte carried)
        BR      MVTO
MVRIGHT: SEP    R4
        DW      CURR7
        GLO     R7
        ANI     7
        XRI     7
        BZ      MVSTAY
        GLO     R7
        ADI     1
        BR      MVTO
MVLEFT: SEP     R4
        DW      CURR7
        GLO     R7
        ANI     7
        BZ      MVSTAY
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
        SEP     R4              ; off the screen: the view moves, all drawn again
        DW      VIEW
        BNF     MVT2
        SEP     R4
        DW      REDRAW
        BR      MVSTAY
MVT2:   SEP     R4
        DW      PUTCELL
MVSTAY: LOAD    RD, SHOWP
        LDI     1
        STR     RD
        LBR     MAINL
; ---- Esc: leave, asking first if there is something unsaved
QUIT:   LOAD    RD, CHG
        LDN     RD
        BZ      QT5
        LOAD    R8, QQUIT
        SEP     R4
        DW      ASKYN
        BDF     QT5
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
        BNF     KCANCEL
SV3:    SEP     R4              ; NAME.CSV: the values, written (the sheet keeps its own name)
        DW      ISCSV
        BNF     SVCSV
        SEP     R4
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
        BDF     SV8
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
; SVCSV: the sheet's values as CSV in the pool's free room (TOPV up), saved as TMP11 in WDIR (ASKNAME's)
SVCSV:  LOAD    RD, TOPV
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, OUTP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, FSTART
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, CFULL
        LDI     0
        STR     RD
        LOAD    RD, MAXR        ; the rows and columns in use
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        PLO     R7
CX1:    GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     7
        BZ      CX2
        GLO     R7
        SHR
        SHR
        SHR
        ADI     1
        PLO     RC
        LOAD    RD, MAXR
        LDN     RD
        STR     R2
        GLO     RC
        SD
        BDF     CX1B
        GLO     RC
        STR     RD
CX1B:   GLO     R7
        ANI     7
        ADI     1
        PLO     RC
        LOAD    RD, MAXC
        LDN     RD
        STR     R2
        GLO     RC
        SD
        BDF     CX2
        GLO     RC
        STR     RD
CX2:    INC     R7
        GLO     R7
        BNZ     CX1
        LOAD    RD, CROW
        LDI     0
        STR     RD
CX3:    LOAD    RD, MAXR        ; a row
        LDN     RD
        STR     R2
        LOAD    RD, CROW
        LDN     RD
        XOR
        LBZ     CXDONE
        LOAD    RD, CCOL
        LDI     0
        STR     RD
CX4:    LOAD    RD, MAXC        ; a column
        LDN     RD
        STR     R2
        LOAD    RD, CCOL
        LDN     RD
        XOR
        BZ      CX9
        LDN     RD
        BZ      CX5
        LDI     ','
        SEP     R4
        DW      PUTO
CX5:    LOAD    RD, CROW        ; R7.0 = the cell
        LDN     RD
        SHL
        SHL
        SHL
        STR     R2
        LOAD    RD, CCOL
        LDN     RD
        OR
        PLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     7
        BZ      CX8             ; empty: nothing between the commas
        XRI     K_TEXT
        BZ      CXT
        LDN     RD
        ANI     7
        SMI     K_FERR
        BDF     CXE
        SEP     R4              ; a number, or a formula's: its value, two decimals
        DW      GETV
        SEP     R4
        DW      FMT
        LOAD    R8, FMTB
CXV:    LDA     R8
        BZ      CX8
        SEP     R4
        DW      PUTO
        BR      CXV
CXE:    LOAD    R8, SERR
        BR      CXV
CXT:    SEP     R4              ; text: in quotes if it holds a comma or a quote (a quote in it doubled)
        DW      SRCP
        GHI     R8
        PHI     RB
        GLO     R8
        PLO     RB
CXT1:   LDA     R8
        XRI     0AH
        BZ      CXT5
        XRI     0AH XOR ','
        BZ      CXT2
        XRI     ',' XOR '"'
        BZ      CXT2
        BR      CXT1
CXT2:   GHI     RB
        PHI     R8
        GLO     RB
        PLO     R8
        LDI     '"'
        SEP     R4
        DW      PUTO
CXT3:   LDA     R8
        XRI     0AH
        BZ      CXT4
        XRI     0AH XOR '"'
        BNZ     CXT3A
        LDI     '"'
        SEP     R4
        DW      PUTO
CXT3A:  DEC     R8
        LDA     R8
        SEP     R4
        DW      PUTO
        BR      CXT3
CXT4:   LDI     '"'
        SEP     R4
        DW      PUTO
        BR      CX8
CXT5:   GHI     RB
        PHI     R8
        GLO     RB
        PLO     R8
CXT6:   LDA     R8
        XRI     0AH
        BZ      CX8
        DEC     R8
        LDA     R8
        SEP     R4
        DW      PUTO
        BR      CXT6
CX8:    LOAD    RD, CCOL
        LDN     RD
        ADI     1
        STR     RD
        LBR     CX4
CX9:    LDI     0DH             ; the row's end: CR LF
        SEP     R4
        DW      PUTO
        LDI     0AH
        SEP     R4
        DW      PUTO
        LOAD    RD, CROW
        LDN     RD
        ADI     1
        STR     RD
        LBR     CX3
CXDONE: LOAD    RD, CFULL
        LDN     RD
        BZ      CXD1
        LOAD    R8, MCSVBIG
        LBR     KMSG
CXD1:   LOAD    RD, FSTART      ; RA = its start, RC = its length
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, OUTP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RA
        STR     R2
        GLO     RC
        SM
        PLO     RC
        GHI     RA
        STR     R2
        GHI     RC
        SMB
        PHI     RC
        LOAD    RD, TMP11
        SEP     R4
        DW      K_SAVER
        LBDF    SV8
        LOAD    R8, MSAVCSV
        BR      KMSG
; PUTO: D at OUTP, OUTP + 1 - unless the pool is full (CFULL then 1). RD RF used.
PUTO:   STXD
        LOAD    RD, CFULL
        LDN     RD
        BNZ     PO9
        LOAD    RD, OUTP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        IRX
        LDX
        STR     RF
        INC     RF
        GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        GLO     RF
        XRI     LOW(POOLE)
        BNZ     PO8
        GHI     RF
        XRI     HIGH(POOLE)
        BNZ     PO8
        LOAD    RD, CFULL
        LDI     1
        STR     RD
PO8:    SEP     R5
PO9:    IRX
        SEP     R5
KMSG:   SEP     R4
        DW      MESSAGE
        LBR     MAINL
; ---- ^R / ^L: a row inserted above the cursor's, or the cursor's deleted; a column to its left, or its own. Every
;   cell's line is written again in the pool's free room under its new name, references in formulas moved as Excel
;   moves them (a range grows or shrinks; a reference to a deleted cell becomes A0: ERR), then the sheet is read
;   from those lines as a file is (Craig, 2026-11-24). Inserting is refused if row 32 / column H holds anything.
ROWK:   LDI     0               ; RCOP: 0 insert a row, 1 delete it, 2 insert a column, 3 delete it
        BR      RCK
COLK:   LDI     2
RCK:    STXD
        BNZ     XR0
        LOAD    R8, QROW
        BR      XR1
XR0:    LOAD    R8, QCOL
XR1:    SEP     R4
        DW      MESSAGE
        SEP     R4
        DW      RKEY
        LOAD    RD, KEY
        LDN     RD
        ANI     0DFH
        PLO     RC
        IRX
        LDX
        PLO     RB              ; RB.0 = 0 rows, 2 columns
        GLO     RC
        XRI     'I'
        BZ      XR2
        GLO     RC
        XRI     'D'
        LBNZ    KCANCEL
        INC     RB
XR2:    LOAD    RD, RCOP
        GLO     RB
        STR     RD
        SEP     R4              ; RCN = the cursor's row (1-32) or column (1-8)
        DW      CURR7
        GLO     RB
        ANI     2
        BNZ     XR3
        GLO     R7
        SHR
        SHR
        SHR
        BR      XR4
XR3:    GLO     R7
        ANI     7
XR4:    ADI     1
        PLO     RC
        LOAD    RD, RCN
        GLO     RC
        STR     RD
        GLO     RB              ; inserting: row 32 / column H empty?
        ANI     1
        BNZ     XR8
        LDI     0
        PLO     R7
XR5:    GLO     RB
        BNZ     XR6
        GLO     R7              ; a row: cells 248-255
        SMI     248
        BNF     XR7
        BR      XR6A
XR6:    GLO     R7              ; a column: cell & 7 = 7
        ANI     7
        XRI     7
        BNZ     XR7
XR6A:   GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     7
        BZ      XR7
        GLO     RB
        BNZ     XR6B
        LOAD    R8, MR32
        BR      KMSG
XR6B:   LOAD    R8, MCH
        BR      KMSG
XR7:    INC     R7
        GLO     R7
        BNZ     XR5
XR8:    LOAD    RD, SPON        ; (the spinner on: REPARSE's LOADFILE end turns it off)
        LDI     1
        STR     RD
        LOAD    RD, TOPV        ; the new lines at the pool's top: OUTP = FSTART = TOPV
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, OUTP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, FSTART
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, CFULL
        LDI     0
        STR     RD
        PLO     R7
XR9:    SEP     R4
        DW      SPINT
        GLO     R7              ; each cell with something in it
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     7
        LBZ     XR19
        GLO     R7              ; RA.1 = its row (1-32), RA.0 its column (1-8)
        SHR
        SHR
        SHR
        ADI     1
        PHI     RA
        GLO     R7
        ANI     7
        ADI     1
        PLO     RA
        SEP     R4              ; where it goes (DF = 1: a deleted one's)
        DW      RCMOVE
        LBDF    XR19
        SEP     R4
        DW      PUTREF
        LDI     ' '
        SEP     R4
        DW      PUTO
        SEP     R4              ; what it holds: a formula's references moved too
        DW      SRCP
        LDN     R8
        XRI     '='
        BNZ     XR17
        LOAD    RD, PREVC
        LDI     '='
        STR     RD
        SEP     R4
        DW      PUTO
        INC     R8
XR10:   LDN     R8              ; a formula, a character at a time
        XRI     0AH
        LBZ     XR18
        LDN     R8
        ANI     0DFH
        SMI     'A'
        BNF     XR15
        SMI     8
        BDF     XR15
        LOAD    RD, PREVC       ; a letter A-H, after no letter or digit: a reference?
        LDN     RD
        ANI     0DFH
        SMI     'A'
        BNF     XR11
        SMI     26
        BNF     XR15
XR11:   LDN     RD
        SMI     '0'
        BNF     XR12
        SMI     10
        BNF     XR15
XR12:   GHI     R8              ; (R8 kept: PREF moves it even when it says no)
        PHI     RB
        GLO     R8
        PLO     RB
        SEP     R4
        DW      PREF
        BNF     XR13
        GHI     RB
        PHI     R8
        GLO     RB
        PLO     R8
        BR      XR15
XR13:   GHI     RA              ; RA: 1-based
        ADI     1
        PHI     RA
        INC     RA
        LDN     R8              ; a range: A1:B7
        XRI     ':'
        BNZ     XR14
        GHI     RA
        STXD
        GLO     RA
        STXD
        GHI     R8
        PHI     RB
        GLO     R8
        PLO     RB
        INC     R8
        SEP     R4
        DW      PREF
        BNF     XR13A
        GHI     RB              ; not one after the colon: the first alone
        PHI     R8
        GLO     RB
        PLO     R8
        IRX
        LDXA
        PLO     RA
        LDX
        PHI     RA
        BR      XR14
XR13A:  GHI     RA              ; the pair: RA the first, RC the second
        ADI     1
        PHI     RC
        GLO     RA
        ADI     1
        PLO     RC
        IRX
        LDXA
        PLO     RA
        LDX
        PHI     RA
        SEP     R4
        DW      RCPAIR
        SEP     R4
        DW      PUTREF
        LDI     ':'
        SEP     R4
        DW      PUTO
        GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA
        SEP     R4
        DW      PUTREF
        BR      XR14B
XR14:   SEP     R4              ; one reference
        DW      RCMOVE
        BNF     XR14A
        LOAD    RA, 0001H       ; it is gone: A0, ERR
XR14A:  SEP     R4
        DW      PUTREF
XR14B:  LOAD    RD, PREVC
        LDI     '1'
        STR     RD
        BR      XR10
XR15:   LDA     R8              ; any other character, as it is
        PLO     RC
        LOAD    RD, PREVC
        GLO     RC
        STR     RD
        SEP     R4
        DW      PUTO
        BR      XR10
XR17:   LDA     R8              ; a number or text, as it is
        XRI     0AH
        LBZ     XR18
        XRI     0AH
        SEP     R4
        DW      PUTO
        LBR     XR17
XR18:   LDI     0AH
        SEP     R4
        DW      PUTO
XR19:   INC     R7
        GLO     R7
        LBNZ    XR9
        LOAD    RD, CFULL       ; no room: nothing changed
        LDN     RD
        LBZ     XR20
        SEP     R4
        DW      SPINEND
        LOAD    RD, SPON
        LDI     0
        STR     RD
        LOAD    R8, MNORM
        LBR     KMSG
XR20:   LOAD    RD, CUR         ; the cursor and the view kept over CLEAR
        LDN     RD
        STXD
        LOAD    RD, VTOP
        LDN     RD
        STXD
        SEP     R4
        DW      CLEAR
        IRX
        LDXA
        PLO     RB
        LDX
        PHI     RB
        LOAD    RD, VTOP
        GLO     RB
        STR     RD
        LOAD    RD, CUR
        GHI     RB
        STR     RD
        LOAD    RD, FSTART      ; the lines down to POOL
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, OUTP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RA, POOL
XR21:   GLO     RF
        STR     R2
        GLO     RC
        XOR
        BNZ     XR22
        GHI     RF
        STR     R2
        GHI     RC
        XOR
        BZ      XR23
XR22:   LDA     RF
        STR     RA
        INC     RA
        BR      XR21
XR23:   LOAD    RD, CSVM        ; then read as a file is (RA: their top), worked out, drawn again
        LDI     0
        STR     RD
        SEP     R4
        DW      REPARSE
        LOAD    RD, CHG
        LDI     1
        STR     RD
        SEP     R4
        DW      REDRAW
        LBR     MAINL
REPARSE: LBR    LO5
; RCMOVE: the cell RA (RA.1 row 1-32, RA.0 column 1-8) as RCOP moves it. DF = 1: it is deleted. RC kept.
RCMOVE: SEP     R4
        DW      RCWHICH         ; RF.0 = the part that moves (row or column), RF.1 = which (0 row, 1 col)
        LOAD    RD, RCN
        LDN     RD
        STR     R2
        LOAD    RD, RCOP
        LDN     RD
        ANI     1
        BNZ     XV2
        GLO     RF              ; inserting: n >= N: n + 1 (past the end: gone)
        SM
        BNF     XV8
        GLO     RF
        ADI     1
        PLO     RF
        SEP     R4
        DW      RCMAX
        BDF     XV9
        BR      XV8
XV2:    GLO     RF              ; deleting: n = N gone, n > N: n - 1
        SM
        BNF     XV8
        BZ      XV9
        GLO     RF
        SMI     1
        PLO     RF
XV8:    SEP     R4
        DW      RCPUT
        LDI     0
        SHR
        SEP     R5
XV9:    LDI     1
        SHR
        SEP     R5
; RCPAIR: a range RA:RC moved - each end as RCMOVE, but a deleted end stays at the cut (the low end) or comes back
;   one (the high end); a range all deleted: A0:A0
RCPAIR: GHI     RA              ; RB = the moving parts: RB.1 the first's, RB.0 the second's
        STXD
        GLO     RA
        STXD
        SEP     R4
        DW      RCWHICH
        GLO     RF
        PHI     RB
        GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA
        SEP     R4
        DW      RCWHICH
        GLO     RF
        PLO     RB
        IRX                     ; RA back to the first
        LDXA
        PLO     RA
        LDX
        PHI     RA
        LOAD    RD, PAIRS       ; (the ends kept)
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, RCOP
        LDN     RD
        ANI     1
        BNZ     XQ1
        SEP     R4              ; inserting: both as RCMOVE, past the end: the end
        DW      RCEND
        LBR     XQ9
XQ1:    LOAD    RD, RCN         ; deleting: a range all of it deleted?
        LDN     RD
        STR     R2
        GHI     RB
        XOR
        LBNZ    XQ2
        GLO     RB
        XOR
        LBNZ    XQ2
        LOAD    RA, 0001H
        LOAD    RC, 0001H
        SEP     R5
XQ2:    GHI     RB              ; the first: lo end (<= the second) at N stays; else as RCMOVE
        STR     R2
        GLO     RB
        SM                      ; second - first
        BNF     XQ3
        LDI     0               ; the first is the low end
        BR      XQ4
XQ3:    LDI     1
XQ4:    PLO     RE              ; RE.0 = 1: the first is the high end
        GHI     RB
        SEP     R4
        DW      RCEND1
        PHI     RB
        GLO     RE
        XRI     1
        PLO     RE
        GLO     RB
        SEP     R4
        DW      RCEND1
        PLO     RB
XQ9:    LOAD    RD, PAIRS       ; the ends back with their new parts: the first ...
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GHI     RB
        PLO     RF
        SEP     R4
        DW      RCPUT
        GHI     RA              ; (kept)
        STXD
        GLO     RA
        STXD
        LOAD    RD, PAIRS + 2   ; ... the second, into RC
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GLO     RB
        PLO     RF
        SEP     R4
        DW      RCPUT
        GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        IRX
        LDXA
        PLO     RA
        LDX
        PHI     RA
        SEP     R5
; RCEND (inserting): RB.1 and RB.0, each n >= N: n + 1, past the end: the end
RCEND:  GHI     RB
        SEP     R4
        DW      RCINS
        PHI     RB
        GLO     RB
        SEP     R4
        DW      RCINS
        PLO     RB
        SEP     R5
RCINS:  PLO     RF
        LOAD    RD, RCN
        LDN     RD
        STR     R2
        GLO     RF
        SM
        BNF     XN9
        GLO     RF
        ADI     1
        PLO     RF
        SEP     R4
        DW      RCMAX
        BNF     XN9
        DEC     RF
XN9:    GLO     RF
        SEP     R5
; RCEND1 (deleting): D = an end, RE.0 = 1 if it is the high one: > N: - 1; = N: the high end - 1, the low stays
RCEND1: PLO     RF
        LOAD    RD, RCN
        LDN     RD
        STR     R2
        GLO     RF
        SM
        BNF     XY9
        BNZ     XY8
        GLO     RE
        BZ      XY9
XY8:    DEC     RF
XY9:    GLO     RF
        SEP     R5
; RCWHICH: RF.0 = RA's moving part (RA.1 the row for 0/1, RA.0 the column for 2/3)
RCWHICH: LOAD   RD, RCOP
        LDN     RD
        ANI     2
        BNZ     XW1
        GHI     RA
        PLO     RF
        SEP     R5
XW1:    GLO     RA
        PLO     RF
        SEP     R5
; RCPUT: RA's moving part = RF.0
RCPUT:  LOAD    RD, RCOP
        LDN     RD
        ANI     2
        BNZ     XU1
        GLO     RF
        PHI     RA
        SEP     R5
XU1:    GLO     RF
        PLO     RA
        SEP     R5
; RCMAX: DF = 1 if RF.0 is past the last row (32) or column (8)
RCMAX:  LOAD    RD, RCOP
        LDN     RD
        ANI     2
        BNZ     XX1
        GLO     RF
        SMI     NROW + 1
        SEP     R5
XX1:    GLO     RF
        SMI     9
        SEP     R5
; PUTREF: RA (row 1-32 or 0, column 1-8) as a name: A0 .. H32
PUTREF: GLO     RA
        ADI     'A' - 1
        SEP     R4
        DW      PUTO
        GHI     RA
        PLO     RF
        LDI     0
        PHI     RF
XF1:    GLO     RF
        SMI     10
        BNF     XF3
        PLO     RF
        GHI     RF
        ADI     1
        PHI     RF
        BR      XF1
XF3:    GHI     RF
        LBZ     XF4
        ADI     '0'
        SEP     R4
        DW      PUTO
XF4:    GLO     RF
        ADI     '0'
        LBR     PUTO
QROW:   DB      'Row: I insert one above this, D delete this one (Esc: nothing) ',0
QCOL:   DB      'Column: I insert one left of this, D delete this one (Esc: nothing) ',0
MR32:   DB      'Row 32 is not empty: nothing done.',0
MCH:    DB      'Column H is not empty: nothing done.',0
MNORM:  DB      'No room to do that.',0
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
        SEP     R4              ; a CSV: CSV2CLC makes it a sheet (and runs LTCALC -C)
        DW      ISCSV
        BDF     OK2B
        LOAD    RF, INB
        SEP     R4
        DW      XCSV
        LOAD    R8, MNOFILE
        LBR     KMSG
OK2B:   SEP     R4
        DW      LOADFILE
        LOAD    RD, LRC
        LDN     RD
        BZ      OK5
        XRI     1
        BNZ     OK3
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
MSAVCSV: DB     'Saved the values as CSV.',0
MCSVIN: DB      'From a CSV: ^A saves it as a sheet.',0
TMPCSV: DB      '/_CSV.CLC',0
MCSVBIG: DB     'Not saved: no room for that much CSV.',0
SERR:   DB      'ERR',0
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
        BR      PUSHK
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
        BZ      PK9
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
        BZ      PP9
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
        BDF      GK9
        SEP     R4
        DW      RXPOLL
        BR      GETK
GK9:    SEP     R5
; ESCW: the next key if it comes soon (a sequence's next byte): DF = 1, D. DF = 0: none (~70 ms). R9 used.
ESCW:   LOAD    R9, 150
EW1:    SEP     R4
        DW      POPK
        BDF      EW9
        SEP     R4
        DW      RXPOLL
        DEC     R9
        GLO     R9
        BNZ      EW1
        GHI     R9
        BNZ      EW1
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
        BZ      RK2
        GLO     RB
        XRI     'O'
        BZ      RK2
RK0:    LDI     0
        PLO     RC
        LBR     RK8
RK2:    SEP     R4
        DW      ESCW
        BNF     RK0
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
        BNF     RK8
        PLO     RB
        LBR     RK5
RK8:    LOAD    RD, KEY
        GLO     RC
        STR     RD
        SEP     R5
; ---- printing. TPIN: the text after the call. TSTR: the text at R8. EOL: to the line's end. CLS: the whole screen
TPIN:   LDA     R6
        BZ      TP9
        SEP     R4
        DW      TXB
        BR      TPIN
TP9:    SEP     R5
TSTR:   LDA     R8
        BZ      TP9
        SEP     R4
        DW      TXB
        BR      TSTR
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
        BNF     PN2
        PLO     RB
        GHI     RB
        ADI     1
        PHI     RB
        BR      PN1
PN2:    GHI     RB
        BZ      PN3
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
        BZ      AY1
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
        BNZ     KN1
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
        BZ      EDX
        GLO     RC
        XRI     0AH
        BZ      EDX
        GLO     RC
        XRI     1BH
        BZ      EDX
        GLO     RC
        XRI     08H
        BZ      EDB
        GLO     RC
        XRI     7FH
        BZ      EDB
        LOAD    RD, ARROK
        LDN     RD
        BZ      ED2
        GLO     RC
        XRI     09H
        BZ      EDX
        GLO     RC
        ANI     0FCH
        XRI     80H
        BZ      EDX
ED2:    GLO     RC              ; a printable key
        SMI     20H
        BNF     EDLINE
        GLO     RC
        SHL
        BDF     EDLINE
        LOAD    RD, INLEN
        LDN     RD
        XRI     INMAX
        BZ      EDLINE
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
        BR      EDLINE
EDB:    LOAD    RD, INLEN
        LDN     RD
        BZ      EDLINE
        SMI     1
        STR     RD
        SEP     R4
        DW      TPIN
        DB      8,' ',8,0
        BR      EDLINE
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
        LOAD    RD, VTOP        ; the row numbers: VTOP + 1 on
        LDN     RD
        ADI     1
        PLO     RA
RD1:    LOAD    RD, VTOP        ; (its screen row: RA - VTOP + GROW - 1)
        LDN     RD
        STR     R2
        GLO     RA
        SM
        ADI     GROW - 1
        PHI     RC
        LDI     1
        PLO     RC
        GLO     RA
        SMI     10
        BDF     RD2
        INC     RC              ; (one digit: under the other's units)
RD2:    SEP     R4
        DW      GOTO
        GLO     RA
        SEP     R4
        DW      PNUM
        INC     RA
        LOAD    RD, VTOP
        LDN     RD
        STR     R2
        GLO     RA
        SM
        XRI     SROWS + 1
        BNZ     RD1
        LOAD    RD, TYP         ; the cells with something in them
RD3:    LDN     RD
        ANI     7
        BZ      RD4
        LDN     RD
        ORI     F_DIRTY
        STR     RD
RD4:    INC     RD
        GLO     RD
        BNZ     RD3
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
        BZ      DW2
        LDN     RD
        ANI     0FFH - F_DIRTY
        STR     RD
        SEP     R4
        DW      PUTCELL
DW2:    INC     R7
        GLO     R7
        BNZ     DW1
        SEP     R5
; VIEW: the view moved so that row R7.0 / 8 is on the screen: DF = 1 if it had to move
VIEW:   GLO     R7
        SHR
        SHR
        SHR
        PLO     RB
        LOAD    RD, VTOP
        LDN     RD
        STR     R2
        GLO     RB
        SM                      ; row - VTOP
        BNF     VW1             ; above it: the row at the top
        SMI     SROWS
        BNF     VW9             ; on the screen
        GLO     RB              ; below it: the row at the bottom
        SMI     SROWS - 1
        SKP                     ; (past the GLO)
VW1:    GLO     RB
        STR     RD
        SMI     0               ; DF = 1
        SEP     R5
VW9:    ADI     0               ; DF = 0
        SEP     R5
; CURR7: R7 = the current cell
CURR7:  LOAD    RD, CUR
        LDN     RD
        PLO     R7
        SEP     R5
; PUTCELL: cell R7.0 on the screen (the current one marked)
PUTCELL: LOAD   RD, VTOP        ; (a row off the screen: nothing)
        LDN     RD
        STR     R2
        GLO     R7
        SHR
        SHR
        SHR
        SM
        LBNF    PC9
        PHI     RC
        SMI     SROWS
        LBDF    PC9
        GHI     RC
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
        BNF     PC1
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
        BZ      IC1
        LDI     0
        SHR
        SEP     R5
IC1:    SMI     0
        SEP     R5
; CELLTXT: cell R7.0's nine characters -> CBUF (0-ended): eight of its own and a space, so a long number never
;   runs into the next column (Craig, 2026-11-24; it used all nine)
CELLTXT: LOAD   RD, CBUF
        LDI     9
        PLO     RC
CT1:    LDI     ' '
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        BNZ     CT1
        LDI     0
        STR     RD
        GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        ANI     7
        BZ      CT9             ; empty
        PLO     RB
        XRI     K_TEXT
        BZ      CTT
        GLO     RB
        SMI     K_FERR
        BDF     CTE
        SEP     R4              ; a value
        DW      GETV
        SEP     R4
        DW      FMT
        LOAD    RD, FMTL
        LDN     RD
        PLO     RC
        SDI     8               ; 8 - its length: where it starts
        BNF     CTH             ; too long
        ADI     LOW(CBUF)
        PLO     RD
        LDI     HIGH(CBUF)
        PHI     RD
        LOAD    RF, FMTB
CT2:    LDA     RF
        BZ      CT9
        STR     RD
        INC     RD
        BR      CT2
CTH:    LOAD    RD, CBUF
        LDI     8
        PLO     RC
CT3:    LDI     '#'
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        BNZ     CT3
CT9:    SEP     R5
CTE:    LOAD    RD, CBUF + 5
        LDI     'E'
        STR     RD
        INC     RD
        LDI     'R'
        STR     RD
        INC     RD
        STR     RD
        SEP     R5
CTT:    SEP     R4              ; text: its first eight characters
        DW      SRCP
        LOAD    RD, CBUF
        LDI     8
        PLO     RC
CT4:    LDA     R8
        PLO     RB
        SMI     20H
        BNF     CT9
        GLO     RB
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        BNZ     CT4
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
        BR      SC8
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
        BNZ     SA1
        SEP     R4
        DW      TPIN
        DB      '(no name)',0
        BR      SA5
SA1:    LOAD    R8, NAME11
        LDI     8
        PLO     RC
SA2:    LDA     R8
        PLO     RB
        XRI     ' '
        BZ      SA3
        GLO     RB
        SEP     R4
        DW      TXB
SA3:    DEC     RC
        GLO     RC
        BNZ     SA2
        LDN     R8              ; the extension
        XRI     ' '
        BZ      SA5
        LDI     '.'
        SEP     R4
        DW      TXB
        LDI     3
        PLO     RC
SA4:    LDA     R8
        PLO     RB
        XRI     ' '
        BZ      SA41
        GLO     RB
        SEP     R4
        DW      TXB
SA41:   DEC     RC
        GLO     RC
        BNZ     SA4
SA5:    LOAD    RD, CHG
        LDN     RD
        BZ      SA6
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
        BR      NI1
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
        BNZ     CR1
        LOAD    RD, CUR
        LDI     0
        STR     RD
        LOAD    RD, VTOP
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
        BNZ     SP1
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
        BNZ     GV1
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
        BNZ     SV1
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
        BNZ     SE3
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
        BZ      SE5
        SEP     R4
        DW      INSERT
        SEP     R4
        DW      CLASS
SE5:    LOAD    RD, CHG         ; (the star, the first time)
        LDN     RD
        BNZ     SE6
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
        BZ      RM9
        GHI     RA              ; RB = its end, past the LF
        PHI     RB
        GLO     RA
        PLO     RB
RM1:    LDA     RB
        XRI     0AH
        BNZ     RM1
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
        BNZ     RM3
        GLO     RB
        STR     R2
        GLO     RF
        XOR
        BZ      RM4
RM3:    LDA     RB
        STR     RD
        INC     RD
        GLO     RD              ; (now and then, a key typed meanwhile is kept)
        ANI     3FH
        BNZ     RM2
        SEP     R4
        DW      POLLS
        BR      RM2
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
        LDI     0               ; (256 cells: 0, counted down)
        PLO     RB
AJ1:    LDN     RD              ; (empty)
        BZ      AJ2
        LDN     RF              ; DF = 1: its address >= RA
        STR     R2
        GLO     RA
        SD
        LDN     RD
        STR     R2
        GHI     RA
        SDB
        BNF     AJ2
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
        BR      RI4
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
        BNZ     RI6
        GLO     RF
        STR     R2
        GLO     RA
        XOR
        BZ      RI7
RI6:    DEC     RF
        DEC     RD
        LDN     RF
        STR     RD
        GLO     RD              ; (now and then, a key typed meanwhile is kept)
        ANI     3FH
        BNZ     RI5
        SEP     R4
        DW      POLLS
        BR      RI5
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
        BZ      RI85
        STR     RD
        INC     RD
        BR      RI8
RI85:   LOAD    R8, INB
RI9:    LDA     R8
        BZ      RI95
        STR     RD
        INC     RD
        BR      RI9
RI95:   LDI     0AH
        STR     RD
        SEP     R5
; CLASS: what cell R7.0 holds, from its text: TYP (dirty), and a number's value
CLASS:  SEP     R4
        DW      SRCP
        LDN     R8
        XRI     '='
        BNZ     CL1
        LDI     K_FORM + F_WAIT + F_DIRTY + F_CHG
        BR      CLK
CL1:    LOAD    RD, MSIGN       ; a number? [+-] digits [. digits], and nothing after
        LDI     0
        STR     RD
        LDN     R8
        XRI     '-'
        BNZ     CL2
        LDI     80H
        STR     RD
        INC     R8
        BR      CL3
CL2:    LDN     R8
        XRI     '+'
        BNZ     CL3
        INC     R8
CL3:    LDN     R8              ; a digit, or a point and a digit
        XRI     '.'
        BNZ     CL4
        INC     R8
        LDN     R8
        DEC     R8
        BR      CL5
CL4:    LDN     R8
CL5:    SMI     '0'
        BNF     CLT
        SMI     10
        BDF     CLT
        SEP     R4
        DW      PNUMB
        BDF     CLO
        LDN     R8
        SMI     20H
        BDF     CLT
        SEP     R4
        DW      SGNF
        SEP     R4
        DW      STV
        LDI     K_NUM + F_DIRTY + F_CHG
        BR      CLK
CLO:    LDI     K_NERR + F_DIRTY + F_CHG
        BR      CLK
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
LO1:    LOAD    RD, SPON        ; the spinner on while a file is read and worked out
        LDI     1
        STR     RD
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    LO8             ; a folder
        LOAD    RD, KS_DSIZE    ; fits?
        LDA     RD
        LBNZ    LO8
        LDA     RD
        BNZ     LO8
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
        BDF     LO8
        GLO     RC
        SDI     LOW(POOLE)
        GHI     RC
        SDBI    HIGH(POOLE)
        BDF     LO2
LO8:    LDI     2
LO9:    PLO     RC
        LOAD    RD, LRC
        GLO     RC
        STR     RD
        SEP     R4              ; the spinner rubbed out, and off
        DW      SPINEND
        LOAD    RD, SPON
        LDI     0
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
        BNF     LO3
        LDI     3
        LBR     LO9
LO3:    LOAD    RD, KS_LDEND    ; the top
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GLO     RA              ; empty?
        XRI     LOW(POOL)
        BNZ     LO4
        GHI     RA
        XRI     HIGH(POOL)
        BZ      LO5
LO4:    DEC     RA              ; a last line with no LF gets one
        LDA     RA
        XRI     0AH
        BZ      LO5
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
LO6:    SEP     R4
        DW      SPINT
        LOAD    RD, LNP
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LOAD    RD, TOPV        ; at the top: done
        LDA     RD
        STR     R2
        GHI     R8
        XOR
        BNZ     LO61
        LDN     RD
        STR     R2
        GLO     R8
        XOR
        LBZ     LO7
LO61:   LDN     R8              ; (a line starting with a space is no cell's)
        XRI     ' '
        BZ      LO65
        SEP     R4
        DW      PREF
        BDF     LO65
        LDN     R8
        XRI     ' '
        BNZ     LO65
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
        LOAD    RD, CSVM        ; LTCALC -C (a CSV CSV2CLC made into /_CSV.CLC): a sheet with no name yet, not saved
        LDN     RD
        LBZ     LO7A
        LOAD    RD, CHG
        LDI     1
        STR     RD
        INC     RD              ; NAMED
        LDI     0
        STR     RD
LO7A:   LDI     0
        LBR     LO9
; XCSV: a CSV to open: the file named at RF (as typed) made a sheet by CSV2CLC -L, which then runs LTCALC -C. TMP11
;   (in WDIR) is the CSV: not there - DF = 1, nothing done. (CSV reading is CSV2CLC's: room for the sheet here.)
XCSV:   GHI     RF
        STXD
        GLO     RF
        STXD
        LOAD    RD, TMP11
        SEP     R4
        DW      KS_FINDN
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        BNF     XC1
        SEP     R5
XC1:    LOAD    RD, INB         ; the name to INB first (it may be in LINE itself: LTCALC NAME.CSV)
XC0:    LDA     RF
        STR     RD
        INC     RD
        BZ      XC0A
        XRI     ' '
        BNZ     XC0
        DEC     RD
        LDI     0
        STR     RD
XC0A:   LOAD    RA, XCCMD       ; LINE = CSV2CLC -L name
        LOAD    RD, KS_LINE
XC2:    LDA     RA
        BZ      XC3
        STR     RD
        INC     RD
        BR      XC2
XC3:    LOAD    RF, INB
XC3A:   LDA     RF
        STR     RD
        INC     RD
        BNZ     XC3A
        SEP     R4
        DW      CLS
        LBR     K_EXEC
XCCMD:  DB      'CSV2CLC -L ',0
; SPINT: while SPON, the spinner (spin.inc) turned every 32nd call - a long read or recalculation is seen to work
SPINT:  LOAD    RD, SPON
        LDN     RD
        LBZ     SPT9
        LOAD    RD, SPK
        LDN     RD
        ADI     1
        STR     RD
        ANI     1FH
        LBZ     SPIN
SPT9:   SEP     R5
SPK:    DB      0
        INCL    "spin.inc"
; ISCSV: DF = 0 if TMP11's extension is CSV (RD used)
ISCSV:  LOAD    RD, TMP11 + 8
        LDA     RD
        XRI     'C'
        LBNZ    IS9
        LDA     RD
        XRI     'S'
        LBNZ    IS9
        LDN     RD
        XRI     'V'
        BNZ     IS9
        LDI     0
        SHR
        SEP     R5
IS9:    LDI     1
        SHR
        SEP     R5
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
        BZ      RP2
        XRI     K_FORM XOR K_FERR
        BNZ     RP4
RP2:    SEP     R4              ; (a key typed meanwhile is kept)
        DW      RXPOLL
        SEP     R4
        DW      DEPS
        BNF     RP4
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
        LBNZ    RP1
        LOAD    RD, PROG
        LDN     RD
        LBNZ    RECALC
        LOAD    RD, TYP         ; those formulas wait
RC1:    LDN     RD
        ANI     F_CHG
        BZ      RC3
        LDN     RD
        ANI     7
        XRI     K_FORM
        BZ      RC2
        LDN     RD
        ANI     7
        XRI     K_FERR
        BNZ     RC3
RC2:    LDN     RD
        ORI     F_WAIT
        STR     RD
RC3:    INC     RD
        GLO     RD
        BNZ     RC1
RC4:    SEP     R4              ; (a file read: the spinner turns, a pass at a time)
        DW      SPINT
        LOAD    RD, PROG        ; a pass
        LDI     0
        STR     RD
        PLO     R7
RC5:    GLO     R7
        PLO     RD
        LDI     HIGH(TYP)
        PHI     RD
        LDN     RD
        SHL
        BNF     RC8             ; not waiting
        SEP     R4              ; (a key typed meanwhile is kept)
        DW      RXPOLL
        SEP     R4
        DW      EVAL
        LOAD    RD, ECODE
        LDN     RD
        XRI     2
        BZ      RC8             ; it needs one still waiting
        LOAD    RD, PROG
        LDI     1
        STR     RD
        LOAD    RD, ECODE
        LDN     RD
        BNZ     RC6
        SEP     R4              ; a value
        DW      STV
        LDI     K_FORM
        BR      RC7
RC6:    LDI     0
        PLO     RB
        LDI     K_FERR
RC7:    PLO     RC
        SEP     R4
        DW      SETK
RC8:    INC     R7
        GLO     R7
        BNZ     RC5
        LOAD    RD, PROG
        LDN     RD
        BNZ     RC4
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
        BNF     RC95
        LDI     0
        PLO     RB
        LDI     K_FERR
        PLO     RC
        SEP     R4
        DW      SETK
RC95:   INC     R7
        GLO     R7
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
        LOAD    R9, VPG + 0A0H  ; (the value stack: PUSHA stops at the page's end)
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      PEEK
        GLO     RF
        SMI     20H
        BDF     EVERR           ; something left over
        LDI     0
        BR      EVEND
EVWAIT: LDI     2
        BR      EVEND
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
        BNZ     PE1
        INC     R8
        BR      PEEK
PE1:    LDN     R8
        PLO     RF
        SMI     'a'
        BNF     PE9
        SMI     26
        BDF     PE9
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
        BZ      EXA
        GLO     RF
        XRI     '-'
        BZ      EXS
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
        BR      EX1
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
        BR      EX1
TERM:   SEP     R4
        DW      UNARY
TM1:    SEP     R4
        DW      PEEK
        GLO     RF
        XRI     '*'
        BZ      TMM
        GLO     RF
        XRI     '/'
        BZ      TMD
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
        BR      TM1
TMD:    INC     R8
        SEP     R4
        DW      PUSHA
        SEP     R4
        DW      UNARY
        SEP     R4
        DW      POPB
        SEP     R4
        DW      DIVBA
        BR      TM1
UNARY:  SEP     R4
        DW      PEEK
        GLO     RF
        XRI     '-'
        BNZ     UN1
        INC     R8
        SEP     R4
        DW      UNARY
        LOAD    RD, ACC + 3
        LBR     NEGP
UN1:    GLO     RF
        XRI     '+'
        BNZ     UN2
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
        BNF     UN5
        SMI     10
        BDF     UN5
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
        BR      CELLV
; PREF: a cell's name at R8 -> RA.1 its row (0-31), RA.0 its column; R8 past it. DF = 1: not a cell.
PREF:   SEP     R4
        DW      PEEK
        GLO     RF
        SMI     'A'
        BNF     PRX
        PLO     RA
        SMI     8
        BDF     PRX
        INC     R8
        LDN     R8
        SMI     '0'
        BNF     PRX
        SMI     10
        BDF     PRX
        LDA     R8
        SMI     '0'
        PHI     RA
        LDN     R8
        SMI     '0'
        BNF     PR2
        SMI     10
        BDF     PR2
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
        BZ      PRX
        SMI     NROW + 1
        BDF     PRX
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
        BNF     CV0
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
        BNZ     FN2
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
        BR      FN5
FN3:    INC     RB              ; the next one's name
        DEC     RC
        GLO     RC
        BNZ     FN3
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
        BNZ     FN7
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
        BNZ     FN8
        INC     R8
        BR      FN6
FN8:    GLO     RF
        XRI     ')'
        LBNZ    EVERR
        INC     R8
        LOAD    RD, FK          ; the answer
        LDN     RD
        PLO     RC
        XRI     1
        BNZ     FN81
        LOAD    RF, FSUM
        BR      FNCP
FN81:   GLO     RC
        XRI     3
        BNZ     FN82
        LOAD    RF, FMIN
        BR      FNCP
FN82:   GLO     RC
        XRI     4
        BNZ     FN83
        LOAD    RF, FMAX
FNCP:   LOAD    RD, ACC
        LBR     COPY4
FN83:   GLO     RC
        XRI     5
        BNZ     FN84
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
        BDF     DP1
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
        BNZ     DP3
        INC     R8
        SEP     R4
        DW      PREF
        BDF     DP1
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
        BZ      DP6
        INC     RA
        BR      DP5
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
        BNF     FG1
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
        BNF     FG5
        SEP     R4
        DW      FACC
FG5:    SEP     R4              ; (a long range: a key typed meanwhile is kept)
        DW      RXPOLL
        LOAD    RD, C2V
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        BZ      FG6
        INC     RA
        BR      FG4
FG6:    LOAD    RD, R2V
        LDN     RD
        STR     R2
        GHI     RA
        XOR
        BZ      FG9
        GHI     RA
        ADI     1
        PHI     RA
        BR      FG3
FG9:    SEP     R5
; FACC: ACC into the function's sum, count, least and most
FACC:   LOAD    RD, FCNT
        LDA     RD
        STR     R2
        LDN     RD
        OR
        BZ      FA1             ; the first: least and most
        LOAD    RF, ACC + 3
        LOAD    RD, FMIN + 3
        SEP     R4
        DW      CMPV
        BDF     FA2
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
        BNZ     PA1
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
        BNZ     PO1
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
        BNZ     AD9
        LDA     RD
        BNZ     AD9
        LDA     RD
        BNZ     AD9
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
        BZ      SG2
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
        BR      MD1
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
        BNZ     MC0
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
        BDF      DV4             ; 9 bits: it goes
        SM
        BNF      DV6
        BR       DV5
DV4:    SM
DV5:    PLO     RA
        GLO     RB
        ORI     1
        PLO     RB
DV6:    DEC     RC
        GLO     RC
        BNZ      DV3
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
        BNZ     DL3
        LOAD    RF, MP + 1
        LDI     7
        PHI     RC
DL2:    LDA     RF
        STR     RD
        INC     RD
        GHI     RC
        SMI     1
        PHI     RC
        BNZ     DL2
        LDI     0
        STR     RD
        GLO     RC
        SMI     8
        PLO     RC
        BNZ     DL1
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
        BDF     DVUP
        BR      DVF
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
        BNZ     DU1
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
        BNF     PB2
        SMI     10
        BDF     PB2
        LDA     R8
        SMI     '0'
        PLO     RF
        SEP     R4
        DW      M10
        LBDF    PB9
        BR      PB1
PB2:    LDN     R8
        XRI     '.'
        BNZ     PB3
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
        BNF     PB6
        SMI     10
        BNF     PB5
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
        BDF     M19
        SEP     R4
        DW      SH1
        BDF     M19
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
        BZ      FM1
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
        BNF     FM4
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
        BR      FM3
FM4:    GHI     R9
        STR     R8
        INC     R8
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        DEC     R9
        GLO     R9
        BNZ     FM2
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
        BNZ     FM7
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
        BNZ     FM8
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
VPG     EQU     DATA + 700H     ; the variables, the math, the value stack ($A0 up)
RING    EQU     DATA + 800H     ; 128 keys; the typed line and the cell's text at $A0 up
POOL    EQU     DATA + 900H
POOLE   EQU     PTOP - 2        ; (a last line with no LF gets one)
; the tail of TYP
TV      EQU     VPG - 0A0H      ; (the variables keep the offsets they had in TYP's tail)
CUR     EQU     TV + 0A0H
TOPV    EQU     TV + 0A1H      ; (2) the pool's top
CHG     EQU     TV + 0A3H      ; changed since it was saved
NAMED   EQU     TV + 0A4H      ; (follows CHG) it has a name
MYDIR   EQU     TV + 0A5H      ; (2) its folder
RHEAD   EQU     TV + 0A7H      ; the key ring (RTAIL follows RHEAD)
RTAIL   EQU     TV + 0A8H
KEY     EQU     TV + 0A9H
INLEN   EQU     TV + 0AAH
ARROK   EQU     TV + 0ABH
SHOWP   EQU     TV + 0ACH      ; rows 1 and 2 are out of date
NLEN    EQU     TV + 0ADH
ECODE   EQU     TV + 0AEH
MSIGN   EQU     TV + 0AFH
FK      EQU     TV + 0B0H
R1V     EQU     TV + 0B1H      ; a range: R1V C1V R2V C2V
C1V     EQU     TV + 0B2H
R2V     EQU     TV + 0B3H
C2V     EQU     TV + 0B4H
FNEG    EQU     TV + 0B5H
PROG    EQU     TV + 0B6H
EVR2    EQU     TV + 0B7H      ; (2) and EVR6 (2) after it
LNP     EQU     TV + 0BBH      ; (2)
LRC     EQU     TV + 0BDH
FMTL    EQU     TV + 0BEH
NAME11  EQU     TV + 0C0H      ; (11)
TMP11   EQU     TV + 0CBH      ; (11)
ACC     EQU     TV + 0D6H      ; (4)
BV      EQU     TV + 0DAH      ; (4)
FSUM    EQU     TV + 0DEH      ; (4) then FMIN FMAX FCNT, cleared together
FMIN    EQU     TV + 0E2H
FMAX    EQU     TV + 0E6H
FCNT    EQU     TV + 0EAH      ; (2)
VTOP    EQU     TV + 0ECH      ; the first row on the screen (0-12)
OUTP    EQU     TV + 0EDH      ; (2) CSV: where the next byte goes
CROW    EQU     TV + 0EFH      ; CSV: the row (1 up reading, 0 up writing) and the column
CCOL    EQU     TV + 0F0H
FSTART  EQU     TV + 0F1H      ; (2) CSV: where this field's line starts (writing: the text's start)
FLEN    EQU     TV + 0F3H      ; CSV: the field's characters
MAXR    EQU     TV + 0F4H      ; CSV: the rows and columns in use (MAXC follows)
MAXC    EQU     TV + 0F5H
CFULL   EQU     TV + 0F6H      ; CSV: no room left for it
CSVM    EQU     TV + 0F7H      ; 1: LTCALC -C - the sheet is a CSV's, read by CSV2CLC
RCOP    EQU     VPG + 8DH      ; ^R / ^L: 0 insert a row, 1 delete it, 2 insert a column, 3 delete it
RCN     EQU     VPG + 8EH      ; the row (1-32) or column (1-8) it is done at
PREVC   EQU     VPG + 8FH      ; the character before, in a formula being copied
PAIRS   EQU     VPG + 90H      ; (4) a range's two ends being moved
SPON    EQU     VPG + 94H      ; 1: the spinner turns (a file read, ^R / ^L)
; the typed line and the cell's text: the top of RING's page
INB     EQU     RING + 0A0H       ; (61)
NBUF    EQU     RING + 0E0H       ; (5)
CBUF    EQU     RING + 0F0H       ; (10)
; the math: after the variables in VPG
PLV     EQU     VPG + 58H - 0A0H
MX      EQU     PLV + 0A0H       ; (8)
MP      EQU     PLV + 0A8H       ; (8)
MY      EQU     PLV + 0B0H       ; (4)
MD      EQU     PLV + 0B4H       ; (4)
MR      EQU     PLV + 0B8H       ; (4)
DIGB    EQU     PLV + 0BCH       ; (10)
FMTB    EQU     PLV + 0C6H       ; (14)
        END
