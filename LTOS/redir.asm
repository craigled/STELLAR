; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; redir.asm - LTOS-SH's output redirection (INCL'd by the kernel): "> NAME", ">> NAME" and "> NUL" anywhere in a
; command line, outside quotes. REDIR (MAIN, once the line is typed) takes it out of the line and opens the file;
; then every character a program prints - F_TYPE, F_MSG, PIN ... all come to KOUT (the kernel's SCRT) - goes into
; OBUF ($7400-$75FF), a full one written as the file's next sector. The CR of each CR LF is dropped (LF line
; ends, as Linux's and RAWK -o's). RCLOSE (MAIN, before the prompt) writes the rest and the entry: the file's
; first cluster, size and time. ">" keeps the old file until then (its clusters are given back after the
; switch); ">>" goes on from the old file's end. The card full (or failing) partway: nothing more is written,
; the clusters taken are given back, the file is as it was, and RCLOSE says so. A new file's entry is made at
; once (so nothing else the command does takes it). A question still reaches the screen: K_TTYON first, then
; K_YESNO (which ends it). KRDIR ($033E): 0 the screen, 1 a file, 2 nowhere (NUL, or a file that failed).
OBUF    EQU     7400H

; RVAR: RD = RVARS + the byte after the call (SEP R4 / DW RVAR / DB X - RVARS: 4 bytes, not LOAD's 8)
RVAR:   LDA     R6
        ADI     LOW(RVARS)
        PLO     RD
        LDI     HIGH(RVARS)
        ADCI    0
        PHI     RD
        SEP     R5

; ---- REDIR: DF = 0: no '>', or the file is open (KRDIR set); DF = 1: it could not be (said why), KSTAT = 1
REDIR:  LOAD    RD, KSTAT       ; every command starts as all right
        LDI     0
        STR     RD
        LOAD    RF, LINE
        LDI     0
        PLO     RB              ; RB.0 = the quote the scan is in (0: none)
RE1:    LDA     RF
        LBZ     RENO            ; no '>': nothing to do
        PHI     RB
        GLO     RB
        LBZ     RE2
        STR     R2              ; in quotes: the closing one?
        GHI     RB
        XOR
        LBNZ    RE1
        PLO     RB
        LBR     RE1
RE2:    GHI     RB
        XRI     27H
        LBZ     REQ
        XRI     27H XOR 22H
        LBZ     REQ
        XRI     22H XOR '>'
        LBNZ    RE1
        LBR     RE3
REQ:    GHI     RB              ; a quote opens
        PLO     RB
        LBR     RE1
RENO:   LDI     0
        SHR
        SEP     R5
RE3:    GHI     RF              ; RC = the '>' (RF is past it) ...
        PHI     RC
        GLO     RF
        PLO     RC
        DEC     RC
RE3A:   GLO     RC              ; ... and back over the spaces before it: the line is cut there
        XRI     LOW(LINE)
        LBNZ    RE3B
        GHI     RC
        XRI     HIGH(LINE)
        LBZ     RE3C
RE3B:   DEC     RC
        LDN     RC
        XRI     ' '
        LBZ     RE3A
        INC     RC
RE3C:   SEP     R4
        DW      RVAR
        DB      RCUT - RVARS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4              ; '>>': on from the file's end
        DW      RVAR
        DB      RAPP - RVARS
        LDI     0
        STR     RD
        LDN     RF
        XRI     '>'
        LBNZ    RE4
        INC     RF
        LDI     1
        STR     RD
RE4:    LDN     RF
        XRI     ' '
        LBNZ    RE5
        INC     RF
        LBR     RE4
RE5:    LDN     RF
        LBNZ    RE6
        SEP     R4
        DW      PIN
        DB      'A file name must follow the >.',0DH,0AH,0
        LBR     REBAD
RE6:    GHI     RF              ; RA = where the name starts
        PHI     RA
        GLO     RF
        PLO     RA
        LDA     RF              ; NUL: nowhere
        ANI     0DFH
        XRI     'N'
        LBNZ    RE7
        LDA     RF
        ANI     0DFH
        XRI     'U'
        LBNZ    RE7
        LDA     RF
        ANI     0DFH
        XRI     'L'
        LBNZ    RE7
        LDN     RF
        LBZ     RENUL
        XRI     ' '
        LBZ     RENUL
RE7:    GHI     RA
        PHI     RF
        GLO     RA
        PLO     RF
        SEP     R4
        DW      RVAR
        DB      RNAME - RVARS
        SEP     R4
        DW      PARSE           ; WDIR = its folder
        LBDF    REPB
        SEP     R4              ; a wildcard is not a name
        DW      RVAR
        DB      RNAME - RVARS
        LDI     11
        PLO     RB
RE7A:   LDA     RD
        XRI     '?'
        LBZ     REPN
        DEC     RB
        GLO     RB
        LBNZ    RE7A
        LDI     1
        LSKP
RENUL:  LDI     0
        STXD              ; (RISF: 1 a file, 0 NUL)
        SEP     R4
        DW      RVAR
        DB      RISF - RVARS
        IRX
        LDX
        STR     RD
        SEP     R4              ; the rest of the line moves down over "> NAME"
        DW      RVAR
        DB      RCUT - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
RECA:   LDA     RF
        STR     RC
        INC     RC
        LBNZ    RECA
        SEP     R4
        DW      RVAR
        DB      RISF - RVARS
        LDN     RD
        LBZ     REN2
        SEP     R4
        DW      ROPEN
        LBDF    REBAD
        LDI     1
        LSKP
REN2:   LDI     2
        PLO     RE
        LOAD    RD, KRDIR
        GLO     RE
        STR     RD
        LDI     0
        SHR
        SEP     R5
REPB:   XRI     2               ; PARSE's D: 2 no such folder, 3 a folder; else not a name
        LBZ     REPF
        XRI     2 XOR 3
        LBZ     ROFD
REPN:   SEP     R4
        DW      PIN
        DB      'That is not a file name.',0DH,0AH,0
        LBR     REBAD
REPF:   SEP     R4
        DW      PIN
        DB      'There is no such folder.',0DH,0AH,0
REBAD:  LOAD    RD, KSTAT
        LDI     1
        STR     RD
        SEP     R4
        DW      RWCWD
        LDI     1
        SHR
        SEP     R5

; ---- ROPEN: RNAME in WDIR, for writing: there already - its entry, its clusters and size kept (the old file stays
;      until RCLOSE); new - a free entry, with the name in it now. Then the writer's state (">>": from the old
;      file's end). DF = 1: it could not be (said why).
ROPEN:  LOAD    RD, WDIR        ; the file's folder, for RCLOSE
        LOAD    RC, RWDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R4
        DW      RVAR
        DB      RNEWF - RVARS
        LDI     0
        STR     RD
        SEP     R4
        DW      RVAR
        DB      RNAME - RVARS
        SEP     R4
        DW      FINDN
        LBDF    RO2             ; not there: a new file
        LOAD    RD, DATTR
        LDN     RD
        ANI     10H
        LBNZ    ROFD
        SEP     R4              ; its entry: its sector, where in DIRBUF
        DW      RVAR
        DB      RESEC - RVARS
        LOAD    RC, DSEC
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
        SEP     R4              ; its clusters and size (ROLDCL, RSIZE: as DCLUS, DSIZE)
        DW      RVAR
        DB      ROLDCL - RVARS
        LOAD    RC, DCLUS
        LDI     6
        PLO     RB
RO1:    LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    RO1
        LBR     RO3
RO2:    SEP     R4              ; a free entry (a folder may grow by a cluster for it)
        DW      DSLOT
        LBNF    RO2A
        SEP     R4
        DW      PIN
        DB      'The directory is full.',0DH,0AH,0
        LBR     ROERR
RO2A:   SEP     R4
        DW      RVAR
        DB      RESEC - RVARS
        LOAD    RC, WDSEC       ; WDSEC, WDPTR
        LDI     4
        PLO     RB
RO2B:   LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    RO2B
        SEP     R4              ; no clusters, no bytes
        DW      RVAR
        DB      ROLDCL - RVARS
        LDI     6
        PLO     RB
RO2C:   LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    RO2C
        SEP     R4
        DW      RVAR
        DB      RNEWF - RVARS
        LDI     1
        STR     RD
        SEP     R4              ; the entry: the name, archive, the rest 0 (an empty file)
        DW      RENTRY
        LBDF    ROCF
        LDI     32
        PLO     RB
RO2D:   LDI     0
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    RO2D
        SEP     R4
        DW      RVAR
        DB      REPTR - RVARS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      RVAR
        DB      RNAME - RVARS
        LDI     11
        PLO     RB
RO2E:   LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    RO2E
        LDI     20H
        STR     RF
        SEP     R4
        DW      RENTWR
        LBDF    ROCF
RO3:    SEP     R4              ; the writer: nothing yet
        DW      RVAR
        DB      RERR - RVARS
        LDI     0
        STR     RD
        SEP     R4              ; RFIRST RPREV RNEW1 RLAST RSLEFT: 0
        DW      RVAR
        DB      RFIRST - RVARS
        LDI     9
        PLO     RB
RO3A:   LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    RO3A
        SEP     R4
        DW      RVAR
        DB      RPTR - RVARS
        LDI     HIGH(OBUF)
        STR     RD
        INC     RD
        LDI     LOW(OBUF)
        STR     RD
        SEP     R4
        DW      RVAR
        DB      RAPP - RVARS
        LDN     RD
        LBZ     RO4             ; '>': from nothing
        SEP     R4
        DW      RVAR
        DB      ROLDCL - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    RO5
        GLO     RC
        LBNZ    RO5
RO4:    SEP     R4              ; (an empty old file: as a new one)
        DW      RVAR
        DB      RSIZE - RVARS
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LBR     RWCWD
RO5:    SEP     R4              ; '>>': its first cluster stays; its last one ...
        DW      RVAR
        DB      RFIRST - RVARS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
RO5A:   SEP     R4
        DW      RVAR
        DB      RLAST - RVARS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      FATNEXT
        LBDF    ROCF
        SEP     R4
        DW      CLVALID
        LBDF    RO5A
        SEP     R4              ; ... is where the new part links on
        DW      RVAR
        DB      RLAST - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      RVAR
        DB      RPREV - RVARS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4              ; RTMP = the sector it ends in: (RSIZE / 512) mod SPC
        DW      RVAR
        DB      RSIZE+1 - RVARS
        LDA     RD
        SHR
        LDN     RD
        SHRC
        STR     R2
        LOAD    RD, SPC
        LDN     RD
        SMI     1
        AND
        STXD
        SEP     R4
        DW      RVAR
        DB      RTMP - RVARS
        IRX
        LDX
        STR     RD
        SEP     R4              ; ROFF = the bytes in that sector: RSIZE mod 512
        DW      RVAR
        DB      RSIZE+2 - RVARS
        LDA     RD
        ANI     1
        PHI     RA
        LDN     RD
        PLO     RA
        SEP     R4
        DW      RVAR
        DB      ROFF - RVARS
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R4              ; both 0: the last cluster is full - the next part takes a new one
        DW      RVAR
        DB      RTMP - RVARS
        LDN     RD
        LBNZ    RO6
        GHI     RA
        LBNZ    RO6
        GLO     RA
        LBZ     RWCWD
RO6:    SEP     R4              ; RLBA = its sector, RSLEFT = the sectors from there to the cluster's end
        DW      CL2LBA
        SEP     R4
        DW      RVAR
        DB      RTMP - RVARS
        LDN     RD
        PLO     RC
        LDI     0
        PHI     RC
        SEP     R4
        DW      ADD16
        SEP     R4
        DW      RVAR
        DB      RLBA - RVARS
        SEP     R4
        DW      ST32
        SEP     R4
        DW      RVAR
        DB      RSLEFT - RVARS
        LOAD    RC, SPC
        LDN     RC
        STR     R2
        LOAD    RC, RTMP
        LDN     RC
        SD
        STR     RD
        SEP     R4              ; a part of a sector: it into OBUF, written again with the new bytes after it
        DW      RVAR
        DB      ROFF - RVARS
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     RWCWD
        SEP     R4
        DW      RVAR
        DB      RLBA - RVARS
        SEP     R4
        DW      LD32
        LOAD    RF, OBUF
        SEP     R4
        DW      IDERD
        LBDF    ROCF
        SEP     R4              ; RPTR = OBUF + it
        DW      RVAR
        DB      ROFF - RVARS
        LOAD    RC, RPTR
        LDA     RD
        ADI     HIGH(OBUF)
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R4              ; RSIZE: to that sector's start (the bytes in OBUF are added at RCLOSE)
        DW      RVAR
        DB      RSIZE+2 - RVARS
        LDN     RD
        ANI     0FEH
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LBR     RWCWD
ROFD:   SEP     R4
        DW      PIN
        DB      'That is a folder.',0DH,0AH,0
        LBR     ROERR
ROCF:   SEP     R4
        DW      PIN
        DB      'The card did not answer.',0DH,0AH,0
ROERR:  LDI     1
        SHR
        SEP     R5
; RWCWD: WDIR = CWD (DF = 0)
RWCWD:  LOAD    RD, CWD
        LOAD    RC, WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        LDI     0
        SHR
        SEP     R5
; RENTRY: the file's entry - its folder (WDIR = RWDIR), its sector in DIRBUF, RF -> it. RENTWR: written back.
RENTRY: SEP     R4
        DW      RVAR
        DB      RWDIR - RVARS
        LOAD    RC, WDIR
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
        SEP     R4
        DW      RESC
        SEP     R4
        DW      DIRRD
        LBDF    REN9
        SEP     R4
        DW      RVAR
        DB      REPTR - RVARS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDI     0
        SHR
REN9:   SEP     R5
RENTWR: SEP     R4
        DW      RESC
        LBR     DIRWR
RESC:   SEP     R4
        DW      RVAR
        DB      RESEC - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R5

; ---- KOUT: D to where the output goes (every register kept, D too). TTYF: the screen whatever KRDIR says.
KOUT:   STXD                    ; the character (for the end)
        PLO     RE
        GLO     RF
        STXD
        GHI     RF
        STXD
        GLO     RD
        STXD
        GHI     RD
        STXD
        LOAD    RD, KRDIR
        LDN     RD
        LBZ     KOS             ; the screen
        LOAD    RD, TTYF
        LDN     RD
        LBNZ    KOS
        LOAD    RD, KRDIR
        LDN     RD
        XRI     1
        LBNZ    KOX             ; nowhere
        GLO     RE
        XRI     0DH
        LBZ     KOX             ; CR LF -> LF
        LOAD    RD, RPTR
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
        XRI     HIGH(OBUF + 512)
        LBNZ    KOX
        SEP     R4              ; a full OBUF: the file's next sector
        DW      RFLUSH
KOX:    IRX
        LDXA
        PHI     RD
        LDXA
        PLO     RD
        LDXA
        PHI     RF
        LDXA
        PLO     RF
        LDX
        SEP     R5
KOS:    IRX
        LDXA
        PHI     RD
        LDXA
        PLO     RD
        LDXA
        PHI     RF
        LDXA
        PLO     RF
        LDX
        LBR     F_TYPE
; KMSG: F_MSG's string at RF, a character at a time through KOUT (RF ends past its 0, as the BIOS's)
KMSG:   LDA     RF
        BZ      KM9
        SEP     R4
        DW      KOUT
        BR      KMSG
