; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cfscan.asm - CFSCAN: test every sector of the CF card (native 1802; was the Stellar C CF-Scan). CALL 3000 from
; the monitor - STELLAR, if it is in RAM, is not touched - or RUN CFSCAN.PRG in LTOS.
;
;   R  a read scan: every sector read once; nothing changes.
;   W  a write test: each sector saved, written with a pattern and read back, written with the pattern inverted
;      and read back (every bit of every byte written as 0 and as 1), then written back as it was and checked.
; You choose the first and last sector (hex; Enter = the whole card). Q (or ESC) stops between sectors. A status
; line every few seconds: the sector, %, time gone, time left (the DS12887 clock), bad sectors. LTOS's CF driver:
; the stack slot and a pause after each byte.

        CPU     1802
        INCL    "ltos.inc"

SAVEB   EQU     6000H           ; the sector as it was
WBUF    EQU     6200H           ; pattern 1
WBUF2   EQU     6E00H           ; pattern 2 = pattern 1 inverted
RBUF    EQU     6400H           ; what was read back
KT      EQU     6600H           ; the pattern: an LFSR stream, 256 bytes, used twice a sector
BADL    EQU     6700H           ; the first 16 bad sectors (4 bytes each)

        ORG     3000H - 6       ; the LTOS program header: load address, length, start
        DW      START, PEND - START, START

        ORG     3000H
START:  LOAD    RD, SAVR2       ; the caller's stack and return: BYE goes back from anywhere
        GHI     R2
        STR     RD
        INC     RD
        GLO     R2
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
        DB      0DH,0AH,'CFSCAN - every sector of the CF card',0DH,0AH,0
        SEP     R4
        DW      CARD
        LBDF    BYE
        LOAD    RF, KT          ; the pattern table: an 8-bit Galois LFSR (taps $B8) from $A5
        LDI     0A5H
        PLO     RA
KT1:    GLO     RA
        SHR
        LBNF    KT2
        XRI     0B8H
KT2:    PLO     RA
        STR     RF
        INC     RF
        GLO     RF
        LBNZ    KT1
        LOAD    RD, WBUF        ; WBUF = KT twice; WBUF2 = its inverse (built once; each sector's number is
        LOAD    RF, WBUF2       ;  put in their first 4 bytes, so a sector that answers for another shows)
        LOAD    RC, 512
KT3:    GLO     RD
        PLO     R9
        LDI     HIGH(KT)
        PHI     R9
        LDN     R9
        STR     RD
        INC     RD
        XRI     0FFH
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    KT3
        GHI     RC
        LBNZ    KT3
AGAIN:  SEP     R4
        DW      SCAN
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'S = scan again, any other key = quit: ',0
        SEP     R4
        DW      F_READ
        ANI     0DFH
        XRI     'S'
        LBNZ    DONE
        SEP     R4
        DW      PCRLF
        LBR     AGAIN
DONE:   SEP     R4
        DW      PIN
        DB      0DH,0AH,'CFSCAN finished.',0DH,0AH,0
        LBR     BYE

; ---- SCAN: the questions, then the scan
SCAN:   SEP     R4
        DW      PIN
        DB      0DH,0AH,'R = read scan (reads every sector, changes nothing)',0DH,0AH
        DB      'W = write test (every bit of every sector written as 0 and as 1, each sector put back)',0DH,0AH
        DB      'Q = quit',0DH,0AH,'Which? ',0
        SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      PCRLF
        LOAD    RD, MODE
        GLO     RB
        ANI     0DFH
        XRI     'R'
        LBZ     SC0             ; (D = 0: a read scan)
        GLO     RB
        ANI     0DFH
        XRI     'W'
        LBNZ    SCQ
        LDI     1
SC0:    STR     RD
        LBR     FIRST
SCQ:    LBR     DONE            ; anything else: quit
FIRST:  SEP     R4              ; the first sector
        DW      PIN
        DB      'First sector, in hex (Enter = 0): ',0
        SEP     R4
        DW      GETHEX
        GLO     RB
        LBZ     FI0
        XRI     2
        LBZ     DONE
        XRI     1               ; (2 xor 3)
        LBNZ    FI1
FIBAD:  SEP     R4
        DW      PIN
        DB      '  - not a sector on this card',0DH,0AH,0
        LBR     FIRST
FI0:    LOAD    R7, 0
        LOAD    R8, 0
