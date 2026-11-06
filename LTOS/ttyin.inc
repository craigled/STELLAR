; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; ttyin.inc - GETSTR and FETCH: the prompt and a new line on the screen (K_TTY: never into a file).

; PROMPT: RF -> the arguments: -p "text" (or 'text', or one word) shown on the screen; RF past it
PROMPT: SEP     R4
        DW      K_SKIPSP
        LDN     RF
        XRI     '-'
        LBNZ    PR9
        INC     RF
        LDN     RF
        ORI     20H
        XRI     'p'
        LBZ     PR1
        DEC     RF              ; (not -p: a name that starts with -)
PR9:    SEP     R5
PR1:    INC     RF
        SEP     R4
        DW      K_SKIPSP
        LDN     RF              ; RC.0 = the quote it is in (0: none - up to a space)
        PLO     RC
        XRI     '"'
        LBZ     PR2
        GLO     RC
        XRI     27H
        LBZ     PR2
        LDI     0
        PLO     RC
        LBR     PR3
PR2:    INC     RF
PR3:    LDN     RF
        LBZ     PR9
        GLO     RC
        LBNZ    PR4
        LDN     RF
        XRI     ' '
        LBZ     PR9
        LBR     PR5
PR4:    LDN     RF
        STR     R2
        GLO     RC
        XOR
        LBNZ    PR5
        INC     RF              ; the closing quote
        SEP     R5
PR5:    LDA     RF
        SEP     R4
        DW      K_TTY
        LBR     PR3
; TTYNL: a new line on the screen.
TTYNL:  LDI     0DH
        SEP     R4
        DW      K_TTY
        LDI     0AH
        LBR     K_TTY
