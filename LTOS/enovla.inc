; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; enovla.inc - NANO.OVL, its first half: at $6900-$6DFF while NANO runs (the text's room ends at $6900).
;   NANO.OVL is loaded once ATTACH.PRG has run (it may use RAM to $6AFF); its first 1,280 bytes go to $6900,
;   the rest (enovlb.inc) to $7700. The first word: PEND (NANO.PRG checks it - the two built together).
;   FIXUP (the screen's layout), RKEY (the keys), Up / Down by screen rows. RE.1 is never touched; a call clobbers RE.0 and M(R2).
        ORG     6900H
OVLHD:  DW      PEND

; ---- FIXUP: the top line (the cursor kept on the screen), the table of the rows each line on it takes (LROWS,
;   valid for NLV lines from the top), the cursor's line (CLP its start, CLI its index on the screen), its row
;   CSUB in that line, its column COL (in the line) and CSCOL (on the screen), CROW - and what must be drawn
FIXUP:  SEP     R4              ; an edit (the gap's size changed), or another part: the table stale from the
        DW      GWB             ;  edited line on, and the mark gone
        DB      V_GL
        SEP     R4
        DW      GW
        DB      V_GH
        SEP     R4
        DW      SUBRB           ; R7 = GH - GL
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GW
        DB      V_PGAP
        GLO     RC
        STR     R2
        GLO     R7
        XOR
        BNZ     FX1
        GHI     RC
        STR     R2
        GHI     R7
        XOR
        BNZ     FX1
        SEP     R4
        DW      GWB
        DB      V_WOFF
        SEP     R4
        DW      GW
        DB      V_PWOFF
        GLO     RB
        STR     R2
        GLO     R7
        XOR
        BNZ     FX0
        GHI     RB
        STR     R2
        GHI     R7
        XOR
        LBZ     FX3             ; neither
FX0:    LDI     0               ; another part: none of it
        SEP     R4
        DW      PB
        DB      V_NLV
        LBR     FX2
FX1:    GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_PGAP
        SEP     R4              ; NLV = the smaller of it and (the smaller of PCLN and CLN) - TLN
        DW      GWB
        DB      V_PCLN
        SEP     R4
        DW      GW
        DB      V_CLN
        SEP     R4
        DW      MIN7B
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GWB
        DB      V_TLN
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        SEP     R4
        DW      SUBRB           ; R7 = it - TLN (below 0: 0; 256 or more: NLV as it is)
        LDI     0
        LBNF    FX1A
        GHI     R7
        LBNZ    FX2
        GLO     R7
FX1A:   PLO     RC
        SEP     R4
        DW      GB
        DB      V_NLV
        PHI     RC
        GLO     RC
        STR     R2
        GHI     RC
        SM
        BNF     FX2
        GLO     RC
        SEP     R4
        DW      PB
        DB      V_NLV
FX2:    SEP     R4              ; the mark goes (an edit, another part)
        DW      GB
        DB      V_MKON
        BZ      FX2A
        LDI     0
        SEP     R4
        DW      PB
        DB      V_MKON
        LDI     1
        SEP     R4
        DW      SETRD
FX2A:   SEP     R4
        DW      GW
        DB      V_WOFF
        SEP     R4
        DW      PW
        DB      V_PWOFF
; ---- the top line: CLN < TLN, or CLN - TLN >= NROWS: TLN = CLN - 10 (or 0)
FX3:    SEP     R4
        DW      GWB
        DB      V_TLN
        SEP     R4
        DW      GW
        DB      V_CLN
        SEP     R4
        DW      SUBRB           ; R7 = CLN - TLN
        BNF     FXN
        GHI     R7
        BNZ     FXN
        GLO     R7
        SMI     NROWS
        BNF     FX4
FXN:    SEP     R4
        DW      GW
        DB      V_CLN
        GLO     R7
        SMI     10
        PLO     R7
        GHI     R7
        SMBI    0
        PHI     R7
        BDF     FXN1
        LOAD    R7, 0
FXN1:   SEP     R4
        DW      PW
        DB      V_TLN
        LDI     0
        SEP     R4
        DW      PB
        DB      V_NLV
        LDI     1
        SEP     R4
        DW      SETRD
        LBR     FX3
FX4:    GLO     R7
        SEP     R4
        DW      PB
        DB      V_CLI
; ---- CLP: the cursor's line's start; COL
        SEP     R4
        DW      GW8
        DB      V_GL
        SEP     R4
        DW      BACKL           ; R8 -> its line's start
        SEP     R4
        DW      PW8
        DB      V_CLP
        SEP     R4              ; COL = GL - CLP
        DW      GW
        DB      V_GL
        GLO     R8
        STR     R2
        GLO     R7
        SM
        PLO     R7
        GHI     R8
        STR     R2
        GHI     R7
        SMB
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_COL
; ---- the table: the rows of lines NLV .. CLI - 1 (they are all before the gap)
FX6:    SEP     R4              ; (none to count: on)
        DW      GB
        DB      V_NLV
        PLO     RC
        SEP     R4
        DW      GB
        DB      V_CLI
        STR     R2
        GLO     RC
        SM
        LBDF    FX9
        SEP     R4              ; back from CLP to line NLV's start
        DW      GAPR
        SEP     R4
        DW      GW8
        DB      V_CLP
        SEP     R4
        DW      GB
        DB      V_CLI
        PLO     RC
FX6A:   SEP     R4
        DW      GB
        DB      V_NLV
        STR     R2
        GLO     RC
        XOR
        BZ      FX7
        DEC     RC
        DEC     R8
        SEP     R4
        DW      BACKL
        BR      FX6A
FX7:    SEP     R4              ; then on: each line's rows, to the cursor's line
        DW      GB
        DB      V_CLI
        STR     R2
        GLO     RC
        XOR
        BZ      FX9
        SEP     R4
        DW      LROWS1
        INC     RC
        GLO     RC
        SEP     R4
        DW      PB
        DB      V_NLV
        BR      FX7
; ---- the cursor's line: its rows, the one the cursor is on, its column there
FX9:    SEP     R4
        DW      GW8
        DB      V_CLP
        SEP     R4
        DW      CURSEG
; ---- CROW = the rows above it + CSUB; too low: lines off the top until it is at row 12 at most
FXR:    SEP     R4
        DW      GB
        DB      V_CSUB
        PLO     RC
        SEP     R4
        DW      ROWSUM          ; D = the rows of lines 0 .. CLI - 1
        STR     R2
        GLO     RC
        ADD
        SEP     R4
        DW      PB
        DB      V_CROW
        SMI     NROWS
        LBNF    FXK
        SEP     R4              ; drop the top line (the cursor's line is not the top one: CLI > 0)
        DW      GB
        DB      V_CLI
        LBZ     FXK
FXR1:   SEP     R4
        DW      GB
        DB      V_CLI
        LBZ     FXR2
        SEP     R4
        DW      GB
        DB      V_CROW
        SMI     12
        BNF     FXR2
        BZ      FXR2
        SEP     R4              ; CROW -= LROWS[0]; the table moves up one; TLN + 1; CLI - 1; TOPP past it
        DW      DROPT
        BR      FXR1
FXR2:   LDI     1
        SEP     R4
        DW      SETRD
; ---- what to draw: the cursor's line (an edit) took more or fewer rows - from it on
FXK:    SEP     R4
        DW      GWB
        DB      V_PCLN
        SEP     R4
        DW      GW
        DB      V_CLN
        GLO     RB
        STR     R2
        GLO     R7
        XOR
        PLO     RC
        GHI     RB
        STR     R2
        GHI     R7
        XOR
        STR     R2
        GLO     RC
        OR
        PLO     RC              ; RC.0 = 0: the same line as before
        BNZ     FXM
        SEP     R4
        DW      GB
        DB      V_CLR
        PHI     RC
        SEP     R4
        DW      GB
        DB      V_PCLR
        STR     R2
        GHI     RC
        XOR
        BZ      FXM
        SEP     R4
        DW      GB
        DB      V_CLI
        SEP     R4
        DW      PB
        DB      V_DFROM
        LDI     2
        SEP     R4
        DW      SETRD
; ---- the mark: the cursor moved - its line drawn again (and every line between, from another line)
FXM:    SEP     R4
        DW      GB
        DB      V_MKON
        BZ      FXD
        SEP     R4
        DW      GWB
        DB      V_GL
        LOAD    RD, PGL
        LDA     RD
        STR     R2
        GHI     RB
        XOR
        PHI     RF
        LDN     RD
        STR     R2
        GLO     RB
        XOR
        STR     R2
        GHI     RF
        OR
        BZ      FXD             ; not moved
        GLO     RC
        BNZ     FXM2
        LDI     4               ; the same line
        SEP     R4
        DW      SETRD
        BR      FXD
FXM2:   SEP     R4              ; from the upper of the two lines
        DW      GB
        DB      V_PCLI
        PLO     RB
        SEP     R4
        DW      GB
        DB      V_CLI
        STR     R2
        GLO     RB
        SM
        BNF     FXM3
        LDN     R2
        PLO     RB
FXM3:   GLO     RB
        SEP     R4
        DW      PB
        DB      V_DFROM
        LDI     2
        SEP     R4
        DW      SETRD
; ---- DCOL := CSCOL after a move across; what is kept for next time
FXD:    SEP     R4
        DW      GB
        DB      V_SETD
        BZ      FXE
        LDI     0
        SEP     R4
        DW      PB
        DB      V_SETD
        SEP     R4
        DW      MOVV
        DB      V_CSCOL, V_DCOL
FXE:    SEP     R4
        DW      MOVV
        DB      V_CLN, V_PCLN
        SEP     R4
        DW      GB
        DB      V_CLR
        SEP     R4
        DW      PB
        DB      V_PCLR
        SEP     R4
        DW      GB
        DB      V_CLI
        SEP     R4
        DW      PB
        DB      V_PCLI
        SEP     R4
        DW      GWB
        DB      V_GL
        LOAD    RD, PGL
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        SEP     R5
; BACKL: R8 back to the start of the line it is in (TS at most). RD RF kept.
BACKL:  GLO     R8
        XRI     LOW(TS)
        BNZ     BL1
        GHI     R8
        XRI     HIGH(TS)
        BZ      BL9
BL1:    LDI     15H             ; a key in? kept
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        BZ      BL2
        SEP     R4
        DW      RXKEEP
BL2:    DEC     R8
        LDN     R8
        XRI     0AH
        BNZ     BACKL
        INC     R8
BL9:    SEP     R5
; LROWS1: line RC.0's rows (the line at R8) -> LROWS[RC.0]; R8 = the next line. SKIPLN: R8 past the line.
LROWS1: LDI     0
        PHI     RC
LR1:    SEP     R4
        DW      SEGLEN
        BDF     LR2
        GHI     RC
        ADI     1
        PHI     RC
        BR      LR1
LR2:    GHI     RC
        ADI     1
        PHI     RC
        GLO     RC
        ADI     LOW(LROWS)
        PLO     RD
        LDI     HIGH(LROWS)
        ADCI    0
        PHI     RD
        GHI     RC
        STR     RD
        SEP     R5
SKIPLN: SEP     R4
        DW      SEGLEN
        BNF     SKIPLN
        SEP     R5
; CURSEG: the cursor's line (at R8): CLR its rows, CSUB the one the cursor is on (COL into the line), CSCOL its
;   column there. (RC.0: a row's characters, RC.1 = 1: the line's last row; RF: the row's end in the line)
CURSEG: SEP     R4
        DW      GAPR
        LDI     0
        SEP     R4
        DW      PB
        DB      V_CLR
        LOAD    R7, 0
        SEP     R4              ; T1: the row's start in the line
        DW      PW
        DB      V_T1
        LDI     0FFH
        SEP     R4
        DW      PB
        DB      V_CSUB
CS1:    SEP     R4
        DW      SEGLEN          ; RB.0 = its characters, DF = 1: the last row
        LDI     0
        SHLC
        PHI     RC
        GLO     RB
        PLO     RC
        SEP     R4              ; RF = T1 + n
        DW      GW
        DB      V_T1
        GLO     RC
        STR     R2
        GLO     R7
        ADD
        PLO     RF
        GHI     R7
        ADCI    0
        PHI     RF
        SEP     R4              ; the cursor placed already?
        DW      GB
        DB      V_CSUB
        XRI     0FFH
        BNZ     CS3
        GHI     RC              ; on this row if it is the last, or COL < RF
        BNZ     CS2
        SEP     R4
        DW      GWB
        DB      V_COL
        GHI     RF
        PHI     R7
        GLO     RF
        PLO     R7
        SEP     R4
        DW      SUBRB           ; R7 = RF - COL
        BNF     CS3
        GLO     R7
        BNZ     CS2
        GHI     R7
        BZ      CS3
CS2:    SEP     R4
        DW      GB
        DB      V_CLR
        SEP     R4
        DW      PB
        DB      V_CSUB
        SEP     R4              ; CSCOL = COL - T1
        DW      GWB
        DB      V_T1
        SEP     R4
        DW      GW
        DB      V_COL
        SEP     R4
        DW      SUBRB
        SEP     R4
        DW      PW
        DB      V_CSCOL
CS3:    GHI     RF              ; T1 = RF
        PHI     R7
        GLO     RF
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_T1
        SEP     R4
        DW      GB
        DB      V_CLR
        ADI     1
        SEP     R4
        DW      PB
        DB      V_CLR
        GHI     RC
        BZ      CS1
        SEP     R5
; ROWSUM: D = the rows of lines 0 .. CLI - 1 (LROWS). RD RF used.
ROWSUM: SEP     R4
        DW      GB
        DB      V_CLI
        PLO     RF
        LDI     0
        PHI     RF
        LOAD    RD, LROWS
RS1:    GLO     RF
        BZ      RS9
        GHI     RF
        SEX     RD
        ADD
        SEX     R2
        PHI     RF
        INC     RD
        DEC     RF
        BR      RS1
RS9:    GHI     RF
        SEP     R5
; DROPT: the top line off the screen: CROW -= LROWS[0], LROWS moves up one, NLV - 1, TLN + 1, CLI - 1
DROPT:  SEP     R4
        DW      GB
        DB      V_CROW
        PLO     RC
        LOAD    RD, LROWS
        LDN     RD
        STR     R2
        GLO     RC
        SM
        SEP     R4
        DW      PB
        DB      V_CROW
        LOAD    RD, LROWS
        LDI     NROWS - 1
        PLO     RF
DP1:    INC     RD
        LDN     RD
        DEC     RD
        STR     RD
        INC     RD
        DEC     RF
        GLO     RF
        BNZ     DP1
        SEP     R4
        DW      GB
        DB      V_NLV
        BZ      DP2
        SMI     1
        SEP     R4
        DW      PB
        DB      V_NLV
DP2:    SEP     R4
        DW      GB
        DB      V_CLI
        SMI     1
        SEP     R4
        DW      PB
        DB      V_CLI
        SEP     R4
        DW      GW
        DB      V_TLN
        INC     R7
        SEP     R4
        DW      PW
        DB      V_TLN
        SEP     R5
; ---- RKEY: D = a key: a character, a control key, a lone Esc (1BH), or K_xxx: ESC [ x, ESC O x (arrows,
;   Home, End), ESC [ n ~, ESC [ 1 ; 2 x (Shift + an arrow: K_Sxx), ESC x (an arrow whose [ was lost), Alt-\
;   Alt-/ (the document's top, end), Alt-A (the mark), Alt-6 (copy). 0: nothing. (R8 R9 RB RC used)
RKEY:   SEP     R4
        DW      GETK
        XRI     1BH
        BZ      RK1
        XRI     1BH
        SEP     R5
RK1:    SEP     R4
        DW      ESCW
        BNF     RKESC
        PLO     RC
        XRI     '['
        BZ      RK2
        XRI     '[' XOR 'O'
        BZ      RK2
        LOAD    R8, ALTT        ; ESC x
        BR      LOOKK
RK2:    SEP     R4
        DW      ESCW
        BNF     RKNO
        PLO     RC
        SMI     40H
        BDF     RK4             ; a letter: ESC [ x
        GLO     RC
        PHI     RC              ; RC.1 = the first digit
        LDI     0
        PLO     RB              ; RB.0 = the modifier (after a ;)
RK5:    SEP     R4              ; to the last byte (~ or a letter)
        DW      ESCW
        BNF     RKNO
        PLO     RC
        XRI     ';'
        BNZ     RK6
        SEP     R4
        DW      ESCW
        BNF     RKNO
        PLO     RB
        BR      RK5
RK6:    GLO     RC
        SMI     40H
        BNF     RK5
        GLO     RC
        XRI     '~'
        BZ      RK7
        GLO     RB              ; ESC [ 1 ; 2 x: Shift
        XRI     '2'
        BNZ     RK4
        LOAD    R8, SHFT
        BR      LOOKK
RK4:    LOAD    R8, ESCT
        BR      LOOKK
RK7:    GHI     RC              ; ESC [ n ~
        PLO     RC
        LOAD    R8, DIGT
; LOOKK: RC.0 in the table at R8 (pairs, 0-ended) -> D = its key (0: not there)
LOOKK:  LDA     R8
        BZ      LK9
        STR     R2
        GLO     RC
        XOR
        BZ      LK1
        INC     R8
        BR      LOOKK
LK1:    LDN     R8
LK9:    SEP     R5
RKNO:   LDI     0
        SEP     R5
RKESC:  LDI     1BH
        SEP     R5
ESCT:   DB      'A',K_UP,'B',K_DN,'C',K_RT,'D',K_LT,'H',K_HOME,'F',K_END,0
SHFT:   DB      'A',K_SUP,'B',K_SDN,'C',K_SRT,'D',K_SLT,0
DIGT:   DB      '1',K_HOME,'7',K_HOME,'4',K_END,'8',K_END,'3',K_DEL,'5',K_PGUP,'6',K_PGDN,0
ALTT:   DB      5CH,K_TOP,'/',K_BOT,'a',K_MARK,'A',K_UP,'B',K_DN,'C',K_RT,'D',K_LT,'6',K_COPY,0

; ---- Up / Down: a screen row (the line's next or last row, or the line above / below), column DCOL in it
HDOWN:  SEP     R4
        DW      GB
        DB      V_CLR
        PLO     RC
        SEP     R4
        DW      GB
        DB      V_CSUB
        ADI     1
        STR     R2
        GLO     RC
        SM
        BZ      HD2             ; the line's last row: the line below
        LDN     R2
        LBR     HU3
HD2:    SEP     R4
        DW      LINEDN
        LBDF    LOOP
        LDI     0
        LBR     HU3
HUP:    SEP     R4
        DW      GB
        DB      V_CSUB
        BZ      HU2
        SMI     1
        LBR     HU3
HU2:    SEP     R4
        DW      LINEUP
        LBDF    LOOP
        LDI     0FFH            ; its last row
HU3:    SEP     R4
        DW      SEGAT
        SEP     R4
        DW      COLIN
        SEP     R4
        DW      MOVETO
        LBR     LOOP
; SEGAT: the cursor's line's row D (or its last): T2 = the line's start, T1 = the row's start in it, RB.0 its
;   characters, RC.1 = 1 if it is the line's last row
SEGAT:  PLO     RC
        SEP     R4
        DW      GAPR
        SEP     R4
        DW      LSTART          ; R7 = the line's start
        SEP     R4
        DW      PW
        DB      V_T2
        GLO     R7
        ADI     LOW(TS)
        PLO     R8
        GHI     R7
        ADCI    HIGH(TS)
        PHI     R8
        LOAD    R7, 0
        SEP     R4
        DW      PW
        DB      V_T1
SGA1:   SEP     R4
        DW      SEGLEN
        LDI     0
        SHLC
        PHI     RC
        BNZ     SGA9            ; the last row
        GLO     RC
        BZ      SGA9            ; the one asked for
        DEC     RC
        SEP     R4              ; T1 += n
        DW      GW
        DB      V_T1
        GLO     RB
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_T1
        BR      SGA1
SGA9:   SEP     R5
; COLIN: R7 = T2 + T1 + the smaller of DCOL and the row's last column (RB.0 on the last row, RB.0 - 1 on another)
COLIN:  GLO     RB
        PLO     RC
        GHI     RC
        LBNZ    CI1
        GLO     RC
        BZ      CI1
        DEC     RC
CI1:    SEP     R4
        DW      GW
        DB      V_DCOL
        GHI     R7
        LBNZ    CI2
        GLO     RC
        STR     R2
        GLO     R7
        SD
        BDF     CI3
CI2:    GLO     RC
        PLO     R7
        LDI     0
        PHI     R7
CI3:    GHI     R7              ; + T1 + T2
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GWB
        DB      V_T1
        SEP     R4
        DW      GW
        DB      V_T2
        SEP     R4
        DW      ADDRB
        GHI     RC
        PHI     RB
        GLO     RC
        PLO     RB
        LBR     ADDRB

OVLAE:
