; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; eroff.asm - EROFF.PRG: EROFF name - a small nroff: the file's text filled and justified into pages.
; What it does, exactly: eroff_model.py (verify_eroff.py holds this program to it). In short - requests are
; lines that start with '.': .br .sp N .bp .ne N .fi .nf .ad .na .ce N .in N .ti N .ll N .pl N .pp
; .he 'l'c'r' .fo 'l'c'r' (% the page number) .\" (a comment); +N / -N for .in .ti .ll; a blank line is
; a break and a blank line; a line starting with spaces starts that far in. A page: the header, 2 blank lines,
; PL - 6 lines, 2 blank lines, the footer, a form feed (into a file only - on the screen the pages just follow
; one another). EROFF DOC.RF > DOC.TXT keeps it (elfprint -p prints it).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

MAXLL   EQU     132
NOTI    EQU     0FFH            ; TI: no temporary indent

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
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        SEP     R4
        DW      KS_NAMEARG      ; (not there, a folder ...: the kernel says so, back to the prompt)
        SEP     R4
        DW      KS_FOPEN
        LOAD    RF, INIT        ; the state, from INIT (a rerun starts clean)
        LOAD    RD, VARS
        LDI     VARSN
        PLO     RC
ST1:    LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST1
        LOAD    RD, JMPV
        LDI     0C0H            ; (LBR)
        STR     RD
        LOAD    RD, HE          ; no header, no footer
        LDI     0
        STR     RD
        LOAD    RD, FO
        LDI     0
        STR     RD
; ---- the file, a sector at a time: each line (CR dropped, a tab a space, 255 characters kept) to FEED
RD1:    SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    REOF
        LOAD    RF, KS_DATBUF
RD2:    GHI     RC
        LBNZ    RD3
        GLO     RC
        LBZ     RD1
RD3:    DEC     RC
        LDA     RF
        XRI     0DH
        LBZ     RD2             ; CR: dropped
        XRI     0DH XOR 0AH
        LBZ     RDLF
        XRI     0AH XOR 09H
        LBNZ    RD4
        LDI     ' ' XOR 09H     ; a tab: a space
RD4:    XRI     09H
        PLO     RE              ; RE.0 = the character
        LOAD    RD, LLEN
        LDN     RD
        XRI     0FFH
        LBZ     RD2             ; 255 kept: the rest dropped
        XRI     0FFH
        ADI     LOW(LINE)
        PLO     RB
        LDI     HIGH(LINE)
        ADCI    0
        PHI     RB
        GLO     RE
        STR     RB
        LDN     RD
        ADI     1
        STR     RD
        LBR     RD2
RDLF:   SEP     R4              ; a line: FEED it (RF, RC kept around it)
        DW      SAVRC
        SEP     R4
        DW      FEED
        SEP     R4
        DW      GETRC
        LBR     RD2
REOF:   LOAD    RD, LLEN        ; the end: a last line with no LF, if any
        LDN     RD
        LBZ     RE1
        SEP     R4
        DW      FEED
RE1:    SEP     R4
        DW      BRK
        LOAD    RD, KEEPING     ; a display still kept: out
        LDN     RD
        LBZ     RE2
        SEP     R4
        DW      FLUSH
RE2:
        SEP     R4
        DW      PLON            ; pages, and a page started: its end (no form feed)
        LBZ     RE9
        SEP     R4
        DW      LNOV
        LBZ     RE9
        LDI     1
        SEP     R4
        DW      ENDPG
RE9:    SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'EROFF name - the text formatted into pages (> NAME keeps it). HELP EROFF: the requests.',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
SAVRC:  LOAD    RD, RPTR
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
        SEP     R5
GETRC:  LOAD    RD, RPTR
        LDA     RD
        PHI     RF
        LDA     RD
        PLO     RF
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R5

; ---- small helpers: D = a variable (Z set as D)
; (they use R9 only. NB: every SEP R4 call uses RE.0 and the stack byte at R2 - nothing is kept in either
; across a call. RE.1 is never touched: it is the Elf2K BIOS's console setting, and F_TYPE to the screen
; goes wrong if it changes - HW 2026-10-30)
PLON:   LOAD    R9, PL          ; D = PL (0: no pages)
        LDN     R9
        SEP     R5
LNOV:   LOAD    R9, LNO
        LDN     R9
        SEP     R5
BODY:   LOAD    R9, PL          ; D = PL - 6, the text lines a page
        LDN     R9
        SMI     6
        SEP     R5
LLV:    LOAD    R9, LL
        LDN     R9
        SEP     R5
CURIND: LOAD    R9, TI          ; D = the indent now: TI if set, else IN
        LDN     R9
        XRI     NOTI
        LBZ     CI1
        LDN     R9
        SEP     R5
CI1:    LOAD    R9, PIND        ; IN + .ip's indent, at most LL - 1
        LDN     R9
        STR     R2
        LOAD    R9, IND
        LDN     R9
        ADD
        LBDF    CI2
        PLO     R8
        LOAD    R9, LL
        LDN     R9
        SMI     1
        STR     R2
        GLO     R8
        SD                      ; (LL - 1) - it
        LBNF    CI2
        GLO     R8
        SEP     R5
CI2:    LOAD    R9, LL
        LDN     R9
        SMI     1
        SEP     R5
SPCS:   PLO     RE              ; D spaces at RF (RF past them)
SPC1:   GLO     RE
        LBZ     SPC9
        LDI     ' '
        STR     RF
        INC     RF
        DEC     RE
        LBR     SPC1
SPC9:   SEP     R5

; ==== FEED: the line at LINE (LLEN characters) - a request, a blank line, or text; then LLEN = 0
FEED:   LOAD    RD, LLEN
        LDN     RD
        ADI     LOW(LINE)
        PLO     RF
        LDI     HIGH(LINE)
        ADCI    0
        PHI     RF
        LDI     0
        STR     RF              ; 0-ended
        STR     RD              ; (LLEN = 0 for the next line)
        LOAD    RF, LINE
        LDN     RF
        XRI     '.'
        LBZ     REQ
        SEP     R4              ; text: \fB \fI \fR \fP -> their bytes
        DW      CONV
        LOAD    RF, LINE
FD1:    LDA     RF              ; all spaces (or nothing)?
        LBZ     FDBL
        XRI     ' '
        LBZ     FD1
        LBR     TEXT
FDBL:   SEP     R4              ; a blank line: a break and a blank line
        DW      BRK
        LOAD    RD, SPN
        LDI     0
        STR     RD
        INC     RD
        LDI     1
        STR     RD
        LBR     SPACE

; ==== the requests
REQ:    INC     RF              ; RF -> the name
        LDA     RF
        LBZ     RQ9
        PHI     RA
        XRI     5CH             ; a backslash
        LBNZ    RQ1
        LDN     RF
        XRI     '"'
        LBZ     RQ9             ; .\" a comment
RQ1:    LDA     RF
        LBNZ    RQ1A            ; one letter (.B): as 'B ', the argument empty
        DEC     RF
        LDI     ' '
RQ1A:   ORI     20H
        PLO     RA              ; RA = the name, lower case
        GHI     RA
        ORI     20H
        PHI     RA
        LOAD    RD, ARGP        ; RF -> the argument (after the 2 letters)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, RQTAB
RQ2:    LDA     RD              ; the table: 2 letters, then where
        LBZ     RQ9             ; not found: ignored
        STR     R2
        GHI     RA
        XOR
        LBNZ    RQ3
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBNZ    RQ3
        INC     RD
        LOAD    RF, JMPV + 1    ; LBR there (a jump in RAM: R3 is the PC)
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LBR     JMPV
RQ3:    INC     RD
        INC     RD
        INC     RD
        LBR     RQ2
RQ9:    SEP     R5
RQTAB:  DB      'br'
        DW      H_BR
        DB      'sp'
        DW      H_SP
        DB      'bp'
        DW      H_BP
        DB      'ne'
        DW      H_NE
        DB      'fi'
        DW      H_FI
        DB      'nf'
        DW      H_NF
        DB      'ad'
        DW      H_AD
        DB      'na'
        DW      H_NA
        DB      'ce'
        DW      H_CE
        DB      'in'
        DW      H_IN
        DB      'ti'
        DW      H_TI
        DB      'll'
        DW      H_LL
        DB      'pl'
        DW      H_PL
        DB      'pp'
        DW      H_PP
        DB      'he'
        DW      H_HE
        DB      'fo'
        DW      H_FO
        DB      'lp'
        DW      H_LP
        DB      'ip'
        DW      H_IP
        DB      'sh'
        DW      H_SH
        DB      'nh'
        DW      H_NH
        DB      'tl'
        DW      H_TL
        DB      'ds'
        DW      H_DS
        DB      'de'
        DW      H_DE
        DB      'b '
        DW      H_B
        DB      'i '
        DW      H_I
        DB      'r '
        DW      H_R
        DB      0

H_BR:   LBR     BRK
H_SP:   SEP     R4
        DW      BRK
        SEP     R4
        DW      SPUN            ; RD = the lines
        LOAD    RF, SPN
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        LBR     SPACE
H_BP:   SEP     R4
        DW      BRK
        SEP     R4
        DW      PLON
        LBZ     HX
        SEP     R4
        DW      LNOV
        LBZ     HX
        LDI     0
        LBR     ENDPG
