; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; squeeze.asm - SQUEEZE.PRG: SQUEEZE - the root folder's deleted entries taken out, the rest packed together.
;   Every name LTOS looks for (each program, a .SH before it) is looked for in the root before /BIN, and a lookup
;   reads the root up to its last entry - deleted ones too. A root that once held many files is read far
;   further than its files need. This packs its entries to the front, in the same order (a long name stays just
;   before its file, hidden files and the card's label stay), and clears the sectors after them.
;   First it counts and asks. Then: each root sector is read and the entries kept go into the next sector to be
;   written - which is never one not read yet, as packing only moves entries forward. Files' clusters and the
;   FATs are not touched. (A power cut half-way can leave an entry twice: FSCK then says so.)
; verify_squeeze.py runs it on the simulated Elf2K.
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
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USE
        LOAD    RD, LIVE        ; LIVE (2), DEAD (2), LASTS: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
; ---- 1: count
        LDI     0
        PLO     R9              ; R9.0 = the sector
P1:     SEP     R4
        DW      ATEND
        LBDF    P1E
        SEP     R4
        DW      RDSEC
        LOAD    RF, IB
        LDI     16
        PHI     R9              ; R9.1 = entries left in it
P11:    LDN     RF
        LBZ     P1X             ; the end of the folder
        XRI     0E5H
        LBNZ    P12
        LOAD    RD, DEAD + 1
        LBR     P13
P12:    LOAD    RD, LIVE + 1
P13:    LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R4
        DW      NEXTE
        GHI     R9
        SMI     1
        PHI     R9
        LBNZ    P11
        INC     R9
        LBR     P1
P1X:    INC     R9              ; (the sector with the end counts: it is cleared too)
P1E:    LOAD    RD, LASTS
        GLO     R9
        STR     RD
        SEP     R4
        DW      K_PIN
        DB      'The root folder: ',0
        LOAD    RF, LIVE
        SEP     R4
        DW      PNUM
        SEP     R4
        DW      K_PIN
        DB      ' entries and ',0
        LOAD    RF, DEAD
        SEP     R4
        DW      PNUM
        SEP     R4
        DW      K_PIN
        DB      ' deleted ones, in ',0
        LOAD    RD, LASTS
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' sectors.',0DH,0AH,0
        LOAD    RD, DEAD
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    ASK
        SEP     R4
        DW      K_PIN
        DB      'Nothing to squeeze.',0DH,0AH,0
        LBR     K_MAIN
ASK:    SEP     R4
        DW      K_TTYON
        SEP     R4
        DW      K_PIN
        DB      'Take the deleted ones out? (Y/N) ',0
        SEP     R4
        DW      K_YESNO
        LBNF    K_MAIN
; ---- 2: the entries kept, packed; RA.0 = the sector written next, RB -> the next place in OB
        LDI     0
        PLO     R9
        PLO     RA
        LOAD    RB, OB
P2:     LOAD    RD, LASTS       ; past the last sector with entries?
        LDN     RD
        STR     R2
        GLO     R9
        XOR
        LBZ     P2E
        SEP     R4
        DW      RDSEC
        LOAD    RF, IB
        LDI     16
        PHI     R9
P21:    LDN     RF
        LBZ     P2E             ; the end
        XRI     0E5H
        LBZ     P23             ; deleted: left out
        LDI     32              ; kept: into OB
        PLO     RD
P22:    LDA     RF
        STR     RB
        INC     RB
        DEC     RD
        GLO     RD
        LBNZ    P22
        GHI     RB              ; OB full: written
        XRI     HIGH(OB + 512)
        LBNZ    P24
        SEP     R4
        DW      WROB
        LBR     P24
P23:    SEP     R4
        DW      NEXTE
P24:    GHI     R9
        SMI     1
        PHI     R9
        LBNZ    P21
        INC     R9
        LBR     P2
P2E:    GHI     RB              ; the last sector of entries: the rest of it 0
        XRI     HIGH(OB)
        LBNZ    P25
        GLO     RB
        LBZ     P27             ; (nothing in it)
P25:    LDI     0
        STR     RB
        INC     RB
        GHI     RB
        XRI     HIGH(OB + 512)
        LBNZ    P25
        SEP     R4
        DW      WROB
P27:    LOAD    RD, NEW         ; the sectors with entries now
        GLO     RA
        STR     RD
P28:    LOAD    RD, LASTS       ; and the ones after them, up to where the old end was: cleared
        LDN     RD
        STR     R2
        GLO     RA
        SD
        LBNF    P29
        LBZ     P29
        LOAD    RB, OB
P281:   LDI     0
        STR     RB
        INC     RB
        GHI     RB
        XRI     HIGH(OB + 512)
        LBNZ    P281
        SEP     R4
        DW      WROB
        LBR     P28
P29:    LOAD    RD, KS_DSEC     ; LTOS's own copy of a directory sector: read again
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      K_PIN
        DB      'Squeezed: ',0
        LOAD    RF, LIVE
        SEP     R4
        DW      PNUM
        SEP     R4
        DW      K_PIN
        DB      ' entries, now in ',0
        LOAD    RD, NEW
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' sectors.',0DH,0AH,0
        LBR     K_MAIN
; ATEND: DF = 1: R9.0 is past the root folder's sectors
ATEND:  LOAD    RD, KS_ROOTSECS
        LDA     RD
        LBNZ    AE1             ; (more than 255: never, for FAT16's 512 entries)
        LDN     RD
        STR     R2
        GLO     R9
        SM
        SEP     R5
AE1:    ADI     0
        SEP     R5
; NEXTE: RF past the entry (+32)
NEXTE:  GLO     RF
        ADI     32
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        SEP     R5
; RDSEC: root sector R9.0 -> IB. WROB: OB -> root sector RA.0, then RA + 1, RB = OB (RF kept). A card failure: said, stopped.
RDSEC:  GLO     R9
        SEP     R4
        DW      LBAOF
        LOAD    RF, IB
        SEP     R4
        DW      KS_IDERD
        LBDF    BAD
        SEP     R5
WROB:   GHI     RF              ; (RF: where the caller is in IB - kept)
        STXD
        GLO     RF
        STXD
        GLO     RA
        SEP     R4
        DW      LBAOF
        LOAD    RF, OB
        SEP     R4
        DW      KS_IDEWR
        LBDF    BAD
        INC     RA
        LOAD    RB, OB
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        SEP     R5
; LBAOF: R8:R7 = the root's first sector + D
LBAOF:  PLO     RC
        LDI     0
        PHI     RC
        LOAD    RD, KS_ROOTLBA
        SEP     R4
        DW      KS_LD32
        LBR     KS_ADD16
BAD:    SEP     R4
        DW      K_PIN
        DB      'The card failed. Run FSCK: the root folder may need it.',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
; PNUM: the 16-bit number at RF (big-endian)
PNUM:   LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LBR     K_PDEC
USE:    SEP     R4
        DW      K_PIN
        DB      'SQUEEZE - takes the deleted entries out of the root folder (HELP SQUEEZE)',0DH,0AH,0
        LBR     K_MAIN
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        LBR     K_MAIN
PEND:
LIVE:   DS      2               ; LIVE, DEAD, LASTS: in this order
DEAD:   DS      2
LASTS:  DS      1
NEW:    DS      1
DATA    EQU     ((NEW + 1 + 511) / 512) * 512
OB      EQU     DATA            ; (512-aligned: OB + 512's low byte is 0)
IB      EQU     DATA + 200H
        END
