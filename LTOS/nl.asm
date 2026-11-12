; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; nl.asm - NL.PRG: NL [options] name - the file's lines with numbers in front, as Unix nl (checked against the Mac's).
;   -b a|t|n   which lines get a number: all, those with text (the default), none
;   -n ln|rn|rz   the number left in its field, right (the default), right with leading zeros
;   -w N       the field's width (6; 1-40); a longer number is printed whole
;   -s TEXT    what goes between the number and the line (a TAB; -s ': ' or -s ". " with quotes for spaces)
;   -v N       the first number (1), -i N the step (1): 0-65535; it counts on to 16,777,215
; A line not numbered gets the field's width in spaces and the separator, as nl. Options may be joined to their
; values (-ba -nrz -w4). CR dropped, LF a new line; "NL A.TXT > B.TXT" keeps it.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
TAB     EQU     09H

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
        LOAD    RD, BMODE       ; the defaults: -b t -n rn -w 6 -v 1 -i 1 -s TAB
        LDI     'T'
        STR     RD
        INC     RD
        LDI     'R'             ; NFMT
        STR     RD
        INC     RD
        LDI     6               ; WIDTH
        STR     RD
        INC     RD
        LDI     0               ; NUM (24 bits)
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        LDI     1
        STR     RD
        INC     RD
        LDI     0               ; INCR
        STR     RD
        INC     RD
        LDI     1
        STR     RD
        INC     RD
        LDI     TAB             ; SEPB
        STR     RD
        INC     RD
        LDI     0
        STR     RD
; ---- the options
OPT:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USAGE
        XRI     '-'
        LBNZ    ONAME
        INC     RF
        LDA     RF
        ANI     0DFH
        PLO     RB              ; RB.0 = the option's letter
        SEP     R4
        DW      K_SKIPSP        ; its value, joined or after spaces
        GLO     RB
        XRI     'B'
        LBZ     OB
        GLO     RB
        XRI     'N'
        LBZ     ON
        GLO     RB
        XRI     'W'
        LBZ     OW
        GLO     RB
        XRI     'V'
        LBZ     OV
        GLO     RB
        XRI     'I'
        LBZ     OI
        GLO     RB
        XRI     'S'
        LBZ     OS
        LBR     USAGE
OB:     LDA     RF              ; -b a|t|n
        ANI     0DFH
        PLO     RB
        XRI     'A'
        LBZ     OB1
        GLO     RB
        XRI     'T'
        LBZ     OB1
        GLO     RB
        XRI     'N'
        LBNZ    USAGE
OB1:    LOAD    RD, BMODE
        GLO     RB
        STR     RD
        LBR     OEND
ON:     LDA     RF              ; -n ln|rn|rz
        ANI     0DFH
        PLO     RB
        LDA     RF
        ANI     0DFH
        PHI     RB
        GLO     RB
        XRI     'L'
        LBNZ    ON1
        GHI     RB
        XRI     'N'
        LBNZ    USAGE
        LDI     'L'
        LBR     ON3
ON1:    GLO     RB
        XRI     'R'
        LBNZ    USAGE
        GHI     RB
        XRI     'N'
        LBZ     ON2
        GHI     RB
        XRI     'Z'
        LBNZ    USAGE
        LDI     'Z'
        LBR     ON3
ON2:    LDI     'R'
ON3:    PLO     RB
        LOAD    RD, NFMT
        GLO     RB
        STR     RD
        LBR     OEND
OW:     SEP     R4              ; -w N: 1-40
        DW      NUMARG
        LBDF    USAGE
        GHI     RD
        LBNZ    USAGE
        GLO     RD
        LBZ     USAGE
        SMI     41
        LBDF    USAGE
        GLO     RD
        PLO     RB
        LOAD    RD, WIDTH
        GLO     RB
        STR     RD
        LBR     OEND
OV:     SEP     R4              ; -v N
        DW      NUMARG
        LBDF    USAGE
        LOAD    RA, NUM
        LDI     0
        STR     RA
        INC     RA
        LBR     OV1
OI:     SEP     R4              ; -i N
        DW      NUMARG
        LBDF    USAGE
        LOAD    RA, INCR
