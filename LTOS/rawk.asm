; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; rawk.asm - RAWK.PRG: RAWK [-F c] [-v x=val] [-o file] 'program' names (or -f PROG.AWK names) - awk for LTOS,
;   phases 1 and 2 (PLANS/LTOS-AWK.md), whole numbers. The program (in single quotes, as on Linux, or a file) is
;   turned once into steps for a small value-stack machine - BEGIN's, the main rules', END's, all in one buffer
;   (STEPB), each a chain of pieces - then the main ones run for each line of the files: NR, FNR, NF, $0, $1 ..
;   $NF, FILENAME, FS, OFS. Numbers are 32 bits (whole); a value is a number, a text, or a text that looks like a
;   number (a field: compared as a number, printed as it is) - as awk's. Statements: { } if else while do for
;   break continue next exit print printf; substr index toupper tolower length; /.../ and ~ take ^ $ . * + ?
;   [...] \c. Names: paths or patterns by DIR's rules. Lines are LF-ended (CR dropped); past 250 characters a line
;   is cut. A screen at a time (Q stops).  -o NAME: what it prints goes into the file NAME instead ("replace it?"
;   if it is there), written a sector at a time like XFER's; anything going wrong: nothing saved.
;   Memory: the code, then (CBEG .. PEND) the compiler - once the program is compiled, the buffers for running it
;   (VARS, LBUF, FLDS, VSTK, FLBUF, VHEAP) go on top of it; while it compiles, $7700-$7BFF holds the program's
;   text, the names, the holes and the loops (OBUF and TMPH's once it runs). RE.1 is the BIOS's: never touched.
;
;       RAWK '{s += $3} END {print s}' SALES.TXT          RAWK -F, '$2 > 100 {print $1}' DATA.CSV
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
FLMAX   EQU     60
LMAX    EQU     250
VMAX    EQU     40              ; variables (NR NF FNR FILENAME FS OFS are 0-5)
VSTKN   EQU     40              ; the value stack's entries (5 bytes: type, then 4)
PSRCN   EQU     623             ; the program's text (PSRC, while it is compiled)
CONN    EQU     400             ; the program's texts ("..." and /.../)
TMPN    EQU     768            ; texts made while a rule runs (joined, numbers as text)
OBUF    EQU     7700H           ; -o: the file's next sector - and TMPH: in $7700-$7BFF, the RAM above LTOS's
TMPH    EQU     7900H           ;  buffers (STLRX.PRG's only while RECV takes a STELLAR app)
TMPE    EQU     TMPH + TMPN
VHN     EQU     1024            ; the variables' texts
STEPN   EQU     1280            ; the steps (whole pages)
PSRC    EQU     7700H           ; while the program is compiled, $7700-$7BFF (OBUF and TMPH's once it runs) holds
VNAMES  EQU     PSRC + PSRCN + 1        ;  its text, its variables' names (12 bytes each), the holes and
VNAMEE  EQU     VNAMES + VMAX * 12      ;  the loops open
HOLES   EQU     VNAMEE
HOLESE  EQU     HOLES + 128
LOOPS   EQU     HOLESE
LOOPSE  EQU     LOOPS + 6 * 8
; a value's type
TUN     EQU     0               ; not set yet: 0 and ""
TNUM    EQU     1               ; a number: 4 bytes, big-endian
TSTR    EQU     2               ; a text: where (2), its length (1)
TSN     EQU     3               ; a text that looks like a number (a field)
TFLD    EQU     4               ; a field not looked at yet: TSN or TSTR, decided when it matters (CLASS)
; the tokens
TEOF    EQU     0
TNUMT   EQU     1
TSTRT   EQU     2
TERE    EQU     3
TNAME   EQU     4
TBEGIN  EQU     5
TEND    EQU     6
TPRINT  EQU     7
TLEN    EQU     8
TDOL    EQU     9
TLP     EQU     10
TRP     EQU     11
TLB     EQU     12
TRB     EQU     13
TSEMI   EQU     14
TCOMMA  EQU     15
TNOT    EQU     16
TPLUS   EQU     17
TMINUS  EQU     18
TSTAR   EQU     19
TSLASH  EQU     20
TPCT    EQU     21
TLT     EQU     22              ; TLT .. TNE: in the order of OLT .. ONEQ
TLE     EQU     23
TGT     EQU     24
TGE     EQU     25
TEQ     EQU     26
TNE     EQU     27
TASG    EQU     28
TADDA   EQU     29              ; TADDA .. TMODA: in the order of OADD .. OMOD
TSUBA   EQU     30
TMULA   EQU     31
TDIVA   EQU     32
TMODA   EQU     33
TINC    EQU     34
TDEC    EQU     35
TAND    EQU     36
TOR     EQU     37
TMAT    EQU     38
TNMAT   EQU     39
TNL     EQU     40              ; a line's end (in a -f file): ends a statement, as ; does
TIF     EQU     41
TELSE   EQU     42
TWHILE  EQU     43
TFOR    EQU     44
TDO     EQU     45
TBREAK  EQU     46
TCONT   EQU     47
TNEXT   EQU     48
TEXIT   EQU     49
TPRINTF EQU     50
TFN     EQU     51              ; substr, index, toupper, tolower (TOKV+3: its step)
; the steps (DTAB's order)
ORET    EQU     0
OPUSHN  EQU     1               ; + 4 bytes
OPUSHS  EQU     2               ; + where (2), length
OGETV   EQU     3               ; + the variable
OSETV   EQU     4               ; + the variable (the value stays)
OFIELD  EQU     5
OPOP    EQU     6
OADD    EQU     7
OSUB    EQU     8
OMUL    EQU     9
ODIV    EQU     10
OMOD    EQU     11
ONEG    EQU     12
OUPLUS  EQU     13
ONOT    EQU     14
OLT     EQU     15
OLE     EQU     16
OGT     EQU     17
OGE     EQU     18
OEQ     EQU     19
ONEQ    EQU     20
OCAT    EQU     21
OMATCH  EQU     22
OJF     EQU     23              ; + where (2)
OJT     EQU     24
OJ      EQU     25
OPRINT  EQU     26              ; + how many
OLEN    EQU     27
OINCV   EQU     28              ; + the variable
ODECV   EQU     29
OPINC   EQU     30
OPDEC   EQU     31
OPUSH0  EQU     32
OPUSH1  EQU     33
ONEXT   EQU     34
OEXIT   EQU     35
OPRINTF EQU     36              ; + how many
OSUBSTR EQU     37              ; + how many (2 or 3)
OINDEX  EQU     38
OTOUP   EQU     39
OTOLOW  EQU     40
OPUSHV  EQU     41              ; + where (2), length: a -v value (a text that may look like a number)

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
        LOAD    RD, ZBEG        ; every variable from ZBEG to ZEND: 0 (DS is not cleared at the load)
        LOAD    RC, ZEND - ZBEG
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST1
        GHI     RC
        LBNZ    ST1
        LOAD    RD, NVARS
        LDI     6
        STR     RD
        LOAD    RD, TOKP        ; (a mistake in -v: " near: " and nothing)
        LDI     HIGH(KONE)
        STR     RD
        INC     RD
        LDI     LOW(KONE)
        STR     RD
        LOAD    RD, SHOLE       ; each part's steps start at its SENT
        LDI     HIGH(SENT)
        STR     RD
        INC     RD
        LDI     LOW(SENT)
        STR     RD
        INC     RD
        LDI     HIGH(SENT + 2)
        STR     RD
        INC     RD
        LDI     LOW(SENT + 2)
        STR     RD
        INC     RD
        LDI     HIGH(SENT + 4)
        STR     RD
        INC     RD
        LDI     LOW(SENT + 4)
        STR     RD
        LOAD    RD, LOOPSP
        LDI     HIGH(LOOPS)
        STR     RD
        INC     RD
        LDI     LOW(LOOPS)
        STR     RD
        LOAD    RD, HOLESP
        LDI     HIGH(HOLES)
        STR     RD
        INC     RD
        LDI     LOW(HOLES)
        STR     RD
        LOAD    RD, CONP
        LDI     HIGH(CONB)
        STR     RD
        INC     RD
        LDI     LOW(CONB)
        STR     RD
        LOAD    RD, VHP
        LDI     HIGH(VHEAP)
        STR     RD
        INC     RD
        LDI     LOW(VHEAP)
        STR     RD
        LOAD    RD, CURK        ; no part yet
        LDI     0FFH
        STR     RD
        LOAD    RD, EMP
        LDI     HIGH(STEPB)
        STR     RD
        INC     RD
        LDI     LOW(STEPB)
        STR     RD
        LOAD    RD, EML
        LDI     HIGH(STEPE)
        STR     RD
; ---- the flags: -F c (or -Fc, -F 'c'; -Ft and -F '\t' a tab)
AR1:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        XRI     '-'
        LBNZ    AR5
        INC     RF
        LDA     RF
        XRI     'F'
        LBZ     AF1
        XRI     'F' XOR 'o'
        LBZ     AO1
        XRI     'o' XOR 'f'
        LBZ     AFF
        XRI     'f' XOR 'v'
        LBZ     AV1
        LBR     USE
AF1:    LDN     RF
        LBZ     USE
        XRI     ' '
        LBNZ    AF2
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
AF2:    LDN     RF
        XRI     27H
        LBNZ    AF3
        INC     RF
AF3:    LDA     RF
        PLO     RB
        XRI     't'
        LBNZ    AF4
        LDI     9
        PLO     RB
AF4:    GLO     RB
        XRI     5CH
        LBNZ    AF5
        LDN     RF
        XRI     't'
        LBNZ    AF5
        INC     RF
        LDI     9
        PLO     RB
AF5:    LDN     RF
        XRI     27H
        LBNZ    AF6
        INC     RF
AF6:    LOAD    RD, FSB         ; (FS = it once the program is compiled)
        GLO     RB
        STR     RD
        LBR     AR1
AO1:    SEP     R4              ; -o NAME: ONAME, OWDIR (a path: its folder)
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        XRI     27H             ; (no name: the program came next)
        LBZ     USE
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_FNAME
        LOAD    RC, ONAME
        LDI     11
        PLO     RB
AO2:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    AO2
        LOAD    RD, KS_WDIR
        LOAD    RC, OWDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, OMODE
        LDI     1
        STR     RD
        LBR     AR1
AFF:    SEP     R4              ; -f NAME: the program from that file (into PSRC)
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        GHI     RF              ; (the line's rest)
        STXD
        GLO     RF
        STXD
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    AFNO
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    AFNO
        SEP     R4
        DW      KS_FOPEN
        LOAD    RA, PSRC
        LOAD    RB, PSRCN
AFF1:   LOAD    RD, GLSAV       ; a sector (FREAD uses most registers)
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
        SEP     R4
        DW      KS_FREAD        ; -> RC bytes at KS_DATBUF; DF = 1: no more
        LOAD    RD, GLSAV
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LBDF    AFF9
        LOAD    RF, KS_DATBUF
AFF2:   GHI     RC
        LBNZ    AFF3
        GLO     RC
        LBZ     AFF1
AFF3:   GHI     RB
        LBNZ    AFF4
        GLO     RB
        LBZ     AFLONG
AFF4:   LDA     RF
        STR     RA
        INC     RA
        DEC     RB
        DEC     RC
        LBR     AFF2
AFF9:   LDI     0
        STR     RA
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LOAD    RD, GOTF
        LDI     1
        STR     RD
        LBR     AR1
AFNO:   SEP     R4
        DW      EMSGR
        DB      'cannot find the program file',0
AFLONG: SEP     R4
        DW      EMSGR
        DB      'the program file is too long (623 at most)',0
AV1:    SEP     R4              ; -v name=value: the variable set before BEGIN ('name=value' too)
        DW      K_SKIPSP
        LOAD    RD, AVQ
        LDI     0
        STR     RD
        LDN     RF
        XRI     27H
        LBNZ    AV1A
        INC     RF
        LDI     1
        STR     RD
AV1A:   LOAD    RD, NBUF
        LDI     0
        PLO     RB
AV2:    LDN     RF
        LBZ     AVBAD
        XRI     '='
        LBZ     AV3
        XRI     '=' XOR ' '
        LBZ     AVBAD
        GLO     RB
        XRI     11
        LBZ     AVBAD
        LDA     RF
        STR     RD
        INC     RD
        INC     RB
        LBR     AV2
AV3:    INC     RF
        LDI     0
        STR     RD
        GLO     RB
        LBZ     AVBAD
        GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      KWLOOK
        LBDF    AV3B
        GHI     RB              ; a word of awk's: FS and OFS only
        XRI     1
        LBNZ    AVBAD
        GLO     RB
        SMI     4
        LBNF    RDO1
        LBR     AV3C
AV3B:   SEP     R4
        DW      VFIND
        LBDF    LXMANY
AV3C:   IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        GLO     RB
        STXD                    ; the variable
        SEP     R4              ; the value -> CONB: to a space, or in '...'; \t \n
        DW      CONBEG
        LOAD    RD, AVQ
        LDN     RD
        PLO     RD              ; RD.0 = 1: in quotes (CONPUT keeps RD)
        LBNZ    AV4
        LDN     RF
        XRI     27H
        LBNZ    AV4
        INC     RF
        LDI     1
        PLO     RD
AV4:    LDN     RF
        LBZ     AV8
        GLO     RD
        LBZ     AV4A
        LDN     RF
        XRI     27H
        LBNZ    AV5
        INC     RF
        LBR     AV8
AV4A:   LDN     RF
        XRI     ' '
        LBZ     AV8
AV5:    LDA     RF
        XRI     5CH
        LBNZ    AV6
        LDN     RF
        LBZ     AV6B
        LDA     RF
        XRI     't'
        LBNZ    AV5A
        LDI     9
        LBR     AV7
AV5A:   XRI     't' XOR 'n'
        LBNZ    AV5B
        LDI     0AH
        LBR     AV7
AV5B:   DEC     RF
        LDA     RF
        LBR     AV7
AV6B:   LDI     5CH
        LBR     AV7
AV6:    XRI     5CH
AV7:    SEP     R4
        DW      CONPUT
        LBR     AV4
AV8:    SEP     R4
        DW      CONEND
        LOAD    RD, GLSAV       ; (the line's rest: SELBUF and EMIT1 use RF)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDI     0               ; BEGIN's first steps: the value into the variable
        SEP     R4
        DW      SELBUF
        LDI     OPUSHV
        SEP     R4
        DW      EPUSHX
        LDI     OSETV
        SEP     R4
        DW      EMIT1
        IRX
        LDX
        SEP     R4
        DW      EMIT1
        LDI     OPOP
        SEP     R4
        DW      EMIT1
        LOAD    RD, GLSAV
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LBR     AR1
AVBAD:  SEP     R4
        DW      EMSGR
        DB      '-v takes name=value',0
; ---- the program -> PSRC (0-ended): in single quotes, or one word
AR5:    LOAD    RD, GOTF        ; -f gave the program: the rest are names
        LDN     RD
        LBNZ    AP9N
        LDN     RF
        LBZ     USE
        LOAD    RD, PSRC
        LDI     255             ; (the command line is shorter)
        PLO     RB
        LDN     RF
        XRI     27H
        LBNZ    AP4
        INC     RF
AP1:    LDA     RF
        LBZ     APNC
        XRI     27H
        LBZ     AP9
        XRI     27H
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    AP1
        LBR     USE
APNC:   SEP     R4
        DW      EMSGR
        DB      'the program',27H,'s ',27H,' is not closed',0
AP4:    LDN     RF
        LBZ     AP9
        XRI     ' '
        LBZ     AP9
        LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    AP4
        LBR     USE
AP9:    LDI     0
        STR     RD
AP9N:   LOAD    RD, NAMES       ; the names: after it
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
; ---- compile: the program into STEPB, each part's chain ended with ORET
        LOAD    RD, SRCP
        LDI     HIGH(PSRC)
        STR     RD
        INC     RD
        LDI     LOW(PSRC)
        STR     RD
        SEP     R4
        DW      PPROG
        LDI     0
        SEP     R4
        DW      SELBUF
        LDI     ORET
        SEP     R4
        DW      EMIT1
        LDI     1
        SEP     R4
        DW      SELBUF
        LDI     ORET
        SEP     R4
        DW      EMIT1
        LDI     2
        SEP     R4
        DW      SELBUF
        LDI     ORET
        SEP     R4
        DW      EMIT1
; ---- the variables (on top of the compiler, no longer needed): all 0; FS and OFS " ", or FS = -F's
        LOAD    RD, VARS
        LOAD    RC, VMAX * 8
VZ1:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    VZ1
        GHI     RC
        LBNZ    VZ1
        LOAD    RD, VARS + 4 * 8
        SEP     R4
        DW      SETSP
        LOAD    RD, VARS + 5 * 8
        SEP     R4
        DW      SETSP
        LOAD    RD, FSB
        LDN     RD
        LBZ     VZ2
        LOAD    RD, VARS + 4 * 8 + 2    ; FS -> FSB
        LDI     LOW(FSB)
        STR     RD
        DEC     RD
        LDI     HIGH(FSB)
        STR     RD
VZ2:
; ---- the files (with main rules or END); -o's file; BEGIN; the files; END; -o's file saved
        LOAD    RD, HASMAIN
        LDN     RD
        LBNZ    RF0
        INC     RD              ; (HASEND)
        LDN     RD
        LBNZ    RF0
        LBR     RB0             ; BEGIN alone: no files
RF0:    LOAD    RD, NEEDF
        LDI     1
        STR     RD
        LOAD    RD, NAMES
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    RF1
        SEP     R4
        DW      EMSG
        DB      'name the files to read',0DH,0AH,0
        LBR     USE
RF1:    SEP     R4
        DW      FLIST
        LOAD    RD, FLN
        LDN     RD
        LBNZ    RB0
        SEP     R4
        DW      K_PIN
        DB      'No file matches.',0DH,0AH,0
        SEP     R5
RB0:    LOAD    RD, OMODE
        LDN     RD
        LBZ     RB1
        SEP     R4
        DW      OOPEN
RB1:    LOAD    RD, SENT        ; BEGIN
        SEP     R4
        DW      RUNS
        LOAD    RD, EXITF       ; exit in BEGIN: on to END
        LDN     RD
        LBNZ    GEND
        LOAD    RD, NEEDF
        LDN     RD
        LBZ     GEND
GF0:    LOAD    RD, FI
        LDI     0
        STR     RD
; ---- each file, a line at a time: LBUF (LLEN); FNR, FILENAME
GF1:    LOAD    RD, FI
        LDN     RD
        PLO     RC
        SEP     R4
        DW      FLGET
        LOAD    RF, NAMEP
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        SEP     R4
        DW      KS_FINDN
        LBDF    GFN
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, NAMEP       ; FILENAME: NAME.EXT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RF, FNTXT
        SEP     R4
        DW      NM2TX
        GLO     RF
        SMI     LOW(FNTXT)
        STR     R2
        LOAD    RD, FNLEN
        LDN     R2
        STR     RD
        LOAD    RD, FNRV        ; FNR, SREM: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, SREM
        LDI     0
        STR     RD
        INC     RD
        STR     RD
GL1:    SEP     R4              ; each line
        DW      GLINE
        LBDF    GFN
        SEP     R4
        DW      RECORD
        LOAD    RD, EXITF       ; exit: on to END
        LDN     RD
        LBNZ    GEND
        LBR     GL1
GFN:    LOAD    RD, FI          ; the next file
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, FLN
        LDN     RD
        SM
        LBNZ    GF1
GEND:   LOAD    RD, SENT + 4    ; END
        SEP     R4
        DW      RUNS
        LOAD    RD, OMODE
        LDN     RD
        LBZ     GE9
        SEP     R4
        DW      OCLOSE
GE9:    SEP     R5

; RECORD: a line has ended - NR, FNR + 1, its fields, the main rules; LLEN = 0
RECORD: LOAD    RD, NRV
        SEP     R4
        DW      INC32
        LOAD    RD, FNRV
        SEP     R4
        DW      INC32
        SEP     R4
        DW      SPLIT
        LOAD    RD, HASMAIN
        LDN     RD
        LBZ     RC9
        LOAD    RD, SENT + 2
        LBR     RUNS
RC9:    SEP     R5

; GLINE: the open file's next line -> LBUF, LLEN (LF-ended, CR dropped, past LMAX cut). DF = 1: the file
;        has ended (LBUF, LLEN, the fields: still the last line's - END sees it). A sector at a time: KS_FREAD.
GLINE:  LOAD    RD, LLEN        ; (the last line's length, if nothing more comes)
        LDN     RD
        PHI     RB
        LDI     0
        PLO     RB              ; RB.0 = this one's
        LOAD    RD, SPTR
        LDA     RD
        PHI     RF
        LDA     RD
        PLO     RF
        LDA     RD              ; (SREM follows SPTR)
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RA, LBUF
GN1:    GHI     RC
        LBNZ    GN2
        GLO     RC
        LBNZ    GN2
        LOAD    RD, GLSAV       ; the next sector (FREAD uses most registers)
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
        SEP     R4
        DW      KS_FREAD        ; -> RC bytes at KS_DATBUF; DF = 1: no more
        LOAD    RD, GLSAV
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LBDF    GNEND
        LOAD    RF, KS_DATBUF
        LBR     GN1
GN2:    LDA     RF
        DEC     RC
        XRI     0DH
        LBZ     GN1
        XRI     0DH XOR 0AH
        LBZ     GN9
        GLO     RB
        XRI     LMAX
        LBZ     GN1
        DEC     RF
        LDA     RF
        STR     RA
        INC     RA
        INC     RB
        LBR     GN1
GNEND:  LDI     0               ; the end: a last line with no LF?
        PHI     RC
        PLO     RC
        GLO     RB
        LBNZ    GN9
        LOAD    RD, SPTR + 2    ; no: SREM = 0, LLEN as it was, DF = 1
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LDI     1
        SHR
        SEP     R5
GN9:    LOAD    RD, SPTR        ; SPTR, SREM, LLEN
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
        LOAD    RD, LLEN
        GLO     RB
        STR     RD
        LDI     0
        SHR
        SEP     R5

; SETSP: the variable at RD = " " (a text that is no variable's own)
SETSP:  LDI     TSTR
        STR     RD
        INC     RD
        LDI     HIGH(SPACE1)
        STR     RD
        INC     RD
        LDI     LOW(SPACE1)
        STR     RD
        INC     RD
        LDI     1
        STR     RD
        SEP     R5
SPACE1: DB      ' '

USE:    SEP     R4
        DW      K_PIN
        DB      'RAWK [-F c] [-v x=val] [-o file] ',27H,'program',27H,' (or -f file) names - HELP RAWK',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
; EMSG: "RAWK: " and the text after the call.  EMSGN: and then NEAR.  EMSGR: and then RERR.
;       RERR: a new line, back to the prompt.
EMSGR:  LDI     2
        LSKP
EMSGN:  LDI     1
        LSKP
EMSG:   LDI     0
        PLO     RE
        LOAD    RD, EMFL
        GLO     RE
        STR     RD
        SEP     R4
        DW      K_PIN
        DB      0DH,0AH,'RAWK: ',0
EM1:    LDA     R6
        LBZ     EM2
        SEP     R4
        DW      F_TYPE
        LBR     EM1
EM2:    LOAD    RD, EMFL
        LDN     RD
        LBZ     EM3
        XRI     1
        LBZ     NEAR
        LBR     RERR
EM3:    SEP     R5
RERR:   SEP     R4
        DW      K_PIN
        DB      0DH,0AH,0
OGIVE:  LOAD    RD, WFIRST      ; -o's clusters taken so far: given back
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    OG1
        GLO     RC
        LBZ     K_MAIN
OG1:    SEP     R4
        DW      KS_FREECH
        LBR     K_MAIN

; ======== running the steps ========
; RUNS: the steps whose start is at RD.  RUNC: the steps at R7, to their ORET. R7 = the next step, R8 = the value stack's top (VSTK up, 5 bytes each).
RUNS:   LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
RUNC:   LOAD    R8, VSTK
        LOAD    RD, TMPP
        LDI     HIGH(TMPH)
        STR     RD
        INC     RD
        LDI     LOW(TMPH)
        STR     RD
RL:     LOAD    RD, RCALL + 1
        LDA     R7
        LBZ     RLX
        SHL
        ADI     LOW(DTAB)
        PLO     RF
        LDI     HIGH(DTAB)
        ADCI    0
        PHI     RF
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
RCALL:  SEP     R4              ; (patched) the step's routine
        DW      0
        LBR     RL
RLX:    SEP     R5
DTAB:   DW      RLX, XPUSHN, XPUSHS, XGETV, XSETV, XFIELD, XPOP, XADD
        DW      XSUB, XMUL, XDIV, XMOD, XNEG, XUPLUS, XNOT, XLT
        DW      XLE, XGT, XGE, XEQ, XNE, XCAT, XMATCH, XJF
        DW      XJT, XJ, XPRINT, XLEN, XINCV, XDECV, XPINC, XPDEC
        DW      XPUSH0, XPUSH1, XNEXT, XEXIT, XPRINTF, XSUBSTR, XINDEX, XTOUP
        DW      XTOLOW, XPUSHV

; TOSRF: RF -> the top value.  NOSRD: RD -> the one under it.  POP1: one off.  PUSHE: RF -> a new one.
TOSRF:  GLO     R8
        SMI     5
        PLO     RF
        GHI     R8
        SMBI    0
        PHI     RF
        SEP     R5
NOSRD:  GLO     R8
        SMI     10
        PLO     RD
        GHI     R8
        SMBI    0
        PHI     RD
        SEP     R5
POP1:   GLO     R8
        SMI     5
        PLO     R8
        GHI     R8
        SMBI    0
        PHI     R8
        SEP     R5
PUSHE:  GHI     R8
        XRI     HIGH(VSTKE)
        LBNZ    PE1
        GLO     R8
        XRI     LOW(VSTKE)
        LBZ     PEFULL
PE1:    GHI     R8
        PHI     RF
        GLO     R8
        PLO     RF
        GLO     R8
        ADI     5
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        SEP     R5
PEFULL: SEP     R4
        DW      EMSGR
        DB      'the expression is too deep',0
; SETN8: the value at RF = the number D (0-255). RF kept.
SETN8:  STXD
        LDI     TNUM
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        IRX
        LDX
        STR     RF
        DEC     RF
        DEC     RF
        DEC     RF
        DEC     RF
        SEP     R5

XPUSHN: SEP     R4
        DW      PUSHE
        LDI     TNUM
        STR     RF
        INC     RF
XP4:    LDA     R7
        STR     RF
        INC     RF
        LDA     R7
        STR     RF
        INC     RF
XP2:    LDA     R7
        STR     RF
        INC     RF
        LDA     R7
        STR     RF
        SEP     R5
XPUSHS: SEP     R4
        DW      PUSHE
        LDI     TSTR
XPS2:   STR     RF
        INC     RF
        LDA     R7
        STR     RF
        INC     RF
        LBR     XP2
XPUSH0: LDI     0
        LSKP
XPUSH1: LDI     1
        STXD
        SEP     R4
        DW      PUSHE
        IRX
        LDX
        LBR     SETN8
; VCELL: D = a variable -> RD = its 8 bytes (type, value 4, its own text's place 2, room 1). Uses RD only.
VCELL:  PLO     RD
        LDI     0
        PHI     RD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        GLO     RD
        ADI     LOW(VARS)
        PLO     RD
        GHI     RD
        ADCI    HIGH(VARS)
        PHI     RD
        SEP     R5
; XGETV: a variable's value; NR NF FNR FILENAME made now
XGETV:  LDA     R7
        PLO     RB
        SEP     R4
        DW      PUSHE
        GLO     RB
        SMI     4
        LBDF    GV5
        GLO     RB
        LBNZ    GV1
        LOAD    RD, NRV         ; NR
        LBR     GV4N
GV1:    XRI     1
        LBNZ    GV2
        LOAD    RD, NFV         ; NF
        LDN     RD
        LBR     SETN8
GV2:    XRI     1 XOR 2
        LBNZ    GV3
        LOAD    RD, FNRV        ; FNR
GV4N:   LDI     TNUM
        STR     RF
        INC     RF
        LDI     4
        PLO     RB
        LBR     GV6
GV3:    LDI     TSTR            ; FILENAME
        STR     RF
        INC     RF
        LDI     HIGH(FNTXT)
        STR     RF
        INC     RF
        LDI     LOW(FNTXT)
        STR     RF
        INC     RF
        LOAD    RD, FNLEN
        LDN     RD
        STR     RF
        SEP     R5
GV5:    GLO     RB
        SEP     R4
        DW      VCELL
        LDI     5
        PLO     RB
GV6:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    GV6
        SEP     R5
; XSETV: the top value into a variable (it stays on the stack)
XSETV:  LDA     R7
        SEP     R4
        DW      VCELL
        SEP     R4
        DW      TOSRF
; STOREV: the value at RF into the variable at RD - a text is copied into the variable's own place
STOREV: LDN     RF
        SMI     TSTR
        LBDF    SV2
        LDI     5               ; a number, or not set
        PLO     RB
SV1:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    SV1
        SEP     R5
SV2:    INC     RF              ; RA = the text, RB.0 = its length
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA
        LDN     RF
        PLO     RB
        DEC     RF
        DEC     RF
        DEC     RF
        GLO     RD              ; RC -> the variable's room
        ADI     7
        PLO     RC
        GHI     RD
        ADCI    0
        PHI     RC
        LDN     RC
        STR     R2
        GLO     RB
        SD                      ; room - length
        LBDF    SV4
        GLO     RB              ; too small: a new place, the length + 8
        ADI     8
        LBNF    SV3
        LDI     0FFH
SV3:    STR     RC
        SEP     R4
        DW      VALLOC          ; -> R9 (RA, RB, RD, RF kept)
        GLO     RD
        ADI     6
        PLO     RC
        GHI     RD
        ADCI    0
        PHI     RC
        GLO     R9
        STR     RC
        DEC     RC
        GHI     R9
        STR     RC
        INC     RC
        INC     RC
SV4:    DEC     RC              ; R9 = its place
        LDN     RC
        PLO     R9
        DEC     RC
        LDN     RC
        PHI     R9
        LDN     RF              ; the variable: the type, its place, the length
        STR     RD
        INC     RD
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
SV5:    GLO     RB              ; the text
        LBZ     SV9
        LDA     RA
        STR     R9
        INC     R9
        DEC     RB
        LBR     SV5
SV9:    SEP     R5
; VALLOC: D bytes in VHEAP -> R9 (uses RC).  TALLOC: D bytes in TMPH -> RA (uses RC).  No room: said.
VALLOC: PLO     RE
        LOAD    RC, VHP
        LDA     RC
        PHI     R9
        LDN     RC
        PLO     R9
        GLO     RE
        STR     R2
        GLO     R9
        ADD
        STR     RC
        DEC     RC
        GHI     R9
        ADCI    0
        STR     RC
        LDA     RC              ; past VHE?
        STR     R2
        LDI     HIGH(VHE)
        SM
        LBNF    VAFULL
        LBNZ    VA9
        LDN     RC
        STR     R2
        LDI     LOW(VHE)
        SM
        LBNF    VAFULL
VA9:    SEP     R5
VAFULL: SEP     R4
        DW      EMSGR
        DB      'no more room for the variables',27H,' texts',0
TALLOC: PLO     RE
        LOAD    RC, TMPP
        LDA     RC
        PHI     RA
        LDN     RC
        PLO     RA
        GLO     RE
        STR     R2
        GLO     RA
        ADD
        STR     RC
        DEC     RC
        GHI     RA
        ADCI    0
        STR     RC
        LDA     RC
        STR     R2
        LDI     HIGH(TMPE)
        SM
        LBNF    TAFULL
        LBNZ    VA9
        LDN     RC
        STR     R2
        LDI     LOW(TMPE)
        SM
        LBNF    TAFULL
        SEP     R5
TAFULL: SEP     R4
        DW      EMSGR
        DB      'a rule made too much text',0
; XFIELD: $n - the top value (a number) -> that field ($0 the line; past NF: "")
XFIELD: SEP     R4
        DW      TOSRF
        SEP     R4
        DW      TONUM
        INC     RF
        LDN     RF
        ANI     80H
        LBNZ    FDNEG
        LDA     RF              ; (big: past NF)
        LBNZ    FDNO
        LDA     RF
        LBNZ    FDNO
        LDA     RF
        LBNZ    FDNO
        LDN     RF
        PLO     RC              ; RC.0 = n
        DEC     RF
        DEC     RF
        DEC     RF
        DEC     RF
        GLO     RC
        LBNZ    FD2
        LOAD    RA, LBUF        ; $0
        LOAD    RD, LLEN
        LDN     RD
        PLO     RB
        LBR     FD5
FD2:    LOAD    RD, NFV         ; past NF?
        LDN     RD
        STR     R2
        GLO     RC
        SD                      ; NF - n
        LBNF    FDNO0
        GLO     RC              ; RD -> FLDS + 2 (n - 1)
        SMI     1
        SHL
        ADI     LOW(FLDS)
        PLO     RD
        LDI     HIGH(FLDS)
        ADCI    0
        PHI     RD
        LDA     RD
        ADI     LOW(LBUF)
        PLO     RA
        LDI     HIGH(LBUF)
        ADCI    0
        PHI     RA
        LDN     RD
        PLO     RB
FD5:    LDI     TFLD            ; a field (looked at when a comparison needs it)
        STR     RF
        INC     RF
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        SEP     R5
FDNO:   SEP     R4
        DW      TOSRF
FDNO0:  LDI     0
        PLO     RB
        LBR     FD5
FDNEG:  SEP     R4
        DW      EMSGR
        DB      'a field number below 0',0

; BINN: both top values numbers; RD -> the lower's 4 bytes, RF -> the top's
BINN:   GLO     R8              ; RF -> the top
        SMI     5
        PLO     RF
        GHI     R8
        SMBI    0
        PHI     RF
        LDN     RF
        XRI     TNUM
        LBZ     BN1
        SEP     R4
        DW      TONUM
BN1:    GLO     RF              ; RD -> the lower
        SMI     5
        PLO     RD
        GHI     RF
        SMBI    0
        PHI     RD
        LDN     RD
        XRI     TNUM
        LBZ     BN2
        GHI     RF
        STXD
        GLO     RF
        STXD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        SEP     R4
        DW      TONUM
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
BN2:    INC     RD
        INC     RF
        SEP     R5
XADD:   SEP     R4
        DW      BINN
        SEP     R4
        DW      ADD4
        LBR     POP1
XSUB:   SEP     R4
        DW      BINN
        SEP     R4
        DW      SUB4
        LBR     POP1
XMUL:   SEP     R4
        DW      BINN
        SEP     R4
        DW      MUL4
        LBR     POP1
XDIV:   SEP     R4
        DW      BINN
        SEP     R4
        DW      SDIV
        LBR     POP1
XMOD:   SEP     R4
        DW      BINN
        SEP     R4
        DW      SDIV
        SEP     R4
        DW      NOSRD
        INC     RD
        LOAD    RF, REM4
        LDI     4
        PLO     RB
XM1:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    XM1
        LBR     POP1
XNEG:   SEP     R4
        DW      TOSRF
        SEP     R4
        DW      TONUM
        INC     RF
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        LBR     NEG4
XUPLUS: SEP     R4
        DW      TOSRF
        LBR     TONUM
XNOT:   SEP     R4
        DW      TOSRF
        SEP     R4
        DW      TRUTH
        LBZ     XNT1
        LDI     0
        LBR     SETN8
XNT1:   LDI     1
        LBR     SETN8
; the comparisons: numbers unless one is a text (then as texts) -> 1 or 0.  CMPM: 1 =, 2 <, 4 >.
XLT:    LDI     2
        LBR     XCMP
XLE:    LDI     3
        LBR     XCMP
XGT:    LDI     4
        LBR     XCMP
XGE:    LDI     5
        LBR     XCMP
XEQ:    LDI     1
        LBR     XCMP
XNE:    LDI     6
XCMP:   PLO     RB
        LOAD    RD, CMPM
        GLO     RB
        STR     RD
        SEP     R4
        DW      TOSRF
        SEP     R4
        DW      CLASS
        SEP     R4
        DW      NOSRD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        SEP     R4
        DW      CLASS
        LDN     RF
        XRI     TSTR
        LBZ     XCS
        SEP     R4
        DW      TOSRF
        LDN     RF
        XRI     TSTR
        LBZ     XCS
        SEP     R4
        DW      BINN
        SEP     R4
        DW      CMP4
        LBR     XCR
XCS:    SEP     R4              ; as texts
        DW      TXT2            ; -> RA, RB.0 the lower; RC, RB.1 the top
        SEP     R4
        DW      STRCMP
XCR:    PLO     RB              ; 0 =, 1 <, 2 >  ->  its bit in CMPM?
        LDI     1
        PLO     RC
XCR1:   GLO     RB
        LBZ     XCR2
        DEC     RB
        GLO     RC
        SHL
        PLO     RC
        LBR     XCR1
XCR2:   LOAD    RD, CMPM
        LDN     RD
        STR     R2
        GLO     RC
        AND
        LBZ     XCR3
        LDI     1
XCR3:   PLO     RB
        SEP     R4
        DW      NOSRD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        GLO     RB
        SEP     R4
        DW      SETN8
        LBR     POP1
; TXT2: both top values texts: RA, RB.0 = the lower's; RC, RB.1 = the top's
TXT2:   SEP     R4
        DW      TOSRF
        SEP     R4
        DW      TOSTR
        SEP     R4
        DW      NOSRD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        SEP     R4
        DW      TOSTR
        INC     RF
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA
        LDN     RF
        PLO     RB
        SEP     R4
        DW      TOSRF
        INC     RF
        LDA     RF
        PHI     RC
        LDA     RF
        PLO     RC
        LDN     RF
        PHI     RB
        SEP     R5
; STRCMP: RA (RB.0 long) against RC (RB.1 long) -> D: 0 the same, 1 less, 2 more (byte by byte)
STRCMP: GLO     RB
        LBNZ    SC2
        GHI     RB
        LBZ     SC9
SCLT:   LDI     1
        SEP     R5
SC2:    GHI     RB
        LBZ     SCGT
        LDA     RC
        STR     R2
        LDA     RA
        SM
        LBZ     SC3
        LBNF    SCLT
SCGT:   LDI     2
        SEP     R5
SC3:    DEC     RB
        GHI     RB
        SMI     1
        PHI     RB
        LBR     STRCMP
SC9:    SEP     R5
; XCAT: the two top values joined (if the lower one ends the made texts, the top one is added after it)
XCAT:   SEP     R4
        DW      TXT2
        GLO     RB              ; a + b past 255: b cut
        STR     R2
        GHI     RB
        ADD
        LBNF    XC1
        GLO     RB
        SDI     0FFH
        PHI     RB
XC1:    GLO     RA              ; RA + RB.0 = TMPP?
        STR     R2
        GLO     RB
        ADD
        PLO     RD
        GHI     RA
        ADCI    0
        PHI     RD
        LOAD    RF, TMPP
        LDA     RF
        STR     R2
        GHI     RD
        XOR
        LBNZ    XC3
        LDN     RF
        STR     R2
        GLO     RD
        XOR
        LBNZ    XC3
        GHI     RA              ; yes: room for b only (RA kept in R9)
        PHI     R9
        GLO     RA
        PLO     R9
        GHI     RB
        SEP     R4
        DW      TALLOC          ; -> RA (= TMPP before; uses RC)
        LBR     XC4
XC3:    GHI     RA              ; no: room for both; a copied first
        PHI     R9
        GLO     RA
        PLO     R9
        GLO     RB
        STR     R2
        GHI     RB
        ADD
        SEP     R4
        DW      TALLOC
        GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
        GLO     RB
        PLO     RF
XC3A:   GLO     RF
        LBZ     XC3B
        LDA     R9
        STR     RD
        INC     RD
        DEC     RF
        LBR     XC3A
XC3B:   GHI     RA
        PHI     R9
        GLO     RA
        PLO     R9
        GLO     RB
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
XC4:    SEP     R4              ; RA -> where b goes, R9 = the result's start; RC, RB.1 = b
        DW      TOSRF
        INC     RF
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        GHI     RB
        PLO     RF
XC5:    GLO     RF
        LBZ     XC6
        LDA     RC
        STR     RA
        INC     RA
        DEC     RF
        LBR     XC5
XC6:    GLO     RB              ; the lower value: TSTR, R9, a + b
        STR     R2
        GHI     RB
        ADD
        PLO     RB
        SEP     R4
        DW      NOSRD
        LDI     TSTR
        STR     RD
        INC     RD
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LBR     POP1
; XMATCH: the lower value matches the top one as a pattern -> 1 or 0.  ^ (at the start) $ (at the end) . * + ?
;         [abc] [a-z] [^...] \c - not ( ) | yet
XMATCH: SEP     R4
        DW      TXT2
        GHI     RC              ; the pattern: no ( ) | yet
        PHI     RA
        GLO     RC
        PLO     RA
        GHI     RB
        PLO     RB
        SEP     R4
        DW      SPECIAL
        LBDF    XMSP
        SEP     R4
        DW      TXT2            ; RA, RB.0 = the text; RC, RB.1 = the pattern
        SEP     R4
        DW      RMATCH
        LDI     0
        SHLC                    ; D = DF
        LBR     XCR3
XMSP:   SEP     R4
        DW      EMSGR
        DB      '( ) | in a pattern come later',0
; RMATCH: does the text at RA (RB.0 long) contain the pattern at RC (RB.1 long)? DF = 1: yes. Uses R9, RD, RF,
;         RE.0 (not RE.1: the BIOS's). The pattern ends at RXEND throughout. Only * + ? go deeper (the stack).
RMATCH: GHI     RB              ; RXEND = its end
        STR     R2
        GLO     RC
        ADD
        PLO     RF
        GHI     RC
        ADCI    0
        PHI     RF
        LOAD    RD, RXEND
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GHI     RB
        LBZ     RHERE
        LDN     RC
        XRI     '^'
        LBNZ    RM2
        INC     RC              ; ^: at the start only
        LBR     RHERE
RM2:    GHI     RA              ; each place it could start
        STXD
        GLO     RA
        STXD
        GLO     RB
        STXD
        GHI     RC
        STXD
        GLO     RC
        STXD
        SEP     R4
        DW      RHERE
        IRX
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDXA
        PLO     RB
        LDXA
        PLO     RA
        LDX
        PHI     RA
        LBDF    RYES
        GLO     RB
        LBZ     RNO
        INC     RA
        DEC     RB
        LBR     RM2
; PLEN: D = how much of the pattern is left (RXEND - RC). Uses RF.
PLEN:   LOAD    RF, RXEND + 1
        GLO     RC
        STR     R2
        LDN     RF
        SM
        SEP     R5
; RHERE: does the pattern (from RC) match at the text's start (RA, RB.0 long)? DF = 1: yes
RHERE:  SEP     R4              ; no pattern left: yes
        DW      PLEN
        LBZ     RYES
        XRI     1               ; $ last: the text must end here
        LBNZ    RH1
        LDN     RC
        XRI     '$'
        LBNZ    RH1
        GLO     RB
        LBZ     RYES
        LBR     RNO
RH1:    SEP     R4
        DW      ATOMLEN         ; RD.0 = the first thing's length
        GLO     RD              ; R9 -> after it: * + ?
        STR     R2
        GLO     RC
        ADD
        PLO     R9
        GHI     RC
        ADCI    0
        PHI     R9
        SEP     R4              ; more after it?
        DW      PLEN
        STR     R2
        GLO     RD
        SD
        LBZ     RH5
        LDN     R9
        XRI     '*'
        LBZ     RSTAR
        XRI     '*' XOR '+'
        LBZ     RPLUS
        XRI     '+' XOR '?'
        LBZ     RQUES
RH5:    GLO     RB              ; once: this character
        LBZ     RNO
        SEP     R4
        DW      ATOMOK
        LBNF    RNO
        INC     RA
        DEC     RB
        GHI     R9
        PHI     RC
        GLO     R9
        PLO     RC
        LBR     RHERE
RYES:   LDI     1
        SHR
        SEP     R5
RNO:    LDI     0
        SHR
        SEP     R5
RPLUS:  GLO     RB              ; +: once, then as *
        LBZ     RNO
        SEP     R4
        DW      ATOMOK
        LBNF    RNO
        INC     RA
        DEC     RB
RSTAR:  LDI     0FFH            ; *: the rest here, else one more of it and again (RB.1: how many more)
        LSKP
RQUES:  LDI     1               ; ?: the same, once at most
        PHI     RB
        INC     R9              ; R9 -> the rest
RS1:    GHI     RA
        STXD
        GLO     RA
        STXD
        GHI     RB
        STXD
        GLO     RB
        STXD
        GHI     RC
        STXD
        GLO     RC
        STXD
        GLO     RD
        STXD
        GHI     R9
        STXD
        GLO     R9
        STXD
        GHI     R9
        PHI     RC
        GLO     R9
        PLO     RC
        SEP     R4
        DW      RHERE
        IRX
        LDXA
        PLO     R9
        LDXA
        PHI     R9
        LDXA
        PLO     RD
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDXA
        PLO     RB
        LDXA
        PHI     RB
        LDXA
        PLO     RA
        LDX
        PHI     RA
        LBDF    RYES
        GLO     RB
        LBZ     RNO
        GHI     RB
        LBZ     RNO
        SEP     R4
        DW      ATOMOK
        LBNF    RNO
        INC     RA
        DEC     RB
        GHI     RB
        SMI     1
        PHI     RB
        LBR     RS1
; ATOMLEN: the pattern's first thing (RC; 1 left at least) -> RD.0 its length: \c 2, [...] to its ], else 1
;          (a ] first in [...] or [^...] is a character; no ] at all: the [ is a character). Uses RF.
ATOMLEN: SEP    R4
        DW      PLEN
        PHI     RD              ; RD.1 = what is left (1 at least)
        LDI     1
        PLO     RD
        LDN     RC
        XRI     5CH
        LBNZ    AL2
        GHI     RD
        XRI     1
        LBZ     AL9
        LDI     2
        PLO     RD
        SEP     R5
AL2:    LDN     RC
        XRI     '['
        LBNZ    AL9
        GHI     RC
        PHI     RF
        GLO     RC
        PLO     RF
        INC     RF
        GHI     RD              ; RD.0 = what is looked at
        STR     R2
        GLO     RD
        XOR
        LBZ     AL8
        LDN     RF
        XRI     '^'
        LBNZ    AL3
        INC     RF
        INC     RD
        GHI     RD
        STR     R2
        GLO     RD
        XOR
        LBZ     AL8
AL3:    LDN     RF
        XRI     ']'
        LBNZ    AL4
        INC     RF
        INC     RD
AL4:    GHI     RD
        STR     R2
        GLO     RD
        XOR
        LBZ     AL8
        LDA     RF
        INC     RD
        XRI     ']'
        LBNZ    AL4
        SEP     R5
AL8:    LDI     1
        PLO     RD
AL9:    SEP     R5
; ATOMOK: the pattern's first thing (RC, RD.0 long) takes the character at RA? DF = 1: yes.
;         RA, RB, RC, RD.0, R9 kept; uses RF, RE.0, RD.1.
ATOMOK: LDN     RA
        PLO     RE
        GLO     RD
        XRI     1
        LBNZ    AK2
        LDN     RC              ; one character: itself, or . any
        XRI     '.'
        LBZ     RYES
        LDN     RC
        STR     R2
        GLO     RE
        XOR
        LBZ     RYES
        LBR     RNO
AK2:    LDN     RC
        XRI     5CH
        LBNZ    AK3
        GHI     RC              ; \c: c (\t a tab, \n a line's end)
        PHI     RF
        GLO     RC
        PLO     RF
        INC     RF
        LDN     RF
        XRI     't'
        LBNZ    AK2A
        LDI     9
        LBR     AK2C
AK2A:   XRI     't' XOR 'n'
        LBNZ    AK2B
        LDI     0AH
        LBR     AK2C
AK2B:   LDN     RF
AK2C:   STR     R2
        GLO     RE
        XOR
        LBZ     RYES
        LBR     RNO
AK3:    GHI     RC              ; [...]: RF -> inside, RD.1 = how many there
        PHI     RF
        GLO     RC
        PLO     RF
        INC     RF
        GLO     RD
        SMI     2
        PHI     RD
        LDN     RF
        XRI     '^'
        LBNZ    AK5
        INC     RF
        GHI     RD
        SMI     1
        PHI     RD
AK5:    GHI     RD
        LBZ     AKNO
        SMI     3               ; a - b (the - not last)?
        LBNF    AK6
        INC     RF
        LDN     RF
        DEC     RF
        XRI     '-'
        LBNZ    AK6
        LDN     RF              ; a <= it
        STR     R2
        GLO     RE
        SM
        LBNF    AK7
        INC     RF              ; it <= b
        INC     RF
        LDN     RF
        DEC     RF
        DEC     RF
        STR     R2
        GLO     RE
        SD
        LBDF    AKYES
AK7:    INC     RF
        INC     RF
        INC     RF
        GHI     RD
        SMI     3
        PHI     RD
        LBR     AK5
AK6:    LDA     RF
        STR     R2
        GLO     RE
        XOR
        LBZ     AKYES
        GHI     RD
        SMI     1
        PHI     RD
        LBR     AK5
AKYES:  LDI     1
        LSKP
AKNO:   LDI     0
        PHI     RD              ; [^...]: the other way round
        GHI     RC
        PHI     RF
        GLO     RC
        PLO     RF
        INC     RF
        LDN     RF
        XRI     '^'
        LBNZ    AK9
        GHI     RD
        XRI     1
        PHI     RD
AK9:    GHI     RD
        SHR
        SEP     R5
; XJF / XJT: off the stack; if it is false / true, go to the step given.  XJ: go.
XJF:    LDI     0
        LSKP
XJT:    LDI     1
        STXD
        SEP     R4
        DW      TOSRF
        SEP     R4
        DW      TRUTH
        LBZ     XJ1
        LDI     1
XJ1:    IRX
        XOR
        PLO     RB              ; 0: go
        SEP     R4
        DW      POP1
        SEP     R4              ; (a test done: its texts free)
        DW      TRESET
        GLO     RB
        LBZ     XJ
        INC     R7
        INC     R7
        SEP     R5
XJ:     LDA     R7
        PHI     RC
        LDN     R7
        PLO     R7
        GHI     RC
        PHI     R7
        SEP     R5
; XPRINT: n values off the stack, OFS between, then a new line (counted: a screen at a time)
XPRINT: LDA     R7
        PLO     RB
        LOAD    RD, PRN
        GLO     RB
        STR     RD
XPR1:   SEP     R4              ; R8 down to the first of them
        DW      POP1
        DEC     RB
        GLO     RB
        LBNZ    XPR1
        LOAD    RD, PRP
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        LOAD    RD, VARS + 5 * 8        ; OFS as a text -> OFSE
        LOAD    RF, OFSE
        LDI     5
        PLO     RB
XPR2:   LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    XPR2
        LOAD    RF, OFSE
        SEP     R4
        DW      TOSTR
XPR3:   LOAD    RD, PRP         ; the next one
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      TOSTR
        SEP     R4
        DW      PRVAL
        LOAD    RD, PRP + 1
        LDN     RD
        ADI     5
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, PRN
        LDN     RD
        SMI     1
        STR     RD
        LBZ     XPR9
        LOAD    RF, OFSE
        SEP     R4
        DW      PRVAL
        LBR     XPR3
XPR9:   LDI     0AH             ; the line's end: LF into the file, or a new line on the screen
        SEP     R4
        DW      OUTC
        LBR     TRESET
; PRVAL: the text value at RF on the screen
PRVAL:  INC     RF
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA
        LDN     RF
        PLO     RB
        GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
PV1:    GLO     RB
        LBZ     PV9
        LDA     RF
        SEP     R4
        DW      OUTC
        DEC     RB
        LBR     PV1
PV9:    SEP     R5
; XLEN: the top value's length as text
XLEN:   SEP     R4
        DW      TOSRF
        SEP     R4
        DW      TOSTR
        INC     RF
        INC     RF
        INC     RF
        LDN     RF
        DEC     RF
        DEC     RF
        DEC     RF
        LBR     SETN8
; XINCV XDECV: ++v --v (the new value);  XPINC XPDEC: v++ v-- (the old one)
XINCV:  LDI     1
        LBR     XIV
XDECV:  LDI     3
        LBR     XIV
XPINC:  LDI     0
        LBR     XIV
XPDEC:  LDI     2
XIV:    PLO     RB              ; bit 0: the new value; bit 1: down
        LOAD    RD, IVMODE
        GLO     RB
        STR     RD
        LDA     R7
        INC     RD              ; (IVVAR)
        STR     RD
        SEP     R4
        DW      VCELL
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        SEP     R4
        DW      TONUM
        LOAD    RD, IVMODE
        LDN     RD
        SHR
        LBDF    XIV2
        SEP     R4              ; the old value first
        DW      IVPUSH
XIV2:   LOAD    RD, IVVAR
        LDN     RD
        SEP     R4
        DW      VCELL
        INC     RD
        LOAD    RF, KONE
        LOAD    RC, IVMODE
        LDN     RC
        ANI     2
        LBNZ    XIV3
        SEP     R4
        DW      ADD4
        LBR     XIV4
XIV3:   SEP     R4
        DW      SUB4
XIV4:   LOAD    RD, IVMODE
        LDN     RD
        SHR
        LBNF    XIV9
IVPUSH: LOAD    RD, IVVAR       ; the variable's value onto the stack
        LDN     RD
        SEP     R4
        DW      VCELL
        SEP     R4
        DW      PUSHE
        LDI     5
        PLO     RB
IVP1:   LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    IVP1
XIV9:   SEP     R5
KONE:   DB      0, 0, 0, 1

; CLASS: a field at RF (TFLD) -> TSN if it looks like a number, else TSTR. RF kept.
CLASS:  LDN     RF
        XRI     TFLD
        LBNZ    CL9
        INC     RF
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA
        LDN     RF
        PLO     RB
        DEC     RF
        DEC     RF
        DEC     RF
        SEP     R4
        DW      LOOKN
        LDI     TSTR
        LBNF    CL1
        LDI     TSN
CL1:    STR     RF
CL9:    SEP     R5
; TRUTH: the value at RF -> D = 0 false (0, "", not set); RF kept
TRUTH:  SEP     R4
        DW      CLASS
        LDN     RF
        LBZ     TR9
        XRI     TSN
        LBNZ    TR2
        SEP     R4              ; looks like a number: as a number
        DW      TONUM
TR2:    LDN     RF
        XRI     TNUM
        LBNZ    TR3
        INC     RF
        LDA     RF
        STR     R2
        LDA     RF
        OR
        STR     R2
        LDA     RF
        OR
        STR     R2
        LDN     RF
        OR
        DEC     RF
        DEC     RF
        DEC     RF
        DEC     RF
        SEP     R5
TR3:    INC     RF              ; a text: its length
        INC     RF
        INC     RF
        LDN     RF
        DEC     RF
        DEC     RF
        DEC     RF
TR9:    SEP     R5
; TONUM: the value at RF -> a number (a text: its leading number; not set: 0). RF kept.
TONUM:  LDN     RF
        XRI     TNUM
        LBZ     TN9
        LDN     RF
        LBNZ    TN2
        LDI     0
        LBR     SETN8
TN2:    INC     RF
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA
        LDN     RF
        PLO     RB
        DEC     RF
        DEC     RF
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        DEC     RF
        GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      STRTON
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LDI     TNUM
        STR     RF
TN9:    SEP     R5
; TOSTR: the value at RF -> a text (a number: its digits, made in TMPH; not set: ""). RF kept.
TOSTR:  LDN     RF
        SMI     TSTR
        LBDF    TS9
        LDN     RF
        LBNZ    TS2
        LDI     TSTR
        STR     RF
        INC     RF
        INC     RF
        INC     RF
        LDI     0
        STR     RF
        DEC     RF
        DEC     RF
        DEC     RF
        SEP     R5
TS2:    GHI     RF
        STXD
        GLO     RF
        STXD
        INC     RF
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        SEP     R4
        DW      NTOS            ; -> RA, RB.0
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LDI     TSTR
        STR     RF
        INC     RF
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        DEC     RF
        DEC     RF
        DEC     RF
TS9:    SEP     R5
; STRTON: the text at RA (RB.0 long) -> its leading number (blanks, a sign, digits) -> 4 bytes at RD.
;         Uses R9, RA, RB, RC, RF; RD kept.
STRTON: LDI     0
        PHI     R9
        PLO     R9
        PHI     RC
        PLO     RC
        PHI     RB              ; RB.1 = 1: minus
SN1:    GLO     RB
        LBZ     SNE
        LDN     RA
        XRI     ' '
        LBZ     SN1S
        XRI     ' ' XOR 9
        LBNZ    SN2
SN1S:   INC     RA
        DEC     RB
        LBR     SN1
SN2:    LDN     RA
        XRI     '-'
        LBNZ    SN3
        LDI     1
        PHI     RB
        LBR     SN4
SN3:    LDN     RA
        XRI     '+'
        LBNZ    SN5
SN4:    INC     RA
        DEC     RB
SN5:    GLO     RB
        LBZ     SNE
        LDN     RA
        SMI     '0'
        LBNF    SNE
        SMI     10
        LBDF    SNE
        SEP     R4              ; R9:RC x 10
        DW      X10
        LDN     RA              ; + the digit
        SMI     '0'
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        GLO     R9
        ADCI    0
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        INC     RA
        DEC     RB
        LBR     SN5
SNE:    GHI     RB
        LBZ     SNE2
        GLO     RC
        SDI     0
        PLO     RC
        GHI     RC
        SDBI    0
        PHI     RC
        GLO     R9
        SDBI    0
        PLO     R9
        GHI     R9
        SDBI    0
        PHI     R9
SNE2:   GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        DEC     RD
        DEC     RD
        DEC     RD
        SEP     R5
; X10: R9:RC x 10 = x 8 + x 2 (uses RF, T4)
X10:    GLO     RC              ; (x 2)
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     R9
        SHLC
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        LOAD    RF, T4
        GHI     R9
        STR     RF
        INC     RF
        GLO     R9
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LDI     2
        PLO     RE
X10A:   GLO     RC              ; (x 8)
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     R9
        SHLC
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        DEC     RE
        GLO     RE
        LBNZ    X10A
        SEX     RF              ; + x 2 (RF -> T4's last byte)
        GLO     RC
        ADD
        PLO     RC
        DEC     RF
        GHI     RC
        ADC
        PHI     RC
        DEC     RF
        GLO     R9
        ADC
        PLO     R9
        DEC     RF
        GHI     R9
        ADC
        PHI     R9
        SEX     R2
        SEP     R5
; NTOS: the number at RD -> its digits in TMPH: RA = them, RB.0 = how many. Uses R9, RB, RC, RD, RF.
NTOS:   LOAD    RF, NV          ; NV = it
        LDI     4
        PLO     RB
NT0:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    NT0
        LDI     12
        SEP     R4
        DW      TALLOC          ; -> RA
        GHI     RA
        PHI     R9
        GLO     RA
        PLO     R9
        LDI     0
        PHI     RC              ; RC.1 = 1: a digit written
        LOAD    RD, NV
        LDN     RD
        ANI     80H
        LBZ     NT1
        LDI     '-'
        STR     R9
        INC     R9
        SEP     R4
        DW      NEG4
NT1:    LOAD    RB, P10
NT2:    LDI     0
        PLO     RC
NT3:    LOAD    RD, NV
        GHI     RB
        PHI     RF
        GLO     RB
        PLO     RF
        SEP     R4
        DW      SUB4
        LBNF    NT4
        INC     RC
        LBR     NT3
NT4:    LOAD    RD, NV          ; one too many: back
        GHI     RB
        PHI     RF
        GLO     RB
        PLO     RF
        SEP     R4
        DW      ADD4
        GLO     RC
        LBNZ    NT5
        GHI     RC
        LBZ     NT6
NT5:    GLO     RC
        ADI     '0'
        STR     R9
        INC     R9
        LDI     1
        PHI     RC
NT6:    INC     RB
        INC     RB
        INC     RB
        INC     RB
        GLO     RB
        XRI     LOW(P10E)
        LBNZ    NT2
        LOAD    RD, NV + 3      ; the last digit
        LDN     RD
        ADI     '0'
        STR     R9
        INC     R9
        LOAD    RD, TMPP        ; TMPP = past them
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        GLO     R9
        STR     R2
        GLO     RA
        SD
        PLO     RB
        SEP     R5
P10:    DB      3BH, 9AH, 0CAH, 00H, 05H, 0F5H, 0E1H, 00H, 00H, 98H, 96H, 80H, 00H, 0FH, 42H, 40H
        DB      00H, 01H, 86H, 0A0H, 00H, 00H, 27H, 10H, 00H, 00H, 03H, 0E8H, 00H, 00H, 00H, 64H
        DB      00H, 00H, 00H, 0AH
P10E:
; LOOKN: does the text at RA (RB.0 long) look like a number? DF = 1: yes ([blanks][sign]digits[.digits]
;        [e[sign]digits][blanks]). RA, RB, RF kept; uses RC, RD.
LOOKN:  GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        GLO     RB
        PLO     RD              ; RD.0 = left
        LDI     0
        PHI     RD              ; RD.1 = digits seen
        SEP     R4
        DW      LKBL
        SEP     R4
        DW      LKSGN
        SEP     R4
        DW      LKDIG
        GLO     RD
        LBZ     LK5
        LDN     RC
        XRI     '.'
        LBNZ    LK5
        INC     RC
        DEC     RD
        SEP     R4
        DW      LKDIG
LK5:    GHI     RD
        LBZ     LKNO
        GLO     RD
        LBZ     LKYES
        LDN     RC
        ANI     0DFH
        XRI     'E'
        LBNZ    LK7
        INC     RC
        DEC     RD
        SEP     R4
        DW      LKSGN
        LDI     0
        PHI     RD
        SEP     R4
        DW      LKDIG
        GHI     RD
        LBZ     LKNO
LK7:    SEP     R4
        DW      LKBL
        GLO     RD
        LBZ     LKYES
LKNO:   LDI     0
        SHR
        SEP     R5
LKYES:  LDI     1
        SHR
        SEP     R5
LKBL:   GLO     RD              ; blanks
        LBZ     LKR
        LDN     RC
        XRI     ' '
        LBZ     LKB1
        XRI     ' ' XOR 9
        LBNZ    LKR
LKB1:   INC     RC
        DEC     RD
        LBR     LKBL
LKSGN:  GLO     RD              ; a sign
        LBZ     LKR
        LDN     RC
        XRI     '+'
        LBZ     LKS1
        XRI     '+' XOR '-'
        LBNZ    LKR
LKS1:   INC     RC
        DEC     RD
LKR:    SEP     R5
LKDIG:  GLO     RD              ; digits (RD.1 = 1 if any)
        LBZ     LKR
        LDN     RC
        SMI     '0'
        LBNF    LKR
        SMI     10
        LBDF    LKR
        INC     RC
        DEC     RD
        LDI     1
        PHI     RD
        LBR     LKDIG
; SPLIT: LBUF (LLEN) -> FLDS (offset, length each) and NF; by FS: " " runs of blanks, else that character
SPLIT:  LOAD    RD, VARS + 4 * 8        ; FS: one character?
        LDN     RD
        SMI     TSTR
        LBNF    SPBAD
        INC     RD
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDN     RD
        XRI     1
        LBNZ    SPBAD
        LDN     RA
        PLO     RE              ; (RE.0: FS's character, while SPLIT runs)
        LOAD    RA, LBUF
        LOAD    RD, LLEN
        LDN     RD
        PLO     RB              ; RB.0 = characters left
        LOAD    RC, FLDS
        LDI     0
        PLO     RD              ; RD.0 = NF
        PLO     R9              ; R9.0 = the offset
        GLO     RE
        XRI     ' '
        LBNZ    SP5
SP1:    GLO     RB              ; blanks
        LBZ     SP9
        LDN     RA
        XRI     ' '
        LBZ     SP1S
        XRI     ' ' XOR 9
        LBNZ    SP2
SP1S:   INC     RA
        INC     R9
        DEC     RB
        LBR     SP1
SP2:    GLO     R9              ; a field: up to a blank
        STR     RC
        INC     RC
        LDI     0
        PHI     RD
SP3:    GLO     RB
        LBZ     SP4
        LDN     RA
        XRI     ' '
        LBZ     SP4
        XRI     ' ' XOR 9
        LBZ     SP4
        INC     RA
        INC     R9
        DEC     RB
        GHI     RD
        ADI     1
        PHI     RD
        LBR     SP3
SP4:    GHI     RD
        STR     RC
        INC     RC
        INC     RD
        GLO     RD
        XRI     128
        LBNZ    SP1
        LBR     SP9
SP5:    GLO     RB              ; one character: every field between them (none in an empty line)
        LBZ     SP9
        LDI     0
        PHI     RD
SP6:    GLO     R9              ; its offset
        STR     RC
SP7:    GLO     RB
        LBZ     SP8
        LDN     RA
        STR     R2
        GLO     RE
        XOR
        LBZ     SP8
        INC     RA
        INC     R9
        DEC     RB
        GHI     RD
        ADI     1
        PHI     RD
        LBR     SP7
SP8:    INC     RC              ; its length
        GHI     RD
        STR     RC
        INC     RC
        INC     RD
        GLO     RB              ; the end: done; else past the separator
        LBZ     SP9
        GLO     RD
        XRI     128
        LBZ     SP9
        INC     RA
        INC     R9
        DEC     RB
        LDI     0
        PHI     RD
        GLO     RB              ; a separator last: one more, empty
        LBNZ    SP6
        GLO     R9
        STR     RC
        INC     RC
        LDI     0
        STR     RC
        INC     RD
SP9:    LOAD    RF, NFV
        GLO     RD
        STR     RF
        SEP     R5
SPBAD:  SEP     R4
        DW      EMSGR
        DB      'FS must be one character in RAWK',0

; ---- 32-bit numbers (big-endian, RD and RF -> their first byte; both pointers move)
; ADD4: M(RD) += M(RF).  SUB4: M(RD) -= M(RF) (DF = 0: it borrowed).  NEG4: M(RD) = -M(RD).
ADD4:   INC     RD
        INC     RD
        INC     RD
        INC     RF
        INC     RF
        INC     RF
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
        SEP     R5
SUB4:   INC     RD
        INC     RD
        INC     RD
        INC     RF
        INC     RF
        INC     RF
        SEX     RF
        LDN     RD
        SM
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        SMB
        STR     RD
        SEX     R2
        SEP     R5
NEG4:   INC     RD
        INC     RD
        INC     RD
        LDN     RD
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
        SDBI    0
        STR     RD
        SEP     R5
; CMP4: M(RD) against M(RF), signed -> D: 0 the same, 1 less, 2 more
CMP4:   LDN     RD
        XRI     80H
        STR     R2
        LDN     RF
        XRI     80H
        SD
        LBNZ    CM8
        LDI     3
        PLO     RE
CM1:    INC     RD
        INC     RF
        LDN     RF
        STR     R2
        LDN     RD
        SM
        LBNZ    CM8
        DEC     RE
        GLO     RE
        LBNZ    CM1
        SEP     R5
CM8:    LBDF    CM9
        LDI     1
        SEP     R5
CM9:    LDI     2
        SEP     R5
; MUL4: M(RD) = M(RD) x M(RF) (the low 32 bits - right for signed numbers too)
MUL4:   GHI     RD
        STXD
        GLO     RD
        STXD
        LDA     RD              ; A = R9:RA
        PHI     R9
        LDA     RD
        PLO     R9
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDA     RF              ; B = RB:RC
        PHI     RB
        LDA     RF
        PLO     RB
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        LDI     0               ; the product = RD:RF
        PHI     RD
        PLO     RD
        PHI     RF
        PLO     RF
MU1:    GHI     RB              ; B = 0: done
        STR     R2
        GLO     RB
        OR
        STR     R2
        GHI     RC
        OR
        STR     R2
        GLO     RC
        OR
        LBZ     MU9
        GHI     RB              ; B >> 1; its low bit -> DF
        SHR
        PHI     RB
        GLO     RB
        SHRC
        PLO     RB
        GHI     RC
        SHRC
        PHI     RC
        GLO     RC
        SHRC
        PLO     RC
        LBNF    MU2
        GLO     RF              ; P += A
        STR     R2
        GLO     RA
        ADD
        PLO     RF
        GHI     RF
        STR     R2
        GHI     RA
        ADC
        PHI     RF
        GLO     RD
        STR     R2
        GLO     R9
        ADC
        PLO     RD
        GHI     RD
        STR     R2
        GHI     R9
        ADC
        PHI     RD
MU2:    GLO     RA              ; A << 1
        SHL
        PLO     RA
        GHI     RA
        SHLC
        PHI     RA
        GLO     R9
        SHLC
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        LBR     MU1
MU9:    IRX
        LDXA
        PLO     RA
        LDX
        PHI     RA
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        INC     RA
        GHI     RF
        STR     RA
        INC     RA
        GLO     RF
        STR     RA
        SEP     R5
; SDIV: M(RD) / M(RF), signed (towards 0) -> the quotient at RD, the remainder (the sign of M(RD)) at REM4.
;       Dividing by 0: said, back to the prompt.
SDIV:   GHI     RD
        STXD
        GLO     RD
        STXD
        LOAD    RC, QN          ; QN = M(RD), DVS = M(RF)
        LDI     4
        PLO     RB
SD1:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    SD1
        LOAD    RC, DVS
        LDI     4
        PLO     RB
        LDI     0
        PHI     RB              ; RB.1: is it 0?
SD2:    LDA     RF
        STR     RC
        INC     RC
        STR     R2
        GHI     RB
        OR
        PHI     RB
        DEC     RB
        GLO     RB
        LBNZ    SD2
        GHI     RB
        LBZ     SDZERO
        LOAD    RD, QN          ; SGN: the quotient's and the remainder's signs
        LDN     RD
        ANI     80H
        PLO     RB
        LOAD    RD, DVS
        LDN     RD
        ANI     80H
        STR     R2
        GLO     RB
        XOR
        PHI     RB              ; RB.1: the quotient's, RB.0: the remainder's
        LOAD    RD, SGN
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LOAD    RD, QN
        LDN     RD
        ANI     80H
        LBZ     SD3
        SEP     R4
        DW      NEG4
SD3:    LOAD    RD, DVS
        LDN     RD
        ANI     80H
        LBZ     SD4
        SEP     R4
        DW      NEG4
SD4:    LOAD    RD, QN          ; Q = R9:RA, R = RB:RC = 0
        LDA     RD
        PHI     R9
        LDA     RD
        PLO     R9
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDI     0
        PHI     RB
        PLO     RB
        PHI     RC
        PLO     RC
        LOAD    RD, DCNT
        LDI     32
        STR     RD
SD5:    GLO     RA              ; R:Q << 1
        SHL
        PLO     RA
        GHI     RA
        SHLC
        PHI     RA
        GLO     R9
        SHLC
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        GLO     RC
        SHLC
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     RB
        SHLC
        PLO     RB
        GHI     RB
        SHLC
        PHI     RB
        LOAD    RF, DVS + 3     ; TT = R - DVS
        LOAD    RD, TT + 3
        SEX     RF
        GLO     RC
        SM
        STR     RD
        DEC     RD
        DEC     RF
        GHI     RC
        SMB
        STR     RD
        DEC     RD
        DEC     RF
        GLO     RB
        SMB
        STR     RD
        DEC     RD
        DEC     RF
        GHI     RB
        SMB
        STR     RD
        SEX     R2
        LBNF    SD6
        LDA     RD              ; it went: R = TT, Q + 1
        PHI     RB
        LDA     RD
        PLO     RB
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RA
        ORI     1
        PLO     RA
SD6:    LOAD    RD, DCNT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    SD5
        LOAD    RD, SGN         ; the signs
        LDN     RD
        LBZ     SD7
        GLO     RA
        SDI     0
        PLO     RA
        GHI     RA
        SDBI    0
        PHI     RA
        GLO     R9
        SDBI    0
        PLO     R9
        GHI     R9
        SDBI    0
        PHI     R9
SD7:    INC     RD
        LDN     RD
        LBZ     SD8
        GLO     RC
        SDI     0
        PLO     RC
        GHI     RC
        SDBI    0
        PHI     RC
        GLO     RB
        SDBI    0
        PLO     RB
        GHI     RB
        SDBI    0
        PHI     RB
SD8:    LOAD    RD, REM4
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        INC     RD
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R5
SDZERO: SEP     R4
        DW      EMSGR
        DB      'division by zero',0

; ---- phase 2's steps
; TRESET: the value stack empty (a statement or a test done) - the texts made for it are free again
TRESET: GLO     R8
        XRI     LOW(VSTK)
        LBNZ    TRS9
        GHI     R8
        XRI     HIGH(VSTK)
        LBNZ    TRS9
        LOAD    RD, TMPP
        LDI     HIGH(TMPH)
        STR     RD
        INC     RD
        LDI     LOW(TMPH)
        STR     RD
TRS9:   SEP     R5
XPOP:   SEP     R4
        DW      POP1
        LBR     TRESET
; XPUSHV: a -v value: a text that is a number if it looks like one (as a field)
XPUSHV: SEP     R4
        DW      PUSHE
        LDI     TFLD
        LBR     XPS2
; XEXIT: exit - this part stops (END comes next, unless this is END).  XNEXT: next - on to the next line.
XEXIT:  LOAD    RD, EXITF
        LDI     1
        STR     RD
XNEXT:  LOAD    R7, KONE        ; (a 0: RUNC's ORET)
        SEP     R5
; XPRINTF n: n values off the stack, the first the format: its text out, each %[-][0][width][.precision]c
;            taking the next value - c: d i u (a whole number), s (text), c (a character), x X (hex), %
XPRINTF: LDA    R7
        PLO     RB
        LOAD    RD, PRN
        GLO     RB
        STR     RD
XPF1:   SEP     R4              ; R8 down to the format
        DW      POP1
        DEC     RB
        GLO     RB
        LBNZ    XPF1
        GLO     R8              ; PRP: the value after it
        ADI     5
        PLO     RB
        GHI     R8
        ADCI    0
        PHI     RB
        LOAD    RD, PRP
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        GHI     R8
        PHI     RF
        GLO     R8
        PLO     RF
        SEP     R4
        DW      TOSTR
        INC     RF
        LOAD    RD, FMTP
        LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        INC     RD              ; (FMTL)
        LDN     RF
        STR     RD
XPF2:   SEP     R4
        DW      FGETC
        LBDF    XPF9
        XRI     '%'
        LBZ     XPF3
        XRI     '%'
XPFOUT: SEP     R4
        DW      OUTC
        LBR     XPF2
XPF3:   LOAD    RD, PFL         ; no flags, no width, no precision
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        LDI     0FFH
        STR     RD
XPF4:   SEP     R4
        DW      FGETC
        LBDF    XPFPC
        XRI     '-'
        LBNZ    XPF5
        LDI     1
        LBR     XPF5A
XPF5:   XRI     '-' XOR '0'
        LBNZ    XPF5B
        LDI     2
        LBR     XPF5A
XPF5B:  XRI     '0' XOR '+'
        LBNZ    XPF6
        LDI     4
XPF5A:  STR     R2
        LOAD    RD, PFL
        LDN     RD
        OR
        STR     RD
        LBR     XPF4
XPF6:   LOAD    RD, PWID        ; the width
        SEP     R4
        DW      DIGIT
        LBNF    XPF7
        SEP     R4
        DW      FGETC
        LBDF    XPFPC
        LBR     XPF6
XPF7:   LOAD    RD, FCH         ; .precision
        LDN     RD
        XRI     '.'
        LBNZ    XPF8
        LOAD    RD, PPREC
        LDI     0
        STR     RD
XPF7A:  SEP     R4
        DW      FGETC
        LBDF    XPFPC
        LOAD    RD, PPREC
        SEP     R4
        DW      DIGIT
        LBDF    XPF7A
XPF8:   LOAD    RD, FCH         ; the conversion
        LDN     RD
        XRI     'd'
        LBZ     XPFD
        XRI     'd' XOR 'i'
        LBZ     XPFD
        XRI     'i' XOR 'u'
        LBZ     XPFD
        XRI     'u' XOR 's'
        LBZ     XPFS
        XRI     's' XOR 'c'
        LBZ     XPFC
        XRI     'c' XOR 'x'
        LBZ     XPFX
        XRI     'x' XOR 'X'
        LBZ     XPFX
        XRI     'X' XOR '%'
        LBZ     XPFPC
        LDI     '%'             ; not one RAWK knows: as it is
        SEP     R4
        DW      OUTC
        LOAD    RD, FCH
        LDN     RD
        LBR     XPFOUT
XPFPC:  LDI     '%'
        LBR     XPFOUT
XPF9:   LBR     TRESET
; FGETC: the format's next character -> D and FCH (DF = 1: no more)
FGETC:  LOAD    RD, FMTL
        LDN     RD
        LBZ     FGNO
        SMI     1
        STR     RD
        LOAD    RD, FMTP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDA     RF
        STR     R2
        GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        LOAD    RD, FCH
        LDN     R2
        STR     RD
        ADI     0               ; (DF = 0)
        SEP     R5
FGNO:   LDI     1
        SHR
        SEP     R5
; DIGIT: FCH a digit? DF = 1: M(RD) = M(RD) x 10 + it.  RD kept; uses RF.
DIGIT:  LOAD    RF, FCH
        LDN     RF
        SMI     '0'
        LBNF    DGN
        SMI     10
        LBDF    DGN
        LDN     RD
        SHL
        STR     R2
        SHL
        SHL
        ADD
        STR     R2
        LDN     RF
        SMI     '0'
        ADD
        STR     RD
        LDI     1
        SHR
        SEP     R5
DGN:    LDI     0
        SHR
        SEP     R5
; NEXTV: RF -> the next value in the list (none left: an empty one)
NEXTV:  LOAD    RD, PRN
        LDN     RD
        SMI     1
        LBZ     NXV2
        STR     RD
        LOAD    RD, PRP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        ADI     5
        STR     RD
        DEC     RD
        GHI     RF
        ADCI    0
        STR     RD
        SEP     R5
NXV2:   LOAD    RF, XVAL
        LDI     TUN
        STR     RF
        SEP     R5
; %d: the number's digits (its - in PSG); precision: at least that many digits
XPFD:   SEP     R4
        DW      NEXTV
        SEP     R4
        DW      TONUM
        INC     RF
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        SEP     R4
        DW      NTOS            ; -> RA, RB.0
        LDI     0
        PLO     RC              ; the sign: -, or + with the + flag
        LOAD    RD, PFL
        LDN     RD
        ANI     4
        LBZ     XPD1
        LDI     '+'
        PLO     RC
XPD1:   LDN     RA
        XRI     '-'
        LBNZ    XPNUM
        INC     RA
        DEC     RB
        LDI     '-'
        PLO     RC
XPNUM:  LOAD    RD, PSG         ; a number's text at RA (RB.0): the sign RC.0 first
        GLO     RC
        STR     RD
        INC     RD              ; PNZ = precision - digits (if more)
        LDI     0
        STR     RD
        LOAD    RF, PPREC
        LDN     RF
        XRI     0FFH
        LBZ     XPEMIT
        LDN     RF
        STR     R2
        GLO     RB
        SD
        LBNF    XPEMIT
        STR     RD
        LOAD    RF, PFL         ; (a precision: the 0 flag does nothing)
        LDN     RF
        ANI     5
        STR     RF
        LBR     XPEMIT
; %x %X: hex digits (32 bits)
XPFX:   SEP     R4
        DW      NEXTV
        SEP     R4
        DW      TONUM
        INC     RF
        LOAD    RA, HEXB
        LDI     4
        PLO     RC
XPX1:   LDN     RF              ; two digits a byte
        SHR
        SHR
        SHR
        SHR
        SEP     R4
        DW      HEXD
        LDA     RF
        ANI     0FH
        SEP     R4
        DW      HEXD
        DEC     RC
        GLO     RC
        LBNZ    XPX1
        LOAD    RA, HEXB        ; past leading 0s (one digit at least)
        LDI     8
        PLO     RB
XPX2:   GLO     RB
        XRI     1
        LBZ     XPX3
        LDN     RA
        XRI     '0'
        LBNZ    XPX3
        INC     RA
        DEC     RB
        LBR     XPX2
XPX3:   LDI     0
        PLO     RC
        LBR     XPNUM
; HEXD: D (0-15) as a hex digit at RA (FCH X: capitals) - RA + 1. Uses RB.0, RD.
HEXD:   ADI     0F6H            ; 10 and up: DF
        LBNF    HXD2
        ADI     'a' - '0' - 10
        PLO     RB
        LOAD    RD, FCH
        LDN     RD
        XRI     'X'
        LBNZ    HXD1
        GLO     RB
        SMI     20H
        PLO     RB
HXD1:   GLO     RB
HXD2:   ADI     '0' + 10
        STR     RA
        INC     RA
        SEP     R5
; %s: the text (precision: at most that many characters)
XPFS:   SEP     R4
        DW      NEXTV
        SEP     R4
        DW      TOSTR
        INC     RF
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA
        LDN     RF
        PLO     RB
        LOAD    RF, PPREC
        LDN     RF
        STR     R2
        GLO     RB
        SM
        LBNF    XPS3
        LDN     R2
        PLO     RB
XPS3:   LOAD    RF, PFL         ; (no 0s for a text)
        LDN     RF
        ANI     1
        STR     RF
        LDI     0
        LBR     XPNUM2
; %c: a number: that character; a text: its first
XPFC:   SEP     R4
        DW      NEXTV
        SEP     R4
        DW      CLASS
        LDN     RF
        XRI     TNUM
        LBZ     XPC2
        LDN     RF
        XRI     TSN
        LBZ     XPC2
        SEP     R4
        DW      TOSTR
        INC     RF
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA
        LDN     RF
        LBZ     XPC3
        LDI     1
XPC3:   PLO     RB
        LBR     XPS3
XPC2:   SEP     R4
        DW      TONUM
        INC     RF
        INC     RF
        INC     RF
        INC     RF
        LOAD    RA, CHB
        LDN     RF
        STR     RA
        LDI     1
        PLO     RB
        LBR     XPS3
XPNUM2: LOAD    RD, PSG         ; no sign, no 0s
        LDI     0
        STR     RD
        INC     RD
        STR     RD
; XPEMIT: PSG, then PNZ 0s, then the text at RA (RB.0) - spaces to the width (after it with -; with the
;         0 flag 0s after the sign instead)
XPEMIT: LOAD    RD, PSG         ; RC.0 = the width - all of it (0 if none over)
        LDN     RD
        LBZ     XPE1
        LDI     1
XPE1:   INC     RD
        SEX     RD
        ADD                     ; + PNZ
        SEX     R2
        STR     R2
        GLO     RB
        ADD
        STR     R2
        LOAD    RD, PWID
        LDN     RD
        SM
        LBDF    XPE2
        LDI     0
XPE2:   PLO     RC
        LOAD    RD, PFL
        LDN     RD
        ANI     3
        LBNZ    XPE3
        SEP     R4              ; right, spaces first
        DW      XPSP
XPE3:   LOAD    RD, PSG
        LDN     RD
        LBZ     XPE4
        SEP     R4
        DW      OUTC
XPE4:   LOAD    RD, PFL         ; the 0 flag (not with -): 0s for the width
        LDN     RD
        ANI     3
        XRI     2
        LBNZ    XPE5
        LOAD    RD, PNZ
        GLO     RC
        SEX     RD
        ADD
        SEX     R2
        STR     RD
        LDI     0
        PLO     RC
XPE5:   LOAD    RD, PNZ
        LDN     RD
        PLO     RD              ; (OUTC keeps RD, but not RE)
XPE6:   GLO     RD
        LBZ     XPE7
        LDI     '0'
        SEP     R4
        DW      OUTC
        DEC     RD
        LBR     XPE6
XPE7:   GLO     RB              ; the text
        LBZ     XPE8
        LDA     RA
        SEP     R4
        DW      OUTC
        DEC     RB
        LBR     XPE7
XPE8:   LOAD    RD, PFL         ; -: spaces after it
        LDN     RD
        ANI     1
        LBZ     XPF2
        SEP     R4
        DW      XPSP
        LBR     XPF2
; XPSP: RC.0 spaces (RC.0 = 0 after)
XPSP:   GLO     RC
        LBZ     XSP9
        LDI     ' '
        SEP     R4
        DW      OUTC
        DEC     RC
        LBR     XPSP
XSP9:   SEP     R5
; XSUBSTR n: substr(s, m [, l]) as the Mac's awk: m below 1 is 1 (l as it is), past the end gives "";
;            l below 0 is 0; the part of s from m, l long at most (no copy)
XSUBSTR: LDA    R7
        XRI     3
        LBNZ    XSB2
        SEP     R4              ; l -> SUBN (0-255)
        DW      TOSRF
        SEP     R4
        DW      BYTEV
        LBNF    XSB1
        LDI     0
XSB1:   PLO     RE
        LOAD    RD, SUBN
        GLO     RE
        STR     RD
        SEP     R4
        DW      POP1
        LBR     XSB3
XSB2:   LOAD    RD, SUBN        ; no l: all the rest
        LDI     0FFH
        STR     RD
XSB3:   SEP     R4              ; m -> SUBM (1-255)
        DW      TOSRF
        SEP     R4
        DW      BYTEV
        LBDF    XSB3A           ; below 1: 1
        LBNZ    XSB4
XSB3A:  LDI     1
XSB4:   PLO     RE
        LOAD    RD, SUBM
        GLO     RE
        STR     RD
        SEP     R4
        DW      POP1
        SEP     R4              ; s
        DW      TOSRF
        SEP     R4
        DW      TOSTR
        INC     RF
        INC     RF
        INC     RF
        LDN     RF              ; its length
        PLO     RB
        LOAD    RD, SUBM        ; past the end?
        LDN     RD
        SMI     1
        STR     R2
        GLO     RB
        SM                      ; length - (m - 1): what is left from m
        LBDF    XSB5
        LDI     0
XSB5:   STR     R2
        LOAD    RD, SUBN        ; the length: l, at most that
        LDN     RD
        SD
        LBNF    XSB6            ; less than l left: that
        LDN     RD
        STR     R2
XSB6:   LDN     R2
        STR     RF              ; the new length
        DEC     RF              ; the start + m - 1 (m past the end: no characters, so it does not matter)
        LOAD    RD, SUBM
        LDN     RD
        SMI     1
        STR     R2
        LDN     RF
        ADD
        STR     RF
        DEC     RF
        LDN     RF
        ADCI    0
        STR     RF
        DEC     RF
        LDI     TSTR
        STR     RF
        SEP     R5
; BYTEV: the value at RF as a number 0-255: D (more: 255); DF = 1: below 0.  Z: 0.
BYTEV:  SEP     R4
        DW      TONUM
        INC     RF
        LDN     RF
        ANI     80H
        LBNZ    BYV8
        LDA     RF
        STR     R2
        LDA     RF
        OR
        STR     R2
        LDA     RF
        OR
        LBNZ    BYV7
        LDN     RF
        LBR     BYV9
BYV7:   LDI     0FFH
        LBR     BYV9
BYV8:   LDI     1
        SHR
        LDI     0
        SEP     R5
BYV9:   PLO     RE
        LDI     0
        SHR
        GLO     RE
        SEP     R5
; XINDEX: index(s, t): where t first starts in s (1 ..), 0 if not there (as the Mac's awk: t "" is at 1,
;         unless s is "" too)
XINDEX: SEP     R4
        DW      TXT2            ; RA, RB.0 = s; RC, RB.1 = t
        LDI     1
        PLO     RE              ; RE.0 = the place
        GLO     RB
        LBZ     XIX0
XIX1:   GHI     RB              ; t past the end of s?
        STR     R2
        GLO     RB
        SM
        LBNF    XIX0
        GHI     RA              ; compare t here
        PHI     R9
        GLO     RA
        PLO     R9
        GHI     RC
        PHI     RF
        GLO     RC
        PLO     RF
        GHI     RB
        PHI     RD
XIX2:   GHI     RD
        LBZ     XIX4            ; all of it: found
        LDA     R9
        STR     R2
        LDA     RF
        XOR
        LBNZ    XIX3
        GHI     RD
        SMI     1
        PHI     RD
        LBR     XIX2
XIX4:   GLO     RE
        LBR     XCR3
XIX3:   INC     RA
        DEC     RB
        INC     RE
        LBR     XIX1
XIX0:   LDI     0
        LBR     XCR3
; XTOUP / XTOLOW: the top value as text, in capitals / small letters (a new text)
XTOUP:  LDI     0
        LSKP
XTOLOW: LDI     1
        STXD                    ; (a call uses RE.0)
        SEP     R4
        DW      TOSRF
        SEP     R4
        DW      TOSTR
        INC     RF
        LDA     RF
        PHI     R9
        LDA     RF
        PLO     R9
        LDN     RF
        PLO     RB
        GLO     RB
        SEP     R4
        DW      TALLOC          ; -> RA (uses RC, RE)
        IRX
        LDX
        PLO     RE
        DEC     RF              ; the value: the new text
        GLO     RA
        STR     RF
        DEC     RF
        GHI     RA
        STR     RF
        DEC     RF
        LDI     TSTR
        STR     RF
        GLO     RB
        PLO     RD
XTU1:   GLO     RD
        LBZ     XTU9
        LDA     R9
        PLO     RC
        GLO     RE
        LBNZ    XTU3
        GLO     RC              ; a-z -> A-Z
        SMI     'a'
        LBNF    XTU5
        SMI     26
        LBDF    XTU5
        GLO     RC
        SMI     20H
        LBR     XTU6
XTU3:   GLO     RC              ; A-Z -> a-z
        SMI     'A'
        LBNF    XTU5
        SMI     26
        LBDF    XTU5
        GLO     RC
        ADI     20H
        LBR     XTU6
XTU5:   GLO     RC
XTU6:   STR     RA
        INC     RA
        DEC     RD
        LBR     XTU1
XTU9:   SEP     R5

; ======== -o NAME: the output file
; OOPEN: ONAME in OWDIR: there already - "replace it?" (ESEC/EPTR its entry, OLDCL its clusters); new - a free
;        entry (DSLOT). The old file stays until OCLOSE switches the entry.
OOPEN:  SEP     R4
        DW      ONSET
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    OO2
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    KS_ISDIR
        LOAD    RD, ESEC        ; its entry: its sector, where in DIRBUF; its clusters
        LOAD    RC, KS_DSEC
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        INC     RD
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, OLDCL
        LOAD    RC, KS_DCLUS
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        LOAD    RD, REPL
        LDI     1
        STR     RD
        SEP     R4              ; (the question on the screen, even with the output in a file)
        DW      K_TTYON
        SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ' is already on the card - replace it? (Y/N) ',0
        SEP     R4
        DW      K_YESNO
        LBNF    OONO
        LBR     OO3
OONO:   SEP     R4
        DW      K_PIN
        DB      'Nothing written.',0DH,0AH,0
        LBR     K_MAIN
OO2:    SEP     R4              ; a new file: a free entry (a folder may grow by a cluster for it)
        DW      KS_DSLOT
        LBNF    OO2A
        SEP     R4
        DW      K_PIN
        DB      'The directory is full.',0DH,0AH,0
        LBR     K_MAIN
OO2A:   LOAD    RD, ESEC
        LOAD    RC, KS_WDSEC    ; WDSEC, WDPTR
        LDI     4
        PLO     RB
OO2B:   LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    OO2B
OO3:    LOAD    RD, OPTR        ; nothing in OBUF yet
        LDI     HIGH(OBUF)
        STR     RD
        INC     RD
        LDI     LOW(OBUF)
        STR     RD
        SEP     R5
; ONSET: KS_FNAME = ONAME, KS_WDIR = OWDIR
ONSET:  LOAD    RD, ONAME
        LOAD    RC, KS_FNAME
        LDI     11
        PLO     RB
ONS1:   LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    ONS1
        LOAD    RD, OWDIR
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R5
; OUTC: D on the screen, or (-o) into OBUF - a full one written as the file's next sector. Every register kept.
OUTC:   PLO     RE
        GHI     RD
        STXD
        GLO     RD
        STXD
        GHI     RF
        STXD
        GLO     RF
        STXD
        LOAD    RD, OMODE
        LDN     RD
        LBZ     OUSCR
        INC     RD              ; (OPTR follows OMODE)
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     RE
        STR     RF
        INC     RF
        GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        XRI     HIGH(OBUF + 512)
        LBNZ    OU9
        GLO     RF
        XRI     LOW(OBUF + 512)
        LBNZ    OU9
        SEP     R4
        DW      OFLUSH
OU9:    IRX
        LDXA
        PLO     RF
        LDXA
        PHI     RF
        LDXA
        PLO     RD
        LDX
        PHI     RD
        SEP     R5
OUSCR:  IRX
        LDXA
        PLO     RF
        LDXA
        PHI     RF
        LDXA
        PLO     RD
        LDX
        PHI     RD
        GLO     RE
        XRI     0AH
        LBZ     OUNL
        GLO     RE
        LBR     K_OUT           ; (the kernel's: the screen, or a file with > - F_TYPE straight would miss it)
OUNL:   GHI     RA              ; a line's end: a new line (a screen at a time); RA RB RF kept
        STXD
        GLO     RA
        STXD
        GHI     RB
        STXD
        GLO     RB
        STXD
        GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      NEWLN
        IRX
        LDXA
        PLO     RF
        LDXA
        PHI     RF
        LDXA
        PLO     RB
        LDXA
        PHI     RB
        LDXA
        PLO     RA
        LDX
        PHI     RA
        SEP     R5
; OFLUSH: OBUF (512 bytes) as the file's next sector; SIZE + 512; OPTR = OBUF. Registers kept.
OFLUSH: GHI     R7
        STXD
        GLO     R7
        STXD
        GHI     R8
        STXD
        GLO     R8
        STXD
        GHI     R9
        STXD
        GLO     R9
        STXD
        GHI     RA
        STXD
        GLO     RA
        STXD
        GHI     RB
        STXD
        GLO     RB
        STXD
        GHI     RC
        STXD
        GLO     RC
        STXD
        GHI     RD
        STXD
        GLO     RD
        STXD
        GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      WRBLK
        LBNF    OF2
        XRI     2
        LBNZ    OF1
        SEP     R4
        DW      EMSGR
        DB      'the card is full - nothing saved',0
OF1:    SEP     R4
        DW      EMSGR
        DB      'the card did not answer - nothing saved',0
OF2:    LOAD    RD, SIZE + 2    ; SIZE + 512
        LDN     RD
        ADI     2
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, OPTR
        LDI     HIGH(OBUF)
        STR     RD
        INC     RD
        LDI     LOW(OBUF)
        STR     RD
        IRX
        LDXA
        PLO     RF
        LDXA
        PHI     RF
        LDXA
        PLO     RD
        LDXA
        PHI     RD
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDXA
        PLO     RB
        LDXA
        PHI     RB
        LDXA
        PLO     RA
        LDXA
        PHI     RA
        LDXA
        PLO     R9
        LDXA
        PHI     R9
        LDXA
        PLO     R8
        LDXA
        PHI     R8
        LDXA
        PLO     R7
        LDX
        PHI     R7
        SEP     R5
; WRBLK: OBUF's 512 bytes as the file's next sector (a new cluster when this one is full). DF = 1 + D:
;        2 the card is full, 3 the card failed (XFER's)
WRBLK:  LOAD    RD, WSLEFT
        LDN     RD
        LBNZ    WB4
        SEP     R4              ; a cluster for the next part
        DW      KS_FREECL
        LBDF    WBFULL
        LOAD    RD, NEWC
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    R9, 0FFFFH      ; it ends the chain ...
        SEP     R4
        DW      KS_FATPUT
        LBDF    WBERR
        LOAD    RD, WPREV       ; ... and the last one points at it (or it is the first)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, NEWC
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        GHI     RC
        LBNZ    WB2
        GLO     RC
        LBNZ    WB2
        LOAD    RD, WFIRST
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LBR     WB3
WB2:    SEP     R4
        DW      KS_FATPUT
        LBDF    WBERR
WB3:    LOAD    RD, NEWC        ; WPREV = it; WLBA = its first sector, WSLEFT = its sectors
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, WPREV
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      KS_CL2LBA
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_ST32
        LOAD    RD, KS_SPC
        LDN     RD
        PLO     RB
        LOAD    RD, WSLEFT
        GLO     RB
        STR     RD
WB4:    LOAD    RD, WLBA        ; the sector
        SEP     R4
        DW      KS_LD32
        LOAD    RF, OBUF
        SEP     R4
        DW      KS_IDEWR
        LBDF    WBERR
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_LD32
        LOAD    RC, 1
        SEP     R4
        DW      KS_ADD16
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_ST32
        LOAD    RD, WSLEFT
        LDN     RD
        SMI     1
        STR     RD
        LDI     0
        SHR
        SEP     R5
WBFULL: LDI     2
        LSKP
WBERR:  LDI     3
        SMI     0               ; DF = 1, D kept
        SEP     R5
; OCLOSE: the last part of OBUF (0s after it) written; the FAT; the entry (the switch), then the old file's
;         clusters; "Saved NAME, N bytes."
OCLOSE: LOAD    RD, OPTR        ; RC = the bytes in OBUF; SIZE + them
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        SMI     LOW(OBUF)
        PLO     RC
        GHI     RC
        SMBI    HIGH(OBUF)
        PHI     RC
        LOAD    RD, SIZE + 3
        GLO     RC
        STR     R2
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        GHI     RC
        STR     R2
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        GHI     RC              ; any? then 0s to the sector's end, and it is written
        LBNZ    OC1
        GLO     RC
        LBZ     OC3
OC1:    LOAD    RD, OPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
OC2:    LDI     0
        STR     RF
        INC     RF
        GHI     RF
        XRI     HIGH(OBUF + 512)
        LBNZ    OC2
        GLO     RF
        XRI     LOW(OBUF + 512)
        LBNZ    OC2
        LOAD    RD, SIZE        ; (OFLUSH adds 512: taken off again first)
        SEP     R4
        DW      SUB512
        SEP     R4
        DW      OFLUSH
OC3:    SEP     R4
        DW      KS_FATFLUSH
        LBDF    OCERR
        SEP     R4              ; its folder
        DW      ONSET
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRRD
        LBDF    OCERR
        SEP     R4
        DW      KS_STAMP
        LOAD    RD, EPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, ONAME       ; 0-10 the name
        LDI     11
        PLO     RB
OC4:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    OC4
        LDI     20H             ; 11 archive; 12, 13
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 14-17 created
        DW      KS_PUTST
        LOAD    RD, KS_STD      ; 18-19 used
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LDI     0               ; 20-21
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 22-25 written
        DW      KS_PUTST
        LOAD    RD, WFIRST      ; 26-27 the first cluster, 28-31 the size (little-endian)
        LDA     RD
        PHI     RC
        LDN     RD
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        LOAD    RD, SIZE + 3
        LDI     4
        PLO     RB
OC5:    LDN     RD
        STR     RF
        INC     RF
        DEC     RD
        DEC     RB
        GLO     RB
        LBNZ    OC5
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    OCERR
        LOAD    RD, WFIRST      ; it is saved: nothing to give back now
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, REPL        ; the old file's clusters
        LDN     RD
        LBZ     OC6
        LOAD    RD, OLDCL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_FREECH
OC6:    SEP     R4
        DW      K_PIN
        DB      'Saved ',0
        SEP     R4
        DW      ONSET
        SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ', ',0
        LOAD    RD, SIZE
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      ' bytes.',0DH,0AH,0
        SEP     R5
OCERR:  SEP     R4
        DW      EMSGR
        DB      'the card did not answer - nothing saved',0
; SUB512: the 4 bytes at RD - 512
SUB512: INC     RD
        INC     RD
        LDN     RD
        SMI     2
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        SEP     R5

        INCL    "tools.inc"
        INCL    "flist.inc"

; SPECIAL: the text at RA (RB.0 long) has a pattern character RAWK cannot do yet: ( ) |? DF = 1: yes.
;          RA, RB, RF kept.
SPECIAL: GHI    RA
        PHI     RC
        GLO     RA
        PLO     RC
        GLO     RB
        PLO     RD
SPC1:   GLO     RD
        LBZ     SPC9
        LDA     RC
        STR     R2
        LOAD    R9, SPCH
SPC2:   LDA     R9
        LBZ     SPC3
        XOR
        LBNZ    SPC2
        LDI     1
        SHR
        SEP     R5
SPC3:   DEC     RD
        LBR     SPC1
SPC9:   LDI     0
        SHR
        SEP     R5
SPCH:   DB      '()|',0

; ======== compiling (CBEG to PEND: only until the program is compiled - the buffers for running it
;          (LBUF, FLDS, VSTK, VHEAP, FLBUF) are on top of it from then on) ========
CBEG:
; SELBUF: D = 0 BEGIN's, 1 the main rules', 2 END's steps from here on. The three share one buffer (STEPB), each
;         a chain of pieces: leaving one, OJ and a hole (its SHOLE); back to it, that hole -> here.
SELBUF: PLO     RB
        LOAD    RD, CURK
        LDN     RD
        STR     R2
        GLO     RB
        XOR
        LBZ     SB9             ; the same one
        LDN     RD
        XRI     0FFH
        LBZ     SB2             ; none yet
        LDI     OJ
        SEP     R4
        DW      EMIT1
        SEP     R4
        DW      EMHOLE          ; RD = the hole (RB kept)
        LOAD    RF, CURK
        LDN     RF
        SHL
        ADI     LOW(SHOLE)
        PLO     RF
        LDI     HIGH(SHOLE)
        ADCI    0
        PHI     RF
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
SB2:    LOAD    RD, CURK
        GLO     RB
        STR     RD
        SHL
        ADI     LOW(SHOLE)
        PLO     RF
        LDI     HIGH(SHOLE)
        ADCI    0
        PHI     RF
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LBR     PATCH           ; its last hole -> here
SB9:    SEP     R5

; EMIT1: D into the steps (EMP + 1); LVAL, FLV = 0. Uses RD, RF.
EMIT1:  STXD
        LOAD    RD, EMP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, EML         ; full?
        LDN     RD
        STR     R2
        GHI     RF
        XOR
        LBZ     EMFULL
        IRX
        LDX
        STR     RF
        INC     RF
        LOAD    RD, EMP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, LVAL
        LDI     0
        STR     RD
        INC     RD              ; (FLV)
        STR     RD
        SEP     R5
EMFULL: SEP     R4
        DW      EMSGR
        DB      'the program is too long',0
; EMITD: RD's two bytes (high first).  EMHOLE: two bytes to fill in later - RD = where they are.
EMITD:  GLO     RD
        STXD
        GHI     RD
        SEP     R4
        DW      EMIT1
        IRX
        LDX
        SEP     R4
        DW      EMIT1
        SEP     R5
EMHOLE: LOAD    RD, EMP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        STXD
        GLO     RC
        STXD
        LDI     0
        SEP     R4
        DW      EMIT1
        LDI     0
        SEP     R4
        DW      EMIT1
        IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        SEP     R5
; PATCH: the hole at RD = EMP (the next step's place)
PATCH:  LOAD    RF, EMP
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        SEP     R5

; ---- NEXT: the next token -> TOKT (TOKV: a number, or TOKV+3 a variable; TOKS / TOKL: a text in CONB);
;      LASTT = the one before; TOKP = where it starts. Uses RA-RD, RF.
NEXT:   LOAD    RD, TOKT
        LDN     RD
        INC     RD              ; (LASTT)
        STR     RD
        LOAD    RD, SRCP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
LX0:    LDN     RF              ; spaces, tabs, CRs; # to the line's end; a \ just before a line's end
        XRI     ' '
        LBZ     LX0S
        XRI     ' ' XOR 9
        LBZ     LX0S
        XRI     9 XOR 0DH
        LBZ     LX0S
        XRI     0DH XOR '#'
        LBZ     LXCOM
        XRI     '#' XOR 5CH
        LBNZ    LX1
        GHI     RF              ; \: the line goes on (else it is a character RAWK cannot use)
        PHI     RA
        GLO     RF
        PLO     RA
        INC     RF
        LDN     RF
        XRI     0DH
        LBNZ    LX0C
        INC     RF
LX0C:   LDN     RF
        XRI     0AH
        LBZ     LX0S
        GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        LBR     LX1
LX0S:   INC     RF
        LBR     LX0
LXCOM:  INC     RF              ; (the line's end stays: it ends the statement)
        LDN     RF
        LBZ     LX1
        XRI     0AH
        LBNZ    LXCOM
LX1:    LOAD    RD, TOKP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDN     RF
        LBNZ    LX2
        LDI     TEOF
        LBR     LXSET
LX2:    XRI     0AH             ; a line's end
        LBNZ    LX2A
        INC     RF
        LDI     TNL
        LBR     LXSET
LX2A:   LDN     RF
        SMI     '0'             ; a digit: a number
        LBNF    LX3
        SMI     10
        LBNF    LXNUM
LX3:    LDN     RF              ; a letter or _: a name
        ANI     0DFH
        SMI     'A'
        LBNF    LX4
        SMI     26
        LBNF    LXNAME
LX4:    LDN     RF
        XRI     '_'
        LBZ     LXNAME
        XRI     '_' XOR '"'
        LBZ     LXSTR
        XRI     '"' XOR '/'
        LBNZ    LX5
        LOAD    RD, LASTT       ; '/': after a value it divides, else /text/ starts
        LDN     RD
        PLO     RB
        LOAD    RD, OPEND
LX4A:   LDA     RD
        LBZ     LXERE
        XRI     0FFH
        STR     R2
        GLO     RB
        XOR
        LBNZ    LX4A
LX5:    LOAD    RD, OPS2        ; two characters?
LX5A:   LDA     RD
        LBZ     LX6
        STR     R2
        LDN     RF
        XOR
        LBNZ    LX5B
        INC     RF
        LDN     RF
        DEC     RF
        STR     R2
        LDN     RD
        XOR
        LBNZ    LX5B
        INC     RD
        INC     RF
        INC     RF
        LDN     RD
        LBR     LXSET
LX5B:   INC     RD
        INC     RD
        LBR     LX5A
LX6:    LOAD    RD, OPS1        ; one
LX6A:   LDA     RD
        LBZ     LXBAD
        STR     R2
        LDN     RF
        XOR
        LBZ     LX6B
        INC     RD
        LBR     LX6A
LX6B:   INC     RF
        LDN     RD
LXSET:  PLO     RB              ; TOKT = D; SRCP = RF
        LOAD    RD, TOKT
        GLO     RB
        STR     RD
        LOAD    RD, SRCP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R5
LXBAD:  SEP     R4
        DW      EMSGN
        DB      'RAWK cannot use this character',0
; a number: its digits -> TOKV
LXNUM:  GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
        LDI     0
        PLO     RB
LXN1:   LDN     RF
        SMI     '0'
        LBNF    LXN2
        SMI     10
        LBDF    LXN2
        INC     RF
        INC     RB
        LBR     LXN1
LXN2:   LDN     RF
        XRI     '.'
        LBZ     LXNW
        LDN     RF
        ANI     0DFH
        XRI     'E'
        LBZ     LXNW
        GHI     RF
        STXD
        GLO     RF
        STXD
        LOAD    RD, TOKV
        SEP     R4
        DW      STRTON
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LDI     TNUMT
        LBR     LXSET
LXNW:   SEP     R4
        DW      EMSGN
        DB      'whole numbers only (SAWK does decimals)',0
; a name -> NBUF; a keyword, a built-in variable, or the program's own
LXNAME: LOAD    RD, NBUF
        LDI     0
        PLO     RB
LXA1:   LDN     RF
        XRI     '_'
        LBZ     LXA2
        LDN     RF
        SMI     '0'
        LBNF    LXA3
        SMI     10
        LBNF    LXA2
        LDN     RF
        ANI     0DFH
        SMI     'A'
        LBNF    LXA3
        SMI     26
        LBDF    LXA3
LXA2:   GLO     RB
        XRI     11
        LBZ     LXLONG
        LDA     RF
        STR     RD
        INC     RD
        INC     RB
        LBR     LXA1
LXLONG: SEP     R4
        DW      EMSGN
        DB      'a name is too long (11 letters at most)',0
LXA3:   LDI     0
        STR     RD
        GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      KWLOOK          ; -> DF = 0: RB.1 = its kind, RB.0 its value
        LBDF    LXA6
        GHI     RB
        LBNZ    LXA4
        GLO     RB              ; a keyword: its token
        LBR     LXA9
LXA4:   XRI     1
        LBZ     LXA4B
        XRI     1 XOR 3
        LBNZ    LXLATER
        GLO     RB              ; a function: TOKV+3 = its step
        PLO     RB
        LOAD    RD, TOKV + 3
        GLO     RB
        STR     RD
        LDI     TFN
        LBR     LXA9
LXA4B:  GLO     RB              ; a built-in variable
        LBR     LXA8
LXLATER: SEP    R4
        DW      EMSG
        DB      0
        LOAD    RA, NBUF
        SEP     R4
        DW      PRSTR
        SEP     R4
        DW      K_PIN
        DB      ' comes in a later version',0
        LBR     NEAR
LXA6:   SEP     R4              ; the program's own: found, or added
        DW      VFIND
        LBDF    LXMANY
        GLO     RB
LXA8:   PLO     RB              ; TOKV+3 = the variable
        LOAD    RD, TOKV + 3
        GLO     RB
        STR     RD
        LDI     TNAME
LXA9:   PLO     RB
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        GLO     RB
        LBR     LXSET
LXMANY: SEP     R4
        DW      EMSGN
        DB      'too many variables',0
; VFIND: the name in NBUF, one of the program's own variables: found, or added -> RB.0 (DF = 1: too many)
VFIND:  LOAD    RD, NVARS
        LDN     RD
        PLO     RC              ; RC.0 = the count
        LDI     0
        PLO     RB              ; RB.0 = this one
VF1:    GLO     RB
        STR     R2
        GLO     RC
        XOR
        LBZ     VFADD
        GLO     RB
        SEP     R4
        DW      VNAME           ; -> RF
        LOAD    RD, NBUF
VF2:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    VF3
        LDN     R2
        LBNZ    VF2
        LDI     0               ; the same: DF = 0
        SHR
        SEP     R5
VF3:    INC     RB
        LBR     VF1
VFADD:  GLO     RC
        XRI     VMAX
        LBZ     VFMANY
        GLO     RC
        SEP     R4
        DW      VNAME
        LOAD    RD, NBUF
VF4:    LDA     RD
        STR     RF
        INC     RF
        LBNZ    VF4
        LOAD    RD, NVARS
        GLO     RC
        ADI     1
        STR     RD
        GLO     RC
        PLO     RB
        LDI     0
        SHR
        SEP     R5
VFMANY: LDI     1
        SHR
        SEP     R5
; VNAME: D = a variable -> RF = its name's place in VNAMES (12 bytes each: x 8 + x 4)
VNAME:  PLO     RF
        LDI     0
        PHI     RF
        GLO     RF              ; x 4
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
        PHI     RF
        GHI     RF
        STXD
        GLO     RF
        STXD
        GLO     RF              ; x 8
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF
        IRX                     ; + x 4
        GLO     RF
        ADD
        PLO     RF
        IRX
        GHI     RF
        ADC
        PHI     RF
        GLO     RF
        ADI     LOW(VNAMES)
        PLO     RF
        GHI     RF
        ADCI    HIGH(VNAMES)
        PHI     RF
        SEP     R5
; KWLOOK: NBUF in KWTAB? DF = 0: RB.1 = kind (0 a token, 1 a built-in variable, 2 not yet), RB.0 = value
KWLOOK: LOAD    RF, KWTAB
KW1:    LDN     RF
        LBZ     KWNO
        LOAD    RD, NBUF
KW2:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    KW3
        LDN     R2
        LBNZ    KW2
        LDA     RF              ; found
        PHI     RB
        LDN     RF
        PLO     RB
        LDI     0
        SHR
        SEP     R5
KW3:    DEC     RF              ; to its 0, then past kind and value
KW3A:   LDA     RF
        LBNZ    KW3A
        INC     RF
        INC     RF
        LBR     KW1
KWNO:   LDI     1
        SHR
        SEP     R5
; a "text": escapes \" \\ \/ \n \t -> CONB
LXSTR:  INC     RF
        SEP     R4
        DW      CONBEG          ; RC = CONP, RB.0 = 0
LXS1:   LDA     RF
        LBZ     LXSNC
        XRI     '"'
        LBZ     LXS9
        XRI     '"' XOR 5CH
        LBNZ    LXS3
        LDA     RF
        LBZ     LXSNC
        XRI     'n'
        LBNZ    LXS2
        LDI     0AH
        LBR     LXS4
LXS2:   XRI     'n' XOR 't'
        LBNZ    LXS2A
        LDI     9
        LBR     LXS4
LXS2A:  DEC     RF
        LDA     RF
        LBR     LXS4
LXS3:   DEC     RF
        LDA     RF
LXS4:   SEP     R4
        DW      CONPUT
        LBR     LXS1
LXS9:   SEP     R4
        DW      CONEND
        LDI     TSTRT
        LBR     LXSET
LXSNC:  SEP     R4
        DW      EMSGN
        DB      'a " is not closed',0
; a /text/: \/ is a /; plain characters only for now
LXERE:  INC     RF
        SEP     R4
        DW      CONBEG
LXE1:   LDA     RF
        LBZ     LXENC
        XRI     '/'
        LBZ     LXE9
        XRI     '/' XOR 5CH
        LBNZ    LXE3
        LDN     RF
        XRI     '/'
        LBNZ    LXE3
        INC     RF
LXE3:   DEC     RF
        LDA     RF
        SEP     R4
        DW      CONPUT
        LBR     LXE1
LXE9:   SEP     R4
        DW      CONEND
        LOAD    RD, TOKS
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        INC     RD
        LDN     RD
        PLO     RB
        SEP     R4
        DW      SPECIAL
        LBDF    LXESP
        LDI     TERE
        LBR     LXSET
LXENC:  SEP     R4
        DW      EMSGN
        DB      'a / is not closed',0
LXESP:  LBR     XMSP
; CONBEG: a text starts at CONP (TOKS).  CONPUT: D onto it.  CONEND: TOKL = its length; CONP past it.
CONBEG: LOAD    RD, CONP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, TOKS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LDI     0
        PLO     RB
        SEP     R5
CONPUT: STR     RC
        GHI     RC              ; full?
        XRI     HIGH(CONE)
        LBNZ    CP1
        GLO     RC
        XRI     LOW(CONE)
        LBZ     CPFULL
CP1:    GLO     RB
        XRI     0FFH
        LBZ     CPFULL
        INC     RC
        INC     RB
        SEP     R5
CPFULL: SEP     R4
        DW      EMSGN
        DB      'too much text in the program',0
CONEND: LOAD    RD, TOKL
        GLO     RB
        STR     RD
        LOAD    RD, CONP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
; NEAR: " near: " and the program from TOKP (24 characters at most), back to the prompt
NEAR:   SEP     R4
        DW      K_PIN
        DB      ' near: ',0
        LOAD    RD, TOKP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDI     24
        PLO     RB
NR1:    LDA     RF
        LBZ     RERR
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    NR1
        LBR     RERR

; the tokens after which '/' divides; two-character and one-character operators; the names
OPEND:  DB      TNUMT XOR 0FFH, TSTRT XOR 0FFH, TERE XOR 0FFH, TNAME XOR 0FFH, TRP XOR 0FFH
        DB      TLEN XOR 0FFH, TINC XOR 0FFH, TDEC XOR 0FFH, 0
OPS2:   DB      '<','=',TLE, '>','=',TGE, '=','=',TEQ, '!','=',TNE, '+','=',TADDA, '-','=',TSUBA
        DB      '*','=',TMULA, '/','=',TDIVA, '%','=',TMODA, '+','+',TINC, '-','-',TDEC
        DB      '&','&',TAND, '|','|',TOR, '!','~',TNMAT, 0
OPS1:   DB      '$',TDOL, '(',TLP, ')',TRP, '{',TLB, '}',TRB, ';',TSEMI, ',',TCOMMA, '!',TNOT
        DB      '+',TPLUS, '-',TMINUS, '*',TSTAR, '/',TSLASH, '%',TPCT, '<',TLT, '>',TGT, '=',TASG
        DB      '~',TMAT, 0
KWTAB:  DB      'BEGIN',0,0,TBEGIN, 'END',0,0,TEND, 'print',0,0,TPRINT, 'length',0,0,TLEN
        DB      'NR',0,1,0, 'NF',0,1,1, 'FNR',0,1,2, 'FILENAME',0,1,3, 'FS',0,1,4, 'OFS',0,1,5
        DB      'if',0,0,TIF, 'else',0,0,TELSE, 'while',0,0,TWHILE, 'for',0,0,TFOR, 'do',0,0,TDO
        DB      'break',0,0,TBREAK, 'continue',0,0,TCONT, 'next',0,0,TNEXT, 'nextfile',0,2,0
        DB      'exit',0,0,TEXIT, 'printf',0,0,TPRINTF
        DB      'getline',0,2,0, 'function',0,2,0, 'func',0,2,0, 'return',0,2,0, 'delete',0,2,0
        DB      'in',0,2,0, 'close',0,2,0, 'system',0,2,0, 'sprintf',0,2,0, 'substr',0,3,OSUBSTR
        DB      'index',0,3,OINDEX, 'split',0,2,0, 'sub',0,2,0, 'gsub',0,2,0, 'match',0,2,0
        DB      'tolower',0,3,OTOLOW, 'toupper',0,3,OTOUP, 'int',0,2,0, 'sqrt',0,2,0, 'exp',0,2,0
        DB      'log',0,2,0, 'sin',0,2,0, 'cos',0,2,0, 'atan2',0,2,0, 'rand',0,2,0, 'srand',0,2,0
        DB      'fflush',0,2,0, 'ORS',0,2,0, 'RS',0,2,0, 'OFMT',0,2,0, 'CONVFMT',0,2,0
        DB      'SUBSEP',0,2,0, 'RSTART',0,2,0, 'RLENGTH',0,2,0, 'ENVIRON',0,2,0, 'ARGC',0,2,0
        DB      'ARGV',0,2,0, 0

; ---- the parser: recursive descent; each part emits its steps (operands first). TOKT is the token ahead.
GETT:   LOAD    RD, TOKT
        LDN     RD
        SEP     R5
; PPROG: items until the end, ';' between them as wanted
PPROG:  SEP     R4
        DW      NEXT
PG1:    SEP     R4
        DW      GETT
        LBZ     PG9
        XRI     TSEMI
        LBZ     PG1A
        XRI     TSEMI XOR TNL
        LBNZ    PG2
PG1A:   SEP     R4
        DW      NEXT
        LBR     PG1
PG2:    SEP     R4
        DW      PITEM
        LBR     PG1
PG9:    SEP     R5
; PITEM: BEGIN { }, END { }, { } or pattern [{ }] - a pattern alone prints the line
PITEM:  SEP     R4
        DW      GETT
        XRI     TBEGIN
        LBNZ    PI2
        LDI     0
        LBR     PI2A
PI2:    XRI     TBEGIN XOR TEND
        LBNZ    PI3
        LOAD    RD, HASEND
        LDI     1
        STR     RD
        LDI     2
PI2A:   SEP     R4
        DW      SELBUF
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      SKIPNL
        SEP     R4
        DW      GETT
        XRI     TLB
        LBNZ    NOLB
PIACT:  SEP     R4
        DW      NEXT
        SEP     R4
        DW      PSTMTS
        SEP     R4
        DW      NEXT
        SEP     R5
NOLB:   SEP     R4
        DW      EMSGN
        DB      'a { is missing',0
PI3:    LDI     1
        SEP     R4
        DW      SELBUF
        LOAD    RD, HASMAIN
        LDI     1
        STR     RD
        SEP     R4
        DW      GETT
        XRI     TLB
        LBZ     PIACT
        SEP     R4              ; pattern: JF past its action
        DW      PEXPR
        LDI     OJF
        SEP     R4
        DW      EMIT1
        SEP     R4
        DW      EMHOLE
        GHI     RD
        STXD
        GLO     RD
        STXD
        SEP     R4
        DW      GETT
        XRI     TLB
        LBNZ    PI5
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PSTMTS
        SEP     R4
        DW      NEXT
        LBR     PI6
PI5:    SEP     R4
        DW      EPRT0
PI6:    IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        SEP     R4
        DW      PATCH
        SEP     R5
; EPRT0: the steps of "print" ($0)
EPRT0:  LDI     OPUSH0
        SEP     R4
        DW      EMIT1
        LDI     OFIELD
        SEP     R4
        DW      EMIT1
        LDI     OPRINT
        SEP     R4
        DW      EMIT1
        LDI     1
        LBR     EMIT1
; PSTMTS: statements up to the '}' (left as the token); ; or a line's end between them - none needed after
;         one that ended with its own (an if that looked for an else, a { } block)
PSTMTS: SEP     R4
        DW      GETT
        XRI     TSEMI
        LBZ     PSN
        XRI     TSEMI XOR TNL
        LBZ     PSN
        XRI     TNL XOR TRB
        LBZ     PS9
        XRI     TRB XOR TEOF
        LBNZ    PS3
        SEP     R4
        DW      EMSGN
        DB      'a } is missing',0
PSN:    SEP     R4
        DW      NEXT
        LBR     PSTMTS
PS3:    SEP     R4
        DW      PSTMT
        SEP     R4
        DW      GETT
        XRI     TSEMI
        LBZ     PSTMTS
        XRI     TSEMI XOR TNL
        LBZ     PSTMTS
        XRI     TNL XOR TRB
        LBZ     PS9
        LOAD    RD, LASTT
        LDN     RD
        XRI     TSEMI
        LBZ     PSTMTS
        XRI     TSEMI XOR TNL
        LBZ     PSTMTS
        XRI     TNL XOR TRB
        LBZ     PSTMTS
        LBR     SYNERR
PS9:    SEP     R5
; PSTMT: { ... }, if, while, do, for, break, continue, next, exit, print, printf, or an expression (dropped)
PSTMT:  SEP     R4
        DW      GETT
        XRI     TLB
        LBZ     YBLK
        XRI     TLB XOR TIF
        LBZ     YIF
        XRI     TIF XOR TWHILE
        LBZ     YWH
        XRI     TWHILE XOR TDO
        LBZ     YDO
        XRI     TDO XOR TFOR
        LBZ     YFOR
        XRI     TFOR XOR TBREAK
        LBZ     YBRK
        XRI     TBREAK XOR TCONT
        LBZ     YCON
        XRI     TCONT XOR TNEXT
        LBZ     YNXT
        XRI     TNEXT XOR TEXIT
        LBZ     YEXIT
        XRI     TEXIT XOR TPRINTF
        LBZ     YPRF
        XRI     TPRINTF XOR TPRINT
        LBZ     PST2
PSIMPL: SEP     R4              ; an expression, its value dropped
        DW      PEXPR
        LDI     OPOP
        LBR     EMIT1
; PBODY: the statement an if, else, while, do or for runs (new lines before it; a ; alone: nothing)
PBODY:  SEP     R4
        DW      SKIPNL
        SEP     R4
        DW      GETT
        XRI     TSEMI
        LBNZ    PSTMT
        LBR     NEXT
; SKIPNL: past line ends.  SKIPT: past line ends and ;s
SKIPNL: SEP     R4
        DW      GETT
        XRI     TNL
        LBNZ    SKN9
        SEP     R4
        DW      NEXT
        LBR     SKIPNL
SKN9:   SEP     R5
SKIPT:  SEP     R4
        DW      GETT
        XRI     TNL
        LBZ     SKT1
        XRI     TNL XOR TSEMI
        LBNZ    SKN9
SKT1:   SEP     R4
        DW      NEXT
        LBR     SKIPT
; YBLK: { statements }
YBLK:   SEP     R4
        DW      NEXT
        SEP     R4
        DW      PSTMTS
        LBR     NEXT
; PCOND: past the keyword, ( expression ) and the token after it
PCOND:  SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TLP
        LBNZ    NOLP
        SEP     R4
        DW      NEXT
        LBR     PPAREN
NOLP:   SEP     R4
        DW      EMSGN
        DB      'a ( is missing',0
; YIF: if (c) s [else s]  ->  c JF E; s; [J F; E: s; F:]
YIF:    SEP     R4
        DW      PCOND
        LDI     OJF
        SEP     R4
        DW      EMIT1
        SEP     R4
        DW      EMHOLE
        GHI     RD
        STXD
        GLO     RD
        STXD
        SEP     R4
        DW      PBODY
        SEP     R4
        DW      SKIPT
        SEP     R4
        DW      GETT
        XRI     TELSE
        LBNZ    YIF9
        LDI     OJ
        SEP     R4
        DW      EMIT1
        SEP     R4
        DW      EMHOLE          ; RD = the J's hole
        IRX                     ; RC = the JF's
        LDXA
        PLO     RC
        LDX
        PHI     RC
        GHI     RD
        STXD
        GLO     RD
        STXD
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R4
        DW      PATCH
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PBODY
YIF9:   IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        LBR     PATCH
; ---- loops: LOOPS holds one entry per loop open (6 bytes): where continue goes (0: not known yet), the
;      continue holes, the break holes - each a chain: a hole holds the one before it (0: the first)
; LPUSH: a loop starts; continue goes to RD (0: not known yet)
LPUSH:  LOAD    RF, LOOPSP
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        GHI     RC
        XRI     HIGH(LOOPSE)
        LBNZ    LPU1
        GLO     RC
        XRI     LOW(LOOPSE)
        LBNZ    LPU1
        SEP     R4
        DW      EMSGN
        DB      'loops nested too deep',0
LPU1:   GHI     RD
        STR     RC
        INC     RC
        GLO     RD
        STR     RC
        INC     RC
        LDI     0
        STR     RC
        INC     RC
        STR     RC
        INC     RC
        STR     RC
        INC     RC
        STR     RC
        INC     RC
        GLO     RC
        STR     RF
        DEC     RF
        GHI     RC
        STR     RF
        SEP     R5
; LTOP: RC = the innermost loop's entry (DF = 1: no loop open)
LTOP:   LOAD    RF, LOOPSP
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        GHI     RC
        XRI     HIGH(LOOPS)
        LBNZ    LTO1
        GLO     RC
        XRI     LOW(LOOPS)
        LBNZ    LTO1
        LDI     1
        SHR
        SEP     R5
LTO1:   GLO     RC
        SMI     6
        PLO     RC
        GHI     RC
        SMBI    0
        PHI     RC
        LDI     0
        SHR
        SEP     R5
; JCHAIN: the step D (OJ or OJF) and a hole, put on the chain at RC
JCHAIN: PLO     RE
        GHI     RC
        STXD
        GLO     RC
        STXD
        GLO     RE
        SEP     R4
        DW      EMIT1
        SEP     R4
        DW      EMHOLE          ; RD = the hole
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        LDA     RC              ; the hole = the chain's last
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        DEC     RD
        DEC     RC
        GHI     RD              ; the chain's last = the hole
        STR     RC
        INC     RC
        GLO     RD
        STR     RC
        DEC     RC
        SEP     R5
; PATCHC: every hole on the chain at RC -> here
PATCHC: LDA     RC
        PHI     RD
        LDN     RC
        PLO     RD
PCH1:   GHI     RD
        LBZ     PCH9
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        DEC     RD
        SEP     R4
        DW      PATCH
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        LBR     PCH1
PCH9:   SEP     R5
; LPOP: the loop ends here: its breaks -> here
LPOP:   SEP     R4
        DW      LTOP
        INC     RC
        INC     RC
        INC     RC
        INC     RC
        SEP     R4
        DW      PATCHC
        LOAD    RF, LOOPSP + 1
        LDN     RF
        SMI     6
        STR     RF
        DEC     RF
        LDN     RF
        SMBI    0
        STR     RF
        SEP     R5
; YWH: while (c) s  ->  T: c JF out; s; J T
YWH:    LOAD    RF, EMP
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      LPUSH
        SEP     R4
        DW      PCOND
        SEP     R4
        DW      LTOP
        INC     RC
        INC     RC
        INC     RC
        INC     RC
        LDI     OJF
        SEP     R4
        DW      JCHAIN
        SEP     R4
        DW      PBODY
YLOOP:  SEP     R4              ; J back to where continue goes; the breaks -> here
        DW      LTOP
        LDI     OJ
        SEP     R4
        DW      EMIT1
        LDA     RC
        PHI     RD
        LDN     RC
        PLO     RD
        SEP     R4
        DW      EMITD
        LBR     LPOP
; YDO: do s while (c)  ->  T: s; C: c JT T
YDO:    SEP     R4
        DW      NEXT
        LOAD    RF, EMP
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        GHI     RD
        STXD
        GLO     RD
        STXD
        LDI     0
        PHI     RD
        PLO     RD
        SEP     R4
        DW      LPUSH
        SEP     R4
        DW      PBODY
        SEP     R4
        DW      SKIPT
        SEP     R4
        DW      GETT
        XRI     TWHILE
        LBZ     YDO2
        SEP     R4
        DW      EMSGN
        DB      'a do needs its while',0
YDO2:   SEP     R4              ; continue -> here
        DW      LTOP
        INC     RC
        INC     RC
        SEP     R4
        DW      PATCHC
        SEP     R4
        DW      PCOND
        LDI     OJT
        SEP     R4
        DW      EMIT1
        IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        SEP     R4
        DW      EMITD
        LBR     LPOP
; YFOR: for (a; c; b) s  ->  a; C: c JF out; J S; B: b; J C; S: s; J B
YFOR:   SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TLP
        LBNZ    NOLP
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TSEMI
        LBZ     YF1
        SEP     R4
        DW      PSIMPL
YF1:    SEP     R4
        DW      PSEMI
        LDI     0
        PHI     RD
        PLO     RD
        SEP     R4
        DW      LPUSH
        LOAD    RF, EMP         ; C
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        GHI     RD
        STXD
        GLO     RD
        STXD
        SEP     R4
        DW      GETT
        XRI     TSEMI
        LBZ     YF2
        SEP     R4
        DW      PEXPR
        SEP     R4
        DW      LTOP
        INC     RC
        INC     RC
        INC     RC
        INC     RC
        LDI     OJF
        SEP     R4
        DW      JCHAIN
YF2:    SEP     R4
        DW      PSEMI
        LDI     OJ
        SEP     R4
        DW      EMIT1
        SEP     R4
        DW      EMHOLE
        GHI     RD
        STXD
        GLO     RD
        STXD
        SEP     R4              ; continue -> B (here)
        DW      LTOP
        LOAD    RF, EMP
        LDA     RF
        STR     RC
        INC     RC
        LDN     RF
        STR     RC
        SEP     R4
        DW      GETT
        XRI     TRP
        LBZ     YF3
        SEP     R4
        DW      PSIMPL
        SEP     R4
        DW      GETT
        XRI     TRP
        LBNZ    NORP
YF3:    SEP     R4
        DW      NEXT
        LDI     OJ              ; (EMIT1 uses RD)
        SEP     R4
        DW      EMIT1
        IRX                     ; RC = the hole over B, RD = C
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDXA
        PLO     RD
        LDX
        PHI     RD
        GHI     RC
        STXD
        GLO     RC
        STXD
        SEP     R4
        DW      EMITD
        IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        SEP     R4
        DW      PATCH
        SEP     R4
        DW      PBODY
        LBR     YLOOP
; PSEMI: a ; (and line ends after it)
PSEMI:  SEP     R4
        DW      GETT
        XRI     TSEMI
        LBZ     PSE1
        SEP     R4
        DW      EMSGN
        DB      'a ; is missing',0
PSE1:   SEP     R4
        DW      NEXT
        LBR     SKIPNL
; YBRK / YCON: break, continue
YBRK:   SEP     R4
        DW      LTOP
        LBDF    NOLOOP
        INC     RC
        INC     RC
        INC     RC
        INC     RC
YBRK2:  LDI     OJ
        SEP     R4
        DW      JCHAIN
        LBR     NEXT
YCON:   SEP     R4
        DW      LTOP
        LBDF    NOLOOP
        LDA     RC
        PHI     RD
        LDN     RC
        PLO     RD
        INC     RC
        GHI     RD
        LBZ     YBRK2           ; (a do: not known yet - on its chain)
        GHI     RD
        STXD
        GLO     RD
        STXD
        LDI     OJ              ; (EMIT1 uses RD)
        SEP     R4
        DW      EMIT1
        IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        SEP     R4
        DW      EMITD
        LBR     NEXT
NOLOOP: SEP     R4
        DW      EMSGN
        DB      'break or continue outside a loop',0
; YNXT: next (main rules only).  YEXIT: exit [value]
YNXT:   LOAD    RD, CURK
        LDN     RD
        XRI     1
        LBZ     YNX2
        SEP     R4
        DW      EMSGN
        DB      'next is not for BEGIN or END',0
YNX2:   LDI     ONEXT
        SEP     R4
        DW      EMIT1
        LBR     NEXT
YEXIT:  SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        LBZ     YEX2
        XRI     TSEMI
        LBZ     YEX2
        XRI     TSEMI XOR TNL
        LBZ     YEX2
        XRI     TNL XOR TRB
        LBZ     YEX2
        SEP     R4              ; its value (RAWK does not use it)
        DW      PSIMPL
YEX2:   LDI     OEXIT
        LBR     EMIT1
; PST2: print [list].  YPRF: printf list, or printf (list)
PST2:   SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        LBZ     EPRT0
        XRI     TSEMI
        LBZ     EPRT0
        XRI     TSEMI XOR TRB
        LBZ     EPRT0
        XRI     TRB XOR TNL
        LBZ     EPRT0
        LDI     OPRINT
PLST0:  STXD                    ; the step
        LOAD    RD, NOGT        ; (a comparison in the list needs ( ): print > file in awk)
        LDI     1
        STR     RD
        INC     RD              ; PCNT = 0
        LDI     0
        STR     RD
        SEP     R4
        DW      PLIST
        LOAD    RD, NOGT
        LDI     0
        STR     RD
        SEP     R4
        DW      GETT
        SMI     TLT
        LBNF    PST5
        SMI     6
        LBDF    PST5
        SEP     R4
        DW      EMSGN
        DB      'put a comparison after print in ( )',0
PST5:   IRX
        LDX
PLST9:  SEP     R4
        DW      EMIT1
        LOAD    RD, PCNT
        LDN     RD
        LBR     EMIT1
YPRF:   SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TLP
        LBZ     YPF2
        LDI     OPRINTF
        LBR     PLST0
YPF2:   SEP     R4
        DW      NEXT
        LOAD    RD, NOGT
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      PLIST
        SEP     R4
        DW      GETT
        XRI     TRP
        LBNZ    NORP
        SEP     R4
        DW      NEXT
        LDI     OPRINTF
        LBR     PLST9
; PLIST: expressions with , between (new lines after a ,); PCNT counts them
PLIST:  SEP     R4
        DW      PEXPR
        LOAD    RD, PCNT
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      GETT
        XRI     TCOMMA
        LBNZ    PL9
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      SKIPNL
        LBR     PLIST
PL9:    SEP     R5
; PRFN: substr(s, m[, n]), index(s, t), toupper(s), tolower(s) - the values, then the step
PRFN:   LOAD    RD, TOKV + 3
        LDN     RD
        STXD                    ; the step
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TLP
        LBNZ    NOLP
        SEP     R4
        DW      NEXT
        LOAD    RD, NOGT
        LDN     RD
        STXD                    ; NOGT (off inside)
        LDI     0
        STR     RD
        STXD                    ; how many
PF1:    SEP     R4
        DW      PEXPR
        IRX
        LDX
        ADI     1
        STXD
        SEP     R4
        DW      GETT
        XRI     TCOMMA
        LBNZ    PF2
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      SKIPNL
        LBR     PF1
PF2:    SEP     R4
        DW      GETT
        XRI     TRP
        LBNZ    NORP
        IRX
        LDXA
        PLO     RC              ; RC.0 = how many
        LDXA
        PLO     RB              ; NOGT
        LDX
        PHI     RC              ; RC.1 = the step
        LOAD    RD, NOGT
        GLO     RB
        STR     RD
        LOAD    RD, FNTAB       ; how many it takes
PF3:    LDA     RD
        STR     R2
        GHI     RC
        XOR
        LBZ     PF4
        INC     RD
        INC     RD
        LBR     PF3
PF4:    LDA     RD              ; at least
        STR     R2
        GLO     RC
        SM
        LBNF    FNARGS
        LDN     RD              ; at most
        STR     R2
        GLO     RC
        SD
        LBNF    FNARGS
        GHI     RC
        SEP     R4
        DW      EMIT1
        GHI     RC
        XRI     OSUBSTR
        LBNZ    NEXT
        GLO     RC              ; substr: how many
        SEP     R4
        DW      EMIT1
        LBR     NEXT
FNARGS: SEP     R4
        DW      EMSGN
        DB      'wrong number of values for a function',0
FNTAB:  DB      OSUBSTR, 2, 3, OINDEX, 2, 2, OTOUP, 1, 1, OTOLOW, 1, 1
; PEXPR: an expression; = += -= *= /= %= (right to left) after a variable alone
PEXPR:  SEP     R4
        DW      POR
        SEP     R4
        DW      GETT
        PLO     RC
        SMI     TASG
        LBNF    PX9
        SMI     TMODA - TASG + 1
        LBDF    PX9
        LOAD    RD, LVAL
        LDN     RD
        LBNZ    PX2
        INC     RD
        LDN     RD
        LBNZ    FLDASG
        SEP     R4
        DW      EMSGN
        DB      'only a variable can be given a value',0
PX2:    SMI     1
        SEP     R4
        DW      RDONLY          ; (D kept)
        STXD                    ; the variable, the operator
        GLO     RC
        STXD
        XRI     TASG
        LBNZ    PX3
        LOAD    RD, EMP         ; '=': its GETV goes
        INC     RD
        LDN     RD
        SMI     2
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
PX3:    SEP     R4
        DW      NEXT
        SEP     R4
        DW      PEXPR
        IRX                     ; RC.0 = the operator, RC.1 = the variable
        LDXA
        PLO     RC
        LDX
        PHI     RC
        GLO     RC
        XRI     TASG
        LBZ     PX4
        GLO     RC
        ADI     OADD - TADDA
        SEP     R4
        DW      EMIT1
PX4:    LDI     OSETV
        SEP     R4
        DW      EMIT1
        GHI     RC
        LBR     EMIT1
PX9:    SEP     R5
FLDASG: SEP     R4
        DW      EMSGN
        DB      '$n = value comes in a later version',0
; RDONLY: D = a variable: NR NF FNR FILENAME (0-3) cannot be changed. D kept.
RDONLY: PLO     RE
        SMI     4
        LBNF    RDO1
        GLO     RE
        SEP     R5
RDO1:   SEP     R4
        DW      EMSGN
        DB      'NR, NF, FNR, FILENAME cannot be changed yet',0
SYNERR: SEP     R4
        DW      GETT
        LBNZ    SYN1
        SEP     R4
        DW      EMSGN
        DB      'the program ends too soon',0
SYN1:   SEP     R4
        DW      EMSGN
        DB      'this is not understood',0
; PUSHRD / POPRD would be calls; the parts below keep holes on the stack themselves.
; POR: a || b -> a JT T; b JT T; 0; J E; T: 1; E:
POR:    SEP     R4
        DW      PAND
PO1:    SEP     R4
        DW      GETT
        XRI     TOR
        LBNZ    PX9
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      SKIPNL
        LDI     OJT
        SEP     R4
        DW      EMHOLE1
        SEP     R4
        DW      PAND
        LDI     OJT
        SEP     R4
        DW      EMHOLE1
        LDI     OPUSH0
        SEP     R4
        DW      EMIT1
        LDI     OJ
        SEP     R4
        DW      EMHOLE1
        LDI     OPUSH1
        SEP     R4
        DW      ENDJ3
        LBR     PO1
; PAND: a && b -> a JF F; b JF F; 1; J E; F: 0; E:
PAND:   SEP     R4
        DW      PMATCH
PN1:    SEP     R4
        DW      GETT
        XRI     TAND
        LBNZ    PX9
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      SKIPNL
        LDI     OJF
        SEP     R4
        DW      EMHOLE1
        SEP     R4
        DW      PMATCH
        LDI     OJF
        SEP     R4
        DW      EMHOLE1
        LDI     OPUSH1
        SEP     R4
        DW      EMIT1
        LDI     OJ
        SEP     R4
        DW      EMHOLE1
        LDI     OPUSH0
        SEP     R4
        DW      ENDJ3
        LBR     PN1
; EMHOLE1: the step D and a hole; the hole's place goes into HOLES (a little stack of its own)
EMHOLE1: SEP    R4
        DW      EMIT1
        SEP     R4
        DW      EMHOLE
        LOAD    RF, HOLESP
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        GHI     RD
        STR     RC
        INC     RC
        GLO     RD
        STR     RC
        INC     RC
        GHI     RC              ; (64 deep at most: past that the program is too long anyway)
        XRI     HIGH(HOLESE)
        LBNZ    EH1
        GLO     RC
        XRI     LOW(HOLESE)
        LBZ     EMFULL
EH1:    LOAD    RF, HOLESP
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R5
; POPH: RD = the last hole (off HOLES)
POPH:   LOAD    RF, HOLESP
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        DEC     RC
        LDN     RC
        PLO     RD
        DEC     RC
        LDN     RC
        PHI     RD
        DEC     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R5
; ENDJ3: the last three holes (J1 J2 J3): J1 and J2 -> here; then the step D; J3 -> here
ENDJ3:  STXD
        SEP     R4
        DW      POPH
        GHI     RD
        STXD
        GLO     RD
        STXD
        SEP     R4
        DW      POPH
        SEP     R4
        DW      PATCH
        SEP     R4
        DW      POPH
        SEP     R4
        DW      PATCH
        IRX
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDX
        SEP     R4
        DW      EMIT1
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        LBR     PATCH
; PMATCH: a ~ b, a !~ b (b: a /text/ or an expression)
PMATCH: SEP     R4
        DW      PREL
PM1:    SEP     R4
        DW      GETT
        XRI     TMAT
        LBZ     PM2
        XRI     TMAT XOR TNMAT
        LBNZ    PX9
        LDI     ONOT
        LSKP
PM2:    LDI     0
        STXD
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TERE
        LBNZ    PM3
        SEP     R4
        DW      EPUSHS
        SEP     R4
        DW      NEXT
        LBR     PM4
PM3:    SEP     R4
        DW      PREL
PM4:    LDI     OMATCH
        SEP     R4
        DW      EMIT1
        IRX
        LDX
        LBZ     PM1
        SEP     R4
        DW      EMIT1
        LBR     PM1
; EPUSHS: OPUSHS and the token's text (TOKS, TOKL)
EPUSHS: LDI     OPUSHS
EPUSHX: SEP     R4
        DW      EMIT1
        LOAD    RD, TOKS
        LDA     RD
        PHI     RC
        LDA     RD
        PLO     RC
        LDN     RD
        STXD
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R4
        DW      EMITD
        IRX
        LDX
        LBR     EMIT1
; PREL: a < b, <=, >, >=, ==, != (once; not at the top of a print's list)
PREL:   SEP     R4
        DW      PCAT
        SEP     R4
        DW      GETT
        SMI     TLT
        LBNF    PX9
        SMI     6
        LBDF    PX9
        LOAD    RD, NOGT
        LDN     RD
        LBNZ    PX9
        SEP     R4
        DW      GETT
        STXD
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PCAT
        IRX
        LDX
        ADI     OLT - TLT
        LBR     EMIT1
; PCAT: a b (side by side: joined), while a value can start
PCAT:   SEP     R4
        DW      PADD
PC1:    SEP     R4
        DW      GETT
        STR     R2
        LOAD    RD, CATST
PC2:    LDA     RD
        LBZ     PX9
        XOR
        LBNZ    PC2
        SEP     R4
        DW      PADD
        LDI     OCAT
        SEP     R4
        DW      EMIT1
        LBR     PC1
CATST:  DB      TNUMT, TSTRT, TNAME, TLEN, TDOL, TLP, TFN, 0
; PADD: + -.  PMUL: * / %
PADD:   SEP     R4
        DW      PMUL
PD1:    SEP     R4
        DW      GETT
        XRI     TPLUS
        LBNZ    PD2
        LDI     OADD
        LBR     PD3
PD2:    XRI     TPLUS XOR TMINUS
        LBNZ    PX9
        LDI     OSUB
PD3:    STXD
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PMUL
        IRX
        LDX
        SEP     R4
        DW      EMIT1
        LBR     PD1
PMUL:   SEP     R4
        DW      PUNARY
PU1:    SEP     R4
        DW      GETT
        XRI     TSTAR
        LBNZ    PU2
        LDI     OMUL
        LBR     PU4
PU2:    XRI     TSTAR XOR TSLASH
        LBNZ    PU3
        LDI     ODIV
        LBR     PU4
PU3:    XRI     TSLASH XOR TPCT
        LBNZ    PX9
        LDI     OMOD
PU4:    STXD
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PUNARY
        IRX
        LDX
        SEP     R4
        DW      EMIT1
        LBR     PU1
; PUNARY: ! - + before a value
PUNARY: SEP     R4
        DW      GETT
        XRI     TNOT
        LBNZ    PY2
        LDI     ONOT
        LBR     PY4
PY2:    XRI     TNOT XOR TMINUS
        LBNZ    PY3
        LDI     ONEG
        LBR     PY4
PY3:    XRI     TMINUS XOR TPLUS
        LBNZ    PPOST
        LDI     OUPLUS
PY4:    STXD
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PUNARY
        IRX
        LDX
        LBR     EMIT1
; PPOST: a value, then ++ or -- after a variable
PPOST:  SEP     R4
        DW      PPRIM
        SEP     R4
        DW      GETT
        XRI     TINC
        LBNZ    PT2
        LDI     OPINC
        LBR     PT3
PT2:    XRI     TINC XOR TDEC
        LBNZ    PX9
        LDI     OPDEC
PT3:    PLO     RC
        LOAD    RD, LVAL
        LDN     RD
        LBNZ    PT4
        INC     RD
        LDN     RD
        LBNZ    FLDASG
        SEP     R4
        DW      EMSGN
        DB      '++ and -- need a variable',0
PT4:    SMI     1
        SEP     R4
        DW      RDONLY
        PHI     RC              ; RC.1 = the variable, RC.0 = the step
        LOAD    RD, EMP         ; its GETV goes
        INC     RD
        LDN     RD
        SMI     2
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        GLO     RC
        SEP     R4
        DW      EMIT1
        GHI     RC
        SEP     R4
        DW      EMIT1
        LBR     NEXT
; PPRIM: a number, "text", /text/, a variable, $value, ( expr ), ++var, --var, length[(expr)]
PPRIM:  SEP     R4
        DW      GETT
        XRI     TNUMT
        LBNZ    PR2
        LDI     OPUSHN
        SEP     R4
        DW      EMIT1
        LOAD    RD, TOKV
        LDA     RD
        PHI     RC
        LDA     RD
        PLO     RC
        LDA     RD
        STXD
        LDN     RD
        STXD
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R4
        DW      EMITD
        IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        SEP     R4
        DW      EMITD
        LBR     NEXT
PR2:    XRI     TNUMT XOR TSTRT
        LBNZ    PR3
        SEP     R4
        DW      EPUSHS
        LBR     NEXT
PR3:    XRI     TSTRT XOR TERE
        LBNZ    PR4
        LDI     OPUSH0          ; /text/: $0 ~ it
        SEP     R4
        DW      EMIT1
        LDI     OFIELD
        SEP     R4
        DW      EMIT1
        SEP     R4
        DW      EPUSHS
        LDI     OMATCH
        SEP     R4
        DW      EMIT1
        LBR     NEXT
PR4:    XRI     TERE XOR TNAME
        LBNZ    PR5
        LDI     OGETV
        SEP     R4
        DW      EMIT1
        LOAD    RD, TOKV + 3
        LDN     RD
        SEP     R4
        DW      EMIT1
        LOAD    RD, TOKV + 3    ; LVAL = the variable + 1 (after EMIT1 cleared it)
        LDN     RD
        ADI     1
        PLO     RB
        LOAD    RD, LVAL
        GLO     RB
        STR     RD
        LBR     NEXT
PR5:    XRI     TNAME XOR TDOL
        LBNZ    PR6
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PPRIM
        LDI     OFIELD
        SEP     R4
        DW      EMIT1
        LOAD    RD, FLV
        LDI     1
        STR     RD
        SEP     R5
PR6:    XRI     TDOL XOR TLP
        LBNZ    PR7
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      PPAREN
        SEP     R5
PR7:    XRI     TLP XOR TINC
        LBNZ    PR8
        LDI     OINCV
        LBR     PR9
PR8:    XRI     TINC XOR TDEC
        LBNZ    PR10
        LDI     ODECV
PR9:    STXD
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TNAME
        LBNZ    PRNOV
        IRX
        LDX
        SEP     R4
        DW      EMIT1
        LOAD    RD, TOKV + 3
        LDN     RD
        SEP     R4
        DW      RDONLY
        SEP     R4
        DW      EMIT1
        LBR     NEXT
PRNOV:  SEP     R4
        DW      EMSGN
        DB      '++ and -- need a variable',0
PR10:   XRI     TDEC XOR TLEN
        LBZ     PR10A
        XRI     TLEN XOR TFN
        LBZ     PRFN
        LBR     SYNERR
PR10A:
        SEP     R4              ; length, length(), length(x)
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TLP
        LBNZ    PRL0
        SEP     R4
        DW      NEXT
        SEP     R4
        DW      GETT
        XRI     TRP
        LBZ     PRL1
        SEP     R4
        DW      PPAREN
        LDI     OLEN
        LBR     EMIT1
PRL1:   SEP     R4
        DW      NEXT
PRL0:   LDI     OPUSH0
        SEP     R4
        DW      EMIT1
        LDI     OFIELD
        SEP     R4
        DW      EMIT1
        LDI     OLEN
        LBR     EMIT1
; PPAREN: an expression and its ')' (NOGT off inside), the token after it next
PPAREN: LOAD    RD, NOGT
        LDN     RD
        STXD
        LDI     0
        STR     RD
        SEP     R4
        DW      PEXPR
        IRX
        LDX
        PLO     RB
        LOAD    RD, NOGT
        GLO     RB
        STR     RD
        SEP     R4
        DW      GETT
        XRI     TRP
        LBNZ    NORP
        LBR     NEXT
NORP:   SEP     R4
        DW      EMSGN
        DB      'a ) is missing',0
PEND:
; ---- the variables (from ZBEG to ZEND: set to 0 at the start)
ZBEG:
LINES:  DS      1
FSB:    DS      1
EMFL:   DS      1
HASMAIN: DS     1               ; HASMAIN, HASEND: in this order
HASEND: DS      1
EXITF:  DS      1               ; 1: exit was run
GOTF:   DS      1               ; 1: -f gave the program
SENT:   DS      6               ; where BEGIN's, the main rules' and END's steps start
SHOLE:  DS      6               ; the hole each one's next piece fills in
LOOPSP: DS      2
FMTP:   DS      2               ; printf: the format's next character, how many are left
FMTL:   DS      1
PFL:    DS      1               ; printf: bit 0 -, bit 1 0 (PFL, PWID, PPREC: in this order)
PWID:   DS      1
PPREC:  DS      1               ;  (0FFH: none)
PSG:    DS      1               ;  the sign to put first (0: none), zeros after it
PNZ:    DS      1
RXEND:  DS      2               ; a pattern's end, while it is matched
FCH:    DS      1               ; printf: the format's character just taken
AVQ:    DS      1               ; -v: the value in quotes
SUBM:   DS      1               ; substr: from, how many
SUBN:   DS      1
XVAL:   DS      5               ; printf: a value the list did not give
CHB:    DS      1               ; %c's character
HEXB:   DS      8               ; %x's digits
NVARS:  DS      1
CURK:   DS      1
EMP:    DS      2
EML:    DS      1
LVAL:   DS      1               ; LVAL, FLV: in this order
FLV:    DS      1
NOGT:   DS      1               ; NOGT, PCNT: in this order
PCNT:   DS      1
TOKT:   DS      1               ; TOKT, LASTT: in this order
LASTT:  DS      1
TOKV:   DS      4
TOKS:   DS      2               ; TOKS, TOKL: in this order
TOKL:   DS      1
TOKP:   DS      2
SRCP:   DS      2
CONP:   DS      2
NAMES:  DS      2
HOLESP: DS      2
NBUF:   DS      16
TMPP:   DS      2
VHP:    DS      2
NRV:    DS      4
FNRV:   DS      4
NFV:    DS      1
FNLEN:  DS      1
FNTXT:  DS      14
LLEN:   DS      1
SPTR:   DS      2               ; SPTR, SREM: in this order
SREM:   DS      2
GLSAV:  DS      4
FI:     DS      1
FLN:    DS      1
FLP:    DS      2
NXARG:  DS      2
NAMEP:  DS      2
CMPM:   DS      1
NEEDF:  DS      1               ; 1: there are files to read
OMODE:  DS      1               ; -o: 1 (OMODE, OPTR: in this order)
OPTR:   DS      2               ; where the next byte goes in OBUF
ONAME:  DS      11
OWDIR:  DS      2
ESEC:   DS      2               ; ESEC, EPTR: in this order - its entry's sector, where in DIRBUF
EPTR:   DS      2
OLDCL:  DS      2               ; the old file's first cluster
REPL:   DS      1               ; 1: replacing it
WFIRST: DS      2               ; the new chain: its first cluster (0: none, or saved), its last, a new one
WPREV:  DS      2
NEWC:   DS      2
WLBA:   DS      4               ; the next sector
WSLEFT: DS      1               ; sectors left in this cluster
SIZE:   DS      4               ; the file's bytes (big-endian)
PRN:    DS      1
PRP:    DS      2
OFSE:   DS      5
IVMODE: DS      1               ; IVMODE, IVVAR: in this order
IVVAR:  DS      1
T4:     DS      4
NV:     DS      4
QN:     DS      4
DVS:    DS      4
TT:     DS      4
REM4:   DS      4
SGN:    DS      2
DCNT:   DS      1
ZEND:
CONB:   DS      CONN + 1
CONE    EQU     CONB + CONN
CEND:
        ORG     6C00H - STEPN
STEPB:  DS      STEPN           ; the steps: BEGIN's, the main rules', END's - each a chain of pieces
STEPE:
RAWKEND:
; ---- what only running the program needs: on top of the compiler (CBEG .. PEND), which it no longer needs
        ORG     CBEG
VARS:   DS      VMAX * 8
LBUF:   DS      LMAX + 1
FLDS:   DS      256
VSTK:   DS      VSTKN * 5
VSTKE:
FLBUF:  DS      FLMAX * 13
VHEAP:  DS      VHN
VHE:
RUNEND:
        END
