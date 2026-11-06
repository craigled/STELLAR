; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; recv.asm - RECV.PRG: RECV name - a file sent from the terminal (its "send text file"), saved on the card.
;   Intel HEX (the first thing sent is ':'): the data records' bytes, from the lowest address to the highest,
;     the gaps 0. NAME.PRG gets the LTOS program header (load and start = the lowest address). Every record's
;     checksum is checked; any bad one and nothing is saved.
;   Text (anything else): every character, up to a line holding just "." or a Ctrl-Z (neither is kept).
;   NAME.STL (a STELLAR app's .lst): STLRX.PRG (stlrx.asm - the same code, built for $6800) takes it.
; Ctrl-C stops. The UART is read directly - no echo, nothing printed while it arrives - so it keeps up at
; full speed; if characters are lost anyway (the UART overran), it says so and saves nothing. It all goes to
; memory first (up to ~17 KB of file), then to the card. The code: recvcore.asm.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
STLRX   EQU     0
        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        INCL    "recvcore.asm"
        END
