; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; mv.asm - MV.PRG: MV from to - a file or a folder to another folder, and / or a new name.
;   MV A.TXT DOCS        into DOCS (a folder there), keeping its name
;   MV A.TXT DOCS/B.TXT  into DOCS as B.TXT        MV DOCS/B.TXT ..   up a level
;   MV *.STL GAMES       every file that matches, into the folder GAMES (each named as it goes; one with a
;                        name GAMES has already is left where it is)
; The entry moves; the data stays where it is. A folder moved: its '..' entry points at its new folder. A folder
; cannot go into itself or a folder inside it. The new entry is written first, then the old one goes.
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
        DW      SRCARG          ; SNM in SDIR (WILD: a pattern)
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        SEP     R4
        DW      DSTARG          ; DNM in DDIR (ISDIR: DDIR is the folder named)
        LOAD    RD, WILD
        LDN     RD
        LBNZ    MW
; ---- one: MV A B
        LOAD    RD, ISDIR       ; into a folder: the same name
        LDN     RD
        LBZ     M1
        LOAD    RD, SNM
        LOAD    RC, DNM
        SEP     R4
        DW      CP11
M1:     LOAD    RD, SNM
        LOAD    RC, SNM1
        SEP     R4
        DW      CP11
        SEP     R4
        DW      MOVE1
        LBNF    DONE
        XRI     3
        LBZ     NOF
        XRI     3 XOR 1
        LBZ     TAKEN
        XRI     1 XOR 2
        LBZ     INTO
        LBR     KS_CARDF
NOF:    LOAD    RD, SNM         ; (the kernel's "There is no file" prints FNAME)
        LOAD    RC, KS_FNAME
        SEP     R4
        DW      CP11
        LBR     KS_NOFILE
TAKEN:  SEP     R4
        DW      K_PIN
        DB      'There is already a ',0
        LOAD    RD, DNM
        SEP     R4
        DW      KS_PFNAMD
        SEP     R4
        DW      K_PCRLF
DONE:   SEP     R5
INTO:   SEP     R4
        DW      K_PIN
        DB      'A folder cannot go into itself.',0DH,0AH,0
        SEP     R5
; ---- many: MV *.STL GAMES - each file that matches; NSKIP = the ones left behind (a name already there)
MW:     LOAD    RD, ISDIR
        LDN     RD
        LBZ     NOTDIR
        SEP     R4
        DW      SAMED
        LBDF    SAMEDIR
        LOAD    RD, NSKIP
        LDI     0
        STR     RD
        LOAD    RD, NDONE
        LDI     0
        STR     RD
        INC     RD
        STR     RD
MW1:    SEP     R4              ; the next one (moved ones are gone from SDIR: the walk starts again)
        DW      MATCHN
        LBDF    MW9
        GHI     RF              ; CUR = its name; it keeps it
        PHI     RD
        GLO     RF
        PLO     RD
        LOAD    RC, CUR
        SEP     R4
        DW      CP11
        SEP     R4
        DW      PCUR
        LOAD    RD, CUR         ; SNM, DNM = CUR (SNM is the pattern: kept in PATN)
        LOAD    RC, SNM1
        SEP     R4
        DW      CP11
        LOAD    RD, CUR
        LOAD    RC, DNM
        SEP     R4
        DW      CP11
        SEP     R4
        DW      MOVE1
        LBNF    MW2
        XRI     1
        LBNZ    KS_CARDF        ; (the card failed)
        SEP     R4
        DW      K_PIN
        DB      ' - the folder has one already: left where it is',0DH,0AH,0
        LOAD    RD, NSKIP
        LDN     RD
        ADI     1
        STR     RD
        LBR     MW1
MW2:    SEP     R4
        DW      K_PCRLF
        LOAD    RD, NDONE+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     MW1
MW9:    LOAD    RD, NDONE
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
        DB      ' moved.',0DH,0AH,0
        SEP     R5

        INCL    "move1.inc"

USE:    SEP     R4
        DW      K_PIN
        DB      'MV from to  (to: a folder, a new name, or a folder/name; MV *.STL GAMES: all into a folder)',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
DOTDOT: DB      '..         '
        INCL    "wild.inc"
SNM1:   DS      11              ; MOVE1's one name (SNM may be a pattern)
MCL:    DS      2
ENT:    DS      32
PEND:
        END
