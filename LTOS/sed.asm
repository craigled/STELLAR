; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; sed.asm - SED.PRG: SED [-n] [-E] [-e script] [-f file] [script] names - the Unix stream editor, in 1802 code.
;   Commands: s y d D p P n N g G h H x a i c = l q Q b t T : { } #. Addresses: a number, $, /re/, \cREc, two with a
;   comma, ! after them. s takes g p a number and I; /re/ takes I. The file is not changed: > sends the result on.
;   Not here: r and w (LTOS reads one file at a time), M, e, the \U family.
;
; Regular expressions (POSIX basic; -E extended): . * [set] [^set] [[:alpha:]] ^ $ \( \) \1-\9 \{m,n\} \+ \? \|.
; Each is compiled to a little program, run by a backtracking machine with its own stack (BT):
;   a run of one thing (a* .* [0-9]\{2,\}) is one REP, backed off a character at a time; groups use SPLIT and JMP.
;
; The script is compiled once into CMDT: 16 bytes for each command (the C_ offsets), the regexes and texts in HEAP.
; Lines: a line read ahead in NX tells $ from the rest; the pattern and hold spaces are 0-ended (a NUL in a file is
; dropped, so is a CR); 1,023 characters at most, and more is cut. verify_sed.py holds it to the Mac's own sed.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
FLMAX   EQU     38
NCMD    EQU     48
C_FL    EQU     1               ; flags: 1 = !, 2 = a range is open
C_K1    EQU     2               ; address kinds: 0 none, 1 a line, 2 $, 3 a regex
C_K2    EQU     3
C_V1    EQU     4               ; its line, or regex (0: the last one used)
C_V2    EQU     6
C_A1    EQU     8               ; s: the regex; a i c: the text; b t T: the target, then the label; {: its }
C_A2    EQU     10              ; s: the replacement
C_SF    EQU     12              ; s: 1 = g, 2 = p
C_NTH   EQU     13              ; s: the number (0: the first)
OP_MATCH EQU    0               ; the machine's instructions
OP_CHAR EQU     1               ; c
OP_CHARI EQU    2               ; c (in capitals)
OP_ANY  EQU     3
OP_SET  EQU     4               ; 32 bytes
OP_BOL  EQU     5
OP_EOL  EQU     6
OP_SAVE EQU     7               ; slot
OP_SPLIT EQU    8               ; offset (2): go on; on failure there
OP_JMP  EQU     9               ; offset (2)
OP_REP  EQU     10              ; min max (0: no limit), then one of CHAR CHARI ANY SET
OP_BREF EQU     11              ; slot
OP_LOOP EQU     12              ; slot offset (2): back round, unless that group matched nothing (slot FF: always)

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
        LOAD    RD, VARS        ; the variables: 0
        LDI     0
        PLO     RC
ZV1:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ZV1
        LOAD    RD, HS          ; the hold space starts empty
        LDI     0
        STR     RD
        LOAD    RD, SRCP
        LDI     HIGH(SRC)
        STR     RD
        INC     RD
        LDI     LOW(SRC)
        STR     RD
; ---- the flags
AR1:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        XRI     '-'
        LBNZ    AR8
        INC     RF
AR2:    LDA     RF
        LBZ     USE
        PLO     RC
        XRI     ' '
        LBZ     AR1
        GLO     RC
        XRI     'n'
        LBNZ    AR3
        LOAD    RD, NFLAG
AR21:   LDI     1
        STR     RD
        LBR     AR2
AR3:    GLO     RC
        XRI     'E'
        LBZ     AR31
        GLO     RC
        XRI     'r'
        LBNZ    AR4
AR31:   LOAD    RD, EFLAG
        LBR     AR21
AR4:    GLO     RC
        XRI     'e'
        LBNZ    AR5
        SEP     R4
        DW      K_SKIPSP
        SEP     R4
        DW      WORDS
        LBR     AR6
AR5:    GLO     RC
        XRI     'f'
        LBNZ    USE
        SEP     R4
        DW      K_SKIPSP
        SEP     R4
        DW      SFILE
AR6:    LOAD    RD, GOTS
        LDI     1
        STR     RD
        LBR     AR1
AR8:    LOAD    RD, GOTS        ; no -e or -f: the first word is the script
        LDN     RD
        LBNZ    AR9
        LDN     RF
        LBZ     USE
        SEP     R4
        DW      WORDS
AR9:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        LOAD    RD, ARGS        ; (the names, once the script is compiled)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, SRCP        ; the script's end
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDI     0
        STR     RF
        SEP     R4
        DW      COMPILE
        LOAD    RD, ARGS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      FLIST
        LOAD    RD, FLN
        LDN     RD
        LBNZ    RUN
        SEP     R4
        DW      K_PIN
        DB      'No file matches.',0DH,0AH,0
        LBR     STAT1
USE:    SEP     R4
        DW      K_PIN
        DB      'SED [-n] [-E] [-e script] [-f file] [script] names (HELP SED)',0DH,0AH,0
STAT1:  LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        LBR     K_MAIN
; BAD: the script is wrong: what, and where
BAD:    SEP     R4
        DW      K_PIN
        DB      'SED: bad script near: ',0
BD1:    DEC     R8              ; (from the start of the line it is on)
        GHI     R8
        XRI     HIGH(SRC - 1)
        LBNZ    BD2
        GLO     R8
        XRI     LOW(SRC - 1)
        LBZ     BD3
BD2:    LDN     R8
        XRI     0AH
        LBNZ    BD1
BD3:    INC     R8
BD4:    LDA     R8
        LBZ     BD5
        PLO     RB
        XRI     0AH
        LBZ     BD5
        GLO     RB
        SEP     R4
        DW      F_TYPE
        LBR     BD4
BD5:    SEP     R4
        DW      NEWL
        LBR     STAT1
; WORDS: the word at RF (in '' or "", or to a space) onto the script, with an LF
WORDS:  LOAD    RD, SRCP
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LDI     ' '
        PLO     RC              ; RC.0: what ends it
        LDN     RF
        XRI     27H
        LBZ     WD1
        LDN     RF
        XRI     '"'
        LBNZ    WD2
WD1:    LDA     RF
        PLO     RC
WD2:    LDN     RF
        LBZ     WD8
        STR     R2
        GLO     RC
        XOR
        LBZ     WD7
        LDA     RF
        STR     RB
        INC     RB
        GHI     RB
        XRI     HIGH(SRCEND)
        LBNZ    WD2
        LBR     TOOLONG
WD7:    INC     RF
WD8:    LDI     0AH
        STR     RB
        INC     RB
        LOAD    RD, SRCP
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        SEP     R5
TOOLONG: SEP     R4
        DW      K_PIN
        DB      'SED: the script is too long.',0DH,0AH,0
        LBR     STAT1
; SFILE: the file named at RF onto the script (RF past the name)
SFILE:  LOAD    RD, TMP11
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, ARGS
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, TMP11
        SEP     R4
        DW      KS_FINDN
        LBNF    SF1
        SEP     R4
        DW      K_PIN
        DB      'SED: there is no such script file.',0DH,0AH,0
        LBR     STAT1
SF1:    SEP     R4
        DW      KS_FOPEN
        LOAD    RD, SREM
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, SRCP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
SF2:    SEP     R4
        DW      GETB
        LBDF    SF5
        LBZ     SF2             ; (a NUL)
        PLO     RB
        XRI     0DH
        LBZ     SF2
        GLO     RB
        STR     RA
        INC     RA
        GHI     RA
        XRI     HIGH(SRCEND)
        LBNZ    SF2
        LBR     TOOLONG
SF5:    LDI     0AH
        STR     RA
        INC     RA
        LOAD    RD, SRCP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, ARGS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5
; ==== the compiler. R8 the script, R7 the command being made, RA the next free byte of HEAP
COMPILE: LOAD   R8, SRC
        LOAD    R7, CMDT
        LOAD    RA, HEAP
CP1:    SEP     R4
        DW      SKIPSEP
        LDN     R8
        LBZ     CP9
        XRI     '#'
        LBNZ    CP2
CP11:   LDA     R8              ; a comment
        LBZ     CP12
        XRI     0AH
        LBNZ    CP11
        LBR     CP1
CP12:   DEC     R8
        LBR     CP1
CP2:    GHI     R7              ; room?
        XRI     HIGH(CMDT + NCMD * 16 - 16)
        LBNZ    CP21
        GLO     R7
        XRI     0F0H
        LBZ     BAD
CP21:   GHI     R7              ; the record: 0
        PHI     RD
        GLO     R7
        PLO     RD
        LDI     16
        PLO     RC
CP22:   LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    CP22
        GLO     R7
        ORI     C_K1
        PLO     RF
        GHI     R7
        PHI     RF
        GHI     RF
        PHI     RB
        GLO     RF
        PLO     RB
        SEP     R4
        DW      PADDR
        GLO     R7
        ORI     C_K1
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        LBZ     CP3
        SEP     R4
        DW      SKIPWS
        LDN     R8
        XRI     ','
        LBNZ    CP3
        INC     R8
        SEP     R4
        DW      SKIPWS
        GLO     R7
        ORI     C_K2
        PLO     RF
        GHI     R7
        PHI     RF
        GHI     RF
        PHI     RB
        GLO     RF
        PLO     RB
        SEP     R4
        DW      PADDR
        GLO     R7
        ORI     C_K2
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        LBZ     BAD
CP3:    SEP     R4
        DW      SKIPWS
        LDN     R8
        XRI     '!'
        LBNZ    CP4
        INC     R8
        GLO     R7
        ORI     C_FL
        PLO     RF
        GHI     R7
        PHI     RF
        LDI     1
        STR     RF
        LBR     CP3
CP4:    LDA     R8
        LBZ     BAD
        STR     R7
        PLO     RC
        LOAD    RF, CCMDS       ; which kind of command?
CP41:   LDA     RF
        LBZ     CP5
        STR     R2
        GLO     RC
        XOR
        LBNZ    CP41
        LBR     CP8             ; one with nothing after it
CP5:    GLO     RC
        XRI     '{'
        LBNZ    CP51
        LOAD    RD, BRD         ; the open blocks: a stack in BRS
        LDN     RD
        PLO     RB
        ADI     1
        STR     RD
        GLO     RB
        XRI     12
        LBZ     BAD
        GLO     RB
        SHL
        ADI     LOW(BRS)
        PLO     RD
        LDI     HIGH(BRS)
        ADCI    0
        PHI     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        LBR     CP85            ; (the next command may follow at once)