OV1:    GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        LBR     OEND
OS:     LDN     RF              ; -s TEXT: to a space, or in quotes
        LBZ     USAGE
        XRI     27H             ; '
        LBZ     OS1
        LDN     RF
        XRI     22H             ; "
        LBZ     OS1
        LDI     20H             ; no quote: a space ends it
        LBR     OS2
OS1:    LDA     RF
OS2:    PLO     RB              ; RB.0 = what ends it
        LOAD    RD, SEPB
        LDI     15
        PHI     RB              ; at most 15 characters
OS3:    LDN     RF
        LBZ     OS8
        GLO     RB
        STR     R2
        LDN     RF
        XOR
        LBZ     OS7
        LDA     RF
        STR     RD
        INC     RD
        GHI     RB
        SMI     1
        PHI     RB
        LBZ     USAGE
        LBR     OS3
OS7:    GLO     RB              ; the closing quote (a space is left for OEND)
        XRI     20H
        LBZ     OS8
        INC     RF
OS8:    LDI     0
        STR     RD
OEND:   LDN     RF              ; then a space, or the end
        LBZ     OPT
        XRI     20H
        LBNZ    USAGE
        LBR     OPT
; ---- the file
ONAME:  SEP     R4
        DW      KS_NAMEARG      ; (not there, a folder ...: the kernel says so, back to the prompt)
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, BOL
        LDI     1
        STR     RD
RD1:    SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    RDEND
        LOAD    RF, KS_DATBUF
RD2:    GHI     RC
        LBNZ    RD3
        GLO     RC
        LBZ     RD1
RD3:    DEC     RC
        LDA     RF
        XRI     0DH
        LBZ     RD2             ; CR: dropped
        XRI     0DH
        PLO     RB
        LOAD    RD, CH          ; (kept in memory: the output may be a file, which uses registers)
        GLO     RB
        STR     RD
        LOAD    RD, BOL
        LDN     RD
        LBZ     RD6
        GLO     RB              ; the start of a line
        XRI     0AH
        LBNZ    RD4
        LOAD    RD, BMODE       ; an empty line: a number with -b a only
        LDN     RD
        XRI     'A'
        LBZ     RD31
        LDI     0
        LBR     RD32
RD31:   LDI     1
RD32:   SEP     R4
        DW      PREFIX
        SEP     R4
        DW      K_PCRLF
        LBR     RD2
RD4:    LOAD    RD, BMODE       ; a line with text: a number, but with -b n
        LDN     RD
        XRI     'N'
        LBZ     RD41
        LDI     1
        LBR     RD42
RD41:   LDI     0
RD42:   SEP     R4
        DW      PREFIX
        LOAD    RD, BOL
        LDI     0
        STR     RD
RD6:    LOAD    RD, CH
        LDN     RD
        XRI     0AH
        LBZ     RD7
        LDN     RD
        SEP     R4
        DW      F_TYPE
        LBR     RD2
RD7:    SEP     R4
        DW      K_PCRLF
        LOAD    RD, BOL
        LDI     1
        STR     RD
        LBR     RD2
RDEND:  LOAD    RD, BOL         ; a last line with no LF: ended
        LDN     RD
        LBNZ    RD9
        SEP     R4
        DW      K_PCRLF
RD9:    SEP     R5