H_NE:   SEP     R4
        DW      BRK
        LOAD    RA, 1
        SEP     R4
        DW      NUM             ; RD = the lines needed
        SEP     R4
        DW      PLON
        LBZ     HX
        SEP     R4
        DW      LNOV
        LBZ     HX
        STR     R2              ; RD = LNO + N (DF: past 65535: too many)
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LBDF    NE1
        SEP     R4
        DW      BODY            ; past BODY: a new page
        STR     R2
        GLO     RD
        SD                      ; BODY - (LNO + N) < 0?
        GHI     RD
        SDBI    0
        LBDF    HX
NE1:    LDI     0
        LBR     ENDPG
H_FI:   SEP     R4
        DW      BRK
        LDI     1
        LBR     H_NF1
H_NF:   SEP     R4
        DW      BRK
        LDI     0
H_NF1:  PLO     RE
        LOAD    RD, FILL
        GLO     RE
        STR     RD
HX:     SEP     R5
H_AD:   LDI     1
        LBR     H_NA1
H_NA:   LDI     0
H_NA1:  PLO     RE
        LOAD    RD, ADJ
        GLO     RE
        STR     RD
        SEP     R5
H_CE:   SEP     R4
        DW      BRK
        LOAD    RA, 1
        SEP     R4
        DW      NUM
        LOAD    RF, CE
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        SEP     R5
H_IN:   SEP     R4
        DW      BRK
        SEP     R4
        DW      INTI            ; D = the new indent, 0 .. LL - 1
        PLO     RE
        LOAD    RD, IND
        GLO     RE
        STR     RD
        SEP     R5
H_TI:   SEP     R4
        DW      BRK
        SEP     R4
        DW      INTI
        PLO     RE
        LOAD    RD, TI
        GLO     RE
        STR     RD
        SEP     R5
INTI:   LOAD    RD, IND         ; D = (IN, or IN + N, IN - N) kept to 0 .. LL - 1
        LDN     RD
        PLO     RB
        LDI     0
        PHI     RB              ; RB = now
        LOAD    RA, 0           ; (the default: 0)
        SEP     R4
        DW      REL
        LDI     0
        PLO     RA              ; low 0
        SEP     R4
        DW      LLV
        SMI     1
        PHI     RA              ; high LL - 1
        LBR     CLAMP
H_LL:   SEP     R4
        DW      LLV
        PLO     RB
        LDI     0
        PHI     RB
        LOAD    RA, 65
        SEP     R4
        DW      REL
        LDI     10
        PLO     RA
        LDI     MAXLL
        PHI     RA
        SEP     R4
        DW      CLAMP
        PLO     RE
        LOAD    RD, LL
        GLO     RE
        STR     RD
        SMI     1               ; IN = min(IN, LL - 1)
        STR     R2
        LOAD    RD, IND
        LDN     RD
        SD                      ; (LL - 1) - IN
        LBDF    HX
        LDX
        STR     RD
        SEP     R5
H_PL:   LOAD    RA, 60
        SEP     R4
        DW      NUM
        GHI     RD
        LBNZ    PL2             ; over 255: 255
        GLO     RD
        LBZ     PL3             ; 0: no pages
        SMI     7
        LBDF    PL1
        LDI     7               ; under 7: 7
        LBR     PL4
PL1:    GLO     RD
        LBR     PL4
PL2:    LDI     255
        LBR     PL4
PL3:    LOAD    RD, PL          ; no pages: LNO = 0 too
        LDI     0
        STR     RD
        LOAD    RD, LNO
        LDI     0
        STR     RD
        SEP     R5
PL4:    PLO     RB
        LOAD    RD, PL
        GLO     RB
        STR     RD
        SEP     R4              ; this page already past the new length: it ends
        DW      BODY
        PLO     RB
        SEP     R4
        DW      LNOV
        LBZ     HX
        STR     R2
        GLO     RB
        SD                      ; LNO - BODY >= 0?
        LBNF    HX
        LDI     0
        LBR     ENDPG
H_PP:   SEP     R4
        DW      BRK
        SEP     R4
        DW      ENDIP
        LOAD    RD, SPN
        LDI     0
        STR     RD
        INC     RD
        LDI     1
        STR     RD
        SEP     R4
        DW      SPACE
        LOAD    RD, IND         ; TI = min(IN + 5, LL - 1)
        LDN     RD
        ADI     5
        PLO     RB
        SEP     R4
        DW      LLV
        SMI     1
        STR     R2
        GLO     RB
        SD                      ; (LL - 1) - (IN + 5)
        LBDF    PP1
        LDX
        PLO     RB
PP1:    LOAD    RD, TI
        GLO     RB
        STR     RD
        SEP     R5
H_HE:   LOAD    RA, HE
        LBR     HF1
H_FO:   LOAD    RA, FO
HF1:    SEP     R4
        DW      ARGRF
        SEP     R4
        DW      K_SKIPSP
        LDI     80              ; 80 characters at most
        PLO     RE
HF2:    GLO     RE
        LBZ     HF3
        LDA     RF
        STR     RA
        LBZ     HX
        INC     RA
        DEC     RE
        LBR     HF2
HF3:    LDI     0
        STR     RA
        SEP     R5
; ---- -ms's: .lp .ip .sh .nh .tl .ds .de
ENDIP:  LOAD    RD, PIND        ; .ip's indent and tag: gone
        LDI     0
        STR     RD
        LOAD    RD, TAGN
        LDI     0
        STR     RD
        SEP     R5
SPACE1: LOAD    RD, SPN         ; SPACE 1
        LDI     0
        STR     RD
        INC     RD
        LDI     1
        STR     RD
        LBR     SPACE
H_LP:   SEP     R4
        DW      BRK
        SEP     R4
        DW      ENDIP
        LBR     SPACE1
H_IP:   SEP     R4
        DW      BRK
        SEP     R4
        DW      ENDIP
        SEP     R4
        DW      SPACE1
        SEP     R4              ; the tag: "words" or a word -> TAGB (TAGN)
        DW      ARGRF
        SEP     R4
        DW      K_SKIPSP
        LOAD    RD, TAGB
        LDI     0
        PLO     RB              ; RB.0 = its length
        LDN     RF
        XRI     '"'
        LBNZ    IP3
        INC     RF
IP1:    LDN     RF              ; quoted: to the next ", or the end
        LBZ     IP5
        INC     RF
        XRI     '"'
        LBZ     IP5
        DEC     RF
        LDA     RF
        STR     RD
        INC     RD
        INC     RB
        LBR     IP1
IP3:    LDN     RF              ; a word: to a space or the end
        LBZ     IP5
        XRI     ' '
        LBZ     IP5
        LDA     RF
        STR     RD
        INC     RD
        INC     RB
        LBR     IP3
IP5:    LOAD    RD, TAGN
        GLO     RB
        STR     RD
        LOAD    RD, ARGP        ; the rest: N (5)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RA, 5
        SEP     R4
        DW      NUM
        LOAD    RF, IND         ; PIND = min(N, LL - 1 - IN)
        LDN     RF
        STR     R2
        LOAD    RF, LL
        LDN     RF
        SMI     1
        SM
        PLO     RB              ; RB.0 = LL - 1 - IN
        GHI     RD
        LBNZ    IP6
        GLO     RB
        STR     R2
        GLO     RD
        SD                      ; m - N
        LBNF    IP6
        GLO     RD
        LBR     IP7
IP6:    GLO     RB
IP7:    PLO     RB
        LOAD    RD, PIND
        GLO     RB
        STR     RD
        LOAD    RD, TAGN        ; a tag: fits in the indent (shorter than it): it waits for the line; else
        LDN     RD              ;  on a line of its own, at IN
        LBZ     HX
        STR     R2
        GLO     RB
        SM                      ; PIND - tag
        LBZ     IP8
        LBDF    HX
IP8:    LOAD    RF, LBUF
        LOAD    RD, IND
        LDN     RD
        SEP     R4
        DW      SPCS
        LOAD    RD, TAGN
        LDN     RD
        PLO     RB
        LDI     0
        STR     RD
        LOAD    RD, TAGB
IP9:    GLO     RB
        LBZ     LINEO
        LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        LBR     IP9
H_SH:   LDI     0
        LBR     HD0
H_NH:   LDI     1
HD0:    PLO     RB
        LOAD    RD, NUMH
        GLO     RB
        STR     RD
        SEP     R4
        DW      BRK
        SEP     R4
        DW      ENDIP
        SEP     R4
        DW      SPACE1
        SEP     R4              ; 3 lines must fit, else a new page
        DW      PLON
        LBZ     HD2
        SEP     R4
        DW      LNOV
        LBZ     HD2
        ADI     3
        PLO     RB
        LBDF    HD1
        SEP     R4
        DW      BODY
        STR     R2
        GLO     RB
        SD
        LBDF    HD2
HD1:    LDI     0
        SEP     R4
        DW      ENDPG
