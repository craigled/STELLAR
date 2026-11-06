; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; diskinfo.asm - DISKINFO.PRG: DISKINFO [-Q | -S] - all about the card: what it is (its IDENTIFY answer), its partition,
;   the volume (FAT16: who formatted it, the label, the serial, clusters, FATs), the space free and used, the files
;   and folders in every folder, the clusters the FAT marks bad. -S also reads every sector of the card (any key
;   stops it) and counts the ones that fail. -Q: quick - the card, the partition and the volume alone, from the card's
;   IDENTIFY answer and two sectors: no FAT or folders read, so no space or contents (the label: the boot record's).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
QMAX    EQU     256             ; folders waiting to be looked in, at most

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
        LOAD    RD, VARS        ; the variables: 0
        LDI     NVARS
        PLO     RB
ST1:    LDI     0
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    ST1
        LDN     RF              ; -S: the surface scan too
        XRI     '-'
        LBNZ    ST2
        INC     RF
        LDA     RF
        ORI     20H
        PLO     RC
        LDN     RF              ; (nothing after the letter)
        LBNZ    USE
        GLO     RC
        XRI     'q'
        LBNZ    ST1A
        LOAD    RD, QUICK
        LDI     1
        STR     RD
        LBR     ST3
ST1A:   GLO     RC
        XRI     's'
        LBNZ    USE
        LOAD    RD, SCAN
        LDI     1
        STR     RD
        LBR     ST3
ST2:    LDN     RF
        LBNZ    USE
; ---- the card: its IDENTIFY answer
ST3:    SEP     R4
        DW      KS_PIN
        DB      'Card',0DH,0AH,'  Model:         ',0
        LOAD    RF, KS_SECBUF
        SEP     R4
        DW      KS_IDEID
        LBDF    NOCARD
        LOAD    RF, KS_SECBUF+54        ; words 27-46
        LDI     40
        SEP     R4
        DW      PIDS
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Serial number: ',0
        LOAD    RF, KS_SECBUF+20        ; words 10-19
        LDI     20
        SEP     R4
        DW      PIDS
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Firmware:      ',0
        LOAD    RF, KS_SECBUF+46        ; words 23-26
        LDI     8
        SEP     R4
        DW      PIDS
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Kind:          ',0
        LOAD    RF, KS_SECBUF   ; word 0: 848AH for CompactFlash
        LDA     RF
        XRI     8AH
        LBNZ    K2
        LDN     RF
        XRI     84H
        LBNZ    K2
        SEP     R4
        DW      KS_PIN
        DB      'CompactFlash',0
        LBR     K3
K2:     SEP     R4
        DW      KS_PIN
        DB      'ATA (IDE) drive',0
        LOAD    RF, KS_SECBUF
        LDN     RF
        ANI     80H
        LBZ     K3
        SEP     R4
        DW      KS_PIN
        DB      ', removable',0
K3:     LOAD    RF, KS_SECBUF+99        ; word 49 bit 9: LBA
        LDN     RF
        ANI     02H
        LBZ     K4
        SEP     R4
        DW      KS_PIN
        DB      ', LBA addressing',0
K4:     SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Size:          ',0
        LOAD    RF, KS_SECBUF+120       ; words 60-61: the sectors
        SEP     R4
        DW      KS_GETLE32
        LOAD    RD, NSEC
        SEP     R4
        DW      KS_ST32
        SEP     R4
        DW      KS_PMB
        SEP     R4
        DW      KS_PIN
        DB      ' = ',0
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' sectors of 512 bytes',0DH,0AH,0
        LOAD    RF, KS_SECBUF+2         ; word 1: cylinders (0: no geometry given)
        LDA     RF
        STR     R2
        LDN     RF
        OR
        LBZ     K5
        SEP     R4
        DW      KS_PIN
        DB      '  Geometry:      ',0
        LOAD    RF, KS_SECBUF+2
        SEP     R4
        DW      LE16P
        SEP     R4
        DW      KS_PIN
        DB      ' cylinders, ',0
        LOAD    RF, KS_SECBUF+6         ; word 3: heads
        SEP     R4
        DW      LE16P
        SEP     R4
        DW      KS_PIN
        DB      ' heads, ',0
        LOAD    RF, KS_SECBUF+12        ; word 6: sectors a track
        SEP     R4
        DW      LE16P
        SEP     R4
        DW      KS_PIN
        DB      ' sectors a track',0DH,0AH,0
; ---- the partition table (sector 0)
K5:     LOAD    R7, 0
        LOAD    R8, 0
        LOAD    RF, VBUF
        SEP     R4
        DW      KS_IDERD
        LBDF    RDERR
        SEP     R4
        DW      KS_PIN
        DB      'Partition',0DH,0AH,'  Table:         ',0
        LOAD    RD, KS_PSTART
        SEP     R4
        DW      KS_LD32
        GLO     R7
        STR     R2
        GHI     R7
        OR
        STR     R2
        GLO     R8
        OR
        STR     R2
        GHI     R8
        OR
        LBNZ    P1
        SEP     R4
        DW      KS_PIN
        DB      'none - the whole card is one volume',0
        LBR     P5
P1:     SEP     R4
        DW      KS_PIN
        DB      'MBR; the first partition',27H,'s type is $',0
        LOAD    RF, VBUF+1C2H
        LDN     RF
        SEP     R4
        DW      KS_PHEX2
        LOAD    RF, VBUF+1C2H
        LDN     RF
        XRI     06H
        LBZ     P2
        XRI     02H             ; (06H, then 04H)
        LBZ     P2
        XRI     0AH             ; (04H, then 0EH)
        LBNZ    P3
P2:     SEP     R4
        DW      KS_PIN
        DB      ' (FAT16)',0
P3:     LDI     0               ; the other three entries in use
        PLO     RC
        LOAD    RF, VBUF+1D2H
P3A:    LDN     RF
        LBZ     P3B
        INC     RC
P3B:    GLO     RF
        ADI     16
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        XRI     HIGH(VBUF+1F2H+16)
        LBNZ    P3A
        GLO     RF
        XRI     LOW(VBUF+1F2H+16)
        LBNZ    P3A
        GLO     RC
        LBZ     P4
        SEP     R4
        DW      KS_PIN
        DB      '; others: ',0
        GLO     RC
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      KS_PDEC
P4:     SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Starts at:     sector ',0
        LOAD    RD, KS_PSTART
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
P5:     SEP     R4
        DW      KS_PCRLF
; ---- the volume's boot sector (kept in VBUF), the FAT counted, every folder looked in
        LOAD    RD, KS_PSTART
        SEP     R4
        DW      KS_LD32
        LOAD    RF, VBUF
        SEP     R4
        DW      KS_IDERD
        LBDF    RDERR
        LOAD    RD, QUICK       ; -Q: neither
        LDN     RD
        LBNZ    VOL
        SEP     R4
        DW      FATCNT
        LBDF    RDERR
        SEP     R4
        DW      WALK
        LBDF    RDERR
        SEP     R4
        DW      DOTEND
; ---- the volume
VOL:    SEP     R4
        DW      KS_PIN
        DB      'Volume',0DH,0AH,'  Format:        ',0
        LOAD    RF, VBUF+26H    ; the extended boot record (29H): its file system name
        LDN     RF
        XRI     29H
        LBNZ    V1
        LOAD    RF, VBUF+36H
        LDI     8
        SEP     R4
        DW      PSTRN
        LBR     V2
V1:     SEP     R4
        DW      KS_PIN
        DB      'FAT16',0
V2:     SEP     R4
        DW      KS_PIN
        DB      ', formatted by ',22H,0
        LOAD    RF, VBUF+3
        LDI     8
        SEP     R4
        DW      PSTRN
        SEP     R4
        DW      KS_PIN
        DB      22H,0DH,0AH,'  Label:         ',0
        LOAD    RD, HASLBL      ; the root's label entry, else the boot record's
        LDN     RD
        LBZ     V3
        LOAD    RF, LABEL
        LBR     V4
V3:     LOAD    RF, VBUF+26H
        LDN     RF
        XRI     29H
        LBNZ    V5
        LOAD    RF, VBUF+2BH
        LDN     RF
        XRI     'N'
        LBNZ    V4
        INC     RF
        LDN     RF
        XRI     'O'
        DEC     RF
        LBZ     V5              ; NO NAME: none
V4:     LDI     11
        SEP     R4
        DW      PSTRN
        LBR     V6
V5:     SEP     R4
        DW      KS_PIN
        DB      '(none)',0
V6:     LOAD    RF, VBUF+26H
        LDN     RF
        XRI     29H
        LBNZ    V7
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Serial number: ',0
        LOAD    RF, VBUF+2AH
        LDN     RF
        SEP     R4
        DW      KS_PHEX2
        DEC     RF
        LDN     RF
        SEP     R4
        DW      KS_PHEX2
        LDI     '-'
        SEP     R4
        DW      F_TYPE
        DEC     RF
        LDN     RF
        SEP     R4
        DW      KS_PHEX2
        DEC     RF
        LDN     RF
        SEP     R4
        DW      KS_PHEX2
V7:     SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Sectors:       ',0
        LOAD    RF, VBUF+13H    ; 16-bit count, else the 32-bit one
        SEP     R4
        DW      KS_GETLE16
        GLO     RC
        STR     R2
        GHI     RC
        OR
        LBZ     V8
        GHI     RC
        PHI     R7
        GLO     RC
        PLO     R7
        LOAD    R8, 0
        LBR     V9
V8:     LOAD    RF, VBUF+20H
        SEP     R4
        DW      KS_GETLE32
V9:     LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' in the volume (',0
        LOAD    RF, VBUF+0EH
        SEP     R4
        DW      LE16P
        SEP     R4
        DW      KS_PIN
        DB      ' reserved), media byte $',0
        LOAD    RF, VBUF+15H
        LDN     RF
        SEP     R4
        DW      KS_PHEX2
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Cluster size:  ',0
        LOAD    RD, KS_SPC
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' sectors = ',0
        LOAD    R7, 1
        SEP     R4
        DW      CL2B
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' bytes',0DH,0AH,'  FATs:          ',0
        LOAD    RD, KS_NFATS
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' copies of ',0
        LOAD    RF, KS_FATSZ
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' sectors',0DH,0AH,'  Root folder:   room for ',0
        LOAD    RF, VBUF+11H
        SEP     R4
        DW      LE16P
        SEP     R4
        DW      KS_PIN
        DB      ' entries',0DH,0AH,0
        LOAD    RD, QUICK
        LDN     RD
        LBNZ    DONE
; ---- the space
        SEP     R4
        DW      KS_PIN
        DB      'Space',0DH,0AH,'  Clusters:      ',0
        LOAD    RF, KS_NCLUS
        SEP     R4
        DW      BE16P
        SEP     R4
        DW      KS_PIN
        DB      ' in all, ',0
        LOAD    RF, NFREE
        SEP     R4
        DW      BE16P
        SEP     R4
        DW      KS_PIN
        DB      ' free, ',0
        SEP     R4              ; used = all - free - bad
        DW      USED
        GHI     R7
        PHI     RD
        GLO     R7
        PLO     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R4
        DW      KS_PIN
        DB      ' used, ',0
        LOAD    RF, NBAD
        SEP     R4
        DW      BE16P
        SEP     R4
        DW      KS_PIN
        DB      ' marked bad',0DH,0AH,'  Bytes:         ',0
        LOAD    RF, KS_NCLUS
        SEP     R4
        DW      BE16R7
        SEP     R4
        DW      CL2B
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' in all, ',0
        LOAD    RF, NFREE
        SEP     R4
        DW      BE16R7
        SEP     R4
        DW      CL2B
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' free, ',0
        SEP     R4
        DW      USED
        SEP     R4
        DW      CL2B
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' used',0DH,0AH
; ---- the contents
        DB      'Contents',0DH,0AH,'  Files:         ',0
        LOAD    RF, NFIL
        SEP     R4
        DW      BE16P
        SEP     R4
        DW      KS_PIN
        DB      ', holding ',0
        LOAD    RD, FBYTES
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PIN
        DB      ' bytes',0DH,0AH,'  Folders:       ',0
        LOAD    RF, NDIR
        SEP     R4
        DW      BE16P
        SEP     R4
        DW      KS_PIN
        DB      ' (and the root)',0DH,0AH,0
        LOAD    RD, QFULL
        LDN     RD
        LBZ     C1
        SEP     R4
        DW      KS_PIN
        DB      '  (more than 256 folders: some not counted)',0DH,0AH,0
; ---- bad sectors
C1:     SEP     R4
        DW      KS_PIN
        DB      'Bad sectors',0DH,0AH,'  In the FAT:    ',0
        LOAD    RF, NBAD
        SEP     R4
        DW      BE16P
        SEP     R4
        DW      KS_PIN
        DB      ' clusters marked bad',0DH,0AH,0
        LOAD    RD, SCAN
        LDN     RD
        LBNZ    SCANS
        SEP     R4
        DW      KS_PIN
        DB      '  (DISKINFO -S reads every sector of the card to look for more)',0DH,0AH,0
        LBR     DONE

; ---- -S: every sector read (0 .. NSEC - 1); a dot each 2,048 (1 MB); any key stops it
SCANS:  SEP     R4
        DW      KS_PIN
        DB      '  Reading every sector (a dot a MB; a key stops it) ',0
SC1:    LOAD    RD, SLBA        ; done? SLBA = NSEC
        SEP     R4
        DW      KS_LD32
        LOAD    RD, NSEC+3
        SEX     RD
        GLO     R7
        SM
        DEC     RD
        GHI     R7
        SMB
        DEC     RD
        GLO     R8
        SMB
        DEC     RD
        GHI     R8
        SMB
        SEX     R2
        LBDF    SC8
        GLO     R7              ; each 64 sectors: a key in? (the UART's line status)
        ANI     3FH
        LBNZ    SC2
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        LBZ     SC1A
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Stopped at sector ',0
        LOAD    RD, SLBA
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PCRLF
        LBR     SC9
SC1A:   LOAD    RD, SLBA        ; a dot each 2,048 sectors
        SEP     R4
        DW      KS_LD32
        GHI     R7
        ANI     07H
        STR     R2
        GLO     R7
        OR
        LBNZ    SC2
        LDI     '.'
        SEP     R4
        DW      F_TYPE
SC2:    LOAD    RD, SLBA
        SEP     R4
        DW      KS_LD32
        LOAD    RF, KS_DIRBUF
        SEP     R4
        DW      KS_IDERD
        LBNF    SC3
        LOAD    RD, NSBAD       ; a bad one: counted and named
        SEP     R4
        DW      INC16
        SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'  Bad: sector ',0
        LOAD    RD, SLBA
        SEP     R4
        DW      KS_LD32
        LDI     0
        SEP     R4
        DW      KS_PDEC32
        SEP     R4
        DW      KS_PCRLF
SC3:    LOAD    RD, SLBA
        SEP     R4
        DW      KS_LD32
        LOAD    RC, 1
        SEP     R4
        DW      KS_ADD16
        LOAD    RD, SLBA
        SEP     R4
        DW      KS_ST32
        LBR     SC1
SC8:    SEP     R4
        DW      KS_PCRLF
SC9:    SEP     R4
        DW      KS_PIN
        DB      '  Unreadable:    ',0
        LOAD    RF, NSBAD
        SEP     R4
        DW      BE16P
        SEP     R4
        DW      KS_PIN
        DB      ' sectors (the card moves worn sectors away itself; these it could not)',0DH,0AH,0
DONE:   LOAD    RD, KS_WDIR     ; (WDIR as the kernel leaves it: the root)
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R5

NOCARD: SEP     R4
        DW      KS_PIN
        DB      'the card did not answer',0DH,0AH,0
        SEP     R5
RDERR:  SEP     R4
        DW      KS_PIN
        DB      0DH,0AH,'The card could not be read.',0DH,0AH,0
        LBR     DONE
USE:    SEP     R4
        DW      KS_PIN
        DB      'Usage: DISKINFO [-Q | -S]   (-Q: quick, no space or files; -S: read every sector too)',0DH,0AH,0
        SEP     R5

; ---- FATCNT: the FAT's entries for clusters 2 .. NCLUS + 1: NFREE the free ones (0), NBAD the bad (FFF7). DF = 1: unread
FATCNT: LOAD    RD, KS_NCLUS    ; RB = the last entry + 1 = NCLUS + 2
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        INC     RB
        INC     RB
        LDI     0
        PHI     RA              ; RA = the entry
        PLO     RA
        PHI     R9              ; R9 = free entries
        PLO     R9
FC0:    GLO     RA              ; a new FAT sector every 256 entries
        LBNZ    FC4
        GHI     RA              ; a dot every 4 sectors
        ANI     3
        LBNZ    FC1
        SEP     R4
        DW      DOT
FC1:
        GHI     RA
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    RD, KS_FATLBA
        SEP     R4
        DW      KS_LD32
        SEP     R4
        DW      KS_ADD16
        LOAD    RF, KS_FATBUF
        SEP     R4
        DW      KS_IDERD
        LBDF    FC9
        LOAD    RF, KS_FATBUF
FC4:    LDA     RF
        PLO     RD
        LDA     RF
        PHI     RD
        GHI     RA              ; a cluster (2 or more)?
        LBNZ    FC5
        GLO     RA
        SMI     2
        LBNF    FC7
FC5:    GLO     RD
        STR     R2
        GHI     RD
        OR
        LBNZ    FC6
        INC     R9              ; free
        LBR     FC7
FC6:    GLO     RD              ; bad: FFF7
        XRI     0F7H
        LBNZ    FC7
        GHI     RD
        XRI     0FFH
        LBNZ    FC7
        LOAD    RD, NBAD
        SEP     R4
        DW      INC16
FC7:    INC     RA
        GLO     RA
        STR     R2
        GLO     RB
        XOR
        LBNZ    FC0
        GHI     RA
        STR     R2
        GHI     RB
        XOR
        LBNZ    FC0
        LOAD    RD, NFREE
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        ADI     0               ; DF = 0
FC9:    LOAD    RD, KS_FATCUR   ; FATBUF no longer holds FATCUR's sector
        LDI     0FFH
        STR     RD
        INC     RD
        STR     RD
        SEP     R5

; ---- WALK: every folder, the root first (a queue of their first clusters): NFIL, FBYTES, NDIR, the root's label
WALK:   LOAD    RD, QH          ; QH = QT = QUE; the root (cluster 0) in it
        LDI     HIGH(QUE)
        STR     RD
        INC     RD
        LDI     LOW(QUE)
        STR     RD
        INC     RD
        LDI     HIGH(QUE+2)
        STR     RD
        INC     RD
        LDI     LOW(QUE+2)
        STR     RD
        LOAD    RD, QUE
        LDI     0
        STR     RD
        INC     RD
        STR     RD
W0:     LOAD    RD, QH          ; the queue empty: done (DF = 0)
        LDA     RD
        PHI     RF
        LDA     RD
        PLO     RF
        LDA     RD
        STR     R2
        GHI     RF
        XOR
        LBNZ    W0A
        LDN     RD
        STR     R2
        GLO     RF
        XOR
        LBNZ    W0A
        ADI     0
        SEP     R5
W0A:    LOAD    RD, KS_WDIR     ; WDIR = the next folder; QH on
        LDA     RF
        STR     RD
        INC     RD
        LDA     RF
        STR     RD
        LOAD    RD, QH
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, DSI         ; its sector 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
W1:     SEP     R4              ; a dot for each sector of a folder
        DW      DOT
        LOAD    RD, DSI
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRLBA       ; DF = 1: past the folder's end
        LBDF    W0
        LOAD    RF, KS_DIRBUF
        SEP     R4
        DW      KS_IDERD
        LBDF    W9
        LOAD    RF, KS_DIRBUF
        LDI     16
        PLO     RB
W2:     LDN     RF              ; 0: the folder's end
        LBZ     W0
        XRI     0E5H            ; deleted
        LBZ     W8
        GLO     RF              ; RD = its attributes
        ADI     11
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        XRI     0FH             ; a long name's piece
        LBZ     W8
        LDN     RD
        ANI     08H
        LBNZ    WLBL
        LDN     RD
        ANI     10H
        LBNZ    WFOLD
        LOAD    RD, NFIL        ; a file: counted, its size added
        SEP     R4
        DW      INC16
        GLO     RF
        ADI     28
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        SEP     R4
        DW      KS_GETLE32
        LOAD    RD, FBYTES
        SEP     R4
        DW      KS_ADDM32
        SEP     R4
        DW      KS_ST32
        GLO     RF
        SMI     28
        PLO     RF
        GHI     RF
        SMBI    0
        PHI     RF
        LBR     W8
WLBL:   LOAD    RD, KS_WDIR     ; a label: the root's is the volume's
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    W8
        LOAD    RD, HASLBL
        LDI     1
        STR     RD
        INC     RD              ; (LABEL follows HASLBL)
        LDI     11
        PLO     RC
WL1:    LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    WL1
        GLO     RF
        SMI     11
        PLO     RF
        GHI     RF
        SMBI    0
        PHI     RF
        LBR     W8
WFOLD:  LDN     RF              ; a folder: . and .. are not
        XRI     '.'
        LBZ     W8
        LOAD    RD, NDIR
        SEP     R4
        DW      INC16
        LOAD    RD, QT          ; its first cluster to the queue's end (if there is room)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        XRI     HIGH(QUE+2*QMAX)
        LBNZ    WD1
        GLO     RC
        XRI     LOW(QUE+2*QMAX)
        LBNZ    WD1
        LOAD    RD, QFULL
        LDI     1
        STR     RD
        LBR     W8
WD1:    GLO     RF              ; its cluster: bytes 26-27, little-endian
        ADI     26
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        INC     RD
        LDN     RD
        STR     RC
        INC     RC
        DEC     RD
        LDN     RD
        STR     RC
        INC     RC
        LOAD    RD, QT
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
W8:     GLO     RF              ; the next entry
        ADI     32
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        DEC     RB
        GLO     RB
        LBNZ    W2
        LOAD    RD, DSI         ; the folder's next sector
        SEP     R4
        DW      INC16
        LBR     W1
W9:     SEP     R5              ; (DF = 1)

; ---- small helpers
; PIDS: D characters of an IDENTIFY string at RF (each word's two swapped), its leading spaces left out
PIDS:   PLO     RC
        LOAD    RD, PFLAG       ; PFLAG: 1 once a character has been printed
        LDI     0
        STR     RD
        PHI     RC              ; RC.1 = the next one's index
PI1:    GHI     RC
        XRI     1
        STR     R2
        GLO     RF
        ADD
        PLO     RD
        GHI     RF
        ADCI    0
        PHI     RD
        LDN     RD
        XRI     ' '
        LBNZ    PI2
        LOAD    RD, PFLAG
        LDN     RD
        LBZ     PI3
        LDI     ' '
        LBR     PI2A
PI2:    XRI     ' '
        STR     R2
        LOAD    RD, PFLAG
        LDI     1
        STR     RD
        LDN     R2
PI2A:   SEP     R4
        DW      F_TYPE
PI3:    GHI     RC
        ADI     1
        PHI     RC
        STR     R2
        GLO     RC
        XOR
        LBNZ    PI1
        SEP     R5
; PSTRN: D characters at RF, its trailing spaces left out
PSTRN:  PLO     RC
        STR     R2              ; RB = RF + D - 1: the last; back while it is a space
        GLO     RF
        ADD
        PLO     RB
        GHI     RF
        ADCI    0
        PHI     RB
PS1:    DEC     RB
        LDN     RB
        XRI     ' '
        LBNZ    PS2
        DEC     RC
        GLO     RC
        LBNZ    PS1
        SEP     R5
PS2:
PS3:    LDA     RF
        SEP     R4
        DW      F_TYPE
        DEC     RC
        GLO     RC
        LBNZ    PS3
        SEP     R5
; LE16P: the little-endian word at RF in decimal. BE16P: the big-endian one. BE16R7: R7 = the big-endian word at RF
LE16P:  SEP     R4
        DW      KS_GETLE16
        GHI     RC
        PHI     RD
        GLO     RC
        PLO     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R5
BE16P:  LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      KS_PDEC
        SEP     R5
BE16R7: LDA     RF
        PHI     R7
        LDN     RF
        PLO     R7
        SEP     R5
; INC16: the big-endian word at RD + 1
INC16:  INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5
; USED: R7 = NCLUS - NFREE - NBAD
USED:   LOAD    RD, KS_NCLUS
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LOAD    RD, NFREE+1
        SEP     R4
        DW      SUB7
        LOAD    RD, NBAD+1
SUB7:   SEX     RD              ; R7 -= the big-endian word ending at RD
        GLO     R7
        SM
        PLO     R7
        DEC     RD
        GHI     R7
        SMB
        PHI     R7
        SEX     R2
        SEP     R5
; CL2B: R7 clusters -> R8:R7 bytes (<< SHIFT + 9)
CL2B:   LDI     0
        PHI     R8
        PLO     R8
        LOAD    RD, KS_SHIFT
        LDN     RD
        ADI     9
        PLO     RB
CB1:    SEP     R4
        DW      KS_SHL32
        DEC     RB
        GLO     RB
        LBNZ    CB1
        SEP     R5

OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
VARS:
SCAN:   DS      1
QUICK:  DS      1
NFREE:  DS      2
NBAD:   DS      2
NFIL:   DS      2
NDIR:   DS      2
FBYTES: DS      4
QFULL:  DS      1
NSBAD:  DS      2
SLBA:   DS      4
HASLBL: DS      1
LABEL:  DS      11              ; (just after HASLBL)
NVARS   EQU     $ - VARS
        INCL    "dots.inc"
PEND:
NSEC    EQU     PEND            ; (past the file: not in DISKINFO.PRG)
QH      EQU     PEND + 4
QT      EQU     PEND + 6
DSI     EQU     PEND + 8
PFLAG   EQU     PEND + 10
VBUF    EQU     ((PEND + 11 + 255) / 256) * 256
QUE     EQU     VBUF + 512
        END