KM9:    SEP     R5
; TTYON (K_TTYON): the output to the screen until the next K_YESNO's answer (or the prompt). Every register kept.
TTYON:  STXD
        GLO     RD
        STXD
        GHI     RD
        STXD
        SEP     R4
        DW      RVAR
        DB      TTYF - RVARS
        LDI     1
        STR     RD
        IRX
        LDXA
        PHI     RD
        LDXA
        PLO     RD
        LDX
        SEP     R5

; ---- RFLUSH: OBUF as the file's next sector; RSIZE + 512; RPTR = OBUF. A failure: RERR = it, KRDIR = 2 (nothing
;      more). Registers kept (R7 - RD, RF).
RFLUSH: GHI     R7
        STXD
        GLO     R7
        STXD
        GHI     R8
        STXD
        GLO     R8
        STXD
        GHI     R9
        STXD
        GLO     R9
        STXD
        GHI     RA
        STXD
        GLO     RA
        STXD
        GHI     RB
        STXD
        GLO     RB
        STXD
        GHI     RC
        STXD
        GLO     RC
        STXD
        GHI     RD
        STXD
        GLO     RD
        STXD
        GHI     RF
        STXD
        GLO     RF
        STXD
        SEP     R4
        DW      RWRBLK
        LBNF    RFL2
        STXD
        SEP     R4
        DW      RVAR
        DB      RERR - RVARS
        IRX
        LDX
        STR     RD
        LOAD    RD, KRDIR
        LDI     2
        STR     RD
        BR      RFL3
