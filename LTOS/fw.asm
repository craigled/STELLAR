; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; fw.asm - FW.PRG: FW [name] - a STELLAR firmware from the card into memory ($0000-$2EFF), then the monitor, however
; LTOS was started (MON puts STELLAR back only if it was in RAM when LTOS booted). FW alone: STELLAR.BIN (the root,
; else /BIN); FW NAME.BIN: that file (where its path says; a name alone: here, the root, then /BIN). Not there:
; said, and LTOS goes on. Its last step is MON's stub - its own copy, run at $3000 (the firmware loads over the
; kernel) - with its own last line over the stub's ("STELLAR is in memory").
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
        INCL    "out/monstub_syms.inc"

        ORG     6800H - 6       ; (high: its stub goes to $3000)
        DW      START, PEND - START, START
        ORG     6800H
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    FW2
        SEP     R4              ; FW alone: STELLAR.BIN, the root, else /BIN
        DW      KS_STLFIND
        LBR     FW5
FW2:    LOAD    RD, FWNAME      ; FW NAME: its folder (WDIR) ...
        SEP     R4
        DW      K_PARSE
        LBDF    KS_PPERR        ; (not a name: the kernel says why, back to the prompt)
        SEP     R4
        DW      TRYFW
        LBNZ    FW5
        LOAD    RD, KS_PPSL     ; ... a path: only there; a name alone: the root, then /BIN too
        LDN     RD
        LBNZ    FWNO
        LOAD    RD, KS_WDIR
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      TRYFW
        LBNZ    FW5
        SEP     R4
        DW      KS_TOBIN
        LBDF    FWNO
        SEP     R4
        DW      TRYFW
        LBNZ    FW5
FWNO:   LOAD    RD, FWNAME
        SEP     R4
        DW      KS_PFNAMD
        SEP     R4
        DW      K_PIN
        DB      ' is not on the card, or not a STELLAR firmware (12 KB at least).',0DH,0AH,0
        SEP     R5
; TRYFW: FWNAME's sectors listed from WDIR (KS_SECLST) -> D = KS_STLN (24 if it is there)
TRYFW:  LOAD    RD, FWNAME
        SEP     R4
        DW      KS_SECLST
        LOAD    RD, KS_STLN
        LDN     RD
        SEP     R5
FW5:    LOAD    RD, KS_STLN     ; (FW alone: STLFIND said)
        LDN     RD
        LBZ     FWNO
        SEP     R4
        DW      K_PIN
        DB      'Loading ',0
        LOAD    RD, FWNAME
        SEP     R4
        DW      KS_PFNAMD
        SEP     R4
        DW      K_PIN
        DB      ' into memory ... ',0
        LOAD    RD, MSTUBD      ; MON's stub to $3000 ...
        LOAD    RF, 3000H
        LOAD    RC, MSTUBN
FW6:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GHI     RC
        LBNZ    FW6
        GLO     RC
        LBNZ    FW6
        LOAD    RD, FWMSG       ; ... its last line ours
        LOAD    RF, MS_MSOK
FW7:    LDA     RD
        STR     RF
        INC     RF
        LBNZ    FW7
        LOAD    RF, MACT        ; its job: the firmware's 24 sectors to $0000, then the monitor
        LDI     0
        STR     RF
        INC     RF              ; (MJOBS = MACT + 1)
        LDI     24
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        LOAD    RD, KS_STLLST
        LDI     48
        PLO     RC
FW8:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    FW8
        STR     RF              ; (0) no more jobs
        LOAD    R6, 3000H       ; the BIOS's SCRT for the stub (LTOS's goes when the firmware loads over it)
        LBR     F_INITCALL
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
FWNAME: DB      'STELLAR BIN'
FWMSG:  DB      'done.',0DH,0AH,'Back to the monitor - STELLAR is in memory.',0DH,0AH,0
FWMSGN  EQU     $ - FWMSG
MSTUBD: INCL    "out/monstub.inc"       ; MON's last step (monstub.asm, assembled at $3000)
MSTUBN  EQU     $ - MSTUBD
PEND:
        END
