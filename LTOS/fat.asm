; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; fat.asm - LTOS's FAT16 layer, read side (phase 2), INCL'd by the kernel.
;
; 32-bit numbers live in memory big-endian, and in R8:R7 (R8 = the high 16 bits) - the same shape the IDE
; driver takes a sector number in. The root directory only (folders: phase 5).
;
;   MOUNT    read the MBR and the partition's boot record; set the layout. DF = 1 + D: 1 no MBR / not 512-byte
;            sectors / not FAT16-like
;   CL2LBA   RC = a cluster -> R8:R7 = its first sector
;   FATNEXT  RC = a cluster -> RC = the next one in its chain (FATBUF caches one FAT sector)
;   DOPEN    start a walk of the directory WDIR (0: the root, else a folder's first cluster), matching the pattern at PAT (11 bytes, '?' = any)
;   DNEXT    the next matching entry: DF = 0 and its fields in DATTR DCLUS DSIZE DDATE DTIME, RF -> it in
;            DIRBUF; DF = 1 at the end. Skips deleted, long-name, volume, hidden / system and '.' entries.
;   FOPEN    open the entry just found (DCLUS, DSIZE) for reading
;   FREAD    its next sector -> DATBUF; RC = the bytes in it that are the file's (0-512); DF = 1 at the end,
;            or D = 2 if the chain is broken
;   PARSE    RF -> a path "[/]folder/name.ext": WDIR = its folder, the name's 11-byte form at RD (spaces,
;            upper case; * fills '?'); DF = 1 if it is not one (D says why). RF ends past it.
;   PNAME    the same for one name; FOLDIN  WDIR = the folder named at RD, in WDIR
; All keep R2-R6 and RE.1; most use R7 R8 R9 RA RB RC RD RF freely.

; ---- R8:R7 <-> 4 bytes at RD (big-endian); RD left at the first byte
LD32:   LDA     RD
        PHI     R8
        LDA     RD
        PLO     R8
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        DEC     RD
        DEC     RD
        DEC     RD
        SEP     R5
ST32:   GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        DEC     RD
        DEC     RD
        DEC     RD
        SEP     R5
; ---- R8:R7 += the 4 bytes at RD (big-endian)
ADDM32: INC     RD
        INC     RD
        INC     RD
        SEX     RD
        GLO     R7
        ADD
        PLO     R7
        DEC     RD
        GHI     R7
        ADC
        PHI     R7
        DEC     RD
        GLO     R8
        ADC
        PLO     R8
        DEC     RD
        GHI     R8
        ADC
        PHI     R8
        SEX     R2
        SEP     R5
; ---- R8:R7 += RC
ADD16:  GLO     RC
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     RC
        STR     R2
        GHI     R7
        ADC
        PHI     R7
        GLO     R8
        ADCI    0
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        SEP     R5
; ---- R8:R7 <- 4 little-endian bytes at RF;  RC <- 2 little-endian bytes at RF (RF kept)
GETLE32: LDA    RF
        PLO     R7
        LDA     RF
        PHI     R7
        LDA     RF
        PLO     R8
        LDN     RF
        PHI     R8
        DEC     RF
        DEC     RF
        DEC     RF
        SEP     R5
GETLE16: LDA    RF
        PLO     RC
        LDN     RF
        PHI     RC
        DEC     RF
        SEP     R5
; ---- R8:R7 <<= 1 / >>= 1
SHL32:  GLO     R7
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        GLO     R8
        SHLC
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        SEP     R5
SHR32:  GHI     R8
        SHR
        PHI     R8
        GLO     R8
        SHRC
        PLO     R8
        GHI     R7
        SHRC
        PHI     R7
        GLO     R7
        SHRC
        PLO     R7
        SEP     R5
