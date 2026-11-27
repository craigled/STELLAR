; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; lc.inc - LC's names, shared by LC.PRG (lc.asm) and LC.OVL's parts (lcov0.asm, lcov1.asm).
ESC     EQU     1BH
RECSZ   EQU     22
ROWS    EQU     18              ; the lines of names in a pane (screen rows 3-20)
; memory: LC.PRG (the core) $3000-$45FF; a part of LC.OVL $4600-$57FF; the indexes; the records of both panes
; in one pool (the left's from its bottom up, the right's from its top down); keys, a path, lines; View's pages
CORETOP EQU     4600H           ; the core ends below here (build.py checks)
OVLA    EQU     4600H           ; LC.OVL's part loaded here: [DW the core's PEND, DB its number, LBR .., LBR ..]
OVSECS  EQU     9               ; a part's sectors (4,608 bytes: to $57FF)
IDX0    EQU     5800H           ; the indexes (a page each: its low byte is the entry)
IDX1    EQU     5900H
POOL    EQU     5A00H           ; the records: the left pane's record i at POOL + 22i, the right's at POOLE - 22(i + 1)
POOLE   EQU     6A00H
POOLN   EQU     (POOLE - POOL) / RECSZ
PMAX    EQU     160             ; at most this many for one pane (the other keeps room)
RING    EQU     6A00H           ; the keys (32, page-aligned)
VPATHB  EQU     6A40H           ; View / Info: the file's path (80)
NUMB    EQU     6AA0H           ; a number as text (12)
SEQB    EQU     6AC0H           ; what came after an Esc (16)
HBUF    EQU     6AE0H           ; View: a hex line's 16 bytes
LBUF    EQU     6B00H           ; a line built (up to 255; page-aligned: its low byte is the column)
VPT     EQU     7700H           ; View: where each page starts (VPMAX x 10: the kernel's FCLUS FSEC FREM, the
                                ; offset in that sector (2), the flags) - in LTOS's free $7700-$7BFF
VPMAX   EQU     128
; a pane's fields
P_CLUS  EQU     0               ; (2) its folder: 0 the root, else its first cluster
P_N     EQU     2               ; the records
P_TOP   EQU     3               ; the entry on its first line
P_CUR   EQU     4               ; the cursor's entry
P_MORE  EQU     5               ; 1: the folder had more than the pane could hold
P_UP    EQU     6               ; 1: a ".." record (not the root)
P_IDXH  EQU     7               ; its index's page
P_RECH  EQU     8               ; (not used)
P_COL   EQU     9               ; the screen column of its left side
P_NUM   EQU     10              ; 0 left, 1 right
P_PATH  EQU     11              ; its path ("/", "/BIN/GAMES"), 0-ended
PATHL   EQU     60
PSZ     EQU     P_PATH + PATHL + 4
; keys as KEY gives them
KUP     EQU     80H
KDN     EQU     81H
KLT     EQU     82H
KRT     EQU     83H
KPU     EQU     84H
KPD     EQU     85H
KHM     EQU     86H
KEN     EQU     87H
KINS    EQU     88H
KDEL    EQU     89H
