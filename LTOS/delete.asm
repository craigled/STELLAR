; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; delete.asm - DELETE.PRG: DELETE names - files moved to /TRASH (made if it is not there), not deleted. Wildcards;
; more than one name. A name /TRASH has already: the older one there goes. Folders are left alone. Back again:
; MV /TRASH/NAME .   For good: EMPTY.   (DEL and RM delete at once.)
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
        LDN     RF
        LBZ     USE
        SEP     R4
        DW      SAVEARG
        SEP     R4
        DW      TRASHD          ; DDIR = /TRASH
        LOAD    RD, NDONE
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, ARGP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
NXT:    SEP     R4              ; the next name: SNM in SDIR
        DW      SRCARG
        SEP     R4
        DW      SAVEARG
        SEP     R4
        DW      SAMED
        LBDF    INTR
        LOAD    RD, NSKIP
        LDI     0
        STR     RD
        LOAD    RD, FOUND
        LDI     0
        STR     RD
D1:     SEP     R4              ; (moved ones are gone from SDIR: the walk starts again)
        DW      MATCHN
        LBDF    D8
        GHI     RF              ; CUR = its name; SNM1, DNM too (SNM is the pattern)
        PHI     RD
        GLO     RF
        PLO     RD
        LOAD    RC, CUR
        SEP     R4
        DW      CP11
        LOAD    RD, CUR
        LOAD    RC, SNM1
        SEP     R4
        DW      CP11
        LOAD    RD, CUR
        LOAD    RC, DNM
        SEP     R4
        DW      CP11
D2:     SEP     R4
        DW      MOVE1
        LBNF    D3
        XRI     1
        LBNZ    KS_CARDF
        LOAD    RD, DDIR        ; the trash has that name: the older one goes
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, DNM
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_CARDF
        SEP     R4
        DW      KS_DELENT
        LBDF    KS_CARDF
        LBR     D2
D3:     LOAD    RD, FOUND
        LDI     1
        STR     RD
        LOAD    RD, NDONE+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     D1
D8:     LOAD    RD, FOUND
        LDN     RD
        LBNZ    NA
        SEP     R4
        DW      K_PIN
        DB      'No file matches.',0DH,0AH,0
NA:     LOAD    RD, ARGP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    NXT
        LOAD    RD, NDONE
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     FIN
        LOAD    RD, NDONE
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' moved to /TRASH.',0DH,0AH,0
FIN:    SEP     R5
INTR:   SEP     R4
        DW      K_PIN
        DB      'That is in the trash already: EMPTY deletes it for good.',0DH,0AH,0
        LBR     NA
SAVEARG: LOAD   RD, ARGP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R5
; TRASHD: DDIR = /TRASH's first cluster; not there: made first
TRASHD: SEP     R4
        DW      TFIND
        LBNF    TD2
        LOAD    RD, TRNAME
        LOAD    RC, KS_FNAME
        SEP     R4
        DW      CP11
        SEP     R4
        DW      MK1
        SEP     R4
        DW      TFIND
        LBDF    KS_CARDF
TD2:    GLO     RF              ; a folder?
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDN     RF
        ANI     10H
        LBZ     TDF
        LOAD    RD, KS_DCLUS
        LOAD    RC, DDIR
        LBR     CP2
TDF:    SEP     R4
        DW      K_PIN
        DB      'A file called TRASH is in the way.',0DH,0AH,0
        LBR     K_MAIN
TFIND:  LOAD    RD, KS_WDIR     ; the root
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, TRNAME
        LBR     KS_FINDN
USE:    SEP     R4
        DW      K_PIN
        DB      'DELETE names  (moved to /TRASH; EMPTY deletes them for good)',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
TRNAME: DB      'TRASH      '
DOTDOT: DB      '..         '
        INCL    "move1.inc"
        INCL    "mkfold.inc"
        INCL    "wild.inc"
SNM1:   DS      11              ; MOVE1's one name (SNM may be a pattern)
MCL:    DS      2
ENT:    DS      32
ARGP:   DS      2
FOUND:  DS      1
PEND:
        END
