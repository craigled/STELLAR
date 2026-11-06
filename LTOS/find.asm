; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; find.asm - FIND.PRG: FIND name - every file and folder on the card with that name, as a full path (as
;   Linux's find -name). Wildcards * and ?; no dot means any extension (FIND NOTE finds NOTE.TXT). The whole
;   card, from the root, a screen at a time. Folders end with a /.
;
;       FIND *.STL      /GAMES/LW2.STL ...       FIND DOCS     /DOCS/
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
WMAX    EQU     8
PMAXL   EQU     120

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
        LOAD    RD, LINES       ; LINES, FOUND (2): 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LDN     RF
        LBZ     USE
        GHI     RF              ; a dot in it?
        PHI     RC
        GLO     RF
        PLO     RC
        LDI     0
        PHI     RA
FA1:    LDA     RC
        LBZ     FA2
        XRI     ' '
        LBZ     FA2
        XRI     0EH
        LBNZ    FA1
        LDI     1
        PHI     RA
FA2:    LOAD    RD, UPAT        ; the name: 11 bytes, * -> ?s
        SEP     R4
        DW      KS_PNAME
        LBDF    KS_PPERR
        GHI     RA
        LBNZ    FA3
        LOAD    RD, UPAT+8      ; no dot: any extension
        LDI     '?'
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
FA3:    LOAD    RD, KS_WDIR     ; from the root: PATH = "/"
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, PATH
        LDI     '/'
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RD, PLENG
        LDI     1
        STR     RD
        SEP     R4
        DW      WALK
        LOAD    RD, FOUND
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    FA9
        SEP     R4
        DW      K_PIN
        DB      'Nothing by that name.',0DH,0AH,0
FA9:    SEP     R5

; W_ENTRY: its name against UPAT ('?' matches anything): the path, the name (a folder: and a /)
W_ENTRY: LOAD   RD, WENT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, UPAT
        LDI     11
        PLO     RB
WN1:    LDA     RD
        XRI     '?'
        LBZ     WN2
        XRI     '?'
        STR     R2
        LDN     RC
        XOR
        LBNZ    WN9
WN2:    INC     RC
        DEC     RB
        GLO     RB
        LBNZ    WN1
        LOAD    RA, PATH
        SEP     R4
        DW      PRSTR
        LOAD    RD, WENT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RF, NBUF
        SEP     R4
        DW      NM2TX
        LOAD    RA, NBUF
        SEP     R4
        DW      PRSTR
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBZ     WN3
        LDI     '/'
        SEP     R4
        DW      F_TYPE
WN3:    SEP     R4
        DW      NEWLN
        LOAD    RD, FOUND
        INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
WN9:    SEP     R5
W_INTO: SEP     R5
W_OUT:  SEP     R5

USE:    SEP     R4
        DW      K_PIN
        DB      'FIND name - every file or folder on the card by that name (FIND *.STL)',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "tools.inc"
        INCL    "walk.inc"
PEND:
LINES:  DS      1               ; LINES, FOUND: in this order
FOUND:  DS      2
UPAT:   DS      11
NBUF:   DS      14
WDEPTH: DS      1               ; WDEPTH, WIDX: in this order
WIDX:   DS      2
WCL:    DS      2
WENT:   DS      2
PLENG:  DS      1
PATH:   DS      PMAXL + 14
WSTK:   DS      WMAX * 5
        END
