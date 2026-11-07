; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; stellar.asm - STELLAR.PRG: STELLAR [firmware.BIN] [app ...] - start the STELLAR virtual machine from the card.
;   The firmware: the .BIN named, or STELLAR.BIN - its 12 KB to $0000-$2EFF.
;   Apps: NAME.STL files (RECV NAME.STL makes one from a .lst): each block of 512 bytes to its address in
;   $4000-$7EFF (a $7E00 block: only its first half - $7F00-$7FFF is the BIOS's). Several apps (up to 4) load in the order given - the VM1 app first, as with D-lines.
; Everything is found through the FAT first; then MON's stub (from $3000, out of the kernel's way) reads the
; sectors and starts STELLAR exactly as the monitor's RUN would - R0 = 0, R1 = the monitor's breakpoint
; entry, X = P = 0. A STELLAR program's end then breaks to the monitor as always; BOOT brings LTOS back.
; The breakpoint entry is found in the ROM itself: the monitor's RUN ends LDI hi / PHI R1 / LDI lo / PLO R1 /
; SEX R0 / SEP R0 (V87: $8EB1; v120: $8F53), so any monitor version works.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

MAXJOBS EQU     MJOBS + 0F0H    ; the jobs must end before the stub's stack (it grows down from $33FF)
BACKA   EQU     0180H           ; BACK, the way back to LTOS: in the firmware's free bytes $0175-$019F (Craig)
BACKS   EQU     MAXJOBS         ;  ... kept at $32F0 (between the jobs and NOTEB) until MON's stub copies it

        ORG     4000H - 6
        DW      START, PEND - START, START
        ORG     4000H           ; (not PRGORG: $3000-$3FFF is MON's stub, the jobs, ATTACH's note and its names list)
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        LOAD    RD, VARS        ; the variables: 0
        LOAD    RC, VEND - VARS
VZ:     LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    VZ
        GHI     RC
        LBNZ    VZ
        LOAD    RD, ARG0        ; where the arguments start (the kernel's auto-STELLAR: at the command's name)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, FWNAME      ; the defaults: STELLAR.BIN, no apps
        LOAD    RC, DEFNM
        LDI     11
        PLO     RB
ST0:    LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST0
        LOAD    RD, NAPPS
        LDI     0
        STR     RD
        LOAD    RD, HASDOC
        LDI     0
        STR     RD
        LOAD    RD, RETMON      ; RETMON (-M), USEBACK: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, KS_CWD      ; the firmware: in this folder, else the root
        LOAD    R9, FWREC
        LDA     RD
        STR     R9
        INC     R9
        LDN     RD
        STR     R9
        INC     R9
        LDI     0
        STR     R9
; ---- the arguments
ARG:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     ARGEND
        XRI     '-'             ; -M: when the program ends, the monitor (as before), not LTOS
        LBNZ    AR0
        INC     RF
        LDA     RF
        ORI     20H
        XRI     'm'
        LBNZ    BADN
        LDN     RF
        LBZ     ARM
        XRI     ' '
        LBNZ    BADN
ARM:    LOAD    RD, RETMON
        LDI     1
        STR     RD
        LBR     ARG
AR0:    LOAD    RD, TMPN
        SEP     R4
        DW      K_PARSE         ; (RF past it)
        LBDF    BADN
        LOAD    RD, TMPN        ; no wildcards
        LDI     11
        PLO     RB
AR1:    LDA     RD
        XRI     '?'
        LBZ     BADN
        DEC     RB
        GLO     RB
        LBNZ    AR1
        LOAD    RD, TMPN+8      ; .BIN: the firmware
        LDA     RD
        XRI     'B'
        LBNZ    AR3
        LDA     RD
        XRI     'I'
        LBNZ    AR3
        LDN     RD
        XRI     'N'
        LBNZ    AR3
        LOAD    RD, FWNAME
        LOAD    R9, FWREC
        LBR     AR5
AR3:    LOAD    RD, TMPN+8      ; no extension: .STL
        LDN     RD
        XRI     ' '
        LBNZ    AR4
        LDI     'S'
        STR     RD
        INC     RD
        LDI     'T'
        STR     RD
        INC     RD
        LDI     'L'
        STR     RD
