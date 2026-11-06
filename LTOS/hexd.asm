; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; hexd.asm - HEX.PRG: HEX name - any file in hex and text, 18 bytes a line (it fits 80 columns), read a sector
; at a time (any size). A screen (22 lines) at a time: the space bar goes on a screen, Enter one line,
; Q (Ctrl-C, Esc) stops.  The offset has 4 hex digits, or 6 for a file of 64 KB or more (79 columns both):
;   0000  4C 54 4F 53 20 30 2E 34 20 2D 20 74 68 65 20 63 6F 6D  LTOS 0.4 - the com
;   012340 4C 54 4F 53 20 30 2E 34 20 2D 20 74 68 65 20 63 6F 6D LTOS 0.4 - the com
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
PERLN   EQU     18              ; bytes a line
PAGE    EQU     22              ; lines a screen

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
        LDN     RF
        LBZ     USE
        SEP     R4              ; the file (or a message, and back to the prompt)
        DW      KS_NAMEARG
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, VARS        ; OFS (3), SREM (2), LINES, WIDE, EOFF, BROKE: 0
        LDI     9
        PLO     RB
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST1
        LOAD    RD, KS_DSIZE    ; 64 KB or more: 6-digit offsets
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     ST2
        LOAD    RD, WIDE
        LDI     1
        STR     RD
ST2:    LOAD    RD, KS_FNAME    ; NAME.EXT, its size
        SEP     R4
        DW      KS_PFNAMD
        SEP     R4
        DW      K_PIN
        DB      ', ',0
        LOAD    RD, KS_DSIZE
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      ' bytes',0
        SEP     R4
        DW      NEWLN
; ---- a line: up to 18 bytes into LBUF (RB.0 = how many)
LINE:   LOAD    R9, LBUF
        LDI     0
        PLO     RB
FL1:    GLO     RB
        XRI     PERLN
        LBZ     FL3
        SEP     R4
        DW      GETB
        LBDF    FL2
        STR     R9
        INC     R9
        INC     RB
        LBR     FL1
FL2:    LOAD    RD, EOFF        ; the end of the file
        LDI     1
        STR     RD
FL3:    GLO     RB
        LBZ     DONE
        LOAD    RD, NLINE       ; (NLINE = the count, kept over the pause)
        GLO     RB
        STR     RD
        SEP     R4              ; a full screen: wait first
        DW      PAUSE
        LOAD    RD, WIDE        ; the offset: 6 or 4 hex digits, then 1 or 2 spaces
        LDN     RD
        PLO     R8
        LOAD    R9, OFS
        LDA     R9
        PLO     R7
        GLO     R8
        LBZ     OF1
        GLO     R7
        SEP     R4
        DW      HEX2
OF1:    LDA     R9
        SEP     R4
        DW      HEX2
        LDN     R9
        SEP     R4
        DW      HEX2
        SEP     R4
        DW      SPACE
        GLO     R8
        LBNZ    OF2
        SEP     R4
        DW      SPACE
OF2:    LOAD    RD, NLINE       ; the bytes in hex; blanks after a short last line
        LDN     RD
        PLO     R8
        LDI     PERLN
        PLO     RB
        LOAD    R9, LBUF
HX1:    GLO     R8
        LBZ     HX2
        DEC     R8
        LDA     R9
        SEP     R4
        DW      HEX2
        LBR     HX3
HX2:    SEP     R4
        DW      SPACE
        SEP     R4
        DW      SPACE
HX3:    SEP     R4
        DW      SPACE
        DEC     RB
        GLO     RB
        LBNZ    HX1
        LOAD    RD, WIDE        ; then a space (4-digit offsets only: 79 columns either way) and the text,
        LDN     RD              ;  a dot for anything not printable
        LBNZ    TX0
        SEP     R4
        DW      SPACE
TX0:    LOAD    RD, NLINE
        LDN     RD
        PLO     R8
        LOAD    R9, LBUF
TX1:    LDA     R9
        PLO     R7
        SMI     20H
        LBNF    TX2
        GLO     R7
        SMI     7FH
        LBDF    TX2
        GLO     R7
        LSKP
