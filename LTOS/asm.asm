; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; asm.asm - ASM.PRG: ASM [-l] [-o file] name - an 1802 assembler on LTOS, for the same source a18 takes:
; name.ASM (".ASM" if no extension is typed) -> name.PRG (or -o file), the bytes from the lowest address the code
; uses to the highest (an LTOS program starts with its own 6-byte header: ORG PRGORG - 6 / DW ...). -l lists each
; line with its address and bytes (ASM -l X > X.LST keeps it). Nothing is saved if there is a mistake.
;
; As a18 (William C. Colley III's, 1985; as used for LTOS itself): labels in the first column (a ':' after one is
; dropped), the 1802's opcodes, ORG EQU SET DB/BYTE DW/WORD DS/BLK FILL TEXT PAGE LOAD CALL RETN INCL CPU END,
; IF / ELSE / ENDI; expressions with a18's own order: + - (and unary), * / MOD SHL SHR, = < > <= >= <> (EQ LT GT LE
; GE NE), NOT, AND, OR XOR, HIGH LOW, ( ), $ (here), 'c' "cc" (escapes \n \t \r \\ \' \" \xHH \ooo), numbers
; 123 0FFH 101B 17Q (or O) $FF %101 @17. Names: case counts; opcodes: either case. One error is shown for a line.
;
; Two passes, each reading the source (and its INCL files: 3 deep, a18's 4 files) a sector at a time - any size.
; A name is kept only as a 32-bit CRC and its value (6 bytes; 900 of them), so ltos.inc, kapi.inc and the kernel's
; 665 KS_ names fit with a program's own. The .PRG goes to the card a sector at a time in pass 2 (XFER's way: the
; old file stays until the new one is all there; a mistake gives the clusters back). The code must go up in
; address (ORG back over code already made is a mistake).
;
; Memory: the code $3000-$567F; the names $5680-$6BFD (917); the output sector $7700; a string $7900; the
; expression's frames $7A00; a word $7A80; IFs $7AC0; the line $7B00.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

SYMT    EQU     5680H           ; the names: 6 bytes each - the CRC (its top 6 bits of 8 with 2 flags: 80H
NSLOT   EQU     917             ;  defined in pass 2 already, 40H SET), its value - to $6BFF (verify_asm checks)
MAXSYM  EQU     900
OUTB    EQU     7700H           ; the .PRG's next sector
SBUF    EQU     7900H           ; a string (escapes done)
ESTK    EQU     7A00H           ; EVAL's frames: 4 bytes (pre, op, u) - 30 deep
NBUF    EQU     7A80H           ; a word (63 + 0)
IFSTK   EQU     7AC0H           ; IF's: 1 on, 0FFH off, 0 inside an off one (16)
LBYT    EQU     7AD0H           ; the listing's first 4 bytes of a line
LBUF    EQU     7B00H           ; the line (255 + 0)
TEOL    EQU     0               ; token kinds
TSEP    EQU     1
TOPR    EQU     2
TSTR    EQU     3
TVAL    EQU     4
PSTART  EQU     11              ; a18's precedences (>> 8)
PLPREN  EQU     9
O_AND   EQU     1               ; word operators (others are their character)
O_GE    EQU     2
O_HIGH  EQU     3
O_LE    EQU     4
O_LOW   EQU     5
O_MOD   EQU     6
O_NE    EQU     7
O_NOT   EQU     8
O_OR    EQU     9
O_SHR   EQU     10
O_SHL   EQU     11
O_XOR   EQU     12
FRSZ    EQU     29              ; a file's state (CUR): 0 the kernel's position before its sector (7), 7 the
C_OFF   EQU     7               ;  offset in DATBUF (2), 9 the bytes there (2), 11 the line (2), 13 its name (16)
C_N     EQU     9
C_LINE  EQU     11
C_NAME  EQU     13

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
        LOAD    RD, VARS        ; the variables: 0
        LOAD    RC, VEND - VARS
ST0:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST0
        GHI     RC
        LBNZ    ST0
        LOAD    RD, JMPV
        LDI     0C0H            ; (LBR)
        STR     RD
        LOAD    RD, SYMT        ; the names: none (RAM keeps a run before's)
        LOAD    RC, NSLOT * 6
ST0A:   LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST0A
        GHI     RC
        LBNZ    ST0A
; ---- the words typed
AR1:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     AR9
        XRI     '-'
        LBNZ    AR4
        INC     RF
        LDA     RF
        ANI     0DFH
        XRI     'L'
        LBNZ    AR2
        LOAD    RD, LFLAG
        LDI     1
        STR     RD
        LDN     RF
        LBZ     AR1
        XRI     ' '
        LBNZ    USE
        LBR     AR1
AR2:    XRI     03H             ; ('L' ^ 'O') -o file
        LBNZ    USE
        LDN     RF
        XRI     ' '
        LBNZ    USE
        SEP     R4
        DW      K_SKIPSP
        LOAD    RD, OUTT
        SEP     R4
        DW      CPARG
        LBDF    USE
        LBR     AR1
AR4:    LOAD    RD, SRCT        ; the source (one)
        LDN     RD
        LBNZ    USE
        SEP     R4
        DW      CPARG
        LBDF    USE
        LBR     AR1
AR9:    LOAD    RD, SRCT
        LDN     RD
        LBZ     USE
        LOAD    RF, SRCT        ; no extension: .ASM
        SEP     R4
        DW      HASEXT
        LBNF    AR10
        LOAD    RA, SASM
        SEP     R4
        DW      APPEND
AR10:   LOAD    RD, OUTT        ; no -o: the source's name, .PRG
        LDN     RD
        LBNZ    AR12
        LOAD    RF, SRCT
        LOAD    RD, OUTT
AR11:   LDA     RF
        STR     RD
        INC     RD
        LBNZ    AR11
        LOAD    RF, OUTT        ; its extension off
        SEP     R4
        DW      HASEXT          ; (RA -> its '.')
        LDI     0
        STR     RA
        LOAD    RF, OUTT
        LOAD    RA, SPRG
        SEP     R4
        DW      APPEND
AR12:   LOAD    RF, OUTT        ; a name? (checked now, before the work)
        LOAD    RD, ON11
        SEP     R4
        DW      K_PARSE
        LBDF    BADOUT
        LOAD    RD, ON11
        LDI     11
        PLO     RC
AR13:   LDA     RD
        XRI     '?'
        LBZ     BADOUT
        DEC     RC
        GLO     RC
        LBNZ    AR13
        LOAD    RD, PASS        ; pass 1
        LDI     1
        STR     RD
        SEP     R4
        DW      RUNPASS
        LOAD    RD, PASS        ; pass 2: the .PRG made as it goes
        LDI     2
        STR     RD
        SEP     R4
        DW      WSETUP
        SEP     R4
        DW      RUNPASS
        LOAD    RD, ERRS
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    ENDBAD
        SEP     R4
        DW      WFIN
        LBR     K_MAIN
ENDBAD: SEP     R4
        DW      WFREE
        LOAD    RD, ERRS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' mistake(s) - nothing saved.',0DH,0AH,0
FAILST: LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
USE:    SEP     R4
        DW      K_PIN
        DB      'Usage: ASM [-l] [-o file] name     (name.ASM -> name.PRG)',0DH,0AH,0
        LBR     FAILST
BADOUT: SEP     R4
        DW      K_PIN
        DB      'ASM: not a name for the output: ',0
        LOAD    RF, OUTT
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PCRLF
        LBR     FAILST
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
; CPARG: the word at RF (to a space) -> RD, 0-ended (63 at most: DF = 1); RF past it
CPARG:  LDI     63
        PLO     RC
CA1:    LDN     RF
        LBZ     CA9
        XRI     ' '
        LBZ     CA9
        LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    CA1
        LDI     1
        SHR
        SEP     R5
CA9:    LDI     0
        STR     RD
        SHR
        SEP     R5
; HASEXT: RF -> a path: DF = 1 if its last part has no '.'; else RA -> that '.'
HASEXT: LDI     0
        PHI     RA
CX1:    LDN     RF
        LBZ     CX9
        XRI     '/'
        LBNZ    CX2
        LDI     0
        PHI     RA
CX2:    LDN     RF
        XRI     '.'
        LBNZ    CX3
        GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
CX3:    INC     RF
        LBR     CX1
CX9:    GHI     RA
        LBZ     CX8
        LDI     0
        SHR
        SEP     R5
CX8:    LDI     1
        SHR
        SEP     R5
; APPEND: the 0-ended text at RA after the one at RF's ... (RF -> the text; RA -> what to add)
APPEND: LDN     RF
        LBZ     AP1
        INC     RF
        LBR     APPEND
AP1:    LDA     RA
        STR     RF
        INC     RF
        LBNZ    AP1
        SEP     R5

; ==== a pass over the source: RUNPASS
RUNPASS: LOAD   RD, PC
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, IFSP
        LDI     0
        STR     RD
        LOAD    RD, OFF
        LDI     0
        STR     RD
        LOAD    RD, DONE
        LDI     0
        STR     RD
        LOAD    RD, LEVEL
        LDI     0
        STR     RD
        LOAD    RD, ESP
        LDI     0FCH
        STR     RD
        LOAD    RD, IFSTK
        LDI     1
        STR     RD
        LOAD    RD, PASS
        LDN     RD
        XRI     1
        LBNZ    RP0
        LOAD    RD, LO          ; pass 1: the code's lowest and highest addresses
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, HI
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LBR     RP0A
RP0:    LOAD    RD, LO          ; pass 2: the output from LO
        LOAD    RC, OUTPC
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, LFLAG
        LDN     RD
        LBNZ    RP0B
        SEP     R4
        DW      K_PIN
        DB      'Pass 2',0
        LBR     RP0B
RP0A:   LOAD    RD, LFLAG
        LDN     RD
        LBNZ    RP0B
        SEP     R4
        DW      K_PIN
        DB      'Pass 1',0
RP0B:   LOAD    RF, SRCT        ; the source
        SEP     R4
        DW      OPENF
        LBNF    RP0C
        SEP     R4
        DW      K_PIN
        DB      0DH,0AH,'ASM: there is no ',0
        LOAD    RF, SRCT
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PCRLF
        LBR     FAILST
RP0C:   LOAD    RF, SRCT
        SEP     R4
        DW      SETNAME
RP1:    SEP     R4
        DW      RDLINE
        LBNF    RP2
        LOAD    RD, LEVEL       ; the end of a file: an INCL's - back to the one that had it
        LDN     RD
        LBZ     RP1E
        SEP     R4
        DW      POPF
        LBR     RP1
RP1E:   LOAD    RD, ERRC        ; the end with no END
        LDI     'N'
        STR     RD
        LOAD    RD, LBUF
        LDI     0
        STR     RD
        SEP     R4
        DW      LINEERR
        LBR     RP9
RP2:    SEP     R4
        DW      ASMLINE
        SEP     R4
        DW      LINEEND
        LOAD    RD, DONE
        LDN     RD
        LBNZ    RP9
        LOAD    RD, LFLAG       ; a dot every 64 lines (not with a listing)
        LDN     RD
        LBNZ    RP1
        LOAD    RD, CUR + C_LINE + 1
        LDN     RD
        ANI     3FH
        LBNZ    RP1
        LDI     '.'
        SEP     R4
        DW      K_TTY
        LBR     RP1
RP9:    LOAD    RD, LFLAG
        LDN     RD
        LBNZ    RP9A
        SEP     R4
        DW      K_PCRLF
RP9A:   SEP     R5

; ==== the files
; OPENF: RF -> a path: DF = 0 open (CUR new: line 0); DF = 1 not there (CUR as it was)
OPENF:  LOAD    RD, FN11
        SEP     R4
        DW      K_PARSE
        LBDF    OF9
        LOAD    RD, FN11
        LDI     11
        PLO     RC
OF1:    LDA     RD
        XRI     '?'
        LBZ     OF9
        DEC     RC
        GLO     RC
        LBNZ    OF1
        LOAD    RD, FN11
        SEP     R4
        DW      KS_FINDN
        LBDF    OF9
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    OF9
        LDI     0
        SHR
        SEP     R5
OF9:    LDI     1
        SHR
        SEP     R5
; FSTART: the file FINDN found: opened, CUR from its start (after OPENF)
FSTART: SEP     R4
        DW      KS_FOPEN
        LOAD    RD, CUR + C_OFF
        LDI     6
        PLO     RC
FS1:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    FS1
        SEP     R5
; SETNAME: RF -> the file's name as typed: CUR's name (15 at most)
SETNAME: SEP    R4
        DW      FSTART
        LOAD    RD, CUR + C_NAME
        LDI     15
        PLO     RC
SN1:    LDA     RF
        LBZ     SN9
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    SN1
SN9:    LDI     0
        STR     RD
        SEP     R5
; RDLINE: the next line -> LBUF (0-ended; CR, other control characters and those over 7EH left out, a Tab kept).
;         DF = 1: the file's end (nothing more)
RDLINE: LOAD    RD, CUR + C_OFF ; RA -> the next byte in DATBUF, RC = the bytes left there
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD              ; C_N
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RA
        STR     R2
        GLO     RC
        SM
        PLO     RC
        GHI     RA
        STR     R2
        GHI     RC
        SMB
        PHI     RC
        GLO     RA
        ADI     LOW(KS_DATBUF)
        PLO     RA
        GHI     RA
        ADCI    HIGH(KS_DATBUF)
        PHI     RA
        LDI     0
        PHI     RF
        LOAD    RD, LBUF
        LDI     255
        PLO     RB
RL1:    GHI     RC              ; the sector used up: the next
        LBNZ    RL2
        GLO     RC
        LBNZ    RL2
        GHI     RF              ; (a character read so far; its place in LBUF, and the room left, kept)
        PLO     RE
        LOAD    RF, GOTC
        GLO     RE
        STR     RF
        GLO     RD
        STR     R2
        LOAD    RD, RLKEEP
        LDN     R2
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LOAD    RD, CUR         ; the position before it (an INCL's file comes back to it)
        LOAD    RF, KS_FCLUS
        LDI     7
        PLO     RB
RL1A:   LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    RL1A
        SEP     R4
        DW      KS_FREAD
        LBDF    RLEOF
        LOAD    RD, CUR + C_N
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RA, KS_DATBUF
        LOAD    RD, GOTC
        LDN     RD
        PHI     RF
        LOAD    RD, RLKEEP
        LDA     RD
        PLO     RE
        LDN     RD
        PLO     RB
        LDI     HIGH(LBUF)
        PHI     RD
        GLO     RE
        PLO     RD
        LBR     RL1
RL2:    LDA     RA
        DEC     RC
        PLO     RE
        GHI     RF              ; (RF.1 = 1: a character read - GOTC at the end)
        LBNZ    RL2A
        LDI     1
        PHI     RF
RL2A:   GLO     RE
        XRI     0AH
        LBZ     RL8
        GLO     RE
        XRI     09H
        LBZ     RL3
        GLO     RE
        SMI     20H
        LBNF    RL1
        GLO     RE
        SMI     7FH
        LBDF    RL1
RL3:    GLO     RB
        LBZ     RLLONG
        GLO     RE
        STR     RD
        INC     RD
        DEC     RB
        LBR     RL1
RLLONG: LOAD    RF, LONGF       ; too long: the rest left out
        LDI     1
        STR     RF
        LBR     RL1
RLEOF:  LOAD    RD, CUR + C_N   ; nothing left in the file
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, CUR + C_OFF
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, GOTC        ; a last line with no LF?
        LDN     RD
        LBZ     RLE9
        LOAD    RD, RLKEEP
        LDA     RD
        PLO     RE
        LDI     HIGH(LBUF)
        PHI     RD
        GLO     RE
        PLO     RD
        LBR     RL9
RLE9:   LDI     1
        SHR
        SEP     R5
RL8:    LOAD    RF, CUR + C_OFF ; the place: back in CUR
        GLO     RA
        SMI     LOW(KS_DATBUF)
        PLO     RE
        GHI     RA
        SMBI    HIGH(KS_DATBUF)
        STR     RF
        INC     RF
        GLO     RE
        STR     RF
RL9:    LDI     0
        STR     RD
        LOAD    RD, CUR + C_LINE + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LDI     0
        SHR
        SEP     R5
; POPF: back to the file that had the INCL: its CUR, its sector read again
POPF:   LOAD    RD, LEVEL
        LDN     RD
        SMI     1
        STR     RD
        SEP     R4
        DW      INCAT           ; RA -> its saved CUR
        LOAD    RD, CUR
        LDI     FRSZ
        PLO     RB
PO1:    LDA     RA
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    PO1
        LOAD    RD, KS_FCLUS
        LOAD    RF, CUR
        LDI     7
        PLO     RB
PO2:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    PO2
        LOAD    RD, CUR + C_N   ; (none read yet: nothing to read again)
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     PO9
        SEP     R4
        DW      KS_FREAD
PO9:    SEP     R5
; INCAT: RA -> INCS + LEVEL x FRSZ
INCAT:  LOAD    RA, INCS
        LOAD    RD, LEVEL
        LDN     RD
        PLO     RB
IA1:    GLO     RB
        LBZ     IA9
        GLO     RA
        ADI     FRSZ
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        DEC     RB
        LBR     IA1
IA9:    SEP     R5

; ==== a line: ASMLINE
ASMLINE: LOAD   RD, ERRC        ; the line's state: no mistake, no bytes, no label ...
        LDI     0
        STR     RD
        LOAD    RD, NBYTES
        LDI     0
        STR     RD
        LOAD    RD, HASLBL
        LDI     0
        STR     RD
        LOAD    RD, SKIPL
        LDI     0
        STR     RD
        LOAD    RD, TOLD
        LDI     0
        STR     RD
        LOAD    RD, FORWD       ; (a18 clears it every line)
        LDI     0
        STR     RD
        LOAD    RD, LONGF       ; too long?
        LDN     RD
        LBZ     AL0
        LDI     0
        STR     RD
        LDI     'X'
        SEP     R4
        DW      ERR
AL0:    LOAD    RD, PC          ; the listing shows PC (EQU: its value)
        LOAD    RC, LSHOW
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RF, LBUF
        LDN     RF              ; a label?
        LBZ     AL4
        XRI     ' '
        LBZ     AL4
        LDN     RF
        XRI     09H
        LBZ     AL4
        LDN     RF
        XRI     ';'
        LBZ     AL4
        LDN     RF
        SEP     R4
        DW      ISALPH
        LBDF    AL2
        SEP     R4
        DW      GETWORD         ; -> NBUF, NLEN
        SEP     R4
        DW      SAVLP
        LOAD    RD, NLEN        ; a ':' at its end: not part of it
        LDN     RD
        PLO     RB
        LOAD    RD, NBUF - 1
        GLO     RB
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LDN     RD
        XRI     ':'
        LBNZ    AL1
        LDI     0
        STR     RD
        DEC     RB
        LOAD    RD, NLEN
        GLO     RB
        STR     RD
AL1:    GLO     RB
        LBZ     AL2X
        SEP     R4              ; an operator's word is not a label
        DW      OPWORD
        LBNF    AL2X
        LOAD    RD, NLEN
        LDN     RD
        PLO     RC
        SEP     R4
        DW      HASHN
        LOAD    RA, HV          ; the label's CRC kept
        LOAD    RD, LBLH
        LDI     4
        PLO     RB
AL1A:   LDA     RA
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    AL1A
        LOAD    RD, HASLBL
        LDI     1
        STR     RD
        LBR     AL4L
AL2:    LDN     RF              ; not a label: to the next space
        LBZ     AL2Y
        XRI     ' '
        LBZ     AL2Y
        LDN     RF
        XRI     09H
        LBZ     AL2Y
        INC     RF
        LBR     AL2
AL2Y:   LOAD    RD, LP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
AL2X:   LDI     'L'
        SEP     R4
        DW      ERR
        LBR     AL4L
AL4:    LOAD    RD, LP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
AL4L:   SEP     R4              ; the opcode
        DW      SKIPLP
        LDN     RF
        LBZ     AL5
        XRI     ';'
        LBZ     AL5
        LDN     RF
        SEP     R4
        DW      ISALPH
        LBNF    AL6
        LDI     'S'
        SEP     R4
        DW      ERR
AL5:    LOAD    RD, OFF         ; none: the label alone
        LDN     RD
        LBNZ    ALOFF
        LBR     DOLABEL
AL6:    SEP     R4
        DW      GETWORD
        LOAD    RD, LP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      OPFIND          ; RA -> its entry (DF = 1: none)
        LBNF    AL7
        LOAD    RD, OFF
        LDN     RD
        LBNZ    ALOFF
        LDI     'O'
        SEP     R4
        DW      ERR
        LBR     DOLABEL
AL7:    INC     RA              ; kind, code
        INC     RA
        INC     RA
        INC     RA
        LDA     RA
        PLO     RB
        LDN     RA
        PHI     RB
        LOAD    RD, OPC
        GHI     RB
        STR     RD
        LOAD    RD, OPK
        GLO     RB
        STR     RD
        LOAD    RD, OFF         ; in an IF that is off: only IF ELSE ENDI
        LDN     RD
        LBZ     AL8
        GLO     RB
        XRI     26
        LBZ     AL8
        GLO     RB
        XRI     28
        LBZ     AL8
        GLO     RB
        XRI     31
        LBZ     AL8
ALOFF:  LOAD    RD, SKIPL
        LDI     1
        STR     RD
        SEP     R5
AL8:    GLO     RB
        SMI     20
        LBDF    PSEUDO
        SEP     R4              ; an instruction: its label, its bytes
        DW      DOLABEL
        LOAD    RD, OPK
        LDN     RD
        PLO     RB
        LOAD    RD, PASS
        LDN     RD
        XRI     1
        LBNZ    IN1
        GLO     RB              ; pass 1: only how many bytes
        SMI     4
        LBNF    IN0
        LDI     1
        LSKP
IN0:    LDI     0
        STR     R2
        GLO     RB
        SMI     6
        LBNF    IN0A
        LDI     2
        STR     R2
IN0A:   LDN     R2
        ADI     1
        PLO     RE
        LOAD    RD, NBYTES
        GLO     RE
        STR     RD
        SEP     R5
IN1:    GLO     RB              ; pass 2: kinds 0-6
        LBZ     INNONE
        XRI     4
        LBZ     INIMM
        GLO     RB
        XRI     5
        LBZ     INBR
        GLO     RB
        XRI     6
        LBZ     INLBR
        SEP     R4              ; 1 2 3: a register or a port
        DW      EXPR
        LOAD    RD, RV
        LDA     RD
        LBNZ    INREGB
        LDN     RD
        PLO     RC
        SMI     16
        LBDF    INREGB
        LOAD    RD, OPK
        LDN     RD
        XRI     1
        LBZ     INREG2
        GLO     RC              ; 2, 3: not 0
        LBZ     INREGB
        LDN     RD
        XRI     3
        LBNZ    INREG2
        GLO     RC              ; 3: 1-7
        SMI     8
        LBDF    INREGB
INREG2: LOAD    RD, OPC
        LDN     RD
        STR     R2
        GLO     RC
        ADD
        SEP     R4
        DW      PUTOBJ
        LBR     ENDCHK
INREGB: LDI     'R'
        SEP     R4
        DW      ERR
        SEP     R4              ; (the byte all the same: the addresses stay right)
        DW      PUTOPC
        LBR     ENDCHK
INNONE: SEP     R4
        DW      PUTOPC
        LBR     ENDCHK
INIMM:  SEP     R4
        DW      PUTOPC
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      BYTEV
        SEP     R4
        DW      PUTOBJ
        LBR     ENDCHK
INBR:   SEP     R4
        DW      PUTOPC
        SEP     R4
        DW      EXPR
        LOAD    RD, PC          ; in this page? (PC + 1, the byte's own)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        INC     RC
        LOAD    RD, RV
        LDA     RD
        STR     R2
        GHI     RC
        XOR
        LBZ     INBR2
        LDI     'B'
        SEP     R4
        DW      ERR
        LOAD    RD, RV + 1
INBR2:  LDN     RD
        SEP     R4
        DW      PUTOBJ
        LBR     ENDCHK
INLBR:  SEP     R4
        DW      PUTOPC
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      PUTRV
        LBR     ENDCHK
PUTOPC: LOAD    RD, OPC
        LDN     RD
        LBR     PUTOBJ
PUTRV:  LOAD    RD, RV          ; RV, high byte first
        LDN     RD
        SEP     R4
        DW      PUTOBJ
        LOAD    RD, RV + 1
        LDN     RD
        LBR     PUTOBJ
; BYTEV: D = RV's low byte; a value over 255 (but not -128..-1): 'V'
BYTEV:  LOAD    RD, RV
        LDN     RD
        LBZ     BV9
        XRI     0FFH
        LBNZ    BVBAD
        INC     RD
        LDN     RD
        SMI     80H
        LBDF    BV9A
BVBAD:  LDI     'V'
        SEP     R4
        DW      ERR
        LDI     0
        SEP     R5
BV9:    INC     RD
BV9A:   LOAD    RD, RV + 1
        LDN     RD
        SEP     R5
; ENDCHK: nothing more on the line ('T')
ENDCHK: SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        LBZ     EC9
        LDI     'T'
        SEP     R4
        DW      ERR
EC9:    SEP     R5

; ---- the directives (OPK 20-39), through JMPV
PSEUDO: SMI     0               ; (D = kind - 20) x 2 -> PSTAB
        SHL
        ADI     LOW(PSTAB)
        PLO     RA
        LDI     HIGH(PSTAB)
        ADCI    0
        PHI     RA
        LOAD    RD, JMPV + 1
        LDA     RA
        STR     RD
        INC     RD
        LDN     RA
        STR     RD
        LBR     JMPV
PSTAB:  DW      P_DS, P_DB, P_CALL, P_CPU, P_DW, P_NONE, P_ELSE, P_END, P_ENDI, P_EQU
        DW      P_FILL, P_IF, P_INCL, P_LOAD, P_ORG, P_PAGE, P_RETN, P_SET, P_TEXT, P_NONE
P_NONE: SEP     R4              ; EJCT, TITL: nothing (the rest of the line too)
        DW      DOLABEL
        SEP     R5
P_DS:   SEP     R4
        DW      DOLABEL
        SEP     R4
        DW      EXPRNF
        LBDF    ENDCHK
        LOAD    RD, PC + 1
        LOAD    RC, RV + 1
        LDN     RC
        STR     R2
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        DEC     RC
        LDN     RC
        STR     R2
        LDN     RD
        ADC
        STR     RD
        LBR     ENDCHK
P_ORG:  SEP     R4
        DW      EXPRNF
        LBDF    PO1E
        LOAD    RD, RV
        LOAD    RC, PC
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, RV          ; (the listing: the new address)
        LOAD    RC, LSHOW
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
PO1E:   SEP     R4
        DW      DOLABEL
        LBR     ENDCHK
P_PAGE: LOAD    RD, PC + 1      ; to the next page start
        LDN     RD
        LBZ     PPG1
        LDI     0
        STR     RD
        DEC     RD
        LDN     RD
        ADI     1
        STR     RD
PPG1:   SEP     R4
        DW      DOLABEL
        LBR     ENDCHK
P_CPU:  SEP     R4
        DW      DOLABEL
        SEP     R4
        DW      EXPRNF
        LBDF    ENDCHK
        LOAD    RD, RV          ; 1802 or 1805 (=070AH, 070DH)
        LDA     RD
        XRI     07H
        LBNZ    PCPUB
        LDN     RD
        XRI     0AH
        LBZ     ENDCHK
        LDN     RD
        XRI     0DH
        LBZ     ENDCHK
PCPUB:  LDI     'V'
        SEP     R4
        DW      ERR
        LBR     ENDCHK
P_CALL: SEP     R4
        DW      DOLABEL
        LDI     0D4H
        SEP     R4
        DW      PUTOBJ
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      PUTRV
        LBR     ENDCHK
P_RETN: SEP     R4
        DW      DOLABEL
        LDI     0D5H
        SEP     R4
        DW      PUTOBJ
        LBR     ENDCHK
P_LOAD: SEP     R4              ; LOAD r, value: LDI hi PHI r LDI lo PLO r
        DW      DOLABEL
        SEP     R4
        DW      EXPR
        LOAD    RD, RV
        LDA     RD
        LBNZ    PLDB
        LDN     RD
        SMI     16
        LBNF    PLD1
PLDB:   LDI     'R'
        SEP     R4
        DW      ERR
        LOAD    RD, RV + 1
        LDI     0
        STR     RD
PLD1:   LOAD    RD, RV + 1
        LDN     RD
        PLO     RE
        LOAD    RD, LDREG
        GLO     RE
        STR     RD
        SEP     R4
        DW      EXPR
        LDI     0F8H
        SEP     R4
        DW      PUTOBJ
        LOAD    RD, RV
        LDN     RD
        SEP     R4
        DW      PUTOBJ
        LOAD    RD, LDREG
        LDN     RD
        ORI     0B0H
        SEP     R4
        DW      PUTOBJ
        LDI     0F8H
        SEP     R4
        DW      PUTOBJ
        LOAD    RD, RV + 1
        LDN     RD
        SEP     R4
        DW      PUTOBJ
        LOAD    RD, LDREG
        LDN     RD
        ORI     0A0H
        SEP     R4
        DW      PUTOBJ
        LBR     ENDCHK
P_DB:   SEP     R4              ; DB / BYTE: values and strings
        DW      DOLABEL
PDB1:   SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        XRI     TSEP
        LBZ     PDB1            ; (nothing between two ,)
        LDN     RD
        XRI     TSTR
        LBNZ    PDB3
        SEP     R4              ; a string: its characters
        DW      PUTSTR
        SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        XRI     TSEP
        LBZ     PDB1
        SEP     R4
        DW      UNLEX
        LBR     ENDCHK
PDB3:   SEP     R4
        DW      UNLEX
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      BYTEV
        SEP     R4
        DW      PUTOBJ
        LOAD    RD, TTYPE       ; (EXPR stops at a , or the end)
        LDN     RD
        XRI     TSEP
        LBZ     PDB1
        SEP     R5
P_DW:   SEP     R4              ; DW / WORD
        DW      DOLABEL
PDW1:   SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        XRI     TSEP
        LBNZ    PDW2
        LOAD    RD, RV          ; (nothing: 0)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LBR     PDW3
PDW2:   SEP     R4
        DW      UNLEX
        SEP     R4
        DW      EXPR
PDW3:   SEP     R4
        DW      PUTRV
        LOAD    RD, TTYPE
        LDN     RD
        XRI     TSEP
        LBZ     PDW1
        SEP     R5
P_TEXT: SEP     R4              ; strings only
        DW      DOLABEL
PTX1:   SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        LBZ     PTX9
        XRI     TSTR
        LBZ     PTX2
        LDI     'S'
        SEP     R4
        DW      ERR
        SEP     R5
PTX2:   SEP     R4
        DW      PUTSTR
        SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        XRI     TSEP
        LBZ     PTX1
        SEP     R4
        DW      UNLEX
        LBR     PTX1
PTX9:   SEP     R5
P_FILL: SEP     R4              ; FILL value, count
        DW      DOLABEL
        SEP     R4
        DW      EXPR
        SEP     R4
        DW      BYTEV
        PLO     RE
        LOAD    RD, FILLV
        GLO     RE
        STR     RD
        SEP     R4
        DW      EXPR
        LOAD    RD, RV
        LDA     RD
        LBNZ    PFLB
        LDN     RD
        XRI     0FFH
        LBNZ    PFL1
PFLB:   LDI     'V'
        SEP     R4
        DW      ERR
        LBR     ENDCHK
PFL1:   LDN     RD
        PLO     RB
PFL2:   GLO     RB
        LBZ     ENDCHK
        LOAD    RD, FILLV
        LDN     RD
        SEP     R4
        DW      PUTOBJ          ; (keeps RB)
        DEC     RB
        LBR     PFL2
P_END:  SEP     R4
        DW      DOLABEL
        LOAD    RD, LEVEL       ; in an INCL's file: a mistake
        LDN     RD
        LBZ     PEN1
        LDI     '*'
        SEP     R4
        DW      ERR
        SEP     R5
PEN1:   LOAD    RD, DONE
        LDI     1
        STR     RD
        LOAD    RD, IFSP
        LDN     RD
        LBZ     PEN9
        LDI     'I'
        SEP     R4
        DW      ERR
PEN9:   SEP     R5
P_INCL: SEP     R4              ; INCL "file"
        DW      DOLABEL
        SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        XRI     TSTR
        LBZ     PIN1
        LDI     'S'
        SEP     R4
        DW      ERR
        SEP     R5
PIN1:   LOAD    RD, LEVEL
        LDN     RD
        SMI     3
        LBNF    PIN2
        LDI     'Z'
        SEP     R4
        DW      ERR
        SEP     R5
PIN2:   LOAD    RF, SBUF
        SEP     R4
        DW      OPENF
        LBNF    PIN3
        LDI     'F'
        SEP     R4
        DW      ERR
        SEP     R5
PIN3:   SEP     R4              ; this file's place kept
        DW      INCAT
        LOAD    RD, CUR
        LDI     FRSZ
        PLO     RB
PIN4:   LDA     RD
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    PIN4
        LOAD    RD, LEVEL
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, INCLN       ; (shown in the listing / a mistake with the INCL's line)
        LDI     1
        STR     RD
        LOAD    RF, SBUF
        LBR     SETNAME
P_EQU:  LOAD    RD, HASLBL      ; NAME EQU value
        LDN     RD
        LBNZ    PEQ1
        LDI     'L'
        LBR     ERR
PEQ1:   SEP     R4
        DW      EXPRNF
        LOAD    RD, RV          ; (the listing: its value)
        LOAD    RC, LSHOW
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LDI     0
        SEP     R4
        DW      DEFSYM
        LBR     ENDCHK
P_SET:  LOAD    RD, HASLBL      ; NAME SET value (again and again)
        LDN     RD
        LBNZ    PST1
        LDI     'L'
        LBR     ERR
PST1:   SEP     R4
        DW      EXPR
        LDI     40H
        SEP     R4
        DW      DEFSYM
        LBR     ENDCHK
P_IF:   SEP     R4
        DW      IFLBL
        LOAD    RD, IFSP
        LDN     RD
        ADI     1
        STR     RD
        SMI     16
        LBNF    PIF1
        LDI     'I'
        SEP     R4
        DW      ERR
        LOAD    RD, IFSP
        LDI     15
        STR     RD
PIF1:   SEP     R4
        DW      EXPR
        LOAD    RD, FORWD
        LDN     RD
        LBZ     PIF2
        LDI     'P'
        SEP     R4
        DW      ERR
        LOAD    RD, RV + 1
        LDI     1
        STR     RD
PIF2:   SEP     R4
        DW      IFAT            ; RA -> IFSTK[IFSP]
        LOAD    RD, OFF
        LDN     RD
        LBZ     PIF3
        LDI     0
        STR     RA
        LBR     ENDCHK
PIF3:   LOAD    RD, RV
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     PIF4
        LDI     1
        STR     RA
        LBR     ENDCHK
PIF4:   LDI     0FFH
        STR     RA
        LOAD    RD, OFF
        LDI     1
        STR     RD
        LBR     ENDCHK
P_ELSE: SEP     R4
        DW      IFLBL
        LOAD    RD, IFSP
        LDN     RD
        LBZ     PIFBAD
        SEP     R4
        DW      IFAT
        LDN     RA              ; turned round (0 stays 0)
        SDI     0
        STR     RA
PEL1:   XRI     1
        LBZ     PEL2
        LDI     1
PEL2:   PLO     RE
        LOAD    RD, OFF
        GLO     RE
        STR     RD
        LBR     ENDCHK
P_ENDI: SEP     R4
        DW      IFLBL
        LOAD    RD, IFSP
        LDN     RD
        LBZ     PIFBAD
        SMI     1
        STR     RD
        SEP     R4
        DW      IFAT
        LDN     RA
        LBR     PEL1
PIFBAD: LDI     'I'
        SEP     R4
        DW      ERR
        LBR     ENDCHK
IFLBL:  LOAD    RD, HASLBL      ; IF ELSE ENDI take no label
        LDN     RD
        LBZ     IL9
        LDI     0
        STR     RD
        LDI     'L'
        LBR     ERR
IL9:    SEP     R5
IFAT:   LOAD    RD, IFSP
        LDN     RD
        ADI     LOW(IFSTK)
        PLO     RA
        LDI     HIGH(IFSTK)
        PHI     RA
        SEP     R5
; EXPRNF: EXPR, and a name defined only further on is a mistake ('P', DF = 1)
EXPRNF: SEP     R4
        DW      EXPR
        LOAD    RD, FORWD
        LDN     RD
        LBZ     ENF9
        LDI     'P'
        SEP     R4
        DW      ERR
        LDI     1
        SHR
        SEP     R5
ENF9:   SHR
        SEP     R5
; PUTSTR: SBUF's SLEN characters out
PUTSTR: LOAD    RD, SLEN
        LDN     RD
        PLO     RB
        LOAD    RA, SBUF
PS1:    GLO     RB
        LBZ     PS9
        LDA     RA
        SEP     R4
        DW      PUTOBJ          ; (keeps RA, RB)
        DEC     RB
        LBR     PS1
PS9:    SEP     R5

; ---- the names
; DOLABEL: the line's label = PC
DOLABEL: LOAD   RD, PC
        LOAD    RC, RV
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LDI     0
; DEFSYM: the line's label = RV (D = 40H: SET). Pass 1: a new name kept (one there already: as it was, unless SET).
;         Pass 2: marked as defined; a different value: 'M'
DEFSYM: PLO     RE
        LOAD    RD, HASLBL
        LDN     RD
        LBZ     DS9
        LOAD    RD, SETF
        GLO     RE
        STR     RD
        LOAD    RA, LBLH
        LOAD    RD, HV
        LDI     4
        PLO     RB
DS1:    LDA     RA
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    DS1
        SEP     R4
        DW      SYMFIND         ; RA -> its entry (DF = 1: an empty one)
        LBNF    DS4
        LOAD    RD, PASS
        LDN     RD
        XRI     1
        LBNZ    DSP             ; (pass 2 and not there: cannot be)
        LOAD    RD, NSYM + 1    ; a new one
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SMI     HIGH(MAXSYM)
        LBNF    DS2
        LBNZ    DSFULL
        INC     RD
        LDN     RD
        SMI     LOW(MAXSYM)
        LBDF    DSFULL
DS2:    LOAD    RD, HV + 3      ; the CRC, the flag
        LDN     RD
        ANI     3FH
        STR     R2
        LOAD    RD, SETF
        LDN     RD
        OR
        STR     RA
        INC     RA
        LOAD    RD, HV + 2
        LDN     RD
        STR     RA
        INC     RA
        DEC     RD
        LDN     RD
        STR     RA
        INC     RA
        DEC     RD
        LDN     RD
        STR     RA
        INC     RA
DS3:    LOAD    RD, RV          ; its value
        LDA     RD
        STR     RA
        INC     RA
        LDN     RD
        STR     RA
DS9:    SEP     R5
DS4:    LDN     RA              ; there already: SET may change it
        ANI     40H
        LBZ     DS5
        LOAD    RD, SETF
        LDN     RD
        LBZ     DS5
        LOAD    RD, PASS
        LDN     RD
        XRI     2
        LBNZ    DS4A
        LDN     RA
        ORI     80H
        STR     RA
DS4A:   INC     RA
        INC     RA
        INC     RA
        INC     RA
        LBR     DS3
DS5:    LOAD    RD, PASS
        LDN     RD
        XRI     1
        LBZ     DS9             ; pass 1: the first stays
        LDN     RA              ; pass 2: defined now; the same value?
        ORI     80H
        STR     RA
        INC     RA
        INC     RA
        INC     RA
        INC     RA
        LOAD    RD, RV
        LDA     RD
        STR     R2
        LDA     RA
        XOR
        LBNZ    DSM
        LDN     RD
        STR     R2
        LDN     RA
        XOR
        LBZ     DS9
DSM:    LDI     'M'
        LBR     ERR
DSP:    LDI     'P'
        LBR     ERR
DSFULL: SEP     R4
        DW      K_PIN
        DB      0DH,0AH,'ASM: too many names (900; out/ksyms.inc alone has 665).',0DH,0AH,0
        LBR     FAILST
; SYMFIND: HV -> RA = its entry, DF = 0; or DF = 1, RA = the empty slot for it
SYMFIND: LOAD   RD, HV + 1      ; slot = HV's low 10 bits; x 6
        LDN     RD
        ANI     03H
        PHI     RA
        INC     RD
        DEC     RD
        DEC     RD
        LDN     RD
        PLO     RA
        GLO     RA              ; (mod NSLOT: under 1024 < 2 NSLOT)
        SMI     LOW(NSLOT)
        PLO     RC
        GHI     RA
        SMBI    HIGH(NSLOT)
        LBNF    SFX
        PHI     RA
        GLO     RC
        PLO     RA
SFX:    GLO     RA              ; x 2 -> RC, x 4 -> RA; RA + RC
        SHL
        PLO     RC
        GHI     RA
        SHLC
        PHI     RC
        GLO     RC
        SHL
        PLO     RA
        GHI     RC
        SHLC
        PHI     RA
        GLO     RC
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GHI     RC
        STR     R2
        GHI     RA
        ADC
        PHI     RA
        GLO     RA              ; + SYMT
        ADI     LOW(SYMT)
        PLO     RA
        GHI     RA
        ADCI    HIGH(SYMT)
        PHI     RA
SF1:    LDN     RA              ; empty?
        ANI     3FH
        INC     RA
        STR     R2
        LDA     RA
        OR
        STR     R2
        LDA     RA
        OR
        STR     R2
        LDN     RA
        OR
        DEC     RA
        DEC     RA
        DEC     RA
        LBZ     SFNO
        LOAD    RD, HV + 3      ; the same CRC?
        LDN     RD
        ANI     3FH
        STR     R2
        LDA     RA
        ANI     3FH
        XOR
        LBNZ    SF2
        DEC     RD
        LDN     RD
        STR     R2
        LDA     RA
        XOR
        LBNZ    SF3
        DEC     RD
        LDN     RD
        STR     R2
        LDA     RA
        XOR
        LBNZ    SF4
        DEC     RD
        LDN     RD
        STR     R2
        LDN     RA
        XOR
        LBNZ    SF5
        DEC     RA
        DEC     RA
        DEC     RA
        SHR                     ; (D = 0: DF = 0)
        SEP     R5
SF5:                            ; the next slot (the last: back to the first)
SF4:    DEC     RA
SF3:    DEC     RA
SF2:    DEC     RA
        GLO     RA
        ADI     6
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        XRI     HIGH(SYMT + NSLOT * 6)
        LBNZ    SF1
        GLO     RA
        XRI     LOW(SYMT + NSLOT * 6)
        LBNZ    SF1
        LOAD    RA, SYMT
        LBR     SF1
SFNO:   LDI     1
        SHR
        SEP     R5
; HASHN: the CRC-32 of NBUF's first RC.0 characters -> HV (0 low .. 3 high; never all 0 in its 30 bits).
;        A byte at a time from two 16-entry tables (CRCL, CRCH: 128 bytes, not 1 KB): R8:R7 = the CRC
HASHN:  LDI     0FFH
        PHI     R7
        PLO     R7
        PHI     R8
        PLO     R8
        LOAD    RD, NBUF
HN1:    GLO     RC
        LBZ     HN9
        LDA     RD
        STR     R2
        GLO     R7
        XOR
        PLO     R7
        PLO     R9              ; i = (CRC xor c) & 0FFH; CRC = (CRC >> 8) xor CRCL[i & 15] xor CRCH[i >> 4]
        GHI     R7              ; >> 8: bytes down
        PLO     R7
        GLO     R8
        PHI     R7
        GHI     R8
        PLO     R8
        LDI     0
        PHI     R8
        GLO     R9
        ANI     0FH
        SHL
        SHL
        ADI     LOW(CRCL)
        PLO     RB
        LDI     HIGH(CRCL)
        ADCI    0
        PHI     RB
        SEX     RB              ; R8:R7 xor the 4 bytes at RB (low first)
        GLO     R7
        XOR
        PLO     R7
        INC     RB
        GHI     R7
        XOR
        PHI     R7
        INC     RB
        GLO     R8
        XOR
        PLO     R8
        INC     RB
        GHI     R8
        XOR
        PHI     R8
        SEX     R2
        GLO     R9
        SHR
        SHR
        ANI     3CH             ; (i >> 4) x 4
        ADI     LOW(CRCH)
        PLO     RB
        LDI     HIGH(CRCH)
        ADCI    0
        PHI     RB
        SEX     RB              ; R8:R7 xor the 4 bytes at RB (low first)
        GLO     R7
        XOR
        PLO     R7
        INC     RB
        GHI     R7
        XOR
        PHI     R7
        INC     RB
        GLO     R8
        XOR
        PLO     R8
        INC     RB
        GHI     R8
        XOR
        PHI     R8
        SEX     R2
        DEC     RC
        LBR     HN1
HN9:    LOAD    RD, HV
        GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        INC     RD
        GHI     R8
        STR     RD
        ANI     3FH
        STR     R2
        GLO     R8
        OR
        STR     R2
        GHI     R7
        OR
        STR     R2
        GLO     R7
        OR
        LBNZ    HN10
        LOAD    RD, HV
        LDI     1
        STR     RD
HN10:   SEP     R5
CRCL:
        DB      000H,000H,000H,000H, 096H,030H,007H,077H, 02CH,061H,00EH,0EEH, 0BAH,051H,009H,099H
        DB      019H,0C4H,06DH,007H, 08FH,0F4H,06AH,070H, 035H,0A5H,063H,0E9H, 0A3H,095H,064H,09EH
        DB      032H,088H,0DBH,00EH, 0A4H,0B8H,0DCH,079H, 01EH,0E9H,0D5H,0E0H, 088H,0D9H,0D2H,097H
        DB      02BH,04CH,0B6H,009H, 0BDH,07CH,0B1H,07EH, 007H,02DH,0B8H,0E7H, 091H,01DH,0BFH,090H
CRCH:
        DB      000H,000H,000H,000H, 064H,010H,0B7H,01DH, 0C8H,020H,06EH,03BH, 0ACH,030H,0D9H,026H
        DB      090H,041H,0DCH,076H, 0F4H,051H,06BH,06BH, 058H,061H,0B2H,04DH, 03CH,071H,005H,050H
        DB      020H,083H,0B8H,0EDH, 044H,093H,00FH,0F0H, 0E8H,0A3H,0D6H,0D6H, 08CH,0B3H,061H,0CBH
        DB      0B0H,0C2H,064H,09BH, 0D4H,0D2H,0D3H,086H, 078H,0E2H,00AH,0A0H, 01CH,0F2H,0BDH,0BDH

; ---- words, opcodes, operators
; GETWORD: RF -> a name's characters -> NBUF (63 kept, a 0 after), RC.0 = how many kept; RF past them all
GETWORD: LOAD   RD, NBUF
        LDI     0
        PLO     RC
GW1:    LDN     RF              ; (ISALNUM, here: it runs for every character)
        SMI     40H
        LBNF    GW2
        SMI     3FH             ; @ .. ~
        LBNF    GW5
        LBR     GW9
GW2:    LDN     RF
        SMI     '0'
        LBNF    GW3
        SMI     10
        LBNF    GW5
GW3:    LDN     RF
        XRI     '!'
        LBZ     GW5
        LDN     RF
        SMI     '#'             ; # $ % &
        LBNF    GW4
        SMI     4
        LBNF    GW5
GW4:    LDN     RF
        XRI     '.'
        LBZ     GW5
        LDN     RF
        XRI     ':'
        LBZ     GW5
        LDN     RF
        XRI     '?'
        LBNZ    GW9
GW5:    LDA     RF
        PLO     RE
        GLO     RC
        XRI     63
        LBZ     GW1
        GLO     RE
        STR     RD
        INC     RD
        INC     RC
        LBR     GW1
GW9:    LDI     0
        STR     RD
        LOAD    RD, NLEN
        GLO     RC
        STR     RD
        SEP     R5
; ISALPH: D a name's first character (a18's: @ to ~, ! # $ % & . : ?) -> DF = 0; ISALNUM: or a digit
ISALNUM: PLO    RE
        SMI     '0'
        LBNF    IA0
        SMI     10
        LBNF    ISY
IA0:    GLO     RE
ISALPH: PLO     RE
        SMI     40H
        LBNF    IA2
        GLO     RE
        SMI     7FH
        LBNF    ISY
        LBR     ISN
IA2:    GLO     RE
        XRI     '!'
        LBZ     ISY
        GLO     RE
        SMI     '#'             ; # $ % &
        LBNF    IA3
        SMI     4
        LBNF    ISY
IA3:    GLO     RE
        XRI     '.'
        LBZ     ISY
        GLO     RE
        XRI     ':'
        LBZ     ISY
        GLO     RE
        XRI     '?'
        LBZ     ISY
ISN:    LDI     1
        SHR
        SEP     R5
ISY:    LDI     0
        SHR
        SEP     R5
; UPKEY: NBUF's first 4 characters in upper case -> KEY (0-filled); DF = 1 if NBUF is longer than 4
UPKEY:  LOAD    RA, NBUF
        LOAD    RD, KEY
        LDI     4
        PLO     RB
UK1:    LDA     RA
        LBZ     UK2
        SMI     'a'
        LBNF    UK1A
        SMI     26
        LBDF    UK1A
        DEC     RA
        LDA     RA
        SMI     20H
        LSKP
UK1A:   DEC     RA
        LDA     RA
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    UK1
        LDN     RA              ; longer?
        LBZ     UK3
        LDI     1
        SHR
        SEP     R5
UK2:    DEC     RA              ; the rest 0
UK2A:   LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    UK2A
UK3:    LDI     0
        SHR
        SEP     R5
; OPFIND: NBUF an opcode? -> RA its entry (DF = 0)
OPFIND: SEP     R4
        DW      UPKEY
        LBDF    OFNO
        LOAD    RD, KEY
        LDN     RD
        SMI     'A'
        LBNF    OFNO
        SMI     26
        LBDF    OFNO
        LDN     RD
        SMI     'A'
        SHL
        ADI     LOW(OPIX)
        PLO     RA
        LDI     HIGH(OPIX)
        ADCI    0
        PHI     RA
        LDA     RA
        PHI     RC
        LDN     RA
        PLO     RA
        GHI     RC
        PHI     RA
        LBZ     OFNO
OF2:    LDN     RA              ; still this letter?
        STR     R2
        LOAD    RD, KEY
        LDA     RD
        XOR
        LBNZ    OFNO
        INC     RA              ; the second (the rest only if it is the same)
        LDN     RA
        DEC     RA
        STR     R2
        LDN     RD
        XOR
        LBNZ    OF3
        SEP     R4
        DW      KEYEQ
        LBNF    OF9F
OF3:    GLO     RA
        ADI     6
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     OF2
OF9F:   SEP     R5
OFNO:   LDI     1
        SHR
        SEP     R5
; KEYEQ: the 4 bytes at RA = KEY? DF = 0 (RA kept)
KEYEQ:  LOAD    RD, KEY
        LDI     4
        PLO     RB
KE1:    LDA     RA
        STR     R2
        LDA     RD
        XOR
        LBNZ    KE8
        DEC     RB
        GLO     RB
        LBNZ    KE1
        DEC     RA
        DEC     RA
        DEC     RA
        DEC     RA
        SHR
        SEP     R5
KE8:    GLO     RB              ; RA back by 5 - RB
        SDI     5
        PLO     RB
KE8A:   DEC     RA
        DEC     RB
        GLO     RB
        LBNZ    KE8A
        LDI     1
        SHR
        SEP     R5
; OPWORD: NBUF an operator's word ($ AND EQ ...)? DF = 0: RA -> its entry (4 letters, attr, code)
OPWORD: SEP     R4
        DW      UPKEY
        LBDF    OFNO
        LOAD    RA, OPWT
OW1:    LDN     RA
        LBZ     OFNO
        STR     R2              ; (its first letter first: most names are not one)
        LOAD    RD, KEY
        LDN     RD
        XOR
        LBNZ    OW2
        SEP     R4
        DW      KEYEQ
        LBNF    OF9F
OW2:    GLO     RA
        ADI     6
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     OW1
OPWT:   DB      '$',0,0,0,40H,'$'
        DB      'AND',0,85H,O_AND
        DB      'EQ',0,0,83H,'='
        DB      'GE',0,0,83H,O_GE
        DB      'GT',0,0,83H,'>'
        DB      'HIGH',47H,O_HIGH
        DB      'LE',0,0,83H,O_LE
        DB      'LOW',0,47H,O_LOW
        DB      'LT',0,0,83H,'<'
        DB      'MOD',0,81H,O_MOD
        DB      'NE',0,0,83H,O_NE
        DB      'NOT',0,44H,O_NOT
        DB      'OR',0,0,86H,O_OR
        DB      'SHL',0,81H,O_SHL
        DB      'SHR',0,81H,O_SHR
        DB      'XOR',0,86H,O_XOR
        DB      0
; SKIPLP: RF = LP, past spaces and Tabs (LP too)
SKIPLP: LOAD    RD, LP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
SK1:    LDN     RF
        XRI     ' '
        LBZ     SK2
        LDN     RF
        XRI     09H
        LBNZ    SK9
SK2:    INC     RF
        LBR     SK1
SK9:    GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        SEP     R5

; ==== the tokens: LEX -> TTYPE, TV (2), TATTR (operators: 80H binary, 40H unary, the low 4 bits a18's
;      precedence); a string's characters in SBUF (SLEN). UNLEX: the same one again next time.
UNLEX:  LOAD    RD, TOLD
        LDI     1
        STR     RD
        SEP     R5
LEX:    LOAD    RD, TOLD
        LDN     RD
        LBZ     LX0
        LDI     0
        STR     RD
        SEP     R5
LX0:    SEP     R4
        DW      SKIPLP
        LDN     RF
        LBZ     LXEOL
        XRI     ';'
        LBZ     LXEOL
        LDN     RF
        SEP     R4
        DW      ISALPH
        LBNF    LXW
        LDN     RF
        SMI     '0'
        LBNF    LX2
        SMI     10
        LBNF    LXN
LX2:    LDA     RF              ; the others: one character (or two)
        PLO     RB
        SEP     R4
        DW      SAVLP
        GLO     RB
        XRI     ','
        LBNZ    LX3
        LDI     TSEP
        LBR     LXT
LX3:    GLO     RB
        XRI     27H
        LBZ     LXS
        GLO     RB
        XRI     22H
        LBZ     LXS
        LOAD    RA, CHOPS       ; ( ) + - * /
LX4:    LDA     RA
        LBZ     LX5
        STR     R2
        GLO     RB
        XOR
        LBZ     LX4A
        INC     RA
        LBR     LX4
LX4A:   LDN     RA
        LBR     SETOP
LX5:    GLO     RB              ; < = >
        XRI     '<'
        LBNZ    LX6
        LDN     RF
        XRI     '='
        LBNZ    LX5A
        LDI     O_LE
        LBR     LXREL2
LX5A:   LDN     RF
        XRI     '>'
        LBNZ    LXREL
        LDI     O_NE
        LBR     LXREL2
LX6:    GLO     RB
        XRI     '='
        LBNZ    LX7
        LDN     RF
        XRI     '<'
        LBNZ    LX6A
        LDI     O_LE
        LBR     LXREL2
LX6A:   LDN     RF
        XRI     '>'
        LBNZ    LXREL
        LDI     O_GE
        LBR     LXREL2
LX7:    GLO     RB
        XRI     '>'
        LBNZ    LXBAD
        LDN     RF
        XRI     '<'
        LBNZ    LX7A
        LDI     O_NE
        LBR     LXREL2
LX7A:   LDN     RF
        XRI     '='
        LBNZ    LXREL
        LDI     O_GE
LXREL2: PLO     RB              ; a two-character one
        INC     RF
        SEP     R4
        DW      SAVLP
LXREL:  LDI     83H
        LBR     SETOP
LXBAD:  LDI     'E'             ; a character that means nothing here
        SEP     R4
        DW      XERR
LXEOL:  LDI     TEOL
LXT:    PLO     RE
        LOAD    RD, TTYPE
        GLO     RE
        STR     RD
        LOAD    RD, TV
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R5
SETOP:  PLO     RC              ; an operator: D = its attr, RB.0 = its code
        LOAD    RD, TATTR
        GLO     RC
        STR     RD
        LOAD    RD, TV
        LDI     0
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LOAD    RD, TTYPE
        LDI     TOPR
        STR     RD
        SEP     R5
CHOPS:  DB      '(',49H,')',88H,'+',0C2H,'-',0C2H,'*',81H,'/',81H,0
SAVLP:  LOAD    RD, LP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R5
; a word: an operator, a $ % @ number, or a name
LXW:    SEP     R4
        DW      GETWORD
        SEP     R4
        DW      SAVLP
        SEP     R4
        DW      OPWORD
        LBDF    LXW2
        INC     RA
        INC     RA
        INC     RA
        INC     RA
        LDA     RA
        PLO     RC
        LDN     RA
        PLO     RB
        GLO     RC
        LBR     SETOP
LXW2:   LOAD    RD, NBUF        ; $ % @: a number
        LDN     RD
        XRI     '$'
        LBNZ    LXW3
        LDI     16
        LBR     LXW5
LXW3:   LDN     RD
        XRI     '%'
        LBNZ    LXW4
        LDI     2
        LBR     LXW5
LXW4:   LDN     RD
        XRI     '@'
        LBNZ    LXNM
        LDI     8
LXW5:   PLO     RE
        LOAD    RD, NLEN
        LDN     RD
        SMI     1
        PLO     RB
        LOAD    RA, NBUF + 1
        GLO     RE
        LBR     MKNUM
LXNM:   LOAD    RD, NLEN        ; a name: its value
        LDN     RD
        PLO     RC
        SEP     R4
        DW      HASHN
        SEP     R4
        DW      SYMFIND
        LBDF    LXU
        LDN     RA              ; (pass 2: not defined yet - forward)
        ANI     80H
        LBNZ    LXN1
        LOAD    RD, PASS
        LDN     RD
        XRI     2
        LBNZ    LXN1
        LOAD    RD, FORWD
        LDI     1
        STR     RD
LXN1:   INC     RA
        INC     RA
        INC     RA
        INC     RA
        LOAD    RD, TV
        LDA     RA
        STR     RD
        INC     RD
        LDN     RA
        STR     RD
        LBR     LXV
LXU:    LOAD    RD, PASS        ; not there: pass 2 'U'; pass 1 0 (a forward one)
        LDN     RD
        XRI     2
        LBNZ    LXU1
        LDI     'U'
        SEP     R4
        DW      XERR
LXU1:   LOAD    RD, FORWD
        LDI     1
        STR     RD
        LOAD    RD, XBAD
        LDI     1
        STR     RD
        LOAD    RD, TV
        LDI     0
        STR     RD
        INC     RD
        STR     RD
LXV:    LOAD    RD, TTYPE
        LDI     TVAL
        STR     RD
        SEP     R5
; a number from a digit: its last letter the base (B, O/Q, D, H; none: 10)
LXN:    SEP     R4
        DW      GETWORD
        SEP     R4
        DW      SAVLP
        LOAD    RD, NLEN
        LDN     RD
        PLO     RB
        LOAD    RA, NBUF - 1    ; the last character
        GLO     RB
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LDN     RA
        ANI     0DFH
        XRI     'B'
        LBNZ    LXN2
        LDI     2
        LBR     LXN6
LXN2:   LDN     RA
        ANI     0DFH
        XRI     'O'
        LBZ     LXN3
        LDN     RA
        ANI     0DFH
        XRI     'Q'
        LBNZ    LXN4
LXN3:   LDI     8
        LBR     LXN6
LXN4:   LDN     RA
        ANI     0DFH
        XRI     'H'
        LBNZ    LXN5
        LDI     16
        LBR     LXN6
LXN5:   LDN     RA
        ANI     0DFH
        XRI     'D'
        LBZ     LXN5A
        INC     RB              ; (no letter: all of it)
LXN5A:  LDI     10
LXN6:   DEC     RB
        PLO     RE
        LOAD    RA, NBUF
        GLO     RE
; MKNUM: RB.0 digits at RA in base D -> TV, a value token ('D': not a digit of the base)
MKNUM:  PLO     RE
        LOAD    RD, NBASE
        GLO     RE
        STR     RD
        LDI     0
        PLO     R8
        PHI     R8
MN1:    GLO     RB
        LBZ     MN9
        LDA     RA              ; its digit
        PLO     RE
        SMI     '0'
        LBNF    MNBAD
        SMI     10
        LBNF    MN2
        GLO     RE
        ANI     0DFH
        SMI     'A'
        LBNF    MNBAD
        SMI     6
        LBDF    MNBAD
        ADI     16              ; (A-F: 10-15)
        LSKP
MN2:    ADI     10
        PLO     RE
        LOAD    RD, NBASE
        LDN     RD
        STR     R2
        GLO     RE
        SM
        LBDF    MNBAD
        LDN     RD              ; R8 x base (shifts; 10: x 8 + x 2) + the digit
        XRI     10
        LBNZ    MN3
        GLO     R8              ; x 2 -> R7
        SHL
        PLO     R8
        PLO     R7
        GHI     R8
        SHLC
        PHI     R8
        PHI     R7
        GLO     R8              ; x 4 more: x 8
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        GLO     R8
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        GLO     R7
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     R7
        STR     R2
        GHI     R8
        ADC
        PHI     R8
        LBR     MN4
MN3:    LDN     RD              ; 2, 8, 16: one shift each time it halves
        SHR
MN3A:   PLO     R9
        GLO     R8
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        GLO     R9
        SHR
        LBNZ    MN3A
MN4:    GLO     RE
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        DEC     RB
        LBR     MN1
MNBAD:  LDI     'D'
        SEP     R4
        DW      XERR
MN9:    LOAD    RD, TV
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        LBR     LXV
; a string: to its closing quote, the escapes done -> SBUF, SLEN; its value the first character (two: both)
LXS:    LOAD    RD, SBUF
        LDI     0
        PLO     RC
LS1:    LDN     RF
        LBZ     LSOPEN
        GLO     RB
        STR     R2
        LDN     RF
        XOR
        LBZ     LS8
        LDA     RF
        XRI     5CH
        LBZ     LSESC
        XRI     5CH
LS2:    STR     RD
        INC     RD
        INC     RC
        GLO     RC
        XRI     0FFH
        LBNZ    LS1
LSOPEN: LDI     0               ; no closing quote (the 0 first: XERR uses RD)
        STR     RD
        LDI     22H
        SEP     R4
        DW      XERR
        LBR     LS9A
LS8:    INC     RF
LS9:    LDI     0               ; (a 0 after it: INCL's name)
        STR     RD
LS9A:   SEP     R4
        DW      SAVLP
        LOAD    RD, SLEN
        GLO     RC
        STR     RD
        LOAD    RD, TV
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        GLO     RC
        LBZ     LS9B
        LOAD    RA, SBUF
        LDA     RA
        STR     RD
        GLO     RC
        XRI     1
        LBZ     LS9B
        LDN     RD
        DEC     RD
        STR     RD
        INC     RD
        LDN     RA
        STR     RD
LS9B:   LOAD    RD, TTYPE
        LDI     TSTR
        STR     RD
        SEP     R5
LSESC:  LDA     RF              ; \x (R9.0)
        PLO     R9
        LBNZ    LSE1
        DEC     RF
        LBR     LSOPEN
LSE1:   LOAD    RA, ESCT
LE1:    LDA     RA
        LBZ     LE2
        STR     R2
        GLO     R9
        XOR
        LBZ     LE1A
        INC     RA
        LBR     LE1
LE1A:   LDN     RA
        LBR     LS2
LE2:    GLO     R9              ; three octal digits?
        SMI     '0'
        LBNF    LE4
        SMI     8
        LBDF    LE4
        LDN     RF
        SMI     '0'
        LBNF    LE4
        SMI     8
        LBDF    LE4
        INC     RF
        LDN     RF
        DEC     RF
        SMI     '0'
        LBNF    LE4
        SMI     8
        LBDF    LE4
        GLO     R9
        SMI     '0'
        SHL
        SHL
        SHL
        STR     R2
        LDA     RF
        SMI     '0'
        OR
        SHL
        SHL
        SHL
        STR     R2
        LDA     RF
        SMI     '0'
        OR
        LBR     LS2
LE4:    GLO     R9              ; x and two hex digits?
        ANI     0DFH
        XRI     'X'
        LBNZ    LE9
        LDN     RF
        SEP     R4
        DW      HEXD
        LBDF    LE9
        SHL
        SHL
        SHL
        SHL
        PHI     R9
        INC     RF
        LDN     RF
        DEC     RF
        SEP     R4
        DW      HEXD
        LBDF    LE9
        STR     R2
        GHI     R9
        OR
        INC     RF
        INC     RF
        LBR     LS2
LE9:    LDI     5CH             ; not one: the character as it is
        SEP     R4
        DW      XERR
        GLO     RC              ; (RD again: XERR used it)
        PLO     RD
        LDI     HIGH(SBUF)
        PHI     RD
        GLO     R9
        LBR     LS2
ESCT:   DB      22H,22H,27H,27H,5CH,5CH,'a',07H,'b',08H,'f',0CH,'n',0AH,'r',0DH,'t',09H,'v',0BH,0
; HEXD: D a hex digit -> its value, DF = 0 (M(R2) used)
HEXD:   PLO     RE
        SMI     '0'
        LBNF    HDN
        SMI     10
        LBNF    HD1
        GLO     RE
        ANI     0DFH
        SMI     'A'
        LBNF    HDN
        SMI     6
        LBDF    HDN
        ADI     16
        LSKP
HD1:    ADI     10
        PLO     RE
        LDI     0
        SHR
        GLO     RE
        SEP     R5
HDN:    LDI     1
        SHR
        SEP     R5

; ==== expressions, a18's way: EXPR -> RV (0 if it went wrong), FORWD = 1 if a name was not defined yet
EXPR:   LOAD    RD, XBAD
        LDI     0
        STR     RD
        LDI     PSTART
        SEP     R4
        DW      EVAL
        LOAD    RD, XBAD
        LDN     RD
        LBZ     EXR9
        LOAD    RD, RV
        LDI     0
        STR     RD
        INC     RD
        STR     RD
EXR9:   SEP     R5
; XERR: D = a mistake in an expression: noted, and the expression's value will be 0
XERR:   PLO     RE
        LOAD    RD, XBAD
        LDI     1
        STR     RD
        LOAD    RD, FORWD
        LDI     1
        STR     RD
        GLO     RE
; ERR: D = a mistake's letter, kept if it is the line's first
ERR:    PLO     RE
        LOAD    RD, ERRC
        LDN     RD
        LBNZ    ER9
        GLO     RE
        STR     RD
ER9:    SEP     R5
; GETFR: RA -> the current frame (pre, op, u)
GETFR:  LOAD    RA, ESP         ; (RD kept)
        LDN     RA
        PLO     RA
        LDI     HIGH(ESTK)
        PHI     RA
        SEP     R5
; EVAL: D = pre -> RV
EVAL:   PLO     RE
        LOAD    RD, ESP         ; a new frame
        LDN     RD
        ADI     4
        STR     RD
        PLO     RA
        SMI     120
        LBNF    EV0
        LDI     'Z'             ; too deep
        SEP     R4
        DW      XERR
        LOAD    RD, RV
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LBR     EVZ
EV0:    LDI     HIGH(ESTK)
        PHI     RA
        GLO     RE
        STR     RA
EV1:    SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        LBZ     EVE
        XRI     TSEP
        LBZ     EVS
        XRI     03H             ; (TSEP ^ TOPR)
        LBZ     EVO
        LOAD    RD, TV          ; a value or a string: u
EV2:    SEP     R4
        DW      GETFR
        INC     RA
        INC     RA
        LDA     RD
        STR     RA
        INC     RA
        LDN     RD
        STR     RA
        LBR     EVV
EVS:    SEP     R4              ; , : (only the top one keeps it)
        DW      GETFR
        LDN     RA
        XRI     PSTART
        LBZ     EVE
        SEP     R4
        DW      UNLEX
EVE:    LDI     'E'
        SEP     R4
        DW      XERR
        LOAD    RD, TV
        LBR     EVR
EVO:    LOAD    RD, TATTR       ; an operator first: unary only
        LDN     RD
        ANI     40H
        LBNZ    EVO1
        LDI     'E'
        SEP     R4
        DW      XERR
        LBR     EV1
EVO1:   SEP     R4
        DW      GETFR
        INC     RA
        LOAD    RD, TV + 1
        LDN     RD
        STR     RA
        XRI     '$'
        LBNZ    EVO2
        LOAD    RD, PC          ; $: here
        LBR     EV2
EVO2:   LDN     RD
        XRI     '+'
        LBZ     EVO3
        LDN     RD
        XRI     '-'
        LBZ     EVO3
        LOAD    RD, TATTR
        LDN     RD
        ANI     0FH
        LSKP
EVO3:   LDI     0
        SEP     R4
        DW      EVAL
        SEP     R4
        DW      GETFR
        INC     RA
        LDA     RA              ; the operator
        PLO     RB
        LOAD    RD, RV
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        GLO     RB
        XRI     '-'
        LBNZ    EVO4
        GLO     R8
        SDI     0
        PLO     R8
        GHI     R8
        SDBI    0
        PHI     R8
        LBR     EVO9
EVO4:   GLO     RB
        XRI     O_NOT
        LBNZ    EVO5
        GLO     R8
        XRI     0FFH
        PLO     R8
        GHI     R8
        XRI     0FFH
        PHI     R8
        LBR     EVO9
EVO5:   GLO     RB
        XRI     O_HIGH
        LBNZ    EVO6
        GHI     R8
        PLO     R8
        LDI     0
        PHI     R8
        LBR     EVO9
EVO6:   GLO     RB
        XRI     O_LOW
        LBNZ    EVO9
        LDI     0
        PHI     R8
EVO9:   GHI     R8              ; u
        STR     RA
        INC     RA
        GLO     R8
        STR     RA
; EVV: a value so far (u): then , ) the end, or a binary operator
EVV:    SEP     R4
        DW      LEX
        LOAD    RD, TTYPE
        LDN     RD
        LBZ     EVV9
        XRI     TSEP
        LBZ     EVVS
        XRI     03H
        LBZ     EVVO
        LDI     'E'             ; a value after a value
        SEP     R4
        DW      XERR
        LBR     EVV
EVVS:   SEP     R4
        DW      GETFR
        LDN     RA
        XRI     PSTART
        LBZ     EVV9
        SEP     R4
        DW      UNLEX
EVV9:   SEP     R4
        DW      GETFR
        LDN     RA
        XRI     PLPREN
        LBNZ    EVV9A
        LDI     '('
        SEP     R4
        DW      XERR
EVV9A:  SEP     R4
        DW      GETFR
        INC     RA
        INC     RA
        GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
EVR:    LOAD    RC, RV          ; RV = the 2 bytes at RD; the frame off
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
EVZ:    LOAD    RD, ESP
        LDN     RD
        SMI     4
        STR     RD
        SEP     R5
EVVO:   LOAD    RD, TATTR       ; binary?
        LDN     RD
        ANI     80H
        LBNZ    EVVO1
        LDI     'E'
        SEP     R4
        DW      XERR
        LBR     EVV
EVVO1:  LDN     RD              ; its precedence >= pre: not this one's
        ANI     0FH
        PLO     RB
        SEP     R4
        DW      GETFR
        LDN     RA
        STR     R2
        GLO     RB
        SM
        LBNF    EVVO2
        SEP     R4
        DW      UNLEX
        LBR     EVV9A
EVVO2:  INC     RA              ; the operator
        LOAD    RD, TV + 1
        LDN     RD
        STR     RA
        XRI     ')'
        LBZ     EVV3
        GLO     RB              ; v = the rest, as far as it binds tighter
        SEP     R4
        DW      EVAL
EVV3:   SEP     R4
        DW      GETFR
        INC     RA
        LDA     RA
        PLO     RB              ; the operator
        LDA     RA              ; R8 = u, R7 = v
        PHI     R8
        LDN     RA
        PLO     R8
        LOAD    RD, RV
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LOAD    RA, BOPS        ; its routine
EVV4:   LDA     RA
        LBZ     EVV9A           ; (cannot be)
        STR     R2
        GLO     RB
        XOR
        LBZ     EVV5
        INC     RA
        INC     RA
        LBR     EVV4
EVV5:   LOAD    RD, JMPV + 1
        LDA     RA
        STR     RD
        INC     RD
        LDN     RA
        STR     RD
        LBR     JMPV
BOPS:   DB      '+'
        DW      B_ADD
        DB      '-'
        DW      B_SUB
        DB      '*'
        DW      B_MUL
        DB      '/'
        DW      B_DIV
        DB      O_MOD
        DW      B_MOD
        DB      O_AND
        DW      B_AND
        DB      O_OR
        DW      B_OR
        DB      O_XOR
        DW      B_XOR
        DB      '<'
        DW      B_LT
        DB      O_LE
        DW      B_LE
        DB      '='
        DW      B_EQ
        DB      O_GE
        DW      B_GE
        DB      '>'
        DW      B_GT
        DB      O_NE
        DW      B_NE
        DB      O_SHL
        DW      B_SHL
        DB      O_SHR
        DW      B_SHR
        DB      ')'
        DW      B_RP
        DB      0
B_ADD:  GLO     R7
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     R7
        STR     R2
        GHI     R8
        ADC
        PHI     R8
        LBR     BSET
B_SUB:  GLO     R7
        STR     R2
        GLO     R8
        SM
        PLO     R8
        GHI     R7
        STR     R2
        GHI     R8
        SMB
        PHI     R8
        LBR     BSET
B_AND:  GLO     R7
        STR     R2
        GLO     R8
        AND
        PLO     R8
        GHI     R7
        STR     R2
        GHI     R8
        AND
        PHI     R8
        LBR     BSET
B_OR:   GLO     R7
        STR     R2
        GLO     R8
        OR
        PLO     R8
        GHI     R7
        STR     R2
        GHI     R8
        OR
        PHI     R8
        LBR     BSET
B_XOR:  GLO     R7
        STR     R2
        GLO     R8
        XOR
        PLO     R8
        GHI     R7
        STR     R2
        GHI     R8
        XOR
        PHI     R8
        LBR     BSET
B_MUL:  GHI     R8              ; R9 = u; R8 = 0; v times: add (shift and add, 16 bits)
        PHI     R9
        GLO     R8
        PLO     R9
        LDI     0
        PHI     R8
        PLO     R8
        LDI     16
        PLO     RC
BM1:    GLO     R8              ; R8 x 2
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        GLO     R7              ; v's top bit
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        LBNF    BM2
        GLO     R9
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     R9
        STR     R2
        GHI     R8
        ADC
        PHI     R8
BM2:    DEC     RC
        GLO     RC
        LBNZ    BM1
        LBR     BSET
B_DIV:  SEP     R4
        DW      DIV16
        LBR     BSET
B_MOD:  SEP     R4
        DW      DIV16
        GHI     R9
        PHI     R8
        GLO     R9
        PLO     R8
        LBR     BSET
; DIV16: R8 / R7 -> R8, the rest R9 (by 0: 'E', 0)
DIV16:  GHI     R7
        LBNZ    DV1
        GLO     R7
        LBNZ    DV1
        LDI     'E'
        SEP     R4
        DW      XERR
        LDI     0
        PHI     R8
        PLO     R8
        PHI     R9
        PLO     R9
        SEP     R5
DV1:    LDI     0
        PHI     R9
        PLO     R9
        LDI     16
        PLO     RC
DV2:    GLO     R8              ; R9:R8 x 2
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        GLO     R9
        SHLC
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        GLO     R7              ; R9 >= v: take it, a 1
        STR     R2
        GLO     R9
        SM
        PLO     RE
        GHI     R7
        STR     R2
        GHI     R9
        SMB
        LBNF    DV3
        PHI     R9
        GLO     RE
        PLO     R9
        INC     R8
DV3:    DEC     RC
        GLO     RC
        LBNZ    DV2
        SEP     R5
; the comparisons: R8 - R7 (DF = 1: u >= v), the same?
B_LT:   SEP     R4
        DW      BCMP
        LBNF    BTRUE
        LBR     BFALSE
B_GE:   SEP     R4
        DW      BCMP
        LBDF    BTRUE
        LBR     BFALSE
B_LE:   SEP     R4
        DW      BCMP
        LBNF    BTRUE
        LBZ     BTRUE
        LBR     BFALSE
B_GT:   SEP     R4
        DW      BCMP
        LBNF    BFALSE
        LBZ     BFALSE
        LBR     BTRUE
B_EQ:   SEP     R4
        DW      BCMP
        LBZ     BTRUE
        LBR     BFALSE
B_NE:   SEP     R4
        DW      BCMP
        LBNZ    BTRUE
BFALSE: LDI     0
        LSKP
BTRUE:  LDI     1
        PLO     R8
        LDI     0
        PHI     R8
        LBR     BSET
; BCMP: DF = 1 if R8 >= R7; D = 0 if they are the same
BCMP:   GLO     R7
        STR     R2
        GLO     R8
        SM
        PLO     RE
        GHI     R7
        STR     R2
        GHI     R8
        SMB
        STR     R2
        GLO     RE
        OR
        SEP     R5
B_SHL:  SEP     R4
        DW      BSHN
        LBDF    BSET
BSL1:   GLO     R7
        LBZ     BSET
        GLO     R8
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        DEC     R7
        LBR     BSL1
B_SHR:  SEP     R4
        DW      BSHN
        LBDF    BSET
BSR1:   GLO     R7
        LBZ     BSET
        GHI     R8
        SHR
        PHI     R8
        GLO     R8
        SHRC
        PLO     R8
        DEC     R7
        LBR     BSR1
; BSHN: v over 15: 'E' (DF = 1, u as it was)
BSHN:   GHI     R7
        LBNZ    BSH1
        GLO     R7
        SMI     16
        LBDF    BSH1
        SHR                     ; (DF stays 0: D - 16 borrowed)
        LDI     0
        SHR
        SEP     R5
BSH1:   LDI     'E'
        SEP     R4
        DW      XERR
        LDI     1
        SHR
        SEP     R5
B_RP:   SEP     R4              ; ): the end of a ( ... ) if that is what this is
        DW      GETFR
        LDN     RA
        XRI     PLPREN
        LBZ     EVV9A
        LDI     '('
        SEP     R4
        DW      XERR
        LBR     EVV
BSET:   SEP     R4              ; u = R8, on
        DW      GETFR
        INC     RA
        INC     RA
        GHI     R8
        STR     RA
        INC     RA
        GLO     R8
        STR     RA
        LBR     EVV

; ==== bytes out: PUTOBJ (D) - pass 1 counts them; pass 2 puts them in the .PRG at PC + NBYTES (keeps RA, RB)
PUTOBJ: PLO     RE
        LOAD    RD, PASS
        LDN     RD
        XRI     1
        LBZ     PB8
        GLO     RE              ; the listing's first 4
        STR     R2
        LOAD    RD, NBYTES
        LDN     RD
        SMI     4
        LBDF    PB1
        LDN     RD
        ADI     LOW(LBYT)
        PLO     RD
        LDI     HIGH(LBYT)
        PHI     RD
        LDN     R2
        STR     RD
PB1:    LDN     R2              ; its address: PC + NBYTES
        PHI     R9
        LOAD    RD, NBYTES
        LDN     RD
        STR     R2
        LOAD    RD, PC + 1
        LDN     RD
        ADD
        PLO     RC
        DEC     RD
        LDN     RD
        ADCI    0
        PHI     RC
        LOAD    RD, OUTPC       ; before what is out already: 'G'
        LDA     RD
        STR     R2
        GHI     RC
        SM
        LBNF    PBGO
        LBNZ    PB3
        LDN     RD
        STR     R2
        GLO     RC
        SM
        LBNF    PBGO
PB3:    LOAD    RD, OUTPC       ; a gap: 0s
        LDA     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    PB4
        LDN     RD
        STR     R2
        GLO     RC
        XOR
        LBZ     PB5
PB4:    LDI     0
        SEP     R4
        DW      PUTB
        LBR     PB3
PB5:    GHI     R9
        SEP     R4
        DW      PUTB
        LBR     PB8
PBGO:   LDI     'G'
        SEP     R4
        DW      ERR
PB8:    LOAD    RD, NBYTES
        LDN     RD
        ADI     1
        STR     RD
        SEP     R5
; PUTB: D the .PRG's next byte (OUTPC + 1); a full sector to the card. Nothing once there is a mistake.
;       Keeps RA, RB, RC, R9.
PUTB:   PLO     RE
        LOAD    RD, OUTPC + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, ERRS
        LDA     RD
        LBNZ    PU9
        LDN     RD
        LBNZ    PU9
        LOAD    RD, OUTN
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     RE
        STR     RF
        INC     RF
        GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        XRI     HIGH(OUTB + 512)
        LBNZ    PU9
        LDI     HIGH(OUTB)
        STR     RD
        GLO     RA              ; (WRBLK uses them)
        STXD
        GHI     RA
        STXD
        GLO     RB
        STXD
        GHI     RB
        STXD
        GLO     RC
        STXD
        GHI     RC
        STXD
        GLO     R9
        STXD
        GHI     R9
        STXD
        SEP     R4
        DW      WRBLK
        LBDF    WFULL
        IRX
        LDXA
        PHI     R9
        LDXA
        PLO     R9
        LDXA
        PHI     RC
        LDXA
        PLO     RC
        LDXA
        PHI     RB
        LDXA
        PLO     RB
        LDXA
        PHI     RA
        LDX
        PLO     RA
PU9:    SEP     R5

; ==== the line's end: LINEEND
LINEEND: LOAD   RD, PASS
        LDN     RD
        XRI     1
        LBNZ    LE20
        LOAD    RD, NBYTES      ; pass 1: LO / HI
        LDN     RD
        LBZ     LEPC
        PLO     RB
        LOAD    RD, PC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, LO          ; PC < LO: LO = PC
        LDA     RD
        STR     R2
        GHI     RC
        SM
        LBNF    LE11
        LBNZ    LE12
        LDN     RD
        STR     R2
        GLO     RC
        SM
        LBDF    LE12
LE11:   LOAD    RD, LO
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
LE12:   GLO     RB              ; PC + n > HI: HI = it
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LOAD    RD, HI
        LDA     RD
        STR     R2
        GHI     RC
        SM
        LBNF    LEPC
        LBNZ    LE13
        LDN     RD
        STR     R2
        GLO     RC
        SM
        LBNF    LEPC
        LBZ     LEPC
LE13:   LOAD    RD, HI
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LBR     LEPC
LE20:   LOAD    RD, LFLAG       ; pass 2: the listing, the mistake
        LDN     RD
        LBZ     LE21
        SEP     R4
        DW      LISTL
LE21:   SEP     R4
        DW      LINEERR
LEPC:   LOAD    RD, NBYTES      ; PC + the bytes
        LDN     RD
        STR     R2
        LOAD    RD, PC + 1
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, INCLN       ; (an INCL's first line comes next: its line number)
        LDI     0
        STR     RD
        SEP     R5
; LISTL: "AAAA BBBBBBBB  the line" (a line that IF skips: no address)
LISTL:  LOAD    RD, SKIPL
        LDN     RD
        LBZ     LI1
        SEP     R4
        DW      K_PIN
        DB      '               ',0
        LBR     LI8
LI1:    LOAD    RD, LSHOW
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      K_PHEX4
        LDI     ' '
        SEP     R4
        DW      K_OUT
        LDI     0
        PLO     RB
LI2:    LOAD    RD, LCNT        ; (kept: the kernel's output keeps only RD, RF)
        GLO     RB
        STR     RD
        LOAD    RD, NBYTES
        LDN     RD
        STR     R2
        GLO     RB
        SM
        LBDF    LI3
        GLO     RB
        SMI     4
        LBDF    LI3
        GLO     RB
        ADI     LOW(LBYT)
        PLO     RD
        LDI     HIGH(LBYT)
        PHI     RD
        LDN     RD
        SEP     R4
        DW      K_PHEX2
        LBR     LI4
LI3:    SEP     R4
        DW      K_PIN
        DB      '  ',0
LI4:    LOAD    RD, LCNT
        LDN     RD
        ADI     1
        PLO     RB
        XRI     4
        LBNZ    LI2
        SEP     R4
        DW      K_PIN
        DB      '  ',0
LI8:    LOAD    RF, LBUF
        SEP     R4
        DW      PSTR
        LBR     K_PCRLF
; LINEERR: the line's mistake, if any: counted; the first 20 shown ("NAME line: what", then the line)
LINEERR: LOAD   RD, ERRC
        LDN     RD
        LBZ     LR9
        LOAD    RD, PASS
        LDN     RD
        XRI     2
        LBNZ    LR9
        LOAD    RD, ERRS + 1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBNZ    LR9
        INC     RD
        LDN     RD
        SMI     21
        LBDF    LR9
        LOAD    RF, CUR + C_NAME
        SEP     R4
        DW      PSTR
        LDI     ' '
        SEP     R4
        DW      K_OUT
        LOAD    RD, CUR + C_LINE
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ': ',0
        LOAD    RA, MSGS        ; its words
LR1:    LDA     RA
        LBZ     LR3
        STR     R2
        LOAD    RD, ERRC
        LDN     RD
        XOR
        LBZ     LR3
LR2:    LDA     RA
        LBNZ    LR2
        LBR     LR1
LR3:    GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PCRLF
        LOAD    RD, LFLAG       ; the line (the listing shows it)
        LDN     RD
        LBNZ    LR9
        LOAD    RD, LBUF
        LDN     RD
        LBZ     LR9
        SEP     R4
        DW      K_PIN
        DB      '    ',0
        LOAD    RF, LBUF
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PCRLF
LR9:    SEP     R5
MSGS:   DB      'E','not a good expression',0
        DB      'U','a name not defined',0
        DB      'D','not a number in its base',0
        DB      'R','not a register (0-15) or port (1-7)',0
        DB      'V','a value out of range',0
        DB      'B','a short branch out of this page',0
        DB      'P','a name defined only further on',0
        DB      'M','defined twice, with two values',0
        DB      'L','not a label',0
        DB      'O','not an opcode',0
        DB      'S','not as it should be written',0
        DB      'T','more on the line than there should be',0
        DB      'I','IF / ELSE / ENDI out of order',0
        DB      '(','( and ) do not match',0
        DB      22H,'no closing quote',0
        DB      5CH,'not a ',5CH,' escape',0
        DB      '*','END inside an INCL file',0
        DB      'F','no such INCL file',0
        DB      'Z','too deep (INCL 3, IF 15, ( 29)',0
        DB      'G','code at an address already made (an ORG back)',0
        DB      'N','no END at the end',0
        DB      'X','the line is too long (255)',0
        DB      0,'?',0
; PSTR: RF -> 0-ended text, out
PSTR:   LDA     RF
        LBZ     PST9
        SEP     R4
        DW      K_OUT
        LBR     PSTR
PST9:   SEP     R5

; ==== the .PRG, a sector at a time (XFER's writer)
; WSETUP: its directory entry: the old one to switch (and its clusters to free after), or a new slot
WSETUP: LOAD    RF, OUTT
        LOAD    RD, ON11
        SEP     R4
        DW      K_PARSE
        LBDF    BADOUT
        LOAD    RD, ON11
        SEP     R4
        DW      KS_FINDN
        LBDF    WS2
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    BADOUT
        LOAD    RD, ESEC        ; the entry to rewrite: its sector, where in DIRBUF; its clusters
        LOAD    RC, KS_DSEC
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        INC     RD
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, OLDCL
        LOAD    RC, KS_DCLUS
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        LOAD    RD, REPL
        LDI     1
        STR     RD
        LBR     WS3
WS2:    SEP     R4              ; a new file: a free entry (a folder may grow by a cluster for it)
        DW      KS_DSLOT
        LBNF    WS2A
        SEP     R4
        DW      K_PIN
        DB      'ASM: the directory is full.',0DH,0AH,0
        LBR     FAILST
WS2A:   LOAD    RD, ESEC
        LOAD    RC, KS_WDSEC    ; WDSEC, WDPTR
        LDI     4
        PLO     RB
WS2B:   LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    WS2B
WS3:    LOAD    RD, OUTN        ; the sector empty
        LDI     HIGH(OUTB)
        STR     RD
        INC     RD
        LDI     LOW(OUTB)
        STR     RD
        SEP     R5
; WRBLK: OUTB's 512 bytes as the file's next sector (a new cluster when this one is full). DF = 1: failed
WRBLK:  LOAD    RD, WSLEFT
        LDN     RD
        LBNZ    WB4
        SEP     R4              ; a cluster for the next part
        DW      KS_FREECL
        LBDF    WBERR
        LOAD    RD, NEWC
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    R9, 0FFFFH      ; it ends the chain ...
        SEP     R4
        DW      KS_FATPUT
        LBDF    WBERR
        LOAD    RD, WPREV       ; ... and the last one points at it (or it is the first)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, NEWC
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        GHI     RC
        LBNZ    WB2
        GLO     RC
        LBNZ    WB2
        LOAD    RD, WFIRST
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LBR     WB3
WB2:    SEP     R4
        DW      KS_FATPUT
        LBDF    WBERR
WB3:    LOAD    RD, NEWC        ; WPREV = it; WLBA = its first sector, WSLEFT = its sectors
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, WPREV
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      KS_CL2LBA
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_ST32
        LOAD    RD, KS_SPC
        LDN     RD
        PLO     RB
        LOAD    RD, WSLEFT
        GLO     RB
        STR     RD
WB4:    LOAD    RD, WLBA        ; the sector
        SEP     R4
        DW      KS_LD32
        LOAD    RF, OUTB
        SEP     R4
        DW      KS_IDEWR
        LBDF    WBERR
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_LD32
        LOAD    RC, 1
        SEP     R4
        DW      KS_ADD16
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_ST32
        LOAD    RD, WSLEFT
        LDN     RD
        SMI     1
        STR     RD
        LDI     0
        SHR
        SEP     R5
WBERR:  LDI     1
        SHR
        SEP     R5
; WFULL: the card full or failing: the clusters given back, back to the prompt
WFULL:  SEP     R4
        DW      WFREE
        SEP     R4
        DW      K_PIN
        DB      0DH,0AH,'ASM: the card is full (or did not answer) - nothing saved.',0DH,0AH,0
        LBR     FAILST
; WFREE: the clusters taken given back
WFREE:  LOAD    RD, WFIRST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    WF1
        GLO     RC
        LBZ     WF9
WF1:    SEP     R4
        DW      KS_FREECH
        SEP     R4
        DW      KS_FATFLUSH
WF9:    SEP     R5
; WFIN: the last sector, the FAT, the entry (the switch), the old file's clusters; "Saved ..."
WFIN:   LOAD    RD, LO          ; the size: HI - LO (nothing: said)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, HI + 1
        GLO     RC
        STR     R2
        LDN     RD
        SM
        PLO     RC
        DEC     RD
        GHI     RC
        STR     R2
        LDN     RD
        SMB
        PHI     RC
        LBNF    WFNONE
        LOAD    RD, SIZE
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        GHI     RC
        LBNZ    WFI1
        GLO     RC
        LBZ     WFNONE
WFI1:   LOAD    RD, OUTN        ; the last part of a sector: 0s after it, out
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     RF
        LBNZ    WFI2
        GHI     RF
        XRI     HIGH(OUTB)
        LBZ     WFI3
WFI2:   LDI     0
        STR     RF
        INC     RF
        GHI     RF
        XRI     HIGH(OUTB + 512)
        LBNZ    WFI2
        SEP     R4
        DW      WRBLK
        LBDF    WFULL
WFI3:   SEP     R4
        DW      KS_FATFLUSH
        LBDF    WFULL
        LOAD    RF, OUTT        ; WDIR = the .PRG's folder again (an INCL moved it; DIRRD counts from it)
        LOAD    RD, ON11
        SEP     R4
        DW      K_PARSE
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRRD
        LBDF    WFULL
        SEP     R4
        DW      KS_STAMP
        LOAD    RD, EPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, ON11        ; 0-10 the name
        LDI     11
        PLO     RB
WF3:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    WF3
        LDI     20H             ; 11 archive; 12, 13
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 14-17 created
        DW      KS_PUTST
        LOAD    RD, KS_STD      ; 18-19 used
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LDI     0               ; 20-21
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 22-25 written
        DW      KS_PUTST
        LOAD    RD, WFIRST      ; 26-27 the first cluster, 28-31 the size (little-endian)
        LDA     RD
        PHI     RC
        LDN     RD
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        LOAD    RD, SIZE + 1
        LDN     RD
        STR     RF
        INC     RF
        DEC     RD
        LDN     RD
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    WFULL
        LOAD    RD, REPL        ; the old file's clusters
        LDN     RD
        LBZ     WF4
        LOAD    RD, OLDCL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_FREECH
        SEP     R4
        DW      KS_FATFLUSH
WF4:    SEP     R4
        DW      K_PIN
        DB      'Saved ',0
        LOAD    RF, OUTT
        SEP     R4
        DW      PSTR
        SEP     R4
        DW      K_PIN
        DB      ': ',0
        LOAD    RD, SIZE
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' bytes, $',0
        LOAD    RD, LO
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      K_PHEX4
        SEP     R4
        DW      K_PIN
        DB      '-$',0
        LOAD    RD, HI
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        DEC     RD
        SEP     R4
        DW      K_PHEX4
        SEP     R4
        DW      K_PIN
        DB      '.',0DH,0AH,0
        SEP     R5
WFNONE: SEP     R4
        DW      K_PIN
        DB      'ASM: no code - nothing saved.',0DH,0AH,0
        SEP     R5

SASM:   DB      '.ASM',0
SPRG:   DB      '.PRG',0
        INCL    "asmops.inc"
PEND:
VARS:
JMPV:   DS      3
LFLAG:  DS      1
SRCT:   DS      64
OUTT:   DS      64
ON11:   DS      11
FN11:   DS      11
PASS:   DS      1
PC:     DS      2
LO:     DS      2
HI:     DS      2
OUTPC:  DS      2
OUTN:   DS      2
SIZE:   DS      2
ERRS:   DS      2
NSYM:   DS      2
ERRC:   DS      1
NBYTES: DS      1
HASLBL: DS      1
SKIPL:  DS      1
LONGF:  DS      1
GOTC:   DS      1
RLKEEP: DS      2
LSHOW:  DS      2
LCNT:   DS      1
INCLN:  DS      1
DONE:   DS      1
OFF:    DS      1
IFSP:   DS      1
LEVEL:  DS      1
LP:     DS      2
OPK:    DS      1
OPC:    DS      1
LDREG:  DS      1
FILLV:  DS      1
SETF:   DS      1
LBLH:   DS      4
HV:     DS      4
KEY:    DS      4
TOLD:   DS      1
TTYPE:  DS      1
TV:     DS      2
TATTR:  DS      1
SLEN:   DS      1
NBASE:  DS      1
NLEN:   DS      1
XBAD:   DS      1
FORWD:  DS      1
RV:     DS      2
ESP:    DS      1
CUR:    DS      FRSZ
INCS:   DS      FRSZ * 3
ESEC:   DS      2
EPTR:   DS      2
OLDCL:  DS      2
REPL:   DS      1
WFIRST: DS      2
WPREV:  DS      2
NEWC:   DS      2
WLBA:   DS      4
WSLEFT: DS      1
VEND:
        END