AR4:    LOAD    RD, TMPN+8      ; .STL: an app (anything else: a document for Lite-Writer 2)
        LDA     RD
        XRI     'S'
        LBNZ    ARDOC
        LDA     RD
        XRI     'T'
        LBNZ    ARDOC
        LDN     RD
        XRI     'L'
        LBNZ    ARDOC
        LOAD    RD, NAPPS       ; APPN + 11 x NAPPS
        LDN     RD
        XRI     4
        LBZ     MANY
        LDN     RD
        ADI     1
        STR     RD
        SMI     1
        PLO     RC              ; RC.0 = NAPPS - 1: x 11 = 8x + 2x + x
        SHL
        SHL
        SHL
        STR     R2
        GLO     RC
        SHL
        ADD
        STR     R2
        GLO     RC
        ADD
        ADI     LOW(APPN)
        PLO     RD
        LDI     HIGH(APPN)
        ADCI    0
        PHI     RD
        SEP     R4              ; R9 = its record
        DW      RECOF
        LBR     AR5
ARDOC:  LOAD    RD, HASDOC      ; (one only)
        LDN     RD
        LBNZ    BADN
        LDI     1
        STR     RD
        LOAD    RD, DOCNM
        LOAD    R9, DOCREC
AR5:    LOAD    RC, KS_WDIR     ; its record: the folder it was named in, and whether a path was given
        LDA     RC
        STR     R9
        INC     R9
        LDN     RC
        STR     R9
        INC     R9
        LOAD    RC, KS_PPSL
        LDN     RC
        STR     R9
        LOAD    RC, TMPN        ; TMPN -> RD
        LDI     11
        PLO     RB
AR6:    LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    AR6
        LBR     ARG
; ---- the firmware's 24 sectors (the kernel's SECLST: in KS_STLLST)
ARGEND: LOAD    RD, HASDOC      ; a document but no app: Lite-Writer 2 (STELLAR DOC.TXT = STELLAR LW2 DOC.TXT)
        LDN     RD
        LBZ     AN0
        LOAD    RD, NAPPS
        LDN     RD
        LBNZ    AE1
        LOAD    RC, LW2N        ; TMPN = LW2.STL, named alone in the current folder (RF stays at the end)
        LOAD    RD, TMPN
        LDI     11
        PLO     RB
AE0:    LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    AE0
        LOAD    RD, KS_CWD
        LOAD    RC, KS_WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, KS_PPSL
        LDI     0
        STR     RD
        LBR     AR4
AN0:    LOAD    RD, NAPPS       ; LW2 (or LTWRITER) alone, no document: HASDOC = 2 - a new one here, named at its first ^W
        LDN     RD
        XRI     1
        LBNZ    AE1
        LOAD    RD, APPN        ; (STELLAR.PRG is full: LW2 or LTW is enough to know them by)
        LDA     RD
        XRI     'L'
        LBNZ    AE1
        LDA     RD
        XRI     'W'
        LBNZ    AN1B
        LDN     RD
        XRI     '2'
        LBNZ    AE1
        LBR     AN1A
AN1B:   XRI     'W' XOR 'T'
        LBNZ    AE1
        LDN     RD
        XRI     'W'
        LBNZ    AE1
AN1A:
        LOAD    RD, HASDOC
        LDI     2
        STR     RD
        LOAD    RD, DOCNM       ; the name: 11 spaces
        LDI     11
        PLO     RB
AN2:    LDI     ' '
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    AN2
        LOAD    RD, KS_CWD      ; its folder: here
        LOAD    RC, DOCREC
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        INC     RC
        LDI     0
        STR     RC
AE1:    LOAD    R9, FWREC
        SEP     R4
        DW      SETDIR
        SEP     R4
        DW      TRYFW
        LBDF    FW1
        LOAD    R9, FWREC       ; not there: the root, then /BIN, if a name alone
        SEP     R4
        DW      TOROOT
        LBDF    FWB
        SEP     R4
        DW      TRYFW
        LBDF    FW1
FWB:    LOAD    R9, FWREC
        SEP     R4
        DW      INBIN
        LBDF    FW0
        SEP     R4
        DW      TRYFW
        LBDF    FW1
