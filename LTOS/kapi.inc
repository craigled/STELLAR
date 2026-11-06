; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; kapi.inc - the LTOS kernel's calls for programs (the jump table at $0309). SEP R4 / DW K_xxx.
K_MAIN   EQU    0309H           ; back to the LTOS> prompt (from any depth)
K_LOADF  EQU    030CH           ; RF -> a file name, RA = where, RC = the most bytes -> RC = bytes, RF past it
K_SAVEF  EQU    030FH           ; RF -> a file name, RA = the data, RC = its bytes: saved; never returns
K_PIN    EQU    0312H           ; the text after the call
K_PDEC   EQU    0315H           ; RD in decimal
K_PHEX4  EQU    0318H           ; RD in hex
K_PHEX2  EQU    031BH           ; D in hex
K_PCRLF  EQU    031EH           ; a new line
K_SKIPSP EQU    0321H           ; RF past spaces
K_HEXARG EQU    0324H           ; RF -> a hex number -> RD (DF = 1: none)
K_YESNO  EQU    0327H           ; a key: DF = 1 if Y
K_PARSE  EQU    032AH           ; RF -> a name -> 11 bytes at RD (DF = 1: not a name)
K_STAMP  EQU    032DH           ; (2 bytes) the kernel's build stamp
K_SAVER  EQU    032FH           ; RD -> an 11-byte name, RA = data, RC = bytes: saved, replacing, and returns
                                ;  DF = 0, or DF = 1 + D: 1 directory full, 2 card full, 3 card failed, 4 folder
K_OUT    EQU    0332H           ; D to the output (the screen, or a file)  (LTOS-SH)
K_TTY    EQU    0335H           ; D to the screen, always
K_IN     EQU    0338H           ; a key (the keyboard, or a file) -> D
K_TTYON  EQU    033BH           ; the output to the screen until the next K_YESNO's answer (a question)
K_RDIR   EQU    033EH           ; (a byte) 0: the output goes to the screen; 1 a file; 2 nowhere (> NUL)
K_STAT   EQU    033FH           ; (a byte) the exit status of the command (0 = all right)
K_EXEC   EQU    0340H           ; (LBR to it) run the command line at LINE (up to 255), then MAIN as after any command
K_SHHOOK EQU    0343H           ; (3 bytes) 0: no script; else LBR hh ll - MAIN goes there after a command
PTOP     EQU    6C00H           ; programs end below here (LTOS's buffers start)
