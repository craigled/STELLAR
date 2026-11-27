; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; COUNTDN.asm - COUNTDN.BIN, a raw 1802 program for LTOS's 1802 command:  1802 COUNTDN
; The LEDs count down from FF to 00, about 20 ms a step (5 seconds), then stay at 00.
; Raw: no LTOS header, it starts at $0000 as after a reset (R0 the PC, X = P = 0). RESET, then BOOT at the
; monitor, brings LTOS back. Timed for a 3 MHz Elf2K (375,000 machine cycles a second); slower on a 1.79 MHz one.
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
DELAY   EQU     0500H           ; 1,280 x 6 = 7,680 machine cycles: about 20 ms a step at 3 MHz
        ORG     0
START:  LDI     HIGH(SHOW)      ; R2 -> SHOW, the byte OUT 4 sends; X = R2
        PHI     R2
        LDI     LOW(SHOW)
        PLO     R2
        SEX     R2
        LDI     0FFH
        PLO     R7              ; R7.0 = the count
DOWN:
        GLO     R7              ; the count to the LEDs: OUT 4 sends M(R2) (and steps R2 on)
        STR     R2
        OUT     4
        DEC     R2
        LDI     HIGH(DELAY)     ; wait: DELAY x (DEC, GLO, BNZ) = DELAY x 6 machine cycles
        PHI     RC
        LDI     LOW(DELAY)
        PLO     RC
W1:    DEC     RC
        GLO     RC
        BNZ     W1
        GHI     RC
        BNZ     W1
        GLO     R7              ; 00 shown: done
        BZ      DONE
        DEC     R7
        BR      DOWN
DONE:   BR      DONE            ; 00 stays on the LEDs (RESET leaves)
SHOW:   DB      0
        END