FW0:    LOAD    RD, FWNAME
        SEP     R4
        DW      PNAME
        SEP     R4
        DW      K_PIN
        DB      ' is not on the card, or not a STELLAR firmware (12 KB).',0DH,0AH,0
        SEP     R5
; TRYFW: the firmware's sectors listed (KS_SECLST) from WDIR: DF = 1 there (KS_STLN not 0)
TRYFW:  LOAD    RD, FWNAME
        SEP     R4
        DW      KS_SECLST
        LOAD    RD, KS_STLN
        LDN     RD
        ADI     0FFH            ; DF = 1: not 0
        SEP     R5
FW1:    LOAD    RF, MJOBS       ; job 1: it, to $0000
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
FW2:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    FW2
        LOAD    RD, JP          ; JP = where the next job goes
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
; ---- each app: its header (sector 0), then a job for each block
        LOAD    RD, APPI
        LDI     0
        STR     RD
AP1:    LOAD    RD, APPI
        LDN     RD
        STR     R2
        LOAD    RD, NAPPS
        LDN     RD
        XOR
        LBZ     GO              ; all done
        LDN     R2              ; RD -> APPN + 11 x APPI; APPI + 1
        PLO     RC
        LOAD    RD, APPI
        GLO     RC
        ADI     1
        STR     RD
        GLO     RC              ; x 11 = 8x + 2x + x
        SHL
        SHL
        SHL
        STR     R2
        GLO     RC
        SHL
        ADD
        STR     R2
        GLO     RC
        ADD
        ADI     LOW(APPN)
        PLO     RD
        LDI     HIGH(APPN)
        ADCI    0
        PHI     RD
        SEP     R4              ; its folder
        DW      RECOF
        LOAD    RF, RECP
        GHI     R9
        STR     RF
        INC     RF
        GLO     R9
        STR     RF
        SEP     R4
        DW      SETDIR
        LOAD    RF, CURN        ; (CURN: the name, for messages)
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        SEP     R4
        DW      KS_FINDN        ; on the card?
        LBNF    AP1F
        LOAD    RF, RECP        ; not there: the root, then /BIN, if a name alone
        LDA     RF
        PHI     R9
        LDN     RF
        PLO     R9
        SEP     R4
        DW      TOROOT
        LBDF    AP1B
        SEP     R4
        DW      FINDC
        LBNF    AP1F
AP1B:   LOAD    RF, RECP
        LDA     RF
        PHI     R9
        LDN     RF
        PLO     R9
        SEP     R4
        DW      INBIN
        LBDF    NOAPP
        SEP     R4
        DW      FINDC
        LBDF    NOAPP
AP1F:   LOAD    RD, BADF        ; (an argument it could not take, the app there: say so)
        LDN     RD
        LBNZ    BADN2
        SEP     R4
        DW      KS_FOPEN
        SEP     R4
        DW      KS_FREAD        ; its sector 0 -> DATBUF
        LBDF    NOTSTL
        LOAD    RD, KS_DATBUF   ; 'STL1', then 1 - 32 blocks (all of $4000-$7EFF)
        LOAD    RF, STLID
        LDI     4
        PLO     RB
AP2:    LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    NOTSTL
        DEC     RB
        GLO     RB
        LBNZ    AP2
        LDN     RD
        LBZ     NOTSTL
        SMI     33
        LBDF    NOTSTL
        LDA     RD              ; NBLK, ADDRS = the count and the addresses
        PLO     RB
        LOAD    RF, NBLK
        GLO     RB
        STR     RF
        INC     RF              ; (ADDRS follows NBLK)
        LDI     64
        PLO     RB
AP3:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    AP3
        LOAD    RD, KIDX        ; the file's sectors, through its chain: KIDX = which, SIDX = which in the
        LDI     0               ;  cluster, CCLUS = the cluster
        STR     RD
        INC     RD              ; (SIDX follows KIDX)
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
AP4:    LOAD    RD, CCLUS       ; RC = the cluster: a real one?
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_CLVALID
        LBNF    NOTSTL
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
        LOAD    RD, KIDX        ; sector 0 is the header: no job
        LDN     RD
        LBZ     AP6
        SMI     1               ; a job: 1 sector, to ADDRS[KIDX - 1], from R7
        SHL
        ADI     LOW(ADDRS)
        PLO     RC
        LDI     HIGH(ADDRS)
        ADCI    0
        PHI     RC
        LOAD    RD, JP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     RF              ; room for it?
        SMI     LOW(MAXJOBS)
        GHI     RF
        SMBI    HIGH(MAXJOBS)
        LBDF    MANY
        LDI     1
        STR     RF
        INC     RF
        LDA     RC
        STR     RF
        INC     RF
        LDN     RC
        STR     RF
        INC     RF
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
        LOAD    RD, KIDX        ; the last block?
        LDN     RD
        STR     R2
        LOAD    RD, NBLK
        LDN     RD
        XOR
        LBZ     AP1