CP51:   GLO     RC
        XRI     '}'
        LBNZ    CP52
        GLO     R7
        ORI     C_K1
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        LBNZ    BAD
        LOAD    RD, BRD
        LDN     RD
        LBZ     BAD
        SMI     1
        STR     RD
        SHL
        ADI     LOW(BRS)
        PLO     RD
        LDI     HIGH(BRS)
        ADCI    0
        PHI     RD
        LDA     RD              ; the { : its target is this }
        PHI     RF
        LDN     RD
        ORI     C_A1
        PLO     RF
        GHI     R7
        STR     RF
        INC     RF
        GLO     R7
        STR     RF
        LBR     CP8
CP52:   GLO     RC
        XRI     ':'
        LBZ     CP53
        GLO     RC
        XRI     'b'
        LBZ     CP53
        GLO     RC
        XRI     't'
        LBZ     CP53
        GLO     RC
        XRI     'T'
        LBNZ    CP54
CP53:   SEP     R4          ; a label: into HEAP, to a space, ; or the line's end
        DW      SKIPWS
        GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     R8
        LBZ     CP8
        XRI     ';'
        LBZ     CP8
        LDN     R8
        XRI     0AH
        LBZ     CP8
        LDN     R8
        XRI     '}'
        LBZ     CP8
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
CP531:  LDN     R8
        LBZ     CP533
        XRI     ';'
        LBZ     CP533
        LDN     R8
        XRI     0AH
        LBZ     CP533
        LDN     R8
        XRI     ' '
        LBZ     CP533
        LDA     R8
        SEP     R4
        DW      EMIT
        LBR     CP531
CP533:  LDI     0
        SEP     R4
        DW      EMIT
        LBR     CP8
CP54:   GLO     RC
        XRI     'a'
        LBZ     CP55
        GLO     RC
        XRI     'i'
        LBZ     CP55
        GLO     RC
        XRI     'c'
        LBNZ    CP56
CP55:   SEP     R4
        DW      CTEXT
        LBR     CP85
CP56:   GLO     RC
        XRI     's'
        LBNZ    CP57
        SEP     R4
        DW      CSUB
        LBR     CP8
CP57:   GLO     RC
        XRI     'y'
        LBNZ    BAD
        SEP     R4
        DW      CY
CP8:    SEP     R4          ; the command must end here
        DW      SKIPWS
        LDN     R8
        LBZ     CP85
        XRI     ';'
        LBZ     CP85
        LDN     R8
        XRI     0AH
        LBZ     CP85
        LDN     R8
        XRI     '}'
        LBZ     CP85
        LDN     R8
        XRI     '#'
        LBNZ    BAD
