; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; ltos.inc - LTOS (LiteOS) common definitions: registers, the Elf2K BIOS, the Disk/UART/RTC card.
;
; Calls use the BIOS's SCRT: R4 = CALL (SEP R4 / DW addr), R5 = RETURN (SEP R5), R2 = stack (X = R2),
; R3 = PC, R6 = the caller's return. D and DF do not survive a CALL or RETURN. RE.1 is the BIOS's baud
; byte - never touched.

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

; ---- the Elf2K BIOS (the same vectors in BIOS 1.0.6 and 1.0.12+)
F_TYPE  EQU     0FF03H          ; D -> the console
F_READ  EQU     0FF06H          ; the console -> D (waits)
F_MSG   EQU     0FF09H          ; the zero-ended string at RF -> the console
F_INPUTL EQU    0FF69H          ; a line into RF, at most RC characters (Backspace; Ctrl-C: DF = 1)
F_IDEREAD EQU   0FF3CH          ; read the sector R8 (R8.1 = E0 + LBA 24-27) : R7 -> RF (BOOT uses it)
F_INITCALL EQU  0FF3FH          ; set R4 / R5 to the BIOS's SCRT, then go on at R6 (as R3)
MONWARM EQU     08003H          ; the monitor's warm start

; ---- the Disk/UART/RTC card: OUT 2 = select, INP / OUT 3 = the selected register, INP 2 = card status
SELPORT EQU     2
DATPORT EQU     3
IDE_DATA EQU    0               ; ATA task file (select values)
IDE_ERR  EQU    1               ;   error (read) / feature (write)
IDE_CNT  EQU    2
IDE_LBA0 EQU    3
IDE_LBA1 EQU    4
IDE_LBA2 EQU    5
IDE_DEV  EQU    6               ;   E0 + LBA 24-27
IDE_CMD  EQU    7               ;   status (read) / command (write)
IDE_CTL  EQU    0EH             ;   device control: 04 soft reset, 02 interrupts off

MR1     EQU     31FDH           ; MON's stub, MACT = 1: R1 for STELLAR (the monitor's breakpoint entry)
MACT    EQU     31FFH           ; MON's last step (monstub, at $3000): 0 = then the monitor, 1 = start STELLAR
MJOBS   EQU     3200H           ;  its jobs: [sectors, where (2), the sectors' numbers (2 each)] ..., 0
NAMESB  EQU     3400H           ; ATTACH.PRG's list of a folder's names for LW2 with no file (STELLAR.PRG's job -> LWNAMES)
LWNAMES EQU     70CDH           ; ... where Lite-Writer 2 checks a new name against it: the top of its text room under
                                ; LTOS, ending at its card code ($7740); the text stays below it until the name is set
ATTORG  EQU     4D00H           ; ATTACH.PRG's address (just after STELLAR.PRG): its TEMP follows it
NAMESMX EQU     150             ; at most this many names (more: no new file there); build_litewriter2.py checks the room
PRGORG  EQU     3000H           ; LTOS's programs load here (the kernel: $0300-$2CFF, its variables $2D00-$2DFF)
NOTEB   EQU     3300H           ; ATTACH.PRG's note for the app (96 bytes; MON's stub copies it to $7EA0)
ATTFND  EQU     4644H           ; STELLAR.PRG -> ATTACH.PRG in RC: its FINDN of the document just found it
CFDLY   EQU     10              ; (cfdiag* only now) a pause after every byte (~130 us) - LTOS 0.2 needed it while a failing 74HC245; some CF cards give
                                ; wrong bytes when read faster (the Elf2K cannot honour IORDY) - CFDIAG's
                                ; slow read, reliable on all of Craig's cards
STACK   EQU     07DFFH          ; LTOS's stack top (grows down; $7F00-$7FFF is the monitor's)