AP6:    LOAD    RD, KIDX        ; the next sector: in this cluster, or the next one's first
        LDN     RD
        ADI     1
        STR     RD
        INC     RD
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, KS_SPC
        LDN     RD
        XOR
        LBNZ    AP4
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
        LBDF    NOTSTL
        LOAD    RD, CCLUS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LBR     AP4
; ---- the monitor's breakpoint entry: its RUN's ending, in the ROM
GO:     LOAD    RD, HASDOC      ; a document (or LW2 alone): the file attached
        LDN     RD
        LBZ     GO9
; ---- ATTACH.PRG puts the document in place on the card and writes its note at NOTEB ($7EA0 later)
GA0:    SEP     R4              ; ATTACH.PRG: in /BIN (where RECV SYSTEM puts it: each folder searched
        DW      TOBINC          ;  in vain reads all of it), else here, else in the root
        LBDF    GA0H
        LOAD    RD, ATTN
        SEP     R4
        DW      KS_FINDN
        LBNF    GA0A
GA0H:   LOAD    R9, KS_CWD
        SEP     R4
        DW      SETDIR
        LOAD    RD, ATTN
        SEP     R4
        DW      KS_FINDN
        LBNF    GA0A
        LOAD    RD, KS_WDIR
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, ATTN
        SEP     R4
        DW      KS_FINDN
        LBDF    NOATT
GA0A:   LOAD    RD, KS_LDDST    ; its code to ATTORG (the 6-byte header skipped)
        LDI     HIGH(ATTORG)
        STR     RD
        INC     RD
        LDI     LOW(ATTORG)
        STR     RD
        LOAD    RD, KS_LDSKIP
        LDI     6
        STR     RD
        SEP     R4
        DW      KS_LOADF
        LBDF    KS_LDFAIL
        LOAD    RD, HASDOC      ; LW2 alone: no document - ATTACH gets a new one ready, here (no name yet)
        LDN     RD
        XRI     2
        LBZ     GA1
        LOAD    R9, DOCREC      ; the document's folder: where it is (a name alone: here, else the root) ...
        SEP     R4
        DW      SETDIR
        LOAD    RD, DOCNM
        SEP     R4
        DW      KS_FINDN
        LBNF    GA2F
        LOAD    R9, DOCREC
        SEP     R4
        DW      TOROOT
        LBDF    GA1
        LOAD    RD, DOCNM
        SEP     R4
        DW      KS_FINDN
        LBNF    GA2F
GA1:    LOAD    R9, DOCREC      ; ... or, a new one, where it was named
        SEP     R4
        DW      SETDIR
        LDI     0               ; RC: not ATTFND
        LSKP
GA2F:   LDI     HIGH(ATTFND)    ; RC = ATTFND: found just now - ATTACH takes FINDN's result (no second search)
        PHI     RC
        LDI     LOW(ATTFND)
        PLO     RC
GA2:    LOAD    RD, DOCNM
        SEP     R4
        DW      ATTORG          ; ATTACH: DF = 1 - it said why
        LBDF    GA9
        LOAD    RA, NOTEB       ; the note's job: NOTEB -> $7EA0, 96 bytes
        LOAD    RB, 7EA0H
        LOAD    RC, 96
        SEP     R4
        DW      ADDCP
        LBDF    MANY
        LOAD    RD, HASDOC      ; no name yet: the folder's names too, for Lite-Writer to check a new one
        LDN     RD
        XRI     2
        LBNZ    GO9
        LOAD    RA, NAMESB
        LOAD    RB, LWNAMES
        LOAD    RC, 11 * NAMESMX + 1
        SEP     R4
        DW      ADDCP
        LBDF    MANY