CP85:   GLO     R7
        ADI     16
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        LBR     CP1
CP9:    LOAD    RD, BRD         ; a { not closed
        LDN     RD
        LBNZ    BAD
        LDI     0               ; the end
        STR     R7
        LOAD    RD, CMEND
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
; ---- the labels: b t T -> the : they name, or the end
        LOAD    R9, CMDT
LB1:    LDN     R9
        LBZ     LB9
        XRI     'b'
        LBZ     LB2
        LDN     R9
        XRI     't'
        LBZ     LB2
        LDN     R9
        XRI     'T'
        LBNZ    LB8
LB2:    GHI     R9              ; RB -> the name
        PHI     RF
        GLO     R9
        ORI     C_A1
        PLO     RF
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        DEC     RF
        GHI     RB
        LBNZ    LB3
        LOAD    RD, CMEND       ; none: the end
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LBR     LB8
LB3:    LOAD    RC, CMDT        ; find it
LB4:    LDN     RC
        LBZ     LBX
        XRI     ':'
        LBNZ    LB6
        GHI     RC
        PHI     RD
        GLO     RC
        ORI     C_A1
        PLO     RD
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        GHI     R8
        LBZ     LB6
        GHI     RB
        PHI     RD
        GLO     RB
        PLO     RD
LB5:    LDA     RD
        STR     R2
        LDA     R8
        XOR
        LBNZ    LB6
        LDN     R2
        LBNZ    LB5
        GHI     RC              ; there
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LBR     LB8
LB6:    GLO     RC
        ADI     16
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LBR     LB4
LBX:    SEP     R4
        DW      K_PIN
        DB      'SED: no such label.',0DH,0AH,0
        LBR     STAT1
LB8:    GLO     R9
        ADI     16
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
        LBR     LB1
LB9:    SEP     R5
CCMDS:  DB      'dDgGhHnNpPxl=qQ',0
SKIPSEP: LDN    R8
        XRI     ' '
        LBZ     SS1
        LDN     R8
        XRI     9
        LBZ     SS1
        LDN     R8
        XRI     0AH
        LBZ     SS1
        LDN     R8
        XRI     ';'
        LBNZ    SS9
SS1:    INC     R8
        LBR     SKIPSEP
SS9:    SEP     R5
SKIPWS: LDN     R8
        XRI     ' '
        LBZ     SW1
        LDN     R8
        XRI     9
        LBNZ    SS9
SW1:    INC     R8
        LBR     SKIPWS
; EMIT: D into HEAP
EMIT:   STR     RA
        INC     RA
        GHI     RA
        XRI     HIGH(HEAPEND)
        LBNZ    SS9
        LBR     TOOLONG
; PNUMB: digits at R8 -> RC (DF = 1: none)
PNUMB:  LDI     0
        PHI     RC
        PLO     RC
        LDN     R8
        SMI     '0'
        LBNF    PN8
        SMI     10
        LBDF    PN8
PN1:    LDN     R8
        SMI     '0'
        LBNF    PN7
        SMI     10
        LBDF    PN7
        GLO     RC              ; * 10
        SHL
        PLO     RD
        GHI     RC
        SHLC
        PHI     RD              ; RD = * 2
        GLO     RD
        SHL
        PLO     RC
        GHI     RD
        SHLC
        PHI     RC
        GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC              ; RC = * 8
        GLO     RD
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RD
        STR     R2
        GHI     RC
        ADC
        PHI     RC
        LDA     R8
        SMI     '0'
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LBR     PN1
PN7:    LDI     0
        SHR
        SEP     R5
PN8:    LDI     0
        SMI     0
        SEP     R5
; PADDR: an address at R8, if there is one: its kind at RB, its value at RB + 2 (RB is the kind's; C_V is 2 or 3 on)
PADDR:  GLO     RB              ; the value's place: K1 -> V1, K2 -> V2
        XRI     0               ; (C_K1 = 2 -> +2; C_K2 = 3 -> +3)
        ANI     1
        ADI     2
        STR     R2
        GLO     RB
        ADD
        PLO     RF
        GHI     RB
        PHI     RF              ; RF -> the value
        LDN     R8
        XRI     '$'
        LBNZ    PA1
        INC     R8
        LDI     2
        STR     RB
        SEP     R5
PA1:    LDN     R8
        XRI     '/'
        LBZ     PA2
        LDN     R8
        XRI     5CH             ; \c
        LBNZ    PA3
        INC     R8
PA2:    GHI     RF
        STXD
        GLO     RF
        STXD
        GHI     RB
        STXD
        GLO     RB
        STXD
        LDA     R8              ; the delimiter
        SEP     R4
        DW      RXGET
        LOAD    RD, ICASE
        LDI     0
        STR     RD
        LDN     R8
        XRI     'I'
        LBNZ    PA21
        INC     R8
        LDI     1
        STR     RD
PA21:   SEP     R4             ; -> RC
        DW      RXC
        IRX
        LDXA
        PLO     RB
        LDXA
        PHI     RB
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LDI     3
        STR     RB
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R5
PA3:    GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      PNUMB
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LBDF    SS9             ; no address
        LDI     1
        STR     RB
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R5
; CTEXT: a i c's text: "a\" then the lines, or "a text": into HEAP (\ at a line's end: it goes on)
CTEXT:  GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        SEP     R4
        DW      SKIPWS
        LDN     R8
        XRI     5CH
        LBNZ    CT2
        INC     R8
        SEP     R4
        DW      SKIPWS
        LDN     R8
        XRI     0AH
        LBNZ    CT2
        INC     R8
CT2:    LDA     R8
        LBZ     CT8
        PLO     RC
        XRI     0AH
        LBZ     CT9
        GLO     RC
        XRI     5CH
        LBNZ    CT3
        LDA     R8              ; \x: x (\ and the line's end: LF)
        LBZ     CT8
        PLO     RC
CT3:    GLO     RC
        SEP     R4
        DW      EMIT
        LBR     CT2
CT8:    DEC     R8
CT9:    LDI     0
        LBR     EMIT
; CSUB: s/re/replacement/flags
CSUB:   LDA     R8
        LBZ     BAD
        PLO     RC
        XRI     0AH
        LBZ     BAD
        GLO     RC
        XRI     5CH
        LBZ     BAD
        GLO     RC
        SEP     R4
        DW      RXGET
        GLO     R7            ; the replacement: 1 n for & and \n, an LF for \LF
        ORI     C_A2
        PLO     RF
        GHI     R7
        PHI     RF
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
CS1:    LDA     R8
        LBZ     BAD
        PLO     RC
        STR     R2
        LOAD    RD, DELIM
        LDN     RD
        XOR
        LBZ     CS7
        GLO     RC
        XRI     '&'
        LBNZ    CS2
        LDI     1
        SEP     R4
        DW      EMIT
        LDI     0
        SEP     R4
        DW      EMIT
        LBR     CS1
CS2:    GLO     RC
        XRI     5CH
        LBNZ    CS5
        LDA     R8
        LBZ     BAD
        PLO     RC
        XRI     'n'
        LBNZ    CS3
        LDI     0AH
        PLO     RC
        LBR     CS5
CS3:    GLO     RC
        XRI     't'
        LBNZ    CS4
        LDI     9
        PLO     RC
        LBR     CS5
CS4:    GLO     RC              ; \1 - \9
        SMI     '1'
        LBNF    CS5
        SMI     9
        LBDF    CS5
        LDI     1
        SEP     R4
        DW      EMIT
        GLO     RC
        SMI     '0'
        SEP     R4
        DW      EMIT
        LBR     CS1
CS5:    GLO     RC
        SEP     R4
        DW      EMIT
        LBR     CS1
CS7:    LDI     0
        SEP     R4
        DW      EMIT
        LOAD    RD, ICASE       ; the flags
        LDI     0
        STR     RD
CS71:   LDN     R8
        XRI     'g'
        LBNZ    CS72
        INC     R8
        GLO     R7
        ORI     C_SF
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ORI     1
        STR     RF
        LBR     CS71
CS72:   LDN     R8
        XRI     'p'
        LBNZ    CS73
        INC     R8
        GLO     R7
        ORI     C_SF
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ORI     2
        STR     RF
        LBR     CS71
CS73:   LDN     R8
        XRI     'I'
        LBZ     CS74
        LDN     R8
        XRI     'i'
        LBNZ    CS75
CS74:   INC     R8
        LOAD    RD, ICASE
        LDI     1
        STR     RD
        LBR     CS71
CS75:   SEP     R4
        DW      PNUMB
        LBDF    CS8
        GLO     R7
        ORI     C_NTH
        PLO     RF
        GHI     R7
        PHI     RF
        GLO     RC
        STR     RF
        LBR     CS71
CS8:    SEP     R4
        DW      RXC
        GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R5
; CY: y/abc/xyz/ -> pairs in HEAP, 0-ended
CY:     LDA     R8
        LBZ     BAD
        PLO     RC
        SEP     R4           ; DELIM
        DW      RXSET
        GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        GHI     R8              ; RB -> the first list; count it, R9 -> the second
        PHI     RB
        GLO     R8
        PLO     RB
CY1:    SEP     R4
        DW      YCHAR
        LBNF    CY1
        GHI     R8
        PHI     R9
        GLO     R8
        PLO     R9
CY2:    GHI     RB              ; a pair
        PHI     R8
        GLO     RB
        PLO     R8
        SEP     R4
        DW      YCHAR
        LBDF    CY5             ; the first list is done
        PLO     RC
        GHI     R8
        PHI     RB
        GLO     R8
        PLO     RB
        GLO     RC
        SEP     R4
        DW      EMIT
        GHI     R9
        PHI     R8
        GLO     R9
        PLO     R8
        SEP     R4
        DW      YCHAR
        LBDF    BAD             ; shorter
        SEP     R4
        DW      EMIT
        GHI     R8
        PHI     R9
        GLO     R8
        PLO     R9
        LBR     CY2
CY5:    GHI     R9
        PHI     R8
        GLO     R9
        PLO     R8
        SEP     R4
        DW      YCHAR
        LBNF    BAD             ; longer
        LDI     0
        SEP     R4
        DW      EMIT
        LDI     0
        LBR     EMIT
; YCHAR: the next character of a y list -> D, or DF = 1 at the delimiter (R8 past it)
YCHAR:  LDA     R8
        LBZ     BAD
        PHI     RD
        XRI     0AH
        LBZ     BAD
        GHI     RD
        XRI     5CH
        LBNZ    YC3
        LDA     R8
        LBZ     BAD
        PHI     RD
        XRI     'n'
        LBNZ    YC1
        LDI     0AH
        PHI     RD
YC1:    GHI     RD
        ADI     0
        SEP     R5
YC3:    GHI     RD
        STR     R2
        LOAD    RD, DELIM
        LDN     RD
        XOR
        LBZ     YC4
        LDN     R2
        ADI     0               ; DF = 0
        SEP     R5
YC4:    SMI     0               ; DF = 1
        SEP     R5
; RXSET: DELIM = RC.0. RXGET: D the delimiter; the regex at R8 to it -> RXT (\delim: delim), R8 past it
RXSET:  LOAD    RD, DELIM
        GLO     RC
        STR     RD
        SEP     R5
RXGET:  PLO     RC
        SEP     R4
        DW      RXSET
        LOAD    RB, RXT
RG1:    LDA     R8
        LBZ     BAD
        PLO     RC
        XRI     0AH
        LBZ     BAD
        GLO     RC
        STR     R2
        LOAD    RD, DELIM
        LDN     RD
        XOR
        LBZ     RG8
        GLO     RC
        XRI     5CH
        LBNZ    RG3
        LDA     R8
        LBZ     BAD
        PLO     RC
        STR     R2
        LOAD    RD, DELIM
        LDN     RD
        XOR
        LBZ     RG4             ; \delim: just the character
        LDI     5CH
        STR     RB
        INC     RB
        LBR     RG4
RG3:    GLO     RC              ; [ ... ]: the delimiter is plain in there
        XRI     '['
        LBNZ    RG4
        GLO     RC
        STR     RB
        INC     RB
        LDN     R8
        XRI     '^'
        LBNZ    RG31
        LDA     R8
        STR     RB
        INC     RB
RG31:   LDN     R8
        XRI     ']'
        LBNZ    RG32
        LDA     R8
        STR     RB
        INC     RB
RG32:   LDA     R8
        LBZ     BAD
        STR     RB
        INC     RB
        XRI     ']'
        LBNZ    RG32
        LBR     RG1
RG4:    GLO     RC
        STR     RB
        INC     RB
        GHI     RB
        XRI     HIGH(RXT + 255)
        LBNZ    RG1
        GLO     RB
        XRI     LOW(RXT + 255)
        LBNZ    RG1
        LBR     BAD
RG8:    LDI     0
        STR     RB
        SEP     R5
; RXC: RXT compiled into HEAP -> RC (0: empty: the last regex). ICASE: any case
RXC:    LOAD    RD, RXT
        LDN     RD
        LBNZ    RX1
        LOAD    RC, 0
        SEP     R5
RX1:    GHI     RA
        STXD
        GLO     RA
        STXD
        LOAD    R9, RXT
        LOAD    RD, NGRP
        LDI     0
        STR     RD
        SEP     R4
        DW      RALT
        SEP     R4            ; a ) with no (
        DW      RTOK
        LOAD    RD, TK
        LDN     RD
        LBNZ    BAD
        LDI     OP_MATCH
        SEP     R4
        DW      EMIT
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        SEP     R5
; RTOK: the next token at R9: TK, TC. 0 end, 1 a character, 2 ., 3 [, 4 *, 5 (, 6 ), 7 |, 8 +, 9 ?, 10 {, 11 ^,
;       12 $, 13 \1-\9, 14 } (of \{ \})
RTOK:   LOAD    RD, PREV
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LDA     R9
        PLO     RC
        LBNZ    RT1
        DEC     R9
        LDI     0
        LBR     RTX
RT1:    XRI     5CH
        LBZ     RTB
        LOAD    RF, RTAB1       ; always special
        SEP     R4
        DW      RTFIND
        LBDF    RTX
        LOAD    RD, EFLAG
        LDN     RD
        LBZ     RTL
        LOAD    RF, RTAB2       ; special with -E
        SEP     R4
        DW      RTFIND
        LBDF    RTX
RTL:    LDI     1
        LBR     RTX
RTB:    LDA     R9
        PLO     RC
        LBNZ    RB1
        DEC     R9
        LDI     5CH
        PLO     RC
        LBR     RTL
RB1:    XRI     'n'
        LBNZ    RB2
        LDI     0AH
        PLO     RC
        LBR     RTL
RB2:    GLO     RC
        XRI     't'
        LBNZ    RB3
        LDI     9
        PLO     RC
        LBR     RTL
RB3:    GLO     RC              ; \1 - \9
        SMI     '1'
        LBNF    RB4
        SMI     9
        LBDF    RB4
        GLO     RC
        SMI     '1'
        SHL
        SHL
        PLO     RC              ; its slot
        LDI     13
        LBR     RTX
RB4:    LOAD    RD, EFLAG
        LDN     RD
        LBNZ    RTL
        LOAD    RF, RTAB2       ; \( and so on, without -E
        SEP     R4
        DW      RTFIND
        LBDF    RTX
        LBR     RTL
RTX:    PLO     RB
        LOAD    RD, TK
        GLO     RB
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
; RTFIND: RC.0 in the table at RF (character, token): DF = 1, D the token
RTFIND: LDA     RF
        LBZ     RF8
        STR     R2
        GLO     RC
        XOR
        LBZ     RF7
        INC     RF
        LBR     RTFIND
RF7:    LDN     RF
        SMI     0
        LDN     RF
        SEP     R5
RF8:    ADI     0
        SEP     R5
RTAB1:  DB      '.',2,'[',3,'*',4,'^',11,'$',12,0
RTAB2:  DB      '(',5,')',6,'|',7,'+',8,'?',9,'{',10,'}',14,0
; RALT: a b c | d e f ...: to the end, or a ) (left for the caller)
RALT:   GHI     RA              ; where this one starts
        STXD
        GLO     RA
        STXD
        SEP     R4
        DW      RSEQ
        SEP     R4
        DW      RTOK
        LOAD    RD, TK
        LDN     RD
        XRI     7
        LBZ     RA1
        SEP     R4
        DW      UNTOK
        INC     R2
        INC     R2
        SEP     R5
RA1:    IRX                     ; RF = the start
        LDXA
        PLO     RF
        LDX
        PHI     RF
        SEP     R4           ; SPLIT over it and the JMP
        DW      SPANI
        INC     RC
        INC     RC
        INC     RC
        LDI     OP_SPLIT
        SEP     R4
        DW      PUT3
        GHI     RA              ; the JMP, to fill in
        STXD
        GLO     RA
        STXD
        LDI     OP_JMP
        SEP     R4
        DW      EMIT
        LDI     0
        SEP     R4
        DW      EMIT
        LDI     0
        SEP     R4
        DW      EMIT
        SEP     R4
        DW      RALT
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF              ; RF -> the JMP
        INC     RF
        INC     RF
        INC     RF              ; past it
        GLO     RF
        STR     R2
        GLO     RA
        SM
        PLO     RC
        GHI     RF
        STR     R2
        GHI     RA
        SMB
        PHI     RC              ; RC = the end - that
        DEC     RF
        DEC     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R5
UNTOK:  LOAD    RD, PREV
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        SEP     R5
; SPANI: RF = where a span starts (to RA): 3 bytes made free there; RC = the span's length
SPANI:  GLO     RF
        STR     R2
        GLO     RA
        SM
        PLO     RC
        GHI     RF
        STR     R2
        GHI     RA
        SMB
        PHI     RC
        GHI     RA              ; RD = the old end, RA + 3 the new
        PHI     RD
        GLO     RA
        PLO     RD
        INC     RA
        INC     RA
        INC     RA
        GHI     RA
        PHI     RB
        GLO     RA
        PLO     RB
SI1:    GHI     RD
        STR     R2
        GHI     RF
        XOR
        LBNZ    SI2
        GLO     RD
        STR     R2
        GLO     RF
        XOR
        LBZ     SS9
SI2:    DEC     RD
        DEC     RB
        LDN     RD
        STR     RB
        LBR     SI1
; PUT3: D, RC at RF
PUT3:   STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        SEP     R5
; RSEQ: atoms, each with what repeats it
RSEQ:   LOAD    RD, ATST
        LDI     1
        STR     RD
RS1:    SEP     R4
        DW      RTOK
        LOAD    RD, TK
        LDN     RD
        PLO     RB
        LBZ     RSU
        XRI     6
        LBZ     RSU
        GLO     RB
        XRI     7
        LBNZ    RS2
RSU:    LBR     UNTOK           ; the end, ) or |: back for RALT
RS2:    LOAD    RD, ATST        ; RC.1 = at the start; then not
        LDN     RD
        PHI     RC
        LDI     0
        STR     RD
        GHI     RA              ; the atom's start
        STXD
        GLO     RA
        STXD
        GLO     RB
        XRI     2
        LBNZ    RS3
        LDI     OP_ANY
        SEP     R4
        DW      EMIT
        LBR     RSQ
RS3:    GLO     RB
        XRI     3
        LBNZ    RS4
        SEP     R4
        DW      RSET
        LBR     RSQ
RS4:    GLO     RB
        XRI     5
        LBNZ    RS5
        LOAD    RD, NGRP        ; a group
        LDN     RD
        PLO     RC
        XRI     9
        LBZ     BADRE
        GLO     RC
        ADI     1
        STR     RD
        GLO     RC
        SHL
        SHL
        STXD                    ; its slot
        PLO     RC
        LDI     OP_SAVE
        SEP     R4
        DW      EMIT
        GLO     RC
        SEP     R4
        DW      EMIT
        SEP     R4
        DW      RALT
        SEP     R4
        DW      RTOK
        LOAD    RD, TK
        LDN     RD
        XRI     6
        LBNZ    BADRE
        LDI     OP_SAVE
        SEP     R4
        DW      EMIT
        IRX
        LDX
        ADI     2
        SEP     R4
        DW      EMIT
        LBR     RSQ
RS5:    GLO     RB
        XRI     13
        LBNZ    RS6
        LDI     OP_BREF
        SEP     R4
        DW      EMIT
        LOAD    RD, TC
        LDN     RD
        SEP     R4
        DW      EMIT
        LBR     RSQ
RS6:    GLO     RB
        XRI     11
        LBNZ    RS7
        LOAD    RD, EFLAG       ; ^: an anchor at the start (with -E: anywhere)
        LDN     RD
        LBNZ    RS61
        GHI     RC
        LBZ     RSLIT
RS61:   LDI     OP_BOL
        SEP     R4
        DW      EMIT
        LOAD    RD, ATST        ; (^* : the * is plain)
        LDI     1
        STR     RD
        INC     R2
        INC     R2
        LBR     RS1
RS7:    GLO     RB
        XRI     12
        LBNZ    RS8
        LOAD    RD, EFLAG       ; $: an anchor at the end
        LDN     RD
        LBNZ    RS71
        LDN     R9
        LBZ     RS71
        XRI     5CH
        LBNZ    RSLIT
        INC     R9
        LDN     R9
        DEC     R9
        XRI     ')'
        LBZ     RS71
        INC     R9
        LDN     R9
        DEC     R9
        XRI     '|'
        LBNZ    RSLIT
RS71:   LDI     OP_EOL
        SEP     R4
        DW      EMIT
        INC     R2
        INC     R2
        LBR     RS1
RS8:    GLO     RB              ; * at the start is plain; a stray + ? { } is too
RSLIT:  LOAD    RD, TC
        LDN     RD
        PLO     RC
        LOAD    RD, ICASE
        LDN     RD
        LBZ     RL1
        GLO     RC
        ANI     0DFH
        SMI     'A'
        LBNF    RL1
        SMI     26
        LBDF    RL1
        LDI     OP_CHARI
        SEP     R4
        DW      EMIT
        GLO     RC
        ANI     0DFH
        SEP     R4
        DW      EMIT
        LBR     RSQ
RL1:    LDI     OP_CHAR
        SEP     R4
        DW      EMIT
        GLO     RC
        SEP     R4
        DW      EMIT
RSQ:    SEP     R4            ; what repeats it?
        DW      RTOK
        LOAD    RD, TK
        LDN     RD
        PLO     RB
        XRI     4
        LBZ     RQ1
        GLO     RB
        XRI     8
        LBZ     RQ2
        GLO     RB
        XRI     9
        LBZ     RQ3
        GLO     RB
        XRI     10
        LBZ     RQ4
        SEP     R4           ; nothing
        DW      UNTOK
        INC     R2
        INC     R2
        LBR     RS1
RQ1:    LOAD    RC, 0           ; RC.1 min, RC.0 max (0: no limit)
        LBR     RQ5
RQ2:    LOAD    RC, 0100H
        LBR     RQ5
RQ3:    LOAD    RC, 0001H
        LBR     RQ5
RQ4:    SEP     R4
        DW      RBRACE
RQ5:    IRX                     ; RF = the atom (kept on the stack)
        LDXA
        PLO     RF
        LDX
        PHI     RF
        DEC     R2
        DEC     R2
        LDN     RF
        SMI     OP_SET + 1
        LBDF    RQM             ; not a single character
        LBR     RQS             ; REP min max before it
RQM:    LDN     RF              ; a* * : the second adds nothing
        XRI     OP_REP
        LBZ     RSQ
        LDI     0FFH            ; LSLOT: the group's slot, for OP_LOOP
        PLO     RC
        LDN     RF
        XRI     OP_SAVE
        LBNZ    RQM1
        INC     RF
        LDN     RF
        DEC     RF
        PLO     RC
RQM1:   LOAD    RD, LSLOT
        GLO     RC
        STR     RD
        LOAD    RD, TK          ; a group: * + ? only
        LDN     RD
        PLO     RB
        XRI     14
        LBZ     BADRE
        GLO     RB
        XRI     8
        LBZ     RQP
        GLO     RB              ; * ?: SPLIT over it
        STXD
        SEP     R4
        DW      SPANI
        IRX
        LDX
        PLO     RB
        XRI     4
        LBNZ    RQN
        GLO     RC              ; *: and over the LOOP
        ADI     4
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
RQN:    LDI     OP_SPLIT
        SEP     R4
        DW      PUT3
        GLO     RB
        XRI     4
        LBNZ    RSQ9
        GLO     RC              ; LOOP -(len + 7): RC is len + 4
        ADI     3
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LBR     RQJ
RQP:    GLO     RF              ; +: after it, SPLIT past a LOOP back
        STR     R2
        GLO     RA
        SM
        PLO     RC
        GHI     RF
        STR     R2
        GHI     RA
        SMB
        PHI     RC              ; its length
        LDI     OP_SPLIT
        SEP     R4
        DW      EMIT
        LDI     0
        SEP     R4
        DW      EMIT
        LDI     4
        SEP     R4
        DW      EMIT
        GLO     RC
        ADI     7
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
RQJ:    GLO     RC              ; RC = minus it
        SDI     0
        PLO     RC
        GHI     RC
        SDBI    0
        PHI     RC
        LDI     OP_LOOP
        SEP     R4
        DW      EMIT
        LOAD    RD, LSLOT
        LDN     RD
        SEP     R4
        DW      EMIT
        GHI     RC
        SEP     R4
        DW      EMIT
        GLO     RC
        SEP     R4
        DW      EMIT
RSQ9:   LBR     RSQ
RQS:    GLO     RC
        STXD
        GHI     RC
        STXD
        SEP     R4
        DW      SPANI
        IRX
        LDXA
        PHI     RC
        LDX
        PLO     RC
        LDI     OP_REP
        SEP     R4
        DW      PUT3
        LBR     RSQ
BADRE:  LBR     BAD
; RBRACE: m}, m,} or m,n} (\} without -E) at R9 -> RC.1 min, RC.0 max
RBRACE: LDI     0
        PHI     RC
        PLO     RC
        SEP     R4
        DW      RBNUM
        PHI     RC
        LDN     R9
        XRI     ','
        LBNZ    RB81
        INC     R9
        SEP     R4
        DW      RBNUM
        PLO     RC
        LBR     RB82
