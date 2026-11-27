; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lcjobs.inc - the parts of LC's jobs that change the card, shared by LC.OVL's parts 1 and 3 (each has its own
;   copy, assembled where that part is): the kernel trap, prompts and messages, the tagged entries, the panes
;   read again after a job, and their variables.

; ==== the jobs that change the card: Rename, MkDir, Move, Delete. While one runs the kernel's script hook is
;   TRAP's (TRAPON): if the kernel gives up - a folder or the card full, the card failing - it says why on row 22
;   (the cursor is put there first) and goes to MAIN, and MAIN comes here instead of the LTOS> prompt.
TRAPON: LOAD    RF, K_SHHOOK
        LOAD    RD, SHSV
        LOAD    RC, 3
        SEP     R4
        DW      MCOPY
        LOAD    RD, K_SHHOOK
        LDI     0C0H
        STR     RD
        INC     RD
        LDI     HIGH(TRAP)
        STR     RD
        INC     RD
        LDI     LOW(TRAP)
        STR     RD
        SEP     R4
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',' ',0
        SEP     R5
TRAPOFF: LOAD   RF, SHSV
        LOAD    RD, K_SHHOOK
        LOAD    RC, 3
        LBR     MCOPY
TRAP:   SEP     R4              ; (from MAIN: R2 the kernel's fresh stack) - the kernel's word stays on row 22
        DW      TRAPOFF
        LOAD    RD, MSGF
        LDI     1
        STR     RD
        LOAD    RD, OTHRL
        LDI     1
        STR     RD
        LOAD    RD, FINDNM
        LDI     0
        STR     RD
        SEP     R4
        DW      REFRESH
        LBR     LOOP

; ---- the jobs' parts
; JDONE: after a job: the panes read again (REFRESH), then the text after the call (if any) on row 22, kept until
;   the next key; RA at its end (LBUF), for more (then JSAY)
JDONE:  LOAD    RD, MSGF
        LDI     1
        STR     RD
        SEP     R4
        DW      REFRESH
        LOAD    RA, LBUF
        LDI     ' '
        STR     RA
        INC     RA
JD1:    LDA     R6
        LBZ     JD2
        STR     RA
        INC     RA
        LBR     JD1
JD2:    GLO     RA              ; (no text: the caller says more first, then JSAY)
        XRI     LOW(LBUF + 1)
        LBZ     RET0
JSAY:   GLO     RA              ; (at most 79)
        SMI     79
        LBNF    JS1
        LDI     79
        PLO     RA
JS1:    LDI     0
        STR     RA
        SEP     R4
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',0
        LOAD    RF, LBUF
        LBR     PUTS
JBADN:  SEP     R4
        DW      MSGI
        DB      'Not a name: 1-8 letters or digits, then . and up to 3 more.',0
        SEP     R5
JTHERE: SEP     R4
        DW      TRAPOFF
        SEP     R4
        DW      MSGI
        DB      'There is one by that name in this folder already.',0
        SEP     R5
JGONE:  SEP     R4
        DW      TRAPOFF
        LOAD    RD, OTHRL
        LDI     1
        STR     RD
        SEP     R4
        DW      JDONE
        DB      'It is not there now: both panes read again.',0
        SEP     R5
JFAILX: XRI     1               ; (Delete's: MOVE1's code again, as JFAIL has it)
        SMI     3
        LBNF    JGONE
JFAIL:  ADI     3               ; MOVE1's 3 not found, 4 the folder full, 5 the card failed
        XRI     4
        LBNZ    JGONE2
        SEP     R4
        DW      TRAPOFF
        LOAD    RD, OTHRL
        LDI     1
        STR     RD
        SEP     R4
        DW      JDONE
        DB      'Stopped: that folder is full.',0
        SEP     R5
JGONE2: XRI     4 XOR 5
        LBNZ    JGONE
        LBR     KS_CARDF
JNO:    SEP     R4              ; (No: as it was)
        DW      UNSEL
        LBR     INFO
; JASK: row 22: the text after the call, then the one entry's NAME.EXT or how many; RA at the end of it in LBUF
JASK:   LOAD    RA, LBUF
JA1:    LDA     R6
        LBZ     JA2
        STR     RA
        INC     RA
        LBR     JA1
JA2:    LOAD    RD, JNS
        LDN     RD
        XRI     1
        LBZ     JA3
        LDN     RD
        LBR     U8STR
JA3:    LOAD    RD, JI          ; the one: found from the start
        LDI     0
        STR     RD
        SEP     R4
        DW      NEXTSEL
        LOAD    RC, SNM1
        LBR     NAMEFMT
; ASKYN: the text at RF after LBUF's, on row 22, then a key: DF = 1 if Y
ASKYN:  SEP     R4
        DW      CPYS
        LDI     0
        STR     RA
        SEP     R4
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',0
        LOAD    RF, LBUF
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      KEY
        ANI     0DFH
        XRI     'Y'
        LBZ     GRYES
        LBR     GRNO
; OTHPATH: the other pane's path at RA
OTHPATH: LOAD   RD, ACT
        LDN     RD
        XRI     1
        SEP     R4
        DW      SETCP
        LDI     P_PATH
        SEP     R4
        DW      PFLD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        SEP     R4
        DW      CPYS
        LBR     ACTCP
; SDDIRS: SDIR = this pane's folder, DDIR = the other's
SDDIRS: LDI     P_CLUS
        SEP     R4
        DW      PFLD
        LOAD    RC, SDIR
        SEP     R4
        DW      CP2
        LOAD    RD, ACT
        LDN     RD
        XRI     1
        SEP     R4
        DW      SETCP
        LDI     P_CLUS
        SEP     R4
        DW      PFLD
        LOAD    RC, DDIR
        SEP     R4
        DW      CP2
        LBR     ACTCP
; SETWD: KS_WDIR = this pane's folder
SETWD:  LDI     P_CLUS
        SEP     R4
        DW      PFLD
        LOAD    RC, KS_WDIR
        LBR     CP2
; CURREC: RF -> the record under the cursor; DF = 1: none, or ".."
CURREC: LDI     P_N
        SEP     R4
        DW      GETF
        LBZ     GRYES
        LDI     P_CUR
        SEP     R4
        DW      GETF
        PLO     R7
        LDI     P_UP
        SEP     R4
        DW      GETF
        LBZ     CU1
        GLO     R7
        LBZ     GRYES
CU1:    GLO     R7
        SEP     R4
        DW      ENTP
        LBR     GRNO
; SELECT: JNS = the tagged entries; none: the one under the cursor tagged (SELTMP = 1). DF = 1: nothing at all.
SELECT: LOAD    RD, SELTMP
        LDI     0
        STR     RD
        LOAD    RD, JI
        LDI     0
        STR     RD
        LOAD    RD, JNS
        LDI     0
        STR     RD
SE1:    SEP     R4
        DW      NEXTSEL
        LBDF    SE2
        LOAD    RD, JNS
        LDN     RD
        ADI     1
        STR     RD
        LBR     SE1
SE2:    LOAD    RD, JI          ; (from the start again for the job)
        LDI     0
        STR     RD
        LOAD    RD, JNS
        LDN     RD
        LBNZ    GRNO
        SEP     R4
        DW      CURREC
        LBDF    RET0
        GLO     RF
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDN     RF
        ORI     80H
        STR     RF
        LOAD    RD, SELTMP
        LDI     1
        STR     RD
        LOAD    RD, JNS
        LDI     1
        STR     RD
        LBR     GRNO
; UNSEL: the tag SELECT put on (if it did) taken off
UNSEL:  LOAD    RD, SELTMP
        LDN     RD
        LBZ     RET0
        SEP     R4
        DW      CURREC
        LBDF    RET0
        GLO     RF
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDN     RF
        ANI     7FH
        STR     RF
        SEP     R5
; NEXTSEL: the next tagged entry from JI on, as the pane shows them (not ".."): SNM1 = DNM = its name, JATTR its attribute; DF = 1: no more
NEXTSEL: LDI    P_N
        SEP     R4
        DW      GETF
        STR     R2
        LOAD    RD, JI
        LDN     RD
        SD                      ; N - JI
        LBZ     GRYES
        LBNF    GRYES
        LDN     RD
        PLO     R7
        ADI     1
        STR     RD
        GLO     R7              ; (in the order the pane shows them: the index)
        SEP     R4
        DW      ENTP
        GLO     RF
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        ANI     80H
        LBZ     NEXTSEL
        LDN     RD
        PLO     R7
        LOAD    RD, JATTR
        GLO     R7
        STR     RD
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        LOAD    RC, SNM1
        SEP     R4
        DW      CP11
        LOAD    RD, SNM1
        LOAD    RC, DNM
        SEP     R4
        DW      CP11
        LBR     GRNO
; JZERO: JN1 JN2 JN3 = 0, JI = 0
JZERO:  LOAD    RD, JN1
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, JI
        LDI     0
        STR     RD
        SEP     R5
; PATHNM: VPATHB = this pane's path, a /, the 11-byte name at RC as NAME.EXT
PATHNM: GHI     RC
        STXD
        GLO     RC
        STXD
        LDI     P_PATH
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
        LBZ     PH1
        LDI     '/'
        STR     RA
        INC     RA
PH1:    IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        SEP     R4
        DW      NAMEFMT
        LDI     0
        STR     RA
        SEP     R5
; OTHFIX: the other pane in the folder VPATHB (or one inside it) - which moved, was renamed or went: it goes to
;   this pane's folder (OTHRL: read again)
OTHFIX: LOAD    RD, ACT
        LDN     RD
        XRI     1
        SEP     R4
        DW      SETCP
        LDI     P_PATH
        SEP     R4
        DW      PFLD
        LOAD    RF, VPATHB
OF1:    LDA     RF
        LBZ     OF2
        STR     R2
        LDA     RD
        XOR
        LBNZ    OFX
        LBR     OF1
OF2:    LDN     RD
        LBZ     OF3
        XRI     '/'
        LBNZ    OFX
OF3:    LDI     P_CLUS          ; this pane's folder and path copied over the other's
        SEP     R4
        DW      PFLD
        GHI     RD
        PHI     RC
        GLO     RD
        PLO     RC              ; RC -> the other's P_CLUS
        SEP     R4
        DW      ACTCP
        LDI     P_CLUS
        SEP     R4
        DW      PFLD
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LDI     P_PATH
        SEP     R4
        DW      PFLD
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        GLO     RC
        ADI     P_PATH - 1
        PLO     RD
        GHI     RC
        ADCI    0
        PHI     RD
        LOAD    RC, PATHL
        SEP     R4
        DW      MCOPY
        LOAD    RD, OTHRL
        LDI     1
        STR     RD
OFX:    LBR     ACTCP
; SAME2: DF = 1 if the 2 bytes at RD are those at RC (RD RC kept)
SAME2:  LDA     RD
        STR     R2
        LDA     RC
        XOR
        DEC     RD
        DEC     RC
        LBNZ    GRNO
        INC     RD
        INC     RC
        LDN     RD
        STR     R2
        LDN     RC
        XOR
        DEC     RD
        DEC     RC
        LBNZ    GRNO
        LBR     GRYES
; REFRESH: after a job: this pane read again, the cursor on NBUF's name (FINDNM) or where it was (or the last);
;   the other pane read again if OTHRL or it shows the same folder; both drawn; the file's line (unless MSGF)
REFRESH: SEP    R4
        DW      ACTCP
        LDI     P_CLUS          ; the same folder in both: both read again
        SEP     R4
        DW      PFLD
        GHI     RD
        PHI     RC
        GLO     RD
        PLO     RC
        LOAD    RD, ACT
        LDN     RD
        XRI     1
        SEP     R4
        DW      SETCP
        LDI     P_CLUS
        SEP     R4
        DW      PFLD
        SEP     R4
        DW      SAME2
        LBNF    RF1
        LOAD    RD, OTHRL
        LDI     1
        STR     RD
RF1:    SEP     R4
        DW      ACTCP
        LDI     P_CUR
        SEP     R4
        DW      GETF
        PLO     R7
        LOAD    RD, OLDCUR
        GLO     R7
        STR     RD
        SEP     R4
        DW      LOADP
        LOAD    RD, FINDNM
        LDN     RD
        LBZ     RF4
        LDI     0
        STR     RD
        LOAD    RD, OLDCUR      ; the cursor on NBUF's name: its entry looked for
        LDI     0
        STR     RD
RF2:    LDI     P_N
        SEP     R4
        DW      GETF
        STR     R2
        LOAD    RD, OLDCUR
        LDN     RD
        SD
        LBZ     RF4
        LBNF    RF4
        LDN     RD
        SEP     R4
        DW      ENTP
        LOAD    RD, NBUF
        LDI     11
        PLO     RB
RF3:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBNZ    RF3N
        DEC     RB
        GLO     RB
        LBNZ    RF3
        LBR     RF5
RF3N:   LOAD    RD, OLDCUR
        LDN     RD
        ADI     1
        STR     RD
        LBR     RF2
RF4:    LDI     P_N             ; where it was, or the last
        SEP     R4
        DW      GETF
        LBZ     RF7
        SMI     1
        PLO     R7
        STR     R2
        LOAD    RD, OLDCUR
        LDN     RD
        SD                      ; last - OLDCUR
        LBDF    RF5
        GLO     R7
        STR     RD
RF5:    LOAD    RD, OLDCUR
        LDN     RD
        PLO     R7
        LDI     P_CUR
        SEP     R4
        DW      PFLD
        GLO     R7
        STR     RD
        GLO     R7
        SMI     ROWS
        LBNF    RF7
        GLO     R7
        SMI     ROWS / 2
        PLO     R7
        LDI     P_TOP
        SEP     R4
        DW      PFLD
        GLO     R7
        STR     RD
RF7:    SEP     R4
        DW      PANEDRAW
        LOAD    RD, OTHRL       ; the other pane
        LDN     RD
        LBZ     RF8
        LDI     0
        STR     RD
        LOAD    RD, ACT
        LDN     RD
        XRI     1
        SEP     R4
        DW      SETCP
        SEP     R4
        DW      LOADP
        SEP     R4
        DW      PANEDRAW
RF8:    SEP     R4
        DW      ACTCP
        LOAD    RD, MSGF
        LDN     RD
        LBNZ    RET0
        LBR     INFO
CP2:    LDA     RD              ; RD's 2 bytes to RC, RD's 11 to RC (as wild.inc's)
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R5
CP11:   LDI     11
        PLO     RB
C11:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    C11
        SEP     R5

STO:    DB      ' to ',0
SQYN:   DB      '? (Y/N) ',0
SDIR:   DS      2               ; MOVE1's (move1.inc): from, to, the name, the new name, the entry, its cluster
DDIR:   DS      2
SNM1:   DS      11
DNM:    DS      11
ENT:    DS      32
MCL:    DS      2
NBUF:   DS      11              ; a name typed, as the card has it
SHSV:   DS      3               ; the kernel's script hook, kept while a job runs
OTHRL:  DS      1               ; 1: the other pane read again after the job
FINDNM: DS      1               ; 1: the cursor on NBUF's name after it
OLDCUR: DS      1
JI:     DS      1               ; NEXTSEL: the next record to look at
JN1:    DS      1               ; JN1 JN2 JN3: in this order (JZERO)
JN2:    DS      1
JN3:    DS      1
JNS:    DS      1               ; the entries to work on
SELTMP: DS      1               ; 1: SELECT tagged the cursor's entry itself
JATTR:  DS      1