GO9:    LOAD    RA, 8000H
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
        LBZ     FOUND
SC2:    INC     RA
        GHI     RA
        LBNZ    SC1             ; (to $FFFF)
        SEP     R4
        DW      K_PIN
        DB      'No monitor RUN in this ROM: STELLAR cannot start.',0DH,0AH,0
        SEP     R5
; ---- the way back to LTOS: when the program ends (R1), BACK at $0180 boots LTOS again - if the firmware's
;      bytes there are free (0), and not -M; else the monitor's breakpoint, as the monitor's RUN would
FOUND:  LOAD    RD, ROMRA
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, RETMON
        LDN     RD
        LBNZ    FD5
        LOAD    RD, KS_STLLST   ; the firmware's first sector ($0000-$01FF)
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LDI     0
        PHI     R8
        PLO     R8
        LOAD    RF, KS_DATBUF
        SEP     R4
        DW      KS_IDERD
        LBDF    FDE1
        LOAD    RD, KS_DATBUF + BACKA
        LDI     BACKN
        PLO     RB
FD1:    LDA     RD
        LBNZ    FDE2            ; used: the monitor
        DEC     RB
        GLO     RB
        LBNZ    FD1
        LOAD    RD, BACKS       ; BACK -> BACKS, and its job: -> BACKA, after the firmware
        LOAD    RF, BACK
        LDI     BACKN
        PLO     RB
FD2:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    FD2
        LOAD    RA, BACKS
        LOAD    RB, BACKA
        LOAD    RC, BACKN
        SEP     R4
        DW      ADDCP
        LBDF    FDE3
        LOAD    RD, USEBACK
        LDI     1
        STR     RD
        LBR     FD5
FDE1:   SEP     R4              ; (why not: said, so it is not a surprise)
        DW      K_PIN
        DB      '(The firmware could not be read',0
        LBR     FDE9
FDE2:   SEP     R4
        DW      K_PIN
        DB      '(This firmware uses $0180',0
        LBR     FDE9
FDE3:   SEP     R4
        DW      K_PIN
        DB      '(Too many jobs',0
FDE9:   SEP     R4
        DW      K_PIN
        DB      ': programs end at the monitor.)',0DH,0AH,0
