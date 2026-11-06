; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; dir.asm - DIR.PRG: DIR [-aestrwph] [path] (a folder: all of it; a pattern: those in its folder) - the files:
;   name, size, date and time, then the count and the total. The flags, before or after the path, in any mix:
;   -a by name, -e by extension, -s by size (largest first), -t by date (newest first) - folders first;
;   -r the other way round; -w wide (names only, five across); -p a screen at a time; -h hidden files too.
;   The entries are gathered first (records from TBL up to $6800, pointers to them at PTRS), then printed.
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
; ---- the flags: words starting with '-'; the other word is the path
        LOAD    RD, FLAGS       ; MODE FLR FLW FLP FLH PATP(2): 0
        LDI     7
        PLO     RB
FZ:     LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    FZ
FA0:    SEP     R4
        DW      KS_SKIPSP
        LDN     RF
        LBZ     FA9
        XRI     '-'
        LBNZ    FAP
        INC     RF
FA1:    LDN     RF              ; the letters of a -word
        LBZ     FA0
        XRI     ' '
        LBZ     FA0
        LDA     RF
        ORI     20H             ; (either case)
        PLO     RB
        LOAD    RD, FLTAB
FA2:    LDA     RD
        LBZ     USAGE           ; not one of them
        STR     R2
        GLO     RB
        XOR
        LBZ     FA3
        INC     RD
        INC     RD
        LBR     FA2
FA3:    LDA     RD              ; FLAGS + its offset = its value
        ADI     LOW(FLAGS)
        PLO     RC
        LDI     HIGH(FLAGS)
        ADCI    0
        PHI     RC
        LDN     RD
        STR     RC
        LBR     FA1
FAP:    LOAD    RD, PATP        ; the path: here
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
FAS:    LDN     RF
        LBZ     FA0
        XRI     ' '
        LBZ     FA0
        INC     RF
        LBR     FAS
FA9:    LOAD    RD, PATP        ; RF -> the path, or an empty one
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     RF
        LBNZ    DIP
        LOAD    RF, ZERO
; ---- the path or pattern -> PAT, WDIR
DIP:
        LOAD    RD, KS_PAT
        LDN     RF
        LBNZ    DI1
        LDI     11              ; no pattern: every file
        PLO     RB
DI0:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    DI0
        LBR     DI2
DIALL:  LOAD    RD, KS_PAT
        LDI     11
        PLO     RB
        LBR     DI0
DI1:    GHI     RF              ; is there a dot? (no dot: "S*" means S*.*, as in DOS)
        PHI     RC
        GLO     RF
        PLO     RC
        LDI     0
        PHI     RA              ; RA.1 = 1: a dot (PARSE keeps RA.1)
DI1A:   LDA     RC
        LBZ     DI1B
        XRI     ' '
        LBZ     DI1B
        XRI     0EH             ; (' ' xor '.')
        LBNZ    DI1A
        LDI     1
        PHI     RA
DI1B:   SEP     R4
        DW      KS_PARSE        ; (a path: WDIR = its folder)
        LBNF    DI1C
        XRI     3
        LBZ     DIALL           ; "DIR GAMES/": all of that folder
        XRI     3
        LBR     KS_PPERR
DI1C:   LOAD    RD, KS_PAT      ; a folder's name (no wildcards): all of it
        LDI     11
        PLO     RB
DI1D:   LDA     RD
        XRI     '?'
        LBZ     DI1E
        DEC     RB
        GLO     RB
        LBNZ    DI1D
        LOAD    RD, KS_PAT
        SEP     R4
        DW      KS_FOLDIN
        LBNF    DIALL
DI1E:   GHI     RA
        LBNZ    DI2
        LOAD    RD, KS_PAT+8       ; no dot: any extension
        LDI     '?'
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
DI2:    LOAD    RD, KS_NFILES   ; NFILES (2) and TOTAL (4), NREC (2) and MISS (2): zero
        LDI     6
        PLO     RB
DI3:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    DI3
        LOAD    RD, NREC
        LDI     4
        PLO     RB
DI4:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    DI4
        LOAD    RD, NEXTR
        LDI     HIGH(TBL)
        STR     RD
        INC     RD
        LDI     LOW(TBL)
        STR     RD
        SEP     R4
        DW      KS_DOPEN
        LOAD    RD, FLH         ; -h: hidden and system files too (DOPEN clears DNALL)
        LDN     RD
        LBZ     DL1
        LOAD    RD, KS_DNALL
        LDI     1
        STR     RD
