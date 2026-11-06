; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; tools.inc - shared by WC, GREP, FIND, TREE, SEND and FSCK (INCL'd after a program's own code).
; A program that includes it defines LINES (DS 1).
;
;   PATARG  RF -> one word, a path or pattern -> KS_PAT and KS_WDIR, by DIR's rules: a folder's name (or
;           "GAMES/") means all of it; no dot means any extension ("S*" = S*.*). RF ends past the word.
;           A bad name: the kernel says why, and back to the prompt.
;   NEWLN   CR LF, counted; after 22 lines it waits: a key goes on, Q (Ctrl-C, Esc) stops - back to the prompt.
;   PRSTR   the 0-ended text at RA (RA ends past its 0)
;   INC32   the 4 bytes at RD (big-endian) + 1

PATARG: LOAD    RD, KS_PAT
        GHI     RF              ; is there a dot? (no dot: "S*" means S*.*, as in DOS)
        PHI     RC
        GLO     RF
        PLO     RC
        LDI     0
        PHI     RA              ; RA.1 = 1: a dot (PARSE keeps RA.1)
TPA1:   LDA     RC
        LBZ     TPA2
        XRI     ' '
        LBZ     TPA2
        XRI     0EH             ; (' ' xor '.')
        LBNZ    TPA1
        LDI     1
        PHI     RA
TPA2:   SEP     R4
        DW      KS_PARSE        ; (a path: WDIR = its folder)
        LBNF    TPA3
        XRI     3
        LBZ     TPALL           ; "GAMES/": all of that folder
        XRI     3
        LBR     KS_PPERR
TPA3:   LOAD    RD, KS_PAT      ; a folder's name (no wildcards): all of it
        LDI     11
        PLO     RB
TPA4:   LDA     RD
        XRI     '?'
        LBZ     TPA5
        DEC     RB
        GLO     RB
        LBNZ    TPA4
        GHI     RF              ; (FOLDIN uses RF)
        STXD
        GLO     RF
        STXD
        LOAD    RD, KS_PAT
        SEP     R4
        DW      KS_FOLDIN
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LBNF    TPALL
TPA5:   GHI     RA
        LBNZ    TPA9
        LOAD    RD, KS_PAT+8    ; no dot: any extension
        LDI     '?'
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
TPA9:   SEP     R5
TPALL:  LOAD    RD, KS_PAT      ; every name
        LDI     11
        PLO     RB
TPA6:   LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    TPA6
        SEP     R5

NEWLN:  LDI     0DH
        SEP     R4
        DW      F_TYPE
        LDI     0AH
        SEP     R4
        DW      F_TYPE
        LOAD    RD, K_RDIR      ; the output in a file: no pages
        LDN     RD
        LBNZ    TNL9
        LOAD    RD, LINES
        LDN     RD
        ADI     1
        STR     RD
        XRI     22
        LBNZ    TNL9
        STR     RD
        SEP     R4
        DW      K_PIN
        DB      '-- more: a key goes on, Q stops --',0
        SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      K_PIN
        DB      0DH,'                                  ',0DH,0
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
TNL9:   SEP     R5

PRSTR:  LDA     RA
        LBZ     TPS9
        SEP     R4
        DW      F_TYPE
        LBR     PRSTR
TPS9:   SEP     R5

INC32:  INC     RD
        INC     RD
        INC     RD
        LDI     4
        PLO     RB
TIN1:   LDN     RD
        ADI     1
        STR     RD
        LBNF    TIN9            ; no carry: done
        DEC     RD
        DEC     RB
        GLO     RB
        LBNZ    TIN1
TIN9:   SEP     R5

; NM2TX: the 11-byte name at RC as NAME.EXT at RF (RF past it, a 0 there)
NM2TX:  LDI     8
        PLO     RB
NX1:    LDA     RC
        XRI     ' '
        LBZ     NX2
        XRI     ' '
        STR     RF
        INC     RF
NX2:    DEC     RB
        GLO     RB
        LBNZ    NX1
        LDN     RC
        XRI     ' '
        LBZ     NX9
        LDI     '.'
        STR     RF
        INC     RF
        LDI     3
        PLO     RB
NX3:    LDA     RC
        XRI     ' '
        LBZ     NX4
        XRI     ' '
        STR     RF
        INC     RF
NX4:    DEC     RB
        GLO     RB
        LBNZ    NX3
NX9:    LDI     0
        STR     RF
        SEP     R5