FD5:    LOAD    RD, USEBACK     ; RB.1 = USEBACK (STELLAR.PRG's variables are under MON's stub, copied next)
        LDN     RD
        PHI     RB
        LOAD    RD, ROMRA
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, JP          ; the jobs end
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDI     0
        STR     RF
        LOAD    RD, MSTUBD      ; MON's stub to $3000 ...
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
        LOAD    RF, MR1         ; ... R1 for STELLAR (BACK, or the monitor's breakpoint), and its job
        GHI     RB
        LBZ     MR0
        LDI     HIGH(BACKA)
        STR     RF
        INC     RF
        LDI     LOW(BACKA)
        STR     RF
        LBR     MR2
MR0:    INC     RA
        LDA     RA
        STR     RF
        INC     RF
        INC     RA
        INC     RA
        LDN     RA
        STR     RF
MR2:    INC     RF              ; (MACT follows)
        LDI     1
        STR     RF
        SEP     R4
        DW      K_PIN
        DB      'Starting STELLAR ... ',0
GOSTUB: LOAD    R6, 3000H       ; the BIOS's SCRT for MON's stub (LTOS-SH's own goes when STELLAR loads)
        LBR     F_INITCALL
; ---- trouble
; NOAPP: the app is not on the card. Run by the kernel for "LW2 DOC.TXT" (no LW2.PRG: the arguments start at
; the line's first word) and the first app is the one missing: an unknown command, as the kernel says it.
; A script by that name (NAME.SH: here, the root, /BIN) is run instead: "SH NAME ..." (SH.PRG).
NOAPP:  SEP     R4              ; (RD -> the line's first word)
        DW      AUTOQ
        LBNF    NA9
        LOAD    RF, CURN        ; (the first app: its name at APPN)
        LDA     RF
        XRI     HIGH(APPN)
        LBNZ    NA9
        LDN     RF
        XRI     LOW(APPN)
        LBNZ    NA9
        SEP     R4
        DW      SHTRY           ; NAME.SH? (it runs; no return)
        SEP     R4
        DW      E127
        SEP     R4
        DW      K_PIN
        DB      'Unknown command: ',0
NA3:    LDN     RD
        LBZ     NA4
        XRI     ' '
        LBZ     NA4
        LDA     RD
        SEP     R4
        DW      F_TYPE
        LBR     NA3
NA4:    SEP     R4
        DW      K_PIN
        DB      '  (see HELP)',0DH,0AH,0
        SEP     R5
NA9:    SEP     R4
        DW      E127
        SEP     R4
        DW      CPNAME
        SEP     R4
        DW      K_PIN
        DB      ' is not on the card.',0DH,0AH,0
        SEP     R5
; E127: an error - on the screen (the output in a file too), status 127, as sh's. RD kept.
E127:   SEP     R4
        DW      K_TTYON
        LDI     HIGH(K_STAT)
        PHI     RF
        LDI     LOW(K_STAT)
        PLO     RF
        LDI     127
        STR     RF
        SEP     R5
; SHTRY: the first app's name as NAME.SH - in its folder, else the root, else /BIN (a name typed alone): found,
;        the line becomes "SH " and the line from its first word (RD), and the kernel runs that (K_EXEC: never
;        returns). Not found: back, RD kept.
SHTRY:  GLO     RD
        STXD
        GHI     RD
        STXD
        LDI     'S'
        PHI     RC
        LDI     'H'
        PLO     RC
        LDI     ' '
        SEP     R4
        DW      FIND3
        LBDF    SHTN
        IRX                     ; RD = the line from its first word: to DATBUF first (it moves 3 along)
        LDXA
        PHI     RD
        LDX
        PLO     RD
        LOAD    RF, KS_DATBUF
        LDI     252
        PLO     RC
SHT1:   LDA     RD
        STR     RF
        INC     RF
        LBZ     SHT2
        DEC     RC
        GLO     RC
        LBNZ    SHT1
        LDI     0
        STR     RF
SHT2:   LOAD    RF, KS_LINE
        LDI     'S'
        STR     RF
        INC     RF
        LDI     'H'
        STR     RF
        INC     RF
        LDI     ' '
        STR     RF
        INC     RF
        LOAD    RD, KS_DATBUF
SHT3:   LDA     RD
        STR     RF
        INC     RF
        LBNZ    SHT3
        LBR     K_EXEC
SHTN:   IRX
        LDXA
        PHI     RD
        LDX
        PLO     RD
        SEP     R5
; FIND3: the first app's name with the extension RC.1 RC.0 D: in its folder, else the root, else /BIN (a name
;        typed alone) - DF = 0 found (not a folder)
FIND3:  STXD
        LOAD    RF, APPN+10
        IRX
        LDX
        STR     RF
        DEC     RF
        GLO     RC
        STR     RF
        DEC     RF
        GHI     RC
        STR     RF
        LOAD    RF, CURN
        LDI     HIGH(APPN)
        STR     RF
        INC     RF
        LDI     LOW(APPN)
        STR     RF
        LOAD    R9, APREC
        SEP     R4
        DW      SETDIR
        SEP     R4
        DW      FINDC
        LBNF    F3Y
        LOAD    R9, APREC
        SEP     R4
        DW      TOROOT
        LBDF    F3B
        SEP     R4
        DW      FINDC
        LBNF    F3Y
F3B:    LOAD    R9, APREC
        SEP     R4
        DW      INBIN
        LBDF    F3N
        SEP     R4
        DW      FINDC
        LBDF    F3N
F3Y:    LOAD    RD, KS_DATTR    ; (a folder of that name: no)
        LDN     RD
        ANI     10H
        LBNZ    F3N
        SHR
        SEP     R5
F3N:    LDI     1
        SHR
        SEP     R5
; AUTOSH: run by the kernel for "NAME words" (no NAME.PRG), and the words are not ones STELLAR takes: NAME.SH,
;         if there is no NAME.STL (it never returns then)
AUTOSH: LOAD    RD, NAPPS
        LDN     RD
        LBZ     AUS9
        LOAD    RD, KS_LINE
AUS1:   LDN     RD
        XRI     ' '
        LBNZ    AUS2
        INC     RD
        LBR     AUS1
AUS2:   LOAD    RF, ARG0
        LDA     RF
        STR     R2
        GHI     RD
        XOR
        LBNZ    AUS9
        LDN     RF
        STR     R2
        GLO     RD
        XOR
        LBNZ    AUS9
        GLO     RD
        STXD
        GHI     RD
        STXD
        LDI     'S'
        PHI     RC
        LDI     'T'
        PLO     RC
        LDI     'L'
        SEP     R4
        DW      FIND3
        IRX
        LDXA
        PHI     RD
        LDX
        PLO     RD
        LBNF    AUS9
        LBR     SHTRY
AUS9:   SEP     R5
NOTSTL: SEP     R4
        DW      K_TTYON
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R4
        DW      CPNAME
        SEP     R4
        DW      K_PIN
        DB      ' is not a STELLAR app.',0DH,0AH,0
        SEP     R5
FAR:    SEP     R4
        DW      K_PIN
        DB      'That is past sector 65535 - STELLAR cannot load it.',0DH,0AH,0
        SEP     R5
MANY:   SEP     R4
        DW      AUTOSH
        SEP     R4
        DW      K_PIN
        DB      'Too many apps or blocks at once.',0DH,0AH,0
        SEP     R5
; BADN: an argument STELLAR cannot take. Run by the kernel for a word it does not know ("RAWK2 -f ..."): the
;       rest is left and the first app looked for - not on the card, NOAPP says "Unknown command"; there, this.
BADN:   LOAD    RD, BADF
        LDN     RD
        LBNZ    BADN2
        SEP     R4
        DW      AUTOQ
        LBNF    BADN2
        LOAD    RD, NAPPS
        LDN     RD
        LBZ     BADN2
        LOAD    RD, BADF
        LDI     1
        STR     RD
        LBR     ARGEND
BADN2:  SEP     R4
        DW      AUTOSH
        SEP     R4
        DW      K_PIN
        DB      'STELLAR [-M] [firmware.BIN] [app ...] [document]',0DH,0AH,0
        SEP     R5
; AUTOQ: run by the kernel for an unknown command (the arguments start at the line's first word)? DF = 1: yes
AUTOQ:  LOAD    RD, KS_LINE
AQ1:    LDN     RD
        XRI     ' '
        LBNZ    AQ2
        INC     RD
        LBR     AQ1
AQ2:    LOAD    RF, ARG0
        LDA     RF
        STR     R2
        GHI     RD
        XOR
        LBNZ    AQN
        LDN     RF
        STR     R2
        GLO     RD
        XOR
        LBNZ    AQN
        LDI     1
        SHR
        SEP     R5
AQN:    LDI     0
        SHR
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
; CPNAME: CURN's name; PNAME: the 11 bytes at RD - as NAME.EXT
CPNAME: LOAD    RF, CURN
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
PNAME:  LBR     KS_PFNAMD
; RECOF: R9 = APREC + 3 x RC.0 (an app's record). SETDIR: WDIR = the record's folder (R9 kept).
; TOROOT: a name typed alone, not found in a folder: WDIR = the root, DF = 0. Else DF = 1.
RECOF:  GLO     RC
        SHL
        STR     R2
        GLO     RC
        ADD
        ADI     LOW(APREC)
        PLO     R9
        LDI     HIGH(APREC)
        ADCI    0
        PHI     R9
        SEP     R5
; TOBINC: KS_TOBIN, but /BIN's cluster kept in BINC the first time: after it, the root is not read again for it
TOBINC: LOAD    R9, BINC
        LDA     R9
        STR     R2
        LDN     R9
        DEC     R9
        OR
        LBZ     TBC1            ; not known yet
        ADI     0               ; DF = 0: WDIR = BINC (SETDIR)
SETDIR: LOAD    RF, KS_WDIR
        LDA     R9
        STR     RF
        INC     RF
        LDN     R9
        STR     RF
        DEC     R9
        SEP     R5
TBC1:   SEP     R4
        DW      KS_TOBIN
        LBDF    TBC9
        LOAD    R9, BINC        ; (R9 again: the kernel's card routines use it)
        LOAD    RF, KS_WDIR
        LDA     RF
        STR     R9
        INC     R9
        LDN     RF
        STR     R9
TBC9:   SEP     R5
TOROOT: INC     R9
        INC     R9
        LDN     R9              ; a path was given: no
        DEC     R9
        DEC     R9
        LBNZ    TR9
        LDA     R9              ; already the root: no
        STR     R2
        LDN     R9
        DEC     R9
        OR
        LBZ     TR9
        LOAD    RF, KS_WDIR
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        SHR
        SEP     R5
TR9:    LDI     1
        SHR
        SEP     R5
; INBIN: the record at R9: a name typed alone: WDIR = /BIN, DF = 0. Else (or no /BIN) DF = 1.
INBIN:  INC     R9
        INC     R9
        LDN     R9
        DEC     R9
        DEC     R9
        LBNZ    TR9
        LBR     TOBINC
; FINDC: KS_FINDN for CURN's name
FINDC:  LOAD    RF, CURN
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LBR     KS_FINDN
; ADDCP: one more job - copy RC bytes from RA to RB in memory (MON's stub does it last). DF = 1: no room.
ADDCP:  LOAD    RD, JP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     RF              ; room for 7 more and the 0 after?
        ADI     7
        PLO     R9
        GHI     RF
        ADCI    0
        PHI     R9
        GLO     R9
        SMI     LOW(MAXJOBS)
        GHI     R9
        SMBI    HIGH(MAXJOBS)
        LBDF    AC9
        LDI     0FFH
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
        LOAD    RD, JP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        ADI     0               ; DF = 0
AC9:    SEP     R5
NOATT:  SEP     R4
        DW      K_PIN
        DB      'ATTACH.PRG is not on the card.',0DH,0AH,0
GA9:    SEP     R5
ATTN:   DB      'ATTACH  PRG'
LW2N:   DB      'LW2     STL'
DEFNM:  DB      'STELLAR BIN'
STLID:  DB      'STL1'
; BACK - run with P = R1 when a STELLAR program ends: interrupts off, then the BIOS's F_BOOT ($FF00, P = R3,
; RE.1 = 1: the UART), which loads LTOS again. STELLAR's own stack (R2) is still good.
BACK:   DB      0F8H,01H,0BEH           ; LDI 1 / PHI RE
        DB      0F8H,0FFH,0B3H          ; LDI FF / PHI R3
        DB      0F8H,00H,0A3H           ; LDI 0 / PLO R3
        DB      0E2H                    ; SEX R2
        DB      0F8H,23H,52H            ; LDI 23 / STR R2
        DB      71H                     ; DIS: X = 2, P = 3 (-> $FF00), IE = 0
BACKN   EQU     $ - BACK
MSTUBD: INCL    "out/monstub.inc"       ; MON's last step (monstub.asm, assembled at $3000) - its own copy, as MON.PRG's
MSTUBN  EQU     $ - MSTUBD
PEND:
; ---- the variables: at $6B00, not after the code - they must stay clear of MON's stub ($3000-$31FF) and
;      the jobs ($3200 up), which are built while they are in use. START clears them.
        ORG     6B00H           ; (ATTACH.PRG's TEMP runs to $6AFF)
VARS:
FWNAME: DS      11
TMPN:   DS      11
NAPPS:  DS      1
ARG0:   DS      2               ; RF at the start: the arguments
BADF:   DS      1               ; 1: an argument it could not take (BADN)
RETMON: DS      1               ; RETMON, USEBACK: in this order
USEBACK: DS     1
ROMRA:  DS      2
APPN:   DS      44
APPI:   DS      1
FWREC:  DS      3               ; the firmware's folder (2) and 1 = a path was given
APREC:  DS      12              ; the same for each app
RECP:   DS      2
HASDOC: DS      1               ; 1: a document, attached for the app (Lite-Writer 2); 2: LW2 alone (no name yet)
DOCNM:  DS      11
DOCREC: DS      3
CURN:   DS      2
BINC:   DS      2               ; /BIN's first cluster, once TOBINC has found it (0: not yet)
JP:     DS      2
KIDX:   DS      1               ; KIDX, SIDX: in this order
SIDX:   DS      1
CCLUS:  DS      2
NBLK:   DS      1               ; NBLK, ADDRS: in this order
ADDRS:  DS      64
VEND:
        END
