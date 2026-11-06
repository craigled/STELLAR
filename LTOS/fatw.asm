; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; fatw.asm - LTOS's FAT16 layer, write side (phase 3), INCL'd by the kernel after fat.asm.
;
; Every change keeps all the FATs in step (NFATS copies, FATSZ sectors apart). The order of writes is chosen
; so a power cut can lose only the file being written or deleted - never another file:
;   a new file:   its data, then the FAT (both copies), then its directory entry last;
;   deleting:     its directory entry first (the file is gone), then its clusters are freed.
; A cut in between leaves "lost clusters" (in use in the FAT, owned by no entry) - space, not damage.
; Long names (the Mac's): deleting or renaming a file marks its long-name pieces deleted too, so the Mac and
; fsck never see orphans.
;
;   FATSEC   FATBUF = FAT sector RC.1, writing back a changed one first (keeps RC). DF = 1: the card failed
;   FATPUT   FAT entry RC = R9 (in FATBUF; written by FATFLUSH, or when another FAT sector is needed)
;   FATFLUSH a changed FATBUF to every FAT. DF = 1: the card failed
;   CLVALID  DF = 1 if RC is a cluster of this card (2 .. NCLUS + 1)
;   FREECL   RC = a free cluster (from FHINT on, round once). DF = 1: none (or the card failed)
;   FREECH   free the chain starting at cluster RC (to the end, or a bad link), then FATFLUSH
;   DSLOT    a free root entry: WDSEC, WDPTR (and DIRBUF = its sector). DF = 1: the directory is full
;   DIRRD / DIRWR   root directory sector RC <-> DIRBUF
;   FINDN    RD -> an 11-byte name: is it on the card? DF = 0: yes (DNEXT's fields, RF -> it in DIRBUF).
;            Hidden and system files count here (a new file must not take their name).
;   KILLLFN  the long-name pieces of the entry DNEXT just gave (ENTP) marked deleted - the earlier sectors
;            written, DSEC's left in DIRBUF for the caller to write
;   DELENT   delete the entry DNEXT just gave (RF -> it): long name, entry, clusters
;   WFILE    a new file FNAME: PFXN bytes at PFXB (a program's header), then WLEN bytes from WSRC.
;            DF = 1 + D: 1 the directory is full, 2 the card is full, 3 the card failed
;   STAMP    STT / STD = now, in FAT's form: from the DS12887, or DATEV (when LTOS was built) with no clock

; ---- FATSEC / FATPUT / FATFLUSH
FATSEC: LOAD    RD, FATCUR
        LDA     RD
        STR     R2
        GHI     RC
        XOR
        LBNZ    FS1
        LDN     RD
        LBNZ    FS1
        LDI     0               ; already there
        SHR
        SEP     R5
FS1:    SEP     R4              ; another sector: the changed one out first
        DW      FATFLUSH
        LBDF    FS9
        GLO     RC
        STXD
        GHI     RC
        STXD
        PLO     RC              ; RC = the sector's number in the FAT
        LDI     0
        PHI     RC
        LOAD    RD, FATLBA
        SEP     R4
        DW      LD32
        SEP     R4
        DW      ADD16
        LOAD    RF, FATBUF
        SEP     R4
        DW      IDERD
        IRX
        LDXA
        PHI     RC
        LDX
        PLO     RC
        LBDF    FS8
        LOAD    RD, FATCUR
        GHI     RC
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        SHR                     ; DF = 0
        SEP     R5
FS8:    LOAD    RD, FATCUR      ; nothing cached now
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        LDI     1
        SHR
FS9:    SEP     R5

; FATPTR: RF = FATBUF + 2 x RC.0 (FATBUF is page-aligned)
FATPTR: GLO     RC
        SHL
        PLO     RF
        LDI     HIGH(FATBUF)
        ADCI    0
        PHI     RF
        SEP     R5

FATPUT: SEP     R4
        DW      FATSEC
        LBDF    FP9
        SEP     R4
        DW      FATPTR
        GLO     R9              ; little-endian
        STR     RF
        INC     RF
        GHI     R9
        STR     RF
        LOAD    RD, FATDIRTY
        LDI     1
        STR     RD
        LDI     0
        SHR
FP9:    SEP     R5

FATFLUSH: LOAD  RD, FATDIRTY
        LDN     RD
        LBZ     FF8
        GLO     RC
        STXD
        GHI     RC
        STXD
        LOAD    RD, FATCUR      ; R8:R7 = FAT 1's copy of the sector
        LDN     RD
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    RD, FATLBA
        SEP     R4
        DW      LD32
        SEP     R4
        DW      ADD16
        LOAD    RD, NFATS
        LDN     RD
        PLO     RB              ; RB.0 = copies left (the driver keeps RB)
FF1:    LOAD    RF, FATBUF
        SEP     R4
        DW      IDEWR
        LBDF    FF7
        LOAD    RD, FATSZ       ; the next FAT's copy: FATSZ sectors on
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      ADD16
        DEC     RB
        GLO     RB
        LBNZ    FF1
        LOAD    RD, FATDIRTY
        LDI     0
        STR     RD
        IRX
        LDXA
        PHI     RC
        LDX
        PLO     RC
FF8:    LDI     0
        SHR
        SEP     R5
FF7:    IRX
        LDXA
        PHI     RC
        LDX
        PLO     RC
        LDI     1
        SHR
        SEP     R5

; ---- CLVALID: DF = 1 if 2 <= RC <= NCLUS + 1.  Uses RF, RD.
CLVALID: GLO    RC              ; RF = RC - 2 (a borrow: under 2)
        SMI     2
        PLO     RF
        GHI     RC
        SMBI    0
        PHI     RF
        LBNF    CV9
        LOAD    RD, NCLUS+1     ; RF < NCLUS?
        SEX     RD
        GLO     RF
        SM
        DEC     RD
        GHI     RF
        SMB
        SEX     R2
        LBDF    CV9
        LDI     1
        SHR
        SEP     R5
CV9:    LDI     0
        SHR
        SEP     R5

; ---- FREECL: RA = the cluster tried, R9 = tries left (NCLUS)
FREECL: LOAD    RD, FHINT
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LOAD    RD, NCLUS
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
FK1:    GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        SEP     R4
        DW      CLVALID
        LBDF    FK2
        LOAD    RA, 2           ; past the end: round to the first
        LOAD    RC, 2
FK2:    SEP     R4
        DW      FATNEXT         ; RC = its entry
        LBDF    FKX
        GHI     RC
        LBNZ    FK3
        GLO     RC
        LBZ     FK5             ; 0: free
FK3:    INC     RA
        DEC     R9
        GLO     R9
        LBNZ    FK1
        GHI     R9
        LBNZ    FK1
FKX:    LDI     1
        SHR
        SEP     R5
FK5:    GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        INC     RA              ; the next search starts after it
        LOAD    RD, FHINT
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        LDI     0
        SHR
        SEP     R5

; ---- FREECH: free the chain from RC
FREECH: SEP     R4
        DW      CLVALID
        LBNF    FH8             ; the end (or a link that is not a cluster)
        GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA              ; RA = this one
        SEP     R4
        DW      FATNEXT         ; RC = the next
        LBDF    FHX
        LOAD    RD, FNXT
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        LOAD    R9, 0
        SEP     R4
        DW      FATPUT
        LBDF    FHX
        LOAD    RD, FNXT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LBR     FREECH
FH8:    LBR     FATFLUSH
FHX:    LDI     1
        SHR
        SEP     R5

; ---- DIRRD / DIRWR: root directory sector RC <-> DIRBUF
DIRRD:  SEP     R4              ; (DF = 1: past the directory's end)
        DW      DIRLBA
        LBDF    DR9
        LOAD    RF, DIRBUF
        LBR     IDERD
DIRWR:  SEP     R4
        DW      DIRLBA
        LBDF    DR9
        LOAD    RF, DIRBUF
        LBR     IDEWR
DR9:    SEP     R5
; DIRLBA: R8:R7 = sector RC of the directory WDIR (0: the root - ROOTSECS of them at ROOTLBA; else a folder:
;         its cluster chain). DF = 1: there is no such sector. RC kept.
DIRLBA: GLO     RC              ; (RC, RA, RB, R9 kept: KILLLFN and DSLOT count on them)
        STXD
        GHI     RC
        STXD
        GLO     RA
        STXD
        GHI     RA
        STXD
        GLO     RB
        STXD
        GHI     RB
        STXD
        GLO     R9
        STXD
        GHI     R9
        STXD
        LOAD    RD, WDIR
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    DL5
        LOAD    RD, ROOTSECS+1  ; the root: RC < ROOTSECS?
        SEX     RD
        GLO     RC
        SM
        DEC     RD
        GHI     RC
        SMB
        SEX     R2
        LBDF    DLNO
        LOAD    RD, ROOTLBA
        SEP     R4
        DW      LD32
        SEP     R4
        DW      ADD16
        LBR     DLOK
DL5:    GLO     RC              ; a folder: RA = the sector, RC = the cluster
        PLO     RA
        GHI     RC
        PHI     RA
        LOAD    RD, WDIR
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
DL6:    LOAD    RD, SPC         ; in this cluster? (RA < SPC)
        LDN     RD
        STR     R2
        GHI     RA
        LBNZ    DL7
        GLO     RA
        SM
        LBNF    DL8
DL7:    GLO     RA              ; no: SPC on, in the next cluster
        SM
        PLO     RA
        GHI     RA
        SMBI    0
        PHI     RA
        SEP     R4
        DW      FATNEXT
        LBDF    DLNO
        SEP     R4
        DW      CLVALID
        LBNF    DLNO            ; (the chain's end)
        LBR     DL6
DL8:    SEP     R4
        DW      CL2LBA
        GLO     RA
        PLO     RC
        LDI     0
        PHI     RC
        SEP     R4
        DW      ADD16
DLOK:  IRX
        LDXA
        PHI     R9
        LDXA
        PLO     R9
        LDXA
        PHI     RB
        LDXA
        PLO     RB
        LDXA
        PHI     RA
        LDXA
        PLO     RA
        LDXA
        PHI     RC
        LDX
        PLO     RC
        LDI     0
        SHR
        SEP     R5
DLNO:  IRX
        LDXA
        PHI     R9
        LDXA
        PLO     R9
        LDXA
        PHI     RB
        LDXA
        PLO     RB
        LDXA
        PHI     RA
        LDXA
        PLO     RA
        LDXA
        PHI     RC
        LDX
        PLO     RC
        LDI     1
        SHR
        SEP     R5

; ---- DSLOT: RC = the sector, RF the entry, RB.0 entries left in the sector
DSLOT:  LOAD    RC, 0
SL1:    SEP     R4
        DW      DIRRD
        LBDF    SLX             ; its end: the root is full; a folder grows
        LOAD    RF, DIRBUF
        LDI     16
        PLO     RB
SL3:    LDN     RF
        LBZ     SL5             ; never used
        XRI     0E5H
        LBZ     SL5             ; deleted
        GLO     RF
        ADI     32
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        DEC     RB
        GLO     RB
        LBNZ    SL3
        INC     RC
        LBR     SL1
SL5:    LOAD    RD, WDSEC       ; WDSEC, WDPTR: in this order
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDI     0
        SHR
        SEP     R5
SLF:    LDI     1
        SHR
        SEP     R5
; SLX: sector RC is past the folder's end: a new cluster for it - zeroed, then chained on - and its first entry
SLX:    LOAD    RD, WDIR
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     SLF             ; the root does not grow
        GLO     RC
        STXD
        GHI     RC
        STXD
        SEP     R4
        DW      FREECL          ; RC = the new cluster
        LBDF    SLFP
        LOAD    RD, DSXC
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      ZDIR            ; its sectors: zeros (DIRBUF too)
        LBDF    SLFP
        LOAD    R9, 0FFFFH      ; it ends the chain ...
        SEP     R4
        DW      FATPUT
        LBDF    SLFP
        LOAD    RD, WDIR        ; ... and the folder's last cluster points at it
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
SX1:    GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA
        SEP     R4
        DW      FATNEXT
        LBDF    SLFP
        SEP     R4
        DW      CLVALID
        LBDF    SX1
        GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
        LOAD    RD, DSXC
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        SEP     R4
        DW      FATPUT
        LBDF    SLFP
        SEP     R4
        DW      FATFLUSH
        LBDF    SLFP
        IRX                     ; the slot: sector RC's first entry (DIRBUF is that zeroed sector)
        LDXA
        PHI     RC
        LDX
        PLO     RC
        LOAD    RF, DIRBUF
        LBR     SL5
SLFP:   IRX
        IRX
        LBR     SLF
; ZDIR: DIRBUF = zeros, written to every sector of cluster RC (RC kept). DF = 1: the card failed.
ZDIR:   LOAD    RF, DIRBUF
        LDI     0
        PLO     RB
ZD1:    LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    ZD1
        SEP     R4
        DW      CL2LBA
        LOAD    RD, SPC
        LDN     RD
        PLO     RB
ZD2:    LOAD    RF, DIRBUF
        SEP     R4
        DW      IDEWR
        LBDF    ZD9
        GLO     RC
        STXD
        GHI     RC
        STXD
        LOAD    RC, 1
        SEP     R4
        DW      ADD16
        IRX
        LDXA
        PHI     RC
        LDX
        PLO     RC
        DEC     RB
        GLO     RB
        LBNZ    ZD2
        LDI     0
        SHR
ZD9:    SEP     R5

; ---- FINDN: RD -> the name. (DOPEN clears DNALL; it is set after.)
FINDN:  LOAD    RF, PAT
        LDI     11
        PLO     RB
FI1:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    FI1
        SEP     R4
        DW      DOPEN
        LOAD    RD, DNALL
        LDI     1
        STR     RD
        SEP     R4
        DW      DNEXT
        LOAD    RD, DNALL       ; (LOAD keeps DF)
        LDI     0
        STR     RD
        SEP     R5

; ---- KILLLFN: R9 = the sector being marked, RA = the entry being marked
KILLLFN: LOAD   RD, RLFN
        LDN     RD
        LBZ     KL9             ; no long name
        LOAD    RD, LFNSEC
        LDA     RD
        PHI     R9
        LDA     RD
        PLO     R9
        LDA     RD              ; LFNPTR follows LFNSEC
        PHI     RA
        LDN     RD
        PLO     RA
        LDI     0
        PLO     RB              ; RB.0 = 1: DIRBUF was read over, DSEC's must be read back
KL1:    LOAD    RD, DSEC        ; the long name started in an earlier sector?
        LDA     RD
        STR     R2
        GHI     R9
        XOR
        LBNZ    KL2
        LDN     RD
        STR     R2
        GLO     R9
        XOR
        LBZ     KL5
KL2:    GHI     R9              ; that sector: read it, mark to its end, write it
        PHI     RC
        GLO     R9
        PLO     RC
        SEP     R4
        DW      DIRRD
        LBDF    KLX
        LDI     1
        PLO     RB
        LOAD    RF, DIRBUF+512
        SEP     R4
        DW      MARKE5
        GHI     R9
        PHI     RC
        GLO     R9
        PLO     RC
        SEP     R4
        DW      DIRWR
        LBDF    KLX
        INC     R9
        LOAD    RA, DIRBUF
        LBR     KL1
KL5:    GLO     RB              ; DSEC's sector back in DIRBUF, if it was read over
        LBZ     KL6
        LOAD    RD, DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      DIRRD
        LBDF    KLX
KL6:    LOAD    RD, ENTP        ; mark from RA up to the entry itself
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R4
        DW      MARKE5
KL9:    LDI     0
        SHR
        SEP     R5
KLX:    LDI     1
        SHR
        SEP     R5
; MARKE5: $E5 into the first byte of each entry from RA up to (not including) RF; RA ends at RF
MARKE5: GLO     RA
        STR     R2
        GLO     RF
        XOR
        LBNZ    ME1
        GHI     RA
        STR     R2
        GHI     RF
        XOR
        LBZ     ME9
ME1:    LDI     0E5H
        STR     RA
        GLO     RA
        ADI     32
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     MARKE5
ME9:    SEP     R5

; ---- DELENT
DELENT: LOAD    RD, ENTP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R4
        DW      KILLLFN
        LBDF    DE9
        LOAD    RD, ENTP        ; the entry itself
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LDI     0E5H
        STR     RF
        LOAD    RD, DSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      DIRWR
        LBDF    DE9
        LOAD    RD, DCLUS       ; then its clusters
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LBR     FREECH
DE9:    SEP     R5

; ---- WFILE
WFILE:  LOAD    RD, WATTR       ; a file
        LDI     20H
        STR     RD
WFILE1: SEP     R4              ; (MKDIR comes in here with WATTR = $10)
        DW      DSLOT
        LDI     1
        LBDF    WFX             ; the directory is full
WFILE2:                         ; (ATTACH.PRG comes in here: WDSEC / WDPTR chosen already)
        LOAD    RD, PFXN        ; WTOT = WREM = PFXN + WLEN; WFIRST = WPREV = 0; PFXP = PFXB
        LDN     RD
        STR     R2
        LOAD    RD, WLEN+1
        LDN     RD
        ADD
        PLO     RC
        DEC     RD
        LDN     RD
        ADCI    0
        PHI     RC
        LOAD    RD, WTOT        ; WTOT, WREM, WFIRST, WPREV: in this order
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, PFXP
        LDI     HIGH(PFXB)
        STR     RD
        INC     RD
        LDI     LOW(PFXB)
        STR     RD
        LOAD    RD, WATTR       ; a folder (MKDIR): its cluster, made already, is the first
        LDN     RD
        XRI     10H
        LBNZ    WF1
        LOAD    RD, MKCL
        LOAD    RC, WFIRST
        LDA     RD
        STR     RC
        INC     RC
        LDN     RD
        STR     RC
WF1:    LOAD    RD, WREM        ; all written?
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     WF6
        SEP     R4              ; a cluster for the next part
        DW      FREECL
        LBDF    WFFULL
        LOAD    RD, WCLUS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    R9, 0FFFFH      ; it ends the chain ...
        SEP     R4
        DW      FATPUT
        LBDF    WFERR
        LOAD    RD, WPREV       ; ... and the last one points at it (or it is the first)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, WCLUS
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        GHI     RC
        LBNZ    WF2
        GLO     RC
        LBNZ    WF2
        LOAD    RD, WFIRST
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LBR     WF3
WF2:    SEP     R4
        DW      FATPUT
        LBDF    WFERR
WF3:    LOAD    RD, WCLUS       ; WPREV = WCLUS; WLBA = its first sector
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
        DW      CL2LBA
        LOAD    RD, WLBA
        SEP     R4
        DW      ST32
        LOAD    RD, SPC         ; WSLEFT = its sectors
        LDN     RD
        PLO     RB
        LOAD    RD, WSLEFT
        GLO     RB
        STR     RD
WF4:    SEP     R4              ; a sector of the file
        DW      FILLSEC
        LOAD    RD, WLBA
        SEP     R4
        DW      LD32
        LOAD    RF, DATBUF
        SEP     R4
        DW      IDEWR
        LBDF    WFERR
        LOAD    RC, 1
        SEP     R4
        DW      ADD16
        LOAD    RD, WLBA
        SEP     R4
        DW      ST32
        LOAD    RD, WREM        ; done?
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     WF6
        LOAD    RD, WSLEFT      ; more sectors in this cluster?
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    WF4
        LBR     WF1
WF6:    SEP     R4              ; the FAT, then the entry
        DW      FATFLUSH
        LBDF    WFERR
        LOAD    RD, WDSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      DIRRD
        LBDF    WFERR
        SEP     R4
        DW      STAMP
        LOAD    RD, WDPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, FNAME       ; 0-10 the name
        LDI     11
        PLO     RB
WF7:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    WF7
        LOAD    RD, WATTR       ; 11 the attribute: archive (a file), or folder (MKDIR)
        LDN     RD
        STR     RF
        INC     RF
        LDI     0               ; 12, 13
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 14-17 created
        DW      PUTST
        LOAD    RD, STD         ; 18-19 used
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LDI     0               ; 20-21 (FAT32's high cluster)
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 22-25 written
        DW      PUTST
        LOAD    RD, WFIRST      ; 26-27 the first cluster, 28-31 the size (little-endian)
        LDA     RD
        PHI     RC
        LDN     RD
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        LOAD    RD, WTOT+1
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
        LOAD    RD, WDSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      DIRWR
        LBDF    WFERR
        LDI     0
        SHR
        SEP     R5
WFFULL: LOAD    RD, WFIRST      ; the card is full: give back what was taken
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      FREECH
        LDI     2
        LSKP
WFERR:  LDI     3
WFX:    SMI     0               ; DF = 1, D kept
        SEP     R5
; PUTST: STT then STD at RF (little-endian, as stored)
PUTST:  LOAD    RD, STT
        LDI     4
        PLO     RB
PS1:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    PS1
        SEP     R5
; FILLSEC: DATBUF = the next min(512, WREM) bytes - the header first, then memory - and 0s after them
FILLSEC: LOAD   RF, DATBUF
        LOAD    RC, 512
FL1:    LOAD    RD, WREM        ; nothing left: 0s
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     FL5
        LOAD    RD, PFXN        ; the header?
        LDN     RD
        LBZ     FL2
        SMI     1
        STR     RD
        LOAD    RD, PFXP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDA     RA
        STR     RF
        GLO     RA
        STR     RD
        DEC     RD
        GHI     RA
        STR     RD
        LBR     FL3
FL2:    LOAD    RD, WSRC        ; memory
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDA     RA
        STR     RF
        GLO     RA
        STR     RD
        DEC     RD
        GHI     RA
        STR     RD
FL3:    INC     RF
        LOAD    RD, WREM+1      ; one less to go
        LDN     RD
        SMI     1
        STR     RD
        DEC     RD
        LDN     RD
        SMBI    0
        STR     RD
        DEC     RC
        GLO     RC
        LBNZ    FL1
        GHI     RC
        LBNZ    FL1
        SEP     R5
FL5:    LDI     0               ; the rest of the sector
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    FL5
        GHI     RC
        LBNZ    FL5
        SEP     R5

; ---- STAMP: the DS12887 (registers: 0 seconds, 2 minutes, 4 hours, 7 day, 8 month, 9 year, A / B status)
STAMP:  LDI     8BH             ; register B: $FF = no clock
        SEP     R4
        DW      RTCRD
        PLO     RB              ; RB.0 = B: bit 2 binary, bit 1 24-hour
        XRI     0FFH
        LBNZ    SM1
        LOAD    RD, DATEV       ; no clock: when LTOS was built
        LOAD    RF, STT
        LDI     4
        PLO     RC
SM0:    LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    SM0
        SEP     R5
SM1:    LDI     0               ; register A: wait while it updates (at most ~2 ms)
        PLO     RC
SM2:    LDI     8AH
        SEP     R4
        DW      RTCRD
        ANI     80H
        LBZ     SM3
        DEC     RC
        GLO     RC
        LBNZ    SM2
SM3:    LDI     84H             ; the hour (12-hour: bit 7 = PM, 12 = 0)
        SEP     R4
        DW      RTCRD
        PLO     RA
        ANI     7FH
        SEP     R4
        DW      RTCBIN
        PHI     RA              ; RA.1 = the hour
        GLO     RB
        ANI     02H
        LBNZ    SM5             ; 24-hour
        GHI     RA
        XRI     12
        LBNZ    SM4
        PHI     RA
SM4:    GLO     RA
        ANI     80H
        LBZ     SM5
        GHI     RA
        ADI     12
        PHI     RA
SM5:    LDI     82H             ; the minutes
        SEP     R4
        DW      RTCBIN2
        PLO     R9              ; R9.0 = minutes
        LDI     80H             ; the seconds
        SEP     R4
        DW      RTCBIN2
        SHR                     ; / 2
        PHI     R9              ; R9.1 = seconds / 2
        LOAD    RD, STT         ; time = hour << 11 | minutes << 5 | seconds / 2 (stored little-endian)
        GLO     R9              ; low: (minutes & 7) << 5 | seconds / 2
        ANI     07H
        SHL
        SHL
        SHL
        SHL
        SHL
        STR     R2
        GHI     R9
        OR
        STR     RD
        INC     RD
        GHI     RA              ; high: hour << 3 | minutes >> 3
        SHL
        SHL
        SHL
        STR     R2
        GLO     R9
        SHR
        SHR
        SHR
        OR
        STR     RD
        INC     RD              ; STD follows STT
        LDI     89H             ; the year: binary (as the Elf2K BIOS keeps it) = 1972 + it; BCD = 2000 + it
        SEP     R4
        DW      RTCBIN2
        STR     R2
        GLO     RB
        ANI     04H
        LBZ     SY1
        LDN     R2              ; FAT counts from 1980
        SMI     8
        LBR     SY2
SY1:    LDN     R2
        ADI     20
SY2:    PHI     RA
        LDI     88H
        SEP     R4
        DW      RTCBIN2
        PLO     RA              ; RA.0 = the month
        LDI     87H
        SEP     R4
        DW      RTCBIN2
        PLO     R9              ; R9.0 = the day
        GLO     RA              ; low: (month & 7) << 5 | day
        ANI     07H
        SHL
        SHL
        SHL
        SHL
        SHL
        STR     R2
        GLO     R9
        OR
        STR     RD
        INC     RD
        GHI     RA              ; high: year << 1 | month >> 3
        SHL
        STR     R2
        GLO     RA
        SHR
        SHR
        SHR
        OR
        STR     RD
        SEP     R5
; RTCRD: D = $80 + a register -> D = its value.  RTCBIN2: the same, then from BCD (unless B says binary).
RTCRD:  STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SEP     R5
RTCBIN2: SEP    R4
        DW      RTCRD
RTCBIN: PLO     RE              ; D -> binary, unless RB.0 (register B) bit 2 says it is already
        GLO     RB
        ANI     04H
        LBNZ    RB9
        GLO     RE
        SHR
        SHR
        SHR
        SHR
        STR     R2              ; tens
        SHL
        SHL
        ADD                     ; x 5
        SHL                     ; x 10
        STR     R2
        GLO     RE
        ANI     0FH
        ADD
        SEP     R5
RB9:    GLO     RE
        SEP     R5
