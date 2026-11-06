; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; webbios.asm - a stand-in for the Elf2K ROM ($8000-$FFFF), so LTOS can run on the web without Spare Time
; Gizmos' ROM (theirs, not ours to publish). Our own code: only the BIOS calls LTOS and its programs use,
; at the ROM's addresses, with the ROM's register rules (each checked against the real ROM in the simulator,
; verify_webbios.py):
;   F_BOOT     $FF00  SCRT set up, the stack at $00F0, LBA 0 read to $0100, then $0106 with P = R3
;   F_TYPE     $FF03  D -> the UART (D and RE.0 = the character after)
;   F_READ     $FF06  the UART -> D and RE.0 (waits); echoed if RE.1 bit 0 is set
;   F_MSG      $FF09  the zero-ended string at RF -> the UART (RF past its 0, D = 0)
;   F_IDEREAD  $FF3C  the sector R8:R7 (R8.1 = $E0 + LBA 24-27) -> RF (RF past it); DF = 1: it failed
;   F_INITCALL $FF3F  R4 / R5 = SCRT's call / return, then on at R6 (as R3)
;   F_INPUTL   $FF69  a line -> RF, at most RC characters; Backspace; Enter: DF = 0; Ctrl-C: DF = 1
; $8003 (the ROM's monitor) says there is none here and boots LTOS again; RUN's ending is there for STELLAR.PRG.
; Any other call stops with a message.
; The UART: port 2 selects ($15 the line status, $10 the data), port 3 reads / writes it. The CF card: port 2
; selects an IDE register (0-7), port 3 its data.

        CPU     1802

R0      EQU     0
R1      EQU     1
R2      EQU     2
R3      EQU     3
R4      EQU     4
R5      EQU     5
R6      EQU     6
R7      EQU     7
R8      EQU     8
R9      EQU     9
RA      EQU     10
RB      EQU     11
RC      EQU     12
RD      EQU     13
RE      EQU     14
RF      EQU     15

        ORG     8000H
        LBR     COLD            ; $8000: power on
        LBR     MONIT           ; $8003: the ROM's monitor (MON.PRG and the tests' way out)

