; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; install.asm - the LTOS installer (F = format + install, U = update LTOS, keeping the files). Load INSTALL.HEX with the monitor (it pastes Intel HEX records),
; then CALL 3000. It formats the CF card as one FAT16 partition, saves the STELLAR firmware that is in
; RAM ($0000-$2EFF) as STELLAR.BIN, writes the kernel (none yet in phase 0) and the boot sector.
;
; Memory: this code $3000-$47FF, the boot sector image $4800 (build.py puts it there), the kernel image $4A00
; (21 sectors at most, to $73FF), the files for the card after it (FTAB), SBUF FBUF RBUF VBUF $7600-$7DFF,
; NUMBUF $7E00. $0000-$2EFF (STELLAR) is only read.
;
; The card:  LBA 0 = MBR (boot code + partition table) | LBA 64 = the partition: its boot record (BPB),
; 31 reserved sectors for the kernel, FAT 1, FAT 2, the root directory (512 entries, 32 sectors), data.
; Clusters: 1 sector up to ~32 MB, then 2, 4 ... so there are never more than 65,000 (FAT16's limit
; is 65,524). Written in this order - tables, STELLAR.BIN, kernel, partition boot record, MBR last - so a
; card left half-done never boots.

        CPU     1802
        INCL    "ltos.inc"

SBUF    EQU     7620H
FBUF    EQU     7820H           ; the FAT's first sector, built here
RBUF    EQU     7A20H           ; the root directory's first sector, built here
VBUF    EQU     7C20H           ; WRSEC reads each sector back here
NUMBUF  EQU     7E20H           ; (PDEC32's digits; the monitor's stack is above, its RAM from $7F00)
FTABMAX EQU     7400H           ; the files' table (FTAB): right after the kernel image, $7400 at the latest -
                                ;  a count, then name (11) size (2) where (2) each; their bytes after (build.py)
BOOTIMG EQU     4800H
KERNIMG EQU     4A00H
I2AT    EQU     4800H           ; INSTALL2.HEX's files (CALL 3003, after F: the kernel image is on the card by then)
PSTART  EQU     64              ; the partition's first sector
RESV    EQU     32              ; its reserved sectors (boot record + kernel)
ROOTN   EQU     32              ; root directory sectors
STLSIZE EQU     2F00H           ; STELLAR firmware, $0000-$2EFF
STLSECT EQU     24

        ORG     3000H
START:  LBR     START0          ; CALL 3000: F (format + install) or U (update)
        LBR     ADD2            ; CALL 3003: after F, the files INSTALL2.HEX brought (RECV first) onto the card
START0:
        GLO     R2              ; for FATAL: the monitor's stack and return
        PLO     RF
        GHI     R2
        PHI     RF
        LDI     HIGH(SAVR2)
        PHI     RD
        LDI     LOW(SAVR2)
        PLO     RD
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        INC     RD
        GHI     R6
        STR     RD
        INC     RD
        GLO     R6
        STR     RD
        SEX     R2
        LOAD    RD, NGLITCH     ; the read-back counts start at 0 every run
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'LTOS installer - LTOS 0.5',0DH,0AH,0
        SEP     R4
        DW      CHKIMG          ; did INSTALL.HEX load as it was built?
        SEP     R4
        DW      PIN
        DB      'Card reset, 8-bit mode:   ',0
        SEP     R4
        DW      IDERST
        LBDF    NOCARD
        SEP     R4
        DW      PIN
        DB      'OK',0DH,0AH,'Card:                     ',0
        LDI     3
        PLO     RA              ; up to 3 tries for two IDENTIFYs whose model, LBA flag and size agree
ID0:    LOAD    RF, SBUF
        SEP     R4
        DW      IDEID
        LBDF    NOCARD
        LOAD    RF, VBUF
        SEP     R4
        DW      IDEID
        LBDF    NOCARD
        LOAD    RD, SBUF        ; every byte that differs is shown; only the fields used must agree
        LOAD    RF, VBUF
        LDI     0
        PHI     RB              ; RB.1 = differences in the fields used
        PLO     RC              ; RC = the offset
        PHI     RC
        PLO     RB              ; RB.0 = differences shown (8 at most)
ID1:    LDA     RD
        STR     R2
        LDA     RF
        XOR
        LBZ     ID4
        GLO     RB              ; show it: "  IDENTIFY byte $oo: $aa / $bb"
        SMI     8
        LBDF    ID1A
        INC     RB
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'  IDENTIFY byte $',0
        GHI     RC
        SEP     R4
        DW      PHEX2
        GLO     RC
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ': $',0
        DEC     RD
        LDN     RD
        INC     RD
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ' / $',0
        DEC     RF
        LDN     RF
        INC     RF
        SEP     R4
        DW      PHEX2
ID1A:   GHI     RC              ; a field used? bytes 54-93 (model), 98-99 (LBA), 120-123 (size)
        LBNZ    ID4
        GLO     RC
        SMI     54
        LBNF    ID4
        GLO     RC
        SMI     94
        LBNF    IDUSE
        GLO     RC
        SMI     98
        LBNF    ID4
        GLO     RC
        SMI     100
        LBNF    IDUSE
        GLO     RC
        SMI     120
        LBNF    ID4
        GLO     RC
        SMI     124
        LBDF    ID4
IDUSE:  GHI     RB
        ADI     1
        PHI     RB
ID4:    INC     RC
        GHI     RC
        XRI     2
        LBNZ    ID1
        GHI     RB
        LBZ     ID3             ; the fields used agree
        DEC     RA
        GLO     RA
        LBNZ    ID0
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'The card gives a different model or size each time it is asked - nothing written.',0DH,0AH,0
        LBR     FATAL
ID3:    GLO     RB
        LBZ     ID3B
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'  (only bytes LTOS does not use differ)',0DH,0AH,'                          ',0
ID3B:

