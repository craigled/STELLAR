; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; play.asm - PLAY.PRG: PLAY name - a tune file played on Q (the Elf2K's speaker), a square wave.
;            PLAY -n notes - the notes on the command line (O there: > < are the shell's). No extension: .MUS.
;            PLAY -s MHz ... - for an Elf2K clocked at MHz (1.00-9.99; 3.58 if not given): the table worked out again.
; The notes (upper or lower case; spaces, new lines, | and , between them are ignored):
;   C D E F G A B   a note; then # or + sharp, - flat; then a length (1 whole, 2, 4 quarter, 8, 16, 32, 3 6 12 ...
;                   triplets - any 1-64; none: L's); then . dotted, .. double dotted.     C#8  E-4.  G
;   R (or P)        a rest, with a length and dots as a note's.
;   O n  > <        the octave, 1-7 (O4: middle C up to B); > one up, < one down.
;   L n             the length for notes that do not give one (4 at the start).
;   T n             the tempo, 32-255 quarter notes a minute (120 at the start).
;   MN ML MS        normal (each note 7/8 of its length, then quiet), legato (all of it), staccato (3/4).
;   ; text          to the end of the line: printed as it is reached (a title, the words).
; Any key stops it. It uses only the kernel's fixed calls (kapi.inc), so it works with any LTOS 0.5 kernel.
;
; The tone: TONE (at $3000, so its short branches stay in one page) toggles Q every half-period of
; 42 + 6 x K machine cycles, 8 more when a running fraction carries - see play_gen.py, which makes the table for
; the Elf2K at 3.5795 MHz (C1 to B7 in tune).
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
; ---- TONE: R7 = half-periods + $FF, R8 = K + $FF, RA.0 = FRAC, RB.0 = 0: quiet (a rest) else sound.
;      DF = 1: a key was pressed (read and dropped). Q is off after. Uses R9, RA.1.
TONE:   LDI     15H             ; the UART's line status, for the key check in the loop
        STR     R2
        OUT     SELPORT
        DEC     R2
HP:     GLO     RB              ; 2   (cycles)
        BZ      HPR             ; 2
        BQ      QOFF            ; 2
        SEQ                     ; 2
        BR      ACC             ; 2
QOFF:   REQ                     ; 2
        BR      ACC             ; 2
HPR:    REQ                     ; 2
        SEX     R2              ; 2
        BR      ACC             ; 2   10 each way
ACC:    INP     DATPORT         ; 2   a key?
        ANI     01H             ; 2
        BNZ     TKEY            ; 2
        GLO     RA              ; 2   RA.1 += FRAC: DF = the carry
        STR     R2              ; 2
        GHI     RA              ; 2
        ADD                     ; 2
        PHI     RA              ; 2
        GLO     R8              ; 2
        PLO     R9              ; 2
        GHI     R8              ; 2
        PHI     R9              ; 2
        BNF     DL              ; 2   36
        INC     R9              ; 2   a carry: one more round below, 8 cycles in all
DL:     DEC     R9              ; 2
        GHI     R9              ; 2
        BNZ     DL              ; 2   6 x K
        DEC     R7              ; 2
        GHI     R7              ; 2
        BNZ     HP              ; 2   42 + 6 K
        REQ
        LDI     0
        SHR
        SEP     R5
TKEY:   REQ
        LDI     10H             ; the key, read so it is not left for the prompt
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        LDI     1
        SHR
        SEP     R5

START:  SEX     R2
        REQ
OPT:    SEP     R4              ; the options: -s MHz, -n
        DW      K_SKIPSP
        LDN     RF
        LBZ     USAGE
        XRI     2DH             ; '-'
        LBNZ    FNAME
        INC     RF
        LDA     RF
        ANI     0DFH
        XRI     'N'
        LBZ     OPTN
        XRI     1DH             ; 'N' xor 'S'
        LBNZ    USAGE
        SEP     R4
        DW      K_SKIPSP
; ---- -s MHz: the Elf2K's clock, 1.00-9.99 (two decimals kept) -> C100 = MHz x 100
        SEP     R4
        DW      NUM             ; the whole MHz
        GHI     R7
        LBZ     MZBAD
        GHI     RD
        LBNZ    MZBAD
        GLO     RD
        SMI     10
        LBDF    MZBAD
        LDI     0
        PHI     RA
        PLO     RA
MZ1:    GLO     RD              ; RA = MHz x 100
        LBZ     MZ2
        DEC     RD
        GLO     RA
        ADI     100
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     MZ1
MZ2:    LDN     RF
        XRI     2EH             ; '.'
        LBNZ    MZ9
        INC     RF
        LDN     RF              ; tenths
        SMI     '0'
        LBNF    MZ9
        SMI     10
        LBDF    MZ9
        LDA     RF
        SMI     '0'
        PLO     R9
MZ3:    GLO     R9
        LBZ     MZ4
        DEC     R9
        GLO     RA
        ADI     10
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     MZ3
MZ4:    LDN     RF              ; hundredths
        SMI     '0'
        LBNF    MZ9
        SMI     10
        LBDF    MZ9
        LDA     RF
        SMI     '0'
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
MZ5:    LDN     RF              ; more decimals: passed over
        SMI     '0'
        LBNF    MZ9
        SMI     10
        LBDF    MZ9
        INC     RF
        LBR     MZ5
MZ9:    LDN     RF              ; then a space or the end
        LBZ     MZ10
        XRI     20H
        LBNZ    MZBAD
MZ10:   GLO     RA              ; 100-999
        SMI     LOW(1000)
        GHI     RA
        SMBI    HIGH(1000)
        LBDF    MZBAD
        GLO     RA
        SMI     100
        GHI     RA
        SMBI    0
        LBNF    MZBAD
        LOAD    RD, C100
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R4
        DW      RETUNE          ; the notes worked out for that clock
        LBR     OPT
MZBAD:  SEP     R4
        DW      K_PIN
        DB      'PLAY -s MHz: the Elf2K',27H,'s clock, 1.00 to 9.99 (3.58 if not given):  PLAY -s 1.79 ODE',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     DONE
OPTN:   SEP     R4
        DW      K_SKIPSP
        LBR     GO
; ---- the name, with .MUS if it has no extension
FNAME:  LOAD    RD, NAMEB
        LDI     0
        PLO     RA              ; RA.0 = 1: a '.' since the last '/'
        LDI     60
        PLO     RC
FN1:    LDN     RF
        LBZ     FN2
        XRI     20H
        LBZ     FN2
        LDA     RF
        STR     RD
        INC     RD
        XRI     2EH             ; '.'
        LBNZ    FN3
        LDI     1
        PLO     RA
        LBR     FN4
FN3:    XRI     01H             ; '/' ('.' xor '/' = 1)
        LBNZ    FN4
        LDI     0
        PLO     RA
FN4:    DEC     RC
        GLO     RC
        LBNZ    FN1
        LBR     USAGE
FN2:    GLO     RA
        LBNZ    FN5
        LDI     2EH
        STR     RD
        INC     RD
        LDI     'M'
        STR     RD
        INC     RD
        LDI     'U'
        STR     RD
        INC     RD
        LDI     'S'
        STR     RD
        INC     RD
FN5:    LDI     0
        STR     RD
        LOAD    RF, NAMEB
        LOAD    RA, BUF
        LOAD    RC, PTOP - BUF - 1
        SEP     R4
        DW      K_LOADF         ; RC = its bytes (no file, too big: said, and back to the prompt)
        GLO     RC              ; a 0 after it
        ADI     LOW(BUF)
        PLO     RD
        GHI     RC
        ADCI    HIGH(BUF)
        PHI     RD
        LDI     0
        STR     RD
        LOAD    RF, BUF
; ---- the notes at RF, to a 0
GO:     LOAD    RD, OCT
        LDI     3               ; O4
        STR     RD
        INC     RD
        LDI     4               ; DLEN: L4
        STR     RD
        INC     RD
        LDI     120             ; TEMPO
        STR     RD
        INC     RD
        LDI     0               ; ART: normal
        STR     RD
        INC     RD
        STR     RD              ; LINE = 1
        INC     RD
        LDI     1
        STR     RD
NEXT:   LDA     RF
        PHI     RB              ; RB.1 = the character
        LBZ     DONE
        XRI     0AH
        LBZ     NEWLN
        GHI     RB
        SMI     21H
        LBNF    NEXT            ; a space, tab, CR
        GHI     RB
        XRI     7CH             ; '|'
        LBZ     NEXT
        GHI     RB
        XRI     2CH             ; ','
        LBZ     NEXT
        GHI     RB
        XRI     3BH             ; ';'
        LBZ     CMNT
        GHI     RB
        XRI     3EH             ; '>'
        LBZ     OCTUP
        GHI     RB
        XRI     3CH             ; '<'
        LBZ     OCTDN
        GHI     RB
        SMI     60H
        LBNF    NX1
        GHI     RB
        ANI     0DFH
        PHI     RB
NX1:    GHI     RB
        SMI     'A'
        LBNF    BAD
        GHI     RB
        SMI     'H'
        LBNF    NOTE            ; A-G
        GHI     RB
        XRI     'R'
        LBZ     REST
        GHI     RB
        XRI     'P'
        LBZ     REST
        GHI     RB
        XRI     'O'
        LBZ     SETO
        GHI     RB
        XRI     'L'
        LBZ     SETL
        GHI     RB
        XRI     'T'
        LBZ     SETT
        GHI     RB
        XRI     'M'
        LBZ     SETM
BAD:    SEP     R4
        DW      K_PIN
        DB      'PLAY: line ',0
        LOAD    RD, LINE
        LDA     RD
        PHI     R7
        LDN     RD
        PLO     RD
        GHI     R7
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ': what is ',27H,0
        GHI     RB
        SEP     R4
        DW      K_OUT
        SEP     R4
        DW      K_PIN
        DB      27H,'?',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
DONE:   REQ
        SEP     R5
USAGE:  SEP     R4
        DW      K_PIN
        DB      'PLAY name      a tune file (.MUS if no extension)',0DH,0AH
        DB      'PLAY -n notes  the notes here:  PLAY -n T180 C E G O5 C',0DH,0AH
        DB      '               (use O, not > <: those send the output to a file)',0DH,0AH
        DB      'PLAY -s MHz .. the Elf2K',27H,'s clock (3.58 if not given):  PLAY -s 1.79 ODE',0DH,0AH
        DB      'HELP PLAY for the notes. Any key stops it.',0DH,0AH,0
        SEP     R5

NEWLN:  LOAD    RD, LINE+1
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LBR     NEXT
; ---- ; text: printed, to the end of the line (the LF is left for NEWLN)
CMNT:   LDN     RF
        XRI     20H
        LBNZ    CM1
        INC     RF
CM1:    LDN     RF
        LBZ     CM9
        XRI     0DH
        LBZ     CM9
        XRI     07H             ; LF (CR xor LF = 7)
        LBZ     CM9
        LDA     RF
        SEP     R4
        DW      K_OUT
        LBR     CM1
CM9:    SEP     R4
        DW      K_PCRLF
        LBR     NEXT
OCTUP:  LOAD    RD, OCT
        LDN     RD
        XRI     6
        LBZ     NEXT
        XRI     6
        ADI     1
        STR     RD
        LBR     NEXT
OCTDN:  LOAD    RD, OCT
        LDN     RD
        LBZ     NEXT
        SMI     1
        STR     RD
        LBR     NEXT
SETO:   SEP     R4
        DW      NUM
        GHI     R7
        LBZ     BAD
        LDI     1               ; 1-7 -> 0-6
        PHI     R9
        LDI     7
        SEP     R4
        DW      CLAMP
        SMI     1
        PLO     R9
        LOAD    RD, OCT
        GLO     R9
        STR     RD
        LBR     NEXT
SETL:   SEP     R4
        DW      NUM
        GHI     R7
        LBZ     BAD
        LDI     1
        PHI     R9
        LDI     64
        SEP     R4
        DW      CLAMP
        PLO     R9
        LOAD    RD, DLEN
        GLO     R9
        STR     RD
        LBR     NEXT
SETT:   SEP     R4
        DW      NUM
        GHI     R7
        LBZ     BAD
        LDI     32
        PHI     R9
        LDI     255
        SEP     R4
        DW      CLAMP
        PLO     R9
        LOAD    RD, TEMPO
        GLO     R9
        STR     RD
        LBR     NEXT
SETM:   LDA     RF
        ANI     0DFH
        PHI     RB
        XRI     'N'
        LBZ     SM0
        XRI     02H             ; 'N' xor 'L'
        LBZ     SM1
        XRI     1FH             ; 'L' xor 'S'
        LBZ     SM2
        LBR     BAD
SM0:    LDI     0
        LBR     SM3
SM1:    LDI     1
        LBR     SM3
SM2:    LDI     2
SM3:    PLO     R9
        LOAD    RD, ART
        GLO     R9
        STR     RD
        LBR     NEXT

; ---- a note: R8.0 = semitone + 1 (0-13), then the octave's 12s
NOTE:   LOAD    RD, SEMIT - 'A'
        GHI     RB
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
        LDN     RD
        PLO     R8
        LDN     RF
        XRI     23H             ; '#'
        LBZ     SHARP
        LDN     RF
        XRI     2BH             ; '+'
        LBZ     SHARP
        LDN     RF
        XRI     2DH             ; '-'
        LBNZ    NT1
        INC     RF
        DEC     R8
        LBR     NT1
SHARP:  INC     RF
        INC     R8
NT1:    LOAD    RD, OCT         ; + octave x 12 (x 8 + x 4)
        LDN     RD
        SHL
        SHL
        STR     R2
        SHL
        ADD
        STR     R2
        GLO     R8
        ADD                     ; 0-85
        LBZ     NT2             ; below C1: C1
        SMI     1
        STR     R2
        SMI     84
        LBNF    NT3
        LDI     83              ; above B7: B7
        LBR     NT3A
NT2:    LDI     0
NT3A:   STR     R2
NT3:    LDN     R2
        PLO     R8              ; the table's index
        LDI     1
        LBR     PLAYIT
REST:   LDI     84
        PLO     R8
        LDI     0
; ---- PLAYIT: R8.0 = the table index, D = 1 sound / 0 quiet; RF -> the length and dots
PLAYIT: PHI     R8
        LOAD    RD, SND
        GHI     R8
        STR     RD
        SEP     R4              ; the length
        DW      NUM
        GHI     R7
        LBNZ    PL1
        LOAD    RD, DLEN
        LDN     RD
        LBR     PL2
PL1:    LDI     1
        PHI     R9
        LDI     64
        SEP     R4
        DW      CLAMP
PL2:    PLO     RB              ; RB.0 = the length
        LDI     0
        PHI     RB              ; RB.1 = the dots
PL3:    LDN     RF
        XRI     2EH
        LBNZ    PL4
        INC     RF
        GHI     RB
        ADI     1
        PHI     RB
        LBR     PL3
PL4:    LOAD    RD, NDOTS
        GHI     RB
        STR     RD
        LOAD    RD, SAVRF       ; RF is free from here
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        ; DVS = TEMPO x the length
        LOAD    RD, TEMPO
        LDN     RD
        PLO     R9
        LDI     0
        PHI     R9              ; R9 = TEMPO, shifted up
        PHI     R7
        PLO     R7              ; R7 = the product
ML1:    GLO     RB
        LBZ     ML9
        SHR
        PLO     RB
        LBNF    ML2
        GLO     R9
        STR     R2
        GLO     R7
        ADD
        PLO     R7
        GHI     R9
        STR     R2
        GHI     R7
        ADC
        PHI     R7
ML2:    GLO     R9
        SHL
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        LBR     ML1
ML9:    LOAD    RD, DVS
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        ; the table's entry: R8 = K + $FF, FRAC, P -> RD.0:RC
        GLO     R8
        PLO     R9
        LDI     0
        PHI     R9
        GLO     R9              ; x 8
        SHL
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        GLO     R9
        SHL
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        GLO     R9
        SHL
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        GLO     R9
        ADI     LOW(PTAB)
        PLO     R9
        GHI     R9
        ADCI    HIGH(PTAB)
        PHI     R9
        LDA     R9
        PHI     R8
        LDA     R9
        PLO     R8
        LOAD    R7, FRAC
        LDA     R9
        STR     R7
        LDA     R9
        PLO     RD
        LDA     R9
        PHI     RC
        LDA     R9
        PLO     RC
        LOAD    R7, OVH
        LDA     R9
        STR     R7
        INC     R7
        LDN     R9
        STR     R7              ; OVH = PLAY's own time, in this note's half-periods
        LOAD    R9, DVS         ; + half the divisor, so the division rounds
        LDA     R9
        SHR
        PHI     RA
        LDN     R9
        SHRC
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RA
        STR     R2
        GHI     RC
        ADC
        PHI     RC
        GLO     RD
        ADCI    0
        PLO     RD
        SEP     R4
        DW      DIV             ; RD.0:RC = P / (TEMPO x length), rounded
        GLO     RD
        LBNZ    BIG
        GHI     RC
        XRI     0FFH
        LBNZ    PL5
BIG:    LOAD    RC, 0FF00H
PL5:    GHI     RC              ; at least 1
        LBNZ    PL6
        GLO     RC
        LBNZ    PL6
        INC     RC
PL6:    LOAD    RD, NDOTS       ; the dots: + a half, + a quarter ...
        LDN     RD
        PLO     RB
        GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA
DT1:    GLO     RB
        LBZ     DT9
        DEC     RB
        GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RA
        STR     R2
        GHI     RC
        ADC
        PHI     RC
        LBDF    DTBIG
        XRI     0FFH
        LBNZ    DT1
DTBIG:  LOAD    RC, 0FF00H
DT9:    LOAD    RD, OVH+1       ; less PLAY's own time (at least 1 left)
        LDN     RD
        STR     R2
        GLO     RC
        SM
        PLO     RA
        DEC     RD
        LDN     RD
        STR     R2
        GHI     RC
        SMB
        LBNF    OV1             ; shorter than that: 1
        PHI     RC
        GLO     RA
        PLO     RC
        GHI     RC
        LBNZ    DT10
        GLO     RC
        LBNZ    DT10
OV1:    LOAD    RC, 1
DT10:   ; the gap after a note: none (legato, a rest), N/8 (normal), N/4 (staccato)
        LDI     0
        PHI     RA
        PLO     RA              ; RA = the gap
        LOAD    RD, SND
        LDN     RD
        LBZ     GP9
        LOAD    RD, ART
        LDN     RD
        XRI     1
        LBZ     GP9
        XRI     1
        PLO     RB              ; 0 normal, 2 staccato
        GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA
        GHI     RA              ; / 4
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        GLO     RB
        LBNZ    GP2
        GHI     RA              ; / 8
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
GP2:    GLO     RA              ; the sound = N - the gap
        STR     R2
        GLO     RC
        SM
        PLO     RC
        GHI     RA
        STR     R2
        GHI     RC
        SMB
        PHI     RC
GP9:    LOAD    RD, GAP
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        GHI     RC              ; the sound (or the rest)
        LBNZ    PL7
        GLO     RC
        LBZ     PL8
PL7:    GLO     RC
        ADI     0FFH
        PLO     R7
        GHI     RC
        ADCI    0
        PHI     R7
        LOAD    RD, FRAC
        LDN     RD
        PLO     RA
        LOAD    RD, SND
        LDN     RD
        PLO     RB
        SEP     R4
        DW      TONE
        LBDF    STOP
PL8:    LOAD    RD, GAP         ; the gap, quiet
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    PL9
        GLO     RC
        LBZ     PL10
PL9:    GLO     RC
        ADI     0FFH
        PLO     R7
        GHI     RC
        ADCI    0
        PHI     R7
        LOAD    RD, FRAC
        LDN     RD
        PLO     RA
        LDI     0
        PLO     RB
        SEP     R4
        DW      TONE
        LBDF    STOP
PL10:   LOAD    RD, SAVRF
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LBR     NEXT
STOP:   SEP     R4
        DW      K_PIN
        DB      'Stopped.',0DH,0AH,0
        LBR     DONE

; ---- NUM: RF -> digits -> RD (at most 255 kept: more is 256+), R7.1 = 1 if there were any. RF past them.
NUM:    LDI     0
        PHI     RD
        PLO     RD
        PHI     R7
NU1:    LDN     RF
        SMI     '0'
        LBNF    NU9
        SMI     10
        LBDF    NU9
        LDI     1
        PHI     R7
        GHI     RD
        LBNZ    NU2             ; already 256 or more
        GLO     RD              ; RD = RD x 10 + the digit
        PLO     R9
        LDI     0
        PHI     R9
        GLO     R9
        SHL
        PLO     RD
        LDI     0
        SHLC
        PHI     RD              ; RD = x 2
        GLO     R9
        SHL
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        GLO     R9
        SHL
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        GLO     R9
        SHL
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9              ; R9 = x 8
        GLO     R9
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     R9
        STR     R2
        GHI     RD
        ADC
        PHI     RD
        LDN     RF
        SMI     '0'
        STR     R2
        GLO     RD
        ADD
        PLO     RD
        GHI     RD
        ADCI    0
        PHI     RD
NU2:    INC     RF
        LBR     NU1
NU9:    SEP     R5

; ---- CLAMP: RD (from NUM) into R9.1 .. D -> D
CLAMP:  STR     R2              ; the top
        GHI     RD
        LBNZ    CL2             ; 256 or more: the top
        GLO     RD
        SD                      ; top - RD
        LBNF    CL2             ; RD > top
        GHI     R9
        STR     R2
        GLO     RD
        SM                      ; RD - bottom
        LBNF    CL1
        GLO     RD
        SEP     R5
CL1:    GHI     R9
        SEP     R5
CL2:    LDN     R2
        SEP     R5

; ---- DIV: RD.0:RC (24 bits) / DVS (16) -> RD.0:RC. Uses R7, R9 (the remainder), RA, RB.0, RF.1.
DIV:    LOAD    R7, DVS+1
        LDI     0
        PHI     R9
        PLO     R9
        LDI     24
        PLO     RB
DV1:    GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     RD
        SHLC
        PLO     RD
        GLO     R9
        SHLC
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        LDI     0
        SHLC
        PHI     RA              ; RA.1 = the 17th bit
        SEX     R7
        GLO     R9
        SM
        PLO     RA
        DEC     R7
        GHI     R9
        SMB
        INC     R7
        PHI     RF
        LBDF    DVC
        GHI     RA
        LBZ     DVN
DVC:    GHI     RF
        PHI     R9
        GLO     RA
        PLO     R9
        INC     RC
DVN:    SEX     R2
        DEC     RB
        GLO     RB
        LBNZ    DV1
        SEP     R5

;-- RETUNE: the note table worked out again for a clock of C100 / 100 MHz (it is for 3.58 as built). For each of
;   O7's notes, its half-period x 32 = 320,000 x C100 / (Hz x 16) (DIV32), doubled for each octave down: the first
;   octave TONE can make is worked out by dividing (EFULL), the ones below from it (ENEXT); the rest likewise.
;   P stays (half-periods a second do not change), but for a note too high for the clock (ECLAMP).
RETUNE: LOAD    RD, SAVRF
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, BIGN         ; BIGN = 0, MADD = 320,000
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD              ; MADD = 00 04 E2 00
        INC     RD
        LDI     04H
        STR     RD
        INC     RD
        LDI     0E2H
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        LOAD    RD, C100
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
RT1:    GHI     RA              ; BIGN = 320,000 x C100: MADD added for each 1 bit, doubled each time
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        LBNF    RT2
        LOAD    RD, BIGN+3
        LOAD    R9, MADD+3
        SEX     R9
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        DEC     R9
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        DEC     R9
        LDN     RD
        ADC
        STR     RD
        DEC     RD
        DEC     R9
        LDN     RD
        ADC
        STR     RD
        SEX     R2
RT2:    LOAD    RD, MADD+3
        LDN     RD
        SHL
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        GHI     RA
        LBNZ    RT1
        GLO     RA
        LBNZ    RT1
        LOAD    RD, FTP         ; the 12 notes, from O7's
        LDI     HIGH(FTAB)
        STR     RD
        INC     RD
        LDI     LOW(FTAB)
        STR     RD
        INC     RD              ; CNT
        LDI     12
        STR     RD
        LOAD    R8, PTAB + 72 * 8
RT3:    SEP     R4
        DW      HTOP            ; HV = BIGN / the next FTAB value
        LOAD    RD, NXT
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        INC     RD              ; OCN = 7 octaves
        LDI     7
        STR     RD
        INC     RD              ; STATE = 0: not worked out yet
        LDI     0
        STR     RD
RT4:    LOAD    RD, STATE
        LDN     RD
        LBNZ    RT5
        SEP     R4              ; still too high (clamped), or the first that is not: worked out from HV
        DW      EFULL
        LBR     RT6
RT5:    SEP     R4              ; an octave below one worked out
        DW      ENEXT
RT6:    LOAD    RD, HV+2        ; an octave down: twice the half-period
        LDN     RD
        SHL
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        GLO     R8              ; the entry 12 before
        SMI     96
        PLO     R8
        GHI     R8
        SMBI    0
        PHI     R8
        LOAD    RD, OCN
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    RT4
        LOAD    RD, NXT         ; the next note up
        LDA     RD
        PHI     R8
        LDN     RD
        ADI     8
        PLO     R8
        GHI     R8
        ADCI    0
        PHI     R8
        LOAD    RD, CNT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    RT3
        SEP     R4              ; the rest (FTP is at its value now)
        DW      HTOP
        LOAD    R8, PTAB + 84 * 8
        SEP     R4
        DW      EFULL
        LOAD    RD, SAVRF
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5
; HTOP: HV (3 bytes) = BIGN / the word at FTP; FTP moves on
HTOP:   LOAD    R9, FTP
        LDA     R9
        PHI     R7
        LDN     R9
        PLO     R7
        LOAD    R9, DVS
        LDA     R7
        STR     R9
        INC     R9
        LDA     R7
        STR     R9
        LOAD    R9, FTP
        GHI     R7
        STR     R9
        INC     R9
        GLO     R7
        STR     R9
        LOAD    R9, BIGN
        LDA     R9
        PHI     RD
        LDA     R9
        PLO     RD
        LDA     R9
        PHI     RC
        LDN     R9
        PLO     RC
        SEP     R4
        DW      DIV32
        LOAD    R9, HV
        GLO     RD
        STR     R9
        INC     R9
        GHI     RC
        STR     R9
        INC     R9
        GLO     RC
        STR     R9
        SEP     R5
; EFULL: the entry at R8 (kept) from HV, its half-period x 32. Below 1,536 (faster than TONE goes): K 1, FRAC 0,
;   OV 51, and P from the clock (5 x cycles a second), so it lasts as long as it should. Else K = (HV - 1344) / 192,
;   FRAC = what is left, OVX = OV x 256 = 77,760 x 256 / HV (2,430 cycles x 32), and STATE = 1.
EFULL:  LOAD    R9, HV
        LDA     R9
        PLO     RD
        LDA     R9
        PHI     RC
        LDN     R9
        PLO     RC
        GLO     RC
        SMI     LOW(1344)
        PLO     RC
        GHI     RC
        SMBI    HIGH(1344)
        PHI     RC
        GLO     RD
        SMBI    0
        PLO     RD
        LBNF    ECLAMP          ; below 1,344
        LBNZ    EF1
        GHI     RC
        LBNZ    EF1
        GLO     RC
        SMI     192
        LBNF    ECLAMP
EF1:    LOAD    R9, DVS
        LDI     0
        STR     R9
        INC     R9
        LDI     192
        STR     R9
        SEP     R4
        DW      DIV             ; RC = K, R9.0 = FRAC
        LOAD    RD, KC
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        INC     RD
        GLO     R9
        STR     RD              ; FC
        LOAD    R9, HV+1        ; OVX = 19,906,560 ($012FC000) / HV  (HV is below 65,536 here)
        LOAD    RD, DVS
        LDA     R9
        STR     RD
        INC     RD
        LDN     R9
        STR     RD
        LOAD    RD, 012FH
        LOAD    RC, 0C000H
        SEP     R4
        DW      DIV32
        GLO     RD              ; (its top byte: RD.0)
        PLO     RA
        LOAD    RD, OVX
        GLO     RA
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, STATE
        LDI     1
        STR     RD
        LBR     ESTORE
; ENEXT: an octave below: K = 2 K + 7 (1,344 = 7 x 192), FRAC = 2 FRAC (less 192, and K + 1, if it reaches it);
;   OVX halved
ENEXT:  LOAD    RD, FC
        LDN     RD
        SHL
        STR     RD
        LBDF    EX1             ; (2 FRAC can pass 255)
        SMI     192
        LBNF    EX2
EX1:    LDN     RD
        SMI     192
        STR     RD
        LDI     8               ; 2 K + 8
        LBR     EX3
EX2:    LDI     7               ; 2 K + 7
EX3:    PLO     RA
        LOAD    RD, KC+1
        LDN     RD
        SHL
        STR     RD
        DEC     RD
        LDN     RD
        SHLC
        STR     RD
        INC     RD
        GLO     RA
        STR     R2
        LDN     RD
        ADD
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        LOAD    RD, OVX
        LDN     RD
        SHR
        STR     RD
        INC     RD
        LDN     RD
        SHRC
        STR     RD
        INC     RD
        LDN     RD
        SHRC
        STR     RD
; ESTORE: KC, FC, OVX -> the entry at R8: K + $FF, FRAC, OV = OVX / 256 rounded
ESTORE: GHI     R8
        PHI     RD
        GLO     R8
        PLO     RD
        LOAD    R9, KC
        LDA     R9
        PHI     RC
        LDA     R9
        PLO     RC
        GLO     RC
        ADI     0FFH
        PLO     RA
        GHI     RC
        ADCI    0
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        LDA     R9              ; FC
        STR     RD
        LOAD    R9, OVX+2       ; OV = (OVX + 128) / 256
        LDN     R9
        ADI     80H
        DEC     R9
        LDN     R9
        ADCI    0
        PLO     RC
        DEC     R9
        LDN     R9
        ADCI    0
        PHI     RC
        LBR     EOV
ECLAMP: LOAD    R9, BIGN        ; P = 240 s x cycles a second / 48 = 5 x (BIGN / 256)
        LDA     R9
        PLO     RB              ; RB.0:RA = BIGN / 256 (the cycles a second)
        LDA     R9
        PHI     RA
        LDN     R9
        PLO     RA
        GLO     RB              ; RB.1:R7 = x 4
        PHI     RB
        GHI     RA
        PHI     R7
        GLO     RA
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        GHI     RB
        SHLC
        PHI     RB
        GLO     R7
        SHL
        PLO     R7
        GHI     R7
        SHLC
        PHI     R7
        GHI     RB
        SHLC
        PHI     RB
        GLO     R8              ; P at the entry + 3: x 4 + x 1
        ADI     5
        PLO     RD
        GHI     R8
        ADCI    0
        PHI     RD
        GLO     R7
        STR     R2
        GLO     RA
        ADD
        STR     RD
        DEC     RD
        GHI     R7
        STR     R2
        GHI     RA
        ADC
        STR     RD
        DEC     RD
        GHI     RB
        STR     R2
        GLO     RB
        ADC
        STR     RD
        GHI     R8              ; K + $FF = $0100, FRAC 0
        PHI     RD
        GLO     R8
        PLO     RD
        LDI     1
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        LOAD    RC, 51          ; OV: 77,760 / 1,536
EOV:    GLO     R8              ; OV at the entry + 6
        ADI     6
        PLO     RD
        GHI     R8
        ADCI    0
        PHI     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5

; ---- DIV32: RD:RC (32 bits) / DVS (16) -> RD:RC, the remainder in R9. Uses R7, RA, RB.0, RF.1.
DIV32:  LOAD    R7, DVS+1
        LDI     0
        PHI     R9
        PLO     R9
        LDI     32
        PLO     RB
D32A:   GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     RD
        SHLC
        PLO     RD
        GHI     RD
        SHLC
        PHI     RD
        GLO     R9
        SHLC
        PLO     R9
        GHI     R9
        SHLC
        PHI     R9
        LDI     0
        SHLC
        PHI     RA
        SEX     R7
        GLO     R9
        SM
        PLO     RA
        DEC     R7
        GHI     R9
        SMB
        INC     R7
        PHI     RF
        LBDF    D32C
        GHI     RA
        LBZ     D32N
D32C:   GHI     RF
        PHI     R9
        GLO     RA
        PLO     R9
        INC     RC
D32N:   SEX     R2
        DEC     RB
        GLO     RB
        LBNZ    D32A
        SEP     R5

SEMIT:  DB      10, 12, 1, 3, 5, 6, 8   ; A B C D E F G: the semitone + 1
        INCL    "playtab.inc"
PEND:
OCT:    DS      1               ; 0-6 = O1-O7     (GO sets these five in order)
DLEN:   DS      1
TEMPO:  DS      1
ART:    DS      1
LINE:   DS      2
SND:    DS      1
NDOTS:  DS      1
FRAC:   DS      1
DVS:    DS      2
GAP:    DS      2
OVH:    DS      2
C100:   DS      2               ; -s: the clock in MHz x 100
BIGN:    DS      4               ; 320,000 x C100  (MADD follows it: RETUNE clears both)
MADD:   DS      4
HV:     DS      3
FTP:    DS      2               ; (CNT follows it)
CNT:    DS      1
NXT:    DS      2               ; (OCN, STATE follow it)
OCN:    DS      1
STATE:  DS      1
KC:     DS      2               ; (FC follows it)
FC:     DS      1
OVX:    DS      3
SAVRF:  DS      2
NAMEB:  DS      64
BUF:
        END
