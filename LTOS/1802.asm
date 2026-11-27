; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; 1802.asm - 1802.PRG: 1802 [-Z] name [load [start]] [-Z] - a raw 1802 program (NAME.BIN: bytes only, no header) run on the
;   bare machine, as if it were the only thing in the Elf2K. No sandbox: it may use every register, port and
;   byte of RAM. The kernel is not kept safe in RAM - it does not need to be: RESET, then BOOT at the monitor,
;   loads LTOS again from the card. (Only the card itself - ports 2 and 3 - is still in the program's reach.)
;
;   load   where the file goes (hex; $0000 if not given). Whole sectors are read, so the file, rounded up to
;          512 bytes, must fit in $0000-$2FFF or in $3400-$7EFF (not $3000-$33FF: MON's stub, its jobs and
;          its stack; not $7F00-$7FFF: the monitor's page). Up to 12 KB low, 18.5 KB high.
;   start  where it starts (hex; = load if not given). It starts as the machine starts after a reset: R0 the
;          PC, X = P = 0, IE = 1, Q off - at $0000. A start that is not $0000 gets an LBR there (P stays 0), so
;          $0000-$0002 must then be outside what is loaded.
;   -Z     all of RAM it may clear set to 00 first - $0000-$2FFF and $3400-$7EFF (not MON's stub at
;          $3000-$33FF, not the monitor's page) - then the file loaded: a clean machine (~2 s at 1.79 MHz).
;          Done by MON's stub as copy jobs: a 00 copied to the first byte, then each byte to the next.
;   R1 = the monitor's breakpoint entry (as the monitor's RUN gives it), so an interrupt or SEP R1 ends at
;   the monitor's register dump; BOOT there brings LTOS back.
;
; How: as STELLAR.PRG does it - the file's sectors are listed through its FAT chain while the kernel is still
; here, as one job for MON's stub ($3000, out of the way): it reads them over the kernel with LTOS's own
; sector read, then starts the program exactly as the monitor's RUN would (MACT = 1).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

MAXJOBS EQU     MJOBS + 0F0H    ; the jobs end before $32F0 (the stub's stack grows down from $33FF)
TRAMPS  EQU     MAXJOBS         ; $32F0: the LBR to the start, until the stub copies it to $0000 (its last job)
ZSRC    EQU     TRAMPS + 3      ; $32F3: a 00 for -Z's copy jobs
MAXSEC  EQU     37              ; the most sectors ($3400-$7DFF); one job: 3 + 2 x 37 bytes

        ORG     4000H - 6
        DW      START, PEND - START, START
        ORG     4000H           ; (not PRGORG: $3000-$33FF is MON's stub and its jobs, built here)
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
; ---- the name: copied to NBUF, with .BIN put on when it has no extension (a '.' after the last '/')
        LOAD    RD, ZFLAG       ; no -Z yet
        LDI     0
        STR     RD
        SEP     R4
        DW      OPTZ            ; -Z before the name
        LDN     RF
        LBZ     USE
        XRI     '-'             ; any other option: not understood
        LBZ     USE
        LOAD    RD, NBUF
        LDI     0
        PLO     R9              ; R9.0 = 1: an extension typed
        LDI     NBMAX
        PLO     RC
NW1:    LDN     RF
        LBZ     NW4
        XRI     ' '
        LBZ     NW4
        LDA     RF
        STR     RD
        INC     RD
        XRI     '/'
        LBNZ    NW2
        PLO     R9              ; a '/': D = 0 - no extension in this part
        LBR     NW3
NW2:    XRI     '/' XOR '.'
        LBNZ    NW3
        LDI     1
        PLO     R9
NW3:    DEC     RC
        GLO     RC
        LBNZ    NW1
        LBR     USE             ; a name longer than NBUF
NW4:    GLO     R9
        LBNZ    NW5
        LDI     '.'
        STR     RD
        INC     RD
        LDI     'B'
        STR     RD
        INC     RD
        LDI     'I'
        STR     RD
        INC     RD
        LDI     'N'
        STR     RD
        INC     RD
NW5:    LDI     0
        STR     RD
        LOAD    RD, REST        ; the rest of the line, for the addresses
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RF, NBUF        ; found? (no: the kernel says so and goes back to the prompt)
        SEP     R4
        DW      KS_NAMEARG
        LOAD    RD, REST
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
; ---- load [start]
        SEP     R4
        DW      K_HEXARG        ; none: RD = 0
        LOAD    RA, LADDR
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        SEP     R4
        DW      K_HEXARG
        LBNF    SA1
        LOAD    RA, LADDR       ; none: the start = load
        LDA     RA
        PHI     RD
        LDN     RA
        PLO     RD
SA1:    LOAD    RA, SADDR
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
        SEP     R4
        DW      OPTZ            ; -Z after it (K_HEXARG left it alone); anything more: not understood
        LDN     RF
        LBNZ    USE
; ---- its size -> NSEC (sectors, 1 - MAXSEC)
        LOAD    RD, KS_DSIZE
        SEP     R4
        DW      KS_LD32         ; R8:R7
        GHI     R8
        LBNZ    TOOBIG
        GLO     R8
        LBNZ    TOOBIG
        GHI     R7
        LBNZ    SZ1
        GLO     R7
        LBZ     EMPTY
SZ1:    GLO     R7              ; (size + 511) / 512
        ADI     0FFH
        GHI     R7
        ADCI    01H
        LBDF    TOOBIG
        SHR
        PLO     RB              ; RB.0 = sectors
        SMI     MAXSEC + 1
        LBDF    TOOBIG
        LOAD    RD, NSEC
        GLO     RB
        STR     RD
; ---- where: the end (load + 512 x sectors: its high byte in RB.1, its low byte = load's) must be in the
;      low area ($0000-$2FFF) or the high one ($3400-$7EFF)
        LOAD    RD, LADDR
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA              ; RA = load
        GLO     RB
        SHL
        STR     R2
        GHI     RA
        ADD
        PHI     RB              ; RB.1 = the end's high byte
        LBDF    NOFIT
        GLO     RA              ; $3000 - end: no borrow, the low area
        SDI     00H
        GHI     RB
        SDBI    30H
        LBDF    FT1
        GLO     RA              ; else load >= $3400 ...
        SMI     00H
        GHI     RA
        SMBI    34H
        LBNF    NOFIT
        GLO     RA              ; ... and end <= $7F00
        SDI     00H
        GHI     RB
        SDBI    7FH
        LBNF    NOFIT
FT1:    LOAD    RD, SADDR       ; a start that is not $0000: the LBR at $0000-$0002 must miss the program
        LDA     RD
        LBNZ    FT2
        LDN     RD
        LBZ     FT3
FT2:    GHI     RA              ; load >= $0003?
        LBNZ    FT3
        GLO     RA
        SMI     3
        LBNF    NOLBR
FT3:
; ---- the job: [sectors, load (2), each sector's number (2)], through the file's FAT chain
        LOAD    RF, MJOBS
        LOAD    RD, ZFLAG       ; -Z: the clearing jobs first
        LDN     RD
        LBZ     ZJ9
        LOAD    RD, ZSRC
        LDI     0
        STR     RD
        LOAD    RA, ZSRC        ; $0000-$2FFF: a 00 to $0000, then each byte to the next
        LOAD    RB, 0000H
        LOAD    RC, 1
        SEP     R4
        DW      CPJOB
        LOAD    RA, 0000H
        LOAD    RB, 0001H
        LOAD    RC, 2FFFH
        SEP     R4
        DW      CPJOB
        LOAD    RA, ZSRC        ; $3400-$7EFF the same way
        LOAD    RB, 3400H
        LOAD    RC, 1
        SEP     R4
        DW      CPJOB
        LOAD    RA, 3400H
        LOAD    RB, 3401H
        LOAD    RC, 7EFFH - 3400H
        SEP     R4
        DW      CPJOB
        LOAD    RD, LADDR       ; RA = load, RB.0 = sectors, again
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, NSEC
        LDN     RD
        PLO     RB
ZJ9:    GLO     RB
        STR     RF
        INC     RF
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        INC     RF
        LOAD    RD, JP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, LEFT
        GLO     RB
        STR     RD
        LOAD    RD, SIDX
        LDI     0
        STR     RD
        LOAD    RD, KS_DCLUS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, CCLUS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
CH1:    LOAD    RD, CCLUS       ; RC = the cluster: a real one?
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_CLVALID
        LBNF    BADCH
        SEP     R4
        DW      KS_CL2LBA       ; R8:R7 = its first sector, + SIDX
        LOAD    RD, SIDX
        LDN     RD
        PLO     RC
        LDI     0
        PHI     RC
        SEP     R4
        DW      KS_ADD16
        GHI     R8              ; (MON's stub reads 16-bit sector numbers)
        LBNZ    FAR
        GLO     R8
        LBNZ    FAR
        LOAD    RD, JP          ; the sector's number into the job
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     R7
        STR     RF
        INC     RF
        GLO     R7
        STR     RF
        INC     RF
        LOAD    RD, JP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, LEFT        ; the last?
        LDN     RD
        SMI     1
        STR     RD
        LBZ     CH9
        LOAD    RD, SIDX        ; the next: in this cluster, or the next cluster's first
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, KS_SPC
        LDN     RD
        XOR
        LBNZ    CH1
        LOAD    RD, SIDX
        LDI     0
        STR     RD
        LOAD    RD, CCLUS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_FATNEXT
        LBDF    BADCH
        LOAD    RD, CCLUS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LBR     CH1
; ---- a start that is not $0000: LBR start at TRAMPS, and a copy job [FF, from, to, bytes] to $0000
CH9:    LOAD    RD, JP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, SADDR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    TR1
        GLO     RC
        LBZ     TR9
TR1:    LOAD    RD, TRAMPS
        LDI     0C0H            ; LBR
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LDI     0FFH
        STR     RF
        INC     RF
        LDI     HIGH(TRAMPS)
        STR     RF
        INC     RF
        LDI     LOW(TRAMPS)
        STR     RF
        INC     RF
        LDI     0               ; to $0000, 3 bytes
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        LDI     3
        STR     RF
        INC     RF
TR9:    LDI     0               ; no more jobs
        STR     RF
; ---- R1: the monitor's breakpoint entry - its RUN ends LDI hi / PHI R1 / LDI lo / PLO R1 / SEX R0 / SEP R0
        LOAD    RA, 8000H
SC1:    LDN     RA
        XRI     0F8H
        LBNZ    SC2
        GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        INC     RF
        INC     RF
        LDA     RF
        XRI     0B1H            ; PHI R1
        LBNZ    SC2
        LDA     RF
        XRI     0F8H            ; LDI
        LBNZ    SC2
        INC     RF
        LDA     RF
        XRI     0A1H            ; PLO R1
        LBNZ    SC2
        LDA     RF
        XRI     0E0H            ; SEX R0
        LBNZ    SC2
        LDN     RF
        XRI     0D0H            ; SEP R0
        LBZ     SC3
SC2:    INC     RA
        GHI     RA
        LBNZ    SC1             ; (to $FFFF)
        LOAD    RD, MONWARM     ; not found: the monitor's warm start
        LBR     SC5
SC3:    INC     RA              ; RD = hi, lo
        LDA     RA
        PHI     RD
        INC     RA
        INC     RA
        LDN     RA
        PLO     RD
SC5:    LOAD    RA, R1V
        GHI     RD
        STR     RA
        INC     RA
        GLO     RD
        STR     RA
; ---- "Starting NAME.BIN: $llll-$eeee, at $ssss"
        SEP     R4
        DW      K_PIN
        DB      'Starting ',0
        SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ': $',0
        LOAD    RA, LADDR
        SEP     R4
        DW      P4AT
        SEP     R4
        DW      K_PIN
        DB      '-$',0
        LOAD    RD, KS_DSIZE + 2 ; the last byte: load + size - 1
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, LADDR + 1
        SEX     RD
        GLO     RC
        ADD
        PLO     RC
        DEC     RD
        GHI     RC
        ADC
        PHI     RD
        GLO     RC
        PLO     RD
        SEX     R2
        DEC     RD
        SEP     R4
        DW      K_PHEX4
        SEP     R4
        DW      K_PIN
        DB      ', at $',0
        LOAD    RA, SADDR
        SEP     R4
        DW      P4AT
        SEP     R4
        DW      K_PIN
        DB      '.',0DH,0AH,'RESET, then BOOT at the monitor, brings LTOS back.',0DH,0AH
        DB      0
        LOAD    RD, ZFLAG
        LDN     RD
        LBZ     LD1
        SEP     R4
        DW      K_PIN
        DB      'Clearing RAM, then l',0
        LBR     LD2
LD1:    SEP     R4
        DW      K_PIN
        DB      'L',0
LD2:    SEP     R4
        DW      K_PIN
        DB      'oading ... ',0
; ---- MON's stub to $3000, R1 for it (MR1), MACT = 1: it starts the program; the BIOS's SCRT for the stub
        LOAD    RD, MSTUBD
        LOAD    RF, 3000H
        LOAD    RC, MSTUBN
CP1:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    CP1
        GHI     RC
        LBNZ    CP1
; IE = 1, as after a reset: the stub's ending - R1 from MR1, R0 = 0, SEX R0, SEP R0 (STEND) - becomes R1 =
; R1V, R0 = 0, SEX R2, STR R2 (D = 0), RET: X = P = 0 from the 0 at R2, IE = 1. (Not found: started as is.)
        LOAD    RA, 3000H
        LOAD    RC, MSTUBN - STENDN + 1
PS1:    GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        LOAD    RD, STEND
        LDI     STENDN
        PLO     RB
PS2:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    PS3
        DEC     RB
        GLO     RB
        LBNZ    PS2
        GHI     RA              ; found at RA: NEWEND over it
        PHI     RF
        GLO     RA
        PLO     RF
        LOAD    RD, NEWEND
        LDI     STENDN
        PLO     RB
PS4:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    PS4
        LOAD    RD, R1V         ; R1's value into it
        INC     RA
        LDA     RD
        STR     RA
        INC     RA
        INC     RA
        INC     RA
        LDN     RD
        STR     RA
        LBR     PS9
PS3:    INC     RA
        DEC     RC
        GLO     RC
        LBNZ    PS1
        GHI     RC
        LBNZ    PS1
PS9:    LOAD    RD, R1V
        LOAD    RF, MR1
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF              ; (MACT follows)
        LDI     1
        STR     RF
        REQ                     ; Q off, as after a reset
        LOAD    R6, 3000H       ; the BIOS's SCRT for MON's stub (the kernel's goes when the program loads)
        LBR     F_INITCALL
; P4AT: the 2 bytes at RA in hex
; OPTZ: RF past spaces; a -Z (or -z) there: ZFLAG = 1, RF past it and the spaces after it
OPTZ:   SEP     R4
        DW      K_SKIPSP
        LDN     RF
        XRI     '-'
        LBNZ    OZ9
        INC     RF
        LDA     RF
        ANI     0DFH            ; (upper case)
        XRI     'Z'
        LBNZ    OZ8
        LDN     RF              ; then a space or the end
        LBZ     OZ1
        XRI     ' '
        LBNZ    OZ8
OZ1:    LOAD    RD, ZFLAG
        LDI     1
        STR     RD
        LBR     K_SKIPSP
OZ8:    DEC     RF              ; not -Z: RF back at the '-'
        DEC     RF
OZ9:    SEP     R5
; CPJOB: a copy job at RF - [FF, from RA, to RB, RC bytes]; RF past it
CPJOB:  LDI     0FFH
        STR     RF
        INC     RF
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        INC     RF
        GHI     RB
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        INC     RF
        SEP     R5
P4AT:   LDA     RA
        PHI     RD
        LDN     RA
        PLO     RD
        LBR     K_PHEX4
; ---- trouble
USE:    SEP     R4
        DW      K_PIN
        DB      'Usage: 1802 [-Z] name [load [start]]   (hex; NAME.BIN, at $0000)',0DH,0AH,0
        LBR     FAIL
EMPTY:  SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ' is empty.',0DH,0AH,0
        LBR     FAIL
TOOBIG: SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ' is too big (18.5 KB at most, 12 KB from $0000).',0DH,0AH,0
        LBR     FAIL
NOFIT:  SEP     R4
        DW      K_PIN
        DB      'It must go in $0000-$2FFF or $3400-$7EFF (in whole 512-byte sectors).',0DH,0AH,0
        LBR     FAIL
NOLBR:  SEP     R4
        DW      K_PIN
        DB      'A start that is not $0000 needs $0000-$0002 free: load at $0003 or above.',0DH,0AH,0
        LBR     FAIL
BADCH:  SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ': its clusters are broken (FSCK finds why).',0DH,0AH,0
        LBR     FAIL
FAR:    SEP     R4
        DW      KS_PFNAME
        SEP     R4
        DW      K_PIN
        DB      ' is past sector 65,535 - copy it, then run the copy.',0DH,0AH,0
        LBR     FAIL
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
FAIL:   LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
STEND:  DB      0F8H,HIGH(MR1),0BDH,0F8H,LOW(MR1),0ADH  ; LOAD RD, MR1
        DB      4DH,0B1H,0DH,0A1H                       ; LDA RD / PHI R1 / LDN RD / PLO R1
        DB      0F8H,00H,0B0H,0A0H,0E0H,0D0H            ; LDI 0 / PHI R0 / PLO R0 / SEX R0 / SEP R0
STENDN  EQU     $ - STEND
NEWEND: DB      0F8H,00H,0B1H,0F8H,00H,0A1H             ; LDI hi / PHI R1 / LDI lo / PLO R1 (R1V put in)
        DB      0F8H,00H,0B0H,0A0H                      ; LDI 0 / PHI R0 / PLO R0
        DB      0E2H,52H,70H                            ; SEX R2 / STR R2 / RET: X = P = 0, IE = 1
        DB      0,0,0
MSTUBD: INCL    "out/monstub.inc"       ; MON's last step (monstub.asm, assembled at $3000)
MSTUBN  EQU     $ - MSTUBD
PEND:
; ---- the variables (cleared by nothing: each is set before it is used)
NBMAX   EQU     60
NBUF:   DS      NBMAX + 5
REST:   DS      2
LADDR:  DS      2
SADDR:  DS      2
NSEC:   DS      1
LEFT:   DS      1
SIDX:   DS      1
CCLUS:  DS      2
JP:     DS      2
R1V:    DS      2
ZFLAG:  DS      1
        END
