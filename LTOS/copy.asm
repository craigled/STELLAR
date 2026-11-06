; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; copy.asm - COPY.PRG: COPY from to. The file is read whole into memory, then saved under the new name
; (asked first if that name is taken) - so it may be up to the free program memory (~16 KB).
;   COPY *.TXT DOCS   every file that matches, into the folder DOCS (each named as it goes; one with a name
;                     DOCS has already is not copied - nothing is replaced)
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
        LDN     RF
        LBZ     USE
        SEP     R4
        DW      KS_MNTCHK
        LOAD    RD, LINE0       ; the line as typed, for the plain form
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      SRCARG          ; SNM in SDIR (WILD: a pattern)
        LOAD    RD, WILD
        LDN     RD
        LBNZ    CW
; ---- one: COPY A B - load it, save it (asked first if B is taken)
        LOAD    RD, LINE0
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RA, BUF
        LOAD    RC, PTOP - BUF
        SEP     R4
        DW      K_LOADF         ; RC = its bytes, RF past the name
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        LOAD    RA, BUF
        SEP     R4
        DW      K_SAVEF         ; (never returns)
; ---- many: COPY *.TXT DOCS
CW:     SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     USE
        SEP     R4
        DW      DSTARG
        LOAD    RD, ISDIR
        LDN     RD
        LBZ     NOTDIR
        SEP     R4
        DW      SAMED
        LBDF    SAMEDIR
        LOAD    RD, NSKIP       ; NSKIP = the files done (copied or not): the walk starts again each time
        LDI     0
        STR     RD
        LOAD    RD, NDONE
        LDI     0
        STR     RD
        INC     RD
        STR     RD
CW1:    SEP     R4
        DW      MATCHN
        LBDF    CW9
        GHI     RF              ; CUR = its name
        PHI     RD
        GLO     RF
        PLO     RD
        LOAD    RC, CUR
        SEP     R4
        DW      CP11
        LOAD    RD, NSKIP
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      PCUR
        LOAD    RD, KS_DSIZE    ; it must fit in BUF ... PTOP
        LDA     RD
        LBNZ    CWBIG
        LDA     RD
        LBNZ    CWBIG
        LDA     RD              ; RC = its bytes
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        SMI     LOW(PTOP - BUF)
        GHI     RC
        SMBI    HIGH(PTOP - BUF)
        LBDF    CWBIG
        LOAD    RD, CSIZE
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, KS_LDDST    ; read it (DNEXT left DCLUS / DSIZE) to BUF
        LDI     HIGH(BUF)
        STR     RD
        INC     RD
        LDI     LOW(BUF)
        STR     RD
        LOAD    RD, KS_LDSKIP
        LDI     0
        STR     RD
        SEP     R4
        DW      KS_LOADF
        LBDF    KS_LDFAIL
        LOAD    RD, DDIR        ; the folder has one by that name: not copied
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, CUR
        SEP     R4
        DW      KS_FINDN
        LBDF    CW2
        SEP     R4
        DW      K_PIN
        DB      ' - the folder has one already: not copied',0DH,0AH,0
        LBR     CW1
CW2:    LOAD    RD, DDIR
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, CSIZE
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RA, BUF
        LOAD    RD, CUR
        SEP     R4
        DW      KS_KSAVER       ; DF = 1: WFILE's D
        LBDF    KS_WERR
        SEP     R4
        DW      K_PCRLF
        LOAD    RD, NDONE+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     CW1
CWBIG:  SEP     R4
        DW      K_PIN
        DB      ' - too big to copy (16 KB at most): not copied',0DH,0AH,0
        LBR     CW1
CW9:    LOAD    RD, NDONE
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
        DB      ' copied.',0DH,0AH,0
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'COPY from to - copies a file;  COPY *.TXT DOCS - all that match, into a folder',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "wild.inc"
LINE0:  DS      2
CSIZE:  DS      2
BUF:
PEND:
        END
