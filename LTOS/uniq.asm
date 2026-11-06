; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; uniq.asm - UNIQ.PRG: UNIQ [-c] [-d] name - the file's lines, a line the same as the one before it left out.
;   -c  each line with how many times it came, in a row (7 wide, then a space)
;   -d  only the lines that came more than once in a row
; Lines: CR dropped, up to 255 characters kept (as EROFF). verify_uniqsort.py holds it to Python's answer.
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
        SEP     R4
        DW      KS_MNTCHK
        LOAD    RD, OPTC        ; OPTC, OPTD, HAVE, LEN = 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
OPT1:   SEP     R4              ; the options: -c -d (together or apart)
        DW      K_SKIPSP
        LDN     RF
        XRI     '-'
        LBNZ    OPT9
        INC     RF
OPT2:   LDN     RF
        LBZ     USE
        XRI     ' '
        LBZ     OPT1
        LDA     RF
        ORI     20H
        XRI     'c'
        LBNZ    OPT3
        LOAD    RD, OPTC
        LBR     OPT4
OPT3:   XRI     'c' XOR 'd'
        LBNZ    USE
        LOAD    RD, OPTD
OPT4:   LDI     1
        STR     RD
        LBR     OPT2
OPT9:   LDN     RF
        LBZ     USE
        SEP     R4
        DW      KS_NAMEARG      ; (not there, a folder ...: the kernel says so, back to the prompt)
        SEP     R4
        DW      KS_FOPEN
; ---- the file a sector at a time; each line to ONE
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
        XRI     0AH
        PLO     RE              ; RE.0 = the character
        LOAD    RD, LEN
        LDN     RD
        XRI     0FFH
        LBZ     RD2             ; 255 kept: the rest dropped
        XRI     0FFH
        ADI     LOW(CUR)
        PLO     RB
        LDI     HIGH(CUR)
        ADCI    0
        PHI     RB
        GLO     RE
        STR     RB
        LDN     RD
        ADI     1
        STR     RD
        LBR     RD2
RDLF:   LOAD    RD, RPTR        ; a line: ONE (RF, RC kept around it)
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
        SEP     R4
        DW      ONE
        LOAD    RD, RPTR
        LDA     RD
        PHI     RF
        LDA     RD
        PLO     RF
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LBR     RD2
REOF:   LOAD    RD, LEN         ; a last line with no LF
        LDN     RD
        LBZ     RE1
        SEP     R4
        DW      ONE
RE1:    LOAD    RD, HAVE        ; the last line kept
        LDN     RD
        LBZ     RE9
        SEP     R4
        DW      PUTPREV
RE9:    SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'UNIQ [-c] [-d] name - the lines, a repeat of the line before left out',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5

; ONE: the line in CUR (LEN characters): the same as PREV: COUNT + 1; else PREV out, CUR -> PREV, COUNT = 1
ONE:    LOAD    RD, LEN         ; CUR 0-ended; LEN = 0 for the next
        LDN     RD
        ADI     LOW(CUR)
        PLO     RF
        LDI     HIGH(CUR)
        ADCI    0
        PHI     RF
        LDI     0
        STR     RF
        STR     RD
        LOAD    RD, HAVE
        LDN     RD
        LBZ     ON3
        LOAD    RF, CUR         ; the same as PREV?
        LOAD    RD, PREV
ON1:    LDA     RD
        STR     R2
        LDN     RF
        XOR
        LBNZ    ON2
        LDA     RF
        LBNZ    ON1
        LOAD    RD, COUNT + 1   ; the same: COUNT + 1 (at 65535 it stays)
        LDN     RD
        ADI     1
        PLO     RE
        DEC     RD
        LDN     RD
        ADCI    0
        LBDF    ON9
        STR     RD
        INC     RD
        GLO     RE
        STR     RD
ON9:    SEP     R5
ON2:    SEP     R4
        DW      PUTPREV
ON3:    LOAD    RF, CUR         ; CUR -> PREV, COUNT = 1, HAVE
        LOAD    RD, PREV
ON4:    LDA     RF
        STR     RD
        INC     RD
        LBNZ    ON4
        LOAD    RD, COUNT
        LDI     0
        STR     RD
        INC     RD
        LDI     1
        STR     RD
        LOAD    RD, HAVE
        LDI     1
        STR     RD
        SEP     R5

; PUTPREV: PREV out (-d: only if COUNT > 1; -c: the count first)
PUTPREV: LOAD   RD, OPTD
        LDN     RD
        LBZ     PP1
        LOAD    RD, COUNT       ; -d: COUNT 1 is left out
        LDA     RD
        LBNZ    PP1
        LDN     RD
        XRI     1
        LBZ     ON9
PP1:    LOAD    RD, OPTC
        LDN     RD
        LBZ     PP3
        LOAD    RD, COUNT       ; -c: the count, 7 wide
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDI     6               ; spaces: 6 less one for each digit past the first
        PLO     RB
        LOAD    RF, TENS
PP2:    LDA     RF              ; RA >= this power of ten: one space less
        PHI     RC
        LDA     RF
        PLO     RC
        GHI     RC
        LBZ     PP2A
PP2B:   GLO     RC
        STR     R2
        GLO     RA
        SM
        GHI     RC
        STR     R2
        GHI     RA
        SMB
        LBNF    PP2C
        DEC     RB
        LBR     PP2
PP2A:   GLO     RC
        LBNZ    PP2B
PP2C:   GLO     RB
        LBZ     PP2E
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        DEC     RB
        LBR     PP2C
PP2E:   GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
        SEP     R4
        DW      K_PDEC
        LDI     ' '
        SEP     R4
        DW      F_TYPE
PP3:    LOAD    RF, PREV
PP4:    LDA     RF
        LBZ     PP5
        SEP     R4
        DW      F_TYPE
        LBR     PP4
PP5:    SEP     R4
        DW      K_PCRLF
        SEP     R5
TENS:   DW      10, 100, 1000, 10000, 0
PEND:
OPTC:   DS      1               ; OPTC, OPTD, HAVE, LEN: in this order
OPTD:   DS      1
HAVE:   DS      1
LEN:    DS      1
COUNT:  DS      2
RPTR:   DS      4
CUR:    DS      257
PREV:   DS      257
        END
