; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; fsck.asm - FSCK.PRG: FSCK [-F] - checks the card's FAT16: every folder (read raw - the Mac's hidden files too),
;   every file's chain of clusters, the clusters nobody owns, and the FAT's two copies.
;     a cross-link    a cluster in two files' chains           (reported; not mended)
;     a broken chain  a chain that runs off the card or into a free cluster (reported)
;     a size mismatch the chain is longer or shorter than the size needs   (reported)
;     lost clusters   in use in the FAT, in no file's chain: FSCK -F frees them (after a Y)
;     the FAT copies  sectors where FAT 2 is not FAT 1                     (reported)
;   Folders are gone into only if their own chain is sound (a broken folder cannot send it round in a loop).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
WMAX    EQU     10
PMAXL   EQU     120

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
        LOAD    RD, LINES       ; LINES ... NDIFF: 0
        LDI     NVARS
        PLO     RB
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST1
        LDN     RF              ; -F: mend
        XRI     '-'
        LBNZ    ST2
        INC     RF
        LDA     RF
        ORI     20H
        XRI     'f'
        LBNZ    USE
        LOAD    RD, FFIX
        LDI     1
        STR     RD
        LBR     ST3
ST2:    LDN     RF
        LBNZ    USE
ST3:    LOAD    RD, KS_NCLUS    ; the bitmap: (NCLUS + 2) / 8 + 1 bytes, 0
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        INC     RC
        INC     RC
        GHI     RC
        SHR
        PHI     RC
        GLO     RC
        SHRC
        PLO     RC
        GHI     RC
        SHR
        PHI     RC
        GLO     RC
        SHRC
        PLO     RC
        GHI     RC
        SHR
        PHI     RC
        GLO     RC
        SHRC
        PLO     RC
        INC     RC
        LOAD    RD, BM
ST4:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST4
        GHI     RC
        LBNZ    ST4
        SEP     R4
        DW      K_PIN
        DB      'Checking the card ...',0
        SEP     R4
        DW      NEWLN
        LOAD    RD, KS_WDIR     ; from the root
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, PATH
        LDI     '/'
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RD, PLENG
        LDI     1
        STR     RD
        LOAD    RD, SIDX        ; SIDX, EIDX, DEPTH: 0 (left from a run before, else)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, DEPTH
        LDI     0
        STR     RD
; ---- 1: every entry of every folder (DIRBUF: sector SIDX of WDIR; EIDX: the entry in it)
FR:     LOAD    RD, SIDX
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRRD
        LBDF    FEND            ; past the folder's end
FE:     LOAD    RD, EIDX
        LDN     RD
        XRI     16
        LBNZ    FE1
        STR     RD              ; the next sector
        LOAD    RD, SIDX+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     FR
FE1:    LDN     RD              ; RF -> entry EIDX (DIRBUF + 32 x EIDX); EIDX + 1
        PLO     RF
        ADI     1
        STR     RD
        LDI     0
        PHI     RF
        LDI     5
        PLO     RB
FE2:    GLO     RF
        SHL
        PLO     RF
        GHI     RF
        SHLC
        PHI     RF
        DEC     RB
        GLO     RB
        LBNZ    FE2
        GLO     RF
        ADI     LOW(KS_DIRBUF)
        PLO     RF
        GHI     RF
        ADCI    HIGH(KS_DIRBUF)
        PHI     RF
        LDN     RF              ; 0: the folder's end; E5: deleted
        LBZ     FEND
        XRI     0E5H
        LBZ     FE
        GLO     RF              ; its attribute: a long-name piece or the volume label - not a file
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        XRI     0FH
        LBZ     FE
        LDN     RD
        ANI     08H
        LBNZ    FE
        LDN     RD              ; RA.0 = the attribute
        PLO     RA
        LDN     RF              ; "." and ".."
        XRI     '.'
        LBNZ    FE3
        INC     RF
        LDN     RF
        DEC     RF
        XRI     ' '
        LBZ     FE
        XRI     ' ' XOR '.'
        LBNZ    FE3
        INC     RF
        INC     RF
        LDN     RF
        DEC     RF
        DEC     RF
        XRI     ' '
        LBZ     FE
