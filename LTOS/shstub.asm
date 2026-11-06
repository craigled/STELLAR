; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; shstub.asm - SH's way back, at $2E00 (sh.asm copies it there; build.py puts its bytes in out/shstub.inc). The
; kernel's MAIN comes here after each outside command a script ran (K_SHHOOK: LBR $2E00), R2 a fresh stack.
; The command's status is kept ($?). SH's code still there (the sum of $4000 .. SEND as SH left it)? On with the
; script ($4003). Not (RAWK, COPY ... used that RAM): the kernel runs "SH" - SH.PRG found as any program is (here,
; the root, /BIN) - and SH, seeing SRELD, goes on with the script. Back here again with SRELD still 1: SH.PRG was
; not found (the kernel said so) - the script stops.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
        INCL    "shstate.inc"

        ORG     SHSTUB
STUB:   LOAD    RD, K_STAT      ; $? = the command's status
        LOAD    RF, SSTAT
        LDN     RD
        STR     RF
        SEP     R4
        DW      SSUMIT          ; RD = the sum now
        LOAD    RF, SSUM
        LDA     RF
        STR     R2
        GHI     RD
        XOR
        BNZ     SRL             ; (short branches: the stub is all in page $2E)
        LDN     RF
        STR     R2
        GLO     RD
        XOR
        LBZ     SHNEXTA         ; as it was: on
SRL:    LDI     LOW(SRELD)      ; SH.PRG again - unless that was tried (RF is in page $2E)
        PLO     RF
        LDN     RF
        BNZ     SRLX
        GHI     RF
        STR     RF
        LOAD    RF, KS_LINE
        LDI     'S'
        STR     RF
        INC     RF
        LDI     'H'
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        LBR     K_EXEC
SRLX:   LOAD    RF, K_SHHOOK    ; no SH.PRG: the script stops
        LDI     0
        STR     RF
        LBR     K_MAIN
; SSUMIT: RD = the 16-bit sum of $4000 .. SH's end (SEND: how many 8 bytes; SH's code is a multiple of 8). With
;         X = RF: ADD takes the byte, IRX steps on; RB.0 counts the carries out of D (the sum's high byte).
SSUMIT: LOAD    RF, SEND
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        LDI     HIGH(SHLO)
        PHI     RF
        LDI     0               ; (SHLO is a page's start)
        PLO     RF
        PLO     RB
        SEX     RF
SS1:    ADD
        IRX
        BNF     SS2
        INC     RB
SS2:    ADD
        IRX
        BNF     SS3
        INC     RB
SS3:    ADD
        IRX
        BNF     SS4
        INC     RB
SS4:    ADD
        IRX
        BNF     SS5
        INC     RB
SS5:    ADD
        IRX
        BNF     SS6
        INC     RB
SS6:    ADD
        IRX
        BNF     SS7
        INC     RB
SS7:    ADD
        IRX
        BNF     SS8
        INC     RB
SS8:    ADD
        IRX
        BNF     SS9
        INC     RB
SS9:    PLO     RD              ; 8 more: RC - 1
        DEC     RC
        GLO     RC
        BNZ     SSA
        GHI     RC
        BZ      SSB
SSA:    GLO     RD
        BR      SS1
SSB:    GLO     RB
        PHI     RD
        SEX     R2
        SEP     R5
STUBEND:
        END
