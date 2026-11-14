; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; morse.asm - MORSE.PRG: Morse code on the Elf2K - sent as a tone on Q, received from a key on an EF line.
;   MORSE -s name    send the file
;   MORSE -t         type lines and each is sent as written (as MORSETX.STL): the letters and their dots and dashes
;   MORSE -r name    receive: key Morse on EF4 (the INPUT switch); it learns your speed as you go (as MORSERX.STL);
;                    the letters show as they are decoded, and Esc saves them in the file
;   -w WPM   the speed, 5-40 words a minute (12)      -f Hz   the tone, 200-2000 (700)
;   -e N     the EF line the key is on, 1-4 (4)       -c MHz  the Elf2K's clock, 1.00-9.99 (3.58; Craig's is 1.79)
; Timing (PARIS): a dot 1.2 s / WPM; a dash 3 dots; the gap inside a letter 1, between letters 3, between words 7.
; Everything is counted in half-periods of the tone, so pitch and time come from the one clock.
; The characters are Firmware-Math/morse_table.py's (morse_gen.py -> morsetab.inc), the same as the STELLAR apps'.
; Esc (or Ctrl-C) stops sending, and ends receiving. Only the kernel's fixed calls: it works with any LTOS 0.5.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
ESC     EQU     1BH
DGK     EQU     4               ; the gap loop's extra cycles over the mark loop's, / 6: a key (22), -a (32)
DGA     EQU     5
NDOWN   EQU     3               ; -a: samples hearing sound that start a mark
SRAUD   EQU     4000            ; -a: samples a second (a sound module's short pulses are caught at any pitch)
RXOVH   EQU     30              ; the receive loops' own cycles a sample, outside the delay (measured in the sim)
OVE     EQU     220             ; sending: cycles of work around each element's quiet, a letter's, a word's
OVL     EQU     360             ;  (measured in the sim; taken off those quiets, as half-periods)
OVW     EQU     190

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
; ---- TONE (PLAY's): R7 = half-periods + $FF, R8 = K + $FF, RA.0 = FRAC, RB.0 = 0: quiet, else Q toggles.
;      A half-period is 42 + 6 K machine cycles (+8 when the FRAC sum carries). DF = 1: a key was pressed (read).
TONE:   LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
HP:     GLO     RB
        BZ      HPR
        BQ      QOFF
        SEQ
        BR      ACC
QOFF:   REQ
        BR      ACC
HPR:    REQ
        SEX     R2
        BR      ACC
ACC:    INP     DATPORT
        ANI     01H
        BNZ     TKEY
        GLO     RA
        STR     R2
        GHI     RA
        ADD
        PHI     RA
        GLO     R8
        PLO     R9
        GHI     R8
        PHI     R9
        BNF     DL
        INC     R9
DL:     DEC     R9
        GHI     R9
        BNZ     DL
        DEC     R7
        GHI     R7
        BNZ     HP
        REQ
        LDI     0
        SHR
        SEP     R5
TKEY:   REQ
        LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        PLO     R9              ; R9.0 = the key (R7 = what was left: SOUND goes on with it for other keys)
        LDI     1
        SHR
        SEP     R5

; ---- the receive loops, one sample a time round (one half-period of the tone): RC counts samples, R7 / R8 count
;      down to the end of the letter / the word (0 = not counting), RB.0 = samples the key has read the other way
;      in a row (the debounce), RA.1 = how many make a change, RD = the delay (K + $FF). KEYM / KEYG are B1-B4,
;      patched for the EF line. While the key is down Q toggles: a sidetone at the tone's pitch.
RXM:    BQ      RXM1
RXMQ:   SEQ                     ; (-a: patched to REQ - no sidetone, the microphone would hear it)
        BR      RXM2
RXM1:   REQ
        SEX     R2
RXM2:   INC     RC
        INP     DATPORT
        ANI     01H
        BNZ     RXKM
KEYM:   B4      RXM3            ; (patched) still down
        GLO     RB
        ADI     1
        PLO     RB
        STR     R2
        GHI     RA
        XOR
        BZ      RXMUP
        BR      RXM4
RXM3:   LDI     0
        PLO     RB
RXM4:   GLO     RD
        PLO     R9
        GHI     RD
        PHI     R9
RXMD:   DEC     R9
        GHI     R9
        BNZ     RXMD
        BR      RXM
RXMUP:  LBR     MARKEND
RXKM:   LBR     RXKEY

RXG:    REQ
        SEX     R2
        SEX     R2
        INC     RC
        INP     DATPORT
        ANI     01H
        BNZ     RXKG
        GLO     R7              ; the letter's countdown
        BNZ     RXG1
        GHI     R7
        BZ      RXG2
RXG1:   DEC     R7
        GLO     R7
        BNZ     RXG2
        GHI     R7
        BNZ     RXG2
        LBR     LETEV           ; (back at RXG2)
RXG2:   GLO     R8              ; the word's countdown
        BNZ     RXG3
        GHI     R8
        BZ      RXG4
RXG3:   DEC     R8
        GLO     R8
        BNZ     RXG4
        GHI     R8
        BNZ     RXG4
        LBR     WORDEV          ; (back at RXG4)
RXG4:
KEYG:   B4      RXG5            ; (patched) down?
        LDI     0
        PLO     RB
        BR      RXG6
RXG5:   GLO     RB
        ADI     1
        PLO     RB
        STR     R2
        GHI     RA
        XOR
        BZ      RXGDN
RXG6:   GLO     RD
        PLO     R9
        GHI     RD
        PHI     R9
RXGD:   DEC     R9
        GHI     R9
        BNZ     RXGD
        BR      RXG
RXGDN:  LBR     GAPEND
RXKG:   LBR     RXKEY
; -a: a sound module flickers at the tone's pitch, so in the gap KEYG is patched to BR TGSUB: a mark starts at the
;   NDOWN-th sample that hears sound, the count forgotten after RA.1 (the hold) samples of quiet. (In the mark, RXM's
;   own rule - RA.1 samples of quiet end it - already rides over the flicker.)
TGSUB:
KEYT:   B4      TG5             ; (patched) sound?
        GHI     RB              ; quiet: RB.1 counts it
        ADI     1
        PHI     RB
        STR     R2
        GHI     RA
        XOR
        BNZ     RXG6
        LDI     0               ; the hold's worth of quiet: what was heard is forgotten
        PLO     RB
        PHI     RB
        BR      RXG6
TG5:    LDI     0
        PHI     RB
        GLO     RB
        ADI     1
        PLO     RB
        XRI     NDOWN
        BZ      RXGDN
        BR      RXG6
RXEND:

; =================================================================================================== the options
START:  SEX     R2
        REQ
        LOAD    RD, C100        ; the defaults: 3.58 MHz, 12 WPM, 700 Hz, EF4, no mode yet
        LDI     HIGH(358)
        STR     RD
        INC     RD
        LDI     LOW(358)
        STR     RD
        INC     RD              ; WPM
        LDI     12
        STR     RD
        INC     RD              ; FREQ
        LDI     HIGH(700)
        STR     RD
        INC     RD
        LDI     LOW(700)
        STR     RD
        INC     RD              ; EFN
        LDI     4
        STR     RD
        INC     RD              ; MODE
        LDI     0
        STR     RD
        INC     RD              ; VERB
        STR     RD
        INC     RD              ; AUDIO
        STR     RD
        INC     RD              ; INV
        STR     RD
        INC     RD              ; HOLD (0: the default)
        STR     RD
OPT:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     OPEND
        XRI     '-'
        LBNZ    USAGE
        INC     RF
        LDA     RF
        ANI     0DFH
        PLO     RB              ; the letter
        SEP     R4
        DW      K_SKIPSP
        GLO     RB
        XRI     'S'
        LBZ     OSEND
        GLO     RB
        XRI     'R'
        LBZ     OSEND
        GLO     RB
        XRI     'T'
        LBZ     OTEXT
        GLO     RB
        XRI     'W'
        LBZ     OWPM
        GLO     RB
        XRI     'F'
        LBZ     OFREQ
        GLO     RB
        XRI     'E'
        LBZ     OEF
        GLO     RB
        XRI     'C'
        LBZ     OCLK
        GLO     RB
        XRI     'V'
        LBZ     OVERB
        GLO     RB
        XRI     'A'
        LBZ     OAUD
        GLO     RB
        XRI     'I'
        LBZ     OINV
        GLO     RB
        XRI     'H'
        LBZ     OHOLD
        LBR     USAGE
OAUD:   LOAD    RD, AUDIO       ; -a: a sound module on the EF line
        LDI     1
        STR     RD
        LBR     OPT
OINV:   LOAD    RD, INV         ; -i: the line the other way up (a module whose output goes high on sound)
        LDI     1
        STR     RD
        LBR     OPT
OHOLD:  SEP     R4              ; -h ms: 1-50, the hold (-a: 8) or the key's debounce (5)
        DW      NUMARG
        LBDF    USAGE
        GHI     RD
        LBNZ    USAGE
        GLO     RD
        LBZ     USAGE
        SMI     51
        LBDF    USAGE
        GLO     RD
        PLO     RB
        LOAD    RD, HOLD
        GLO     RB
        STR     RD
        LBR     OEND
OVERB:  LOAD    RD, VERB        ; -v: each mark and gap shown, in samples
        LDI     1
        STR     RD
        LBR     OPT
OSEND:  SEP     R4              ; -s name / -r name: MODE = 'S' / 'R', NAMEP -> the name
        DW      SETMODE
        LBDF    USAGE
        LDN     RF
        LBZ     USAGE
        LOAD    RD, NAMEP
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
OS1:    LDN     RF              ; past the name
        LBZ     OPT
        XRI     20H
        LBZ     OS2
        INC     RF
        LBR     OS1
OS2:    LDI     0               ; the name ends here
        STR     RF
        INC     RF
        LBR     OPT
OTEXT:  SEP     R4
        DW      SETMODE
        LBDF    USAGE
        LBR     OPT
OWPM:   SEP     R4              ; -w 5-40
        DW      NUMARG
        LBDF    USAGE
        GHI     RD
        LBNZ    USAGE
        GLO     RD
        SMI     5
        LBNF    USAGE
        SMI     36
        LBDF    USAGE
        GLO     RD
        PLO     RB
        LOAD    RD, WPM
        GLO     RB
        STR     RD
        LBR     OEND
OFREQ:  SEP     R4              ; -f 200-2000
        DW      NUMARG
        LBDF    USAGE
        GLO     RD
        SMI     LOW(200)
        GHI     RD
        SMBI    HIGH(200)
        LBNF    USAGE
        GLO     RD
        SMI     LOW(2001)
        GHI     RD
        SMBI    HIGH(2001)
        LBDF    USAGE
        GHI     RD
        PHI     RB
        GLO     RD
        PLO     RB
        LOAD    RD, FREQ
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LBR     OEND
OEF:    LDA     RF              ; -e 1-4
        SMI     '1'
        LBNF    USAGE
        SMI     4
        LBDF    USAGE
        ADI     5               ; 1-4
        PLO     RB
        LOAD    RD, EFN
        GLO     RB
        STR     RD
        LBR     OEND
OCLK:   SEP     R4              ; -c MHz: 1.00-9.99, two decimals kept -> C100
        DW      NUMARG
        LBDF    USAGE
        GHI     RD
        LBNZ    USAGE
        GLO     RD
        LBZ     USAGE
        SMI     10
        LBDF    USAGE
        LDI     0
        PHI     RA
        PLO     RA
OC1:    GLO     RD              ; RA = MHz x 100
        LBZ     OC2
        DEC     RD
        GLO     RA
        ADI     100
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     OC1
OC2:    LDN     RF
        XRI     '.'
        LBNZ    OC9
        INC     RF
        LDI     10
        PLO     RB              ; the tenths' weight, then the hundredths'
OC3:    LDN     RF
        SMI     '0'
        LBNF    OC9
        SMI     10
        LBDF    OC9
        LDA     RF
        SMI     '0'
        PLO     R9
OC4:    GLO     R9              ; RA += digit x weight
        LBZ     OC5
        DEC     R9
        GLO     RB
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GHI     RA
        ADCI    0
        PHI     RA
        LBR     OC4
OC5:    GLO     RB
        XRI     10
        LBNZ    OC6
        LDI     1
        PLO     RB
        LBR     OC3
OC6:    LDN     RF              ; more decimals: passed over
        SMI     '0'
        LBNF    OC9
        SMI     10
        LBDF    OC9
        INC     RF
        LBR     OC6
OC9:    LOAD    RD, C100
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
OEND:   LDN     RF              ; then a space, or the end
        LBZ     OPT
        XRI     20H
        LBNZ    USAGE
        LBR     OPT
; SETMODE: MODE = RB.0 ('S' 'R' 'T'), DF = 0; DF = 1 if a mode was given already
SETMODE: LOAD   RD, MODE
        LDN     RD
        LBNZ    SM1
        GLO     RB
        STR     RD
        LDI     0
        SHR
        SEP     R5
SM1:    LDI     1
        SHR
        SEP     R5
OPEND:  LOAD    RD, MODE
        LDN     RD
        LBZ     USAGE
        SEP     R4
        DW      SETUP           ; the timing for the clock, the speed and the tone
        LOAD    RD, MODE
        LDN     RD
        XRI     'S'
        LBZ     SFILE
        LDN     RD
        XRI     'T'
        LBZ     TTEXT
        LBR     RFILE

USAGE:  SEP     R4
        DW      K_PIN
        DB      'MORSE -s name   send the file as Morse (a tone on Q)',0DH,0AH
        DB      'MORSE -t        type lines; each is sent as written',0DH,0AH
        DB      'MORSE -r name   receive Morse keyed on EF4 (the INPUT switch); Esc saves',0DH,0AH
        DB      '  -w WPM 5-40 (12)  -f Hz 200-2000 (700)  -e EF 1-4 (4)  -c MHz clock (3.58)',0DH,0AH
        DB      '  -r with: -v each mark and gap shown (in samples)  -a a sound module on the line',0DH,0AH
        DB      '           -i the line the other way up  -h ms the hold (-a 8) / debounce (5)',0DH,0AH,0
        LOAD    RD, K_STAT
        LDI     1
        STR     RD
DONE:   REQ
        SEP     R5

; =================================================================================================== the timing
; SETUP: MCB = cycles a second = C100 x 1,250; H = MCB / (2 x FREQ), the half-period; K = (H - 42) / 6, FRAC = what
;   is left x 32 (TONE's carry adds 8 cycles); UNIT = 24 x FREQ / (10 x WPM) half-periods a dot, rounded; DOTS2-4,
;   DASHU; DEB = FREQ / 100 (5 ms) at least 2; KRX = (H - RXOVH) / 6 for the receive loops.
SETUP:  LOAD    RD, C100        ; RA = C100
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDI     0               ; RD.0:RC = 0, R9:RB.0 = 1,250 shifted up (24 bits: R9.0 high, RB 16)
        PLO     RD
        PHI     RC
        PLO     RC
        PLO     R9
        LDI     HIGH(1250)
        PHI     RB
        LDI     LOW(1250)
        PLO     RB
SU1:    GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        LBNF    SU2
        GLO     RB
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RB
        STR     R2
        GHI     RC
        ADC
        PHI     RC
        GLO     R9
        STR     R2
        GLO     RD
        ADC
        PLO     RD
SU2:    GLO     RB
        SHL
        PLO     RB
        GHI     RB
        SHLC
        PHI     RB
        GLO     R9
        SHLC
        PLO     R9
        GHI     RA
        LBNZ    SU1
        GLO     RA
        LBNZ    SU1
        LOAD    RF, MCB         ; kept: the cycles a second (-r -a works its sampling out from it)
        GLO     RD
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LDI     2               ; RD.0:RC = MC x 4
        PLO     RA
SUX:    GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        GLO     RD
        SHLC
        PLO     RD
        DEC     RA
        GLO     RA
        LBNZ    SUX
        LOAD    RF, FREQ        ; H8 = MC x 4 / FREQ: the half-period in eighths of a cycle
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV             ; RC = H8
        GHI     RC              ; HALF = H8 / 8
        PHI     RA
        GLO     RC
        PLO     RA
        LDI     3
        PLO     R9
SUH:    GHI     RA
        SHR
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        DEC     R9
        GLO     R9
        LBNZ    SUH
        LOAD    RF, HALF
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        GLO     RC              ; K: below 48 cycles (384 eighths), as fast as TONE goes
        SMI     LOW(384)
        GHI     RC
        SMBI    HIGH(384)
        LBDF    SU3
        LOAD    RC, 1
        LDI     0
        PLO     R9
        LBR     SU4
SU3:    GLO     RC              ; (H8 - 336) / 48: K, and what is left (0-47) x 4 = FRAC (a carry: 8 cycles)
        SMI     LOW(336)
        PLO     RC
        GHI     RC
        SMBI    HIGH(336)
        PHI     RC
        LDI     0
        PLO     RD
        LOAD    RB, 48
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV             ; RC = K, R9 = left
        GLO     R9              ; FRAC = what is left x 4
        SHL
        SHL
        PLO     R9
SU4:    LOAD    RF, KB          ; KB = K + $FF, FRAC = left x 4
        GLO     RC
        ADI     0FFH
        PLO     RB
        GHI     RC
        ADCI    0
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        INC     RF              ; FRAC
        GLO     R9
        STR     RF
        LOAD    RF, HALF        ; KRX = (H - RXOVH) / 6, at least 1
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        GLO     RC
        SMI     RXOVH + 6
        GHI     RC
        SMBI    0
        LBDF    SU5
        LOAD    RC, 1
        LBR     SU6
SU5:    GLO     RC
        SMI     RXOVH
        PLO     RC
        GHI     RC
        SMBI    0
        PHI     RC
        LDI     0
        PLO     RD
        LOAD    RB, 6
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
SU6:    LOAD    RF, KRX
        GLO     RC
        ADI     0FFH
        PLO     RB
        GHI     RC
        ADCI    0
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        LOAD    RF, FREQ        ; UNIT = (24 x FREQ + 5 x WPM) / (10 x WPM)
        LDA     RF
        PHI     RA
        LDN     RF
        PLO     RA              ; RA = FREQ
        LDI     0
        PLO     RD
        PHI     RC
        PLO     RC
        LDI     24
        PLO     R9
SU7:    GLO     RA              ; RD.0:RC += RA, 24 times
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
        DEC     R9
        GLO     R9
        LBNZ    SU7
        LOAD    RF, WPM
        LDN     RF
        PLO     R9              ; R9.0 = WPM
        SHL                     ; + 5 x WPM (4 x + 1 x), so the division rounds
        SHL
        STR     R2
        GLO     R9
        ADD
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        GLO     RD
        ADCI    0
        PLO     RD
        GLO     R9              ; DVS = 10 x WPM (to 400)
        SHL
        SHL
        STR     R2
        GLO     R9
        ADD
        SHL
        PLO     RB
        LDI     0
        SHLC
        PHI     RB
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV             ; RC = UNIT
        LOAD    RF, UNIT        ; UNIT, then x2 x3 x4 x7
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        INC     RF
        GLO     RC              ; U2
        SHL
        PLO     RB
        GHI     RC
        SHLC
        PHI     RB
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        INC     RF
        GLO     RC              ; U3 = U2 + U
        STR     R2
        GLO     RB
        ADD
        PLO     RA
        GHI     RC
        STR     R2
        GHI     RB
        ADC
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        INC     RF
        GLO     RB              ; U4 = 2 x U2
        SHL
        PLO     RA
        GHI     RB
        SHLC
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        LOAD    RF, UNIT+1      ; the quiets less the work around them: QE = UNIT, QL = U2, QW = U4, less it.
        LDN     RF              ;  An even UNIT: a tone's last half-period is silent (TONE starts each with Q on),
        ANI     1               ;  so the gap after it is one half-period less as well
        LBNZ    SUQ
        LOAD    RF, HALF
        LDA     RF
        PHI     RC
        LDN     RF
        ADI     LOW(OVE)
        PLO     RC
        GHI     RC
        ADCI    HIGH(OVE)
        PHI     RC
        LBR     SUQ2
SUQ:    LOAD    RC, OVE
SUQ2:   SEP     R4
        DW      CYC2H
        LOAD    RF, UNIT
        LOAD    RD, QE
        SEP     R4
        DW      QSUB
        LOAD    RC, OVL
        SEP     R4
        DW      CYC2H
        LOAD    RF, U2
        LOAD    RD, QL
        SEP     R4
        DW      QSUB
        LOAD    RC, OVW
        SEP     R4
        DW      CYC2H
        LOAD    RF, U4
        LOAD    RD, QW
        SEP     R4
        DW      QSUB
        LOAD    RF, FREQ        ; DEB = FREQ / 100, at least 2
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        LDI     0
        PLO     RD
        LOAD    RB, 100
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        GLO     RC
        SMI     2
        LBDF    SU8
        LDI     2
        PLO     RC
SU8:    LOAD    RF, DEB
        GLO     RC
        STR     RF
        SEP     R5
; CYC2H: RC cycles -> RC half-periods, rounded
CYC2H:  LOAD    RF, HALF
        LDA     RF
        PHI     RB
        LDN     RF
        PLO     RB
        GHI     RB              ; + HALF / 2
        SHR
        PHI     RA
        GLO     RB
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
        LDI     0
        PLO     RD
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        SEP     R5
; QSUB: [RD] = [RF] - RC, at least 1
QSUB:   INC     RF
        LDN     RF
        STR     R2
        GLO     RC
        SD
        PLO     RA
        DEC     RF
        LDN     RF
        STR     R2
        GHI     RC
        SDB
        PHI     RA
        LBNF    QS1
        GLO     RA
        LBNZ    QS2
        GHI     RA
        LBNZ    QS2
QS1:    LOAD    RA, 1
QS2:    GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R5
; SETDVS: DVS = RB
SETDVS: LOAD    RF, DVS
        GHI     RB
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        SEP     R5

; =================================================================================================== sending
; SOUND: RF -> a word: that many half-periods; D = 1 a tone, 0 quiet. DF = 1: a key was pressed. Keeps RF (TONE
;   uses R7-R9, RA, RB).
SOUND:  PLO     RB
        LDA     RF
        PHI     R7
        LDN     RF
        DEC     RF
        ADI     0FFH
        PLO     R7
        GHI     R7
        ADCI    0
        PHI     R7
        GLO     RB              ; (keep the flag across the LOADs)
        PHI     RB
        LOAD    R9, KB
        LDA     R9
        PHI     R8
        LDA     R9
        PLO     R8
        LDN     R9
        PLO     RA
        GHI     RB
        PLO     RB
SO1:    SEP     R4
        DW      TONE
        LBNF    SO9
        GLO     R9              ; a key: Esc or Ctrl-C stops; any other is dropped and the tone goes on
        XRI     ESC
        LBZ     SO8
        XRI     18H             ; (Esc xor Ctrl-C)
        LBZ     SO8
        GHI     R7
        LBNZ    SO1
SO9:    LDI     0
        SHR
        SEP     R5
SO8:    LDI     1
        SHR
        SEP     R5
; SENDTXT: the text at RF, to a 0. Spaces, tabs, new lines: a word gap (one, however many). Each character shown as it
;   starts (-t: then its dots and dashes, as MORSETX). DF = 1: stopped by a key.
SENDTXT: LOAD   RD, LASTL     ; LASTL = 0, PENDW = 0
        LDI     0
        STR     RD
        INC     RD
        STR     RD
ST1:    LDA     RF
        LBZ     ST9
        PLO     RB
        XRI     0DH
        LBZ     ST1
        GLO     RB
        XRI     0AH
        LBZ     STWS
        GLO     RB
        XRI     09H
        LBZ     STWS
        GLO     RB
        XRI     20H
        LBZ     STWS
        GLO     RB              ; upper case
        SMI     'a'
        LBNF    ST2
        SMI     26
        LBDF    ST2
        GLO     RB
        SMI     20H
        PLO     RB
ST2:    GLO     RB              ; in the table?
        SMI     20H
        LBNF    ST1
        SMI     40H
        LBDF    ST1
        GLO     RB
        SMI     20H
        ADI     LOW(STBL)
        PLO     RD
        LDI     HIGH(STBL)
        ADCI    0
        PHI     RD
        LDN     RD
        LBZ     ST1             ; no Morse for it: passed over
        PLO     R8              ; (R8.0 = the code, briefly)
        LOAD    RD, ECODE
        GLO     R8
        STR     RD
        LOAD    RD, SCH         ; the character, kept (SOUND uses RB)
        GLO     RB
        STR     RD
        LOAD    RD, PENDW       ; a word gap waiting: sent now, as another letter follows
        LDN     RD
        LBZ     ST4
        LDI     0
        STR     RD
        GHI     RF
        STXD
        GLO     RF
        STXD
        LOAD    RF, QW
        LDI     0
        SEP     R4
        DW      SOUND
        IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        LBDF    ST8
ST4:    LOAD    RD, SCH         ; shown (-t: then a space, before its dots and dashes)
        LDN     RD
        SEP     R4
        DW      F_TYPE
        LOAD    RD, MODE
        LDN     RD
        XRI     'T'
        LBNZ    ST3
        LDI     20H
        SEP     R4
        DW      F_TYPE
ST3:    SEP     R4
        DW      SENDCH
        LBDF    ST8
        LOAD    RD, LASTL
        LDI     1
        STR     RD
        LOAD    RD, MODE        ; -t: a space after the dots and dashes
        LDN     RD
        XRI     'T'
        LBNZ    ST1
        LDI     20H
        SEP     R4
        DW      F_TYPE
        LBR     ST1
STWS:   GLO     RB              ; a new line in a file: shown
        XRI     0AH
        LBNZ    STW1
        SEP     R4
        DW      K_PCRLF
        LBR     STW2
STW1:   LOAD    RD, MODE
        LDN     RD
        XRI     'S'
        LBNZ    STW2
        LDI     20H
        SEP     R4
        DW      F_TYPE
STW2:   LOAD    RD, LASTL       ; a word gap (7 dots in all, 3 came after the letter): only if a letter follows
        LDN     RD
        LBZ     ST1
        LDI     0
        STR     RD
        INC     RD              ; PENDW
        LDI     1
        STR     RD
        LBR     ST1
ST8:    LDI     1
        SHR
        SEP     R5
ST9:    LDI     0
        SHR
        SEP     R5
; SENDCH: the code at ECODE (leading-1: A = %101) as dots and dashes, each followed by a dot's quiet, then 2 more.
;   -t: '.' or '-' shown as each starts. DF = 1: stopped. Keeps RF.
SENDCH: GHI     RF
        STXD
        GLO     RF
        STXD
        LOAD    RD, ECODE
        LDN     RD
        PLO     RB
        LDI     7
        PHI     RB
SC1:    GLO     RB              ; past the leading 1
        SHL
        LBDF    SC2
        PLO     RB
        GHI     RB
        SMI     1
        PHI     RB
        LBR     SC1
SC2:    STR     RD              ; ECODE = the elements, from the top bit
        INC     RD              ; ECNT
        GHI     RB
        STR     RD
SC3:    LOAD    RD, ECODE
        LDN     RD
        SHL
        STR     RD
        LBDF    SC4
        LOAD    RF, UNIT        ; a dot
        LDI     '.'
        LBR     SC5
SC4:    LOAD    RF, U3          ; a dash
        LDI     '-'
SC5:    PLO     RB
        LOAD    RD, MODE
        LDN     RD
        XRI     'T'
        LBNZ    SC6
        GLO     RB
        SEP     R4
        DW      F_TYPE
SC6:    LDI     1
        SEP     R4
        DW      SOUND
        LBDF    SC9
        LOAD    RF, QE          ; the dot's quiet after it
        LDI     0
        SEP     R4
        DW      SOUND
        LBDF    SC9
        LOAD    RD, ECNT
        LDN     RD
        SMI     1
        STR     RD
        LBNZ    SC3
        LOAD    RF, QL          ; the letter's end: 3 dots of quiet in all
        LDI     0
        SEP     R4
        DW      SOUND
SC9:    IRX
        LDXA
        PLO     RF
        LDX
        PHI     RF
        SEP     R5

; -s name: the file, sent
SFILE:  LOAD    RD, NAMEP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RA, BUF
        LOAD    RC, PTOP - BUF - 1
        SEP     R4
        DW      K_LOADF         ; RC = its bytes (not there, too big: said, and back to the prompt)
        GLO     RC
        ADI     LOW(BUF)
        PLO     RD
        GHI     RC
        ADCI    HIGH(BUF)
        PHI     RD
        LDI     0
        STR     RD
        SEP     R4
        DW      SPEED
        LOAD    RF, BUF
        SEP     R4
        DW      SENDTXT
        LBNF    SF9
        SEP     R4
        DW      K_PIN
        DB      0DH,0AH,'Stopped.',0
SF9:    SEP     R4
        DW      K_PCRLF
        LBR     DONE

; -t: lines typed, each sent
TTEXT:  SEP     R4
        DW      SPEED
        SEP     R4
        DW      K_PIN
        DB      'Type a line and press Enter to send it; an empty line (or Ctrl-C) ends.',0DH,0AH,0
TT1:    SEP     R4
        DW      K_PIN
        DB      '> ',0
        LOAD    RF, BUF
        LOAD    RC, 72
        SEP     R4
        DW      F_INPUTL
        LBDF    TT9
        SEP     R4
        DW      K_PCRLF
        LOAD    RF, BUF
        LDN     RF
        LBZ     TT9
        SEP     R4
        DW      SENDTXT
        LBNF    TT2
        SEP     R4
        DW      K_PIN
        DB      ' (stopped)',0
TT2:    SEP     R4
        DW      K_PCRLF
        LBR     TT1
TT9:    SEP     R4
        DW      K_PCRLF
        LBR     DONE

; SPEED: "N WPM, F Hz, M.MM MHz" shown
SPEED:  LOAD    RD, WPM
        LDN     RD
        PLO     RD
        LDI     0
        PHI     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' WPM, ',0
        LOAD    RF, FREQ
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' Hz, on an Elf2K at ',0
        LOAD    RF, C100
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        LDI     0
        PLO     RD
        LOAD    RB, 100
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV             ; RC = MHz, R9 = hundredths
        GLO     R9              ; RD = the hundredths (the output keeps RD), RC.1 = 1: a 0 first
        PLO     RD
        LDI     0
        PHI     RD
        GLO     R9
        SMI     10
        LDI     0
        SHLC
        XRI     1
        PHI     RC
        GLO     RC
        ADI     '0'
        SEP     R4
        DW      F_TYPE
        LDI     '.'
        SEP     R4
        DW      F_TYPE
        GLO     RD
        SMI     10
        LBDF    SP1
        LDI     '0'
        SEP     R4
        DW      F_TYPE
SP1:    SEP     R4
        DW      K_PDEC
        SEP     R4
        DW      K_PIN
        DB      ' MHz (-c)',0DH,0AH,0
        SEP     R5

; =================================================================================================== receiving
RFILE:  LOAD    RD, NAMEP       ; a good name? (said now, not after the keying)
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, PNAME
        SEP     R4
        DW      K_PARSE
        LBNF    RF1
        SEP     R4
        DW      K_PIN
        DB      'MORSE -r: not a name to save in (or no such folder).',0DH,0AH,0
        LBR     DONE
RF1:    SEP     R4
        DW      SPEED
        SEP     R4
        DW      K_PIN
        DB      'Listening on EF',0
        LOAD    RD, EFN
        LDN     RD
        ADI     '0'
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      K_PIN
        DB      ' - key away. It learns your speed as you go. Esc saves.',0DH,0AH,0
        LOAD    RD, AUDIO
        LDN     RD
        LBZ     RF4
        SEP     R4
        DW      K_PIN
        DB      '(-a: a sound module - no sidetone on Q, so it cannot hear itself.)',0DH,0AH,0
RF4:    SEP     R4
        DW      K_PCRLF
        LOAD    RD, EFN         ; the key's line: B1-B4 ($34-$37), -i BN1-BN4 ($3C-$3F), at KEYM, KEYG, KEYT
        LDN     RD
        ADI     33H
        PLO     RB
        LOAD    RD, INV
        LDN     RD
        LBZ     RF2
        GLO     RB
        ADI     8
        PLO     RB
RF2:    LOAD    RD, KEYM
        GLO     RB
        STR     RD
        LOAD    RD, KEYG
        GLO     RB
        STR     RD
        LOAD    RD, KEYT
        GLO     RB
        STR     RD
        LOAD    RD, AUDIO       ; -a: no sidetone (RXMQ: REQ); the gap's sound test is TGSUB's (KEYG: BR TGSUB)
        LDN     RD
        LBZ     RF3
        LOAD    RD, RXMQ
        LDI     7AH
        STR     RD
        LOAD    RD, KEYG
        LDI     30H
        STR     RD
        INC     RD
        LDI     LOW(TGSUB)
        STR     RD
RF3:    SEP     R4
        DW      RXTIME          ; the samples: how many a second, the dot, the hold
        LOAD    RF, UNIT        ; the averages start at the speed given: dot 1, dash 3; gaps 1, 3, 7
        SEP     R4
        DW      LDW
        LOAD    RF, DOT
        SEP     R4
        DW      STW
        LOAD    RF, GI
        SEP     R4
        DW      STW
        LOAD    RF, U3
        SEP     R4
        DW      LDW
        LOAD    RF, DASH
        SEP     R4
        DW      STW
        LOAD    RF, GL
        SEP     R4
        DW      STW
        LOAD    RF, U4          ; 7 = 4 + 3
        SEP     R4
        DW      LDW
        LOAD    RF, U3
        LDA     RF
        PHI     RB
        LDN     RF
        STR     R2
        GLO     RA
        ADD
        PLO     RA
        GHI     RB
        STR     R2
        GHI     RA
        ADC
        PHI     RA
        LOAD    RF, GW
        SEP     R4
        DW      STW
        LOAD    RD, CODE        ; CODE 1 (nothing), BAD, LETD, PHASE, LONG, COL 0
        LDI     1
        STR     RD
        INC     RD
        LDI     0
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        INC     RD
        STR     RD
        LOAD    RD, BPTR
        LDI     HIGH(BUF)
        STR     RD
        INC     RD
        LDI     LOW(BUF)
        STR     RD
        LOAD    RC, 0
        LOAD    R7, 0
        LOAD    R8, 0
        LBR     TOGAP

; MARKEND: the key came up (RC - DEB samples ago): a dot or a dash; then the gap
MARKEND: SEP    R4
        DW      LESSDEB         ; RC = the mark
        LOAD    RD, MSAV
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      CLASS
        LOAD    RD, VERB        ; -v: '.' or '-' and the mark's samples
        LDN     RD
        LBZ     MK1
        GLO     R9
        LBZ     MK0
        LDI     '-'
        LBR     MKP
MK0:    LDI     '.'
MKP:    SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      SHOWMS
MK1:    SEP     R4
        DW      THRESH          ; LET, WRD for this gap
        LOAD    RF, DEB         ; RC = DEB (the gap so far); R7 = LET - DEB, R8 = WRD - DEB (at least 1)
        LDN     RF
        PLO     RB
        LOAD    RF, LET
        SEP     R4
        DW      LDW
        SEP     R4
        DW      MINUSB
        GHI     RA
        PHI     R7
        GLO     RA
        PLO     R7
        LOAD    RF, WRD
        SEP     R4
        DW      LDW
        SEP     R4
        DW      MINUSB
        GHI     RA
        PHI     R8
        GLO     RA
        PLO     R8
        LDI     0
        PHI     RC
        GLO     RB
        PLO     RC
        LOAD    RD, PHASE
        LDI     0
        STR     RD
TOGAP:  LOAD    RD, STATE
        LDI     0
        STR     RD
        SEP     R4
        DW      LOOPREG
        LBR     RXG
; GAPEND: the key went down: the gap is learned; then the mark
GAPEND: SEP     R4
        DW      LESSDEB
        LOAD    RD, VERB        ; -v: '_' and the gap's samples
        LDN     RD
        LBZ     GE1
        LOAD    RD, MSAV
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LDI     '_'
        SEP     R4
        DW      F_TYPE
        SEP     R4
        DW      SHOWMS
        LOAD    RF, MSAV
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
GE1:    SEP     R4
        DW      LGAP
        LOAD    RD, PHASE
        LDI     0
        STR     RD
        INC     RD              ; LONG
        STR     RD
        LOAD    RF, DEB
        LDN     RF
        PLO     RC
        LDI     0
        PHI     RC
        LOAD    R7, 0
        LOAD    R8, 0
        LOAD    RD, STATE
        LDI     1
        STR     RD
        SEP     R4
        DW      LOOPREG
        LBR     RXM
; SHOWMS: MSAV in decimal, then a space (-v)
SHOWMS: LOAD    RF, MSAV
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R4
        DW      K_PDEC
        LDI     20H
        SEP     R4
        DW      F_TYPE
        SEP     R5
; RXTIME: the receive timing. Key: a sample a half-period of the tone (SETUP's KRX, UNIT, U3, U4): SR = 2 x FREQ.
;   -a: about SRAUD a second - K = (MCB / SRAUD - RXOVH) / 6, SR = MCB / (RXOVH + 6 K), and the dot UNIT, U3, U4 in
;   those samples. Then DEB = SR x the hold (-h, else -a 8 ms, the key 5 ms) / 1000, at least 2.
RXTIME: LOAD    RF, FREQ        ; SR = 2 x FREQ
        LDA     RF
        PHI     RA
        LDN     RF
        SHL
        PLO     RA
        GHI     RA
        SHLC
        PHI     RA
        LOAD    RD, AUDIO
        LDN     RD
        LBZ     RT9
        SEP     R4
        DW      LDMC            ; RD.0:RC = MCB
        LOAD    RB, SRAUD
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV             ; RC = cycles a sample wanted
        GLO     RC              ; K = (that - RXOVH) / 6, at least 1
        SMI     RXOVH + 6
        GHI     RC
        SMBI    0
        LBDF    RT1
        LOAD    RC, 1
        LBR     RT2
RT1:    GLO     RC
        SMI     RXOVH
        PLO     RC
        GHI     RC
        SMBI    0
        PHI     RC
        LDI     0
        PLO     RD
        LOAD    RB, 6
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
RT2:    GHI     RC              ; at least DGA + 1, so the gap loop can be DGA shorter (below)
        LBNZ    RT2A
        GLO     RC
        SMI     DGA + 1
        LBDF    RT2A
        LDI     DGA + 1
        PLO     RC
RT2A:   LOAD    RF, KRX         ; KRX = K + $FF
        GLO     RC
        ADI     0FFH
        PLO     RB
        GHI     RC
        ADCI    0
        STR     RF
        INC     RF
        GLO     RB
        STR     RF
        GLO     RC              ; RB = RXOVH + 6 K: the cycles a sample really
        SHL
        PLO     RB
        GHI     RC
        SHLC
        PHI     RB
        GLO     RC
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RC
        STR     R2
        GHI     RB
        ADC
        PHI     RB
        GLO     RB
        SHL
        PLO     RB
        GHI     RB
        SHLC
        PHI     RB
        GLO     RB
        ADI     RXOVH
        PLO     RB
        GHI     RB
        ADCI    0
        PHI     RB
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      LDMC
        SEP     R4
        DW      DIV             ; RC = SR
        GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA
        LOAD    RF, SR          ; (kept while the dot is worked out)
        GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        LDI     0               ; UNIT = (12 x SR + 5 x WPM) / (10 x WPM): 1.2 s / WPM in samples
        PLO     RD
        PHI     RC
        PLO     RC
        LDI     12
        PLO     R9
RT3:    GLO     RA
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
        DEC     R9
        GLO     R9
        LBNZ    RT3
        LOAD    RF, WPM
        LDN     RF
        PLO     R9
        SHL
        SHL
        STR     R2
        GLO     R9
        ADD
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     RC
        ADCI    0
        PHI     RC
        GLO     RD
        ADCI    0
        PLO     RD
        GLO     R9
        SHL
        SHL
        STR     R2
        GLO     R9
        ADD
        SHL
        PLO     RB
        LDI     0
        SHLC
        PHI     RB
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV             ; RC = UNIT
        LOAD    RF, UNIT        ; UNIT, U3 = 3 x, U4 = 4 x (what RFILE starts the averages from)
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        GLO     RC
        SHL
        PLO     RB
        GHI     RC
        SHLC
        PHI     RB
        LOAD    RF, U3
        GLO     RC
        STR     R2
        GLO     RB
        ADD
        PLO     RA
        GHI     RC
        STR     R2
        GHI     RB
        ADC
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        INC     RF              ; U4
        GLO     RB
        SHL
        PLO     RA
        GHI     RB
        SHLC
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        LOAD    RF, SR
        LDA     RF
        PHI     RA
        LDN     RF
        PLO     RA
RT9:    LOAD    RD, AUDIO       ; KRXG = KRX less DGK (a key) or DGA (-a): the gap loop's extra work - its counting
        LDN     RD              ;  down, TGSUB - so a sample takes as long in a gap as in a mark (measured in the sim)
        LBZ     RT9A
        LDI     DGA
        LBR     RT9B
RT9A:   LDI     DGK
RT9B:   PLO     RB
        LOAD    RF, KRX+1
        LDN     RF
        STR     R2
        GLO     RB
        SD                      ; KRX.lo - DG
        PLO     RC
        DEC     RF
        LDN     RF
        SMBI    0
        PHI     RC
        GHI     RC              ; below K = 1 ($0100): 1
        LBNZ    RT9C
        LOAD    RC, 0100H
RT9C:   LOAD    RF, KRXG
        GHI     RC
        STR     RF
        INC     RF
        GLO     RC
        STR     RF
        LOAD    RD, HOLD        ; DEB = SR x the hold / 1000 (RA = SR)
        LDN     RD
        LBNZ    RT10
        LOAD    RD, AUDIO
        LDN     RD
        LBZ     RT11
        LDI     8
        LBR     RT10
RT11:   LDI     5
RT10:   PLO     R9              ; R9.0 = ms
        LDI     0
        PLO     RD
        PHI     RC
        PLO     RC
RT12:   GLO     RA              ; RD.0:RC += SR, ms times
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
        DEC     R9
        GLO     R9
        LBNZ    RT12
        LOAD    RB, 1000
        SEP     R4
        DW      SETDVS
        SEP     R4
        DW      DIV
        GHI     RC              ; at most 255, at least 2
        LBZ     RT13
        LDI     255
        PLO     RC
RT13:   GLO     RC
        SMI     2
        LBDF    RT14
        LDI     2
        PLO     RC
RT14:   LOAD    RF, DEB
        GLO     RC
        STR     RF
        SEP     R5
; LDMC: RD.0:RC = MCB
LDMC:   LOAD    RF, MCB
        LDA     RF
        PLO     RD
        LDA     RF
        PHI     RC
        LDN     RF
        PLO     RC
        SEP     R5
; LOOPREG: RB = 0, RA.1 = DEB, RD = KRX (a mark: STATE 1) or KRXG (a gap), the UART's status selected
LOOPREG: LDI    0
        PLO     RB
        PHI     RB
        LOAD    RF, DEB
        LDN     RF
        PHI     RA
        LOAD    RF, STATE
        LDN     RF
        LBZ     LR1
        LOAD    RF, KRX
        LBR     LR2
LR1:    LOAD    RF, KRXG
LR2:
        LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        SEP     R5
; LESSDEB: RC -= DEB (the samples that confirmed the change), at least 1
LESSDEB: LOAD   RF, DEB
        LDN     RF
        STR     R2
        GLO     RC
        SM
        PLO     RC
        GHI     RC
        SMBI    0
        PHI     RC
        LBNF    LD1
        GLO     RC
        LBNZ    LD9
        GHI     RC
        LBNZ    LD9
LD1:    LOAD    RC, 1
LD9:    SEP     R5
; MINUSB: RA -= RB.0, at least 1
MINUSB: GLO     RB
        STR     R2
        GLO     RA
        SM
        PLO     RA
        GHI     RA
        SMBI    0
        PHI     RA
        LBNF    MB1
        GLO     RA
        LBNZ    MB9
        GHI     RA
        LBNZ    MB9
MB1:    LOAD    RA, 1
MB9:    SEP     R5

; LETEV: the gap passed LET: the letter is decoded and shown. After a word gap (PHASE 1) it means a long pause:
;   a new line, and the gap is not learned (LONG).
LETEV:  SEP     R4
        DW      SAVEREG
        LOAD    RD, PHASE
        LDN     RD
        LBNZ    LONGP
        SEP     R4
        DW      DECODE
        LBR     EVR2
LONGP:  INC     RD              ; LONG = 1
        LDI     1
        STR     RD
        LOAD    RD, COL
        LDN     RD
        LBZ     EVR2
        SEP     R4
        DW      NEWLN
EVR2:   SEP     R4
        DW      RESTREG
        LBR     RXG2
; WORDEV: the gap passed WRD: a space (or a new line past column 64) if a letter came since the last; then R7 counts
;   on to 2 word gaps (a long pause)
WORDEV: SEP     R4
        DW      SAVEREG
        LOAD    RD, LETD
        LDN     RD
        LBZ     WE2
        LDI     0
        STR     RD
        LOAD    RD, COL
        LDN     RD
        SMI     64
        LBNF    WE1
        SEP     R4
        DW      NEWLN
        LBR     WE2
WE1:    LDI     20H
        SEP     R4
        DW      PUTRX
WE2:    LOAD    RD, PHASE
        LDI     1
        STR     RD
        SEP     R4
        DW      RESTREG
        LOAD    RF, GW          ; R7 = GW (the gap now is WRD: on to WRD + GW, about 2 word gaps)
        SEP     R4
        DW      LDW
        GHI     RA
        PHI     R7
        GLO     RA
        PLO     R7
        LDI     0
        PHI     RA              ; (RA.1 = DEB again)
        LOAD    RF, DEB
        LDN     RF
        PHI     RA
        LBR     RXG4
; SAVEREG / RESTREG: R7, R8, RB.0, RC around an event (the output may be a file); RESTREG also LOOPREG
SAVEREG: LOAD   RD, SAVR
        GHI     R7
        STR     RD
        INC     RD
        GLO     R7
        STR     RD
        INC     RD
        GHI     R8
        STR     RD
        INC     RD
        GLO     R8
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5
RESTREG: LOAD   RD, SAVR
        LDA     RD
        PHI     R7
        LDA     RD
        PLO     R7
        LDA     RD
        PHI     R8
        LDA     RD
        PLO     R8
        INC     RD
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, SAVR+4
        LDN     RD
        PLO     R9              ; (LOOPREG clears RB; put RB.0 back after)
        SEP     R4
        DW      LOOPREG
        GLO     R9
        PLO     RB
        SEP     R5
; DECODE: CODE -> the character (RTBL), '*' if none or more than 6 elements; shown and kept. CODE = 1 again.
DECODE: LOAD    RD, CODE
        LDN     RD
        XRI     1
        LBZ     DC9             ; nothing keyed
        LDN     RD
        PLO     RB
        INC     RD              ; BAD
        LDN     RD
        LBNZ    DC1
        GLO     RB
        ADI     LOW(RTBL)
        PLO     RD
        LDI     HIGH(RTBL)
        ADCI    0
        PHI     RD
        LDN     RD
        LBNZ    DC2
DC1:    LDI     '*'
DC2:    SEP     R4
        DW      PUTRX
        LOAD    RD, CODE
        LDI     1
        STR     RD
        INC     RD              ; BAD
        LDI     0
        STR     RD
        INC     RD              ; LETD
        LDI     1
        STR     RD
DC9:    SEP     R5
; PUTRX: D shown, and kept at BPTR while there is room; COL + 1
PUTRX:  PLO     RB
        LOAD    RD, PCH
        GLO     RB
        STR     RD
        SEP     R4
        DW      F_TYPE
        LOAD    RD, PCH
        LDN     RD
        SEP     R4
        DW      KEEP
        LOAD    RD, COL
        LDN     RD
        ADI     1
        STR     RD
        SEP     R5
NEWLN:  SEP     R4
        DW      K_PCRLF
        LDI     0AH
        SEP     R4
        DW      KEEP
        LOAD    RD, COL
        LDI     0
        STR     RD
        SEP     R5
; KEEP: D at BPTR, while BPTR is below PTOP - 1
KEEP:   PLO     RB
        LOAD    RD, BPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     RF
        XRI     HIGH(PTOP - 1)
        LBNZ    KP1
        GLO     RF
        XRI     LOW(PTOP - 1)
        LBZ     KP9
KP1:    GLO     RB
        STR     RF
        INC     RF
        GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
KP9:    SEP     R5

; RXKEY: a key on the terminal: Esc or Ctrl-C ends; any other is passed over
RXKEY:  LDI     10H
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        XRI     ESC
        LBZ     RXSTOP
        XRI     18H             ; (Esc xor Ctrl-C)
        LBZ     RXSTOP
        LDI     15H
        STR     R2
        OUT     SELPORT
        DEC     R2
        LOAD    RF, STATE
        LDN     RF
        LBZ     RXG
        LBR     RXM
RXSTOP: REQ
        SEP     R4              ; a letter still keyed: decoded
        DW      DECODE
        SEP     R4
        DW      K_PCRLF
TR1:    LOAD    RD, BPTR        ; spaces and new lines at the end taken off
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        GHI     RF
        XRI     HIGH(BUF)
        LBNZ    TR2
        GLO     RF
        XRI     LOW(BUF)
        LBZ     TR9
TR2:    DEC     RF
        LDN     RF
        XRI     20H
        LBZ     TR3
        LDN     RF
        XRI     0AH
        LBNZ    TR9
TR3:    GLO     RF
        STR     RD
        DEC     RD
        GHI     RF
        STR     RD
        LBR     TR1
TR9:    LOAD    RD, BPTR        ; RC = what was kept
        LDA     RD
        PHI     RC
        LDN     RD
        SMI     LOW(BUF)
        PLO     RC
        GHI     RC
        SMBI    HIGH(BUF)
        PHI     RC
        GLO     RC
        LBNZ    RS1
        GHI     RC
        LBNZ    RS1
        SEP     R4
        DW      K_PIN
        DB      'Nothing received - no file saved.',0DH,0AH,0
        LBR     DONE
RS1:    LDI     0AH             ; the last line ended
        SEP     R4
        DW      KEEP
        INC     RC
        LOAD    RD, NAMEP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RA, BUF
        SEP     R4
        DW      K_SAVEF         ; (asks before replacing; never returns)

; ---- CLASS: RC = a mark: a dot if below (DOT + DASH) / 2, else a dash; that average moves a quarter of the way to
;      it (a mark over 2 dashes counts as 2 dashes); the dash is kept between 2 and 4 dots; CODE takes the element.
CLASS:  LOAD    RF, DOT
        LOAD    RD, DASH
        SEP     R4
        DW      SUMHALF         ; RA = MID
        GLO     RA
        STR     R2
        GLO     RC
        SM
        GHI     RA
        STR     R2
        GHI     RC
        SMB
        LBNF    CDOT
        LOAD    RF, DASH        ; a dash: at most 2 dashes learned
        SEP     R4
        DW      LDW
        GLO     RA
        SHL
        PLO     RA
        GHI     RA
        SHLC
        PHI     RA
        GLO     RA              ; RC = min(RC, 2 x DASH)
        STR     R2
        GLO     RC
        SM
        GHI     RA
        STR     R2
        GHI     RC
        SMB
        LBNF    CL1
        GHI     RA
        PHI     RC
        GLO     RA
        PLO     RC
CL1:    LOAD    RF, DASH
        SEP     R4
        DW      AVG4
        LDI     1
        LBR     CL2
CDOT:   LOAD    RF, DOT
        SEP     R4
        DW      AVG4
        LDI     0
CL2:    PLO     R9              ; R9.0 = the element
        LDI     16              ; DASH at most 4 dots: else 3
        SEP     R4
        DW      DOTK            ; RC = 4 dots
        LOAD    RF, DASH
        SEP     R4
        DW      LDW
        SEP     R4
        DW      RCLTRA          ; DF = 1: RC < RA (DASH over 4 dots)
        LBNF    CL3
        LDI     12
        LBR     CL4
CL3:    LDI     8               ; at least 2 dots
        SEP     R4
        DW      DOTK
        SEP     R4
        DW      RCLTRA
        LBDF    CL5
        LDI     8
CL4:    SEP     R4
        DW      DOTK
        GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA
        LOAD    RF, DASH
        SEP     R4
        DW      STW
CL5:    LOAD    RD, CODE        ; CODE x 2 + the element; a 7th element: BAD
        LDN     RD
        SMI     64
        LBDF    CL6
        LDN     RD
        SHL
        STR     R2
        GLO     R9
        ADD
        STR     RD
        SEP     R5
CL6:    INC     RD
        LDI     1
        STR     RD
        SEP     R5

; THRESH: LET = (GI + GL) / 2, at most 2.75 dots; WRD = (GL + GW) / 2, between 4.5 and 6.5 dots
THRESH: LOAD    RF, GI
        LOAD    RD, GL
        SEP     R4
        DW      SUMHALF
        LDI     11
        SEP     R4
        DW      DOTK
        SEP     R4
        DW      MINRA
        LOAD    RF, LET
        SEP     R4
        DW      STW
        LOAD    RF, GL
        LOAD    RD, GW
        SEP     R4
        DW      SUMHALF
        LDI     18
        SEP     R4
        DW      DOTK
        SEP     R4
        DW      MAXRA
        LDI     26
        SEP     R4
        DW      DOTK
        SEP     R4
        DW      MINRA
        LOAD    RF, WRD
        SEP     R4
        DW      STW
        SEP     R5

; LGAP: RC = a gap, learned as inside a letter (below LET), between letters (below WRD) or between words (below
;   2 x GW); not after a long pause
LGAP:   LOAD    RF, LONG
        LDN     RF
        LBNZ    LG9
        LOAD    RF, LET
        SEP     R4
        DW      LDW
        SEP     R4
        DW      RCLTRA
        LBNF    LG1
        LOAD    RF, GI
        LBR     LG8
LG1:    LOAD    RF, WRD
        SEP     R4
        DW      LDW
        SEP     R4
        DW      RCLTRA
        LBNF    LG2
        LOAD    RF, GL
        LBR     LG8
LG2:    LOAD    RF, GW
        SEP     R4
        DW      LDW
        GLO     RA
        SHL
        PLO     RA
        GHI     RA
        SHLC
        PHI     RA
        SEP     R4
        DW      RCLTRA
        LBNF    LG9
        LOAD    RF, GW
LG8:    SEP     R4
        DW      AVG4
LG9:    SEP     R5

; ---- 16-bit helpers (words high byte first). LDW: RA = [RF]; STW: [RF] = RA
LDW:    LDA     RF
        PHI     RA
        LDN     RF
        PLO     RA
        DEC     RF
        SEP     R5
STW:    GHI     RA
        STR     RF
        INC     RF
        GLO     RA
        STR     RF
        DEC     RF
        SEP     R5
; RCLTRA: DF = 1 if RC < RA
RCLTRA: GLO     RA
        STR     R2
        GLO     RC
        SM
        GHI     RA
        STR     R2
        GHI     RC
        SMB
        LBDF    RL0
        LDI     1
        SHR
        SEP     R5
RL0:    LDI     0
        SHR
        SEP     R5
; MINRA: RA = min(RA, RC); MAXRA: RA = max(RA, RC)
MINRA:  SEP     R4
        DW      RCLTRA
        LBNF    MM9
MM1:    GHI     RC
        PHI     RA
        GLO     RC
        PLO     RA
MM9:    SEP     R5
MAXRA:  SEP     R4
        DW      RCLTRA
        LBDF    MM9
        LBR     MM1
; SUMHALF: RA = ([RF] + [RD]) / 2
SUMHALF: INC    RF
        INC     RD
        LDN     RD
        STR     R2
        LDN     RF
        ADD
        PLO     RA
        DEC     RF
        DEC     RD
        LDN     RD
        STR     R2
        LDN     RF
        ADC
        PHI     RA
        GHI     RA
        SHRC
        PHI     RA
        GLO     RA
        SHRC
        PLO     RA
        SEP     R5
; AVG4: [RF] = (3 x [RF] + RC) / 4
AVG4:   LDA     RF
        PHI     R8
        LDN     RF
        PLO     R8
        DEC     RF
        GLO     R8              ; RB = 3 x
        SHL
        PLO     RB
        GHI     R8
        SHLC
        PHI     RB
        GLO     R8
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     R8
        STR     R2
        GHI     RB
        ADC
        PHI     RB
        GLO     RC              ; + RC (a 17th bit into the halving)
        STR     R2
        GLO     RB
        ADD
        PLO     RB
        GHI     RC
        STR     R2
        GHI     RB
        ADC
        PHI     RB
        GHI     RB
        SHRC
        PHI     RB
        GLO     RB
        SHRC
        PLO     RB
        GHI     RB
        SHR
        PHI     RB
        GLO     RB
        SHRC
        STR     R2
        INC     RF
        STR     RF
        DEC     RF
        GHI     RB
        STR     RF
        SEP     R5
; DOTK: RC = DOT x D / 4
DOTK:   PLO     RB
        LOAD    RF, DOT
        LDA     RF
        PHI     R8
        LDN     RF
        PLO     R8
        LDI     0
        PHI     RC
        PLO     RC
DK1:    GLO     RB
        LBZ     DK9
        SHR
        PLO     RB
        LBNF    DK2
        GLO     R8
        STR     R2
        GLO     RC
        ADD
        PLO     RC
        GHI     R8
        STR     R2
        GHI     RC
        ADC
        PHI     RC
DK2:    GLO     R8
        SHL
        PLO     R8
        GHI     R8
        SHLC
        PHI     R8
        LBR     DK1
DK9:    GHI     RC
        SHR
        PHI     RC
        GLO     RC
        SHRC
        PLO     RC
        GHI     RC
        SHR
        PHI     RC
        GLO     RC
        SHRC
        PLO     RC
        SEP     R5

; ---- DIV (PLAY's): RD.0:RC (24 bits) / DVS (16) -> RD.0:RC, the remainder in R9. Uses R7, RA, RB.0, RF.1.
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

        INCL    "numarg.inc"
        INCL    "morsetab.inc"
PEND:
C100:   DS      2               ; (START sets these seven in order)
WPM:    DS      1
FREQ:   DS      2
EFN:    DS      1
MODE:   DS      1               ; 'S' 'T' 'R'
VERB:   DS      1               ; -v
AUDIO:  DS      1               ; -a
INV:    DS      1               ; -i
HOLD:   DS      1               ; -h ms (0: the default)
NAMEP:  DS      2
PNAME:  DS      11
DVS:    DS      2
MCB:    DS      3               ; machine cycles a second
SR:     DS      2               ; -r: samples a second
HALF:   DS      2               ; the half-period, machine cycles
KB:     DS      2               ; (FRAC follows it)
FRAC:   DS      1
KRX:    DS      2
KRXG:   DS      2               ; the gap loop's delay
UNIT:   DS      2               ; half-periods: a dot  (U2 U3 U4 follow it)
U2:     DS      2
U3:     DS      2
U4:     DS      2
DEB:    DS      1
QE:     DS      2
QL:     DS      2
QW:     DS      2
LASTL:  DS      1               ; (PENDW follows it)
PENDW:  DS      1
SCH:    DS      1
ECODE:  DS      1               ; (ECNT follows it)
ECNT:   DS      1
DOT:    DS      2               ; the receiver's averages, samples
DASH:   DS      2
GI:     DS      2
GL:     DS      2
GW:     DS      2
LET:    DS      2
WRD:    DS      2
CODE:   DS      1               ; (BAD LETD PHASE LONG COL follow it, RFILE sets them in order)
BAD:    DS      1
LETD:   DS      1
PHASE:  DS      1
LONG:   DS      1
COL:    DS      1
STATE:  DS      1
BPTR:   DS      2
SAVR:   DS      7
MSAV:   DS      2
PCH:    DS      1
BUF:
        END
