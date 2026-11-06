; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; hello.asm - HELLO.PRG, the sample program the installer puts on the card. An LTOS program: a 6-byte header
; (load address, length, start - big-endian), then the code. RUN calls it with RF -> the rest of the command
; line, R2 a stack, the BIOS's SCRT in R4 / R5; it ends with SEP R5.

        CPU     1802
        INCL    "ltos.inc"

        ORG     PRGORG - 6
        DW      START, PEND - START, START

        ORG     PRGORG
START:  GHI     RF              ; keep the arguments
        PHI     R7
        GLO     RF
        PLO     R7
        LOAD    RF, MSG1
        SEP     R4
        DW      F_MSG
        LDN     R7
        LBNZ    ARGS
        LOAD    RF, MSG2
        SEP     R4
        DW      F_MSG
        SEP     R5
ARGS:   LOAD    RF, MSG3
        SEP     R4
        DW      F_MSG
        GHI     R7
        PHI     RF
        GLO     R7
        PLO     RF
        SEP     R4
        DW      F_MSG
        LOAD    RF, MSG4
        SEP     R4
        DW      F_MSG
        SEP     R5
MSG1:   DB      'Hello from HELLO.PRG at $3000.',0DH,0AH,0
MSG2:   DB      'Try: HELLO hi there',0DH,0AH,0
MSG3:   DB      'You said: "',0
MSG4:   DB      '"',0DH,0AH,0
PEND:
        END
