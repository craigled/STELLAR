; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; apps.asm - APPS.PRG: the STELLAR apps on the card (NAME.STL): each one's blocks, its size, the VMs it runs in
; (VM1 $4000, VM2 $5000, VM3 $6000, VM4 $7000) and its version. STELLAR NAME starts one.
; APPS -P: the programs in /BIN (NAME.PRG): each one's size and version.
; Versions: an .STL keeps one in sector 0 at +128 (RECV takes the first word of a "; VERSION:  v02" line in the .lst); a .PRG
; starts with "VER:1.2",0 at its load address, its header's start address just past it.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        DB      'VER:1.1',0
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        SEP     R4              ; nothing: the .STL apps; -P: the programs in /BIN
        DW      K_SKIPSP
        LDN     RF
        LBZ     STLS
        XRI     '-'
        LBNZ    USAGE
        INC     RF
        LDA     RF
        ANI     0DFH
        XRI     'P'
        LBNZ    USAGE
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USAGE
        LBR     PRGS
USAGE:  SEP     R4
        DW      K_PIN
        DB      'Usage: APPS [-P]',0DH,0AH,0
        SEP     R5
STLS:   SEP     R4
        DW      KS_MNTCHK
        LOAD    RF, EXSTL       ; every *.STL
        SEP     R4
        DW      SETPAT
        LOAD    RD, NAPP
        LDI     0
        STR     RD
        SEP     R4
        DW      KS_DOPEN
A1:     SEP     R4
        DW      KS_DNEXT
        LBDF    AEND
        LOAD    RD, KS_DATTR    ; (a folder named *.STL: not an app)
        LDN     RD
        ANI     10H
        LBNZ    A1
        LOAD    RD, NAPP
        LDN     RD
        ADI     1
        STR     RD
        GHI     RF              ; its name, as NAME (the .STL is understood)
        PHI     RD
        GLO     RF
        PLO     RD
        LDI     8
        PLO     RB
A2:     LDA     RD
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    A2
        SEP     R4
        DW      KS_FOPEN        ; its header
        SEP     R4
        DW      KS_FREAD
        LBDF    ABAD
        LOAD    RD, KS_DATBUF
        LDA     RD
        XRI     'S'
        LBNZ    ABAD
        LDA     RD
        XRI     'T'
        LBNZ    ABAD
        LDA     RD
        XRI     'L'
        LBNZ    ABAD
        LDA     RD
        XRI     '1'
        LBNZ    ABAD
        LDA     RD              ; blocks: NBLK, and each block's address high byte -> HB
        PLO     RA
        LOAD    RF, NBLK
        GLO     RA
        STR     RF
        INC     RF
CP1:    GLO     RA
        LBZ     CP2
        LDA     RD
        STR     RF
        INC     RF
        INC     RD              ; (its low byte: 0)
        DEC     RA
        LBR     CP1
CP2:    LOAD    RF, KS_DATBUF+128       ; its version (0: none), kept: the blocks' sectors are read into DATBUF
        LOAD    RD, VERB
        LDI     16
        PLO     RA
CPV:    LDA     RF
        STR     RD
        INC     RD
        DEC     RA
        GLO     RA
        LBNZ    CPV
        LOAD    RD, VMS         ; VMS, IDX, POS = 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
; A VM runs when its block starts with START ($CD) - as the firmware decides. The .lst's claim lines
; (D 5000 00 ...) put blocks in every app; only $CD counts. So for each block at $4000/$5000/$6000/$7000
; its first sector is read: the ones before it are stepped over (FSEC, FCLUS), not read.
BL1:    LOAD    RD, NBLK
        LDN     RD
        STR     R2
        LOAD    RD, IDX
        LDN     RD
        SM                      ; IDX - NBLK
        LBDF    BLE             ; every block seen
        SEP     R4
        DW      HBI             ; D = HB[IDX]
        ANI     0FH
        LBNZ    BLN             ; not the start of a VM's block
        SEP     R4
        DW      HBI
        SMI     40H
        LBNF    BLN
        SMI     40H
        LBDF    BLN