; ---- RF = DIRBUF + RD (a field's offset)
DBF:    GLO     RD
        ADI     LOW(DIRBUF)
        PLO     RF
        GHI     RD
        ADCI    HIGH(DIRBUF)
        PHI     RF
        SEP     R5

; ---- MOUNT
MOUNT:  LOAD    RD, MOUNTED
        LDI     0
        STR     RD
        LOAD    RD, WDIR        ; WDIR, CWD: in this order - the root
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    R7, 0
        LOAD    R8, 0
        LOAD    RF, DIRBUF
        SEP     R4
        DW      IDERD           ; the MBR
        LBDF    MNTE1
        LOAD    RD, 1FEH
        SEP     R4
        DW      DBF
        LDA     RF
        XRI     55H
        LBNZ    MNTE1
        LDN     RF
        XRI     0AAH
        LBNZ    MNTE1
        LOAD    RD, 1C6H        ; partition 1: where it starts
        SEP     R4
        DW      DBF
        SEP     R4
        DW      GETLE32
        LOAD    RD, PSTART
        SEP     R4
        DW      ST32
        LOAD    RF, DIRBUF
        SEP     R4
        DW      IDERD           ; its boot record (R8:R7 = PSTART still)
        LBDF    MNTE1
        LOAD    RD, 11          ; 512 bytes a sector
        SEP     R4
        DW      DBF
        SEP     R4
        DW      GETLE16
        GLO     RC
        LBNZ    MNTE1
        GHI     RC
        XRI     02H
        LBNZ    MNTE1
        LOAD    RD, 13          ; sectors a cluster: a power of 2 -> SHIFT
        SEP     R4
        DW      DBF
        LDN     RF
        LBZ     MNTE1
        LOAD    RD, SPC
        LDN     RF
        STR     RD
        PLO     RC
        LDI     0
        PHI     RC              ; RC.1 = the shift
MS1:    GLO     RC
        SHR
        LBDF    MS2             ; the 1 bit: the rest must be 0
        PLO     RC
        GHI     RC
        ADI     1
        PHI     RC
        LBR     MS1
MS2:    LBNZ    MNTE1           ; more than one bit set
        LOAD    RD, SHIFT
        GHI     RC
        STR     RD
        LOAD    RD, 14          ; FATLBA = PSTART + reserved
        SEP     R4
        DW      DBF
        SEP     R4
        DW      GETLE16
        LOAD    RD, PSTART
        SEP     R4
        DW      LD32
        SEP     R4
        DW      ADD16
        LOAD    RD, FATLBA
        SEP     R4
        DW      ST32
        LOAD    RD, 22          ; ROOTLBA = FATLBA + FATs x FAT size
        SEP     R4
        DW      DBF
        SEP     R4
        DW      GETLE16
        LOAD    RD, FATSZ
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, 16
        SEP     R4
        DW      DBF
        LDN     RF
        LBZ     MNTE1
        PLO     RB              ; RB.0 = the number of FATs
        LOAD    RD, NFATS
        GLO     RB
        STR     RD
MS3:    SEP     R4
        DW      ADD16
        DEC     RB
        GLO     RB
        LBNZ    MS3
        LOAD    RD, ROOTLBA
        SEP     R4
        DW      ST32
        LOAD    RD, 17          ; DATALBA = ROOTLBA + root entries / 16
        SEP     R4
        DW      DBF
        SEP     R4
        DW      GETLE16
        LDI     4
        PLO     RB
MS4:    GHI     RC
        SHR
        PHI     RC
        GLO     RC
        SHRC
        PLO     RC
        DEC     RB
        GLO     RB
        LBNZ    MS4
        LOAD    RD, ROOTSECS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      ADD16
        LOAD    RD, DATALBA
        SEP     R4
        DW      ST32
        LOAD    RD, 19          ; the partition's size: 16 bits, or 0 and 32 bits at +32
        SEP     R4
        DW      DBF
        SEP     R4
        DW      GETLE16
        LDI     0
        PHI     R8
        PLO     R8
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        STR     R2
        GHI     RC
        OR
        LBNZ    MS5
        LOAD    RD, 32
        SEP     R4
        DW      DBF
        SEP     R4
        DW      GETLE32
MS5:    LOAD    RD, PSTART      ; clusters = (size - (DATALBA - PSTART)) >> SHIFT
        SEP     R4
        DW      ADDM32
        LOAD    RD, DATALBA+3   ; R8:R7 = PSTART + size - DATALBA
        SEX     RD
        GLO     R7
        SM
        PLO     R7
        DEC     RD
        GHI     R7
        SMB
        PHI     R7
        DEC     RD
        GLO     R8
        SMB
        PLO     R8
        DEC     RD
        GHI     R8
        SMB
        PHI     R8
        SEX     R2
        LOAD    RD, SHIFT
        LDN     RD
        PLO     RB
MS6:    GLO     RB
        LBZ     MS7
        SEP     R4
        DW      SHR32
        DEC     RB
        LBR     MS6
MS7:    LOAD    RD, NCLUS
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        LOAD    RD, FATCUR      ; no FAT sector cached, none changed; free clusters looked for from 2
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, FATDIRTY
        LDI     0
        STR     RD
        LOAD    RD, FHINT
        LDI     0
        STR     RD
        INC     RD
        LDI     2
        STR     RD
        LOAD    RD, MOUNTED
        LDI     1
        STR     RD
        LDI     0
        SHR                     ; DF = 0
        SEP     R5
MNTE1:  LDI     1
        SHR                     ; DF = 1
        SEP     R5

; ---- CL2LBA: RC = a cluster -> R8:R7 = DATALBA + (RC - 2) << SHIFT
CL2LBA: GLO     RC
        SMI     2
        PLO     R7
        GHI     RC
        SMBI    0
        PHI     R7
        LDI     0
        PHI     R8
        PLO     R8
        LOAD    RD, SHIFT
        LDN     RD
        PLO     RB
CL1:    GLO     RB
        LBZ     CL2
        SEP     R4
        DW      SHL32
        DEC     RB
        LBR     CL1
CL2:    LOAD    RD, DATALBA
        SEP     R4
        DW      ADDM32
        SEP     R5

; ---- FATNEXT: RC = a cluster -> RC = the next (FAT entry RC: sector RC.1 of the FAT, word RC.0)
FATNEXT: SEP    R4              ; FAT sector RC.1 in FATBUF (fatw.asm: a changed one is written back first)
        DW      FATSEC
        LBDF    FNERR
        SEP     R4              ; RF = FATBUF + 2 x RC.0
        DW      FATPTR
        LDA     RF
        PLO     RC
        LDN     RF
        PHI     RC
        LDI     0
        SHR
        SEP     R5
FNERR:  LOAD    RC, 0FFF7H      ; a read error: as if the chain were broken
        LDI     1
        SHR
        SEP     R5

; ---- DOPEN / DNEXT: walk the root directory
DOPEN:  LOAD    RD, DSEC
        LDI     0FFH            ; -1: the first DNEXT loads sector 0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, DLEFT
        LDI     0
        STR     RD              ; no entries left in the (unloaded) sector
        LOAD    RD, DNALL       ; hidden / system files skipped (FINDN sets DNALL after)
        LDI     0
        STR     RD
        LOAD    RD, LFNON       ; no long name seen
        LDI     0
        STR     RD
        LOAD    RD, DDONE       ; not at its end
        LDI     0
        STR     RD
        SEP     R5
DNEXT:  LOAD    RD, DDONE       ; the end was found already
        LDN     RD
        LBNZ    DNEND
        LOAD    RD, DLEFT
        LDN     RD
        LBNZ    DN2
        LOAD    RD, DSEC        ; the next sector of the directory (WDIR: the root, or a folder's chain)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        INC     RC
        GLO     RC
        STR     RD
        DEC     RD
        GHI     RC
        STR     RD
        SEP     R4
        DW      DIRRD           ; DF = 1: past its end (or the card failed)
        LBDF    DNEND
        LOAD    RD, DLEFT
        LDI     16
        STR     RD
        LOAD    RD, DPTR
        LDI     HIGH(DIRBUF)
        STR     RD
        INC     RD
        LDI     LOW(DIRBUF)
        STR     RD
DN2:    LOAD    RD, DLEFT       ; take the entry at DPTR; DPTR += 32
        LDN     RD
        SMI     1
        STR     RD
        LOAD    RD, DPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        ADI     32
        STR     RD
        DEC     RD
        GHI     RF
        ADCI    0
        STR     RD
        LDN     RF              ; first byte
        LBZ     DNLAST          ; 0: the end of the directory
        XRI     0E5H
        LBZ     DNX             ; deleted
        LDN     RF
        XRI     '.'
        LBZ     DNX             ; '.' names (the Mac's own)
        GLO     RF              ; the attribute byte
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        XRI     0FH
        LBZ     DNLFN           ; a long-name piece
        LDN     RD
        ANI     08H
        LBNZ    DNX             ; the volume label
        LDN     RD
        ANI     06H
        LBZ     DNOK
        LOAD    RC, DNALL       ; hidden or system: only for FINDN
        LDN     RC
        LBZ     DNX
DNOK:   LOAD    RD, PAT         ; the pattern: 11 bytes, '?' matches anything
        GHI     RF
        PHI     RC
        GLO     RF
        PLO     RC              ; (RC walks the entry, RF stays on it)
        LDI     11
        PLO     RB
DN3:    LDA     RD
        XRI     '?'
        LBZ     DN4
        DEC     RD
        LDA     RD
        STR     R2
        LDN     RC
        XOR
        LBNZ    DNX
DN4:    INC     RC
        DEC     RB
        GLO     RB
        LBNZ    DN3
        LOAD    RD, LFNON       ; a match: RLFN = whether a long name came just before it (LFNSEC, LFNPTR)
        LDN     RD
        PLO     RB
        LDI     0
        STR     RD
        LOAD    RD, RLFN
        GLO     RB
        STR     RD
        LOAD    RD, DATTR       ; RC is at the attribute
        LDN     RC
        STR     RD
        GLO     RF              ; the time and date (22-25), cluster (26) and size (28)
        ADI     22
        PLO     RF
        SEP     R4
        DW      GETLE16
        LOAD    RD, DTIME
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RF
        INC     RF
        SEP     R4
        DW      GETLE16
        INC     RD
        GHI     RC
        STR     RD              ; DDATE (follows DTIME)
        INC     RD
        GLO     RC
        STR     RD
        INC     RF
        INC     RF
        SEP     R4
        DW      GETLE16
        INC     RD
        GHI     RC
        STR     RD              ; DCLUS (follows DDATE)
        INC     RD
        GLO     RC
        STR     RD
        INC     RF
        INC     RF
        SEP     R4
        DW      GETLE32
        LOAD    RD, DSIZE
        SEP     R4
        DW      ST32
        GLO     RF              ; RF back to the entry
        SMI     28
        PLO     RF
        GHI     RF
        SMBI    0
        PHI     RF
        LDI     0
        SHR
        SEP     R5
DNX:    LOAD    RD, LFNON       ; skipped: a long name before it was not this file's
        LDI     0
        STR     RD
        LBR     DNEXT
DNLFN:  LOAD    RD, LFNON       ; a long-name piece: where the run starts, if this is its first
        LDN     RD
        LBNZ    DNEXT
        LDI     1
        STR     RD
        LOAD    RD, LFNSEC      ; LFNSEC, LFNPTR: in this order
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
        LBR     DNEXT
DNLAST: LOAD    RD, DDONE       ; the end: every later DNEXT ends too
        LDI     1
        STR     RD
DNEND:  LDI     1
        SHR
        SEP     R5

; ---- FOPEN / FREAD
FOPEN:  LOAD    RD, DCLUS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, FCLUS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        LDI     0
        STR     RD              ; FSEC (follows FCLUS)
        LOAD    RD, DSIZE
        SEP     R4
        DW      LD32
        LOAD    RD, FREM
        SEP     R4
        DW      ST32
        SEP     R5
FREAD:  LOAD    RD, FREM
        SEP     R4
        DW      LD32
        GHI     R8
        LBNZ    FR1
        GLO     R8
        LBNZ    FR1
        GHI     R7
        LBNZ    FR1
        GLO     R7
        LBNZ    FR1
        LDI     1               ; nothing left
        SHR
        SEP     R5
FR1:    LOAD    RD, FCLUS       ; a sane cluster?
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SMI     2
        GHI     RC
        SMBI    0
        LBNF    FRBAD           ; under 2
        GLO     RC
        SMI     0F7H
        GHI     RC
        SMBI    0FFH
        LBDF    FRBAD           ; $FFF7 and up
        SEP     R4
        DW      CL2LBA
        LOAD    RD, FSEC
        LDN     RD
        PLO     RC
        LDI     0
        PHI     RC
        SEP     R4
        DW      ADD16
        LOAD    RF, DATBUF
        SEP     R4
        DW      IDERD
        LBDF    FRBAD
        LOAD    RD, FSEC        ; the next sector: of this cluster, or the next cluster's first
        LDN     RD
        ADI     1
        STR     RD
        PLO     RB
        LOAD    RD, SPC
        SEX     RD
        GLO     RB
        XOR
        SEX     R2
        LBNZ    FR2
        LOAD    RD, FSEC
        LDI     0
        STR     RD
        LOAD    RD, FCLUS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      FATNEXT
        LOAD    RD, FCLUS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
FR2:    LOAD    RD, FREM        ; RC = min(512, FREM); FREM -= RC
        SEP     R4
        DW      LD32
        LOAD    RC, 512
        GHI     R8
        LBNZ    FR3
        GLO     R8
        LBNZ    FR3
        GLO     R7
        SMI     LOW(512)
        GHI     R7
        SMBI    HIGH(512)
        LBDF    FR3
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
FR3:    GLO     RC
        STR     R2
        GLO     R7
        SM
        PLO     R7
        GHI     RC
        STR     R2
        GHI     R7
        SMB
        PHI     R7
        GLO     R8
        SMBI    0
        PLO     R8
        GHI     R8
        SMBI    0
        PHI     R8
        SEP     R4
        DW      ST32
        LDI     0
        SHR
        SEP     R5
FRBAD:  LDI     5               ; D = 2 after SHR: the chain or the card failed
        SHR
        SEP     R5

;      RD kept; RF ends past the name. Uses RB, RC, R9, RA.0.
; ---- PARSE: RF -> a path - [/]folder/folder/name - the last part's 11 bytes at RD (kept), WDIR = the folder
;        it is in (from CWD; a leading '/': from the root; '.' and '..' as parts). RF past it; RA kept.
;        DF = 0: a name.  DF = 1: D = 1 not a name; D = 2 no such folder (the part's 11 bytes at RD);
;        D = 3 the path names a folder, not a name in it ("GAMES/", "/"): WDIR = that folder.
;        PPSL = 1: there was a '/' (a name typed alone is looked for in the root too, by the auto-run).
PARSE:  GLO     RA
        STXD
        GHI     RA
        STXD
        SEP     R4
        DW      PPATH
        PLO     RE
        IRX
        LDXA
        PHI     RA
        LDX
        PLO     RA
        GLO     RE
        SEP     R5
PPATH:  SEP     R4
        DW      SKIPSP
        LOAD    RC, PPRD        ; PPRD = RD; PPSL = 0; WDIR = CWD
        GHI     RD
        STR     RC
        INC     RC
        GLO     RD
        STR     RC
        LOAD    RC, PPSL
        LDI     0
        STR     RC
        LOAD    RC, CWD
        LOAD    R9, WDIR
        LDA     RC
        STR     R9
        INC     R9
        LDN     RC
        STR     R9
        LDN     RF
        XRI     '/'
        LBNZ    PZ1
        INC     RF              ; '/': from the root
        LOAD    RC, WDIR
        LDI     0
        STR     RC
        INC     RC
        STR     RC
        LOAD    RC, PPSL
        LDI     1
        STR     RC
PZ1:    LOAD    RC, PPRD
        LDA     RC
        PHI     RD
        LDN     RC
        PLO     RD
        LDN     RF              ; an empty part: the path ends at a folder
        LBZ     PZE
        XRI     ' '
        LBZ     PZE
        SEP     R4
        DW      DOTS            ; '.' or '..'?
        LBNF    PZ2
        SEP     R4
        DW      PNAME
        LBDF    PZBAD
PZ2:    LDN     RF
        XRI     '/'
        LBNZ    PZNAME          ; the last part: a name
        INC     RF              ; a folder: into it
        LOAD    RC, PPSL
        LDI     1
        STR     RC
        LOAD    RC, PPTX
        GHI     RF
        STR     RC
        INC     RC
        GLO     RF
        STR     RC
        SEP     R4
        DW      FOLDIN
        LOAD    RC, PPTX        ; (LOAD keeps DF)
        LDA     RC
        PHI     RF
        LDN     RC
        PLO     RF
        LBNF    PZ1
        LOAD    RC, PPRD
        LDA     RC
        PHI     RD
        LDN     RC
        PLO     RD
        LDI     5               ; D = 2: no such folder
        SHR
        SEP     R5
PZNAME: LDI     0
        SHR
        SEP     R5
PZE:    LDI     7               ; D = 3: a folder
        SHR
        SEP     R5
PZBAD:  LDI     3               ; D = 1: not a name
        SHR
        SEP     R5
; DOTS: RF -> '.' or '..' (then a space, '/' or the end): RD = its 11 bytes, RF past it, DF = 0. Else DF = 1.
DOTS:   GHI     RF
        PHI     RC
        GLO     RF
        PLO     RC
        LDI     0
        PLO     RB
DT1:    LDN     RC
        XRI     '.'
        LBNZ    DT2
        INC     RC
        INC     RB
        LBR     DT1
DT2:    GLO     RB
        LBZ     DTNO
        SMI     3
        LBDF    DTNO
        LDN     RC
        LBZ     DT3
        XRI     ' '
        LBZ     DT3
        LDN     RC
        XRI     '/'
        LBNZ    DTNO
DT3:    GHI     RC
        PHI     RF
        GLO     RC
        PLO     RF
        GHI     RD
        PHI     R9
        GLO     RD
        PLO     R9
        LDI     11
        PLO     RC
DT4:    LDI     ' '
        STR     R9
        INC     R9
        DEC     RC
        GLO     RC
        LBNZ    DT4
        GHI     RD
        PHI     R9
        GLO     RD
        PLO     R9
DT5:    LDI     '.'
        STR     R9
        INC     R9
        DEC     RB
        GLO     RB
        LBNZ    DT5
        LDI     0
        SHR
        SEP     R5
DTNO:   LDI     1
        SHR
        SEP     R5
; FOLDIN: WDIR = the folder named by the 11 bytes at RD, in WDIR ('.': WDIR; '..': its parent - the root
;         stays the root). DF = 1: there is none (or it is a file).
FOLDIN: LDN     RD
        XRI     '.'
        LBNZ    FO5
        INC     RD
        LDN     RD
        DEC     RD
        XRI     '.'
        LBNZ    FOOK            ; '.'
        LOAD    RC, WDIR        ; '..'
        LDA     RC
        STR     R2
        LDN     RC
        OR
        LBZ     FOOK
        LOAD    RC, 0           ; a folder's first sector: '..' is its second entry
        SEP     R4
        DW      DIRRD
        LBDF    FONO
        LOAD    RF, DIRBUF+32
        LDA     RF
        XRI     '.'
        LBNZ    FONO
        LDN     RF
        XRI     '.'
        LBNZ    FONO
        LOAD    RF, DIRBUF+32+26
        SEP     R4
        DW      GETLE16         ; RC = the parent (0: the root)
        LBR     FOSET
FO5:    SEP     R4
        DW      FINDN
        LBDF    FONO
        LOAD    RD, DATTR
        LDN     RD
        ANI     10H
        LBZ     FONO
        LOAD    RD, DCLUS
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
FOSET:  LOAD    RD, WDIR
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
FOOK:   LDI     0
        SHR
        SEP     R5
FONO:   LDI     1
        SHR
        SEP     R5
; ---- PNAME: RF -> one name; RD -> 11 bytes (8 + 3, spaces, upper case, * -> ?s). DF = 1: not a name.
PNAME:  SEP     R4
        DW      SKIPSP
        GHI     RD              ; spaces first
        PHI     RC
        GLO     RD
        PLO     RC
        LDI     11
        PLO     RB
PA0:    LDI     ' '
        STR     RC
        INC     RC
        DEC     RB
        GLO     RB
        LBNZ    PA0
        GHI     RD              ; the name: up to 8, from RD
        PHI     RC
        GLO     RD
        PLO     RC
        LDI     0
        PHI     RB              ; RB.1 = characters taken
        LDI     8
        PLO     RB
        SEP     R4
        DW      PAPART
        LBDF    PABAD
        GHI     RB
        LBZ     PABAD           ; no name at all
        LDN     RF
        XRI     '.'
        LBNZ    PAEND
        INC     RF              ; the extension: up to 3, from RD + 8
        GLO     RD
        ADI     8
        PLO     RC
        GHI     RD
        ADCI    0
        PHI     RC
        LDI     3
        PLO     RB
        SEP     R4
        DW      PAPART
        LBDF    PABAD
PAEND:  LDN     RF              ; it must end at a space, '/' (a path goes on) or the end of the line
        LBZ     PAOK
        XRI     ' '
        LBZ     PAOK
        LDN     RF
        XRI     '/'
        LBNZ    PABAD
PAOK:   LDI     0
        SHR
        SEP     R5
PABAD:  LDI     1
        SHR
        SEP     R5
; PAPART: up to RB.0 characters from RF to RC; stops at '.', space or 0; '*' fills the rest of the part
; with '?'. RB.1 counts the characters taken. DF = 1: a character a name cannot have, or too many.
PAPART: LDN     RF
        LBZ     PPOK
        XRI     ' '
        LBZ     PPOK
        LDN     RF
        XRI     '.'
        LBZ     PPOK
        LDN     RF
        XRI     '/'             ; (a path's next part)
        LBZ     PPOK
        LDN     RF
        XRI     '*'
        LBNZ    PP3
        INC     RF              ; '*': the rest of the part is '?'
        GHI     RB
        ADI     1
        PHI     RB
PP2:    GLO     RB
        LBZ     PPOK
        LDI     '?'
        STR     RC
        INC     RC
        DEC     RB
        LBR     PP2
PP3:    GLO     RB
        LBZ     PPBAD           ; too long
        LDN     RF
        SEP     R4
        DW      UPCH
        PLO     RA
        SMI     '!'
        LBNF    PPBAD           ; control characters and space
        GLO     RA
        SMI     7FH
        LBDF    PPBAD
        LOAD    R9, BADCH       ; and the ones FAT names cannot have
PP4:    LDA     R9
        LBZ     PP5
        STR     R2
        GLO     RA
        XOR
        LBNZ    PP4
        LBR     PPBAD
PP5:    GLO     RA
        STR     RC
        INC     RC
        INC     RF
        DEC     RB
        GHI     RB
        ADI     1
        PHI     RB
        LBR     PAPART
PPOK:   LDI     0
        SHR
        SEP     R5
PPBAD:  LDI     1
        SHR
        SEP     R5
BADCH:  DB      '"*+,:;<=>[', 5CH, ']|',0        ; (a18 takes no backslash in a string; '/' separates)