FE3:    GLO     RA              ; EATTR, ENAME, ECL, ESIZE (big-endian)
        PLO     RB
        GLO     RF
        PLO     RA
        GHI     RF
        PHI     RA
        LOAD    RD, EATTR
        GLO     RB
        STR     RD
        LOAD    RD, ENAME
        LDI     11
        PLO     RB
FE4:    LDA     RA
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    FE4
        GLO     RF              ; +26: the cluster (little-endian), +28: the size
        ADI     26
        PLO     RA
        GHI     RF
        ADCI    0
        PHI     RA
        LOAD    RD, ECL+1
        LDA     RA
        STR     RD
        DEC     RD
        LDA     RA
        STR     RD
        LOAD    RD, ESIZE+3
        LDA     RA
        STR     RD
        DEC     RD
        LDA     RA
        STR     RD
        DEC     RD
        LDA     RA
        STR     RD
        DEC     RD
        LDN     RA
        STR     RD
        LOAD    RD, EATTR       ; a folder or a file: counted
        LDN     RD
        ANI     10H
        LBZ     FE5
        LOAD    RD, NDIR
        LBR     FE6
FE5:    LOAD    RD, NFIL
FE6:    SEP     R4
        DW      INC16
        SEP     R4              ; a dot every 8 entries
        DW      TICK
        SEP     R4              ; its chain (DF = 1: not sound)
        DW      CHAIN
        LBDF    FE
        LOAD    RD, EATTR       ; a sound folder: in (not too deep, the path has room)
        LDN     RD
        ANI     10H
        LBZ     FE
        LOAD    RD, DEPTH
        LDN     RD
        XRI     WMAX
        LBZ     FE
        LOAD    RD, PLENG
        LDN     RD
        SMI     PMAXL
        LBDF    FE
; ---- in: FSTK[DEPTH] = WDIR (2), SIDX (2), EIDX, PLENG; PATH + its name + /; WDIR = it
        LOAD    RD, DEPTH
        SEP     R4
        DW      STKPTR          ; RF -> FSTK + 6 x DEPTH
        LOAD    RD, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LOAD    RD, SIDX
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LOAD    RD, EIDX
        LDN     RD
        STR     RF
        INC     RF
        LOAD    RD, PLENG
        LDN     RD
        STR     RF
        LOAD    RD, DEPTH
        LDN     RD
        ADI     1
        STR     RD
        LOAD    RD, PLENG       ; the name onto PATH, and a /
        LDN     RD
        ADI     LOW(PATH)
        PLO     RF
        LDI     HIGH(PATH)
        ADCI    0
        PHI     RF
        LOAD    RC, ENAME
        SEP     R4
        DW      NM2TX
        LDI     '/'
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        LOAD    RD, PLENG
        GLO     RF
        SMI     LOW(PATH)
        STR     RD
        LOAD    RD, ECL         ; WDIR = it; SIDX, EIDX = 0
        LOAD    RF, KS_WDIR
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        LOAD    RD, SIDX
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LBR     FR
; ---- a folder's end: back to its parent's next entry
FEND:   LOAD    RD, DEPTH
        LDN     RD
        LBZ     P2
        SMI     1
        STR     RD
        SEP     R4
        DW      STKPTR
        LOAD    RD, KS_WDIR
        LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        LOAD    RD, SIDX
        LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        INC     RD              ; (EIDX follows SIDX)
        LDA     RF
        STR     RD
        LOAD    RD, PLENG
        LDN     RF
        STR     RD
        ADI     LOW(PATH)
        PLO     RF
        LDI     HIGH(PATH)
        ADCI    0
        PHI     RF
        LDI     0
        STR     RF
        LBR     FR
; ---- 2: lost clusters (in use in the FAT, in no chain) - counted
P2:     LOAD    RD, PASS
        LDI     0
        STR     RD
        SEP     R4
        DW      LOST
; ---- 3: the FAT's copies, sector by sector
        LOAD    RD, KS_NFATS
        LDN     RD
        SMI     2
        LBNF    P4
        LOAD    RD, FS          ; FS = 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