RB81:   GHI     RC              ; {m}: max = m
        PLO     RC
RB82:   GHI     RC
        STXD
        GLO     RC
        STXD
        SEP     R4
        DW      RTOK
        LOAD    RD, TK
        LDN     RD
        XRI     14
        LBNZ    BADRE
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        SEP     R5
; RBNUM: a number at R9 (up to 255) -> D
RBNUM:  LDI     0
        PLO     RB
RN1:    LDN     R9
        SMI     '0'
        LBNF    RN9
        SMI     10
        LBDF    RN9
        GLO     RB
        SHL
        STR     R2
        SHL
        SHL
        ADD
        STR     R2
        LDA     R9
        SMI     '0'
        ADD
        PLO     RB
        LBR     RN1
RN9:    GLO     RB
        SEP     R5
; RSET: [ ... ] at R9 (past the [): SET and its 32 bytes into HEAP
RSET:   LDI     OP_SET
        SEP     R4
        DW      EMIT
        GHI     RA
        PHI     RB
        GLO     RA
        PLO     RB              ; RB -> the bits
        LDI     32
        PLO     RC
RE1:    LDI     0
        SEP     R4
        DW      EMIT
        DEC     RC
        GLO     RC
        LBNZ    RE1
        LOAD    RD, SNEG
        LDI     0
        STR     RD
        LDN     R9
        XRI     '^'
        LBNZ    RE2
        INC     R9
        LDI     1
        STR     RD
RE2:    LDN     R9              ; a ] first is plain
        XRI     ']'
        LBNZ    RE3
        INC     R9
        LDI     ']'
        SEP     R4
        DW      SETB
RE3:    LDA     R9
        LBZ     BAD
        PLO     RC
        XRI     ']'
        LBZ     RE8
        GLO     RC
        XRI     '['
        LBNZ    RE4
        LDN     R9
        XRI     ':'
        LBNZ    RE4
        SEP     R4
        DW      RCLASS
        LBR     RE3
RE4:    GLO     RC              ; \n \t
        XRI     5CH
        LBNZ    RE5
        LDN     R9
        XRI     'n'
        LBNZ    RE41
        INC     R9
        LDI     0AH
        PLO     RC
        LBR     RE5