RFL2:   SEP     R4              ; RSIZE + 512
        DW      RVAR
        DB      RSIZE+2 - RVARS
        LDN     RD
        ADI     2
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
RFL3:   SEP     R4
        DW      RVAR
        DB      RPTR - RVARS
        LDI     HIGH(OBUF)
        STR     RD
        INC     RD
        LDI     LOW(OBUF)
        STR     RD
        IRX
        LDXA
        PLO     RF
        LDXA
        PHI     RF
        LDXA
        PLO     RD
        LDXA
        PHI     RD
        LDXA
        PLO     RC
        LDXA
        PHI     RC
        LDXA
        PLO     RB
        LDXA
        PHI     RB
        LDXA
        PLO     RA
        LDXA
        PHI     RA
        LDXA
        PLO     R9
        LDXA
        PHI     R9
        LDXA
        PLO     R8
        LDXA
        PHI     R8
        LDXA
        PLO     R7
        LDX
        PHI     R7
        SEP     R5
; RWRBLK: OBUF's 512 bytes as the file's next sector (a new cluster when this one is full). DF = 1 + D:
;         2 the card is full, 3 the card failed. RNEW1: the first cluster it took.
RWRBLK: SEP     R4
        DW      RVAR
        DB      RSLEFT - RVARS
        LDN     RD
        LBNZ    RW4
        SEP     R4              ; a cluster for the next part
        DW      FREECL
        LBDF    RWFULL
        SEP     R4
        DW      RVAR
        DB      RNEWC - RVARS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      RVAR
        DB      RNEW1 - RVARS
        LDA     RD
        STR     R2
        LDN     RD
        OR
        BNZ     RW1
        GLO     RC
        STR     RD
        DEC     RD
        GHI     RC
        STR     RD
RW1:    LOAD    R9, 0FFFFH      ; it ends the chain ...
        SEP     R4
        DW      FATPUT
        LBDF    RWERR
        SEP     R4              ; ... and the last one points at it (or it is the first)
        DW      RVAR
        DB      RPREV - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      RVAR
        DB      RNEWC - RVARS
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        GHI     RC
        BNZ     RW2
        GLO     RC
        BNZ     RW2
        SEP     R4
        DW      RVAR
        DB      RFIRST - RVARS
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        BR      RW3
RW2:    SEP     R4
        DW      FATPUT
        LBDF    RWERR
RW3:    SEP     R4              ; RPREV = it; RLBA = its first sector, RSLEFT = its sectors
        DW      RVAR
        DB      RNEWC - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      RVAR
        DB      RPREV - RVARS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      CL2LBA
        SEP     R4
        DW      RVAR
        DB      RLBA - RVARS
        SEP     R4
        DW      ST32
        LOAD    RD, SPC
        LDN     RD
        PLO     RB
        SEP     R4
        DW      RVAR
        DB      RSLEFT - RVARS
        GLO     RB
        STR     RD
RW4:    SEP     R4              ; the sector
        DW      RVAR
        DB      RLBA - RVARS
        SEP     R4
        DW      LD32
        LOAD    RF, OBUF
        SEP     R4
        DW      IDEWR
        LBDF    RWERR
        SEP     R4
        DW      RVAR
        DB      RLBA - RVARS
        SEP     R4
        DW      LD32
        LOAD    RC, 1
        SEP     R4
        DW      ADD16
        SEP     R4
        DW      RVAR
        DB      RLBA - RVARS
        SEP     R4
        DW      ST32
        SEP     R4
        DW      RVAR
        DB      RSLEFT - RVARS
        LDN     RD
        SMI     1
        STR     RD
        LDI     0
        SHR
        SEP     R5