; ---- PREFIX: D = 1: the number in its field, then the separator, and the number moves on; D = 0: the field's
;      width in spaces and the separator. Keeps RF, RC (the kernel's output keeps RD, RA).
PREFIX: PLO     R9              ; (a LOAD changes D)
        LOAD    RD, PFX
        GLO     R9
        STR     RD
        LOAD    RD, WIDTH
        LDN     RD
        PHI     RA              ; RA.1 = the spaces still to go
        LOAD    RD, PFX
        LDN     RD
        LBNZ    PNUM
PB1:    GHI     RA
        LBZ     PSEP
        LDI     20H
        SEP     R4
        DW      F_TYPE
        GHI     RA
        SMI     1
        PHI     RA
        LBR     PB1
PNUM:   LOAD    RD, NUM         ; eight digits at DIGB: 10,000,000s ... (by subtracting)
        LDA     RD
        PHI     RA              ; RA.1:R9 = the number
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LOAD    RD, PWRS
        LOAD    R8, DIGB
        LDI     8
        PLO     RA
PN1:    LDA     RD              ; R7.0:RB = the power of ten
        PLO     R7
        LDA     RD
        PHI     RB
        LDA     RD
        PLO     RB
        LDI     '0'
        STR     R8
PN2:    GLO     RB
        STR     R2
        GLO     R9
        SM
        PLO     R9
        GHI     RB
        STR     R2
        GHI     R9
        SMB
        PHI     R9
        GLO     R7
        STR     R2
        GHI     RA
        SMB
        PHI     RA
        LBNF    PN3
        LDN     R8
        ADI     1
        STR     R8
        LBR     PN2
PN3:    GLO     RB              ; too far: back
        STR     R2
        GLO     R9
        ADD
        PLO     R9
        GHI     RB
        STR     R2
        GHI     R9
        ADC
        PHI     R9
        GLO     R7
        STR     R2
        GHI     RA
        ADC
        PHI     RA
        INC     R8
        DEC     RA
        GLO     RA
        LBNZ    PN1
        LOAD    R7, WIDTH       ; RA.1 = the width again
        LDN     R7
        PHI     RA
        LOAD    RD, DIGB        ; the leading zeros passed over (the last digit stays)
        LDI     7
        PLO     RA
PN4:    GLO     RA
        LBZ     PN5
        LDN     RD
        XRI     '0'
        LBNZ    PN5
        INC     RD
        DEC     RA
        LBR     PN4
PN5:    GLO     RA              ; RA.0 = its digits, RD -> the first
        ADI     1
        PLO     RA
        STR     R2              ; RA.1 = the padding: the width less the digits (none if it is longer)
        GHI     RA
        SM
        LBDF    PN6
        LDI     0
PN6:    PHI     RA
        LOAD    R7, NFMT
        LDN     R7
        XRI     'L'
        LBZ     PN8
        SEP     R4              ; rn, rz: the padding first
        DW      PAD
PN7:    LDA     RD              ; the digits
        SEP     R4
        DW      F_TYPE
        DEC     RA
        GLO     RA
        LBNZ    PN7
        LBR     PN9
PN8:    LDA     RD              ; ln: the digits, then the padding
        SEP     R4
        DW      F_TYPE
        DEC     RA
        GLO     RA
        LBNZ    PN8
        SEP     R4
        DW      PAD
PN9:    LOAD    RD, NUM+2       ; NUM + INCR
        LOAD    R7, INCR+1
        SEX     R7
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        DEC     R7
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEX     R2
PSEP:   LOAD    RD, SEPB        ; the separator
PS1:    LDA     RD
        LBZ     PS9
        SEP     R4
        DW      F_TYPE
        LBR     PS1
PS9:    SEP     R5
; PAD: RA.1 of the padding character: '0' for rz, else a space
PAD:    GHI     RA
        LBZ     PA9
        LOAD    R7, NFMT
        LDN     R7
        XRI     'Z'
        LBZ     PA1
        LDI     20H
        LBR     PA2
PA1:    LDI     '0'
PA2:    SEP     R4
        DW      F_TYPE
        GHI     RA
        SMI     1
        PHI     RA
        LBR     PAD
PA9:    SEP     R5

USAGE:  SEP     R4
        DW      K_PIN
        DB      'NL [-b a|t|n] [-n ln|rn|rz] [-w N] [-s sep] [-v N] [-i N] name',0DH,0AH
        DB      '  the lines numbered: -b which (t: those with text), -n how, -w width (6),',0DH,0AH
        DB      '  -s between (a TAB), -v the first number (1), -i the step (1)',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PWRS:   DB      098H, 096H, 080H, 00FH, 042H, 040H, 001H, 086H, 0A0H, 000H, 027H, 010H  ; 10,000,000 1,000,000 100,000 10,000
        DB      000H, 003H, 0E8H, 000H, 000H, 064H, 000H, 000H, 00AH, 000H, 000H, 001H  ; 1,000 100 10 1
        INCL    "numarg.inc"
PEND:
BMODE:  DS      1               ; 'A' 'T' 'N'      (START sets these seven in order)
NFMT:   DS      1               ; 'L' 'R' 'Z'
WIDTH:  DS      1
NUM:    DS      3
INCR:   DS      2
SEPB:   DS      16
BOL:    DS      1               ; 1: at the start of a line
CH:     DS      1
PFX:    DS      1
DIGB:   DS      8
        END