P3:     LOAD    RD, FS          ; FS < FATSZ?
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, KS_FATSZ+1
        GLO     RC
        SEX     RD
        SM
        DEC     RD
        GHI     RC
        SMB
        SEX     R2
        LBDF    P4
        LOAD    RD, KS_FATLBA   ; FAT 1's sector FS -> BUFA
        SEP     R4
        DW      KS_LD32
        SEP     R4
        DW      KS_ADD16
        LOAD    RF, BUFA
        SEP     R4
        DW      KS_IDERD
        LBDF    P3N
        LOAD    RD, KS_FATLBA   ; FAT 2's -> BUFB: FATLBA + FS + FATSZ
        SEP     R4
        DW      KS_LD32
        LOAD    RD, FS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_ADD16
        LOAD    RD, KS_FATSZ
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_ADD16
        LOAD    RF, BUFB
        SEP     R4
        DW      KS_IDERD
        LBDF    P3N
        LOAD    RA, BUFA
        LOAD    RB, BUFB
        LOAD    RC, 512
P3C:    LDA     RB
        STR     R2
        LDA     RA
        XOR
        LBNZ    P3D
        DEC     RC
        GLO     RC
        LBNZ    P3C
        GHI     RC
        LBNZ    P3C
        LBR     P3N
P3D:    LOAD    RD, NDIFF
        SEP     R4
        DW      INC16
P3N:    LOAD    RD, FS+1        ; a dot every 8 FAT sectors
        LDN     RD
        ANI     7
        LBNZ    P3M
        SEP     R4
        DW      DOT
P3M:    LOAD    RD, FS
        SEP     R4
        DW      INC16
        LBR     P3
; ---- 4: what was found
P4:     SEP     R4
        DW      DOTEND
        SEP     R4
        DW      K_PIN
        DB      'Checked: ',0
        LOAD    RD, NFIL
        SEP     R4
        DW      PNUM
        SEP     R4
        DW      K_PIN
        DB      ' files, ',0
        LOAD    RD, NDIR
        SEP     R4
        DW      PNUM
        SEP     R4
        DW      K_PIN
        DB      ' folders.',0
        SEP     R4
        DW      NEWLN
        LOAD    RD, NLOST
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     P41
        LOAD    RD, NLOST
        SEP     R4
        DW      PNUM
        SEP     R4
        DW      K_PIN
        DB      ' lost clusters (in use, but in no file)',0
        LOAD    RD, FFIX
        LDN     RD
        LBNZ    P40
        SEP     R4
        DW      K_PIN
        DB      ' - FSCK -F frees them',0
P40:    SEP     R4
        DW      NEWLN
P41:    LOAD    RD, NDIFF
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     P42
        SEP     R4
        DW      K_PIN
        DB      'The FAT',27H,'s two copies differ in ',0
        LOAD    RD, NDIFF
        SEP     R4
        DW      PNUM
        SEP     R4
        DW      K_PIN
        DB      ' sectors.',0
        SEP     R4
        DW      NEWLN
P42:    LOAD    RD, NPROB       ; nothing wrong?
        LDA     RD
        STR     R2
        LDN     RD
        OR
        STR     R2
        LOAD    RD, NLOST
        LDA     RD
        OR
        STR     R2
        LDN     RD
        OR
        STR     R2
        LOAD    RD, NDIFF
        LDA     RD
        OR
        STR     R2
        LDN     RD
        OR
        LBNZ    P43
        SEP     R4
        DW      K_PIN
        DB      'No problems found.',0
        SEP     R4
        DW      NEWLN
        SEP     R5
P43:    LOAD    RD, FFIX        ; -F, and lost clusters: free them?
        LDN     RD
        LBZ     P49
        LOAD    RD, NLOST
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     P49
        SEP     R4              ; (the question on the screen, even with the output in a file)
        DW      K_TTYON
        SEP     R4
        DW      K_PIN
        DB      'Free the lost clusters? (Y/N) ',0
        SEP     R4
        DW      K_YESNO
        LBNF    P49
        LOAD    RD, PASS
        LDI     1
        STR     RD
        SEP     R4
        DW      LOST
        SEP     R4
        DW      KS_FATFLUSH
        LBDF    P48
        SEP     R4
        DW      K_PIN
        DB      'Freed.',0DH,0AH,0
        SEP     R5