BS1:    LOAD    RD, POS         ; step over the blocks before it
        LDN     RD
        STR     R2
        LOAD    RD, IDX
        LDN     RD
        SM
        LBZ     BS2
        SEP     R4
        DW      SKIP
        LOAD    RD, POS
        LDN     RD
        ADI     1
        STR     RD
        LBR     BS1
BS2:    SEP     R4
        DW      KS_FREAD
        LBDF    BLE             ; (the file is short: stop)
        LOAD    RD, POS
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, KS_DATBUF
        LDN     RD
        XRI     0CDH
        LBNZ    BLN
        SEP     R4
        DW      HBI             ; its VM's bit: 1 << (HB / 16 - 4)
        SHR
        SHR
        SHR
        SHR
        SMI     4
        PLO     RB
        LDI     1
BB1:    PLO     RF
        GLO     RB
        LBZ     BB2
        DEC     RB
        GLO     RF
        SHL
        LBR     BB1
BB2:    LOAD    RD, VMS
        GLO     RF
        STR     R2
        LDN     RD
        OR
        STR     RD
BLN:    LOAD    RD, IDX
        LDN     RD
        ADI     1
        STR     RD
        LBR     BL1
BLE:    LOAD    RD, VMS
        LDN     RD
        PLO     R9              ; R9.0 = the VMs, a bit each
        LOAD    RD, NBLK
        LDN     RD
        PLO     RC              ; RC.0 = the blocks, to print
AV3:    SEP     R4
        DW      K_PIN
        DB      '  ',0
        GLO     RC
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' blocks  ',0
        GLO     RC              ; and the size: 512 bytes a block -> blocks / 2 KB, .5 for an odd count
        SHR
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        GLO     RC
        ANI     1
        LBZ     AV3K
        SEP     R4
        DW      K_PIN
        DB      '.5',0
AV3K:   SEP     R4
        DW      K_PIN
        DB      ' KB  VM',0
        LDI     1               ; RB.0 = the VM's number, RB.1 = its bit
        PLO     RB
        PHI     RB
AV4:    GHI     RB
        STR     R2
        GLO     R9
        AND
        LBZ     AV5
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        GLO     RB
        ADI     '0'
        SEP     R4
        DW      F_TYPE
AV5:    GHI     RB
        SHL
        PHI     RB
        INC     RB
        GLO     RB
        XRI     5
        LBNZ    AV4
        LOAD    RD, VERB        ; and its version
        LDN     RD
        LBZ     AV6
        SEP     R4
        DW      K_PIN
        DB      '  ',0
        LOAD    RD, VERB
        SEP     R4
        DW      PVER
AV6:    SEP     R4
        DW      K_PCRLF
        LBR     A1
ABAD:   SEP     R4
        DW      K_PIN
        DB      '  - not a STELLAR app',0DH,0AH,0
        LBR     A1
AEND:   LOAD    RD, NAPP
        LDN     RD
        LBNZ    AE1
        SEP     R4
        DW      K_PIN
        DB      'No apps on the card - RECV NAME.STL makes one from its .lst.',0DH,0AH,0
AE1:    SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
; ---- APPS -P: the programs in /BIN - NAME, the size (KB, to the half), the version if it has one
PRGS:   SEP     R4
        DW      KS_MNTCHK
        SEP     R4
        DW      KS_TOBIN
        LBNF    PG0
        SEP     R4
        DW      K_PIN
        DB      'No /BIN folder on the card.',0DH,0AH,0
        SEP     R5
PG0:    LOAD    RF, EXPRG
        SEP     R4
        DW      SETPAT
        LOAD    RD, NAPP
        LDI     0
        STR     RD
        SEP     R4
        DW      KS_DOPEN
PG1:    SEP     R4
        DW      KS_DNEXT
        LBDF    PGEND
        LOAD    RD, KS_DATTR    ; (a folder named *.PRG: not a program)
        LDN     RD
        ANI     10H
        LBNZ    PG1
        LOAD    RD, NAPP
        LDN     RD
        ADI     1
        STR     RD
        GHI     RF              ; its name
        PHI     RD
        GLO     RF
        PLO     RD
        LDI     8
        PLO     RB