; ---- gather: the totals, and a record for each entry
DL1:    SEP     R4
        DW      KS_DNEXT
        LBDF    DLEND
        LOAD    RD, ENTRY       ; (RF -> the entry in DIRBUF)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    DL2
        LOAD    RD, KS_DSIZE    ; a file: the totals
        SEP     R4
        DW      KS_LD32
        LOAD    RD, KS_TOTAL
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        LOAD    RD, KS_NFILES
        SEP     R4
        DW      INC16
DL2:    LOAD    RD, NREC        ; room for its record? (512 pointers; records below $6800)
        LDN     RD
        XRI     HIGH(NMAX)
        LBZ     DLX
        LOAD    RD, NEXTR
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GLO     RA
        ADI     RECL
        GHI     RA
        ADCI    0
        SMI     HIGH(PTRS)
        LBDF    DLX
        GHI     RA              ; R9 = the record
        PHI     R9
        GLO     RA
        PLO     R9
        LOAD    RD, KS_DATTR    ; its key: 0 a folder, $10 a file ...
        LDN     RD
        ANI     10H
        XRI     10H
        STR     RA
        INC     RA
        LOAD    RD, MODE        ; ... then what it is sorted by (11 bytes)
        LDN     RD
        SMI     2
        LBZ     KE
        SMI     1
        LBZ     KS
        SMI     1
        LBZ     KT
        SEP     R4              ; none or -a: the name
        DW      GETE
        LDI     11
        SEP     R4
        DW      CPY
        LBR     KN
KE:     SEP     R4              ; -e: the extension, the name
        DW      GETE
        GLO     RC
        ADI     8
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LDI     3
        SEP     R4
        DW      CPY
        SEP     R4
        DW      GETE
        LDI     8
        SEP     R4
        DW      CPY
        LBR     KN
KS:     LOAD    RC, KS_DSIZE    ; -s: the size, largest first (complemented); the name's first 7
        LDI     4
        SEP     R4
        DW      CPYN
        LBR     K7
KT:     LOAD    RC, KS_DDATE    ; -t: the date and time, newest first (complemented); the name's first 7
        LDI     2
        SEP     R4
        DW      CPYN
        LOAD    RC, KS_DTIME
        LDI     2
        SEP     R4
        DW      CPYN
K7:     SEP     R4
        DW      GETE
        LDI     7
        SEP     R4
        DW      CPY
KN:     SEP     R4              ; then the name, and DTIME DDATE DCLUS DSIZE as the kernel has them
        DW      GETE
        LDI     11
        SEP     R4
        DW      CPY
        LOAD    RC, KS_DTIME
        LDI     10
        SEP     R4
        DW      CPY
        LOAD    RD, NEXTR       ; the next record goes after it
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
; ---- its pointer: at the end, or (sorted) moved down past every one with a greater key
        LOAD    RD, NREC        ; RB = j = the count; R8 = PTRS + 2j
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        GLO     RB
        SHL
        PLO     R8
        GHI     RB
        SHLC
        ADI     HIGH(PTRS)
        PHI     R8
        LOAD    RD, MODE
        LDN     RD
        LBZ     INS9
INS1:   GLO     RB              ; j = 0: here
        LBNZ    INS2
        GHI     RB
        LBZ     INS9
INS2:   DEC     R8              ; RC = PTRS[j-1]
        DEC     R8
        LDA     R8
        PHI     RC
        LDN     R8
        PLO     RC
        DEC     R8
        GHI     R9              ; its key against the new one's
        PHI     RA
        GLO     R9
        PLO     RA
        LDI     KEYL
        PLO     R7
CMP1:   LDN     RA
        STR     R2
        LDN     RC
        SM
        LBNZ    CMP2
        INC     RA
        INC     RC
        DEC     R7
        GLO     R7
        LBNZ    CMP1
        LBR     INS8            ; the same: the new one after it
CMP2:   LBNF    INS8            ; smaller: the new one after it
        LDN     R8              ; greater: it moves up one (PTRS[j] = PTRS[j-1]); j = j - 1
        INC     R8
        INC     R8
        STR     R8
        DEC     R8
        LDN     R8
        INC     R8
        INC     R8
        STR     R8
        DEC     R8
        DEC     R8
        DEC     R8
        DEC     RB
        LBR     INS1
INS8:   INC     R8
        INC     R8
INS9:   GHI     R9
        STR     R8
        INC     R8
        GLO     R9
        STR     R8
        LOAD    RD, NREC
        SEP     R4
        DW      INC16
        LBR     DL1
DLX:    LOAD    RD, MISS        ; no room: counted, not listed
        SEP     R4
        DW      INC16
        LBR     DL1
