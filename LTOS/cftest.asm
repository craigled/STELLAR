; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; cftest.asm - CFTEST: read and write one sector of the CF card, and put it back (native 1802; was the Stellar C
; CF-Test). CALL 3000 from the monitor - STELLAR, if it is in RAM, is not touched - or RUN CFTEST.PRG in LTOS.
;
; It saves the sector, reads it again (two reads must agree), writes five patterns and reads each back, then
; writes the saved bytes back and checks them. Sector 0 (the boot record) is refused. Every transfer goes
; through LTOS's CF driver: the stack slot and a pause after each byte (the Elf2K's own rules, CFDIAG).

        CPU     1802
        INCL    "ltos.inc"

SAVEB   EQU     6000H           ; what was in the sector
WBUF    EQU     6200H           ; the pattern written
RBUF    EQU     6400H           ; what was read back

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
        DB      0DH,0AH,'CFTEST - read and write one sector of the CF card, and put it back',0DH,0AH,0
        SEP     R4
        DW      CARD
        LBDF    BYE
AGAIN:  SEP     R4
        DW      TEST1
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'R = test again, any other key = quit: ',0
        SEP     R4
        DW      F_READ
        ANI     0DFH
        XRI     'R'
        LBNZ    DONE
        SEP     R4
        DW      PCRLF
        LBR     AGAIN
DONE:   SEP     R4
        DW      PIN
        DB      0DH,0AH,'CFTEST finished.',0DH,0AH,0
        LBR     BYE

; ---- TEST1: choose a sector, then the test
TEST1:  SEP     R4              ; the default: the last sector, N - 1
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
        LOAD    RD, DEFSEC
        SEP     R4
        DW      ST32LE
PICK:   SEP     R4
        DW      PIN
        DB      0DH,0AH,'Sector to test, in hex (Enter = the last one, ',0
        LOAD    RD, DEFSEC
        SEP     R4
        DW      LD32LE
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      '; Q = quit): ',0
        SEP     R4
        DW      GETHEX
        GLO     RB
        LBZ     PK0             ; Enter: the default
        XRI     2
        LBZ     DONE            ; Q
        XRI     1               ; (2 xor 3: now zero if it was 3)
        LBNZ    PK1
        SEP     R4
        DW      PIN
        DB      '  - not a sector number',0
        LBR     PICK
PK0:    LOAD    RD, DEFSEC
        SEP     R4
        DW      LD32LE
PK1:    GHI     R8              ; not sector 0
        STR     R2
        GLO     R8
        OR
        STR     R2
        GHI     R7
        OR
        STR     R2
        GLO     R7
        OR
        LBNZ    PK2
        SEP     R4
        DW      PIN
        DB      '  - not sector 0: it holds the card',39,'s boot record',0
        LBR     PICK
PK2:    LOAD    RD, NSEC        ; on the card?
        SEP     R4
        DW      CMP32
        LBNF    PK3
        SEP     R4
        DW      PIN
        DB      '  - the card has only ',0
        SEP     R4
        DW      LDNSEC
        SEP     R4
        DW      PHEX7
        SEP     R4
        DW      PIN
        DB      ' sectors',0
        LBR     PICK
PK3:    LOAD    RD, LSEC
        SEP     R4
        DW      ST32LE
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'This WRITES sector ',0
        SEP     R4
        DW      PLSEC
        SEP     R4
        DW      PIN
        DB      ' five times, then puts back what was there.',0DH,0AH
        DB      'Press Y to go on, any other key to stop: ',0
        SEP     R4
        DW      F_READ
        PLO     RB
        SEP     R4
        DW      PCRLF
        GLO     RB
        ANI     0DFH
        XRI     'Y'
        LBZ     GO
        SEP     R5

GO:     LOAD    RD, COUNTS      ; fails, writes, reads
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        SEP     R4
        DW      PIN
        DB      0DH,0AH,'Reading what is there:      ',0
        LOAD    RF, SAVEB
        SEP     R4
        DW      RDSEC
        LBDF    RFAIL0
        SEP     R4
        DW      PIN
        DB      'OK',0DH,0AH,' ',0
        LOAD    RF, SAVEB       ; its first 16 bytes
        LDI     16
        PLO     RA
