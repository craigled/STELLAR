; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; monstub.asm - MON's last step, assembled to run at $3000 (build.py puts its bytes in the kernel, which
; copies them there and writes its jobs after them). Each job: a count of sectors, where they go (2 bytes),
; then each sector's number (2 bytes each, in order) - read with LTOS's own sector read (bread.asm), over
; where the kernel was. Then (MACT = 0) the monitor. MON's job: STELLAR.BIN's 24 sectors to $0000, wherever
; they are on the card - STELLAR is then as it was before LTOS booted.
; Or (MACT = 1, STELLAR.PRG) start what was loaded at $0000 exactly as the monitor's RUN does: R0 = 0, R1 =
; the monitor's breakpoint entry (MR1), SEX R0, SEP R0 - a STELLAR program's end then breaks to the monitor.
; In: the BIOS's SCRT in R4 / R5. Its stack: $33FF down (the jobs may load over LTOS's).

        CPU     1802
        INCL    "ltos.inc"

        ORG     3000H
MSTUB:  LOAD    R2, 33FFH       ; a stack of its own, in STELLAR's core area (rebuilt when STELLAR starts)
        SEX     R2
        LOAD    R9, MJOBS       ; R9 = the next job's byte (BREAD uses RB.0, RC, RD)
MJ1:    LDA     R9
        LBZ     MJ9             ; no more jobs
        PLO     RA              ; RA.0 = its sectors
        XRI     0FFH
        LBZ     MJC             ; $FF: a copy in memory - [from (2), to (2), bytes (2)] (STELLAR.PRG's slots)
        LDA     R9
        PHI     RF
        LDA     R9
        PLO     RF              ; RF = where (BREAD leaves RF after each sector)
MJ2:    LDA     R9
        PHI     R7
        LDA     R9
        PLO     R7
        SEP     R4
        DW      BREAD           ; LTOS's own read (bread.asm), not the BIOS's
        LBDF    MSF
        DEC     RA
        GLO     RA
        LBNZ    MJ2
        LBR     MJ1
MJC:    LDA     R9
        PHI     RF
        LDA     R9
        PLO     RF
        LDA     R9
        PHI     RD
        LDA     R9
        PLO     RD
        LDA     R9
        PHI     RC
        LDA     R9
        PLO     RC
MJC1:   GHI     RC
        LBNZ    MJC2
        GLO     RC
        LBZ     MJ1
MJC2:   LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        LBR     MJC1
MJ9:    LOAD    RD, MACT
        LDN     RD
        LBNZ    MRUN
        LOAD    RF, MSOK
        LBR     MSG
MRUN:   LOAD    RF, MSGO        ; start STELLAR, as RUN does
        SEP     R4
        DW      F_MSG
        LOAD    RD, MR1
        LDA     RD
        PHI     R1
        LDN     RD
        PLO     R1
        LDI     0
        PHI     R0
        PLO     R0
        SEX     R0
        SEP     R0
MSF:    LOAD    RF, MSBAD
MSG:    SEP     R4
        DW      F_MSG
        LBR     MONWARM
MSOK:   DB      'done.',0DH,0AH,'Back to the monitor - STELLAR is as it was before LTOS.',0DH,0AH,0
MSGO:   DB      'done.',0DH,0AH,0
MSBAD:  DB      'READ FAILED - load STELLAR again before you use it.',0DH,0AH,'Back to the monitor.',0DH,0AH,0
        INCL    "bread.asm"
MSEND:
        END