FI1:    LOAD    RD, NSEC        ; it must be on the card
        SEP     R4
        DW      CMP32
        LBDF    FIBAD
        LOAD    RD, SFIRST
        SEP     R4
        DW      ST32LE
LAST:   SEP     R4              ; the last sector
        DW      PIN
        DB      'Last sector, in hex (Enter = the last one): ',0
        SEP     R4
        DW      GETHEX
        GLO     RB
        LBZ     LA0
        XRI     2
        LBZ     DONE
        XRI     1
        LBNZ    LA1
LABAD:  SEP     R4
        DW      PIN
        DB      '  - not a sector on this card',0DH,0AH,0
        LBR     LAST
LA0:    SEP     R4              ; Enter: N - 1
        DW      LDNSEC
        GLO     R7
        SMI     1
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
LA1:    LOAD    RD, NSEC
        SEP     R4
        DW      CMP32
        LBDF    LABAD
        LOAD    RD, SFIRST      ; and not before the first
        SEP     R4
        DW      CMP32
        LBDF    LA2
        SEP     R4
        DW      PIN
        DB      '  - it is before the first',0DH,0AH,0
        LBR     LAST
LA2:    GLO     R7              ; SEND = the last + 1
        ADI     1
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        GLO     R8
        ADCI    0
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        LOAD    RD, SEND
        SEP     R4
        DW      ST32LE
        LOAD    RD, MODE        ; the question
        LDN     RD
        LBZ     AS1
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'The write test writes every sector three times. Each is saved first and written back,',0DH,0AH
        DB      'but if the power fails during the scan, the sector being tested then is lost.',0DH,0AH
        DB      'Back up the card first. Press Y to start, any other key to stop: ',0
        LBR     AS2
AS1:    SEP     R4
        DW      PIN
        DB      0DH,0AH,'Press Y to start the read scan, any other key to stop: ',0
AS2:    SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      PCRLF
        GLO     RB
        ANI     0DFH
        XRI     'Y'
        LBZ     GOSCAN
        SEP     R5

GOSCAN: SEP     R4
        DW      PIN
        DB      0DH,0AH,'Scanning ',0
        LOAD    RD, SFIRST
        SEP     R4
        DW      LD32LE
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      ' to ',0
        SEP     R4
        DW      LDLAST
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      '. Q stops (the sector in hand is finished first).',0DH,0AH,0
        LOAD    RD, SFIRST      ; CUR = the first
        SEP     R4
        DW      LD32LE
        LOAD    RD, CUR
        SEP     R4
        DW      ST32LE
        LOAD    RD, NBAD        ; NBAD, STOPPED, DAYS, TICK, NGL, NRW: 0
        LDI     10
        PLO     RA
GS1:    LDI     0
        STR     RD
        INC     RD
        DEC     RA
        GLO     RA
        LBNZ    GS1
        SEP     R4              ; the start time
        DW      MINDAY
        LOAD    RD, CLOCK
        LDI     1
        LSNF                    ; (no clock, DF = 1: CLOCK = 0, times not shown)
        LDI     0
        STR     RD
        LOAD    RD, M0
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        GHI     RC              ; MLAST = M0
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      STATUS

; the sectors, one at a time
SL1:    LOAD    RD, CUR         ; at the end?
        SEP     R4
        DW      LD32LE
        LOAD    RD, SEND
        SEP     R4
        DW      CMP32
        LBDF    SEND1
        SEP     R4
        DW      SECTOR          ; DF = 1: the card stopped answering
        LBDF    SSTOP
        LOAD    RD, CUR         ; the next
        SEP     R4
        DW      LD32LE
        GLO     R7
        ADI     1
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        GLO     R8
        ADCI    0
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        LOAD    RD, CUR
        SEP     R4
        DW      ST32LE
        LOAD    RD, TICK        ; a status line every 128 (read) / 16 (write) sectors
        LDN     RD
        ADI     1
        STR     RD
        PLO     RB
        LOAD    RD, MODE
        LDN     RD
        LBZ     SL2
        GLO     RB
        ANI     0FH
        LBR     SL3
SL2:    GLO     RB
        ANI     7FH
SL3:    LBNZ    SL4
        SEP     R4
        DW      STATUS
SL4:    SEP     R4              ; Q / ESC / Ctrl-C stops
        DW      KEYHIT
        LBNF    SL1
        PLO     RB
        ANI     0DFH
        XRI     'Q'
        LBZ     SSTOP2
        GLO     RB
        XRI     1BH
        LBZ     SSTOP2
        GLO     RB
        XRI     03H
        LBNZ    SL1
