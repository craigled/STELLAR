; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lcov4.asm - LC.OVL's part 4 (LC4.OVL): Run, and the way back. Loaded by LC.PRG (OVLD) into OVLA when wanted;
;   it uses LC.PRG's routines and variables by their names (out/lcsyms.inc, written by build.py).
;
; Run (9 / F9, or Enter on a file of these kinds), in the pane's folder (CWD set to it first):
;   .PRG  NAME.PRG          .SH  SH NAME          .MUS  PLAY -s 3 NAME (the Elf2K's 3 MHz)
;   .SC   SC NAME           .STL STELLAR NAME
; LC keeps where it was (both panes, which is active) in /_LC.DAT (hidden). Then:
;   a STELLAR app: it ends by loading LTOS again, so LC leaves its mark (LCMARK: 'L','C', "LC -r") - the
;     kernel's WARM runs LC -r once LTOS is up.
;   the others: /_LC.SH (hidden) - the command, then LC -k - run by SH (as MAKE does): LC -k waits for a key
;     (the program's output stays to be read), then LC as it was.
; LC -r / -k (LC.PRG's START, ORESTORE): /_LC.DAT read back, both folders read again, the cursors where they were.
; Edit (E): the same way, with EDITT's kinds (.SC .TXT .SH .RF .LOG .TAB): /_LC.SH = NANO NAME.EXT, then LC -e -
;   LC as it was, no key (NANO's screen is nothing to read) (Craig, 2026-11-24).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
        INCL    "lc.inc"
        INCL    "out/lcsyms.inc"
STSZ    EQU     2 * PSZ + 1     ; PANE0, PANE1, ACT: one after the other

        ORG     OVLA
        DW      PEND            ; (this LC.PRG's: LC.PRG checks it)
        DB      4
        LBR     ORUN
        LBR     ORESTORE
        LBR     OEDIT

; ---- ORUN: D = 1 from Enter (DF = 1 back: not a kind LC runs - View it), 0 from 9 (not one: said)
ORUN:   PLO     R7              ; (R7.1: 0 Run, 1 Edit -> REDIT)
        LDI     0
        LBR     ORUN0
OEDIT:  LDI     0               ; E: Edit (not a kind it edits: said)
        PLO     R7
        LDI     1
ORUN0:  PHI     R7
        LOAD    RD, REDIT
        GHI     R7
        STR     RD
        LOAD    RD, RENT
        GLO     R7
        STR     RD
        LDI     P_N             ; the entry under the cursor (not "..", not a folder)
        SEP     R4
        DW      GETF
        LBZ     RUNNO
        LDI     P_CUR
        SEP     R4
        DW      GETF
        PLO     R7
        LDI     P_UP
        SEP     R4
        DW      GETF
        LBZ     RU1
        GLO     R7
        LBZ     RUNNO
RU1:    GLO     R7
        SEP     R4
        DW      ENTP
        LOAD    RD, RECP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        GLO     RF              ; its extension: which kind
        ADI     8
        PLO     RC
        GHI     RF
        ADCI    0
        PHI     RC
        LOAD    RD, REDIT
        LDN     RD
        LBZ     RU1K
        LOAD    RD, EDITT
        LBR     RU2
RU1K:   LOAD    RD, KINDT       ; ext (3), the command's start (0-ended) ... 0
RU2:    LDN     RD
        LBZ     RUNNO
        SEP     R4
        DW      CMP3R
        LBDF    RU3
RU2A:   LDA     RD              ; (on past this one's text)
        LBNZ    RU2A
        INC     RD              ; (and its kind byte)
        LBR     RU2
RU3:    INC     RD              ; LBUF = the command: its start, the name (NAME, or NAME.PRG)
        INC     RD
        INC     RD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        LOAD    RA, LBUF
        SEP     R4
        DW      CPYS
        LDN     RF              ; (CPYS leaves RF past the 0: the kind byte - 1 .PRG, 2 a STELLAR app, 0 others)
        PLO     R7
        LOAD    RD, RKIND
        GLO     R7
        STR     RD
        LOAD    RD, RECP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDI     8
        PLO     RB
RU4:    LDA     RC
        XRI     ' '
        LBZ     RU5
        XRI     ' '
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    RU4
RU5:    LOAD    RD, RKIND
        LDN     RD
        XRI     1
        LBNZ    RU5E
        LOAD    RF, SDPRG
        SEP     R4
        DW      CPYS
        LBR     RU6
RU5E:   XRI     1 XOR 3         ; 3 (Edit): NAME.EXT
        LBNZ    RU6
        LDI     '.'
        STR     RA
        INC     RA
        LOAD    RD, RECP
        LDA     RD
        PHI     RC
        LDN     RD
        ADI     8
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LDI     3
        PLO     RB
RU5F:   LDA     RC
        XRI     ' '
        LBZ     RU6
        XRI     ' '
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    RU5F
RU6:    LDI     0
        STR     RA
        SEP     R4              ; where LC is: /_LC.DAT
        DW      SAVEST
        LBDF    RUNERR
        LDI     P_CLUS          ; CWD = this pane's folder
        SEP     R4
        DW      PFLD
        LOAD    RF, KS_CWD
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, RKIND
        LDN     RD
        XRI     2
        LBNZ    RU8
        LOAD    RF, SMARK       ; a STELLAR app: the mark, then the command
        LOAD    RD, LCMARK
        LDI     8
        PLO     RB
RU7:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    RU7
        LOAD    RF, LBUF
        LBR     RUGO
RU8:    LOAD    RA, LBUF        ; the others: /_LC.SH = the command, then LC -k
RU8A:   LDA     RA
        LBNZ    RU8A
        DEC     RA
        LOAD    RF, SKLINE
        LOAD    RD, REDIT
        LDN     RD
        LBZ     RU8B
        LOAD    RF, SELINE      ; Edit: LC -e (no key)
RU8B:   SEP     R4
        DW      CPYS
        GLO     RA              ; (its length: RC)
        SMI     LOW(LBUF)
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    RF, SSHN
        LOAD    RA, LBUF
        SEP     R4
        DW      SAVEH
        LBDF    RUNERR
        LOAD    RD, RESMODE     ; LC was started by /_LC.SH itself (LC -k, its last line): that script ends
        LDN     RD              ;  here - not one more inside it each time (LC -e too)
        XRI     'K'
        LBZ     RU8K
        XRI     'K' XOR 'E'
        LBNZ    RU9
RU8K:        LOAD    RD, K_SHHOOK
        LDI     0
        STR     RD
RU9:    LOAD    RF, SSHRUN
RUGO:   LOAD    RD, KS_LINE     ; LINE = the command; the screen cleared, the cursor shown; run
RUG1:   LDA     RF
        STR     RD
        INC     RD
        LBNZ    RUG1
        SEP     R4
        DW      INL
        DB      ESC,'[0m',ESC,'[2J',ESC,'[1;1H',ESC,'[?25h',0
        LBR     K_EXEC
RUNNO:  LOAD    RD, RENT        ; not a kind LC runs: Enter - View it; 9 - said
        LDN     RD
        LBNZ    GRYES
        LOAD    RD, REDIT
        LDN     RD
        LBZ     RUNN9
        SEP     R4
        DW      MSGI
        DB      'Edit (NANO): .SC .TXT .SH .RF .LOG .TAB - a file (not a folder)',0
        LBR     GRNO
RUNN9:  SEP     R4
        DW      MSGI
        DB      'Run: .PRG .SH .STL .MUS .SC (a .BIN: 1802 NAME at LTOS> - it does not come back)',0
        LBR     GRNO
RUNERR: SEP     R4
        DW      MSGI
        DB      'Run: /_LC.DAT or /_LC.SH could not be written (the card full?).',0
        LBR     GRNO
; SAVEST: PANE0 PANE1 ACT -> /_LC.DAT (hidden). DF = 1: not saved
SAVEST: LOAD    RF, SDATN
        LOAD    RA, PANE0
        LOAD    RC, STSZ
; SAVEH: RC bytes at RA -> the file named at RF (a path), replacing it, then hidden. DF = 1: not saved
;   (K_PARSE uses RC: RA, RC and RF kept on the stack meanwhile)
SAVEH:  GHI     RF
        STXD
        GLO     RF
        STXD
        GHI     RA
        STXD
        GLO     RA
        STXD
        GHI     RC
        STXD
        GLO     RC
        STXD
        LOAD    RD, N11
        SEP     R4
        DW      K_PARSE
        IRX                     ; RC, RA back (RF stays on the stack)
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDXA
        PLO     RA
        LDX
        PHI     RA
        LBDF    SH9
        LOAD    RD, N11
        SEP     R4
        DW      K_SAVER
        LBDF    SH9
        IRX                     ; found again, its hidden bit set (DIR -h shows it)
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LOAD    RD, N11
        SEP     R4
        DW      K_PARSE
        LBDF    GRYES
        LOAD    RD, N11
        SEP     R4
        DW      KS_FINDN
        LBDF    GRYES
        GLO     RF
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDN     RF
        ORI     02H
        STR     RF
        LOAD    RD, KS_DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        SEP     R5              ; (DF as DIRWR left it)
SH9:    IRX                     ; (RF off the stack)
        IRX
        LBR     GRYES
; CMP3R: DF = 1 if the 3 bytes at RC are those at RD (RC RD kept)
CMP3R:  LDN     RC
        STR     R2
        LDN     RD
        XOR
        LBNZ    GRNO
        INC     RC
        INC     RD
        LDN     RC
        STR     R2
        LDN     RD
        XOR
        LBNZ    C3X1
        INC     RC
        INC     RD
        LDN     RC
        STR     R2
        LDN     RD
        XOR
        DEC     RC
        DEC     RD
C3X1:   DEC     RC
        DEC     RD
        LBNZ    GRNO
        LBR     GRYES

; ---- ORESTORE (LC -r / LC -k): DF = 0 - LC as it was (both panes read again); DF = 1: nothing kept (a fresh start)
ORESTORE: LOAD  RD, LCMARK      ; the mark: never used twice
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, RESMODE     ; LC -k: a key first - the program's output stays to be read
        LDN     RD
        XRI     'K'
        LBNZ    RSA1
        LOAD    RD, CLKOFF
        LDI     1
        STR     RD
        SEP     R4
        DW      INL
        DB      0DH,0AH,' LC: a key goes back to it ',0
        SEP     R4
        DW      KEY
        LOAD    RD, CLKOFF
        LDI     0
        STR     RD
RSA1:    LOAD    RF, SDATN       ; /_LC.DAT: found, the size it should be
        LOAD    RD, N11
        SEP     R4
        DW      K_PARSE
        LBDF    GRYES
        LOAD    RD, N11
        SEP     R4
        DW      KS_FINDN
        LBDF    GRYES
        LOAD    RD, KS_DSIZE + 2
        LDA     RD
        XRI     HIGH(STSZ)
        LBNZ    GRYES
        LDN     RD
        XRI     LOW(STSZ)
        LBNZ    GRYES
        SEP     R4
        DW      KS_FOPEN
        SEP     R4
        DW      KS_FREAD
        LBDF    GRYES
        LOAD    RF, KS_DATBUF   ; kept apart first (the fixed fields - pages, columns - are this LC's)
        LOAD    RD, LBUF
        LOAD    RC, STSZ
        SEP     R4
        DW      MCOPY
        LDI     0               ; each pane: its folder and path, then read; its cursor and top again
        SEP     R4
        DW      RSPANE
        LDI     1
        SEP     R4
        DW      RSPANE
        LOAD    RD, LBUF + 2 * PSZ
        LDN     RD
        ANI     1
        PLO     R7
        LOAD    RD, ACT
        GLO     R7
        STR     RD
        LBR     GRNO
; RSPANE: pane D from LBUF's copy: P_CLUS and P_PATH, read (LOADP), then P_CUR and P_TOP (kept inside the folder)
RSPANE: STXD
        SEP     R4
        DW      SETCP
        IRX
        LDX
        LBZ     RP1
        LOAD    RF, LBUF + PSZ
        LBR     RP2
RP1:    LOAD    RF, LBUF
RP2:    GHI     RF              ; RA -> the copy
        PHI     RA
        GLO     RF
        PLO     RA
        LDI     P_CLUS
        SEP     R4
        DW      PFLD
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        GLO     RA              ; the path
        ADI     P_PATH
        PLO     RF
        GHI     RA
        ADCI    0
        PHI     RF
        LDI     P_PATH
        SEP     R4
        DW      PFLD
        LOAD    RC, PATHL
        SEP     R4
        DW      MCOPY
        GLO     RA              ; (its cursor and top: kept on the stack while it is read)
        ADI     P_CUR
        PLO     RF
        GHI     RA
        ADCI    0
        PHI     RF
        LDN     RF
        STXD
        DEC     RF
        LDN     RF
        STXD
        SEP     R4
        DW      LOADP
        IRX
        LDXA
        PLO     R8              ; R8.0 = top
        LDX
        PLO     R7              ; R7.0 = cursor
        LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     RET0
        STR     R2              ; the cursor: at most the last
        GLO     R7
        SM
        LBNF    RP3
        LDN     R2
        SMI     1
        PLO     R7
RP3:    GLO     R7              ; the top: at most the cursor, and the cursor on the screen
        STR     R2
        GLO     R8
        SD                      ; cursor - top
        LBNF    RP4
        SMI     ROWS
        LBNF    RP5
RP4:    GLO     R7
        SMI     ROWS / 2
        LBDF    RP4A
        LDI     0
RP4A:   PLO     R8
RP5:    LDI     P_CUR
        SEP     R4
        DW      PFLD
        GLO     R7
        STR     RD
        LDI     P_TOP
        SEP     R4
        DW      PFLD
        GLO     R8
        STR     RD
        SEP     R5

KINDT:  DB      'PRG',0,1               ; ext, the command's start, 0, its kind (1 .PRG, 2 STELLAR, 0 others)
        DB      'SH ','SH ',0,0
        DB      'STL','STELLAR ',0,2
        DB      'MUS','PLAY -s 3 ',0,0
        DB      'SC ','SC ',0,0
        DB      0
EDITT:  DB      'SC ','NANO ',0,3       ; Edit's kinds: NANO NAME.EXT (kind 3)
        DB      'TXT','NANO ',0,3
        DB      'SH ','NANO ',0,3
        DB      'RF ','NANO ',0,3
        DB      'LOG','NANO ',0,3
        DB      'TAB','NANO ',0,3
        DB      0
SDPRG:  DB      '.PRG',0
SMARK:  DB      'LC','LC -r',0
SKLINE: DB      0DH,0AH,'LC -k',0DH,0AH,0
SELINE: DB      0DH,0AH,'LC -e',0DH,0AH,0
SSHN:   DB      '/_LC.SH',0
SSHRUN: DB      'SH /_LC',0
SDATN:  DB      '/_LC.DAT',0
RENT:   DS      1               ; 1: from Enter
RKIND:  DS      1
REDIT:  DS      1               ; 1: Edit (E), 0: Run
N11:    DS      11
OVEND:
        END
