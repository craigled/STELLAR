; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; attach.asm - ATTACH.PRG: STELLAR.PRG's helper for STELLAR LW2 DOC.TXT (loaded at ATTORG, $4D00, and CALLed, RD -> the
; document's 11-byte name, WDIR = its folder; RC = ATTFND: STELLAR.PRG's FINDN of it just found it, so it is
; not searched for again). It makes the file one Lite-Writer 2 can rewrite on its own,
; with no FAT code and no buffer, then leaves Lite-Writer a note (NOTEB, copied to $7EA0 by MON's stub):
;   * its data starts at the first cluster of a FAT sector that is ALL free (so that FAT sector holds only
;     this file's chain), with room for ROOMS (128) sectors, 64 KB, from it;
;   * its directory entry is the first of a directory sector of its own (the free entries before it in
;     the folder are marked deleted, so the folder reads on to it; the rest of that sector is zero).
; Lite-Writer then writes those sectors WHOLE: the text, 0s; the chain, 0s; the entry, 0s.
; A file not laid out so is copied there a sector at a time (any size up to MAXF; 2026-10-30 - it used to be
; read whole into memory, 4 KB at most), then its old clusters freed and its entry moved to T.
; The note (big-endian but the entry): +0 'LW' +2 0 +3 L (2) +5 D0 (2) the first data sector +7 NSECT
; +8 SPC +9 C1 (2) the first cluster +11 FL1 (2) +13 FL2 (2) the FAT sector in each copy (0: one copy)
; +15 DLBA (2) the directory sector +17 the 32-byte entry +49 the name: NAME.EXT and a 0.
; An old file's entry on the card keeps its dates (opening it and leaving is no change); the note's copy is
; stamped now, so a ^W save carries the time it was opened.
; A file laid out so already (the last open did it, and ^W keeps it so) is not rewritten: nothing on the card is
; written, only the note is made (LAID) - on Craig's 8 MB card the writes were most of an open's 8 s.
; DF = 0: done. DF = 1: it said why (nothing on the card changed, or the file is as it was, rewritten).
; No name (11 spaces: LW2 with no document): no file is made - the folder's names go to NAMESB, T and the FAT
; sector are found as for a new file, and the note's entry has no name; Lite-Writer asks for one at ^W (NN0).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

MAXF    EQU     60000           ; the longest document (Lite-Writer 3 holds a part at a time; LW2 refuses one over 5,204)
ROOMS   EQU     128             ; the sectors kept for the file, 64 KB (2026-10-30: was 8, for 4 KB) - in its own FAT
                                ; sector they cost nothing: nothing else may be written in that FAT sector anyway

        ORG     ATTORG - 6      ; (after STELLAR.PRG; nothing else is there until MON's stub loads the apps)
        DW      START, PEND - START, START
        ORG     ATTORG
START:  GLO     RC              ; R9.0 = 0: RC = ATTFND (STELLAR.PRG's FINDN just found it)
        XRI     LOW(ATTFND)
        STR     R2
        GHI     RC
        XRI     HIGH(ATTFND)
        OR
        PLO     R9
        LOAD    RC, ANAME       ; the name, kept
        SEP     R4
        DW      CP11
; ---- 1: the file there? (L = 0: a new one) Laid out already: only the note. Else COPYF = 1: copied at step 4
        LOAD    RD, COPYF
        LDI     0
        STR     RD
        LOAD    RD, LEN
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, OLDF        ; OLDF = 0: no old entry (yet)
        LDI     0
        STR     RD
        LOAD    RD, NONM        ; NONM = 0: a name was given
        LDI     0
        STR     RD
        LOAD    RD, ANAME       ; no name (spaces: LW2 alone): the folder's names for LW2, and a place made ready
        LDN     RD
        XRI     ' '
        LBZ     NN0
        GLO     R9              ; found just now: FINDN's fields and DIRBUF are it, RF = DPTR - 32
        LBNZ    S1F
        LOAD    RD, KS_DPTR
        LDA     RD
        PHI     RF
        LDN     RD
        SMI     32
        PLO     RF
        GHI     RF
        SMBI    0
        PHI     RF
        LBR     S1G
S1F:    LOAD    RD, ANAME
        SEP     R4
        DW      KS_FINDN
        LBDF    S2              ; not there: a new file
S1G:    GHI     RF              ; there: its entry kept in OLDE (it moves to T if it is copied) ...
        PHI     RA
        GLO     RF
        PLO     RA
        LOAD    RC, OLDE
        LDI     32
        PLO     RB
S1H:    LDA     RA
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    S1H
        GLO     RF              ; ... its dates (entry bytes 13-25) in OLDT, OLDF = 1
        ADI     13
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LOAD    RD, OLDT
        LDI     13
        PLO     RB
OT1:    LDA     RF
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    OT1
        LDI     1
        STR     RD              ; (OLDF follows OLDT)
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    ISDIR
        LOAD    RD, KS_DSIZE    ; DSIZE <= MAXF
        LDA     RD
        LBNZ    TOOBIG
        LDA     RD
        LBNZ    TOOBIG
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        SMI     LOW(MAXF + 1)
        GHI     RC
        SMBI    HIGH(MAXF + 1)
        LBDF    TOOBIG
        LOAD    RD, LEN
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4              ; laid out already (the last open made it so; ^W keeps it so)? Then nothing
        DW      LAID            ; on the card is written - only the note
        LBNF    S5
        LOAD    RD, COPYF       ; no: copied at step 4 (it stays where it is until it has been)
        LDI     1
        STR     RD
; ---- 2: a directory sector of its own: T = the first sector at or after the folder's end marker - or, when the
;      sectors just before the end marker hold only deleted entries (the last open's T among them), the first of
;      those: the folder's end moves back to T. (It used to grow a sector every time a file in it was opened.)
S2:     LOAD    RD, RUNST       ; RUNST: the first of the all-deleted sectors before the end marker (FFFF: none)
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        LOAD    RC, 0
SD1:    SEP     R4
        DW      KS_DIRRD
        LBDF    SDX             ; no end marker in the folder at all: T = RC, past its end
        LOAD    RF, KS_DIRBUF
        LDI     16
        PLO     RB
        LDI     0
        PHI     RB              ; RB.1 = 1: a live entry in this sector
SD2:    LDN     RF              ; the end marker (a never-used entry)?
        LBZ     SD3
        XRI     0E5H
        LBZ     SD2N
        LDI     1
        PHI     RB
SD2N:   GLO     RF
        ADI     32
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        DEC     RB
        GLO     RB
        LBNZ    SD2
        LOAD    RD, RUNST       ; a whole sector: the run of deleted ones ends, starts here, or goes on
        GHI     RB
        LBZ     SD2R
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        LBR     SD2X
SD2R:   LDN     RD
        XRI     0FFH
        LBNZ    SD2X
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
SD2X:   INC     RC
        LBR     SD1
SD3:    GHI     RB              ; the end marker: anything live before it, in this sector?
        LBNZ    SD3L
SD3R:   LOAD    RD, RUNST       ; no: T = the run's first sector, or this one
        LDN     RD
        XRI     0FFH
        LBZ     SD6
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LBR     SD6
SD3L:   LOAD    RD, RUNST       ; yes: no run before it counts any more (live entries follow it)
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
SD4:    LDI     0E5H            ; else: the rest of it marked deleted (the folder then reads on) ...
        STR     RF
        GLO     RF
        ADI     32
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        DEC     RB
        GLO     RB
        LBNZ    SD4
        SEP     R4
        DW      KS_DIRWR
        LBDF    CARD
        INC     RC              ; ... and T is the next one
        SEP     R4
        DW      KS_DIRRD
        LBNF    SD6
SDX:    LOAD    RD, RUNST       ; past the folder's end: its last sectors all deleted - T is the first of them
        LDN     RD
        XRI     0FFH
        LBNZ    SD3R
        SEP     R4              ; else it grows a cluster (the root cannot)
        DW      KS_SLX
        LBDF    DIRFULL
SD6:    LOAD    RD, TSEC        ; TSEC = T
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RF, KS_DIRBUF   ; sector T: all 0, written
        LDI     0
        PLO     RB
SD7:    LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    SD7
        SEP     R4
        DW      KS_DIRWR
        LBDF    CARD
        LOAD    RD, KS_WDSEC    ; the new entry goes at its start
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        LDI     HIGH(KS_DIRBUF)
        STR     RD
        INC     RD
        LDI     LOW(KS_DIRBUF)
        STR     RD
; ---- 3: (after the folder has grown, if it had to - it takes a cluster) a FAT sector that is all free: S (from the end down), C1 = S x 256, K clusters for ROOMS sectors
SF2:    LDI     ROOMS           ; K = ROOMS / SPC rounded up: R9.1
        PLO     R9
        SEP     R4
        DW      KCALC
        LOAD    RD, KCL         ; KCL = K (R9.1)
        GHI     R9
        STR     RD
        LOAD    RD, KS_FATSZ+1  ; S = FATSZ - 1 (at most 255) down to 1
        LDN     RD
        SMI     1
        PLO     RA
        LOAD    RD, KS_FATSZ
        LDN     RD
        LBZ     SS1
        LDI     0FFH
        PLO     RA
SS1:    GLO     RA
        LBZ     NOROOM
        LOAD    RD, KCL         ; its K clusters: S x 256 + K - 1 <= NCLUS + 1 ?
        LDN     RD
        SMI     1
        STR     R2
        LOAD    RD, KS_NCLUS+1
        LDN     RD
        ADI     1
        PLO     RC
        DEC     RD
        LDN     RD
        ADCI    0
        PHI     RC              ; RC = NCLUS + 1
        GLO     RC
        SM
        GHI     RC
        STR     R2
        GLO     RA
        SDB                     ; (RC - (S x 256 + K - 1)): a borrow = it runs past the card's clusters
        LBNF    SSN
        GLO     RA              ; that FAT sector (FATSEC: sector RC.1) - all 0?
        PHI     RC
        LDI     0
        PLO     RC
        SEP     R4
        DW      KS_FATSEC
        LBDF    CARD
        LOAD    RF, KS_FATBUF
        LDI     0
        PLO     RB
SS2:    LDA     RF
        LBNZ    SSN
        LDA     RF
        LBNZ    SSN
        DEC     RB
        GLO     RB
        LBNZ    SS2
        LBR     SS3
SSN:    DEC     RA
        LBR     SS1
SS3:    LOAD    RD, C1          ; C1 = S x 256; the next file written starts there
        GLO     RA
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RD, KS_FHINT
        GLO     RA
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RD, NONM        ; no name yet: nothing more is written - the entry is only the note's
        LDN     RD
        LBNZ    NN4
; ---- 4: the file again: copied to its clusters from C1 on (COPYF), or a new one (empty); its entry at T
        LOAD    RD, COPYF
        LDN     RD
        LBNZ    CY0
        LOAD    RD, KS_WSRC     ; (no bytes: WLEN = LEN = 0)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, LEN
        LOAD    RC, KS_WLEN
        SEP     R4
        DW      CP2
        LOAD    RD, KS_PFXN
        LDI     0
        STR     RD
        LOAD    RD, KS_WATTR
        LDI     20H
        STR     RD
        LOAD    RD, ANAME
        LOAD    RC, KS_FNAME
        SEP     R4
        DW      CP11
        SEP     R4
        DW      KS_WFILE2
        LBDF    KS_WERR
S4E:    LOAD    RD, TSEC        ; the entry, as written (stamped now): the note's +17, for ^W
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRRD
        LBDF    CARD
        LOAD    RD, KS_DIRBUF
        LOAD    RC, NOTEB+17
        LDI     32
        PLO     RB
NE1:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    NE1
        LOAD    RD, OLDF        ; an old file: on the card its entry keeps its own dates (opening it is no change)
        LDN     RD
        LBZ     S5
        LOAD    RD, OLDT
        LOAD    RC, KS_DIRBUF+13
        LDI     13
        PLO     RB
OT2:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    OT2
        LOAD    RD, TSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    CARD
; ---- 5: the note
S5:     LOAD    RD, NOTEB       ; 'LW', 0
        LDI     'L'
        STR     RD
        INC     RD
        LDI     'W'
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RD, LEN         ; +3 L
        LOAD    RC, NOTEB+3
        SEP     R4
        DW      CP2
        LOAD    RD, C1          ; +5 D0 = the first sector of C1 (the card: at most 65,536 sectors)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_CL2LBA
        GHI     R8
        LBNZ    TOOFAR
        GLO     R8
        LBNZ    TOOFAR
        LOAD    RD, NOTEB+5
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        INC     RD              ; +7 NSECT = K x SPC
        LOAD    RF, KCL
        LDN     RF
        PLO     RB
        LOAD    RF, KS_SPC
        LDN     RF
        PHI     RB
        LDI     0
        PLO     RA              ; RA.0 = K x SPC (RA's S is in C1 now)
NS1:    GHI     RB
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        DEC     RB
        GLO     RB
        LBNZ    NS1
        GLO     RA
        STR     RD
        INC     RD
        GHI     RB              ; +8 SPC
        STR     RD
        INC     RD
        LOAD    RF, C1          ; +9 C1
        LDA     RF
        STR     RD
        INC     RD
        LDN     RF
        STR     RD
        INC     RD
        LOAD    RF, KS_FATLBA+2 ; +11 FL1 = FATLBA + S
        LDA     RF
        PHI     R7
        LDN     RF
        PLO     R7
        LOAD    RF, C1
        LDN     RF
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        INC     RD
        LOAD    RF, KS_NFATS    ; +13 FL2 = FL1 + FATSZ, or 0 with one copy
        LDN     RF
        SMI     2
        LBDF    NF2
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        LBR     NF3
NF2:    LOAD    RF, KS_FATSZ+1
        LDN     RF
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        DEC     RF
        LDN     RF
        STR     R2
        GHI     R7
        ADC
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        INC     RD
NF3:    GHI     RD              ; (RD kept on the stack: DIRLBA uses it)
        STXD
        GLO     RD
        STXD
        LOAD    RD, TSEC        ; +15 DLBA = sector T's
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRLBA
        IRX
        LDXA
        PLO     RD
        LDX
        PHI     RD
        LBDF    CARD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        INC     RD
        LOAD    RC, NOTEB+49    ; (+17 the entry: put there above)
        LOAD    RD, ANAME       ; +49 the name, NAME.EXT and a 0
        LDI     8
        PLO     RB
NZ1:    LDA     RD
        XRI     ' '
        LBZ     NZ2
        XRI     ' '
        STR     RC
        INC     RC
NZ2:    DEC     RB
        GLO     RB
        LBNZ    NZ1
        LDN     RD
        XRI     ' '
        LBZ     NZ4
        LDI     '.'
        STR     RC
        INC     RC
        LDI     3
        PLO     RB
NZ3:    LDA     RD
        XRI     ' '
        LBZ     NZ3A
        XRI     ' '
        STR     RC
        INC     RC
NZ3A:   DEC     RB
        GLO     RB
        LBNZ    NZ3
NZ4:    LDI     0
        STR     RC
        ADI     0               ; DF = 0: done
        SEP     R5

; ---- 4, copied: the old file's sectors, in order, to C1's sectors on; then the old file goes (its entry, long
;      name, clusters), the new chain C1 -> C1+1 ... -> FFFF goes in, and the old entry (its first cluster C1)
;      at T, stamped now, as WFILE2 would have made it - S4E then gives it back its dates
CY0:    LOAD    RD, ANAME       ; the old one, still there
        SEP     R4
        DW      KS_FINDN
        LBDF    CARD
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, C1          ; CLBA = C1's first sector
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_CL2LBA
        LOAD    RD, CLBA
        SEP     R4
        DW      KS_ST32
CY1:    SEP     R4              ; the next sector -> DATBUF
        DW      KS_FREAD
        LBNF    CY2
        XRI     2
        LBZ     CARD
        LBR     CY3             ; all of it
CY2:    LOAD    RD, CLBA
        SEP     R4
        DW      KS_LD32
        LOAD    RF, KS_DATBUF
        SEP     R4
        DW      KS_IDEWR
        LBDF    CARD
        LOAD    RD, CLBA
        SEP     R4
        DW      KS_LD32
        LOAD    RC, 1
        SEP     R4
        DW      KS_ADD16
        LOAD    RD, CLBA
        SEP     R4
        DW      KS_ST32
        LBR     CY1
CY3:    LOAD    RD, ANAME       ; the old one goes
        SEP     R4
        DW      KS_FINDN
        LBDF    CARD
        SEP     R4
        DW      KS_DELENT
        LBDF    CARD
        LOAD    RD, LEN+1       ; NCL = (LEN + 511) / 512 sectors / SPC rounded up (LEN = 0: none, no cluster)
        LDN     RD
        ADI     0FFH
        DEC     RD
        LDN     RD
        ADCI    01H
        SHR
        PLO     R9
        LDI     0
        PHI     R9
        GLO     R9
        LBZ     CY5
        SEP     R4
        DW      KCALC
CY5:    LOAD    RD, NCL
        GHI     R9
        STR     RD
        LBZ     CY7
        LOAD    RD, C1
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC              ; RC = the cluster
CY6:    GLO     RC              ; R9 = the next, or FFFF for the last
        ADI     1
        PLO     R9
        GHI     RC
        ADCI    0
        PHI     R9
        LOAD    RD, NCL
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    CY6A
        LDI     0FFH
        PHI     R9
        PLO     R9
CY6A:   SEP     R4
        DW      KS_FATPUT
        LBDF    CARD
        INC     RC
        LOAD    RD, NCL
        LDN     RD
        LBNZ    CY6
CY7:    SEP     R4
        DW      KS_FATFLUSH
        LBDF    CARD
        LOAD    RD, TSEC        ; the entry at T: the old one, C1, LEN, stamped now
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRRD
        LBDF    CARD
        LOAD    RD, OLDE
        LOAD    RC, KS_DIRBUF
        LDI     32
        PLO     RB
CY8:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    CY8
        LOAD    RD, LEN         ; +26 the first cluster (C1, or 0: no bytes), +28 the size (little-endian)
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RC, KS_DIRBUF+26
        LOAD    RD, C1
        GLO     RF
        LBNZ    CY9
        GHI     RF
        LBNZ    CY9
        LDI     0
        STR     RC
        INC     RC
        STR     RC
        LBR     CY9A
CY9:    INC     RD
        LDN     RD
        STR     RC
        INC     RC
        DEC     RD
        LDN     RD
        STR     RC
CY9A:   INC     RC
        GLO     RF
        STR     RC
        INC     RC
        GHI     RF
        STR     RC
        INC     RC
        LDI     0
        STR     RC
        INC     RC
        STR     RC
        SEP     R4
        DW      KS_STAMP
        LOAD    RD, KS_STD      ; 18-19 used
        LOAD    RC, KS_DIRBUF+18
        SEP     R4
        DW      CP2
        LOAD    RD, KS_STT      ; 22-25 written
        LOAD    RC, KS_DIRBUF+22
        SEP     R4
        DW      CP2
        LOAD    RD, KS_STD
        LOAD    RC, KS_DIRBUF+24
        SEP     R4
        DW      CP2
        LOAD    RD, TSEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    CARD
        LBR     S4E

; ---- no name yet (STELLAR LW2 with no document): Lite-Writer asks for one at its first ^W
;   NAMESB: the 11-byte names in the folder, then a 0 (STELLAR.PRG's job copies them to LWNAMES, where
;   Lite-Writer checks the name typed against them); T and S are found as for a new file, but no entry is
;   written - the note's +17 is an entry with no name yet (spaces), 0 bytes, stamped now.
NN0:    LOAD    RD, NONM
        LDI     1
        STR     RD
        LOAD    RD, KS_PAT      ; every name in the folder
        LDI     11
        PLO     RB
NN1:    LDI     '?'
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    NN1
        SEP     R4
        DW      KS_DOPEN
        LOAD    RA, NAMESB      ; RA: where the next one goes
        LDI     NAMESMX + 1
        PHI     R9              ; R9.1: room for so many more (+ 1)
NN2:    GHI     RA              ; (RA, R9.1 kept over DNEXT)
        STXD
        GLO     RA
        STXD
        GHI     R9
        STXD
        SEP     R4
        DW      KS_DNEXT        ; RF -> its entry
        IRX
        LDXA
        PHI     R9
        LDXA
        PLO     RA
        LDX
        PHI     RA
        LBDF    NN3
        GHI     R9
        SMI     1
        PHI     R9
        LBZ     MANYN
        LDI     11
        PLO     RB
NN2A:   LDA     RF
        STR     RA
        INC     RA
        DEC     RB
        GLO     RB
        LBNZ    NN2A
        LBR     NN2
NN3:    LDI     0
        STR     RA
        LBR     S2
NN4:    LOAD    RF, NOTEB+17    ; the entry: the name 11 spaces, a file, made / used / written now, 0 bytes
        LDI     11
        PLO     RB
NN5:    LDI     ' '
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    NN5
        LDI     20H             ; 11
        STR     RF
        INC     RF
        LDI     20              ; 12-31: 0 first
        PLO     RB
NN6:    LDI     0
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    NN6
        SEP     R4
        DW      KS_STAMP
        LOAD    RD, KS_STT      ; 14-17 made
        LOAD    RC, NOTEB+17+14
        SEP     R4
        DW      CP2
        LOAD    RD, KS_STD
        LOAD    RC, NOTEB+17+16
        SEP     R4
        DW      CP2
        LOAD    RD, KS_STD      ; 18-19 used
        LOAD    RC, NOTEB+17+18
        SEP     R4
        DW      CP2
        LOAD    RD, KS_STT      ; 22-25 written
        LOAD    RC, NOTEB+17+22
        SEP     R4
        DW      CP2
        LOAD    RD, KS_STD
        LOAD    RC, NOTEB+17+24
        SEP     R4
        DW      CP2
        SEP     R4              ; (a folder that grew a cluster for T: its FAT)
        DW      KS_FATFLUSH
        LBDF    CARD
        LBR     S5
MANYN:  SEP     R4
        DW      K_PIN
        DB      'That folder holds too many files for a new document - use a name: LW2 NAME.TXT',0DH,0AH,0
        LBR     FAIL
; ---- trouble (DF = 1, said)
ISDIR:  SEP     R4
        DW      K_PIN
        DB      'That is a folder, not a document.',0DH,0AH,0
        LBR     FAIL
TOOBIG: SEP     R4
        DW      K_PIN
        DB      'That document is over 60,000 bytes - too long for Lite-Writer.',0DH,0AH,0
        LBR     FAIL
NOROOM: SEP     R4
        DW      K_PIN
        DB      'The card has no free 128 KB stretch for the document.',0DH,0AH,0
        LBR     FAIL
DIRFULL: SEP    R4
        DW      K_PIN
        DB      'That folder (the root?) has no free directory sector for it.',0DH,0AH,0
        LBR     FAIL
TOOFAR: SEP     R4
        DW      K_PIN
        DB      'The document would be past sector 65535 - too far for Lite-Writer.',0DH,0AH,0
        LBR     FAIL
CARD:   SEP     R4
        DW      K_PIN
        DB      'The card failed.',0DH,0AH,0
FAIL:   SMI     0               ; DF = 1
        SEP     R5
; LAID: is the file FINDN just found (LEN its size) laid out as Lite-Writer needs? DF = 0: yes - C1, KCL, TSEC
; and the note's +17 (the entry, used and written now) are set. DF = 1: no (or a read failed), it is rewritten.
;   * its entry is the first of its directory sector, the rest of that sector 0;
;   * its first cluster C is the first of FAT sector C.1, room for K clusters from it;
;   * that FAT sector is its chain - C -> C+1 -> ... -> an end mark, n clusters for LEN bytes - and the rest 0.
LAID:   LOAD    RD, KS_DPTR     ; the entry first in DIRBUF: DNEXT's DPTR (the next one) = DIRBUF + 32
        LDA     RD
        XRI     HIGH(KS_DIRBUF+32)
        LBNZ    LNO
        LDN     RD
        XRI     LOW(KS_DIRBUF+32)
        LBNZ    LNO
        LOAD    RF, KS_DIRBUF+32 ; the other 15 entries: all 0 (480 bytes)
        LDI     240
        PLO     RB
LA1:    LDA     RF
        LBNZ    LNO
        LDA     RF
        LBNZ    LNO
        DEC     RB
        GLO     RB
        LBNZ    LA1
        LOAD    RD, KS_DCLUS    ; C: C.0 = 0, C.1 > 0
        LDA     RD
        PHI     RC
        LBZ     LNO
        LDN     RD
        LBNZ    LNO
        PLO     RC
        LDI     ROOMS           ; K clusters from C: C + K - 1 <= NCLUS + 1 ?
        PLO     R9
        SEP     R4
        DW      KCALC
        LOAD    RD, KCL
        GHI     R9
        STR     RD
        SMI     1
        STR     R2
        LOAD    RD, KS_NCLUS+1
        LDN     RD
        ADI     1
        PLO     RA
        DEC     RD
        LDN     RD
        ADCI    0
        PHI     RA              ; RA = NCLUS + 1
        GLO     RA
        SM
        GHI     RC
        STR     R2
        GHI     RA
        SMB                     ; RA - (C + K - 1): a borrow = past the card's clusters
        LBNF    LNO
        LOAD    RD, LEN+1       ; n = (LEN + 511) / 512 sectors / SPC rounded up (LEN = 0: no clusters - no)
        LDN     RD
        ADI     0FFH
        DEC     RD
        LDN     RD
        ADCI    01H
        SHR
        LBZ     LNO
        PLO     R9
        SEP     R4
        DW      KCALC
        GHI     R9              ; (n kept on the stack)
        STXD
        SEP     R4              ; FAT sector C.1 (RC kept)
        DW      KS_FATSEC
        IRX
        LDX
        PLO     RB              ; RB.0 = the chain's clusters still to come (n, down to 0)
        LBDF    LNO
        LOAD    RF, KS_FATBUF   ; its 256 entries, RC.0 = the one looked at
LA3:    GLO     RB
        LBZ     LA5
        SMI     1
        PLO     RB
        LBZ     LA4
        GLO     RC              ; a link: to the next cluster
        ADI     1
        STR     R2
        LDA     RF
        XOR
        LBNZ    LNO
        GHI     RC
        STR     R2
        LDA     RF
        XOR
        LBNZ    LNO
        LBR     LA6
LA4:    LDA     RF              ; the last: an end mark (FFF8 - FFFF)
        SMI     0F8H
        LBNF    LNO
        LDA     RF
        XRI     0FFH
        LBNZ    LNO
        LBR     LA6
LA5:    LDA     RF              ; after it: free
        LBNZ    LNO
        LDA     RF
        LBNZ    LNO
LA6:    INC     RC
        GLO     RC
        LBNZ    LA3
        LOAD    RD, KS_DCLUS    ; yes: C1 = C, TSEC = the entry's sector
        LOAD    RC, C1
        SEP     R4
        DW      CP2
        LOAD    RD, KS_DSEC
        LOAD    RC, TSEC
        SEP     R4
        DW      CP2
        LOAD    RD, KS_DIRBUF   ; the note's +17: the entry as it is (created kept), used and written now
        LOAD    RC, NOTEB+17
        LDI     32
        PLO     RB
LA7:    LDA     RD
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    LA7
        SEP     R4
        DW      KS_STAMP
        LOAD    RD, KS_STD      ; 18-19 used
        LOAD    RC, NOTEB+17+18
        SEP     R4
        DW      CP2
        LOAD    RD, KS_STT      ; 22-25 written
        LOAD    RC, NOTEB+17+22
        SEP     R4
        DW      CP2
        LOAD    RD, KS_STD
        LOAD    RC, NOTEB+17+24
        SEP     R4
        DW      CP2
        ADI     0               ; DF = 0
        SEP     R5
LNO:    SMI     0               ; DF = 1
        SEP     R5
; KCALC: R9.1 = R9.0 sectors / SPC, rounded up (R9.0 > 0)
KCALC:  LOAD    RD, KS_SPC
        LDN     RD
        STR     R2
        LDI     0
        PHI     R9
KC1:    GHI     R9
        ADI     1
        PHI     R9
        GLO     R9
        SM
        PLO     R9
        LBZ     KC2
        LBDF    KC1
KC2:    SEP     R5
; CP2 / CP11: 2 / 11 bytes from RD to RC
CP2:    LDA     RD
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
ANAME:  DS      11
LEN:    DS      2
C1:     DS      2
KCL:    DS      1
TSEC:   DS      2
RUNST:  DS      2               ; the first all-deleted sector before the end marker (FFFF: none)
OLDT:   DS      13              ; the old entry's bytes 13-25: its created, used and written dates
OLDF:   DS      1               ; 1: the file was there (follows OLDT)
NONM:   DS      1               ; 1: no name yet (LW2 alone)
COPYF:  DS      1               ; 1: the file is copied to its new place at step 4
OLDE:   DS      32              ; the old entry
CLBA:   DS      4               ; the next sector it is copied to
NCL:    DS      1               ; clusters of the new chain still to put in
PEND:
        END
