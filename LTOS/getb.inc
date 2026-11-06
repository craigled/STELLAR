; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; getb.inc - GETB (GREP, SEND): INCL'd after tools.inc.

; GETB: the open file's next byte in D, DF = 0; DF = 1 at its end (after KS_FOPEN, SREM = 0). The program
; defines SREM (DS 2) and SPTR (DS 2): the bytes left in DATBUF, and where.
GETB:   LOAD    RD, SREM
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
GB1:    GHI     RC
        LBNZ    GB2
        GLO     RC
        LBNZ    GB2
        SEP     R4
        DW      KS_FREAD
        LBDF    GB9
        LOAD    RD, SPTR
        LDI     HIGH(KS_DATBUF)
        STR     RD
        INC     RD
        LDI     LOW(KS_DATBUF)
        STR     RD
        LBR     GB1
GB9:    LDI     1
        SHR
        SEP     R5
GB2:    DEC     RC
        LOAD    RD, SREM
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, SPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDA     RF
        PLO     RE
        GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        LDI     0
        SHR
        GLO     RE
        SEP     R5