RE41:   LDN     R9
        XRI     't'
        LBNZ    RE5
        INC     R9
        LDI     9
        PLO     RC
RE5:    LDN     R9              ; a-z?
        XRI     '-'
        LBNZ    RE6
        INC     R9
        LDN     R9
        DEC     R9
        LBZ     RE6
        XRI     ']'
        LBZ     RE6
        INC     R9
        LDA     R9
        PHI     RC              ; RC.0 - RC.1
        SEP     R4
        DW      SETR
        LBR     RE3
RE6:    GLO     RC
        SEP     R4
        DW      SETB
        LBR     RE3
RE8:    LOAD    RD, ICASE       ; any case: A-Z and a-z alike
        LDN     RD
        LBZ     RE85
        LDI     'A'
        PLO     RC
RE81:   GLO     RC
        SEP     R4
        DW      TSTB
        LBDF    RE82
        GLO     RC
        ADI     20H
        SEP     R4
        DW      TSTB
        LBNF    RE83
RE82:   GLO     RC
        SEP     R4
        DW      SETB
        GLO     RC
        ADI     20H
        SEP     R4
        DW      SETB
RE83:   INC     RC
        GLO     RC
        XRI     'Z' + 1
        LBNZ    RE81
RE85:   LOAD    RD, SNEG
        LDN     RD
        LBZ     SS9
        LDI     32
        PLO     RC
RE86:   LDN     RB              ; [^ ...]
        XRI     0FFH
        STR     RB
        INC     RB
        DEC     RC
        GLO     RC
        LBNZ    RE86
        SEP     R5
; SETR: RC.0 to RC.1 into the bits at RB
SETR:   GLO     RC
        SEP     R4
        DW      SETB
        GLO     RC
        STR     R2
        GHI     RC
        SM
        LBNF    SS9             ; past it (or backwards)
        LBZ     SS9
        INC     RC
        LBR     SETR
; RCLASS: [:name:] at R9 (at the :)
RCLASS: LOAD    RF, CLSS
RC1:    LDN     RF
        LBZ     BAD
        GHI     R9              ; the name, past the :
        PHI     RD
        GLO     R9
        PLO     RD
        INC     RD
        LDI     5
        PLO     RC
RC2:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    RC3
        DEC     RC
        GLO     RC
        LBNZ    RC2
        GLO     R9              ; R9 past :name:]
        ADI     8
        PLO     R9
        GHI     R9
        ADCI    0
        PHI     R9
RC4:    LDA     RF              ; its ranges
        LBZ     SS9
        PLO     RC
        LDA     RF
        PHI     RC
        GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      SETR
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LBR     RC4
RC3:    DEC     RC              ; the next name
        GLO     RC
        LBZ     RC5
        INC     RF
        LBR     RC3
RC5:    LDA     RF
        LBZ     RC1
        INC     RF
        LBR     RC5
CLSS:   DB      'alpha','A','Z','a','z',0
        DB      'digit','0','9',0
        DB      'alnum','0','9','A','Z','a','z',0
        DB      'upper','A','Z',0
        DB      'lower','a','z',0
        DB      'space',9,13,' ',' ',0
        DB      'blank',9,9,' ',' ',0
        DB      'punct','!','/',':','@','[','`','{','~',0
        DB      0
; SETB: D's bit on at RB. TSTB: DF = D's bit at RB. (RD RF.0 used)
SETB:   SEP     R4
        DW      BITAT
        SEX     RD
        OR
        STR     RD
        SEX     R2
        SEP     R5
TSTB:   SEP     R4
        DW      BITAT
        SEX     RD
        AND
        SEX     R2
        LBZ     TB1
        SMI     0
        SEP     R5
TB1:    ADI     0
        SEP     R5
; BITAT: RD -> D's byte in the bits at RB; D = its mask
BITAT:  PLO     RF
        SHR
        SHR
        SHR
        STR     R2
        GLO     RB
        ADD
        PLO     RD
        GHI     RB
        ADCI    0
        PHI     RD
        GLO     RF
        ANI     7
        PLO     RF
        LDI     1
BA1:    PHI     RF
        GLO     RF
        LBZ     BA2
        DEC     RF
        GHI     RF
        SHL
        LBR     BA1
BA2:    GHI     RF
        SEP     R5
; ==== the machine
; RMATCH: the program at R8 from the text at R9: DF = 1 and ENDP. Uses RA (BT), RB, RC, RD, RF.
RMATCH: LOAD    RA, BT
VM:     LDA     R8
        XRI     OP_CHAR
        LBNZ    VM1
        LDA     R8
        STR     R2
        LDN     R9
        XOR
        LBNZ    FAIL
        INC     R9
        LBR     VM
VM1:    XRI     OP_CHAR XOR OP_REP
        LBZ     VREP
        XRI     OP_REP XOR OP_SPLIT
        LBZ     VSPLIT
        XRI     OP_SPLIT XOR OP_JMP
        LBZ     VJMP
        XRI     OP_JMP XOR OP_SAVE
        LBZ     VSAVE
        XRI     OP_SAVE XOR OP_MATCH
        LBZ     VDONE
        XRI     OP_MATCH XOR OP_BOL
        LBZ     VBOL
        XRI     OP_BOL XOR OP_EOL
        LBZ     VEOL
        XRI     OP_EOL XOR OP_BREF
        LBZ     VBREF
        XRI     OP_BREF XOR OP_LOOP
        LBZ     VLOOP
        DEC     R8              ; CHARI ANY SET
        GHI     R8
        PHI     RB
        GLO     R8
        PLO     RB
        SEP     R4
        DW      ATOM
        LBNF    FAIL
        GHI     RB              ; (RB past it)
        PHI     R8
        GLO     RB
        PLO     R8
        INC     R9
        LBR     VM
VDONE:  LOAD    RD, ENDP
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        SMI     0               ; (D kept) DF = 1
        LDI     0
        SMI     0
        SEP     R5
VBOL:   GHI     R9
        XRI     HIGH(PS)
        LBNZ    FAIL
        GLO     R9
        XRI     LOW(PS)
        LBNZ    FAIL
        LBR     VM
VEOL:   LDN     R9
        LBNZ    FAIL
        LBR     VM
VJMP:   LDA     R8
        PHI     RC
        LDA     R8
        PLO     RC
VJ1:    GLO     RC
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     RC
        STR     R2
        GHI     R8
        ADC
        PHI     R8
        LBR     VM
VLOOP:  LDA     R8              ; the slot
        PLO     RB
        LDA     R8
        PHI     RC
        LDA     R8
        PLO     RC
        GLO     RB
        XRI     0FFH
        LBZ     VJ1
        GLO     RB
        ADI     LOW(CAP)
        PLO     RF
        LDI     HIGH(CAP)
        ADCI    0
        PHI     RF
        LDA     RF
        STR     R2
        GHI     R9
        XOR
        LBNZ    VJ1
        LDN     RF
        STR     R2
        GLO     R9
        XOR
        LBNZ    VJ1
        LBR     VM              ; it matched nothing: out of the loop
VSPLIT: LDA     R8
        PHI     RC
        LDA     R8
        PLO     RC
        GLO     RC              ; RD = the other way
        STR     R2
        GLO     R8
        ADD
        PLO     RD
        GHI     RC
        STR     R2
        GHI     R8
        ADC
        PHI     RD
        SEP     R4
        DW      BPUSH
        LBNF    VM
        LDI     0               ; too deep: no match
        SHR
        SEP     R5
; BPUSH: RD, then R9, onto BT
BPUSH:  GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        INC     RA
        GHI     R9
        STR     RA
        INC     RA
        GLO     R9
        STR     RA
        INC     RA
        GHI     RA
        XRI     HIGH(BTLIM)
        LBZ     BP9
        LDI     0
        SHR                     ; DF = 0
        SEP     R5
BP9:    SMI     0               ; DF = 1: too deep
        SEP     R5
VSAVE:  LDA     R8              ; the slot
        PLO     RC
        ADI     LOW(CAP)
        PLO     RF
        LDI     HIGH(CAP)
        ADCI    0
        PHI     RF              ; RF -> it
        LDI     0               ; an undo entry: 0 slot, the old value
        STR     RA
        INC     RA
        GLO     RC
        STR     RA
        INC     RA
        LDA     RF
        STR     RA
        INC     RA
        LDN     RF
        STR     RA
        INC     RA
        DEC     RF
        GHI     R9
        STR     RF
        INC     RF
        GLO     R9
        STR     RF
        GHI     RA
        XRI     HIGH(BTLIM)
        LBNZ    VM
        LDI     0
        SHR
        SEP     R5
VREP:   LDA     R8              ; RC.1 min, RC.0 max
        PHI     RC
        LDA     R8
        PLO     RC
        LOAD    RD, REPS        ; where it starts
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LDI     0
        PLO     R7
VR1:    GLO     RC              ; the limit?
        LBZ     VR2
        GLO     R7
        STR     R2
        GLO     RC
        XOR
        LBZ     VR3
VR2:    GHI     R8
        PHI     RB
        GLO     R8
        PLO     RB
        SEP     R4
        DW      ATOM
        LBNF    VR3
        INC     R9
        GLO     R7              ; (counted to 255, then it stays there)
        XRI     0FFH
        LBZ     VR1
        INC     R7
        LBR     VR1
VR3:    GHI     R8              ; RB past the atom
        PHI     RB
        GLO     R8
        PLO     RB
        SEP     R4
        DW      ATLEN
        GHI     RB
        PHI     R8
        GLO     RB
        PLO     R8
        GLO     R7              ; fewer than min?
        STR     R2
        GHI     RC
        SD
        LBDF    VR31
        LBR     VRF
VR31:   LOAD    RD, REPS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     RC              ; RF += min: the least it may back off to
        STR     R2
        GLO     RF
        ADD
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        GLO     RF              ; R9 > RF? then it may back off
        STR     R2
        GLO     R9
        SM
        GHI     RF
        STR     R2
        GHI     R9
        SMB
        LBNF    VR4
        GLO     RF              ; (equal: nothing to back off)
        STR     R2
        GLO     R9
        XOR
        LBZ     VR4
        GHI     RF              ; the entry: min, pc + 8000, here
        STR     RA
        INC     RA
        GLO     RF
        STR     RA
        INC     RA
        GHI     R8
        ORI     80H
        STR     RA
        INC     RA
        GLO     R8
        STR     RA
        INC     RA
        GHI     R9
        STR     RA
        INC     RA
        GLO     R9
        STR     RA
        INC     RA
        GHI     RA
        XRI     HIGH(BTLIM)
        LBZ     VFULL