HD2:    LOAD    RD, HCNT        ; the heading (255 characters at most) -> TMPL
        LDI     0
        STR     RD
        LOAD    RD, TMPL
        LOAD    RF, HPTR        ; (RD's place kept in HPTR)
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        SEP     R4
        DW      ARGRF
        SEP     R4
        DW      K_SKIPSP
        LOAD    RD, NUMH
        LDN     RD
        LBZ     HD8
        LDI     1               ; .nh: the level (1-5), the numbers
        PLO     RA
        LDN     RF
        SMI     '0'
        LBNF    HD4
        SMI     10
        LBDF    HD4
        LOAD    RD, 0           ; digits -> RD (16 bits)
HD3:    LDN     RF
        SMI     '0'
        LBNF    HD3E
        SMI     10
        LBDF    HD3E
        GLO     RD              ; RD x 10 + the digit
        SHL
        PLO     RC
        GHI     RD
        SHLC
        PHI     RC
        GLO     RC
        SHL
        PLO     RD
        GHI     RC
        SHLC
        PHI     RD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        GLO     RC
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RC
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        LDA     RF
        SMI     '0'
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LBR     HD3
HD3E:   GHI     RD              ; 1 .. 5
        LBNZ    HD3F
        GLO     RD
        LBZ     HD3G
        SMI     6
        LBDF    HD3F
        GLO     RD
        LBR     HD3H
HD3F:   LDI     5
        LBR     HD3H
HD3G:   LDI     1
HD3H:   PLO     RA
        SEP     R4
        DW      K_SKIPSP
HD4:    GLO     RA              ; NUMS[level - 1] + 1, the ones after it 0
        SMI     1
        SHL
        ADI     LOW(NUMS)
        PLO     RD
        LDI     HIGH(NUMS)
        ADCI    0
        PHI     RD
        INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        INC     RD
        INC     RD
        GLO     RA
        PLO     RB
HD5:    GLO     RB
        XRI     5
        LBZ     HD6
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        INC     RB
        LBR     HD5
HD6:    LOAD    RD, HLEV
        GLO     RA
        STR     RD
        LOAD    RD, ARGP        ; (the text's place)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDI     0
        PLO     RA              ; the numbers: "1.2.3. "
HD7:    LOAD    RD, HLEV
        LDN     RD
        STR     R2
        GLO     RA
        SM
        LBDF    HD7E
        GLO     RA
        SHL
        ADI     LOW(NUMS)
        PLO     RD
        LDI     HIGH(NUMS)
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, NUMBUF
        SEP     R4
        DW      DECS
        LDI     '.'
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RF, NUMBUF
HD7B:   LDA     RF
        LBZ     HD7C
        SEP     R4
        DW      HPUT
        LBR     HD7B
HD7C:   INC     RA
        LBR     HD7
HD7E:   LDI     ' '
        SEP     R4
        DW      HPUT
        SEP     R4
        DW      ARGRF
HD8:    LDA     RF              ; the text
        LBZ     HD9
        SEP     R4
        DW      HPUT
        LBR     HD8
HD9:    LOAD    RD, HCNT        ; nothing: no line
        LDN     RD
        LBZ     HX
        LOAD    RD, HPTR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC              ; RC = its end
        LOAD    RF, LBUF        ; LBUF: IN spaces, bold, the heading, the font before
        LOAD    RD, IND
        LDN     RD
        SEP     R4
        DW      SPCS
        LDI     'B'
        SEP     R4
        DW      SETF
        STR     RF
        INC     RF
        LOAD    RD, TMPL
HD10:   GHI     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    HD11
        GLO     RD
        STR     R2
        GLO     RC
        XOR
        LBZ     HD12
HD11:   LDA     RD
        STR     RF
        INC     RF
        LBR     HD10
HD12:   LDI     'P'
        SEP     R4
        DW      SETF
        STR     RF
        INC     RF
        LBR     LINEO
HPUT:   PLO     RB              ; D -> the heading at HPTR, 255 at most (RF, RA kept)
        LOAD    R9, HCNT
        LDN     R9
        XRI     0FFH
        LBZ     HP9
        LDN     R9
        ADI     1
        STR     R9
        LOAD    R9, HPTR
        LDA     R9
        PHI     RD
        LDN     R9
        PLO     RD
        GLO     RB
        STR     RD
        INC     RD
        GLO     RD
        STR     R9
        DEC     R9
        GHI     RD
        STR     R9
HP9:    SEP     R5
H_TL:   SEP     R4              ; a title line, here: the argument (80 at most) -> TLB -> TITLE -> LBUF
        DW      BRK
        SEP     R4
        DW      ARGRF
        SEP     R4
        DW      K_SKIPSP
        LOAD    RD, TLB
        LDI     80
        PLO     RB
TL1:    GLO     RB
        LBZ     TL2
        LDA     RF
        STR     RD
        LBZ     TL3
        INC     RD
        DEC     RB
        LBR     TL1
TL2:    LDI     0
        STR     RD
TL3:    LOAD    RA, TLB
        SEP     R4
        DW      TITLE
        LOAD    RD, TEND
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, TBUF
        LOAD    RF, LBUF
TL4:    GHI     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    TL5
        GLO     RD
        STR     R2
        GLO     RC
        XOR
        LBZ     LINEO
TL5:    LDA     RD
        STR     RF
        INC     RF
        LBR     TL4
H_DS:   SEP     R4              ; a display: kept, no fill; I indented 5 (the default), L left, C centred
        DW      BRK
        LOAD    RD, KEEPING
        LDN     RD
        LBZ     DS1
        SEP     R4
        DW      FLUSH
DS1:    LOAD    RD, DSAV        ; FILL, IN, CE kept for .de (once)
        LDN     RD
        LBNZ    DS2
        LDI     1
        STR     RD
        LOAD    RF, FILL
        LDN     RF
        PLO     RB
        LOAD    RD, SFILL
        GLO     RB
        STR     RD
        LOAD    RF, IND
        LDN     RF
        PLO     RB
        LOAD    RD, SIND
        GLO     RB
        STR     RD
        LOAD    RF, CE
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        LOAD    RD, SCE
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
DS2:    LOAD    RD, FILL
        LDI     0
        STR     RD
        LOAD    RD, KEEPING
        LDI     1
        STR     RD
        SEP     R4
        DW      ARGRF
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        ORI     20H
        XRI     'c'
        LBNZ    DS3
        LOAD    RD, CE
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        SEP     R5
DS3:    XRI     'c' XOR 'l'
        LBZ     HX
        LOAD    RD, IND         ; IN = min(IN + 5, LL - 1)
        LDN     RD
        ADI     5
        PLO     RB
        SEP     R4
        DW      LLV
        SMI     1
        STR     R2
        GLO     RB
        SD
        LBDF    DS4
        LDX
        PLO     RB
DS4:    LOAD    RD, IND
        GLO     RB
        STR     RD
        SEP     R5
H_DE:   SEP     R4
        DW      BRK
        LOAD    RD, KEEPING
        LDN     RD
        LBZ     DE1
        SEP     R4
        DW      FLUSH
        LOAD    RD, KEEPING
        LDI     0
        STR     RD
DE1:    LOAD    RD, DSAV        ; FILL, IN, CE back
        LDN     RD
        LBZ     HX
        LDI     0
        STR     RD
        LOAD    RD, SFILL
        LDN     RD
        PLO     RB
        LOAD    RF, FILL
        GLO     RB
        STR     RF
        LOAD    RD, SIND
        LDN     RD
        PLO     RB
        LOAD    RF, IND
        GLO     RB
        STR     RF
        LOAD    RD, SCE
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RF, CE
        GHI     RB
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        SEP     R5

; SPUN: .sp's argument -> RD lines: N, or N.N with a unit (i inches: 6 lines; c cm; p points: 12 a line;
;       v lines), 99.9 at most; nothing: 1. As eroff_model.spunits.
SPUN:   SEP     R4
        DW      ARGRF
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        XRI     '+'
        LBZ     SU0
        LDN     RF
        XRI     '-'
        LBNZ    SU1
SU0:    INC     RF
SU1:    LOAD    RD, SUHAS       ; SUHAS: 1 digits, 2 a decimal; SUF: the decimal
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, 0
SU2:    LDN     RF              ; digits -> RD (16 bits)
        SMI     '0'
        LBNF    SU3
        SMI     10
        LBDF    SU3
        LOAD    RC, SUHAS
        LDI     1
        STR     RC
        GLO     RD              ; RD x 10 + the digit
        SHL
        PLO     RC
        GHI     RD
        SHLC
        PHI     RC
        GLO     RC
        SHL
        PLO     RD
        GHI     RC
        SHLC
        PHI     RD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        GLO     RC
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RC
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        LDA     RF
        SMI     '0'
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LBR     SU2
SU3:    LDN     RF              ; . and a digit
        XRI     '.'
        LBNZ    SU5
        INC     RF
        LDN     RF
        SMI     '0'
        LBNF    SU4
        SMI     10
        LBDF    SU4
        LDA     RF
        SMI     '0'
        PLO     RB
        LOAD    RC, SUF
        GLO     RB
        STR     RC
        LOAD    RC, SUHAS
        LDN     RC
        ORI     2
        STR     RC
SU3A:   LDN     RF              ; more decimals: left off
        SMI     '0'
        LBNF    SU5
        SMI     10
        LBDF    SU5
        INC     RF
        LBR     SU3A
SU4:    DEC     RF
SU5:    LOAD    RC, SUHAS       ; nothing: 1
        LDN     RC
        LBNZ    SU6
        LOAD    RD, 1
        SEP     R5
SU6:    LDN     RF              ; a unit? (SUU)
        ORI     20H
        PLO     RA
        LOAD    RC, SUU
        GLO     RA
        STR     RC
        XRI     'i'
        LBZ     SU7
        GLO     RA
        XRI     'c'
        LBZ     SU7
        GLO     RA
        XRI     'p'
        LBZ     SU7
        GLO     RA
        XRI     'v'
        LBNZ    HX              ; none: N lines (RD)
SU7:    GHI     RD              ; V10 = min(N x 10 + the decimal, 999)
        LBNZ    SU8
        GLO     RD
        SMI     100
        LBDF    SU8
        GLO     RD
        PLO     RC
        LDI     0
        PHI     RC
        LDI     10
        SEP     R4
        DW      MULK
        LOAD    RD, SUF
        LDN     RD
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LBR     SU9
SU8:    LOAD    RC, 999
SU9:    GHI     RC              ; (999 at most)
        STR     R2
        SMI     3
        LBNF    SU9A
        LBNZ    SU9B
        GLO     RC
        SMI     0E8H
        LBNF    SU9A
SU9B:   LOAD    RC, 999
SU9A:   LOAD    RA, SUU         ; i: (V10 x 6 + 5) / 10; c: (V10 x 59 + 125) / 250; p: (V10 + 60) / 120;
        LDN     RA              ;  v: (V10 + 5) / 10
        PLO     RA
        XRI     'i'
        LBNZ    SUA
        LDI     6
        SEP     R4
        DW      MULK
        LOAD    RA, 5
        LOAD    RB, 10
        LBR     SUD
SUA:    LOAD    RA, SUU
        LDN     RA
        XRI     'c'
        LBNZ    SUB
        LDI     59
        SEP     R4
        DW      MULK
        LOAD    RA, 125
        LOAD    RB, 250
        LBR     SUD
SUB:    LOAD    RA, SUU
        LDN     RA
        XRI     'p'
        LBNZ    SUC
        LOAD    RA, 60
        LOAD    RB, 120
        LBR     SUD
SUC:    LOAD    RA, 5
        LOAD    RB, 10
SUD:    GLO     RA              ; (RC + RA) / RB -> RD
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RA
        STR     R2
        GHI     RC
        ADC
        PHI     RC
        LOAD    RD, 0
SUE:    GLO     RB
        STR     R2
        GLO     RC
        SM
        PLO     RA
        GHI     RB
        STR     R2
        GHI     RC
        SMB
        LBNF    HX
        PHI     RC
        GLO     RA
        PLO     RC
        INC     RD
        LBR     SUE
MULK:   PLO     RA              ; RC = RC x D (small)
        LOAD    RB, 0
MK1:    GLO     RA
        LBZ     MK2
        GLO     RC
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RC
        STR     R2
        GHI     RB
        ADC
        PHI     RB
        DEC     RA
        LBR     MK1
MK2:    GHI     RB
        PHI     RC
        GLO     RB
        PLO     RC
        SEP     R5

; .B .I .R: with text, that text in the font and then the one before (as the line "\fX text \fP"); alone,
;            the font from here on (its change waits for the next word)
H_B:    LDI     'B'
        LBR     HF0
H_I:    LDI     'I'
        LBR     HF0
H_R:    LDI     'R'
HF0:    PLO     RB
        LOAD    RD, FLET
        GLO     RB
        STR     RD
        SEP     R4
        DW      ARGRF
        SEP     R4
        DW      K_SKIPSP
        LDI     0
        PLO     RA              ; RA.0 = '"': it ends the text
        LDN     RF
        XRI     '"'
        LBNZ    HF4
        INC     RF
        LDI     '"'
        PLO     RA
        LDN     RF              ; "" or a lone ": nothing at all
        LBZ     HX
        XRI     '"'
        LBZ     HX
HF4:    LDN     RF
        LBNZ    HF5
        LOAD    RD, FLET        ; alone
        LDN     RD
        SEP     R4
        DW      SETF
        SEP     R4
        DW      PFXADD
        SEP     R5
HF5:    LOAD    RD, TCNT        ; "\fX" text "\fP", 255 characters at most -> TMPL -> LINE
        LDI     0
        STR     RD
        LOAD    RD, TMPL
        LDI     5CH
        SEP     R4
        DW      TPUT
        LDI     'f'
        SEP     R4
        DW      TPUT
        LOAD    RB, FLET
        LDN     RB
        SEP     R4
        DW      TPUT
HF6:    LDA     RF
        LBZ     HF7
        STR     R2
        GLO     RA              ; (the closing ")
        LBZ     HF6A
        XOR
        LBZ     HF7
        LDX
HF6A:   LDX
        SEP     R4
        DW      TPUT
        LBR     HF6
HF7:    LDI     5CH
        SEP     R4
        DW      TPUT
        LDI     'f'
        SEP     R4
        DW      TPUT
        LDI     'P'
        SEP     R4
        DW      TPUT
        LDI     0
        STR     RD
        LOAD    RF, TMPL
        LOAD    RD, LINE
HF8:    LDA     RF
        STR     RD
        INC     RD
        LBNZ    HF8
        SEP     R4
        DW      CONV
        LBR     TEXT
TPUT:   PLO     RB              ; D -> TMPL at RD, if under 255 there (the count in TCNT; RE.0 is not kept by calls)
        LOAD    R9, TCNT
        LDN     R9
        XRI     0FFH
        LBZ     TP9
        LDN     R9
        ADI     1
        STR     R9
        GLO     RB
        STR     RD
        INC     RD
TP9:    SEP     R5
; CONV: LINE's \fB \fI \fR \fP -> the bytes 2, 3, 1 (and P: the font before), in place; anything else as it is
CONV:   LOAD    RF, LINE
        LOAD    RD, LINE
CV1:    LDA     RF
        LBZ     CV9
        XRI     5CH
        LBZ     CV2
        XRI     5CH
CV1A:   STR     RD
        INC     RD
        LBR     CV1
CV2:    LDN     RF              ; \& : nothing
        XRI     '&'
        LBNZ    CV2A
        INC     RF
        LBR     CV1
CV2A:   LDN     RF              ; \f and a font letter?
        XRI     'f'
        LBNZ    CV3
        INC     RF
        LDN     RF
        PLO     RC
        XRI     'B'
        LBZ     CV4
        GLO     RC
        XRI     'I'
        LBZ     CV4
        GLO     RC
        XRI     'R'
        LBZ     CV4
        GLO     RC
        XRI     'P'
        LBZ     CV4
        DEC     RF              ; no: the backslash as it is
CV3:    LDI     5CH
        LBR     CV1A
CV4:    INC     RF
        GLO     RC
        SEP     R4
        DW      SETF
        LBR     CV1A
CV9:    STR     RD
        SEP     R5
; SETF: D = B I R or P -> the font now (P: the one before); D = its byte (1 R, 2 B, 3 I). R8, R9 used.
SETF:   PHI     R8
        XRI     'P'
        LBNZ    SF1
        LOAD    R9, FPRV
        LDN     R9
        PHI     R8
SF1:    LOAD    R9, FCUR        ; FPRV = FCUR, FCUR = it
        LDN     R9
        PLO     R8
        LOAD    R9, FPRV
        GLO     R8
        STR     R9
        LOAD    R9, FCUR
        GHI     R8
        STR     R9
        XRI     'R'
        LBNZ    SF2
        LDI     1
        SEP     R5
SF2:    XRI     'R' XOR 'B'
        LBNZ    SF3
        LDI     2
        SEP     R5
SF3:    LDI     3
        SEP     R5
; PFXADD: D (a font byte) onto PFX, the changes waiting for the next word (32 at most)
PFXADD: PHI     R8
        LOAD    R9, PFXN
        LDN     R9
        XRI     32
        LBZ     PX9
        LDN     R9
        ADI     1
        STR     R9
        SMI     1
        ADI     LOW(PFXB)
        PLO     R9
        LDI     HIGH(PFXB)
        ADCI    0
        PHI     R9
        GHI     R8
        STR     R9
PX9:    SEP     R5
; PFXOUT: PFX's bytes at RF (RF past them), PFXN = 0
PFXOUT: LOAD    RD, PFXN
        LDN     RD
        PLO     RB
        LDI     0
        STR     RD
        LOAD    RD, PFXB
PO1:    GLO     RB
        LBZ     PO9
        LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        LBR     PO1
PO9:    SEP     R5
ARGRF:  LOAD    RD, ARGP        ; RF -> the request's argument
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5

; NUM: the argument -> RD: [+ or -] digits (the sign in SIGN: 0 none, 1 +, 2 -); no digits: RD = RA (the
;      default). As roff_model.num: spaces before the sign, none after it; 16 bits (more wraps).
NUM:    SEP     R4
        DW      ARGRF
        SEP     R4
        DW      K_SKIPSP
        LDI     0
        PLO     RE              ; RE.0 = the sign
        LDN     RF
        XRI     '+'
        LBNZ    NM1
        LDI     1
        LBR     NM2
NM1:    LDN     RF
        XRI     '-'
        LBNZ    NM3
        LDI     2
NM2:    PLO     RE
        INC     RF
NM3:    LOAD    RD, SIGN
        GLO     RE
        STR     RD
        LDN     RF
        SMI     '0'
        LBNF    NMD
        SMI     10
        LBDF    NMD
        LOAD    RD, 0
NM4:    LDN     RF
        SMI     '0'
        LBNF    NM9
        SMI     10
        LBDF    NM9
        GLO     RD              ; RD = RD x 10 + the digit: RC = 2 RD, RD = 8 RD, RD + RC
        SHL
        PLO     RC
        GHI     RD
        SHLC
        PHI     RC
        GLO     RC
        SHL
        PLO     RD
        GHI     RC
        SHLC
        PHI     RD
        GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        GLO     RC
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RC
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        LDA     RF
        SMI     '0'
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LBR     NM4
NMD:    GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
NM9:    SEP     R5

; REL: RB = the value now, RA = the default -> RD = N, now + N or now - N (NUM's sign); BEYOND = 1 below 0,
;      2 past 65535, else 0
REL:    SEP     R4
        DW      NUM
        LOAD    RF, BEYOND
        LDI     0
        STR     RF
        LOAD    RF, SIGN
        LDN     RF
        LBZ     RL9
        XRI     1
        LBNZ    RL2
        GLO     RB              ; +: now + N
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RB
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        LBNF    RL9
        LDI     2
        LBR     RL8
RL2:    GLO     RD              ; -: now - N
        STR     R2
        GLO     RB
        SM
        PLO     RD
        GHI     RD
        STR     R2
        GHI     RB
        SMB
        PHI     RD
        LBDF    RL9
        LDI     1
RL8:    PLO     RE
        LOAD    RF, BEYOND
        GLO     RE
        STR     RF
RL9:    SEP     R5
; CLAMP: RD (and BEYOND) -> D kept to RA.0 .. RA.1
CLAMP:  LOAD    RF, BEYOND
        LDN     RF
        XRI     1
        LBZ     CLLO
        LDN     RF
        LBNZ    CLHI
        GHI     RD
        LBNZ    CLHI
        GHI     RA              ; RD.0 > high?
        STR     R2
        GLO     RD
        SD                      ; high - RD.0
        LBNF    CLHI
        GLO     RA
        STR     R2
        GLO     RD
        SM                      ; RD.0 - low
        LBNF    CLLO
        GLO     RD
        SEP     R5
CLHI:   GHI     RA
        SEP     R5
CLLO:   GLO     RA
        SEP     R5

; ==== text lines
TEXT:   LOAD    RD, CE          ; centring?
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    TXCE
        LOAD    RD, FILL
        LDN     RD
        LBZ     TXNF
; fill: spaces first - a break, and it starts that far in; then each word with the spaces before it
        LOAD    RF, LINE
        LDI     0
        PLO     RA              ; RA.0 = the spaces first
TF1:    LDN     RF
        XRI     ' '
        LBNZ    TF2
        INC     RF
        INC     RA
        LBR     TF1
TF2:    GLO     RA
        LBZ     TF4
        LOAD    RD, LEAD
        GLO     RA
        STR     RD
        SEP     R4
        DW      BRK
        LOAD    RD, LEAD        ; TI = min(IN + spaces, LL - 1)
        LDN     RD
        STR     R2
        LOAD    RD, IND
        LDN     RD
        ADD
        PLO     RB
        LBDF    TF3             ; (past 255: LL - 1)
        SEP     R4
        DW      LLV
        SMI     1
        STR     R2
        GLO     RB
        SD
        LBDF    TF3A
TF3:    SEP     R4
        DW      LLV
        SMI     1
        PLO     RB
TF3A:   LOAD    RD, TI
        GLO     RB
        STR     RD
        LOAD    RF, LINE        ; past the spaces again (BRK used RF)
TF3B:   LDN     RF
        XRI     ' '
        LBNZ    TF4
        INC     RF
        LBR     TF3B
TF4:    LOAD    RD, WGAP        ; the first word: 1 space before it
        LDI     1
        STR     RD
TF5:    LDN     RF
        LBZ     HX              ; the line's end
        XRI     ' '
        LBNZ    TF6
        INC     RF
        LOAD    RD, WGAP        ; a space: one more before the next word
        LDN     RD
        ADI     1
        STR     RD
        LBR     TF5
TF6:    LOAD    RD, WPTR        ; a word: where, how long, how much of it shows
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDI     0
        PLO     RE
        PLO     RC
TF7:    LDN     RF
        LBZ     TF8
        XRI     ' '
        LBZ     TF8
        LDA     RF
        SMI     4
        LBNF    TF7A            ; a font byte: takes no room
        INC     RC
TF7A:   INC     RE
        LBR     TF7
TF8:    LOAD    RD, WLEN
        GLO     RE
        STR     RD
        LOAD    RD, WVIS
        GLO     RC
        STR     RD
        LBNZ    TF8W
        SEP     R4              ; only font changes: onto the last word (or for the next); the spaces
        DW      ATTACH          ;  around them still count, as they come
        LBR     TF5
TF8W:
        LOAD    RD, LPTR        ; (WORD uses RF)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      WORD
        LOAD    RD, LPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, WGAP
        LDI     0
        STR     RD
        LBR     TF5

; no fill: the indent, then the line as it is
TXNF:   SEP     R4
        DW      CURIND
        PLO     RA
        LOAD    RF, LBUF
        GLO     RA
        SEP     R4
        DW      SPCS
        SEP     R4
        DW      PFXOUT
        LOAD    RD, LINE
TN1:    LDA     RD
        STR     RF
        LBZ     TN2
        INC     RF
        LBR     TN1
TN2:    LOAD    RD, TI
        LDI     NOTI
        STR     RD
        LBR     LINEO           ; (RF = its end)

; centred: a break; the line without its spaces, in the middle of IN .. LL
TXCE:   SEP     R4
        DW      BRK
        LOAD    RD, CE          ; CE - 1
        INC     RD
        LDN     RD
        SMI     1
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        LOAD    RF, LINE        ; RF -> the first non-space, RD -> after the last one
TC1:    LDN     RF
        XRI     ' '
        LBNZ    TC2
        INC     RF
        LBR     TC1
TC2:    GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        GHI     RF
        PHI     RB
        GLO     RF
        PLO     RB
TC3:    LDA     RB              ; RD = after the last non-space
        LBZ     TC4
        XRI     ' '
        LBZ     TC3
        GHI     RB
        PHI     RD
        GLO     RB
        PLO     RD
        LBR     TC3
TC4:    GLO     RF              ; RC.0 = how much of it shows (its length less its font bytes)
        STR     R2
        GLO     RD
        SM
        PLO     RC
        GHI     RF
        PHI     RB
        GLO     RF
        PLO     RB
TC4A:   GHI     RB
        STR     R2
        GHI     RD
        XOR
        LBNZ    TC4B
        GLO     RB
        STR     R2
        GLO     RD
        XOR
        LBZ     TC4C
TC4B:   LDA     RB
        SMI     4
        LBDF    TC4A
        DEC     RC
        LBR     TC4A
TC4C:
        SEP     R4              ; RA.0 = LL - IN
        DW      LLV
        STR     R2
        LOAD    RB, IND
        LDN     RB
        SD
        PLO     RA
        GLO     RC              ; pad = (LL - IN - length) / 2, 0 if that is not above 0
        STR     R2
        GLO     RA
        SM
        LBNF    TC5
        SHR
        LBR     TC6
TC5:    LDI     0
TC6:    STR     R2
        LDN     RB              ; + IN
        ADD
        PLO     RA
        LOAD    RB, CPTR        ; (RF, RD kept)
        GHI     RF
        STR     RB
        INC     RB
        GLO     RF
        STR     RB
        INC     RB
        GHI     RD
        STR     RB
        INC     RB
        GLO     RD
        STR     RB
        LOAD    RF, LBUF
        GLO     RA
        SEP     R4
        DW      SPCS
        SEP     R4
        DW      PFXOUT
        LOAD    RB, CPTR
        LDA     RB
        PHI     RD
        LDA     RB
        PLO     RD
        LDA     RB
        PHI     RC
        LDN     RB
        PLO     RC              ; RD -> the text, RC -> its end
TC7:    GHI     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    TC8
        GLO     RD
        STR     R2
        GLO     RC
        XOR
        LBZ     LINEO
TC8:    LDA     RD
        STR     RF
        INC     RF
        LBR     TC7

; ATTACH: the font bytes at WPTR (WLEN) onto the end of the last word, if there is one and OBUF has room
;         (OLEN + them <= 250); else onto PFX. RF kept.
ATTACH: LOAD    RD, NW
        LDN     RD
        LBZ     AT5
        LOAD    RD, WLEN        ; OLEN + WLEN <= 250?
        LDN     RD
        STR     R2
        LOAD    RD, OLEN
        LDN     RD
        ADD
        LBDF    AT5
        SMI     251
        LBDF    AT5
        LOAD    RD, OLEN        ; RB -> OBUF + OLEN
        LDN     RD
        ADI     LOW(OBUF)
        PLO     RB
        LDI     HIGH(OBUF)
        ADCI    0
        PHI     RB
        LOAD    RD, WPTR
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, WLEN
        LDN     RD
        PLO     RE
AT1:    GLO     RE
        LBZ     AT2
        LDA     RA
        STR     RB
        INC     RB
        DEC     RE
        LBR     AT1
AT2:    GLO     RB              ; OLEN, WEND[NW - 1]
        SMI     LOW(OBUF)
        PLO     RA
        LOAD    RD, OLEN
        GLO     RA
        STR     RD
        LOAD    RD, NW
        LDN     RD
        SMI     1
        ADI     LOW(WEND)
        PLO     RD
        LDI     HIGH(WEND)
        ADCI    0
        PHI     RD
        GLO     RA
        STR     RD
        SEP     R5
AT5:    LOAD    RD, WPTR        ; onto PFX
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, WLEN
        LDN     RD
        PLO     RB
AT6:    GLO     RB
        LBZ     AT9
        LDA     RA
        SEP     R4
        DW      PFXADD
        DEC     RB
        LBR     AT6
AT9:    SEP     R5

; ==== WORD: a word (WPTR, WLEN bytes, WVIS showing, the spaces before it WGAP) onto the line being filled,
;      PFX's font changes first; it goes out first if it would not fit (what shows > the width, or > 250 bytes)
WORD:   LOAD    RD, NW
        LDN     RD
        LBZ     WD2
        SEP     R4              ; RA.0 = LL - the indent; RB = OLEN + gap + length
        DW      CURIND
        PLO     RA
        SEP     R4
        DW      LLV
        PHI     RA
        GLO     RA
        STR     R2
        GHI     RA
        SM
        PLO     RA
        LOAD    RD, OVIS        ; RB = OVIS + gap + WVIS (what shows)
        LDN     RD
        PLO     RB
        LDI     0
        PHI     RB
        LOAD    RD, WGAP
        LDN     RD
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        LOAD    RD, WVIS
        LDN     RD
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        LBNZ    WD1             ; over 255: it does not fit
        GLO     RA
        STR     R2
        GLO     RB
        SD                      ; width - total
        LBNF    WD1
        LOAD    RD, OLEN        ; and OLEN + gap + PFXN + WLEN <= 250 (bytes)
        LDN     RD
        PLO     RB
        LDI     0
        PHI     RB
        LOAD    RD, WGAP
        LDN     RD
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        LOAD    RD, PFXN
        LDN     RD
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        LOAD    RD, WLEN
        LDN     RD
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        LBNZ    WD1
        GLO     RB
        SMI     251
        LBNF    WD3             ; it fits
WD1:    LOAD    RD, ADJ
        LDN     RD
        SEP     R4
        DW      EMIT
WD2:    LOAD    RD, NW          ; (a line's first word: no spaces before it)
        LDN     RD
        LBZ     WD4
WD3:    LOAD    RD, OLEN        ; the spaces
        LDN     RD
        ADI     LOW(OBUF)
        PLO     RF
        LDI     HIGH(OBUF)
        ADCI    0
        PHI     RF
        LOAD    RD, WGAP
        LDN     RD
        SEP     R4
        DW      SPCS
        LOAD    RD, WGAP        ; OVIS + gap + WVIS
        LDN     RD
        STR     R2
        LOAD    RD, WVIS
        LDN     RD
        ADD
        STR     R2
        LOAD    RD, OVIS
        LDN     RD
        ADD
        STR     RD
        LBR     WD5
WD4:    LOAD    RF, OBUF        ; the first word: OVIS = WVIS
        LOAD    RD, WVIS
        LDN     RD
        PLO     RB
        LOAD    RD, OVIS
        GLO     RB
        STR     RD
WD5:    LOAD    RD, NW          ; WST[NW] = here

        LDN     RD
        PLO     RA
        ADI     LOW(WST)
        PLO     RD
        LDI     HIGH(WST)
        ADCI    0
        PHI     RD
        GLO     RF
        SMI     LOW(OBUF)
        STR     RD
        GLO     RA              ; WG[NW] = the gap
        ADI     LOW(WG)
        PLO     RD
        LDI     HIGH(WG)
        ADCI    0
        PHI     RD
        LOAD    RB, WGAP
        LDN     RB
        STR     RD
        SEP     R4              ; PFX's font changes first (RA kept)
        DW      PFXOUT
        LOAD    RD, WPTR        ; the word
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RD, WLEN
        LDN     RD
        PLO     RE
WD6:    GLO     RE
        LBZ     WD7
        LDA     RB
        STR     RF
        INC     RF
        DEC     RE
        LBR     WD6
WD7:    GLO     RF              ; OLEN, WEND[NW]
        SMI     LOW(OBUF)
        PLO     RE
        LOAD    RD, OLEN
        GLO     RE
        STR     RD
        GLO     RA
        ADI     LOW(WEND)
        PLO     RD
        LDI     HIGH(WEND)
        ADCI    0
        PHI     RD
        GLO     RE
        STR     RD
        LOAD    RD, NW
        GLO     RA
        ADI     1
        STR     RD
        SEP     R5

; BRK: the words so far out as a line, not justified
BRK:    LOAD    RD, NW
        LDN     RD
        LBZ     HX
        LDI     0
; EMIT: D = 1 justify; the line being filled out (the indent, its words); NW = OLEN = 0, TI none
EMIT:   PLO     RE
        LOAD    RD, JUST
        GLO     RE
        STR     RD
        SEP     R4              ; LBUF: the indent; WIDTH = LL - it
        DW      CURIND
        PLO     RA
        SEP     R4
        DW      LLV
        PHI     RA
        GLO     RA
        STR     R2
        GHI     RA
        SM
        PLO     RB
        LOAD    RD, WIDTH
        GLO     RB
        STR     RD
        LOAD    RF, LBUF
        LOAD    RD, TAGN        ; .ip's tag waiting: IN spaces, the tag, then to the indent (1 space at least)
        LDN     RD
        LBNZ    EMT1
        GLO     RA
        SEP     R4
        DW      SPCS
        LBR     EMT9
EMT1:   LOAD    RD, IND
        LDN     RD
        SEP     R4
        DW      SPCS
        LOAD    RD, TAGN
        LDN     RD
        PLO     RB
        LOAD    RD, TAGB
EMT2:   GLO     RB
        LBZ     EMT3
        LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        LBR     EMT2
EMT3:   LOAD    RD, IND         ; pad = indent - IN - the tag's length; 1 if under 1
        LDN     RD
        STR     R2
        GLO     RA
        SM
        LBNF    EMT4
        PLO     RB
        LOAD    RD, TAGN
        LDN     RD
        STR     R2
        GLO     RB
        SM
        LBNF    EMT4
        LBNZ    EMT5
EMT4:   LDI     1
EMT5:   SEP     R4
        DW      SPCS
        LOAD    RD, TAGN
        LDI     0
        STR     RD
EMT9:   LOAD    RD, JUST        ; justify: NW > 1 and OLEN < width?
        LDN     RD
        LBZ     EM3
        LOAD    RD, NW
        LDN     RD
        SMI     2
        LBNF    EM2
        LOAD    RD, OVIS
        LDN     RD
        STR     R2
        LOAD    RD, WIDTH
        LDN     RD
        SM                      ; extra = width - what shows
        LBNF    EM2
        LBZ     EM2
        PLO     RB              ; RB.0 = extra
        LOAD    RD, NW          ; RA.1 = gaps
        LDN     RD
        SMI     1
        PHI     RA
        LDI     0
        PHI     RB              ; RB.1 = base = extra / gaps; RB.0 = rem
EM1:    GHI     RA
        STR     R2
        GLO     RB
        SM
        LBNF    EM1A
        PLO     RB
        GHI     RB
        ADI     1
        PHI     RB
        LBR     EM1
EM1A:   LOAD    RD, BASE
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD              ; REM
        INC     RD
        GHI     RA
        STR     RD              ; GAPS
        LOAD    RD, DIRL        ; DIRL: the left gaps get the rest (else the right); then the other way
        LDN     RD
        PLO     RE
        XRI     1
        STR     RD
        LOAD    RD, DIRNOW
        GLO     RE
        STR     RD
        LBR     EM3
EM2:    LOAD    RD, JUST
        LDI     0
        STR     RD
EM3:    LDI     0               ; the words: i = 0 ..
        PLO     RA
EM4:    GLO     RA
        STR     R2
        LOAD    RD, NW
        LDN     RD
        SD                      ; i - NW
        LBDF    EM9             ; i >= NW: done
        GLO     RA
        LBZ     EM6             ; the first word: no spaces
        ADI     LOW(WG)         ; the spaces: WG[i] (+ base, + 1 for the gaps that get the rest)
        PLO     RD
        LDI     HIGH(WG)
        ADCI    0
        PHI     RD
        LDN     RD
        PLO     RE
        LOAD    RD, JUST
        LDN     RD
        LBZ     EM5
        LOAD    RD, BASE
        LDA     RD
        STR     R2
        GLO     RE
        ADD
        PLO     RE
        LDA     RD              ; REM
        PHI     RB
        LDN     RD              ; GAPS
        PLO     RB
        GLO     RA              ; j = i - 1
        SMI     1
        PHI     RC
        LOAD    RD, DIRNOW
        LDN     RD
        LBZ     EM4R
        GHI     RB              ; left: j < rem
        STR     R2
        GHI     RC
        SM
        LBDF    EM5
        INC     RE
        LBR     EM5
EM4R:   GLO     RB              ; right: j >= gaps - rem
        STR     R2
        GHI     RB
        SD                      ; gaps - rem
        STR     R2
        GHI     RC
        SM                      ; j - (gaps - rem)
        LBNF    EM5
        INC     RE
EM5:    GLO     RE
        SEP     R4
        DW      SPCS
EM6:    GLO     RA              ; the word: OBUF[WST[i] .. WEND[i])
        ADI     LOW(WST)
        PLO     RD
        LDI     HIGH(WST)
        ADCI    0
        PHI     RD
        LDN     RD
        PLO     RB
        GLO     RA
        ADI     LOW(WEND)
        PLO     RD
        LDI     HIGH(WEND)
        ADCI    0
        PHI     RD
        LDN     RD
        STR     R2
        GLO     RB
        SD                      ; its length
        PLO     RE
        GLO     RB
        ADI     LOW(OBUF)
        PLO     RD
        LDI     HIGH(OBUF)
        ADCI    0
        PHI     RD
EM7:    GLO     RE
        LBZ     EM8
        LDA     RD
        STR     RF
        INC     RF
        DEC     RE
        LBR     EM7
EM8:    INC     RA
        LBR     EM4
EM9:    LOAD    RD, NW
        LDI     0
        STR     RD
        LOAD    RD, OLEN
        LDI     0
        STR     RD
        LOAD    RD, OVIS
        LDI     0
        STR     RD
        LOAD    RD, TI
        LDI     NOTI
        STR     RD
        LBR     LINEO

; ==== LINEO: the line LBUF .. RF out as a page's line (the header first at a page's top; the page's end
;      after its last line)
LINEO:  LOAD    RD, LEND
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, LSTART      ; (from LBUF)
        LDI     HIGH(LBUF)
        STR     RD
        INC     RD
        LDI     LOW(LBUF)
        STR     RD
        LOAD    RD, KEEPING
        LDN     RD
        LBZ     OUTL
; a display being kept: the line onto KBUF (first the kept ones out, if KBUF is full: 60 lines, 3000 bytes)
        LOAD    RD, KNEW        ; (its end: FLUSH uses LEND)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GLO     RF              ; RB = its length
        SMI     LOW(LBUF)
        PLO     RB
        GHI     RF
        SMBI    HIGH(LBUF)
        PHI     RB
        LOAD    RD, KEPTN
        LDN     RD
        XRI     60
        LBZ     LK1
        INC     RD              ; KEPTB + length + 1 > 3000?
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        INC     RA
        GLO     RB
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GHI     RB
        STR     R2
        GHI     RA
        ADC
        PHI     RA
        GLO     RA
        SMI     LOW(3001)
        GHI     RA
        SMBI    HIGH(3001)
        LBNF    LK2
LK1:    SEP     R4
        DW      FLUSH
LK2:    LOAD    RD, KPTR        ; LBUF .. LEND -> KPTR, a 0
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, KNEW
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RF, LBUF
        LDI     0
        PHI     RB              ; RB = bytes (with the 0)
        PLO     RB
LK3:    GHI     RF
        STR     R2
        GHI     RC
        XOR
        LBNZ    LK4
        GLO     RF
        STR     R2
        GLO     RC
        XOR
        LBZ     LK5
LK4:    LDA     RF
        STR     RA
        INC     RA
        INC     RB
        LBR     LK3
LK5:    LDI     0
        STR     RA
        INC     RA
        INC     RB
        LOAD    RD, KPTR
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, KEPTN       ; KEPTN + 1, KEPTB + them
        LDN     RD
        ADI     1
        STR     RD
        INC     RD
        INC     RD
        LDN     RD
        STR     R2
        GLO     RB
        ADD
        STR     RD
        DEC     RD
        LDN     RD
        STR     R2
        GHI     RB
        ADC
        STR     RD
        SEP     R5
; FLUSH: the kept lines out - a new page first if they will not fit on this one
FLUSH:  LOAD    RD, KEPTN
        LDN     RD
        LBZ     FL9
        PLO     RB
        SEP     R4
        DW      PLON
        LBZ     FL2
        SEP     R4
        DW      LNOV
        LBZ     FL2
        STR     R2              ; LNO + KEPTN > BODY: a new page
        GLO     RB
        ADD
        PLO     RB
        LBDF    FL1
        SEP     R4
        DW      BODY
        STR     R2
        GLO     RB
        SD                      ; BODY - (LNO + KEPTN)
        LBDF    FL2
FL1:    LDI     0
        SEP     R4
        DW      ENDPG
FL2:    LOAD    RD, KCUR        ; each line: LSTART .. its 0
        LDI     HIGH(KBUF)
        STR     RD
        INC     RD
        LDI     LOW(KBUF)
        STR     RD
        LOAD    RD, KEPTN
        LDN     RD
        PLO     RB
        LOAD    RD, KLEFT
        GLO     RB
        STR     RD
FL3:    LOAD    RD, KLEFT
        LDN     RD
        LBZ     FL8
        SMI     1
        STR     RD
        LOAD    RD, KCUR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, LSTART
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
FL4:    LDA     RF
        LBNZ    FL4
        LOAD    RD, KCUR        ; the next one after its 0
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        DEC     RF
        LOAD    RD, LEND
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      OUTL
        LBR     FL3
FL8:    LOAD    RD, KEPTN       ; KBUF empty
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, KPTR
        LDI     HIGH(KBUF)
        STR     RD
        INC     RD
        LDI     LOW(KBUF)
        STR     RD
FL9:    SEP     R5
; OUTL: the line LSTART .. LEND out as a page's line
OUTL:   SEP     R4
        DW      PLON
        LBZ     LO2
        SEP     R4
        DW      LNOV
        LBNZ    LO2
        LOAD    RA, HE          ; a page's top: the header, 2 blank lines
        SEP     R4
        DW      TITLE
        SEP     R4
        DW      RAWT
        SEP     R4
        DW      BLANK
        SEP     R4
        DW      BLANK
LO2:    LOAD    RD, LEND
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, LSTART
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      RAW
        SEP     R4
        DW      PLON
        LBZ     HX
        SEP     R4              ; LNO + 1: the page full?
        DW      BODY
        PLO     RB
        LOAD    RD, LNO
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        GLO     RB
        XOR
        LBNZ    HX
; ENDPG: D = 1 the last page. The page's end: blank lines to its last text line, 2 more, the footer, then
;        (not the last) a form feed; PAGE + 1, LNO = 0
ENDPG:  PLO     RE
        LOAD    RD, LASTPG
        GLO     RE
        STR     RD
EP1:    SEP     R4
        DW      BODY
        PLO     RB
        SEP     R4
        DW      LNOV
        STR     R2
        GLO     RB
        SM                      ; BODY - LNO
        LBZ     EP2
        LBNF    EP2
        SEP     R4
        DW      BLANK
        LOAD    RD, LNO
        LDN     RD
        ADI     1
        STR     RD
        LBR     EP1
EP2:    SEP     R4
        DW      BLANK
        SEP     R4
        DW      BLANK
        LOAD    RA, FO
        SEP     R4
        DW      TITLE
        SEP     R4
        DW      RAWT
        LOAD    RD, LASTPG
        LDN     RD
        LBNZ    EP3
        LOAD    RD, K_RDIR      ; a form feed - into a file only: the Elf2K's BIOS stops printing to the
        LDN     RD              ;  screen after one (HW, 2026-10-30)
        XRI     1
        LBNZ    EP3
        LDI     0CH
        SEP     R4
        DW      F_TYPE
EP3:    LOAD    RD, PAGE + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, LNO
        LDI     0
        STR     RD
        SEP     R5

; SPACE: SPN blank lines, as page lines - none at a page's top (no-space)
SPACE:  LOAD    RD, SPN
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     HX
        SEP     R4
        DW      PLON
        LBZ     SP1
        SEP     R4
        DW      LNOV
        LBZ     HX
SP1:    LOAD    RD, SPN + 1
        LDN     RD
        SMI     1
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        LOAD    RF, LBUF
        SEP     R4
        DW      LINEO
        LBR     SPACE

; RAW: RF .. RC out, the spaces at its end left off, then a new line. BLANK: an empty line. RAWT: TBUF .. TEND
RAWT:   LOAD    RD, TEND
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RF, TBUF
        LBR     RAW
BLANK:  LOAD    RF, LBUF
        GHI     RF
        PHI     RC
        GLO     RF
        PLO     RC
RAW:    GHI     RF              ; the end back past spaces
        STR     R2
        GHI     RC
        XOR
        LBNZ    RW1
        GLO     RF
        STR     R2
        GLO     RC
        XOR
        LBZ     RW3
RW1:    DEC     RC
        LDN     RC
        XRI     ' '
        LBZ     RAW
        INC     RC
RW2:    GHI     RF              ; RF .. RC out
        STR     R2
        GHI     RC
        XOR
        LBNZ    RW2A
        GLO     RF
        STR     R2
        GLO     RC
        XOR
        LBZ     RW3
RW2A:   LDA     RF
        PLO     R8
        SMI     4
        LBDF    RW2P
        GLO     R8              ; a font byte: into a file \fR \fB \fI; to the screen, nothing
        XRI     1
        LBNZ    RW2B
        LDI     'R'
        LBR     RW2C
RW2B:   XRI     1 XOR 2
        LBNZ    RW2D
        LDI     'B'
        LBR     RW2C
RW2D:   LDI     'I'
RW2C:   PLO     R8
        LOAD    R9, RLET
        GLO     R8
        STR     R9
        LOAD    R9, K_RDIR
        LDN     R9
        XRI     1
        LBNZ    RW2
        LDI     5CH
        SEP     R4
        DW      F_TYPE
        LDI     'f'
        SEP     R4
        DW      F_TYPE
        LOAD    R9, RLET
        LDN     R9
        SEP     R4
        DW      F_TYPE
        LBR     RW2
RW2P:   GLO     R8
        SEP     R4
        DW      F_TYPE
        LBR     RW2
RW3:    SEP     R4
        DW      K_PCRLF
        SEP     R5

; TITLE: RA -> a 3-part title ('left'centre'right', % the page number) -> TBUF .. TEND, LL wide (none: empty)
TITLE:  LOAD    RF, TBUF
        LOAD    RD, TEND
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDN     RA
        LBZ     HX              ; no title
        SEP     R4              ; the page number's digits -> PGS (PGL of them) - first: PGDIG uses RB
        DW      PGDIG
        LOAD    RF, TBUF        ; (PGDIG used RF)
        LDN     RA
        PLO     RB              ; RB.0 = the delimiter
        SEP     R4              ; LL spaces (R7.0 = LL)
        DW      LLV
        PLO     R7
        SEP     R4
        DW      SPCS
        LOAD    RD, TEND
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        INC     RA              ; RA -> the first part
        LDI     0
        PHI     RB              ; RB.1 = the part (0 left, 1 centre, 2 right)
TT1:    LOAD    RF, PB          ; the part -> PB (% made the page number), RC = its length
        LOAD    RC, 0
TT2:    LDN     RA
        LBZ     TT5             ; the title's end
        INC     RA
        STR     R2
        GLO     RB
        XOR
        LBZ     TT5             ; the delimiter: the part's end (RA past it)
        LDX
        XRI     '%'
        LBZ     TT3
        LDX
        STR     RF
        INC     RF
        INC     RC
        LBR     TT2
TT3:    LOAD    RD, PGS         ; %: the page number
TT4:    LDA     RD
        LBZ     TT2
        STR     RF
        INC     RF
        INC     RC
        LBR     TT4
TT5:    GLO     R7              ; where it goes: RE.0 = the column, RD = characters of it skipped
        PLO     RE              ; (RE.0 = LL for a moment)
        LOAD    RD, 0
        GHI     RB
        LBZ     TT8             ; left: column 0
        XRI     1
        LBNZ    TT6
        GHI     RC              ; centre: (LL - length) / 2, 0 if not above 0
        LBNZ    TT7
        GLO     RC
        STR     R2
        GLO     RE
        SM
        LBNF    TT7
        SHR
        PLO     RE
        LBR     TT9
TT6:    GHI     RC              ; right: LL - length; past the left edge: the first characters skipped
        LBNZ    TT6A
        GLO     RC
        STR     R2
        GLO     RE
        SM
        LBNF    TT6A
        PLO     RE
        LBR     TT9
TT6A:   GLO     RE              ; RD = length - LL
        STR     R2
        GLO     RC
        SM
        PLO     RD
        GHI     RC
        SMBI    0
        PHI     RD
TT7:    LDI     0
        PLO     RE
        LBR     TT9
TT8:    LDI     0
        PLO     RE
TT9:    LOAD    RF, PB          ; RF = PB + skipped; RC = PB + length (the end)
        GLO     RC
        ADI     LOW(PB)
        PLO     RC
        GHI     RC
        ADCI    HIGH(PB)
        PHI     RC
        GLO     RD
        STR     R2
        GLO     RF
        ADD
        PLO     RF
        GHI     RD
        STR     R2
        GHI     RF
        ADC
        PHI     RF
        GLO     RE              ; RD -> TBUF + the column
        ADI     LOW(TBUF)
        PLO     RD
        LDI     HIGH(TBUF)
        ADCI    0
        PHI     RD
TT10:   GLO     RE              ; while column < LL and RF < RC
        STR     R2
        GLO     R7
        SM
        LBZ     TT12
        LBNF    TT12
        GHI     RF
        STR     R2
        GHI     RC
        XOR
        LBNZ    TT11
        GLO     RF
        STR     R2
        GLO     RC
        XOR
        LBZ     TT12
TT11:   LDA     RF
        STR     RD
        INC     RD
        INC     RE
        LBR     TT10
TT12:   GHI     RB              ; the next part
        ADI     1
        PHI     RB
        XRI     3
        LBNZ    TT1
        SEP     R5
; PGDIG: PAGE in decimal, no leading zeros -> PGS (0-ended)
PGDIG:  LOAD    RD, PAGE
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC              ; RC = the page
        LOAD    RD, PGS
        SEP     R4
        DW      DECS
        LDI     0
        STR     RD
        SEP     R5
; DECS: RC in decimal at RD (RD past it). RB, RF, R8, R7.1, RE.0 used.
DECS:   LDI     0
        PLO     RE              ; RE.0 = 1 once a digit is out
        LOAD    RF, PWR
PG1:    LDA     RF              ; the next power of ten
        PHI     RB
        LDA     RF
        PLO     RB
        GHI     RB
        LBNZ    PG2
        GLO     RB
        LBZ     PG9
PG2:    LDI     0
        PHI     R7              ; R7.1 = the digit
PG3:    GLO     RB              ; RC - RB >= 0?
        STR     R2
        GLO     RC
        SM
        PLO     R8
        GHI     RB
        STR     R2
        GHI     RC
        SMB
        LBNF    PG4
        PHI     RC
        GLO     R8
        PLO     RC
        GHI     R7
        ADI     1
        PHI     R7
        LBR     PG3
PG4:    GHI     R7
        LBNZ    PG5
        GLO     RE
        LBNZ    PG5
        GLO     RB              ; a leading 0 (not the last digit): left off
        XRI     1
        LBNZ    PG1
PG5:    GHI     R7
        ADI     '0'
        STR     RD
        INC     RD
        LDI     1
        PLO     RE
        LBR     PG1
PG9:    SEP     R5
PWR:    DW      10000, 1000, 100, 10, 1, 0

; the state a run starts with (copied to VARS)
INIT:   DB      65              ; LL
        DB      0               ; IND
        DB      NOTI            ; TI
        DB      60              ; PL
        DB      1               ; FILL
        DB      1               ; ADJ
        DB      0, 0            ; CE
        DB      1               ; DIRL
        DB      0, 1            ; PAGE
        DB      0               ; LNO
        DB      0               ; NW
        DB      0               ; OLEN
        DB      0               ; LLEN
        DB      'R'             ; FCUR
        DB      'R'             ; FPRV
        DB      0               ; PFXN
        DB      0               ; OVIS
        DB      0               ; PIND
        DB      0               ; TAGN
        DB      0               ; KEEPING
        DB      0, 0, 0         ; KEPTN, KEPTB
        DW      KBUF            ; KPTR
        DB      0               ; DSAV
        DB      0,0,0,0,0,0,0,0,0,0     ; NUMS
PEND:

VARS:
LL:     DS      1
IND:    DS      1
TI:     DS      1
PL:     DS      1
FILL:   DS      1
ADJ:    DS      1
CE:     DS      2
DIRL:   DS      1
PAGE:   DS      2
LNO:    DS      1
NW:     DS      1
OLEN:   DS      1
LLEN:   DS      1
FCUR:   DS      1               ; the font (B I R), the one before
FPRV:   DS      1
PFXN:   DS      1               ; font changes waiting for the next word
OVIS:   DS      1               ; how much of OBUF shows
PIND:   DS      1               ; .ip's indent (on top of IN)
TAGN:   DS      1               ; .ip's tag waiting: its length
KEEPING: DS     1               ; a display being kept
KEPTN:  DS      1               ; KEPTN, KEPTB: in this order
KEPTB:  DS      2
KPTR:   DS      2
DSAV:   DS      1               ; DSAV, SFILL, SIND, SCE: in this order
NUMS:   DS      10              ; .nh's numbers
VARSN   EQU     $ - VARS
SFILL:  DS      1
SIND:   DS      1
SCE:    DS      2
LSTART: DS      2               ; OUTL: the line's start
KCUR:   DS      2
KLEFT:  DS      1
KNEW:   DS      2
NUMH:   DS      1               ; 1 .nh, 0 .sh
HLEV:   DS      1
HCNT:   DS      1
HPTR:   DS      2
NUMBUF: DS      8
SUHAS:  DS      1               ; SUHAS, SUF: in this order
SUF:    DS      1
SUU:    DS      1
TLB:    DS      81
TAGB:   DS      256
JMPV:   DS      3               ; C0 hh ll (set by START)
SIGN:   DS      1
BEYOND: DS      1
ARGP:   DS      2
SPN:    DS      2
RPTR:   DS      4               ; RF, RC while a line is fed
WGAP:   DS      1
WVIS:   DS      1
FLET:   DS      1
RLET:   DS      1
TCNT:   DS      1
PFXB:   DS      32
LEAD:   DS      1
WIDTH:  DS      1
WPTR:   DS      2
WLEN:   DS      1
LPTR:   DS      2
CPTR:   DS      4
JUST:   DS      1
BASE:   DS      1               ; BASE, REM, GAPS: in this order
REM:    DS      1
GAPS:   DS      1
DIRNOW: DS      1
LEND:   DS      2
TEND:   DS      2
LASTPG: DS      1
PGS:    DS      6
HE:     DS      81
FO:     DS      81
WST:    DS      140             ; each word's start in OBUF
WEND:   DS      140             ;   and end
WG:     DS      140             ;   and the spaces before it
LINE:   DS      257             ; the line read (0-ended)
OBUF:   DS      260             ; the words being filled
LBUF:   DS      400             ; a line going out (the indent + up to 255 + its spaces)
TBUF:   DS      140             ; a title line (LL wide)
PB:     DS      410             ; a title's part, % made the page number
TMPL:   DS      260             ; .B text: the line "\fB text \fP"; .sh / .nh: the heading
KBUF:   DS      3000            ; a display kept: its lines, each 0-ended
VEND:
        END
