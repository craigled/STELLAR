; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lcov0.asm - LC.OVL's part 0: View and Info. Loaded by LC.PRG (OVLD) into OVLA when wanted; it uses LC.PRG's
;   routines and variables by their names (out/lcsyms.inc, written by build.py from lc.asm's listing).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
        INCL    "lc.inc"
        INCL    "out/lcsyms.inc"

        ORG     OVLA
        DW      PEND            ; (this LC.PRG's: LC.PRG checks it)
        DB      0
        LBR     OVIEW
        LBR     OFINFO

; ==== View (3 / F3, or Enter on a file): the file a page (22 rows) at a time, as text or in hex (H). The kernel's
;   FOPEN / FREAD read it a sector at a time into DATBUF; where each page starts is kept (VPT: FREAD's place before
;   that sector, the offset in it, the text's flags), so a page back is read again from there, never from the start.
OVIEW:  LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        LDI     P_CUR
        SEP     R4
        DW      GETF
        SEP     R4
        DW      ENTP
        SEP     R4
        DW      SETREC          ; RECP; DF = 1: a folder
        LBNF    VW1
        SEP     R4
        DW      MSGI
        DB      'A folder: Enter goes into it. View is for files.',0
        SEP     R5
VW1:    SEP     R4
        DW      MKPATH
        SEP     R4
        DW      VOPEN           ; FOPEN; page 0's start = there
        LOAD    RD, VMODE       ; text, unless the first sector has bytes that are not
        LDI     0
        STR     RD
        SEP     R4
        DW      VFILL
        LOAD    RD, VLEFT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RF, KS_DATBUF
VW2:    GLO     RC
        STR     R2
        GHI     RC
        OR
        LBZ     VSTART
        DEC     RC
        LDA     RF
        PLO     R7
        ANI     80H
        LBNZ    VW3
        GLO     R7
        SMI     20H
        LBDF    VW2
        GLO     R7              ; a control byte: Tab LF FF CR Ctrl-Z Esc are text's
        XRI     09H
        LBZ     VW2
        XRI     09H XOR 0AH
        LBZ     VW2
        XRI     0AH XOR 0CH
        LBZ     VW2
        XRI     0CH XOR 0DH
        LBZ     VW2
        XRI     0DH XOR 1AH
        LBZ     VW2
        XRI     1AH XOR 1BH
        LBZ     VW2
VW3:    LOAD    RD, VMODE
        LDI     1
        STR     RD
VSTART: LOAD    RD, VPG
        LDI     0
        STR     RD
        SEP     R4
        DW      INL
        DB      ESC,'[0m',ESC,'[2J',ESC,'[24;1H'
        DB      ' Space next page   b back   Home  End   H hex or text   Esc back to the panes',0
VPGO:   SEP     R4
        DW      VGO
        SEP     R4
        DW      VDRAW
        SEP     R4
        DW      VHEAD
VKEY:   SEP     R4
        DW      KEY
        PLO     R7
        LOAD    RF, VKTAB       ; key, where (2) ... 0
VK1:    LDA     RF
        LBZ     VKEY
        STR     R2
        GLO     R7
        XOR
        LBZ     VK2
        INC     RF
        INC     RF
        LBR     VK1
VK2:    LDA     RF
        PHI     R7
        LDN     RF
        PLO     R7
        LOAD    RD, JMPV
        LDI     0C0H
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        LBR     JMPV
VKTAB:  DB      ESC
        DW      DRAWALL
        DB      'q'
        DW      DRAWALL
        DB      'Q'
        DW      DRAWALL
        DB      '3'
        DW      DRAWALL
        DB      ' '
        DW      VNEXT
        DB      KPD
        DW      VNEXT
        DB      KDN
        DW      VNEXT
        DB      0DH
        DW      VNEXT
        DB      'b'
        DW      VPREV
        DB      'B'
        DW      VPREV
        DB      KPU
        DW      VPREV
        DB      KUP
        DW      VPREV
        DB      KHM
        DW      VHOME
        DB      KEN
        DW      VENDK
        DB      'h'
        DW      VHEX
        DB      'H'
        DW      VHEX
        DB      0
VNEXT:  SEP     R4
        DW      VMORE
        LBNF    VKEY
        LOAD    RD, VPG
        LDN     RD
        ADI     1
        STR     RD
        LBR     VPGO
VPREV:  LOAD    RD, VPG
        LDN     RD
        LBZ     VKEY
        SMI     1
        STR     RD
        LBR     VPGO
VHOME:  LOAD    RD, VPG
        LDI     0
        STR     RD
        LBR     VPGO
VHEX:   LOAD    RD, VMODE
        LDN     RD
        XRI     1
        STR     RD
        LBR     VSTART
VENDK:  LOAD    RD, NODRAW      ; End: the pages read on (not drawn, the title kept up) to the last - or to a key
        LDI     1
        STR     RD
VE1:    SEP     R4
        DW      VMORE
        LBNF    VE2
        SEP     R4              ; a key waiting: stop here
        DW      POLL
        LOAD    RD, KQH
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        LBNZ    VE2
        LOAD    RD, VPG         ; (the reading goes straight on: no VGO)
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      VDRAW
        SEP     R4
        DW      VHEAD
        LBR     VE1
VE2:    LOAD    RD, NODRAW
        LDI     0
        STR     RD
        LBR     VPGO
; VMORE: DF = 1 if there is a page after this one (not the end, and room in VPT)
VMORE:  LOAD    RD, VEOFP
        LDN     RD
        LBNZ    GRNO
        LOAD    RD, VPG
        LDN     RD
        XRI     VPMAX - 1
        LBZ     GRNO
        LBR     GRYES
; VOPEN: the file RECP opened (the kernel's DCLUS DSIZE from its record, FOPEN); VPT's page 0 = there
VOPEN:  SEP     R4
        DW      GETREC
        GLO     RF
        ADI     16
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, KS_DCLUS    ; (DCLUS, then DSIZE)
        LOAD    RC, 6
        SEP     R4
        DW      MCOPY
        SEP     R4
        DW      KS_FOPEN
        LOAD    RF, KS_FCLUS
        LOAD    RD, VPT
        LOAD    RC, 7
        SEP     R4
        DW      MCOPY
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, VLEFT
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R5
; VFILL: the next sector into DATBUF (VSNAP = FREAD's place before it); VPTR, VLEFT. RA kept. None: VLEFT 0.
VFILL:  GLO     RA
        STXD
        GHI     RA
        STXD
        LOAD    RF, KS_FCLUS
        LOAD    RD, VSNAP
        LOAD    RC, 7
        SEP     R4
        DW      MCOPY
        SEP     R4
        DW      KS_FREAD
        LBNF    VF1
        LOAD    RD, KS_FREM     ; (the card failed: as if at the end)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RC, 0
VF1:    LOAD    RD, VLEFT
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, VPTR
        LDI     HIGH(KS_DATBUF)
        STR     RD
        INC     RD
        LDI     LOW(KS_DATBUF)
        STR     RD
        IRX
        LDXA
        PHI     RA
        LDX
        PLO     RA
        SEP     R5
; GETB: DF = 0 and D = the file's next byte; DF = 1 at its end. RD RF used (and VFILL's).
GETB:   LOAD    RD, VLEFT
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    GB2
        SEP     R4
        DW      FREMZ
        LBDF    RET0
        SEP     R4
        DW      VFILL
        LOAD    RD, VLEFT
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     GRYES
GB2:    LOAD    RD, VLEFT + 1   ; VLEFT - 1
        LDN     RD
        SMI     1
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        LOAD    RD, VPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDA     RF
        STR     R2
        GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        LDN     R2
        ADI     0
        SEP     R5
; FREMZ: DF = 1 if the kernel's FREM is 0 (nothing more to read)
FREMZ:  LOAD    RD, KS_FREM
        LDA     RD
        STR     R2
        LDA     RD
        OR
        STR     R2
        LDA     RD
        OR
        STR     R2
        LDN     RD
        OR
        LBZ     GRYES
        LBR     GRNO
; VPTE: RF -> VPT's entry for page D (D x 10)
VPTE:   PLO     RF
        LDI     0
        PHI     RF
        GLO     RF
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF              ; 2p
        GLO     RF
        STR     R2
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF
        GLO     RF
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF              ; 8p
        GLO     RF
        ADD
        PLO     RF
        GHI     RF
        ADCI    HIGH(VPT)       ; + 2p (2p < 256) + VPT
        PHI     RF
        SEP     R5
; VGO: back to the start of page VPG: FREAD's place, the sector read and the offset skipped, the flags;
;      VOFS = VPG x 352 (the hex offset); VEOFP 0
VGO:    LOAD    RD, VPG
        LDN     RD
        SEP     R4
        DW      VPTE
        LOAD    RD, KS_FCLUS
        LOAD    RC, 7
        SEP     R4
        DW      MCOPY
        LDA     RF
        PHI     RA
        LDA     RF
        PLO     RA              ; RA = the offset
        LDN     RF
        PLO     R7
        LOAD    RD, VFLAG
        GLO     R7
        STR     RD
        LOAD    RD, VEOFP
        LDI     0
        STR     RD
        LOAD    RD, VLEFT
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        GHI     RA
        STR     R2
        GLO     RA
        OR
        LBZ     VG2
        SEP     R4
        DW      VFILL
        LOAD    RD, VPTR + 1    ; VPTR + the offset, VLEFT - it
        GLO     RA
        STR     R2
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        GHI     RA
        STR     R2
        LDN     RD
        ADC
        STR     RD
        LOAD    RD, VLEFT + 1
        GLO     RA
        STR     R2
        LDN     RD
        SM
        STR     RD
        DEC     RD
        GHI     RA
        STR     R2
        LDN     RD
        SMB
        STR     RD
VG2:    LOAD    RD, VOFS        ; VOFS = VPG x 352
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, VPG
        LDN     RD
        PLO     R7
VG3:    GLO     R7
        LBZ     RET0
        LOAD    RD, VOFS + 2
        LDN     RD
        ADI     LOW(352)
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    HIGH(352)
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        DEC     R7
        LBR     VG3
; VDRAW: page VPG's 22 rows (rows 2-23; NODRAW: read, not drawn), then the next page's start kept in VPT
VDRAW:  LOAD    RD, VROW
        LDI     0
        STR     RD
VD1:    LOAD    RD, VMODE
        LDN     RD
        LBNZ    VD2
        SEP     R4
        DW      VTROW
        LBR     VD3
VD2:    SEP     R4
        DW      VHROW
VD3:    LOAD    RD, NODRAW
        LDN     RD
        LBNZ    VD4
        LOAD    RD, VROW
        LDN     RD
        ADI     2
        PHI     RB
        LDI     1
        PLO     RB
        SEP     R4
        DW      CUP
        LOAD    RF, LBUF
        SEP     R4
        DW      PUTS
        GLO     RF              ; (LBUF's low byte 0: RF.0 = the length + 1)
        SMI     81
        LBDF    VD4
        SEP     R4
        DW      INL
        DB      ESC,'[K',0
VD4:    LOAD    RD, VROW
        LDN     RD
        ADI     1
        STR     RD
        XRI     22
        LBNZ    VD1
        LOAD    RD, VEOFP       ; the end met: no next page
        LDN     RD
        LBNZ    RET0
        LOAD    RD, VLEFT       ; the sector used up: the next page starts with the next sector
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    VD6
        SEP     R4
        DW      FREMZ
        LBNF    VD5
        LOAD    RD, VEOFP       ; and there is none: this is the last page
        LDI     1
        STR     RD
        SEP     R5
VD5:    LOAD    RF, KS_FCLUS
        LOAD    RD, VSNAP
        LOAD    RC, 7
        SEP     R4
        DW      MCOPY
        LOAD    RD, VPTR        ; (offset 0: VPTR = DATBUF)
        LDI     HIGH(KS_DATBUF)
        STR     RD
        INC     RD
        LDI     LOW(KS_DATBUF)
        STR     RD
VD6:    SEP     R4
        DW      VMORE           ; (the last page VPT keeps: no more)
        LBNF    RET0
        LOAD    RD, VPG
        LDN     RD
        ADI     1
        SEP     R4
        DW      VPTE
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        LOAD    RF, VSNAP
        LOAD    RC, 7
        SEP     R4
        DW      MCOPY
        LOAD    RF, VPTR + 1    ; the offset: VPTR - DATBUF
        LDN     RF
        SMI     LOW(KS_DATBUF)
        PLO     R7
        DEC     RF
        LDN     RF
        SMBI    HIGH(KS_DATBUF)
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        INC     RD
        LOAD    RF, VFLAG
        LDN     RF
        STR     RD
        SEP     R5
; VTROW: a text row into LBUF (up to 80): LF, CR or CR LF ends a line; a longer line goes on in the next row;
;   Tab to the next 8th column; other control bytes and those from $7F up as '.'. VFLAG: 1 a CR just ended a
;   line (an LF next is its), 2 the last row was full (an LF or CR next ends that line).
VTROW:  LOAD    RA, LBUF        ; (RF -> the next byte, RC the bytes left, R9.0 the flags: VLD / VST)
        SEP     R4
        DW      VLD
VT1:    GLO     RC
        LBNZ    VT1F
        GHI     RC
        LBNZ    VT1F
        SEP     R4              ; the sector used up: GETB reads the next one (or says the end)
        DW      VST
        SEP     R4
        DW      GETB
        LBDF    VTEOF
        PLO     R7
        SEP     R4
        DW      VLD
        GLO     R7
        LBR     VT2
VT1F:   LDA     RF
        DEC     RC
VT2:    PLO     R7
        GLO     R9
        LBZ     VT3
        PLO     R8
        LDI     0
        PLO     R9
        GLO     R7
        XRI     0AH
        LBZ     VT1             ; LF after a CR, or after a full row: that line's
        GLO     R8
        ANI     2
        LBZ     VT3
        GLO     R7              ; a CR after a full row: that line's end too
        XRI     0DH
        LBNZ    VT3
        LDI     1
        PLO     R9
        LBR     VT1
VT3:    GLO     R7
        XRI     0AH
        LBZ     VTEND
        GLO     R7
        XRI     0DH
        LBNZ    VT4
        LDI     1
        PLO     R9
        LBR     VTEND
VT4:    GLO     R7
        XRI     09H
        LBNZ    VT6
VT5:    LDI     ' '
        STR     RA
        INC     RA
        GLO     RA
        ANI     07H
        LBNZ    VT5
        LBR     VT8
VT6:    GLO     R7
        SMI     20H
        LBNF    VT7
        GLO     R7
        SMI     7FH
        LBDF    VT7
        GLO     R7
        LSKP
VT7:    LDI     '.'
        STR     RA
        INC     RA
VT8:    GLO     RA
        XRI     80
        LBNZ    VT1
        LDI     2
        PLO     R9
VTEND:  SEP     R4
        DW      VST
        LDI     0
        STR     RA
        SEP     R5
VTEOF:  LOAD    RD, VEOFP       ; (the place is stored already)
        LDI     1
        STR     RD
        LDI     0
        STR     RA
        SEP     R5
; VLD: RF = VPTR, RC = VLEFT, R9.0 = VFLAG.  VST: them back.
VLD:    LOAD    RD, VPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, VLEFT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, VFLAG
        LDN     RD
        PLO     R9
        SEP     R5
VST:    LOAD    RD, VPTR
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, VLEFT
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, VFLAG
        GLO     R9
        STR     RD
        SEP     R5
; VHROW: a hex row into LBUF: OOOOOO  hh hh .. hh  hh .. hh  ascii (16 bytes; fewer at the end; none: blank)
VHROW:  LOAD    RA, LBUF        ; (as VTROW: the place in RF RC; R8.1 = the bytes got)
        SEP     R4
        DW      VLD
        LDI     0
        PHI     R8
VH1:    GLO     RC
        LBNZ    VH1F
        GHI     RC
        LBNZ    VH1F
        SEP     R4
        DW      VST
        SEP     R4
        DW      GETB
        LBDF    VH2
        PLO     R7
        SEP     R4
        DW      VLD
        GLO     R7
        LBR     VH1B
VH1F:   LDA     RF
        DEC     RC
VH1B:   PLO     R7
        GHI     R8
        ADI     LOW(HBUF)
        PLO     RD
        LDI     HIGH(HBUF)
        PHI     RD
        GLO     R7
        STR     RD
        GHI     R8
        ADI     1
        PHI     R8
        XRI     16
        LBNZ    VH1
        SEP     R4
        DW      VST
        LBR     VH3
VH2:    LOAD    RD, VEOFP
        LDI     1
        STR     RD
VH3:    GHI     R8              ; none: a blank row
        LBZ     VHEND
        LOAD    RD, VOFS
        LDA     RD
        SEP     R4
        DW      HEX2
        LDA     RD
        SEP     R4
        DW      HEX2
        LDN     RD
        SEP     R4
        DW      HEX2
        LDI     ' '
        STR     RA
        INC     RA
        LOAD    RF, HBUF
        LDI     0
        PLO     R8
VH4:    LDI     ' '
        STR     RA
        INC     RA
        GLO     R8
        STR     R2
        GHI     R8
        SM                      ; n - i: 0 or less, blanks
        LBZ     VH5
        LBNF    VH5
        LDA     RF
        SEP     R4
        DW      HEX2
        LBR     VH6
VH5:    LDI     ' '
        STR     RA
        INC     RA
        STR     RA
        INC     RA
VH6:    GLO     R8
        XRI     7
        LBNZ    VH6A
        LDI     ' '
        STR     RA
        INC     RA
VH6A:   INC     R8
        GLO     R8
        XRI     16
        LBNZ    VH4
        LDI     ' '
        STR     RA
        INC     RA
        STR     RA
        INC     RA
        LOAD    RF, HBUF
        GHI     R8
        PLO     R8
VH7:    LDA     RF
        PLO     R7
        SMI     20H
        LBNF    VH8
        GLO     R7
        SMI     7FH
        LBDF    VH8
        GLO     R7
        LSKP
VH8:    LDI     '.'
        STR     RA
        INC     RA
        DEC     R8
        GLO     R8
        LBNZ    VH7
        LOAD    RD, VOFS + 2
        LDN     RD
        ADI     16
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
VHEND:  LDI     0
        STR     RA
        SEP     R5
; HEX2: D as two hex digits at RA
HEX2:   STXD
        SHR
        SHR
        SHR
        SHR
        SEP     R4
        DW      HEXD
        IRX
        LDX
        ANI     0FH
HEXD:   SMI     10
        LBDF    HD2
        ADI     '0' + 10
        LSKP
HD2:    ADI     'A'
        STR     RA
        INC     RA
        SEP     R5
; VHEAD: row 1, reversed: the path, its size, text or hex, the page (and "the end")
VHEAD:  LOAD    RA, LBUF
        LDI     ' '
        STR     RA
        INC     RA
        LOAD    RF, VPATHB
        SEP     R4
        DW      CPYS
        LOAD    RF, S2SP
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      SIZE87
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LOAD    RF, SBYTES
        SEP     R4
        DW      CPYS
        LOAD    RF, S2SP
        SEP     R4
        DW      CPYS
        LOAD    RF, STEXT
        LOAD    RD, VMODE
        LDN     RD
        LBZ     VHD1
        LOAD    RF, SHEX
VHD1:   SEP     R4
        DW      CPYS
        LOAD    RF, SPAGE
        SEP     R4
        DW      CPYS
        LOAD    RD, VPG
        LDN     RD
        ADI     1
        SEP     R4
        DW      U8STR
        LOAD    RD, VEOFP
        LDN     RD
        LBZ     VHD2
        LOAD    RF, SEND
        SEP     R4
        DW      CPYS
VHD2:   GLO     RA              ; at most 80
        SMI     80
        LBNF    VHD3
        LDI     80
        PLO     RA
VHD3:   GLO     RA
        XRI     80
        LBZ     VHD4
        LDI     ' '
        STR     RA
        INC     RA
        LBR     VHD3
VHD4:   LDI     0
        STR     RA
        SEP     R4
        DW      INL
        DB      ESC,'[1;1H',ESC,'[7m',0
        LOAD    RF, LBUF
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      INL
        DB      ESC,'[0m',0
        SEP     R5

; SETREC: RECP = the record at RF; DF = 1 if it is a folder
SETREC: LOAD    RD, RECP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     10H
        LBZ     GRNO
        LBR     GRYES
; MKPATH: VPATHB = the pane's path, a / (not after the root's), RECP's NAME.EXT
MKPATH: LDI     P_PATH
        SEP     R4
        DW      PFLD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        LOAD    RA, VPATHB
        SEP     R4
        DW      CPYS
        DEC     RA
        LDA     RA
        XRI     '/'
        LBZ     MK1
        LDI     '/'
        STR     RA
        INC     RA
MK1:    LOAD    RD, RECP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      NAMEFMT
        LDI     0
        STR     RA
        SEP     R5

; ==== Info (2 / F2): a box over the panes about the entry under the cursor; a key: the panes again
OFINFO: LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        LDI     P_CUR
        SEP     R4
        DW      GETF
        SEP     R4
        DW      ENTP
        SEP     R4
        DW      SETREC
        LOAD    RD, FKMODE      ; FKMODE, NEEDLN: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      GETREC
        LDN     RF
        XRI     '.'
        LBNZ    FI0
        SEP     R4
        DW      MSGI
        DB      '.. is the folder this one is in.',0
        SEP     R5
FI0:    SEP     R4
        DW      MKPATH
        SEP     R4              ; the box: rows 6-17, columns 8-73
        DW      INL
        DB      ESC,'[6;8H+- Info ','---------------------------------------------------------+',0
        LOAD    RD, BROW
        LDI     7
        STR     RD
        LOAD    RA, LBUF        ; its path
        LDI     ' '
        STR     RA
        INC     RA
        LOAD    RF, VPATHB
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      BOXLN
        SEP     R4
        DW      BOXLN0          ; (a blank line)
        SEP     R4
        DW      GETREC
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     10H
        LBNZ    FIDIR
; -- a file: its size in bytes, sectors and clusters
        LOAD    RF, SSIZE
        SEP     R4
        DW      LBSTR
        SEP     R4
        DW      SIZE87
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LOAD    RF, SBYTES
        SEP     R4
        DW      CPYS
        LDI     ','
        STR     RA
        INC     RA
        LDI     ' '
        STR     RA
        INC     RA
        SEP     R4              ; sectors = (size + 511) / 512
        DW      SIZE87
        GLO     R7
        ADI     0FFH
        GHI     R7
        ADCI    1
        PLO     R7              ; (R7.0 = bits 8-15 of size + 511; then / 2 over all)
        GLO     R8
        ADCI    0
        PHI     R7
        GHI     R8
        ADCI    0
        PLO     R8
        LDI     0
        PHI     R8
        GLO     R8
        SHR
        PLO     R8
        GHI     R7
        SHRC
        PHI     R7
        GLO     R7
        SHRC
        PLO     R7              ; R8:R7 = the sectors
        LOAD    RD, SUM         ; (kept)
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LOAD    RF, SSECT
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      PLURN
        LOAD    RF, SCOMMA
        SEP     R4
        DW      CPYS
        LOAD    RD, SUM         ; clusters = (sectors + SPC - 1) / SPC (SPC a power of 2)
        LDA     RD
        PHI     R8
        LDA     RD
        PLO     R8
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LOAD    RD, KS_SPC
        LDN     RD
        PLO     R9
        SMI     1
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        GLO     R8
        ADCI    0
        PLO     R8
FI1:    GLO     R9
        SHR
        PLO     R9
        LBZ     FI2
        GHI     R8
        SHR
        PHI     R8
        GLO     R8
        SHRC
        PLO     R8
        GHI     R7
        SHRC
        PHI     R7
        GLO     R7
        SHRC
        PLO     R7
        LBR     FI1
FI2:    GLO     R7
        PLO     R9              ; (1 cluster: no s)
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LOAD    RF, SCLUS
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      PLURN
        SEP     R4
        DW      BOXLN
        SEP     R4
        DW      FIDATE
        SEP     R4
        DW      FIATTR
        SEP     R4
        DW      FICLUS
        LOAD    RD, BROW        ; what it is (its row kept: the lines are counted once the box is up)
        LDN     RD
        STR     R2
        LOAD    RD, KROW
        LDN     R2
        STR     RD
        LOAD    RF, SKIND
        SEP     R4
        DW      LBSTR
        SEP     R4
        DW      FKIND
        SEP     R4
        DW      BOXLN
        LBR     FIEND
; -- a folder: what it holds (this level)
FIDIR:  LOAD    RF, SHOLDS
        SEP     R4
        DW      LBSTR
        SEP     R4
        DW      GETREC
        GLO     RF
        ADI     16
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, KS_WDIR
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        LOAD    RD, KS_PAT
        LDI     11
        PLO     RB
FD1:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    FD1
        SEP     R4
        DW      KS_DOPEN
        LOAD    RD, NFIL        ; NFIL NFOL NTAG SUM: 0
        LDI     7
        PLO     RB
FD2:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    FD2
FD3:    SEP     R4
        DW      KS_DNEXT
        LBDF    FD5
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBZ     FD4
        LOAD    RD, NFOL
        LDN     RD
        ADI     1
        STR     RD
        LBR     FD3
FD4:    LOAD    RD, NFIL
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RF, KS_DSIZE + 3 ; SUM + its size
        LOAD    RD, SUM + 3
        SEX     RF
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        DEC     RF
        LDN     RD
        ADC
        STR     RD
        SEX     R2
        LBR     FD3
FD5:    LOAD    RD, NFIL
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SFILE
        SEP     R4
        DW      CPYS
        LOAD    RD, NFIL
        LDN     RD
        SEP     R4
        DW      PLURAL
        LOAD    RF, SOF
        SEP     R4
        DW      CPYS
        LOAD    RD, SUM
        LDA     RD
        PHI     R8
        LDA     RD
        PLO     R8
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LOAD    RF, SBYTES
        SEP     R4
        DW      CPYS
        LOAD    RF, SAND
        SEP     R4
        DW      CPYS
        LOAD    RD, NFOL
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SFOLD
        SEP     R4
        DW      CPYS
        LOAD    RD, NFOL
        LDN     RD
        SEP     R4
        DW      PLURAL
        SEP     R4
        DW      BOXLN
        SEP     R4
        DW      FIDATE
        SEP     R4
        DW      FIATTR
        SEP     R4
        DW      FICLUS
        LOAD    RF, SKIND
        SEP     R4
        DW      LBSTR
        LOAD    RF, SAFOLD
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      BOXLN
FIEND:  LOAD    RD, BROW        ; blank lines to row 16, then the foot (row 17)
        LDN     RD
        XRI     17
        LBZ     FIE1
        SEP     R4
        DW      BOXLN0
        LBR     FIEND
FIE1:   SEP     R4
        DW      INL
        DB      ESC,'[17;8H+',ESC,'[7m',' a key: back to the panes ',ESC,'[0m'
        DB      '--------------------------------------+',0
        LOAD    RD, NEEDLN      ; its lines to count: now, the line drawn again
        LDN     RD
        LBZ     FIE1K
        LOAD    RD, FKMODE
        LDI     1
        STR     RD
        LOAD    RD, KROW
        LDN     RD
        STR     R2
        LOAD    RD, BROW
        LDN     R2
        STR     RD
        LOAD    RF, SKIND
        SEP     R4
        DW      LBSTR
        SEP     R4
        DW      FKIND
        SEP     R4
        DW      BOXLN
FIE1K:  SEP     R4
        DW      KEY
        LOAD    RD, RRC         ; the panes' rows 6-17 drawn again (both panes)
        LDI     3
        STR     RD
FIE2:   LDI     0
        SEP     R4
        DW      SETCP
        LOAD    RD, RRC
        LDN     RD
        SEP     R4
        DW      ROWDRAW
        LDI     1
        SEP     R4
        DW      SETCP
        LOAD    RD, RRC
        LDN     RD
        SEP     R4
        DW      ROWDRAW
        LOAD    RD, RRC
        LDN     RD
        ADI     1
        STR     RD
        XRI     15
        LBNZ    FIE2
        LBR     INFO
; LBSTR: LBUF = the text at RF (RA past it)
LBSTR:  LOAD    RA, LBUF
        LBR     CPYS
; BOXLN0: a blank box line.  BOXLN: LBUF (RA its end) as the box's line at row BROW (| text, padded to 64 |); BROW + 1
BOXLN0: LOAD    RA, LBUF
BOXLN:  GLO     RA
        SMI     64
        LBNF    BX1
        LDI     64
        PLO     RA
BX1:    GLO     RA
        XRI     64
        LBZ     BX2
        LDI     ' '
        STR     RA
        INC     RA
        LBR     BX1
BX2:    LDI     '|'
        STR     RA
        INC     RA
        LDI     0
        STR     RA
        LOAD    RD, BROW
        LDN     RD
        PHI     RB
        ADI     1
        STR     RD
        LDI     8
        PLO     RB
        SEP     R4
        DW      CUP
        SEP     R4
        DW      INL
        DB      '|',0
        LOAD    RF, LBUF
        LBR     PUTS
; FIDATE FIATTR FICLUS: the record's date and time, its attributes, its first cluster - a box line each
FIDATE: LOAD    RF, SWRIT
        SEP     R4
        DW      LBSTR
        LOAD    RD, FULLY
        LDI     1
        STR     RD
        SEP     R4
        DW      GETREC
        SEP     R4
        DW      DATE14
        LOAD    RD, FULLY
        LDI     0
        STR     RD
        LBR     BOXLN
FIATTR: LOAD    RF, SATTR
        SEP     R4
        DW      LBSTR
        SEP     R4
        DW      GETREC
        GLO     RF
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDN     RF
        ANI     27H
        PLO     R7
        LBNZ    FA1
        LOAD    RF, SNONE
        SEP     R4
        DW      CPYS
        LBR     BOXLN
FA1:    LOAD    RF, SATTRS      ; bit 0, 1, 2, 5: each name, a space after
        LDI     1
        PHI     R7
FA2:    GHI     R7
        STR     R2
        GLO     R7
        AND
        LBZ     FA4
FA3:    LDA     RF
        LBZ     FA5
        STR     RA
        INC     RA
        LBR     FA3
FA4:    LDA     RF
        LBNZ    FA4
FA5:    GHI     R7
        SHL
        PHI     R7
        XRI     40H
        LBNZ    FA2
        LBR     BOXLN
FICLUS: LOAD    RF, SFCL
        SEP     R4
        DW      LBSTR
        SEP     R4
        DW      GETREC
        GLO     RF
        ADI     16
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDA     RF
        PHI     R7
        LDN     RF
        PLO     R7
        LDI     0
        PHI     R8
        PLO     R8
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LBR     BOXLN
; FKIND: what the file is, at RA: by its extension and its first sector
FKIND:  SEP     R4
        DW      VOPEN
        SEP     R4
        DW      VFILL
        SEP     R4              ; STELLAR.BIN: the firmware
        DW      GETREC
        LOAD    RD, SFWN
        LDI     11
        PLO     R7
FKF1:   LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    FKF2
        DEC     R7
        GLO     R7
        LBNZ    FKF1
        LOAD    RF, SFW
        LBR     CPYS
FKF2:   SEP     R4
        DW      GETREC
        GLO     RF
        ADI     8
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, KINDS       ; 3 letters, the text, 0 ... ; 0 at the end
FK1:    LDN     RD
        LBZ     FKTXT
        SEP     R4
        DW      CMP3
        LBDF    FK3
FK2:    LDA     RD
        LBNZ    FK2
        LBR     FK1
FK3:    INC     RD
        INC     RD
        INC     RD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      GETREC          ; .PRG: its version and where it loads and starts
        GLO     RF
        ADI     8
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, SPRGX
        SEP     R4
        DW      CMP3
        LBDF    FKPRG
        LOAD    RD, SSTLX       ; .STL: its version (sector 0, +128)
        SEP     R4
        DW      CMP3
        LBNF    FKTX2
        LOAD    RF, KS_DATBUF + 128
        LDN     RF
        LBZ     RET0
        LOAD    RF, SVER
        SEP     R4
        DW      CPYS
        LOAD    RF, KS_DATBUF + 128
        LDI     8
        PLO     R7
FKS1:   LDA     RF
        LBZ     RET0
        STR     RA
        INC     RA
        DEC     R7
        GLO     R7
        LBNZ    FKS1
        SEP     R5
FKTX2:  LOAD    RD, SSHX        ; .SH .SC .TXT: text: its lines too
        SEP     R4
        DW      CMP3
        LBDF    FKLN
        LOAD    RD, SSCX
        SEP     R4
        DW      CMP3
        LBDF    FKLN
        LOAD    RD, STXX
        SEP     R4
        DW      CMP3
        LBDF    FKLN
        SEP     R5
FKPRG:  LOAD    RD, KS_DATBUF + 6 ; "VER:" ?
        LDA     RD
        XRI     'V'
        LBNZ    FKP2
        LDA     RD
        XRI     'E'
        LBNZ    FKP2
        LDA     RD
        XRI     'R'
        LBNZ    FKP2
        LDA     RD
        XRI     ':'
        LBNZ    FKP2
        LOAD    RF, SVER
        SEP     R4
        DW      CPYS
        LDI     8
        PLO     R7
FKP1:   LDA     RD
        LBZ     FKP2
        STR     RA
        INC     RA
        DEC     R7
        GLO     R7
        LBNZ    FKP1
FKP2:   LOAD    RF, SLOADS
        SEP     R4
        DW      CPYS
        LOAD    RD, KS_DATBUF
        LDA     RD
        SEP     R4
        DW      HEX2
        LDA     RD
        SEP     R4
        DW      HEX2
        LOAD    RF, SSTART
        SEP     R4
        DW      CPYS
        LOAD    RD, KS_DATBUF + 4
        LDA     RD
        SEP     R4
        DW      HEX2
        LDN     RD
        LBR     HEX2
FKTXT:  LOAD    RD, VMODE       ; no extension known: text or not, by its first sector (as View)
        LDI     0
        STR     RD
        LOAD    RD, VLEFT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RF, KS_DATBUF
FKT1:   GLO     RC
        STR     R2
        GHI     RC
        OR
        LBZ     FKT3
        DEC     RC
        LDA     RF
        PLO     R7
        ANI     80H
        LBNZ    FKT2
        GLO     R7
        SMI     20H
        LBDF    FKT1
        GLO     R7
        XRI     09H
        LBZ     FKT1
        XRI     09H XOR 0AH
        LBZ     FKT1
        XRI     0AH XOR 0CH
        LBZ     FKT1
        XRI     0CH XOR 0DH
        LBZ     FKT1
        XRI     0DH XOR 1AH
        LBZ     FKT1
        XRI     1AH XOR 1BH
        LBZ     FKT1
FKT2:   LOAD    RF, SBIN
        LBR     CPYS
FKT3:   LOAD    RF, STXT
        SEP     R4
        DW      CPYS
; FKLN: ", N lines" - the file read through (16 KB at most: more, "over")
FKLN:   LOAD    RF, SCOMMA
        SEP     R4
        DW      CPYS
        SEP     R4              ; over 16 KB: not counted (it would take seconds)
        DW      SIZE87
        GHI     R8
        LBNZ    FLOVER
        GLO     R8
        LBNZ    FLOVER
        GLO     R7
        SMI     LOW(4001H)
        GHI     R7
        SMBI    HIGH(4001H)
        LBDF    FLOVER
        LOAD    RD, FKMODE      ; the box not drawn yet: "counting lines ...", counted after
        LDN     RD
        LBNZ    FL0
        LOAD    RD, NEEDLN
        LDI     1
        STR     RD
        LOAD    RF, SCNTG
        LBR     CPYS
FL0:    SEP     R4
        DW      VOPEN
        LOAD    RD, SUM         ; SUM: LFs (2), CRs (2); NTAG: the last byte; NFOL: sectors
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, NTAG
        LDI     0
        STR     RD
        LOAD    RD, NFOL
        LDI     0
        STR     RD
FL1:    SEP     R4              ; a key: stop counting (the key closes the box)
        DW      POLL
        LOAD    RD, KQH
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        LBZ     FL1A
        LOAD    RF, SNOTC
        LBR     CPYS
FL1A:   LOAD    RD, NFOL
        LDN     RD
        XRI     32
        LBZ     FLOVER
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      VFILL
        LOAD    RD, VLEFT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        STR     R2
        GLO     RC
        OR
        LBZ     FL5
        LOAD    RF, KS_DATBUF
FL2:    LDA     RF
        PLO     R7
        XRI     0AH
        LBNZ    FL3
        LOAD    RD, SUM + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     FL4
FL3:    GLO     R7
        XRI     0DH
        LBNZ    FL4
        LOAD    RD, SUM + 3
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
FL4:    DEC     RC
        GLO     RC
        LBNZ    FL2
        GHI     RC
        LBNZ    FL2
        LOAD    RD, NTAG
        GLO     R7
        STR     RD
        SEP     R4
        DW      FREMZ
        LBNF    FL1
FL5:    LOAD    RD, SUM         ; lines: the LFs (none: the CRs), and one more if the last byte ends none
        LDA     RD
        PHI     R7
        LDA     RD
        PLO     R7
        STR     R2
        GHI     R7
        OR
        LBNZ    FL6
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
FL6:    LOAD    RD, NTAG
        LDN     RD
        LBZ     FL7             ; (empty)
        XRI     0AH
        LBZ     FL7
        XRI     0AH XOR 0DH
        LBZ     FL7
        INC     R7
FL7:    LDI     0
        PHI     R8
        PLO     R8
        GLO     R7
        PLO     R9
        SEP     R4
        DW      U32STR
        LOAD    RF, NUMB
        SEP     R4
        DW      CPYS
        LOAD    RF, SLINE
        SEP     R4
        DW      CPYS
; PLURN: an 's' at RA unless NUMB is "1"
PLURN:  LOAD    RD, NUMB
        LDA     RD
        XRI     '1'
        LBNZ    PN8
        LDN     RD
        LBZ     RET0
PN8:    LDI     's'
        STR     RA
        INC     RA
        SEP     R5
FLOVER: LOAD    RF, SOVER
        LBR     CPYS
; CMP3: DF = 1 if the 3 bytes at RF are those at RD (RF RD kept)
CMP3:   LDN     RF
        STR     R2
        LDN     RD
        XOR
        LBNZ    GRNO
        INC     RF
        INC     RD
        LDN     RF
        STR     R2
        LDN     RD
        XOR
        DEC     RF
        DEC     RD
        LBNZ    GRNO
        INC     RF
        INC     RF
        INC     RD
        INC     RD
        LDN     RF
        STR     R2
        LDN     RD
        XOR
        DEC     RF
        DEC     RF
        DEC     RD
        DEC     RD
        LBNZ    GRNO
        LBR     GRYES

S2SP:   DB      '  ',0
STEXT:  DB      'text',0
SHEX:   DB      'hex',0
SPAGE:  DB      '   page ',0
SEND:   DB      ' (the end)',0
SSIZE:  DB      '   Size         ',0
SSECT:  DB      ' sector',0
SCLUS:  DB      ' cluster',0
SWRIT:  DB      '   Written      ',0
SATTR:  DB      '   Attributes   ',0
SNONE:  DB      'none',0
SATTRS: DB      'read-only ',0,'hidden ',0,'system ',0,0,0,'archive ',0
SFCL:   DB      '   First cluster ',0
SKIND:  DB      '   What it is   ',0
SHOLDS: DB      '   Holds        ',0
SOF:    DB      ' of ',0
SAND:   DB      ' and ',0
SAFOLD: DB      'a folder',0
SVER:   DB      ' ',0
SLOADS: DB      ': load $',0
SSTART: DB      ', start $',0
SBIN:   DB      'data (not text)',0
STXT:   DB      'text',0
SCOMMA: DB      ', ',0
SLINE:  DB      ' line',0
SOVER:  DB      'over 16 KB (lines not counted)',0
SFWN:   DB      'STELLAR BIN'
SFW:    DB      'the STELLAR firmware (FW loads it)',0
SCNTG:  DB      'counting lines ...',0
SNOTC:  DB      'lines not counted (a key)',0
FKMODE: DB      0               ; 0: the lines not counted yet (NEEDLN = 1 if they will be); 1: counted
NEEDLN: DB      0
KROW:   DB      0
SPRGX:  DB      'PRG'
SSTLX:  DB      'STL'
SSHX:   DB      'SH '
SSCX:   DB      'SC '
STXX:   DB      'TXT'
KINDS:  DB      'PRG','a program',0
        DB      'OVL','the rest of a program (its overlay)',0
        DB      'STL','a STELLAR app',0
        DB      'MUS','music for PLAY',0
        DB      'SH ','a script for SH',0
        DB      'SC ','Stellar C (SC makes it a .STL)',0
        DB      'BIN','raw bytes',0
        DB      'HLP','a page of HELP',0
        DB      'CLC','a sheet for LTCALC',0
        DB      'TXT','text',0
        DB      0

OVEND:
        END