SSTOP2: LOAD    RD, STOPPED
        LDI     1
        STR     RD
        LBR     SEND2
SSTOP:  SEP     R4
        DW      PIN
        DB      '  The card stopped answering - the scan stops.',0DH,0AH,0
        LBR     SSTOP2
SEND1:
SEND2:  SEP     R4              ; the summary
        DW      STATUS
        SEP     R4
        DW      PIN
        DB      0DH,0AH,0DH,0AH,0
        LOAD    RD, STOPPED
        LDN     RD
        LBZ     SE1
        SEP     R4
        DW      PIN
        DB      'Stopped. To go on later, start at sector ',0
        LOAD    RD, CUR
        SEP     R4
        DW      LD32LE
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      '.',0DH,0AH,0
        LBR     SE2
SE1:    SEP     R4
        DW      PIN
        DB      'Scan complete.',0DH,0AH,0
SE2:    SEP     R4
        DW      PIN
        DB      'Scanned ',0
        LOAD    RD, SFIRST
        SEP     R4
        DW      LD32LE
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      ' up to ',0
        LOAD    RD, CUR
        SEP     R4
        DW      LD32LE
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      ' (',0
        SEP     R4
        DW      DONEN           ; R8:R7 = sectors done
        LDI     11              ; / 2048 = MB
        PLO     RA
SE3:    SEP     R4
        DW      SHR32
        DEC     RA
        GLO     RA
        LBNZ    SE3
        LDI     0
        SEP     R4
        DW      PDEC32
        SEP     R4
        DW      PIN
        DB      ' MB)',0
        LOAD    RD, CLOCK
        LDN     RD
        LBZ     SE4
        SEP     R4
        DW      PIN
        DB      ' in ',0
        LOAD    RD, EM
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      PHM
SE4:    LOAD    RD, MODE
        LDN     RD
        LBZ     SE5
        SEP     R4
        DW      PIN
        DB      ', each written 3 times and read 5 times: ',0
        LBR     SE6
SE5:    SEP     R4
        DW      PIN
        DB      ', each read once: ',0
SE6:    LOAD    RD, NBAD
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    SE7
        SEP     R4
        DW      PIN
        DB      'NO BAD SECTORS.',0DH,0AH,0
        LBR     SE12

SE7:    LOAD    RD, NBAD
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
        DB      ' BAD:',0
        LOAD    RD, NBAD        ; the first 16
        LDA     RD
        LBNZ    SE8
        LDN     RD
        SMI     17
        LBNF    SE9
SE8:    LDI     16
        LSKP
SE9:    LDN     RD
        PLO     RA
        LOAD    R9, BADL
SE10:   LDI     ' '
        SEP     R4
        DW      F_TYPE
        GHI     R9
        PHI     RD
        GLO     R9
        PLO     RD
        SEP     R4
        DW      LD32LE
        SEP     R4
        DW      PHEX7
        INC     R9
        INC     R9
        INC     R9
        INC     R9
        DEC     RA
        GLO     RA
        LBNZ    SE10
        LOAD    RD, NBAD+1
        LDN     RD
        SMI     17
        LBNF    SE11
        SEP     R4
        DW      PIN
        DB      ' ...',0
SE11:   SEP     R4
        DW      PCRLF
SE12:   LOAD    RD, NGL         ; read glitches
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        STR     R2
        GLO     RD
        OR
        LBZ     SE13
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' read glitch(es): a sector read wrong, then right when read again - not counted as bad.',0DH,0AH,0
SE13:   LOAD    RD, NRW
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RD
        GHI     RC
        PHI     RD
        STR     R2
        GLO     RD
        OR
        LBZ     SE14
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ' sector(s) had to be written back more than once (right in the end).',0DH,0AH,0
SE14:   LOAD    RD, CLOCK
        LDN     RD
        LBZ     SE15
        SEP     R4
        DW      PIN
        DB      'Clock: started at ',0
        LOAD    RD, M0
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      PHM
        SEP     R4
        DW      PIN
        DB      ', last read at ',0
        LOAD    RD, MLAST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      PHM
        SEP     R4
        DW      PCRLF
SE15:   SEP     R5

