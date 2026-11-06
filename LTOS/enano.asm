; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; enano.asm - NANO.PRG: NANO [name] - a small full-screen editor in the style of the Linux nano, in 1802 code.
;   Lite-Writer 3's way with a long document: ATTACH.PRG lays the file out in one run of sectors (up to 60,000
;   bytes; 64 KB kept for it); a part of it is in memory (up to RLIM bytes read, the rest of TS-TEND to type in);
;   moving past the part's top or end brings in the next part - the document is written first if it changed.
;   ^O (or ^S) writes it; ^X (or Esc) leaves, asking first if it changed.
;
; Memory ($3000-$6BFF, all of it):
;   $3000-$32FF  code (part 1)
;   $3300-$335F  ATTACH's note (NOTEB) - read in place     $3360-$33FF  the variables (page VP, by offset)
;   $3400-$4CFF  code (part 2)
;   $4D00-$68FF  the text: a gap buffer [TS, GL) gap [GL, GH) [GH, TEND) (ATTACH.PRG runs at $4D00 first)
;   $6900-$6DFF  NANO.OVL's first half (enovla.inc)          $7700-$7BFF  its second half (enovlb.inc)
; and, while it runs, LTOS's buffers (none of them is kept from one command to the next; LTOS's FAT sector is
; forgotten when it leaves - KS_FATCUR):
;   $6E00-$70FF  the cut buffer (^K / ^U)       $7100-$71FF  the key ring, the search text, the typed line
;   $7200-$75FF  IB, OB: the card's two sector buffers
; The text holds LF line ends (a CR LF or a lone CR read from the card becomes one LF; LF is written).
; The terminal: the UART directly (as Lite-Writer 3): a key that arrives while the screen is written (or a long
; move is made) is kept (a ring of 128), not lost. Rows: 1-23 the text - a long line over as many rows as it
; needs (enovl.inc) - and 24 the status line (when no key is waiting), messages and questions. The screen's code,
; the keys and the mark are NANO.OVL, at $7700-$7BFF while it runs (loaded first; enovl.inc, enovl2.inc).
; Registers: RE.1 is never touched (the BIOS's); every SEP R4 call clobbers RE.0 and M(R2).
; verify_enano.py runs it on the simulated Elf2K.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

TS      EQU     4D00H           ; the text
TEND    EQU     6900H           ;  ... its end (the low byte 0: an end test is the high byte alone; NANO.OVL's
                                ;  first half from here to $6DFF)
CLIP    EQU     6E00H           ; the cut buffer
CLIPMX  EQU     768
RLIM    EQU     TEND - TS - 1536 ; the most of the card read into a part: 1,536 bytes left to type
NROWS   EQU     23              ; text rows (row 24: the status line)
WCOL    EQU     79              ; a row's characters at most
NOTE    EQU     NOTEB           ; ATTACH's note: +0 'LW' +2 k +3 L +5 D0 +7 NSECT +8 SPC +9 C1 +11 FL1 +13 FL2
                                ;   +15 DLBA +17 the entry (32) +49 NAME.EXT,0 (big-endian but the entry)
VP      EQU     33H             ; the variables' page
IB      EQU     7200H           ; the reader's sector (512-byte aligned)
OB      EQU     7400H           ; the writer's sector
RING    EQU     7100H           ; 128 keys
FINDB   EQU     7180H           ; the search text (upper case), 0-ended
INB     EQU     71C0H           ; a line typed at a question
NAMEZ   EQU     NOTE + 0E0H     ; NAME.EXT,0
CODEB   EQU     3400H
INMAX   EQU     40

; the variables: offsets in page VP (words big-endian)
V_GL    EQU     60H             ; the gap's low end: the cursor
V_GH    EQU     62H             ; the gap's high end
V_CLN   EQU     64H             ; the cursor's line in the part (from 0)
V_TLN   EQU     66H             ; the top row's line
V_DCOL  EQU     68H             ; the column Up / Down aim for
V_FLEN  EQU     6AH             ; the file's length on the card
V_WOFF  EQU     6CH             ; where the part starts in the file
V_WCARD EQU     6EH             ; the file's bytes the part stands for
V_LOFF  EQU     70H             ; the lines before the part
V_NWOFF EQU     72H             ; a part to read: from here ...
V_CEND  EQU     74H             ;  ... to here at most
V_RAW   EQU     76H
V_NREM  EQU     78H
V_CNT   EQU     7AH
V_ISEC  EQU     7CH             ; the reader: its sector, its place in IB
V_IPTR  EQU     7EH
V_OSEC  EQU     80H             ; the writer: its sector, its place in OB
V_OPTR  EQU     82H
V_S0    EQU     84H
V_LNEW  EQU     86H
V_LLA   EQU     88H
V_LLR   EQU     8AH
V_NLIN  EQU     8CH             ; the part's lines when read
V_CURC  EQU     8EH
V_SRCP  EQU     90H
V_CLIPN EQU     92H             ; bytes in the cut buffer
V_COL   EQU     94H             ; the cursor's column (FIXUP)
V_HS    EQU     96H             ; the cursor's line scrolled left by this
V_PHS   EQU     98H             ;  ... as it was drawn
V_TOPP  EQU     9AH             ; the top row's line, in memory
V_T1    EQU     9CH
V_T2    EQU     0A0H
V_SW    EQU     0A2H            ; a search: the part, the lines before it, the cursor it started from
V_SL    EQU     0A4H
V_SC    EQU     0A6H
V_MOD   EQU     0A8H            ; 1: changed since it was last written
V_PREVF EQU     0A9H
V_CMODE EQU     0AAH
V_TRNC  EQU     0ABH
V_SUBC  EQU     0ACH
V_CUTSQ EQU     0ADH            ; 1: the last key was ^K (another adds to the cut)
V_MSGF  EQU     0AEH            ; 1: a message on row 22
V_RDF   EQU     0AFH            ; to redraw: 1 all, 2 from DFROM on, 4 the cursor's row, 8 row OROW
V_RHEAD EQU     0B0H            ; the key ring (RTAIL follows RHEAD)
V_RTAIL EQU     0B1H
V_CROW  EQU     0B2H            ; the cursor's row (0-19)
V_PROW  EQU     0B3H
V_OROW  EQU     0B4H
V_DFROM EQU     0B5H
V_GR    EQU     0B6H            ; GOTO's row and column
V_GC    EQU     0B7H
V_T3    EQU     0B8H
V_KEY   EQU     0B9H
V_TMOD  EQU     0BAH            ; MOD as the title shows it
V_SETD  EQU     0BCH            ; 1: DCOL := COL at the next FIXUP
V_XERR  EQU     0BDH            ; why XSAVE failed: 3 the card, 4 the file is full
V_PL    EQU     0BEH            ; the typed line's length
V_PGC   EQU     0BFH
V_SMOV  EQU     0C0H            ; 1: a search moved to another part
V_ICH   EQU     0C1H
V_MYDIR EQU     0C2H            ; the document's folder
V_DOCNM EQU     0C4H            ; its 11-byte name (to 0CEH)
V_CLI   EQU     0D0H            ; the cursor's line on the screen (CLN - TLN)
V_NLV   EQU     0D1H            ; LROWS' valid lines, from the top
V_CSUB  EQU     0D2H            ; the cursor's row in its line
V_CLR   EQU     0D3H            ; the cursor's line's rows
V_PCLR  EQU     0D4H            ;  ... as the last FIXUP found them
V_SDIRTY EQU    0D5H            ; 1: the status line to be drawn
V_MKON  EQU     0D6H            ; 1: the mark is set
V_CLP   EQU     0D8H            ; the cursor's line's start (a place in memory)
V_PGAP  EQU     0DAH            ; GH - GL as the last FIXUP found it (it changed: an edit)
V_PCLN  EQU     0DCH            ; CLN as the last FIXUP found it
V_MARK  EQU     0DEH            ; the mark's place
V_VEND  EQU     0E0H
V_CSCOL EQU     V_HS            ; the cursor's column on the screen (its row's)
V_PWOFF EQU     V_PHS           ; WOFF as the last FIXUP found it
V_PCLI  EQU     V_PROW          ; CLI as the last FIXUP found it
V_DLN   EQU     0EDH            ; drawing (after NAMEZ): a line's rows
V_DEND  EQU     0EEH
V_DCNT  EQU     0EFH
V_DROWN EQU     0F0H            ; the row being drawn
V_DLI   EQU     0F1H            ; the line being drawn
V_DALL  EQU     0F2H            ; 1: to the screen's end
V_DL0   EQU     0F3H            ; a row's start, the next row's
V_DNX   EQU     0F5H

K_UP    EQU     80H             ; the keys' codes (RKEY)
K_DN    EQU     81H
K_RT    EQU     82H
K_LT    EQU     83H
K_HOME  EQU     84H
K_END   EQU     85H
K_DEL   EQU     86H
K_PGUP  EQU     87H
K_PGDN  EQU     88H
K_TOP   EQU     89H
K_BOT   EQU     8AH
K_SUP   EQU     8BH             ; Shift + an arrow
K_SDN   EQU     8CH
K_SRT   EQU     8DH
K_SLT   EQU     8EH
K_MARK  EQU     8FH             ; Alt-A
K_COPY  EQU     90H             ; Alt-6

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
        LOAD    RD, K_RDIR      ; its screen is not for a file
        LDN     RD
        LBNZ    NORD
        LOAD    RD, NOTE + V_GL ; the variables: 0
        LDI     V_VEND - V_GL
        PLO     RC
VZ:     LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        BNZ     VZ
        LOAD    RD, NAMEZ
        LDI     0
        STR     RD
        LOAD    RD, FINDB
        LDI     0
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        BNZ     ST1
        SEP     R4              ; no name: asked for
        DW      K_PIN
        DB      'File name: ',0
        LOAD    RF, INB
        LOAD    RC, INMAX
        SEP     R4
        DW      F_INPUTL
        LBDF    K_MAIN
        SEP     R4
        DW      K_PCRLF
        LOAD    RF, INB
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     K_MAIN
ST1:    LOAD    RD, NOTE + V_DOCNM
        SEP     R4              ; a path: the name, WDIR its folder
        DW      K_PARSE
        LBDF    BADNM
        LOAD    RD, NOTE + V_DOCNM
        LDI     11
        PLO     RC
ST2:    LDA     RD              ; no wildcards
        XRI     '?'
        LBZ     BADNM
        DEC     RC
        GLO     RC
        BNZ     ST2
