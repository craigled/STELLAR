; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; help.asm - HELP.PRG: HELP (every command, a line each, by group) / HELP name (that command's page).
;   The text is help.txt, made into HELP.HLP by build.py (HELP.PRG loads it at TEXT: from this folder, else the
;   root, else /BIN - where HELP.PRG itself is found): records of
;     1, heading, 0                                   - a group's name (the list only)
;     2, NAME[,OTHER...], 0, summary, 0, body, 0      - a command (lines end with LF)
;     0                                               - the end
;   A screen (22 lines) at a time: a key goes on, Q (Ctrl-C, Esc) stops.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

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
        LOAD    RD, LINES
        LDI     0
        STR     RD
        SEP     R4              ; the pages
        DW      LDTEXT
        LDN     RF
        LBZ     LIST
; ---- HELP name: the word, in upper case, -> WORD
        LOAD    RD, WORD
        LDI     12
        PLO     RB
HW1:    LDN     RF
        LBZ     HW2
        XRI     ' '
        LBZ     HW2
        LDA     RF
        PLO     RC
        SMI     'a'
        LBNF    HW1A
        GLO     RC
        SMI     'z'+1
        LBDF    HW1A
        GLO     RC
        SMI     20H
        PLO     RC
HW1A:   GLO     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    HW1
HW2:    LDI     0
        STR     RD
        LOAD    RA, TEXT        ; look for it
FS1:    LDN     RA
        LBZ     FSE
        XRI     1
        LBZ     FSH
        GHI     RA              ; a command: R8 = its record
        PHI     R8
        GLO     RA
        PLO     R8
        INC     RA
FSN:    LOAD    RC, WORD        ; one of its names (they end with ',' or 0)
FM1:    LDA     RA
        PLO     R9
        LBZ     FME
        XRI     ','
        LBZ     FME
        LDA     RC
        STR     R2
        GLO     R9
        XOR
        LBZ     FM1
FMS:    LDA     RA              ; not this name: past it
        LBZ     FNX
        XRI     ','
        LBNZ    FMS
        LBR     FSN
FME:    LDN     RC              ; the name ended: did the word end too?
        LBNZ    FME2
        GLO     R9
        LBZ     SHOW
FMK:    LDA     RA              ; (past the other names)
        LBNZ    FMK
        LBR     SHOW
FME2:   GLO     R9
        LBNZ    FSN
FNX:    SEP     R4              ; not this command: past its summary and body
        DW      SKIPS
        SEP     R4
        DW      SKIPS
        LBR     FS1
FSH:    INC     RA              ; a heading: past it
        SEP     R4
        DW      SKIPS
        LBR     FS1
FSE:    SEP     R4              ; the end of HELP.HLP: on with HELP2.HLP (RA = TEXT again)
        DW      NXPART
        LBNF    FS1
NOHELP: SEP     R4
        DW      K_PIN
        DB      'There is no help for ',0
        LOAD    RA, WORD
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      '. HELP alone lists the commands.',0DH,0AH,0
        SEP     R5
; ---- one command: NAME, OTHER - summary, then its page
SHOW:   GHI     RA              ; R7 = the summary
        PHI     R7
        GLO     RA
        PLO     R7
        GHI     R8              ; its names, ', ' between them
        PHI     RA
        GLO     R8
        PLO     RA
        INC     RA
SH1:    LDA     RA
        LBZ     SH2
        XRI     ','
        LBZ     SH1C
        XRI     ','
        SEP     R4
        DW      F_TYPE
        LBR     SH1
SH1C:   LDI     ','
        SEP     R4
        DW      F_TYPE
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LBR     SH1
SH2:    GHI     R7
        PHI     RA
        GLO     R7
        PLO     RA
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     '-'
        SEP     R4
        DW      F_TYPE
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        SEP     R4              ; the summary
        DW      PSTR
        SEP     R4
        DW      NEWLN
        LDN     RA              ; the page, if it has one
        LBZ     SH9
        SEP     R4
        DW      NEWLN
        SEP     R4
        DW      PSTR
SH9:    SEP     R5
; ---- the list
LIST:   LOAD    RA, TITLE
        SEP     R4
        DW      PSTR
        LOAD    RA, TEXT
LI1:    LDN     RA
        LBZ     LIE
        XRI     1
        LBZ     LIH
        INC     RA              ; a command: two spaces, its names (padded to 12), its summary
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     0
        PLO     RB
LI2:    LDA     RA
        LBZ     LI3
        XRI     ','
        LBNZ    LI2A
        LDI     ' '
        LSKP
LI2A:   XRI     ','
        SEP     R4
        DW      F_TYPE
        INC     RB
        LBR     LI2
LI3:    GLO     RB
        SMI     12
        LBDF    LI4
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        INC     RB
        LBR     LI3
LI4:    SEP     R4              ; the summary
        DW      PSTR
        SEP     R4
        DW      NEWLN
        SEP     R4              ; past the page
        DW      SKIPS
        LBR     LI1
LIH:    SEP     R4              ; a heading: a blank line, then it
        DW      NEWLN
        INC     RA
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      NEWLN
        LBR     LI1
LI9:    SEP     R5
LIE:    SEP     R4              ; the end of HELP.HLP: on with HELP2.HLP (RA = TEXT again)
        DW      NXPART
        LBNF    LI1
        LBR     LI9

; PSTR: the text at RA (LF: a new line) up to its 0; RA ends past the 0.  SKIPS: RA past a 0-ended text.
PSTR:   LDA     RA
        LBZ     PS9
        XRI     0AH
        LBZ     PSN
        XRI     0AH
        SEP     R4
        DW      F_TYPE
        LBR     PSTR
PSN:    SEP     R4
        DW      NEWLN
        LBR     PSTR
PS9:    SEP     R5
SKIPS:  LDA     RA
        LBNZ    SKIPS
        SEP     R5
; NEWLN: CR LF; after 22 lines, wait for a key (Q, Ctrl-C or Esc: back to the prompt). RA kept.
NEWLN:  LDI     0DH
        SEP     R4
        DW      F_TYPE
        LDI     0AH
        SEP     R4
        DW      F_TYPE
        LOAD    RD, K_RDIR      ; the output in a file: no pages
        LDN     RD
        LBNZ    NL9
        LOAD    RD, LINES
        LDN     RD
        ADI     1
        STR     RD
        XRI     22
        LBNZ    NL9
        STR     RD
        GHI     RA
        STXD
        GLO     RA
        STXD
        SEP     R4
        DW      K_PIN
        DB      '-- more: a key goes on, Q stops --',0
        SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      K_PIN
        DB      0DH,'                                  ',0DH,0
        IRX
        LDXA
        PLO     RA
        LDX
        PHI     RA
        GLO     RB
        ANI     0DFH
        XRI     'Q'
        LBZ     K_MAIN
        GLO     RB
        XRI     03H
        LBZ     K_MAIN
        GLO     RB
        XRI     1BH
        LBZ     K_MAIN
NL9:    SEP     R5

; ---- LDTEXT: HELP.HLP -> TEXT (as HELP.PRG is found: here, else the root, else /BIN); not there: said, back to the
;      prompt. RF kept. The list and the search go on with HELP2.HLP (NXPART) when they reach HELP.HLP's end -
;      one file in memory at a time (together they no longer fit below the kernel's buffers).
LDTEXT: LOAD    RD, ARGS
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, PART
        LDI     1
        STR     RD
        LOAD    RF, DATN
        SEP     R4
        DW      LDONE
        LBDF    LTNO
        LOAD    RD, ARGS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5
LTNO:   SEP     R4
        DW      K_PIN
        DB      'HELP.HLP (the pages) is not on the card, or could not be read.',0DH,0AH,0
        LBR     K_MAIN
; NXPART: a part's end reached - the next (HELP2.HLP, then HELP3.HLP) into TEXT, RA = TEXT, DF = 0; DF = 1: there
;         is no more (HELP3.HLP's end, or the next is not there). PART: the part in TEXT (1, 2, 3)
NXPART: LOAD    RD, PART
        LDN     RD
        XRI     3
        LBZ     NXP9
        XRI     3
        ADI     1
        STR     RD
        ADI     '0'             ; HELP2 / HELP3
        STR     R2
        LOAD    RF, DAT2N+4
        LDN     R2
        STR     RF
        LOAD    RF, DAT2N
        SEP     R4
        DW      LDONE
        LBDF    NXP9
        LOAD    RA, TEXT
        LDI     0
        SHR
        SEP     R5
NXP9:   LDI     1
        SHR
        SEP     R5
; LDONE: the file named at RF (11 bytes) -> TEXT on; DF = 1: not there, or it could not be read, or too big
LDONE:  LOAD    RD, LPTR
        LDI     HIGH(TEXT)
        STR     RD
        INC     RD
        LDI     LOW(TEXT)
        STR     RD
        LOAD    RD, DNP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, KS_CWD      ; here ...
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R4
        DW      DNFIND
        LBNF    LD2
        LOAD    RD, KS_WDIR     ; ... the root ...
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      DNFIND
        LBNF    LD2
        SEP     R4              ; ... /BIN
        DW      KS_TOBIN
        LBDF    LD9
        SEP     R4
        DW      DNFIND
        LBDF    LD9
LD2:    SEP     R4
        DW      KS_FOPEN
LD3:    SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    LD8
        LOAD    RF, KS_DATBUF
        LOAD    RD, LPTR
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
LD4:    GHI     RC
        LBNZ    LD5
        GLO     RC
        LBZ     LD6
LD5:    GHI     RA              ; (not past $6BFF: the kernel's buffers)
        XRI     HIGH(PTOP)
        LBZ     LD9
        LDA     RF
        STR     RA
        INC     RA
        DEC     RC
        LBR     LD4
LD6:    LOAD    RD, LPTR
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LBR     LD3
LD8:    XRI     2               ; D = 2: the card failed
        LBZ     LD9
        LOAD    RD, LPTR        ; LPTR back to the 0 at its end
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        DEC     RA
        GLO     RA
        STR     RD
        DEC     RD
        GHI     RA
        STR     RD
        LDI     0
        SHR
        SEP     R5
LD9:    LDI     1
        SHR
        SEP     R5
DNFIND: LOAD    RD, DNP         ; FINDN of the name at DNP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      KS_FINDN
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
DATN:   DB      'HELP    HLP'
DAT2N:  DB      'HELP2   HLP'    ; (its digit set by NXPART)
TITLE:  DB      'LTOS 0.5 - the commands.  HELP name tells more about one.',0AH,0
PEND:
LINES:  DS      1
WORD:   DS      13
ARGS:   DS      2
LPTR:   DS      2
DNP:    DS      2
PART:   DS      1
TEXT:                           ; HELP.HLP goes here
        END
