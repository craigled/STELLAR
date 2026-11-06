; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; shstate.inc - SH's state, kept while a script's commands run (no program writes below $3000): sh.asm and
; shstub.asm. $2E00-$2E97 the re-entry stub (shstub.asm, copied there by SH); $2E98-$2EFF the state below; the
; variables from the kernel's last variable ($2F36, KS_KVEND) to $2FFF. ($2E00-$2EFF is STLCHK's at the boot only.)
SHSTUB  EQU     2E00H           ; the stub (152 bytes at most: shstub.asm)
SHLO    EQU     4000H           ; SH.PRG: its code from here (the stub sums $4000 .. SEND)
SHNEXTA EQU     4003H           ; SH's "on with the script" entry
ST      EQU     2E98H
SMAGIC  EQU     ST + 0          ; 'S': a script is running
SSUM    EQU     ST + 1          ; (2) the sum of SH's code, $4000 .. SEND
SEND    EQU     ST + 3          ; (2) SH's code's size, in 8s (its variables after it are not summed)
SFST    EQU     ST + 5          ; (7) the kernel's FCLUS FSEC FREM before the sector the current line starts in
SSOFF   EQU     ST + 12         ; (2) where in that sector the line starts
SLNO    EQU     ST + 14         ; (2) the current line's number
SRES    EQU     ST + 16         ; (1) where in the line to go on (after an outside command)
SIFSP   EQU     ST + 17         ; (1) ifs open
SIFS    EQU     ST + 18         ; (8) each: 1 the condition, 2 running, 3 skipping, 4 done, 5 skipped (inside a skip)
SFLAGS  EQU     ST + 26         ; (1) bit 0: -x (each command shown)
SARGN   EQU     ST + 27         ; (1) $#
SARGO   EQU     ST + 28         ; (10) where $0 .. $9 start in SARGT (0: none)
SSTAT   EQU     ST + 38         ; (1) $?: the last command's status
SRELD   EQU     ST + 39         ; (1) 1: the stub had the kernel run SH.PRG again (its RAM was used)
SKEY    EQU     ST + 40         ; (1) a key typed while the script ran (not Ctrl-C): read takes it first (0: none)
SARGT   EQU     ST + 41         ; (63) their texts, each 0-ended - to $2F00
SARGE   EQU     2F00H
; $7E00-$7EFF (free while LTOS runs: the stack ends at $7DFF; only STELLAR, once started, uses it): the loops
LS      EQU     7E00H
LSP     EQU     LS + 0          ; (1) loops open
SCONN   EQU     LS + 1          ; (1) how the command running joins the next: 0 ; or the line's end, 1 &&, 2 ||
SNEG    EQU     LS + 2          ; (1) 1: the outside command running had a "!" before it ($? turned round)
LFR     EQU     LS + 16         ; the loops: 16 bytes each, 6 at most - kind (1 while, 2 until, 3 for), state
                                ;  (1 the condition, 2 running, 3 ended, 4 break, 5 continue, 6 skipped, 7 back
                                ;  to its start), for's next item, then where its keyword is: SFST SSOFF SLNO (11)
                                ;  and the offset in the line
LMAX    EQU     6
SCAP    EQU     LS + 3          ; (1) 1: a $(...)'s output is in /_SHOUT.TMP, for the command being done again
; $7E70-$7EFF: the functions - FNN (1) how many, then FNMAX of 20 bytes: the name (8, 0 after it), where the body
; starts (12: SFST SSOFF SLNO, the offset in the line)
FNN     EQU     7E70H
FNT     EQU     7E71H
FNMAX   EQU     6
; $7650-$76FF (the kernel's HIST only ever holds 80 bytes, from $7600; nothing else uses this): the calls -
; functions, . files, scripts run from a script. CSN (1) = the bytes used; then each call: its kind (1 a function,
; 2 a . file, 3 a script), where to go on after it (SFST SSOFF SLNO SRES: 12), SCONN, LSP, SIFSP, $# and $0-$9's
; places (11), the texts' length n and the texts, then the call's size (29 + n)
CSN     EQU     7650H
CSB     EQU     7651H
CSROOM  EQU     0AFH