PG2:    LDA     RD
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    PG2
        LOAD    RD, KS_DSIZE+3  ; halves of a KB: (size + 511) / 512 (the size's low 16 bits: a program is < 64 KB)
        LDN     RD
        ADI     0FFH
        DEC     RD
        LDN     RD
        ADCI    1
        SHRC
        PLO     R9              ; R9.0 = the halves
        LDI     0
        PHI     R8
        PLO     R8
        PHI     R7
        GLO     R9
        SHR
        PLO     R7              ; R8:R7 = whole KBs
        GLO     R9
        ANI     1
        LBZ     PG3
        LDI     2               ; " 3.5" / "  14": KB lines up
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      K_PIN
        DB      '.5',0
        LBR     PG4
PG3:    LDI     4
        SEP     R4
        DW      KS_PDEC32
PG4:    SEP     R4
        DW      K_PIN
        DB      ' KB',0
        SEP     R4              ; its header and first bytes: "VER:" at its load address, started past?
        DW      KS_FOPEN
        SEP     R4
        DW      KS_FREAD
        LBDF    PGNL
        GHI     RC
        LBNZ    PG5
        GLO     RC
        SMI     11
        LBNF    PGNL
PG5:    LOAD    RD, KS_DATBUF+4 ; the start is not the load address
        LOAD    RF, KS_DATBUF
        LDA     RF
        SEX     RD
        XOR
        PLO     RC
        INC     RD
        LDN     RF
        XOR
        SEX     R2
        STR     R2
        GLO     RC
        OR
        LBZ     PGNL
        LOAD    RD, KS_DATBUF+6 ; "VER:"
        LOAD    RF, VERTAG
        LDI     4
        PLO     RB
PG6:    LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    PGNL
        DEC     RB
        GLO     RB
        LBNZ    PG6
        SEP     R4
        DW      K_PIN
        DB      '  ',0
        SEP     R4              ; RD -> the version
        DW      PVER
PGNL:   SEP     R4
        DW      K_PCRLF
        LBR     PG1
PGEND:  LOAD    RD, NAPP
        LDN     RD
        LBNZ    PGE1
        SEP     R4
        DW      K_PIN
        DB      'No programs in /BIN.',0DH,0AH,0
PGE1:   SEP     R5
; SETPAT: KS_PAT = ????????EXT, the extension's 3 letters at RF
SETPAT: LOAD    RD, KS_PAT
        LDI     8
        PLO     RB
SP1:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    SP1
        LDI     3
        PLO     RB
SP2:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    SP2
        SEP     R5
; PVER: the version at RD - at most 15 characters, up to a 0 (or anything not printable)
PVER:   LDI     15
        PLO     RB
PV1:    LDN     RD
        SMI     20H
        LBNF    PV9
        SMI     5FH
        LBDF    PV9
        LDA     RD
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    PV1
PV9:    SEP     R5
EXSTL:  DB      'STL'
EXPRG:  DB      'PRG'
VERTAG: DB      'VER:'
; HBI: D = HB[IDX]
HBI:    LOAD    RD, IDX
        LDN     RD
        ADI     LOW(HB)
        PLO     RD
        LDI     HIGH(HB)
        ADCI    0
        PHI     RD
        LDN     RD
        SEP     R5
; SKIP: the open file's next sector stepped over, not read (FREAD's FSEC / FCLUS, as FREAD moves them)
SKIP:   LOAD    RD, KS_FCLUS + 2        ; FSEC (follows FCLUS)
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, KS_SPC
        LDN     RD
        XOR
        LBNZ    SK9
        LOAD    RD, KS_FCLUS + 2        ; FSEC = 0, and the next cluster
        LDI     0
        STR     RD
        LOAD    RD, KS_FCLUS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_FATNEXT
        LOAD    RD, KS_FCLUS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
SK9:    SEP     R5
NAPP:   DS      1
VERB:   DS      16              ; an .STL's version
NBLK:   DS      1               ; NBLK, HB: in this order
HB:     DS      32
VMS:    DS      1               ; VMS, IDX, POS: in this order
IDX:    DS      1
POS:    DS      1               ; the blocks read or stepped over after the header
PEND:
        END
