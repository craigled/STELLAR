; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; empty.asm - EMPTY.PRG: the files in /TRASH (DELETE puts them there) deleted for good, after asking.
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
        LOAD    RF, TRALL
        LOAD    RD, KS_PAT
        SEP     R4
        DW      KS_PARSE
        LBDF    NONE            ; no /TRASH yet
        LDI     0               ; count them
        SEP     R4
        DW      RMWALK
        LOAD    RD, RMCNT
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     NONE
        SEP     R4              ; (the question on the screen, even with the output in a file)
        DW      K_TTYON
        LOAD    RD, RMCNT
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
        DB      ' in the trash - delete for good? (Y/N) ',0
        SEP     R4
        DW      K_YESNO
        LBNF    K_MAIN
        LDI     1               ; delete them
        SEP     R4
        DW      RMWALK
        SEP     R4
        DW      K_PIN
        DB      'The trash is empty now.',0DH,0AH,0
        LBR     K_MAIN
NONE:   SEP     R4
        DW      K_PIN
        DB      'The trash is empty.',0DH,0AH,0
        LBR     K_MAIN
; RMWALK: every file in it: D = 0 count them in RMCNT, 1 delete them (as RM.PRG)
RMWALK: PLO     RB
        LOAD    RD, RMMODE      ; RMMODE, RMCNT: in this order
        GLO     RB
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      KS_DOPEN
RW1:    SEP     R4
        DW      KS_DNEXT
        LBDF    RW9
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    RW1             ; a folder
        LOAD    RD, RMMODE
        LDN     RD
        LBNZ    RW2
        INC     RD              ; count it
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        INC     RC
        GLO     RC
        STR     RD
        DEC     RD
        GHI     RC
        STR     RD
        LBR     RW1
RW2:    SEP     R4
        DW      KS_DELENT
        LBDF    KS_CARDF
        LBR     RW1
RW9:    SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
TRALL:  DB      '/TRASH/*.*',0
PEND:
RMMODE: DS      1               ; RMMODE, RMCNT: in this order
RMCNT:  DS      2
        END