; ---- print them: CURP walks PTRS (backwards with -r), LEFT counts down
DLEND:  LOAD    RD, NREC
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RD, LEFT
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LOAD    RD, COL         ; COL, LINES: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RC, PTRS
        LOAD    RD, FLR
        LDN     RD
        LBZ     PL0
        GLO     RB              ; -r: from the last
        LBNZ    PLR
        GHI     RB
        LBZ     PL0
PLR:    DEC     RB
        GLO     RB
        SHL
        PLO     RC
        GHI     RB
        SHLC
        ADI     HIGH(PTRS)
        PHI     RC
PL0:    LOAD    RD, CURP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
PL1:    LOAD    RD, LEFT
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     PLEND
        LDN     RD              ; LEFT - 1
        SMI     1
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        LOAD    RD, CURP        ; RC = the record; CURP to the next pointer
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDA     RA
        PHI     RC
        LDA     RA
        PLO     RC
        LOAD    RF, FLR
        LDN     RF
        LBZ     PL2
        DEC     RA
        DEC     RA
        DEC     RA
        DEC     RA
PL2:    GLO     RA
        STR     RD
        DEC     RD
        GHI     RA
        STR     RD
        LOAD    RD, DIRF        ; DIRF: 0 a folder
        LDN     RC
        STR     RD
        GLO     RC              ; RF -> its name
        ADI     KEYL
        PLO     RF
        GHI     RC
        ADCI    0
        PHI     RF
        LOAD    RA, KS_DTIME    ; its date, time and size back where the printing wants them
        GLO     RF
        ADI     11
        PLO     RC
        GHI     RF
        ADCI    0
        PHI     RC
        LDI     10
        SEP     R4
        DW      CPY
        LOAD    RD, FLW
        LDN     RD
        LBNZ    WIDE
        LDI     8               ; the name, the extension
        PLO     RB
DN8:    LDA     RF
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    DN8
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     3
        PLO     RB
DN9:    LDA     RF
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    DN9
        LOAD    RD, DIRF
        LDN     RD
        LBNZ    DLF
        SEP     R4
        DW      KS_PIN
        DB      '      <DIR>',0
        LBR     DLD
DLF:    LOAD    RD, KS_DSIZE
        SEP     R4
        DW      KS_LD32
        LDI     11
        SEP     R4
        DW      KS_PDEC32
DLD:    SEP     R4
        DW      PDATE
        SEP     R4
        DW      NEWLN
        LBR     PL1
; -w: NAME.EXT (a folder: NAME/) in 16 columns, five to a line
WIDE:   LDI     0               ; RB.1 = the characters so far
        PHI     RB
        LDI     8
        PLO     RB
W1:     LDA     RF
        XRI     ' '
        LBZ     W2
        XRI     ' '
        SEP     R4
        DW      F_TYPE
        GHI     RB
        ADI     1
        PHI     RB
        DEC     RB
        GLO     RB
        LBNZ    W1
        LBR     W3
W2:     DEC     RB              ; past the rest of the name
        GLO     RB
        LBZ     W3
        INC     RF
        LBR     W2
W3:     LDN     RF              ; an extension?
        XRI     ' '
        LBZ     W5
        LDI     '.'
        SEP     R4
        DW      F_TYPE
        GHI     RB
        ADI     1
        PHI     RB
        LDI     3
        PLO     RB
W4:     LDA     RF
        XRI     ' '
        LBZ     W5
        XRI     ' '
        SEP     R4
        DW      F_TYPE
        GHI     RB
        ADI     1
        PHI     RB
        DEC     RB
        GLO     RB
        LBNZ    W4
W5:     LOAD    RD, DIRF
        LDN     RD
        LBNZ    W6
        LDI     '/'
        SEP     R4
        DW      F_TYPE
        GHI     RB
        ADI     1
        PHI     RB
W6:     LOAD    RD, COL         ; the fifth: a new line
        LDN     RD
        ADI     1
        STR     RD
        XRI     5
        LBNZ    W7
        STR     RD
        SEP     R4
        DW      NEWLN
        LBR     PL1
W7:     GHI     RB              ; else spaces to the next column
        SMI     16
        LBDF    PL1
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        GHI     RB
        ADI     1
        PHI     RB
        LBR     W7
PLEND:  LOAD    RD, COL         ; -w: the last line ended
        LDN     RD
        LBZ     PE1
        SEP     R4
        DW      NEWLN
PE1:    LOAD    RD, MISS        ; any not listed?
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     PE2
        LDN     RD
        PLO     RC
        DEC     RD
        LDN     RD
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' more not listed (too many for DIR at once).',0
        SEP     R4
        DW      NEWLN
PE2:    LOAD    RD, KS_NFILES
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LDI     0
        PHI     R8
        PLO     R8
        LDI     4
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' files, ',0
        LOAD    RD, KS_TOTAL
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' bytes',0DH,0AH,0
        SEP     R5

