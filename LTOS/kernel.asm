; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; kernel.asm - the LTOS kernel, loaded to $0300 by the boot sector (phase 1: the command interpreter).
;
; Memory: $0300-$2CFF the kernel (21 sectors at most), $2D00-$2DFF its variables; $3000-$6BFF programs; $6C00 SECBUF; $7000 the command line;
; the stack from $7DFF down; $7F00-$7FFF is the monitor's. The BIOS's SCRT: SEP R4 / DW, SEP R5.
; RE.1 is the BIOS's console selector - never touched.
;
; Commands: HELP (or ?), VER, CLS, DUMP [addr [len]], MON. A command is a word in the table CMDS; its
; routine gets RF pointing after the word and ends with LBR MAIN.

        CPU     1802
        INCL    "ltos.inc"

LINE    EQU     7000H           ; the command line ($7000-$70FF: up to 255 characters from SH; 79 typed)
LINEMAX EQU     79
DIRBUF  EQU     6C00H           ; the root directory's sector being read
SECBUF  EQU     6C00H           ; (VER's IDENTIFY uses it too)
FATBUF  EQU     6E00H           ; a FAT sector (FATCUR says which)
NUMBUF  EQU     7100H           ; PDEC32's digits
PWDB    EQU     7180H           ; WHERE's text (5 levels of 13 + "/..."), after NUMBUF
HIST    EQU     7600H           ; the last command line (the up arrow brings it back)
PWDL    EQU     72
DATBUF  EQU     7200H           ; a file's sector (FREAD)
PROGLO  EQU     PRGORG          ; programs and LOAD go in $3000-$6BFF
PROGHI  EQU     6C00H
HIGHLO  EQU     7700H           ; and $7700-$7BFF (after HIST; $7C00 up: STLRX's variables, the stack)
HIGHHI  EQU     7C00H

        ORG     0300H
KSTART: LBR     COLD            ; $0300
        DB      'LTOS'          ; $0303: the signature the boot sector checks
        DB      0, 5            ; $0307: version 0.5
; $0309: the kernel's calls for programs (kapi.inc) - these addresses stay put in later versions.
; SEP R4 / DW K_xxx, like any BIOS call.
        LBR     MAIN            ; $0309 K_MAIN    back to the LTOS> prompt (from any depth)
        LBR     KLOADF          ; $030C K_LOADF   RF -> a file name, RA = where, RC = the most bytes:
                                ;                 RC = the bytes loaded, RF past the name (trouble: said, K_MAIN)
        LBR     KSAVEF          ; $030F K_SAVEF   RF -> a file name, RA = the data, RC = its bytes: saved
                                ;                 (asks before replacing); ends the command - never returns
        LBR     PIN             ; $0312 K_PIN     the text after the call
        LBR     PDEC            ; $0315 K_PDEC    RD in decimal
        LBR     PHEX4           ; $0318 K_PHEX4   RD in hex
        LBR     PHEX2           ; $031B K_PHEX2   D in hex
        LBR     PCRLF           ; $031E K_PCRLF   a new line
        LBR     SKIPSP          ; $0321 K_SKIPSP  RF past spaces
        LBR     HEXARG          ; $0324 K_HEXARG  RF -> a hex number -> RD (DF = 1: none)
        LBR     YESNO           ; $0327 K_YESNO   a key: DF = 1 if Y
        LBR     PARSE           ; $032A K_PARSE   RF -> a path -> 11 bytes at RD, WDIR its folder (DF = 1: not
                                ;                 a name - D = 1 bad, 2 no such folder, 3 a folder)
KSTAMP: DW      0               ; $032D this kernel's build stamp (build.py): the system programs on the card
                                ;  (VER.PRG, FREE.PRG) use its routines directly and check it first
        LBR     KSAVER          ; $032F K_SAVER   RD -> an 11-byte name, RA = the data, RC = its bytes: saved,
                                ;                 replacing one of that name without asking. Returns: DF = 1 +
                                ;                 D: 1 the directory is full, 2 the card is full, 3 card failed,
                                ;                 4 a folder has that name
        LBR     KOUT            ; $0332 K_OUT     D to the output: the screen (LTOS-SH phase 1: or a file)
        LBR     KTTY            ; $0335 K_TTY     D to the screen, always (prompts that must be seen)
        LBR     KIN             ; $0338 K_IN      a key: the keyboard (LTOS-SH phase 1: or a file) -> D
        LBR     TTYON           ; $033B K_TTYON   the output to the screen until the next K_YESNO's answer
KRDIR:  DB      0               ; $033E K_RDIR    0: the output goes to the screen; 1 a file (> >>); 2 nowhere
KSTAT:  DB      0               ; $033F K_STAT    the last command's exit status (0 = all right)
        LBR     KEXEC           ; $0340 K_EXEC    run the command line at LINE (SH: a script's command), then MAIN
SHHOOK: DB      0, 0, 0         ; $0343 K_SHHOOK  0: no script; else LBR (C0 hh ll) - MAIN goes there, not the prompt

; ---- LTOS's own SCRT (KINIT: R4 = KCALL, R5 = KRET, then on at R6 - as the BIOS's F_INITCALL). KCALL is the
;      BIOS's CALL with one thing more: a call to the BIOS's F_TYPE, F_READ, F_MSG or F_INPUTL goes to the
;      kernel's KOUT, KIN, KMSG, KINL instead - so every program's output and keys pass through LTOS (and can
;      go to or come from a file). D and DF are kept, as by the BIOS's; RE.0 is used, RE.1 never.
KINIT:  LOAD    R4, KCALL
        LOAD    R5, KRET
        DEC     R2              ; (KRET takes two bytes off the stack, as the BIOS's does here)
        DEC     R2
        SEP     R5
KCX:    SEP     R3
KCALL:  PLO     RE
        GHI     R6
        SEX     R2
        STXD
        GLO     R6
        STXD
        GHI     R3
        PHI     R6
        GLO     R3
        PLO     R6
        LDA     R6
        PHI     R3
        XRI     0FFH            ; a BIOS call ($FFxx)? (tested here: only 1 step more than the BIOS's own CALL, as
        BZ      KCB             ; XFER and RECV read the UART with ~58 steps a character and little to spare)
        LDA     R6
        PLO     R3
KCD:    GLO     RE
        BR      KCX
KCB:    LDA     R6
        PLO     R3
        XRI     LOW(F_TYPE)
        LBZ     KCO
        XRI     LOW(F_TYPE) XOR LOW(F_READ)
        LBZ     KCI
        XRI     LOW(F_READ) XOR LOW(F_MSG)
        LBZ     KCM
        XRI     LOW(F_MSG) XOR LOW(F_INPUTL)
        LBNZ    KCD
        LDI     HIGH(KINL)
        PHI     R3
        LDI     LOW(KINL)
        LBR     KCS
KCO:    LDI     HIGH(KOUT)
        PHI     R3
        LDI     LOW(KOUT)
        LBR     KCS
KCI:    LDI     HIGH(KIN)
        PHI     R3
        LDI     LOW(KIN)
        LBR     KCS
KCM:    LDI     HIGH(KMSG)
        PHI     R3
        LDI     LOW(KMSG)
KCS:    PLO     R3
        LBR     KCD
KRX:    SEP     R3
KRET:   PLO     RE
        GHI     R6
        PHI     R3
        GLO     R6
        PLO     R3
        SEX     R2
        IRX
        LDXA
        PLO     R6
        LDX
        PHI     R6
        GLO     RE
        BR      KRX
; KTTY KIN KINL: where the BIOS's console calls go (KOUT, KMSG: redir.asm - to the screen or a file)
KTTY:   LBR     F_TYPE
KIN:    LBR     F_READ
KINL:   LBR     F_INPUTL

COLD:   PLO     R9              ; D = '0' or '3': which register the BIOS started the boot sector with
        LOAD    R2, STACK
        SEX     R2
        LOAD    R6, WARM        ; (LTOS's own SCRT in R4 / R5: KINIT)
        LBR     KINIT
WARM:   SEP     R4              ; first: say the kernel is running (the boot sector printed a dot a sector)
        DW      PIN
        DB      'done.',0DH,0AH,0
        LOAD    RD, BOOTR
        GLO     R9
        STR     RD
        LOAD    RD, DUMPA       ; DUMP goes on from $0000
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      IDERST          ; LTOS's own driver: 8-bit mode, interrupts off
        LBNF    W2
        LOAD    RF, CARDT
        SEP     R4
        DW      PSTR
W2:     SEP     R4
        DW      MOUNT           ; the FAT16 partition
        LBNF    W3
        LOAD    RF, NOFAT
        SEP     R4
        DW      PSTR
W3:     SEP     R4
        DW      STLFIND         ; STELLAR.BIN on the card: its sectors
        SEP     R4
        DW      STLCHK          ; was STELLAR in RAM when LTOS started?
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'LTOS 0.5 - LiteOS for the Elf2K.  Type HELP for the commands.',0DH,0AH,0

        LOAD    RD, HIST        ; no last command yet
        LDI     0
        STR     RD
                                ; (then the prompt: no start-up script - Craig, 2026-11-08)
; ---- the command loop
MAIN:   LOAD    R2, STACK       ; (a fresh stack for every command)
        SEX     R2
        SEP     R4              ; the last command's output: a file closed, the screen again
        DW      RCLOSE
        LOAD    RD, SHHOOK      ; a script running (SH): its next step, not the prompt
        LDN     RD
        LBNZ    SHHOOK
        SEP     R4
        DW      PIN
        DB      'LTOS',0
        LOAD    RD, CWD         ; in a folder: its path ("LTOS /GAMES> ")
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     MP1
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      WHERE
        SEP     R4
        DW      PSTR
MP1:    SEP     R4
        DW      PIN
        DB      '> ',0
        LOAD    RD, CWD         ; every command starts in the current folder
        LOAD    RF, WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RF, LINE
        LOAD    RC, LINEMAX
        SEP     R4
        DW      GETLN           ; the line, edited (Ctrl-C ends it with DF = 1)
        LBNF    M1
        SEP     R4
        DW      PIN
        DB      '^C',0DH,0AH,0
        LBR     MAIN
M1:     SEP     R4
        DW      PCRLF
M1X:    SEP     R4              ; "> NAME", ">> NAME", "> NUL": out of the line, the file open
        DW      REDIR
        LBDF    MAIN
        LOAD    RF, LINE
MDISP:  SEP     R4              ; (MDISP: RF -> a command line - HELP comes in here)
        DW      SKIPSP
        LDN     RF
        LBZ     MAIN            ; an empty line
        LOAD    RD, CMDS
M2:     LDN     RD
        LBZ     UNKNOWN         ; the end of the table
        GHI     RF              ; RB = where the word starts
        PHI     RB
        GLO     RF
        PLO     RB
M3:     LDN     RD
        LBZ     M5              ; the end of this name
        LDN     RF
        SEP     R4
        DW      UPCH
        STR     R2
        LDA     RD
        XOR
        LBNZ    M4
        INC     RF
        LBR     M3
M4:     LDA     RD              ; not this one: past its name ...
        LBNZ    M4
        INC     RD              ; ... and its address
        INC     RD
        LBR     MNEXT
M5:     LDN     RF              ; the name has ended: the word must end too
        LBZ     M6
        XRI     ' '
        LBZ     M6
        INC     RD
        INC     RD
        INC     RD
MNEXT:  GHI     RB
        PHI     RF
        GLO     RB
        PLO     RF
        LBR     M2
M6:     INC     RD              ; this one: patch JMPV with its routine, and go
        LOAD    RC, JMPV+1
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
JMPV:   LBR     MAIN            ; (patched)

; KEXEC (K_EXEC): the line at LINE run as if typed (redirection and all), then MAIN as after any command
KEXEC:  LOAD    R2, STACK
        SEX     R2
        LBR     M1X

UNKNOWN: LOAD   RD, UKW         ; a program on the card by that name? (COPY = COPY.PRG)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, MOUNTED
        LDN     RD
        LBZ     UK0
        LOAD    RD, FNAME
        SEP     R4
        DW      PARSE
        LBDF    UK0
        LOAD    RD, UKM         ; NAME.SH or NAME.PRG (.SH first) here, else in the root, else in /BIN
        LDI     0
        STR     RD
        LOAD    RD, ARGP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, FNAME       ; (wildcards: no '?' name is on the card... FINDN would match one - so check)
        LDI     8
        PLO     RB
UKQ:    LDA     RD
        XRI     '?'
        LBZ     UK0
        DEC     RB
        GLO     RB
        LBNZ    UKQ
        SEP     R4
        DW      FINDX
        LBNF    UKF
        LOAD    RD, PPSL        ; not here: a name typed alone - in the root too, then in /BIN
        LDN     RD
        LBNZ    UKS
        LOAD    RD, WDIR
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     UKB
UKR:    LDI     0
        STR     RD
        DEC     RD
        STR     RD
        SEP     R4
        DW      FINDX
        LBNF    UKF
UKB:    SEP     R4
        DW      TOBIN
        LBDF    UKS
        SEP     R4
        DW      FINDX
        LBDF    UKS
UKF:    LOAD    RD, DATTR
        LDN     RD
        ANI     10H
        LBNZ    UK0
        LOAD    RD, UKM
        LDN     RD
        LBNZ    RUNIT           ; RUN it, with the rest of the line
        LOAD    RD, UKX
        LDN     RD
        LBNZ    RUNIT
        LOAD    RD, SHNM        ; NAME.SH: SH.PRG (the root, then /BIN) with the whole line - SH NAME ...
        LBR     UKS2
; UKS: no NAME.SH or NAME.PRG here, in the root or in /BIN - perhaps a STELLAR app: STELLAR.PRG (the root, then
;      /BIN) is run with the whole line, as if STELLAR had been typed in front ("LW2 DOC.TXT"). A path typed, or
;      STELLAR.PRG or SH.PRG itself not found: unknown.
UKS:    LOAD    RD, UKM
        LDN     RD
        LBNZ    UK0
        LOAD    RD, PPSL
        LDN     RD
        LBNZ    UK0
        LOAD    RD, STLPN
UKS2:   LOAD    RF, UKM
        LDI     1
        STR     RF
        LOAD    RF, UKW         ; ARGP = the whole line
        LOAD    RC, ARGP
        LDA     RF
        STR     RC
        INC     RC
        LDN     RF
        STR     RC
        LOAD    RF, FNAME       ; FNAME = the 11 bytes at RD
        LDI     11
        PLO     RB
UKS1:   LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    UKS1
        LOAD    RD, WDIR+1      ; the root, then /BIN
        LBR     UKR
SHNM:   DB      'SH      PRG'
; FINDX: in WDIR, FNAME itself (UKM = 1) - or (UKM = 0) NAME.SH, else NAME.PRG (FINDE). DF = 1: not there.
FINDX:  LOAD    RD, UKM
        LDN     RD
        LBZ     FINDE
        LOAD    RD, FNAME
        LBR     FINDN
; FINDE: FNAME's 8 bytes as NAME.SH (UKX = 0) or else NAME.PRG (UKX = 1) - each name in the folder looked at
;        once; a NAME.PRG before a NAME.SH: on to the end, then the .PRG found again. DF = 1: neither.
FINDE:  LOAD    RD, UKX         ; (2: no NAME.PRG seen)
        LDI     2
        STR     RD
        LOAD    RD, FNAME+8     ; NAME.??? (an extension typed: that one)
        LDN     RD
        XRI     ' '
        LBNZ    FE0
        LDI     '?'
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
FE0:    LOAD    RD, FNAME
        SEP     R4
        DW      FINDN
FE1:    LBDF    FE8
        LOAD    RD, DPTR        ; RF -> the match's extension (DPTR is past its entry)
        LDA     RD
        PHI     RF
        LDN     RD
        SMI     24
        PLO     RF
        GHI     RF
        SMBI    0
        PHI     RF
        LDA     RF
        XRI     'S'
        LBNZ    FE2
        LDA     RF
        XRI     'H'
        LBNZ    FE3
        LDN     RF
        XRI     ' '
        LBNZ    FE3
        LOAD    RD, UKX         ; NAME.SH
        LDI     0
        STR     RD
        SHR
        SEP     R5
FE2:    XRI     'S' XOR 'P'
        LBNZ    FE3
        LDA     RF
        XRI     'R'
        LBNZ    FE3
        LDN     RF
        XRI     'G'
        LBNZ    FE3
        LOAD    RD, UKX         ; NAME.PRG: kept in mind
        LDI     1
        STR     RD
FE3:    LOAD    RD, DNALL       ; the next match
        LDI     1
        STR     RD
        SEP     R4
        DW      DNEXT
        LOAD    RD, DNALL       ; (LOAD keeps DF)
        LDI     0
        STR     RD
        LBR     FE1
FE8:    LOAD    RD, UKX
        LDN     RD
        XRI     1
        LBNZ    FE9
        LOAD    RD, FNAME+8     ; the NAME.PRG seen: found again
        LDI     'P'
        STR     RD
        INC     RD
        LDI     'R'
        STR     RD
        INC     RD
        LDI     'G'
        STR     RD
        LOAD    RD, FNAME
        LBR     FINDN
FE9:    LDI     1
        SHR
        SEP     R5
UK0:    SEP     R4              ; (on the screen, as an error; KSTAT 127, as sh's)
        DW      TTYON
        LOAD    RD, KSTAT
        LDI     127
        STR     RD
        LOAD    RD, UKW
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      PIN
        DB      'Unknown command: ',0
UK1:    LDN     RF
        LBZ     UK2
        XRI     ' '
        LBZ     UK2
        LDA     RF
        SEP     R4
        DW      F_TYPE
        LBR     UK1
UK2:    SEP     R4
        DW      PIN
        DB      '  (see HELP)',0DH,0AH,0
        LBR     MAIN

CMDS:   DB      '?',0              ; (HELP is HELP.PRG; ? runs it)
        DW      C_HELP
        DB      'RUN',0
        DW      C_RUN
        DB      0

; ---- HELP: the file HELP.TXT (the installer puts it on the card)
C_HELP: LOAD    RF, HELPN       ; = HELP (HELP.PRG)
        LBR     MDISP
HELPN:  DB      'HELP',0

; ---- CLS

; ---- MON is MON.PRG (mon.asm): STELLAR back from STELLAR.BIN, then the monitor

; ---- STLCHK: STLRAM = 1 if RAM held the STELLAR on this card when LTOS started. The boot only wrote
;      $0100-$2CFF at most (21 sectors) and the variables are at $2D00-$2DFF, so $2E00-$2EFF is still what
;      it was: compare it with the first half of STELLAR.BIN's sector 23 (STELLAR.BIN ends at $2EFF).
STLCHK: LOAD    RD, STLRAM
        LDI     0
        STR     RD
        LOAD    RD, MOUNTED
        LDN     RD
        LBZ     SC9             ; (no card read worked)
        LOAD    RD, STLN
        LDN     RD
        LBZ     SC9             ; no STELLAR.BIN
        LOAD    RB, STLLST+46   ; its 24th sector: $2E00-$2FFF (STELLAR.BIN's part: $2E00-$2EFF)
        LOAD    R9, 2E00H       ; R9 = the RAM to compare
        LDI     1
        PLO     RA
SC1:    LDA     RB
        PHI     R7
        LDA     RB
        PLO     R7
        LOAD    R8, 0
        LOAD    RF, DATBUF
        SEP     R4
        DW      IDERD
        LBDF    SC9
        LOAD    RF, DATBUF
        LOAD    RC, 256
SC2:    LDA     RF
        STR     R2
        LDA     R9
        XOR
        LBNZ    SC9             ; different: not this STELLAR
        DEC     RC
        GLO     RC
        LBNZ    SC2
        GHI     RC
        LBNZ    SC2
        DEC     RA
        GLO     RA
        LBNZ    SC1
        LOAD    RD, STLRAM
        LDI     1
        STR     RD
SC9:    SEP     R5

; ---- STLFIND: STLN = 24 and STLLST = the sectors of STELLAR.BIN's first 12 KB (in order, through its
;      FAT chain - wherever RECV or the installer put it), if it is on the card, that big, and below sector
;      65,536 (MON's stub reads 16-bit sector numbers). RA -> the list, R9.0 = sectors still wanted, R9.1 =
;      this cluster's sectors done.
STLFIND: LOAD   RD, WDIR        ; (in the root, else in /BIN)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, STLNM
        SEP     R4
        DW      SECLST
        LOAD    RD, STLN
        LDN     RD
        LBNZ    SF9
        SEP     R4
        DW      TOBIN
        LBDF    SF9
        LOAD    RD, STLNM
SECLST: GHI     RD              ; (SECLST: the same for the 11-byte name at RD - STELLAR.PRG's other firmware)
        STXD
        GLO     RD
        STXD
        LOAD    RD, STLN
        LDI     0
        STR     RD
        IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        LOAD    RF, MOUNTED
        LDN     RF
        LBZ     SF9
        SEP     R4
        DW      FINDN
        LBDF    SF9
        LOAD    RD, DSIZE       ; at least $0000-$2EFF
        SEP     R4
        DW      LD32
        GHI     R8
        LBNZ    SF0
        GLO     R8
        LBNZ    SF0
        GLO     R7
        SMI     LOW(2F00H)
        GHI     R7
        SMBI    HIGH(2F00H)
        LBNF    SF9
SF0:    LOAD    RA, STLLST
        LDI     24
        PLO     R9
        LOAD    RD, DCLUS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
SF2:    SEP     R4              ; a cluster: its sectors into the list
        DW      CLVALID
        LBNF    SF9
        SEP     R4
        DW      CL2LBA
        GHI     R8
        LBNZ    SF9
        GLO     R8
        LBNZ    SF9
        LDI     0
        PHI     R9
SF3:    GHI     R7
        STR     RA
        INC     RA
        GLO     R7
        STR     RA
        INC     RA
        INC     R7
        DEC     R9
        GLO     R9
        LBZ     SF8             ; all 24
        GHI     R9              ; the cluster's next sector, or the next cluster
        ADI     1
        PHI     R9
        STR     R2
        LOAD    RD, SPC
        LDN     RD
        XOR
        LBNZ    SF3
        SEP     R4
        DW      FATNEXT
        LBDF    SF9
        LBR     SF2
SF8:    LOAD    RD, STLN
        LDI     24
        STR     RD
SF9:    SEP     R5
STLPN:  DB      'STELLAR PRG'
STLNM:  DB      'STELLAR BIN'
; ---- TOBIN: WDIR = the root's BIN folder, DF = 0. DF = 1: no card, or no /BIN (programs are looked for in
;      the current folder, then the root, then /BIN)
TOBIN:  LOAD    RD, MOUNTED
        LDN     RD
        LBZ     TB9
        LOAD    RD, WDIR
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, BINNM
        LBR     FOLDIN
TB9:    LDI     1
        SHR
        SEP     R5
BINNM:  DB      'BIN        '

; ---- GETLN: a command line into LINE (LINEMAX characters at most), edited: left / right arrows, Home / End,
;      Backspace, Delete, typing in the middle; the up arrow brings back the last line (HIST). Enter: DF = 0,
;      the line 0-ended (and kept in HIST); Ctrl-C: DF = 1. Keys come from the UART itself (no echo): the
;      BIOS's line input echoed an arrow's ESC [ D and kept it in the line.  LPOS, LLEN: cursor, length.
GETLN:  LOAD    RD, LPOS
        LDI     0
        STR     RD
        INC     RD
        STR     RD
GL1:    LOAD    RD, LPOS        ; (RD = LPOS while the fast way goes round)
GL1F:   LDI     15H             ; the next key, read here (no call): the UART's line status ...
        STR     R2
        OUT     SELPORT
        DEC     R2
GL2:    INP     DATPORT
        ANI     01H
        LBZ     GL2
        LDI     10H             ; ... then its data (the data register stays selected for the echo)
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RB
        SMI     20H             ; the fast way (typing or pasting at the end: no calls, the echo straight to
        LBNF    GLK             ;  the UART - a pasted line keeps up at 19200 baud): a printable character ...
        GLO     RB
        SMI     7FH
        LBDF    GLK
        LDA     RD              ; ... at the end of the line ...
        STR     R2
        LDN     RD
        XOR
        LBNZ    GLMID
        LDN     RD              ; ... with room
        XRI     LINEMAX
        LBZ     GL1
        LDN     RD              ; LINE + LLEN = it; LLEN, LPOS + 1
        ADI     LOW(LINE)
        PLO     RA
        LDI     HIGH(LINE)
        PHI     RA
        GLO     RB
        STR     RA
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        STR     RD
        GLO     RB              ; the echo, to the data register: no wait - the last echo began at least a
        STR     R2              ;  character's time ago (keys and echoes go at the same speed)
        OUT     DATPORT
        DEC     R2
        LBR     GL1F
GLK:    GLO     RB
        XRI     0DH
        LBZ     GLEND
        GLO     RB
        XRI     03H
        LBZ     GLCC
        GLO     RB
        XRI     08H
        LBZ     GLBS
        GLO     RB
        XRI     7FH
        LBZ     GLBS
        GLO     RB
        XRI     1BH
        LBZ     GLESC
        LBR     GL1             ; other control keys: ignored
GLMID:  LDN     RD              ; a character in the middle (RD -> LLEN): in at the cursor, if there is room
        XRI     LINEMAX
        LBZ     GL1
        SEP     R4              ; RA -> LINE + LLEN, RC.0 = LLEN - LPOS (what moves up one)
        DW      GLPTR
GLI1:   GLO     RC
        LBZ     GLI2
        DEC     RA
        LDA     RA
        STR     RA
        DEC     RA
        DEC     RC
        LBR     GLI1
GLI2:   GLO     RB
        STR     RA
        LOAD    RD, LLEN
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4              ; the rest of the line again
        DW      GLSHOW
        SEP     R4
        DW      GLRT
        LBR     GL1
GLBS:   LOAD    RD, LPOS        ; Backspace: left, then Delete
        LDN     RD
        LBZ     GL1
        SEP     R4
        DW      GLLT
GLDEL:  SEP     R4              ; Delete: the character at the cursor goes
        DW      GLPTR
        GLO     RC
        LBZ     GL1             ; (at the end: nothing)
        LOAD    RD, LPOS
        LDN     RD
        ADI     LOW(LINE)
        PLO     RA
        LDI     HIGH(LINE)
        PHI     RA
GLD1:   DEC     RC
        GLO     RC
        LBZ     GLD2
        INC     RA
        LDN     RA
        DEC     RA
        STR     RA
        INC     RA
        LBR     GLD1
GLD2:   LOAD    RD, LLEN
        LDN     RD
        SMI     1
        STR     RD
        SEP     R4
        DW      GLSHOW
        LBR     GL1
GLESC:  SEP     R4              ; ESC [ or ESC O, then a letter, or digits and '~'
        DW      GETK
        XRI     '['
        LBNZ    GL1
        SEP     R4
        DW      GETK
        PLO     RB
        SMI     '0'
        LBNF    GL1
        SMI     10
        LBDF    GLE3            ; a letter
        GLO     RB              ; digits: RB.1 = the first, up to the '~'
        PHI     RB
GLE2:   SEP     R4
        DW      GETK
        PLO     RC
        XRI     '~'
        LBZ     GLE4
        GLO     RC              ; digits and ';' go on; any other final character (ESC [ 1 ; 5 C): ignored
        SMI     '@'
        LBNF    GLE2
        LBR     GL1
GLE4:   GHI     RB
        XRI     '3'
        LBZ     GLDEL           ; ESC [ 3 ~: Delete
        GHI     RB
        XRI     '1'
        LBZ     GLHOME
        GHI     RB
        XRI     '4'
        LBZ     GLEND2
        LBR     GL1
GLE3:   GLO     RB
        XRI     'D'
        LBNZ    GLE5
        LOAD    RD, LPOS        ; left
        LDN     RD
        LBZ     GL1
        SEP     R4
        DW      GLLT
        LBR     GL1
GLE5:   GLO     RB
        XRI     'C'
        LBNZ    GLE6
        SEP     R4              ; right
        DW      GLPTR
        GLO     RC
        LBZ     GL1
        SEP     R4
        DW      GLRT
        LBR     GL1
GLE6:   GLO     RB
        XRI     'H'
        LBZ     GLHOME
        GLO     RB
        XRI     'F'
        LBZ     GLEND2
        GLO     RB
        XRI     'A'
        LBNZ    GL1
        SEP     R4              ; up: the last line instead of this one - this one blanked with spaces, then
        DW      GLHM            ;  back (no ESC [ K: the BIOS's F_TYPE does not pass ESC on, on Craig's Elf2K)
        LOAD    RD, LLEN
        LDN     RD
        PLO     R8
        PHI     R8
GLU1:   GLO     R8
        LBZ     GLU2
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        DEC     R8
        LBR     GLU1
GLU2:   GHI     R8
        LBZ     GLU3
        LDI     08H
        SEP     R4
        DW      F_TYPE
        GHI     R8
        SMI     1
        PHI     R8
        LBR     GLU2
GLU3:
        LOAD    RA, HIST        ; HIST -> LINE; LLEN = its length
        LOAD    RD, LINE
        LDI     0
        PLO     RC
GLU4:   LDA     RA
        LBZ     GLU5
        STR     RD
        INC     RD
        INC     RC
        GLO     RC
        XRI     LINEMAX
        LBNZ    GLU4
GLU5:   LOAD    RD, LLEN
        GLO     RC
        STR     RD
        SEP     R4
        DW      GLSHOW
GLEND2: SEP     R4              ; End: right to the end
        DW      GLPTR
        GLO     RC
        LBZ     GL1
        SEP     R4
        DW      GLRT
        LBR     GLEND2
GLHOME: SEP     R4
        DW      GLHM
        LBR     GL1
GLCC:   LDI     1               ; Ctrl-C
        SHR
        SEP     R5
GLEND:  LDI     0DH             ; Enter (echoed, as the BIOS's line input did): 0-ended; kept as the last line
        SEP     R4
        DW      F_TYPE
        LOAD    RD, LLEN
        LDN     RD
        LBZ     GLN3
        ADI     LOW(LINE)
        PLO     RA
        LDI     HIGH(LINE)
        PHI     RA
        LDI     0
        STR     RA
        LOAD    RA, LINE
        LOAD    RD, HIST
GLN2:   LDA     RA
        STR     RD
        INC     RD
        LBNZ    GLN2
GLN3:   LOAD    RA, LINE        ; (an empty line: just its 0)
        LOAD    RD, LLEN
        LDN     RD
        LBNZ    GLN4
        STR     RA
GLN4:   LDI     0
        SHR
        SEP     R5
; GLPTR: RA = LINE + LLEN, RC.0 = LLEN - LPOS.  GLSHOW: LINE from the cursor to the end, a space (for one
; that went), then back to the cursor.  GLLT / GLRT: the cursor one left / right.  GLHM: to the start.
GLPTR:  LOAD    RD, LPOS
        LDA     RD
        STR     R2
        LDN     RD
        PLO     RA
        SM
        PLO     RC
        GLO     RA
        ADI     LOW(LINE)
        PLO     RA
        LDI     HIGH(LINE)
        PHI     RA
        SEP     R5
GLSHOW: SEP     R4
        DW      GLPTR
        GLO     RC
        PLO     RB
        PLO     R8
        GLO     RA
        STR     R2
        GLO     RC
        SD
        PLO     RA              ; RA -> LINE + LPOS
GLS1:   GLO     R8              ; (R8, RA, RB: kept by F_TYPE on the Elf2K's BIOS - HW-verified in DIR, HEX)
        LBZ     GLS2
        LDA     RA
        SEP     R4
        DW      F_TYPE
        DEC     R8
        LBR     GLS1
GLS2:   LDI     ' '
        SEP     R4
        DW      F_TYPE
        INC     RB
GLS3:   LDI     08H
        SEP     R4
        DW      F_TYPE
        DEC     RB
        GLO     RB
        LBNZ    GLS3
        SEP     R5
GLLT:   LDI     08H
        SEP     R4
        DW      F_TYPE
        LOAD    RD, LPOS
        LDN     RD
        SMI     1
        STR     RD
        SEP     R5
GLRT:   LOAD    RD, LPOS
        LDN     RD
        ADI     LOW(LINE)
        PLO     RA
        LDI     HIGH(LINE)
        PHI     RA
        LDN     RA
        SEP     R4
        DW      F_TYPE
        LOAD    RD, LPOS
        LDN     RD
        ADI     1
        STR     RD
        SEP     R5
GLHM:   LOAD    RD, LPOS
        LDN     RD
        LBZ     GLH9
        SEP     R4
        DW      GLLT
        LBR     GLHM
GLH9:   SEP     R5
; GETK: the next key from the UART itself (no echo)
GETK:   LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
GK1:    INP     DATPORT
        ANI     01H
        LBZ     GK1
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SEP     R5

; ---- SKIPSP: RF past spaces.  UPCH: D in upper case.  HEXARG: RD = the next hex number at RF
;      (DF = 1 if there is none; RF past it; uses RA, RB.0).
SKIPSP: LDN     RF
        XRI     ' '
        LBNZ    SK9
        INC     RF
        LBR     SKIPSP
SK9:    SEP     R5

UPCH:   PLO     RE
        SMI     'a'
        LBNF    UP9
        SMI     26
        LBDF    UP9
        GLO     RE
        SMI     20H
        SEP     R5
UP9:    GLO     RE
        SEP     R5

HEXARG: SEP     R4
        DW      SKIPSP
        LDI     0
        PHI     RD
        PLO     RD
        PHI     RA              ; RA.1 = digits seen
HA1:    LDN     RF
        SEP     R4
        DW      UPCH
        PLO     RA
        SMI     '0'
        LBNF    HA9
        SMI     10
        LBNF    HADIG           ; 0-9
        GLO     RA
        SMI     'A'
        LBNF    HA9
        SMI     6
        LBDF    HA9
        GLO     RA
        SMI     'A'-10          ; A-F
        LBR     HA2
HADIG:  GLO     RA
        SMI     '0'
HA2:    PLO     RA              ; RD = RD x 16 + the digit
        LDI     4
        PLO     RB
HA3:    GLO     RD
        SHL
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        DEC     RB
        GLO     RB
        LBNZ    HA3
        GLO     RA
        STR     R2
        GLO     RD
        OR
        PLO     RD
        GHI     RA
        ADI     1
        PHI     RA
        INC     RF
        LBR     HA1
HA9:    GHI     RA
        LBZ     HANO
        LDI     0
        SHR                     ; DF = 0: a number
        SEP     R5
HANO:   LDI     1
        SHR                     ; DF = 1: none
        SEP     R5

; ==================================================================== phase 2: reading files
; NOMNT: the card has no FAT16 partition.  NAMEARG: RF -> a file name -> FNAME (no wildcards), the file
; found (DF = 0) - or the message given and back to MAIN.
NOMNT:  LOAD    RF, NOFAT
        SEP     R4
        DW      PSTR
        LBR     MAIN
NOFAT:  DB      'No FAT16 partition on this card.',0DH,0AH,0
NAMEARG: SEP    R4
        DW      MNTCHK
        LOAD    RD, FNAME
        SEP     R4
        DW      NAMEP
        LOAD    RD, ARGP        ; what follows the name (RUN's arguments, LOAD's address)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, FNAME       ; the pattern = the name
        LOAD    RF, PAT
        LDI     11
        PLO     RC
NA2:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    NA2
        SEP     R4
        DW      DOPEN
        SEP     R4
        DW      DNEXT
        LBDF    NOFILE
        LOAD    RD, DATTR
        LDN     RD
        ANI     10H
        LBNZ    ISDIR
        LOAD    RD, ARGP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5              ; DF = 0 (from DNEXT)
PPERR:  XRI     2               ; PARSE's DF = 1: D = 2 no such folder, else not a name
        LBNZ    BADNAME
NOFOLD: SEP     R4              ; (the folder's 11 bytes at PPRD)
        DW      PIN
        DB      'There is no folder ',0
        LOAD    RD, PPRD
        LDA     RD
        PLO     RE
        LDN     RD
        PLO     RD
        GLO     RE
        PHI     RD
        SEP     R4
        DW      PFNAMD
        SEP     R4
        DW      PCRLF
        LBR     MAIN
BADNAME: SEP    R4
        DW      PIN
        DB      'That is not a file name.',0DH,0AH,0
        LBR     MAIN
NOFILE: SEP     R4
        DW      PIN
        DB      'There is no file ',0
        SEP     R4
        DW      PFNAME
        SEP     R4
        DW      PCRLF
        LBR     MAIN
ISDIR:  SEP     R4
        DW      PFNAME
        SEP     R4
        DW      PIN
        DB      ' is a folder.',0DH,0AH,0
        LBR     MAIN
; MNTCHK: back to MAIN with a message if the card has no FAT16 partition
MNTCHK: LOAD    RD, MOUNTED
        LDN     RD
        LBZ     NOMNT
        SEP     R5
; NAMEP: RF -> a name -> 11 bytes at RD (kept); no wildcards. Not a name: the message, back to MAIN.
NAMEP:  SEP     R4
        DW      PARSE
        LBDF    PPERR
        GHI     RD
        PHI     RC
        GLO     RD
        PLO     RC
        LDI     11
        PLO     RB
NP1:    LDA     RC
        XRI     '?'
        LBZ     BADNAME
        DEC     RB
        GLO     RB
        LBNZ    NP1
        SEP     R5
; PFNAME: FNAME as NAME.EXT (PFNAMD: the 11 bytes at RD)
PFNAME: LOAD    RD, FNAME
PFNAMD: LDI     8
        PLO     RB
PF1:    LDA     RD
        XRI     ' '
        LBZ     PF2
        XRI     ' '
        SEP     R4
        DW      F_TYPE
PF2:    DEC     RB
        GLO     RB
        LBNZ    PF1
        LDN     RD
        XRI     ' '
        LBZ     PF9             ; no extension
        LDI     '.'
        SEP     R4
        DW      F_TYPE
        LDI     3
        PLO     RB
PF3:    LDA     RD
        XRI     ' '
        LBZ     PF4
        XRI     ' '
        SEP     R4
        DW      F_TYPE
PF4:    DEC     RB
        GLO     RB
        LBNZ    PF3
PF9:    SEP     R5

; ---- LOAD name [addr] / RUN name [args]
; A program file: 6 bytes - load address, length, start address (big-endian) - then the code.
; ---- LOAD is LOAD.PRG (load.asm) since LTOS 0.5
C_RUN:  SEP     R4
        DW      NAMEARG
RUNIT:  SEP     R4
        DW      PROGHDR
        LBDF    NOTPROG
        SEP     R4
        DW      LOADF
        LBDF    LDFAIL
        LOAD    RD, LDEXEC      ; patch the call below with its start
        LOAD    RF, RUNCALL+1
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, CWD         ; it starts in the current folder (it may have come from the root)
        LOAD    RF, WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, ARGP        ; RF -> the rest of the line, for the program
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      SKIPSP
        SEX     R2
RUNCALL: SEP    R4              ; (patched) CALL the program; it ends with SEP R5
        DW      0
        LOAD    R6, MAIN        ; LTOS's SCRT again, in case the program changed R4 / R5
        LBR     KINIT
NOTPROG: SEP    R4
        DW      PFNAME
        SEP     R4
        DW      PIN
        DB      ' is not a program (no LTOS header).',0DH,0AH,0
        LBR     MAIN
TOOBIG: SEP     R4
        DW      PIN
        DB      'It does not fit in $3000-$6BFF.',0DH,0AH,0
        LBR     MAIN
LDFAIL: SEP     R4
        DW      PIN
        DB      'The file could not be read.',0DH,0AH,0
        LBR     MAIN
; FITS: R7 bytes at LDDST: DF = 0 if $3000 <= LDDST and LDDST + R7 <= $6C00, or all of it in $7700-$7BFF
;      (HIGHLO-HIGHHI: free RAM above LTOS's buffers - STLRX.PRG runs there, so an app's file has $3000-$6BFF)
FITS:   LOAD    RD, LDDST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        SMI     LOW(PROGLO)
        GHI     RC
        SMBI    HIGH(PROGLO)
        LBNF    FTNO
        GLO     R7              ; RC = the end
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     R7
        STR     R2
        GHI     RC
        ADC
        PHI     RC
        LBDF    FTNO            ; past $FFFF
        GLO     RC
        SDI     LOW(PROGHI)
        GHI     RC
        SDBI    HIGH(PROGHI)
        LBDF    FTOK
        GLO     RC              ; else: in $7700-$7BFF?
        SDI     LOW(HIGHHI)
        GHI     RC
        SDBI    HIGH(HIGHHI)
        LBNF    FTNO
        LOAD    RD, LDDST
        LDN     RD
        SMI     HIGH(HIGHLO)
        LBNF    FTNO
FTOK:   LDI     0
        SHR
        SEP     R5
FTNO:   LDI     1
        SHR
        SEP     R5
; PROGHDR: the file's first sector: a header that fits? -> LDDST, LDEXEC, LDSKIP = 6. DF = 1: not a program.
PROGHDR: SEP    R4
        DW      FOPEN
        SEP     R4
        DW      FREAD
        LBDF    PHNO
        GLO     RC              ; at least the header
        SMI     6
        GHI     RC
        SMBI    0
        LBNF    PHNO
        LOAD    RF, DATBUF
        LOAD    RD, LDDST
        LDA     RF              ; load address
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        LDA     RF              ; length -> R7
        PHI     R7
        LDA     RF
        PLO     R7
        LOAD    RD, LDEXEC
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        GHI     R7              ; at least 1 byte
        LBNZ    PH1
        GLO     R7
        LBZ     PHNO
PH1:    SEP     R4
        DW      FITS
        LBDF    PHNO
        LOAD    RD, LDEXEC      ; LDDST <= start < LDDST + length
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, LDDST+1
        SEX     RD
        GLO     RC
        SM
        PLO     RB
        DEC     RD
        GHI     RC
        SMB
        PHI     RB              ; RB = start - LDDST
        SEX     R2
        LBNF    PHNO            ; the start is before the program
        GLO     RB              ; length - (start - LDDST) must be more than 0
        STR     R2
        GLO     R7
        SM
        PLO     RC
        GHI     RB
        STR     R2
        GHI     R7
        SMB
        PHI     RC
        LBNF    PHNO
        GLO     RC
        LBNZ    PH3
        GHI     RC
        LBZ     PHNO
PH3:    LOAD    RD, LDSKIP
        LDI     6
        STR     RD
        LDI     0
        SHR
        SEP     R5
PHNO:   LDI     1
        SHR
        SEP     R5
; LOADF: the file (from its start) to LDDST, the first LDSKIP bytes left out. LDEND = where it ended.
; DF = 1: it could not be read to its end.
LOADF:  SEP     R4
        DW      FOPEN
        LOAD    RD, LDDST
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA              ; RA = where the next byte goes
        LOAD    RD, LDSKIP
        LDN     RD
        PLO     R9              ; R9.0 = bytes still to skip
LF1:    SEP     R4
        DW      FREAD
        LBDF    LF9
        LOAD    RF, DATBUF
LF2:    GHI     RC
        LBNZ    LF3
        GLO     RC
        LBZ     LF1
LF3:    DEC     RC
        LDA     RF
        PLO     RB
        GLO     R9
        LBZ     LF4
        DEC     R9
        LBR     LF2
LF4:    GLO     RB
        STR     RA
        INC     RA
        LBR     LF2
LF9:    PHI     R9              ; (FREAD's D: LOAD below would lose it)
        LOAD    RD, LDEND
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        GHI     R9
        XRI     2               ; D = 2: it failed; else the end: DF = 0
        LBZ     LF8
        LDI     0
        SHR
        SEP     R5
LF8:    LDI     1
        SHR
        SEP     R5
; ==================================================================== phase 3: writing files
; KLOADF / KSAVEF: K_LOADF and K_SAVEF (see $030C)
KLOADF: LOAD    RD, LDDST       ; where; LDMAX = the most
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, LDMAX
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      NAMEARG
        LOAD    RD, DSIZE       ; DSIZE <= LDMAX
        SEP     R4
        DW      LD32
        GHI     R8
        LBNZ    TOOBIG
        GLO     R8
        LBNZ    TOOBIG
        LOAD    RD, LDMAX+1
        SEX     RD
        GLO     R7
        SD
        DEC     RD
        GHI     R7
        SDB
        SEX     R2
        LBNF    TOOBIG
        LOAD    RD, LDSKIP
        LDI     0
        STR     RD
        SEP     R4
        DW      LOADF
        LBDF    LDFAIL
        LOAD    RD, DSIZE+2
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, ARGP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5
KSAVER: LOAD    RF, WSRC        ; WSRC, WLEN, PFXN = 0, FNAME = the name
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        LOAD    RF, WLEN
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LOAD    RF, PFXN
        LDI     0
        STR     RF
        LOAD    RF, FNAME
        LDI     11
        PLO     RB
KR1:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    KR1
        LOAD    RD, FNAME       ; there already?
        SEP     R4
        DW      FINDN
        LBDF    KR2
        LOAD    RD, DATTR
        LDN     RD
        ANI     10H
        LBNZ    KR4
        SEP     R4
        DW      DELENT
        LDI     3
        LBDF    KR9
KR2:    LBR     WFILE           ; (its DF, D)
KR4:    LDI     4
KR9:    SMI     0               ; DF = 1, D kept
        SEP     R5
KSAVEF: LOAD    RD, WSRC        ; WSRC, WLEN from RA, RC (before NAMEP uses them)
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, WLEN
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      MNTCHK
        LOAD    RD, FNAME
        SEP     R4
        DW      NAMEP
        LOAD    RD, PFXN
        LDI     0
        STR     RD
        LBR     SV4
; YESNO: a key; DF = 1 if it was Y.  REPLQ: FNAME already on the card? A folder: no; a file: "replace it?" -
; Y deletes it, N goes back to MAIN.  WERR: WFILE's failure (D) in words, back to MAIN.
YESNO:  LOAD    RB, TTYF        ; the key and its new line on the screen, even with the output in a file;
        LDI     1               ; the question too (K_TTYON before it) - the screen ends here
        STR     RB
        SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      PCRLF
        GLO     RB
        ANI     0DFH
        XRI     'Y'
        STXD                    ; (0: Y)
        LOAD    RB, TTYF
        LDI     0
        STR     RB
        IRX
        LDX
        LBZ     YN1
        LDI     0
        LSKP
YN1:    LDI     1
        SHR
        SEP     R5
REPLQ:  LOAD    RD, FNAME
        SEP     R4
        DW      FINDN
        LBDF    RQ9             ; not there
        LOAD    RD, DATTR
        LDN     RD
        ANI     10H
        LBNZ    ISDIR
        SEP     R4              ; (the question on the screen)
        DW      TTYON
        SEP     R4
        DW      PFNAME
        SEP     R4
        DW      PIN
        DB      ' is already on the card - replace it? (Y/N) ',0
        SEP     R4
        DW      YESNO
        LBNF    MAIN
        SEP     R4
        DW      DELENT
        LBDF    CARDF
RQ9:    SEP     R5
WERR:   XRI     1
        LBNZ    WE2
        SEP     R4
        DW      PIN
        DB      'The directory is full (512 files).',0DH,0AH,0
        LBR     MAIN
WE2:    XRI     3               ; (1 xor 2)
        LBNZ    CARDF
        SEP     R4
        DW      PIN
        DB      'The card is full - nothing was saved.',0DH,0AH,0
        LBR     MAIN
CARDF:  LOAD    RF, CARDT
        SEP     R4
        DW      PSTR
        LBR     MAIN
CARDT:  DB      'The card did not answer.',0DH,0AH,0

SV4:    SEP     R4
        DW      REPLQ
        SEP     R4
        DW      WFILE
        LBDF    WERR
        SEP     R4
        DW      PIN
        DB      'Saved ',0
        SEP     R4
        DW      PFNAME
        SEP     R4
        DW      PIN
        DB      ', ',0
        LOAD    RD, WTOT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' bytes.',0DH,0AH,0
        LBR     MAIN
; ==================================================================== phase 5: folders
QNAME:  DB      '???????????'

; ---- WHERE: RF -> the path of CWD as text ("/GAMES/OLD"; "" for the root), built right to left in PWDB
;       by climbing the '..' entries. Deeper than 5: "/..." in front. A broken chain: "/?".
WHERE:  LOAD    RD, WHP         ; WHP = the end of PWDB: a 0
        LDI     HIGH(PWDB+PWDL)
        STR     RD
        INC     RD
        LDI     LOW(PWDB+PWDL)
        STR     RD
        LOAD    RD, PWDB+PWDL
        LDI     0
        STR     RD
        LOAD    RD, CWD         ; WHC = CWD
        LOAD    RC, WHC
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, WHN         ; WHN = the levels left
        LDI     5
        STR     RD
WH1:    LOAD    RD, WHC         ; the root: done
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     WH9
        LOAD    RD, WHN
        LDN     RD
        LBZ     WHDEEP
        SMI     1
        STR     RD
        LOAD    RD, WHC         ; WDIR = WHC; its parent from its '..'
        LOAD    RC, WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LOAD    RD, DOTDOT
        SEP     R4
        DW      FOLDIN          ; WDIR = the parent
        LBDF    WHBAD
        LOAD    RD, QNAME       ; its entry for WHC: a folder entry with WHC's cluster
        LOAD    RF, PAT
        LDI     11
        PLO     RB
WH2:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    WH2
        SEP     R4
        DW      DOPEN
        LOAD    RD, DNALL
        LDI     1
        STR     RD
WH3:    SEP     R4
        DW      DNEXT
        LBDF    WHBAD
        LOAD    RD, DATTR
        LDN     RD
        ANI     10H
        LBZ     WH3
        LOAD    RD, DCLUS
        LOAD    RC, WHC
        LDA     RD
        STR     R2
        LDA     RC
        XOR
        LBNZ    WH3
        LDN     RD
        STR     R2
        LDN     RC
        XOR
        LBNZ    WH3
        LOAD    RD, WHP         ; RA = WHP; its name goes in front: ext, '.', name, '/'
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        GLO     RF              ; RF = past the 11 bytes
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDI     0
        PLO     R9              ; R9.0 = the extension's characters
        LDI     3
        PLO     RB
WN1:    DEC     RF
        LDN     RF
        XRI     ' '
        LBZ     WN2
        LDN     RF
        DEC     RA
        STR     RA
        INC     R9
WN2:    DEC     RB
        GLO     RB
        LBNZ    WN1
        GLO     R9
        LBZ     WN3
        DEC     RA
        LDI     '.'
        STR     RA
WN3:    LDI     8
        PLO     RB
WN4:    DEC     RF
        LDN     RF
        XRI     ' '
        LBZ     WN5
        LDN     RF
        DEC     RA
        STR     RA
WN5:    DEC     RB
        GLO     RB
        LBNZ    WN4
        DEC     RA
        LDI     '/'
        STR     RA
        LOAD    RD, WHP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LOAD    RD, WDIR        ; climb: WHC = the parent
        LOAD    RC, WHC
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LBR     WH1
WHDEEP: LOAD    RF, WHDT        ; "/..." in front
        LBR     WHPRE
WHBAD:  LOAD    RD, WHP         ; "/?" alone
        LDI     HIGH(PWDB+PWDL)
        STR     RD
        INC     RD
        LDI     LOW(PWDB+PWDL)
        STR     RD
        LOAD    RF, WHBT
WHPRE:  LOAD    RD, WHP         ; the 4 (or 2) bytes at RF in front
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDN     RF              ; (the count first)
        PLO     RB
        GLO     RB
        STR     R2
        GLO     RF
        ADD
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
WP1:    LDN     RF
        DEC     RF
        DEC     RA
        STR     RA
        DEC     RB
        GLO     RB
        LBNZ    WP1
        LOAD    RD, WHP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
WH9:    LOAD    RD, DNALL
        LDI     0
        STR     RD
        LOAD    RD, WHP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5
WHDT:   DB      4, '/...'
WHBT:   DB      2, '/?'
DOTDOT: DB      '..         '

        INCL    "fat.asm"
        INCL    "fatw.asm"
        INCL    "ide.asm"
        INCL    "cons.asm"
        INCL    "nums.asm"
        INCL    "redir.asm"

DATEV:  DB      0, 0, 21H, 5CH  ; the time and date LTOS was built (build.py): files' dates with no clock

KEND:                           ; the kernel's image ends here (build.py: at most 21 sectors, $2CFF)
        ORG     2D00H           ; the variables: $2D00-$2DFF (STLCHK compares $2E00-$2EFF; $2F00-$2FFF spare)
BOOTR:  DS      1               ; '0' or '3'
STLN:   DS      1               ; 24: STELLAR.BIN found, its sectors in STLLST (0: none)
STLLST: DS      48
DUMPA:  DS      2               ; where DUMP goes on from
; the FAT16 layer (fat.asm)
MOUNTED: DS     1
PSTART: DS      4
FATLBA: DS      4
ROOTLBA: DS     4
DATALBA: DS     4
SPC:    DS      1
SHIFT:  DS      1
FATSZ:  DS      2
ROOTSECS: DS    2
NCLUS:  DS      2
FATCUR: DS      2
DSEC:   DS      2
DLEFT:  DS      1
DPTR:   DS      2
PAT:    DS      11
DATTR:  DS      1
DTIME:  DS      2               ; DTIME, DDATE, DCLUS: in this order (DNEXT)
DDATE:  DS      2
DCLUS:  DS      2
DSIZE:  DS      4
FCLUS:  DS      2               ; FCLUS, FSEC: in this order (FOPEN)
FSEC:   DS      1
FREM:   DS      4
; the commands
FNAME:  DS      11
NNAME:  DS      11
UKW:    DS      2
UKX:    DS      1               ; FINDE: 0 NAME.SH found, 1 NAME.PRG
UKM:    DS      1               ; 0: NAME.SH / NAME.PRG looked for, 1: SH.PRG or STELLAR.PRG
LDMAX:  DS      2
ARGP:   DS      2
NFILES: DS      2               ; NFILES, TOTAL: in this order (DIR)
TOTAL:  DS      4
LDDST:  DS      2
LDEXEC: DS      2
LDSKIP: DS      1
LDEND:  DS      2
STLRAM: DS      1               ; 1: STELLAR (this card's STELLAR.BIN) was in RAM when LTOS started
; the FAT16 write side (fatw.asm)
NFATS:  DS      1
FATDIRTY: DS    1
FHINT:  DS      2
DNALL:  DS      1               ; 1: DNEXT gives hidden and system files too
LFNON:  DS      1               ; DNEXT: in a run of long-name pieces
RLFN:   DS      1               ; the entry DNEXT gave has a long name: from LFNSEC / LFNPTR
LFNSEC: DS      2               ; LFNSEC, LFNPTR: in this order
LFNPTR: DS      2
ENTP:   DS      2
FNXT:   DS      2
WDSEC:  DS      2               ; WDSEC, WDPTR: in this order
WDPTR:  DS      2
WTOT:   DS      2               ; WTOT, WREM, WFIRST, WPREV: in this order
WREM:   DS      2
WFIRST: DS      2
WPREV:  DS      2
WCLUS:  DS      2
WLBA:   DS      4
WSLEFT: DS      1
WSRC:   DS      2
WLEN:   DS      2
PFXN:   DS      1
PFXP:   DS      2
PFXB:   DS      6
DDONE:  DS      1               ; DNEXT: the directory's end was found
WDIR:   DS      2               ; the directory DNEXT / DSLOT / DIRRD work in: 0 = the root, else its first cluster
CWD:    DS      2               ; the current folder (0: the root)
DSXC:   DS      2               ; DSLOT: the cluster a folder grows by
WATTR:  DS      1               ; WFILE: the new entry's attribute
PPRD:   DS      2               ; PARSE: where the name goes
PPTX:   DS      2               ; PARSE: the text, while it looks for a folder
PPSL:   DS      1               ; PARSE: 1 = the path had a '/'
MKPAR:  DS      2               ; MKDIR / RMDIR / REN: the folder the name is in
MKCL:   DS      2               ; MKDIR: the new folder's cluster
WHP:    DS      2               ; WHERE: the path's start so far
WHC:    DS      2               ; WHERE: the folder being named
WHN:    DS      1               ; WHERE: levels left
LPOS:   DS      1               ; GETLN: LPOS, LLEN in this order
LLEN:   DS      1
KV1END:                         ; (build.py: the first part ends by $2E00)
        ORG     2F00H           ; the rest at $2F00-$2FFF
; redirection (redir.asm)
RVARS:                          ; (RVAR reaches these)
TTYF:   DS      1               ; 1: the output to the screen for now (K_TTYON ... K_YESNO)
RAPP:   DS      1               ; 1: '>>'
RISF:   DS      1               ; 1: a file is open for the output (0: NUL)
RERR:   DS      1               ; the writer failed: 2 the card is full, 3 the card failed
RNEWF:  DS      1               ; 1: a new file (its entry made by ROPEN)
RTMP:   DS      1
RCUT:   DS      2
RNAME:  DS      11
RWDIR:  DS      2
RESEC:  DS      2               ; RESEC, REPTR: in this order
REPTR:  DS      2
ROLDCL: DS      2               ; ROLDCL, RSIZE: in this order (as DCLUS, DSIZE)
RSIZE:  DS      4
RFIRST: DS      2               ; RFIRST RPREV RNEW1 RLAST RSLEFT: in this order
RPREV:  DS      2
RNEW1:  DS      2
RLAST:  DS      2
RSLEFT: DS      1
RPTR:   DS      2
RNEWC:  DS      2
RLBA:   DS      4
ROFF:   DS      2
STT:    DS      2               ; STT, STD: in this order (little-endian, as a directory entry has them)
STD:    DS      2
KVEND:                          ; (build.py: the variables must end before PROGLO)
        END
