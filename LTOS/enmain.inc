; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; enmain.inc - in NANO.PRG itself (its spare room): the status line.

; ---- the status line (row 24), when no key is waiting and nothing else is there (a message, a question)
IDLE:   SEP     R4
        DW      RXPOLL
        LOAD    RD, NOTE + V_RHEAD
        LDA     RD
        STR     R2
        LDN     RD
        XOR
        LBNZ    ID9             ; a key waiting
        SEP     R4
        DW      GB
        DB      V_SDIRTY
        LBZ     ID9
        SEP     R4
        DW      GB
        DB      V_MSGF
        LBNZ    ID9
        LDI     24
        SEP     R4
        DW      GOTOL
        SEP     R4
        DW      TPIN
        DB      1BH,'[7m NANO 1.1 ',1BH,'[0m  ',0
        LOAD    R8, NAMEZ
        SEP     R4
        DW      TSTR
        SEP     R4
        DW      TPIN
        DB      '  Line ',0
        SEP     R4
        DW      GWB
        DB      V_LOFF
        SEP     R4
        DW      GW
        DB      V_CLN
        SEP     R4
        DW      ADDRB
        INC     R7
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      TPIN
        DB      '  Col ',0
        SEP     R4
        DW      GW
        DB      V_COL
        INC     R7
        SEP     R4
        DW      PDEC
        SEP     R4
        DW      GB
        DB      V_MKON
        BZ      ID2
        SEP     R4
        DW      TPIN
        DB      '  Mark',0
ID2:    SEP     R4
        DW      GB
        DB      V_MOD
        BZ      ID3
        SEP     R4
        DW      TPIN
        DB      '  Modified',0
ID3:    SEP     R4
        DW      TPIN
        DB      '   ^G Help',0
        SEP     R4
        DW      EOL
        LDI     0
        SEP     R4
        DW      PB
        DB      V_SDIRTY
ID9:    SEP     R5