VR4:    LOAD    RD, R7KEEP      ; R7 back
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LBR     VM
VRF:    LOAD    RD, R7KEEP
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LBR     FAIL
VFULL:  LOAD    RD, R7KEEP
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LDI     0
        SHR
        SEP     R5
VBREF:  LDA     R8              ; the slot
        ADI     LOW(CAP)
        PLO     RF
        LDI     HIGH(CAP)
        ADCI    0
        PHI     RF
        LDA     RF              ; RB = the group's start, RC its end
        PHI     RB
        LDA     RF
        PLO     RB
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        GHI     RB
        LBZ     FAIL            ; not set
        GHI     RC
        LBZ     FAIL
VB1:    GHI     RB
        STR     R2
        GHI     RC
        XOR
        LBNZ    VB2
        GLO     RB
        STR     R2
        GLO     RC
        XOR
        LBZ     VM
VB2:    LDA     RB
        STR     R2
        LDN     R9
        XOR
        LBNZ    FAIL
        INC     R9
        LBR     VB1
; FAIL: back to the last choice
FAIL:   GHI     RA
        XRI     HIGH(BT)
        LBNZ    FA1
        GLO     RA
        XRI     LOW(BT)
        LBNZ    FA1
        LDI     0               ; none left
        SHR
        SEP     R5
FA1:    DEC     RA              ; RC = the value, RB = the pc
        LDN     RA
        PLO     RC
        DEC     RA
        LDN     RA
        PHI     RC
        DEC     RA
        LDN     RA
        PLO     RB
        DEC     RA
        LDN     RA
        PHI     RB
        LBNZ    FA2
        GLO     RB              ; 0 slot: a group put back
        ADI     LOW(CAP)
        PLO     RF
        LDI     HIGH(CAP)
        ADCI    0
        PHI     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LBR     FAIL
FA2:    ANI     80H
        LBNZ    FA3
        GHI     RB              ; a SPLIT
        PHI     R8
        GLO     RB
        PLO     R8
        GHI     RC
        PHI     R9
        GLO     RC
        PLO     R9
        LBR     VM
FA3:    GHI     RB              ; a REP: one character less
        ANI     7FH
        PHI     R8
        GLO     RB
        PLO     R8
        DEC     RC
        GHI     RC
        PHI     R9
        GLO     RC
        PLO     R9
        DEC     RA              ; the least it may be
        LDN     RA
        PLO     RF
        DEC     RA
        LDN     RA
        PHI     RF
        GHI     RF              ; there: the entry is done
        STR     R2
        GHI     R9
        XOR
        LBNZ    FA4
        GLO     RF
        STR     R2
        GLO     R9
        XOR
        LBZ     VM
FA4:    INC     RA              ; else it stays, with the new place
        INC     RA
        GHI     R8
        ORI     80H
        STR     RA
        INC     RA
        GLO     R8
        STR     RA
        INC     RA
        GHI     R9
        STR     RA
        INC     RA
        GLO     R9
        STR     RA
        INC     RA
        LBR     VM
