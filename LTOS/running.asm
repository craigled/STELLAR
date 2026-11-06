; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; running.asm - RUNNING.PRG: the screen cleared, then a stick man on the spot in the middle of it, in white blocks
; (reverse-video spaces, two to a block, so a block is about square), as fast as the serial line goes: no waiting,
; and only the blocks that change are sent (walkman.inc, from walk_gen.py). Esc stops him; an arrow key's ESC [ x does not.
; It uses only the UART, so it works with any kernel.
        CPU     1802
        INCL    "ltos.inc"
ESC     EQU     1BH

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  SEX     R2
        LOAD    RA, CLEAR
        SEP     R4
        DW      SEND
        LOAD    RA, FIRST
        SEP     R4
        DW      SEND
        LOAD    RA, LOOP
AGAIN:  SEP     R4              ; the next frame
        DW      SEND
        SEP     R4              ; a key?
        DW      KEY
        LBNF    NEXT
        GLO     RC
        XRI     ESC
        LBNZ    NEXT
        LDI     80H             ; Esc: more straight after it is an arrow key
        PLO     R8
ESC1:   SEP     R4
        DW      KEY
        LBDF    ESC2
        DEC     R8
        GLO     R8
        LBNZ    ESC1
        LOAD    RA, LEAVE       ; alone: done
        SEP     R4
        DW      SEND
        SEP     R5
ESC2:   LDI     80H             ; the rest of it, read and forgotten
        PLO     R8
ESC3:   SEP     R4
        DW      KEY
        DEC     R8
        GLO     R8
        LBNZ    ESC3
NEXT:   LDN     RA              ; the last frame: round again
        LBNZ    AGAIN
        LOAD    RA, LOOP
        LBR     AGAIN
; SEND: the bytes at RA, to a 0, straight to the UART; RA left after the 0
SEND:   LDA     RA
        LBZ     SE9
        PLO     RC
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
SE1:    INP     DATPORT         ; room for it?
        ANI     20H
        BZ      SE1
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        GLO     RC
        STR     R2
        OUT     DATPORT
        DEC     R2
        LBR     SEND
SE9:    SEP     R5
; KEY: DF = 1, RC.0 = a character from the UART; DF = 0 none. Does not wait. (D does not survive the return.)
KEY:    LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        SHR
        LBNF    KE9
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     RC
        SMI     0               ; DF = 1 (D - 0 borrows nothing)
KE9:    SEP     R5
CLEAR:  DB      ESC,'[0m',ESC,'[2J',ESC,'[?25l',ESC,'[23;36HEsc stops',0
LEAVE:  DB      ESC,'[0m',ESC,'[?25h',ESC,'[2J',ESC,'[H',0
        INCL    "walkman.inc"
PEND:
        END