TX2:    LDI     '.'
        SEP     R4
        DW      F_TYPE
        DEC     R8
        GLO     R8
        LBNZ    TX1
        SEP     R4
        DW      NEWLN
        LOAD    R9, OFS+2       ; the offset + 18
        LDN     R9
        ADI     PERLN
        STR     R9
        DEC     R9
        LDN     R9
        ADCI    0
        STR     R9
        DEC     R9
        LDN     R9
        ADCI    0
        STR     R9
        LOAD    RD, EOFF
        LDN     RD
        LBZ     LINE
DONE:   LOAD    RD, BROKE
        LDN     RD
        LBZ     DN9
        SEP     R4
        DW      K_PIN
        DB      '** the file could not be read to its end **',0DH,0AH,0
DN9:    SEP     R5

; GETB: the file's next byte in D, DF = 0; DF = 1 at its end. (SPTR / SREM: where in DATBUF, bytes left)
GETB:   LOAD    RD, SREM
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
GB1:    GHI     RC
        LBNZ    GB2
        GLO     RC
        LBNZ    GB2
        GHI     R9              ; the next sector (R9, RB kept)
        STXD
        GLO     R9
        STXD
        GHI     RB
        STXD
        GLO     RB
        STXD
        SEP     R4
        DW      KS_FREAD        ; RC = its bytes; DF = 1: the end (D = 2: the chain is broken)
        PLO     R7
        IRX
        LDXA
        PLO     RB
        LDXA
        PHI     RB
        LDXA
        PLO     R9
        LDX
        PHI     R9
        LBDF    GBE
        LOAD    RD, SPTR
        LDI     HIGH(KS_DATBUF)
        STR     RD
        INC     RD
        LDI     LOW(KS_DATBUF)
        STR     RD
        LBR     GB1
GBE:    GLO     R7              ; (DF still 1)
        XRI     2
        LBNZ    GBE2
        LOAD    RD, BROKE
        LDI     1
        STR     RD
GBE2:   LDI     1
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
        PHI     RF
        LDN     RD
        PLO     RF
        LDA     RF
        PLO     R7
        GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        LDI     0               ; DF = 0, D = the byte
        SHR
        GLO     R7
        SEP     R5

; HEX2: D as two hex digits.  SPACE: a space.  (F_TYPE keeps the registers these loops use.)
HEX2:   PLO     R7
        SHR
        SHR
        SHR
        SHR
        SEP     R4
        DW      NIB
        GLO     R7
        ANI     0FH
NIB:    ADI     '0'
        PLO     RE
        SMI     '9'+1
        LBNF    NB1
        ADI     'A'
        PLO     RE
NB1:    GLO     RE
        SEP     R4
        DW      F_TYPE
        SEP     R5
SPACE:  LDI     ' '
        SEP     R4
        DW      F_TYPE
        SEP     R5
; NEWLN: CR LF, counted.  PAUSE: after a full screen, wait: space - the next screen, Enter - one more line,
; Q / Ctrl-C / Esc - stop.
NEWLN:  LDI     0DH
        SEP     R4
        DW      F_TYPE
        LDI     0AH
        SEP     R4
        DW      F_TYPE
        LOAD    RD, LINES
        LDN     RD
        ADI     1
        STR     RD
        SEP     R5
PAUSE:  LOAD    RD, K_RDIR      ; the output in a file: no pages
        LDN     RD
        LBNZ    PA9
        LOAD    RD, LINES
        LDN     RD
        XRI     PAGE
        LBNZ    PA9
        SEP     R4
        DW      K_PIN
        DB      '-- space: more, Enter: a line, Q: stop --',0
        SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      K_PIN
        DB      0DH,'                                         ',0DH,0
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
        LOAD    RD, LINES       ; Enter: one more line, then wait again; anything else: a new screen
        GLO     RB
        XRI     0DH
        LBNZ    PA1
        LDI     PAGE - 1
        LSKP
PA1:    LDI     0
        STR     RD
PA9:    SEP     R5

USE:    SEP     R4
        DW      K_PIN
        DB      'HEX name - any file in hex and text, 18 bytes a line, a screen at a time',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
VARS:                           ; (not in the file)
OFS:    DS      3               ; the offset (big-endian)
SREM:   DS      2               ; the bytes left in DATBUF
LINES:  DS      1
WIDE:   DS      1
EOFF:   DS      1
BROKE:  DS      1
NLINE:  DS      1
SPTR:   DS      2
LBUF:   DS      PERLN
        END