G1:     LDI     ' '
        SEP     R4
        DW      F_TYPE
        LDA     RF
        SEP     R4
        DW      PHEX2
        DEC     RA
        GLO     RA
        LBNZ    G1
        SEP     R4
        DW      PIN
        DB      ' ...',0DH,0AH,'Reading it again:           ',0
        LOAD    RF, RBUF
        SEP     R4
        DW      RDSEC
        LBDF    RFAIL0
        LOAD    RD, SAVEB
        SEP     R4
        DW      CMPRB
        LBDF    G2
        SEP     R4
        DW      PIN
        DB      'the same',0DH,0AH,0
        LBR     G3
G2:     SEP     R4
        DW      PIN
        DB      '  (two reads disagree - the test stops)',0DH,0AH,0
        LBR     FAILED1
RFAIL0: SEP     R4              ; the first reads failed: nothing has been written
        DW      PIN
        DB      'FAILED - ',0
        SEP     R4
        DW      WHY
        SEP     R5

G3:     LDI     0
        PLO     R9              ; R9.0 = the pattern
G4:     SEP     R4
        DW      PIN
        DB      'Pattern ',0
        GLO     R9
        ADI     '1'
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      PIN
        DB      ': ',0
        GLO     R9              ; its name: 18 characters each in PNAMES
        PLO     RC
        LDI     0
        PHI     RC
        LDI     18
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      MUL16           ; (R7 = 18 x pattern)
        GLO     R7
        ADI     LOW(PNAMES)
        PLO     RF
        GHI     R7
        ADCI    HIGH(PNAMES)
        PHI     RF
        SEP     R4
        DW      F_MSG
        SEP     R4
        DW      FILL            ; WBUF = pattern R9.0
        LOAD    RF, WBUF
        SEP     R4
        DW      WRSEC
        LBDF    G6
        SEP     R4
        DW      PIN
        DB      'written, ',0
        LOAD    RF, RBUF
        SEP     R4
        DW      RDSEC
        LBDF    G6
        SEP     R4
        DW      PIN
        DB      'read, ',0
        LOAD    RD, WBUF
        SEP     R4
        DW      CMPRB
        LBDF    G5
        SEP     R4
        DW      PIN
        DB      'OK',0DH,0AH,0
        LBR     G7
G5:     SEP     R4
        DW      MISM
        LBR     G7
G6:     SEP     R4
        DW      PIN
        DB      'FAILED - ',0
        SEP     R4
        DW      WHY
        SEP     R4
        DW      FAILED
        LBR     RESTORE         ; stop the patterns - and put the sector back
G7:     INC     R9
        GLO     R9
        XRI     5
        LBNZ    G4

RESTORE: SEP    R4
        DW      PIN
        DB      'Putting the sector back:    ',0
        LOAD    RF, SAVEB
        SEP     R4
        DW      WRSEC
        LBDF    RS2
        LOAD    RF, RBUF
        SEP     R4
        DW      RDSEC
        LBDF    RS2
        LOAD    RD, SAVEB
        SEP     R4
        DW      CMPRB
        LBDF    RS1
        SEP     R4
        DW      PIN
        DB      'written, read back, the same as before',0DH,0AH,0
        LBR     SUMM
RS1:    SEP     R4
        DW      MISM
        LBR     SUMM
RS2:    SEP     R4
        DW      PIN
        DB      'FAILED - ',0
        SEP     R4
        DW      WHY
        SEP     R4
        DW      FAILED
SUMM:   SEP     R4
        DW      PCRLF
        LOAD    RD, COUNTS+1    ; "n writes, m reads of sector $x: ALL PASSED"
        LDN     RD
        SEP     R4
        DW      PBYTE
        SEP     R4
        DW      PIN
        DB      ' writes, ',0
        LOAD    RD, COUNTS+2
        LDN     RD
        SEP     R4
        DW      PBYTE
        SEP     R4
        DW      PIN
        DB      ' reads of sector ',0
        SEP     R4
        DW      PLSEC
        SEP     R4
        DW      PIN
        DB      ': ',0
        LOAD    RD, COUNTS
        LDN     RD
        LBZ     SM1
        SEP     R4
        DW      PBYTE
        SEP     R4
        DW      PIN
        DB      ' FAILED',0DH,0AH,0
        SEP     R5