COLD:   LDI     0
        PHI     R2
        LDI     0F0H
        PLO     R2
        SEX     R2
        LDI     1
        PHI     RE              ; RE.1 = 1: the UART, echo on (as the ROM's monitor leaves it)
        LBR     BOOT

; ---------------------------------------------------------------- SCRT (RCA's standard call and return)
        SEP     R3              ; (the call's last step: on in the subroutine)
SCALL:  PLO     RE              ; R4: SEP R4 / DW addr - R6 pushed, R6 = the return, R3 = addr; D kept
        GHI     R6
        SEX     R2
        STXD
        GLO     R6
        STXD
        GHI     R3
        PHI     R6
        GLO     R3
        PLO     R6
        LDA     R6
        PHI     R3
        LDA     R6
        PLO     R3
        GLO     RE
        BR      SCALL-1

        SEP     R3              ; (the return's last step: back in the caller)
SRET:   PLO     RE              ; R5: SEP R5 - R3 = R6, R6 popped; D kept
        GHI     R6
        PHI     R3
        GLO     R6
        PLO     R3
        SEX     R2
        IRX
        LDXA
        PLO     R6
        LDX
        PHI     R6
        GLO     RE
        BR      SRET-1

INITC:  LDI     HIGH(SRET)      ; F_INITCALL: as the ROM's - R5 and R4 set, then SEP R5 with the stack 2 up
        PHI     R5              ;  (the return pops R6 and goes on at the old R6)
        LDI     LOW(SRET)
        PLO     R5
        LDI     HIGH(SCALL)
        PHI     R4
        LDI     LOW(SCALL)
        PLO     R4
        INC     R2
        INC     R2
        SEP     R5

; ---------------------------------------------------------------- the console
TYPE:   PLO     RE              ; F_TYPE: D -> the UART
TYPE2:  STXD                    ; (F_READ's echo comes in here)
TY1:    LDI     15H
        STR     R2
        OUT     2
        DEC     R2
        INP     3
        ANI     20H
        BZ      TY1             ; the last byte still going
        LDI     10H
        STR     R2
        OUT     2
        LDX                     ; the character, back from the stack
        OUT     3
        DEC     R2
        SEP     R5

READ:   LDI     15H             ; F_READ: the UART -> D (waits)
        STR     R2
        OUT     2
        DEC     R2
RD1:    INP     3
        ANI     01H
        BZ      RD1
        LDI     10H
        STR     R2
        OUT     2
        DEC     R2
        INP     3
        PLO     RE
        GHI     RE
        SHR
        GLO     RE
        BDF     TYPE2           ; RE.1 bit 0: echo it
        SEP     R5

MSG:    LDA     RF              ; F_MSG: the string at RF
        BZ      MSGX
        SEP     R4
        DW      TYPE
        BR      MSG
MSGX:   SEP     R5

INLINE: LDA     R6              ; SEP R4 / DW INLINE / DB 'text',0: the text after the call
        BZ      MSGX
        SEP     R4
        DW      TYPE
        BR      INLINE

INPUTL: GLO     RA              ; F_INPUTL: a line into RF, at most RC characters; RA.0 counts them
        STXD
        GHI     RA
        STXD
        LDI     0
        PLO     RA
IL1:    SEP     R4
        DW      READ            ; (echoed, if RE.1 says so)
        PLO     RE
        SMI     03H
        BZ      ILC             ; Ctrl-C
        SMI     05H
        BZ      ILB             ; Backspace
        SMI     05H
        BZ      ILE             ; Enter
        GLO     RC
        BNZ     IL2
        GHI     RC
        BNZ     IL2
        LDI     08H             ; full: the echo taken back
        SEP     R4
        DW      TYPE
        BR      ILX
IL2:    GLO     RE
        STR     RF
        INC     RF
        INC     RA
        DEC     RC
        BR      IL1
ILB:    GLO     RA
        BZ      IL1             ; nothing to take back
        DEC     RA
        DEC     RF
        INC     RC
ILX:    SEP     R4
        DW      INLINE
        DB      ' ',08H,0
        BR      IL1
ILE:    LDI     0
        SHR                     ; DF = 0
ILZ:    STR     RF              ; the line ends with a 0
        IRX
        LDXA
        PHI     RA
        LDX
        PLO     RA
        SEP     R5
ILC:    SMI     0               ; DF = 1 (D is 0)
        LDI     0
        BR      ILZ

; ---------------------------------------------------------------- the CF card
IDESEL: STR     R2              ; select IDE register D
        OUT     2
        DEC     R2
        SEP     R5
IDEW:   LDI     7               ; wait while the card is busy; D = its status
        SEP     R4
        DW      IDESEL
IW1:    INP     3
        ANI     80H
        BNZ     IW1
        INP     3
        SEP     R5

IDERD:  GLO     RC              ; F_IDEREAD: the sector R8:R7 -> RF
        STXD
        GHI     RC
        STXD
        SEP     R4
        DW      IDEW
        LDI     1               ; 8-bit transfers (feature $01)
        SEP     R4
        DW      IDESEL
        LDI     1
        STR     R2
        OUT     3
        DEC     R2
        LDI     7
        SEP     R4
        DW      IDESEL
        LDI     0EFH
        STR     R2
        OUT     3
        DEC     R2
        SEP     R4
        DW      IDEW
        LDI     2               ; one sector, at LBA R8:R7
        SEP     R4
        DW      IDESEL
        LDI     1
        STR     R2
        OUT     3
        DEC     R2
        LDI     3
        SEP     R4
        DW      IDESEL
        GLO     R7
        STR     R2
        OUT     3
        DEC     R2
        LDI     4
        SEP     R4
        DW      IDESEL
        GHI     R7
        STR     R2
        OUT     3
        DEC     R2
        LDI     5
        SEP     R4
        DW      IDESEL
        GLO     R8
        STR     R2
        OUT     3
        DEC     R2
        LDI     6
        SEP     R4
        DW      IDESEL
        GHI     R8
        STR     R2
        OUT     3
        DEC     R2
        LDI     7               ; READ SECTOR
        SEP     R4
        DW      IDESEL
        LDI     20H
        STR     R2
        OUT     3
        DEC     R2
        SEP     R4
        DW      IDEW
        ANI     01H
        BNZ     IDEF            ; an error
        LDI     0
        SEP     R4
        DW      IDESEL
        LDI     2
        PHI     RC
        LDI     0
        PLO     RC
        SEX     RF
IR1:    INP     3               ; 512 bytes -> RF
        INC     RF
        DEC     RC
        GLO     RC
        BNZ     IR1
        GHI     RC
        BNZ     IR1
        SEX     R2
        ADI     0               ; DF = 0
        BR      IDEX
IDEF:   SMI     0               ; DF = 1
IDEX:   IRX
        LDXA
        PHI     RC
        LDX
        PLO     RC
        LDI     0
        SEP     R5

; ---------------------------------------------------------------- boot, and no monitor
BOOT:   LDI     0               ; F_BOOT
        PHI     R2
        LDI     0F0H
        PLO     R2
        SEX     R2
        LDI     HIGH(BOOT2)
        PHI     R6
        LDI     LOW(BOOT2)
        PLO     R6
        LBR     INITC
BOOT2:  LDI     0
        PLO     R7
        PHI     R7
        PLO     R8
        PLO     RF
        LDI     0E0H
        PHI     R8
        LDI     01H
        PHI     RF              ; LBA 0 -> $0100
        SEP     R4
        DW      IDERD
        LBDF    NOCARD
        LBR     0106H           ; the boot sector, P = R3

NOCARD: SEP     R4
        DW      INLINE
        DB      0DH,0AH,'No card to boot from.',0DH,0AH,0
        LBR     MONIT2

UNKN:   LDI     0               ; a BIOS call this stand-in does not have
        PHI     R2
        LDI     0F0H
        PLO     R2
        SEX     R2
        LDI     HIGH(UNK2)
        PHI     R6
        LDI     LOW(UNK2)
        PLO     R6
        LBR     INITC
UNK2:   SEP     R4
        DW      INLINE
        DB      0DH,0AH,'That needs the Elf2K ROM, which the web version does not have.',0DH,0AH,0
        LBR     MONIT2

MONIT:  LDI     0               ; $8003: the ROM's monitor - none here
        PHI     R2
        LDI     0F0H
        PLO     R2
        SEX     R2
        LDI     HIGH(MONIT2)
        PHI     R6
        LDI     LOW(MONIT2)
        PLO     R6
        LBR     INITC
MONIT2: SEP     R4
        DW      INLINE
        DB      0DH,0AH,'(The Elf2K ROM monitor is not part of the web version.)',0DH,0AH
        DB      'Press a key to start LTOS again.',0DH,0AH,0
        GHI     RE
        ANI     0FEH
        PHI     RE              ; no echo for this key
        SEP     R4
        DW      READ
        GHI     RE
        ORI     01H
        PHI     RE
        LBR     BOOT

; ---------------------------------------------------------------- RUN's ending, for STELLAR.PRG
; STELLAR.PRG finds the monitor's breakpoint entry by looking in the ROM for how the monitor's RUN ends:
; LDI hi / PHI R1 / LDI lo / PLO R1 / SEX R0 / SEP R0. Here it is: a STELLAR program that ends with R1 still
; at it (no BACK) comes to BRK, which boots LTOS again.
MRUN:   LDI     HIGH(BRK)
        PHI     R1
        LDI     LOW(BRK)
        PLO     R1
        SEX     R0
        SEP     R0
BRK:    LBR     MONIT

; ---------------------------------------------------------------- the ROM's call table
        ORG     0FF00H
        LBR     BOOT            ; FF00 F_BOOT
        LBR     TYPE            ; FF03 F_TYPE
        LBR     READ            ; FF06 F_READ
        LBR     MSG             ; FF09 F_MSG
        LBR     UNKN            ; FF0C
        LBR     UNKN            ; FF0F
        LBR     UNKN            ; FF12
        LBR     UNKN            ; FF15
        LBR     UNKN            ; FF18
        LBR     UNKN            ; FF1B
        LBR     UNKN            ; FF1E
        LBR     UNKN            ; FF21
        LBR     UNKN            ; FF24
        LBR     UNKN            ; FF27
        LBR     UNKN            ; FF2A
        LBR     UNKN            ; FF2D
        LBR     UNKN            ; FF30
        LBR     UNKN            ; FF33
        LBR     UNKN            ; FF36
        LBR     UNKN            ; FF39
        LBR     IDERD           ; FF3C F_IDEREAD
        LBR     INITC           ; FF3F F_INITCALL
        LBR     UNKN            ; FF42
        LBR     UNKN            ; FF45
        LBR     UNKN            ; FF48
        LBR     UNKN            ; FF4B
        LBR     TYPE            ; FF4E (the ROM's second F_TYPE)
        LBR     UNKN            ; FF51
        LBR     UNKN            ; FF54
        LBR     UNKN            ; FF57
        LBR     UNKN            ; FF5A
        LBR     UNKN            ; FF5D
        LBR     UNKN            ; FF60
        LBR     UNKN            ; FF63
        LBR     UNKN            ; FF66
        LBR     INPUTL          ; FF69 F_INPUTL
        LBR     UNKN            ; FF6C
        LBR     UNKN            ; FF6F
        LBR     UNKN            ; FF72
        LBR     UNKN            ; FF75
        LBR     UNKN            ; FF78
        LBR     UNKN            ; FF7B
        LBR     UNKN            ; FF7E
        END