; NEWLN: a new line; -p: after 22, wait for a key (Q, Ctrl-C or Esc: back to the prompt)
NEWLN:  SEP     R4
        DW      KS_PCRLF
        LOAD    RD, FLP
        LDN     RD
        LBZ     NL9
        LOAD    RD, K_RDIR      ; the output in a file: no pages
        LDN     RD
        LBNZ    NL9
        LOAD    RD, LINES
        LDN     RD
        ADI     1
        STR     RD
        XRI     22
        LBNZ    NL9
        STR     RD
        SEP     R4
        DW      KS_PIN
        DB      '-- more: a key goes on, Q stops --',0
        SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      KS_PIN
        DB      0DH,'                                   ',0DH,0
        GLO     RB
        ANI     0DFH
        XRI     'Q'
        LBZ     K_MAIN
        GLO     RB
        XRI     03H
        LBZ     K_MAIN
        GLO     RB
        XRI     1BH
        LBZ     K_MAIN
NL9:    SEP     R5
PDATE:  SEP     R4              ; the date and time: yyyy-mm-dd hh:mm
        DW      KS_PIN
        DB      '  ',0
        LOAD    RD, KS_DDATE
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC              ; year = 1980 + date >> 9
        SHR
        ADI     LOW(1980)
        PLO     RD
        LDI     HIGH(1980)
        ADCI    0
        PHI     RD
        SEP     R4
        DW      KS_PDEC
        LDI     '-'
        SEP     R4
        DW      F_TYPE
        GHI     RC              ; month = date >> 5 & 15
        SHR
        GLO     RC
        SHRC
        SHR
        SHR
        SHR
        SHR
        ANI     0FH
        SEP     R4
        DW      KS_P2D
        LDI     '-'
        SEP     R4
        DW      F_TYPE
        GLO     RC              ; day = date & 31
        ANI     1FH
        SEP     R4
        DW      KS_P2D
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LOAD    RD, KS_DTIME
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC              ; hour = time >> 11
        SHR
        SHR
        SHR
        SEP     R4
        DW      KS_P2D
        LDI     ':'
        SEP     R4
        DW      F_TYPE
        GLO     RC              ; minute = time >> 5 & 63 = (hi & 7) << 3 | lo >> 5
        SHR
        SHR
        SHR
        SHR
        SHR
        STR     R2
        GHI     RC
        ANI     07H
        SHL
        SHL
        SHL
        OR
        SEP     R4
        DW      KS_P2D
        SEP     R5

; GETE: RC -> the entry DNEXT gave.  CPY / CPYN: D bytes from RC to RA (CPYN: complemented); both move on.
; INC16: the 2 bytes at RD (big-endian) + 1.
GETE:   LOAD    RD, ENTRY
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R5
CPY:    PLO     RB
CP1:    LDA     RC
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    CP1
        SEP     R5
CPYN:   PLO     RB
CN1:    LDA     RC
        XRI     0FFH
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    CN1
        SEP     R5
INC16:  INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5

USAGE:  SEP     R4
        DW      K_PIN
        DB      'DIR [-a -e -s -t -r -w -p -h] [path]   (folders first when sorted)',0DH,0AH
        DB      '  -a by name   -e by extension   -s by size, largest first   -t by date, newest first',0DH,0AH
        DB      '  -r the other way round   -w wide   -p a screen at a time   -h hidden files too',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
; the flags: letter, its place in FLAGS, its value
FLTAB:  DB      'a',0,1, 'e',0,2, 's',0,3, 't',0,4, 'r',1,1, 'w',2,1, 'p',3,1, 'h',4,1, 0
ZERO:   DB      0
PEND:
FLAGS:                          ; (not in the file: after PEND)
MODE:   DS      1               ; 0 as on the card, 1 -a, 2 -e, 3 -s, 4 -t
FLR:    DS      1
FLW:    DS      1
FLP:    DS      1
FLH:    DS      1
PATP:   DS      2
NREC:   DS      2               ; NREC, MISS: in this order
MISS:   DS      2
NEXTR:  DS      2
ENTRY:  DS      2
LEFT:   DS      2
CURP:   DS      2
COL:    DS      1               ; COL, LINES: in this order
LINES:  DS      1
DIRF:   DS      1
KEYL    EQU     12              ; a record: the key (12), the name (11), DTIME DDATE DCLUS DSIZE (10)
RECL    EQU     33
NMAX    EQU     512
PTRS    EQU     6800H           ; 512 pointers, to $6BFF
TBL:                            ; the records, up to $6800
        END
