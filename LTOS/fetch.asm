; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; fetch.asm - FETCH.PRG: FETCH [-p "prompt"] [file] - one key, no Enter needed.
;   With a file: the key goes into it (CR LF after it; a file already there is replaced). Without: the key is
;   the output - in a script, K=$(FETCH) puts it in the variable K. The key shows on the screen (the BIOS's
;   F_READ shows it), then a new line. Enter gives nothing (an empty line); Ctrl-C: nothing kept, status 1.
;   The kernel's fixed calls only (kapi.inc).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  SEP     R4              ; -p "prompt": on the screen (RF past it)
        DW      PROMPT
        SEP     R4
        DW      K_IN
        PLO     RC              ; RC.0 = the key (a call uses RE.0)
        XRI     03H
        LBZ     FQ
        LOAD    RD, LBUF
        GLO     RC
        STR     RD
        LDI     0
        PLO     RB              ; RB.0 = 1: a key to keep (not Enter)
        GLO     RC
        XRI     0DH
        LBZ     FT2
        XRI     0DH XOR 0AH
        LBZ     FT2
        LDI     1
        PLO     RB
FT2:    LOAD    RD, LLEN
        GLO     RB
        STR     RD
        SEP     R4
        DW      TTYNL
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    INFILE
        LOAD    RD, K_STAT
        LDI     0
        STR     RD
        LOAD    RD, K_RDIR      ; the output on the screen: it is there already
        LDN     RD
        LBZ     FT9
        LOAD    RD, LLEN
        LDN     RD
        LBZ     FT3
        LOAD    RD, LBUF
        LDN     RD
        SEP     R4
        DW      K_OUT
FT3:    SEP     R4
        DW      K_PCRLF
FT9:    SEP     R5
INFILE: LOAD    RD, NAMEB       ; the key (if one), CR LF after it
        SEP     R4
        DW      K_PARSE
        LBDF    BADNM
        LOAD    RD, LLEN
        LDN     RD
        PLO     RB
        LOAD    RA, LBUF
        GLO     RB
        STR     R2
        GLO     RA
        ADD
        PLO     RD
        GHI     RA
        ADCI    0
        PHI     RD
        LDI     0DH
        STR     RD
        INC     RD
        LDI     0AH
        STR     RD
        GLO     RB
        ADI     2
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    RD, NAMEB
        SEP     R4
        DW      K_SAVER
        LBDF    SVERR
        LOAD    RD, K_STAT
        LDI     0
        STR     RD
        SEP     R5
FQ:     SEP     R4              ; Ctrl-C: nothing kept, status 1
        DW      TTYNL
QUIT1:  LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
BADNM:  SEP     R4
        DW      K_PIN
        DB      'Not a file name - nothing saved.',0DH,0AH,0
        LBR     QUIT1
SVERR:  SEP     R4
        DW      K_PIN
        DB      'The file could not be saved.',0DH,0AH,0
        LBR     QUIT1

        INCL    "ttyin.inc"
LBUF:   DS      3
NAMEB:  DS      11
LLEN:   DS      1
PEND:
        END
