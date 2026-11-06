; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; save.asm - SAVE.PRG: SAVE name start end [exec] - memory to a file; with exec, a program (the 6-byte header).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     6800H - 6
        DW      START, PEND - START, START
        ORG     6800H           ; (high: $2C00-$67FF stays free for what it works on)
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
; ---- SAVE name start end [exec]: memory to a file (with exec: a program, with its 6-byte header)
        SEP     R4
        DW      KS_MNTCHK
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        SEP     R4
        DW      KS_HEXARG
        LBDF    SVUSE
        LOAD    RA, KS_WSRC        ; WSRC = start (also the header's load address)
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        LOAD    RA, KS_PFXB
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        SEP     R4
        DW      KS_HEXARG          ; end
        LBDF    SVUSE
        LOAD    RA, KS_WSRC+1      ; WLEN = end - start + 1 (0: too long / end before start)
        SEX     RA
        GLO     RD
        SM
        PLO     RC
        DEC     RA
        GHI     RD
        SMB
        PHI     RC
        SEX     R2
        LBNF    SVUSE
        INC     RC
        GHI     RC
        LBNZ    SV1
        GLO     RC
        LBZ     SVUSE
SV1:    GLO     RD              ; it must not reach SAVE itself, LTOS's buffers and stack ($6800-$7EFF):
        SMI     LOW(6800H)      ;  end < $6800, or start >= $7F00
        GHI     RD
        SMBI    HIGH(6800H)
        LBNF    SV2
        LOAD    RA, KS_WSRC
        LDN     RA
        SMI     7FH
        LBNF    SVBUF
SV2:    LOAD    RA, KS_WLEN
        GHI     RC
        STR     RA
        INC     RA
        GLO     RC
        STR     RA
        LOAD    RA, KS_PFXB+2      ; the header: load, length, start
        GHI     RC
        STR     RA
        INC     RA
        GLO     RC
        STR     RA
        LOAD    RA, KS_PFXN
        LDI     0
        STR     RA
        SEP     R4
        DW      KS_HEXARG          ; exec: start <= exec <= end
        LBDF    KS_SV4
        LOAD    RA, KS_WSRC+1
        SEX     RA
        GLO     RD
        SM
        PLO     RB
        DEC     RA
        GHI     RD
        SMB
        PHI     RB              ; RB = exec - start
        SEX     R2
        LBNF    SVUSE
        LOAD    RA, KS_WLEN+1      ; < WLEN
        SEX     RA
        GLO     RB
        SM
        DEC     RA
        GHI     RB
        SMB
        SEX     R2
        LBDF    SVUSE
        LOAD    RA, KS_PFXB+4
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        LOAD    RA, KS_PFXN
        LDI     6
        STR     RA
        LBR     KS_SV4          ; (the kernel's: replace? then write it - K_SAVEF's end too)
SVUSE:  SEP     R4
        DW      KS_PIN
        DB      'SAVE name start end [exec] - addresses in hex; exec makes it a program.',0DH,0AH,0
        SEP     R5     
SVBUF:  SEP     R4
        DW      KS_PIN
        DB      'That reaches $6800-$7EFF (SAVE itself and the LTOS buffers).',0DH,0AH,0
        SEP     R5     

OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