P48:    SEP     R4
        DW      K_PIN
        DB      'The card did not take the change.',0DH,0AH,0
P49:    SEP     R5

; LOST: every cluster 2 .. NCLUS + 1 in use in the FAT and not in the bitmap: PASS 0 counts them (NLOST),
;       PASS 1 frees them (FATPUT 0; the caller FATFLUSHes)
LOST:   LOAD    RD, LC
        LDI     0
        STR     RD
        INC     RD
        LDI     2
        STR     RD
LS1:    LOAD    RD, LC          ; RC = LC; past NCLUS + 1: done
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_CLVALID
        LBNF    LS9
        SEP     R4
        DW      BMADDR
        LDN     RD
        STR     R2
        GHI     R9
        AND
        LBNZ    LSN             ; in a chain
        LOAD    RD, LC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_FATNEXT      ; RC = its FAT entry
        GHI     RC
        LBNZ    LS2
        GLO     RC
        LBZ     LSN             ; free
LS2:    LOAD    RD, PASS
        LDN     RD
        LBNZ    LS3
        LOAD    RD, NLOST
        SEP     R4
        DW      INC16
        LBR     LSN
LS3:    LOAD    RD, LC          ; free it
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDI     0
        PHI     R9
        PLO     R9
        SEP     R4
        DW      KS_FATPUT
LSN:    LOAD    RD, LC+1        ; a dot every 256 clusters
        LDN     RD
        LBNZ    LSN1
        SEP     R4
        DW      DOT
LSN1:   LOAD    RD, LC
        SEP     R4
        DW      INC16
        LBR     LS1
LS9:    SEP     R5

; CHAIN: the chain from ECL - each cluster valid, in no chain before (the bitmap), then marked; a file's length
;        against its size. DF = 1 if it is not sound (and said so).
CHAIN:  LOAD    RD, CNT
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, ECL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    CH1
        GLO     RC
        LBZ     CH8             ; no clusters at all
CH1:    SEP     R4
        DW      KS_CLVALID
        LBNF    CHBAD
        SEP     R4
        DW      BMADDR          ; RD -> its byte, R9.1 = its bit
        LDN     RD
        STR     R2
        GHI     R9
        AND
        LBNZ    CHX             ; in another chain already
        GHI     R9
        STR     R2
        LDN     RD
        OR
        STR     RD
        GHI     RC
        STXD
        GLO     RC
        STXD
        LOAD    RD, CNT
        SEP     R4
        DW      INC16
        IRX
        LDXA
        PLO     RC
        LDX
        PHI     RC
        SEP     R4
        DW      KS_FATNEXT      ; RC = the next (FFF7 if the FAT could not be read)
        GHI     RC              ; FFF8-FFFF: the end
        XRI     0FFH
        LBNZ    CH1
        GLO     RC
        SMI     0F8H
        LBNF    CH1
CH8:    LOAD    RD, EATTR       ; a folder: no size to match
        LDN     RD
        ANI     10H
        LBZ     CH9
        LOAD    RD, ECL         ; (a folder with no clusters at all: broken)
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     CHBAD
        LDI     0
        SHR
        SEP     R5
CH9:    LOAD    RD, ESIZE       ; clusters it needs: (size + bytes a cluster - 1) >> (9 + SHIFT)
        SEP     R4
        DW      KS_LD32
        LOAD    RC, 01FFH
        LOAD    RD, KS_SHIFT
        LDN     RD
        PLO     RB
CH9A:   GLO     RB
        LBZ     CH9B
        GLO     RC
        SHL
        ORI     1
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        DEC     RB
        LBR     CH9A
CH9B:   SEP     R4
        DW      KS_ADD16
        LOAD    RD, KS_SHIFT
        LDN     RD
        ADI     9
        PLO     RB
CH9C:   SEP     R4
        DW      KS_SHR32
        DEC     RB
        GLO     RB
        LBNZ    CH9C
        GHI     R8              ; = CNT?
        LBNZ    CHM
        GLO     R8
        LBNZ    CHM
        LOAD    RD, CNT
        LDA     RD
        STR     R2
        GHI     R7
        XOR
        LBNZ    CHM
        LDN     RD
        STR     R2
        GLO     R7
        XOR
        LBNZ    CHM
        LDI     0
        SHR
        SEP     R5
