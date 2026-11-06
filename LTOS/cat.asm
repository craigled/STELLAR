; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cat.asm - CAT.PRG: CAT names - the files one after another, as they are (wildcards, folders, as WC's names):
; CR dropped, LF a new line (in a file: LF line ends). No pages - TYPE has those. "CAT A B > C" joins them.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
FLMAX   EQU     100

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
        LDN     RF
        LBZ     USE
        SEP     R4              ; the files
        DW      FLIST
        LOAD    RD, FLN
        LDN     RD
        LBNZ    CA0
        SEP     R4
        DW      K_PIN
        DB      'No file matches.',0DH,0AH,0
        LBR     ST1
CA0:    LOAD    RD, FI
        LDI     0
        STR     RD
; ---- each file: found again, read through
CA1:    LOAD    RD, FI
        LDN     RD
        PLO     RC
        SEP     R4
        DW      FLGET           ; WDIR set, RD -> the name
        SEP     R4
        DW      KS_FINDN
        LBDF    CAN             ; gone since (it cannot be)
        SEP     R4
        DW      KS_FOPEN
CA3:    SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    CA9
        LOAD    RF, KS_DATBUF
CA4:    GHI     RC
        LBNZ    CA5
        GLO     RC
        LBZ     CA3
CA5:    DEC     RC
        LDA     RF
        XRI     0DH
        LBZ     CA4             ; CR: dropped
        XRI     07H             ; (CR xor LF)
        LBZ     CALF
        XRI     0AH
        SEP     R4
        DW      F_TYPE
        LBR     CA4
CALF:   SEP     R4
        DW      K_PCRLF
        LBR     CA4
CA9:    XRI     2               ; D = 2: the chain or the card failed
        LBNZ    CAN
        SEP     R4
        DW      K_TTYON
        SEP     R4
        DW      K_PIN
        DB      0DH,0AH,'** a file could not be read to its end **',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
CAN:    LOAD    RD, FI          ; the next file
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, FLN
        LDN     RD
        SM
        LBNZ    CA1
        SEP     R5
USE:    SEP     R4
        DW      K_PIN
        DB      'CAT names - the files, one after another',0DH,0AH,0
ST1:    LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "tools.inc"
        INCL    "flist.inc"
PEND:
LINES:  DS      1
FI:     DS      1
FLN:    DS      1
FLP:    DS      2
NXARG:  DS      2
FLBUF:  DS      FLMAX * 13
        END
