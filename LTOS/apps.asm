; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; apps.asm - APPS.PRG: the STELLAR apps on the card (NAME.STL): each one's blocks, and the VMs it runs in
; (VM1 $4000, VM2 $5000, VM3 $6000, VM4 $7000). STELLAR NAME starts one.
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
        LOAD    RD, KS_PAT      ; every *.STL
        LDI     8
        PLO     RB
A0:     LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    A0
        LDI     'S'
        STR     RD
        INC     RD
        LDI     'T'
        STR     RD
        INC     RD
        LDI     'L'
        STR     RD
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
CP2:    LOAD    RD, VMS         ; VMS, IDX, POS = 0
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
        DB      ' blocks  VM',0
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
        SEP     R4
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
NBLK:   DS      1               ; NBLK, HB: in this order
HB:     DS      32
VMS:    DS      1               ; VMS, IDX, POS: in this order
IDX:    DS      1
POS:    DS      1               ; the blocks read or stepped over after the header
PEND:
        END