; ---- SECTOR: test CUR. DF = 1 only if the card stopped answering (no answer / no data request).
;      PHASE: 1 reading it, 2 writing pattern 1, 3 reading pattern 1 back, 4 writing pattern 2, 5 reading
;      pattern 2 back, 6 writing it back, 7 reading it back.
SECTOR: LDI     1
        SEP     R4
        DW      SETPH
        LOAD    RD, PBT         ; (PBT: the tries at saving it)
        LDI     3
        STR     RD
SV1:    LOAD    RF, SAVEB
        SEP     R4
        DW      RDCUR
        LBDF    BADRD
        LOAD    RD, MODE
        LDN     RD
        LBZ     SOK             ; a read scan: that is all
        LOAD    RD, SAVEB       ; the write test: read again - the copy kept must be right before anything is
        SEP     R4              ;  written (a glitch in it would be written back)
        DW      CHKR
        LBNF    SV2
        LOAD    RD, PBT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    SV1
        LBR     BADRD           ; never the same twice: nothing written
SV2:    SEP     R4              ; this sector's number in the first 4 bytes of both patterns
        DW      LDCUR
        LOAD    RD, WBUF
        SEP     R4
        DW      ST32LE
        LOAD    RD, WBUF2
        GLO     R7
        XRI     0FFH
        STR     RD
        INC     RD
        GHI     R7
        XRI     0FFH
        STR     RD
        INC     RD
        GLO     R8
        XRI     0FFH
        STR     RD
        INC     RD
        GHI     R8
        XRI     0FFH
        STR     RD
        LDI     2
        SEP     R4
        DW      SETPH
        LOAD    RF, WBUF
        SEP     R4
        DW      WRCUR
        LBDF    BADWR
        LDI     3
        SEP     R4
        DW      SETPH
        LOAD    RD, WBUF
        SEP     R4
        DW      CHKR            ; read back and compare
        LBDF    BADWR
        LDI     4               ; the inverse: every bit the other way
        SEP     R4
        DW      SETPH
        LOAD    RF, WBUF2
        SEP     R4
        DW      WRCUR
        LBDF    BADWR
        LDI     5
        SEP     R4
        DW      SETPH
        LOAD    RD, WBUF2
        SEP     R4
        DW      CHKR
        LBDF    BADWR
        LDI     6               ; written back as it was
        SEP     R4
        DW      SETPH
        SEP     R4
        DW      PUTBACK
        LBDF    BADBK
SOK:    LDI     0
        SHR
        SEP     R5
; a failed read of the sector as it was: nothing has been written
BADRD:  SEP     R4
        DW      BADLN
        SEP     R4
        DW      PCRLF
        LBR     BADEND
; a failure while testing: put the sector back, then say how that went
BADWR:  SEP     R4
        DW      BADLN
        SEP     R4
        DW      PUTBACK
        LBDF    BW1
        SEP     R4
        DW      PIN
        DB      '; put back as it was',0DH,0AH,0
        LBR     BADEND
BW1:    SEP     R4
        DW      PIN
        DB      '; COULD NOT BE PUT BACK',0DH,0AH,0
        LBR     BADEND
BADBK:  SEP     R4              ; putting it back failed
        DW      BADLN
        SEP     R4
        DW      PIN
        DB      ' - IT IS NOT AS IT WAS',0DH,0AH,0
BADEND: LOAD    RD, WHYV        ; no answer / no data request: the card has stopped
        LDN     RD
        XRI     0FFH
        LBZ     BE1
        LDN     RD
        XRI     0FEH
        LBZ     BE1
        LDI     0
        SHR
        SEP     R5
BE1:    LDI     1
        SHR
        SEP     R5
; PUTBACK: write SAVEB to CUR, read it back, compare. DF = 1: failed (PHASE says where).
; PUTBACK: write SAVEB to CUR and check it; up to 3 writes. DF = 1: failed every time (PHASE says where).
PUTBACK: LOAD   RD, PBT
        LDI     3
        STR     RD
PB1:    LDI     6
        SEP     R4
        DW      SETPH
        LOAD    RF, SAVEB
        SEP     R4
        DW      WRCUR
        LBDF    PB2
        LDI     7
        SEP     R4
        DW      SETPH
        LOAD    RD, SAVEB
        SEP     R4
        DW      CHKR
        LBNF    PB3
PB2:    LOAD    RD, PBT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    PB1
        LDI     1
        SHR
        SEP     R5
PB3:    LOAD    RD, PBT         ; right: written more than once?
        LDN     RD
        XRI     3
        LBZ     PB9
        LOAD    RD, NRW+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
