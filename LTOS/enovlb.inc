; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; enovlb.inc - NANO.OVL, its second half: at $7700-$7BFF while NANO runs (LTOS lends that RAM to a program).
;   The drawing, and the mark.
;   The screen: rows 1-23 the text, a long line shown over as many rows as it needs (wrapped after its last
;   space within 79 characters; none: after the 79th) - the text itself is not changed; row 24 the status
;   line (drawn when no key is waiting), messages and questions. The mark (^^, Alt-A, Shift + an arrow): the
;   text from it to the cursor in reverse; ^K cuts it, Alt-6 copies it.
;   RE.1 is never touched (the BIOS's); every call clobbers RE.0 and M(R2).
        ORG     7700H

; ---- small things
; RXKEEP: a key that came -> the ring; RD and RF kept (for the loops that check the UART themselves)
RXKEEP: GHI     RD
        STXD
        GLO     RD
        STXD
        GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      RXPOLL
        IRX
        LDXA
        PLO     RF
        LDXA
        PHI     RF
        LDXA
        PLO     RD
        LDX
        PHI     RD
        SEP     R5
; GAPR: R9 = GL, RA = GH (for SEGLEN, DROW, OFFP)
GAPR:   SEP     R4
        DW      GW9
        DB      V_GL
        SEP     R4
        DW      GW
        DB      V_GH
        GHI     R7
        PHI     RA
        GLO     R7
        PLO     RA
        SEP     R5
; SEGLEN: a screen row of the line at R8 (R9 = GL, RA = GH: the gap stepped over): RB.0 = its characters, R8 =
;   the next row's start; DF = 1: the line ended there (R8 past its LF, or at the text's end). Uses RB RD RF.
SEGLEN: LDI     0
        PLO     RB
        PHI     RB              ; RB.1 = the characters up to and with its last space (0: none)
SG1:    LDI     15H             ; a key in? kept
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        BZ      SG2
        SEP     R4
        DW      RXKEEP
SG2:    GLO     R8              ; the gap stepped over
        STR     R2
        GLO     R9
        XOR
        BNZ     SG3
        GHI     R8
        STR     R2
        GHI     R9
        XOR
        BNZ     SG3
        GHI     RA
        PHI     R8
        GLO     RA
        PLO     R8
SG3:    GHI     R8              ; the text's end
        XRI     HIGH(TEND)
        BZ      SGEND
        GHI     R8
        PHI     RD
        GLO     R8
        PLO     RD              ; RD = this character's place
        LDA     R8
        XRI     0AH
        BZ      SGEND
        GLO     RB              ; a whole row already: it breaks before this one
        XRI     WCOL
        BZ      SGBRK
        LDN     RD
        XRI     ' '
        BNZ     SG4
        GLO     RB              ; a space: the row may break after it
        ADI     1
        PHI     RB
        GHI     R8
        PHI     RF
        GLO     R8
        PLO     RF
SG4:    INC     RB
        BR      SG1
SGEND:  LDI     1
        SHR
        SEP     R5
SGBRK:  GHI     RB
        BZ      SGB2
        PLO     RB              ; after the last space
        GHI     RF
        PHI     R8
        GLO     RF
        PLO     R8
        BR      SGB3
SGB2:   GHI     RD              ; none: after the 79th
        PHI     R8
        GLO     RD
        PLO     R8
SGB3:   LDI     0
        SHR
        SEP     R5
; OFFP: R7 = the place in the text (GL - TS counting) of the character at R8 (R9 = GL, RA = GH)
OFFP:   GLO     R9
        STR     R2
        GLO     R8
        SM
        GHI     R9
        STR     R2
        GHI     R8
        SMB
        GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
        BNF     OFP2             ; before the gap: R8 - TS
        GLO     R9              ; after it: R8 + GL - GH - TS
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     R9
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        GLO     RA
        STR     R2
        GLO     R7
        SM
        PLO     R7
        GHI     RA
        STR     R2
        GHI     R7
        SMB
        PHI     R7
OFP2:    GLO     R7
        SMI     LOW(TS)
        PLO     R7
        GHI     R7
        SMBI    HIGH(TS)
        PHI     R7
        SEP     R5