; ---- the model name: words 27-46, each word's two characters swapped
        LDI     0
        PLO     RC
MOD1:   GLO     RC
        XRI     1
        ADI     LOW(SBUF+54)
        PLO     RF
        LDI     HIGH(SBUF+54)
        ADCI    0
        PHI     RF
        LDN     RF
        SEP     R4
        DW      F_TYPE
        INC     RC
        GLO     RC
        XRI     40
        LBNZ    MOD1

; ---- its size: R8:R7 = sectors (bytes 120-123)
        LDI     HIGH(SBUF+120)
        PHI     RF
        LDI     LOW(SBUF+120)
        PLO     RF
        LDA     RF
        PLO     R7
        LDA     RF
        PHI     R7
        LDA     RF
        PLO     R8
        LDN     RF
        PHI     R8
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'Size:                     ',0
        SEP     R4
        DW      PMB             ; R8:R7 sectors in MB
        LDI     HIGH(SBUF+99)
        PHI     RF
        LDI     LOW(SBUF+99)
        PLO     RF
        LDN     RF
        ANI     02H
        LBNZ    LBAOK
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'This card has no LBA addressing - LTOS needs it.',0DH,0AH,0
        LBR     FATAL
LBAOK:

; ---- the partition: P = sectors - 64, at most 4,190,208 (FAT16's 2 GB); at least 8,192 (4 MB)
        GLO     R7
        SMI     PSTART
        PLO     R7
        GHI     R7
        SMBI    0
        PHI     R7
        GLO     R8
        SMBI    0
        PLO     R8
        GHI     R8
        SMBI    0
        PHI     R8
        LBNZ    CAP
        GLO     R8
        SMI     40H
        LBNF    NOCAP
CAP:    LDI     0
        PHI     R8
        LDI     3FH
        PLO     R8
        LDI     0F0H
        PHI     R7
        LDI     0
        PLO     R7
NOCAP:  GLO     R8
        LBNZ    BIGOK
        GHI     R7
        SMI     20H
        LBDF    BIGOK
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'The card is too small for FAT16 (4 MB at least).',0DH,0AH,0
        LBR     FATAL
BIGOK:  LDI     HIGH(PSEC)      ; keep P
        PHI     RF
        LDI     LOW(PSEC)
        PLO     RF
        GLO     R7
        STR     RF
        INC     RF
        GHI     R7
        STR     RF
        INC     RF
        GLO     R8
        STR     RF
        INC     RF
        GHI     R8
        STR     RF

; ---- sectors per cluster: double it until P / spc < 65,000.  RA:R9 = P / spc, RB.0 = spc, RB.1 = shift
        GHI     R8
        PHI     RA
        GLO     R8
        PLO     RA
        GHI     R7
        PHI     R9
        GLO     R7
        PLO     R9
        LDI     1
        PLO     RB
        LDI     0
        PHI     RB
SPC1:   GHI     RA
        LBNZ    SPC2
        GLO     RA
        LBNZ    SPC2
        GLO     R9
        SMI     0E8H            ; 65,000 = $FDE8
        GHI     R9
        SMBI    0FDH
        LBNF    SPC3
SPC2:   GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        GHI     R9
        SHRC
        PHI     R9
        GLO     R9
        SHRC
        PLO     R9
        GLO     RB
        SHL
        PLO     RB
        GHI     RB
        ADI     1
        PHI     RB
        LBR     SPC1
SPC3:   LDI     HIGH(SPC)
        PHI     RF
        LDI     LOW(SPC)
        PLO     RF
        GLO     RB
        STR     RF
        INC     RF
        GHI     RB
        STR     RF              ; SHIFT
; ---- FAT size = (P/spc + 2 + 255) / 256 sectors, then where everything starts
        GLO     R9
        ADI     01H
        GHI     R9
        ADCI    01H
        PLO     RC              ; RC.0 = F
        LDI     HIGH(FATSZ)
        PHI     RF
        LDI     LOW(FATSZ)
        PLO     RF
        GLO     RC
        STR     RF
        LDI     HIGH(FAT1)      ; FAT1 = 64 + 32
        PHI     RF
        LDI     LOW(FAT1)
        PLO     RF
        LDI     0
        STR     RF
        INC     RF
        LDI     PSTART+RESV
        STR     RF
        INC     RF
        GLO     RC              ; FAT2 = FAT1 + F
        ADI     PSTART+RESV
        PLO     RD
        LDI     0
        ADCI    0
        PHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        INC     RF
        GLO     RC              ; ROOT = FAT2 + F
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        INC     RF
        GLO     RD              ; DATA = ROOT + 32
        ADI     ROOTN
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
; ---- clusters = (P - (DATA - 64)) >> shift; FAT16 needs 4,085 at least
        GLO     RD
        SMI     PSTART
        PLO     RD
        GHI     RD
        SMBI    0
        PHI     RD
        GLO     RD
        STR     R2
        GLO     R7
        SM
        PLO     R9
        GHI     RD
        STR     R2
        GHI     R7
        SMB
        PHI     R9
        GLO     R8
        SMBI    0
        PLO     RA
        GHI     R8
        SMBI    0
        PHI     RA
        GHI     RB
        PLO     RC
CL1:    GLO     RC
        LBZ     CL2
        GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        GHI     R9
        SHRC
        PHI     R9
        GLO     R9
        SHRC
        PLO     R9
        DEC     RC
        LBR     CL1
CL2:    GLO     R9
        SMI     0F5H            ; 4,085 = $0FF5
        GHI     R9
        SMBI    0FH
        LBDF    CLOK
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'Too few clusters for FAT16.',0DH,0AH,0
        LBR     FATAL
CLOK:   SEP     R4
        DW      PIN
        DB      0DH,0AH,'FAT16:                    ',0
        GHI     R9
        PHI     RD
        GLO     R9
        PLO     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' clusters of ',0
        LDI     0
        PHI     RD
        LDI     HIGH(SPC)
        PHI     RF
        LDI     LOW(SPC)
        PLO     RF
        LDN     RF
        SHR                     ; spc x 512 / 1024 = KB (spc 1 -> 0: say 512 bytes)
        PLO     RD
        LBNZ    CLK
        SEP     R4
        DW      PIN
        DB      '512 bytes',0
        LBR     CLK2
CLK:    SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' KB',0
CLK2:

; ---- is STELLAR in RAM? Its first bytes are a jump and its version: 30 10 00 61 xx (V0061.xx). A booted LTOS
;      leaves those but overwrites the rest - so not if LTOS is at $0303.
        LOAD    RD, HASSTL
        LDI     0
        STR     RD
        LOAD    RF, 0000H
        LDA     RF
        XRI     30H
        LBNZ    NOSTL
        LDA     RF
        XRI     10H
        LBNZ    NOSTL
        INC     RF
        LDN     RF
        XRI     61H
        LBNZ    NOSTL
        LOAD    RF, 0303H
        LDA     RF
        XRI     'L'
        LBNZ    ISSTL
        LDA     RF
        XRI     'T'
        LBNZ    ISSTL
        LDA     RF
        XRI     'O'
        LBNZ    ISSTL
        LDN     RF
        XRI     'S'
        LBZ     NOSTL
ISSTL:  LOAD    RD, HASSTL
        LDI     1
        STR     RD
NOSTL:

; ---- the question
        SEP     R4
        DW      PIN
        DB      0DH,0AH,0DH,0AH,'F = format the card - THIS ERASES EVERYTHING ON IT - and install LTOS;',0DH,0AH,0
        LOAD    RD, HASSTL
        LDN     RD
        LBZ     Q1
        SEP     R4
        DW      PIN
        DB      '    STELLAR V00',0
        LOAD    RF, 0003H
        LDA     RF
        SEP     R4
        DW      PHEX2
        LDI     '.'
        SEP     R4
        DW      F_TYPE
        LDN     RF
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ' is in RAM: it is saved on the card as STELLAR.BIN',0
        LBR     Q2
Q1:     SEP     R4
        DW      PIN
        DB      '    (STELLAR is not in RAM: no STELLAR.BIN)',0
Q2:     SEP     R4
        DW      PIN
        DB      0DH,0AH,'U = update LTOS on this card - your files stay as they are'
        DB      0DH,0AH,'anything else = stop.   Which? ',0
        SEP     R4
        DW      F_READ
        ANI     0DFH
        XRI     'F'
        LBZ     GOAHEAD
        XRI     13H             ; ('F' xor 'U': now zero if it was U)
        LBZ     UPDATE
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'Nothing written.',0DH,0AH,0
        LBR     FATAL
GOAHEAD:
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'Clearing the FATs and the root directory ... ',0

; ---- 1. FAT 1, FAT 2 and the root directory: zeros
        SEP     R4
        DW      ZBUF
        LDI     HIGH(FAT1)
        PHI     RF
        LDI     LOW(FAT1)
        PLO     RF
        LDA     RF
        PHI     R7
        LDN     RF
        PLO     R7              ; R7 = FAT1
        LDI     HIGH(DATA)
        PHI     RF
        LDI     LOW(DATA)
        PLO     RF
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD              ; RD = DATA: stop there
        LDI     0
        PHI     R8
        PLO     R8
Z1:     SEP     R4
        DW      WRSB
        INC     R7
        GLO     R7
        STR     R2
        GLO     RD
        XOR
        LBNZ    Z1
        GHI     R7
        STR     R2
        GHI     RD
        XOR
        LBNZ    Z1

; ---- 2-4. the files: STELLAR.BIN from RAM, then the sample files (FTAB) - each in the next free clusters,
;           its FAT chain in FBUF, its directory entry in RBUF; then FBUF to both FATs and RBUF to the root.
        SEP     R4
        DW      PIN
        DB      'done',0DH,0AH,'Writing the files:',0DH,0AH,0
        LOAD    RF, FBUF
        SEP     R4
        DW      ZERO
        LOAD    RF, FBUF        ; the media entries
        LDI     0F8H
        STR     RF
        INC     RF
        LDI     0FFH
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        STR     RF
        LOAD    RF, RBUF
        SEP     R4
        DW      ZERO
        LOAD    RD, DIRTPL      ; the volume label
        LOAD    RF, RBUF
        LDI     32
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    RD, RBPTR
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, NEXTCL
        LDI     0
        STR     RD
        INC     RD
        LDI     2
        STR     RD
        LOAD    RD, HASSTL      ; STELLAR.BIN, if STELLAR is in RAM
        LDN     RD
        LBZ     FL0
        LOAD    RD, STLENT
        SEP     R4
        DW      ADDFILE
FL0:
        LOAD    RF, FTABP       ; the files for the card (FTABP: where build.py put their table)
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LDA     RD
        PLO     RA
FL1:    GLO     RA
        LBZ     FL2
        SEP     R4
        DW      ADDFILE         ; (RD ends at the next entry; RA is kept)
        DEC     RA
        LBR     FL1
FL2:    SEP     R4
        DW      WFR

; ---- 5. the kernel, into the reserved sectors after the partition's boot record
        SEP     R4
        DW      PIN
        DB      'Writing the kernel ... ',0
        SEP     R4
        DW      WKERN
        SEP     R4
        DW      PIN
        DB      'Writing the partition boot record ... ',0

; ---- 6. the partition's boot record (the BPB)
        SEP     R4
        DW      ZBUF
        LDI     HIGH(VBRTPL)
        PHI     RD
        LDI     LOW(VBRTPL)
        PLO     RD
        LDI     HIGH(SBUF)
        PHI     RF
        LDI     LOW(SBUF)
        PLO     RF
        LDI     VBRLEN
        PLO     RC
        SEP     R4
        DW      COPYN
        LDI     HIGH(SBUF+13)   ; sectors per cluster
        PHI     RF
        LDI     LOW(SBUF+13)
        PLO     RF
        LDI     HIGH(SPC)
        PHI     RD
        LDI     LOW(SPC)
        PLO     RD
        LDN     RD
        STR     RF
        LDI     LOW(SBUF+22)    ; FAT size (16 bits, little-endian)
        PLO     RF
        LDI     HIGH(FATSZ)
        PHI     RD
        LDI     LOW(FATSZ)
        PLO     RD
        LDN     RD
        STR     RF
        LDI     HIGH(PSEC+2)    ; the partition's size: 16 bits at +19 if it fits, else 32 bits at +32
        PHI     RD
        LDI     LOW(PSEC+2)
        PLO     RD
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    BIGP
        LDI     LOW(SBUF+19)
        PLO     RF
        LDI     2
        LBR     PUTP
BIGP:   LDI     LOW(SBUF+32)
        PLO     RF
        LDI     4
PUTP:   PLO     RC
        LDI     HIGH(PSEC)
        PHI     RD
        LDI     LOW(PSEC)
        PLO     RD
        SEP     R4
        DW      COPYN
        LDI     HIGH(SBUF+510)
        PHI     RF
        LDI     LOW(SBUF+510)
        PLO     RF
        LDI     55H
        STR     RF
        INC     RF
        LDI     0AAH
        STR     RF
        LDI     PSTART
        PLO     R7
        LDI     0
        PHI     R7
        PHI     R8
        PLO     R8
        SEP     R4
        DW      WRSB

; ---- 7. the MBR, last: the partition table (16 bytes + 48 zeros) and STELLAR.BIN's sector into PTKEEP /
;         STLKEEP, then WMBR
        SEP     R4
        DW      PIN
        DB      'done',0DH,0AH,'Writing the boot sector ... ',0
        LOAD    RF, PTKEEP
        LDI     64
        PLO     RC
PK0:    LDI     0
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    PK0
        LOAD    RD, PTTPL
        LOAD    RF, PTKEEP
        LDI     12              ; status, CHS start, type, CHS end, LBA start
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    RD, PSEC        ; the size
        LDI     4
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    RD, PSEC+2      ; type: $04 (FAT16, under 32 MB) or $06
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     SMALLP
        LOAD    RF, PTKEEP+4
        LDI     06H
        STR     RF
SMALLP: LOAD    RD, DATA        ; STELLAR.BIN starts at the first data sector (0: there is none)
        LOAD    RF, STLKEEP
        LDI     2
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    RD, HASSTL
        LDN     RD
        LBNZ    SMP2
        LOAD    RF, STLKEEP
        LDI     0
        STR     RF
        INC     RF
        STR     RF
SMP2:
        SEP     R4
        DW      WMBR
        SEP     R4
        DW      PIN
        DB      'done',0DH,0AH,0
        SEP     R4
        DW      WSUM
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'The card is ready but for RECV: load INSTALL2.HEX with the monitor, then CALL 3003.',0DH,0AH,0
        LOAD    RD, FDONE       ; (CALL 3003 checks F has been done)
        LDI     0A5H
        STR     RD
        LBR     FATAL
; ---- ADD2 (CALL 3003): after F in this session (FDONE), the files INSTALL2.HEX put at I2AT - [16-bit sum, its
;      bytes, then a count and name (11) size (2) where (2) each; their bytes after] - into the next free clusters
;      and root entries, as F's own (ADDFILE: NEXTCL, RBPTR, FBUF, RBUF as F left them); the FAT and root again.
ADD2:
        GLO     R2              ; for FATAL: the monitor's stack and return
        PLO     RF
        GHI     R2
        PHI     RF
        LDI     HIGH(SAVR2)
        PHI     RD
        LDI     LOW(SAVR2)
        PLO     RD
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        INC     RD
        GHI     R6
        STR     RD
        INC     RD
        GLO     R6
        STR     RD
        SEX     R2
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'LTOS installer - the files from INSTALL2.HEX',0DH,0AH,0
        LOAD    RD, FDONE
        LDN     RD
        XRI     0A5H
        LBZ     A21
        SEP     R4
        DW      PIN
        DB      'First F (CALL 3000); then load INSTALL2.HEX and CALL 3003.',0DH,0AH,0
        LBR     FATAL
A21:    LOAD    RD, I2AT+2      ; RC = its bytes, R7 = their sum
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RF, I2AT+4
        LOAD    R7, 0
A22:    GHI     RC
        LBNZ    A23
        GLO     RC
        LBZ     A24
A23:    LDA     RF
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        DEC     RC
        LBR     A22
A24:    LOAD    RD, I2AT
        LDA     RD
        STR     R2
        GHI     R7
        XOR
        LBNZ    A2BAD
        LDN     RD
        STR     R2
        GLO     R7
        XOR
        LBZ     A25
A2BAD:  SEP     R4
        DW      PIN
        DB      'INSTALL2.HEX did not load as it was built - load it again, then CALL 3003.',0DH,0AH,0
        LBR     FATAL
A25:    LOAD    RD, FDONE       ; (only once)
        LDI     0
        STR     RD
        SEP     R4
        DW      PIN
        DB      'Writing the files:',0DH,0AH,0
        LOAD    RD, I2AT+4
        LDA     RD
        PLO     RA
A26:    GLO     RA
        LBZ     A27
        SEP     R4
        DW      ADDFILE         ; (RD ends at the next entry; RA is kept)
        DEC     RA
        LBR     A26
A27:    SEP     R4
        DW      WFR
        SEP     R4
        DW      WSUM
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'The card is ready. Type BOOT.',0DH,0AH
        DB      'Then the rest of the programs: elfser.py system, or RECV SYSTEM with each LTOS-SYSTEM.HEX.',0DH,0AH,0
        LBR     FATAL           ; (back to the monitor)

; ---- U: a new kernel and boot sector on an LTOS card; its partition, files and STELLAR.BIN stay
UPDATE: SEP     R4
        DW      PIN
        DB      0DH,0AH,'Reading the boot sector ... ',0
        LOAD    R7, 0
        LOAD    R8, 0
        LOAD    RF, SBUF
        SEP     R4
        DW      IDERD
        LBDF    NOCARD
        LOAD    RF, SBUF+3      ; 'LTS' at 3 and the MBR signature: an LTOS card
        LDA     RF
        XRI     'L'
        LBNZ    NOTL
        LDA     RF
        XRI     'T'
        LBNZ    NOTL
        LDN     RF
        XRI     'S'
        LBNZ    NOTL
        LOAD    RF, SBUF+1FEH
        LDA     RF
        XRI     55H
        LBNZ    NOTL
        LDN     RF
        XRI     0AAH
        LBNZ    NOTL
        LOAD    RD, SBUF+1BEH   ; keep its partition table ...
        LOAD    RF, PTKEEP
        LDI     64
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    RD, SBUF+30H    ; ... and where its STELLAR.BIN is
        LOAD    RF, STLKEEP
        LDI     2
        PLO     RC
        SEP     R4
        DW      COPYN
        SEP     R4
        DW      PIN
        DB      'an LTOS card.',0DH,0AH,'Writing the kernel ... ',0
        SEP     R4
        DW      WKERN
        SEP     R4
        DW      PIN
        DB      'Writing the boot sector ... ',0
        SEP     R4
        DW      WMBR
        SEP     R4
        DW      PIN
        DB      'done',0DH,0AH,0
        SEP     R4
        DW      WSUM
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'LTOS is updated; the files on the card are as they were. Type BOOT.',0DH,0AH,0
        LBR     FATAL
NOTL:   SEP     R4
        DW      PIN
        DB      'this card has no LTOS on it - use F to format it.',0DH,0AH,'Nothing written.',0DH,0AH,0
        LBR     FATAL

; ---- WKERN: the kernel image (KSECTS sectors at KERNIMG) to LBA 65 on; prints how many
WKERN:  LOAD    R7, PSTART+1
        LOAD    R8, 0
        LOAD    RF, KERNIMG
        LOAD    RD, KSECTS
        LDN     RD
        PLO     RC
KS1:    GLO     RC
        LBZ     KS2
        SEP     R4
        DW      WRSEC
        INC     R7
        GHI     RF
        ADI     2
        PHI     RF
        DEC     RC
        LBR     KS1
KS2:    LOAD    RD, KSECTS
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' sectors',0DH,0AH,0
        SEP     R5

; ---- WMBR: LBA 0 = the boot sector image, with STLKEEP at $30, KSECTS + KSUM at $32, PTKEEP at $1BE
WMBR:   LOAD    RD, BOOTIMG
        LOAD    RF, SBUF
        LDI     0               ; 256 ...
        PLO     RC
        SEP     R4
        DW      COPYN
        LDI     0               ; ... and 256
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    RD, STLKEEP
        LOAD    RF, SBUF+30H
        LDI     2
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    RD, KSECTS      ; KSECTS and KSUM (3 bytes) to $32-$34
        LDI     3
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    RD, PTKEEP
        LOAD    RF, SBUF+1BEH
        LDI     64
        PLO     RC
        SEP     R4
        DW      COPYN
        LOAD    R7, 0
        LOAD    R8, 0
        SEP     R4
        DW      WRSB
        SEP     R5

NOCARD: PLO     RD
        SEP     R4
        DW      PIN
        DB      'FAILED - ',0
        GLO     RD
        XRI     0FFH
        LBNZ    NC2
        SEP     R4
        DW      PIN
        DB      'no answer. Is a card in the socket?',0DH,0AH,0
        LBR     FATAL
NC2:    SEP     R4
        DW      PIN
        DB      'card error $',0
        GLO     RD
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PCRLF
; ---- WFR: FBUF to both FATs, RBUF to the root directory
WFR:
        LOAD    RD, FAT1        ; the FAT, twice
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LOAD    R8, 0
        LOAD    RF, FBUF
        SEP     R4
        DW      WRSEC
        LOAD    RD, FAT2
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LOAD    RF, FBUF
        SEP     R4
        DW      WRSEC
        LOAD    RD, ROOT        ; the directory
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     R7
        LOAD    RF, RBUF
        SEP     R4
        DW      WRSEC
        SEP     R5
; ---- FATAL: back to the monitor from any depth (its stack and return as START found them)
FATAL:  LDI     HIGH(SAVR2)
        PHI     RD
        LDI     LOW(SAVR2)
        PLO     RD
        LDA     RD
        PHI     R2
        LDA     RD
        PLO     R2
        LDA     RD
        PHI     R6
        LDN     RD
        PLO     R6
        SEX     R2
        SEP     R5

; ---- WRSB: write SBUF to the sector R8:R7.  WRSEC: write RF's 512 bytes there.  A failure is fatal.
WRSB:   LDI     HIGH(SBUF)
        PHI     RF
        LDI     LOW(SBUF)
        PLO     RF
WRSEC:  GLO     RC              ; (RF, RC, RD kept for the callers - saved first)
        STXD
        GHI     RC
        STXD
        GLO     RD
        STXD
        GHI     RD
        STXD
        LOAD    RD, WTRY        ; up to 3 writes
        LDI     3
        STR     RD
WS0:    SEP     R4
        DW      IDEWR
        LBDF    WFAIL
        LOAD    RD, WAGAIN      ; not yet read again
        LDI     0
        STR     RD
WS1:    GHI     RF              ; read it back and compare
        PHI     RC
        GLO     RF
        PLO     RC              ; RC = what was written
        GLO     R7              ; first another sector (LBA 1, empty, before the partition): a card can give back
        STXD                    ;  what it just took from its own buffer - right - and still keep it wrong (the
        GHI     R7              ;  32 MB SDCFB-32, 2026-10-26)
        STXD
        GLO     R8
        STXD
        GHI     R8
        STXD
        LOAD    R7, 1
        LOAD    R8, 0
        LOAD    RF, VBUF
        SEP     R4
        DW      IDERD
        IRX
        LDXA
        PHI     R8
        LDXA
        PLO     R8
        LDXA
        PHI     R7
        LDX
        PLO     R7
        LBDF    WFAIL
        LOAD    RF, VBUF
        SEP     R4
        DW      IDERD
        LBDF    WFAIL
        GHI     RC
        PHI     RF
        GLO     RC
        PLO     RF
        LOAD    RD, VBUF
WV1:    LDA     RD
        STR     R2
        LDA     RC
        XOR
        LBNZ    WVBAD
        GLO     RD              ; all 512 (VBUF is not page-aligned: the high byte alone stopped 32 bytes short)
        XRI     LOW(VBUF+512)
        LBNZ    WV1
        GHI     RD
        XRI     HIGH(VBUF+512)
        LBNZ    WV1
        LOAD    RD, WAGAIN      ; it matches - after a second read only?
        LDN     RD
        LBZ     WVOK
        SEP     R4
        DW      PIN
        DB      ' - read again: it is right (a read glitch).',0DH,0AH,0
        LOAD    RD, NGLITCH
        LDN     RD
        ADI     1
        STR     RD
WVOK:   IRX
        LDXA
        PHI     RD
        LDXA
        PLO     RD
        LDXA
        PHI     RC
        LDX
        PLO     RC
        SEP     R5
WVBAD:  DEC     RD              ; tell what differs: the sector, the byte, wrote / read
        DEC     RC
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'  sector $',0
        GLO     R7
        STXD
        GHI     R7
        SEP     R4
        DW      PHEX2
        IRX
        LDX
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ' byte $',0
        GLO     RD
        SMI     LOW(VBUF)
        PLO     RB
        GHI     RD
        SMBI    HIGH(VBUF)
        SEP     R4
        DW      PHEX2
        GLO     RB
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ': wrote $',0
        LDN     RC
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ', read $',0
        LDN     RD
        SEP     R4
        DW      PHEX2
        LOAD    RD, WAGAIN      ; first time: read it again
        LDN     RD
        LBNZ    WV2
        LDI     1
        STR     RD
        LBR     WS1
WV2:    LOAD    RD, WTRY        ; still wrong: write it again (3 tries)
        LDN     RD
        SMI     1
        STR     RD
        LBZ     VFAIL
        SEP     R4
        DW      PIN
        DB      ' - writing it again.',0DH,0AH,0
        LOAD    RD, NREWR
        LDN     RD
        ADI     1
        STR     RD
        LBR     WS0
VFAIL:  SEP     R4
        DW      PIN
        DB      0DH,0AH,'VERIFY FAILED: the card did not keep what was written to sector $',0
        LBR     WF2
WFAIL:  PLO     RD
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'WRITE FAILED at sector $',0
WF2:
        GHI     R8
        SEP     R4
        DW      PHEX2
        GLO     R8
        SEP     R4
        DW      PHEX2
        GHI     R7
        SEP     R4
        DW      PHEX2
        GLO     R7
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ', error $',0
        GLO     RD
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      '. The card is not bootable; run the installer again.',0DH,0AH,0
        LBR     FATAL

; ---- ADDFILE: RD -> a file: name (11), size (2, big-endian), where it is (2). Puts it in the next free clusters:
;      its chain in FBUF, its entry at RBPTR in RBUF, its sectors on the card. RD ends past the entry; RA kept.
ADDFILE: LOAD   RF, FENT
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        LOAD    RF, RBPTR       ; the entry: name, attribute $20 (archive), dates, cluster, size
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RF
        GHI     RC
        PHI     RF
        LDI     11
        PLO     RC
        SEP     R4
        DW      COPYN           ; (RD now at the size)
        LDI     20H
        STR     RF              ; +11
        INC     RF              ; created +14/+16, accessed +18, written +22/+24
        INC     RF
        INC     RF              ; +14
        SEP     R4
        DW      PUTDT
        SEP     R4
        DW      PUTDT2          ; +18: the date only
        INC     RF
        INC     RF              ; +22
        SEP     R4
        DW      PUTDT           ; RF = +26
        LOAD    RC, NEXTCL+1    ; the first cluster (little-endian)
        LDN     RC
        STR     RF
        INC     RF
        DEC     RC
        LDN     RC
        STR     RF
        INC     RF              ; +28: the size, little-endian, 16 bits used
        LDA     RD
        PHI     R9
        LDA     RD
        PLO     R9              ; R9 = the size
        STR     RF
        INC     RF
        GHI     R9
        STR     RF
        LDA     RD
        PHI     RB
        LDA     RD
        PLO     RB              ; RB = where its bytes are
        LOAD    RF, RBPTR       ; RBPTR += 32
        INC     RF
        LDN     RF
        ADI     32
        STR     RF
        DEC     RF
        LDN     RF
        ADCI    0
        STR     RF
        SEP     R4              ; print it: "  NAME.EXT"
        DW      PIN
        DB      '  ',0
        LOAD    RF, FENT
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        LDI     11
        PLO     RF
AF0:    LDA     RC
        SEP     R4
        DW      F_TYPE
        DEC     RF
        GLO     RF
        LBNZ    AF0
        SEP     R4
        DW      PIN
        DB      '  ',0
        GHI     R9
        PHI     RD
        GLO     R9
        PLO     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' bytes',0DH,0AH,0
        GLO     R9              ; sectors = (size + 511) >> 9  ->  RC.1
        ADI     0FFH
        GHI     R9
        ADCI    01H
        SHR
        PHI     RC
        LOAD    RF, SPC         ; clusters = (sectors + spc - 1) >> shift  ->  RC.0
        LDN     RF
        SMI     1
        STR     R2
        GHI     RC
        ADD
        PLO     RC
        LOAD    RF, SHIFT
        LDN     RF
        PLO     R9              ; (R9: the size is no longer needed)
AF1:    GLO     R9
        LBZ     AF2
        GLO     RC
        SHR
        PLO     RC
        DEC     R9
        LBR     AF1
AF2:    LOAD    RF, NEXTCL      ; the chain: NEXTCL .. NEXTCL + clusters - 1 in FBUF
        LDA     RF
        PHI     R7
        LDN     RF
        PLO     R7              ; R7 = the cluster
        GLO     RC
        PLO     R8              ; R8.0 = clusters to chain
AF3:    GLO     R8
        LBZ     AF5
        GLO     R7              ; RF = FBUF + 2 x cluster (clusters stay under 256: build.py checks)
        SHL
        ADI     LOW(FBUF)
        PLO     RF
        LDI     HIGH(FBUF)
        ADCI    0
        PHI     RF
        DEC     R8
        GLO     R8
        LBZ     AF4
        GLO     R7              ; -> the next cluster
        ADI     1
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        INC     R7
        LBR     AF3
AF4:    LDI     0FFH            ; the end of the chain
        STR     RF
        INC     RF
        STR     RF
        INC     R7
AF5:    LOAD    RF, NEXTCL+1    ; the data starts at DATA + (NEXTCL - 2) << shift ...
        LDN     RF
        SMI     2
        PLO     R8              ; (clusters < 256: one byte)
        GLO     R7              ; ... and NEXTCL moves past this file
        STR     RF
        DEC     RF
        GHI     R7
        STR     RF
        GLO     R8
        PLO     R7
        LDI     0
        PHI     R7
        LOAD    RF, SHIFT
        LDN     RF
        PLO     R9
AF6:    GLO     R9
        LBZ     AF7
        GLO     R7
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        DEC     R9
        LBR     AF6
AF7:    LOAD    RF, DATA        ; + DATA
        INC     RF
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
        PHI     R7
        LDI     0
        PHI     R8
        PLO     R8
        GHI     RB              ; RF = its bytes; RC.1 sectors
        PHI     RF
        GLO     RB
        PLO     RF
AF8:    GHI     RC
        LBZ     AF9
        SEP     R4
        DW      WRSEC
        INC     R7
        GHI     RF
        ADI     2
        PHI     RF
        GHI     RC
        SMI     1
        PHI     RC
        LBR     AF8
AF9:    LOAD    RF, FENT        ; RD past the entry: FENT + 15
        LDA     RF
        PHI     RD
        LDN     RF
        ADI     15
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        SEP     R5
; PUTDT: the time then the date (DATEV: time lo, hi, date lo, hi) at RF; RF past them.  PUTDT2: the date only.
PUTDT:  LOAD    RC, DATEV
        LDA     RC
        STR     RF
        INC     RF
        LDA     RC
        STR     RF
        INC     RF
        LBR     PUTD3
PUTDT2: LOAD    RC, DATEV+2
PUTD3:  LDA     RC
        STR     RF
        INC     RF
        LDN     RC
        STR     RF
        INC     RF
        SEP     R5

; ---- WSUM: how the read-backs went
WSUM:   SEP     R4
        DW      PIN
        DB      'Every sector read back right',0
        LOAD    RF, NGLITCH
        LDA     RF
        STR     R2
        LDN     RF
        OR
        LBNZ    WSU1
        SEP     R4
        DW      PIN
        DB      '.',0DH,0AH,0
        SEP     R5
WSU1:   SEP     R4
        DW      PIN
        DB      ' in the end - read glitches: ',0
        LOAD    RF, NGLITCH
        LDN     RF
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ', sectors written again: ',0
        LOAD    RF, NREWR
        LDN     RF
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PCRLF
        SEP     R5

; ---- CHKIMG: the bytes INSTALL.HEX put in RAM, range by range (CHKTAB: start, length, 16-bit sum - set by
;      build.py), against what was built. A dropped or garbled line in the paste stops the install here.
CHKIMG: LOAD    RD, CKBAD       ; no range wrong yet; CKP = the next CHKTAB entry
        LDI     0
        STR     RD
        LOAD    RD, CKP
        LDI     HIGH(CHKTAB)
        STR     RD
        INC     RD
        LDI     LOW(CHKTAB)
        STR     RD
CI1:    LOAD    RD, CKP         ; RF = start, RC = length, RB = their sum
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        LDA     R9
        PHI     RF
        LDA     R9
        PLO     RF
        LDA     R9
        PHI     RC
        LDA     R9
        PLO     RC
        LDI     0
        PLO     RB
        PHI     RB
CI2:    GHI     RC
        LBNZ    CI3
        GLO     RC
        LBZ     CI4
CI3:    LDA     RF
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        DEC     RC
        LBR     CI2
CI4:    LDA     R9              ; the sum it should be
        STR     R2
        GHI     RB
        XOR
        PLO     RC
        LDA     R9
        STR     R2
        GLO     RB
        XOR
        STR     R2
        GLO     RC
        OR
        LBZ     CI5
        LOAD    RD, CKBAD       ; wrong: say where (start .. RF - 1)
        LDI     1
        STR     RD
        DEC     RF
        SEP     R4
        DW      PIN
        DB      '  $',0
        LOAD    RD, CKP
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDA     RC
        PHI     RD
        LDN     RC
        PLO     RD
        SEP     R4
        DW      PHEX4
        SEP     R4
        DW      PIN
        DB      '-$',0
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        SEP     R4
        DW      PHEX4
        SEP     R4
        DW      PIN
        DB      ' does not add up',0DH,0AH,0
CI5:    LOAD    RD, CKP         ; the next entry: 6 bytes on
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        GLO     R9
        ADI     6
        STR     RD
        DEC     RD
        GHI     R9
        ADCI    0
        STR     RD
        INC     RD
        LDN     RD
        XRI     LOW(CHKTAB+30)  ; (5 entries)
        LBNZ    CI1
        LOAD    RD, CKBAD
        LDN     RD
        LBNZ    CIBAD
        SEP     R5
CIBAD:  SEP     R4
        DW      PIN
        DB      'INSTALL.HEX did not load right. Nothing written. Paste it again, slower.',0DH,0AH,0
        LBR     FATAL

; ---- ZERO: 512 zeros at RF
ZERO:   LDI     0
        PLO     RC
ZE1:    LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    ZE1
        SEP     R5

; ---- ZBUF: SBUF = zeros
ZBUF:   LDI     HIGH(SBUF)
        PHI     RF
        LDI     LOW(SBUF)
        PLO     RF
        LDI     0
        PLO     RC
ZB1:    LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    ZB1
        SEP     R5

; ---- COPYN: RC.0 bytes (0 = 256) from RD to RF; both left past them
COPYN:  LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    COPYN
        SEP     R5

        INCL    "ide.asm"
        INCL    "cons.asm"
        INCL    "nums.asm"

; ---- the partition's boot record: jump, OEM, BPB (fields filled in above), the FAT16 extension
VBRTPL: DB      0EBH, 3CH, 90H, 'LTOS1.0 '
        DB      00H, 02H        ; 11 bytes per sector: 512
        DB      1               ; 13 sectors per cluster (set)
        DB      RESV, 0         ; 14 reserved sectors
        DB      2               ; 16 FATs
        DB      00H, 02H        ; 17 root entries: 512
        DB      0, 0            ; 19 total sectors, 16 bits (set)
        DB      0F8H            ; 21 media: fixed disk
        DB      0, 0            ; 22 sectors per FAT (set)
        DB      32, 0           ; 24 sectors per track (only for CHS)
        DB      64, 0           ; 26 heads (only for CHS)
        DB      PSTART, 0, 0, 0 ; 28 hidden sectors = where the partition starts
        DB      0, 0, 0, 0      ; 32 total sectors, 32 bits (set)
        DB      80H, 0, 29H     ; 36 drive, reserved, extended boot signature
        DB      'LTOS'          ; 39 volume serial number
        DB      'LTOS       '   ; 43 volume label
        DB      'FAT16   '      ; 54 file system type
        DB      'LTOS data partition - boot from the card, not from here.',0
VBRLEN  EQU     $ - VBRTPL

; ---- the partition table entry (the size is added after)
PTTPL:  DB      80H             ; bootable
        DB      02H, 01H, 00H   ; CHS of LBA 64 (32 sectors, 64 heads): head 2, sector 1, cylinder 0
        DB      04H             ; FAT16 under 32 MB (06 put in for bigger)
        DB      0FEH, 0FFH, 0FFH ; CHS end: "use the LBA"
        DB      PSTART, 0, 0, 0 ; LBA start

; ---- the root directory's first entry: the volume label
DIRTPL: DB      'LTOS       ', 08H
        DB      0,0, 0,60H, 4CH,5DH, 4CH,5DH, 0,0, 0,60H, 4CH,5DH, 0,0, 0,0,0,0

CODEEND:                        ; CHKTAB's first range: $3000 up to here
; ---- variables
CHKTAB: DW      0, 0, 0         ; (build.py) the code: start, length, sum
        DW      0, 0, 0         ;            the boot sector image
        DW      0, 0, 0         ;            the kernel image
        DW      0, 0, 0         ;            the files for the card (FTAB)
        DW      0, 0, 0         ;            the files placed after the installer's variables
FTABP:  DW      0               ; (build.py) where the files' table is
CKP:    DW      0               ; CHKIMG: the next CHKTAB entry; 1 if a range did not add up
CKBAD:  DB      0
NGLITCH: DB     0               ; read-backs that were right the second time
NREWR:  DB      0               ; sectors written again
KSECTS: DB      0               ; kernel sectors at KERNIMG (build.py sets it) ...
KSUM:   DW      0               ; ... and the 16-bit sum of their bytes (KSECTS must stay just before KSUM)
DATEV:  DW      0, 0            ; the files' time and date, FAT form, little-endian (build.py: the build's)
STLENT: DB      'STELLAR BIN'   ; STELLAR.BIN for ADDFILE: from RAM $0000, 12,032 bytes
        DB      HIGH(STLSIZE), LOW(STLSIZE), 0, 0
FDONE:  DB      0               ; $A5: F has been done in this session (CALL 3003 may add INSTALL2.HEX's files)
SAVR2:  DS      4
PSEC:   DS      4
SPC:    DS      1
SHIFT:  DS      1
FATSZ:  DS      1
FAT1:   DS      2
FAT2:   DS      2
ROOT:   DS      2
DATA:   DS      2
HASSTL: DS      1               ; 1: STELLAR is in RAM (F saves it as STELLAR.BIN)
NEXTCL: DS      2               ; the next free cluster
RBPTR:  DS      2               ; the next free entry in RBUF
FENT:   DS      2               ; ADDFILE's entry
WTRY:   DS      1               ; WRSEC: writes left
WAGAIN: DS      1               ; WRSEC: 1 = this is the second read
STLKEEP: DS     2               ; STELLAR.BIN's first sector, for the boot sector
PTKEEP: DS      64              ; the partition table, for the boot sector
INSTEND:                        ; build.py checks this is below SBUF
        END