PB9:    LDI     0
        SHR
        SEP     R5
; CHKR: read CUR into RBUF and compare with the 512 bytes at RD. Different: read it again, up to 3 reads in
;       all - right on a later read is a read glitch (counted, the first 8 shown), not a failure.
;       DF = 1: different every time (WHERE = the first difference, WHYV = 4), or the driver's failure.
CHKR:   LOAD    RF, EXP
        GHI     RD
        STR     RF
        INC     RF
        GLO     RD
        STR     RF
        LOAD    RF, TRIES
        LDI     3
        STR     RF
CK1:    LOAD    RF, RBUF
        SEP     R4
        DW      RDCUR
        LBDF    CK9
        LOAD    RF, EXP
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      FCMP
        LBNF    CK5
        LDN     RD              ; different: the byte wanted and the byte read
        PLO     RA
        LDN     RF
        PHI     RA
        LOAD    RF, TRIES       ; the first read: keep where
        LDN     RF
        XRI     3
        LBNZ    CK2
        LOAD    RF, WHERE
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        INC     RF
        GHI     RA
        STR     RF
CK2:    LOAD    RF, TRIES
        LDN     RF
        SMI     1
        STR     RF
        LBNZ    CK1
        LDI     4
        SEP     R4
        DW      SETWHY
        LDI     1
        SHR
CK9:    SEP     R5
CK5:    LOAD    RF, TRIES       ; the same: on the first read?
        LDN     RF
        XRI     3
        LBZ     CK8
        LOAD    RD, NGL         ; a read glitch: count it
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
        LBNZ    CK8             ; show the first 8
        GLO     RC
        SMI     9
        LBDF    CK8
        SEP     R4
        DW      PIN
        DB      0DH,'  read glitch, sector ',0
        SEP     R4
        DW      LDCUR
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      ' byte ',0
        LOAD    RF, WHERE
        LDA     RF
        PHI     RD
        LDA     RF
        PLO     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ': $',0
        LDA     RF
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ' read as $',0
        LDN     RF
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ', right when read again',1BH,'[K',0DH,0AH,0
        LOAD    RD, NGL+1
        LDN     RD
        XRI     8
        LBNZ    CK8
        SEP     R4
        DW      PIN
        DB      '  (more read glitches are counted, not shown)',0DH,0AH,0
CK8:    LDI     0
        SHR
        SEP     R5
; RDCUR / WRCUR: CUR <-> 512 bytes at RF. DF = 1: WHYV = the driver's D (FF no answer, FE no data, or the
;                card's error register).
RDCUR:  SEP     R4
        DW      LDCUR
        SEP     R4
        DW      FRD
        LBNF    RW9
        SEP     R4
        DW      SETWHY
        LDI     1
        SHR
RW9:    SEP     R5
WRCUR:  SEP     R4
        DW      LDCUR
        SEP     R4
        DW      FWR
        LBNF    RW9
        SEP     R4
        DW      SETWHY
        LDI     1
        SHR
        SEP     R5
LDCUR:  LOAD    RD, CUR
        LBR     LD32LE
LDLAST: LOAD    RD, SEND        ; the last sector = SEND - 1
        SEP     R4
        DW      LD32LE
        GLO     R7
        SMI     1
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
        SEP     R5
SETPH:  PLO     RE
        LOAD    RD, PHASE
        GLO     RE
        STR     RD
        SEP     R5
SETWHY: PLO     RE
        LOAD    RD, WHYV
        GLO     RE
        STR     RD
        SEP     R5

; ---- BADLN: "  BAD sector $x: <what was being done> - <why>"; the sector is listed and counted
BADLN:  SEP     R4
        DW      PIN
        DB      0DH,'  BAD sector ',0
        SEP     R4
        DW      LDCUR
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      ': ',0
        LOAD    RD, PHASE       ; what: from PHNAMES, 24 characters each
        LDN     RD
        SMI     1
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    RD, 24
        SEP     R4
        DW      MUL16
        GLO     R7
        ADI     LOW(PHNAMES)
        PLO     RF
        GHI     R7
        ADCI    HIGH(PHNAMES)
        PHI     RF
        SEP     R4
        DW      F_MSG
        SEP     R4
        DW      PIN
        DB      ' - ',0
        LOAD    RD, WHYV
        LDN     RD
        XRI     4
        LBNZ    BL1
        SEP     R4              ; read back different: where, and the bytes
        DW      PIN
        DB      'read back different at byte ',0
        LOAD    RF, WHERE
        LDA     RF
        PHI     RD
        LDA     RF
        PLO     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ': $',0
        LDA     RF
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ' -> $',0
        LDN     RF
        SEP     R4
        DW      PHEX2
        LBR     BL2
