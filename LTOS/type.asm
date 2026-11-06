; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; type.asm - TYPE.PRG: TYPE name - a text file, a screen at a time (HELP is TYPE HELP.TXT).
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
; ---- TYPE name: CR dropped, LF -> a new line; a pause every 22 lines
        SEP     R4              ; (not NAMEARG: FINDN finds hidden files too)
        DW      KS_MNTCHK
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_NAMEP
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_NOFILE
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    KS_ISDIR
        SEP     R4
        DW      KS_FOPEN
        LDI     0
        PLO     R9              ; R9.0 = lines on this screen
        PHI     R9              ; R9.1 = 1 if the last thing printed was not a new line
TL1:    SEP     R4
        DW      KS_FREAD
        LBDF    TLEND
        LOAD    RF, KS_DATBUF
TL2:    GHI     RC
        LBNZ    TL3
        GLO     RC
        LBZ     TL1
TL3:    DEC     RC
        LDA     RF
        XRI     0DH
        LBZ     TL2             ; CR: dropped
        XRI     07H             ; (CR xor LF: now zero if it was LF)
        LBZ     TLLF
        XRI     0AH
        PLO     RA
        SMI     ' '
        LBDF    TL4
        GLO     RA
        XRI     09H
        LBZ     TL4             ; a TAB goes out as it is
        LDI     '.'             ; other control characters: a dot
        PLO     RA
TL4:    GLO     RA
        SEP     R4
        DW      F_TYPE
        LDI     1
        PHI     R9
        LBR     TL2
TLLF:   SEP     R4
        DW      KS_PCRLF
        LDI     0
        PHI     R9
        INC     R9
        GLO     R9
        XRI     22
        LBNZ    TL2
        PLO     R9              ; (0) a full screen: wait - but not with the output in a file
        LOAD    RA, K_RDIR
        LDN     RA
        LBNZ    TL2
        SEP     R4
        DW      KS_PIN
        DB      '-- more: a key goes on, Q stops --',0
        SEP     R4
        DW      F_READ
        PLO     RA
        SEP     R4
        DW      KS_PIN
        DB      0DH,'                                   ',0DH,0
        GLO     RA
        ANI     0DFH
        XRI     'Q'
        LBZ     TLQ
        GLO     RA
        XRI     03H
        LBZ     TLQ
        GLO     RA
        XRI     1BH
        LBNZ    TL2
TLQ:    SEP     R5     
TLEND:  XRI     2               ; D = 2: the chain or the card failed
        LBNZ    TLE2
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'** the file could not be read to its end **',0
        LDI     1
        PHI     R9
TLE2:   GHI     R9
        LBZ     KS_MAIN
        SEP     R4
        DW      KS_PCRLF
        SEP     R5     

OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
PEND:
        END