; ---- drawing
; DROW: the RB.0 characters at R8 on the screen (a control character as ?, a tab as a space; those in the mark
;   in reverse), then ESC [ K; R8 past them. (R7 RB RC RD RF used)
DROW:   GLO     R8              ; (at the gap: past it first - OFFP counts from after it)
        STR     R2
        GLO     R9
        XOR
        BNZ     DW0
        GHI     R8
        STR     R2
        GHI     R9
        XOR
        BNZ     DW0
        GHI     RA
        PHI     R8
        GLO     RA
        PLO     R8
DW0:    SEP     R4
        DW      OFFP            ; R7 = the first one's place
        LDI     0
        PHI     RC              ; RC.1 = 1: reverse on
DW1:    GLO     RB
        LBZ     DW8
        GLO     R8              ; the gap stepped over
        STR     R2
        GLO     R9
        XOR
        BNZ     DW2
        GHI     R8
        STR     R2
        GHI     R9
        XOR
        BNZ     DW2
        GHI     RA
        PHI     R8
        GLO     RA
        PLO     R8
DW2:    LOAD    RD, SELA        ; in the mark: SELA <= R7 < SELB
        INC     RD
        LDN     RD
        STR     R2
        GLO     R7
        SM
        DEC     RD
        LDN     RD
        STR     R2
        GHI     R7
        SMB
        LDI     0
        BNF     DW3
        INC     RD
        INC     RD
        INC     RD
        LDN     RD
        STR     R2
        GLO     R7
        SM
        DEC     RD
        LDN     RD
        STR     R2
        GHI     R7
        SMB
        LDI     0
        BDF     DW3
        LDI     1
DW3:    STR     R2              ; changed?
        GHI     RC
        XOR
        LBZ     DW5
        GHI     RC
        XRI     1
        PHI     RC
        BZ      DW4
        SEP     R4
        DW      TPIN
        DB      1BH,'[7m',0
        BR      DW5
DW4:    SEP     R4
        DW      TPIN
        DB      1BH,'[0m',0
DW5:    LDA     R8
        PLO     RF
        XRI     09H
        BZ      DWSP
        GLO     RF
        SMI     7FH
        BDF     DWQ
        GLO     RF
        SMI     20H
        BDF     DW6
DWQ:    LDI     '?'
        LSKP
DWSP:   LDI     ' '
        PLO     RF
DW6:    GLO     RF
        SEP     R4
        DW      TXB
        INC     R7
        DEC     RB
        LBR     DW1
DW8:    GHI     RC
        BZ      DW9
        SEP     R4
        DW      TPIN
        DB      1BH,'[0m',0
DW9:    LBR     EOL
; DLINE: the line at R8 drawn from screen row DROWN on (rows past the last: counted, not drawn); R8 = the next
;   line; DLN = its rows. (R7 RB RC RD RF used)
DLINE:  LDI     0
        SEP     R4
        DW      PB
        DB      V_DLN
DL1:    SEP     R4              ; R8 kept: this row's start
        DW      PW8
        DB      V_DL0
        SEP     R4
        DW      SEGLEN
        LDI     0
        SHLC
        SEP     R4
        DW      PB
        DB      V_DEND          ; 1: the line ended
        GLO     RB
        SEP     R4
        DW      PB
        DB      V_DCNT
        SEP     R4              ; the next row's start
        DW      PW8
        DB      V_DNX
        SEP     R4
        DW      GB
        DB      V_DROWN
        SMI     NROWS
        BDF     DL2             ; past the last row: not drawn
        ADI     NROWS + 1
        SEP     R4
        DW      GOTOL
        SEP     R4
        DW      GW8
        DB      V_DL0
        SEP     R4
        DW      GB
        DB      V_DCNT
        PLO     RB
        SEP     R4
        DW      DROW
DL2:    SEP     R4              ; the next row
        DW      GB
        DB      V_DROWN
        ADI     1
        SEP     R4
        DW      PB
        DB      V_DROWN
        SEP     R4
        DW      GB
        DB      V_DLN
        ADI     1
        SEP     R4
        DW      PB
        DB      V_DLN
        SEP     R4
        DW      GW8
        DB      V_DNX
        SEP     R4
        DW      GB
        DB      V_DEND
        BZ      DL1
        SEP     R5
; ---- REDRAW: what RDF asks for. 1: every line; 2: from line DFROM (or the cursor's, the upper) on; 4: the
;   cursor's line; 8: line OROW too. The status line marked to be drawn again.
REDRAW: SEP     R4              ; the mark's ends (none: 0 and 0)
        DW      SELAB
        SEP     R4
        DW      GB
        DB      V_RDF
        LBZ     RD9
        ANI     1
        BZ      RD2
        LDI     0
        BR      RD3
RD2:    SEP     R4
        DW      GB
        DB      V_RDF
        ANI     2
        LBZ     RD5
        SEP     R4              ; the upper of DFROM and CLI
        DW      GB
        DB      V_DFROM
        PLO     RB
        SEP     R4
        DW      GB
        DB      V_CLI
        STR     R2
        GLO     RB
        SM
        GLO     RB
        BNF     RD3
        LDN     R2
RD3:    SEP     R4              ; from line D to the screen's end
        DW      LINEAT
        LDI     1
        SEP     R4
        DW      PB
        DB      V_DALL
        SEP     R4
        DW      DRAWLS
        LBR     RD9
RD5:    SEP     R4
        DW      GB
        DB      V_RDF
        ANI     4
        BZ      RD6
        SEP     R4
        DW      GB
        DB      V_CLI
        SEP     R4
        DW      DRAW1
RD6:    SEP     R4
        DW      GB
        DB      V_RDF
        ANI     8
        BZ      RD9
        SEP     R4
        DW      GB
        DB      V_OROW
        SEP     R4
        DW      DRAW1
RD9:    LDI     0
        SEP     R4
        DW      PB
        DB      V_RDF
        LDI     1
        SEP     R4
        DW      PB
        DB      V_SDIRTY
        SEP     R5
; DRAW1: line D alone (not past the screen's end)
DRAW1:  SMI     NROWS
        LBDF    TP9
        ADI     NROWS
        SEP     R4
        DW      LINEAT
        LDI     0
        SEP     R4
        DW      PB
        DB      V_DALL
; DRAWLS: from line DLI (at R8, its first row DROWN) on - DALL 0: that line alone; else to the screen's end (the
;   rows after the text's end cleared). LROWS kept for the lines drawn.
DRAWLS: SEP     R4
        DW      GAPR
DS1:    SEP     R4
        DW      GB
        DB      V_DROWN
        SMI     NROWS
        LBDF    TP9             ; the screen is full
        GLO     R8              ; (the gap stepped over)
        STR     R2
        GLO     R9
        XOR
        BNZ     DS1A
        GHI     R8
        STR     R2
        GHI     R9
        XOR
        BNZ     DS1A
        GHI     RA
        PHI     R8
        GLO     RA
        PLO     R8
DS1A:   GHI     R8              ; the text's end: the rest cleared
        XRI     HIGH(TEND)
        BZ      DS5
        SEP     R4
        DW      DLINE
        SEP     R4              ; LROWS[DLI] = its rows
        DW      GB
        DB      V_DLI
        SMI     NROWS
        BDF     DS2
        ADI     NROWS + LOW(LROWS)
        PLO     RD
        LDI     HIGH(LROWS)
        ADCI    0
        PHI     RD
        SEP     R4
        DW      GB
        DB      V_DLN
        STR     RD
DS2:    SEP     R4
        DW      GB
        DB      V_DALL
        LBZ     TP9
        SEP     R4
        DW      GB
        DB      V_DLI
        ADI     1
        SEP     R4
        DW      PB
        DB      V_DLI
        BR      DS1
DS5:    SEP     R4              ; (an empty line after a last LF: drawn as one)
        DW      GB
        DB      V_DROWN
        ADI     1
        SEP     R4
        DW      GOTOL
        SEP     R4
        DW      EOL
        SEP     R4
        DW      GB
        DB      V_DALL
        LBZ     TP9
        SEP     R4
        DW      GB
        DB      V_DROWN
        ADI     1
        SEP     R4
        DW      PB
        DB      V_DROWN
        BR      DS1
; LINEAT: line D's start -> R8, DLI, DROWN (its first row). Above the cursor's line: back from CLP; below it:
;   on from CLP (the rows of the lines between counted).
LINEAT: SEP     R4
        DW      PB
        DB      V_DLI
        SEP     R4
        DW      GAPR
        SEP     R4
        DW      GW8
        DB      V_CLP
        SEP     R4              ; the cursor's line's first row
        DW      ROWSUM
        SEP     R4
        DW      PB
        DB      V_DROWN
        SEP     R4
        DW      GB
        DB      V_CLI
        PLO     RC
LA1:    SEP     R4              ; above: back a line at a time (its rows off DROWN)
        DW      GB
        DB      V_DLI
        STR     R2
        GLO     RC
        SM
        LBZ     LA9
        BNF     LA5
        DEC     RC
        DEC     R8
        SEP     R4
        DW      BACKL
        SEP     R4
        DW      GB
        DB      V_DROWN
        PLO     RB
        GLO     RC
        ADI     LOW(LROWS)
        PLO     RD
        LDI     HIGH(LROWS)
        ADCI    0
        PHI     RD
        LDN     RD
        STR     R2
        GLO     RB
        SM
        SEP     R4
        DW      PB
        DB      V_DROWN
        LBR     LA1
LA5:    SEP     R4              ; below: on a line at a time (its rows onto DROWN)
        DW      LROWS1
        SEP     R4
        DW      GB
        DB      V_DROWN
        PLO     RB
        GLO     RC
        ADI     LOW(LROWS)
        PLO     RD
        LDI     HIGH(LROWS)
        ADCI    0
        PHI     RD
        LDN     RD
        STR     R2
        GLO     RB
        ADD
        SEP     R4
        DW      PB
        DB      V_DROWN
        INC     RC
        LBR     LA1
LA9:    SEP     R5
; PLACE: the terminal's cursor to ours
PLACE:  SEP     R4
        DW      GB
        DB      V_CROW
        ADI     1
        SEP     R4
        DW      PB
        DB      V_GR
        SEP     R4
        DW      GW
        DB      V_CSCOL
        GLO     R7
        ADI     1
        SEP     R4
        DW      PB
        DB      V_GC
        LBR     GOTO
; ---- the mark
; SELAB: SELA, SELB = the mark's two ends, the smaller first (no mark: 0 and 0). RB = SELA, R7 = SELB too.
SELAB:  LOAD    RB, 0
        LOAD    R7, 0
        SEP     R4
        DW      GB
        DB      V_MKON
        LBZ     SB4
        SEP     R4              ; (GW8 loads R7 too: the mark first)
        DW      GW8
        DB      V_MARK
        SEP     R4
        DW      CUROFF
        GLO     R8              ; R7 = the cursor's place, R8 the mark's: the smaller in RB
        STR     R2
        GLO     R7
        SM
        GHI     R8
        STR     R2
        GHI     R7
        SMB
        BNF     SB2
        GHI     R8
        PHI     RB
        GLO     R8
        PLO     RB
        BR      SB4
SB2:    GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
SB4:    LOAD    RD, SELA
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        SEP     R5
; MARKON: the mark set at the cursor, if it is not already
MARKON: SEP     R4
        DW      GB
        DB      V_MKON
        LBNZ    TP9
        LDI     1
        SEP     R4
        DW      PB
        DB      V_MKON
        SEP     R4
        DW      CUROFF
        SEP     R4
        DW      PW
        DB      V_MARK
        SEP     R5
; HMARK (^^, Alt-A): the mark set, or taken away
HMARK:  SEP     R4
        DW      GB
        DB      V_MKON
        BZ      HM2
UNMARK: LDI     0
        SEP     R4
        DW      PB
        DB      V_MKON
        LDI     1
        SEP     R4
        DW      SETRD
        LBR     LOOP
HM2:    SEP     R4
        DW      MARKON
        LBR     LOOP
; Shift + an arrow: the mark set (if it is not), then the move
HSUP:   SEP     R4
        DW      MARKON
        LBR     HUP
HSDN:   SEP     R4
        DW      MARKON
        LBR     HDOWN
HSRT:   SEP     R4
        DW      MARKON
        LBR     HRIGHT
HSLT:   SEP     R4
        DW      MARKON
        LBR     HLEFT
; HESC: a lone Esc - the mark taken away; with none, leave (as ^X)
HESC:   SEP     R4
        DW      GB
        DB      V_MKON
        BNZ     UNMARK
        LBR     HEXIT
; HCUTX (^K): the marked text cut; with no mark, the line (HCUT)
HCUTX:  SEP     R4
        DW      GB
        DB      V_MKON
        LBZ     HCUT
        SEP     R4
        DW      MSIZE           ; RC = its size (DF = 1: too big - said)
        LBDF    LOOP
        SEP     R4              ; the cursor to its start: the marked text then just after the gap
        DW      SELAB
        GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
        SEP     R4
        DW      MOVETO
        SEP     R4              ; (MOD, DCOL, from this line on)
        DW      MARK
        SEP     R4              ; (RC again, from SELA and SELB: MOVETO used it, and the cursor is at the mark now)
        DW      MSIZE2
        SEP     R4
        DW      GW9
        DB      V_GH
        SEP     R4
        DW      CLIPIN          ; RC bytes from R9 into the cut buffer
        SEP     R4
        DW      PW
        DB      V_CLIPN
        SEP     R4
        DW      PW9
        DB      V_GH            ; and gone from the text
        LBR     MDONE
; HCOPY (Alt-6): the marked text copied into the cut buffer
HCOPY:  SEP     R4
        DW      GB
        DB      V_MKON
        LBZ     LOOP
        SEP     R4
        DW      MSIZE
        LBDF    LOOP
        SEP     R4              ; the cursor at its end: it is before the gap (from TS + SELA); at its start: after
        DW      GWB
        DB      V_MARK
        SEP     R4
        DW      CUROFF
        SEP     R4
        DW      SUBRB           ; DF = 1: the cursor after the mark
        LBNF    HC2
        SEP     R4
        DW      GW9
        DB      V_MARK
        GLO     R9
        ADI     LOW(TS)
        PLO     R9
        GHI     R9
        ADCI    HIGH(TS)
        PHI     R9
        BR      HC3
HC2:    SEP     R4
        DW      GW9
        DB      V_GH
HC3:    SEP     R4
        DW      CLIPIN
        SEP     R4
        DW      PW
        DB      V_CLIPN
        SEP     R4
        DW      MSGI
        DB      'Copied',0
MDONE:  LDI     0               ; the mark gone, everything drawn again, the next ^K a new cut
        SEP     R4
        DW      PB
        DB      V_CUTSQ
        LBR     UNMARK
; MSIZE: RC = the marked text's size; more than the cut buffer holds: said, DF = 1
MSIZE:  SEP     R4
        DW      SELAB
        LBR     MSZ
MSIZE2: LOAD    RD, SELA
        LDA     RD
        PHI     RB
        LDA     RD
        PLO     RB
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
MSZ:    SEP     R4
        DW      SUBRB           ; R7 = SELB - SELA
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        GLO     R7              ; more than CLIPMX?
        SMI     LOW(CLIPMX + 1)
        GHI     R7
        SMBI    HIGH(CLIPMX + 1)
        BNF     MS9
        SEP     R4
        DW      MSGI
        DB      'Too much to cut or copy (768 bytes at most)',0
        LDI     1
        SHR
        SEP     R5
MS9:    ADI     0
        SEP     R5
; CLIPIN: RC bytes from R9 into the cut buffer; R7 = RC (the count); R9 past them
CLIPIN: GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        LOAD    RD, CLIP
CLI1:    GLO     RC
        BNZ     CLI2
        GHI     RC
        BZ      CLI9
CLI2:    LDA     R9
        STR     RD
        INC     RD
        DEC     RC
        BR      CLI1
CLI9:    SEP     R5

; ---- the overlay's own variables (not in the file: set before use)
PGL:    DS      2               ; GL as the last FIXUP left it
SELA:   DS      2               ; the mark's ends, the smaller first (SELA, SELB: in this order)
SELB:   DS      2
LROWS:  DS      NROWS           ; the rows each line on the screen takes (NLV of them valid, from the top)
OVLEND:
