; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lcov3.asm - LC.OVL's part 3: Copy. Loaded by LC.PRG (OVLD) into OVLA when wanted; it uses LC.PRG's routines
;   and variables by their names (out/lcsyms.inc, written by build.py from lc.asm's listing).
;
; 5 / F5: the tagged entries (or the one under the cursor) copied to the other pane's folder, after Y / N.
;   A file: read a sector at a time (the kernel's FOPEN / FREAD, into DATBUF) and each sector written to a new
;   cluster chain (as XFER -R: FREECL, FATPUT, IDEWR); then the FAT flushed and its entry written - the old one's
;   own, its dates and attributes kept, the new chain in it. A name there already: asked (Y, N, A all, Esc stop);
;   the old file stays until the new one is whole, then its clusters are freed. A folder: made there (or the one
;   there used), and all in it copied the same way, folders in it too (8 deep; hidden files too); never into
;   itself or a folder inside it. Esc while a file is being copied: it stops there, the clusters taken given back.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
        INCL    "lc.inc"
        INCL    "out/lcsyms.inc"
DEPTH   EQU     8               ; folders in folders, at most

        ORG     OVLA
        DW      PEND            ; (this LC.PRG's: LC.PRG checks it)
        DB      3
        LBR     OCOPY

OCOPY:  SEP     R4
        DW      SDDIRS          ; SDIR = this pane's folder, DDIR = the other's
        LOAD    RD, SDIR
        LOAD    RC, DDIR
        SEP     R4
        DW      SAME2
        LBNF    CO1
        SEP     R4
        DW      MSGI
        DB      'Both panes show this folder: Copy copies to the other pane',39,'s.',0
        SEP     R5
CO1:    SEP     R4
        DW      SELECT
        LBDF    RET0
        SEP     R4              ; " Copy NAME (or 3) to /PATH? (Y/N) "
        DW      JASK
        DB      ' Copy ',0
        LOAD    RF, STO
        SEP     R4
        DW      CPYS
        SEP     R4
        DW      OTHPATH
        LOAD    RF, SQYN
        SEP     R4
        DW      ASKYN
        LBNF    JNO
        SEP     R4
        DW      TRAPON
        SEP     R4
        DW      JZERO
        LOAD    RD, REPALL      ; REPALL, CSTOP: 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, DDIR        ; the other pane's folder, kept (DDIR changes in a folder's walk)
        LOAD    RC, TOPDD
        SEP     R4
        DW      CP2
CO2:    SEP     R4
        DW      NEXTSEL         ; SNM1 = DNM = its name, JATTR
        LBDF    CO9
        LOAD    RD, TOPDD
        LOAD    RC, DDIR
        SEP     R4
        DW      CP2
        LOAD    RD, SDIR        ; its entry (32 bytes) to ENT
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, SNM1
        SEP     R4
        DW      KS_FINDN
        LBDF    JGONE
        SEP     R4
        DW      ENTCP
        LOAD    RD, JATTR
        LDN     RD
        ANI     10H
        LBZ     CO3
        SEP     R4
        DW      CPDIR
        LBR     CO4
CO3:    SEP     R4
        DW      CPFIL
CO4:    LOAD    RD, CSTOP       ; stopped (Esc, or the card / a folder full): no more
        LDN     RD
        LBZ     CO2
CO9:    SEP     R4
        DW      TRAPOFF
        LOAD    RD, OTHRL
        LDI     1
        STR     RD
        SEP     R4
        DW      JDONE
        DB      0
        LOAD    RD, JN1         ; "3 copied to /DOCS." " 1 folder made." " 2 left as they were." / "Stopped: ..."
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SCOPD
        SEP     R4
        DW      CPYS
        LOAD    RD, TOPDD       ; (the other pane's path)
        LOAD    RC, DDIR
        SEP     R4
        DW      CP2
        SEP     R4
        DW      OTHPATH
        LDI     '.'
        STR     RA
        INC     RA
        LOAD    RD, JN3
        LDN     RD
        LBZ     CO10
        LDI     ' '
        STR     RA
        INC     RA
        LOAD    RD, JN3
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SFOLD
        SEP     R4
        DW      CPYS
        LOAD    RD, JN3
        LDN     RD
        SEP     R4
        DW      PLURAL
        LOAD    RF, SMADE
        SEP     R4
        DW      CPYS
CO10:   LOAD    RD, JN2
        LDN     RD
        LBZ     CO11
        LDI     ' '
        STR     RA
        INC     RA
        LOAD    RD, JN2
        LDN     RD
        SEP     R4
        DW      U8STR
        LOAD    RF, SLEFT3
        SEP     R4
        DW      CPYS
CO11:   LOAD    RD, CSTOP
        LDN     RD
        LBZ     JSAY
        LOAD    RF, SSTOPD
        SEP     R4
        DW      CPYS
        LOAD    RD, CWHY
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      CPYS
        LBR     JSAY

; ENTCP: ENT = the 32-byte entry at RF (FINDN's or DNEXT's, in DIRBUF)
ENTCP:  LOAD    RD, ENT
        LDI     32
        PLO     RB
EC1:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    EC1
        SEP     R5

; ---- CPFIL: the file ENT copied as DNM into DDIR. JN1 + 1 (copied) or JN2 + 1 (left); CSTOP = 1: stop.
CPFIL:  LOAD    RD, WFIRST      ; no chain of its own yet (a stop now gives nothing back)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4              ; row 22: what is being copied
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',' Copying ',0
        LOAD    RC, DNM
        LOAD    RA, LBUF
        SEP     R4
        DW      NAMEFMT
        LDI     0
        STR     RA
        LOAD    RF, LBUF
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      INL
        DB      ' ...  (Esc stops)',0
        LOAD    RD, DDIR        ; there already?
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, DNM
        SEP     R4
        DW      KS_FINDN
        LBDF    CF2
        LOAD    RD, KS_DATTR    ; a folder by that name: the file is left
        LDN     RD
        ANI     10H
        LBNZ    CFLEFT
        SEP     R4              ; ESEC EPTR CLOLD: the entry to rewrite, the old file's chain
        DW      CFKEEP
        LOAD    RD, REPALL
        LDN     RD
        LBNZ    CF1
        SEP     R4              ; " NAME is there already: replace it? (Y/N/A all; Esc stops) "
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',' ',0
        LOAD    RF, LBUF
        SEP     R4
        DW      PUTS
        SEP     R4
        DW      INL
        DB      ' is there already: replace it? (Y, N, A all of them; Esc stops) ',0
        SEP     R4
        DW      KEY
        PLO     R7
        XRI     ESC
        LBZ     CFSTOP
        GLO     R7
        ANI     0DFH
        XRI     'Y'
        LBZ     CF1A
        XRI     'Y' XOR 'A'
        LBNZ    CFLEFT
        LOAD    RD, REPALL
        LDI     1
        STR     RD
CF1A:   SEP     R4              ; (the question asked: the entry found again - nothing moved meanwhile)
        DW      INL
        DB      ESC,'[22;1H',ESC,'[K',' Copying ...  (Esc stops)',0
CF1:    LOAD    RD, REPL
        LDI     1
        STR     RD
        LBR     CF3
CF2:    LOAD    RD, DDIR        ; a new name: a free entry (the folder may grow by a cluster for it)
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        SEP     R4
        DW      KS_DSLOT
        LBDF    CFFULD
        LOAD    RD, KS_WDSEC    ; WDSEC, WDPTR -> ESEC, EPTR
        LOAD    RC, ESEC
        LDI     4
        PLO     RB
CF2A:   LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    CF2A
        LOAD    RD, REPL
        LDI     0
        STR     RD
CF3:    LOAD    RD, WFIRST      ; WFIRST WPREV NEWC: 0; WSLEFT 0
        LDI     7
        PLO     RB
CF3A:   LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    CF3A
        LOAD    RD, ENT + 27    ; the file opened: DCLUS, DSIZE from its entry (little-endian there)
        LOAD    RC, KS_DCLUS
        LDN     RD
        STR     RC
        INC     RC
        DEC     RD
        LDN     RD
        STR     RC
        INC     RC
        LOAD    RD, ENT + 31
        LDI     4
        PLO     RB
CF3B:   LDN     RD
        STR     RC
        INC     RC
        DEC     RD
        DEC     RB
        GLO     RB
        LBNZ    CF3B
        SEP     R4
        DW      KS_FOPEN
CF4:    SEP     R4              ; Esc typed: stop here
        DW      POLL
        LOAD    RD, KQH
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        LBZ     CF4A
        SEP     R4
        DW      GETK
        XRI     ESC
        LBZ     CFABRT
CF4A:   SEP     R4              ; a sector (none: the end)
        DW      KS_FREAD
        LBDF    CF5
        SEP     R4
        DW      WRBLK
        LBNF    CF4
        XRI     2
        LBZ     CFFULL
        LBR     CFFAIL
CF5:    LBNZ    CFFAIL          ; (D = 2: the card failed; 0: the end)
        SEP     R4              ; the FAT, then the entry: the old one's own, with its name and the new chain
        DW      KS_FATFLUSH
        LBDF    CFFAIL
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRRD
        LBDF    CFFAIL
        LOAD    RD, EPTR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, ENT
        LDI     32
        PLO     RB
CF6:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    CF6
        LOAD    RD, EPTR        ; its name, its first cluster (26-27, low byte first; 20-21 0)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, DNM
        SEP     R4
        DW      CP11
        GLO     RC
        ADI     20 - 11
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        LDI     0
        STR     RC
        INC     RC
        STR     RC
        INC     RC
        INC     RC
        INC     RC
        INC     RC
        INC     RC
        LOAD    RD, WFIRST + 1
        LDN     RD
        STR     RC
        INC     RC
        DEC     RD
        LDN     RD
        STR     RC
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    CFFAIL
        LOAD    RD, REPL        ; the old file's clusters, now it is replaced
        LDN     RD
        LBZ     CF7
        LOAD    RD, CLOLD
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        STR     R2
        GLO     RC
        OR
        LBZ     CF7
        SEP     R4
        DW      KS_FREECH
CF7:    LOAD    RD, JN1
        LBR     CF8
CFLEFT: LOAD    RD, JN2
CF8:    LDN     RD
        ADI     1
        STR     RD
        SEP     R5
CFSTOP: LOAD    RF, SESC        ; Esc at the question: nothing more
        LBR     CFX
CFABRT: LOAD    RF, SESC        ; stopped part way: the clusters taken given back
        LBR     CFX
CFFULL: LOAD    RF, SFULL
        LBR     CFX
CFFULD: LOAD    RF, SFULD
        LBR     CFX
CFFAIL: LOAD    RF, SFAIL
CFX:    LOAD    RD, CWHY
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, WFIRST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        STR     R2
        GLO     RC
        OR
        LBZ     CFX2
        SEP     R4
        DW      KS_FREECH
CFX2:   LOAD    RD, CSTOP
        LDI     1
        STR     RD
        SEP     R5
; CFKEEP: the entry just found: ESEC (DSEC), EPTR (RF), CLOLD (DCLUS)
CFKEEP: LOAD    RD, ESEC
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
        LOAD    RD, KS_DCLUS
        LOAD    RC, CLOLD
        LBR     CP2

; WRBLK: DATBUF's 512 bytes as the new file's next sector (a new cluster when this one is full) - as XFER's.
;   DF = 1 + D: 2 the card is full, 3 the card failed
WRBLK:  LOAD    RD, WSLEFT
        LDN     RD
        LBNZ    WB4
        SEP     R4              ; a cluster for the next part
        DW      KS_FREECL
        LBDF    WBFULL
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
        LOAD    RF, KS_DATBUF
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
WBFULL: LDI     2
        LSKP
WBERR:  LDI     3
        SMI     0               ; DF = 1, D kept
        SEP     R5

; ---- CPDIR: the folder ENT copied as DNM into DDIR, and all in it: a stack of [its folder, the copy's, how many
;   of its entries are done] - each step the folder walked again to its next entry (the kernel walks one at a time)
CPDIR:  SEP     R4              ; not into itself, or a folder inside it
        DW      INSIDE
        LBDF    CFLEFT
        SEP     R4              ; the copy: the folder there by that name, or a new one (a file there: left)
        DW      MKCOPY
        LBDF    RET0
        LOAD    RD, SP3
        LDI     0
        STR     RD
        SEP     R4
        DW      PUSHL
CD1:    SEP     R4              ; the level on top: its folder walked to its next entry
        DW      TOPL            ; RF -> it: [S (2), D (2), k]
        LDA     RF
        PHI     RC
        LDA     RF
        PLO     RC
        LOAD    RD, KS_WDIR
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LDA     RF              ; DDIR = D
        PHI     RC
        LDA     RF
        PLO     RC
        LOAD    RD, DDIR
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LDN     RF              ; k, then k + 1 kept
        PLO     R8
        ADI     1
        STR     RF
        LOAD    RD, KS_PAT      ; every name, hidden ones too
        LDI     11
        PLO     RB
CD2:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    CD2
        SEP     R4
        DW      KS_DOPEN
        LOAD    RD, KS_DNALL
        LDI     1
        STR     RD
        INC     R8
CD3:    GLO     R8              ; past k of them, to the next
        STXD
        SEP     R4
        DW      KS_DNEXT
        IRX
        LDX
        PLO     R8
        LBDF    CD8             ; none left: this level done
        DEC     R8
        GLO     R8
        LBNZ    CD3
        SEP     R4
        DW      ENTCP           ; ENT = it; DNM = its name
        LOAD    RD, ENT
        LOAD    RC, DNM
        SEP     R4
        DW      CP11
        LOAD    RD, ENT + 11
        LDN     RD
        ANI     10H
        LBNZ    CD5
        SEP     R4              ; a file
        DW      CPFIL
        LOAD    RD, CSTOP
        LDN     RD
        LBZ     CD1
        SEP     R5
CD5:    LOAD    RD, SP3         ; a folder: one level down (8 at most: deeper ones left)
        LDN     RD
        XRI     DEPTH
        LBZ     CD6
        SEP     R4
        DW      MKCOPY
        LBDF    CD1
        SEP     R4
        DW      PUSHL
        LBR     CD1
CD6:    LOAD    RD, JN2
        LDN     RD
        ADI     1
        STR     RD
        LBR     CD1
CD8:    LOAD    RD, SP3         ; up a level (the last: done)
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    CD1
        SEP     R5
; MKCOPY: the copy of folder ENT (its cluster: MCL) named DNM in DDIR: the folder there, or made (JN3 + 1).
;   DF = 1: a file has that name there (left: JN2 + 1)
MKCOPY: LOAD    RD, ENT + 27
        LOAD    RC, MCL
        LDN     RD
        STR     RC
        INC     RC
        DEC     RD
        LDN     RD
        STR     RC
        LOAD    RD, DDIR
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, DNM
        SEP     R4
        DW      KS_FINDN
        LBDF    MC2
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    MC3
        LOAD    RD, JN2
        LDN     RD
        ADI     1
        STR     RD
        LBR     GRYES
MC2:    LOAD    RD, DNM         ; made (mkfold.inc's MK1, as MKDIR)
        LOAD    RC, KS_FNAME
        SEP     R4
        DW      CP11
        LOAD    RD, DDIR
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        SEP     R4
        DW      MK1
        LOAD    RD, JN3
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, DDIR        ; found again: its cluster
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LOAD    RD, DNM
        SEP     R4
        DW      KS_FINDN
        LBDF    KS_CARDF
MC3:    LOAD    RD, KS_DCLUS    ; NEWD = the copy's cluster
        LOAD    RC, NEWD
        SEP     R4
        DW      CP2
        LBR     GRNO
; PUSHL: a level on the stack: [MCL, NEWD, 0]; SP3 + 1.  TOPL: RF -> the top one.
PUSHL:  LOAD    RD, SP3
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      TOPL
        LOAD    RD, MCL
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LOAD    RD, NEWD
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        SEP     R5
TOPL:   LOAD    RD, SP3         ; RF = STK + 5 x (SP3 - 1)
        LDN     RD
        SMI     1
        PLO     R7
        SHL
        SHL
        STR     R2
        GLO     R7
        ADD
        ADI     LOW(STK)
        PLO     RF
        LDI     HIGH(STK)
        ADCI    0
        PHI     RF
        SEP     R5
; INSIDE: DF = 1 if DDIR is the folder ENT, or inside it (up from DDIR to the root by the '..' entries)
INSIDE: LOAD    RD, ENT + 27
        LOAD    RC, MCL
        LDN     RD
        STR     RC
        INC     RC
        DEC     RD
        LDN     RD
        STR     RC
        LOAD    RD, DDIR
        LOAD    RC, KS_WDIR
        SEP     R4
        DW      CP2
        LDI     64
        PLO     R9
IN1:    LOAD    RD, KS_WDIR
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     GRNO            ; the root: not inside
        DEC     RD
        LOAD    RC, MCL
        SEP     R4
        DW      SAME2
        LBDF    RET0
        GLO     R9
        STXD
        LOAD    RD, DOTDOT
        SEP     R4
        DW      KS_FOLDIN
        IRX
        LDX
        PLO     R9
        LBDF    GRYES           ; (a broken chain: as if inside - nothing done)
        DEC     R9
        GLO     R9
        LBNZ    IN1
        LBR     GRYES
        INCL    "mkfold.inc"
        INCL    "lcjobs.inc"

SCOPD:  DB      ' copied to ',0
SMADE:  DB      ' made.',0
SLEFT3: DB      ' left as they were.',0
SSTOPD: DB      ' Stopped: ',0
SESC:   DB      'Esc.',0
SFULL:  DB      'the card is full.',0
SFULD:  DB      'that folder is full.',0
SFAIL:  DB      'the card failed.',0
REPALL: DS      1               ; REPALL, CSTOP: in this order - 1: replace every one without asking
CSTOP:  DS      1               ; 1: stop
CWHY:   DS      2               ; why it stopped (its text)
TOPDD:  DS      2               ; the other pane's folder
ESEC:   DS      2               ; ESEC, EPTR: the new entry's sector, where in DIRBUF
EPTR:   DS      2
CLOLD:  DS      2               ; the file it replaces: its first cluster
REPL:   DS      1               ; 1: replacing
WFIRST: DS      2               ; WFIRST WPREV NEWC WSLEFT: the new chain - its first cluster, its last, a new one
WPREV:  DS      2
NEWC:   DS      2
WSLEFT: DS      1               ; sectors left in this cluster
WLBA:   DS      4               ; the next sector
NEWD:   DS      2               ; MKCOPY: the copy folder's cluster
SP3:    DS      1               ; the levels on the stack
STK:    DS      5 * DEPTH
OVEND:
        END