BL1:    LDN     RD              ; (the driver's code; WHY ends the line - take it back)
        SEP     R4
        DW      WHYS
BL2:    LOAD    RD, NBAD        ; count it; list the first 16
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SMI     16
        GHI     RC
        SMBI    0
        LBDF    BL3
        SEP     R4
        DW      LDCUR
        GLO     RC              ; BADL + 4 x NBAD
        SHL
        SHL
        ADI     LOW(BADL)
        PLO     RD
        LDI     HIGH(BADL)
        ADCI    0
        PHI     RD
        GLO     R7
        STR     RD
        INC     RD
        GHI     R7
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        INC     RD
        GHI     R8
        STR     RD
BL3:    INC     RC
        LOAD    RD, NBAD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
; WHYS: D (the driver's failure) in words, no new line
WHYS:   PLO     RB
        XRI     0FFH
        LBNZ    WS1
        SEP     R4
        DW      PIN
        DB      'no answer',0
        SEP     R5
WS1:    GLO     RB
        XRI     0FEH
        LBNZ    WS2
        SEP     R4
        DW      PIN
        DB      'the card never asked for the data',0
        SEP     R5
WS2:    SEP     R4
        DW      PIN
        DB      'card error $',0
        GLO     RB
        SEP     R4
        DW      PHEX2
        SEP     R5
PHNAMES: DB     'reading it',0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DB      'writing pattern 1',0,0,0,0,0,0,0
        DB      'reading pattern 1 back',0,0
        DB      'writing pattern 2',0,0,0,0,0,0,0
        DB      'reading pattern 2 back',0,0
        DB      'writing it back',0,0,0,0,0,0,0,0,0
        DB      'reading it back',0,0,0,0,0,0,0,0,0

; ---- DONEN: R8:R7 = CUR - SFIRST
DONEN:  LOAD    RD, CUR
        SEP     R4
        DW      LD32LE
        LOAD    RD, SFIRST
        LBR     SUB32LE
; SUB32LE: R8:R7 -= the 4 little-endian bytes at RD
SUB32LE: SEX    RD
        GLO     R7
        SM
        PLO     R7
        IRX
        GHI     R7
        SMB
        PHI     R7
        IRX
        GLO     R8
        SMB
        PLO     R8
        IRX
        GHI     R8
        SMB
        PHI     R8
        SEX     R2
        SEP     R5

; ---- STATUS: "\r  sector $x  nn%  h:mm gone  ~h:mm left  n bad "
STATUS: SEP     R4
        DW      PIN
        DB      0DH,'  sector ',0
        SEP     R4
        DW      LDCUR
        SEP     R4
        DW      PHEX7
        SEP     R4              ; done / total, both shifted until the total is under 656
        DW      DONEN
        LOAD    RD, DSV
        SEP     R4
        DW      ST32LE
        LOAD    RD, SEND
        SEP     R4
        DW      LD32LE
        LOAD    RD, SFIRST
        SEP     R4
        DW      SUB32LE         ; R8:R7 = total
ST1:    GHI     R8
        LBNZ    ST2
        GLO     R8
        LBNZ    ST2
        GLO     R7
        SMI     LOW(656)
        GHI     R7
        SMBI    HIGH(656)
        LBNF    ST3
ST2:    SEP     R4
        DW      SHR32
        GHI     R7              ; (the total in R8:R7; done shifted alongside, in DSV)
        STXD
        GLO     R7
        STXD
        GHI     R8
        STXD
        GLO     R8
        STXD
        LOAD    RD, DSV
        SEP     R4
        DW      LD32LE
        SEP     R4
        DW      SHR32
        LOAD    RD, DSV
        SEP     R4
        DW      ST32LE
        IRX
        LDXA
        PLO     R8
        LDXA
        PHI     R8
        LDXA
        PLO     R7
        LDX
        PHI     R7
        LBR     ST1
ST3:    LOAD    RD, TS          ; TS = the total, DS = done (16 bits now)
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        LOAD    RD, DSV
        LDA     RD
        PLO     RC
        LDN     RD
        PHI     RC              ; RC = done
        LOAD    RD, DS
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, 100         ; % = done x 100 / total
        SEP     R4
        DW      MUL16
        LOAD    RF, TS
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      DIV32
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        GLO     R7              ; right-aligned in 3
        SMI     100
        LBDF    ST4
        LDI     ' '
        SEP     R4
        DW      F_TYPE
        GLO     R7
        SMI     10
        LBDF    ST4
        LDI     ' '
        SEP     R4
        DW      F_TYPE
ST4:    GHI     R7
        PHI     RD
        GLO     R7
        PLO     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      '%  ',0
        LOAD    RD, CLOCK
        LDN     RD
        LBZ     ST9
        SEP     R4              ; EM = minutes since the start
        DW      MINDAY
        LBDF    ST9
        LOAD    RD, MLAST+1     ; earlier than the last time looked? by more than 12 hours: midnight passed;
        SEX     RD              ;  by less: a misread - keep the last time
        GLO     RC
        SM
        PLO     RF
        DEC     RD
        GHI     RC
        SMB
        PHI     RF              ; RF = now - MLAST
        SEX     R2
        LBDF    ST6
        GLO     RF
        ADI     LOW(720)
        GHI     RF
        ADCI    HIGH(720)
        LBNF    ST5
        LOAD    RD, MLAST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LBR     ST6
ST5:    LOAD    RD, DAYS
        LDN     RD
        ADI     1
        STR     RD
ST6:    LOAD    RD, MLAST
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, DAYS        ; EM = DAYS x 1440 + now - M0
        LDN     RD
        PLO     RA
ST7:    GLO     RA
        LBZ     ST8
        GLO     RC
        ADI     LOW(1440)
        PLO     RC
        GHI     RC
        ADCI    HIGH(1440)
        PHI     RC
        DEC     RA
        LBR     ST7
ST8:    LOAD    RD, M0+1
        SEX     RD
        GLO     RC
        SM
        PLO     RC
        DEC     RD
        GHI     RC
        SMB
        PHI     RC
        SEX     R2
        LOAD    RD, EM
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      PHM
        SEP     R4
        DW      PIN
        DB      ' gone  ',0
        LOAD    RF, DS          ; time left = EM x (TS - DS) / DS
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        GHI     RD
        LBNZ    STL1
        GLO     RD
        LBZ     STL9            ; nothing done yet
STL1:   LOAD    RF, TS+1
        SEX     RF
        GLO     RD
        SD
        PLO     RC
        DEC     RF
        GHI     RD
        SDB
        PHI     RC              ; RC = TS - DS
        SEX     R2
        LOAD    RF, EM
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      MUL16           ; R8:R7 = (TS - DS) x EM
        LOAD    RF, DS
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      DIV32
        GHI     R7
        PHI     RC
        GLO     R7
        PLO     RC
        LDI     '~'
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      PHM
        SEP     R4
        DW      PIN
        DB      ' left  ',0
        LBR     ST9
STL9:   SEP     R4
        DW      PIN
        DB      '         left  ',0
ST9:    LOAD    RD, NBAD
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
        DB      ' bad',1BH,'[K',0      ; (and clear the rest of the line)
        SEP     R5

; ---- PHM: RC minutes as h:mm (RC is used up)
PHM:    LOAD    R9, 0           ; R9 = hours, RC = what is left, by subtracting 60s
PH1:    GLO     RC
        SMI     60
        STR     R2
        GHI     RC
        SMBI    0
        LBNF    PH2
        PHI     RC
        LDN     R2
        PLO     RC
        INC     R9
        LBR     PH1
PH2:    GHI     R9
        PHI     RD
        GLO     R9
        PLO     RD
        SEP     R4
        DW      PDEC
        LDI     ':'
        SEP     R4
        DW      F_TYPE
        GLO     RC
        SEP     R4
        DW      P2D
        SEP     R5

; ---- FRD / FWR: CUR's sector (R8:R7) <-> 512 bytes at RF, as fast as the 1802 goes: X = RF, INP / OUT straight
;      to and from the buffer, 8 to a turn. (LTOS's ide.asm still has the pause and the stack slot that Craig's
;      failing 74HC245 needed; the 245 is replaced.) DF = 1: D = the card's error, $FF no answer, $FE no data.
        ORG     ($ + 0FFH) AND 0FF00H   ; FRD, FWR, FCMP on one page: their loops use short branches (2 cycles,
                                        ;  not 3) - build.py checks they fit
FRD:    GLO     RC              ; (the same frame as ide.asm's IDERD: IDEX4 restores RF, RC)
        STXD
        GHI     RC
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      IDEWAIT
        LBDF    IDEX4
        SEP     R4
        DW      IDELBA
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     20H             ; READ SECTORS
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R4
        DW      IDEDRQ
        LBDF    IDEX4
        LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     64
        PLO     RC
        SEX     RF
FR1:    INP     DATPORT
        INC     RF
        INP     DATPORT
        INC     RF
        INP     DATPORT
        INC     RF
        INP     DATPORT
        INC     RF
        INP     DATPORT
        INC     RF
        INP     DATPORT
        INC     RF
        INP     DATPORT
        INC     RF
        INP     DATPORT
        INC     RF
        DEC     RC
        GLO     RC
        BNZ     FR1
        SEX     R2
        LDI     0
        SHR
        LBR     IDEX4
FWR:    GLO     RC
        STXD
        GHI     RC
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      IDEWAIT
        LBDF    IDEX4
        SEP     R4
        DW      IDELBA
        LDI     IDE_CMD
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     30H             ; WRITE SECTORS
        STR     R2
        OUT     DATPORT
        DEC     R2
        SEP     R4
        DW      IDEDRQ
        LBDF    IDEX4
        LDI     IDE_DATA
        STR     R2
        OUT     SELPORT
        DEC     R2
        LDI     0               ; 256 x 2 bytes, each from the stack slot (an OUT straight from some RAM
        PLO     RC              ;  addresses slips on Craig's Elf2K - see ide.asm)
FW1:    LDA     RF
        STR     R2
        OUT     DATPORT
        DEC     R2
        LDA     RF
        STR     R2
        OUT     DATPORT
        DEC     R2
        DEC     RC
        GLO     RC
        BNZ     FW1
        SEP     R4
        DW      IDEDONE         ; written; its error, if any
        LBR     IDEX4
; ---- FCMP: RBUF against the 512 bytes at RD (CMPRB's contract): DF = 0 the same; DF = 1, RC = where, RD / RF
;      on the two bytes. X = RD, 8 to a turn.
FCMP:   LOAD    RF, RBUF
        LDI     64
        PLO     RC
        SEX     RD
FC1:    LDA     RF
        XOR
        BNZ     FC2
        IRX
        LDA     RF
        XOR
        BNZ     FC2
        IRX
        LDA     RF
        XOR
        BNZ     FC2
        IRX
        LDA     RF
        XOR
        BNZ     FC2
        IRX
        LDA     RF
        XOR
        BNZ     FC2
        IRX
        LDA     RF
        XOR
        BNZ     FC2
        IRX
        LDA     RF
        XOR
        BNZ     FC2
        IRX
        LDA     RF
        XOR
        BNZ     FC2
        IRX
        DEC     RC
        GLO     RC
        BNZ     FC1
        SEX     R2
        LDI     0
        SHR
        SEP     R5
FC2:    SEX     R2
        DEC     RF              ; back on the byte read; RD is on the byte wanted
        GLO     RF
        SMI     LOW(RBUF)
        PLO     RC
        GHI     RF
        SMBI    HIGH(RBUF)
        PHI     RC
        LDI     1
        SHR
        SEP     R5
FPEND:

        INCL    "cfcom.asm"
        INCL    "ide.asm"
        INCL    "cons.asm"
        INCL    "nums.asm"

MODE:   DS      1               ; 0 read scan, 1 write test
SFIRST: DS      4               ; the first sector (little-endian, like CUR and SEND)
SEND:   DS      4               ; one past the last
CUR:    DS      4               ; the sector in hand
NBAD:   DS      2               ; NBAD, STOPPED, DAYS, TICK: zeroed together (6 bytes)
STOPPED: DS     1
DAYS:   DS      1
TICK:   DS      1
        DS      1
NGL:    DS      2               ; read glitches
NRW:    DS      2               ; sectors that needed writing back more than once
CLOCK:  DS      1               ; 1: the clock answers
M0:     DS      2               ; M0, MLAST: in this order
MLAST:  DS      2
EM:     DS      2               ; minutes since the start
DSV:    DS      4
TS:     DS      2
DS:     DS      2
PHASE:  DS      1
WHYV:   DS      1
WHERE:  DS      4               ; the byte (2), wanted, read
EXP:    DS      2               ; CHKR: the bytes wanted, reads left
TRIES:  DS      1
PBT:    DS      1               ; PUTBACK: writes left
PEND:
        END