RWFULL: LDI     2
        LSKP
RWERR:  LDI     3
        SMI     0               ; DF = 1, D kept
        SEP     R5

; ---- RCLOSE: (MAIN, before the prompt) the output back to the screen; a file: its last part (0s after it), the
;      FAT, its entry (first cluster, size, time), then the old file's clusters (">"). A failure: the clusters it
;      took given back (">>": the old file's last cluster ends the chain again), said, KSTAT = 1.
RCLOSE: SEP     R4
        DW      RVAR
        DB      TTYF - RVARS
        LDI     0
        STR     RD
        LOAD    RD, KRDIR
        LDN     RD
        LBZ     RCX
        LDI     0
        STR     RD
        SEP     R4
        DW      RVAR
        DB      RISF - RVARS
        LDN     RD
        LBZ     RCX             ; NUL
        LDI     0
        STR     RD
        SEP     R4
        DW      RVAR
        DB      RERR - RVARS
        LDN     RD
        LBNZ    RCF
        SEP     R4              ; RC = the bytes in OBUF; RSIZE + them
        DW      RVAR
        DB      RPTR - RVARS
        LDA     RD
        SMI     HIGH(OBUF)
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      RVAR
        DB      RSIZE+3 - RVARS
        GLO     RC
        STR     R2
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        GHI     RC
        STR     R2
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        GHI     RC              ; any? then 0s to the sector's end, and it is written
        BNZ     RC1
        GLO     RC
        BZ      RC3
RC1:    SEP     R4
        DW      RVAR
        DB      RPTR - RVARS
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
RC2:    LDI     0
        STR     RF
        INC     RF
        GHI     RF
        XRI     HIGH(OBUF + 512)
        BNZ     RC2
        SEP     R4
        DW      RWRBLK
        LBDF    RCF0
RC3:    SEP     R4
        DW      FATFLUSH
        LBDF    RCF3
        SEP     R4
        DW      STAMP
        SEP     R4
        DW      RENTRY
        LBDF    RCF3
        GLO     RF              ; 11: archive
        ADI     11
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LDN     RF
        ORI     20H
        STR     RF
        INC     RF              ; 14-19 (a new file): created, used
        INC     RF
        INC     RF
        SEP     R4
        DW      RVAR
        DB      RNEWF - RVARS
        LDN     RD
        BZ      RC4
        SEP     R4
        DW      PUTST
        LOAD    RD, STD
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        DEC     RF
        DEC     RF
        DEC     RF
        DEC     RF
        DEC     RF
RC4:    GLO     RF              ; 22-25 written
        ADI     8
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        SEP     R4
        DW      PUTST
        SEP     R4              ; 26-27 the first cluster, 28-31 the size (little-endian)
        DW      RVAR
        DB      RFIRST - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        SEP     R4
        DW      RVAR
        DB      RSIZE+3 - RVARS
        LDI     4
        PLO     RB
RC5:    LDN     RD
        STR     RF
        INC     RF
        DEC     RD
        DEC     RB
        GLO     RB
        BNZ     RC5
        SEP     R4
        DW      RENTWR
        LBDF    RCF3
        SEP     R4              ; '>': the old file's clusters
        DW      RVAR
        DB      RAPP - RVARS
        LDN     RD
        LBNZ    RWCWD
        SEP     R4
        DW      RVAR
        DB      ROLDCL - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        BNZ     RC6
        GLO     RC
        LBZ     RWCWD
RC6:    SEP     R4
        DW      FREECH
        LBR     RWCWD
RCX:    SEP     R5
RCF3:   LDI     3
RCF0:   STXD
        SEP     R4
        DW      RVAR
        DB      RERR - RVARS
        IRX
        LDX
        STR     RD
RCF:    SEP     R4              ; ">>": the old last cluster ends the chain again
        DW      RVAR
        DB      RLAST - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        BNZ     RCF1
        GLO     RC
        BZ      RCF2
RCF1:   LOAD    R9, 0FFFFH
        SEP     R4
        DW      FATPUT
RCF2:   SEP     R4              ; the clusters taken: free again
        DW      RVAR
        DB      RNEW1 - RVARS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        BNZ     RCF4
        GLO     RC
        BNZ     RCF4
        SEP     R4
        DW      FATFLUSH
        BR      RCF5
RCF4:   SEP     R4
        DW      FREECH
RCF5:   SEP     R4
        DW      RVAR
        DB      RERR - RVARS
        LDN     RD
        XRI     2
        BNZ     RCF6
        SEP     R4
        DW      PIN
        DB      'The card is full - ',0
        BR      RCF7
RCF6:   SEP     R4
        DW      PIN
        DB      'The card did not answer - ',0
RCF7:   SEP     R4
        DW      RVAR
        DB      RNAME - RVARS
        SEP     R4
        DW      PFNAMD
        SEP     R4
        DW      PIN
        DB      ' is as it was.',0DH,0AH,0
        LOAD    RD, KSTAT
        LDI     1
        STR     RD
        LBR     RWCWD
