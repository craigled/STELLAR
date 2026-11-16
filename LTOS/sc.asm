; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; sc.asm - SC.PRG: SC name - Tiny Stellar C on LTOS: NAME.SC (".SC" if no extension is typed) -> NAME.STL, a
; STELLAR app (run it by typing NAME). The language and the code it makes are SC/tsc.py's, step for step (that
; is the reference: verify_sc.py checks SC.PRG's .STL is tsc's byte for byte); tsc.py's own words say what the
; language holds. One pass as the source is read (a sector at a time); the 3 KB program block is made in RAM
; ($5200 = STELLAR's $4000): the code grows up from its start, variables and strings take room down from its
; top; a jump forward is filled in when its place is known (the ones still to fill make a chain through their
; own address bytes). A mistake: its line, and nothing saved.
;
; Memory: the code $3000-$4FFF; the .STL $5000-$63FF (its first sector, the 3 KB block, 3 empty blocks); the
; names $6400-$6BFF (24 bytes each: 85); loops $7700, names $7740 $7750 $7760 $77E0, file names $7800, a string
; $7900.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

HDR     EQU     5000H           ; the .STL's first sector
IMG     EQU     5200H           ; the 3 KB block (STELLAR's $4000; addresses in it are 0-0BFFH)
BLOCK   EQU     0CH             ; (its size, in pages)
STLEND  EQU     6400H           ; (3 empty blocks after it: $5000 $6000 $7000)
SYMT    EQU     6400H           ; the names: 0-15 the name (0s after), 16 the kind (c v a f), 17-18 the value,
SYMTOP  EQU     6C00H           ;  19 parameters, 20 1 = gives a value, 21-22 where the parameters are (85)
SYMSZ   EQU     24
LOOPS   EQU     7700H           ; break chain (2), continue target (2) - 16 deep
NBUF    EQU     7740H           ; the name being worked with (16, 0s after)
TBUF    EQU     7750H           ; the token's name (16, 0s after)
PNAMES  EQU     7760H           ; the parameters' names (8 x 16)
FNAMEB  EQU     77E0H           ; a function's name (16)
OPTXT   EQU     77F0H           ; "x expected" (16)
CXBUF   EQU     78C0H           ; NBUF kept while a constant's name is looked for (16)
SRCT    EQU     7800H           ; the source's name (64)
OUTT    EQU     7840H           ; the .STL's (64)
SBUF    EQU     7900H           ; a string (255)
NTEMP   EQU     11
TEOF    EQU     0               ; token kinds
TNUM    EQU     1
TID     EQU     2
TSTR    EQU     3
TOP     EQU     4
KU16    EQU     1               ; keywords (KW of a name)
KVOID   EQU     2
KCONST  EQU     3
KIF     EQU     4
KELSE   EQU     5
KWHILE  EQU     6
KFOR    EQU     7
KBREAK  EQU     8
KCONT   EQU     9
KRET    EQU     10
O_EQ    EQU     80H             ; two-character operators (in the order of OPS2)
O_NE    EQU     81H
O_LE    EQU     82H
O_GE    EQU     83H
O_AND   EQU     84H
O_OR    EQU     85H
O_INC   EQU     86H
O_DEC   EQU     87H
O_SHL   EQU     90H
O_SHR   EQU     91H

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
        LOAD    RD, VARS        ; the variables 0
        LOAD    RC, VEND - VARS
ST0:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST0
        GHI     RC
        LBNZ    ST0
        LOAD    RD, HDR         ; the .STL: 0s
        LOAD    RC, STLEND - HDR
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST1
        GHI     RC
        LBNZ    ST1
        LOAD    RD, JMPV
        LDI     0C0H
        STR     RD
        SEP     R4              ; the name
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        LOAD    RD, SRCT
        LDI     63
        PLO     RC
AR1:    LDN     RF
        LBZ     AR2
        XRI     ' '
        LBZ     AR2
        LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBZ     USE
        LBR     AR1
AR2:    LDI     0
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USE
        LOAD    RF, SRCT        ; no extension: .SC; the output: .STL
        SEP     R4
        DW      HASEXT
        LBNF    AR3
        LOAD    RA, SSC
        SEP     R4
        DW      APPEND
AR3:    LOAD    RF, SRCT
        LOAD    RD, OUTT
AR4:    LDA     RF
        STR     RD
        INC     RD
        LBNZ    AR4
        LOAD    RF, OUTT
        SEP     R4
        DW      HASEXT
        LDI     0
        STR     RA
        LOAD    RF, OUTT
        LOAD    RA, SSTL
        SEP     R4
        DW      APPEND
        LOAD    RF, OUTT        ; a name for it?
        LOAD    RD, ON11
        SEP     R4
        DW      K_PARSE
        LBDF    BADOUT
        LOAD    RF, SRCT        ; the source
        LOAD    RD, FN11
        SEP     R4
        DW      K_PARSE
        LBDF    NOSRC
        LOAD    RD, FN11
        SEP     R4
        DW      KS_FINDN
        LBDF    NOSRC
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    NOSRC
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, LINE + 1
        LDI     1
        STR     RD
        LOAD    RD, DTOP        ; the variables' room: from the top down
        LDI     BLOCK
        STR     RD
        LOAD    RD, SYME
        LDI     HIGH(SYMT)
        STR     RD
        INC     RD
        LDI     LOW(SYMT)
        STR     RD
        SEP     R4              ; the first two characters, the first token
        DW      NEXTCH
        SEP     R4
        DW      NEXTCH
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PROGRAM
        LOAD    RF, OUTT        ; the .STL saved (WDIR: its folder)
        LOAD    RD, ON11
        SEP     R4
        DW      K_PARSE
        LOAD    RD, ON11
        LOAD    RA, HDR
        LOAD    RC, STLEND - HDR
        SEP     R4
        DW      K_SAVER
        LBDF    NOSAVE
        SEP     R4
        DW      K_PIN
        DB      'Saved ',0
        LOAD    RF, OUTT
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      ': ',0
        LOAD    RD, PC
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' bytes of code, ',0
        LOAD    RD, DTOP        ; data: 3072 - DTOP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        SDI     0
        PLO     RD
        GHI     RC
        SDBI    BLOCK
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' of data.',0DH,0AH,0
        SEP     R5
NOSAVE: SEP     R4
        DW      K_PIN
        DB      'SC: the card is full - nothing saved.',0DH,0AH,0
        LBR     FAILST
NOSRC:  SEP     R4
        DW      K_PIN
        DB      'SC: there is no ',0
        LOAD    RF, SRCT
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PCRLF
        LBR     FAILST
BADOUT: SEP     R4
        DW      K_PIN
        DB      'SC: not a name for the output: ',0
        LOAD    RF, OUTT
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PCRLF
        LBR     FAILST
USE:    SEP     R4
        DW      K_PIN
        DB      'Usage: SC name     (name.SC -> name.STL: HELP SC)',0DH,0AH,0
FAILST: LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
; HASEXT: RF -> a path: DF = 1 if its last part has no '.'; else RA -> that '.'
HASEXT: LDI     0
        PHI     RA
HX1:    LDN     RF
        LBZ     HX9
        XRI     '/'
        LBNZ    HX2
        LDI     0
        PHI     RA
HX2:    LDN     RF
        XRI     '.'
        LBNZ    HX3
        GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
HX3:    INC     RF
        LBR     HX1
HX9:    GHI     RA
        LBZ     HX8
        LDI     0
        SHR
        SEP     R5
HX8:    LDI     1
        SHR
        SEP     R5
; APPEND: the text at RA after the one at RF
APPEND: LDN     RF
        LBZ     AP1
        INC     RF
        LBR     APPEND
AP1:    LDA     RA
        STR     RF
        INC     RF
        LBNZ    AP1
        SEP     R5
; PSTR: RF -> 0-ended text, out
PSTR:   LDA     RF
        LBZ     PS9
        SEP     R4
        DW      K_OUT
        LBR     PSTR
PS9:    SEP     R5

; ==== mistakes: "NAME.SC line n: what", $? 1, nothing saved
; ERRT: the text after the call.  ERRN: the name (NBUF) first.  ERRX: the text at RF.
ERRN:   SEP     R4
        DW      ERRHD
        LOAD    RF, NBUF
        SEP     R4
        DW      PSTR
        LBR     ERRT1
ERRT:   SEP     R4
        DW      ERRHD
ERRT1:  GHI     R6              ; the text after the call (R6 -> it)
        PHI     RF
        GLO     R6
        PLO     RF
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PCRLF
        LBR     FAILST
ERRX:   GHI     RF              ; (keep it while the header goes out)
        PHI     R6
        GLO     RF
        PLO     R6
        SEP     R4
        DW      ERRHD
        LBR     ERRT1
ERRHD:  LOAD    RF, SRCT        ; "NAME.SC line n: "
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      ' line ',0
        LOAD    RD, LINE
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ': ',0
        SEP     R5
; ERRP: two texts after the call, the name between them
ERRP:   SEP     R4
        DW      ERRHD
        GHI     R6
        PHI     RF
        GLO     R6
        PLO     RF
        SEP     R4
        DW      PSTR
        GHI     RF
        PHI     R6
        GLO     RF
        PLO     R6
        LOAD    RF, NBUF
        SEP     R4
        DW      PSTR
        LBR     ERRT1

; ==== reading the source: NEXTCH - CUR = NXT, NXT = the next character (CR and CR LF are LF; 0 the end)
NEXTCH: LOAD    RD, NXT
        LDN     RD
        PLO     RE
        LOAD    RD, CUR
        GLO     RE
        STR     RD
NC1:    SEP     R4
        DW      GETB
        LBDF    NCEOF
        PLO     RE
        XRI     0DH
        LBNZ    NC2
        LOAD    RD, CRF         ; CR: LF, and an LF after it left out
        LDI     1
        STR     RD
        LDI     0AH
        LBR     NC4
NC2:    GLO     RE
        XRI     0AH
        LBNZ    NC3
        LOAD    RD, CRF
        LDN     RD
        LBZ     NC3
        LDI     0
        STR     RD
        LBR     NC1
NC3:    LOAD    RD, CRF
        LDI     0
        STR     RD
        GLO     RE
NC4:    PLO     RE
        LOAD    RD, NXT
        GLO     RE
        STR     RD
        SEP     R5
NCEOF:  LDI     0
        LBR     NC4
; GETB: the file's next byte -> D, DF = 0; DF = 1 at its end
GETB:   LOAD    RD, SREM
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
GB1:    GHI     RC
        LBNZ    GB2
        GLO     RC
        LBNZ    GB2
        GLO     R7              ; (the kernel's read uses R7-RB: kept)
        STXD
        GHI     R7
        STXD
        GLO     R8
        STXD
        GHI     R8
        STXD
        GLO     R9
        STXD
        GHI     R9
        STXD
        GLO     RA
        STXD
        GHI     RA
        STXD
        GLO     RB
        STXD
        GHI     RB
        STXD
        SEP     R4
        DW      KS_FREAD
        IRX
        LDXA
        PHI     RB
        LDXA
        PLO     RB
        LDXA
        PHI     RA
        LDXA
        PLO     RA
        LDXA
        PHI     R9
        LDXA
        PLO     R9
        LDXA
        PHI     R8
        LDXA
        PLO     R8
        LDXA
        PHI     R7
        LDX
        PLO     R7
        LBDF    GB9
        LOAD    RD, SPTR
        LDI     HIGH(KS_DATBUF)
        STR     RD
        INC     RD
        LDI     LOW(KS_DATBUF)
        STR     RD
        LBR     GB1
GB9:    LDI     1
        SHR
        SEP     R5
GB2:    DEC     RC
        LOAD    RD, SREM
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, SPTR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDA     RC
        PLO     RE
        GLO     RC
        STR     RD
        DEC     RD
        GHI     RC
        STR     RD
        LDI     0
        SHR
        GLO     RE
        SEP     R5
INCLINE: LOAD   RD, LINE + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5
; CURIS: D = a character: DF = 0 if CUR is it
CURIS:  PLO     RE
        LOAD    RD, CUR
        LDN     RD
        STR     R2
        GLO     RE
        XOR
        LBZ     CI9
        LDI     1
        SHR
        SEP     R5
CI9:    SHR
        SEP     R5

; ==== the tokens: NEXT -> TKIND, TVAL, TOPC (an operator), KW (a name's keyword), NBUF, SBUF/SLEN
NEXT:   LOAD    RD, CUR         ; spaces, new lines, comments
        LDN     RD
        LBZ     NXEOF
        XRI     0AH
        LBNZ    NX1
        SEP     R4
        DW      INCLINE
        LBR     NXSKIP
NX1:    LDN     RD
        XRI     ' '
        LBZ     NXSKIP
        LDN     RD
        XRI     09H
        LBNZ    NX2
NXSKIP: SEP     R4
        DW      NEXTCH
        LBR     NEXT
NX2:    LDN     RD
        XRI     '/'
        LBNZ    NX4
        LOAD    RD, NXT
        LDN     RD
        XRI     '/'
        LBNZ    NX3
NX2A:   SEP     R4              ; // to the line's end
        DW      NEXTCH
        LOAD    RD, CUR
        LDN     RD
        LBZ     NEXT
        XRI     0AH
        LBNZ    NX2A
        LBR     NEXT
NX3:    LDN     RD
        XRI     '*'
        LBNZ    NX4
        SEP     R4              ; /* to */
        DW      NEXTCH
        SEP     R4
        DW      NEXTCH
NX3A:   LOAD    RD, CUR
        LDN     RD
        LBNZ    NX3B
        SEP     R4
        DW      ERRT
        DB      'a /* with no */',0
NX3B:   XRI     '*'
        LBNZ    NX3C
        LOAD    RD, NXT
        LDN     RD
        XRI     '/'
        LBNZ    NX3C
        SEP     R4
        DW      NEXTCH
        SEP     R4
        DW      NEXTCH
        LBR     NEXT
NX3C:   LOAD    RD, CUR
        LDN     RD
        XRI     0AH
        LBNZ    NX3D
        SEP     R4
        DW      INCLINE
NX3D:   SEP     R4
        DW      NEXTCH
        LBR     NX3A
NXEOF:  LDI     TEOF
        LBR     SETK
NX4:    LOAD    RD, CUR         ; a number?
        LDN     RD
        SMI     '0'
        LBNF    NX5
        SMI     10
        LBDF    NX5
        LBR     LXNUM
NX5:    LDN     RD
        XRI     27H
        LBZ     LXCHR
        LDN     RD
        XRI     22H
        LBZ     LXSTR
        LDN     RD
        SEP     R4
        DW      ISLET
        LBNF    LXID
        LOAD    RA, OPS2        ; two characters?
        LDI     80H
        PLO     RB
NX6:    LDN     RA
        LBZ     NX7
        LOAD    RD, CUR
        LDA     RA
        STR     R2
        LDN     RD
        XOR
        LBNZ    NX6A
        LOAD    RD, NXT
        LDN     RA
        STR     R2
        LDN     RD
        XOR
        LBNZ    NX6A
        SEP     R4
        DW      NEXTCH
        SEP     R4
        DW      NEXTCH
        GLO     RB
        LBR     SETOP
NX6A:   INC     RA
        INC     RB
        LBR     NX6
NX7:    LOAD    RA, OPS1        ; one
NX7A:   LDA     RA
        LBZ     NXBAD
        STR     R2
        LOAD    RD, CUR
        LDN     RD
        XOR
        LBNZ    NX7A
        LDN     RD
        PLO     RB
        SEP     R4
        DW      NEXTCH
        GLO     RB
SETOP:  PLO     RE              ; D = the operator's code
        LOAD    RD, TOPC
        GLO     RE
        STR     RD
        LDI     TOP
SETK:   PLO     RE
        LOAD    RD, TKIND
        GLO     RE
        STR     RD
        SEP     R5
NXBAD:  SEP     R4
        DW      ERRT
        DB      'not a character of Stellar C',0
OPS2:   DB      '==!=<=>=&&||++--+=-=*=/=%=&=|=^=<<>>',0
OPS1:   DB      '+-*/%&|^~!<>=(){}[];,',0
; ISLET: D a letter or _ ? DF = 0
ISLET:  PLO     RE
        XRI     '_'
        LBZ     IL9
        GLO     RE
        ANI     0DFH
        SMI     'A'
        LBNF    IL8
        SMI     26
        LBNF    IL9
IL8:    LDI     1
        SHR
        SEP     R5
IL9:    LDI     0
        SHR
        SEP     R5
; a number: 123 or 0x1F (over 65535: a mistake)
LXNUM:  LDI     0
        PHI     R8
        PLO     R8
        PLO     R9              ; R9.0: over 16 bits
        LDN     RD
        XRI     '0'
        LBNZ    LN1
        LOAD    RD, NXT
        LDN     RD
        ANI     0DFH
        XRI     'X'
        LBZ     LXHEX
LN1:    LOAD    RD, CUR         ; decimal: x 10 + the digit
        LDN     RD
        SMI     '0'
        LBNF    LN9
        SMI     10
        LBDF    LN9
        LDN     RD
        SMI     '0'
        PLO     RE
        GLO     R8              ; R8 x 2 -> R7
        SHL
        PLO     R7
        GHI     R8
        SHLC
        PHI     R7
        LBNF    LN2
        INC     R9
LN2:    GLO     R7              ; x 8 -> R8
        SHL
        PLO     R8
        GHI     R7
        SHLC
        PHI     R8
        LBNF    LN3
        INC     R9
LN3:    GLO     R8
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        LBNF    LN4
        INC     R9
LN4:    GLO     R7              ; x 8 + x 2
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     R7
        STR     R2
        GHI     R8
        ADC
        PHI     R8
        LBNF    LN5
        INC     R9
LN5:    GLO     RE
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        LBNF    LN6
        INC     R9
LN6:    SEP     R4
        DW      NEXTCH
        LBR     LN1
LN9:    GLO     R9
        LBZ     LNOK
LNBIG:  SEP     R4
        DW      ERRT
        DB      'a number over 65535',0
LNOK:   LOAD    RD, TVAL
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        LDI     TNUM
        LBR     SETK
LXHEX:  SEP     R4              ; 0x: digits
        DW      NEXTCH
        SEP     R4
        DW      NEXTCH
        LDI     0
        PLO     R7              ; R7.0: digits
LH1:    LOAD    RD, CUR
        LDN     RD
        SEP     R4
        DW      HEXD
        LBDF    LH9
        PLO     RE
        GHI     R8              ; a digit would push one out of 16 bits?
        ANI     0F0H
        LBZ     LH2
        INC     R9
LH2:    LDI     4
        PLO     RB
LH3:    GLO     R8
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        DEC     RB
        GLO     RB
        LBNZ    LH3
        GLO     RE
        STR     R2
        GLO     R8
        OR
        PLO     R8
        INC     R7
        SEP     R4
        DW      NEXTCH
        LBR     LH1
LH9:    GLO     R7
        LBNZ    LN9
        SEP     R4
        DW      ERRT
        DB      '0x with no digits',0
; HEXD: D a hex digit -> its value, DF = 0
HEXD:   PLO     RE
        SMI     '0'
        LBNF    HDN
        SMI     10
        LBNF    HD1
        GLO     RE
        ANI     0DFH
        SMI     'A'
        LBNF    HDN
        SMI     6
        LBDF    HDN
        ADI     16
        LSKP
HD1:    ADI     10
        PLO     RE
        LDI     0
        SHR
        GLO     RE
        SEP     R5
HDN:    LDI     1
        SHR
        SEP     R5
; 'c'
LXCHR:  SEP     R4
        DW      NEXTCH
        LOAD    RD, CUR
        LDN     RD
        LBZ     LCBAD
        XRI     27H
        LBZ     LCBAD
        XRI     2DH             ; (27H ^ 0AH)
        LBZ     LCBAD
        SEP     R4
        DW      ESCAPE
        PLO     R8
        LDI     0
        PHI     R8
        LDI     27H
        SEP     R4
        DW      CURIS
        LBNF    LC2
        SEP     R4
        DW      ERRT
        DB      'no closing ',27H,0
LC2:    SEP     R4
        DW      NEXTCH
        LBR     LNOK
LCBAD:  SEP     R4
        DW      ERRT
        DB      'not a character',0
; "text"
LXSTR:  SEP     R4
        DW      NEXTCH
        LOAD    RD, SLEN
        LDI     0
        STR     RD
LS1:    LOAD    RD, CUR
        LDN     RD
        XRI     22H
        LBZ     LS9
        LDN     RD
        LBZ     LSOPEN
        XRI     0AH
        LBZ     LSOPEN
        SEP     R4
        DW      ESCAPE
        PLO     RE
        LOAD    RD, SLEN
        LDN     RD
        PLO     RA
        ADI     1
        LBZ     LSBIG
        STR     RD
        LDI     HIGH(SBUF)
        PHI     RA
        GLO     RE
        STR     RA
        LBR     LS1
LS9:    SEP     R4
        DW      NEXTCH
        LDI     TSTR
        LBR     SETK
LSOPEN: SEP     R4
        DW      ERRT
        DB      'no closing ',22H,0
LSBIG:  SEP     R4
        DW      ERRT
        DB      'a string over 254 characters',0
; ESCAPE: a character of a 'c' or "text" (\n \r \t \b \e \0 \\ \' \") -> D
ESCAPE: LOAD    RD, CUR
        LDN     RD
        PLO     R9
        SEP     R4
        DW      NEXTCH
        GLO     R9
        XRI     5CH
        LBZ     ES1
        GLO     R9
        SEP     R5
ES1:    LOAD    RD, CUR
        LDN     RD
        PLO     R9
        SEP     R4
        DW      NEXTCH
        LOAD    RA, ESCT
ES2:    LDA     RA
        LBZ     ES9
        STR     R2
        GLO     R9
        XOR
        LBZ     ES3
        INC     RA
        LBR     ES2
ES3:    LDN     RA
        SEP     R5
ES9:    SEP     R4
        DW      ERRT
        DB      'not an escape',0
ESCT:   DB      'n',0AH,'r',0DH,'t',09H,'b',08H,'e',1BH,'0',0,5CH,5CH,27H,27H,22H,22H,0
; a name: up to 15 letters, digits and _ -> NBUF (0s after); KW its keyword (0: none)
LXID:   LOAD    RD, TBUF
        LDI     16
        PLO     RC
LI0:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    LI0
        LDI     0
        PLO     RB
LI1:    LOAD    RD, CUR
        LDN     RD
        SEP     R4
        DW      ISLET
        LBNF    LI2
        LDN     RD
        SMI     '0'
        LBNF    LI5
        SMI     10
        LBDF    LI5
LI2:    GLO     RB
        XRI     15
        LBNZ    LI3
        SEP     R4
        DW      ERRT
        DB      'a name over 15 letters',0
LI3:    GLO     RB
        ADI     LOW(TBUF)
        PLO     RA
        LDI     HIGH(TBUF)
        PHI     RA
        LDN     RD
        STR     RA
        INC     RB
        SEP     R4
        DW      NEXTCH
        LBR     LI1
LI5:    LOAD    RD, KW          ; a keyword?
        LDI     0
        STR     RD
        LOAD    RA, KWT
        LDI     1
        PLO     RB
LI6:    LDN     RA
        LBZ     LI9
        SEP     R4
        DW      NAMEQ           ; the 0-ended text at RA = NBUF? (RA past it)
        LBDF    LI7
        LOAD    RD, KW
        GLO     RB
        STR     RD
        LBR     LI9
LI7:    INC     RB
        LBR     LI6
LI9:    LDI     TID
        LBR     SETK
KWT:    DB      'u16',0,'void',0,'const',0,'if',0,'else',0,'while',0,'for',0,'break',0,'continue',0,'return',0
        DB      'print',0,'printu',0,'putc',0,'getc',0,'halt',0,0
; NAMEQ: the 0-ended text at RA = TBUF? DF = 0; RA ends past its 0 either way
NAMEQ:  LOAD    RD, TBUF
        LDI     0
        PLO     RE
NQ1:    LDA     RA
        STR     R2
        LDA     RD
        XOR
        LBZ     NQ2
        LDI     1
        PLO     RE
NQ2:    LDN     R2
        LBNZ    NQ1
        GLO     RE
        SHR
        SEP     R5

; ---- token tests: ISOP / TAKEOP / NEEDOP (D = the operator's code), ISKW / TAKEKW (D = the keyword)
ISOP:   PLO     RE              ; DF = 0 if the token is it
        LOAD    RD, TKIND
        LDN     RD
        XRI     TOP
        LBNZ    NO
        LOAD    RD, TOPC
        LDN     RD
        STR     R2
        GLO     RE
        XOR
        LBNZ    NO
YES:    LDI     0
        SHR
        SEP     R5
NO:     LDI     1
        SHR
        SEP     R5
ISKW:   PLO     RE
        LOAD    RD, TKIND
        LDN     RD
        XRI     TID
        LBNZ    NO
        LOAD    RD, KW
        LDN     RD
        STR     R2
        GLO     RE
        XOR
        LBNZ    NO
        LBR     YES
TAKEOP: SEP     R4
        DW      ISOP
        LBDF    NO
TK1:    SEP     R4
        DW      NEXT
        LBR     YES
TAKEKW: SEP     R4
        DW      ISKW
        LBDF    NO
        LBR     TK1
NEEDOP: PLO     R9              ; "x expected"
        SEP     R4
        DW      TAKEOP
        LBNF    NE9
        LOAD    RF, OPTXT
        GLO     R9
        SEP     R4
        DW      OPNAME          ; -> "x expected" at OPTXT
        LOAD    RF, OPTXT
        LBR     ERRX
NE9:    SEP     R5
NEEDKW: SEP     R4              ; (only u16: a parameter)
        DW      TAKEKW
        LBNF    NE9
        SEP     R4
        DW      ERRT
        DB      'u16 expected',0
; OPNAME: D = an operator's code -> "its text expected" at RF
OPNAME: PLO     RE
        ANI     80H
        LBZ     ON1
        GLO     RE              ; two characters: from OPS2
        ANI     1FH
        SHL
        ADI     LOW(OPS2)
        PLO     RA
        LDI     HIGH(OPS2)
        ADCI    0
        PHI     RA
        LDA     RA
        STR     RF
        INC     RF
        LDN     RA
        LBR     ON2
ON1:    GLO     RE
ON2:    STR     RF
        INC     RF
        LOAD    RA, SEXP
        LBR     AP1
SEXP:   DB      ' expected',0
; NAME: the token a name (not a keyword) -> NBUF (NKW its builtin's number, if one); on to the next token
NAME:   LOAD    RD, TKIND
        LDN     RD
        XRI     TID
        LBNZ    NM9
        LOAD    RD, KW
        LDN     RD
        LBZ     NM1
        SMI     11
        LBNF    NM9
NM1:    LOAD    RD, KW
        LDN     RD
        PLO     RE
        LOAD    RD, NKW
        GLO     RE
        STR     RD
        SEP     R4
        DW      TBNAME
        LBR     NEXT
NM9:    SEP     R4
        DW      ERRT
        DB      'a name expected',0
; TBNAME: NBUF = TBUF
TBNAME: LOAD    RA, TBUF
        LOAD    RD, NBUF
        LDI     16
        PLO     RC
TB1:    LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    TB1
        SEP     R5

; ==== code: EMIT D at PC (over DTOP: the program is over 4 KB)
EMIT:   PLO     RE
        LOAD    RD, PC
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, DTOP        ; PC < DTOP?
        LDA     RD
        STR     R2
        GHI     RF
        SM
        LBNF    EM1
        LBNZ    BIG
        LDN     RD
        STR     R2
        GLO     RF
        SM
        LBDF    BIG
EM1:    GLO     RF
        ADI     LOW(IMG)
        PLO     RD
        GHI     RF
        ADCI    HIGH(IMG)
        PHI     RD
        GLO     RE
        STR     RD
        INC     RF
        LOAD    RD, PC
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R5
BIG:    SEP     R4
        DW      ERRT
        DB      'the program is over 3 KB',0
; EMITN: the bytes after the call (a count first)
EMITN:  LDA     R6
        PLO     R9
EN1:    LDA     R6
        SEP     R4
        DW      EMIT
        DEC     R9
        GLO     R9
        LBNZ    EN1
        SEP     R5
; WORD: RF -> 2 bytes out, high first.  EMITW: the word RC
EMITW:  GHI     RC
        SEP     R4
        DW      EMIT
        GLO     RC
        LBR     EMIT
; HERE: RC = PC
HERE:   LOAD    RD, PC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R5
; PATCH: the word at RA (an address in the block) = RC
PATCH:  GLO     RA
        ADI     LOW(IMG)
        PLO     RD
        GHI     RA
        ADCI    HIGH(IMG)
        PHI     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
; PATCHPC: the chain at RA (each place holds the next; 0 ends it) = PC
PATCHPC: SEP    R4
        DW      HERE
PP1:    GHI     RA
        LBNZ    PP2
        GLO     RA
        LBZ     PP9
PP2:    GLO     RA              ; the next first
        ADI     LOW(IMG)
        PLO     RD
        GHI     RA
        ADCI    HIGH(IMG)
        PHI     RD
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        SEP     R4
        DW      PATCH
        GHI     RB
        PHI     RA
        GLO     RB
        PLO     RA
        LBR     PP1
PP9:    SEP     R5
; DATA: RC = bytes -> RC = their address (DTOP down by them; below PC: over 4 KB)
DATA:   LOAD    RD, DTOP + 1
        GLO     RC
        STR     R2
        LDN     RD
        SM
        STR     RD
        DEC     RD
        GHI     RC
        STR     R2
        LDN     RD
        SMB
        STR     RD
        LBNF    BIG
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, PC          ; DTOP < PC?
        LDA     RD
        STR     R2
        GHI     RC
        SM
        LBNF    BIG
        LBNZ    DA9
        LDN     RD
        STR     R2
        GLO     RC
        SM
        LBNF    BIG
DA9:    SEP     R5
; LDV: Rk (D) = the variable at RC: LOADXI RF addr; COPYMXY 02 Fk.  STV: the same, Rk -> it
LDV:    PLO     R9
        SEP     R4
        DW      LDRF
        LDI     39H
        SEP     R4
        DW      EMIT
        LDI     02H
        SEP     R4
        DW      EMIT
        GLO     R9
        ORI     0F0H
        LBR     EMIT
STV:    PLO     R9
        SEP     R4
        DW      LDRF
        LDI     3AH
        SEP     R4
        DW      EMIT
        LDI     02H
        SEP     R4
        DW      EMIT
        GLO     R9
        SHL
        SHL
        SHL
        SHL
        ORI     0FH
        LBR     EMIT
LDRF:   LDI     11H             ; LOADXI RF RC
        SEP     R4
        DW      EMIT
        LDI     0FH
        SEP     R4
        DW      EMIT
        LBR     EMITW
; LDXI: LOADXI Rk (D) RC
LDXI:   PLO     R9
        LDI     11H
        SEP     R4
        DW      EMIT
        GLO     R9
        SEP     R4
        DW      EMIT
        LBR     EMITW
; JMPW: D = an opcode (A0 A1 B0), then a place to fill: its chain link RC; -> RC = the place (PC before the word)
JMPW:   SEP     R4
        DW      EMIT
        GHI     RC
        PHI     R9
        GLO     RC
        PLO     R9
        SEP     R4
        DW      HERE
        GHI     RC
        STXD
        GLO     RC
        STXD
        GHI     R9
        PHI     RC
        GLO     R9
        PLO     RC
        SEP     R4
        DW      EMITW
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        SEP     R5

; ==== names
; FIND: NBUF -> RA = its entry (the last one of that name), DF = 0; DF = 1 none
FIND:   LOAD    RD, SYME
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
FD1:    GHI     RA
        XRI     HIGH(SYMT)
        LBNZ    FD2
        GLO     RA
        XRI     LOW(SYMT)
        LBZ     NO
FD2:    GLO     RA
        SMI     SYMSZ
        PLO     RA
        GHI     RA
        SMBI    0
        PHI     RA
        SEP     R4
        DW      SYMEQ
        LBDF    FD1
        SEP     R5
; SYMEQ: the entry at RA's name = NBUF? DF = 0 (RA kept)
SYMEQ:  GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        LOAD    RD, NBUF
        LDI     16
        PLO     RB
SQ1:    LDA     RC
        STR     R2
        LDA     RD
        XOR
        LBNZ    NO
        DEC     RB
        GLO     RB
        LBNZ    SQ1
        LBR     YES
; ADD: NBUF a new name, D its kind, RC its value -> RA its entry (defined twice in this function, or among the
;      globals: a mistake)
ADD:    PLO     R9
        GHI     RC
        PHI     R8
        GLO     RC
        PLO     R8
        LOAD    RD, FN          ; from NGLOB in a function, else from the start
        LDA     RD
        LBZ     AD0
        LOAD    RD, NGLOB
        LBR     AD0A
AD0:    LOAD    RA, SYMT
        LBR     AD1
AD0A:   LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
AD1:    LOAD    RD, SYME
        LDA     RD
        STR     R2
        GHI     RA
        XOR
        LBNZ    AD2
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBZ     AD3
AD2:    SEP     R4
        DW      SYMEQ
        LBDF    AD2A
        SEP     R4
        DW      ERRN
        DB      ' defined twice',0
AD2A:   GLO     RA
        ADI     SYMSZ
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     AD1
AD3:    GLO     RA              ; room? (RA + 24 <= SYMTOP)
        SMI     LOW(SYMTOP - SYMSZ)
        GHI     RA
        SMBI    HIGH(SYMTOP - SYMSZ)
        LBNF    AD4
        LBZ     AD3A
        LBR     AD3B
AD3A:   GLO     RA
        XRI     LOW(SYMTOP - SYMSZ)
        LBZ     AD4
AD3B:
        SEP     R4
        DW      ERRT
        DB      'too many names',0
AD4:    LOAD    RD, NBUF
        LDI     16
        PLO     RB
AD5:    LDA     RD
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    AD5
        GLO     R9              ; kind, value, 0s
        STR     RA
        INC     RA
        GHI     R8
        STR     RA
        INC     RA
        GLO     R8
        STR     RA
        INC     RA
        LDI     5
        PLO     RB
AD6:    LDI     0
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    AD6
        LOAD    RD, SYME
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        GLO     RA
        SMI     SYMSZ
        PLO     RA
        GHI     RA
        SMBI    0
        PHI     RA
        SEP     R5
; CEXPR: a constant: [-] a number, a character, a constant's name -> RC
CEXPR:  LDI     '-'
        SEP     R4
        DW      TAKEOP
        LDI     0
        LBDF    CX0
        LDI     1
CX0:    PLO     R9
        GLO     R9
        STXD
        LOAD    RD, TKIND
        LDN     RD
        XRI     TNUM
        LBNZ    CX2
        LOAD    RD, TVAL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LBR     CX5
CX2:    LDN     RD
        XRI     TID
        LBNZ    CX9
        LOAD    RA, NBUF        ; (NBUF kept: it may be the name being declared)
        LOAD    RD, CXBUF
        LDI     16
        PLO     RC
CX2A:   LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    CX2A
        SEP     R4
        DW      TBNAME
        SEP     R4
        DW      FIND
        LBDF    CX3
        GLO     RA
        ADI     16
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LDA     RA
        XRI     'c'
        LBNZ    CX3
        LDA     RA
        PHI     RC
        LDN     RA
        PLO     RC
        LOAD    RA, CXBUF       ; NBUF back
        LOAD    RD, NBUF
        LDI     16
        PLO     RB
CX4:    LDA     RA
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    CX4
CX5:    GHI     RC
        STXD
        GLO     RC
        STXD
        SEP     R4
        DW      NEXT
        IRX
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDX
        LBZ     CX6
        GLO     RC              ; - : 0 - it
        SDI     0
        PLO     RC
        GHI     RC
        SDBI    0
        PHI     RC
CX6:    SEP     R5
CX3:    SEP     R4
        DW      ERRN
        DB      ' is not a constant',0
CX9:    SEP     R4
        DW      ERRT
        DB      'a constant expected',0

; ==== registers: PUSHK (Rk = a new one -> D = k); VALUE (the Test flag's answer a number in Rk)
PUSHK:  LOAD    RD, K
        LDN     RD
        XRI     NTEMP
        LBNZ    PK1
        SEP     R4
        DW      ERRT
        DB      'the expression is too deep',0
PK1:    LDN     RD
        ADI     1
        STR     RD
        SEP     R5
GETK:   LOAD    RD, K
        LDN     RD
        SEP     R5
VALUE:  LOAD    RD, FLAG        ; (0FFH: the value is in Rk already)
        LDN     RD
        XRI     0FFH
        LBZ     VA9
        SEP     R4              ; A0 (A1) yes / LOADXI Rk 0 / B0 end / yes: LOADXI Rk 1 / end:
        DW      HERE
        GLO     RC
        ADI     10
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LOAD    RD, FLAG
        LDN     RD
        XRI     1
        LBZ     VA1
        LDI     0A1H
        LSKP
VA1:    LDI     0A0H
        SEP     R4
        DW      EMIT
        SEP     R4
        DW      EMITW
        SEP     R4
        DW      GETK
        PLO     R9
        LDI     11H
        SEP     R4
        DW      EMIT
        GLO     R9
        SEP     R4
        DW      EMIT
        LDI     0
        SEP     R4
        DW      EMIT
        LDI     0
        SEP     R4
        DW      EMIT
        LDI     0B0H
        SEP     R4
        DW      EMIT
        INC     RC
        INC     RC
        INC     RC
        INC     RC
        SEP     R4
        DW      EMITW
        SEP     R4
        DW      GETK
        PLO     R9
        LDI     11H
        SEP     R4
        DW      EMIT
        GLO     R9
        SEP     R4
        DW      EMIT
        LDI     0
        SEP     R4
        DW      EMIT
        LDI     1
        SEP     R4
        DW      EMIT
        LOAD    RD, FLAG
        LDI     0FFH
        STR     RD
VA9:    SEP     R5
; TOJUMP: a jump if the condition (Rk, or the Test flag) is false -> RC = its place (to fill); Rk freed
TOJUMP: LOAD    RD, FLAG
        LDN     RD
        XRI     0FFH
        LBNZ    TJ1
        SEP     R4              ; 8C 0k (TESTXZ: Test = it is 0), A0
        DW      GETK
        PLO     R9
        LDI     8CH
        SEP     R4
        DW      EMIT
        GLO     R9
        SEP     R4
        DW      EMIT
        LDI     0A0H
        LBR     TJ3
TJ1:    LDN     RD
        LBZ     TJ2
        LDI     0A1H
        LBR     TJ3
TJ2:    LDI     0A0H
TJ3:    PLO     R9
        LOAD    RD, FLAG
        LDI     0FFH
        STR     RD
        LOAD    RD, K
        LDN     RD
        SMI     1
        STR     RD
        LDI     0
        PLO     RC
        PHI     RC
        GLO     R9
        LBR     JMPW
; CONDJ: a jump (chained on RC) taken when the operand is true (D = 1) or false (0) -> RC; its register freed
CONDJ:  PLO     R8              ; R8.0 = when; R8.1 / RC kept
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        LOAD    RD, FLAG
        LDN     RD
        XRI     0FFH
        LBNZ    CJ1
        SEP     R4
        DW      GETK
        PLO     R9
        LDI     8CH
        SEP     R4
        DW      EMIT
        GLO     R9
        SEP     R4
        DW      EMIT
        LDI     0
        LBR     CJ2
CJ1:    LDN     RD
CJ2:    STR     R2              ; f == when: A0, else A1
        GLO     R8
        XOR
        LBZ     CJ3
        LDI     0A1H
        LSKP
CJ3:    LDI     0A0H
        PLO     R9
        LOAD    RD, FLAG
        LDI     0FFH
        STR     RD
        LOAD    RD, K
        LDN     RD
        SMI     1
        STR     RD
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        GLO     R9
        LBR     JMPW

; ==== expressions (tsc's expr / logic / unary / primary): each leaves one more register in use, or the Test flag.
;      A routine that calls itself keeps its own variables in memory, and the outer one's on the R2 stack.
; EXPR: D = the level (0 || .. 9 * / %, 10 unary)
EXPR:   PLO     RE
        XRI     10
        LBZ     UNARY
        GLO     RE
        SMI     2
        LBNF    LOGIC1
        LOAD    RD, ELVL        ; the outer one's ELVL, EOP kept
        LDA     RD
        STXD
        LDN     RD
        STXD
        DEC     RD
        GLO     RE
        STR     RD
        ADI     1
        SEP     R4
        DW      EXPR
EX1:    LOAD    RD, ELVL        ; an operator of this level?
        LDN     RD
        SEP     R4
        DW      INPREC
        LBDF    EX9
        PLO     RE
        LOAD    RD, EOP
        GLO     RE
        STR     RD
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      VALUE
        LOAD    RD, EOP
        LDN     RD
        XRI     O_SHL
        LBZ     EXSHL
        LDN     RD
        XRI     O_SHR
        LBZ     EXSHR
        LOAD    RD, ELVL        ; the right side: one level higher
        LDN     RD
        ADI     1
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        SEP     R4              ; b = K; a = b - 1; K = a
        DW      GETK
        PLO     R8              ; R8.0 = b
        SMI     1
        STR     RD
        PHI     R8              ; R8.1 = a
        LOAD    RD, EOP
        LDN     RD
        SEP     R4
        DW      BINOP
        LBR     EX1
EX9:    IRX                     ; the outer one's back
        LDXA
        PLO     RC
        LDX
        PHI     RC
        LOAD    RD, ELVL
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
EXSHL:  SEP     R4              ; << n: ADDXYZ a + a -> a, n times
        DW      SHIFTN
        PLO     R9
EXL1:   GLO     R9
        LBZ     EX1
        SEP     R4
        DW      GETK
        PLO     R8
        LDI     50H
        SEP     R4
        DW      EMIT
        GLO     R8
        SHL
        SHL
        SHL
        SHL
        STR     R2
        GLO     R8
        OR
        SEP     R4
        DW      EMIT
        GLO     R8
        SEP     R4
        DW      EMIT
        DEC     R9
        LBR     EXL1
EXSHR:  SEP     R4              ; >> n: b = a new one; LOADXI b 2^n; DIVXY a b; COPYAX MA -> a
        DW      SHIFTN
        PLO     R9
        LDI     1               ; RC = 1 << n
        PLO     RC
        LDI     0
        PHI     RC
EXR1:   GLO     R9
        LBZ     EXR2
        GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        DEC     R9
        LBR     EXR1
EXR2:   SEP     R4
        DW      PUSHK
        SEP     R4
        DW      LDXI
        SEP     R4
        DW      GETK
        PLO     R9              ; b
        SMI     1
        STR     RD              ; K = a
        PLO     R8              ; a
        LDI     4DH
        SEP     R4
        DW      EMIT
        GLO     R8
        SHL
        SHL
        SHL
        SHL
        STR     R2
        GLO     R9
        OR
        SEP     R4
        DW      EMIT
        LDI     21H
        SEP     R4
        DW      EMIT
        GLO     R8
        ORI     10H
        SEP     R4
        DW      EMIT
        LBR     EX1
; SHIFTN: the shift's constant -> D (over 15: a mistake)
SHIFTN: SEP     R4
        DW      CEXPR
        GHI     RC
        LBNZ    SN9
        GLO     RC
        SMI     16
        LBDF    SN9
        GLO     RC
        SEP     R5
SN9:    SEP     R4
        DW      ERRT
        DB      'a shift over 15',0
; INPREC: D = a level 2-9: DF = 0, D = the operator, if the token is one of its
INPREC: SMI     2
        SHL
        ADI     LOW(PRECT)
        PLO     RA
        LDI     HIGH(PRECT)
        ADCI    0
        PHI     RA
        LDA     RA
        PHI     RC
        LDN     RA
        PLO     RA
        GHI     RC
        PHI     RA
        LOAD    RD, TKIND
        LDN     RD
        XRI     TOP
        LBNZ    NO
        LOAD    RD, TOPC
IP1:    LDA     RA
        LBZ     NO
        STR     R2
        LDN     RD
        XOR
        LBNZ    IP1
        LDI     0
        SHR
        LDN     RD
        SEP     R5
PRECT:  DW      PR2, PR3, PR4, PR5, PR6, PR7, PR8, PR9
PR2:    DB      O_EQ, O_NE, 0
PR3:    DB      '<', O_LE, '>', O_GE, 0
PR4:    DB      '|', 0
PR5:    DB      '^', 0
PR6:    DB      '&', 0
PR7:    DB      O_SHL, O_SHR, 0
PR8:    DB      '+', '-', 0
PR9:    DB      '*', '/', '%', 0
; BINOP: D = the operator, R8.1 = a, R8.0 = b: its code (comparisons: the Test flag)
BINOP:  PLO     R9
        GHI     R8              ; RC.0 = a*16+b, RC.1 = b*16+a
        SHL
        SHL
        SHL
        SHL
        STR     R2
        GLO     R8
        OR
        PLO     RC
        GLO     R8
        SHL
        SHL
        SHL
        SHL
        STR     R2
        GHI     R8
        OR
        PHI     RC
        LOAD    RA, BOPT
BO1:    LDA     RA
        LBZ     BO9
        STR     R2
        GLO     R9
        XOR
        LBZ     BO2
        INC     RA
        INC     RA
        LBR     BO1
BO2:    LOAD    RD, JMPV + 1
        LDA     RA
        STR     RD
        INC     RD
        LDN     RA
        STR     RD
        LBR     JMPV
BO9:    SEP     R5
BOPT:   DB      '+'
        DW      OP_ADD
        DB      '-'
        DW      OP_SUB
        DB      '*'
        DW      OP_MUL
        DB      '/'
        DW      OP_DIV
        DB      '%'
        DW      OP_MOD
        DB      '&'
        DW      OP_AND
        DB      '|'
        DW      OP_OR
        DB      '^'
        DW      OP_XOR
        DB      O_EQ
        DW      OP_EQ
        DB      O_NE
        DW      OP_NE
        DB      '<'
        DW      OP_LT
        DB      O_GE
        DW      OP_GE
        DB      '>'
        DW      OP_GT
        DB      O_LE
        DW      OP_LE
        DB      0
OP_ADD: LDI     50H             ; 50 ab 0a
        LBR     OPXYZ
OP_SUB: LDI     51H
OPXYZ:  SEP     R4
        DW      EMIT
        GLO     RC
        SEP     R4
        DW      EMIT
        GHI     R8
        LBR     EMIT
OP_MUL: LDI     4AH             ; 4A ab 21 1a (4D: /)
        LSKP
OP_DIV: LDI     4DH
        SEP     R4
        DW      EMIT
        GLO     RC
        SEP     R4
        DW      EMIT
        LDI     21H
        SEP     R4
        DW      EMIT
        GHI     R8
        ORI     10H
        LBR     EMIT
OP_MOD: LDI     4DH             ; 4D ab 27 21 0a
        SEP     R4
        DW      EMIT
        GLO     RC
        SEP     R4
        DW      EMIT
        LDI     27H
        SEP     R4
        DW      EMIT
        LDI     21H
        SEP     R4
        DW      EMIT
        GHI     R8
        LBR     EMIT
OP_AND: LDI     65H             ; 22 0b 6x 0a 21 1a
        LBR     OPLOG
OP_OR:  LDI     63H
        LBR     OPLOG
OP_XOR: LDI     64H
OPLOG:  PLO     R9
        LDI     22H
        SEP     R4
        DW      EMIT
        GLO     R8
        SEP     R4
        DW      EMIT
        GLO     R9
        SEP     R4
        DW      EMIT
        GHI     R8
        SEP     R4
        DW      EMIT
        LDI     21H
        SEP     R4
        DW      EMIT
        GHI     R8
        ORI     10H
        LBR     EMIT
OP_EQ:  LDI     1               ; TESTXY a b: true when Test = 1
        LSKP
OP_NE:  LDI     0
        PLO     R9
        LDI     87H
        LBR     OPTAB
OP_LT:  LDI     1               ; TESTLXY a b
        LSKP
OP_GE:  LDI     0
        PLO     R9
        LDI     89H
OPTAB:  SEP     R4
        DW      EMIT
        GLO     RC
        LBR     OPTF
OP_GT:  LDI     1               ; TESTLXY b a
        LSKP
OP_LE:  LDI     0
        PLO     R9
        LDI     89H
        SEP     R4
        DW      EMIT
        GHI     RC
OPTF:   SEP     R4
        DW      EMIT
        LOAD    RD, FLAG
        GLO     R9
        STR     RD
        SEP     R5

; LOGIC: D = 0 (||) or 1 (&&), short: the answer a number, 0 or 1
LOGIC1: GLO     RE
LOGIC:  PLO     RE
        LOAD    RD, LLVL        ; the outer one's LLVL, LCHAIN kept
        LDA     RD
        STXD
        LDA     RD
        STXD
        LDN     RD
        STXD
        LOAD    RD, LLVL
        GLO     RE
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        GLO     RE
        ADI     1
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      LOGOP
        SEP     R4
        DW      ISOP
        LBDF    LG9
LG1:    SEP     R4
        DW      LOGOP
        SEP     R4
        DW      TAKEOP
        LBDF    LG2
        SEP     R4
        DW      LGJUMP
        LOAD    RD, LLVL
        LDN     RD
        ADI     1
        SEP     R4
        DW      EXPR
        LBR     LG1
LG2:    SEP     R4
        DW      LGJUMP
        SEP     R4              ; the answer's register
        DW      PUSHK
        PLO     RE
        LOAD    RD, LK
        GLO     RE
        STR     RD
        LOAD    RD, LLVL        ; || : 0 first, && : 1
        LDN     RD
        PLO     RC
        LDI     0
        PHI     RC
        GLO     RE
        SEP     R4
        DW      LDXI
        LDI     0               ; B0 end
        PLO     RC
        PHI     RC
        LDI     0B0H
        SEP     R4
        DW      JMPW
        LOAD    RD, LEND
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, LCHAIN      ; the chain: here
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      PATCHPC
        LOAD    RD, LLVL        ; || : 1, && : 0
        LDN     RD
        XRI     1
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    RD, LK
        LDN     RD
        SEP     R4
        DW      LDXI
        LOAD    RD, LEND
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      HERE
        SEP     R4
        DW      PATCH
LG9:    IRX                     ; the outer one's back
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDX
        PLO     R9
        LOAD    RD, LLVL
        GLO     R9
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
; LGJUMP: a jump on the operand (|| : when true, && : when false), on LCHAIN
LGJUMP: LOAD    RD, LCHAIN
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, LLVL
        LDN     RD
        XRI     1
        SEP     R4
        DW      CONDJ
        LOAD    RD, LCHAIN
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
; LOGOP: LLVL's operator -> D
LOGOP:  LOAD    RD, LLVL
        LDN     RD
        LBZ     LO1
        LDI     O_AND
        SEP     R5
LO1:    LDI     O_OR
        SEP     R5

; UNARY: - ~ ! then a primary
UNARY:  LDI     '-'
        SEP     R4
        DW      TAKEOP
        LBDF    UN2
        SEP     R4
        DW      UNARY
        SEP     R4
        DW      VALUE
        SEP     R4
        DW      GETK
        PLO     R8
        SEP     R4
        DW      EMITN
        DB      5, 11H, 0EH, 0, 0, 51H
        GLO     R8
        ORI     0E0H
        SEP     R4
        DW      EMIT
        GLO     R8
        LBR     EMIT
UN2:    LDI     '~'
        SEP     R4
        DW      TAKEOP
        LBDF    UN3
        SEP     R4
        DW      UNARY
        SEP     R4
        DW      VALUE
        SEP     R4
        DW      GETK
        PLO     R8
        LDI     64H
        SEP     R4
        DW      EMIT
        GLO     R8
        ORI     10H
        SEP     R4
        DW      EMIT
        SEP     R4
        DW      EMITN
        DB      3, 0FFH, 0FFH, 21H
        GLO     R8
        ORI     10H
        LBR     EMIT
UN3:    LDI     '!'
        SEP     R4
        DW      TAKEOP
        LBDF    PRIMARY
        SEP     R4
        DW      UNARY
        LOAD    RD, FLAG
        LDN     RD
        XRI     0FFH
        LBZ     UN4
        LDN     RD
        XRI     1
        STR     RD
        SEP     R5
UN4:    SEP     R4              ; TESTXZ k: Test = 1 when it is 0
        DW      GETK
        PLO     R8
        LDI     8CH
        SEP     R4
        DW      EMIT
        GLO     R8
        SEP     R4
        DW      EMIT
        LOAD    RD, FLAG
        LDI     1
        STR     RD
        SEP     R5

; PRIMARY: ( e ), a number, a name: a constant, a variable, a[i], f(...)
PRIMARY: LDI    '('
        SEP     R4
        DW      TAKEOP
        LBDF    PM1
        LDI     0
        SEP     R4
        DW      EXPR
        LDI     ')'
        LBR     NEEDOP
PM1:    LOAD    RD, TKIND
        LDN     RD
        XRI     TNUM
        LBNZ    PM2
        LOAD    RD, TVAL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      PUSHK
        SEP     R4
        DW      LDXI
        LBR     NEXT
PM2:    LDN     RD
        XRI     TID
        LBZ     PM3
        SEP     R4
        DW      ERRT
        DB      'a value expected',0
PM3:    SEP     R4
        DW      NAME
        LDI     '('
        SEP     R4
        DW      ISOP
        LBDF    PM4
        LDI     1
        LBR     CALL
PM4:    SEP     R4
        DW      FIND
        LBNF    PM5
        SEP     R4
        DW      ERRN
        DB      ' not defined',0
PM5:    SEP     R4
        DW      ENTKIND         ; D = the kind, RC = the value
        XRI     'c'
        LBNZ    PM6
        SEP     R4
        DW      PUSHK
        LBR     LDXI
PM6:    XRI     15H             ; ('c' ^ 'v')
        LBNZ    PM7
        SEP     R4
        DW      PUSHK
        LBR     LDV
PM7:    XRI     17H             ; ('v' ^ 'a')
        LBZ     PM8
        SEP     R4
        DW      ERRN
        DB      ' is a function: ( expected',0
PM8:    GHI     RC              ; a[i]: its base kept on the stack
        STXD
        GLO     RC
        STXD
        LDI     '['
        SEP     R4
        DW      NEEDOP
        LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        LDI     ']'
        SEP     R4
        DW      NEEDOP
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        SEP     R4              ; 50 kk 0k 52 0k base 39 02 kk
        DW      GETK
        PLO     R8
        SHL
        SHL
        SHL
        SHL
        STR     R2
        GLO     R8
        OR
        PHI     R8              ; kk
        LDI     50H
        SEP     R4
        DW      EMIT
        GHI     R8
        SEP     R4
        DW      EMIT
        GLO     R8
        SEP     R4
        DW      EMIT
        LDI     52H
        SEP     R4
        DW      EMIT
        GLO     R8
        SEP     R4
        DW      EMIT
        SEP     R4
        DW      EMITW
        LDI     39H
        SEP     R4
        DW      EMIT
        LDI     02H
        SEP     R4
        DW      EMIT
        GHI     R8
        LBR     EMIT
; ENTKIND: RA -> an entry: D = its kind, RC = its value
ENTKIND: GLO    RA
        ADI     16
        PLO     RD
        GHI     RA
        ADCI    0
        PHI     RD
        LDA     RD
        PLO     RE
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RE
        SEP     R5

; ==== calls. CALL: NBUF = the name, the token (; D = 1: its value wanted.  CWANT CADDR CPB CN CK0 CJ (8 bytes)
;      are this call's; the outer call's are kept on the stack (a call can be inside another's values)
CALL:   PLO     RE
        LOAD    RD, CVARS       ; the outer one's kept
        LDI     8
        PLO     RC
CL0:    LDA     RD
        STXD
        DEC     RC
        GLO     RC
        LBNZ    CL0
        LOAD    RD, CWANT
        GLO     RE
        STR     RD
        LDI     '('
        SEP     R4
        DW      NEEDOP
        LOAD    RD, NKW         ; a builtin? (NAME set NKW; NEXT leaves it)
        LDN     RD
        SMI     11
        LBNF    CL1
        SEP     R4
        DW      BUILTIN
        LBR     CL99
CL1:    SEP     R4
        DW      FIND
        LBDF    CANOF
        SEP     R4
        DW      ENTKIND
        XRI     'f'
        LBZ     CL2
CANOF:  SEP     R4
        DW      ERRP
        DB      'no function ',0,'() (defined before this?)',0
CL2:    LOAD    RD, FN          ; itself?
        LDA     RD
        STR     R2
        GHI     RA
        XOR
        LBNZ    CL3
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBNZ    CL3
        SEP     R4
        DW      ERRN
        DB      '() calls itself: no recursion',0
CL3:    LOAD    RD, CADDR       ; CADDR = its address
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        GLO     RA              ; RA -> 19: nargs, 20 gives a value, 21-22 pbase
        ADI     19
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LOAD    RD, CWANT
        LDN     RD
        LBZ     CL4
        INC     RA
        LDN     RA
        DEC     RA
        LBNZ    CL4
        SEP     R4
        DW      ERRN
        DB      '() gives no value',0
CL4:    LDA     RA
        PLO     RE
        LOAD    RD, CN
        GLO     RE
        STR     RD
        INC     RA
        LOAD    RD, CPB
        LDA     RA
        STR     RD
        INC     RD
        LDN     RA
        STR     RD
        SEP     R4
        DW      GETK
        PLO     RE
        LOAD    RD, CK0
        GLO     RE
        STR     RD
        INC     RD              ; CJ = 0
        LDI     0
        STR     RD
CL5:    LOAD    RD, CN          ; the values (CJ of CN so far)
        LDN     RD
        STR     R2
        LOAD    RD, CJ
        LDN     RD
        XOR
        LBZ     CL7
        LDN     RD
        LBZ     CL6
        LDI     ','
        SEP     R4
        DW      NEEDOP
CL6:    LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        LOAD    RD, CJ
        LDN     RD
        ADI     1
        STR     RD
        LBR     CL5
CL7:    LDI     ')'
        SEP     R4
        DW      NEEDOP
        LOAD    RD, CJ          ; each into its parameter: R(k0 + 1 + j) -> pbase + 2j
        LDI     0
        STR     RD
CL8:    LOAD    RD, CN
        LDN     RD
        STR     R2
        LOAD    RD, CJ
        LDN     RD
        XOR
        LBZ     CL9
        LDN     RD              ; RC = pbase + 2j
        SHL
        STR     R2
        LOAD    RD, CPB + 1
        LDN     RD
        ADD
        PLO     RC
        DEC     RD
        LDN     RD
        ADCI    0
        PHI     RC
        LOAD    RD, CK0         ; D = k0 + 1 + j
        LDA     RD
        STR     R2
        LDN     RD
        ADD
        ADI     1
        SEP     R4
        DW      STV
        LOAD    RD, CJ
        LDN     RD
        ADI     1
        STR     RD
        LBR     CL8
CL9:    LOAD    RD, CK0         ; K = k0; PUSHX R1 .. Rk0
        LDN     RD
        PLO     RE
        LOAD    RD, K
        GLO     RE
        STR     RD
        LDI     1
        PLO     R9
CL10:   GLO     R9
        STR     R2
        GLO     RE
        SM
        LBNF    CL11
        LDI     72H
        SEP     R4
        DW      EMIT
        GLO     R9
        SEP     R4
        DW      EMIT
        INC     R9
        LOAD    RD, CK0
        LDN     RD
        PLO     RE
        LBR     CL10
CL11:   LDI     0BDH            ; CALL its address
        SEP     R4
        DW      EMIT
        LOAD    RD, CADDR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      EMITW
        LOAD    RD, CK0         ; POPX Rk0 .. R1
        LDN     RD
        PLO     R9
CL12:   GLO     R9
        LBZ     CL13
        LDI     73H
        SEP     R4
        DW      EMIT
        GLO     R9
        SEP     R4
        DW      EMIT
        DEC     R9
        LBR     CL12
CL13:   LOAD    RD, CWANT       ; its value: COPYXY RD -> Rk
        LDN     RD
        LBZ     CL99
        SEP     R4
        DW      PUSHK
        PLO     R8
        SEP     R4
        DW      EMITN
        DB      2, 23H, 00H
        GLO     R8
        ORI     0D0H
        SEP     R4
        DW      EMIT
CL99:   LOAD    RD, CVARS + 7   ; the outer one's back
        LDI     8
        PLO     RC
CL98:   IRX
        LDX
        STR     RD
        DEC     RD
        DEC     RC
        GLO     RC
        LBNZ    CL98
        SEP     R5
; BUILTIN: NKW = 11 print, 12 printu, 13 putc, 14 getc, 15 halt (the ( taken; CWANT)
BUILTIN: LOAD   RD, NKW
        LDN     RD
        XRI     11
        LBNZ    BI2
        SEP     R4
        DW      NOWANT
        LOAD    RD, TKIND       ; print("text")
        LDN     RD
        XRI     TSTR
        LBZ     BI1
        SEP     R4
        DW      ERRT
        DB      'print("text") expected',0
BI1:    LOAD    RD, SLEN        ; its room, the text there
        LDN     RD
        ADI     1
        PLO     RC
        LDI     0
        PHI     RC
        SEP     R4
        DW      DATA
        GLO     RC
        ADI     LOW(IMG)
        PLO     RA
        GHI     RC
        ADCI    HIGH(IMG)
        PHI     RA
        LOAD    RD, SLEN
        LDN     RD
        PLO     RB
        LOAD    RD, SBUF
BI1A:   GLO     RB
        LBZ     BI1B
        LDA     RD
        STR     RA
        INC     RA
        DEC     RB
        LBR     BI1A
BI1B:   GHI     RC              ; (RC kept on the stack)
        STXD
        GLO     RC
        STXD
        SEP     R4
        DW      NEXT
        LDI     ')'
        SEP     R4
        DW      NEEDOP
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        SEP     R4
        DW      LDRF
        LDI     0C1H
        SEP     R4
        DW      EMIT
        LDI     0FH
        LBR     EMIT
BI2:    LDN     RD              ; printu, putc: a value
        SMI     14
        LBDF    BI5
        SEP     R4
        DW      NOWANT
        LOAD    RD, NKW         ; (kept: a name in the value sets NKW)
        LDN     RD
        STXD
        LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        LDI     ')'
        SEP     R4
        DW      NEEDOP
        SEP     R4              ; 22 0k, K - 1
        DW      GETK
        PLO     R8
        SMI     1
        STR     RD
        LDI     22H
        SEP     R4
        DW      EMIT
        GLO     R8
        SEP     R4
        DW      EMIT
        IRX
        LDX
        XRI     13
        LBNZ    BI4
        LDI     0C9H            ; putc: SEROUT
        LBR     EMIT
BI4:    SEP     R4              ; printu: 24 6B 00 6E
        DW      EMITN
        DB      4, 24H, 6BH, 00H, 6EH
        SEP     R5
BI5:    LDI     ')'             ; getc, halt: ) first
        SEP     R4
        DW      NEEDOP
        LOAD    RD, NKW
        LDN     RD
        XRI     14
        LBNZ    BI7
        SEP     R4              ; getc: CB 21 0k
        DW      PUSHK
        PLO     R8
        LDI     0CBH
        SEP     R4
        DW      EMIT
        LDI     21H
        SEP     R4
        DW      EMIT
        GLO     R8
        SEP     R4
        DW      EMIT
        LOAD    RD, CWANT
        LDN     RD
        LBNZ    BI6
        LOAD    RD, K
        LDN     RD
        SMI     1
        STR     RD
BI6:    SEP     R5
BI7:    SEP     R4              ; halt: GAL 0004
        DW      NOWANT
        SEP     R4
        DW      EMITN
        DB      3, 0B0H, 00H, 04H
        SEP     R5
NOWANT: LOAD    RD, CWANT       ; (print, printu, putc, halt give no value)
        LDN     RD
        LBZ     NW9
        SEP     R4
        DW      ERRN
        DB      '() gives no value',0
NW9:    SEP     R5

; ==== statements (tsc's stmt / simple)
; STMT: one statement. Its SAT SEND STOP SSTEP SBODY (10 bytes) kept for the outer one on the stack
STMT:   LOAD    RD, SVARS
        LDI     10
        PLO     RC
SM0:    LDA     RD
        STXD
        DEC     RC
        GLO     RC
        LBNZ    SM0
        SEP     R4
        DW      STMT1
        LOAD    RD, SVARS + 9
        LDI     10
        PLO     RC
SM9:    IRX
        LDX
        STR     RD
        DEC     RD
        DEC     RC
        GLO     RC
        LBNZ    SM9
        SEP     R5
STMT1:  SEP     R4              ; K = 0, no flag
        DW      CLEARK
        LDI     '{'
        SEP     R4
        DW      TAKEOP
        LBDF    SB2
SB1:    LDI     '}'
        SEP     R4
        DW      TAKEOP
        LBNF    SB1Z
        LOAD    RD, TKIND
        LDN     RD
        LBNZ    SB1A
        SEP     R4
        DW      ERRT
        DB      '} expected',0
SB1A:   SEP     R4
        DW      STMT
        LBR     SB1
SB1Z:   SEP     R5
SB2:    LDI     ';'
        SEP     R4
        DW      TAKEOP
        LBNF    SB1Z
        LDI     KU16
        SEP     R4
        DW      TAKEKW
        LBDF    STIF
STD1:   SEP     R4              ; u16 x [= e], ... ;
        DW      NAME
        LDI     '['
        SEP     R4
        DW      ISOP
        LBDF    STD2
        SEP     R4
        DW      ERRT
        DB      'arrays are declared outside functions',0
STD2:   LDI     2
        PLO     RC
        LDI     0
        PHI     RC
        SEP     R4
        DW      DATA
        LOAD    RD, SAT
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LDI     'v'
        SEP     R4
        DW      ADD
        LDI     '='
        SEP     R4
        DW      TAKEOP
        LBDF    STD3
        SEP     R4
        DW      CLEARK
        LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        LOAD    RD, SAT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDI     1
        SEP     R4
        DW      STV
        SEP     R4
        DW      CLEARK
STD3:   LDI     ','
        SEP     R4
        DW      TAKEOP
        LBNF    STD1
        LDI     ';'
        LBR     NEEDOP
STIF:   LDI     KIF             ; if ( e ) s [else s]
        SEP     R4
        DW      TAKEKW
        LBDF    STWH
        SEP     R4
        DW      PAREN
        SEP     R4
        DW      TOJUMP
        LOAD    RD, SAT
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      STMT
        LDI     KELSE
        SEP     R4
        DW      TAKEKW
        LBDF    SI2
        LDI     0               ; B0 end; at -> here; s; end -> here
        PLO     RC
        PHI     RC
        LDI     0B0H
        SEP     R4
        DW      JMPW
        LOAD    RD, SEND
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      PATAT
        SEP     R4
        DW      STMT
        LOAD    RD, SEND
        LBR     PATRD
SI2:    LBR     PATAT
STWH:   LDI     KWHILE          ; while ( e ) s
        SEP     R4
        DW      TAKEKW
        LBDF    STFOR
        SEP     R4
        DW      HERE
        LOAD    RD, STOP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      PAREN
        SEP     R4
        DW      TOJUMP          ; the chain starts with it; continue: the top
        LOAD    RD, STOP
        SEP     R4
        DW      LOOPIN
        SEP     R4
        DW      STMT
        LOAD    RD, STOP
        SEP     R4
        DW      GALRD
        LBR     ENDLOOP
STFOR:  LDI     KFOR            ; for ( [simple] ; [e] ; [simple] ) s
        SEP     R4
        DW      TAKEKW
        LBDF    STBRK
        LDI     '('
        SEP     R4
        DW      NEEDOP
        LDI     ';'
        SEP     R4
        DW      ISOP
        LBNF    SF1
        SEP     R4
        DW      SIMPLE
SF1:    LDI     ';'
        SEP     R4
        DW      NEEDOP
        SEP     R4
        DW      HERE
        LOAD    RD, STOP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, SAT         ; the chain: none yet
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LDI     ';'
        SEP     R4
        DW      ISOP
        LBNF    SF2
        SEP     R4
        DW      CLEARK
        LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      TOJUMP
        LOAD    RD, SAT
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
SF2:    LDI     ';'
        SEP     R4
        DW      NEEDOP
        LDI     0               ; B0 body
        PLO     RC
        PHI     RC
        LDI     0B0H
        SEP     R4
        DW      JMPW
        LOAD    RD, SBODY
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4              ; step: here
        DW      HERE
        LOAD    RD, SSTEP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LDI     ')'
        SEP     R4
        DW      ISOP
        LBNF    SF3
        SEP     R4
        DW      SIMPLE
SF3:    LDI     ')'
        SEP     R4
        DW      NEEDOP
        LOAD    RD, STOP
        SEP     R4
        DW      GALRD
        LOAD    RD, SBODY       ; body -> here
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      HERE
        SEP     R4
        DW      PATCH
        LOAD    RD, SAT         ; the loop: the chain, continue: the step
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, SSTEP
        SEP     R4
        DW      LOOPIN
        SEP     R4
        DW      STMT
        LOAD    RD, SSTEP
        SEP     R4
        DW      GALRD
        LBR     ENDLOOP
STBRK:  LDI     KBREAK          ; break ;
        SEP     R4
        DW      TAKEKW
        LBDF    STCONT
        SEP     R4
        DW      LOOPAT          ; RA -> the loop (none: a mistake)
        LBDF    SBNO
        LDI     ';'
        SEP     R4
        DW      NEEDOP
        SEP     R4
        DW      LOOPAT
        LDA     RA
        PHI     RC
        LDN     RA
        PLO     RC
        DEC     RA
        GHI     RA
        STXD
        GLO     RA
        STXD
        LDI     0B0H
        SEP     R4
        DW      JMPW
        IRX
        LDXA
        PLO     RA
        LDX
        PHI     RA
        GHI     RC
        STR     RA
        INC     RA
        GLO     RC
        STR     RA
        SEP     R5
SBNO:   SEP     R4
        DW      ERRT
        DB      'break outside a loop',0
STCONT: LDI     KCONT           ; continue ;
        SEP     R4
        DW      TAKEKW
        LBDF    STRET
        SEP     R4
        DW      LOOPAT
        LBDF    SCNO
        LDI     ';'
        SEP     R4
        DW      NEEDOP
        SEP     R4
        DW      LOOPAT
        INC     RA
        INC     RA
        GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
        LBR     GALRD
SCNO:   SEP     R4
        DW      ERRT
        DB      'continue outside a loop',0
STRET:  LDI     KRET            ; return [e] ;
        SEP     R4
        DW      TAKEKW
        LBDF    STSIM
        LDI     ';'
        SEP     R4
        DW      ISOP
        LBNF    SR2
        SEP     R4
        DW      FNVAL
        LBNZ    SR1
        SEP     R4
        DW      ERRT
        DB      'a void function returns no value',0
SR1:    LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        SEP     R4              ; COPYXY Rk -> RD
        DW      GETK
        PLO     R8
        LDI     23H
        SEP     R4
        DW      EMIT
        LDI     00H
        SEP     R4
        DW      EMIT
        GLO     R8
        SHL
        SHL
        SHL
        SHL
        ORI     0DH
        SEP     R4
        DW      EMIT
        LBR     SR3
SR2:    SEP     R4
        DW      FNVAL
        LBZ     SR3
        SEP     R4
        DW      ERRT
        DB      'return: a value expected',0
SR3:    LDI     ';'
        SEP     R4
        DW      NEEDOP
        SEP     R4
        DW      EMITN
        DB      2, 0BEH, 00H
        SEP     R5
STSIM:  SEP     R4              ; simple ;
        DW      SIMPLE
        LDI     ';'
        LBR     NEEDOP
; PAREN: ( e )
PAREN:  LDI     '('
        SEP     R4
        DW      NEEDOP
        LDI     0
        SEP     R4
        DW      EXPR
        LDI     ')'
        LBR     NEEDOP
; PATAT: SAT's place -> here.  PATRD: the place at RD -> here
PATAT:  LOAD    RD, SAT
PATRD:  LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      HERE
        LBR     PATCH
; GALRD: B0 and the address at RD
GALRD:  LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDI     0B0H
        SEP     R4
        DW      EMIT
        LBR     EMITW
; CLEARK: K = 0, FLAG = 0FFH (no flag)
CLEARK: LOAD    RD, K
        LDI     0
        STR     RD
        LOAD    RD, FLAG
        LDI     0FFH
        STR     RD
        SEP     R5
; FNVAL: D = 1 if the function being compiled gives a value
FNVAL:  LOAD    RD, FN
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GLO     RA
        ADI     20
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LDN     RA
        SEP     R5
; LOOPIN: a loop in: its chain RC, its continue target the word at RD
LOOPIN: LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LOAD    RD, LSP
        LDN     RD
        XRI     16
        LBNZ    LI0X
        SEP     R4
        DW      ERRT
        DB      'loops 16 deep',0
LI0X:   LDN     RD
        ADI     1
        STR     RD
        SMI     1
        SHL
        SHL
        ADI     LOW(LOOPS)
        PLO     RA
        LDI     HIGH(LOOPS)
        PHI     RA
        GHI     RC
        STR     RA
        INC     RA
        GLO     RC
        STR     RA
        INC     RA
        GHI     R8
        STR     RA
        INC     RA
        GLO     R8
        STR     RA
        SEP     R5
; LOOPAT: RA -> the innermost loop's record; DF = 1 none
LOOPAT: LOAD    RD, LSP
        LDN     RD
        LBZ     NO
        SMI     1
        SHL
        SHL
        ADI     LOW(LOOPS)
        PLO     RA
        LDI     HIGH(LOOPS)
        PHI     RA
        LBR     YES
; ENDLOOP: the loop out; its chain (the false jump, breaks) -> here
ENDLOOP: SEP    R4
        DW      LOOPAT
        LDA     RA
        PHI     RC
        LDN     RA
        PLO     RA
        GHI     RC
        PHI     RA
        LOAD    RD, LSP
        LDN     RD
        SMI     1
        STR     RD
        LBR     PATCHPC

; SIMPLE: x = e, x op= e, x++, x--, a[i] ..., f(...)
SIMPLE: SEP     R4
        DW      CLEARK
        SEP     R4
        DW      NAME
        LDI     '('
        SEP     R4
        DW      ISOP
        LBDF    SP1
        LDI     0
        LBR     CALL
SP1:    SEP     R4
        DW      FIND
        LBDF    SPNOV
        SEP     R4
        DW      ENTKIND
        PLO     RE
        LOAD    RD, SADDR
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, SKIND
        GLO     RE
        STR     RD
        XRI     'v'
        LBZ     SP3
        LDN     RD
        XRI     'a'
        LBZ     SP2
SPNOV:  SEP     R4
        DW      ERRN
        DB      ' is not a variable',0
SP2:    LDI     '['             ; a[i]: R1 = the element's address (50 11 01 52 01 base)
        SEP     R4
        DW      NEEDOP
        LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        LDI     ']'
        SEP     R4
        DW      NEEDOP
        SEP     R4
        DW      EMITN
        DB      5, 50H, 11H, 01H, 52H, 01H
        LOAD    RD, SADDR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      EMITW
SP3:    LDI     '='
        SEP     R4
        DW      TAKEOP
        LBDF    SP4
        LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        LBR     SSAVE
SP4:    LOAD    RD, TKIND       ; ++ -- op=
        LDN     RD
        XRI     TOP
        LBNZ    SPEQ
        LOAD    RD, TOPC
        LDN     RD
        SMI     O_INC
        LBNF    SPEQ
        SMI     10
        LBDF    SPEQ
        LDN     RD
        PLO     RE
        LOAD    RD, SOP
        GLO     RE
        STR     RD
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PUSHK
        SEP     R4
        DW      SLOAD
        LOAD    RD, SOP
        LDN     RD
        XRI     O_INC
        LBZ     SP5
        LDN     RD
        XRI     O_DEC
        LBNZ    SP6
        LDI     43H
        LSKP
SP5:    LDI     42H
        SEP     R4
        DW      EMIT
        SEP     R4
        DW      GETK
        SEP     R4
        DW      EMIT
        LBR     SSAVE
SP6:    LDI     0
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      VALUE
        SEP     R4              ; b = K, a = b - 1, K = a
        DW      GETK
        PLO     R8
        SMI     1
        STR     RD
        PHI     R8
        LOAD    RD, SOP         ; the op's character
        LDN     RD
        SMI     88H
        ADI     LOW(OPEQT)
        PLO     RA
        LDI     HIGH(OPEQT)
        ADCI    0
        PHI     RA
        LDN     RA
        SEP     R4
        DW      BINOP
        LBR     SSAVE
SPEQ:   SEP     R4
        DW      ERRT
        DB      '= expected',0
OPEQT:  DB      '+', '-', '*', '/', '%', '&', '|', '^'
; SLOAD: the variable (or a[i]) -> Rk.  SSAVE: R1 (or R2 at a[i]) -> it
SLOAD:  LOAD    RD, SKIND
        LDN     RD
        XRI     'a'
        LBNZ    SL1
        SEP     R4
        DW      EMITN
        DB      3, 39H, 02H, 12H
        SEP     R5
SL1:    LOAD    RD, SADDR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      GETK
        LBR     LDV
SSAVE:  LOAD    RD, SKIND
        LDN     RD
        XRI     'a'
        LBNZ    SS1
        SEP     R4
        DW      EMITN
        DB      3, 3AH, 02H, 21H
        SEP     R5
SS1:    LOAD    RD, SADDR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDI     1
        LBR     STV

; ==== the program: consts, globals, functions; then F0 00 00 and the .STL's first sector
PROGRAM: SEP    R4              ; CD BD 00 00 00
        DW      EMITN
        DB      5, 0CDH, 0BDH, 0, 0, 0
PG1:    LOAD    RD, TKIND
        LDN     RD
        LBZ     PG9
        LDI     KCONST
        SEP     R4
        DW      TAKEKW
        LBDF    PG2
        SEP     R4              ; const NAME = constant ;
        DW      NAME
        LDI     '='
        SEP     R4
        DW      NEEDOP
        SEP     R4
        DW      CEXPR
        LDI     'c'
        SEP     R4
        DW      ADD
        LDI     ';'
        SEP     R4
        DW      NEEDOP
        LBR     PG1
PG2:    LDI     KVOID
        SEP     R4
        DW      TAKEKW
        LBDF    PG3
        SEP     R4
        DW      NAME
        LDI     0
        SEP     R4
        DW      FUNCTION
        LBR     PG1
PG3:    LDI     KU16
        SEP     R4
        DW      TAKEKW
        LBNF    PG4
        SEP     R4
        DW      ERRT
        DB      'u16, void or const expected',0
PG4:    SEP     R4
        DW      NAME
        LDI     '('
        SEP     R4
        DW      ISOP
        LBDF    PG5
        LDI     1
        SEP     R4
        DW      FUNCTION
        LBR     PG1
PG5:    LDI     '['             ; a global: an array, or a variable [= constant]
        SEP     R4
        DW      TAKEOP
        LBDF    PG6
        SEP     R4
        DW      CEXPR
        GLO     RC              ; 1-2000 (07D0H)
        STR     R2
        GHI     RC
        OR
        LBZ     PGBIG
        GLO     RC
        SMI     0D1H
        GHI     RC
        SMBI    07H
        LBDF    PGBIG
        GLO     RC              ; x 2
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GHI     RC
        STXD
        GLO     RC
        STXD
        LDI     ']'
        SEP     R4
        DW      NEEDOP
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        SEP     R4
        DW      DATA
        LDI     'a'
        SEP     R4
        DW      ADD
        LBR     PG8
PGBIG:  SEP     R4
        DW      ERRT
        DB      'an array of 1-2000 expected',0
PG6:    LDI     2
        PLO     RC
        LDI     0
        PHI     RC
        SEP     R4
        DW      DATA
        GHI     RC
        STXD
        GLO     RC
        STXD
        LDI     'v'
        SEP     R4
        DW      ADD
        LDI     '='
        SEP     R4
        DW      TAKEOP
        LBDF    PG7
        SEP     R4              ; = constant: into the block
        DW      CEXPR
        IRX
        LDXA
        PLO     RA
        LDX
        PHI     RA
        SEP     R4
        DW      PATCH
        LBR     PG8
PG7:    IRX
        IRX
PG8:    LDI     ','
        SEP     R4
        DW      TAKEOP
        LBDF    PG8A
        SEP     R4
        DW      NAME
        LBR     PG5
PG8A:   LDI     ';'
        SEP     R4
        DW      NEEDOP
        LBR     PG1
PG9:    LOAD    RA, SMAIN       ; main()?
        LOAD    RD, NBUF
        LDI     16
        PLO     RC
PG9A:   LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    PG9A
        SEP     R4
        DW      FIND
        LBDF    PGNOM
        SEP     R4
        DW      ENTKIND
        XRI     'f'
        LBZ     PG10
PGNOM:  SEP     R4
        DW      ERRT
        DB      'no main()',0
PG10:   SEP     R4
        DW      EMITN
        DB      3, 0F0H, 00H, 00H
        LOAD    RA, STLHD       ; the first sector: STL1, 9 blocks
        LOAD    RD, HDR
        LDI     23
        PLO     RC
PG11:   LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    PG11
        SEP     R5
STLHD:  DB      'STL1', 9, 40H, 0, 42H, 0, 44H, 0, 46H, 0, 48H, 0, 4AH, 0, 50H, 0, 60H, 0, 70H, 0
SMAIN:  DB      'main', 0,0,0,0,0,0,0,0,0,0,0,0
; FUNCTION: NBUF = its name, D = 1 if it gives a value: ( u16 p, ... ) { ... }
FUNCTION: PLO   RE
        LOAD    RD, FVAL
        GLO     RE
        STR     RD
        LOAD    RA, NBUF        ; its name kept (the parameters' go through NBUF)
        LOAD    RD, FNAMEB
        LDI     16
        PLO     RC
FU0:    LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    FU0
        LDI     '('
        SEP     R4
        DW      NEEDOP
        LOAD    RD, PCNT
        LDI     0
        STR     RD
        LDI     ')'
        SEP     R4
        DW      ISOP
        LBNF    FU3
FU1:    LDI     KU16
        SEP     R4
        DW      NEEDKW
        SEP     R4
        DW      NAME
        LOAD    RD, PCNT        ; NBUF -> PNAMES[PCNT] (8 at most)
        LDN     RD
        XRI     8
        LBNZ    FU1A
        SEP     R4
        DW      ERRT
        DB      'more than 8 parameters',0
FU1A:   LDN     RD
        ADI     1
        STR     RD
        SMI     1
        SHL
        SHL
        SHL
        SHL
        ADI     LOW(PNAMES)
        PLO     RD
        LDI     HIGH(PNAMES)
        ADCI    0
        PHI     RD
        LOAD    RA, NBUF
        LDI     16
        PLO     RC
FU2:    LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    FU2
        LDI     ','
        SEP     R4
        DW      TAKEOP
        LBNF    FU1
FU3:    LDI     ')'
        SEP     R4
        DW      NEEDOP
        LOAD    RD, PCNT        ; pbase: their room (none: DTOP)
        LDN     RD
        SHL
        PLO     RC
        LDI     0
        PHI     RC
        GLO     RC
        LBZ     FU4
        SEP     R4
        DW      DATA
        LBR     FU5
FU4:    LOAD    RD, DTOP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
FU5:    LOAD    RD, FPB
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RA, FNAMEB      ; the function: NBUF = its name, value = PC
        LOAD    RD, NBUF
        LDI     16
        PLO     RC
FU6:    LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    FU6
        SEP     R4
        DW      HERE
        LDI     'f'
        SEP     R4
        DW      ADD             ; RA -> its entry
        GLO     RA
        ADI     19
        PLO     RD
        GHI     RA
        ADCI    0
        PHI     RD
        LOAD    RF, PCNT
        LDN     RF
        STR     RD
        INC     RD
        LOAD    RF, FVAL
        LDN     RF
        STR     RD
        INC     RD
        LOAD    RF, FPB
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        LOAD    RD, FN          ; FN = it; NGLOB = the names' end
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, SYME
        LOAD    RF, NGLOB
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RA, SMAIN       ; main: CALL main's address (at 2)
        SEP     R4
        DW      NAMEQN
        LBDF    FU7
        LOAD    RA, 2
        SEP     R4
        DW      HERE
        SEP     R4
        DW      PATCH
FU7:    LDI     0               ; the parameters: names, pbase + 2j
        PLO     R9
FU8:    LOAD    RD, PCNT
        LDN     RD
        STR     R2
        GLO     R9
        XOR
        LBZ     FU9
        GLO     R9
        SHL
        SHL
        SHL
        SHL
        ADI     LOW(PNAMES)
        PLO     RA
        LDI     HIGH(PNAMES)
        ADCI    0
        PHI     RA
        LOAD    RD, NBUF
        LDI     16
        PLO     RC
FU8A:   LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    FU8A
        GLO     R9
        SHL
        STR     R2
        LOAD    RD, FPB + 1
        LDN     RD
        ADD
        PLO     RC
        DEC     RD
        LDN     RD
        ADCI    0
        PHI     RC
        GLO     R9
        STXD
        LDI     'v'
        SEP     R4
        DW      ADD
        IRX
        LDX
        PLO     R9
        INC     R9
        LBR     FU8
FU9:    LDI     '{'
        SEP     R4
        DW      ISOP
        LBNF    FU10
        SEP     R4
        DW      ERRT
        DB      '{ expected',0
FU10:   SEP     R4
        DW      STMT
        SEP     R4
        DW      EMITN
        DB      2, 0BEH, 00H
        LOAD    RD, NGLOB       ; its locals gone
        LOAD    RF, SYME
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, FN
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R5
; NAMEQN: the 16 bytes at RA = FNAMEB? DF = 0
NAMEQN: LOAD    RD, FNAMEB
        LDI     16
        PLO     RB
NQN1:   LDA     RA
        STR     R2
        LDA     RD
        XOR
        LBNZ    NO
        DEC     RB
        GLO     RB
        LBNZ    NQN1
        LBR     YES

SSC:    DB      '.SC',0
SSTL:   DB      '.STL',0
PEND:
VARS:
JMPV:   DS      3
ON11:   DS      11
FN11:   DS      11
CUR:    DS      1
NXT:    DS      1
CRF:    DS      1
SREM:   DS      2
SPTR:   DS      2
LINE:   DS      2
TKIND:  DS      1
TVAL:   DS      2
TOPC:   DS      1
KW:     DS      1
NKW:    DS      1
SLEN:   DS      1
PC:     DS      2
DTOP:   DS      2
K:      DS      1
FLAG:   DS      1
SYME:   DS      2
NGLOB:  DS      2
FN:     DS      2
ELVL:   DS      1
EOP:    DS      1
LLVL:   DS      1
LCHAIN: DS      2
LK:     DS      1
LEND:   DS      2
CVARS:
CWANT:  DS      1
CADDR:  DS      2
CPB:    DS      2
CN:     DS      1
CK0:    DS      1
CJ:     DS      1
SVARS:
SAT:    DS      2
SEND:   DS      2
STOP:   DS      2
SSTEP:  DS      2
SBODY:  DS      2
SKIND:  DS      1
SADDR:  DS      2
SOP:    DS      1
LSP:    DS      1
FVAL:   DS      1
FPB:    DS      2
PCNT:   DS      1
VEND:
        END
