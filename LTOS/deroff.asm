; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; deroff.asm - DEROFF.PRG: DEROFF [-w] name - the text of an EROFF / nroff file, its formatting taken out (Unix deroff).
;   A line starting with . or ' is a request: left out - but the text EROFF prints from it is kept: .sh text,
;   .nh L text (the level dropped), .ip TAG (the tag; "words" in quotes), .B / .I / .R text. A .TS ... .TE
;   (table) or .EQ ... .EN (equation) block is left out whole.
;   In the text: \fX \f(XX (fonts), \sN \s+N \s-N \s(NN (sizes), \(xx (special characters), \*x \*(xx (strings),
;   \nx \n(xx (numbers) are left out; \" ends the line (a comment); \& \% \c \| \^ are dropped; \e and \\ are \,
;   \- is -, "\ " and \0 a space; any other \x is x.
;   -w: the words instead, one to a line: runs of letters, digits, & and ' (with no ' at either end) that hold
;   two letters or more (as Unix deroff -w); 63 characters of a word at most.
; CR dropped, LF ends a line; a line over 1000 characters goes as 1000-character pieces. verify_deroff.py holds
; the same rules in Python and checks one against the other.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
LMAX    EQU     1000
WMAX    EQU     63

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        DB      'VER:1.0',0
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        SEP     R4
        DW      KS_MNTCHK
        LOAD    RD, WORDS       ; WORDS SKIP LEN WLEN = 0
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
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USAGE
        XRI     '-'
        LBNZ    ONAME
        INC     RF              ; -w
        LDA     RF
        ANI     0DFH
        XRI     'W'
        LBNZ    USAGE
        LDN     RF
        LBZ     USAGE
        XRI     ' '
        LBNZ    USAGE
        LOAD    RD, WORDS
        LDI     1
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USAGE
        XRI     '-'
        LBZ     USAGE
ONAME:  SEP     R4
        DW      KS_NAMEARG      ; (not there, a folder ...: the kernel says so, back to the prompt)
        SEP     R4
        DW      KS_FOPEN
RD1:    SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    RDEND
        LOAD    RF, KS_DATBUF
RD2:    GHI     RC
        LBNZ    RD3
        GLO     RC
        LBZ     RD1
RD3:    DEC     RC
        LDA     RF
        PLO     RE
        XRI     0DH
        LBZ     RD2             ; CR: dropped
        XRI     07H             ; (0DH XOR 0AH)
        LBZ     RDLF
        LOAD    RD, CH          ; a character: kept in CH (LINE uses the registers and the stack)
        GLO     RE
        STR     RD
        LOAD    RD, LEN         ; into LBUF - a full one goes first, as a piece
        LDA     RD
        XRI     HIGH(LMAX)
        LBNZ    RD4
        LDN     RD
        XRI     LOW(LMAX)
        LBNZ    RD4
        SEP     R4
        DW      LINE            ; (keeps RF and RC)
RD4:    LOAD    RD, LEN         ; LBUF[LEN] = it, LEN + 1
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        INC     RA
        GLO     RA
        STR     RD
        DEC     RD
        GHI     RA
        STR     RD
        DEC     RA
        GLO     RA
        ADI     LOW(LBUF)
        PLO     RA
        GHI     RA
        ADCI    HIGH(LBUF)
        PHI     RA
        LOAD    RD, CH
        LDN     RD
        STR     RA
        LBR     RD2
RDLF:   SEP     R4              ; LF: the line
        DW      LINE
        LBR     RD2
RDEND:  LOAD    RD, LEN         ; a last line with no LF
        LDA     RD
        LBNZ    RE1
        LDN     RD
        LBZ     RE9
RE1:    SEP     R4
        DW      LINE
RE9:    SEP     R5

; ---- LINE: LBUF[0 .. LEN) as a line (then LEN = 0). Keeps RF and RC (the file's place) in memory.
LINE:   LOAD    RD, SAVRF
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, LEN         ; LBUF[LEN] = 0, LEN = 0
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDI     0
        STR     RD
        DEC     RD
        STR     RD
        GLO     RA
        ADI     LOW(LBUF)
        PLO     RA
        GHI     RA
        ADCI    HIGH(LBUF)
        PHI     RA
        LDI     0
        STR     RA
        SEP     R4
        DW      DOLINE
        LOAD    RD, SAVRF
        LDA     RD
        PHI     RF
        LDA     RD
        PLO     RF
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R5

; DOLINE: the line at LBUF (0-ended)
DOLINE: LOAD    RD, SKIP        ; in a table or equation: only its end is looked for
        LDN     RD
        LBZ     DL1
        LOAD    RF, LBUF
        LDA     RF
        XRI     '.'
        LBNZ    DL0
        LDA     RF
        XRI     'T'
        LBNZ    DLEQ
        LDN     RF
        XRI     'E'
        LBNZ    DL0
        LDN     RD
        XRI     1
        LBNZ    DL0
        LBR     DLOFF
DLEQ:   XRI     11H             ; ('T' XOR 'E')
        LBNZ    DL0
        LDN     RF
        XRI     'N'
        LBNZ    DL0
        LDN     RD
        XRI     2
        LBNZ    DL0
DLOFF:  LDI     0
        STR     RD
DL0:    SEP     R5
DL1:    LOAD    RF, LBUF
        LDN     RF
        XRI     '.'
        LBZ     DLREQ
        XRI     09H             ; ('.' XOR 27H: ')
        LBZ     DLREQ
        LBR     TEXT
DLREQ:  INC     RF              ; a request: its name - 1 or 2 characters, then a space, a TAB or the end
        LDA     RF
        PHI     RB              ; RB.1 = the first
        LBZ     DL0
        LDN     RF
        PLO     RB              ; RB.0 = the second (0 if the name is one character)
        SEP     R4
        DW      ENDCH
        LBNZ    DLR2
        LDI     0               ; one character: B I R
        PLO     RB
        GHI     RB
        XRI     'B'
        LBZ     DLTXT
        GHI     RB
        XRI     'I'
        LBZ     DLTXT
        GHI     RB
        XRI     'R'
        LBZ     DLTXT
        SEP     R5
DLR2:   INC     RF              ; two: then the end
        SEP     R4
        DW      ENDCH
        LBNZ    DL0
        LOAD    RD, REQS        ; which? (TS EQ sh nh ip)
        LDI     0
        PLO     RA
DLR3:   LDA     RD
        LBZ     DL0
        STR     R2
        GHI     RB
        XOR
        LBNZ    DLR4
        LDN     RD
        STR     R2
        GLO     RB
        XOR
        LBZ     DLR5
DLR4:   INC     RD
        INC     RA
        LBR     DLR3
DLR5:   GLO     RA
        LBZ     DLTS
        XRI     1
        LBZ     DLEQS
        XRI     3               ; (1 XOR 2)
        LBZ     DLTXT           ; sh: its text
        XRI     1               ; (2 XOR 3)
        LBZ     DLNH
        SEP     R4              ; ip: the tag - a word, or "words"
        DW      SKIPSP
        LDN     RF
        XRI     '"'
        LBNZ    DLIP2
        INC     RF
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
DLIP1:  LDN     RD              ; to the closing quote (or the end)
        LBZ     TEXTN
        XRI     '"'
        LBZ     DLIP3
        INC     RD
        LBR     DLIP1
DLIP2:  GHI     RF              ; to the word's end
        PHI     RD
        GLO     RF
        PLO     RD
DLIP4:  LDN     RD
        LBZ     TEXTN
        XRI     ' '
        LBZ     DLIP3
        XRI     29H             ; (' ' XOR TAB)
        LBZ     DLIP3
        INC     RD
        LBR     DLIP4
DLIP3:  LDI     0
        STR     RD
        LBR     TEXTN
DLTS:   LDI     1
        LBR     DLSK
DLEQS:  LDI     2
DLSK:   STR     R2
        LOAD    RD, SKIP
        LDN     R2
        STR     RD
        SEP     R5
DLNH:   SEP     R4              ; nh L text: the level dropped
        DW      SKIPSP
DLNH1:  LDN     RF
        LBZ     DL0
        XRI     ' '
        LBZ     DLTXT
        XRI     29H             ; (' ' XOR TAB)
        LBZ     DLTXT
        INC     RF
        LBR     DLNH1
DLTXT:  SEP     R4              ; the text after it (none: no line)
        DW      SKIPSP
TEXTN:  LDN     RF
        LBZ     DL0
; ---- TEXT: RF -> a line's text: its escapes worked out, then a new line (-w: its words)
TEXT:   LDA     RF
        LBZ     TEND
        XRI     5CH
        LBZ     TESC
        XRI     5CH
TOUT:   SEP     R4
        DW      EMIT
        LBR     TEXT
TESC:   LDA     RF
        LBZ     TEND            ; (a \ at the end: dropped)
        PLO     RE
        XRI     'f'
        LBZ     TSKF
        GLO     RE
        XRI     '*'
        LBZ     TSKF
        GLO     RE
        XRI     'n'
        LBZ     TSKF
        GLO     RE
        XRI     's'
        LBZ     TSKS
        GLO     RE
        XRI     '('
        LBZ     TSK2
        GLO     RE
        XRI     '"'
        LBZ     TEND
        GLO     RE
        XRI     'e'
        LBZ     TBSL
        GLO     RE
        XRI     5CH
        LBZ     TBSL
        GLO     RE
        XRI     ' '
        LBZ     TSP
        GLO     RE
        XRI     '0'
        LBZ     TSP
        LOAD    RD, DROPS       ; & % c | ^: nothing
TD1:    LDA     RD
        LBZ     TD2
        STR     R2
        GLO     RE
        XOR
        LBZ     TEXT
        LBR     TD1
TD2:    GLO     RE              ; - and the rest: itself
        LBR     TOUT
TBSL:   LDI     5CH
        LBR     TOUT
TSP:    LDI     ' '
        LBR     TOUT
TSKF:   LDN     RF              ; \fX \*x \nx, or with ( and two
        XRI     '('
        LBZ     TSK3
TSK1:   LDI     1
        LBR     TSKN
TSK2:   LDI     2
        LBR     TSKN
TSK3:   LDI     3
TSKN:   PLO     RE              ; past RE.0 characters (not past the end)
TSK4:   LDN     RF
        LBZ     TEXT
        INC     RF
        DEC     RE
        GLO     RE
        LBNZ    TSK4
        LBR     TEXT
TSKS:   LDN     RF              ; \s: a + or -, then (NN or a digit
        XRI     '+'
        LBZ     TSS1
        LDN     RF
        XRI     '-'
        LBNZ    TSS2
TSS1:   INC     RF
TSS2:   LDN     RF
        XRI     '('
        LBZ     TSK3
        LDN     RF
        SMI     '0'
        LBNF    TEXT
        SMI     10
        LBDF    TEXT
        LBR     TSK1
TEND:   LOAD    RD, WORDS
        LDN     RD
        LBNZ    TEW
        SEP     R4
        DW      K_PCRLF
        SEP     R5
TEW:    SEP     R4              ; -w: the last word
        DW      WFLUSH
        SEP     R5

; EMIT: D = a character of the text: out, or (-w) into the word. Keeps RF.
EMIT:   PLO     RE
        LOAD    RD, WORDS
        LDN     RD
        LBNZ    EM1
        GLO     RE
        SEP     R4
        DW      F_TYPE
        SEP     R5
EM1:    GLO     RE              ; a word's character? letters, digits, & '
        XRI     '&'
        LBZ     EM3
        GLO     RE
        XRI     27H
        LBZ     EM3
        GLO     RE
        SMI     '0'
        LBNF    EM2
        SMI     10
        LBNF    EM3
        GLO     RE
        ANI     0DFH
        SMI     'A'
        LBNF    EM2
        SMI     26
        LBNF    EM3
EM2:    LBR     WFLUSH          ; not: the word so far ends
EM3:    LOAD    RD, WLEN        ; into WBUF (63 at most)
        LDN     RD
        XRI     WMAX
        LBZ     EM9
        LDN     RD
        ADI     1
        STR     RD
        ADI     LOW(WBUF - 1)
        PLO     RD
        LDI     HIGH(WBUF - 1)
        ADCI    0
        PHI     RD
        GLO     RE
        STR     RD
EM9:    SEP     R5

; WFLUSH: the word in WBUF (WLEN), its ' at either end left off: out on a line of its own if it has two letters
WFLUSH: LOAD    RD, WLEN
        LDN     RD
        PLO     RA              ; RA.0 = its length
        LDI     0
        STR     RD
        LOAD    RD, WBUF
WF1:    GLO     RA              ; leading '
        LBZ     WF9
        LDN     RD
        XRI     27H
        LBNZ    WF2
        INC     RD
        DEC     RA
        LBR     WF1
WF2:    GLO     RA              ; trailing ': RB -> the last
        STR     R2
        GLO     RD
        ADD
        PLO     RB
        GHI     RD
        ADCI    0
        PHI     RB
WF3:    DEC     RB
        LDN     RB
        XRI     27H
        LBNZ    WF4
        DEC     RA
        LBR     WF3
WF4:    GHI     RD              ; the letters: two or more?
        PHI     RB
        GLO     RD
        PLO     RB
        GLO     RA
        PLO     RC
        LDI     0
        PHI     RC              ; RC.1 = the letters
WF5:    GLO     RC
        LBZ     WF6
        LDA     RB
        ANI     0DFH
        SMI     'A'
        LBNF    WF5B
        SMI     26
        LBDF    WF5B
        GHI     RC
        ADI     1
        PHI     RC
WF5B:   DEC     RC
        LBR     WF5
WF6:    GHI     RC
        SMI     2
        LBNF    WF9
WF7:    GLO     RA              ; out (RD walks it; the output keeps RD)
        LBZ     WF8
        LDA     RD
        SEP     R4
        DW      F_TYPE
        DEC     RA
        LBR     WF7
WF8:    SEP     R4
        DW      K_PCRLF
WF9:    SEP     R5

; ENDCH: the character at RF a space, a TAB or the end? D = 0 if so
ENDCH:  LDN     RF
        LBZ     EC9
        XRI     ' '
        LBZ     EC9
        XRI     29H             ; (' ' XOR TAB)
EC9:    SEP     R5
; SKIPSP: RF past spaces and TABs
SKIPSP: LDN     RF
        XRI     ' '
        LBZ     SS1
        XRI     29H             ; (' ' XOR TAB)
        LBNZ    SS9
SS1:    INC     RF
        LBR     SKIPSP
SS9:    SEP     R5

USAGE:  SEP     R4
        DW      K_PIN
        DB      'Usage: DEROFF [-w] name   (-w: the words, one to a line)',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
REQS:   DB      'TSEQshnhip',0
DROPS:  DB      '&%c|^',0
WORDS:  DS      1               ; WORDS SKIP LEN (2) WLEN: in this order
SKIP:   DS      1               ; 1 in a .TS table, 2 in a .EQ equation
LEN:    DS      2
WLEN:   DS      1
CH:     DS      1
SAVRF:  DS      4
WBUF:   DS      WMAX
LBUF:   DS      LMAX + 1
PEND:
        END
