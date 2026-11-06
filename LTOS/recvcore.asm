; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
        IF      STLRX = 0
; ---- the Intel HEX receive loop: first, so it sits in one page (PRGORG) and its branches are the short,
;      2-cycle kind. At 19200 baud a character takes ~58 instructions' time on the Elf2K; this takes ~30-36.
;      Upper-case hex digits (Intel HEX's). R7.0 = the record's checksum, R8.0 = its data bytes still to
;      come (0: header, checksum, or a record that is not data: HXSLOW), R9.0 = 1: a low nibble is next,
;      RC.1 = the high nibble, RA = where the data goes, RD.0 = the character. The status register stays
;      selected between characters.
HXL:    INP     DATPORT         ; the line status: a character?
        SHR
        BNF     HXL
        LDI     10H             ; the character
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RD
        LDI     15H             ; the status again, ready for the next
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RD
        SMI     3AH
        BDF     HX1             ; ':' or a letter
        ADI     10
        BNF     HXSP            ; below '0': a control character or a space
        BR      HXN
HX1:    BZ      HXCOL
        SMI     7
        BNF     HXSP            ; ';' .. '@'
        SMI     6
        BDF     HXSP            ; past 'F'
        ADI     16
HXN:    STR     R2              ; the digit's value
        GLO     R9
        BNZ     HXLO
        LDN     R2              ; the high nibble
        SHL
        SHL
        SHL
        SHL
        PHI     RC
        INC     R9
        BR      HXL
HXLO:   DEC     R9              ; the low nibble: the byte, at M(R2)
        GHI     RC
        OR
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GLO     R8
        BZ      HXSL
        LDN     R2              ; a data byte: in place
        STR     RA
        INC     RA
        DEC     R8
        BR      HXL
HXSL:   LBR     HXSLOW
HXCOL:  GLO     RB              ; ':' - a record starts. The last one never reached its checksum (a digit
        BZ      HXC0            ;  was lost: the rest of it shifted half a byte): it is a bad one
        GHI     R7
        BNZ     HXC0
        LBR     HXSHORT
HXC0:   LDI     0
        PLO     RB
        PLO     R7
        PHI     R7              ; (R7.1 = 1: this record's checksum came)
        PLO     R9
        PLO     R8
        BR      HXL
HXSP:   GLO     RD              ; Ctrl-C stops; the rest are ignored (CR, LF ...)
        XRI     03H
        BNZ     HXL
        LBR     ABORT
        ENDI
        IF      STLRX = 1
; ---- a STELLAR .lst (RECV NAME.STL): only lines "D aaaa bb bb ..." count. R9.0 = 0 a line's start, 1 in its
;      address, 2 in its bytes, 3 skipping it; RC.0 = digits of the address so far / 1 = a low nibble is next;
;      RC.1 = the high nibble; R8 = the address being read; RA = the address of the next byte, RF = where it
;      goes; R7 = quiet time left (R7.1 back to $C0 with every character: ~2.5 s); RB.0 = 1 once a D-line came.
DLL:    INP     DATPORT
        SHR
        BDF     DLC
        DEC     R7
        GHI     R7
        BNZ     DLL
        LBR     DLIDLE
DLC:    LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RD
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0C0H
        PHI     R7
        GLO     R9
        XRI     2
        BNZ     DLN2
        GLO     RD              ; in the bytes: a hex digit?
        SMI     3AH
        BDF     DLLT
        ADI     10
        BNF     DLNH
        BR      DLNB
DLLT:   SMI     7
        BNF     DLNH
        SMI     6
        BDF     DLNH
        ADI     16
DLNB:   STR     R2
        GLO     RC
        BNZ     DLLO
        LDN     R2              ; a high nibble
        SHL
        SHL
        SHL
        SHL
        PHI     RC
        INC     RC
        BR      DLL
DLLO:   DEC     RC              ; a low one: the byte, in place
        GHI     RC
        OR
        STR     RF
        INC     RF
        INC     RA
        GLO     RA
        BNZ     DLL
        GHI     RA
        ANI     1
        BNZ     DLL
        LBR     DLX             ; into the next 512-byte block: where it goes
DLNH:   GLO     RD              ; not a digit: a space goes on
        XRI     ' '
        BZ      DLL
DLN2:   GLO     RD              ; (states 0, 1 and 3 too) a line's end
        XRI     0DH
        BZ      DLEOL
        XRI     07H
        BZ      DLEOL
        GLO     R9
        XRI     3
        BZ      DLL             ; a line that is not a D-line: skipped
        LBR     DLSLOW
DLEOL:  LDI     0
        PLO     R9
        PLO     RC
        BR      DLL
        ENDI
HXPEND:

START:  LDN     RF
        LBZ     USE
        LOAD    RD, NTXT        ; the name: checked now, used when it is saved
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, NBUF
        SEP     R4
        DW      K_PARSE
        LBDF    BADN
        LOAD    RD, NBUF        ; no wildcards
        LDI     11
        PLO     RB
ST1:    LDA     RD
        XRI     '?'
        LBZ     BADN
        DEC     RB
        GLO     RB
        LBNZ    ST1
        LOAD    RD, NBUF+8      ; ISPRG: the extension is PRG
        LDA     RD
        XRI     'P'
        LBNZ    ST2
        LDA     RD
        XRI     'R'
        LBNZ    ST2
        LDN     RD
        XRI     'G'
        LBNZ    ST2
        LDI     1
        LSKP
ST2:    LDI     0
        PLO     RB
        LOAD    RD, ISPRG
        GLO     RB
        STR     RD
        LOAD    RD, NBUF+8      ; NAME.STL: a STELLAR app, from its .lst
        LDA     RD
        XRI     'S'
        LBNZ    ST4
        LDA     RD
        XRI     'T'
        LBNZ    ST4
        LDN     RD
        XRI     'L'
        IF      STLRX = 1
        LBZ     STLM
ST4:    LBR     BADN            ; (STLRX.PRG takes NAME.STL only)
        ELSE
        LBZ     TOSTL           ; RECV.PRG: STLRX.PRG does it (its room: $2C00-$6BFF)
        ENDI
        IF      STLRX = 0
ST4:
        SEP     R4
        DW      K_PIN
        DB      'Send it: Intel HEX, or text ending with a . line (or Ctrl-Z). Ctrl-C stops.',0DH,0AH,0
        LOAD    RD, HAVEB       ; HAVEB, NBAD, NREC: 0
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
        LOAD    RD, MAXE
        LDI     HIGH(BUF)
        STR     RD
        INC     RD
        LDI     LOW(BUF)
        STR     RD
        LOAD    RA, BUF
        LDI     0
        PLO     R9              ; R9.0 = text flags, R9.1 = 1: the UART overran
        PHI     R9
; the first character that is not a blank decides
FW:     LDI     15H             ; (GETC, inline: the UART's line status ...)
        STR     R2
        OUT     SELPORT
        DEC     R2
FW1:    INP     DATPORT
        ANI     01H
        LBZ     FW1
        LDI     10H             ; (... then its data)
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RB
        XRI     ':'
        LBZ     HEX
        GLO     RB
        XRI     03H
        LBZ     ABORT
        GLO     RB
        XRI     0DH
        LBZ     FW
        GLO     RB
        XRI     0AH
        LBZ     FW
        GLO     RB
        XRI     ' '
        LBZ     FW
        LDI     01H             ; text: at the start of a line
        PLO     R9
        GLO     RB
        LBR     TL

; ---- text: R9.0 bit 0 = at the start of a line, bit 1 = a "." is waiting (at a line's start)
TL:     PLO     RB
        XRI     1AH
        LBZ     TEND            ; Ctrl-Z
        GLO     RB
        XRI     03H
        LBZ     ABORT
        GLO     R9
        ANI     02H
        LBZ     TL2
        GLO     RB              ; a "." waits: alone on its line ends it all
        XRI     0DH
        LBZ     TEND
        GLO     RB
        XRI     0AH
        LBZ     TEND
        LDI     '.'             ; it was not: keep it
        STR     RA
        INC     RA
        GLO     R9
        ANI     0FDH
        PLO     R9
        GHI     RA
        XRI     HIGH(PTOP)
        LBZ     TFULL
TL2:    GLO     R9              ; a "." at the start of a line: wait and see
        ANI     01H
        LBZ     TL3
        GLO     RB
        XRI     '.'
        LBNZ    TL3
        LDI     02H
        PLO     R9
        LBR     TNX
TL3:    GLO     RB              ; an LF right after a CR: kept already (CR was saved as CR LF)
        XRI     0AH
        LBNZ    TL3A
        GLO     R9
        ANI     04H
        LBNZ    TL4
TL3A:   GLO     RB              ; keep it
        STR     RA
        INC     RA
        GHI     RA
        XRI     HIGH(PTOP)
        LBZ     TFULL
        GLO     RB              ; CR (the terminal's Enter): CR LF - TYPE and the Mac see the line end
        XRI     0DH
        LBNZ    TL3B
        LDI     0AH
        STR     RA
        INC     RA
        GHI     RA
        XRI     HIGH(PTOP)
        LBZ     TFULL
        LDI     05H             ; (bit 2: an LF next is that same line end)
        LBR     TL4B
TL3B:   GLO     RB              ; the start of a line after LF
        XRI     0AH
        LBZ     TL4
        LDI     0
        LSKP
TL4:    LDI     01H
TL4B:   PLO     R9
TNX:    LDI     15H             ; (GETC)
        STR     R2
        OUT     SELPORT
        DEC     R2
TN1:    INP     DATPORT
        ANI     01H
        LBZ     TN1
        LDN     R2              ; overrun (bit 1)?
        ANI     02H
        LBZ     TN2
        LDI     1
        PHI     R9
TN2:    LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        LBR     TL
TEND:   GLO     RA              ; RC = its bytes
        SMI     LOW(BUF)
        PLO     RC
        GHI     RA
        SMBI    HIGH(BUF)
        PHI     RC
        LOAD    RA, BUF
        LBR     SAVEIT

; ---- Intel HEX, from the first ':' (at FW): into HXL, set up
HEX:    LDI     15H             ; the status selected
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0
        PLO     RB
        PLO     R7
        PHI     R7
        PLO     R9
        PLO     R8
        LBR     HXL
; HXSHORT: a record cut short - one more bad checksum; then the new record
HXSHORT: LOAD   RD, NBAD+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     HXC0
; HXSLOW: a byte (at M(R2)) that is not a data byte: RB.0 = which byte of the record (RC.0 = its count,
;         RF = its address, R8.1 = its type)
HXSLOW: GLO     RB
        SMI     4
        LBDF    HS4
        GLO     RB
        LBZ     HS0
        SMI     1
        LBZ     HS1
        SMI     1
        LBZ     HS2
        LDN     R2              ; 3: the type
        PHI     R8
        LBNZ    HSNX            ; not data
        GLO     RC
        LBZ     HSNX            ; no bytes
        LOAD    RD, HAVEB       ; RA = BUF + address - BASE (the first data record sets BASE)
        LDN     RD
        LBNZ    PL1
        LDI     1
        STR     RD
        LOAD    RD, BASE
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
PL1:    LOAD    RD, BASE+1
        SEX     RD
        GLO     RF
        SM
        PLO     RA
        DEC     RD
        GHI     RF
        SMB
        PHI     RA
        SEX     R2
        LBNF    HOOPS           ; before the first
        GLO     RA
        ADI     LOW(BUF)
        PLO     RA
        GHI     RA
        ADCI    HIGH(BUF)
        PHI     RA
        LBDF    HOOPS
        GLO     RC              ; and its end below PTOP
        STR     R2
        GLO     RA
        ADD
        GHI     RA
        ADCI    0
        SMI     HIGH(PTOP)
        LBDF    HOOPS
        GLO     RC              ; R8.0 = the data bytes to come; RB.0 = 3 + count (4 + count after
        PLO     R8              ;  the INC: the checksum's place)
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        LBR     HSNX
HS0:    LDN     R2              ; 0: the count
        PLO     RC
        LBR     HSNX
HS1:    LDN     R2              ; 1, 2: the address
        PHI     RF
        LBR     HSNX
HS2:    LDN     R2
        PLO     RF
        LBR     HSNX
HS4:    GLO     RC              ; 4 on: the checksum is byte 4 + count; before it, a byte of a record
        ADI     4               ;  that is not data
        STR     R2
        GLO     RB
        XOR
        LBNZ    HSNX
        LDI     1               ; (it came)
        PHI     R7
        GLO     R7              ; the checksum: the record's bytes add up to 0
        LBZ     HC1
        LOAD    RD, NBAD+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
HC1:    GHI     R8
        XRI     1
        LBZ     HEND            ; type 1: the end
        GHI     R8
        LBNZ    HSNX
        LOAD    RD, MAXE+1      ; a data record: MAXE = max(MAXE, RA)
        SEX     RD
        GLO     RA
        SM
        DEC     RD
        GHI     RA
        SMB
        SEX     R2
        LBNF    HSNX
        LOAD    RD, MAXE
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
HSNX:   INC     RB
        LBR     HXL
        ENDI
        IF      STLRX = 1
; ---- STL mode: the app as 512-byte blocks. BUF = the file: sector 0 'STL1', the block count, each block's
;      address; then the blocks, in the order they first appear. BMAP: a block's slot (0: none yet), for the 32
;      blocks of $4000-$7EFF ($7F00-$7FFF is the Elf2K BIOS's).
STLM:   LOAD    RF, BUF         ; zero: the file's room and BMAP - BEFORE asking for the .lst (the UART
                                ;  holds one byte: what came while zeroing 16 KB would be lost)
        LOAD    RC, (MAXSLOT + 1) * 512
SL0:    LDI     0
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    SL0
        GHI     RC
        LBNZ    SL0
        LOAD    RF, BMAP
        LDI     32 + 2          ; (BMAP, then STLBAD's 2 flags)
        PLO     RC
SL1:    LDI     0
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    SL1
        LOAD    RF, BUF         ; 'STL1'
        LDI     'S'
        STR     RF
        INC     RF
        LDI     'T'
        STR     RF
        INC     RF
        LDI     'L'
        STR     RF
        INC     RF
        LDI     '1'
        STR     RF
        SEP     R4
        DW      K_PIN
        DB      'Send the .lst (only its D-lines count; it ends when the line is quiet, or',0DH,0AH
        DB      'Ctrl-Z). Ctrl-C stops.',0DH,0AH,0
        LDI     0
        PLO     R9
        PLO     RC
        PLO     RB
        LOAD    R7, 0C000H
        LDI     15H             ; the status selected
        STR     R2
        OUT     SELPORT
        DEC     R2
        LBR     DLL
; DLSLOW: a line's first character, its address, or something odd among its bytes
DLSLOW: GLO     R9
        LBZ     DS0
        XRI     1
        LBZ     DS1
DSSKIP: LDI     3               ; skip the rest of the line
        PLO     R9
        LBR     DLL
DS0:    GLO     RD              ; a line's start: 'D' - or the end, or stop
        XRI     'D'
        LBNZ    DS0A
        LDI     1
        PLO     R9
        LDI     0
        PLO     RC
        LBR     DLL
DS0A:   GLO     RD
        XRI     1AH
        LBZ     DLEND
        GLO     RD
        XRI     03H
        LBZ     ABORT
        LBR     DSSKIP
DS1:    GLO     RD              ; the address: spaces before it, 4 hex digits, a space after
        XRI     ' '
        LBNZ    DS1A
        GLO     RC
        LBZ     DLL
        XRI     4
        LBNZ    DSSKIP
        GHI     R8              ; the address is complete: RA = it, and where it goes
        PHI     RA
        GLO     R8
        PLO     RA
        LBR     DLX
DS1A:   GLO     RD              ; a hex digit (upper case)?
        SMI     3AH
        LBDF    DS1L
        ADI     10
        LBNF    DSSKIP
        LBR     DS1D
DS1L:   SMI     7
        LBNF    DSSKIP
        SMI     6
        LBDF    DSSKIP
        ADI     16
DS1D:   STR     R2
        GLO     RC
        ANI     1
        LBNZ    DS1O
        LDN     R2              ; 1st / 3rd digit
        SHL
        SHL
        SHL
        SHL
        PHI     RC
        INC     RC
        LBR     DLL
DS1O:   GHI     RC              ; 2nd / 4th: a byte of the address
        OR
        PLO     RD
        GLO     RC
        XRI     1
        LBNZ    DS1P
        GLO     RD
        PHI     R8
        INC     RC
        LBR     DLL
DS1P:   GLO     RD
        PLO     R8
        INC     RC
        LBR     DLL
; DLX: RA = an address: RF = where its byte goes (its block's slot, given one if new). Then the bytes.
DLX:    GHI     RA              ; $4000-$7EFF only ($7F00-$7FFF: the Elf2K BIOS's)
        SMI     40H
        LBNF    DLBAD
        SMI     3FH
        LBDF    DLBAD
        GHI     RA              ; RD -> BMAP[(RA - $4000) >> 9]
        SMI     40H
        SHR
        ADI     LOW(BMAP)
        PLO     RD
        LDI     HIGH(BMAP)
        ADCI    0
        PHI     RD
        LDN     RD
        LBNZ    DLX2
        LOAD    RF, BUF+4       ; a new block: the next slot
        LDN     RF
        XRI     MAXSLOT
        LBZ     DLBIG
        LDN     RF
        ADI     1
        STR     RF
        STR     RD
        SHL                     ; its address in the header: BUF + 3 + 2 x slot
        ADI     3
        PLO     RF
        GHI     RA
        ANI     0FEH
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        LDN     RD
DLX2:   SHL                     ; RF = BUF + 512 x slot + (RA & 511) (BUF is page-aligned)
        STR     R2
        GHI     RA
        ANI     1
        ADD
        ADI     HIGH(BUF)
        PHI     RF
        GLO     RA
        PLO     RF
        LDI     2
        PLO     R9
        LDI     0
        PLO     RC
        LDI     1
        PLO     RB
        LBR     DLL
DLBAD:  LOAD    RF, STLBAD      ; not $4000-$7EFF: noted, the line skipped
        LDI     1
        STR     RF
        LBR     DSSKIP
DLBIG:  LOAD    RF, STLBAD+1    ; more blocks than there is room for
        LDI     1
        STR     RF
        LBR     DSSKIP
DLIDLE: GLO     RB              ; quiet: the end, if a D-line came
        LBNZ    DLEND
        LDI     0C0H
        PHI     R7
        LBR     DLL
DLEND:  SEP     R4
        DW      DRAIN
        LOAD    RD, BMAP+31     ; the $7E00 block: its second half ($7F00-$7FFF) must be empty (a line that ran on)
        LDN     RD
        LBZ     DLE2
        SHL                     ; RF = BUF + 512 x slot + 256
        ADI     HIGH(BUF+100H)  
        PHI     RF
        LDI     0
        PLO     RF
DLE1:   LDA     RF
        LBNZ    DLE1B
        GLO     RF
        LBNZ    DLE1
        LBR     DLE2
DLE1B:  LOAD    RD, STLBAD
        LDI     1
        STR     RD
DLE2:   LOAD    RD, STLBAD
        LDA     RD
        LBZ     DE1
        SEP     R4
        DW      K_PIN
        DB      'An address outside $4000-$7EFF',0
        LBR     NOSAVE
DE1:    LDN     RD
        LBZ     DE2
        SEP     R4
        DW      K_PIN
        DB      'Too big for RECV (15 KB): on the PC/Mac/Linux, elfser.py putstl NAME.lst',0
        LBR     NOSAVE
DE2:    LOAD    RD, BUF+4       ; RC = 512 x (1 + blocks)
        LDN     RD
        LBNZ    DE3
        SEP     R4
        DW      K_PIN
        DB      'No D-lines',0
        LBR     NOSAVE
DE3:    ADI     1
        SHL
        PHI     RC
        LDI     0
        PLO     RC
        LOAD    RA, BUF
        LBR     SV1
        ENDI
        IF      STLRX = 0
HEND:   SEP     R4
        DW      DRAIN
        LOAD    RD, NBAD
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     HE1
        LOAD    RD, NBAD
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' bad checksums',0
        LBR     NOSAVE
        SEP     R5
HE1:    LOAD    RD, HAVEB
        LDN     RD
        LBNZ    HE2
        SEP     R4
        DW      K_PIN
        DB      'No data',0
        LBR     NOSAVE
HE2:    LOAD    RD, NBUF        ; STELLAR.BIN: only a whole firmware image, from $0000
        LOAD    RF, STLN11
        LDI     11
        PLO     RB
HE3:    LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    HE4
        DEC     RB
        GLO     RB
        LBNZ    HE3
        LOAD    RD, BASE
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     HE4
        SEP     R4
        DW      K_PIN
        DB      'STELLAR.BIN is not from $0000',0
        LBR     NOSAVE
HE4:    LOAD    RD, BUF         ; a bundle of files (build.py's LTOS-SYSTEM.HEX: 'LPAK', then a count and
        LOAD    RF, PAKID       ;  name (11) / offset (2) / length (2) for each, then their bytes)?
        LDI     4
        PLO     RB
HE5:    LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    HE6
        DEC     RB
        GLO     RB
        LBNZ    HE5
        LBR     UNPAK
HE6:    LOAD    RD, MAXE        ; RC = MAXE - BUF
        LDA     RD
        PHI     RC
        LDN     RD
        SMI     LOW(BUF)
        PLO     RC
        GHI     RC
        SMBI    HIGH(BUF)
        PHI     RC
        LOAD    RA, BUF
        LOAD    RD, ISPRG       ; NAME.PRG: the header in front
        LDN     RD
        LBZ     SAVE2
        LOAD    RD, HDR
        LOAD    RF, BASE
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        DEC     RF
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        GLO     RC
        ADI     6
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LOAD    RA, HDR
        LBR     SAVE2
SAVEIT: SEP     R4              ; (text) the rest of what the terminal sends after the end
        DW      DRAIN
SAVE2:  GHI     R9              ; characters lost?
        LBZ     SV1
        SEP     R4
        DW      K_PIN
        DB      'Characters were lost - send it with a delay after each line',0
        LBR     NOSAVE
        ENDI
SV1:    LOAD    RD, SRCA        ; (RA kept in memory across the printing)
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R4
        DW      K_PIN
        DB      'Received ',0
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' bytes.',0DH,0AH,0
        LOAD    RD, SRCA
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, NTXT
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      K_SAVEF         ; (never returns)
        IF      STLRX = 0
; UNPAK: every file in the bundle saved (replacing), each named as it goes. With a /BIN folder, each .PRG and
;  .STL goes into /BIN and the rest (HELP.TXT) into the root; without one, all of them in this folder. The
;  folder: set by K_PARSE (kapi.inc - a fixed address) of "/BIN/" or "/", never through the kernel's KS_
;  symbols - they move with every new kernel, and this RECV is the one on the card when U has just put one there.
UNPAK:  LOAD    RD, PKB         ; PKB = 0: no /BIN
        LDI     0
        STR     RD
        LOAD    RF, PBIN        ; a /BIN? (D = 3: "/BIN/" is a folder)
        SEP     R4
        DW      UPAT
        XRI     3
        LBNZ    UPH
        LOAD    RD, PKB
        LDI     1
        STR     RD
        LBR     UP0
UPH:    LOAD    RF, PHERE       ; none: this folder again
        SEP     R4
        DW      UPAT
UP0:    LOAD    RD, BUF+4
        LDA     RD
        PLO     RB
        LOAD    RF, PKN         ; PKN, PKP: in this order
        GLO     RB
        STR     RF
        INC     RF
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
UP1:    LOAD    RF, PKN
        LDN     RF
        LBZ     UP9
        SMI     1
        STR     RF
        SEP     R4              ; the folder it goes in
        DW      UPDIR
        LOAD    RF, PKP         ; RD -> the entry
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     11              ; its name
        PLO     RB
UP2:    LDA     RD
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    UP2
        LDA     RD              ; RA = BUF + offset, RC = length; PKP = the next entry
        STR     R2
        LDA     RD
        ADI     LOW(BUF)
        PLO     RA
        LDN     R2
        ADCI    HIGH(BUF)
        PHI     RA
        LDA     RD
        PHI     RC
        LDA     RD
        PLO     RC
        LOAD    RF, PKP
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        GLO     RD              ; RD back to the name for K_SAVER
        SMI     15
        PLO     RD
        GHI     RD
        SMBI    0
        PHI     RD
UPS:    SEP     R4
        DW      K_SAVER
        LBDF    UP3
        SEP     R4
        DW      K_PIN
        DB      '  saved',0DH,0AH,0
        LBR     UP1
UP3:    SEP     R4
        DW      K_PIN
        DB      '  NOT SAVED (the card is full, or failed)',0DH,0AH,0
        LBR     UP1
UP9:    SEP     R5
; UPDIR: with /BIN (PKB = 1), the file at PKP goes in /BIN if it is a .PRG or .STL, else in the root
UPDIR:  LOAD    RF, PKB
        LDN     RF
        LBZ     UD9
        LOAD    RF, PKP         ; RF -> its extension
        LDA     RF
        PHI     RD
        LDN     RF
        ADI     8
        PLO     RF
        GHI     RD
        ADCI    0
        PHI     RF
        LDA     RF
        XRI     'P'
        LBNZ    UPX1
        LDA     RF
        XRI     'R'
        LBNZ    UPRT
        LDN     RF
        XRI     'G'
        LBR     UPX2
UPX1:   XRI     'P' XOR 'S'
        LBNZ    UPRT
        LDA     RF
        XRI     'T'
        LBNZ    UPRT
        LDN     RF
        XRI     'L'
UPX2:   LBNZ    UPRT
        LOAD    RF, PBIN        ; a program: /BIN
        LBR     UPAT
UPRT:   LOAD    RF, PROOT       ; the rest: the root
UPAT:   LOAD    RD, NBUF        ; UPAT: K_PARSE of the path at RF - WDIR = its folder (the 11 bytes: NBUF)
        SEP     R4
        DW      K_PARSE
UD9:    SEP     R5
PBIN:   DB      '/BIN/',0
PROOT:  DB      '/',0
PHERE:  DB      'X',0
HOOPS:  SEP     R4
        DW      DRAIN
        SEP     R4
        DW      K_PIN
        DB      'A record is out of order, or past memory',0
        LBR     NOSAVE
TFULL:  SEP     R4
        DW      DRAIN
        SEP     R4
        DW      K_PIN
        DB      'Too big',0
        LBR     NOSAVE
        ENDI
ABORT:  SEP     R4
        DW      DRAIN
        SEP     R4
        DW      K_PIN
        DB      'Stopped',0
NOSAVE: SEP     R4
        DW      K_PIN
        DB      ' - nothing saved.',0DH,0AH,0
        SEP     R5
BADN:   SEP     R4
        DW      K_PIN
        DB      'Not a file name',0
        LBR     NOSAVE
USE:    SEP     R4
        DW      K_PIN
        DB      'RECV name - a file from the terminal',0DH,0AH,0
        SEP     R5
        IF      STLRX = 0
; TOSTL: NAME.STL - STLRX.PRG (here, else the root, else /BIN) is run with the same arguments: the kernel's RUN
TOSTL:  LOAD    RD, 032DH       ; (KS_ symbols: this kernel's?)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    TOOLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    TOOLD
        LOAD    RD, NTXT        ; ARGP = the name's text, as typed
        LOAD    RC, KS_ARGP
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, STLRXN      ; FNAME = STLRX.PRG
        LOAD    RC, KS_FNAME
        LDI     11
        PLO     RB
TS1:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    TS1
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBNF    TS2
        LOAD    RD, KS_WDIR     ; not here: the root
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBNF    TS2
        SEP     R4              ; not there: /BIN (KS_ is safe here - the stamp was checked)
        DW      KS_TOBIN
        LBDF    TSNO
        LOAD    RD, KS_FNAME
        SEP     R4
        DW      KS_FINDN
        LBDF    TSNO
TS2:    LBR     KS_RUNIT
TSNO:   SEP     R4
        DW      K_PIN
        DB      'STLRX.PRG is not on the card (RECV SYSTEM puts it there)',0
        LBR     NOSAVE
TOOLD:  SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again',0
        LBR     NOSAVE
STLRXN: DB      'STLRX   PRG'
        ENDI
; DRAIN: whatever else arrives, until it has been quiet for ~0.5 s
DRAIN:  LOAD    RD, 2000H
DR1:    LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        LBZ     DR2
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        LBR     DRAIN
DR2:    DEC     RD
        GHI     RD
        LBNZ    DR1
        GLO     RD
        LBNZ    DR1
        SEP     R5

STLN11: DB      'STELLAR BIN'
PAKID:  DB      'LPAK'
        IF      STLRX = 1
PEND:                           ; (STLRX.PRG's code ends here; its variables: in the free RAM under the stack)
        ORG     7C00H
        ENDI
PKN:    DS      1               ; UNPAK: files left, the next entry
PKP:    DS      2
PKB:    DS      1               ; UNPAK: 1 = programs into /BIN, the rest into the root
NTXT:   DS      2
NBUF:   DS      11
ISPRG:  DS      1
HAVEB:  DS      1               ; HAVEB, NBAD, NREC: in this order
NBAD:   DS      2
NREC:   DS      2
BASE:   DS      2
MAXE:   DS      2
SRCA:   DS      2
        IF      STLRX = 1
BMAP:   DS      32              ; STL mode: each block's slot
STLBAD: DS      2               ; an address out of range; too many blocks
STLVEND:
BUF     EQU     PRGORG          ; STLRX.PRG: the file from PRGORG (page-aligned) up to LTOS's buffers ($6C00)
MAXSLOT EQU     ((6C00H - BUF) / 512) - 1
        ELSE
        ORG     ((($ + 6) + 0FFH) AND 0FF00H) - 6
HDR:    DS      6               ; a program's header goes just before the data
BUF:                            ; (page-aligned)
PEND:
        ENDI