; ATOM: DF = 1: the atom at RB matches the character at R9; RB past it if DF = 1 (not through REP's use)
ATOM:   LDN     R9
        LBZ     AT8             ; the end of the text
        LDA     RB
        XRI     OP_CHAR
        LBNZ    AT1
        LDA     RB
        STR     R2
        LDN     R9
        XOR
        LBNZ    AT8
AT7:    LDI     0
        SMI     0
        SEP     R5
AT8:    LDI     0
        SHR
        SEP     R5
AT1:    XRI     OP_CHAR XOR OP_ANY
        LBZ     AT7
        XRI     OP_ANY XOR OP_CHARI
        LBNZ    AT3
        LDN     R9              ; capitals
        PLO     RD
        SMI     'a'
        LBNF    AT2
        SMI     26
        LBDF    AT2
        GLO     RD
        ANI     0DFH
        PLO     RD
AT2:    LDA     RB
        STR     R2
        GLO     RD
        XOR
        LBNZ    AT8
        LBR     AT7
AT3:    LDN     R9              ; a set
        SEP     R4
        DW      TSTB
        LBNF    AT8
        GLO     RB
        ADI     32
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        LBR     AT7
; ATLEN: RB past the atom at RB
ATLEN:  LDA     RB
        XRI     OP_ANY
        LBZ     SS9
        XRI     OP_ANY XOR OP_SET
        LBZ     AL1
        INC     RB
        SEP     R5
AL1:    GLO     RB
        ADI     32
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        SEP     R5
; SEARCH: the regex at RCUR, from SPOS on: DF = 1, MST ENDP and CAP
SEARCH: LOAD    RD, R7KEEP
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        LOAD    RD, CAP         ; no group yet (a try that fails puts them all back)
        LDI     36
        PLO     RC
SE0:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    SE0
SE1:    LOAD    RD, RCUR
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        LOAD    RD, SPOS
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LDN     R8              ; starts with a plain character: find it first
        XRI     OP_CHAR
        LBNZ    SE3
        INC     R8
        LDN     R8
        DEC     R8
        STR     R2
SE2:    LDN     R9
        LBZ     SEN
        XOR
        LBZ     SE21
        INC     R9
        LBR     SE2
SE21:   LOAD    RD, SPOS
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
SE3:    SEP     R4
        DW      RMATCH
        LBDF    SEY
        LOAD    RD, RCUR        ; ^ first: only one place to try
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDN     RF
        XRI     OP_BOL
        LBZ     SEN
        LOAD    RD, SPOS        ; on
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LDN     R9
        LBZ     SEN
        INC     R9
        LOAD    RD, SPOS
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LBR     SE1
SEN:    LDI     0
        SHR
        SEP     R5
SEY:    LDI     0
        SMI     0
        SEP     R5
; USERE: RC = a regex (0: the last): RCUR; SPOS = the start of the line; then SEARCH
USERE:  GHI     RC
        LBZ     UR1
        LOAD    RD, RCUR
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
UR1:    LOAD    RD, SPOS
        LDI     HIGH(PS)
        STR     RD
        INC     RD
        LDI     LOW(PS)
        STR     RD
        LBR     SEARCH
; ==== reading
; NEXTL: the next line into NX; NXOK = 1, or 0 at the end of the last file
NEXTL:  GLO     R7              ; (the kernel's file reading uses R7)
        STXD
        GHI     R7
        STXD
        LOAD    RD, NXOK
        LDI     0
        STR     RD
        LOAD    RD, GOTB
        LDI     0
        STR     RD
        LOAD    RA, NX
NL1:    LOAD    RD, INOPEN
        LDN     RD
        LBNZ    NL3
        LOAD    RD, FI          ; the next file
        LDN     RD
        PLO     RC
        STR     R2
        LOAD    RD, FLN
        LDN     RD
        XOR
        LBZ     NL9             ; no more
        SEP     R4
        DW      FLGET
        SEP     R4
        DW      KS_FINDN
        LBDF    NL2             ; gone
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, SREM
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, INOPEN
        LDI     1
        STR     RD
        LBR     NL3
NL2:    LOAD    RD, FI
        LDN     RD
        ADI     1
        STR     RD
        LBR     NL1
NL3:    SEP     R4
        DW      GETB
        LBDF    NL6             ; the end of this file
        LBZ     NL3             ; a NUL
        PLO     RB
        XRI     0DH
        LBZ     NL3
        LOAD    RD, GOTB
        LDI     1
        STR     RD
        GLO     RB
        XRI     0AH
        LBZ     NL8
        GHI     RA              ; full: the rest is cut
        XRI     HIGH(NXEND)
        LBZ     NL3
        GLO     RB
        STR     RA
        INC     RA
        LBR     NL3
NL6:    LOAD    RD, INOPEN
        LDI     0
        STR     RD
        LOAD    RD, FI
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, GOTB        ; a last line with no LF
        LDN     RD
        LBZ     NL1
NL8:    LOAD    RD, NXOK
        LDI     1
        STR     RD
NL9:    LDI     0
        STR     RA
        IRX
        LDXA
        PHI     R7
        LDX
        PLO     R7
        SEP     R5
; GETL: PS = the line read ahead, the next read ahead. DF = 1: none. N: GETLA adds it to PS after an LF
GETL:   LOAD    RD, NXOK
        LDN     RD
        LBZ     GL9
        LOAD    RD, PS
        LBR     GL1
GETLA:  LOAD    RD, NXOK
        LDN     RD
        LBZ     GL9
        LOAD    RD, PS
        SEP     R4
        DW      FINDEND
        LDI     0AH
        STR     RD
        INC     RD
GL1:    LOAD    RF, NX
        LDI     HIGH(PS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        SEP     R4
        DW      NEXTL
        LOAD    RD, LNO + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LDI     0
        SHR
        SEP     R5
GL9:    LDI     0
        SMI     0
        SEP     R5
; FINDEND: RD -> the 0 of the text at RD
FINDEND: LDN    RD
        LBZ     SS9
        INC     RD
        LBR     FINDEND
; SCOPY: the text at RF to RD, 0-ended, cut where RD's high byte reaches RB.1. RD ends at the 0.
SCOPY:  LDN     RF
        LBZ     SC9
        GHI     RD
        STR     R2
        GHI     RB
        XOR
        LBZ     SC9
        LDA     RF
        STR     RD
        INC     RD
        LBR     SCOPY
SC9:    LDI     0
        STR     RD
        SEP     R5
; ==== printing: PUTS the text at RF, PUTC D (an LF as a new line). NEWL a new line
PUTS:   LDA     RF
        LBZ     SS9
        SEP     R4
        DW      PUTC
        LBR     PUTS
PUTC:   PLO     RB
        XRI     0AH
        LBZ     NEWL
        GLO     RB
        SEP     R4
        DW      F_TYPE
        SEP     R5
NEWL:   LDI     0DH
        SEP     R4
        DW      F_TYPE
        LDI     0AH
        SEP     R4
        DW      F_TYPE
        SEP     R5
PPS:    LOAD    RF, PS
        SEP     R4
        DW      PUTS
        LBR     NEWL
; AUTOP: the pattern space, unless -n. Then what a queued. FLUSHA alone: what a queued
AUTOP:  LOAD    RD, NFLAG
        LDN     RD
        LBNZ    FLUSHA
        SEP     R4
        DW      PPS
FLUSHA: LOAD    RD, NAQ
        LDN     RD
        LBZ     SS9
        LDI     0
        PLO     RC
FU1:    GLO     RC
        SHL
        ADI     LOW(AQ)
        PLO     RD
        LDI     HIGH(AQ)
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     RC
        STXD
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      NEWL
        IRX
        LDX
        ADI     1
        PLO     RC
        STR     R2
        LOAD    RD, NAQ
        LDN     RD
        XOR
        LBNZ    FU1
        LOAD    RD, NAQ
        LDI     0
        STR     RD
        SEP     R5
; ==== running it
RUN:    SEP     R4           ; the first line, read ahead
        DW      NEXTL
CYCLE:  SEP     R4
        DW      GETL
        LBDF    DONE
        LOAD    RD, SFLAG
        LDI     0
        STR     RD
RESTART: LOAD   R7, CMDT
EX:     LDN     R7
        LBZ     ENDC
        SEP     R4
        DW      SELECT
        LBDF    EX2
        LDN     R7              ; not for this line
        XRI     '{'
        LBNZ    NEXTC
        GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     R7
        GHI     RB
        PHI     R7
NEXTC:  GLO     R7
        ADI     16
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        LBR     EX
EX2:    LDN     R7
        PLO     RC
        LOAD    RF, DTAB
EX3:    LDA     RF
        LBZ     NEXTC           ; { } : nothing to do
        STR     R2
        GLO     RC
        XOR
        LBZ     EX4
        INC     RF
        INC     RF
        LBR     EX3
EX4:    LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        LOAD    RD, JMPT + 1    ; go there
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
JMPT:   LBR     0
ENDC:   SEP     R4
        DW      AUTOP
        LBR     CYCLE
DONE:   LBR     K_MAIN
XQUIT:  SEP     R4
        DW      AUTOP
        LBR     K_MAIN
DTAB:   DB      's'
        DW      XS
        DB      'p'
        DW      XP
        DB      'd'
        DW      XD
        DB      'b'
        DW      XB
        DB      't'
        DW      XT
        DB      'T'
        DW      XTT
        DB      'n'
        DW      XN
        DB      'N'
        DW      XNN
        DB      'q'
        DW      XQUIT
        DB      'Q'
        DW      K_MAIN
        DB      'g'
        DW      XG
        DB      'G'
        DW      XGG
        DB      'h'
        DW      XH
        DB      'H'
        DW      XHH
        DB      'x'
        DW      XX
        DB      'P'
        DW      XPP
        DB      'D'
        DW      XDD
        DB      'a'
        DW      XA
        DB      'i'
        DW      XI
        DB      'c'
        DW      XC
        DB      '='
        DW      XEQ
        DB      'y'
        DW      XY
        DB      'l'
        DW      XL
        DB      0
XP:     SEP     R4
        DW      PPS
        LBR     NEXTC
XD:     SEP     R4
        DW      FLUSHA
        LBR     CYCLE
XDD:    LOAD    RF, PS          ; an LF? all up to it goes, and round again with no new line
XD1:    LDA     RF
        LBZ     XD
        XRI     0AH
        LBNZ    XD1
        LOAD    RD, PS
        LDI     HIGH(PS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        SEP     R4
        DW      FLUSHA
        LBR     RESTART
XPP:    LOAD    RF, PS          ; to the first LF
XPP1:   LDA     RF
        LBZ     XPP2
        PLO     RB
        XRI     0AH
        LBZ     XPP2
        GLO     RB
        SEP     R4
        DW      F_TYPE
        LBR     XPP1
XPP2:   SEP     R4
        DW      NEWL
        LBR     NEXTC
XB:     GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     R7
        GHI     RB
        PHI     R7
        LBR     EX
XT:     LOAD    RD, SFLAG
        LDN     RD
        LBZ     NEXTC
        LDI     0
        STR     RD
        LBR     XB
XTT:    LOAD    RD, SFLAG
        LDN     RD
        LBZ     XB
        LDI     0
        STR     RD
        LBR     NEXTC
XN:     LOAD    RD, NXOK        ; none left: as q
        LDN     RD
        LBZ     XQUIT
        SEP     R4
        DW      AUTOP
        SEP     R4
        DW      GETL
        LBR     NEXTC
XNN:    SEP     R4
        DW      GETLA
        LBDF    XQUIT
        LBR     NEXTC
XG:     LOAD    RF, HS
        LOAD    RD, PS
        LDI     HIGH(PS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LBR     NEXTC
XGG:    LOAD    RD, PS
        SEP     R4
        DW      FINDEND
        LDI     0AH
        STR     RD
        INC     RD
        LOAD    RF, HS
        LDI     HIGH(PS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LBR     NEXTC
XH:     LOAD    RF, PS
        LOAD    RD, HS
        LDI     HIGH(HS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LBR     NEXTC
XHH:    LOAD    RD, HS
        SEP     R4
        DW      FINDEND
        LDI     0AH
        STR     RD
        INC     RD
        LOAD    RF, PS
        LDI     HIGH(HS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LBR     NEXTC
XX:     LOAD    RF, PS          ; through OB
        LOAD    RD, OB
        LDI     HIGH(OB + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LOAD    RF, HS
        LOAD    RD, PS
        LDI     HIGH(PS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LOAD    RF, OB
        LOAD    RD, HS
        LDI     HIGH(HS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LBR     NEXTC
XA:     LOAD    RD, NAQ         ; at the end of the cycle
        LDN     RD
        PLO     RC
        XRI     16
        LBZ     NEXTC
        GLO     RC
        ADI     1
        STR     RD
        GLO     RC
        SHL
        ADI     LOW(AQ)
        PLO     RD
        LDI     HIGH(AQ)
        ADCI    0
        PHI     RD
        GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        LBR     NEXTC
XI:     SEP     R4
        DW      PTEXT
        LBR     NEXTC
XC:     GLO     R7            ; a range: the text at its end
        ORI     C_K2
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        LBZ     XC1
        GLO     R7
        ORI     C_FL
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ANI     2
        LBNZ    XC2
XC1:    SEP     R4
        DW      PTEXT
XC2:    LBR     XD
PTEXT:  GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RF
        GHI     RB
        PHI     RF
        SEP     R4
        DW      PUTS
        LBR     NEWL
XEQ:    LOAD    RF, LNO
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      NEWL
        LBR     NEXTC
XY:     GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        PHI     R9
        LDN     RF
        PLO     R9              ; R9 -> the pairs
        LOAD    RD, PS
XY1:    LDN     RD
        LBZ     NEXTC
        GHI     R9
        PHI     RF
        GLO     R9
        PLO     RF
XY2:    LDA     RF
        LBZ     XY4
        STR     R2
        LDN     RD
        XOR
        LBZ     XY3
        INC     RF
        LBR     XY2
XY3:    LDN     RF
        STR     RD
XY4:    INC     RD
        LBR     XY1
XL:     LOAD    R9, PS          ; each character plainly, $ at the end; 69 to a line
        LDI     0
        PLO     RA
XL1:    LDA     R9
        LBZ     XL9
        PLO     RC
        LOAD    RF, LESC
XL2:    LDA     RF
        LBZ     XL3
        STR     R2
        GLO     RC
        XOR
        LBZ     XL25
        INC     RF
        LBR     XL2
XL25:   LDN     RF              ; \n \t \\
        PLO     RC
        LDI     5CH
        SEP     R4
        DW      XLC
        GLO     RC
        SEP     R4
        DW      XLC
        LBR     XL1
XL3:    GLO     RC
        SMI     20H
        LBNF    XL4
        GLO     RC
        SHL
        LBDF    XL4
        GLO     RC
        SMI     7FH
        LBZ     XL4
        GLO     RC
        SEP     R4
        DW      XLC
        LBR     XL1
XL4:    LDI     5CH             ; octal
        SEP     R4
        DW      XLC
        GLO     RC
        SHR
        SHR
        SHR
        SHR
        SHR
        SHR
        ADI     '0'
        SEP     R4
        DW      XLC
        GLO     RC
        SHR
        SHR
        SHR
        ANI     7
        ADI     '0'
        SEP     R4
        DW      XLC
        GLO     RC
        ANI     7
        ADI     '0'
        SEP     R4
        DW      XLC
        LBR     XL1
XL9:    LDI     '$'
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      NEWL
        LBR     NEXTC
XLC:    PHI     RC
        GLO     RA
        XRI     69
        LBNZ    XLC1
        LDI     5CH
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      NEWL
        LDI     0
        PLO     RA
XLC1:   INC     RA
        GHI     RC
        SEP     R4
        DW      F_TYPE
        SEP     R5
LESC:   DB      0AH,'n',9,'t',5CH,5CH,0
; SELECT: DF = 1: this command is for this line
SELECT: GLO     R7
        ORI     C_K1
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        LBZ     SL8             ; no address: yes
        GLO     R7
        ORI     C_K2
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        LBNZ    SL2
        LOAD    RC, C_K1
        SEP     R4
        DW      TESTA
        LBR     SL9
SL2:    GLO     R7            ; a range
        ORI     C_FL
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ANI     2
        LBNZ    SL4
        LOAD    RC, C_K1        ; closed: does it open?
        SEP     R4
        DW      TESTA
        LBNF    SL9
        GLO     R7
        ORI     C_K2
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        XRI     1
        LBNZ    SL3
        GLO     R7            ; to a line already passed: this line alone
        ORI     C_V2
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        LOAD    RD, LNO + 1
        LDN     RD
        STR     R2
        GLO     RB
        SD                      ; LNO - V2
        DEC     RD
        LDN     RD
        STR     R2
        GHI     RB
        SDB
        LBDF    SL8
SL3:    GLO     R7
        ORI     C_FL
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ORI     2
        STR     RF
        LBR     SL8
SL4:    GLO     R7            ; open: does it close?
        ORI     C_K2
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        XRI     1
        LBNZ    SL5
        GLO     R7            ; a line: closes at it, or past it
        ORI     C_V2
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        LOAD    RD, LNO + 1
        LDN     RD
        STR     R2
        GLO     RB
        SD
        DEC     RD
        LDN     RD
        STR     R2
        GHI     RB
        SDB
        LBNF    SL8             ; before it
        LBR     SL6
SL5:    LOAD    RC, C_K2
        SEP     R4
        DW      TESTA
        LBNF    SL8
SL6:    GLO     R7
        ORI     C_FL
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ANI     0FDH
        STR     RF
SL8:    LDI     0
        SMI     0
SL9:    GLO     R7            ; ! turns it round (FLD keeps DF)
        ORI     C_FL
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ANI     1
        LBNZ    SL95
        SEP     R5
SL95:   LBDF    SL96
        LDI     0
        SMI     0
        SEP     R5
SL96:   LDI     0
        SHR
        SEP     R5
; TESTA: RC.0 = C_K1 or C_K2: DF = 1: that address is this line
TESTA:  GLO     RC              ; RF -> the kind
        STR     R2
        GLO     R7
        OR
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        PLO     RB
        GLO     RC              ; RF -> the value: K1 +2, K2 +3
        ANI     1
        ADI     2
        STR     R2
        GLO     RF
        ADD
        PLO     RF
        GLO     RB
        XRI     2
        LBNZ    TA2
        LOAD    RD, NXOK        ; $: no line read ahead
        LDN     RD
        LBZ     TAY
TAN:    LDI     0
        SHR
        SEP     R5
TAY:    LDI     0
        SMI     0
        SEP     R5
TA2:    GLO     RB
        XRI     1
        LBNZ    TA3
        LOAD    RD, LNO         ; a line
        LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    TAN
        LDN     RF
        STR     R2
        LDN     RD
        XOR
        LBNZ    TAN
        LBR     TAY
TA3:    LDA     RF              ; a regex
        PHI     RC
        LDN     RF
        PLO     RC
        LBR     USERE
; XS: s
XS:     GLO     R7
        ORI     C_A1
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        SEP     R4           ; RCUR, SPOS, nothing found yet
        DW      USEXS
        LOAD    RD, OP
        LDI     HIGH(OB)
        STR     RD
        INC     RD
        LDI     LOW(OB)
        STR     RD
XS1:    SEP     R4         ; (from SPOS: but copying starts at CPOS)
        DW      SEARCHA
        LBNF    XS8
        LOAD    RD, ENDP        ; empty, and just after the last one: step on
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, SPOS
        LDA     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    XS3
        LDN     RD
        STR     R2
        GLO     RC
        XOR
        LBNZ    XS3
        LOAD    RD, LASTE       ; (empty: ENDP = SPOS, where the match began)
        LDA     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    XS3
        LDN     RD
        STR     R2
        GLO     RC
        XOR
        LBNZ    XS3
        LOAD    RD, CNT
        LDN     RD
        LBZ     XS3
        LBR     XS6             ; not a match: one character on
XS3:    SEP     R4            ; what is before it
        DW      CPTO
        LOAD    RD, CNT         ; count it
        LDN     RD
        ADI     1
        STR     RD
        PLO     RC
        GLO     R7           ; this one? (0: the first)
        ORI     C_NTH
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        LBNZ    XS31
        LDI     1
XS31:   STR     R2
        GLO     RC
        SM
        LBDF    XS32
        SEP     R4         ; too early: it stays
        DW      CPMATCH
        LBR     XS4
XS32:   SEP     R4
        DW      REPL
        LOAD    RD, DID
        LDI     1
        STR     RD
XS4:    LOAD    RD, ENDP        ; on from its end
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, LASTE
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, CPOS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, SPOS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, DID         ; not g: one is enough
        LDN     RD
        LBZ     XS5
        GLO     R7
        ORI     C_SF
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ANI     1
        LBZ     XS8
XS5:    LBR     XS1             ; (an empty match: the test at XS1 steps on)
XS6:    LOAD    RD, SPOS        ; (the character is copied when the next one is)
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDN     RF
        LBZ     XS8
        INC     RF
        LOAD    RD, SPOS
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LBR     XS1
XS8:    LOAD    RD, DID
        LDN     RD
        LBZ     NEXTC           ; nothing changed
        LOAD    RD, CPOS        ; the rest
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, OP
        LDA     RD
        STR     R2
        LDN     RD
        PLO     RD
        LDN     R2
        PHI     RD
        LDI     HIGH(OB + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LOAD    RF, OB
        LOAD    RD, PS
        LDI     HIGH(PS + 400H)
        PHI     RB
        SEP     R4
        DW      SCOPY
        LOAD    RD, SFLAG
        LDI     1
        STR     RD
        GLO     R7
        ORI     C_SF
        PLO     RF
        GHI     R7
        PHI     RF
        LDN     RF
        ANI     2
        LBZ     NEXTC
        SEP     R4
        DW      PPS
        LBR     NEXTC
; USEXS: RCUR = RC (0: the last), SPOS CPOS = the line's start, CNT DID LASTE: 0
USEXS:  GHI     RC
        LBZ     UX1
        LOAD    RD, RCUR
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
UX1:    LOAD    RD, SPOS
        LDI     HIGH(PS)
        STR     RD
        INC     RD
        LDI     LOW(PS)
        STR     RD
        LOAD    RD, CPOS
        LDI     HIGH(PS)
        STR     RD
        INC     RD
        LDI     LOW(PS)
        STR     RD
        LOAD    RD, CNT
        LDI     0
        STR     RD
        LOAD    RD, DID
        LDI     0
        STR     RD
        LOAD    RD, LASTE
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R5
; SEARCHA: SEARCH, keeping MST = where it matched (SPOS, moved on to it)
SEARCHA: SEP     R4
        DW      SEARCH
        LBNF    SS9
        LOAD    RD, SPOS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, MST
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LDI     0
        SMI     0
        SEP     R5
; CPTO: from CPOS to MST into OB. CPMATCH: from MST to ENDP. REPL: the replacement
CPTO:   LOAD    RD, CPOS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, MST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LBR     CPR
CPMATCH: LOAD   RD, MST
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, ENDP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
; CPR: RF up to RC into OB (at OP)
CPR:    LOAD    RD, OP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
CR1:    GHI     RF
        STR     R2
        GHI     RC
        XOR
        LBNZ    CR2
        GLO     RF
        STR     R2
        GLO     RC
        XOR
        LBZ     CR9
CR2:    GHI     RA
        XRI     HIGH(OB + 400H)
        LBZ     CR9
        LDA     RF
        STR     RA
        INC     RA
        LBR     CR1
CR9:    LOAD    RD, OP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R5
REPL:   GLO     R7
        ORI     C_A2
        PLO     RF
        GHI     R7
        PHI     RF
        LDA     RF
        PHI     R9
        LDN     RF
        PLO     R9
RP1:    LDA     R9
        LBZ     SS9
        PLO     RC
        XRI     1
        LBZ     RP2
        LOAD    RD, OP          ; a character
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     RF
        XRI     HIGH(OB + 400H)
        LBZ     RP1
        GLO     RC
        STR     RF
        INC     RF
        LOAD    RD, OP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LBR     RP1
RP2:    LDA     R9              ; & or \n
        LBNZ    RP3
        SEP     R4
        DW      CPMATCH
        LBR     RP1
RP3:    SMI     1               ; group n
        SHL
        SHL
        ADI     LOW(CAP)
        PLO     RD
        LDI     HIGH(CAP)
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     RF
        LDA     RD
        PLO     RF
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RF
        LBZ     RP1             ; it took no part
        GHI     RC
        LBZ     RP1
        SEP     R4
        DW      CPR
        LBR     RP1
        INCL    "tools.inc"
        INCL    "flist.inc"
        INCL    "getb.inc"
PEND:
; ---- the data (the program clears what it needs)
DATA    EQU     ((PEND + 255) / 256) * 256
CMDT    EQU     DATA            ; NCMD * 16
PSB     EQU     DATA + 300H
PS      EQU     PSB + 1         ; the pattern space, the hold space, the s output: 1,023 characters each
HS      EQU     PSB + 401H      ;  (from a page's second byte: a high byte of base + 4 is the end, and the 0 there
OB      EQU     PSB + 801H      ;   falls on the next one's unused first byte)
NX      EQU     PSB + 0C01H     ; the line read ahead
NXEND   EQU     PSB + 0E00H
SRC     EQU     PSB + 0E01H     ; the script while it is compiled; then BT, the machine's stack
SRCEND  EQU     PSB + 1200H
BT      EQU     SRC
BTLIM   EQU     PSB + 1100H
RXT     EQU     PSB + 1200H     ; a regex's text
HEAP    EQU     PSB + 1300H
HEAPEND EQU     PSB + 1900H
VARS    EQU     PSB + 1900H
FLBUF   EQU     VARS + 100H
DEND    EQU     FLBUF + FLMAX * 13
NFLAG   EQU     VARS
EFLAG   EQU     VARS + 1
GOTS    EQU     VARS + 2
SRCP    EQU     VARS + 3        ; (2)
ARGS    EQU     VARS + 5        ; (2)
TMP11   EQU     VARS + 7        ; (11)
BRD     EQU     VARS + 18
BRS     EQU     VARS + 19       ; (24)
CMEND   EQU     VARS + 43       ; (2)
ICASE   EQU     VARS + 45
DELIM   EQU     VARS + 46
NGRP    EQU     VARS + 47
TK      EQU     VARS + 48       ; TC follows it
TC      EQU     VARS + 49
PREV    EQU     VARS + 50       ; (2)
ATST    EQU     VARS + 52
SNEG    EQU     VARS + 53
CAP     EQU     VARS + 54       ; (36)
ENDP    EQU     VARS + 90       ; (2)
R7KEEP  EQU     VARS + 92       ; (2)
RCUR    EQU     VARS + 94       ; (2)
SPOS    EQU     VARS + 96       ; (2)
CPOS    EQU     VARS + 98       ; (2)
MST     EQU     VARS + 100      ; (2)
LASTE   EQU     VARS + 102      ; (2)
OP      EQU     VARS + 104      ; (2)
CNT     EQU     VARS + 106
DID     EQU     VARS + 107
LNO     EQU     VARS + 108      ; (2)
NXOK    EQU     VARS + 110
GOTB    EQU     VARS + 111
INOPEN  EQU     VARS + 112
SFLAG   EQU     VARS + 113
NAQ     EQU     VARS + 114
AQ      EQU     VARS + 115      ; (32)
SREM    EQU     VARS + 147      ; (2)
SPTR    EQU     VARS + 149      ; (2)
FI      EQU     VARS + 151
FLN     EQU     VARS + 152
FLP     EQU     VARS + 153      ; (2)
NXARG   EQU     VARS + 155      ; (2)
REPS    EQU     VARS + 157      ; (2)
LINES   EQU     VARS + 159      ; (tools.inc's)
LSLOT   EQU     VARS + 160
        END
