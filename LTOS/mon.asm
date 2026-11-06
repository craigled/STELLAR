; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; mon.asm - MON.PRG: back to the monitor - with STELLAR put back from STELLAR.BIN if it was in RAM when LTOS
; started (the kernel's STLCHK said so in STLRAM). Its last step (monstub.asm) runs at $3000, as STELLAR.BIN
; loads over the kernel; its bytes are this program's own (out/monstub.inc), as STELLAR.PRG's are.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     6800H - 6       ; (high: its stub goes to $3000, where programs start)
        DW      START, PEND - START, START
        ORG     6800H
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        LOAD    RF, KS_STLRAM
        LDN     RF
        LBNZ    MON0
        SEP     R4
        DW      KS_PIN
        DB      'Back to the monitor.',0DH,0AH,0
        LBR     KS_MONWARM
MON0:   SEP     R4              ; STELLAR.BIN again (it may have been replaced since the boot)
        DW      KS_STLFIND
        LOAD    RD, KS_STLN
        LDN     RD
        LBNZ    MON1
        SEP     R4
        DW      KS_PIN
        DB      'STELLAR.BIN is not on the card.',0DH,0AH,0
        LBR     KS_MONWARM
MON1:   SEP     R4
        DW      KS_PIN
        DB      'Putting STELLAR back from STELLAR.BIN ... ',0
        LOAD    RD, MSTUBD      ; its last step runs at $3000 - the kernel is about to be overwritten
        LOAD    RF, STUBAT
        LOAD    RC, MSTUBN
MON2:   LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GHI     RC
        LBNZ    MON2
        GLO     RC
        LBNZ    MON2
        LOAD    RF, MACT        ; its job: STELLAR.BIN's 24 sectors to $0000, then the monitor
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
MON3:   LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    MON3
        STR     RF              ; (0) no more jobs
        LOAD    R6, STUBAT      ; the BIOS's SCRT for the stub (LTOS's goes when STELLAR loads over it)
        LBR     F_INITCALL
OLD:    SEP     R4              ; (an older MON.PRG after U: still the way out - $8003 is the ROM's, never moves)
        DW      K_PIN
        DB      'MON.PRG is not for this kernel: back to the monitor, STELLAR not put back.',0DH,0AH,0
        LBR     8003H
STUBAT  EQU     3000H
MSTUBD: INCL    "out/monstub.inc"       ; MON's last step (monstub.asm, assembled at $3000)
MSTUBN  EQU     $ - MSTUBD
PEND:
        END
