; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; sh.asm - SH.PRG: SH [-x] NAME [words] - runs the script NAME.SH (here, else the root, else /BIN), a line at a
; time. Typing NAME alone does the same (STELLAR.PRG: no NAME.PRG, no NAME.STL, but a NAME.SH).
;
; Phase 2: # comments, ; between commands, '...' and "..." quotes, NAME=value, $NAME ${NAME} $0-$9 $# $?,
; if / then / elif / else / fi (nested 8 deep), and the built-ins echo [-n], exit [n], test / [ ], true, false,
; :, set (the variables; -x / +x), unset, read [-p prompt] NAME.
; Phase 3: while / until / for NAME [in words - wildcards too]; do ... done (6 deep), break, continue, && ||,
; ! cmd, $((arithmetic)) (16-bit), ${NAME:-default} ${NAME:=default}, shift [n], sleep n, pause, set -e / +e.
; Anything else is an outside command: the line, its $ replaced, goes to
; the kernel (K_EXEC) exactly as if typed - "> file" and all - and when it ends the kernel comes back here
; (K_SHHOOK -> the stub at $2E00, shstub.asm: SH.PRG loaded again if the command used its RAM).
; Ctrl-C (or Esc) between lines stops the script. SH -x shows each command before it runs.
;
; What is kept while an outside command runs ($2E98-$2EFF, shstate.inc): where the current line starts on the card
; (the kernel's file position before its sector, and the offset in it), how far along the line SH was, the ifs,
; $0-$9. The variables: $2F36-$2FFF ("NAME=value",0 each; a 0 ends them). Everything else SH works with is in
; $7700-$79FF (free while SH itself works: RECV's STLRX and LOAD use it, never at the same time) and made again from the card each time.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
        INCL    "shstate.inc"

RAWL    EQU     7700H           ; the line as it is in the script (255 characters at most; page-aligned)
WBUF    EQU     7800H           ; its words, for a built-in: quotes gone, each 0-ended
ARGV    EQU     7900H           ; where each word starts (2 bytes each)
MAXW    EQU     24
V       EQU     7940H
ARGC    EQU     V + 0           ; (1) the words
NFST    EQU     V + 1           ; (7) the next line: the file position before its sector ...
NSOFF   EQU     V + 8           ; (2) ... and the offset in it (NFST, NSOFF: as SFST, SSOFF)
CURST   EQU     V + 10          ; (7) the file position before the sector in DATBUF
NEXTP   EQU     V + 17          ; (2) the next command on the line (0: none)
NAMEP   EQU     V + 19          ; (2) the script's name as typed
SNM     EQU     V + 21          ; (11) a name (K_PARSE)
BUFOK   EQU     V + 32          ; (1) 1: DATBUF holds the sector read from BUFPRE
BUFPRE  EQU     V + 33          ; (7) the position it was read from
BUFPOST EQU     V + 40          ; (7) the position after it
BUFN    EQU     V + 47          ; (2) its bytes
NEGF    EQU     V + 49          ; (1) test: 1 = "!"
TOP     EQU     V + 50          ; (1) test: the operator
TA      EQU     V + 51          ; (2) test: the first operand
TB      EQU     V + 53          ; (2) test: the second
JMPV    EQU     V + 55          ; (3) LBR to a built-in (here, not in the code: the code's sum must not change)
VALP    EQU     V + 58          ; (2) VSET: the value
KWP     EQU     V + 60          ; (2) where the keyword being done starts (a loop's: its place to come back to)
NEXTC   EQU     V + 62          ; (1) how this command joins the next (SCONN's)
RANCMD  EQU     V + 63          ; (1) 1: a built-in or NAME=value ran in this command (set -e)
GK      EQU     V + 64          ; (1) for: the item still to find
GW      EQU     V + 65          ; (1) for: the words left
GP      EQU     V + 66          ; (2) for: the next word
GM      EQU     V + 68          ; (1) for: a wildcard's matches
FNP     EQU     V + 69          ; (2) for: the NAME ...
FNL     EQU     V + 71          ; (1) ... its length
PREVC   EQU     V + 72          ; (1) how the command before joined this one (SCONN as it was)
CMDP    EQU     V + 73          ; (2) where this command starts (after its keywords): $(...) comes back to it
CAPN    EQU     V + 75          ; (1) the $(...) in this command so far
OUTP    EQU     V + 76          ; (2) $(...): where its text goes in LINE
SPF     EQU     V + 78          ; (1) $(...): 1 a space owed, 2 something put already
CNAME   EQU     V + 79          ; (3) a case's word: the variable ?Cn (n its depth)
NESTF   EQU     V + 82          ; (1) 1: SH run from a script (a call, kind 3)
AUTOF   EQU     V + 83          ; (1) 1: SH -a (/AUTOEXEC.SH at boot: not there, nothing said)
VEND2   EQU     V + 84
POOL    EQU     KS_KVEND        ; the variables
POOLE   EQU     3000H

        ORG     SHLO - 6
        DW      START, PEND - START, START
        ORG     SHLO
START:  LBR     SHMAIN          ; $4000: SH ... (the kernel's RUN)
        LBR     SHRET           ; $4003: back after an outside command (the stub)

; ---- SH [-x] NAME [words]
SHMAIN: LOAD    RD, K_STAMP     ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        LOAD    RD, K_SHHOOK    ; a script running already?
        LDN     RD
        LBZ     SM0
        LOAD    RD, SRELD       ; the stub had SH.PRG loaded again (a command used its RAM): on with it
        LDN     RD
        LBZ     SM00
        LDI     0
        STR     RD
        SEP     R4
        DW      SS_SUM
        LOAD    RF, SSUM
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        LBR     SHRET
SM00:   LOAD    RD, NESTF       ; SH from a script: a call (kind 3) - where it goes on after is set already
        LDI     1
        STR     RD
        LBR     SMX
SM0:    LOAD    RD, NESTF
        LDI     0
        STR     RD
        LOAD    RD, ST          ; the state: 0
        LDI     128
        PLO     RC
SM0A:   LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    SM0A
        LOAD    RD, FNN         ; no functions, no calls
        LDI     0
        STR     RD
        LOAD    RD, CSN
        LDI     0
        STR     RD
        LOAD    RD, LS          ; the loops: none
        LDI     16
        PLO     RC
SM0C:   LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    SM0C
        LOAD    RD, BUFOK
        LDI     0
        STR     RD
SMX:    LOAD    RD, AUTOF
        LDI     0
        STR     RD
        LDN     RF              ; -x? -a?
        XRI     '-'
        LBNZ    SM1
        INC     RF
        LDA     RF
        ANI     0DFH
        XRI     'X'
        LBZ     SMXX
        XRI     'X' XOR 'A'
        LBNZ    USAGE
        LDN     RF              ; -a: /AUTOEXEC (the kernel, at boot)
        LBZ     SMXA
        XRI     ' '
        LBNZ    USAGE
SMXA:   LDI     1
        STR     RD
        LOAD    RF, AUTON
        LBR     SM1
SMXX:
        LDN     RF
        LBZ     SM0B
        XRI     ' '
        LBNZ    USAGE
SM0B:   LOAD    RD, SFLAGS
        LDI     1
        STR     RD
        SEP     R4
        DW      K_SKIPSP
SM1:    LDN     RF
        LBZ     USAGE
        LOAD    RD, NAMEP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, NESTF       ; from a script: its $0-$9 ... kept first
        LDN     RD
        LBZ     SM1A
        LDI     3
        SEP     R4
        DW      PUSHF
SM1A:   SEP     R4              ; $0 .. $9
        DW      SPLITA
        LOAD    RD, NAMEP       ; the script: NAME (.SH if no extension)
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, SNM
        SEP     R4
        DW      K_PARSE
        LBDF    NOFILE
        LOAD    RD, SNM+8
        LDN     RD
        XRI     ' '
        LBNZ    SM2
        LDI     'S'
        STR     RD
        INC     RD
        LDI     'H'
        STR     RD
SM2:    LOAD    RD, SNM         ; here ...
        SEP     R4
        DW      KS_FINDN
        LBNF    SM4
        LOAD    RD, KS_PPSL     ; (a path given: only there)
        LDN     RD
        LBNZ    NOFILE
        LOAD    RD, KS_WDIR     ; ... the root ...
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, SNM
        SEP     R4
        DW      KS_FINDN
        LBNF    SM4
        SEP     R4              ; ... /BIN
        DW      KS_TOBIN
        LBDF    NOFILE
        LOAD    RD, SNM
        SEP     R4
        DW      KS_FINDN
        LBDF    NOFILE
SM4:    LOAD    RD, KS_DATTR    ; (a folder: no)
        LDN     RD
        ANI     10H
        LBNZ    NOFILE
        LOAD    RD, NESTF       ; from a script: on with this one, the other's state kept
        LDN     RD
        LBZ     SM4A
        SEP     R4
        DW      OPENSH
        LBR     SHNEXT
SM4A:   SEP     R4
        DW      KS_FOPEN
        LOAD    RD, KS_FCLUS    ; the first line: from the file's start
        LOAD    RF, SFST
        SEP     R4
        DW      CP7
        LOAD    RD, SLNO+1
        LDI     1
        STR     RD
        LOAD    RD, POOL        ; no variables
        LDI     0
        STR     RD
        LOAD    RD, STUBIMG     ; the stub to $2E00
        LOAD    RF, SHSTUB
        LDI     STUBN
        PLO     RC
SM5:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    SM5
        LOAD    RD, SEND        ; the code's size (in 8s) and its sum (the stub checks it)
        LDI     HIGH((PEND - SHLO) / 8)
        STR     RD
        INC     RD
        LDI     LOW((PEND - SHLO) / 8)
        STR     RD
        SEP     R4
        DW      SS_SUM
        LOAD    RF, SSUM
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        LOAD    RD, K_SHHOOK+1  ; the kernel comes back here after each command: LBR $2E00
        LDI     HIGH(SHSTUB)
        STR     RD
        INC     RD
        LDI     LOW(SHSTUB)
        STR     RD
        LOAD    RD, K_SHHOOK
        LDI     0C0H
        STR     RD
        LOAD    RD, SMAGIC
        LDI     'S'
        STR     RD
        LBR     SHNEXT
NOFILE: LOAD    RD, AUTOF       ; (SH -a: no AUTOEXEC.SH - nothing to say)
        LDN     RD
        LBZ     NOFX
        LOAD    RD, K_STAT
        LDI     0
        STR     RD
        SEP     R5
NOFX:   LOAD    RD, NESTF       ; (from a script: its $0-$9 ... back)
        LDN     RD
        LBZ     NOF0
        SEP     R4
        DW      POPF
NOF0:   SEP     R4
        DW      K_TTYON
        SEP     R4
        DW      K_PIN
        DB      'SH: ',0
        LOAD    RD, NAMEP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
NF1:    LDA     RF
        LBZ     NF2
        XRI     ' '
        LBZ     NF2
        DEC     RF
        LDA     RF
        SEP     R4
        DW      K_OUT
        LBR     NF1
NF2:    SEP     R4
        DW      K_PIN
        DB      ' is not on the card.',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     127
        STR     RD
        SEP     R5
AUTON:  DB      '/AUTOEXEC',0
USAGE:  SEP     R4
        DW      K_PIN
        DB      'SH [-x] NAME [words] - runs the script NAME.SH',0DH,0AH,0
ST2:    LOAD    RD, K_STAT
        LDI     2
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5

; SPLITA: RF -> the words: each (quotes taken out) into SARGT, where it starts in SARGO; SARGN = $#
SPLITA: LOAD    R9, SARGO       ; $0-$9: none yet (a script from a script: the other's are kept apart)
        LDI     10
        PLO     RC
SA0:    LDI     0
        STR     R9
        INC     R9
        DEC     RC
        GLO     RC
        LBNZ    SA0
        LOAD    R9, SARGT
        LDI     0
        PLO     RC
        PLO     RB
SA1:    LDN     RF
        LBZ     SA9
        XRI     ' '
        LBNZ    SA2
        INC     RF
        LBR     SA1
SA2:    GLO     RC              ; ten at most, and room
        XRI     10
        LBZ     SA9
        GHI     R9
        XRI     HIGH(SARGE)
        LBZ     SA9
        LOAD    RD, SARGO
        GLO     RC
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GLO     R9
        STR     RD
        INC     RC
SA3:    LDA     RF
        LBZ     SA5
        PLO     RA
        GLO     RB
        LBNZ    SAQ
        GLO     RA
        XRI     ' '
        LBZ     SA6
        GLO     RA
        XRI     27H
        LBZ     SAO
        GLO     RA
        XRI     22H
        LBZ     SAO
SAC:    GLO     R9              ; (the last byte kept for the 0)
        XRI     0FFH
        LBZ     SA3
        GLO     RA
        STR     R9
        INC     R9
        LBR     SA3
SAO:    GLO     RA
        PLO     RB
        LBR     SA3
SAQ:    GLO     RA
        STR     R2
        GLO     RB
        XOR
        LBNZ    SAC
        PLO     RB
        LBR     SA3
SA5:    DEC     RF
SA6:    LDI     0
        STR     R9
        INC     R9
        LBR     SA1
SA9:    LOAD    RD, SARGN
        GLO     RC
        SMI     1
        STR     RD
        SEP     R5

; ---- the next step: after an outside command (the stub has put its status in $?), or the next line
SHRET:  LOAD    RD, BUFOK       ; (DATBUF: the command's now)
        LDI     0
        STR     RD
        LOAD    RD, RANCMD      ; (an outside command ran: set -e looks at it)
        LDI     1
        STR     RD
        SEP     R4              ; "!" before it; set -e
        DW      AFTER
        LBR     SHNEXT
SHNEXT: LOAD    R2, KS_STACK    ; (a fresh stack: a loop's done comes here from inside DOCMD)
        LDI     15H             ; a key waiting? Ctrl-C or Esc stops the script
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        LBZ     SN1
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RB
        XRI     03H
        LBZ     STOPPED
        XRI     03H XOR 1BH
        LBZ     STOPPED
        LOAD    RD, SKEY        ; another key: kept for read
        GLO     RB
        STR     RD
SN1:    SEP     R4              ; the line, from the card
        DW      RDLINE
        LBDF    SEOF
        LOAD    RD, SRES        ; from where SH was in it
        LDN     RD
        PLO     RF
        LDI     HIGH(RAWL)
        PHI     RF
SEG:    SEP     R4              ; this command: to its ';' && || (or the line's end)
        DW      SEGEND
        LOAD    RD, SCONN       ; joined to the one before by && or ||: run only if that one's status says so
        LDN     RD
        PLO     RB
        LOAD    RD, PREVC
        GLO     RB
        STR     RD
        LBZ     SEG1
        XRI     3               ; ;; - a case's branch ended
        LBNZ    SEG0
        SEP     R4
        DW      CASEEND
        LBR     SEG1
SEG0:   GLO     RB
        XRI     1
        LBNZ    SEGOR
        LOAD    RD, SSTAT       ; &&: only after 0
        LDN     RD
        LBNZ    SEGSK
        LBR     SEG1
SEGOR:  LOAD    RD, SSTAT       ; ||: only after not 0
        LDN     RD
        LBZ     SEGSK
SEG1:   SEP     R4              ; SCONN = how this one joins the next
        DW      SETCON
        LOAD    RD, RANCMD
        LDI     0
        STR     RD
        SEP     R4
        DW      DOCMD
        SEP     R4
        DW      AFTER
        LBR     SEGN
SEGSK:  SEP     R4              ; skipped ($? as it was)
        DW      SETCON
SEGN:   LOAD    RD, NEXTP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     RF
        LBNZ    SEG
        SEP     R4
        DW      NEXTLN
        LBR     SHNEXT
SEOF:   LOAD    RD, CSN         ; a . file, or a script run from this one: back to it
        LDN     RD
        LBZ     SEOF0
        SEP     R4
        DW      CSTOP
        XRI     1
        LBZ     SEOFF
        SEP     R4
        DW      POPF
        LBR     SHNEXT
SEOFF:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'a function',27H,'s } is missing',0DH,0AH,0
        LBR     FATAL
SEOF0:  LOAD    RD, SIFSP       ; the end: every if closed?
        LDN     RD
        LBZ     SHENDS
        SEP     R4
        DW      TOPC0
        XRI     12
        LBZ     SEOFF
        SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'if without fi',0DH,0AH,0
        LBR     FATAL
STOPPED: SEP    R4
        DW      K_TTYON
        SEP     R4
        DW      PNAME0
        SEP     R4
        DW      K_PIN
        DB      ' stopped at line ',0
        SEP     R4
        DW      PLNO
        SEP     R4
        DW      K_PCRLF
        LDI     130
        PLO     RB
        LBR     SHENDB
FATAL:  LDI     2
        PLO     RB
        LBR     SHENDB
SHENDS: LOAD    RD, SSTAT       ; the end: the status is $?
        LDN     RD
        PLO     RB
SHENDB: LOAD    RD, K_STAT      ; (RB.0: the status)
        GLO     RB
        STR     RD
        LOAD    RD, K_SHHOOK
        LDI     0
        STR     RD
        LOAD    RD, SMAGIC
        LDI     0
        STR     RD
        LBR     K_MAIN

; SETCON: SCONN = NEXTC
SETCON: LOAD    RD, NEXTC
        LDN     RD
        PLO     RB
        LOAD    RD, SCONN
        GLO     RB
        STR     RD
        SEP     R5
; AFTER: a command has run: "!" before it turns $? round; set -e stops the script at a status not 0 - unless the
;        command was a condition (if, while, until), or && / || follows it, or it had a "!"
AFTER:  LOAD    RD, SNEG
        LDN     RD
        PLO     RB              ; RB.0 = 1: a "!"
        LDI     0
        STR     RD
        GLO     RB
        LBZ     AF1
        LOAD    RD, SSTAT
        LDN     RD
        LBZ     AF0
        LDI     0
        LSKP
AF0:    LDI     1
        STR     RD
        SEP     R5              ; (a "!": never set -e's)
AF1:    LOAD    RD, SFLAGS      ; set -e?
        LDN     RD
        ANI     2
        LBZ     AF9
        LOAD    RD, RANCMD      ; a command ran (not just a keyword)
        LDN     RD
        LBZ     AF9
        LOAD    RD, SSTAT
        LDN     RD
        LBZ     AF9
        LOAD    RD, SCONN       ; && or || after it
        LDN     RD
        LBNZ    AF9
        SEP     R4              ; a condition
        DW      INCOND
        LBNF    AF9
        LOAD    RD, SSTAT       ; set -e: the end, with that status
        LDN     RD
        PLO     RB
        LBR     SHENDB
AF9:    SEP     R5
; INCOND: DF = 0 if the command was an if's, while's or until's condition (the top one: state 1)
INCOND: LOAD    RD, SIFSP
        LDN     RD
        LBZ     IC1
        SEP     R4
        DW      TOPP
        LDN     RD
        XRI     1
        LBZ     IC0
IC1:    SEP     R4
        DW      LTOP
        LBDF    IC9
        XRI     1
        LBNZ    IC9
IC0:    ADI     0               ; (D = 0: DF = 0)
        SEP     R5
IC9:    SMI     0               ; (DF = 1)
        LDI     1
        SHR
        SEP     R5

; NEXTLN: on to the next line
NEXTLN: LOAD    RD, NFST        ; SFST, SSOFF = NFST, NSOFF
        LOAD    RF, SFST
        LDI     9
        SEP     R4
        DW      CPN
        LOAD    RD, SLNO+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, SRES
        LDI     0
        STR     RD
        SEP     R5

; EXTERN: an outside command, at LINE: on from after it next time, and the kernel runs it
EXTERN: SEP     R4
        DW      ADVANCE
XEXEC:  LOAD    RD, KS_TTYF     ; (an error said before: the screen only until now)
        LDI     0
        STR     RD
        LBR     K_EXEC
; ADVANCE: the place after this command - on along the line (SRES), or the next line
ADVANCE: LOAD   RD, NEXTP
        LDA     RD
        LBZ     NEXTLN
        LDN     RD
        PLO     RB
        LOAD    RD, SRES
        GLO     RB
        STR     RD
        SEP     R5

; ---- RDLINE: the line at SFST / SSOFF into RAWL, 0-ended (CRs and 0s left out; past 255 characters dropped);
;      NFST / NSOFF = where the next one starts. DF = 1: the script's end. (A card failure: said, the end.)
RDLINE: LOAD    RD, SFST
        LOAD    RF, CURST
        SEP     R4
        DW      CP7
        SEP     R4
        DW      RDSEC
        LBDF    RLE0
        LOAD    RD, SSOFF       ; R9 = DATBUF + SSOFF; RA = DATBUF + its bytes
        LDA     RD
        ADI     HIGH(KS_DATBUF)
        PHI     R9
        LDN     RD
        PLO     R9
        SEP     R4
        DW      RAEND
        LOAD    RB, RAWL
        LDI     0
        PLO     R8              ; R8.0 = 1: something read (a line, though empty)
RL1:    GHI     R9              ; the sector's end?
        STR     R2
        GHI     RA
        XOR
        LBNZ    RL2
        GLO     R9
        STR     R2
        GLO     RA
        XOR
        LBNZ    RL2
        GLO     RB              ; the next sector
        STXD
        GHI     RB
        STXD
        GLO     R8
        STXD
        LOAD    RD, KS_FCLUS
        LOAD    RF, CURST
        SEP     R4
        DW      CP7
        SEP     R4
        DW      RDSEC
        PHI     R7              ; (why it ended; DF kept)
        IRX
        LDXA
        PLO     R8
        LDXA
        PHI     RB
        LDX
        PLO     RB
        LBDF    RLE
        LOAD    R9, KS_DATBUF
        SEP     R4
        DW      RAEND
        LBR     RL1
RL2:    LDI     1
        PLO     R8
        LDA     R9
        LBZ     RL1
        XRI     0AH
        LBZ     RLLF
        XRI     0AH XOR 0DH
        LBZ     RL1
        XRI     0DH
        PLO     RC
        GLO     RB
        XRI     0FFH
        LBZ     RL1
        GLO     RC
        STR     RB
        INC     RB
        LBR     RL1
RLE:    GHI     R7              ; the file ended (or failed) inside the line
        XRI     2
        LBZ     RLF
        GLO     R8
        LBZ     RLEOF
RLLF:   LDI     0               ; the line's end: the next starts here
        STR     RB
        LOAD    RD, CURST
        LOAD    RF, NFST
        SEP     R4
        DW      CP7
        LOAD    RD, NSOFF
        GHI     R9
        SMI     HIGH(KS_DATBUF)
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LDI     0
        SHR
        SEP     R5
RLE0:   XRI     2
        LBZ     RLF
RLEOF:  LDI     1
        SHR
        SEP     R5
RLF:    SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'the card could not be read',0DH,0AH,0
        LDI     1
        PLO     RB
        LBR     SHENDB
; RAEND: RA = DATBUF + RC (the bytes FREAD gave)
RAEND:  GLO     RC
        PLO     RA
        GHI     RC
        ADI     HIGH(KS_DATBUF)
        PHI     RA
        SEP     R5
; RDSEC: the sector at CURST into DATBUF (FREAD: RC its bytes, DF = 1 + D: 1 the end, 2 failed). The one there
;        already, if it is that one (lines in the same sector: read once).
RDSEC:  LOAD    RD, BUFOK
        LDN     RD
        LBZ     RS1
        LOAD    RD, CURST
        LOAD    RF, BUFPRE
        LDI     7
        PLO     RC
RS0:    LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    RS1
        DEC     RC
        GLO     RC
        LBNZ    RS0
        LOAD    RD, BUFPOST     ; that one: the position after it, its bytes
        LOAD    RF, KS_FCLUS
        SEP     R4
        DW      CP7
        LOAD    RD, BUFN
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDI     0
        SHR
        SEP     R5
RS1:    LOAD    RD, BUFOK
        LDI     0
        STR     RD
        LOAD    RD, CURST
        LOAD    RF, KS_FCLUS
        SEP     R4
        DW      CP7
        SEP     R4
        DW      KS_FREAD
        LBDF    RS9
        LOAD    RD, BUFN
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, CURST
        LOAD    RF, BUFPRE
        SEP     R4
        DW      CP7
        LOAD    RD, KS_FCLUS
        LOAD    RF, BUFPOST
        SEP     R4
        DW      CP7
        LOAD    RD, BUFOK
        LDI     1
        STR     RD
        LOAD    RD, BUFN
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDI     0
        SHR
        SEP     R5
RS9:    SEP     R5
; CP7: 7 bytes from RD to RF. CPN: D bytes.
CP7:    LDI     7
CPN:    PLO     RC
CP1:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    CP1
        SEP     R5

; ---- SEGEND: RF -> a command in RAWL: it ends at a ';' outside quotes (made 0: NEXTP = after it) or at the
;      line's end, or at a '#' starting a word (the rest is a comment) - NEXTP = 0. RF kept.
SEGEND: GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        LDI     0
        PLO     RB              ; RB.0 = the quote it is in
        LDI     ' '
        PHI     RB              ; RB.1 = the character before
SE1:    LDN     RD
        LBZ     SENONE
        PLO     RC
        GLO     RB
        LBZ     SE2
        GLO     RC              ; in quotes: the closing one?
        STR     R2
        GLO     RB
        XOR
        LBNZ    SE5
        PLO     RB
        LBR     SE5
SE2:    GLO     RC
        XRI     27H
        LBZ     SEQ
        GLO     RC
        XRI     22H
        LBZ     SEQ
        GLO     RC
        XRI     ';'
        LBZ     SESEMI
        GLO     RC              ; && or ||?
        XRI     '&'
        LBZ     SEAA
        GLO     RC
        XRI     '|'
        LBZ     SEOO
        GLO     RC
        XRI     '#'
        LBNZ    SE5
        GHI     RB
        XRI     ' '
        LBZ     SENON0
        LBR     SE5
SEQ:    GLO     RC
        PLO     RB
SE5:    GLO     RC
        PHI     RB
        INC     RD
        LBR     SE1
SEAA:   INC     RD              ; && (one & alone: a character)
        LDN     RD
        DEC     RD
        XRI     '&'
        LBNZ    SE5
        LDI     1
        LBR     SECON
SEOO:   INC     RD              ; || (| alone: a character)
        LDN     RD
        DEC     RD
        XRI     '|'
        LBNZ    SE5
        LDI     2
SECON:  PLO     RB
        LDI     0
        STR     RD
        INC     RD
        INC     RD
        LBR     SESEM2
SESEMI: INC     RD              ; ;; (a case's branch ends): 3
        LDN     RD
        DEC     RD
        XRI     ';'
        LBNZ    SESEM1
        LDI     3
        LBR     SECON
SESEM1: LDI     0
        STR     RD
        INC     RD
        PLO     RB              ; (; : 0)
SESEM2: LOAD    RC, NEXTC
        GLO     RB
        STR     RC
        LOAD    RC, NEXTP
        GHI     RD
        STR     RC
        INC     RC
        GLO     RD
        STR     RC
        SEP     R5
SENON0: LDI     0
        STR     RD
SENONE: LOAD    RC, NEXTP
        LDI     0
        STR     RC
        INC     RC
        STR     RC
        LOAD    RC, NEXTC
        LDI     0
        STR     RC
        SEP     R5

; ---- DOCMD: RF -> one command (0-ended): a keyword, a built-in, NAME=value, or an outside command (no return:
;      EXTERN). Skipped if an if says so.
DOCMD:  SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     DCRET
        LOAD    RD, KWP         ; (where the keyword starts: a loop comes back to it)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4              ; a case, waiting for a pattern: this is one (or esac)
        DW      CASEQ
        LBDF    DC1
        LOAD    RD, ESTAB
        SEP     R4
        DW      WORDIS
        LBNZ    KESAC
        LBR     CPAT
DC1:    LOAD    RD, KWTAB       ; if then elif else fi while until for do done case esac }
        SEP     R4
        DW      WORDIS
        LBZ     DC2
        SMI     1
        LBZ     KIF
        SMI     1
        LBZ     KTHEN
        SMI     1
        LBZ     KELIF
        SMI     1
        LBZ     KELSE
        SMI     1
        LBZ     KFI
        SMI     1
        LBZ     KWHILE
        SMI     1
        LBZ     KUNTIL
        SMI     1
        LBZ     KFOR
        SMI     1
        LBZ     KDO
        SMI     1
        LBZ     KDONE
        SMI     1
        LBZ     KCASE
        SMI     1
        LBZ     KESAC
        LBR     KBRACE
DC2:    LDN     RF              ; NAME() { - a function
        SEP     R4
        DW      ISIDS
        LBNF    DC5
        SEP     R4
        DW      VNAME
        LDN     RF
        XRI     '('
        LBNZ    DC2X
        INC     RF
        LDN     RF
        DEC     RF
        XRI     ')'
        LBZ     FNDEF
DC2X:   GHI     RA              ; not one: back to the word
        PHI     RF
        GLO     RA
        PLO     RF
DC5:    SEP     R4              ; skipping (an if's other branch, a loop ended ...)?
        DW      ACTIVE
        LBDF    DCRET
        LDN     RF              ; "! command": its status turned round (AFTER)
        XRI     '!'
        LBNZ    DC5N
        INC     RF
        LDN     RF
        LBZ     DC5M
        XRI     ' '
        LBZ     DC5M
        DEC     RF
        LBR     DC5N
DC5M:   LOAD    RD, SNEG
        LDI     1
        STR     RD
        SEP     R4
        DW      K_SKIPSP
DC5N:   LOAD    RD, CMDP        ; (where it starts: $(...) does it again from here)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, CAPN
        LDI     0
        STR     RD
        SEP     R4              ; $ replaced: LINE
        DW      EXPAND
        LOAD    RD, SFLAGS      ; -x: shown
        LDN     RD
        SHR
        LBNF    DC6
        SEP     R4
        DW      K_PIN
        DB      '+ ',0
        LOAD    RF, KS_LINE
DC5A:   LDA     RF
        LBZ     DC5B
        SEP     R4
        DW      K_OUT
        LBR     DC5A
DC5B:   SEP     R4
        DW      K_PCRLF
DC6:    LOAD    RD, RANCMD      ; (a command ran: set -e looks at it; an outside one: SHRET says so)
        LDI     1
        STR     RD
        SEP     R4              ; NAME=value?
        DW      ISASG
        LBNF    ASSIGN
        SEP     R4              ; the words (DF = 1: a '>' - the kernel does that: ECHO.PRG for echo)
        DW      SPLIT
        LBDF    EXTERN
        LOAD    RD, ARGC
        LDN     RD
        LBZ     DCRET           ; nothing ("$EMPTY")
        LOAD    RD, ARGV
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, BTAB
        SEP     R4
        DW      WORDIS
        LBZ     DCFN
        SMI     1               ; RD = BJMP + 2 x (index - 1) -> JMPV: LBR there
        SHL
        ADI     LOW(BJMP)
        PLO     RD
        LDI     HIGH(BJMP)
        ADCI    0
        PHI     RD
        LOAD    RF, JMPV
        LDI     0C0H
        STR     RF
        INC     RF
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LBR     JMPV            ; (it ends with SEP R5)
DCFN:   SEP     R4              ; a function?
        DW      FFIND
        LBNF    CALLF
        LBR     EXTERN
DCRET:  SEP     R5
KWTAB:  DB      'IF',0,'THEN',0,'ELIF',0,'ELSE',0,'FI',0,'WHILE',0,'UNTIL',0,'FOR',0,'DO',0,'DONE',0
        DB      'CASE',0,'ESAC',0,'}',0,0
ESTAB:  DB      'ESAC',0,0
BTAB:   DB      'ECHO',0,'EXIT',0,'TEST',0,'[',0,'TRUE',0,':',0,'FALSE',0,'SET',0,'UNSET',0,'READ',0
        DB      'BREAK',0,'CONTINUE',0,'SHIFT',0,'SLEEP',0,'PAUSE',0,'RETURN',0,'.',0,0
BJMP:   DW      B_ECHO, B_EXIT, B_TEST, B_TEST, B_TRUE, B_TRUE, B_FALSE, B_SET, B_UNSET, B_READ
        DW      B_BREAK, B_CONT, B_SHIFT, B_SLEEP, B_PAUSE, B_RET, B_DOT

; ---- the ifs. SIFS: 1 the condition is running, 2 the branch running, 3 skipping it (another may run), 4 done
;      (skipping the rest), 5 the whole if skipped (inside a skipped part)
KIF:    LOAD    RD, SIFSP
        LDN     RD
        XRI     8
        LBNZ    KIF1
        SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'if: more than 8 inside each other',0DH,0AH,0
        LBR     FATAL
KIF1:   SEP     R4
        DW      ACTIVE
        LDI     1
        LBNF    KIF2
        LDI     5
KIF2:   PLO     RB
        LOAD    RD, SIFSP
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      TOPP
        GLO     RB
        STR     RD
        LBR     DOCMD           ; the rest: the condition
KTHEN:  SEP     R4
        DW      TOPC
        XRI     1
        LBNZ    DOCMD           ; (4, 5: as they are)
        LOAD    RD, SSTAT       ; the condition's status: 0 runs the branch
        LDN     RD
        LBZ     KTH1
        LDI     3
        LSKP
KTH1:   LDI     2
        PLO     RB
KSET:   SEP     R4
        DW      TOPP
        GLO     RB
        STR     RD
        LBR     DOCMD
KELIF:  SEP     R4
        DW      TOPC
        XRI     2
        LBZ     KEL4            ; a branch ran: done
        XRI     2 XOR 3
        LBNZ    DOCMD
        LDI     1               ; none yet: this condition
        PLO     RB
        LBR     KSET
KEL4:   LDI     4
        PLO     RB
        LBR     KSET
KELSE:  SEP     R4
        DW      TOPC
        XRI     2
        LBZ     KEL4
        XRI     2 XOR 3
        LBNZ    DOCMD
        LDI     2
        PLO     RB
        LBR     KSET
KFI:    SEP     R4
        DW      TOPC
        XRI     3               ; no branch ran: $? = 0 (as sh)
        LBNZ    KFI1
        LOAD    RD, SSTAT
        LDI     0
        STR     RD
KFI1:   LOAD    RD, SIFSP
        LDN     RD
        SMI     1
        STR     RD
        LBR     DOCMD
; ---- the loops (LFR at $7E00: kept while outside commands run). A loop's keyword line is read again for each
;      round: done goes back to the keyword's place (its frame: state 7), and the keyword sees its own frame.
KWHILE: LDI     1
        LSKP
KUNTIL: LDI     2
        PLO     RB              ; RB.0 = the kind
        SEP     R4              ; back here from its done?
        DW      LTOP
        LBDF    KW1
        XRI     7
        LBNZ    KW1
        INC     RD              ; the condition again
        LDI     1
        STR     RD
        LBR     DOCMD
KW1:    SEP     R4              ; a new loop: its condition (or all of it skipped)
        DW      ACTIVE
        LDI     1
        LBNF    KW2
        LDI     6
KW2:    PHI     RB
        SEP     R4
        DW      LPUSH
        LBR     DOCMD
KDO:    SEP     R4
        DW      LTOP
        LBDF    LNONE
        XRI     1
        LBNZ    DOCMD           ; (running, skipped ...: as it is)
        LDN     RD              ; the condition's status: while runs on 0, until on not 0
        XRI     2
        PLO     RB              ; RB.0 = 0: until
        LOAD    RA, SSTAT
        LDN     RA
        LBZ     KDO1
        LDI     1
KDO1:   STR     R2              ; (1: not 0)
        GLO     RB
        LBNZ    KDO2
        LDN     R2
        XRI     1
        STR     R2
KDO2:   LDN     R2
        LBZ     KDO3
        LDI     3               ; ended
        LSKP
KDO3:   LDI     2               ; running
        INC     RD
        STR     RD
        LBR     DOCMD           ; (RF: after "do" - the rest)
KDONE:  SEP     R4
        DW      LTOP
        LBDF    LNONE
        XRI     2
        LBZ     KDN1
        XRI     2 XOR 5
        LBZ     KDN1
        XRI     5 XOR 3         ; ended, or broken out of: $? 0 (as sh)
        LBZ     KDN0
        XRI     3 XOR 4
        LBNZ    KDN2
KDN0:   LOAD    RA, SSTAT
        LDI     0
        STR     RA
KDN2:   LOAD    RD, LSP         ; the loop is done with
        LDN     RD
        SMI     1
        STR     RD
        LBR     DOCMD
KDN1:   INC     RD              ; running, or continue: back to its keyword
        LDI     7
        STR     RD
        DEC     RD
        LBR     LJUMP
LNONE:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'do or done without while, until or for',0DH,0AH,0
        LBR     FATAL
; for NAME [in words]: each round the next item (index at frame + 2); none left: ended
KFOR:   SEP     R4
        DW      LTOP
        LBDF    KF1
        XRI     7
        LBNZ    KF1
        LBR     KF3             ; back from its done: the next item
KF1:    SEP     R4
        DW      ACTIVE
        LDI     2
        LBNF    KF2
        LDI     6
KF2:    PHI     RB
        LDI     3
        PLO     RB
        SEP     R4
        DW      LPUSH
        GHI     RB
        XRI     6
        LBZ     DOCMD           ; skipped: the rest too
KF3:    INC     RD              ; RD -> the frame: 7 until the item is set (a $(...) in the words comes back here)
        LDI     7
        STR     RD
        DEC     RD
        LOAD    RA, KWP
        LOAD    R9, CMDP
        LDA     RA
        STR     R9
        INC     R9
        LDN     RA
        STR     R9
        LOAD    RA, CAPN
        LDI     0
        STR     RA
        SEP     R4              ; RF -> NAME: the next item into it
        DW      K_SKIPSP
        LDN     RF
        SEP     R4
        DW      ISIDS
        LBNF    KFBAD
        SEP     R4
        DW      VNAME
        LOAD    RD, FNP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        SEP     R4
        DW      LTOP            ; GK = the item wanted
        INC     RD
        INC     RD
        LDN     RD
        PLO     RB
        LOAD    RD, GK
        GLO     RB
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LOAD    RD, INTAB       ; "in words": those; else $1 .. $#
        SEP     R4
        DW      WORDIS
        LBZ     KFARG
        SEP     R4
        DW      EXPAND
        SEP     R4
        DW      SPLIT
        SEP     R4
        DW      ITEMK           ; LINE = item GK (DF = 1: none)
        LBDF    KFEND
        LBR     KFSET
KFARG:  LOAD    RD, SARGN       ; $1 .. $#: item GK is $(GK + 1)
        LDN     RD
        STR     R2
        LOAD    RD, GK
        LDN     RD
        SD                      ; $# - GK: none left if 0 (or less)
        LBNF    KFEND
        LBZ     KFEND
        LDN     RD
        ADI     LOW(SARGO + 1)
        PLO     RD
        LDI     HIGH(SARGO)
        PHI     RD
        LDN     RD
        PLO     RD
        LDI     HIGH(SARGT)
        PHI     RD
        LOAD    RF, KS_LINE
KFA1:   LDA     RD
        STR     RF
        INC     RF
        LBNZ    KFA1
KFSET:  LOAD    RD, FNP         ; NAME = it
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDN     RD
        PLO     R9
        LOAD    RF, KS_LINE
        SEP     R4
        DW      VSET
        SEP     R4              ; running; the next one next time
        DW      LTOP
        INC     RD
        LDI     2
        STR     RD
        INC     RD
        LDN     RD
        ADI     1
        STR     RD
        SEP     R5
KFEND:  SEP     R4              ; none left: ended
        DW      LTOP
        INC     RD
        LDI     3
        STR     RD
        SEP     R5
KFBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'for NAME [in words]',0DH,0AH,0
        LBR     FATAL
INTAB:  DB      'IN',0,0
; ITEMK: the words at ARGV (ARGC of them), a word with * or ? standing for the names it matches here (none: the
;        word itself): LINE = item number GK (from 0), DF = 0; DF = 1 there are not that many
ITEMK:  LOAD    RD, ARGC
        LDN     RD
        PLO     RB
        LOAD    RD, GW
        GLO     RB
        STR     RD
        LOAD    RD, GP
        LDI     HIGH(ARGV)
        STR     RD
        INC     RD
        LDI     LOW(ARGV)
        STR     RD
IK1:    LOAD    RD, GW          ; the next word
        LDN     RD
        LBZ     IKNO
        SMI     1
        STR     RD
        LOAD    R9, GP          ; RF = it; GP + 2
        LDA     R9
        PHI     RD
        LDN     R9
        PLO     RD
        LDA     RD
        PHI     RF
        LDA     RD
        PLO     RF
        LOAD    R9, GP
        GHI     RD
        STR     R9
        INC     R9
        GLO     RD
        STR     R9
        GHI     RF              ; a wildcard in it?
        PHI     RA
        GLO     RF
        PLO     RA
IK2:    LDA     RA
        LBZ     IKW
        XRI     '*'
        LBZ     IKG
        XRI     '*' XOR '?'
        LBNZ    IK2
IKG:    LOAD    RD, GM          ; the names it matches here
        LDI     0
        STR     RD
        GLO     RF
        STXD
        GHI     RF
        STXD
        LOAD    RD, KS_PAT
        SEP     R4
        DW      K_PARSE
        LBDF    IKG9
        SEP     R4
        DW      KS_DOPEN
IKG1:   SEP     R4
        DW      KS_DNEXT
        LBDF    IKG9
        LOAD    RD, GM
        LDI     1
        STR     RD
        SEP     R4              ; this one?
        DW      IKTAKE
        LBDF    IKG1
        IRX                     ; yes: LINE = the word's folder part (to its last '/'), then the name
        LDXA
        PHI     RF
        LDX
        PLO     RF
        GHI     RF
        PHI     RA
        PHI     R9
        GLO     RF
        PLO     RA
        PLO     R9
IKG2:   LDA     RF
        LBZ     IKG3
        XRI     '/'
        LBNZ    IKG2
        GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
        LBR     IKG2
IKG3:   LOAD    RD, KS_LINE
IKG4:   GLO     R9
        STR     R2
        GLO     RA
        XOR
        LBNZ    IKG5
        GHI     R9
        STR     R2
        GHI     RA
        XOR
        LBZ     IKG6
IKG5:   LDA     R9
        STR     RD
        INC     RD
        LBR     IKG4
IKG6:   LOAD    RF, KS_DPTR     ; the entry: DPTR - 32 -> NAME.EXT
        LDA     RF
        PHI     RA
        LDN     RF
        SMI     32
        PLO     RA
        GHI     RA
        SMBI    0
        PHI     RA
        LDI     8
        PLO     RC
IKN1:   LDA     RA
        XRI     ' '
        LBZ     IKN2
        XRI     ' '
        STR     RD
        INC     RD
IKN2:   DEC     RC
        GLO     RC
        LBNZ    IKN1
        LDN     RA
        XRI     ' '
        LBZ     IKN4
        LDI     '.'
        STR     RD
        INC     RD
        LDI     3
        PLO     RC
IKN3:   LDA     RA
        XRI     ' '
        LBZ     IKN3A
        XRI     ' '
        STR     RD
        INC     RD
IKN3A:  DEC     RC
        GLO     RC
        LBNZ    IKN3
IKN4:   LDI     0
        STR     RD
        SHR                     ; (DF = 0)
        SEP     R5
IKG9:   IRX                     ; no more matches; none at all: the word itself
        LDXA
        PHI     RF
        LDX
        PLO     RF
        LOAD    RD, GM
        LDN     RD
        LBNZ    IK1
IKW:    SEP     R4              ; a word: this one?
        DW      IKTAKE
        LBDF    IK1
        LOAD    RD, KS_LINE
IKW1:   LDA     RF
        STR     RD
        INC     RD
        LBNZ    IKW1
        SHR
        SEP     R5
IKNO:   LDI     1
        SHR
        SEP     R5
; IKTAKE: GK = 0? DF = 0 (take this one). Else GK - 1, DF = 1.
IKTAKE: LOAD    RD, GK
        LDN     RD
        LBZ     IKT0
        SMI     1
        STR     RD
        LDI     1
        SHR
        SEP     R5
IKT0:   SHR
        SEP     R5
; LTOP: RD -> the innermost loop's frame, D = its state, DF = 0; DF = 1: no loop
LTOP:   LOAD    RD, LSP
        LDN     RD
        LBZ     LTNO
        SMI     1
        SHL
        SHL
        SHL
        SHL
        ADI     LOW(LFR)
        PLO     RD
        LDI     HIGH(LFR)
        PHI     RD
        INC     RD
        LDN     RD
        DEC     RD
        SEP     R5
LTNO:   LDI     1
        SHR
        SEP     R5
; LPUSH: a new loop - kind RB.0, state RB.1, at the keyword's place (KWP, this line): RD -> its frame
LPUSH:  LOAD    RD, LSP
        LDN     RD
        XRI     LMAX
        LBNZ    LP1
        SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'loops: more than 6 inside each other',0DH,0AH,0
        LBR     FATAL
LP1:    LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      LTOP
        GLO     RB
        STR     RD
        INC     RD
        GHI     RB
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        INC     RD
        LOAD    R9, SFST        ; SFST SSOFF SLNO: 11 bytes
        LDI     11
        PLO     RC
LP2:    LDA     R9
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    LP2
        LOAD    R9, KWP+1       ; the offset in the line (RAWL is page-aligned)
        LDN     R9
        STR     RD
        SEP     R4
        DW      LTOP
        SEP     R5
; LJUMP: back to the keyword of the loop at RD (the line read again; SHNEXT)
LJUMP:  INC     RD
        INC     RD
        INC     RD
        LOAD    RF, SFST
        LDI     11
        SEP     R4
        DW      CPN
        LDN     RD
        PLO     RB
        LOAD    RD, SRES
        GLO     RB
        STR     RD
        LOAD    RD, SCONN
        LDI     0
        STR     RD
        LBR     SHNEXT
; break, continue: the innermost loop - out of it, or on to its next round
B_BREAK: LDI    4
        LSKP
B_CONT: LDI     5
        PLO     RB
        SEP     R4
        DW      LTOP
        LBDF    BKNO
        INC     RD
        GLO     RB
        STR     RD
        LBR     ST0
BKNO:   SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'break or continue outside a loop',0DH,0AH,0
        LBR     FATAL

; ---- case WORD in  pat|pat) commands ;;  ...  esac. On the ifs' stack: 8 waiting for a pattern, 9 its branch
;      running, 10 done (one ran: the rest skipped), 11 in a branch that did not match; 5 all of it skipped. The
;      word is kept as the variable ?Cn (n: its depth).
KCASE:  SEP     R4
        DW      ACTIVE
        LBNF    KC1
        LDI     5               ; skipped: all of it
        LBR     IPUSHD
KC1:    LOAD    RA, KWP         ; (a $(...) in the word: back to this case)
        LOAD    R9, CMDP
        LDA     RA
        STR     R9
        INC     R9
        LDN     RA
        STR     R9
        LOAD    RA, CAPN
        LDI     0
        STR     RA
        SEP     R4              ; the word: to a space outside quotes - made 0 for now, $ replaced
        DW      K_SKIPSP
        GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
        LDI     0
        PLO     RC
        PHI     RC              ; RC.1 = ( ... ) open
KW0:    LDN     RF
        LBZ     KW0E
        PLO     R8
        GLO     RC
        LBNZ    KW0Q
        GLO     R8
        XRI     '('
        LBNZ    KW01
        GHI     RC
        ADI     1
        PHI     RC
KW01:   GLO     R8
        XRI     ')'
        LBNZ    KW02
        GHI     RC
        SMI     1
        PHI     RC
KW02:   GHI     RC
        LBNZ    KW0N
        GLO     R8
        XRI     ' '
        LBZ     KW0E
        GLO     R8
        XRI     27H
        LBZ     KW0O
        GLO     R8
        XRI     22H
        LBNZ    KW0N
KW0O:   GLO     R8
        PLO     RC
        LBR     KW0N
KW0Q:   GLO     R8
        STR     R2
        GLO     RC
        XOR
        LBNZ    KW0N
        PLO     RC
KW0N:   INC     RF
        LBR     KW0
KW0E:   LDN     RF              ; (the character there, and where)
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        LDI     0
        STR     RF
        GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        SEP     R4
        DW      EXPAND
        SEP     R4
        DW      SPLIT
        IRX                     ; back as it was
        LDXA
        PHI     RF
        LDXA
        PLO     RF
        LDX
        STR     RF
        SEP     R4              ; then "in"
        DW      K_SKIPSP
        LOAD    RD, INTAB
        SEP     R4
        DW      WORDIS
        LBZ     KCBAD
        LDI     8
        SEP     R4
        DW      IPUSH
        GLO     RF              ; ?Cn = the word (none: empty)
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      CNAMEQ
        LOAD    RF, PTEMP
        LOAD    RD, ARGC
        LDN     RD
        LBZ     KC2
        LOAD    RD, ARGV
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
KC2:    SEP     R4
        DW      VSET
        IRX
        LDXA
        PHI     RF
        LDX
        PLO     RF
        LBR     DOCMD           ; the rest: a pattern, if one is on this line
KCBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'case WORD in',0DH,0AH,0
        LBR     FATAL
; CNAMEQ: RA -> "?Cn" (n = the ifs open), R9.0 = 3
CNAMEQ: LOAD    RA, CNAME
        LDI     '?'
        STR     RA
        INC     RA
        LDI     'C'
        STR     RA
        INC     RA
        LOAD    R9, SIFSP
        LDN     R9
        ADI     '0'
        STR     RA
        LOAD    RA, CNAME
        LDI     3
        PLO     R9
        SEP     R5
; CASEQ: DF = 0 if the top if is a case waiting for a pattern
CASEQ:  LOAD    RD, SIFSP
        LDN     RD
        LBZ     CQNO
        SEP     R4
        DW      TOPP
        LDN     RD
        XRI     8
        LBNZ    CQNO
        SHR
        SEP     R5
CQNO:   LDI     1
        SHR
        SEP     R5
; CASEEND: ;; - the branch running is done (10); one that did not match: the next pattern (8)
CASEEND: LOAD   RD, SIFSP
        LDN     RD
        LBZ     CE9
        SEP     R4
        DW      TOPP
        LDN     RD
        XRI     9
        LBNZ    CE1
        LDI     10
        STR     RD
        SEP     R5
CE1:    XRI     9 XOR 11
        LBNZ    CE9
        LDI     8
        STR     RD
CE9:    SEP     R5
; CPAT: RF -> "pat|pat) commands": a pattern that matches the word runs the commands (9); none: 11
CPAT:   LDN     RF
        XRI     '('
        LBNZ    PT0
        INC     RF
PT0:    SEP     R4              ; R8 -> the word
        DW      CNAMEQ
        SEP     R4
        DW      VFIND
        LBNF    PT0A
        LOAD    R7, PTEMP
PT0A:   LOAD    RD, TA
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        LDI     11
        PHI     RB              ; RB.1 = the state it gets: 11 none matched yet
PT1:    LOAD    R7, WBUF        ; a pattern (quotes out) into WBUF
        LDI     0
        PLO     RB
PT2:    LDA     RF
        LBZ     PTBAD
        PLO     RC
        GLO     RB
        LBNZ    PTQ
        GLO     RC
        XRI     27H
        LBZ     PTO
        GLO     RC
        XRI     22H
        LBZ     PTO
        GLO     RC
        XRI     '|'
        LBZ     PT3
        GLO     RC
        XRI     ')'
        LBZ     PT3
        GLO     RC
        XRI     ' '
        LBZ     PT2
PTC:    GLO     RC
        STR     R7
        INC     R7
        LBR     PT2
PTO:    GLO     RC
        PLO     RB
        LBR     PT2
PTQ:    GLO     RC
        STR     R2
        GLO     RB
        XOR
        LBNZ    PTC
        PLO     RB
        LBR     PT2
PT3:    LDI     0
        STR     R7
        GLO     RC              ; (the character that ended it)
        STXD
        LOAD    R7, WBUF        ; does it match?
        LOAD    RD, TA
        LDA     RD
        PHI     R8
        LDN     RD
        PLO     R8
        SEP     R4
        DW      GMATCH
        LBDF    PT4
        LDI     9
        PHI     RB
PT4:    IRX
        LDX
        XRI     '|'
        LBZ     PT1
        SEP     R4              ; ')': the state; the rest of the command (the branch's first) runs if 9
        DW      TOPP
        GHI     RB
        STR     RD
        LBR     DOCMD
PTBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'case: a pattern needs its )',0DH,0AH,0
        LBR     FATAL
PTEMP:  DB      0
; esac: the case done with ($? 0 if no branch ran)
KESAC:  SEP     R4
        DW      TOPC
        PLO     RB
        SMI     8
        LBNF    KES2
        GLO     RB              ; (8, 11: none ran)
        XRI     8
        LBZ     KES0
        GLO     RB
        XRI     11
        LBNZ    KES1
KES0:   LOAD    RD, SSTAT
        LDI     0
        STR     RD
KES1:   SEP     R4              ; ?Cn unset
        DW      CNAMEQ
        SEP     R4
        DW      VFIND
        LBDF    KES2
        SEP     R4
        DW      VDEL
KES2:   LOAD    RD, SIFSP
        LDN     RD
        SMI     1
        STR     RD
        LBR     DOCMD
; IPUSH: a new if (or case) frame, state D (8 deep at most). IPUSHD: then the rest of the command.
IPUSHD: SEP     R4
        DW      IPUSH
        LBR     DOCMD
IPUSH:  PLO     RB
        LOAD    RD, SIFSP
        LDN     RD
        XRI     8
        LBNZ    IP1
        SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'if and case: more than 8 inside each other',0DH,0AH,0
        LBR     FATAL
IP1:    LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      TOPP
        GLO     RB
        STR     RD
        SEP     R5
; GMATCH: R7 -> a pattern, R8 -> a text (both 0-ended): DF = 0 if it matches (* any characters, ? one)
GMATCH: LDI     0
        PHI     RA              ; RA = after the last * (0: none yet), R9 = where the text was then
        PLO     RA
GM1:    LDN     R7
        XRI     '*'
        LBZ     GMSTAR
        LDN     R8
        LBNZ    GM2
GM1A:   LDN     R7              ; the text's end: only *s may be left
        LBZ     GMYES
        XRI     '*'
        LBNZ    GMBACK
        INC     R7
        LBR     GM1A
GM2:    LDN     R7
        LBZ     GMBACK
        XRI     '?'
        LBZ     GM3
        LDN     R7
        STR     R2
        LDN     R8
        XOR
        LBNZ    GMBACK
GM3:    INC     R7
        INC     R8
        LBR     GM1
GMSTAR: INC     R7
        GHI     R7
        PHI     RA
        GLO     R7
        PLO     RA
        GHI     R8
        PHI     R9
        GLO     R8
        PLO     R9
        LBR     GM1
GMBACK: GHI     RA              ; the last * takes one more character
        LBNZ    GMB1
        GLO     RA
        LBZ     GMNO
GMB1:   LDN     R9
        LBZ     GMNO
        INC     R9
        GHI     R9
        PHI     R8
        GLO     R9
        PLO     R8
        GHI     RA
        PHI     R7
        GLO     RA
        PLO     R7
        LBR     GM1
GMYES:  SHR
        SEP     R5
GMNO:   LDI     1
        SHR
        SEP     R5

; ---- functions: NAME() { ... }. Defining one keeps where its body starts (FNT) and skips the body (an if
;      frame, state 12, to its }); calling one: a call (CSB), $1 .. its words, the body; } or return: back.
FNDEF:  INC     RF              ; past "()", to "{"
        INC     RF
        SEP     R4
        DW      K_SKIPSP
        LDA     RF
        XRI     '{'
        LBNZ    FDBAD
        SEP     R4
        DW      ACTIVE
        LBDF    FD9             ; inside a skipped part: only its body skipped
        GLO     R9              ; 8 letters at most
        SMI     9
        LBDF    FDBAD
        SEP     R4              ; this name already: that entry; else a new one
        DW      FFIND0
        LBNF    FD2
        LOAD    RD, FNN
        LDN     RD
        XRI     FNMAX
        LBZ     FDFULL
        LDN     RD
        ADI     1
        STR     RD
        SMI     1               ; RD = FNT + 20 x (FNN - 1)
        SEP     R4
        DW      FNENT
FD2:    GHI     RD              ; RC = the entry
        PHI     RC
        GLO     RD
        PLO     RC
        LDI     8               ; the name, 0s after it
        PLO     RB
FD3:    GLO     R9
        LBZ     FD4
        LDA     RA
        STR     RC
        INC     RC
        DEC     R9
        DEC     RB
        LBR     FD3
FD4:    GLO     RB
        LBZ     FD5
        LDI     0
        STR     RC
        INC     RC
        DEC     RB
        LBR     FD4
FD5:    LOAD    RD, SFST        ; where the body starts: this line, after the {
        LDI     11
        PLO     RB
FD6:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    FD6
        GLO     RF
        STR     RC
FD9:    LDI     12              ; the body: skipped now
        LBR     IPUSHD
FDBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'NAME() { ... } - NAME of 8 letters at most',0DH,0AH,0
        LBR     FATAL
FDFULL: SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'more than 6 functions',0DH,0AH,0
        LBR     FATAL
; FNENT: RD = FNT + 20 x D
FNENT:  PLO     RB
        LOAD    RD, FNT
FE1:    GLO     RB
        LBZ     FE9
        GLO     RD
        ADI     20
        PLO     RD
        DEC     RB
        LBR     FE1
FE9:    SEP     R5
; FFIND: RF -> a word (0-ended, WBUF): DF = 0, RD -> its function. FFIND0: RA -> a name, R9.0 its length.
FFIND:  GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
        LDI     0
        PLO     R9
FF0:    LDA     RF
        LBZ     FFIND0
        INC     R9
        LBR     FF0
FFIND0: LDI     0
        PHI     R9              ; R9.1 = the entry
FF1:    LOAD    RD, FNN
        LDN     RD
        STR     R2
        GHI     R9
        SD
        LBNF    FFNO            ; (FNN - entry, a borrow: none left)
        LBZ     FFNO
        GHI     R9
        SEP     R4
        DW      FNENT
        GHI     RA              ; the same name? (8 at most: its next byte 0, or the 8th)
        PHI     RC
        GLO     RA
        PLO     RC
        GLO     R9
        SMI     9
        LBDF    FF4
        GLO     R9
        PLO     RB
FF2:    GLO     RB
        LBZ     FF3
        LDA     RC
        STR     R2
        LDA     RD
        XOR
        LBNZ    FF4
        DEC     RB
        LBR     FF2
FF3:    GLO     R9
        XRI     8
        LBZ     FFYES
        LDN     RD
        LBZ     FFYES
FF4:    GHI     R9
        ADI     1
        PHI     R9
        LBR     FF1
FFYES:  GHI     R9
        SEP     R4
        DW      FNENT
        SHR                     ; (D = an address's low byte, but DF: FNENT's ADI ... - so made 0)
        LDI     0
        SHR
        SEP     R5
FFNO:   LDI     1
        SHR
        SEP     R5
; CALLF: the function at RD, with the words after its name as $1 ..
CALLF:  GLO     RD
        STXD
        GHI     RD
        STXD
        SEP     R4              ; the place after the call
        DW      ADVANCE
        LDI     1
        SEP     R4
        DW      PUSHF
        SEP     R4
        DW      ARGSET
        IRX
        LDXA
        PHI     RD
        LDX
        PLO     RD
        LDI     8
        PLO     RB
CF1:    INC     RD
        DEC     RB
        GLO     RB
        LBNZ    CF1
        LBR     GOPOS
; } : a function's body defined (12): done; else the end of the function being run - back from it
KBRACE: SEP     R4
        DW      TOPC0
        XRI     12
        LBNZ    KBR1
        LOAD    RD, SIFSP
        LDN     RD
        SMI     1
        STR     RD
        LBR     DOCMD
KBR1:   SEP     R4              ; skipping (an if's other branch ...): nothing
        DW      ACTIVE
        LBDF    DCRET
        LDI     1               ; back from a function
        LBR     RETTO
; TOPC0: D = the top if's state, 0 if none
TOPC0:  LOAD    RD, SIFSP
        LDN     RD
        LBZ     TC09
        SEP     R4
        DW      TOPP
        LDN     RD
TC09:   SEP     R5
; return [n]: back from the function (or . file) being run, $? = n
B_RET:  LOAD    RD, ARGC
        LDN     RD
        SMI     2
        LBNF    BR9
        LOAD    RD, ARGV+2
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      ATOI
        LBDF    EXBAD
        LOAD    RD, SSTAT
        GLO     R8
        STR     RD
BR9:    LDI     2               ; (a function or a . file)
; RETTO: back from the innermost call of kind 1 (or 2 too, if D = 2); calls above it dropped. None: said.
RETTO:  PHI     RB
RT1:    LOAD    R9, CSN
        LDN     R9
        LBZ     RTNO
        SEP     R4
        DW      CSTOP           ; RA -> the top call, D = its kind
        XRI     3
        LBZ     RTNO            ; (a script run from this one: not past it)
        XRI     3
        STR     R2
        GHI     RB
        SM                      ; kind <= RB.1: this one
        LBDF    RT2
        SEP     R4              ; (a . file inside a function: dropped)
        DW      CSDROP
        LBR     RT1
RT2:    SEP     R4
        DW      POPF
        LBR     SHNEXT
RTNO:   SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'return or } outside a function',0DH,0AH,0
        LBR     FATAL
; . NAME: its lines run here, as if they were in this script; then on after the .
B_DOT:  LOAD    RD, ARGC
        LDN     RD
        SMI     2
        LBNF    BDBAD
        LOAD    RD, ARGV+2
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      FINDSH
        LBDF    BDNO
        SEP     R4
        DW      ADVANCE
        LDI     2
        SEP     R4
        DW      PUSHF
        SEP     R4
        DW      OPENSH
        LBR     SHNEXT
BDNO:   SEP     R4
        DW      EHEAD
        LOAD    RD, ARGV+2
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
BDN1:   LDA     RF
        LBZ     BDN2
        SEP     R4
        DW      K_OUT
        LBR     BDN1
BDN2:   SEP     R4
        DW      K_PIN
        DB      ' is not on the card',0DH,0AH,0
        LBR     ST1
BDBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      '. NAME',0DH,0AH,0
        LBR     ST2X
; FINDSH: RF -> a script's name (.SH if none): here, else the root, else /BIN (a name alone). DF = 0 found.
FINDSH: LOAD    RD, SNM
        SEP     R4
        DW      K_PARSE
        LBDF    FS9
        LOAD    RD, SNM+8
        LDN     RD
        XRI     ' '
        LBNZ    FS1
        LDI     'S'
        STR     RD
        INC     RD
        LDI     'H'
        STR     RD
FS1:    LOAD    RD, SNM
        SEP     R4
        DW      KS_FINDN
        LBNF    FS4
        LOAD    RD, KS_PPSL
        LDN     RD
        LBNZ    FS9
        LOAD    RD, KS_WDIR
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, SNM
        SEP     R4
        DW      KS_FINDN
        LBNF    FS4
        SEP     R4
        DW      KS_TOBIN
        LBDF    FS9
        LOAD    RD, SNM
        SEP     R4
        DW      KS_FINDN
        LBDF    FS9
FS4:    LOAD    RD, KS_DATTR    ; (a folder: no)
        LDN     RD
        ANI     10H
        LBNZ    FS9
        SHR
        SEP     R5
FS9:    LDI     1
        SHR
        SEP     R5
; OPENSH: the script FINDSH found, from its first line
OPENSH: SEP     R4
        DW      KS_FOPEN
        LOAD    RD, KS_FCLUS
        LOAD    RF, SFST
        SEP     R4
        DW      CP7
        LDI     0               ; SSOFF 0, line 1, from its start
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        LDI     1
        STR     RF
        LOAD    RD, SRES
        LDI     0
        STR     RD
        LOAD    RD, SCONN
        LDI     0
        STR     RD
        SEP     R5
; PUSHF: a call of kind D: where to go on after it (SFST SSOFF SLNO SRES as they are now), SCONN, LSP, SIFSP,
;        $# and $0-$9. No room: said, the script stops.
PUSHF:  STXD                    ; (the kind: ARGLEN uses RB)
        SEP     R4              ; RC.0 = the texts' length
        DW      ARGLEN
        IRX
        LDX
        PLO     RB
        LOAD    R9, CSN         ; room?
        LDN     R9
        ADI     29
        STR     R2
        GLO     RC
        ADD
        LBDF    PFFULL
        SMI     CSROOM + 1
        LBNF    PF1
PFFULL: SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'calls: too many inside each other',0DH,0AH,0
        LBR     FATAL
PF1:    LDN     R9              ; RA -> the new call
        ADI     LOW(CSB)
        PLO     RA
        LDI     HIGH(CSB)
        PHI     RA
        GLO     RB
        STR     RA
        INC     RA
        LOAD    R9, SFST        ; SFST SSOFF SLNO (11)
        LDI     11
        PLO     RB
PF2:    LDA     R9
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    PF2
        LOAD    R9, SRES
        LDN     R9
        STR     RA
        INC     RA
        LOAD    R9, SCONN
        LDN     R9
        STR     RA
        INC     RA
        LOAD    R9, LSP
        LDN     R9
        STR     RA
        INC     RA
        LOAD    R9, SIFSP
        LDN     R9
        STR     RA
        INC     RA
        LOAD    R9, SARGN       ; SARGN SARGO (11)
        LDI     11
        PLO     RB
PF3:    LDA     R9
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    PF3
        GLO     RC              ; n, the texts
        STR     RA
        INC     RA
        LOAD    R9, SARGT
PF4:    GLO     RC
        LBZ     PF5
        LDA     R9
        STR     RA
        INC     RA
        DEC     RC
        LBR     PF4
PF5:    LOAD    R9, CSN         ; its size, and CSN
        LDN     R9
        PLO     RB              ; (CSN before)
        GLO     RA
        SMI     LOW(CSN)        ; the size = RA + 1 - (CSB + CSN) (CSN = CSB - 1)
        STR     R2
        GLO     RB
        SD
        STR     RA
        STR     R2
        GLO     RB
        ADD
        STR     R9
        SEP     R5
; ARGLEN: RC.0 = the length of $0-$9's texts (to the end of the last one)
ARGLEN: LDI     0
        PLO     RC
        LOAD    R9, SARGO
        LDI     10
        PLO     RB
AL1:    LDA     R9
        LBZ     AL3
        PLO     RA
        LDI     HIGH(SARGT)
        PHI     RA
AL2:    LDA     RA
        LBNZ    AL2
        GLO     RA              ; its end + 1 - SARGT
        SMI     LOW(SARGT)
        STR     R2
        GLO     RC
        SD
        LBNF    AL3
        LDN     R2
        PLO     RC
AL3:    DEC     RB
        GLO     RB
        LBNZ    AL1
        SEP     R5
; ARGSET: $1 .. = ARGV's words after the first ($0 kept), $# their number
ARGSET: LOAD    RD, SARGO       ; R9 = after $0's text
        LDN     RD
        PLO     R9
        LDI     HIGH(SARGT)
        PHI     R9
AG1:    LDA     R9
        LBNZ    AG1
        LOAD    RD, SARGO+1     ; $1 .. $9: none
        LDI     9
        PLO     RB
AG2:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    AG2
        LOAD    RD, ARGC
        LDN     RD
        SMI     1
        PLO     RC              ; RC.0 = the words
        LDI     0
        PHI     RC              ; RC.1 = $n
        LOAD    RA, ARGV+2
AG3:    GLO     RC
        LBZ     AG9
        GHI     RC
        XRI     9
        LBZ     AG9
        GHI     R9              ; room left?
        XRI     HIGH(SARGE)
        LBZ     AG9
        GHI     RC
        ADI     1
        PHI     RC
        ADI     LOW(SARGO)
        PLO     RD
        LDI     HIGH(SARGO)
        PHI     RD
        GLO     R9
        STR     RD
        LDA     RA
        PHI     RF
        LDA     RA
        PLO     RF
AG4:    GLO     R9
        XRI     0FFH
        LBZ     AG5
        LDA     RF
        STR     R9
        INC     R9
        LBNZ    AG4
        LBR     AG6
AG5:    LDI     0
        STR     R9
        INC     R9
AG6:    DEC     RC
        LBR     AG3
AG9:    LOAD    RD, SARGN
        GHI     RC
        STR     RD
        SEP     R5
; CSTOP: RA -> the top call, D = its kind. CSDROP: the top call taken off (nothing restored).
CSTOP:  LOAD    R9, CSN
        LDN     R9
        ADI     LOW(CSN)        ; its last byte (the size) is at CSN + CSN's count
        PLO     R9
        LDN     R9
        STR     R2
        GLO     R9              ; RA = that + 1 - size
        ADI     1
        SM
        PLO     RA
        LDI     HIGH(CSB)
        PHI     RA
        LDN     RA
        SEP     R5
CSDROP: LOAD    R9, CSN
        LDN     R9
        ADI     LOW(CSN)
        PLO     R9
        LDN     R9
        STR     R2
        LDI     HIGH(CSN)
        PHI     R9
        LDI     LOW(CSN)
        PLO     R9
        LDN     R9
        SM
        STR     R9
        SEP     R5
; POPF: the top call taken off: where it went on, SCONN, LSP, SIFSP, $# $0-$9 as they were. D = its kind.
POPF:   SEP     R4
        DW      CSTOP
        PLO     RB
        GLO     RB
        STXD
        SEP     R4
        DW      CSDROP
        INC     RA              ; past the kind
        LOAD    R9, SFST
        LDI     11
        PLO     RC
PO1:    LDA     RA
        STR     R9
        INC     R9
        DEC     RC
        GLO     RC
        LBNZ    PO1
        LOAD    R9, SRES
        LDA     RA
        STR     R9
        LOAD    R9, SCONN
        LDA     RA
        STR     R9
        LOAD    R9, LSP
        LDA     RA
        STR     R9
        LOAD    R9, SIFSP
        LDA     RA
        STR     R9
        LOAD    R9, SARGN
        LDI     11
        PLO     RC
PO2:    LDA     RA
        STR     R9
        INC     R9
        DEC     RC
        GLO     RC
        LBNZ    PO2
        LDA     RA
        PLO     RC
        LOAD    R9, SARGT
PO3:    GLO     RC
        LBZ     PO4
        LDA     RA
        STR     R9
        INC     R9
        DEC     RC
        LBR     PO3
PO4:    IRX
        LDX
        SEP     R5
; GOPOS: on at the place at RD (12 bytes: SFST SSOFF SLNO, the offset in the line)
GOPOS:  LOAD    RF, SFST
        LDI     11
        SEP     R4
        DW      CPN
        LDN     RD
        PLO     RB
        LOAD    RD, SRES
        GLO     RB
        STR     RD
        LOAD    RD, SCONN
        LDI     0
        STR     RD
        LBR     SHNEXT

; TOPC: D = the top if's state (none: said, the script stops). TOPP: RD -> it.
TOPC:   LOAD    RD, SIFSP
        LDN     RD
        LBZ     TOPX
        SEP     R4
        DW      TOPP
        LDN     RD
        SEP     R5
TOPX:   SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'then, elif, else or fi without if',0DH,0AH,0
        LBR     FATAL
TOPP:   LOAD    RD, SIFSP
        LDN     RD
        ADI     LOW(SIFS - 1)
        PLO     RD
        LDI     HIGH(SIFS)
        PHI     RD
        SEP     R5
; ACTIVE: DF = 0 if commands run here (every if and loop open is at its condition or running: state 1 or 2);
;         DF = 1 skipping
ACTIVE: LOAD    RD, SIFSP
        LDN     RD
        PLO     RC
        LOAD    RD, SIFS
AC1:    GLO     RC
        LBZ     AC2
        LDA     RD
        XRI     9               ; (a case's branch running)
        LBZ     AC1A
        XRI     9
        SMI     3
        LBDF    ACNO
AC1A:   DEC     RC
        LBR     AC1
AC2:    LOAD    RD, LSP
        LDN     RD
        PLO     RC
        LOAD    RD, LFR+1
AC3:    GLO     RC
        LBZ     AC0
        LDN     RD
        SMI     3
        LBDF    ACNO
        GLO     RD
        ADI     16
        PLO     RD
        DEC     RC
        LBR     AC3
ACNO:   LDI     1
        SHR
        SEP     R5
AC0:    LDI     0
        SHR
        SEP     R5

; ---- WORDIS: RF -> a word (ending at a space or 0), RD -> a table of names in capitals (each 0-ended; a 0
;      ends it): D = which (1 ...), RF past the word; D = 0 none, RF kept. Any case matches.
WORDIS: LDI     0
        PLO     RC
WI1:    LDN     RD
        LBZ     WINO
        INC     RC
        GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
WI2:    LDN     RD
        LBZ     WI4
        LDN     RA
        SEP     R4
        DW      UPC
        STR     R2
        LDA     RD
        XOR
        LBNZ    WI3
        INC     RA
        LBR     WI2
WI3:    LDA     RD
        LBNZ    WI3
        LBR     WI1
WI4:    INC     RD              ; (past the name's 0)
        LDN     RA
        LBZ     WIYES
        XRI     ' '
        LBNZ    WI1
WIYES:  GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        GLO     RC
        SEP     R5
WINO:   LDI     0
        SEP     R5
; UPC: D in capitals
UPC:    STR     R2
        SMI     'a'
        LBNF    UPC9
        SMI     26
        LBDF    UPC9
        LDN     R2
        ANI     0DFH
        SEP     R5
UPC9:   LDN     R2
        SEP     R5
; ISIDC: DF = 1 if D is a letter, a digit or '_'; ISIDS: a letter or '_'; ISDIG: a digit
ISIDC:  STR     R2
        SMI     '0'
        LBNF    ISN
        SMI     10
        LBNF    ISY
        LDN     R2
ISIDS:  STR     R2
        XRI     '_'
        LBZ     ISY
        LDN     R2
        ANI     0DFH
        SMI     'A'
        LBNF    ISN
        SMI     26
        LBNF    ISY
ISN:    LDI     0
        SHR
        SEP     R5
ISY:    LDI     1
        SHR
        SEP     R5
ISDIG:  SMI     '0'
        LBNF    ISN
        SMI     10
        LBNF    ISY
        LBR     ISN

; ---- EXPAND: RF -> a command -> LINE (255 characters at most, 0-ended): $NAME ${NAME} $0-$9 $# $? replaced,
;      except inside '...'. The quotes stay (a program sees them as typed).
EXPAND: LOAD    RD, KS_LINE
        LDI     0
        PLO     RB              ; RB.0 = the quote it is in
EX1:    LDA     RF
        LBZ     EXEND
        PLO     RC
        GLO     RB
        XRI     27H
        LBZ     EXSQ
        GLO     RC
        XRI     '$'
        LBZ     EXDOL
        GLO     RB
        LBNZ    EXINQ
        GLO     RC
        XRI     27H
        LBZ     EXOPEN
        GLO     RC
        XRI     22H
        LBNZ    EXPUT
EXOPEN: GLO     RC
        PLO     RB
        LBR     EXPUT
EXINQ:  GLO     RC
        XRI     22H
        LBNZ    EXPUT
EXCL:   LDI     0
        PLO     RB
        LBR     EXPUT
EXSQ:   GLO     RC
        XRI     27H
        LBZ     EXCL
EXPUT:  GLO     RC
        SEP     R4
        DW      PUTC
        LBR     EX1
EXEND:  LDI     0
        STR     RD
        SEP     R5
EXDOL:  LDN     RF              ; what follows the '$'
        XRI     '('             ; $((: arithmetic
        LBNZ    EXDL1
        INC     RF
        LDN     RF
        DEC     RF
        XRI     '('
        LBZ     EXAR
        LBR     EXCMD
EXDL1:  LDN     RF
        XRI     '?'
        LBZ     EXQM
        LDN     RF
        XRI     '#'
        LBZ     EXNUM
        LDN     RF
        XRI     '{'
        LBZ     EXBR
        LDN     RF
        SEP     R4
        DW      ISDIG
        LBDF    EXARG
        LDN     RF
        SEP     R4
        DW      ISIDS
        LBDF    EXVAR
        LBR     EXPUT           ; a '$' alone
EXQM:   INC     RF
        LOAD    R7, SSTAT
        LBR     EXN1
EXNUM:  INC     RF
        LOAD    R7, SARGN
EXN1:   LDN     R7
        PLO     R8
        LDI     0
        PHI     R8
        SEP     R4
        DW      PUTDEC
        LBR     EX1
EXARG:  LDA     RF              ; $0 .. $9
        SMI     '0'
        ADI     LOW(SARGO)
        PLO     R7
        LDI     HIGH(SARGO)
        PHI     R7
        LDN     R7
        LBZ     EX1             ; not given: nothing
        PLO     R7
        LDI     HIGH(SARGT)
        PHI     R7
        LBR     EXCPY
EXBR:   INC     RF              ; ${NAME}, ${NAME:-default}, ${NAME:=default} (= sets it too)
        SEP     R4
        DW      VNAME
        LDN     RF
        XRI     ':'
        LBZ     EXBC
        LDN     RF
        XRI     '}'
        LBNZ    EXB1
        INC     RF
EXB1:   LBR     EXV1
EXBC:   INC     RF
        LDA     RF              ; RB.1 = '-' or '='
        PHI     RB
        SEP     R4              ; set, and not empty: it (the default passed over)
        DW      VFIND
        LBDF    EXBD
        LDN     R7
        LBZ     EXBD
EXBS:   LDA     RF
        LBZ     EXBS9
        XRI     '}'
        LBNZ    EXBS
        LBR     EXCPY
EXBS9:  DEC     RF
        LBR     EXCPY
EXBD:   GLO     RA              ; the default: out, and into WBUF (for =)
        STXD
        GHI     RA
        STXD
        GLO     R9
        STXD
        LOAD    R7, WBUF
EXBD1:  LDA     RF
        LBZ     EXBD2A
        XRI     '}'
        LBZ     EXBD2
        XRI     '}'
        STR     R7
        INC     R7
        SEP     R4
        DW      PUTC
        LBR     EXBD1
EXBD2A: DEC     RF
EXBD2:  LDI     0
        STR     R7
        IRX
        LDXA
        PLO     R9
        LDXA
        PHI     RA
        LDX
        PLO     RA
        GHI     RB
        XRI     '='
        LBNZ    EX1
        GLO     RF              ; ${NAME:=default}: NAME = it
        STXD
        GHI     RF
        STXD
        GLO     RD
        STXD
        GHI     RD
        STXD
        GLO     RB
        STXD
        LOAD    RF, WBUF
        SEP     R4
        DW      VSET
        IRX
        LDXA
        PLO     RB
        LDXA
        PHI     RD
        LDXA
        PLO     RD
        LDXA
        PHI     RF
        LDX
        PLO     RF
        LBR     EX1
; ---- $(command): the command runs first (an outside one, its output into /_SHOUT.TMP), then this command is
;      done again from its start with the file's text here (lines joined by spaces; the file deleted). One a
;      command.
EXCMD:  INC     RF
        LOAD    R7, CAPN
        LDN     R7
        ADI     1
        STR     R7
        SMI     2
        LBDF    EXCBAD
        LOAD    R7, SCAP
        LDN     R7
        LBNZ    EXSUB
        LOAD    R7, WBUF        ; the command, to its ) (outside quotes), into WBUF
        LDI     0
        PLO     RC
EC1:    LDA     RF
        LBZ     EXCBAD
        PLO     R8
        GLO     RC
        LBNZ    ECQ
        GLO     R8
        XRI     ')'
        LBZ     EC3
        GLO     R8
        XRI     27H
        LBZ     ECO
        GLO     R8
        XRI     22H
        LBNZ    ECC
ECO:    GLO     R8
        PLO     RC
ECC:    GLO     R8
        STR     R7
        INC     R7
        LBR     EC1
ECQ:    GLO     R8
        STR     R2
        GLO     RC
        XOR
        LBNZ    ECC
        PLO     RC
        LBR     ECC
EC3:    LDI     0
        STR     R7
        LOAD    RF, WBUF        ; LINE = it, its $ replaced, then " > /_SHOUT.TMP"
        SEP     R4
        DW      EXPAND
        LOAD    RF, SHOUTR
EC4:    LDA     RF
        STR     RD
        INC     RD
        LBNZ    EC4
        LOAD    RD, SCAP
        LDI     1
        STR     RD
        LOAD    RD, CMDP+1      ; then this command again, joined to the one before as it was
        LDN     RD
        PLO     RB
        LOAD    RD, SRES
        GLO     RB
        STR     RD
        LOAD    RD, PREVC
        LDN     RD
        PLO     RB
        LOAD    RD, SCONN
        GLO     RB
        STR     RD
        LBR     XEXEC
EXCBAD: SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      '$(...): one a command, with its )',0DH,0AH,0
        LBR     FATAL
SHOUTR: DB      ' > /_SHOUT.TMP',0
SHOUTN: DB      '_SHOUT  TMP'
EXSUB:  LDI     0               ; the command has run: past its ) ...
        PLO     RC
ES1:    LDA     RF
        LBZ     ES1Z
        PLO     R8
        GLO     RC
        LBNZ    ES1Q
        GLO     R8
        XRI     ')'
        LBZ     ES2
        GLO     R8
        XRI     27H
        LBZ     ES1O
        GLO     R8
        XRI     22H
        LBNZ    ES1
ES1O:   GLO     R8
        PLO     RC
        LBR     ES1
ES1Q:   GLO     R8
        STR     R2
        GLO     RC
        XOR
        LBNZ    ES1
        PLO     RC
        LBR     ES1
ES1Z:   DEC     RF
ES2:    LOAD    R7, OUTP        ; ... and its output here
        GHI     RD
        STR     R7
        INC     R7
        GLO     RD
        STR     R7
        GLO     RF
        STXD
        GHI     RF
        STXD
        GLO     RB
        STXD
        LOAD    RD, SPF
        LDI     0
        STR     RD
        GLO     RB              ; NAME=$(...) outside quotes: in quotes (SPF bit 2), not split as words
        LBNZ    ES2A
        LOAD    R7, OUTP
        LDA     R7
        PHI     RD
        LDN     R7
        PLO     RD
        LDI     0
        STR     RD
        SEP     R4
        DW      ISASG
        LBDF    ES2A
        LDI     22H
        SEP     R4
        DW      OUTC
        LOAD    RD, SPF
        LDI     4
        STR     RD
ES2A:   LOAD    RD, KS_WDIR
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, SHOUTN
        SEP     R4
        DW      KS_FINDN
        LBDF    ES9
        SEP     R4
        DW      KS_FOPEN
ES3:    SEP     R4
        DW      KS_FREAD
        LBDF    ES8
        LOAD    R9, KS_DATBUF
ES4:    GHI     RC
        LBNZ    ES4A
        GLO     RC
        LBZ     ES3
ES4A:   DEC     RC
        LDA     R9
        PLO     RA
        XRI     0DH
        LBZ     ES4
        GLO     RA
        XRI     0AH
        LBZ     ES5
        GLO     RA
        XRI     09H
        LBZ     ES5
        GLO     RA
        XRI     ' '
        LBZ     ES5
        LOAD    R7, SPF         ; a character: the space owed first
        LDN     R7
        ANI     1
        LBZ     ES4B
        LDI     ' '
        SEP     R4
        DW      OUTC
ES4B:   LOAD    R7, SPF         ; (something put; the space owed paid)
        LDN     R7
        ANI     4
        ORI     2
        STR     R7
        GLO     RA
        SEP     R4
        DW      OUTC
        LBR     ES4
ES5:    LOAD    R7, SPF         ; a space or line end: one space owed, if something came before
        LDN     R7
        ANI     2
        LBZ     ES4
        LDN     R7
        ORI     1
        STR     R7
        LBR     ES4
ES8:    LOAD    RD, KS_WDIR     ; the file deleted
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, SHOUTN
        SEP     R4
        DW      KS_FINDN
        LBDF    ES9
        SEP     R4
        DW      KS_DELENT
ES9:    LOAD    RD, SPF         ; (in quotes: closed)
        LDN     RD
        ANI     4
        LBZ     ES9A
        LDI     22H
        SEP     R4
        DW      OUTC
ES9A:   LOAD    RD, BUFOK       ; (DATBUF: the file's)
        LDI     0
        STR     RD
        LOAD    RD, SCAP
        LDI     0
        STR     RD
        IRX
        LDXA
        PLO     RB
        LDXA
        PHI     RF
        LDX
        PLO     RF
        LOAD    R7, OUTP
        LDA     R7
        PHI     RD
        LDN     R7
        PLO     RD
        LBR     EX1
; OUTC: D to LINE at OUTP (PUTC). Uses R8.
OUTC:   STXD
        LOAD    R8, OUTP
        LDA     R8
        PHI     RD
        LDN     R8
        PLO     RD
        IRX
        LDX
        SEP     R4
        DW      PUTC
        LOAD    R8, OUTP
        GHI     RD
        STR     R8
        INC     R8
        GLO     RD
        STR     R8
        SEP     R5
; ---- $((...)): whole numbers, 16 bits (-32768 .. 32767): + - * / % ( ), - ! before, < <= > >= == !=;
;      NAME or $NAME is its value (0 if not set or not a number), $1 .. $9 $# $? too
EXAR:   INC     RF
        INC     RF
        GLO     RB
        STXD
        GLO     RD
        STXD
        GHI     RD
        STXD
        SEP     R4
        DW      AEXPR
        SEP     R4
        DW      ASKIP
        LDA     RF
        XRI     ')'
        LBNZ    AXBAD
        LDA     RF
        XRI     ')'
        LBNZ    AXBAD
        IRX
        LDXA
        PHI     RD
        LDXA
        PLO     RD
        LDX
        PLO     RB
        GHI     R8              ; negative: '-' and the size
        ANI     80H
        LBZ     EXAR1
        LDI     '-'
        SEP     R4
        DW      PUTC
        SEP     R4
        DW      NEG8
EXAR1:  SEP     R4
        DW      PUTDEC
        LBR     EX1
AXBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      '$((...)) not understood',0DH,0AH,0
        LBR     FATAL
ASKIP:  LDN     RF
        XRI     ' '
        LBNZ    AS9
        INC     RF
        LBR     ASKIP
AS9:    SEP     R5
; AEXPR: a sum, or two compared (1 true, 0 false) -> R8
AEXPR:  SEP     R4
        DW      AADD
        SEP     R4
        DW      ASKIP
        LDA     RF
        XRI     '<'
        LBZ     AELT
        XRI     '<' XOR '>'
        LBZ     AEGT
        XRI     '>' XOR '='
        LBZ     AEEQ
        XRI     '=' XOR '!'
        LBZ     AENE
AE0:    DEC     RF
        SEP     R5
AELT:   LDN     RF
        XRI     '='
        LBNZ    AELT1
        INC     RF
        LDI     6               ; <=
        LBR     AECMP
AELT1:  LDI     4               ; <
        LBR     AECMP
AEGT:   LDN     RF
        XRI     '='
        LBNZ    AEGT1
        INC     RF
        LDI     3               ; >=
        LBR     AECMP
AEGT1:  LDI     1               ; >
        LBR     AECMP
AEEQ:   LDA     RF
        XRI     '='
        LBNZ    AXBAD
        LDI     2               ; ==
        LBR     AECMP
AENE:   LDN     RF
        XRI     '='
        LBNZ    AE0
        INC     RF
        LDI     5               ; !=
AECMP:  STXD                    ; what is true: 4 less, 2 equal, 1 more
        GLO     R8
        STXD
        GHI     R8
        STXD
        SEP     R4
        DW      AADD
        IRX
        LDXA
        XRI     80H             ; (the signs turned round: then they compare as unsigned)
        PHI     R7
        LDXA
        PLO     R7
        LDN     R2              ; RA.0 = what is true (R2 is back where it was: the byte is free now)
        PLO     RA
        GHI     R8
        XRI     80H
        PHI     R8
        GLO     R8              ; R7 - R8
        STR     R2
        GLO     R7
        SM
        PLO     RC
        GHI     R8
        STR     R2
        GHI     R7
        SMB
        LBNF    AECL
        LBNZ    AECG
        GLO     RC
        LBNZ    AECG
        LDI     2
        LBR     AECR
AECL:   LDI     4
        LBR     AECR
AECG:   LDI     1
AECR:   STR     R2
        GLO     RA
        AND
        LBZ     AECF
        LDI     1
AECF:   PLO     R8
        LDI     0
        PHI     R8
        SEP     R5
; AADD: terms + and - -> R8
AADD:   SEP     R4
        DW      AMUL
AA1:    SEP     R4
        DW      ASKIP
        LDN     RF
        XRI     '+'
        LBZ     AA2
        LDN     RF
        XRI     '-'
        LBNZ    AA9
AA2:    LDA     RF
        STXD
        GLO     R8
        STXD
        GHI     R8
        STXD
        SEP     R4
        DW      AMUL
        IRX
        LDXA
        PHI     R7
        LDXA
        PLO     R7
        LDX
        XRI     '+'
        LBNZ    AA3
        GLO     R8
        STR     R2
        GLO     R7
        ADD
        PLO     R8
        GHI     R8
        STR     R2
        GHI     R7
        ADC
        PHI     R8
        LBR     AA1
AA3:    GLO     R8              ; R7 - R8
        STR     R2
        GLO     R7
        SM
        PLO     R8
        GHI     R8
        STR     R2
        GHI     R7
        SMB
        PHI     R8
        LBR     AA1
AA9:    SEP     R5
; AMUL: factors * / % -> R8
AMUL:   SEP     R4
        DW      AUN
AM1:    SEP     R4
        DW      ASKIP
        LDN     RF
        XRI     '*'
        LBZ     AM2
        LDN     RF
        XRI     '/'
        LBZ     AM2
        LDN     RF
        XRI     '%'
        LBNZ    AA9
AM2:    LDA     RF
        STXD
        GLO     R8
        STXD
        GHI     R8
        STXD
        SEP     R4
        DW      AUN
        IRX
        LDXA
        PHI     R7
        LDXA
        PLO     R7
        LDX
        XRI     '*'
        LBNZ    AM3
        SEP     R4
        DW      MUL16
        LBR     AM1
AM3:    XRI     '*' XOR '/'
        PLO     RB              ; RB.0 = 0: /, else %
        SEP     R4
        DW      DIVS            ; R8 = R7 / R8, R7 = the remainder
        GLO     RB
        LBZ     AM1
        GHI     R7
        PHI     R8
        GLO     R7
        PLO     R8
        LBR     AM1
; AUN: a number, a NAME, $..., ( ... ), or - ! + before one -> R8
AUN:    SEP     R4
        DW      ASKIP
        LDN     RF
        XRI     '-'
        LBNZ    AU1
        INC     RF
        SEP     R4
        DW      AUN
NEG8:   GLO     R8              ; (NEG8: R8 = - R8)
        SDI     0
        PLO     R8
        GHI     R8
        SDBI    0
        PHI     R8
        SEP     R5
AU1:    LDN     RF
        XRI     '!'
        LBNZ    AU2
        INC     RF
        SEP     R4
        DW      AUN
        GLO     R8
        STR     R2
        GHI     R8
        OR
        LDI     0
        LBNZ    AU1A
        LDI     1
AU1A:   PLO     R8
        LDI     0
        PHI     R8
        SEP     R5
AU2:    LDN     RF
        XRI     '+'
        LBNZ    AU3
        INC     RF
        LBR     AUN
AU3:    LDN     RF
        XRI     '('
        LBNZ    AU4
        INC     RF
        SEP     R4
        DW      AEXPR
        SEP     R4
        DW      ASKIP
        LDA     RF
        XRI     ')'
        LBNZ    AXBAD
        SEP     R5
AU4:    LDN     RF              ; $
        XRI     '$'
        LBNZ    AU5
        INC     RF
        LDN     RF
        XRI     '#'
        LBZ     AUNUM
        LDN     RF
        XRI     '?'
        LBZ     AUST
        LDN     RF
        SEP     R4
        DW      ISDIG
        LBNF    AU5
        LDA     RF              ; $0 .. $9
        SMI     '0'
        ADI     LOW(SARGO)
        PLO     R7
        LDI     HIGH(SARGO)
        PHI     R7
        LDN     R7
        LBZ     AUZERO
        PLO     RA
        LDI     HIGH(SARGT)
        PHI     RA
        LBR     AUTXT
AUNUM:  INC     RF
        LOAD    R7, SARGN
        LBR     AUB
AUST:   INC     RF
        LOAD    R7, SSTAT
AUB:    LDN     R7
        PLO     R8
        LDI     0
        PHI     R8
        SEP     R5
AU5:    LDN     RF              ; a number
        SEP     R4
        DW      ISDIG
        LBNF    AU6
        LOAD    R8, 0
AU5A:   LDN     RF
        SEP     R4
        DW      ISDIG
        LBNF    AA9
        LOAD    R7, 10
        SEP     R4
        DW      MUL16
        LDA     RF
        SMI     '0'
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        LBR     AU5A
AU6:    LDN     RF              ; a NAME: its value
        SEP     R4
        DW      ISIDS
        LBNF    AXBAD
        SEP     R4
        DW      VNAME
        SEP     R4
        DW      VFIND
        LBDF    AUZERO
        GHI     R7
        PHI     RA
        GLO     R7
        PLO     RA
AUTXT:  SEP     R4              ; RA -> a text: its number (0 if not one)
        DW      ATOI
        LBNF    AA9
AUZERO: LOAD    R8, 0
        SEP     R5
; MUL16: R8 = R7 x R8 (the low 16 bits). Uses RC, R9.
MUL16:  LDI     0
        PHI     RC
        PLO     RC
        LDI     16
        PLO     R9
MU1:    GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     R7
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        LBNF    MU2
        GLO     R8
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     R8
        STR     R2
        GHI     RC
        ADC
        PHI     RC
MU2:    DEC     R9
        GLO     R9
        LBNZ    MU1
        GHI     RC
        PHI     R8
        GLO     RC
        PLO     R8
        SEP     R5
; DIVS: R8 = R7 / R8, R7 = the remainder (both as sh: towards 0; the remainder has R7's sign). Uses RA, RB.1,
;       RC, R9. / 0: said, the script stops.
DIVS:   GHI     R8
        LBNZ    DV0
        GLO     R8
        LBNZ    DV0
        SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'divided by 0',0DH,0AH,0
        LBR     FATAL
DV0:    GHI     R7              ; RB.1: bit 7 the remainder's sign, bit 0 the quotient's
        ANI     80H
        PHI     RB
        LBZ     DV1
        GLO     R7
        SDI     0
        PLO     R7
        GHI     R7
        SDBI    0
        PHI     R7
DV1:    GHI     R8
        ANI     80H
        LBZ     DV2
        GLO     R8
        SDI     0
        PLO     R8
        GHI     R8
        SDBI    0
        PHI     R8
        GHI     RB
        XRI     1
        PHI     RB
DV2:    GHI     RB
        SHL
        LBNF    DV3
        GHI     RB
        XRI     1
        PHI     RB
DV3:    LDI     0               ; RC = the remainder, R7 -> the quotient
        PHI     RC
        PLO     RC
        LDI     16
        PLO     R9
DV4:    GLO     R7
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        GLO     RC
        SHLC
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     R8
        STR     R2
        GLO     RC
        SM
        PLO     RA
        GHI     R8
        STR     R2
        GHI     RC
        SMB
        LBNF    DV5
        PHI     RC
        GLO     RA
        PLO     RC
        INC     R7
DV5:    DEC     R9
        GLO     R9
        LBNZ    DV4
        GHI     RB              ; the quotient's sign
        ANI     1
        LBZ     DV6
        GLO     R7
        SDI     0
        PLO     R7
        GHI     R7
        SDBI    0
        PHI     R7
DV6:    GHI     RB              ; the remainder's
        ANI     80H
        LBZ     DV7
        GLO     RC
        SDI     0
        PLO     RC
        GHI     RC
        SDBI    0
        PHI     RC
DV7:    GHI     R7
        PHI     R8
        GLO     R7
        PLO     R8
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        SEP     R5
EXVAR:  SEP     R4
        DW      VNAME
EXV1:   SEP     R4
        DW      VFIND
        LBDF    EX1             ; not set: nothing
EXCPY:  LDA     R7
        LBZ     EX1
        SEP     R4
        DW      PUTC
        LBR     EXCPY
; VNAME: RF -> a name: RA = it, R9.0 = its length, RF past it
VNAME:  GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
        LDI     0
        PLO     R9
VN1:    LDN     RF
        SEP     R4
        DW      ISIDC
        LBNF    VN9
        INC     RF
        INC     R9
        LBR     VN1
VN9:    SEP     R5
; PUTC: D to RD (LINE), unless it is full
PUTC:   STXD
        GLO     RD
        XRI     0FFH
        IRX
        LBZ     PUTF
        LDX
        STR     RD
        INC     RD
PUTF:   SEP     R5
; PUTDEC: R8 in decimal, by PUTC. Uses R7, R9, RA, RC.
PUTDEC: LOAD    R7, DECT
        LDI     0
        PHI     R9
PD1:    LDA     R7
        PHI     RA
        LDA     R7
        PLO     RA
        LDI     0
        PLO     R9
PD2:    GLO     RA
        STR     R2
        GLO     R8
        SM
        PLO     RC
        GHI     RA
        STR     R2
        GHI     R8
        SMB
        LBNF    PD3
        PHI     R8
        GLO     RC
        PLO     R8
        INC     R9
        LBR     PD2
PD3:    GLO     R9
        LBNZ    PD4
        GHI     R9
        LBNZ    PD4
        GLO     RA
        XRI     1
        LBNZ    PD5
PD4:    LDI     1
        PHI     R9
        GLO     R9
        ADI     '0'
        SEP     R4
        DW      PUTC
PD5:    GLO     RA
        XRI     1
        LBNZ    PD1
        SEP     R5
DECT:   DW      10000, 1000, 100, 10, 1

; ---- the variables: "NAME=value",0 one after another from POOL; a 0 ends them.
; VFIND: RA -> a name, R9.0 its length: DF = 0: R7 -> its value, R8 -> its entry. DF = 1: not set.
VFIND:  LOAD    R8, POOL
VF1:    LDN     R8
        LBZ     VFNO
        GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
        GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        GLO     R9
        PHI     R9
VF2:    GHI     R9
        LBZ     VF3
        LDA     RC
        STR     R2
        LDA     R7
        XOR
        LBNZ    VF4
        GHI     R9
        SMI     1
        PHI     R9
        LBR     VF2
VF3:    LDA     R7
        XRI     '='
        LBZ     VFYES
VF4:    LDA     R8              ; the next entry
        LBNZ    VF4
        LBR     VF1
VFYES:  SHR                     ; (D = 0: DF = 0)
        SEP     R5
VFNO:   LDI     1
        SHR
        SEP     R5
; VDEL: the entry at R8 taken out (the rest moved down over it)
VDEL:   GHI     R8
        PHI     R7
        GLO     R8
        PLO     R7
VD1:    LDA     R7
        LBNZ    VD1
VD2:    GHI     R7
        XRI     HIGH(POOLE)
        LBZ     VD3
        LDA     R7
        STR     R8
        INC     R8
        LBR     VD2
VD3:    SEP     R5
; VSET: RA -> a name, R9.0 its length, RF -> its value (0-ended): set. DF = 1: no room (said).
VSET:   LOAD    RD, VALP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      VFIND
        LBDF    VS0
        SEP     R4
        DW      VDEL
VS0:    LOAD    R8, POOL        ; R8 = the end
VS1:    LDN     R8
        LBZ     VS2
VS1A:   LDA     R8
        LBNZ    VS1A
        LBR     VS1
VS2:    LOAD    RD, VALP        ; room? R8 + length + value + 3 must be $3000 or less
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GLO     R9
        ADI     3
        PLO     RC
        LDI     0
        PHI     RC
VS3:    LDA     RF
        LBZ     VS4
        INC     RC
        LBR     VS3
VS4:    GLO     RC
        STR     R2
        GLO     R8
        ADD
        PLO     RC
        GHI     RC
        STR     R2
        GHI     R8
        ADC
        PHI     RC
        GLO     RC              ; RC - $3001: a borrow if it fits
        SMI     LOW(POOLE + 1)
        GHI     RC
        SMBI    HIGH(POOLE + 1)
        LBDF    VSFULL
VS5:    GLO     R9              ; the name, '=', the value, 0, and the 0 that ends them
        LBZ     VS6
        LDA     RA
        STR     R8
        INC     R8
        DEC     R9
        LBR     VS5
VS6:    LDI     '='
        STR     R8
        INC     R8
        LOAD    RD, VALP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
VS7:    LDA     RF
        STR     R8
        INC     R8
        LBNZ    VS7
        STR     R8
        LDI     0
        SHR
        SEP     R5
VSFULL: SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'no room for more variables',0DH,0AH,0
        LDI     1
        SHR
        SEP     R5

; ISASG: DF = 0 if LINE starts NAME=
ISASG:  LOAD    RF, KS_LINE
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        SEP     R4
        DW      ISIDS
        LBNF    IA9
IA1:    INC     RF
        LDN     RF
        XRI     '='
        LBZ     IA8
        LDN     RF
        SEP     R4
        DW      ISIDC
        LBDF    IA1
IA9:    LDI     1
        SHR
        SEP     R5
IA8:    LDI     0
        SHR
        SEP     R5
; ASSIGN: NAME=value ... - each word one (anything else after them: said)
ASSIGN: SEP     R4
        DW      SPLIT
        LOAD    RD, ARGV
AS1:    LOAD    RF, ARGC
        LDN     RF
        LBZ     ST0
        SMI     1
        STR     RF
        LDA     RD
        PHI     RF
        LDA     RD
        PLO     RF
        GLO     RD
        STXD
        GHI     RD
        STXD
        LDN     RF              ; NAME=?
        SEP     R4
        DW      ISIDS
        LBNF    ASBAD
        SEP     R4
        DW      VNAME
        LDA     RF
        XRI     '='
        LBNZ    ASBAD
        SEP     R4
        DW      VSET
        IRX
        LDXA
        PHI     RD
        LDX
        PLO     RD
        LBDF    ST1
        LBR     AS1
ASBAD:  IRX
        IRX
        SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'only NAME=value words can follow NAME=value',0DH,0AH,0
        LBR     ST2X
; status: ST0 0, ST1 1, ST2X 2 - $? - and back
B_TRUE:
ST0:    LDI     0
        LSKP
B_FALSE:
ST1:    LDI     1
        LSKP
ST2X:   LDI     2
        PLO     RB
        LOAD    RD, SSTAT
        GLO     RB
        STR     RD
        SEP     R5

; ---- SPLIT: LINE -> its words in WBUF (quotes taken out), ARGV, ARGC. DF = 1: a '>' outside quotes.
SPLIT:  LOAD    RF, KS_LINE
        LOAD    RD, WBUF
        LOAD    R9, ARGV
        LDI     0
        PLO     RC
        PLO     RB
        PHI     RB
SP1:    LDN     RF
        LBZ     SPEND
        XRI     ' '
        LBNZ    SP2
        INC     RF
        LBR     SP1
SP2:    GLO     RC
        XRI     MAXW
        LBZ     SPEND
        GHI     RD
        STR     R9
        INC     R9
        GLO     RD
        STR     R9
        INC     R9
        INC     RC
SP3:    LDA     RF
        LBZ     SPW0
        PLO     RA
        GLO     RB
        LBNZ    SPQ
        GLO     RA
        XRI     ' '
        LBZ     SPW
        GLO     RA
        XRI     27H
        LBZ     SPO
        GLO     RA
        XRI     22H
        LBZ     SPO
        GLO     RA
        XRI     '>'
        LBNZ    SPC
        LDI     1
        PHI     RB
SPC:    GLO     RA
        STR     RD
        INC     RD
        LBR     SP3
SPO:    GLO     RA
        PLO     RB
        LBR     SP3
SPQ:    GLO     RA
        STR     R2
        GLO     RB
        XOR
        LBNZ    SPC
        PLO     RB
        LBR     SP3
SPW0:   DEC     RF
SPW:    LDI     0
        STR     RD
        INC     RD
        LBR     SP1
SPEND:  LOAD    R9, ARGC
        GLO     RC
        STR     R9
        GHI     RB
        SHR
        SEP     R5

; ---- echo [-n] words
B_ECHO: LOAD    R9, ARGV+2
        LOAD    RD, ARGC
        LDN     RD
        SMI     1
        PLO     RC              ; RC.0 = the words
        LDI     0
        PHI     RC              ; RC.1 = 1: -n
        PLO     RB              ; RB.0 = 1: a word before
        GLO     RC
        LBZ     BE5
        LDA     R9              ; -n?
        PHI     RA
        LDN     R9
        PLO     RA
        DEC     R9
        LDA     RA
        XRI     '-'
        LBNZ    BE2
        LDA     RA
        ANI     0DFH
        XRI     'N'
        LBNZ    BE2
        LDN     RA
        LBNZ    BE2
        LDI     1
        PHI     RC
        INC     R9
        INC     R9
        DEC     RC
BE2:    GLO     RC
        LBZ     BE5
        GLO     RB
        LBZ     BE3
        LDI     ' '
        SEP     R4
        DW      K_OUT
BE3:    LDI     1
        PLO     RB
        LDA     R9
        PHI     RA
        LDA     R9
        PLO     RA
BE4:    LDA     RA
        LBZ     BE4X
        SEP     R4
        DW      K_OUT
        LBR     BE4
BE4X:   DEC     RC
        LBR     BE2
BE5:    GHI     RC
        LBNZ    ST0
        SEP     R4
        DW      K_PCRLF
        LBR     ST0

; ---- exit [n]
B_EXIT: LOAD    RD, ARGC
        LDN     RD
        SMI     2
        LBNF    BEX0            ; no n: $?
        LOAD    RD, ARGV+2
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      ATOI
        LBDF    EXBAD
        LOAD    RD, SSTAT
        GLO     R8
        STR     RD
BEX0:   LOAD    R9, CSN         ; a script run from another: back to that one (calls above it dropped)
        LDN     R9
        LBZ     SHENDS
        SEP     R4
        DW      CSTOP
        XRI     3
        LBZ     BEX1
        SEP     R4
        DW      CSDROP
        LBR     BEX0
BEX1:   SEP     R4
        DW      POPF
        LBR     SHNEXT
EXBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'exit: a number, please',0DH,0AH,0
        LBR     FATAL

; ---- set: the variables; set -x / set +x
B_SET:  LOAD    RD, ARGC
        LDN     RD
        SMI     1
        LBNZ    BS3
        LOAD    R8, POOL
BS1:    LDN     R8
        LBZ     ST0
        XRI     '?'             ; (a case's word: not shown)
        LBNZ    BS2
BS1A:   LDA     R8
        LBNZ    BS1A
        LBR     BS1
BS2:    LDA     R8
        LBZ     BS2X
        SEP     R4
        DW      K_OUT
        LBR     BS2
BS2X:   SEP     R4
        DW      K_PCRLF
        LBR     BS1
BS3:    LOAD    RD, ARGV+2      ; (one word: -x or +x)
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDA     RA
        PLO     RB
        LDA     RA              ; RB.1 = the flag's bit: x 1, e 2
        ANI     0DFH
        XRI     'X'
        LBZ     BS3X
        XRI     'X' XOR 'E'
        LBNZ    BSBAD
        LDI     2
        LSKP
BS3X:   LDI     1
        PHI     RB
        LDN     RA
        LBNZ    BSBAD
        LOAD    RD, SFLAGS
        GLO     RB
        XRI     '-'
        LBZ     BS4
        GLO     RB
        XRI     '+'
        LBNZ    BSBAD
        GHI     RB
        XRI     0FFH
        STR     R2
        LDN     RD
        AND
        STR     RD
        LBR     ST0
BS4:    GHI     RB
        STR     R2
        LDN     RD
        OR
        STR     RD
        LBR     ST0
BSBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'set: only set, set -x +x -e +e',0DH,0AH,0
        LBR     ST2X

; ---- unset NAME ...
B_UNSET: LOAD   R9, ARGV+2
        LOAD    RD, ARGC
        LDN     RD
        PLO     RC
BU1:    DEC     RC
        GLO     RC
        LBZ     ST0
        LDA     R9
        PHI     RF
        LDA     R9
        PLO     RF
        GLO     R9
        STXD
        GHI     R9
        STXD
        GLO     RC
        STXD
        SEP     R4
        DW      VNAME
        SEP     R4
        DW      VFIND
        LBDF    BU2
        SEP     R4
        DW      VDEL
BU2:    IRX
        LDXA
        PLO     RC
        LDXA
        PHI     R9
        LDX
        PLO     R9
        LBR     BU1

; ---- read [-p prompt] NAME: a line typed (Backspace works; Ctrl-C stops the script) -> $NAME
B_READ: LOAD    R9, ARGV+2
        LOAD    RD, ARGC
        LDN     RD
        SMI     1
        PLO     RC
        SMI     2               ; -p prompt NAME?
        LBNF    BR2
        SEP     R4
        DW      ARGR9
        LDA     RA
        XRI     '-'
        LBNZ    BR2
        LDA     RA
        ANI     0DFH
        XRI     'P'
        LBNZ    BR2
        LDN     RA
        LBNZ    BR2
        INC     R9
        INC     R9
        SEP     R4
        DW      ARGR9
BR1:    LDA     RA              ; the prompt
        LBZ     BR1X
        SEP     R4
        DW      K_TTY
        LBR     BR1
BR1X:   INC     R9
        INC     R9
        DEC     RC
        DEC     RC
BR2:    GLO     RC
        LBZ     BRBAD
        SEP     R4              ; TA = the name
        DW      ARGR9
        LDN     RA
        SEP     R4
        DW      ISIDS
        LBNF    BRBAD
        LOAD    RD, TA
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RF, KS_LINE     ; the line, into LINE
        LDI     0
        PLO     RB
BR3:    LOAD    RD, SKEY        ; one typed before (between lines)?
        LDN     RD
        PLO     RC
        LDI     0
        STR     RD
        GLO     RC
        LBNZ    BR3K
        LDI     15H             ; a key, from the UART itself (as the kernel's line editor: no BIOS echo)
        STR     R2
        OUT     SELPORT
        DEC     R2
BR3W:   INP     DATPORT
        ANI     01H
        LBZ     BR3W
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RC
BR3K:   GLO     RC
        XRI     0DH
        LBZ     BR6
        GLO     RC
        XRI     03H
        LBZ     STOPPED
        GLO     RC
        XRI     08H
        LBZ     BR4
        GLO     RC
        XRI     7FH
        LBZ     BR4
        GLO     RC
        SMI     20H
        LBNF    BR3
        GLO     RB
        XRI     200
        LBZ     BR3
        GLO     RC
        STR     RF
        INC     RF
        INC     RB
        SEP     R4
        DW      K_TTY
        LBR     BR3
BR4:    GLO     RB              ; Backspace
        LBZ     BR3
        DEC     RF
        DEC     RB
        LDI     08H
        SEP     R4
        DW      K_TTY
        LDI     ' '
        SEP     R4
        DW      K_TTY
        LDI     08H
        SEP     R4
        DW      K_TTY
        LBR     BR3
BR6:    LDI     0
        STR     RF
        LDI     0DH
        SEP     R4
        DW      K_TTY
        LDI     0AH
        SEP     R4
        DW      K_TTY
        LOAD    RD, TA          ; NAME = it
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      VNAME
        LOAD    RF, KS_LINE
        SEP     R4
        DW      VSET
        LBDF    ST1
        LBR     ST0
BRBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'read [-p prompt] NAME',0DH,0AH,0
        LBR     ST2X

; ---- shift [n]: $1 = $2 ... (n times)
B_SHIFT: LOAD   RD, ARGC
        LDN     RD
        SMI     2
        LDI     1
        LBNF    BSH0
        LOAD    RD, ARGV+2
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      ATOI
        LBDF    BSHBAD
        GLO     R8
BSH0:   PLO     RC              ; RC.0 = how many
BSH1:   GLO     RC
        LBZ     ST0
        DEC     RC
        LOAD    RD, SARGN
        LDN     RD
        LBZ     BSHNO
        SMI     1
        STR     RD
        LOAD    RD, SARGO+1     ; $1 = $2 ... $8 = $9, $9 none
        LDI     8
        PLO     RB
BSH2:   INC     RD
        LDN     RD
        DEC     RD
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    BSH2
        LDI     0
        STR     RD
        LBR     BSH1
BSHNO:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'shift: no more words',0DH,0AH,0
        LBR     ST1
BSHBAD: SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'shift: a number, please',0DH,0AH,0
        LBR     ST2X
; ---- sleep n: n seconds by the clock (no clock: about that, counted); Ctrl-C stops the script
B_SLEEP: LOAD   RD, ARGC
        LDN     RD
        SMI     2
        LBNF    BSLBAD
        LOAD    RD, ARGV+2
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      ATOI
        LBDF    BSLBAD
        GHI     R8
        ANI     80H
        LBNZ    BSLBAD
        LDI     8BH             ; a clock? (register B: $FF none)
        SEP     R4
        DW      KS_RTCRD
        XRI     0FFH
        LBZ     BSLC
        LDI     80H             ; R9.0 = the seconds now
        SEP     R4
        DW      KS_RTCRD
        PLO     R9
        INC     R8              ; (one tick more: the first may come at once - so n seconds at least)
BSL1:   GHI     R8              ; R8 seconds still to go
        LBNZ    BSL2
        GLO     R8
        LBZ     ST0
BSL2:   SEP     R4
        DW      KEYCHK
        LDI     80H
        SEP     R4
        DW      KS_RTCRD
        STR     R2
        GLO     R9
        XOR
        LBZ     BSL1
        LDN     R2              ; a second gone
        PLO     R9
        DEC     R8
        LBR     BSL1
BSLC:   GHI     R8              ; no clock: about 93,000 instructions a second
        LBNZ    BSLC1
        GLO     R8
        LBZ     ST0
BSLC1:  SEP     R4
        DW      KEYCHK
        LOAD    R7, 31000
BSLC2:  DEC     R7              ; (3 instructions a turn: about a second)
        GLO     R7
        LBNZ    BSLC2
        GHI     R7
        LBNZ    BSLC2
        DEC     R8
        LBR     BSLC
BSLBAD: SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'sleep: seconds, please',0DH,0AH,0
        LBR     ST2X
; ---- pause [text]: the text (or "Press a key to go on ..."), then a key; Ctrl-C stops the script
B_PAUSE: LOAD   RD, ARGC
        LDN     RD
        SMI     1
        LBNZ    BPA1
        SEP     R4
        DW      K_PIN
        DB      'Press a key to go on ... ',0
        LBR     BPA3
BPA1:   PLO     RC              ; the words, as echo's
        LOAD    R9, ARGV+2
        LDI     0
        PLO     RB
BPA2:   GLO     RC
        LBZ     BPA3
        GLO     RB
        LBZ     BPA2A
        LDI     ' '
        SEP     R4
        DW      K_TTY
BPA2A:  LDI     1
        PLO     RB
        LDA     R9
        PHI     RA
        LDA     R9
        PLO     RA
BPA2B:  LDA     RA
        LBZ     BPA2C
        SEP     R4
        DW      K_TTY
        LBR     BPA2B
BPA2C:  DEC     RC
        LBR     BPA2
BPA3:   LOAD    RD, SKEY        ; a key: one typed already, or the next
        LDN     RD
        PLO     RC
        LDI     0
        STR     RD
        GLO     RC
        LBNZ    BPA5
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
BPA4:   INP     DATPORT
        ANI     01H
        LBZ     BPA4
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
BPA5:   XRI     03H
        LBZ     STOPPED
        SEP     R4
        DW      K_PCRLF
        LBR     ST0
; KEYCHK: a key waiting? Ctrl-C or Esc stops the script; another is kept for read (SKEY). Registers kept.
KEYCHK: LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        LBZ     KC9
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        STXD                    ; (the key)
        XRI     03H
        LBZ     STOPPED
        XRI     03H XOR 1BH
        LBZ     STOPPED
        GLO     RD
        STXD
        GHI     RD
        STXD
        LOAD    RD, SKEY        ; SKEY = the key (under RD's two bytes)
        INC     R2
        INC     R2
        INC     R2
        LDN     R2
        STR     RD
        DEC     R2              ; RD back
        LDN     R2
        PLO     RD
        DEC     R2
        LDN     R2
        PHI     RD
        INC     R2
        INC     R2
KC9:    SEP     R5

; ---- test / [ ... ]: -z -n STRING; -e -f -d -s FILE; S1 = S2, S1 != S2; N1 -eq -ne -lt -le -gt -ge N2; ! first
;      turns it round. $? = 0 true, 1 false, 2 wrong (said).
B_TEST: LOAD    R9, ARGV
        LOAD    RD, ARGC
        LDN     RD
        SMI     1
        PLO     RC              ; RC.0 = the words after the name
        LDA     R9              ; '[': the last must be ']'
        PHI     RA
        LDA     R9
        PLO     RA
        LDN     RA
        XRI     '['
        LBNZ    BT0
        GLO     RC
        LBZ     BTNOB
        SHL                     ; ARGV + 2 x ARGC - 2: the last
        ADI     LOW(ARGV)
        PLO     RD
        LDI     HIGH(ARGV)
        PHI     RD
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDA     RA
        XRI     ']'
        LBNZ    BTNOB
        LDN     RA
        LBNZ    BTNOB
        DEC     RC
BT0:    LOAD    RD, NEGF
        LDI     0
        STR     RD
BT1:    GLO     RC              ; "!" before two or more
        SMI     2
        LBNF    BT2
        SEP     R4
        DW      ARGR9
        LDA     RA
        XRI     '!'
        LBNZ    BT2
        LDN     RA
        LBNZ    BT2
        LOAD    RD, NEGF
        LDN     RD
        XRI     1
        STR     RD
        INC     R9
        INC     R9
        DEC     RC
        LBR     BT1
BT2:    GLO     RC
        LBZ     BTF             ; nothing: false
        SMI     1
        LBNZ    BT3
        SEP     R4              ; one: true if not empty
        DW      ARGR9
        LDN     RA
        LBZ     BTF
        LBR     BTT
BT3:    SMI     1
        LBNZ    BT4
        SEP     R4              ; two: -z -n -e -f -d -s
        DW      ARGR9
        GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        LOAD    RD, T2TAB
        SEP     R4
        DW      WORDIS
        LBZ     BTBAD
        PLO     RB
        INC     R9
        INC     R9
        SEP     R4
        DW      ARGR9
        GLO     RB
        SMI     1
        LBZ     BTZ
        SMI     1
        LBZ     BTN
        LOAD    RD, TOP         ; a file: TOP = which
        GLO     RB
        STR     RD
        SEP     R4
        DW      FTEST           ; D: bit 0 there, bit 1 a folder, bit 2 not empty
        PLO     RB
        LOAD    RD, TOP
        LDN     RD
        SMI     3
        LBZ     BTE
        SMI     1
        LBZ     BTFI
        SMI     1
        LBZ     BTD
        GLO     RB              ; -s: a file, not empty
        ANI     6
        XRI     4
        LBZ     BTT
        LBR     BTF
BTE:    GLO     RB
        ANI     1
        LBNZ    BTT
        LBR     BTF
BTFI:   GLO     RB
        ANI     3
        XRI     1
        LBZ     BTT
        LBR     BTF
BTD:    GLO     RB
        ANI     2
        LBNZ    BTT
        LBR     BTF
BTZ:    LDN     RA
        LBZ     BTT
        LBR     BTF
BTN:    LDN     RA
        LBNZ    BTT
        LBR     BTF
BT4:    SMI     1
        LBNZ    BTBAD
        SEP     R4              ; three: A op B
        DW      ARGR9
        LOAD    RD, TA
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     R9
        INC     R9
        SEP     R4
        DW      ARGR9
        GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        INC     R9
        INC     R9
        SEP     R4
        DW      ARGR9
        LOAD    RD, TB
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, T3TAB
        SEP     R4
        DW      WORDIS
        LBZ     BTBAD
        ADI     LOW(T3MASK - 1) ; TOP = what is true: 4 less, 2 equal, 1 more
        PLO     RD
        LDI     HIGH(T3MASK)
        ADCI    0
        PHI     RD
        LDN     RD
        PLO     RB
        LOAD    RD, TOP
        GLO     RB
        STR     RD
        ANI     80H             ; texts (=, !=)?
        LBZ     BTNUM
        SEP     R4
        DW      LDTAB
BTS1:   LDA     RA
        STR     R2
        LDA     RB
        XOR
        LBNZ    BTS2
        DEC     RA
        LDA     RA
        LBNZ    BTS1
        LDI     2               ; the same
        LBR     BTREL
BTS2:   LDI     4               ; not
        LBR     BTREL
BTNUM:  SEP     R4
        DW      LDTAB
        GHI     RB
        STXD
        GLO     RB
        STXD
        SEP     R4
        DW      ATOI
        IRX
        LDXA
        PLO     RA
        LDX
        PHI     RA
        LBDF    BTNN
        GHI     R8              ; R9 = A (signs turned round: then they compare as unsigned)
        XRI     80H
        PHI     R9
        GLO     R8
        PLO     R9
        SEP     R4
        DW      ATOI
        LBDF    BTNN
        GHI     R8
        XRI     80H
        PHI     R8
        GLO     R8              ; A - B
        STR     R2
        GLO     R9
        SM
        PLO     RC
        GHI     R8
        STR     R2
        GHI     R9
        SMB
        LBNF    BTLT
        LBNZ    BTGT
        GLO     RC
        LBNZ    BTGT
        LDI     2
        LBR     BTREL
BTLT:   LDI     4
        LBR     BTREL
BTGT:   LDI     1
BTREL:  STR     R2
        LOAD    RD, TOP
        LDN     RD
        AND
        LBNZ    BTT
BTF:    LDI     1
        LSKP
BTT:    LDI     0
        STR     R2
        LOAD    RD, NEGF
        LDN     RD
        XOR
        PLO     RB
        LOAD    RD, SSTAT
        GLO     RB
        STR     RD
        SEP     R5
BTNN:   SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'test: a number, please',0DH,0AH,0
        LBR     ST2X
BTNOB:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      '[: no ] at the end',0DH,0AH,0
        LBR     ST2X
BTBAD:  SEP     R4
        DW      EHEAD
        SEP     R4
        DW      K_PIN
        DB      'test: not understood',0DH,0AH,0
        LBR     ST2X
; ARGR9: RA = the word R9 points at. LDTAB: RA = TA, RB = TB.
ARGR9:  LDA     R9
        PHI     RA
        LDN     R9
        PLO     RA
        DEC     R9
        SEP     R5
LDTAB:  LOAD    RD, TA
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        SEP     R5
T2TAB:  DB      '-Z',0,'-N',0,'-E',0,'-F',0,'-D',0,'-S',0,0
T3TAB:  DB      '=',0,'!=',0,'-EQ',0,'-NE',0,'-LT',0,'-LE',0,'-GT',0,'-GE',0,0
T3MASK: DB      82H, 85H, 2, 5, 4, 6, 1, 3      ; (80H: texts)
; ATOI: RA -> a whole number (- allowed), 0-ended -> R8. DF = 1: not one.
ATOI:   LOAD    R8, 0
        LDI     0
        PHI     RC              ; RC.1 = 1: negative
        LDN     RA
        XRI     '-'
        LBNZ    AT0
        INC     RA
        LDI     1
        PHI     RC
AT0:    LDN     RA
        LBZ     ATNO            ; no digits
AT1:    LDA     RA
        LBZ     AT9
        SMI     '0'
        LBNF    ATNO
        PLO     RC
        SMI     10
        LBDF    ATNO
        GLO     R8              ; R8 x 10 + the digit
        SHL
        PLO     R7
        GHI     R8
        SHLC
        PHI     R7              ; R7 = 2 x
        GLO     R7
        SHL
        PLO     R8
        GHI     R7
        SHLC
        PHI     R8
        GLO     R8
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8              ; R8 = 8 x
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
        GLO     RC
        STR     R2
        GLO     R8
        ADD
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        LBR     AT1
AT9:    GHI     RC
        LBZ     AT9A
        GLO     R8              ; 0 - R8
        SDI     0
        PLO     R8
        GHI     R8
        SDBI    0
        PHI     R8
AT9A:   LDI     0
        SHR
        SEP     R5
ATNO:   LDI     1
        SHR
        SEP     R5
; FTEST: RA -> a path: D = bit 0 it is there, bit 1 a folder, bit 2 a file with something in it
FTEST:  GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        LOAD    RD, SNM
        SEP     R4
        DW      K_PARSE
        LBNF    FT1
        XRI     3               ; a folder named ("/", "GAMES/")
        LBNZ    FT0
        LDI     3
        SEP     R5
FT0:    LDI     0
        SEP     R5
FT1:    LOAD    RD, SNM
        SEP     R4
        DW      KS_FINDN
        LBDF    FT0
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBZ     FT2
        LDI     3
        SEP     R5
FT2:    LOAD    RD, KS_DSIZE    ; the size: 0?
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
        LBZ     FT3
        LDI     5
        SEP     R5
FT3:    LDI     1
        SEP     R5

; ---- messages
; EHEAD: "NAME line N: " (on the screen)
EHEAD:  SEP     R4
        DW      K_TTYON
        SEP     R4
        DW      PNAME0
        SEP     R4
        DW      K_PIN
        DB      ' line ',0
        SEP     R4
        DW      PLNO
        SEP     R4
        DW      K_PIN
        DB      ': ',0
        SEP     R5
; PNAME0: $0. PLNO: the line's number.
PNAME0: LOAD    RD, SARGO
        LDN     RD
        PLO     RF
        LDI     HIGH(SARGT)
        PHI     RF
PN1:    LDA     RF
        LBZ     PN9
        SEP     R4
        DW      K_OUT
        LBR     PN1
PN9:    SEP     R5
PLNO:   LOAD    RF, SLNO
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      K_PDEC
        SEP     R5

STUBIMG: INCL   "out/shstub.inc"        ; the stub (shstub.asm), copied to $2E00
        DS      (8 - (($ - SHLO) MOD 8)) MOD 8  ; (the stub sums 8 bytes at a time)
PEND:
        END
