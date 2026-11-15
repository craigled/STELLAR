; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; file.asm - FILE.PRG: FILE names - what each file is, from what is in it (as Unix file). Names may be paths and
; patterns (FILE *.TXT, FILE /BIN/*.PRG, FILE GAMES/ - all of a folder). One line each:  NAME.EXT:     what
;   folder; empty
;   STELLAR app, N blocks[, version V]       ('STL1' - an .STL; its version from sector 0 at +128)
;   LTOS bundle (RECV), N files              ('LPAK')
;   LTOS program, $llll-$eeee[, version V]   (a 6-byte header that fits the file: load, length, start)
;   PNG image, GIF image, JPEG image, PDF document, ZIP archive, gzip data, MIDI music, WAV sound, ELF program
;   then, from its first 2 KB: data (a control character other than TAB LF FF CR Ctrl-Z), or text:
;   Intel HEX; STELLAR listing (.lst); LTCALC sheet; EROFF / nroff text; ASCII text, UTF-8 text or 8-bit text -
;   with ", CR LF line ends" when it has them. verify_file.py holds the same rules in Python.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
SCANS   EQU     1               ; sectors given every text test
XSCANS  EQU     16              ; and looked at for a listing's lines (8 KB)

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        DB      'VER:1.0',0
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
        LBZ     USAGE
; ---- each name on the line
ARG:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     AEND
        LOAD    RD, ARGP        ; (kept: for "not found")
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDI     0               ; a dot in it? (DOT; no dot and a wildcard: any extension, as DIR)
        PHI     RA
        GHI     RF
        PHI     RC
        GLO     RF
        PLO     RC
AD1:    LDA     RC
        LBZ     AD2
        XRI     ' '
        LBZ     AD2
        XRI     0EH             ; (' ' XOR '.')
        LBNZ    AD1
        LDI     1
        PHI     RA              ; (PARSE keeps RA)
AD2:    LOAD    RD, KS_PAT
        SEP     R4
        DW      KS_PARSE
        LBNF    A1W
        XRI     3
        LBNZ    A0
        LOAD    RD, KS_PAT      ; "GAMES/": all of it
        LDI     11
        PLO     RB
A0A:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    A0A
        LBR     A1
A0:     XRI     3
        LBR     KS_PPERR
A1W:    GHI     RA              ; a wildcard and no dot: ????????.???
        LBNZ    A1
        LOAD    RD, KS_PAT
        LDI     11
        PLO     RB
A1X:    LDA     RD
        XRI     '?'
        LBZ     A1Y
        DEC     RB
        GLO     RB
        LBNZ    A1X
        LBR     A1
A1Y:    LOAD    RD, KS_PAT+8
        LDI     '?'
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
A1:     LOAD    RD, NEXTA       ; where the next name starts
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, NFOUND
        LDI     0
        STR     RD
        SEP     R4
        DW      KS_DOPEN
A2:     SEP     R4
        DW      KS_DNEXT
        LBDF    A9
        LOAD    RD, NFOUND
        LDI     1
        STR     RD
        LOAD    RD, ENAME       ; its name, kept
        LDI     11
        PLO     RB
A3:     LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    A3
        SEP     R4
        DW      PNAME
        SEP     R4
        DW      WHAT
        SEP     R4
        DW      K_PCRLF
        LBR     A2
A9:     LOAD    RD, NFOUND      ; nothing matched: say so
        LDN     RD
        LBNZ    A9B
        LOAD    RD, ARGP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
A9A:    LDA     RF
        LBZ     A9C
        XRI     ' '
        LBZ     A9C
        XRI     ' '
        SEP     R4
        DW      F_TYPE
        LBR     A9A
A9C:    SEP     R4
        DW      K_PIN
        DB      ': not found',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
A9B:    LOAD    RD, NEXTA
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LBR     ARG
AEND:   SEP     R5
USAGE:  SEP     R4
        DW      K_PIN
        DB      'Usage: FILE names   (paths and patterns: FILE *.TXT, FILE /BIN/*.PRG)',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5

; ---- PNAME: ENAME as NAME.EXT, then ':' and spaces to column 14
PNAME:  LOAD    RD, NCOL
        LDI     14
        STR     RD
        LOAD    RF, ENAME
        LDI     8
        SEP     R4
        DW      PPART
        LOAD    RF, ENAME+8
        LDN     RF
        XRI     ' '
        LBZ     PN1
        LDI     '.'
        SEP     R4
        DW      PCH
        LDI     3
        SEP     R4
        DW      PPART
PN1:    LDI     ':'
        SEP     R4
        DW      PCH
PN2:    LOAD    RD, NCOL
        LDN     RD
        LBZ     PN9
        LDI     ' '
        SEP     R4
        DW      PCH
        LBR     PN2
PN9:    SEP     R5
; PPART: up to D characters at RF, to a space
PPART:  PLO     RE
        LOAD    RD, CNT
        GLO     RE
        STR     RD
PP1:    LOAD    RD, CNT
        LDN     RD
        LBZ     PP9
        SMI     1
        STR     RD
        LDA     RF
        XRI     ' '
        LBZ     PP9
        XRI     ' '
        SEP     R4
        DW      PCH
        LBR     PP1
PP9:    SEP     R5
; PCH: D out, NCOL down by one (not below 0). Keeps RF.
PCH:    PLO     RE
        LOAD    RD, NCOL
        LDN     RD
        LBZ     PC1
        SMI     1
        STR     RD
PC1:    GLO     RE
        SEP     R4
        DW      F_TYPE
        SEP     R5

; ---- WHAT: the entry just found (DATTR, DSIZE, DCLUS): what it is, printed
WHAT:   LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBZ     W1
        SEP     R4
        DW      K_PIN
        DB      'folder',0
        SEP     R5
W1:     LOAD    RD, KS_DSIZE    ; empty?
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
        LBNZ    W2
        SEP     R4
        DW      K_PIN
        DB      'empty',0
        SEP     R5
W2:     LOAD    RD, NSEC        ; the scan: everything zero
        LDI     SCAN_E - NSEC
        PLO     RB
W2A:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    W2A
        LOAD    RD, HEXOK       ; (the "every line" tests start true)
        LDI     1
        STR     RD
        LOAD    RD, CLCOK
        LDI     1
        STR     RD
        SEP     R4
        DW      KS_FOPEN
        SEP     R4              ; sector 0: its first 32 bytes (HDR) and 128-143 (HDRV) kept
        DW      KS_FREAD
        LBDF    W9DATA
        LOAD    RF, KS_DATBUF
        LOAD    RD, HDR
        LDI     32
        PLO     RB
W3:     LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    W3
        LOAD    RF, KS_DATBUF+128
        LDI     16
        PLO     RB
W3A:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    W3A
        SEP     R4              ; the text scan of sector 0, then on (to SCANS sectors)
        DW      SCAN
W4:     LOAD    RD, NSEC
        LDN     RD
        ADI     1
        STR     RD
        XRI     SCANS
        LBZ     W5
        SEP     R4
        DW      KS_FREAD
        LBDF    W5
        SEP     R4
        DW      SCAN
        LBR     W4
W5:     SEP     R4              ; the end of the last line
        DW      EOL
        SEP     R4              ; then, if nothing is decided yet, a listing's lines further on
        DW      XSCAN
; -- STL1
        LOAD    RF, HDR
        LOAD    RD, TSTL
        SEP     R4
        DW      CMP4
        LBNZ    W6
        SEP     R4              ; and 512 bytes at least
        DW      SIZE16
        LBDF    W5A
        GHI     RD
        SMI     2
        LBNF    W6
W5A:    SEP     R4
        DW      K_PIN
        DB      'STELLAR app, ',0
        LOAD    RD, HDR+4
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' blocks',0
        LOAD    RD, HDRV
        LDN     RD
        LBZ     W5B
        SEP     R4
        DW      K_PIN
        DB      ', version ',0
        LOAD    RD, HDRV
        SEP     R4
        DW      PVER
W5B:    SEP     R5
; -- LPAK
W6:     LOAD    RF, HDR
        LOAD    RD, TPAK
        SEP     R4
        DW      CMP4
        LBNZ    W7
        SEP     R4
        DW      SIZE16
        LBDF    W6A
        GHI     RD
        LBNZ    W6A
        GLO     RD
        SMI     5
        LBNF    W7
W6A:    SEP     R4
        DW      K_PIN
        DB      'LTOS bundle (RECV), ',0
        LOAD    RD, HDR+4
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' files',0
        SEP     R5
; -- a program: size < 64 KB, 7 bytes at least, length = size - 6, load <= start < load + length, no wrap
W7:     LOAD    RD, BAD         ; only what would be data (a header's 0s and the like)
        LDN     RD
        LBZ     W8
        SEP     R4
        DW      SIZE16
        LBDF    W8
        GLO     RD              ; RD = size - 6 (a borrow: too short)
        SMI     6
        PLO     RD
        GHI     RD
        SMBI    0
        PHI     RD
        LBNF    W8
        LBNZ    W7A
        GLO     RD
        LBZ     W8              ; (length 0)
W7A:    LOAD    RF, HDR+3       ; the header's length >= it (more: room past the file, its DS bytes)
        LDN     RF
        STR     R2
        GLO     RD
        SD
        DEC     RF
        LDN     RF
        STR     R2
        GHI     RD
        SDB
        LBNF    W8
        LOAD    RF, HDR         ; RC = load, RA = start, RD = length
        LDA     RF
        PHI     RC
        LDA     RF
        PLO     RC
        LDA     RF
        PHI     RD
        LDA     RF
        PLO     RD
        LDA     RF
        PHI     RA
        LDN     RF
        PLO     RA
        GLO     RC              ; R9 = load + length - 1 (the end): no carry out
        STR     R2
        GLO     RD
        ADD
        PLO     R9
        GHI     RC
        STR     R2
        GHI     RD
        ADC
        PHI     R9
        LBNF    W7B
        GLO     R9              ; (a carry: only load + length = $10000 exactly)
        LBNZ    W8
        GHI     R9
        LBNZ    W8
W7B:    DEC     R9
        GLO     RC              ; start >= load
        STR     R2
        GLO     RA
        SM
        GHI     RC
        STR     R2
        GHI     RA
        SMB
        LBNF    W8
        GLO     RA              ; start <= end
        STR     R2
        GLO     R9
        SM
        GHI     RA
        STR     R2
        GHI     R9
        SMB
        LBNF    W8
        LOAD    RD, PEND9       ; (kept over the printing)
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        INC     RD              ; PEND9+2: the load address
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      K_PIN
        DB      'LTOS program, $',0
        LOAD    RF, PEND9+2
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      K_PHEX4
        SEP     R4
        DW      K_PIN
        DB      '-$',0
        LOAD    RF, PEND9
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      K_PHEX4
        LOAD    RF, HDR         ; a version: VER: at the load address, started past it
        LDA     RF
        STR     R2
        LOAD    RD, HDR+4
        LDA     RD
        XOR
        PLO     RC
        LDN     RF
        STR     R2
        LDN     RD
        XOR
        STR     R2
        GLO     RC
        OR
        LBZ     W7Z
        LOAD    RF, HDR+6
        LOAD    RD, TVER
        SEP     R4
        DW      CMP4
        LBNZ    W7Z
        SEP     R4
        DW      K_PIN
        DB      ', version ',0
        LOAD    RD, HDR+10
        SEP     R4
        DW      PVER
W7Z:    SEP     R5
; -- the signatures
W8:     LOAD    R9, MAGIC       ; each: offset, length, the bytes, the name (0-ended); $FF ends the table
W8A:    LDA     R9
        PLO     RA              ; RA.0 = the offset
        XRI     0FFH
        LBZ     W9
        LDA     R9
        PLO     RB              ; RB.0 = the length (counted down)
        PHI     RC              ; RC.1 = the length
        GLO     RA              ; RF -> HDR + offset
        ADI     LOW(HDR)
        PLO     RF
        LDI     HIGH(HDR)
        ADCI    0
        PHI     RF
        LDI     1
        PHI     RB              ; RB.1 = 1 while it matches
W8B:    LDA     R9
        STR     R2
        LDA     RF
        XOR
        LBZ     W8C
        LDI     0
        PHI     RB
W8C:    DEC     RB
        GLO     RB
        LBNZ    W8B
        GHI     RB
        LBZ     W8D
        SEP     R4              ; and the file holds offset + length bytes
        DW      SIZE16
        LBDF    W8E
        GHI     RD
        LBNZ    W8E
        GLO     RA
        STR     R2
        GHI     RC
        ADD
        STR     R2
        GLO     RD
        SM
        LBDF    W8E
W8D:    LDA     R9              ; past the name
        LBNZ    W8D
        LBR     W8A
W8E:    GHI     R9              ; the name: printed
        PHI     RD
        GLO     R9
        PLO     RD
W8F:    LDA     RD
        LBZ     W8G
        SEP     R4
        DW      F_TYPE
        LBR     W8F
W8G:    SEP     R5
; -- text, or data
W9:     LOAD    RD, BAD
        LDN     RD
        LBZ     W9T
W9DATA: SEP     R4
        DW      K_PIN
        DB      'data',0
        SEP     R5
W9T:    LOAD    RD, HEXOK       ; the kind
        LDN     RD
        LBZ     W9A
        LOAD    RD, HEXANY
        LDN     RD
        LBZ     W9A
        SEP     R4
        DW      K_PIN
        DB      'Intel HEX',0
        LBR     W9CR
W9A:    LOAD    RD, DANY
        LDN     RD
        LBZ     W9B
        SEP     R4
        DW      K_PIN
        DB      'STELLAR listing (.lst)',0
        LBR     W9CR
W9B:    LOAD    RD, CLCOK
        LDN     RD
        LBZ     W9C
        LOAD    RD, CLCANY
        LDN     RD
        LBZ     W9C
        SEP     R4
        DW      K_PIN
        DB      'LTCALC sheet',0
        LBR     W9CR
W9C:    LOAD    RD, ROFF
        LDN     RD
        LBZ     W9D
        SEP     R4
        DW      K_PIN
        DB      'EROFF / nroff text',0
        LBR     W9CR
W9D:    LOAD    RD, HI
        LDN     RD
        LBNZ    W9E
        SEP     R4
        DW      K_PIN
        DB      'ASCII text',0
        LBR     W9CR
W9E:    LOAD    RD, U8BAD
        LDN     RD
        LBNZ    W9F
        SEP     R4
        DW      K_PIN
        DB      'UTF-8 text',0
        LBR     W9CR
W9F:    SEP     R4
        DW      K_PIN
        DB      '8-bit text',0
W9CR:   LOAD    RD, CRLF
        LDN     RD
        LBZ     W9Z
        SEP     R4
        DW      K_PIN
        DB      ', CR LF line ends',0
W9Z:    SEP     R5

; XSCAN: text with no kind yet (not data, not HEX, a listing, a sheet, roff): the sectors after the first SCANS
;        (to XSCANS in all) looked at for a listing line only - the first 12 characters of each line kept (LB),
;        the rest of it passed over quickly. LB starts empty at the first of them.
XSCAN:  LOAD    RD, BAD
        LDN     RD
        LBNZ    XS9
        LOAD    RD, HEXOK
        LDN     RD
        LBZ     XS0
        LOAD    RD, HEXANY
        LDN     RD
        LBNZ    XS9
XS0:    LOAD    RD, DANY
        LDN     RD
        LBNZ    XS9
        LOAD    RD, ROFF
        LDN     RD
        LBNZ    XS9
        LOAD    RD, CLCOK
        LDN     RD
        LBZ     XS1
        LOAD    RD, CLCANY
        LDN     RD
        LBNZ    XS9
XS1:    LOAD    RD, NSEC        ; the file goes on? (W4 read all SCANS of them)
        LDN     RD
        XRI     SCANS
        LBNZ    XS9
        LOAD    RD, XCOL
        LDI     0
        STR     RD
XSEC:   LOAD    RD, NSEC
        LDN     RD
        ADI     1
        STR     RD
        XRI     XSCANS + 1
        LBZ     XSE
        SEP     R4
        DW      KS_FREAD
        LBDF    XSE
        LOAD    RF, KS_DATBUF
        LOAD    RD, XCOL
        LDN     RD
        PLO     R8              ; R8.0 = the column (to 12)
X1:     GHI     RC
        LBNZ    X2
        GLO     RC
        LBZ     X9
X2:     DEC     RC
        LDA     RF
        PLO     R9
        XRI     0AH
        LBZ     XLF
        GLO     R8
        SMI     12
        LBDF    X1              ; past 12: passed over
        GLO     R9
        XRI     0DH
        LBZ     X1              ; (CR: skipped)
        GLO     R8
        ADI     LOW(LB)
        PLO     RD
        LDI     HIGH(LB)
        ADCI    0
        PHI     RD
        GLO     R9
        STR     RD
        INC     R8
        LBR     X1
XLF:    GLO     R8              ; a line: a listing's?
        PLO     RA
        SEP     R4
        DW      DLINE
        LBDF    XYES
        SEP     R4
        DW      LBCLR
        LDI     0
        PLO     R8
        LBR     X1
X9:     LOAD    RD, XCOL        ; the sector done: the column kept
        GLO     R8
        STR     RD
        LBR     XSEC
XSE:    LOAD    RD, XCOL        ; the end: the last line too
        LDN     RD
        PLO     RA
        SEP     R4
        DW      DLINE
        LBNF    XS9
XYES:   LOAD    RD, DANY
        LDI     1
        STR     RD
XS9:    SEP     R5
; LBCLR: LB = 12 zeros
LBCLR:  LOAD    RD, LB
        LDI     12
        PLO     RB
LBC1:   LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    LBC1
        SEP     R5

; SIZE16: RD = DSIZE's low 16 bits; DF = 1 if it is 64 KB or more
SIZE16: LOAD    RF, KS_DSIZE
        LDA     RF
        STR     R2
        LDA     RF
        OR
        PLO     RE
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        GLO     RE
        LBZ     SZ1
        LDI     1
        SHR
        SEP     R5
SZ1:    LDI     0
        SHR
        SEP     R5
; CMP4: 4 bytes at RF = 4 at RD? D = 0 if so
CMP4:   LDI     4
        PLO     RE
CM1:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    CM9
        DEC     RE
        GLO     RE
        LBNZ    CM1
CM9:    SEP     R5
; PVER: the version at RD - at most 15 characters, up to a 0 (or anything not printable)
PVER:   GHI     RD              ; (the output keeps RD and RF: RF -> where it stops)
        PHI     RF
        GLO     RD
        ADI     15
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF              ; RF = RD + 15
PV1:    GLO     RD
        STR     R2
        GLO     RF
        XOR
        LBZ     PV9
        LDN     RD
        SMI     20H
        LBNF    PV9
        SMI     5FH
        LBDF    PV9
        LDA     RD
        SEP     R4
        DW      F_TYPE
        LBR     PV1
PV9:    SEP     R5

; ---- SCAN: DATBUF's RC bytes, one at a time, into the text tests
SCAN:   LOAD    RF, KS_DATBUF
SC1:    GHI     RC
        LBNZ    SC2
        GLO     RC
        LBZ     SC9
SC2:    DEC     RC
        LDA     RF
        PLO     R9              ; R9.0 = the byte
        SMI     20H             ; a control character: TAB LF FF CR Ctrl-Z only
        LBDF    SC3
        GLO     R9
        XRI     09H
        LBZ     SC4
        XRI     03H             ; (TAB XOR LF)
        LBZ     SC4
        XRI     06H             ; (LF XOR FF)
        LBZ     SC4
        XRI     01H             ; (FF XOR CR)
        LBZ     SC4
        XRI     17H             ; (CR XOR Ctrl-Z)
        LBZ     SC4
SCBAD:  LOAD    RD, BAD
        LDI     1
        STR     RD
        LBR     SC4
SC3:    GLO     R9
        XRI     7FH
        LBZ     SCBAD
SC4:    GLO     R9              ; CR LF?
        XRI     0AH
        LBNZ    SC5
        LOAD    RD, PREVCR
        LDN     RD
        LBZ     SC5
        LOAD    RD, CRLF
        LDI     1
        STR     RD
SC5:    LOAD    RD, PREVCR
        GLO     R9
        XRI     0DH
        LBZ     SC5A
        LDI     1
SC5A:   XRI     1               ; (1 if CR)
        STR     RD
        SEP     R4              ; UTF-8
        DW      U8
        GLO     R9              ; the line tests: CR skipped, LF ends a line
        XRI     0DH
        LBZ     SC1
        XRI     07H             ; (CR XOR LF)
        LBNZ    SC6
        SEP     R4
        DW      EOL
        LBR     SC1
SC6:    SEP     R4
        DW      LCH
        LBR     SC1
SC9:    SEP     R5

; U8: R9.0 into the UTF-8 check (HI: a byte >= $80 seen; U8BAD: not UTF-8; U8N: continuation bytes due)
U8:     GLO     R9
        ANI     80H
        LBZ     U81
        LOAD    RD, HI
        LDI     1
        STR     RD
U81:    LOAD    RD, U8N
        LDN     RD
        LBZ     U84
        GLO     R9              ; due: $80-$BF
        ANI     0C0H
        XRI     80H
        LBNZ    U8X
        LDN     RD
        SMI     1
        STR     RD
        SEP     R5
U84:    GLO     R9
        ANI     80H
        LBZ     U89
        GLO     R9
        SMI     0C2H
        LBNF    U8X             ; $80-$C1
        GLO     R9
        SMI     0E0H
        LBNF    U8L1
        GLO     R9
        SMI     0F0H
        LBNF    U8L2
        GLO     R9
        SMI     0F5H
        LBDF    U8X
        LDI     3
        LBR     U8S
U8L1:   LDI     1
        LBR     U8S
U8L2:   LDI     2
U8S:    STR     RD
U89:    SEP     R5
U8X:    LOAD    RD, U8N
        LDI     0
        STR     RD
        LOAD    RD, U8BAD
        LDI     1
        STR     RD
        SEP     R5

; LCH: R9.0 = a character of a line: the first 12 kept in LB, the length (to 255), every one after the first a
;      hex digit? (LHEX)
LCH:    LOAD    RD, LLEN
        LDN     RD
        PLO     RA
        XRI     0FFH
        LBZ     LC1
        GLO     RA
        ADI     1
        STR     RD
LC1:    GLO     RA
        SMI     12
        LBDF    LC2
        GLO     RA
        ADI     LOW(LB)
        PLO     RD
        LDI     HIGH(LB)
        ADCI    0
        PHI     RD
        GLO     R9
        STR     RD
LC2:    GLO     RA
        LBZ     LC9
        GLO     R9
        SEP     R4
        DW      ISHEX
        LBNF    LC9
        LOAD    RD, LNHEX       ; (a character that is not)
        LDI     1
        STR     RD
LC9:    SEP     R5

; ISHEX: D a hex digit (0-9 A-F a-f)? DF = 0 if so
ISHEX:  PLO     RE
        SMI     '0'
        LBNF    IH9
        SMI     10
        LBNF    IH0
        GLO     RE
        ANI     0DFH
        SMI     'A'
        LBNF    IH9
        SMI     6
        LBNF    IH0
IH9:    LDI     1
        SHR
        SEP     R5
IH0:    LDI     0
        SHR
        SEP     R5

; EOL: a line ends: its tests (then LLEN, LNHEX = 0, LB cleared)
;   hex line: empty, or ':' then 10 hex digits at least, all hex     -> HEXOK stays (else 0); HEXANY if not empty
;   D-line: "D " 4 upper-case hex digits, then a space or the end     -> DANY
;   cell: empty, or [A-H] 1-20 then a space                           -> CLCOK stays; CLCANY if not empty
;   roff: .xx (two lower-case letters), .X or .XX (upper case), then a space, a TAB or the end; or .\"  -> ROFF
EOL:    LOAD    RD, LLEN
        LDN     RD
        LBZ     EL9             ; empty: nothing changes
        PLO     RA              ; RA.0 = the length
        LOAD    RD, HEXANY      ; -- hex
        LDI     1
        STR     RD
        LOAD    RD, LB
        LDN     RD
        XRI     ':'
        LBNZ    EH0
        GLO     RA
        SMI     11
        LBNF    EH0
        LOAD    RD, LNHEX
        LDN     RD
        LBZ     EH1
EH0:    LOAD    RD, HEXOK
        LDI     0
        STR     RD
EH1:    SEP     R4              ; -- a listing line
        DW      DLINE
        LBNF    ED9
        LOAD    RD, DANY
        LDI     1
        STR     RD
ED9:    LOAD    RD, CLCANY      ; -- cell
        LDI     1
        STR     RD
        LOAD    RD, LB
        LDA     RD
        SMI     'A'
        LBNF    EC0
        SMI     8
        LBDF    EC0
        LDA     RD              ; 1-9
        PLO     RE
        SMI     '1'
        LBNF    EC0
        SMI     9
        LBDF    EC0
        LDA     RD
        XRI     ' '
        LBZ     EC1             ; one digit
        GLO     RE              ; two: 10-19, 20
        XRI     '1'
        LBNZ    EC2
        DEC     RD
        LDA     RD
        SMI     '0'
        LBNF    EC0
        SMI     10
        LBDF    EC0
        LBR     EC3
EC2:    XRI     03H             ; ('1' XOR '2')
        LBNZ    EC0
        DEC     RD
        LDA     RD
        XRI     '0'
        LBNZ    EC0
EC3:    LDN     RD
        XRI     ' '
        LBZ     EC1
EC0:    LOAD    RD, CLCOK
        LDI     0
        STR     RD
EC1:    LOAD    RD, LB          ; -- roff
        LDA     RD
        XRI     '.'
        LBNZ    ER9
        LDA     RD
        PLO     RE
        XRI     5CH             ; .\"
        LBNZ    ER1
        LDN     RD
        XRI     '"'
        LBZ     ERY
        LBR     ER9
ER1:    GLO     RE              ; lower case: two, then the end
        SMI     'a'
        LBNF    ER3
        SMI     26
        LBDF    ER9
        LDA     RD
        SMI     'a'
        LBNF    ER9
        SMI     26
        LBDF    ER9
        GLO     RA
        XRI     3
        LBZ     ERY
        SEP     R4
        DW      SPTAB
        LBZ     ERY
        LBR     ER9
ER3:    GLO     RE              ; upper case: one or two, then the end
        SMI     'A'
        LBNF    ER9
        SMI     26
        LBDF    ER9
        GLO     RA
        XRI     2
        LBZ     ERY
        SEP     R4
        DW      SPTAB
        LBZ     ERY
        LDA     RD
        SMI     'A'
        LBNF    ER9
        SMI     26
        LBDF    ER9
        GLO     RA
        XRI     3
        LBZ     ERY
        SEP     R4
        DW      SPTAB
        LBNZ    ER9
ERY:    LOAD    RD, ROFF
        LDI     1
        STR     RD
ER9:    LOAD    RD, LLEN        ; the next line
        LDI     0
        STR     RD
        INC     RD              ; LNHEX
        STR     RD
        LBR     LBCLR
EL9:    SEP     R5
; DLINE: LB (RA.0 = the line's length, to 255) a STELLAR listing line? DF = 1 if so:
;   D hhhh    ; D hhhh    ;D hhhh    (then a space or the end)    ;hhhh  hh (a disassembly; then a space or the end)
;   - h an upper-case hex digit. Keeps RA.
DLINE:  LOAD    RD, LB
        LDN     RD
        XRI     'D'
        LBNZ    DN1
        INC     RD
        LDN     RD
        XRI     ' '
        LBNZ    DNNO
        LDI     2               ; "D ": the address at 2, the end at 6
        LBR     DNA
DN1:    XRI     7FH             ; ('D' XOR ';')
        LBNZ    DNNO
        INC     RD
        LDN     RD
        XRI     ' '
        LBNZ    DN2
        INC     RD              ; "; D "
        LDA     RD
        XRI     'D'
        LBNZ    DNNO
        LDN     RD
        XRI     ' '
        LBNZ    DNNO
        LDI     4
        LBR     DNA
DN2:    XRI     64H             ; (' ' XOR 'D') ";D "?
        LBNZ    DN3
        INC     RD
        LDN     RD
        XRI     ' '
        LBNZ    DN3
        LDI     3
        LBR     DNA
DN3:    LOAD    RD, LB+1        ; ";hhhh  hh"
        LDI     4
        SEP     R4
        DW      HEXU
        LBDF    DNNO
        LDA     RD
        XRI     ' '
        LBNZ    DNNO
        LDA     RD
        XRI     ' '
        LBNZ    DNNO
        LDI     2
        SEP     R4
        DW      HEXU
        LBDF    DNNO
        LDI     9
        LBR     DNE
DNA:    PLO     RB              ; the address at LB + RB.0, the end 4 on
        ADI     LOW(LB)
        PLO     RD
        LDI     HIGH(LB)
        ADCI    0
        PHI     RD
        LDI     4
        SEP     R4
        DW      HEXU
        LBDF    DNNO
        GLO     RB
        ADI     4
DNE:    PLO     RB              ; the end at RB.0: the length is it, or a space is there
        GLO     RA
        STR     R2
        GLO     RB
        XOR
        LBZ     DNYES
        GLO     RB
        ADI     LOW(LB)
        PLO     RD
        LDI     HIGH(LB)
        ADCI    0
        PHI     RD
        LDN     RD
        XRI     ' '
        LBNZ    DNNO
DNYES:  LDI     1
        SHR
        SEP     R5
DNNO:   LDI     0
        SHR
        SEP     R5
; HEXU: D upper-case hex digits at RD (RD past them)? DF = 0 if so
HEXU:   PLO     RE
HU1:    LDA     RD
        SMI     '0'
        LBNF    HUNO
        SMI     10
        LBNF    HU2
        SMI     7               ; 'A' - ('9' + 1)
        LBNF    HUNO
        SMI     6
        LBDF    HUNO
HU2:    DEC     RE
        GLO     RE
        LBNZ    HU1
        LDI     0
        SHR
        SEP     R5
HUNO:   LDI     1
        SHR
        SEP     R5

; SPTAB: the byte at RD a space or a TAB? D = 0 if so
SPTAB:  LDN     RD
        XRI     ' '
        LBZ     ST9
        XRI     29H             ; (' ' XOR TAB)
ST9:    SEP     R5

TSTL:   DB      'STL1'
TPAK:   DB      'LPAK'
TVER:   DB      'VER:'
MAGIC:  DB      0, 4, 89H, 'PNG', 'PNG image', 0
        DB      0, 4, 'GIF8', 'GIF image', 0
        DB      0, 3, 0FFH, 0D8H, 0FFH, 'JPEG image', 0
        DB      0, 5, '%PDF-', 'PDF document', 0
        DB      0, 4, 'PK', 3, 4, 'ZIP archive', 0
        DB      0, 2, 1FH, 8BH, 'gzip data', 0
        DB      0, 4, 'MThd', 'MIDI music', 0
        DB      8, 4, 'WAVE', 'WAV sound', 0
        DB      0, 4, 7FH, 'ELF', 'ELF program', 0
        DB      0FFH
ARGP:   DS      2
NEXTA:  DS      2
NFOUND: DS      1
NCOL:   DS      1
CNT:    DS      1
PEND9:  DS      4               ; the end, the load address
ENAME:  DS      11
HDR:    DS      32              ; HDR, HDRV: in this order
HDRV:   DS      16
NSEC:   DS      1               ; NSEC ... SCAN_E: zeroed for each file
BAD:    DS      1
HI:     DS      1
U8N:    DS      1
U8BAD:  DS      1
CRLF:   DS      1
PREVCR: DS      1
HEXOK:  DS      1
HEXANY: DS      1
DANY:   DS      1
CLCOK:  DS      1
CLCANY: DS      1
ROFF:   DS      1
LLEN:   DS      1               ; LLEN, LNHEX: in this order
LNHEX:  DS      1
LB:     DS      12
XCOL:   DS      1
SCAN_E:
PEND:
        END