CHM:    SEP     R4
        DW      PROB
        SEP     R4
        DW      K_PIN
        DB      'its size does not match its clusters',0
        LBR     CHE
CHBAD:  SEP     R4
        DW      PROB
        SEP     R4
        DW      K_PIN
        DB      'a broken chain of clusters',0
        LBR     CHE
CHX:    SEP     R4
        DW      PROB
        SEP     R4
        DW      K_PIN
        DB      'cross-linked (a cluster another file has too)',0
CHE:    SEP     R4
        DW      NEWLN
        LDI     1
        SHR
        SEP     R5
; PROB: one more problem (NPROB); PATH, the entry's name, ": "
PROB:   SEP     R4              ; (off the line of dots)
        DW      DOTEND
        LOAD    RD, NPROB
        SEP     R4
        DW      INC16
        LOAD    RA, PATH
        SEP     R4
        DW      PRSTR
        LOAD    RC, ENAME
        LOAD    RF, NBUF
        SEP     R4
        DW      NM2TX
        LOAD    RA, NBUF
        SEP     R4
        DW      PRSTR
        SEP     R4
        DW      K_PIN
        DB      ': ',0
        SEP     R5
; BMADDR: RC = a cluster -> RD -> its byte in the bitmap, R9.1 = its bit. Keeps RC.
BMADDR: GHI     RC              ; RD = RC >> 3
        SHR
        PHI     RD
        GLO     RC
        SHRC
        PLO     RD
        GHI     RD
        SHR
        PHI     RD
        GLO     RD
        SHRC
        PLO     RD
        GHI     RD
        SHR
        PHI     RD
        GLO     RD
        SHRC
        ADI     LOW(BM)
        PLO     RD
        GHI     RD
        ADCI    HIGH(BM)
        PHI     RD
        GLO     RC              ; the bit: 1 << (RC & 7)
        ANI     07H
        PLO     R9
        LDI     1
        PHI     R9
BA1:    GLO     R9
        LBZ     BA2
        GHI     R9
        SHL
        PHI     R9
        DEC     R9
        LBR     BA1
BA2:    SEP     R5
; STKPTR: RF -> FSTK + 6 x the byte at RD
STKPTR: LDN     RD
        PLO     RB
        LOAD    RF, FSTK
SP1:    GLO     RB
        LBZ     SP2
        GLO     RF
        ADI     6
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        DEC     RB
        LBR     SP1
SP2:    SEP     R5
; INC16: the 2 bytes at RD (big-endian) + 1.  PNUM: the 2 bytes at RD in decimal.
INC16:  INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5
PNUM:   LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        LBR     K_PDEC

; TICK: a dot every 8th time. Changes RD.
TICK:   LOAD    RD, DCNT
        LDN     RD
        ADI     1
        STR     RD
        ANI     7
        LBZ     DOT
        SEP     R5
DCNT:   DB      0
        INCL    "dots.inc"
USE:    SEP     R4
        DW      K_PIN
        DB      'FSCK [-F] - check the card (-F: free lost clusters)',0DH,0AH,0
        SEP     R5
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
        INCL    "tools.inc"
PEND:
LINES:  DS      1               ; LINES ... NDIFF: zeroed at the start (NVARS bytes)
FFIX:   DS      1
NFIL:   DS      2
NDIR:   DS      2
NPROB:  DS      2
NLOST:  DS      2
NDIFF:  DS      2
NVARS   EQU     $ - LINES
PASS:   DS      1
LC:     DS      2
FS:     DS      2
CNT:    DS      2
DEPTH:  DS      1
SIDX:   DS      2               ; SIDX, EIDX: in this order
EIDX:   DS      1
EATTR:  DS      1
ENAME:  DS      11
ECL:    DS      2
ESIZE:  DS      4
NBUF:   DS      14
PLENG:  DS      1
PATH:   DS      PMAXL + 14
FSTK:   DS      WMAX * 6
BUFA:   DS      512
BUFB:   DS      512
BM:                             ; the bitmap: a bit a cluster (up to 8 KB)
        END
