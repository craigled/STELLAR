; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cron.asm - CRON.PRG: jobs at set times, from the table /CRON.TAB.
;
;   CRON                the table: now, running or paused, each job with its number
;   CRON START          the table runs (its first line: CRON y)       CRON PAUSE (or STOP): CRON n
;   CRON ON n           job n runs (its own y)                        CRON OFF n: job n waits (n)
;   CRON RUN            cron mode: each job when its time comes; Esc (or Ctrl-C) goes back to the prompt
;   CRON -w [ddhhmm]    (cron mode's own step: waits for the next minute with a job - Esc: exit status 1 - and
;                       writes those jobs to /_CRONJOB.SH, L=ddhhmm first: the minute they were for)
;
; /CRON.TAB (lines end CR LF or LF; # starts a comment):
;   CRON y                                  y: the table runs, n: paused (no such line: it runs)
;   # run min hour day month weekday command
;   y    0   *    *   *     *       PLAY /MUSIC/CHIMES
;   y    30  7    *   *     1-5     MEMVERSE
;   n    */15 *   *   *     *       ECHO tick >> /TICK.TXT
; A field: * (any), n, n-m, a list of those (1,15,30), and /s after * or a range (every s-th from its start).
; min 0-59, hour 0-23, day 1-31, month 1-12, weekday 0-7 (0 and 7 = Sunday, 1 = Monday). As in Unix cron: when
; both the day and the weekday are given (not *), either one will do.
;
; CRON RUN writes /_CRONRUN.SH and runs it with SH:  L=0 / while CRON -w $L; do . /_CRONJOB.SH; done
; - SH runs each job as if typed and comes back. Minutes that pass while jobs run are not caught up.
;
; Memory: code from $3000 (below TAB); the table $5000-$67FF (6 KB at most); the jobs to run $6800-$6AFF;
; a line $6B00-$6BFF.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
TAB     EQU     5000H
TABMAX  EQU     1800H
JOB     EQU     6800H
JOBMAX  EQU     02F0H
LBUF    EQU     6B00H           ; (page-aligned: RF.0 is the offset in the line)
LMAX    EQU     250

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
        LBZ     LIST
        LOAD    RD, W_START
        SEP     R4
        DW      WORDEQ
        LBNF    DOSTRT
        LOAD    RD, W_PAUSE
        SEP     R4
        DW      WORDEQ
        LBNF    DOPAUS
        LOAD    RD, W_STOP
        SEP     R4
        DW      WORDEQ
        LBNF    DOPAUS
        LOAD    RD, W_ON
        SEP     R4
        DW      WORDEQ
        LBNF    DOON
        LOAD    RD, W_OFF
        SEP     R4
        DW      WORDEQ
        LBNF    DOOFF
        LOAD    RD, W_RUN
        SEP     R4
        DW      WORDEQ
        LBNF    DORUN
        LOAD    RD, W_W
        SEP     R4
        DW      WORDEQ
        LBNF    DOWAIT
USE:    SEP     R4
        DW      K_PIN
        DB      'Usage: CRON            the table (/CRON.TAB) and its jobs',0DH,0AH
        DB      '       CRON START      it runs        CRON PAUSE (or STOP): it waits',0DH,0AH
        DB      '       CRON ON n       job n runs     CRON OFF n: job n waits',0DH,0AH
        DB      '       CRON RUN        cron mode: each job at its time; Esc stops it',0DH,0AH
        DB      '       HELP CRON       how to write the table',0DH,0AH,0
FAIL:   LOAD    RD, K_STAT
        LDI     1
        STR     RD
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        LBR     FAIL
NOTAB:  SEP     R4
        DW      K_PIN
        DB      'No /CRON.TAB yet: CRON START makes one (then NANO /CRON.TAB) - HELP CRON shows how.',0DH,0AH,0
        LBR     FAIL

; ==== CRON: the table
LIST:   SEP     R4
        DW      LOADT
        LBDF    NOTAB
        SEP     R4
        DW      RTCGET
        LBDF    LI1
        SEP     R4
        DW      K_PIN
        DB      'Now:  ',0
        SEP     R4
        DW      PHM
        SEP     R4
        DW      K_PIN
        DB      '  ',0
        SEP     R4
        DW      PDATE
LI1:    SEP     R4
        DW      SCANH
        LOAD    RD, RUNNING
        LDN     RD
        LBZ     LI2
        SEP     R4
        DW      K_PIN
        DB      'Cron: on (CRON PAUSE stops it; CRON RUN starts cron mode)',0DH,0AH,0
        LBR     LI3
LI2:    SEP     R4
        DW      K_PIN
        DB      'Cron: paused (CRON START)',0DH,0AH,0
LI3:    SEP     R4
        DW      FIRST
        LOAD    RD, JNUM
        LDI     0
        STR     RD
LI4:    SEP     R4
        DW      NEXTL
        LBDF    LI9
        SEP     R4
        DW      CLASS
        XRI     2
        LBNZ    LI4
        LOAD    RD, JNUM        ; a job: its number, then the line as it is
        LDN     RD
        ADI     1
        STR     RD
        PLO     RD
        LDI     0
        PHI     RD
        GLO     RD
        SMI     10
        LBDF    LI5
        LDI     ' '
        SEP     R4
        DW      F_TYPE
LI5:    SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      '  ',0
        LOAD    RF, LBUF
        SEP     R4
        DW      KS_PSTR
        SEP     R4
        DW      FLAGRF          ; (PARSEJ cuts the line up: after it is shown)
        SEP     R4
        DW      PARSEJ
        LBNF    LI6
        SEP     R4
        DW      K_PIN
        DB      '   <- not understood',0
LI6:    SEP     R4
        DW      K_PCRLF
        LBR     LI4
LI9:    LOAD    RD, JNUM
        LDN     RD
        LBNZ    LI10
        SEP     R4
        DW      K_PIN
        DB      '(no jobs yet: NANO /CRON.TAB - HELP CRON)',0DH,0AH,0
LI10:   SEP     R5

; ==== CRON START / PAUSE: the CRON line's y or n (one made at the top if there is none)
DOSTRT: LDI     'y'
        LBR     DS0
DOPAUS: LDI     'n'
DS0:    PLO     R7              ; R7.0 = the flag (FLG too: SAVET's kernel calls may use R7)
        STR     R2
        LOAD    RD, FLG
        LDN     R2
        STR     RD
        LDN     RF
        LBNZ    USE
        SEP     R4
        DW      LOADT
        LBNF    DS1
        LOAD    RF, TEMPL       ; no table: a new one (a CRON line and the column names)
        LOAD    RD, TAB
DSN:    LDA     RF
        STR     RD
        INC     RD
        LBNZ    DSN
        DEC     RD
        LOAD    RF, TEND
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
DS1:    SEP     R4
        DW      FIRST
DS2:    SEP     R4
        DW      NEXTL
        LBDF    DS5             ; no CRON line
        SEP     R4
        DW      CLASS
        XRI     1
        LBNZ    DS2
        LOAD    RD, FLAGP       ; the CRON line: its flag
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDN     RA
        LBZ     DS5             ; ("CRON" alone: a whole new line, at the top)
        XRI     0DH
        LBZ     DS5
        XRI     0DH XOR 0AH
        LBZ     DS5
        LOAD    RD, FLG
        LDN     RD
        STR     RA
        LBR     DS7
DS5:    LOAD    RD, TEND        ; "CRON y" CR LF at the top: the rest 8 bytes up
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        INC     RA              ; RA = past the 0 at the end; RB = 8 further
        GLO     RA
        ADI     8
        PLO     RB
        GHI     RA
        ADCI    0
        PHI     RB
DS6:    DEC     RA
        DEC     RB
        LDN     RA
        STR     RB
        GLO     RA
        XRI     LOW(TAB)
        LBNZ    DS6
        GHI     RA
        XRI     HIGH(TAB)
        LBNZ    DS6
        LOAD    RD, TAB
        LDI     'C'
        STR     RD
        INC     RD
        LDI     'R'
        STR     RD
        INC     RD
        LDI     'O'
        STR     RD
        INC     RD
        LDI     'N'
        STR     RD
        INC     RD
        LDI     ' '
        STR     RD
        INC     RD
        LOAD    RC, FLG
        LDN     RC
        STR     RD
        INC     RD
        LDI     0DH
        STR     RD
        INC     RD
        LDI     0AH
        STR     RD
        LOAD    RD, TEND
        LDA     RD
        PHI     RA
        LDN     RD
        ADI     8
        STR     RD
        GHI     RA
        ADCI    0
        DEC     RD
        STR     RD
DS7:    SEP     R4
        DW      SAVET
        LBDF    FAIL
        LOAD    RD, FLG
        LDN     RD
        XRI     'y'
        LBNZ    DS8
        SEP     R4
        DW      K_PIN
        DB      'Cron is on: CRON RUN starts cron mode.',0DH,0AH,0
        SEP     R5
DS8:    SEP     R4
        DW      K_PIN
        DB      'Cron is paused (each job keeps its own y or n).',0DH,0AH,0
        SEP     R5

; ==== CRON ON n / OFF n: job n's own y or n
DOON:   LDI     'y'
        LBR     DO0
DOOFF:  LDI     'n'
DO0:    PLO     R7
        SEP     R4
        DW      NUM8
        LBDF    USE
        PHI     R7              ; R7.1 = n (NJ, FLG too)
        LBZ     USE
        STR     R2
        LOAD    RD, NJ
        LDN     R2
        STR     RD
        GLO     R7
        STR     R2
        LOAD    RD, FLG
        LDN     R2
        STR     RD
        SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBNZ    USE
        SEP     R4
        DW      LOADT
        LBDF    NOTAB
        SEP     R4
        DW      FIRST
        LOAD    RD, JNUM
        LDI     0
        STR     RD
DO1:    SEP     R4
        DW      NEXTL
        LBDF    DONO
        SEP     R4
        DW      CLASS
        XRI     2
        LBNZ    DO1
        LOAD    RD, JNUM
        LDN     RD
        ADI     1
        STR     RD
        STR     R2
        LOAD    RD, NJ
        LDN     RD
        XOR
        LBNZ    DO1
        LOAD    RD, FLAGP       ; job n: its first letter
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, FLG
        LDN     RD
        STR     RA
        SEP     R4
        DW      SAVET
        LBDF    FAIL
        SEP     R4
        DW      K_PIN
        DB      'Job ',0
        LOAD    RD, NJ
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        LOAD    RD, FLG
        LDN     RD
        XRI     'y'
        LBNZ    DO2
        SEP     R4
        DW      K_PIN
        DB      ' is on:  ',0
        LBR     DO3
DO2:    SEP     R4
        DW      K_PIN
        DB      ' is off: ',0
DO3:    LOAD    RD, FLAGP       ; the line as it is now
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
DO4:    LDN     RF
        LBZ     DO5
        XRI     0DH
        LBZ     DO5
        XRI     0DH XOR 0AH
        LBZ     DO5
        LDA     RF
        SEP     R4
        DW      F_TYPE
        LBR     DO4
DO5:    SEP     R4
        DW      K_PCRLF
        SEP     R4              ; (the table paused: say so)
        DW      SCANH
        LOAD    RD, RUNNING
        LDN     RD
        LBNZ    DO6
        SEP     R4
        DW      K_PIN
        DB      '(The table is paused: CRON START.)',0DH,0AH,0
DO6:    SEP     R5
DONO:   SEP     R4
        DW      K_PIN
        DB      'There is no job ',0
        LOAD    RD, NJ
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' - CRON lists them.',0DH,0AH,0
        LBR     FAIL

; ==== CRON RUN: /_CRONRUN.SH, then SH runs it (cron mode)
DORUN:  LDN     RF
        LBNZ    USE
        SEP     R4
        DW      LOADT
        LBDF    NOTAB
        SEP     R4
        DW      READY           ; on, with a job on, and a clock - else it said why
        LBDF    FAIL
        LOAD    RF, RUNNM
        LOAD    RA, RUNTXT
        LOAD    RC, RUNEND - RUNTXT
        SEP     R4
        DW      SAVEF
        LBDF    FAIL
        LOAD    RF, RUNCMD      ; the command line: SH _CRONRUN, as typed
        LOAD    RD, KS_LINE
DR1:    LDA     RF
        STR     RD
        INC     RD
        LBNZ    DR1
        LBR     K_EXEC

; ==== CRON -w [ddhhmm]: the next minute with a job -> /_CRONJOB.SH (exit 0); Esc or Ctrl-C: exit status 1
DOWAIT: LOAD    RD, LASTD       ; ddhhmm: the minute the last jobs were for (none: never the same)
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, LASTD
        SEP     R4
        DW      PAIR
        LBDF    DW1
        STR     RD
        INC     RD
        SEP     R4
        DW      PAIR
        LBDF    DW0
        STR     RD
        INC     RD
        SEP     R4
        DW      PAIR
        LBDF    DW0
        STR     RD
        LBR     DW1
DW0:    LOAD    RD, LASTD       ; (not all six: none)
        LDI     0FFH
        STR     RD
DW1:    SEP     R4
        DW      LOADT
        LBDF    NOTAB
        SEP     R4
        DW      READY
        LBDF    FAIL
        LOAD    RD, SEEND       ; SEEN = the minute done with: LAST's if it is now (its jobs ran), else none
        LDI     0FFH
        STR     RD
        LOAD    RD, LASTD
        LDN     RD
        XRI     0FFH
        LBNZ    DW2
        SEP     R4              ; the first time (L=0): what it is waiting for
        DW      K_PIN
        DB      'Cron mode: each job at its time. Esc stops it.',0DH,0AH,0
        LBR     WL
DW2:    SEP     R4
        DW      MKCUR
        LOAD    RD, LASTD
        LOAD    RF, CUR
        SEP     R4
        DW      SAMEM
        LBDF    WL
        LOAD    RD, LASTD
        LOAD    RF, SEEND
        LDI     3
        PLO     RC
DW3:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    DW3
WL:     LDI     15H             ; a key? (the UART's line status: bit 0)
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBNF    WL2
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     7FH
        XRI     1BH
        LBZ     WSTOP
        XRI     1BH XOR 03H
        LBZ     WSTOP
WL2:    SEP     R4
        DW      RTCGET
        LBDF    NOCLK
        SEP     R4
        DW      MKCUR
        LOAD    RD, SEEND       ; a new minute?
        LOAD    RF, CUR
        SEP     R4
        DW      SAMEM
        LBNF    WL
        LOAD    RD, SEEND
        LOAD    RF, CUR
        LDI     3
        PLO     RC
WL3:    LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    WL3
        SEP     R4              ; "hh:mm waiting", over itself each minute
        DW      K_PIN
        DB      0DH,0
        SEP     R4
        DW      PHM
        SEP     R4
        DW      K_PIN
        DB      '  waiting (Esc stops cron mode)',0
        SEP     R4
        DW      WDAY
        STR     R2
        LOAD    RD, WD
        LDN     R2
        STR     RD
        LOAD    RA, JOB         ; L=ddhhmm CR LF, then each job's command
        LDI     'L'
        STR     RA
        INC     RA
        LDI     '='
        STR     RA
        INC     RA
        LOAD    RD, DAY
        LDN     RD
        SEP     R4
        DW      TO2
        LOAD    RD, HOUR
        LDN     RD
        SEP     R4
        DW      TO2
        LOAD    RD, MIN
        LDN     RD
        SEP     R4
        DW      TO2
        LDI     0DH
        STR     RA
        INC     RA
        LDI     0AH
        STR     RA
        INC     RA
        LOAD    RD, JP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, JNUM        ; (here: the jobs due)
        LDI     0
        STR     RD
        LOAD    RD, RUNNING
        LDN     RD
        LBZ     WL
        SEP     R4
        DW      FIRST
WJ1:    SEP     R4
        DW      NEXTL
        LBDF    WJ9
        SEP     R4
        DW      CLASS
        XRI     2
        LBNZ    WJ1
        SEP     R4
        DW      FLAGRF
        SEP     R4
        DW      PARSEJ
        LBDF    WJ1
        LOAD    RD, JFLAG
        LDN     RD
        LBZ     WJ1
        SEP     R4
        DW      MATCHJ
        LBDF    WJ1
        LOAD    RD, JNUM        ; due: its command into the jobs, and on the screen
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      K_PCRLF
        SEP     R4
        DW      PHM
        SEP     R4
        DW      K_PIN
        DB      '  ',0
        LOAD    RD, CMDP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      KS_PSTR
        LOAD    RD, CMDP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, JP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
WJ2:    GHI     RA              ; (room: past JOB + JOBMAX, the rest are left for the next minute)
        XRI     HIGH(JOB + JOBMAX)
        LBZ     WJ1
        LDA     RF
        LBZ     WJ3
        STR     RA
        INC     RA
        LBR     WJ2
WJ3:    LDI     0DH
        STR     RA
        INC     RA
        LDI     0AH
        STR     RA
        INC     RA
        LOAD    RD, JP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LBR     WJ1
WJ9:    LOAD    RD, JNUM
        LDN     RD
        LBZ     WL
        SEP     R4
        DW      K_PCRLF
        LOAD    RD, JP          ; /_CRONJOB.SH: the jobs
        LDA     RD
        PHI     RC
        LDN     RD
        SMI     LOW(JOB)
        PLO     RC
        GHI     RC
        SMBI    HIGH(JOB)
        PHI     RC
        LOAD    RF, JOBNM
        LOAD    RA, JOB
        SEP     R4
        DW      SAVEF
        LBDF    FAIL
        SEP     R5
WSTOP:  SEP     R4
        DW      K_PIN
        DB      0DH,0AH,'Cron mode stopped.',0DH,0AH,0
        LBR     FAIL
NOCLK:  SEP     R4
        DW      K_PIN
        DB      'Cron needs the clock (a DS12887 on the Disk/UART/RTC card).',0DH,0AH,0
        LBR     FAIL

; READY: DF = 0 if the table is on, has a job on, and the clock answers; else it says why, DF = 1
READY:  SEP     R4
        DW      SCANH
        LOAD    RD, RUNNING
        LDN     RD
        LBNZ    RY1
        SEP     R4
        DW      K_PIN
        DB      'Cron is paused: CRON START first.',0DH,0AH,0
        LBR     RY9
RY1:    LOAD    RD, NON
        LDN     RD
        LBNZ    RY2
        SEP     R4
        DW      K_PIN
        DB      'No job is on (CRON lists them; CRON ON n).',0DH,0AH,0
        LBR     RY9
RY2:    SEP     R4
        DW      RTCGET
        LBDF    RY3
        LDI     0
        SHR
        SEP     R5
RY3:    SEP     R4
        DW      K_PIN
        DB      'Cron needs the clock (a DS12887 on the Disk/UART/RTC card).',0DH,0AH,0
RY9:    LDI     1
        SHR
        SEP     R5

; MKCUR: CUR = DAY HOUR MIN (the clock's own order is SEC MIN HOUR DAY MON YY)
MKCUR:  LOAD    RF, CUR
        LOAD    RD, DAY
        LDN     RD
        STR     RF
        INC     RF
        LOAD    RD, HOUR
        LDN     RD
        STR     RF
        INC     RF
        LOAD    RD, MIN
        LDN     RD
        STR     RF
        SEP     R5
; SAMEM: DF = 0 if the 3 bytes at RD and RF are the same (day hour minute)
SAMEM:  LDI     3
        PLO     RC
SM1:    LDA     RF
        STR     R2
        LDA     RD
        XOR
        LBNZ    SM9
        DEC     RC
        GLO     RC
        LBNZ    SM1
        LDI     0
        SHR
        SEP     R5
SM9:    LDI     1
        SHR
        SEP     R5

; PHM: HOUR:MIN.  TO2: D (0-99) -> two digits at RA, RA past them
PHM:    LOAD    RD, HOUR
        LDN     RD
        SEP     R4
        DW      P2D
        LDI     ':'
        SEP     R4
        DW      F_TYPE
        LOAD    RD, MIN
        LDN     RD
        SEP     R4
        DW      P2D
        SEP     R5
TO2:    PLO     RC
        LDI     '0'
        PHI     RC
T21:    GLO     RC
        SMI     10
        LBNF    T22
        PLO     RC
        GHI     RC
        ADI     1
        PHI     RC
        LBR     T21
T22:    GHI     RC
        STR     RA
        INC     RA
        GLO     RC
        ADI     '0'
        STR     RA
        INC     RA
        SEP     R5

; ==== the table
; LOADT: /CRON.TAB -> TAB, a 0 after it (TEND: there). DF = 1: there is none.
LOADT:  LOAD    RF, TABNM
        LOAD    RD, NM11
        SEP     R4
        DW      K_PARSE
        LBDF    LT9
        LOAD    RD, NM11
        SEP     R4
        DW      KS_FINDN
        LBDF    LT9
        LOAD    RF, TABNM
        LOAD    RA, TAB
        LOAD    RC, TABMAX - 16
        SEP     R4
        DW      K_LOADF
        GLO     RC              ; TEND = TAB + the bytes (TAB's low byte is 0)
        PLO     RA
        GHI     RC
        ADI     HIGH(TAB)
        PHI     RA
        LDI     0
        STR     RA
        LOAD    RD, TEND
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LDI     0
        SHR
        SEP     R5
LT9:    LDI     1
        SHR
        SEP     R5
; SAVET: TAB..TEND -> /CRON.TAB.  SAVEF: RF -> a path, RA = the data, RC = its bytes: saved (replacing);
;        DF = 1: it could not be (said why)
SAVET:  LOAD    RD, TEND
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC              ; (TAB's low byte is 0)
        GHI     RC
        SMI     HIGH(TAB)
        PHI     RC
        LOAD    RF, TABNM
        LOAD    RA, TAB
SAVEF:  LOAD    RD, SVA         ; (kept: K_PARSE may use RA, RC)
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, NM11
        SEP     R4
        DW      K_PARSE
        LOAD    RD, SVA
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, NM11
        SEP     R4
        DW      K_SAVER
        LBDF    SV9
        SEP     R5
SV9:    SEP     R4
        DW      K_PIN
        DB      'Could not save it: the card or its folder is full, or the card failed.',0DH,0AH,0
        LDI     1
        SHR
        SEP     R5

; FIRST: the table's first line next.  NEXTL: the next line -> LBUF (0 after it, 250 characters at most),
;        LSTART = where it starts in TAB; DF = 1: no more
FIRST:  LOAD    RD, POS
        LDI     HIGH(TAB)
        STR     RD
        INC     RD
        LDI     LOW(TAB)
        STR     RD
        SEP     R5
NEXTL:  LOAD    RD, POS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDN     RF
        LBZ     NL9
        LOAD    RD, LSTART
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, LBUF
        LDI     LMAX
        PLO     RC
NL1:    LDN     RF
        LBZ     NL4
        XRI     0DH
        LBZ     NL3
        XRI     0DH XOR 0AH
        LBZ     NL3
        GLO     RC
        LBZ     NL2
        LDN     RF
        STR     RD
        INC     RD
        DEC     RC
NL2:    INC     RF
        LBR     NL1
NL3:    LDA     RF              ; CR or LF: past it (CR LF: both)
        XRI     0DH
        LBNZ    NL4
        LDN     RF
        XRI     0AH
        LBNZ    NL4
        INC     RF
NL4:    LDI     0
        STR     RD
        LOAD    RD, POS
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDI     0
        SHR
        SEP     R5
NL9:    LDI     1
        SHR
        SEP     R5

; CLASS: the line in LBUF -> D = 0 nothing (blank, # comment), 1 the CRON line, 2 a job;
;        FLAGP / FLAGO = where its y or n is (in TAB / in LBUF)
CLASS:  LOAD    RF, LBUF
        SEP     R4
        DW      SKIPS
        LDN     RF
        LBZ     CL0
        XRI     '#'
        LBZ     CL0
        LOAD    RD, W_CRON
        SEP     R4
        DW      WORDEQ
        LBDF    CL2
        SEP     R4
        DW      SETFO
        LDI     1
        SEP     R5
CL2:    SEP     R4
        DW      SETFO
        LDI     2
        SEP     R5
CL0:    LDI     0
        SEP     R5
SETFO:  GLO     RF              ; FLAGO = RF's offset in LBUF; FLAGP = LSTART + it
        STR     R2
        LOAD    RD, FLAGO
        LDN     R2
        STR     RD
        LOAD    RD, LSTART
        LDA     RD
        PHI     RC
        LDN     RD
        ADD
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LOAD    RD, FLAGP
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
FLAGRF: LOAD    RD, FLAGO       ; RF = the line's y or n, in LBUF
        LDN     RD
        PLO     RF
        LDI     HIGH(LBUF)
        PHI     RF
        SEP     R5

; SCANH: RUNNING (the CRON line's y; none: 1), NON (the jobs on and understood)
SCANH:  LOAD    RD, RUNNING
        LDI     1
        STR     RD
        INC     RD              ; (NON follows RUNNING)
        LDI     0
        STR     RD
        INC     RD              ; (HASH: a CRON line seen)
        STR     RD
        SEP     R4
        DW      FIRST
SH1:    SEP     R4
        DW      NEXTL
        LBDF    SH9
        SEP     R4
        DW      CLASS
        LBZ     SH1
        XRI     1
        LBNZ    SH3
        LOAD    RD, HASH        ; the CRON line (the first one counts)
        LDN     RD
        LBNZ    SH1
        LDI     1
        STR     RD
        SEP     R4
        DW      FLAGRF
        LDN     RF
        SEP     R4
        DW      UPC
        XRI     'N'
        LBNZ    SH1
        LOAD    RD, RUNNING
        LDI     0
        STR     RD
        LBR     SH1
SH3:    SEP     R4
        DW      FLAGRF
        SEP     R4
        DW      PARSEJ
        LBDF    SH1
        LOAD    RD, JFLAG
        LDN     RD
        LBZ     SH1
        LOAD    RD, NON
        LDN     RD
        ADI     1
        STR     RD
        LBR     SH1
SH9:    SEP     R5

; PARSEJ: RF -> a job's y or n in LBUF -> JFLAG (1 y, 0 n), FP (where each of the 5 fields starts, each 0-ended
;         now), CMDP (the command). DF = 1: not understood (a field wrong, missing, or no command)
PARSEJ: LDA     RF
        SEP     R4
        DW      UPC
        XRI     'Y'
        LBZ     PJ1
        XRI     'Y' XOR 'N'
        LBNZ    PJBAD
        LDI     0
        LBR     PJ2
PJ1:    LDI     1
PJ2:    STR     R2
        LOAD    RD, JFLAG
        LDN     R2
        STR     RD
        LDN     RF              ; a space after it
        XRI     ' '
        LBZ     PJ3
        XRI     ' ' XOR 09H
        LBNZ    PJBAD
PJ3:    LOAD    RD, FP
        LDI     5
        PLO     RB
PJ4:    SEP     R4
        DW      SKIPS
        LDN     RF
        LBZ     PJBAD
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        INC     RD
PJ5:    LDN     RF
        LBZ     PJBAD           ; (the line ends in a field: no command)
        XRI     ' '
        LBZ     PJ6
        XRI     ' ' XOR 09H
        LBZ     PJ6
        INC     RF
        LBR     PJ5
PJ6:    LDI     0
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    PJ4
        SEP     R4
        DW      SKIPS
        LDN     RF
        LBZ     PJBAD
        LOAD    RD, CMDP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDI     0               ; each field must make sense: tried with its smallest value
        PLO     R7
PJ7:    GLO     R7
        PLO     RB
        GLO     R7
        ADI     LOW(FMIN)
        PLO     RD
        LDI     HIGH(FMIN)
        ADCI    0
        PHI     RD
        LDN     RD
        PHI     RB
        SEP     R4
        DW      CALLF
        XRI     2
        LBZ     PJBAD
        INC     R7
        GLO     R7
        XRI     5
        LBNZ    PJ7
        LDI     0
        SHR
        SEP     R5
PJBAD:  LDI     1
        SHR
        SEP     R5

; MATCHJ: DF = 0 if the job PARSEJ took apart is due now (MIN HOUR DAY MON, WD the weekday: 0 = Sunday)
MATCHJ: LOAD    RD, MIN
        LDN     RD
        PHI     RB
        LDI     0
        PLO     RB
        SEP     R4
        DW      CALLF
        LBZ     MJNO
        LOAD    RD, HOUR
        LDN     RD
        PHI     RB
        LDI     1
        PLO     RB
        SEP     R4
        DW      CALLF
        LBZ     MJNO
        LOAD    RD, MON
        LDN     RD
        PHI     RB
        LDI     3
        PLO     RB
        SEP     R4
        DW      CALLF
        LBZ     MJNO
        LOAD    RD, DAY         ; R7.0 = the day matches, R7.1 = the weekday does
        LDN     RD
        PHI     RB
        LDI     2
        PLO     RB
        SEP     R4
        DW      CALLF
        PLO     R7
        LOAD    RD, WD
        LDN     RD
        PHI     RB
        LDI     4
        PLO     RB
        SEP     R4
        DW      CALLF
        PHI     R7
        LBNZ    MJ1
        LOAD    RD, WD          ; Sunday: 7 will do too
        LDN     RD
        LBNZ    MJ1
        LDI     7
        PHI     RB
        LDI     4
        PLO     RB
        SEP     R4
        DW      CALLF
        PHI     R7
MJ1:    LOAD    RD, FP + 4      ; both the day and the weekday given (not *): either; else both
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDN     RF
        XRI     '*'
        LBZ     MJAND
        LOAD    RD, FP + 8
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDN     RF
        XRI     '*'
        LBZ     MJAND
        GLO     R7
        LBNZ    MJYES
        GHI     R7
        LBNZ    MJYES
        LBR     MJNO
MJAND:  GLO     R7
        LBZ     MJNO
        GHI     R7
        LBZ     MJNO
MJYES:  LDI     0
        SHR
        SEP     R5
MJNO:   LDI     1
        SHR
        SEP     R5

; CALLF: field RB.0 (0 min .. 4 weekday) against the value RB.1 -> D = 0 no, 1 yes, 2 not understood
CALLF:  LOAD    RD, FIDX
        GLO     RB
        STR     RD
        INC     RD              ; (FVAL follows FIDX)
        GHI     RB
        STR     RD
        GLO     RB              ; RF = the field: FP + 2 x its number
        SHL
        ADI     LOW(FP)
        PLO     RD
        LDI     HIGH(FP)
        ADCI    0
        PHI     RD
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
; MATCHF: RF -> a field, FIDX its kind, FVAL the value -> D = 0 no, 1 yes, 2 not understood
MATCHF: LOAD    RD, FIDX        ; FLO FHI: the kind's smallest and largest
        LDN     RD
        ADI     LOW(FMIN)
        PLO     RD
        LDI     HIGH(FMIN)
        ADCI    0
        PHI     RD
        LDN     RD
        STR     R2
        LOAD    RD, FLO
        LDN     R2
        STR     RD
        LOAD    RD, FIDX
        LDN     RD
        ADI     LOW(FMAX)
        PLO     RD
        LDI     HIGH(FMAX)
        ADCI    0
        PHI     RD
        LDN     RD
        STR     R2
        LOAD    RD, FHI
        LDN     R2
        STR     RD
        LOAD    RD, MATCHD
        LDI     0
        STR     RD
MI0:    LOAD    RD, FLO         ; an item: * n n-m, then perhaps /s
        LDN     RD
        STR     R2
        LOAD    RD, ILO
        LDN     R2
        STR     RD
        LOAD    RD, FHI
        LDN     RD
        STR     R2
        LOAD    RD, IHI
        LDN     R2
        STR     RD
        INC     RD              ; ISTEP = 1, ISGL = 0 (ISTEP, ISGL follow IHI)
        LDI     1
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LDN     RF
        XRI     '*'
        LBNZ    MI2
        INC     RF
        LBR     MI5
MI2:    SEP     R4
        DW      NUM8
        LBDF    MBAD
        STR     R2
        LOAD    RD, ILO
        LDN     R2
        STR     RD
        INC     RD              ; IHI
        STR     RD
        INC     RD
        INC     RD              ; ISGL = 1: one number (a /s after it runs to the largest)
        LDI     1
        STR     RD
        LDN     RF
        XRI     '-'
        LBNZ    MI5
        INC     RF
        SEP     R4
        DW      NUM8
        LBDF    MBAD
        STR     R2
        LOAD    RD, IHI
        LDN     R2
        STR     RD
        INC     RD
        INC     RD
        LDI     0
        STR     RD
MI5:    LDN     RF
        XRI     '/'
        LBNZ    MI6
        INC     RF
        SEP     R4
        DW      NUM8
        LBDF    MBAD
        LBZ     MBAD            ; (/0)
        STR     R2
        LOAD    RD, ISTEP
        LDN     R2
        STR     RD
        INC     RD
        LDN     RD
        LBZ     MI6
        LOAD    RD, FHI         ; n/s: from n to the largest
        LDN     RD
        STR     R2
        LOAD    RD, IHI
        LDN     R2
        STR     RD
MI6:    LOAD    RD, ILO         ; FLO <= ILO <= IHI <= FHI
        LDN     RD
        STR     R2
        LOAD    RD, FLO
        LDN     RD
        SD                      ; ILO - FLO
        LBNF    MBAD
        LOAD    RD, IHI
        LDN     RD
        STR     R2
        LOAD    RD, FHI
        LDN     RD
        SM                      ; FHI - IHI
        LBNF    MBAD
        LOAD    RD, ILO
        LDN     RD
        STR     R2
        LOAD    RD, IHI
        LDN     RD
        SM                      ; IHI - ILO
        LBNF    MBAD
        PLO     RC              ; RC.0 = IHI - ILO
        LOAD    RD, ILO         ; the value: ILO <= FVAL, FVAL - ILO <= IHI - ILO, a whole number of steps
        LDN     RD
        STR     R2
        LOAD    RD, FVAL
        LDN     RD
        SM
        LBNF    MI7
        PHI     RC              ; RC.1 = FVAL - ILO
        STR     R2
        GLO     RC
        SM
        LBNF    MI7
        GHI     RC              ; ILO itself
        LBZ     MI6C
        LOAD    RD, ISTEP
        LDN     RD
        STR     R2
        GHI     RC
MI6A:   SM                      ; less a step at a time: 0 = a whole number of steps
        LBNF    MI7
        LBNZ    MI6A
MI6C:   LOAD    RD, MATCHD
        LDI     1
        STR     RD
        LBR     MI7
MI7:    LDN     RF              ; the next item, or the end
        XRI     ','
        LBNZ    MI8
        INC     RF
        LBR     MI0
MI8:    LDN     RF
        LBNZ    MBAD
        LOAD    RD, MATCHD
        LDN     RD
        SEP     R5
MBAD:   LDI     2
        SEP     R5

; NUM8: RF -> 1 or 2 digits -> D, RF past them; DF = 1: none, or 3 or more
NUM8:   LDI     0
        PLO     RC
        PHI     RC
N81:    LDN     RF
        SMI     '0'
        LBNF    N82
        SMI     10
        LBDF    N82
        GHI     RC
        ADI     1
        PHI     RC
        XRI     3
        LBZ     N8BAD
        GLO     RC
        SHL
        SHL
        STR     R2
        GLO     RC
        ADD
        SHL
        STR     R2
        LDA     RF
        SMI     '0'
        ADD
        PLO     RC
        LBR     N81
N82:    GHI     RC
        LBZ     N8BAD
        GLO     RC
        ADI     0               ; (DF = 0)
        SEP     R5
N8BAD:  LDI     1
        SHR
        SEP     R5
; PAIR: RF -> exactly two digits -> D (DF = 1: not two digits)
PAIR:   LDN     RF
        SMI     '0'
        LBNF    PRB
        SMI     10
        LBDF    PRB
        LDA     RF
        SMI     '0'
        PLO     RC
        SHL
        SHL
        STR     R2
        GLO     RC
        ADD
        SHL
        STR     R2
        LDN     RF
        SMI     '0'
        LBNF    PRB
        SMI     10
        LBDF    PRB
        LDA     RF
        SMI     '0'
        ADD
        SEP     R5
PRB:    LDI     1
        SHR
        SEP     R5

; WORDEQ: RF -> a word; RD -> one in capitals (0-ended). Same, in any case, and the word ends there: DF = 0, RF
;         past it and its spaces. Else DF = 1, RF as it was.
WORDEQ: GHI     RF
        PHI     RA
        GLO     RF
        PLO     RA
WQ1:    LDN     RD
        LBZ     WQ3
        LDN     RF
        SEP     R4
        DW      UPC
        STR     R2
        LDA     RD
        XOR
        LBNZ    WQ9
        INC     RF
        LBR     WQ1
WQ3:    LDN     RF
        LBZ     WQ4
        XRI     ' '
        LBNZ    WQ9
        SEP     R4
        DW      K_SKIPSP
WQ4:    LDI     0
        SHR
        SEP     R5
WQ9:    GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        LDI     1
        SHR
        SEP     R5
; UPC: D -> D in capitals (letters only).  SKIPS: RF past spaces and tabs
UPC:    PLO     RE
        SMI     'a'
        LBNF    UP9
        SMI     26
        LBDF    UP9
        GLO     RE
        SMI     20H
        SEP     R5
UP9:    GLO     RE
        SEP     R5
SKIPS:  LDN     RF
        XRI     ' '
        LBZ     SK1
        XRI     ' ' XOR 09H
        LBNZ    SK9
SK1:    INC     RF
        LBR     SKIPS
SK9:    SEP     R5

W_START: DB     'START',0
W_PAUSE: DB     'PAUSE',0
W_STOP: DB      'STOP',0
W_ON:   DB      'ON',0
W_OFF:  DB      'OFF',0
W_RUN:  DB      'RUN',0
W_W:    DB      '-W',0
W_CRON: DB      'CRON',0
TABNM:  DB      '/CRON.TAB',0
JOBNM:  DB      '/_CRONJOB.SH',0
RUNNM:  DB      '/_CRONRUN.SH',0
RUNCMD: DB      'SH _CRONRUN',0
TEMPL:  DB      'CRON y',0DH,0AH
        DB      '# run min hour day month weekday  command      (HELP CRON)',0DH,0AH,0
RUNTXT: DB      '# _CRONRUN.SH - made by CRON RUN (cron mode): CRON -w waits for the next job; Esc stops',0DH,0AH
        DB      'L=0',0DH,0AH
        DB      'while CRON -w $L; do',0DH,0AH
        DB      '. /_CRONJOB.SH',0DH,0AH
        DB      'done',0DH,0AH
RUNEND:
FMIN:   DB      0, 0, 1, 1, 0
FMAX:   DB      59, 23, 31, 12, 7

        INCL    "rtc.inc"       ; RTCGET PDATE PTIME WDAY (P2D), and SEC MIN HOUR DAY MON YY
WD:     DS      1
TEND:   DS      2
POS:    DS      2
LSTART: DS      2
FLAGP:  DS      2
FLAGO:  DS      1
RUNNING: DS     1               ; RUNNING NON HASH: in this order
NON:    DS      1
HASH:   DS      1
JNUM:   DS      1
JFLAG:  DS      1
FP:     DS      10
CMDP:   DS      2
FIDX:   DS      1               ; FIDX FVAL: in this order
FVAL:   DS      1
FLO:    DS      1
FHI:    DS      1
ILO:    DS      1
IHI:    DS      1               ; IHI ISTEP ISGL: in this order
ISTEP:  DS      1
ISGL:   DS      1
MATCHD: DS      1
LASTD:  DS      3               ; the minute last done (L=ddhhmm), then SEEN: the minute being waited past
SEEND:  DS      3
CUR:    DS      3               ; DAY HOUR MIN now
FLG:    DS      1               ; START PAUSE ON OFF: the letter to put; ON OFF: the job's number
NJ:     DS      1
SVA:    DS      2
SVC:    DS      2
JP:     DS      2
NM11:   DS      11
PEND:
        END
