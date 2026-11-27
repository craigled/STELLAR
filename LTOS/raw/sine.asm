; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; SINE.asm - SINE.BIN, a raw 1802 program for LTOS's 1802 command:  1802 SINE
; A sine-wave tone on Q (the Elf2K's speaker) for about a second: 390 Hz at 3 MHz.
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
; Q is one bit, so the sine is made the way a CD player's 1-bit converter makes sound: each step a sample of the
; sine (32 a wave) is added to an 8-bit sum, and the carry out sets Q - so Q is on for the share of the time the
; sample says (delta-sigma). The speaker and the ear smooth the fast on/off into the sine. Every step takes the
; same 15 instructions (30 machine cycles: 12,500 steps a second at 3 MHz), so the pitch is 12,500 / 32 = 390 Hz.
LENGTH  EQU     30H             ; $3000 - $00FF = 12,033 steps: about 0.96 s at 3 MHz
        ORG     0
START:  LDI     HIGH(SCR)       ; R2 -> SCR, a byte for ADD; X = R2
        PHI     R2
        LDI     LOW(SCR)
        PLO     R2
        SEX     R2
        LDI     HIGH(TABLE)     ; RA -> the sine table (its own page: only the low byte steps, 00-1F)
        PHI     RA
        LDI     0
        PLO     RA
        LDI     LENGTH          ; RB = how many steps
        PHI     RB
        LDI     0
        PLO     RB
        PLO     R7              ; R7.0 = the sum
STEP:   LDN     RA              ; the sample
        STR     R2
        GLO     R7              ; sum + sample: its carry is this step's Q
        ADD
        PLO     R7
        BDF     HI
        REQ
        BR      NX
HI:     SEQ                     ; (both ways take the same 3 instructions)
        BR      NX
NX:     INC     RA              ; the next sample: 00-1F, round again
        GLO     RA
        ANI     1FH
        PLO     RA
        DEC     RB
        GHI     RB
        BNZ     STEP
        REQ                     ; quiet
DONE:   BR      DONE            ; (RESET leaves)
SCR:    DB      0
        ORG     0100H
TABLE:                          ; 128 + 127 x sin(k x 360 / 32), k = 0-31
        DB      080H,099H,0B1H,0C7H,0DAH,0EAH,0F5H,0FDH
        DB      0FFH,0FDH,0F5H,0EAH,0DAH,0C7H,0B1H,099H
        DB      080H,067H,04FH,039H,026H,016H,00BH,003H
        DB      001H,003H,00BH,016H,026H,039H,04FH,067H
        END