SM1:    SEP     R4
        DW      PIN
        DB      'ALL PASSED',0DH,0AH,0
        SEP     R5
FAILED1: SEP    R4
        DW      FAILED
        LBR     SUMM

; ---- RDSEC / WRSEC: the sector LSEC <-> 512 bytes at RF; counted. DF = 1, D = why: as IDERD / IDEWR.
RDSEC:  LOAD    RD, COUNTS+2
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      LDLSEC
        SEP     R4
        DW      IDERD
        SEP     R5
WRSEC:  LOAD    RD, COUNTS+1
        LDN     RD
        ADI     1
        STR     RD
        SEP     R4
        DW      LDLSEC
        SEP     R4
        DW      IDEWR
        SEP     R5
LDLSEC: LOAD    RD, LSEC
        LBR     LD32LE          ; (in cfcom.asm)
PLSEC:  SEP     R4
        DW      LDLSEC
        SEP     R4
        DW      PHEX7
        SEP     R5

; MISM: "MISMATCH at byte n: wrote $xx, read $yy" (after CMPRB), counted
MISM:   SEP     R4
        DW      PIN
        DB      'MISMATCH at byte ',0
        GHI     RC              ; (PDEC takes RD: keep the pointers)
        PHI     RA
        GLO     RC
        PLO     RA
        GHI     RD
        PHI     R8
        GLO     RD
        PLO     R8              ; R8 -> the byte written (R9.0 is the pattern number)
        GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      PIN
        DB      ': wrote $',0
        LDN     R8
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PIN
        DB      ', read $',0
        LDN     RF
        SEP     R4
        DW      PHEX2
        SEP     R4
        DW      PCRLF
FAILED: LOAD    RD, COUNTS
        LDN     RD
        ADI     1
        STR     RD
        SEP     R5
; PBYTE: D in decimal
PBYTE:  PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      PDEC
        SEP     R5

; ---- FILL: WBUF = pattern R9.0: 0 all $00, 1 all $FF, 2 $55 / $AA, 3 the byte number (low xor high),
;      4 an 8-bit Galois LFSR (taps $B8) from 1
FILL:   LOAD    RF, WBUF
        LOAD    RC, 0           ; the byte number
        LDI     1
        PHI     RA              ; RA.1 = the LFSR
FI1:    GLO     R9
        LBNZ    FI2
        LDI     0
        LBR     FIP
FI2:    XRI     1
        LBNZ    FI3
        LDI     0FFH
        LBR     FIP
FI3:    GLO     R9
        XRI     2
        LBNZ    FI4
        GLO     RC
        ANI     1
        LBZ     FI3A
        LDI     0AAH
        LBR     FIP
FI3A:   LDI     55H
        LBR     FIP
FI4:    GLO     R9
        XRI     3
        LBNZ    FI5
        GHI     RC
        STR     R2
        GLO     RC
        XOR
        LBR     FIP
FI5:    GHI     RA
        SHR
        LBNF    FI6
        XRI     0B8H
FI6:    PHI     RA
FIP:    STR     RF
        INC     RF
        INC     RC
        GHI     RC
        XRI     2
        LBNZ    FI1
        SEP     R5
PNAMES: DB      'all $00          ',0
        DB      'all $FF          ',0
        DB      '$55 / $AA        ',0
        DB      'the byte number  ',0
        DB      'pseudo-random    ',0

        INCL    "cfcom.asm"
        INCL    "ide.asm"
        INCL    "cons.asm"
        INCL    "nums.asm"

DEFSEC: DS      4
LSEC:   DS      4
COUNTS: DS      3               ; fails, writes, reads
PEND:
        END
