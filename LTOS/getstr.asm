; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; getstr.asm - GETSTR.PRG: GETSTR [-p "prompt"] [file] - a line typed (Backspace rubs out, Enter ends it).
;   With a file: the line goes into it (CR LF after it; a file already there is replaced). Without: the line is
;   the output - in a script, NAME=$(GETSTR) puts it in the variable NAME. What is typed shows on the screen
;   either way (K_TTY), so only the line itself goes into a file or a variable.
;   The line is the BIOS's F_INPUTL (it shows the keys). Ctrl-C: nothing kept, status 1. The kernel's fixed
;   calls only (kapi.inc): it outlives a new kernel.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
LMAX    EQU     250             ; characters at most

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  SEP     R4              ; -p "prompt": on the screen (RF past it)
        DW      PROMPT
        GHI     RF              ; (the file's name, if one, for after)
        STXD
        GLO     RF
        STXD
        LOAD    RF, LBUF        ; the BIOS's line (it shows what is typed; Backspace)
        LOAD    RC, LMAX
        SEP     R4
        DW      F_INPUTL
        LBDF    GSQ             ; Ctrl-C
        LOAD    RA, LBUF        ; how many
        LDI     0
        PLO     RB
GS2:    LDA     RA
        LBZ     GS9
        INC     RB
        LBR     GS2
GS9:    LOAD    RD, LLEN        ; a new line on the screen
        GLO     RB
        STR     RD
        SEP     R4
        DW      TTYNL
        IRX                     ; a file named?
        LDXA
        PLO     RF
        LDX
        PHI     RF
; ---- the line (RB.0 long, at LBUF): into the file named, or the output
DONE:   SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    INFILE
        LOAD    RD, K_STAT
        LDI     0
        STR     RD
        LOAD    RD, K_RDIR      ; the output on the screen: it is there already
        LDN     RD
        LBZ     DN9
        LOAD    RA, LLEN
        LDN     RA
        PLO     RB
        LOAD    RA, LBUF
DN1:    GLO     RB
        LBZ     DN2
        LDA     RA
        SEP     R4
        DW      K_OUT
        DEC     RB
        LBR     DN1
DN2:    SEP     R4
        DW      K_PCRLF
DN9:    SEP     R5
INFILE: LOAD    RD, NAMEB       ; the line: CR LF after it
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
GSQ:    INC     R2              ; Ctrl-C: nothing kept, status 1 (the name's place off the stack)
        INC     R2
        SEP     R4
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
LBUF:   DS      LMAX + 2
NAMEB:  DS      11
LLEN:   DS      1
PEND:
        END
