; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; stlrx.asm - STLRX.PRG: RECV NAME.STL - a STELLAR app from its .lst, as 512-byte blocks (RECV.PRG runs it).
; recvcore.asm's STL mode, built at $7700 (free RAM above LTOS's buffers) so the file can fill $2C00-$6BFF: sector 0 and
; all 31 blocks of $4000-$7DFF ... $7E00 (an app of every VM, e.g. STELLAR ORBIT).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"
STLRX   EQU     1
        ORG     7700H - 6
        DW      7700H, PEND - 7700H, START
        ORG     7700H
        INCL    "recvcore.asm"
        END
