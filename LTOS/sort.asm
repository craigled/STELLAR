; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; sort.asm - SORT.PRG: SORT [-r] [-n] [-u] name - the file's lines in order.
;   (none) by their characters (byte by byte; a shorter line first when it is the start of the other)
;   -n     by the number at the start (spaces, then - and digits; none: 0), the same number: as above
;   -r     the other way round        -u   a line the same as the one before it left out
; The whole file is held in memory: about 13 KB of lines at most (else it says so). Lines: CR dropped,
; up to 255 characters kept (as EROFF, UNIQ). A Shell sort of the lines' addresses.
; verify_uniqsort.py holds it to Python's answer.
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
        LOAD    RD, OPTR        ; OPTR, OPTN, OPTU, LEN = 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
OPT1:   SEP     R4              ; the options: -r -n -u (together or apart)
        DW      K_SKIPSP
        LDN     RF
        XRI     '-'
        LBNZ    OPT9
        INC     RF
OPT2:   LDN     RF
        LBZ     USE
        XRI     ' '
        LBZ     OPT1
        LDA     RF
        ORI     20H
        XRI     'r'
        LBNZ    OPT3
        LOAD    RD, OPTR
        LBR     OPT5
OPT3:   XRI     'r' XOR 'n'
        LBNZ    OPT4
        LOAD    RD, OPTN
        LBR     OPT5
OPT4:   XRI     'n' XOR 'u'
        LBNZ    USE
        LOAD    RD, OPTU
OPT5:   LDI     1
        STR     RD
        LBR     OPT2
OPT9:   LDN     RF
        LBZ     USE
        SEP     R4
        DW      KS_NAMEARG      ; (not there, a folder ...: the kernel says so, back to the prompt)
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, TXP         ; TXP = HEAP (the lines go up from it); PTRB = PTOP (their addresses go down)
        LDI     HIGH(HEAP)
        STR     RD
        INC     RD
        LDI     LOW(HEAP)
        STR     RD
        LOAD    RD, PTRB
        LDI     HIGH(PTOP)
        STR     RD
        INC     RD
        LDI     LOW(PTOP)
        STR     RD
        LOAD    RD, NL          ; no lines yet
        LDI     0
        STR     RD
        INC     RD
        STR     RD
; ---- the file a sector at a time; each line onto the heap
RD1:    SEP     R4
        DW      KS_FREAD        ; RC = its bytes in DATBUF
        LBDF    REOF
        LOAD    RF, KS_DATBUF
RD2:    GHI     RC
        LBNZ    RD3
        GLO     RC
        LBZ     RD1
RD3:    DEC     RC
        LDA     RF
        XRI     0DH
        LBZ     RD2             ; CR: dropped
        XRI     0DH XOR 0AH
        LBZ     RDLF
        XRI     0AH
        PLO     RE              ; RE.0 = the character
        LOAD    RD, LEN
        LDN     RD
        XRI     0FFH
        LBZ     RD2             ; 255 kept: the rest dropped
        XRI     0FFH
        ADI     LOW(CUR)
        PLO     RB
        LDI     HIGH(CUR)
        ADCI    0
        PHI     RB
        GLO     RE
        STR     RB
        LDN     RD
        ADI     1
        STR     RD
        LBR     RD2
RDLF:   SEP     R4              ; a line: onto the heap (RF, RC kept)
        DW      KEEP
        LBR     RD2
REOF:   LOAD    RD, LEN         ; a last line with no LF
        LDN     RD
        LBZ     SRT
        SEP     R4
        DW      KEEP
        LBR     SRT
USE:    SEP     R4
        DW      K_PIN
        DB      'SORT [-r] [-n] [-u] name - the lines in order (-r reversed, -n by number, -u no repeats)',0DH,0AH,0
ERR1:   LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
BIG:    SEP     R4
        DW      K_PIN
        DB      'Too big to sort: about 13 KB of lines at most.',0DH,0AH,0
        LBR     ERR1

