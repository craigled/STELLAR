; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; make.asm - MAKE.PRG: MAKE [-n] [-f file] [NAME=value] [targets] - remakes the files that are older than the
; files they are made from, as Unix make, by the rules in MAKEFILE (in this folder):
;
;   # a comment                     NAME = value   NAME := value   NAME += more   NAME ?= value
;   target [target ...]: [names]    a rule: the target is remade when a name is newer, or the target is not there
;   <Tab or spaces>command          the rule's commands (any LTOS command or script line)
;   .PHONY: names                   names that are never files (always remade)
;   $(NAME) ${NAME}  a variable;  $@ the target, $< its first name, $^ all of them;  $$ a $
;   a command starting @ is not shown first; - its failure does not stop MAKE
;
; How: the MAKEFILE is read into memory and its rules listed; each target asked for (the first rule's, with none)
; is looked at, its names first, depth first. The FAT's write date and time (2 seconds) say which is newer.
; Everything to be done is known before anything runs (as make -n), so the commands are written in order to a
; script, /_MAKE.SH (hidden), each shown first (echo) and checked after ($?); then the kernel runs "SH /_MAKE"
; (K_EXEC: it never comes back here). -n shows the commands and runs nothing.
;
; Memory: the code and its variables $3000-$45FF; the MAKEFILE $4600-$55FF (4 KB); the variables $5600-$58FF;
; the rules $5900-$5EFF; the script $5F00-$6BFF; a line $7700, a line expanded $7800, a name $7900, the targets
; asked for $7940, += $7A00, the rules being looked at (20 deep) $7B00.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

MF      EQU     4600H           ; the MAKEFILE, a 0 after it (the code ends below it: verify_make checks)
MFMAX   EQU     0FFFH
VT      EQU     5600H           ; the variables: [flag 'C' (the command line) or 'M'] NAME 0 value 0 ...
VTTOP   EQU     5900H
RT      EQU     5900H           ; the rules: one entry for each target (below)
RTTOP   EQU     5F00H
SB      EQU     5F00H           ; the script
SBTOP   EQU     6C00H
LBUF    EQU     7700H           ; a line as it is (page-aligned)
EXB     EQU     7800H           ; a line with its $(...) put in
NBUF    EQU     7900H           ; a name (64)
GOALS   EQU     7940H           ; the targets asked for: each 0-ended, a 0 after the last
TMPV    EQU     7A00H           ; += : the old value and the new (page-aligned)
FRAMES  EQU     7B00H           ; EVAL's frames (FSZ each, 20 at most: in one page)
FSZ     EQU     12
F_EN    EQU     2               ; frame: 0 the name (2), 2 its rule (2), 4 the next of its names (2),
F_PP    EQU     4               ;  6 its time (4: date, time - high bytes first), 10 1 = it is there,
F_TM    EQU     6               ;  11 1 = it is to be remade
F_EX    EQU     10
F_OUT   EQU     11
; a rule's entry: 0 flags (1 done, 2 being looked at, 4 remade, 8 there), 1 its time (4), 5 where its commands
; start in the MAKEFILE (2, 0: none), 7 where they end (2), 9 the target 0, its names each 0, a 0 after the last

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
        LOAD    RD, VARS        ; the variables: 0
        LOAD    RC, VEND - VARS
ST0:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST0
        GHI     RC
        LBNZ    ST0
        LOAD    RD, CFL         ; no frame yet
        LDI     0F4H
        STR     RD
        LOAD    RD, VTE
        LDI     HIGH(VT)
        STR     RD
        INC     RD
        LDI     LOW(VT)
        STR     RD
        LOAD    RD, RTE
        LDI     HIGH(RT)
        STR     RD
        INC     RD
        LDI     LOW(RT)
        STR     RD
        LOAD    RD, SBE
        LDI     HIGH(SB)
        STR     RD
        INC     RD
        LDI     LOW(SB)
        STR     RD
        LOAD    RD, GOALE
        LDI     HIGH(GOALS)
        STR     RD
        INC     RD
        LDI     LOW(GOALS)
        STR     RD
        LOAD    RD, GOALS
        LDI     0
        STR     RD
        LOAD    RA, DEFMF       ; MAKEFILE unless -f
        LOAD    RD, MFN
ST1:    LDA     RA
        STR     RD
        INC     RD
        LBNZ    ST1
; ---- the words typed
AR1:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     AR9
        XRI     '-'
        LBNZ    AR3
        INC     RF
        LDA     RF
        ANI     0DFH            ; (upper case)
        XRI     'N'
        LBNZ    AR2
        LOAD    RD, NFLAG
        LDI     1
        STR     RD
        LDN     RF              ; -n: then a space or the end
        LBZ     AR1
        XRI     ' '
        LBNZ    USE
        LBR     AR1
AR2:    XRI     08H             ; 'N' ^ 'F': -f file
        LBNZ    USE
        LDN     RF
        XRI     ' '
        LBNZ    USE
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        LOAD    RD, MFN
        LDI     63
        PLO     RC
AR2A:   LDN     RF
        LBZ     AR2B
        XRI     ' '
        LBZ     AR2B
        LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBZ     USE
        LBR     AR2A
AR2B:   LDI     0
        STR     RD
        LBR     AR1
AR3:    GHI     RF              ; NAME=value, or a target?
        PHI     RA
        GLO     RF
        PLO     RA
AR3A:   LDN     RA
        LBZ     AR4
        XRI     ' '
        LBZ     AR4
        LDA     RA
        XRI     '='
        LBNZ    AR3A
        SEP     R4
        DW      CLVAR
        LBR     AR1
AR4:    LOAD    RD, GOALE       ; a target: upper case, to GOALS
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
AR4A:   LDN     RF
        LBZ     AR4B
        XRI     ' '
        LBZ     AR4B
        LDA     RF
        SEP     R4
        DW      UPCH
        STR     RA
        INC     RA
        GLO     RA
        SMI     0FCH
        LBDF    USE
        LBR     AR4A
AR4B:   LDI     0
        STR     RA
        INC     RA
        STR     RA              ; (the end, for now)
        LOAD    RD, GOALE
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LBR     AR1
; ---- the MAKEFILE
AR9:    LOAD    RF, MFN
        LOAD    RD, N11
        SEP     R4
        DW      K_PARSE
        LBDF    NOMF
        LOAD    RD, N11         ; a wildcard is not a name
        LDI     11
        PLO     RC
AR9A:   LDA     RD
        XRI     '?'
        LBZ     NOMF
        DEC     RC
        GLO     RC
        LBNZ    AR9A
        LOAD    RD, N11
        SEP     R4
        DW      KS_FINDN
        LBDF    NOMF
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    NOMF
        LOAD    RF, MFN
        LOAD    RA, MF
        LOAD    RC, MFMAX
        SEP     R4
        DW      K_LOADF         ; RC = its bytes (too big: said, and back to the prompt)
        GLO     RC
        PLO     RD
        GHI     RC
        ADI     HIGH(MF)
        PHI     RD
        LDI     0
        STR     RD
        LOAD    RF, SHEAD       ; the script's first lines
        SEP     R4
        DW      WS
; ---- its lines
        LOAD    RD, PP
        LDI     HIGH(MF)
        STR     RD
        INC     RD
        LDI     LOW(MF)
        STR     RD
PM1:    LOAD    RD, PP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDN     RA
        LBZ     PMEND
        LOAD    RD, LSTART
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, LINENO + 1  ; the line's number
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R4
        DW      CPLINE          ; -> LBUF, RA past it
        LOAD    RD, PP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RF, LBUF
        LDN     RF
        LBZ     PM1             ; empty
        XRI     09H
        LBZ     PMCMD           ; a Tab or a space first: a command
        XRI     29H             ; (09H ^ 20H)
        LBZ     PMCMD
        XRI     03H             ; (20H ^ '#'): a comment
        LBZ     PM1
        LBR     PMR
PMCMD:  SEP     R4
        DW      SKIPW
        LDN     RF
        LBZ     PM1             ; only spaces
        XRI     '#'
        LBZ     PM1
        LOAD    RD, XMODE       ; its $(...) checked now (so a mistake has its line's number)
        LDI     0
        STR     RD
        LOAD    RD, EXB
        SEP     R4
        DW      EXPAND
        LOAD    RD, CURS        ; the rule it belongs to (all its targets)
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        GHI     RB
        LBZ     ENOCMD
PC1:    LOAD    RD, RTE         ; RB = the end?
        LDA     RD
        STR     R2
        GHI     RB
        XOR
        LBNZ    PC2
        LDN     RD
        STR     R2
        GLO     RB
        XOR
        LBZ     PM1
PC2:    GLO     RB              ; RD -> its commands' start
        ADI     5
        PLO     RD
        GHI     RB
        ADCI    0
        PHI     RD
        LDN     RD
        LBNZ    PC3             ; set already
        LOAD    RC, LSTART
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        DEC     RD
PC3:    INC     RD              ; their end: the next line
        INC     RD
        LOAD    RC, PP
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        GHI     RB
        PHI     RA
        GLO     RB
        PLO     RA
        SEP     R4
        DW      NEXTE
        GHI     RA
        PHI     RB
        GLO     RA
        PLO     RB
        LBR     PC1
; a rule or NAME = value: a # comment off, the spaces at the end off
PMR:    LDN     RF
        LBZ     PMR2
        XRI     '#'
        LBZ     PMR1
        INC     RF
        LBR     PMR
PMR1:   LDI     0
        STR     RF
PMR2:   GLO     RF              ; (LBUF is page-aligned: low byte 0 = its start)
        LBZ     PMR3
        DEC     RF
        LDN     RF
        XRI     ' '
        LBZ     PMR2A
        LDN     RF
        XRI     09H
        LBNZ    PMR3
PMR2A:  LDI     0
        STR     RF
        LBR     PMR2
PMR3:   LOAD    RF, LBUF        ; the first ':' or '='
PMR4:   LDN     RF
        LBZ     PMR4Z
        XRI     ':'
        LBZ     PMCOL
        XRI     07H             ; (':' ^ '=')
        LBZ     PMEQ
        INC     RF
        LBR     PMR4
PMR4Z:  LOAD    RF, LBUF        ; nothing left: it was all comment
        LDN     RF
        LBZ     PM1
        LBR     ENOTR
PMCOL:  INC     RF
        LDN     RF
        DEC     RF
        XRI     '='
        LBNZ    PRULE
        GHI     RF              ; NAME := value: the name ends at ':', the value after "="
        PHI     RA
        GLO     RF
        PLO     RA
        INC     RF
        INC     RF
        LDI     0
        LBR     PE3
PMEQ:   GHI     RF              ; NAME = value (+= ?=)
        PHI     RA
        GLO     RF
        PLO     RA
        INC     RF
        GLO     RA
        LBZ     ENONAM          ; '=' first
        DEC     RA
        LDN     RA
        XRI     '+'
        LBNZ    PE1
        LDI     1
        LBR     PE3
PE1:    LDN     RA
        XRI     '?'
        LBNZ    PE2
        LDI     2
        LBR     PE3
PE2:    INC     RA
        LDI     0
PE3:    PLO     RE              ; D = 0 =, 1 +=, 2 ?= ; RA = the name's end, RF = the value
        LOAD    RD, OP
        GLO     RE
        STR     RD
        LDI     0               ; the name: its spaces off the end
        STR     RA
PE4:    GLO     RA
        LBZ     PE5
        DEC     RA
        LDN     RA
        XRI     ' '
        LBZ     PE4A
        LDN     RA
        XRI     09H
        LBNZ    PE5
PE4A:   LDI     0
        STR     RA
        LBR     PE4
PE5:    LOAD    RA, LBUF        ; the name -> VNM (31 at most, no spaces)
        LOAD    RD, VNM
        LDI     31
        PLO     RC
        LDN     RA
        LBZ     ENONAM
PE6:    LDA     RA
        LBZ     PE7
        STR     RD
        INC     RD
        XRI     ' '
        LBZ     EVNAM
        XRI     29H             ; (' ' ^ Tab)
        LBZ     EVNAM
        DEC     RC
        GLO     RC
        LBZ     EVNAM
        LBR     PE6
PE7:    STR     RD
        SEP     R4              ; the value, its $(...) put in
        DW      SKIPW
        LOAD    RD, XMODE
        LDI     0
        STR     RD
        LOAD    RD, EXB
        SEP     R4
        DW      EXPAND
        LOAD    RA, VNM         ; (EXPAND used NBUF)
        LOAD    RD, NBUF
PE7A:   LDA     RA
        STR     RD
        INC     RD
        LBNZ    PE7A
        SEP     R4
        DW      VSETM
        LOAD    RD, CURS        ; the commands before were the last rule's
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LBR     PM1
; a rule: targets: names
PRULE:  LOAD    RD, XMODE
        LDI     0
        STR     RD
        LOAD    RF, LBUF
        LOAD    RD, EXB
        SEP     R4
        DW      EXPAND
        LOAD    RF, EXB         ; upper case
PR0:    LDN     RF
        LBZ     PR0A
        SEP     R4
        DW      UPCH
        STR     RF
        INC     RF
        LBR     PR0
PR0A:   LOAD    RF, EXB
PR1:    LDN     RF
        LBZ     ENOTR
        XRI     ':'
        LBZ     PR2
        INC     RF
        LBR     PR1
PR2:    LDI     0
        STR     RF
        INC     RF
        LOAD    RD, PRQ
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, RTE         ; this rule's entries start at the end
        LOAD    RC, CURS
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, TP
        LDI     HIGH(EXB)
        STR     RD
        INC     RD
        LDI     LOW(EXB)
        STR     RD
        LOAD    RD, NTG
        LDI     0
        STR     RD
PR3:    LOAD    RD, TP          ; the next target
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      SKIPW
        LDN     RF
        LBZ     PR9
        LOAD    RD, NBUF
        LDI     63
        PLO     RC
PR4:    LDN     RF
        LBZ     PR5
        XRI     ' '
        LBZ     PR5
        XRI     29H
        LBZ     PR5
        LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBZ     ETNAME
        LBR     PR4
PR5:    LDI     0
        STR     RD
        LOAD    RD, TP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, NTG
        LDI     1
        STR     RD
        LOAD    R8, NBUF        ; .PHONY may come more than once
        LOAD    R7, SPHONY
        SEP     R4
        DW      SEQ
        LBNF    PR6
        LOAD    RF, NBUF
        SEP     R4
        DW      FINDR
        LBNF    ETWICE
PR6:    LOAD    RD, RTE         ; the new entry
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDI     9
        PLO     RC
PR6A:   LDI     0
        STR     RA
        INC     RA
        DEC     RC
        GLO     RC
        LBNZ    PR6A
        LOAD    R7, NBUF
PR7:    LDA     R7
        STR     RA
        INC     RA
        LBNZ    PR7
        LOAD    RD, PRQ         ; its names, each 0-ended
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
PR8:    SEP     R4
        DW      SKIPW
        LDN     RF
        LBZ     PR8E
PR8A:   LDN     RF
        LBZ     PR8B
        XRI     ' '
        LBZ     PR8B
        XRI     29H
        LBZ     PR8B
        LDA     RF
        STR     RA
        INC     RA
        LBR     PR8A
PR8B:   LDI     0
        STR     RA
        INC     RA
        LBR     PR8
PR8E:   LDI     0
        STR     RA
        INC     RA
        GHI     RA
        SMI     HIGH(RTTOP)
        LBDF    ERFULL
        LOAD    RD, RTE
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LBR     PR3
PR9:    LOAD    RD, NTG
        LDN     RD
        LBZ     ENOTGT
        LBR     PM1
; ---- all read: the targets asked for (none: the first rule's that is not .something)
PMEND:  LOAD    RD, LINENO      ; (mistakes from here on have no line)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, GOALS
        LDN     RD
        LBNZ    GO1
        LOAD    RA, RT
PE8:    LOAD    RD, RTE
        LDA     RD
        STR     R2
        GHI     RA
        XOR
        LBNZ    PE9
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBZ     ENOMFR
PE9:    GLO     RA
        ADI     9
        PLO     RD
        GHI     RA
        ADCI    0
        PHI     RD
        LDN     RD
        XRI     '.'
        LBNZ    PE10
        SEP     R4
        DW      NEXTE
        LBR     PE8
PE10:   LOAD    RA, GOALS
PE11:   LDA     RD
        STR     RA
        INC     RA
        LBNZ    PE11
        STR     RA
GO1:    LOAD    RD, GP
        LDI     HIGH(GOALS)
        STR     RD
        INC     RD
        LDI     LOW(GOALS)
        STR     RD
GO2:    LOAD    RD, GP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDN     RF
        LBZ     GO9
        LOAD    RD, NCMD
        LDN     RD
        PLO     R9
        LOAD    RD, NC0
        GLO     R9
        STR     RD
        SEP     R4
        DW      EVAL
        LOAD    RD, NCMD        ; nothing to do for it?
        LDN     RD
        STR     R2
        LOAD    RD, NC0
        LDN     RD
        XOR
        LBNZ    GO4
        SEP     R4
        DW      K_PIN
        DB      'MAKE: ',0
        LOAD    RD, REX
        LDN     RD
        LBZ     GO3
        SEP     R4
        DW      GPNAM
        SEP     R4
        DW      K_PIN
        DB      ' is up to date.',0DH,0AH,0
        LBR     GO4
GO3:    SEP     R4
        DW      K_PIN
        DB      'nothing to do for ',0
        SEP     R4
        DW      GPNAM
        SEP     R4
        DW      K_PIN
        DB      '.',0DH,0AH,0
GO4:    LOAD    RD, GP          ; the next
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
GO5:    LDA     RF
        LBNZ    GO5
        LOAD    RD, GP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LBR     GO2
GO9:    LOAD    RD, NFLAG       ; -n: shown, that is all
        LDN     RD
        LBNZ    DONE
        LOAD    RD, NCMD
        LDN     RD
        LBZ     DONE
        LOAD    RF, SCRN        ; the script -> /_MAKE.SH
        LOAD    RD, N11
        SEP     R4
        DW      K_PARSE
        LBDF    ESAVE
        LOAD    RD, SBE
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        SMI     HIGH(SB)
        PHI     RC
        LOAD    RA, SB
        LOAD    RD, N11
        SEP     R4
        DW      K_SAVER
        LBDF    ESAVE
        LOAD    RF, SCRN        ; hidden (DIR -h shows it)
        LOAD    RD, N11
        SEP     R4
        DW      K_PARSE
        LBDF    ESAVE
        LOAD    RD, N11
        SEP     R4
        DW      KS_FINDN
        LBDF    ESAVE
        GLO     RF
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDN     RF
        ORI     02H
        STR     RF
        LOAD    RD, KS_DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    ESAVE
        LOAD    RD, KS_CWD      ; run it, from this folder
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RF, RUNL
        LOAD    RD, KS_LINE
GO10:   LDA     RF
        STR     RD
        INC     RD
        LBNZ    GO10
        LBR     K_EXEC
DONE:   SEP     R5
GPNAM:  LOAD    RD, GP          ; the target asked for, shown
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LBR     PSTR

; ---- EVAL: RF -> a name (0-ended, where it stays): looked at, its names first; its commands to the script if it
;      is to be remade. -> RREB = 1: it is being remade (or is .PHONY); REX = 1: it is there; RTM = its time.
EVAL:   LOAD    RD, DEPTH
        LDN     RD
        ADI     1
        STR     RD
        SMI     21
        LBDF    ETDEEP
        LOAD    RD, CFL         ; a new frame
        LDN     RD
        ADI     FSZ
        STR     RD
        PLO     RB
        LDI     HIGH(FRAMES)
        PHI     RB
        GHI     RF
        STR     RB
        INC     RB
        GLO     RF
        STR     RB
        INC     RB
        LDI     10
        PLO     RC
EV0:    LDI     0
        STR     RB
        INC     RB
        DEC     RC
        GLO     RC
        LBNZ    EV0
        SEP     R4              ; its rule
        DW      FINDR
        LBDF    EVNR
        SEP     R4
        DW      GETF
        INC     RB
        INC     RB
        GHI     RA
        STR     RB
        INC     RB
        GLO     RA
        STR     RB
        LDN     RA
        ANI     1
        LBNZ    EVDONE          ; looked at already
        LDN     RA
        ANI     2
        LBNZ    ECIRC
        LDN     RA
        ORI     2
        STR     RA
        SEP     R4              ; its time
        DW      GETF
        LDA     RB
        PHI     RF
        LDN     RB
        PLO     RF
        SEP     R4
        DW      FTIME
        LBDF    EV2             ; not there: to be remade
        SEP     R4
        DW      GETF
        GLO     RB
        ADI     F_TM
        PLO     RB
        LOAD    RD, FTM
        LDI     4
        PLO     RC
EV1:    LDA     RD
        STR     RB
        INC     RB
        DEC     RC
        GLO     RC
        LBNZ    EV1
        LDI     1               ; (RB at F_EX)
        STR     RB
        SEP     R4              ; .PHONY: never there
        DW      GETF
        LDA     RB
        PHI     RF
        LDN     RB
        PLO     RF
        SEP     R4
        DW      ISPH
        LBDF    EV2
        SEP     R4
        DW      GETF
        GLO     RB
        ADI     F_EX
        PLO     RB
        LDI     0
        STR     RB
EV2:    SEP     R4              ; not there: to be remade
        DW      GETF
        GLO     RB
        ADI     F_EX
        PLO     RB
        LDA     RB
        LBNZ    EV3
        LDI     1
        STR     RB
EV3:    SEP     R4              ; its names: F_PP = the first, past the target
        DW      GETF
        INC     RB
        INC     RB
        LDA     RB
        PHI     RA
        LDA     RB
        PLO     RA
        GLO     RA
        ADI     9
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
EV3A:   LDA     RA
        LBNZ    EV3A
        GHI     RA
        STR     RB
        INC     RB
        GLO     RA
        STR     RB
EV4:    SEP     R4              ; the next name
        DW      GETF
        GLO     RB
        ADI     F_PP
        PLO     RB
        LDA     RB
        PHI     RF
        LDN     RB
        PLO     RF
        LDN     RF
        LBZ     EV8
        SEP     R4
        DW      EVAL
        SEP     R4
        DW      GETF
        LOAD    RD, RREB        ; it is being remade: so is this
        LDN     RD
        LBNZ    EV6
        LOAD    RD, REX
        LDN     RD
        LBZ     EV7
        GLO     RB              ; this one not there: being remade already
        ADI     F_EX
        PLO     RB
        LDN     RB
        LBZ     EV7
        GLO     RB
        SMI     F_EX - F_TM
        PLO     RB
        LOAD    RD, RTM         ; newer than this?
        LDI     4
        PLO     RC
EV5:    LDA     RD
        STR     R2
        LDA     RB
        SD                      ; its - this
        LBNZ    EV5B
        DEC     RC
        GLO     RC
        LBNZ    EV5
        LBR     EV7             ; the same: not newer
EV5B:   LBNF    EV7
EV6:    SEP     R4
        DW      GETF
        GLO     RB
        ADI     F_OUT
        PLO     RB
        LDI     1
        STR     RB
EV7:    SEP     R4              ; F_PP past this name
        DW      GETF
        GLO     RB
        ADI     F_PP
        PLO     RB
        LDA     RB
        PHI     RA
        LDN     RB
        PLO     RA
EV7A:   LDA     RA
        LBNZ    EV7A
        DEC     RB
        GHI     RA
        STR     RB
        INC     RB
        GLO     RA
        STR     RB
        LBR     EV4
EV8:    SEP     R4              ; to be remade: its commands
        DW      GETF
        GLO     RB
        ADI     F_OUT
        PLO     RB
        LDN     RB
        LBZ     EV9
        SEP     R4
        DW      GETF
        INC     RB
        INC     RB
        LDA     RB
        PHI     RF
        LDN     RB
        PLO     RF
        SEP     R4
        DW      EMIT
EV9:    SEP     R4              ; the entry: done, remade?, there?, its time
        DW      GETF
        INC     RB
        INC     RB
        LDA     RB
        PHI     RA
        LDA     RB
        PLO     RA
        INC     RB
        INC     RB
        INC     RA
        LDI     4
        PLO     RC
EV9A:   LDA     RB
        STR     RA
        INC     RA
        DEC     RC
        GLO     RC
        LBNZ    EV9A
        GLO     RA
        SMI     5
        PLO     RA
        GHI     RA
        SMBI    0
        PHI     RA
        LDA     RB              ; there: 8
        SHL
        SHL
        SHL
        STR     R2
        LDN     RB              ; remade: 4
        SHL
        SHL
        OR
        ORI     1
        STR     RA
EVDONE: SEP     R4              ; RA = the entry
        DW      RESE
        LBR     EVRET
EVNR:   SEP     R4              ; no rule: it must be there
        DW      GETF
        LDA     RB
        PHI     RF
        LDN     RB
        PLO     RF
        SEP     R4
        DW      FTIME
        LBDF    ENORULE
        LOAD    RD, RREB
        LDI     0
        STR     RD
        LOAD    RD, REX
        LDI     1
        STR     RD
        LOAD    RA, FTM
        LOAD    RD, RTM
        LDI     4
        PLO     RC
EVN1:   LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    EVN1
EVRET:  LOAD    RD, CFL
        LDN     RD
        SMI     FSZ
        STR     RD
        LOAD    RD, DEPTH
        LDN     RD
        SMI     1
        STR     RD
        SEP     R5
; RESE: RA -> an entry -> RREB, REX, RTM
RESE:   LOAD    RD, RREB
        LDA     RA
        PLO     RE
        SHR
        SHR
        ANI     1
        STR     RD
        LOAD    RD, REX
        GLO     RE
        SHR
        SHR
        SHR
        ANI     1
        STR     RD
        LOAD    RD, RTM
        LDI     4
        PLO     RC
RS1:    LDA     RA
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    RS1
        SEP     R5
; GETF: RB = the current frame
GETF:   LOAD    RD, CFL
        LDN     RD
        PLO     RB
        LDI     HIGH(FRAMES)
        PHI     RB
        SEP     R5

; ---- EMIT: RF -> a rule's entry: its commands, $(...) $@ $< $^ put in, to the script (-n: shown)
EMIT:   LOAD    RD, CURE
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GLO     RF
        ADI     5
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        GHI     RA
        LBZ     EMX             ; no commands
        LOAD    RD, EMEND
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
EM1:    LOAD    RD, EMEND       ; the end?
        LDA     RD
        STR     R2
        GHI     RA
        XOR
        LBNZ    EM1A
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBZ     EMX
EM1A:   SEP     R4
        DW      CPLINE
        LOAD    RD, EMP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RF, LBUF        ; a command line? (a comment line between: not)
        LDN     RF
        XRI     09H
        LBZ     EM2
        LDN     RF
        XRI     ' '
        LBNZ    EMNX
EM2:    SEP     R4
        DW      SKIPW
        LDN     RF
        LBZ     EMNX
        XRI     '#'
        LBZ     EMNX
        LOAD    RD, XMODE
        LDI     1
        STR     RD
        LOAD    RD, EXB
        SEP     R4
        DW      EXPAND
        LOAD    RD, SIL
        LDI     0
        STR     RD
        INC     RD              ; (IGN)
        STR     RD
        LOAD    RF, EXB
EM3:    SEP     R4              ; @ - + in front
        DW      SKIPW
        LDN     RF
        XRI     '@'
        LBNZ    EM4
        LOAD    RD, SIL
        LDI     1
        STR     RD
        INC     RF
        LBR     EM3
EM4:    LDN     RF
        XRI     '-'
        LBNZ    EM5
        LOAD    RD, IGN
        LDI     1
        STR     RD
        INC     RF
        LBR     EM3
EM5:    LDN     RF
        XRI     '+'
        LBNZ    EM6
        INC     RF
        LBR     EM3
EM6:    LDN     RF
        LBZ     EMNX
        LOAD    RD, CMDP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, NCMD        ; (255 at most: only "any?" matters)
        LDN     RD
        ADI     1
        LBZ     EM6A
        STR     RD
EM6A:   LOAD    RD, NFLAG
        LDN     RD
        LBZ     EM7
        SEP     R4              ; -n: shown
        DW      PSTR
        SEP     R4
        DW      K_PCRLF
        LBR     EMNX
EM7:    LOAD    RD, SIL         ; echo 'command' first (unless @)
        LDN     RD
        LBNZ    EM9
        LDI     0               ; R9.0: 1 a ' in it, 2 a " or $
        PLO     R9
EM7A:   LDA     RF
        LBZ     EM7D
        XRI     27H
        LBNZ    EM7B
        GLO     R9
        ORI     1
        PLO     R9
        LBR     EM7A
EM7B:   XRI     05H             ; (27H ^ '"')
        LBZ     EM7C
        XRI     06H             ; ('"' ^ '$')
        LBNZ    EM7A
EM7C:   GLO     R9
        ORI     2
        PLO     R9
        LBR     EM7A
EM7D:   GLO     R9
        ANI     1
        LBNZ    EM8
        LDI     27H             ; echo '...'
        LBR     EM8A
EM8:    GLO     R9
        ANI     2
        LBNZ    EM9             ; ' and " or $: not shown
        LDI     22H             ; echo "..."
EM8A:   PLO     R9
        LOAD    RD, QCH
        GLO     R9
        STR     RD
        LOAD    RF, SECHO
        SEP     R4
        DW      WS
        LOAD    RD, QCH
        LDN     RD
        SEP     R4
        DW      WC
        SEP     R4
        DW      WCMD
        LOAD    RD, QCH
        LDN     RD
        SEP     R4
        DW      WC
        LDI     0AH
        SEP     R4
        DW      WC
EM9:    SEP     R4              ; the command
        DW      WCMD
        LDI     0AH
        SEP     R4
        DW      WC
        LOAD    RD, IGN         ; then: stopped if it failed (unless -)
        LDN     RD
        LBNZ    EMNX
        LOAD    RF, SCHK
        SEP     R4
        DW      WS
        LOAD    RD, CURE
        LDA     RD
        PHI     RF
        LDN     RD
        ADI     9
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        SEP     R4
        DW      WS
        LDI     0AH
        SEP     R4
        DW      WC
EMNX:   LOAD    RD, EMP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LBR     EM1
EMX:    SEP     R5
WCMD:   LOAD    RD, CMDP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
; WS: RF -> 0-ended text, to the script
WS:     LDA     RF
        LBZ     WS9
        SEP     R4
        DW      WC
        LBR     WS
WS9:    SEP     R5
; WC: D to the script (RF kept)
WC:     PLO     RE
        LOAD    RD, SBE
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RE
        STR     RC
        INC     RC
        GHI     RC
        XRI     HIGH(SBTOP)
        LBZ     EFULL
        GLO     RC
        STR     RD
        DEC     RD
        GHI     RC
        STR     RD
        SEP     R5

; ---- EXPAND: RF -> a line (0-ended) -> RD, $(NAME) ${NAME} $$ put in, and with XMODE = 1 $@ $< $^ (the rule at
;      CURE); with XMODE = 0 these are left as they are. RF, RD end past it. Uses R9.0, RA, RB, R7, R8.
EXPAND: LDI     254
        PLO     R9
XP1:    LDA     RF
        LBZ     XP9
        XRI     '$'
        LBZ     XP2
        XRI     '$'
        SEP     R4
        DW      XPUT
        LBR     XP1
XP9:    STR     RD
        SEP     R5
XP2:    LDN     RF
        XRI     '$'
        LBNZ    XP3
        INC     RF
        LDI     '$'
        SEP     R4
        DW      XPUT
        LBR     XP1
XP3:    LDN     RF
        XRI     '('
        LBZ     XPV
        LDN     RF
        XRI     '{'
        LBZ     XPV
        LDN     RF
        SEP     R4
        DW      ISAUTO
        LBDF    XP4
        LOAD    RA, XMODE
        LDN     RA
        LBZ     XP4
        LDA     RF
        SEP     R4
        DW      XAUTO
        LBR     XP1
XP4:    LDI     '$'             ; as it is (the next character copied as any other)
        SEP     R4
        DW      XPUT
        LBR     XP1
XPV:    LDA     RF              ; $( or ${: the name to ) or }
        XRI     '('
        LBZ     XPV0
        LDI     '}'
        LSKP
XPV0:   LDI     ')'
        PHI     R7
        LDI     32
        PLO     R7
        LOAD    RA, NBUF
XPN1:   LDN     RF
        LBZ     EUNCL
        STR     R2
        GHI     R7
        XOR
        LBZ     XPN2
        LDA     RF
        STR     RA
        INC     RA
        DEC     R7
        GLO     R7
        LBZ     EUNCL
        LBR     XPN1
XPN2:   INC     RF
        LDI     0
        STR     RA
        LOAD    RA, XMODE       ; $(@) ${<} ...: as $@ $<
        LDN     RA
        LBZ     XPN3
        LOAD    RA, NBUF + 1
        LDN     RA
        LBNZ    XPN3
        DEC     RA
        LDN     RA
        SEP     R4
        DW      ISAUTO
        LBDF    XPN3
        LDN     RA
        SEP     R4
        DW      XAUTO
        LBR     XP1
XPN3:   SEP     R4
        DW      VLOOK
        LBDF    XP1             ; not set: nothing
XPV2:   LDA     RB              ; its value (with XMODE = 1: its $@ $< $^ too)
        LBZ     XP1
        XRI     '$'
        LBNZ    XPV3
        LOAD    RA, XMODE
        LDN     RA
        LBZ     XPV4
        LDN     RB
        SEP     R4
        DW      ISAUTO
        LBDF    XPV4
        LDA     RB
        SEP     R4
        DW      XAUTO
        LBR     XPV2
XPV4:   LDI     '$'
        SEP     R4
        DW      XPUT
        LBR     XPV2
XPV3:   XRI     '$'
        SEP     R4
        DW      XPUT
        LBR     XPV2
XPUT:   STR     RD
        INC     RD
        DEC     R9
        GLO     R9
        LBZ     ELONG
        SEP     R5
ISAUTO: XRI     '@'             ; DF = 0: D is @ < or ^
        LBZ     IAY
        XRI     7CH             ; ('@' ^ '<')
        LBZ     IAY
        XRI     62H             ; ('<' ^ '^')
        LBZ     IAY
        LDI     1
        SHR
        SEP     R5
IAY:    LDI     0
        SHR
        SEP     R5
; XAUTO: D = @ < or ^ -> the rule at CURE's target, first name, all names
XAUTO:  PLO     RE
        LOAD    RA, CURE
        LDA     RA
        PHI     R8
        LDN     RA
        PLO     R8
        GLO     R8
        ADI     9
        PLO     RA
        GHI     R8
        ADCI    0
        PHI     RA
        GLO     RE
        XRI     '@'
        LBZ     XA1
XA2:    LDA     RA              ; past the target
        LBNZ    XA2
        GLO     RE
        XRI     '<'
        LBNZ    XA3
XA1:    LDA     RA              ; to its 0
        LBZ     XA9
        SEP     R4
        DW      XPUT
        LBR     XA1
XA3:    LDN     RA              ; all, a space between
        LBZ     XA9
XA3A:   LDA     RA
        LBZ     XA3B
        SEP     R4
        DW      XPUT
        LBR     XA3A
XA3B:   LDN     RA
        LBZ     XA9
        LDI     ' '
        SEP     R4
        DW      XPUT
        LBR     XA3A
XA9:    SEP     R5

; ---- the variables
; VLOOK: NBUF = a name -> DF = 0: RB -> its value (the last set), VFLG its flag; DF = 1: not set
VLOOK:  LOAD    RC, VFND        ; (RD kept: EXPAND's)
        LDI     0
        STR     RC
        LOAD    RA, VT
VL1:    LOAD    R8, VTE
        LDA     R8
        STR     R2
        GHI     RA
        XOR
        LBNZ    VL2
        LDN     R8
        STR     R2
        GLO     RA
        XOR
        LBZ     VL9
VL2:    LOAD    RC, TFLG        ; its flag
        LDA     RA
        STR     RC
        GHI     RA
        PHI     R8
        GLO     RA
        PLO     R8
        LOAD    R7, NBUF
        SEP     R4
        DW      SEQ
        LBDF    VL4
        LOAD    RC, VVAL        ; this one (a later one wins)
        GHI     R8
        STR     RC
        INC     RC
        GLO     R8
        STR     RC
        LOAD    RC, TFLG
        LDN     RC
        PLO     RE
        LOAD    RC, VFLG
        GLO     RE
        STR     RC
        LOAD    RC, VFND
        LDI     1
        STR     RC
VL4:    LDA     RA              ; past its name and value
        LBNZ    VL4
VL4A:   LDA     RA
        LBNZ    VL4A
        LBR     VL1
VL9:    LOAD    RC, VVAL
        LDA     RC
        PHI     RB
        LDN     RC
        PLO     RB
        LOAD    RC, VFND
        LDN     RC
        XRI     1               ; 1 -> DF = 0
        SHR
        SEP     R5
; VSETM: NBUF = VALUE in EXB, as OP says (0 =, 1 +=, 2 ?=); one set on the command line is kept
VSETM:  SEP     R4
        DW      VLOOK
        LBDF    VS5
        LOAD    RD, VFLG
        LDN     RD
        XRI     'C'
        LBZ     VSX
        LOAD    RD, OP
        LDN     RD
        XRI     2
        LBZ     VSX
        LDN     RD
        XRI     1
        LBNZ    VS5
        LOAD    RA, TMPV        ; +=: the old value, a space, the new
VS1:    LDA     RB
        LBZ     VS2
        STR     RA
        INC     RA
        LBR     VS1
VS2:    GLO     RA
        LBZ     VS3
        LOAD    R7, EXB
        LDN     R7
        LBZ     VS3
        LDI     ' '
        STR     RA
        INC     RA
VS3:    LOAD    R7, EXB
VS3A:   LDA     R7
        STR     RA
        INC     RA
        LBZ     VS4
        GLO     RA
        LBZ     ELONG
        LBR     VS3A
VS4:    LOAD    RF, TMPV
        LBR     VS6
VS5:    LOAD    RF, EXB
VS6:    LDI     'M'
        LBR     VADD
VSX:    SEP     R5
; VADD: NBUF = the value at RF, D = its flag
VADD:   PLO     RE
        LOAD    RD, VTE
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GLO     RE
        STR     RA
        INC     RA
        LOAD    R7, NBUF
VA1:    LDA     R7
        STR     RA
        INC     RA
        LBNZ    VA1
VA2:    LDA     RF
        STR     RA
        INC     RA
        LBNZ    VA2
        GHI     RA
        SMI     HIGH(VTTOP)
        LBDF    EVFULL
        LOAD    RD, VTE
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R5
; CLVAR: RF -> NAME=value typed (no spaces) -> set, kept over the MAKEFILE's; RF past it
CLVAR:  LOAD    RA, NBUF
        LDI     32
        PLO     R7
CV1:    LDA     RF
        XRI     '='
        LBZ     CV2
        XRI     '='
        STR     RA
        INC     RA
        DEC     R7
        GLO     R7
        LBZ     USE
        LBR     CV1
CV2:    LDI     0
        STR     RA
        LOAD    RA, NBUF
        LDN     RA
        LBZ     USE
        LOAD    RA, EXB
CV3:    LDN     RF
        LBZ     CV4
        XRI     ' '
        LBZ     CV4
        LDA     RF
        STR     RA
        INC     RA
        LBR     CV3
CV4:    LDI     0
        STR     RA
        LOAD    RD, ARGP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RF, EXB
        LDI     'C'
        SEP     R4
        DW      VADD
        LOAD    RD, ARGP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5

; ---- the rules
; FINDR: RF -> a name -> DF = 0: RA = its entry; DF = 1: none (RF kept)
FINDR:  LOAD    RA, RT
FR1:    LOAD    RD, RTE
        LDA     RD
        STR     R2
        GHI     RA
        XOR
        LBNZ    FR2
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBZ     FRNO
FR2:    GLO     RA
        ADI     9
        PLO     R8
        GHI     RA
        ADCI    0
        PHI     R8
        GHI     RF
        PHI     R7
        GLO     RF
        PLO     R7
        SEP     R4
        DW      SEQ
        LBNF    FR9
        SEP     R4
        DW      NEXTE
        LBR     FR1
FRNO:   LDI     1
        SHR
FR9:    SEP     R5
; NEXTE: RA -> an entry -> the next
NEXTE:  GLO     RA
        ADI     9
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
NE1:    LDA     RA
        LBNZ    NE1
NE2:    LDA     RA
        LBZ     NE9
NE3:    LDA     RA
        LBNZ    NE3
        LBR     NE2
NE9:    SEP     R5
; ISPH: RF -> a name: DF = 0 if a .PHONY rule names it
ISPH:   LOAD    RD, PHN
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RA, RT
IP1:    LOAD    RD, RTE
        LDA     RD
        STR     R2
        GHI     RA
        XOR
        LBNZ    IP2
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBZ     FRNO
IP2:    GLO     RA
        ADI     9
        PLO     R8
        GHI     RA
        ADCI    0
        PHI     R8
        LOAD    R7, SPHONY
        SEP     R4
        DW      SEQ
        LBDF    IP5
IP3:    LDN     R8              ; its names (R8 past ".PHONY")
        LBZ     IP5
        GHI     R8
        PHI     R9
        GLO     R8
        PLO     R9
        LOAD    RD, PHN
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      SEQ
        LBNF    FR9
        GHI     R9
        PHI     R8
        GLO     R9
        PLO     R8
IP4:    LDA     R8
        LBNZ    IP4
        LBR     IP3
IP5:    SEP     R4
        DW      NEXTE
        LBR     IP1
; SEQ: R8, R7 -> two 0-ended texts: DF = 0 the same (R8 then past its 0)
SEQ:    LDA     R7
        PLO     RE
        SEX     R8
        XOR
        SEX     R2
        INC     R8
        LBNZ    SQN
        GLO     RE
        LBNZ    SEQ
        SHR                     ; (D = 0: DF = 0)
        SEP     R5
SQN:    LDI     1
        SHR
        SEP     R5

; ---- FTIME: RF -> a name: DF = 0 it is there, FTM = its write date and time (high bytes first); DF = 1 not there
FTIME:  LOAD    RD, FTN
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, N11
        SEP     R4
        DW      K_PARSE
        LBNF    FT2
        XRI     2
        LBZ     FTNO            ; no such folder: not there
        XRI     1               ; (2 ^ 3) a folder: there, time 0
        LBZ     FTDIR
        LBR     EBADN
FT2:    LOAD    RD, N11
        LDI     11
        PLO     RC
FT2A:   LDA     RD
        XRI     '?'
        LBZ     EBADN
        DEC     RC
        GLO     RC
        LBNZ    FT2A
        LOAD    RD, N11
        SEP     R4
        DW      KS_FINDN
        LBDF    FTNO
        GLO     RF
        ADI     22
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, FTM + 3
        LDA     RF              ; the time (22-23), the date (24-25), little-endian
        STR     RD
        DEC     RD
        LDA     RF
        STR     RD
        DEC     RD
        LDA     RF
        STR     RD
        DEC     RD
        LDN     RF
        STR     RD
        LDI     0
        SHR
        SEP     R5
FTDIR:  LOAD    RD, FTM
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        SHR
        SEP     R5
FTNO:   LDI     1
        SHR
        SEP     R5

; ---- small things
; CPLINE: RA -> a line of the MAKEFILE -> LBUF (0-ended, CR left out), RA past its LF
CPLINE: LOAD    RD, LBUF
        LDI     254
        PLO     RC
CL1:    LDN     RA
        LBZ     CL9
        LDA     RA
        XRI     0AH
        LBZ     CL9
        XRI     07H             ; (LF ^ CR)
        LBZ     CL1
        XRI     0DH
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBZ     ETLONG
        LBR     CL1
CL9:    LDI     0
        STR     RD
        SEP     R5
; SKIPW: RF past spaces and Tabs
SKIPW:  LDN     RF
        XRI     ' '
        LBZ     SW1
        LDN     RF
        XRI     09H
        LBNZ    SW9
SW1:    INC     RF
        LBR     SKIPW
SW9:    SEP     R5
; UPCH: D in upper case
UPCH:   PLO     RE
        SMI     'a'
        LBNF    UC9
        SMI     26
        LBDF    UC9
        GLO     RE
        SMI     20H
        SEP     R5
UC9:    GLO     RE
        SEP     R5
; PSTR: RF -> 0-ended text, shown
PSTR:   LDA     RF
        LBZ     PS9
        SEP     R4
        DW      K_OUT
        LBR     PSTR
PS9:    SEP     R5

; ---- what went wrong (said, $? = 1, back to the prompt)
ERRL:   SEP     R4              ; "MAKE: line n: " (n = 0: no line)
        DW      K_PIN
        DB      'MAKE: ',0
        LOAD    RD, LINENO
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     RF
        STR     R2
        GLO     RF
        OR
        LBZ     EL9
        SEP     R4
        DW      K_PIN
        DB      'line ',0
        LOAD    RD, LINENO
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
EL9:    SEP     R5
ENOCMD: SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'a command with no rule before it.',0DH,0AH,0
        LBR     FAIL
ENOTR:  SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'not a rule (target: names) or NAME = value.',0DH,0AH,0
        LBR     FAIL
ENONAM: SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'no NAME before the =.',0DH,0AH,0
        LBR     FAIL
EVNAM:  SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'a NAME has no spaces (31 letters at most).',0DH,0AH,0
        LBR     FAIL
ETNAME: SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'a name too long.',0DH,0AH,0
        LBR     FAIL
ENOTGT: SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'a rule with no target.',0DH,0AH,0
        LBR     FAIL
ETWICE: SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'a second rule for ',0
        LOAD    RF, NBUF
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      ' (one rule each).',0DH,0AH,0
        LBR     FAIL
ETLONG: SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'too long (254 characters at most).',0DH,0AH,0
        LBR     FAIL
ELONG:  SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'too long with its $(...) put in (254 at most).',0DH,0AH,0
        LBR     FAIL
EUNCL:  SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'a $( with no ) (or ${ with no }).',0DH,0AH,0
        LBR     FAIL
EVFULL: SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'too many variables (768 bytes of them).',0DH,0AH,0
        LBR     FAIL
ERFULL: SEP     R4
        DW      ERRL
        SEP     R4
        DW      K_PIN
        DB      'too many rules (1.5 KB of them).',0DH,0AH,0
        LBR     FAIL
EFULL:  SEP     R4
        DW      K_PIN
        DB      'MAKE: too many commands (3 KB of them) - nothing run.',0DH,0AH,0
        LBR     FAIL
ENOMFR: SEP     R4
        DW      K_PIN
        DB      'MAKE: no rules in ',0
        LOAD    RF, MFN
        SEP     R4
        DW      PSTR
        LBR     EDOT
ENORULE: SEP    R4
        DW      K_PIN
        DB      'MAKE: no rule to make ',0
        SEP     R4
        DW      GETF
        LDA     RB
        PHI     RF
        LDN     RB
        PLO     RF
        SEP     R4
        DW      PSTR
        LOAD    RD, DEPTH       ; (needed by the one before)
        LDN     RD
        SMI     2
        LBNF    EDOT
        SEP     R4
        DW      K_PIN
        DB      ' (needed by ',0
        SEP     R4
        DW      GETF
        GLO     RB
        SMI     FSZ
        PLO     RB
        LDA     RB
        PHI     RF
        LDN     RB
        PLO     RF
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      ')',0
EDOT:   SEP     R4
        DW      K_PIN
        DB      '.',0DH,0AH,0
        LBR     FAIL
ECIRC:  SEP     R4
        DW      K_PIN
        DB      'MAKE: ',0
        SEP     R4
        DW      GETF
        LDA     RB
        PHI     RF
        LDN     RB
        PLO     RF
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      ' is made from itself (a circle of rules).',0DH,0AH,0
        LBR     FAIL
ETDEEP: SEP     R4
        DW      K_PIN
        DB      'MAKE: the rules go more than 20 deep.',0DH,0AH,0
        LBR     FAIL
EBADN:  SEP     R4
        DW      K_PIN
        DB      'MAKE: ',0
        LOAD    RD, FTN
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      ' is not a file name.',0DH,0AH,0
        LBR     FAIL
ESAVE:  SEP     R4
        DW      K_PIN
        DB      'MAKE: /_MAKE.SH could not be written (the card full?) - nothing run.',0DH,0AH,0
        LBR     FAIL
NOMF:   SEP     R4
        DW      K_PIN
        DB      'MAKE: no ',0
        LOAD    RF, MFN
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      ' here.',0DH,0AH,0
        LBR     FAIL
USE:    SEP     R4
        DW      K_PIN
        DB      'Usage: MAKE [-n] [-f file] [NAME=value] [targets]',0DH,0AH,0
FAIL:   LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5

DEFMF:  DB      'MAKEFILE',0
SPHONY: DB      '.PHONY',0
SCRN:   DB      '/_MAKE.SH',0
RUNL:   DB      'SH /_MAKE',0
SECHO:  DB      'echo ',0
SCHK:   DB      '[ $? -eq 0 ] || MAKEFAIL ',0
SHEAD:  DB      '# made by MAKE.PRG: what it runs',0AH
        DB      'MAKEFAIL() { echo "MAKE: $1 failed - stopped."; exit 1; }',0AH,0
PEND:
VARS:
NFLAG:  DS      1
ARGP:   DS      2
GOALE:  DS      2
GP:     DS      2
VTE:    DS      2
RTE:    DS      2
SBE:    DS      2
PP:     DS      2
LSTART: DS      2
LINENO: DS      2
CURS:   DS      2
OP:     DS      1
TP:     DS      2
PRQ:    DS      2
NTG:    DS      1
XMODE:  DS      1
CURE:   DS      2
EMEND:  DS      2
EMP:    DS      2
CMDP:   DS      2
SIL:    DS      1
IGN:    DS      1
QCH:    DS      1
NCMD:   DS      1
NC0:    DS      1
DEPTH:  DS      1
CFL:    DS      1
RREB:   DS      1
REX:    DS      1
RTM:    DS      4
FTM:    DS      4
FTN:    DS      2
PHN:    DS      2
VFND:   DS      1
VVAL:   DS      2
VFLG:   DS      1
TFLG:   DS      1
N11:    DS      11
VNM:    DS      32
MFN:    DS      64
VEND:
        END