ST3:    LOAD    RD, KS_WDIR     ; MYDIR = WDIR
        LOAD    RC, NOTE + V_MYDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, ATTN        ; ATTACH.PRG: in /BIN, else here, else in the root
        SEP     R4
        DW      FINDP
        LBDF    NOATT
        LOAD    RD, KS_LDDST    ; its code to ATTORG (the 6-byte header left out)
        LDI     HIGH(ATTORG)
        STR     RD
        INC     RD
        LDI     LOW(ATTORG)
        STR     RD
        LOAD    RD, KS_LDSKIP
        LDI     6
        STR     RD
        SEP     R4
        DW      KS_LOADF
        LBDF    KS_LDFAIL
        LOAD    RD, NOTE + V_MYDIR ; WDIR = the document's folder again
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RC, 0           ; (not ATTFND: ATTACH looks for it)
        LOAD    RD, NOTE + V_DOCNM
        SEP     R4
        DW      ATTORG
        LBDF    K_MAIN          ; it said why
        SEP     R4
        DW      KS_FATFLUSH
        SEP     R4              ; NANO.OVL (the screen's code, the keys) - once ATTACH.PRG has run
        DW      LOADOV
        LOAD    RD, NOTE        ; the note
        LDA     RD
        XRI     'L'
        LBNZ    K_MAIN
        LDN     RD
        XRI     'W'
        LBNZ    K_MAIN
        LOAD    RD, NOTE + 49   ; NAME.EXT for the title
        LOAD    RC, NAMEZ
ST4:    LDA     RD
        STR     RC
        INC     RC
        BNZ     ST4
        LOAD    RD, NOTE + 3    ; the first part
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_FLEN
        SEP     R4
        DW      PW
        DB      V_CEND
        SEP     R4
        DW      WLD
        LBDF    CFAIL
        SEP     R4
        DW      FULLD
; ==== the loop: the screen put right, a key, what it does
LOOP:   SEP     R4
        DW      FIXUP
        SEP     R4
        DW      REDRAW
        SEP     R4
        DW      IDLE
        SEP     R4
        DW      PLACE
        SEP     R4
        DW      RKEY
        SEP     R4
        DW      PB
        DB      V_KEY
        SEP     R4
        DW      GB
        DB      V_MSGF
        BZ      LP1
        SEP     R4
        DW      CLRMSG
LP1:    SEP     R4
        DW      GB
        DB      V_KEY
        PLO     RC
        XRI     0BH             ; any key but ^K: the next ^K starts a new cut
        BZ      LP2
        LDI     0
        SEP     R4
        DW      PB
        DB      V_CUTSQ
LP2:    LOAD    R8, KTAB
LP3:    LDA     R8
        BZ      LP5
        STR     R2
        GLO     RC
        XOR
        BZ      LP4
        INC     R8
        INC     R8
        BR      LP3
LP4:    LOAD    RD, LPJ + 1     ; its handler
        LDA     R8
        STR     RD
        INC     RD
        LDN     R8
        STR     RD
LPJ:    LBR     LOOP
LP5:    GLO     RC              ; a character typed
        SMI     20H
        BNF     LOOP
        GLO     RC
        SMI     7FH
        BDF     LOOP
        GLO     RC
        LBR     HCHAR
KTAB:   DB      01H
        DW      HHOME
        DB      02H
        DW      HBOT
        DB      03H
        DW      HPOS
        DB      04H
        DW      HDEL
        DB      05H
        DW      HEND
        DB      06H
        DW      HFIND
        DB      07H
        DW      HHELP
        DB      08H
        DW      HBS
        DB      09H
        DW      HTAB
        DB      0AH
        DW      HENTER
        DB      0BH
        DW      HCUTX
        DB      0CH
        DW      HREFR
        DB      0DH
        DW      HENTER
        DB      0EH
        DW      HDOWN
        DB      0FH
        DW      HSAVE
        DB      10H
        DW      HUP
        DB      13H
        DW      HSAVE
        DB      14H
        DW      HTOP
        DB      15H
        DW      HPASTE
        DB      16H
        DW      HPGDN
        DB      17H
        DW      HFIND
        DB      18H
        DW      HEXIT
        DB      19H
        DW      HPGUP
        DB      1BH
        DW      HESC
        DB      1EH
        DW      HMARK
        DB      1FH
        DW      HGOTO
        DB      7FH
        DW      HBS
        DB      K_UP
        DW      HUP
        DB      K_DN
        DW      HDOWN
        DB      K_RT
        DW      HRIGHT
        DB      K_LT
        DW      HLEFT
        DB      K_HOME
        DW      HHOME
        DB      K_END
        DW      HEND
        DB      K_DEL
        DW      HDEL
        DB      K_PGUP
        DW      HPGUP
        DB      K_PGDN
        DW      HPGDN
        DB      K_TOP
        DW      HTOP
        DB      K_BOT
        DW      HBOT
        DB      K_SUP
        DW      HSUP
        DB      K_SDN
        DW      HSDN
        DB      K_SRT
        DW      HSRT
        DB      K_SLT
        DW      HSLT
        DB      K_MARK
        DW      HMARK
        DB      K_COPY
        DW      HCOPY
        DB      0
; ---- GW: R7 = the word at VP:xx (xx the byte after the call). PW: it := R7. GB: D = the byte. PB: it := D.
GW:     LDA     R6
        PLO     RD
        LDI     VP
        PHI     RD
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R5
PW:     LDA     R6
        PLO     RD
        LDI     VP
        PHI     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        SEP     R5
GB:     LDA     R6
        PLO     RD
        LDI     VP
        PHI     RD
        LDN     RD
        SEP     R5
PB:     PHI     RF
        LDA     R6
        PLO     RD
        LDI     VP
        PHI     RD
        GHI     RF
        STR     RD
        SEP     R5
; GW8 GW9 GWB: as GW, the word in R8 / R9 / RB as well. PW8 PW9 PWB: the word := R8 / R9 / RB (and R7).
GW8:    LDA     R6
        PLO     RD
        LDI     VP
        PHI     RD
        LDA     RD
        PHI     R7
        PHI     R8
        LDN     RD
        PLO     R7
        PLO     R8
        SEP     R5
GW9:    LDA     R6
        PLO     RD
        LDI     VP
        PHI     RD
        LDA     RD
        PHI     R7
        PHI     R9
        LDN     RD
        PLO     R7
        PLO     R9
        SEP     R5
GWB:    LDA     R6
        PLO     RD
        LDI     VP
        PHI     RD
        LDA     RD
        PHI     R7
        PHI     RB
        LDN     RD
        PLO     R7
        PLO     RB
        SEP     R5
PW8:    GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
        BR      PW
PW9:    GHI     R9
        PHI     R7
        GLO     R9
        PLO     R7
        BR      PW
PWB:    GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
        BR      PW
; SETRD: RDF |= D
SETRD:  PLO     RF
        SEP     R4
        DW      GB
        DB      V_RDF
        STR     R2
        GLO     RF
        OR
        SEP     R4
        DW      PB
        DB      V_RDF
        SEP     R5
; MIN7B: R7 = the smaller of R7 and RB
MIN7B:  GLO     RB
        STR     R2
        GLO     R7
        SM
        GHI     RB
        STR     R2
        GHI     R7
        SMB
        BNF     MN9
        GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
MN9:    SEP     R5
; ADDLOF: LOFF += R7. ADDRB: R7 += RB.
ADDLOF: GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        SEP     R4
        DW      GW
        DB      V_LOFF
        SEP     R4
        DW      ADDRB
        SEP     R4
        DW      PW
        DB      V_LOFF
        SEP     R5
SUBRB:  GLO     RB              ; R7 -= RB
        STR     R2
        GLO     R7
        SM
        PLO     R7
        GHI     RB
        STR     R2
        GHI     R7
        SMB
        PHI     R7
        SEP     R5
; MOVV: the word at the first byte after the call := the word at the second (R7 = it)
MOVV:   LDA     R6
        PLO     RD
        LDI     VP
        PHI     RD
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LDA     R6
        PLO     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        SEP     R5
ADDRB:  GLO     RB
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     RB
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        SEP     R5
ENDA:
        ORG     CODEB
; ---- the start's troubles
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        LBR     K_MAIN
BADNM:  SEP     R4
        DW      K_PIN
        DB      'Not a file name.',0DH,0AH,0
        LBR     K_MAIN
NOATT:  SEP     R4
        DW      K_PIN
        DB      'ATTACH.PRG is not on the card.',0DH,0AH,0
        LBR     K_MAIN
NORD:   SEP     R4
        DW      K_PIN
        DB      'Not with > or >>.',0DH,0AH,0
        LBR     K_MAIN
CFAIL:  SEP     R4
        DW      K_PIN
        DB      'The card failed.',0DH,0AH,0
        LBR     K_MAIN
ATTN:   DB      'ATTACH  PRG'
OVLN:   DB      'NANO    OVL'
; FINDP: the file named at RD (11 bytes) in /BIN, else here, else in the root - KS_FINDN'd (DF = 1: nowhere)
FINDP:  SEP     R4
        DW      PWD_
        SEP     R4
        DW      KS_TOBIN
        BDF     FDP1
        SEP     R4
        DW      GWD_
        SEP     R4
        DW      KS_FINDN
        BNF     FDP9
FDP1:    LOAD    RD, KS_CWD
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R4
        DW      GWD_
        SEP     R4
        DW      KS_FINDN
        BNF     FDP9
        LOAD    RD, KS_WDIR
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      GWD_
        SEP     R4
        DW      KS_FINDN
FDP9:    SEP     R5
PWD_:   GHI     RD              ; (the name's place kept in T2)
        PHI     R7
        GLO     RD
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_T2
        SEP     R5
GWD_:   SEP     R4
        DW      GW
        DB      V_T2
        GHI     R7
        PHI     RD
        GLO     R7
        PLO     RD
        SEP     R5
; LOADOV: NANO.OVL into the text's room (OVLTMP), then its first 1,280 bytes to $6900 and the rest to $7700;
;   it must be this NANO's (its first word: PEND)
OVLTMP  EQU     5000H
LOADOV: LOAD    RD, OVLN
        SEP     R4
        DW      FINDP
        LBDF    NOOVL
        LOAD    RD, KS_LDDST
        LDI     HIGH(OVLTMP)
        STR     RD
        INC     RD
        LDI     LOW(OVLTMP)
        STR     RD
        LOAD    RD, KS_LDSKIP
        LDI     0
        STR     RD
        SEP     R4
        DW      KS_LOADF
        LBDF    KS_LDFAIL
        LOAD    RF, OVLTMP
        LOAD    RD, OVLHD
        LOAD    RC, 1280
        SEP     R4
        DW      COPYN
        LOAD    RD, 7700H
        LOAD    RC, OVLEND - 7700H
        SEP     R4
        DW      COPYN
        LOAD    RD, OVLHD
        LDA     RD
        XRI     HIGH(PEND)
        LBNZ    NOOVL
        LDN     RD
        XRI     LOW(PEND)
        LBNZ    NOOVL
        SEP     R5
; COPYN: RC bytes from RF to RD
COPYN:  GLO     RC
        BNZ     CPN1
        GHI     RC
        BZ      CPN9
CPN1:   LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        BR      COPYN
CPN9:   SEP     R5
NOOVL:  SEP     R4
        DW      K_PIN
        DB      'NANO.OVL is missing (or from another NANO): RECV SYSTEM again.',0DH,0AH,0
        LBR     K_MAIN
; ==== the terminal: TXB sends D; while it waits it reads the UART, so a key that comes is kept (RD RF used)
TXB:    PLO     RF
TX1:    LDI     15H             ; the status: a key in?
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        BZ      TX2
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SEP     R4
        DW      PUSHK
        BR      TX1
TX2:    LDN     R2              ; free to send?
        ANI     20H
        BZ      TX1
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
        BZ      RXP9
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        BR      PUSHK
RXP9:   SEP     R5
; PUSHK: D -> the ring (dropped when it is full). RD RF.1 used.
PUSHK:  PHI     RF
        LOAD    RD, NOTE + V_RTAIL
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
        LOAD    RD, NOTE + V_RTAIL
        LDN     R2
        STR     RD
PK9:    SEP     R5
; POPK: DF = 1 and D = the oldest key in the ring; DF = 0: none
POPK:   LOAD    RD, NOTE + V_RHEAD
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
        LOAD    RD, NOTE + V_RHEAD
        LDN     RD
        ADI     1
        ANI     7FH
        STR     RD
        GHI     RF
        SMI     0               ; DF = 1
        SEP     R5
PP9:    ADI     0               ; DF = 0
        SEP     R5
; GETK: D = the next key (waits)
GETK:   SEP     R4
        DW      POPK
        BDF     GK9
        SEP     R4
        DW      RXPOLL
        BR      GETK
GK9:    SEP     R5
; ESCW: the next key if it comes soon (a sequence's next byte): DF = 1, D. DF = 0: none (~70 ms). R9 used.
ESCW:   LOAD    R9, 150
EW1:    SEP     R4
        DW      POPK
        BDF     EW9
        SEP     R4
        DW      RXPOLL
        DEC     R9
        GLO     R9
        BNZ     EW1
        GHI     R9
        BNZ     EW1
        LDI     0
        SHR
EW9:    SEP     R5
; ---- printing
; TPIN: the text after the call (0-ended). TSTR: the text at R8. EOL: ESC [ K. SPCS: D spaces.
TPIN:   LDA     R6
        BZ      TP9
        SEP     R4
        DW      TXB
        BR      TPIN
TP9:    SEP     R5
TSTR:   LDA     R8              ; (a byte 80H + n: n spaces)
        BZ      TP9
        SMI     80H
        BDF     TS2
        ADI     80H
        SEP     R4
        DW      TXB
        BR      TSTR
TS2:    SEP     R4
        DW      SPCS
        BR      TSTR
EOL:    SEP     R4
        DW      TPIN
        DB      1BH,'[K',0
        SEP     R5
SPCS:   SEP     R4
        DW      PB
        DB      V_T3
SP1:    SEP     R4
        DW      GB
        DB      V_T3
        BZ      TP9
        SMI     1
        SEP     R4
        DW      PB
        DB      V_T3
        LDI     ' '
        SEP     R4
        DW      TXB
        LBR     SP1
; GOTOL: to row D, column 1. GOTO: to row GR, column GC.
GOTOL:  SEP     R4
        DW      PB
        DB      V_GR
        LDI     1
        SEP     R4
        DW      PB
        DB      V_GC
GOTO:   SEP     R4
        DW      TPIN
        DB      1BH,'[',0
        SEP     R4
        DW      GB
        DB      V_GR
        SEP     R4
        DW      PD8
        LDI     ';'
        SEP     R4
        DW      TXB
        SEP     R4
        DW      GB
        DB      V_GC
        SEP     R4
        DW      PD8
        LDI     'H'
        LBR     TXB
; PD8: D (0-99) in decimal
PD8:    PHI     RF
        LDI     0
        PLO     RF
P81:    GHI     RF
        SMI     10
        BNF     P82
        PHI     RF
        INC     RF
        BR      P81
P82:    GHI     RF
        SEP     R4
        DW      PB
        DB      V_T3
        GLO     RF
        BZ      P83
        ADI     '0'
        SEP     R4
        DW      TXB
P83:    SEP     R4
        DW      GB
        DB      V_T3
        ADI     '0'
        LBR     TXB
; PDEC: R7 in decimal, no leading zeros (R7 R8 R9 RB used)
PDEC:   LOAD    R8, DECT
        LDI     0
        PHI     RB
PDC1:   LDA     R8
        PHI     R9
        LDA     R8
        PLO     R9
        LDI     0
        PLO     RB
PDC2:   GLO     R9
        STR     R2
        GLO     R7
        SM
        PLO     RF
        GHI     R9
        STR     R2
        GHI     R7
        SMB
        LBNF    PDC3
        PHI     R7
        GLO     RF
        PLO     R7
        INC     RB
        LBR     PDC2
PDC3:   GLO     RB
        BNZ     PDC4
        GHI     RB
        BNZ     PDC4
        GLO     R9
        XRI     1
        BNZ     PDC5
PDC4:   LDI     1
        PHI     RB
        GLO     RB
        ADI     '0'
        SEP     R4
        DW      TXB
PDC5:   GLO     R9
        XRI     1
        LBNZ    PDC1
        SEP     R5
DECT:   DW      10000, 1000, 100, 10, 1
; ---- messages on row 24: MSGI the text after the call, in [ ]; MSGB / MSGE its start and end; CLRMSG
MSGI:   SEP     R4
        DW      MSGB
MI1:    LDA     R6
        LBZ     MSGE
        SEP     R4
        DW      TXB
        BR      MI1
MSGB:   LDI     24
        SEP     R4
        DW      GOTOL
        LDI     1
        SEP     R4
        DW      PB
        DB      V_MSGF
        SEP     R4
        DW      TPIN
        DB      1BH,'[7m[ ',0
        SEP     R5
MSGE:   SEP     R4
        DW      TPIN
        DB      ' ]',1BH,'[0m',1BH,'[K',0
        SEP     R5
CLRMSG: LDI     0               ; the status line goes there again
        SEP     R4
        DW      PB
        DB      V_MSGF
        LDI     1
        SEP     R4
        DW      PB
        DB      V_SDIRTY
        SEP     R5
; ---- the whole screen: FULLD - every line drawn again, the status line
FULLD:  SEP     R4
        DW      TPIN
        DB      1BH,'[0m',1BH,'[2J',0
        LDI     0FFH
        SEP     R4
        DW      SETRD
        LDI     0
        SEP     R4
        DW      PB
        DB      V_MSGF
        SEP     R4
        DW      PB
        DB      V_NLV
        LDI     1
        SEP     R4
        DW      PB
        DB      V_SDIRTY
        SEP     R5
; ==== the gap buffer
; CUROFF: R7 = the cursor's place (GL - TS). GLEN: R7 = the text's length (RB used).
CUROFF: SEP     R4
        DW      GW
        DB      V_GL
        GLO     R7
        SMI     LOW(TS)
        PLO     R7
        GHI     R7
        SMBI    HIGH(TS)
        PHI     R7
        SEP     R5
GLEN:   SEP     R4
        DW      GWB
        DB      V_GH
        SEP     R4
        DW      GW
        DB      V_GL
        SEP     R4
        DW      SUBRB
        GLO     R7
        ADI     LOW(TEND - TS)
        PLO     R7
        GHI     R7
        ADCI    HIGH(TEND - TS)
        PHI     R7
        SEP     R5
; MOVETO: the cursor to place R7 (at most the length); CLN follows. (R7 R8 R9 RB RC RF used)
MOVETO: GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GLEN
        GHI     R7              ; at most the length
        PHI     RB
        GLO     R7
        PLO     RB
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        SEP     R4
        DW      MIN7B
        GLO     R7              ; RB = TS + it
        ADI     LOW(TS)
        PLO     RB
        GHI     R7
        ADCI    HIGH(TS)
        PHI     RB
        SEP     R4
        DW      GW9
        DB      V_GH
        SEP     R4
        DW      GW
        DB      V_CLN
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GW8
        DB      V_GL
        GLO     R8              ; RF = RB - R8
        STR     R2
        GLO     RB
        SM
        PLO     RF
        GHI     R8
        STR     R2
        GHI     RB
        SMB
        PHI     RF
        LBNF    MTB
MTF:    LDI     15H             ; (a key in? kept)
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        BZ      MTFP
        SEP     R4
        DW      RXKEEP
MTFP:
        GLO     RF              ; on: the bytes after the gap to before it
        BNZ     MTF1
        GHI     RF
        LBZ     MTX
MTF1:   DEC     RF
        LDA     R9
        STR     R8
        INC     R8
        XRI     0AH
        LBNZ    MTF
        INC     RC
        LBR     MTF
MTB:    LDI     15H             ; (a key in? kept)
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        BZ      MTBP
        SEP     R4
        DW      RXKEEP
MTBP:
        GLO     RF              ; back (RF counts up to 0)
        BNZ     MTB1
        GHI     RF
        LBZ     MTX
MTB1:   INC     RF
        DEC     R8
        DEC     R9
        LDN     R8
        STR     R9
        XRI     0AH
        LBNZ    MTB
        DEC     RC
        LBR     MTB
MTX:    GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_GL
        SEP     R4
        DW      PW9
        DB      V_GH
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_CLN
        SEP     R5
; LSTART: R7 = the place of the cursor's line's start. LEND: R7 = the place of its end (its LF, or the length).
LSTART: SEP     R4
        DW      GW8
        DB      V_GL
LS1:    GLO     R8
        XRI     LOW(TS)
        BNZ     LS2
        GHI     R8
        XRI     HIGH(TS)
        BZ      LS3
LS2:    LDI     15H             ; (a key in? kept)
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        BZ      LS2P
        SEP     R4
        DW      RXKEEP
LS2P:
        DEC     R8
        LDN     R8
        XRI     0AH
        LBNZ    LS1
        INC     R8
LS3:    GLO     R8
        SMI     LOW(TS)
        PLO     R7
        GHI     R8
        SMBI    HIGH(TS)
        PHI     R7
        SEP     R5
LEND:   SEP     R4
        DW      GW8
        DB      V_GH
LE1:    LDI     15H             ; (a key in? kept)
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        BZ      LE1P
        SEP     R4
        DW      RXKEEP
LE1P:
        GHI     R8
        XRI     HIGH(TEND)
        BZ      LE2
        LDN     R8
        XRI     0AH
        BZ      LE2
        INC     R8
        BR      LE1
LE2:    GLO     R7              ; R8 - GH, + the cursor's place
        STR     R2
        GLO     R8
        SM
        PLO     R8
        GHI     R7
        STR     R2
        GHI     R8
        SMB
        PHI     R8
        SEP     R4
        DW      CUROFF
        GLO     R8
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     R8
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        SEP     R5
; GOCOL: the cursor from its line's start to column DCOL (or the line's end)
GOCOL:  SEP     R4
        DW      LSTART
        SEP     R4
        DW      PW
        DB      V_T2
        SEP     R4
        DW      LEND
        GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        SEP     R4
        DW      GW
        DB      V_DCOL
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GW
        DB      V_T2
        GLO     RC
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     RC
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        BDF     GC1
        SEP     R4
        DW      MIN7B
        LBR     MOVETO
GC1:    GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
        LBR     MOVETO
; LASTP: DF = 1 if this is the document's last part (no more of the file after it). WOFFZ: DF = 1: WOFF = 0.
LASTP:  SEP     R4
        DW      GWB
        DB      V_WOFF
        SEP     R4
        DW      GW
        DB      V_WCARD
        GLO     RB
        STR     R2
        GLO     R7
        ADD
        PLO     RB
        GHI     RB
        STR     R2
        GHI     R7
        ADC
        PHI     RB
        SEP     R4
        DW      GW
        DB      V_FLEN
        GLO     R7              ; DF = 0 if WOFF + WCARD < FLEN
        STR     R2
        GLO     RB
        SM
        GHI     R7
        STR     R2
        GHI     RB
        SMB
        SEP     R5
WOFFZ:  SEP     R4
        DW      GW
        DB      V_WOFF
        GLO     R7
        LBNZ    WZ1
        GHI     R7
        LBNZ    WZ1
        SMI     0
        SEP     R5
WZ1:    ADI     0
        SEP     R5
; AUTONX: the cursor at the part's end (the start of a line) with more of the file after it: the next part
AUTONX: SEP     R4
        DW      GW
        DB      V_GH
        GHI     R7
        XRI     HIGH(TEND)
        LBNZ    TP9
        SEP     R4
        DW      LASTP
        LBDF    TP9
        SEP     R4
        DW      GW
        DB      V_GL
        GLO     R7
        XRI     LOW(TS)
        LBNZ    AX1
        GHI     R7
        XRI     HIGH(TS)
        LBZ     AX2
AX1:    DEC     R7
        LDN     R7
        XRI     0AH
        LBNZ    TP9
AX2:    LDI     1
        LBR     PART
; ==== the keys
HCHAR:  SEP     R4
        DW      INS1
        LBR     LOOP
HENTER: LDI     0AH
        BR      HCHAR
HTAB:   SEP     R4              ; spaces to the next column that is a multiple of 4
        DW      GW
        DB      V_COL
        GLO     R7
        ANI     3
        SDI     4
        SEP     R4
        DW      PB
        DB      V_PGC
HT1:    LDI     ' '
        SEP     R4
        DW      INS1
        LBDF    LOOP
        SEP     R4
        DW      GB
        DB      V_PGC
        SMI     1
        SEP     R4
        DW      PB
        DB      V_PGC
        BNZ     HT1
        LBR     LOOP
; INS1: D into the text at the cursor; a full part: written back, a part from the cursor's line (DF = 1: no)
INS1:   SEP     R4
        DW      PB
        DB      V_ICH
IS0:    SEP     R4
        DW      GW8
        DB      V_GL
        SEP     R4
        DW      GW
        DB      V_GH
        GLO     R7
        STR     R2
        GLO     R8
        XOR
        BNZ     IS1
        GHI     R7
        STR     R2
        GHI     R8
        XOR
        BNZ     IS1
        SEP     R4
        DW      FULLP
        BNF     IS0
        SEP     R5
IS1:    SEP     R4
        DW      MARK            ; (from the cursor's row: DFROM)
        SEP     R4
        DW      GB
        DB      V_ICH
        STR     R8
        INC     R8
        SEP     R4
        DW      PW8
        DB      V_GL
        SEP     R4
        DW      GB
        DB      V_ICH
        XRI     0AH
        BNZ     IS2
        SEP     R4
        DW      GW
        DB      V_CLN
        INC     R7
        SEP     R4
        DW      PW
        DB      V_CLN
        LDI     2
        LSKP
IS2:    LDI     4
        SEP     R4
        DW      SETRD
        ADI     0
        SEP     R5
; MARK: changed: MOD = 1, DCOL follows, DFROM = the cursor's row
MARK:   LDI     1
        SEP     R4
        DW      PB
        DB      V_MOD
        SEP     R4
        DW      PB
        DB      V_SETD
        SEP     R4
        DW      GB
        DB      V_CLI
        SEP     R4
        DW      PB
        DB      V_DFROM
        SEP     R5
; FULLP: the part is full - written back, and a part from the cursor's line read. DF = 1: it could not be.
FULLP:  LDI     3
        LBR     PART
HBS:    SEP     R4
        DW      CUROFF
        GLO     R7
        BNZ     BS1
        GHI     R7
        BNZ     BS1
        SEP     R4              ; at the part's top: the part before, then back
        DW      WOFFZ
        LBDF    LOOP
        LDI     0
        SEP     R4
        DW      PART
        LBDF    LOOP
BS1:    SEP     R4
        DW      MARK
        SEP     R4
        DW      GW
        DB      V_GL
        DEC     R7
        SEP     R4
        DW      PW
        DB      V_GL
        LDN     R7
        XRI     0AH
        LBNZ    BS2
        SEP     R4
        DW      GW
        DB      V_CLN
        DEC     R7
        SEP     R4
        DW      PW
        DB      V_CLN
        LDI     2
        LSKP
BS2:    LDI     4
BS3:    SEP     R4
        DW      SETRD
        LBR     LOOP
HDEL:   SEP     R4
        DW      GW
        DB      V_GH
        GHI     R7
        XRI     HIGH(TEND)
        LBZ     LOOP
        SEP     R4
        DW      MARK
        SEP     R4
        DW      GW
        DB      V_GH
        LDA     R7
        PLO     RB
        SEP     R4
        DW      PW
        DB      V_GH
        GLO     RB
        XRI     0AH
        LBNZ    BS2
        LDI     2
        LBR     BS3
HLEFT:  SEP     R4
        DW      CUROFF
        GLO     R7
        LBNZ    HL1
        GHI     R7
        LBNZ    HL1
        SEP     R4
        DW      WOFFZ
        LBDF    LOOP
        LDI     0
        SEP     R4
        DW      PART
        LBDF    LOOP
        SEP     R4
        DW      CUROFF
HL1:    DEC     R7
        SEP     R4
        DW      MOVETO
HSETD:  LDI     1
        SEP     R4
        DW      PB
        DB      V_SETD
        LBR     LOOP
HRIGHT: SEP     R4
        DW      GW
        DB      V_GH
        GHI     R7
        XRI     HIGH(TEND)
        BNZ     HR1
        SEP     R4
        DW      LASTP
        LBDF    LOOP
        LDI     1
        SEP     R4
        DW      PART
        LBR     HSETD
HR1:    SEP     R4
        DW      CUROFF
        INC     R7
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      AUTONX
        LBR     HSETD
HHOME:  SEP     R4
        DW      LSTART
        SEP     R4
        DW      MOVETO
        LBR     HSETD
HEND:   SEP     R4
        DW      LEND
        SEP     R4
        DW      MOVETO
        LBR     HSETD
; LINEUP / LINEDN: the line above / below, column DCOL; across parts. DF = 1: there is none.
LINEUP: SEP     R4
        DW      GW
        DB      V_CLN
        GLO     R7
        BNZ     LU1
        GHI     R7
        BNZ     LU1
        SEP     R4
        DW      WOFFZ
        LBDF    TP9
        LDI     0
        SEP     R4
        DW      PART
        LBDF    TP9
        BR      LINEUP
LU1:    SEP     R4
        DW      LSTART
        DEC     R7
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      GOCOL
        ADI     0
        SEP     R5
LINEDN: SEP     R4
        DW      LEND
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      GW
        DB      V_GH
        GHI     R7
        XRI     HIGH(TEND)
        BNZ     LD1
        SEP     R4              ; no line end below: the next part's first line, if there is one
        DW      LASTP
        LBDF    TP9
        LDI     1
        SEP     R4
        DW      PART
        LBDF    TP9
        BR      LD2
LD1:    SEP     R4
        DW      CUROFF
        INC     R7
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      AUTONX
LD2:    SEP     R4
        DW      GOCOL
        ADI     0
        SEP     R5
HPGUP:  LDI     NROWS - 3
        SEP     R4
        DW      PB
        DB      V_PGC
PU1:    SEP     R4
        DW      LINEUP
        BDF     PGX
        SEP     R4
        DW      PGDEC
        BNZ     PU1
        BR      PGX
HPGDN:  LDI     NROWS - 3
        SEP     R4
        DW      PB
        DB      V_PGC
PD1:    SEP     R4
        DW      LINEDN
        BDF     PGX
        SEP     R4
        DW      PGDEC
        BNZ     PD1
PGX:    SEP     R4              ; the cursor kept on its line of the screen: TLN = CLN - CLI
        DW      GWB
        DB      V_CLN
        SEP     R4
        DW      GB
        DB      V_CLI
        STR     R2
        GLO     RB
        SM
        PLO     R7
        GHI     RB
        SMBI    0
        PHI     R7
        LBDF    PG2
        LOAD    R7, 0
PG2:    SEP     R4
        DW      PW
        DB      V_TLN
        LDI     1
        SEP     R4
        DW      SETRD
        LBR     LOOP
PGDEC:  SEP     R4
        DW      GB
        DB      V_PGC
        SMI     1
        SEP     R4
        DW      PB
        DB      V_PGC
        SEP     R5
HTOP:   SEP     R4
        DW      WOFFZ
        BDF     HT2
        LDI     4
        SEP     R4
        DW      PART
        LBR     HSETD
HT2:    LOAD    R7, 0
        SEP     R4
        DW      MOVETO
        LBR     HSETD
HBOT:   SEP     R4
        DW      LASTP
        LBDF    HB2
        LDI     5
        SEP     R4
        DW      PART
        LBR     HSETD
HB2:    SEP     R4
        DW      GLEN
        SEP     R4
        DW      MOVETO
        LBR     HSETD
HREFR:  SEP     R4
        DW      FULLD
        LBR     LOOP
; ^K: the cursor's line (and its line end) to the cut buffer - after the last ^K's, if that was the key before
HCUT:   SEP     R4
        DW      GB
        DB      V_CUTSQ
        BNZ     CU1
        LOAD    R7, 0
        SEP     R4
        DW      PW
        DB      V_CLIPN
CU1:    LDI     1
        SEP     R4
        DW      PB
        DB      V_CUTSQ
        SEP     R4
        DW      LSTART
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      MARK
        SEP     R4
        DW      GW8
        DB      V_GH
        SEP     R4
        DW      GW
        DB      V_CLIPN
        GLO     R7
        ADI     LOW(CLIP)
        PLO     R9
        GHI     R7
        ADCI    HIGH(CLIP)
        PHI     R9
        LDI     0
        PLO     RC              ; RC.0 = 1: the cut buffer is full
CU2:    GHI     R8
        XRI     HIGH(TEND)
        BZ      CU3
        GHI     R9
        XRI     HIGH(CLIP + CLIPMX)
        BZ      CU4
        LDA     R8
        STR     R9
        INC     R9
        XRI     0AH
        BNZ     CU2
        BR      CU3
CU4:    INC     RC
CU3:    GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_GH
        GLO     R9
        SMI     LOW(CLIP)
        PLO     R7
        GHI     R9
        SMBI    HIGH(CLIP)
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_CLIPN
        LDI     2
        SEP     R4
        DW      SETRD
        GLO     RC
        LBZ     LOOP
        SEP     R4
        DW      MSGI
        DB      'Cut buffer full',0
        LBR     LOOP
; ^U: the cut buffer into the text at the cursor
HPASTE: SEP     R4
        DW      GW
        DB      V_CLIPN
        GLO     R7
        BNZ     PA0
        GHI     R7
        LBZ     LOOP
PA0:    SEP     R4              ; room? (GH - GL >= CLIPN)
        DW      GW8
        DB      V_GL
        SEP     R4
        DW      GW
        DB      V_GH
        GLO     R8
        STR     R2
        GLO     R7
        SM
        PLO     RB
        GHI     R8
        STR     R2
        GHI     R7
        SMB
        PHI     RB
        SEP     R4
        DW      GW
        DB      V_CLIPN
        GLO     R7
        STR     R2
        GLO     RB
        SM
        GHI     R7
        STR     R2
        GHI     RB
        SMB
        LBDF    PA1
        SEP     R4
        DW      FULLP
        LBDF    LOOP
        LBR     PA0
PA1:    GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      MARK
        SEP     R4
        DW      GWB
        DB      V_CLN
        LOAD    R9, CLIP
PA2:    GLO     RC
        BNZ     PA3
        GHI     RC
        LBZ     PA4
PA3:    DEC     RC
        LDA     R9
        STR     R8
        INC     R8
        XRI     0AH
        LBNZ    PA2
        INC     RB
        LBR     PA2
PA4:    GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_GL
        SEP     R4
        DW      PWB
        DB      V_CLN
        LDI     2
        SEP     R4
        DW      SETRD
        LBR     LOOP
; ^C: where the cursor is
HPOS:   SEP     R4
        DW      MSGB
        SEP     R4
        DW      TPIN
        DB      'Line ',0
        SEP     R4
        DW      GWB
        DB      V_LOFF
        SEP     R4
        DW      GW
        DB      V_CLN
        SEP     R4
        DW      ADDRB
        INC     R7
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      TPIN
        DB      ' col ',0
        SEP     R4
        DW      GW
        DB      V_COL
        INC     R7
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      TPIN
        DB      ', bytes ',0
        SEP     R4
        DW      GW
        DB      V_WOFF
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      TPIN
        DB      '-',0
        SEP     R4
        DW      LASTP           ; (RB = its end)
        GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      TPIN
        DB      ' of ',0
        SEP     R4
        DW      GW
        DB      V_FLEN
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      MSGE
        LBR     LOOP
; ^O, ^S: write it out
HSAVE:  SEP     R4
        DW      SAVE
        LBR     LOOP
SAVE:   SEP     R4
        DW      MSGI
        DB      'Writing ...',0
        SEP     R4
        DW      XSAVE
        BDF     SVF
        LDI     0
        SEP     R4
        DW      PB
        DB      V_MOD
        SEP     R4
        DW      MSGB
        SEP     R4
        DW      TPIN
        DB      'Wrote ',0
        SEP     R4
        DW      GW
        DB      V_FLEN
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      TPIN
        DB      ' bytes to ',0
        LOAD    R8, NAMEZ
        SEP     R4
        DW      TSTR
        SEP     R4
        DW      MSGE
        ADI     0
        SEP     R5
SVF:    SEP     R4
        DW      XMSG
        SMI     0
        SEP     R5
; XMSG: why XSAVE or a part's reading failed
XMSG:   SEP     R4
        DW      GB
        DB      V_XERR
        XRI     4
        LBZ     XM4
        SEP     R4
        DW      MSGI
        DB      'The card failed',0
        SEP     R5
XM4:    SEP     R4
        DW      MSGI
        DB      'Full: 60,000 bytes at most',0
        SEP     R5
; PROMPT: the question at R8 on row 22, a line typed into INB (0-ended). DF = 1: ^C or Esc. RB used.
PROMPT: LDI     24
        SEP     R4
        DW      GOTOL
        SEP     R4
        DW      TPIN
        DB      1BH,'[7m',0
        SEP     R4
        DW      TSTR
        SEP     R4
        DW      TPIN
        DB      1BH,'[0m',1BH,'[K',0
        LDI     0
        SEP     R4
        DW      PB
        DB      V_PL
        LOAD    RD, INB
        LDI     0
        STR     RD
PR1:    SEP     R4
        DW      RKEY
        PLO     RB
        XRI     0DH
        BZ      PR9
        GLO     RB
        XRI     03H
        BZ      PRC
        GLO     RB
        XRI     1BH
        BZ      PRC
        GLO     RB
        XRI     08H
        BZ      PRB
        GLO     RB
        XRI     7FH
        BZ      PRB
        GLO     RB
        SMI     20H
        BNF     PR1
        GLO     RB
        SMI     7FH
        BDF     PR1
        SEP     R4
        DW      GB
        DB      V_PL
        XRI     INMAX
        BZ      PR1
        XRI     INMAX
        ADI     LOW(INB)
        PLO     R9
        LDI     HIGH(INB)
        PHI     R9
        GLO     RB
        STR     R9
        INC     R9
        LDI     0
        STR     R9
        SEP     R4
        DW      GB
        DB      V_PL
        ADI     1
        SEP     R4
        DW      PB
        DB      V_PL
        GLO     RB
        SEP     R4
        DW      TXB
        BR      PR1
PRB:    SEP     R4
        DW      GB
        DB      V_PL
        BZ      PR1
        SMI     1
        SEP     R4
        DW      PB
        DB      V_PL
        ADI     LOW(INB)
        PLO     R9
        LDI     HIGH(INB)
        PHI     R9
        LDI     0
        STR     R9
        SEP     R4
        DW      TPIN
        DB      08H,' ',08H,0
        BR      PR1
PR9:    SEP     R4
        DW      CLRMSG
        ADI     0
        SEP     R5
PRC:    SEP     R4
        DW      CLRMSG
        SMI     0
        SEP     R5
; ^X, Esc: leave (asked first if it changed)
HEXIT:  SEP     R4
        DW      GB
        DB      V_MOD
        LBZ     QUIT
        SEP     R4
        DW      MSGI
        DB      'Save the changes?  Y yes   N no   ^C back',0
HX1:    SEP     R4
        DW      RKEY
        ORI     20H
        XRI     'y'
        LBZ     HX3
        XRI     'y' XOR 'n'
        LBZ     QUIT
        XRI     'n' XOR 23H     ; ^C (03 | 20)
        LBZ     HX2
        XRI     23H XOR 3BH     ; Esc (1B | 20)
        LBNZ    HX1
HX2:    SEP     R4
        DW      CLRMSG
        LBR     LOOP
HX3:    SEP     R4
        DW      SAVE
        LBDF    LOOP
QUIT:   SEP     R4              ; the screen cleared; the kernel's FAT sector forgotten (the card's changed)
        DW      TPIN
        DB      1BH,'[0m',1BH,'[2J',1BH,'[H',0
        LOAD    RD, KS_FATCUR
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, KS_FATDIRTY
        LDI     0
        STR     RD
        LBR     K_MAIN
; ^G: the help screen
HHELP:  SEP     R4
        DW      TPIN
        DB      1BH,'[0m',1BH,'[2J',1BH,'[H',0
        LOAD    R8, HELPT
        SEP     R4
        DW      TSTR
        SEP     R4
        DW      RKEY
        LBR     HREFR
HELPT:  DB      ' NANO 1.1 - every key',093H,'^ is the Ctrl key;  Alt-x: Esc, then x',0DH,0AH,' ','MOVING'
        DB      0A2H,'EDITING',0DH,0AH,'  Arrows',087H,'move about',091H,'Enter',087H,'new line',0DH,0AH
        DB      '  ^P  ^N',087H,'up, down',093H,'Tab',089H,'tab',0DH,0AH,'  ^A  Home',085H,'line start'
        DB      091H,'^H  BkSp',084H,'delete left',0DH,0AH,'  ^E  End',086H,'line end',093H,'^D  Del',085H
        DB      'delete here',0DH,0AH,'  ^Y  PgUp',085H,'page up',094H,'^K',08AH,'cut the line (again:',0DH
        DB      0AH,'  ^V  PgDn',085H,'page down',09EH,'the next goes too)',0DH,0AH,'  ^T  Alt-',5CH,''
        DB      084H,'top of file',090H,'^U',08AH,'paste',0DH,0AH,'  ^B  Alt-/',084H,'end of file',0DH,0AH
        DB      '  ^_',08BH,'go to a line',08EH,'MARKING (select)',0DH,0AH,0AAH,'^^  Alt-A',083H,'mark',' '
        DB      'here (again: off)',0DH,0AH,' FILE',0A5H,'Shift+arrow mark and move',0DH,0AH,'  ^O  ^S'
        DB      087H,'write',096H,'^K',08AH,'cut marked text',0DH,0AH,'  ^X  Esc',086H,'leave',096H,'Alt-6'
        DB      087H,'copy marked text',0DH,0AH,'  ^W  ^F',087H,'find (Enter: again)',088H,'^U',08AH
        DB      'paste it',0DH,0AH,'  ^C',08BH,'where am I',091H,'Esc',089H,'drop the mark',0DH,0AH,'  '
        DB      '^L',08BH,'redraw',0DH,0AH,'  ^G',08BH,'this help',0DH,0AH,0DH,0AH,' Press a key.',0
; ^W, ^F: find (any case) from the cursor on, through the parts after this one; then from this part's top
HFIND:  LOAD    R8, FINDT
        SEP     R4
        DW      PROMPT
        LBDF    LOOP
        LOAD    R8, INB
        LDN     R8
        BZ      FN1
        LOAD    R9, FINDB       ; the new text, in upper case
FN0:    LDA     R8
        PLO     RB
        SMI     'a'
        BNF     FN0A
        SMI     26
        BDF     FN0A
        GLO     RB
        SMI     20H
        PLO     RB
FN0A:   GLO     RB
        STR     R9
        INC     R9
        BNZ     FN0
FN1:    LOAD    R8, FINDB
        LDN     R8
        LBZ     LOOP
        SEP     R4
        DW      MSGI
        DB      'Searching ...',0
        SEP     R4
        DW      MOVV
        DB      V_WOFF, V_SW
        SEP     R4
        DW      MOVV
        DB      V_LOFF, V_SL
        SEP     R4
        DW      CUROFF
        SEP     R4
        DW      PW
        DB      V_SC
        INC     R7
        SEP     R4
        DW      PW
        DB      V_T2            ; T2: the first place to look
        LDI     0
        SEP     R4
        DW      PB
        DB      V_SMOV
FN2:    SEP     R4              ; the gap to the end: the text is all at [TS, GL)
        DW      GLEN
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      GW9
        DB      V_GL
        SEP     R4
        DW      GW
        DB      V_T2
        SEP     R4
        DW      SCAN
        LBNF    FOUND
        SEP     R4              ; not in this part: the next, if there is one
        DW      LASTP
        LBDF    FN3
        LDI     1
        SEP     R4
        DW      PB
        DB      V_SMOV
        LDI     6
        SEP     R4
        DW      PART
        LBDF    LOOP
        LOAD    R7, 0
        SEP     R4
        DW      PW
        DB      V_T2
        LBR     FN2
FN3:    SEP     R4              ; the end: back to the part it started in, and from its top
        DW      GB
        DB      V_SMOV
        BZ      FN4
        SEP     R4
        DW      MOVV
        DB      V_SW, V_NWOFF
        SEP     R4
        DW      MOVV
        DB      V_FLEN, V_CEND
        LDI     0
        SEP     R4
        DW      PB
        DB      V_PREVF
        LDI     1
        SEP     R4
        DW      PB
        DB      V_CMODE
        SEP     R4
        DW      WLD
        LBDF    FNF
        SEP     R4
        DW      MOVV
        DB      V_SL, V_LOFF
        LDI     1
        SEP     R4
        DW      SETRD
FN4:    SEP     R4
        DW      GW9
        DB      V_GL
        LOAD    R7, 0
        SEP     R4
        DW      SCAN
        LBDF    FN5
        SEP     R4
        DW      GW
        DB      V_SC            ; found before where it started: wrapped
        GLO     R7
        STR     R2
        GLO     R8
        SM
        GHI     R7
        STR     R2
        GHI     R8
        SMB
        LBDF    FN6
        SEP     R4
        DW      FOUND1
        SEP     R4
        DW      MSGI
        DB      'Search wrapped',0
        LBR     LOOP
FN6:    SEP     R4              ; at the cursor itself: the only one
        DW      GW
        DB      V_SC
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      MSGI
        DB      'This is the only one',0
        LBR     LOOP
FN5:    SEP     R4
        DW      GW
        DB      V_SC
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      MSGI
        DB      'Not found',0
        LBR     LOOP
FNF:    SEP     R4
        DW      XMSG
        LBR     LOOP
FOUND:  SEP     R4
        DW      FOUND1
        SEP     R4
        DW      CLRMSG
        LBR     LOOP
FOUND1: GHI     R8              ; the cursor at it (R8 = its place)
        PHI     R7
        GLO     R8
        PLO     R7
        SEP     R4
        DW      MOVETO
        LDI     1
        SEP     R4
        DW      PB
        DB      V_SETD
        SEP     R5
FINDT:  DB      'Search: ',0
; SCAN: FINDB in [TS + R7, R9) (R9 = GL: the gap at the end): DF = 0 and R8 = its place (from TS); DF = 1: no.
;   (R7 R8 RA RB RF used)
SCAN:   GLO     R7
        ADI     LOW(TS)
        PLO     R8
        GHI     R7
        ADCI    HIGH(TS)
        PHI     R8
SCN1:   GLO     R9
        STR     R2
        GLO     R8
        SM
        GHI     R9
        STR     R2
        GHI     R8
        SMB
        LBDF    SCNO            ; R8 >= R9: not there
        GHI     R8
        PHI     RA
        GLO     R8
        PLO     RA
        LOAD    RB, FINDB
SCN2:   LDN     RB
        LBZ     SCYES
        GLO     RA              ; the text's end: no
        STR     R2
        GLO     R9
        XOR
        BNZ     SCN3
        GHI     RA
        STR     R2
        GHI     R9
        XOR
        LBZ     SCN5
SCN3:   LDA     RA
        PLO     RF
        SMI     'a'
        LBNF    SCN4
        SMI     26
        BDF     SCN4
        GLO     RF
        SMI     20H
        PLO     RF
SCN4:   LDA     RB
        STR     R2
        GLO     RF
        XOR
        LBZ     SCN2
SCN5:   INC     R8
        LBR     SCN1
SCYES:  GLO     R8
        SMI     LOW(TS)
        PLO     R8
        GHI     R8
        SMBI    HIGH(TS)
        PHI     R8
        ADI     0
        SEP     R5
SCNO:   SMI     0
        SEP     R5
; ^_: go to a line (of the document)
HGOTO:  LOAD    R8, GOTOT
        SEP     R4
        DW      PROMPT
        LBDF    LOOP
        LOAD    R8, INB         ; the number -> RB
        LOAD    RB, 0
GO1:    LDA     R8
        SMI     '0'
        LBNF    GO2
        SMI     10
        LBDF    GO2
        ADI     10
        PLO     RC
        GLO     RB              ; RB = RB x 10 + it
        SHL
        PLO     R7
        GHI     RB
        SHLC
        PHI     R7
        GLO     R7
        SHL
        PLO     RB
        GHI     R7
        SHLC
        PHI     RB
        GLO     RB
        SHL
        PLO     RB
        GHI     RB
        SHLC
        PHI     RB
        GLO     R7
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     R7
        STR     R2
        GHI     RB
        ADC
        PHI     RB
        GLO     RC
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        LBR     GO1
GO2:    GLO     RB              ; line n: n - 1 lines before it (0: the first)
        LBNZ    GO3
        GHI     RB
        LBZ     GO4
GO3:    DEC     RB
GO4:    GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_T2
GO5:    SEP     R4              ; before this part: from the first
        DW      GWB
        DB      V_LOFF
        SEP     R4
        DW      GW
        DB      V_T2
        SEP     R4
        DW      SUBRB
        BDF     GO6
        LDI     4
        SEP     R4
        DW      PART
        LBDF    LOOP
        LBR     GO5
GO6:    SEP     R4              ; R7 = lines into this part; the gap to the end: CLN = its lines
        DW      PW
        DB      V_T1
        SEP     R4
        DW      GLEN
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      GWB
        DB      V_CLN
        SEP     R4
        DW      GW
        DB      V_T1
        GLO     RB              ; past its lines: the next part, if there is one
        STR     R2
        GLO     R7
        SM
        GHI     RB
        STR     R2
        GHI     R7
        SMB
        LBNF    GO7
        SEP     R4              ; at or past its last line: the next part, or (none) its last line
        DW      LASTP
        LBDF    GO6C
        LDI     1
        SEP     R4
        DW      PART
        LBDF    LOOP
        LBR     GO5
GO6C:   SEP     R4
        DW      MOVV
        DB      V_CLN, V_T1
GO7:    SEP     R4              ; R7 lines down from the top: their LFs counted
        DW      GWB
        DB      V_T1
        LOAD    R8, TS
GO7A:   GLO     RB
        BNZ     GO7B
        GHI     RB
        BZ      GO7C
GO7B:   LDA     R8
        XRI     0AH
        BNZ     GO7B
        DEC     RB
        BR      GO7A
GO7C:   GLO     R8
        SMI     LOW(TS)
        PLO     R8
        GHI     R8
        SMBI    HIGH(TS)
        PHI     R8
        SEP     R4
        DW      FOUND1
        LBR     LOOP
GOTOT:  DB      'Go to line: ',0
; ==== the card: the attached file, a sector at a time
; RDSEC / WRSEC: the file's sector RB <-> the buffer at R9. DF = 1: failed. (R7 R8 RD RF used)
RDSEC:  SEP     R4
        DW      SLBA
        LBR     KS_IDERD
WRSEC:  SEP     R4
        DW      SLBA
        LBR     KS_IDEWR
SLBA:   SEP     R4
        DW      RXPOLL
        LOAD    RD, NOTE + 5
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      ADDRB
        LOAD    R8, 0
        GHI     R9
        PHI     RF
        GLO     R9
        PLO     RF
        SEP     R5
; IOPEN / OOPEN: R7 = a place in the file: the reader / writer starts there (its sector read)
IOPEN:  SEP     R4
        DW      OPN
        DB      V_ISEC, HIGH(IB)
        LOAD    R9, IB
        LBR     RDSEC
OOPEN:  SEP     R4
        DW      OPN
        DB      V_OSEC, HIGH(OB)
        LOAD    R9, OB
        LBR     RDSEC
; IOPENB / OOPENB: R7 = an end (> 0): the reader / writer goes down from it (OOPENB reads nothing)
IOPENB: DEC     R7
        SEP     R4
        DW      OPN
        DB      V_ISEC, HIGH(IB)
        SEP     R4
        DW      GW
        DB      V_IPTR
        INC     R7
        SEP     R4
        DW      PW
        DB      V_IPTR
        SEP     R4
        DW      GWB
        DB      V_ISEC
        LOAD    R9, IB
        LBR     RDSEC
OOPENB: DEC     R7
        SEP     R4
        DW      OPN
        DB      V_OSEC, HIGH(OB)
        SEP     R4
        DW      GW
        DB      V_OPTR
        INC     R7
        SEP     R4
        DW      PW
        DB      V_OPTR
        ADI     0
        SEP     R5
; OPN: R7 = a place: [xSEC] = its sector, [xPTR] = the buffer (page hh) + its offset in the sector; RB = the sector
OPN:    GHI     R7
        SHR
        PLO     RB
        LDI     0
        PHI     RB
        GHI     R7
        ANI     1
        STR     R2
        LDA     R6
        PLO     RD
        LDA     R6
        ADD
        PHI     R7              ; (R7.0 is the offset's low byte)
        INC     RD              ; xPTR follows xSEC
        INC     RD
        LDI     VP
        PHI     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        DEC     RD
        DEC     RD
        GLO     RB
        STR     RD
        DEC     RD
        GHI     RB
        STR     RD
        SEP     R5
; OUTB: OB out as sector OSEC; OSEC + 1, OPTR = OB
OUTB:   SEP     R4
        DW      GWB
        DB      V_OSEC
        LOAD    R9, OB
        SEP     R4
        DW      WRSEC
        LBDF    FP9
        SEP     R4
        DW      GW
        DB      V_OSEC
        INC     R7
        SEP     R4
        DW      PW
        DB      V_OSEC
        LOAD    R7, OB
        SEP     R4
        DW      PW
        DB      V_OPTR
        ADI     0
        SEP     R5
; INEXT: R8 = IPTR - the next sector read first if IB is used up. DF = 1: failed.
INEXT:  SEP     R4
        DW      GW8
        DB      V_IPTR
        XRI     LOW(IB + 512)
        LBNZ    FPOK
        GHI     R8
        XRI     HIGH(IB + 512)
        LBNZ    FPOK
        SEP     R4
        DW      GW
        DB      V_ISEC
        INC     R7
        SEP     R4
        DW      PW
        DB      V_ISEC
        GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        LOAD    R9, IB
        SEP     R4
        DW      RDSEC
        LBDF    FP9
        LOAD    R7, IB
        SEP     R4
        DW      PW
        DB      V_IPTR
        LOAD    R8, IB
        LBR     FPOK
; FPUT: CNT bytes from R8 into the writer; R8 moves on. DF = 1: failed. (R7 R9 RB RC used)
FPUT:   SEP     R4
        DW      GWB
        DB      V_CNT
        GLO     RB
        BNZ     FPU1
        GHI     RB
        LBZ     FPOK
FPU1:   SEP     R4
        DW      GW9
        DB      V_OPTR
        GLO     R9              ; R7 = OB + 512 - R9, at most CNT
        SDI     LOW(OB + 512)
        PLO     R7
        GHI     R9
        SDBI    HIGH(OB + 512)
        PHI     R7
        SEP     R4
        DW      MIN7B
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        GLO     RC              ; CNT - it
        STR     R2
        GLO     RB
        SM
        PLO     R7
        GHI     RC
        STR     R2
        GHI     RB
        SMB
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_CNT
FPP:    GLO     RC
        BNZ     FPP1
        GHI     RC
        BZ      FPD
FPP1:   DEC     RC
        LDA     R8
        STR     R9
        INC     R9
        BR      FPP
FPD:    GHI     R9
        PHI     R7
        GLO     R9
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_OPTR
        GHI     R9
        XRI     HIGH(OB + 512)
        LBNZ    FPUT
        SEP     R4
        DW      PW8
        DB      V_SRCP
        SEP     R4
        DW      OUTB
        LBDF    FP9
        SEP     R4
        DW      GW8
        DB      V_SRCP
        LBR     FPUT
FPOK:   ADI     0
FP9:    SEP     R5
; FCOPY: NREM bytes from the reader to the writer (forwards). DF = 1: failed.
FCOPY:  SEP     R4
        DW      GW
        DB      V_NREM
        GLO     R7
        LBNZ    FC1
        GHI     R7
        LBZ     FPOK
FC1:    SEP     R4
        DW      INEXT
        LBDF    FP9
        SEP     R4
        DW      RTAKE           ; RC = what IB still holds, at most NREM; NREM less; IPTR on
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_CNT
        SEP     R4
        DW      FPUT
        LBDF    FP9
        LBR     FCOPY
; RTAKE: R8 = IPTR: RC = IB + 512 - R8, at most NREM; NREM -= RC; IPTR = R8 + RC (R7 RB used)
RTAKE:  SEP     R4
        DW      GWB
        DB      V_NREM
        GLO     R8
        SDI     LOW(IB + 512)
        PLO     R7
        GHI     R8
        SDBI    HIGH(IB + 512)
        PHI     R7
        SEP     R4
        DW      MIN7B
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        GLO     RC
        STR     R2
        GLO     RB
        SM
        PLO     R7
        GHI     RC
        STR     R2
        GHI     RB
        SMB
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_NREM
        GLO     RC
        STR     R2
        GLO     R8
        ADD
        PLO     R7
        GHI     RC
        STR     R2
        GHI     R8
        ADC
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_IPTR
        SEP     R5
; OFLUSH: the writer's last sector - the bytes after OPTR as they are on the card - out
OFLUSH: SEP     R4
        DW      GW
        DB      V_OPTR
        GLO     R7
        BNZ     OF1
        GHI     R7
        XRI     HIGH(OB)
        LBZ     FPOK
OF1:    SEP     R4
        DW      GWB
        DB      V_OSEC
        LOAD    R9, IB
        SEP     R4
        DW      RDSEC
        LBDF    FP9
        SEP     R4
        DW      GW
        DB      V_OPTR
        GHI     R7
        PHI     R9
        SMI     HIGH(OB - IB)
        PHI     R8
        GLO     R7
        PLO     R9
        PLO     R8
OF2:    GHI     R9
        XRI     HIGH(OB + 512)
        LBZ     OUTB
        LDA     R8
        STR     R9
        INC     R9
        LBR     OF2
; BCOPY: NREM bytes from the reader to the writer, backwards (from their ends down). DF = 1: failed.
BCOPY:  SEP     R4
        DW      GW
        DB      V_NREM
        GLO     R7
        BNZ     BC0
        GHI     R7
        LBZ     FPOK
BC0:    SEP     R4
        DW      GW8
        DB      V_IPTR
        LBNZ    BC1
        GHI     R8
        XRI     HIGH(IB)
        LBNZ    BC1
        SEP     R4              ; IB used up: the sector before
        DW      GW
        DB      V_ISEC
        DEC     R7
        SEP     R4
        DW      PW
        DB      V_ISEC
        GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        LOAD    R9, IB
        SEP     R4
        DW      RDSEC
        LBDF    FP9
        LOAD    R8, IB + 512
BC1:    SEP     R4              ; n = the least of R8 - IB, NREM, OPTR - OB
        DW      GWB
        DB      V_NREM
        GLO     R8
        SMI     LOW(IB)
        PLO     R7
        GHI     R8
        SMBI    HIGH(IB)
        PHI     R7
        SEP     R4
        DW      MIN7B
        GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        SEP     R4
        DW      GW9
        DB      V_OPTR
        GLO     R9
        SMI     LOW(OB)
        PLO     R7
        GHI     R9
        SMBI    HIGH(OB)
        PHI     R7
        SEP     R4
        DW      MIN7B
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GW
        DB      V_NREM
        GLO     RC
        STR     R2
        GLO     R7
        SM
        PLO     R7
        GHI     RC
        STR     R2
        GHI     R7
        SMB
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_NREM
BC2:    GLO     RC
        BNZ     BC2A
        GHI     RC
        BZ      BC3
BC2A:   DEC     RC
        DEC     R8
        DEC     R9
        LDN     R8
        STR     R9
        BR      BC2
BC3:    GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_IPTR
        SEP     R4
        DW      PW9
        DB      V_OPTR
        GLO     R9
        LBNZ    BCOPY
        GHI     R9
        XRI     HIGH(OB)
        LBNZ    BCOPY
        SEP     R4              ; OB full: out as OSEC; OSEC - 1, OPTR = OB + 512
        DW      GWB
        DB      V_OSEC
        LOAD    R9, OB
        SEP     R4
        DW      WRSEC
        LBDF    FP9
        SEP     R4
        DW      GW
        DB      V_OSEC
        DEC     R7
        SEP     R4
        DW      PW
        DB      V_OSEC
        LOAD    R7, OB + 512
        SEP     R4
        DW      PW
        DB      V_OPTR
        LBR     BCOPY
; OFLUSHB: the backwards writer's last (lowest) sector - the bytes before OPTR as they are on the card - out
OFLUSHB: SEP    R4
        DW      GW
        DB      V_OPTR
        GLO     R7
        BNZ     OFB1
        GHI     R7
        XRI     HIGH(OB + 512)
        LBZ     FPOK
OFB1:   GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GWB
        DB      V_OSEC
        LOAD    R9, IB
        SEP     R4
        DW      RDSEC
        LBDF    FP9
        LOAD    R8, IB
        LOAD    R9, OB
OFB2:   GLO     R9
        STR     R2
        GLO     RC
        XOR
        LBNZ    OFB3
        GHI     R9
        STR     R2
        GHI     RC
        XOR
        LBNZ    OFB3
        SEP     R4
        DW      GWB
        DB      V_OSEC
        LOAD    R9, OB
        LBR     WRSEC
OFB3:   LDA     R8
        STR     R9
        INC     R9
        LBR     OFB2
; WB: this part back to the card in its place (LNEW = the file's new length). DF = 1: failed.
;   It grew: the rest of the file first moves up, from its end down; then the part goes out from WOFF,
;   and (it shrank or stayed) the rest follows it, read ahead of where it is written.
WB:     SEP     R4
        DW      GWB
        DB      V_WOFF
        SEP     R4
        DW      GW
        DB      V_WCARD
        SEP     R4
        DW      ADDRB
        SEP     R4
        DW      PW
        DB      V_S0
        GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        SEP     R4
        DW      GW
        DB      V_FLEN
        SEP     R4
        DW      SUBRB
        SEP     R4
        DW      PW
        DB      V_NREM          ; the rest's length
        SEP     R4
        DW      GLEN
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GW
        DB      V_WCARD
        GLO     RC              ; WCARD < the length: it grew
        STR     R2
        GLO     R7
        SM
        GHI     RC
        STR     R2
        GHI     R7
        SMB
        LBDF    WBF
        SEP     R4
        DW      GW
        DB      V_NREM
        GLO     R7
        BNZ     WBG
        GHI     R7
        LBZ     WBF
WBG:    SEP     R4
        DW      GW
        DB      V_FLEN
        SEP     R4
        DW      IOPENB
        LBDF    FP9
        SEP     R4
        DW      GW
        DB      V_LNEW
        SEP     R4
        DW      OOPENB
        SEP     R4
        DW      BCOPY
        LBDF    FP9
        SEP     R4
        DW      OFLUSHB
        LBDF    FP9
        LOAD    R7, 0
        SEP     R4
        DW      PW
        DB      V_NREM
WBF:    SEP     R4
        DW      GW
        DB      V_WOFF
        SEP     R4
        DW      OOPEN
        LBDF    FP9
        SEP     R4
        DW      CUROFF          ; [TS, GL)
        SEP     R4
        DW      PW
        DB      V_CNT
        LOAD    R8, TS
        SEP     R4
        DW      FPUT
        LBDF    FP9
        SEP     R4              ; [GH, TEND)
        DW      GW8
        DB      V_GH
        SDI     LOW(TEND)
        PLO     R7
        GHI     R8
        SDBI    HIGH(TEND)
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_CNT
        SEP     R4
        DW      FPUT
        LBDF    FP9
        SEP     R4
        DW      GW
        DB      V_NREM
        GLO     R7
        BNZ     WBR
        GHI     R7
        LBZ     WBE
WBR:    SEP     R4
        DW      GW
        DB      V_S0
        SEP     R4
        DW      IOPEN
        LBDF    FP9
        SEP     R4
        DW      FCOPY
        LBDF    FP9
WBE:    SEP     R4
        DW      OFLUSH
        LBDF    FP9
        SEP     R4
        DW      MOVV
        DB      V_LNEW, V_FLEN
        SEP     R4
        DW      GLEN
        SEP     R4
        DW      PW
        DB      V_WCARD
        LBR     FPOK
; XSAVE: the document written: this part in its place (the rest moved on the card as it grew or shrank),
;   the FAT chain, the entry. DF = 1: no (XERR: 3 the card failed, 4 the file is full).
XSAVE:  SEP     R4              ; LNEW = FLEN - WCARD + the length
        DW      GLEN
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        SEP     R4
        DW      GWB
        DB      V_WCARD
        SEP     R4
        DW      GW
        DB      V_FLEN
        SEP     R4
        DW      SUBRB
        GLO     RC
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     RC
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        LBDF    XFULL
        GHI     R7
        SMI     0FEH
        LBDF    XFULL
        SEP     R4
        DW      PW
        DB      V_LNEW
        GLO     R7              ; its sectors: (L + 511) / 512 <= NSECT
        ADI     0FFH
        GHI     R7
        ADCI    01H
        SHR
        STR     R2
        LOAD    RD, NOTE + 7
        LDN     RD
        SM
        LBNF    XFULL
        LOAD    RD, NOTE + 3    ; the note's L, the entry's size (little-endian)
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        LOAD    RD, NOTE + 17 + 28
        GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        GLO     R7              ; k = its clusters: the sectors / SPC, rounded up -> NOTE + 2
        ADI     0FFH
        GHI     R7
        ADCI    01H
        SHR
        PLO     R9
        LDI     0
        PLO     R8
        LOAD    RD, NOTE + 8
        LDN     RD
        STR     R2
XK1:    GLO     R9
        BZ      XK2
        INC     R8
        GLO     R9
        SM
        PLO     R9
        BDF     XK1
        LDI     0
        PLO     R9
        BR      XK1
XK2:    LOAD    RD, NOTE + 2
        GLO     R8
        STR     RD
        PLO     RB
        LOAD    RD, NOTE + 9    ; the entry's first cluster: C1 (none: 0)
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LOAD    RD, NOTE + 17 + 26
        GLO     RB
        BNZ     XK3
        PLO     R7
        PHI     R7
XK3:    GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        LDI     3
        SEP     R4
        DW      PB
        DB      V_XERR
        SEP     R4              ; the data
        DW      WB
        LBDF    FP9
        LOAD    RD, NOTE + 11   ; the FAT sector, in each copy (FL2 = 0: only one)
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      FATW
        LBDF    FP9
        LOAD    RD, NOTE + 13
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        GLO     R7
        BNZ     XF7
        GHI     R7
        BZ      XE
XF7:    SEP     R4
        DW      FATW
        LBDF    FP9
XE:     SEP     R4              ; the directory sector: the entry, then 0s
        DW      OBZERO
        LOAD    R8, NOTE + 17
        LOAD    R9, OB
        LDI     32
        PLO     RC
XE1:    LDA     R8
        STR     R9
        INC     R9
        DEC     RC
        GLO     RC
        BNZ     XE1
        LOAD    RD, NOTE + 15
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LBR     OBWR
XFULL:  LDI     4
        SEP     R4
        DW      PB
        DB      V_XERR
        LBR     SCNO
; OBZERO: OB = 0s. OBWR: OB out to the card's sector R7 (not the file's: the FAT's, the folder's).
OBZERO: LOAD    R9, OB
        LDI     0
OZ1:    STR     R9
        INC     R9
        GHI     R9
        XRI     HIGH(OB + 512)
        LBZ     TP9
        LDI     0
        BR      OZ1
OBWR:   SEP     R4
        DW      RXPOLL
        LOAD    R8, 0
        LOAD    RF, OB
        LBR     KS_IDEWR
; FATW: the FAT sector R7 := C1 -> C1+1 -> ... -> $FFFF over k entries (NOTE + 2), 0 for the rest
FATW:   SEP     R4
        DW      PW
        DB      V_T1
        LOAD    RD, NOTE + 9
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        INC     R8
        LOAD    RD, NOTE + 2
        LDN     RD
        PLO     RC
        LOAD    R9, OB
        LDI     0
        PLO     RB
FW2:    GLO     RC
        BZ      FW4
        DEC     RC
        GLO     RC
        BZ      FW3
        GLO     R8
        STR     R9
        INC     R9
        GHI     R8
        BR      FW6
FW3:    LDI     0FFH
        STR     R9
        INC     R9
        BR      FW6
FW4:    LDI     0
        STR     R9
        INC     R9
FW6:    STR     R9
        INC     R9
        INC     R8
        DEC     RB
        GLO     RB
        BNZ     FW2
        SEP     R4
        DW      GW
        DB      V_T1
        LBR     OBWR
; ==== parts
; PART: D = 0 the part before (cursor at its end), 1 the part after (cursor at its top), 3 a part from the
;   cursor's line (the cursor kept: the text was full), 4 the first, 5 the last (cursor at its end), 6 the part
;   after with the gap at its end (the search). The document is written first when it changed (always for 3).
;   DF = 1: not done (nothing there, or it failed: it said why).
PART:   SEP     R4
        DW      PB
        DB      V_SUBC
        XRI     3
        LBZ     PTSV
        XRI     3
        BZ      PT0
        XRI     4
        BZ      PT0
        SEP     R4              ; 1, 5, 6: something after it?
        DW      LASTP
        LBDF    FP9
        BR      PTCK
PT0:    SEP     R4              ; 0, 4: something before it?
        DW      WOFFZ
        LBDF    FP9
PTCK:   SEP     R4
        DW      GB
        DB      V_MOD
        BZ      PTNS
PTSV:   SEP     R4
        DW      MSGI
        DB      'Writing ...',0
        SEP     R4
        DW      XSAVE
        LBDF    PTF
        LDI     0
        SEP     R4
        DW      PB
        DB      V_MOD
PTNS:   LDI     0
        SEP     R4
        DW      PB
        DB      V_PREVF
        SEP     R4
        DW      PB
        DB      V_CMODE
        SEP     R4
        DW      MOVV
        DB      V_FLEN, V_CEND
        SEP     R4
        DW      GB
        DB      V_SUBC
        LBZ     PS0
        XRI     1
        LBZ     PS1
        XRI     1 XOR 3
        LBZ     PS3
        XRI     3 XOR 4
        LBZ     PS4
        XRI     4 XOR 6
        LBZ     PS1
        SEP     R4              ; 5: the last - from FLEN - RLIM (or 0), the cursor at its end
        DW      GW
        DB      V_FLEN
        BR      PSB
PS0:    SEP     R4              ; 0: the one before, ending at WOFF
        DW      MOVV
        DB      V_WOFF, V_CEND
PSB:    GLO     R7
        SMI     LOW(RLIM)
        PLO     R7
        GHI     R7
        SMBI    HIGH(RLIM)
        PHI     R7
        BDF     PSB2
        LOAD    R7, 0
PSB2:   SEP     R4
        DW      PW
        DB      V_NWOFF
        LDI     1
        SEP     R4
        DW      PB
        DB      V_PREVF
        SEP     R4
        DW      PB
        DB      V_CMODE
        LBR     PTLD
PS1:    SEP     R4              ; 1, 6: the next - LOFF + this part's lines (the gap to its end: CLN)
        DW      GLEN
        SEP     R4
        DW      MOVETO
        SEP     R4
        DW      GW
        DB      V_CLN
        SEP     R4
        DW      ADDLOF
        SEP     R4
        DW      LASTP           ; (RB = WOFF + WCARD)
        SEP     R4
        DW      PWB
        DB      V_NWOFF
        SEP     R4
        DW      GB
        DB      V_SUBC
        XRI     6
        LBNZ    PTLD
        LDI     1
        SEP     R4
        DW      PB
        DB      V_CMODE
        LBR     PTLD
PS3:    SEP     R4              ; 3: LOFF + CLN; CURC = the column; from the cursor's line's start
        DW      GW
        DB      V_CLN
        SEP     R4
        DW      ADDLOF
        SEP     R4
        DW      LSTART
        SEP     R4
        DW      PW
        DB      V_T2
        GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        SEP     R4
        DW      CUROFF
        SEP     R4
        DW      SUBRB
        SEP     R4
        DW      PW
        DB      V_CURC
        SEP     R4
        DW      GWB
        DB      V_WOFF
        SEP     R4
        DW      GW
        DB      V_T2
        SEP     R4
        DW      ADDRB
        SEP     R4
        DW      PW
        DB      V_NWOFF
        LDI     2
        SEP     R4
        DW      PB
        DB      V_CMODE
        LBR     PTLD
PS4:    LOAD    R7, 0           ; 4: the first
        SEP     R4
        DW      PW
        DB      V_NWOFF
        SEP     R4
        DW      PW
        DB      V_LOFF
PTLD:   SEP     R4
        DW      WLD
        LBDF    PTF
        SEP     R4
        DW      GB
        DB      V_SUBC
        LBNZ    PT5
        SEP     R4              ; 0: LOFF - its lines
        DW      GWB
        DB      V_NLIN
        SEP     R4
        DW      GW
        DB      V_LOFF
        SEP     R4
        DW      SUBRB
        SEP     R4
        DW      PW
        DB      V_LOFF
PT5:    SEP     R4
        DW      GB
        DB      V_SUBC
        XRI     5
        BNZ     PTOK
        SEP     R4
        DW      CNTLF
        LBDF    PTF
PTOK:   LDI     1
        SEP     R4
        DW      SETRD
        SEP     R4
        DW      CLRMSG
        LBR     FPOK
PTF:    SEP     R4
        DW      XMSG
        LBR     SCNO
; WLD: a part from NWOFF (the file's bytes up to CEND, at most RLIM of them) into the text. PREVF = 1: it starts
;   after the first line end (unless it is the file's start, or there is none). Cut after its last line end
;   when CEND was not reached. Then the gap at its end, CLN = NLIN = its lines, and the cursor by CMODE:
;   0 its top, 1 its end, 2 column CURC of its first line. WOFF, WCARD set. DF = 1: failed (XERR = 3).
WLD:    LDI     3
        SEP     R4
        DW      PB
        DB      V_XERR
        SEP     R4
        DW      GWB
        DB      V_NWOFF
        SEP     R4
        DW      GW
        DB      V_CEND
        SEP     R4
        DW      SUBRB
        LOAD    RB, RLIM
        SEP     R4
        DW      MIN7B
        SEP     R4
        DW      PW
        DB      V_RAW
        SEP     R4
        DW      PW
        DB      V_NREM
        LOAD    R7, TS
        SEP     R4
        DW      PW
        DB      V_SRCP
        SEP     R4
        DW      GW
        DB      V_NREM
        GLO     R7
        LBNZ    W2
        GHI     R7
        LBZ     W5
W2:     SEP     R4
        DW      GW
        DB      V_NWOFF
        SEP     R4
        DW      IOPEN
        LBDF    FP9
W3:     SEP     R4
        DW      GW
        DB      V_NREM
        GLO     R7
        BNZ     W3A
        GHI     R7
        LBZ     W5
W3A:    SEP     R4
        DW      INEXT
        LBDF    FP9
        SEP     R4
        DW      RTAKE
        SEP     R4
        DW      GW9
        DB      V_SRCP
W4:     GLO     RC
        BNZ     W4A
        GHI     RC
        BZ      W4E
W4A:    DEC     RC
        LDA     R8
        STR     R9
        INC     R9
        BR      W4
W4E:    GHI     R9
        PHI     R7
        GLO     R9
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_SRCP
        BR      W3
W5:     SEP     R4
        DW      GB
        DB      V_PREVF
        LBZ     W8
        SEP     R4
        DW      GW
        DB      V_NWOFF
        GLO     R7
        BNZ     W5A
        GHI     R7
        LBZ     W8
W5A:    LOAD    R8, TS
        SEP     R4
        DW      GWB
        DB      V_RAW
W6:     GLO     RB
        BNZ     W6A
        GHI     RB
        LBZ     W8
W6A:    DEC     RB
        LDA     R8
        XRI     0AH
        BNZ     W6
        GLO     RB              ; (a line end last: all kept)
        BNZ     W6B
        GHI     RB
        LBZ     W8
W6B:    GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_RAW
        GLO     R8              ; NWOFF + what was stepped over
        SMI     LOW(TS)
        PLO     R7
        GHI     R8
        SMBI    HIGH(TS)
        PHI     R7
        GHI     RB
        PHI     RC
        GLO     RB
        PLO     RC
        GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        SEP     R4
        DW      GW
        DB      V_NWOFF
        SEP     R4
        DW      ADDRB
        SEP     R4
        DW      PW
        DB      V_NWOFF
        LOAD    R9, TS
W7:     GLO     RC
        BNZ     W7A
        GHI     RC
        LBZ     W8
W7A:    DEC     RC
        LDA     R8
        STR     R9
        INC     R9
        BR      W7
W8:     SEP     R4              ; TRNC = NWOFF + RAW < CEND
        DW      GWB
        DB      V_NWOFF
        SEP     R4
        DW      GW
        DB      V_RAW
        SEP     R4
        DW      ADDRB
        GHI     R7
        PHI     RB
        GLO     R7
        PLO     RB
        SEP     R4
        DW      GW
        DB      V_CEND
        GLO     R7
        STR     R2
        GLO     RB
        SM
        GHI     R7
        STR     R2
        GHI     RB
        SMB
        LDI     0
        BDF     W8A
        LDI     1
W8A:    SEP     R4
        DW      PB
        DB      V_TRNC
        SEP     R4
        DW      GWB
        DB      V_RAW
        SEP     R4
        DW      CONV
        SEP     R4
        DW      GB
        DB      V_TRNC
        LBZ     WA
        SEP     R4
        DW      GW
        DB      V_LLA
        GLO     R7
        LBNZ    W9
        GHI     R7
        LBZ     WA
W9:     GLO     R7              ; cut after the last line end
        SMI     LOW(TS)
        PLO     R7
        GHI     R7
        SMBI    HIGH(TS)
        PHI     R7
        SEP     R4
        DW      PW
        DB      V_RAW
        SEP     R4
        DW      GW9
        DB      V_LLR
WA:     SEP     R4
        DW      MOVV
        DB      V_NWOFF, V_WOFF
        SEP     R4
        DW      MOVV
        DB      V_RAW, V_WCARD
        SEP     R4
        DW      PW9
        DB      V_GL
        LOAD    R7, TEND
        SEP     R4
        DW      PW
        DB      V_GH
        LOAD    R8, TS          ; its lines
        LOAD    RB, 0
WB1:    GLO     R8
        STR     R2
        GLO     R9
        XOR
        BNZ     WB2
        GHI     R8
        STR     R2
        GHI     R9
        XOR
        BZ      WB3
WB2:    LDA     R8
        XRI     0AH
        BNZ     WB1
        INC     RB
        BR      WB1
WB3:    GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_CLN
        SEP     R4
        DW      PW
        DB      V_NLIN
        SEP     R4
        DW      GB
        DB      V_CMODE
        BZ      WC0
        XRI     1
        LBZ     FPOK
        SEP     R4
        DW      GW
        DB      V_CURC
        BR      WC2
WC0:    LOAD    R7, 0
WC2:    SEP     R4
        DW      MOVETO
        LBR     FPOK
; CONV: the RB bytes at TS, in place: CR LF, a lone CR, a lone LF: one LF. R9 = their end. LLA = where the
;   source was after its last LF (0: none), LLR = the text's end then.
CONV:   LOAD    R7, 0
        SEP     R4
        DW      PW
        DB      V_LLA
        LOAD    R8, TS
        LOAD    R9, TS
        LDI     0
        PHI     RC              ; RC.1 = 1: the last was a CR
CV1:    GLO     RB
        BNZ     CV2
        GHI     RB
        LBZ     TP9
CV2:    DEC     RB
        LDA     R8
        PLO     RC
        XRI     0DH
        BZ      CVCR
        GLO     RC
        XRI     0AH
        BNZ     CVO
        GHI     RC              ; an LF: after a CR, already written
        BZ      CVLF
        LDI     0
        PHI     RC
        BR      CVL
CVLF:   LDI     0AH
        STR     R9
        INC     R9
CVL:    GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_LLA
        SEP     R4
        DW      PW9
        DB      V_LLR
        LBR     CV1
CVCR:   LDI     1
        PHI     RC
        LDI     0AH
        STR     R9
        INC     R9
        LBR     CV1
CVO:    LDI     0
        PHI     RC
        GLO     RC
        STR     R9
        INC     R9
        LBR     CV1
; CNTLF: LOFF = the line ends (LF) in the file before WOFF. DF = 1: failed.
CNTLF:  LOAD    R7, 0
        SEP     R4
        DW      PW
        DB      V_LOFF
        SEP     R4
        DW      MOVV
        DB      V_WOFF, V_NREM
        GLO     R7
        BNZ     CL0
        GHI     R7
        LBZ     FPOK
CL0:    LOAD    R7, 0
        SEP     R4
        DW      IOPEN
        LBDF    FP9
CL1:    SEP     R4
        DW      GW
        DB      V_NREM
        GLO     R7
        BNZ     CL1A
        GHI     R7
        LBZ     FPOK
CL1A:   SEP     R4
        DW      INEXT
        LBDF    FP9
        SEP     R4
        DW      RTAKE
        SEP     R4
        DW      GWB
        DB      V_LOFF
CL2:    GLO     RC
        BNZ     CL2A
        GHI     RC
        BZ      CL3
CL2A:   DEC     RC
        LDA     R8
        XRI     0AH
        BNZ     CL2
        INC     RB
        BR      CL2
CL3:    GHI     RB
        PHI     R7
        GLO     RB
        PLO     R7
        SEP     R4
        DW      PW
        DB      V_LOFF
        LBR     CL1
        INCL    "enmain.inc"
PEND:
        INCL    "enovla.inc"
        INCL    "enovlb.inc"
        END