; KEEP: CUR (LEN characters) onto the heap, 0-ended, and its address below the others; LEN = 0. RF, RC kept.
;       No room: BIG (and back to the prompt).
KEEP:   LOAD    RD, LEN         ; KLEN = LEN; LEN = 0
        LDN     RD
        PLO     RA
        LDI     0
        STR     RD
        LOAD    RD, KLEN
        GLO     RA
        STR     RD
        LDI     0               ; RA = LEN + 3 (the line, its 0, its address)
        PHI     RA
        GLO     RA
        ADI     3
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LOAD    RD, TXP         ; RB = TXP
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        GLO     RA              ; RA = TXP + it: past PTRB, no room
        STR     R2
        GLO     RB
        ADD
        PLO     RA
        GHI     RA
        STR     R2
        GHI     RB
        ADC
        PHI     RA
        LOAD    RD, PTRB
        LDA     RD
        STR     R2
        GHI     RA
        SD                      ; PTRB.1 - RA.1
        LBNF    BIG
        LBNZ    KP1
        LDN     RD
        STR     R2
        GLO     RA
        SD
        LBNF    BIG
KP1:    LOAD    RD, PTRB        ; PTRB - 2: RB (the line's address) there
        INC     RD
        LDN     RD
        SMI     2
        STR     RD
        PLO     RA
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        PHI     RA
        GHI     RB
        STR     RA
        INC     RA
        GLO     RB
        STR     RA
        LOAD    RD, KLEN        ; the line (KLEN characters from CUR), then a 0
        LDN     RD
        PLO     RE
        LOAD    RD, CUR
KP4:    GLO     RE
        LBZ     KP5
        LDA     RD
        STR     RB
        INC     RB
        DEC     RE
        LBR     KP4
KP5:    LDI     0
        STR     RB
        INC     RB
        LOAD    RD, TXP
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LOAD    RD, NL + 1      ; NL + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5

; ---- the Shell sort: the addresses at PTRB .. (NL of them), gaps NL/2, NL/4 ... 1
SRT:    LOAD    RD, NL          ; GAP = NL / 2
        LDA     RD
        SHR
        PHI     RA
        LDN     RD
        SHRC
        PLO     RA
        LOAD    RD, GAP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
SG1:    LOAD    RD, GAP         ; GAP 0: sorted
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     OUT
        LOAD    RD, GAP         ; I = GAP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, II
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
SI1:    LOAD    RD, II          ; I < NL?
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, NL + 1
        LDN     RD
        STR     R2
        GLO     RA
        SM
        DEC     RD
        LDN     RD
        STR     R2
        GHI     RA
        SMB
        LBDF    SG9             ; I >= NL: the next gap
        SEP     R4              ; TMP = A[I]; J = I
        DW      AGET            ; (RA = the index -> RB = A[it])
        LOAD    RD, TMP
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LOAD    RD, JJ
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
SJ1:    LOAD    RD, JJ          ; J >= GAP?
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, GAP + 1
        LDN     RD
        STR     R2
        GLO     RA
        SM
        PLO     RA
        DEC     RD
        LDN     RD
        STR     R2
        GHI     RA
        SMB
        PHI     RA              ; RA = J - GAP
        LBNF    SJ9             ; J < GAP: done
        SEP     R4              ; A[J - GAP] > TMP?
        DW      AGET
        LOAD    RD, PA
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LOAD    RD, TMP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, PA
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RD, JGAP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R4
        DW      CMP             ; D: 1 RB's line after RC's
        XRI     1
        LBNZ    SJ9
        LOAD    RD, PA          ; A[J] = A[J - GAP]
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RD, JJ
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      APUT
        LOAD    RD, JGAP        ; J = J - GAP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, JJ
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LBR     SJ1
SJ9:    LOAD    RD, TMP         ; A[J] = TMP
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RD, JJ
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      APUT
        LOAD    RD, II + 1      ; I + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     SI1
SG9:    LOAD    RD, GAP         ; GAP / 2
        LDN     RD
        SHR
        STR     RD
        INC     RD
        LDN     RD
        SHRC
        STR     RD
        LBR     SG1

; AGET: RA = an index -> RB = A[it] (RA kept). APUT: A[RA] = RB.
AGET:   SEP     R4
        DW      AADR            ; RD -> A[RA]
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        SEP     R5
APUT:   SEP     R4
        DW      AADR
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        SEP     R5
AADR:   LOAD    RD, PTRB        ; RD = PTRB + 2 RA
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     RA
        SHL
        PLO     RD
        GHI     RA
        SHLC
        PHI     RD
        GLO     RF
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RF
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        SEP     R5

; CMP: RB, RC -> two lines: D = 1 if RB's comes after RC's, else 0 (as Python's sort: -n by the number, then
;      byte by byte)
CMP:    LOAD    RD, OPTN
        LDN     RD
        LBZ     CB
        SEP     R4              ; -n: the numbers first
        DW      NCMP
        LBZ     CB              ; the same number: byte by byte
        XRI     1
        LBZ     CAFT
        LBR     CNOT
CB:     LDA     RB              ; byte by byte
        STR     R2
        LDA     RC
        SM                      ; (RC's) - (RB's)
        LBNZ    CB1
        LDX
        LBNZ    CB
        LBR     CNOT            ; the same
CB1:    LBNF    CAFT            ; RB's byte larger: after
CNOT:   LDI     0
        SEP     R5
CAFT:   LDI     1
        SEP     R5

; NCMP: RB, RC -> D = 0 the same number, 1 RB's larger, 2 RB's smaller. (RB, RC kept.) A number: spaces and tabs,
;       then - and digits; no digits: 0. Compared as text: the sign, then how many digits (leading 0s left
;       off), then the digits.
NCMP:   GHI     RB              ; (kept: they are compared byte by byte after a tie)
        STXD
        GLO     RB
        STXD
        GHI     RC
        STXD
        GLO     RC
        STXD
        SEP     R4              ; RB: its sign class (NSA) and digits (RB -> them, NLA of them)
        DW      NKEY
        LOAD    RD, NSA
        GLO     R9
        STR     RD
        INC     RD              ; NLA
        GHI     R9
        STR     RD
        INC     RD              ; NPA
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GHI     RC
        PHI     RB
        GLO     RC
        PLO     RB
        SEP     R4              ; RC's
        DW      NKEY
        LOAD    RD, NSA         ; the classes: 0 negative, 1 zero, 2 positive
        LDN     RD
        STR     R2
        GLO     R9
        SD                      ; A's class - B's
        LBZ     NC2
        LBNF    NCS
        LDI     1
        LBR     NC9
NCS:    LDI     2
        LBR     NC9
NC2:    LDN     RD              ; the same class: zero - the same
        XRI     1
        LBZ     NC9             ; (D = 0)
        INC     RD              ; how many digits
        LDN     RD
        STR     R2
        GHI     R9
        SD                      ; A's - B's
        LBZ     NC4
        LBNF    NC3
        LDI     1               ; A has more: larger
        LBR     NC8
NC3:    LDI     2
        LBR     NC8
NC4:    PLO     RE              ; the digits, one by one (RE.0 = 0 for now)
        INC     RD
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB              ; RB -> A's digits, RF -> B's
        LOAD    RD, NLA
        LDN     RD
        PLO     RA
NC5:    GLO     RA
        LBZ     NC8             ; (D = 0: the same)
        LDA     RF
        STR     R2
        LDA     RB
        SM                      ; A's - B's
        LBNZ    NC6
        DEC     RA
        LBR     NC5
NC6:    LBNF    NC7
        LDI     1
        LBR     NC8
NC7:    LDI     2
NC8:    PLO     RE              ; negative numbers: the other way round
        LOAD    RD, NSA
        LDN     RD
        LBNZ    NC8A
        GLO     RE
        LBZ     NC8A
        XRI     3
        PLO     RE
NC8A:   GLO     RE
NC9:    PLO     RE
        IRX                     ; RB, RC back
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDXA
        PLO     RB
        LDX
        PHI     RB
        GLO     RE
        SEP     R5

; NKEY: RB -> a line -> R9.0 = its class (0 negative, 1 zero, 2 positive), R9.1 = its digits (leading 0s off),
;       RF -> them. (A line's digits: 255 at most.) Not RE: a call's return uses RE.0, and RE.1 is the
;       Elf2K BIOS's console setting (F_TYPE to the screen goes wrong if it changes).
NKEY:   LDN     RB              ; spaces, tabs
        XRI     ' '
        LBZ     NK1
        LDN     RB
        XRI     09H
        LBNZ    NK2
NK1:    INC     RB
        LBR     NKEY
NK2:    LDI     2
        PLO     R9              ; positive, unless -
        LDN     RB
        XRI     '-'
        LBNZ    NK3
        INC     RB
        LDI     0
        PLO     R9
NK3:    LDN     RB              ; leading zeros
        XRI     '0'
        LBNZ    NK4
        INC     RB
        LBR     NK3
NK4:    GHI     RB
        PHI     RF
        GLO     RB
        PLO     RF
        LDI     0
        PHI     R9
NK5:    LDA     RB              ; the digits
        SMI     '0'
        LBNF    NK6
        SMI     10
        LBDF    NK6
        GHI     R9
        ADI     1
        PHI     R9
        LBR     NK5
NK6:    GHI     R9              ; no digits (or all 0): zero
        LBNZ    NK9
        LDI     1
        PLO     R9
NK9:    SEP     R5

; ---- out: the lines in order (-r: from the end); -u: one the same as the last out left out
OUT:    LOAD    RD, LAST        ; nothing out yet
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, II          ; I = 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
OU1:    LOAD    RD, II          ; I < NL?
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, NL + 1
        LDN     RD
        STR     R2
        GLO     RA
        SM
        DEC     RD
        LDN     RD
        STR     R2
        GHI     RA
        SMB
        LBDF    OU9
        LOAD    RD, OPTR        ; -r: NL - 1 - I
        LDN     RD
        LBZ     OU2
        LOAD    RD, NL + 1
        GLO     RA
        STR     R2
        LDN     RD
        SM
        PLO     RA
        DEC     RD
        GHI     RA
        STR     R2
        LDN     RD
        SMB
        PHI     RA
        DEC     RA
OU2:    SEP     R4
        DW      AGET            ; RB -> the line
        LOAD    RD, OPTU
        LDN     RD
        LBZ     OU4
        LOAD    RD, LAST        ; -u: the same as LAST?
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBZ     OU4             ; (none yet)
        GHI     RB
        PHI     RF
        GLO     RB
        PLO     RF
OU3:    LDA     RC
        STR     R2
        LDN     RF
        XOR
        LBNZ    OU4
        LDA     RF
        LBNZ    OU3
        LBR     OU6             ; the same: left out
OU4:    LOAD    RD, LAST
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
OU5:    LDA     RB
        LBZ     OU5A
        SEP     R4
        DW      F_TYPE
        LBR     OU5
OU5A:   SEP     R4
        DW      K_PCRLF
OU6:    LOAD    RD, II + 1      ; I + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     OU1
OU9:    SEP     R5
PEND:
OPTR:   DS      1               ; OPTR, OPTN, OPTU, LEN: in this order
OPTN:   DS      1
OPTU:   DS      1
LEN:    DS      1
KLEN:   DS      1
TXP:    DS      2
PTRB:   DS      2
NL:     DS      2
GAP:    DS      2
II:     DS      2
JJ:     DS      2
JGAP:   DS      2
TMP:    DS      2
PA:     DS      2
LAST:   DS      2
NSA:    DS      1               ; NSA, NLA, NPA: in this order
NLA:    DS      1
NPA:    DS      2
CUR:    DS      257
HEAP:
        END
