; Copyright (C) 2026 Craig Ledbetter
; SPDX-License-Identifier: GPL-3.0-or-later
; contacts.asm - CONTACTS.PRG: an address book in a plain text file.
;
;   CONTACTS                    add a contact: it asks for each field (Enter: left empty; Esc: nothing added)
;   CONTACTS word ...           show the contacts that have every word (in any field's value; any case)
;   CONTACTS -f FIELD word ...  ... in that field only (CITY, TEL ... ; -f ADDRESS also looks in ADDRESS2)
;   CONTACTS -l [word ...]      the names only (all of them with no word)
;   CONTACTS -d word ...        delete: each contact found is shown and asked about (Y, N, Q: no more questions)
;   CONTACTS -e word ...        edit: the same; Y asks each field again with its value to change (Enter keeps it)
;   -b file                     another book (/CONTACTS.TXT when not said); -a: add (as with no words)
;   "two words"                 one word with a space in it
;
; The book (/CONTACTS.TXT): one "FIELD: value" a line, a blank line after each contact - TYPE shows it, NANO
; edits it, GREP / SED / RAWK work on it (RAWK: RS = "" takes a contact as a record):
;
;   NAME: Ada Lovelace
;   ADDRESS: 12 St James's Square
;   ADDRESS2:
;   CITY: London
;   STATE/CO: Middlesex
;   POSTCODE: SW1Y 4LE
;   COUNTRY: England
;   TEL: 555 0100
;   EMAIL: ada@example.com
;   BDAY: 10 December
;   NOTE: the first programmer
;
; A contact typed in has all eleven fields (an empty one: "ADDRESS2:"); shown, the empty ones are left out. Lines
; of other fields (WEB: ..., added with NANO) are kept and searched; a line with no ':' is all value. Lines end
; CR LF; when CONTACTS writes the book it writes it that way (LF alone, or blank lines more than one, tidied).
; Search results are in the book's own form, so CONTACTS LONDON > LONDON.TXT makes a smaller book.
;
; Any size: the book is read a sector at a time (KS_FREAD), and a change (add, delete, edit) writes a new copy
; a sector at a time (XFER's writer, as ASM's), the old one's clusters freed only once the new entry is in -
; so a power cut loses nothing. One contact up to 3,840 bytes; a longer one (NANO) is copied as it is, not
; searched. A value typed: 70 characters at most.
;
; Memory: the code and variables $3000-$4FFF; a sector to write $5000; the contact read $5200-$61FF; the contact
; typed $6200-$6AFF; the line typed $6B00. verify_contacts.py runs it on the simulated Elf2K.
        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

VMAX    EQU     70              ; a value typed: this many characters at most
OUTB    EQU     5000H           ; a sector to write (page-aligned)
RECB    EQU     5200H           ; a contact as read: its lines (LF after each), a 0 after the last (page-aligned)
RBTOP   EQU     6100H           ; ... a character more than this far: the contact is too big
NEWB    EQU     6200H           ; a contact typed or edited
NBTOP   EQU     6B00H
LBUF    EQU     6B00H           ; a line typed (VMAX + 1)

        ORG     PRGORG - 6
        DW      PRGORG, PEND - PRGORG, START
        ORG     PRGORG
        DB      'VER:1.0',0
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
        LOAD    RD, VARS        ; the variables: 0
        LOAD    RC, VEND - VARS
ST0:    LDI     0
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    ST0
        GHI     RC
        LBNZ    ST0
        LOAD    RD, K_STAT
        LDI     0
        STR     RD
        LOAD    RA, DEFBK       ; /CONTACTS.TXT unless -b
        LOAD    RD, BOOK
ST1:    LDA     RA
        STR     RD
        INC     RD
        LBNZ    ST1
        LOAD    RD, WEND
        LDI     HIGH(WORDS)
        STR     RD
        INC     RD
        LDI     LOW(WORDS)
        STR     RD
; ---- the words typed
AR1:    SEP     R4
        DW      K_SKIPSP
        LDN     RF
        LBZ     AR9
        XRI     '-'
        LBNZ    AWORD
        INC     RF
        LDA     RF
        ANI     0DFH            ; (upper case)
        PLO     RB
        LDN     RF              ; one letter
        LBZ     AR2
        XRI     ' '
        LBNZ    USAGE
AR2:    GLO     RB
        XRI     'F'
        LBZ     AFLD
        GLO     RB
        XRI     'B'
        LBZ     ABOOK
        LDI     2
        PLO     RC
        GLO     RB
        XRI     'D'
        LBZ     AMODE
        INC     RC
        GLO     RB
        XRI     'E'
        LBZ     AMODE
        INC     RC
        GLO     RB
        XRI     'L'
        LBZ     AMODE
        INC     RC
        GLO     RB
        XRI     'A'
        LBZ     AMODE
        LBR     USAGE
AMODE:  LOAD    RD, MODE
        GLO     RC
        STR     RD
        LBR     AR1
AFLD:   SEP     R4              ; -f FIELD (upper case, 15 at most)
        DW      K_SKIPSP
        LDN     RF
        LBZ     USAGE
        LOAD    RD, FIELD
        LDI     15
        PLO     RC
AF1:    LDN     RF
        LBZ     AF9
        XRI     ' '
        LBZ     AF9
        LDN     RF
        XRI     ':'
        LBZ     AF9
        LDA     RF
        SEP     R4
        DW      UPC
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    AF1
AF9:    LDI     0
        STR     RD
AF8:    LDN     RF              ; (the rest of the word)
        LBZ     AR1
        XRI     ' '
        LBZ     AR1
        INC     RF
        LBR     AF8
ABOOK:  SEP     R4              ; -b file
        DW      K_SKIPSP
        LDN     RF
        LBZ     USAGE
        LOAD    RD, BOOK
        LDI     63
        PLO     RC
AB1:    LDN     RF
        LBZ     AB9
        XRI     ' '
        LBZ     AB9
        LDA     RF
        STR     RD
        INC     RD
        DEC     RC
        GLO     RC
        LBNZ    AB1
AB9:    LDI     0
        STR     RD
        LBR     AF8
AWORD:  LOAD    RD, WEND        ; a word: upper case, at WEND; "..." keeps spaces
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LDI     0
        PLO     R8              ; its length
        LDN     RF
        XRI     '"'
        LBNZ    AW2
        INC     RF
        LDI     '"'
        LSKP
AW2:    LDI     ' '
        PLO     RB              ; the character that ends it
AW3:    LDN     RF
        LBZ     AW8
        STR     R2
        GLO     RB
        XOR
        LBZ     AW7
        GLO     RC              ; room? (WORDS: 128)
        SMI     LOW(WORDS + 126)
        GHI     RC
        SMBI    HIGH(WORDS + 126)
        LBDF    USAGE
        LDA     RF
        SEP     R4
        DW      UPC
        STR     RC
        INC     RC
        INC     R8
        LBR     AW3
AW7:    INC     RF
AW8:    GLO     R8              ; ("" is no word)
        LBZ     AR1
        LDI     0
        STR     RC
        INC     RC
        STR     RC              ; (a 0 after the last)
        LOAD    RD, WEND
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    RD, NWORDS
        LDN     RD
        ADI     1
        STR     RD
        LBR     AR1
; ---- what to do
AR9:    LOAD    RD, MODE
        LDN     RD
        LBNZ    AR91
        LOAD    RD, NWORDS      ; no -d -e -l -a: words - a search; none - add
        LDN     RD
        LBNZ    AR90
        LOAD    RD, FIELD
        LDN     RD
        LBNZ    USAGE
        LDI     5
        LSKP
AR90:   LDI     1
        PLO     RC
        LOAD    RD, MODE
        GLO     RC
        STR     RD
AR91:   LOAD    RD, MODE        ; -d / -e: which ones?
        LDN     RD
        SMI     2
        LBZ     AR93
        SMI     1
        LBNZ    AR95
AR93:   LOAD    RD, NWORDS
        LDN     RD
        LBZ     USAGE
AR95:   LOAD    RD, MODE        ; TTYF: the contacts to the screen, not the output (all but a search)
        LDN     RD
        SMI     1
        LBZ     AR96
        SMI     3
        LBZ     AR96
        LOAD    RD, TTYF
        LDI     1
        STR     RD
AR96:   SEP     R4              ; the book's name
        DW      PARSEBK
        LOAD    RD, MODE
        LDN     RD
        SMI     5
        LBZ     ADD
        LOAD    RD, FN11        ; is it there?
        SEP     R4
        DW      KS_FINDN
        LBDF    NOBOOK
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    BADBK
        LOAD    RD, MODE
        LDN     RD
        SMI     2
        LBZ     REWR
        SMI     1
        LBZ     REWR
; ==== a search (MODE 1) or names (4)
SEARCH: SEP     R4
        DW      KS_FOPEN
        LOAD    RD, HAVE
        LDI     1
        STR     RD
SE1:    SEP     R4
        DW      RDREC
        LBDF    SE9
        LOAD    RD, NREC
        SEP     R4
        DW      INC16
        LOAD    RD, BIG         ; too big: past it
        LDN     RD
        LBZ     SE2
        SEP     R4
        DW      RESTREC
        LBR     SE1
SE2:    SEP     R4
        DW      MATCH
        LBNF    SE1
        LOAD    RD, NFOUND
        SEP     R4
        DW      INC16
        LOAD    RD, MODE
        LDN     RD
        XRI     4
        LBZ     SE3
        SEP     R4
        DW      SHOWREC
        LBR     SE1
SE3:    SEP     R4
        DW      SHOWNM
        LBR     SE1
SE9:    LOAD    RD, NFOUND
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     NONE
        SEP     R4
        DW      LDNF
        SEP     R4
        DW      CNT
        SEP     R4
        DW      TPIN
        DB      ' found.',0DH,0AH,0
        LBR     K_MAIN
NONE:   SEP     R4
        DW      TPIN
        DB      'No contact found.',0DH,0AH,0
        LBR     FAILST

; ==== add (MODE 5): the fields asked, then the book copied with the new contact at its end
ADD:    SEP     R4
        DW      TPIN
        DB      'A new contact (Enter: left empty; Esc: nothing added)',0DH,0AH,0
        SEP     R4
        DW      FORM
        LBNF    REWR
        SEP     R4
        DW      TPIN
        DB      'Nothing added.',0DH,0AH,0
        LBR     FAILST

; ==== add, delete (MODE 2), edit (3): the book written again, a sector at a time
REWR:   SEP     R4
        DW      WSETUP
        LOAD    RD, WOUT
        LDI     1
        STR     RD
RW1:    SEP     R4
        DW      RDREC
        LBDF    RW8
        LOAD    RD, NREC
        SEP     R4
        DW      INC16
        LOAD    RD, BIG         ; too big: copied as it is
        LDN     RD
        LBZ     RW2
        LOAD    RB, RECB
        SEP     R4
        DW      PUTREC
        SEP     R4
        DW      RESTREC
        LBR     RW1
RW2:    LOAD    RD, MODE
        LDN     RD
        XRI     5
        LBZ     RWKEEP
        LOAD    RD, QUIET
        LDN     RD
        LBNZ    RWKEEP
        SEP     R4
        DW      MATCH
        LBNF    RWKEEP
        LOAD    RD, NFOUND
        SEP     R4
        DW      INC16
        SEP     R4
        DW      SHOWREC
        LOAD    RD, MODE
        LDN     RD
        XRI     2
        LBNZ    RW3
        SEP     R4
        DW      TPIN
        DB      'Delete this contact? (Y/N, Q: no more) ',0
        LBR     RW4
RW3:    SEP     R4
        DW      TPIN
        DB      'Edit this contact? (Y/N, Q: no more) ',0
RW4:    SEP     R4
        DW      ASK
        XRI     'N'
        LBZ     RWKEEP
        XRI     'N' XOR 'Q'
        LBZ     RWQ
        LOAD    RD, MODE        ; Y
        LDN     RD
        XRI     2
        LBZ     RWDEL
        SEP     R4
        DW      TPIN
        DB      '(Enter keeps a value; Backspace, Ctrl-U change it; Esc: no change)',0DH,0AH,0
        SEP     R4
        DW      FORM
        LBDF    RWQ0
        LOAD    RB, NEWB
        SEP     R4
        DW      PUTREC
        SEP     R4
        DW      PUTNL
        SEP     R4
        DW      TPIN
        DB      0DH,0AH,0
RWDEL:  LOAD    RD, NCHG
        SEP     R4
        DW      INC16
        LBR     RW1
RWQ0:   SEP     R4
        DW      TPIN
        DB      'Not changed.',0DH,0AH,0
RWQ:    LOAD    RD, QUIET       ; Q: the rest as it is
        LDI     1
        STR     RD
RWKEEP: LOAD    RB, RECB
        SEP     R4
        DW      PUTREC
        SEP     R4
        DW      PUTNL
        LBR     RW1
RW8:    LOAD    RD, MODE        ; the end: add - the new one last
        LDN     RD
        XRI     5
        LBNZ    RW9
        LOAD    RB, NEWB
        SEP     R4
        DW      PUTREC
        SEP     R4
        DW      PUTNL
        SEP     R4
        DW      WFIN
        SEP     R4
        DW      TPIN
        DB      'Added: ',0
        SEP     R4
        DW      TBOOK
        SEP     R4
        DW      TPIN
        DB      ' has ',0
        LOAD    RD, NREC
        SEP     R4
        DW      INC16
        SEP     R4
        DW      LDNR
        SEP     R4
        DW      CNT
        SEP     R4
        DW      TPIN
        DB      '.',0DH,0AH,0
        LBR     K_MAIN
RW9:    LOAD    RD, NCHG
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBNZ    RW10
        SEP     R4              ; nothing changed: the new copy's clusters given back
        DW      WFREE
        LOAD    RD, NFOUND
        LDA     RD
        STR     R2
        LDN     RD
        OR
        LBZ     NONE
        SEP     R4
        DW      TPIN
        DB      'Nothing changed.',0DH,0AH,0
        LBR     K_MAIN
RW10:   SEP     R4
        DW      WFIN
        LOAD    RD, MODE
        LDN     RD
        XRI     2
        LBNZ    RW11
        SEP     R4
        DW      TPIN
        DB      'Deleted ',0
        LBR     RW12
RW11:   SEP     R4
        DW      TPIN
        DB      'Changed ',0
RW12:   LOAD    RD, NCHG
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RD
        GHI     RF
        PHI     RD
        SEP     R4
        DW      CNT
        SEP     R4
        DW      TPIN
        DB      '.',0DH,0AH,0
        LBR     K_MAIN

; ---- the mistakes
OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        LBR     FAILST
USAGE:  SEP     R4
        DW      TPIN
        DB      'Usage:  CONTACTS                 add a contact (it asks for each field)',0DH,0AH
        DB      '        CONTACTS word ...        the contacts with all the words',0DH,0AH
        DB      '        CONTACTS -f FIELD word   ... in that field (NAME CITY TEL ...)',0DH,0AH
        DB      '        CONTACTS -l [word]       the names only',0DH,0AH
        DB      '        CONTACTS -d word         delete (each one asked about)',0DH,0AH
        DB      '        CONTACTS -e word         edit (each one asked about)',0DH,0AH
        DB      '        -b file                  another book (not /CONTACTS.TXT)',0DH,0AH,0
FAILST: LOAD    RD, K_STAT
        LDI     1
        STR     RD
        LBR     K_MAIN
NOBOOK: SEP     R4
        DW      TPIN
        DB      'There is no ',0
        SEP     R4
        DW      TBOOK
        SEP     R4
        DW      TPIN
        DB      ' yet - CONTACTS alone adds a contact.',0DH,0AH,0
        LBR     FAILST
BADBK:  SEP     R4
        DW      TPIN
        DB      'CONTACTS: not a book: ',0
        SEP     R4
        DW      TBOOK
        SEP     R4
        DW      TNL
        LBR     FAILST
WFULL:  SEP     R4              ; the card full or failing: the new copy's clusters given back, the book as it was
        DW      WFREE
        SEP     R4
        DW      TPIN
        DB      0DH,0AH,'CONTACTS: the card is full (or did not answer) - nothing changed.',0DH,0AH,0
        LBR     FAILST

; PARSEBK: BOOK -> FN11, WDIR its folder (a bad name: said, and back to the prompt)
PARSEBK: LOAD   RF, BOOK
        LOAD    RD, FN11
        SEP     R4
        DW      K_PARSE
        LBDF    BADBK
        LOAD    RD, FN11
        LDI     11
        PLO     RC
PB1:    LDA     RD
        XRI     '?'
        LBZ     BADBK
        DEC     RC
        GLO     RC
        LBNZ    PB1
        SEP     R5

; ==== reading the book
; RDREC: the next contact -> RECB (each line with a LF after it, CR and other control characters left out, a Tab
;        kept; a 0 after the last line). Blank lines (or spaces only) end a contact. DF = 1: no more.
;        Too big (past RBTOP): BIG = the character that did not fit, the rest left for RESTREC.
;        RA RC: where in KS_DATBUF and how many left (SPTR, SREM between calls); R9 where in RECB, R8 the line's
;        start, R7.0 = 1: the line has more than spaces.
RDREC:  LOAD    RD, HAVE
        LDN     RD
        LBZ     RRNONE
        LOAD    RD, BIG
        LDI     0
        STR     RD
        SEP     R4
        DW      LDSRC
        LOAD    R9, RECB
        LOAD    R8, RECB
        LDI     0
        PLO     R7
RR1:    GLO     RC
        LBNZ    RR2
        GHI     RC
        LBZ     RRFILL
RR2:    DEC     RC
        LDA     RA
        PLO     RB
        XRI     0AH
        LBZ     RRLF
        GLO     RB
        SMI     20H
        LBNF    RR4
        GHI     R9
        XRI     HIGH(RBTOP)
        LBZ     RRBIG
        GLO     RB
        STR     R9
        INC     R9
        XRI     ' '
        LBZ     RR1
        LDI     1
        PLO     R7
        LBR     RR1
RR4:    GLO     RB              ; a control character: a Tab kept
        XRI     09H
        LBNZ    RR1
        GHI     R9
        XRI     HIGH(RBTOP)
        LBZ     RRBIG
        GLO     RB
        STR     R9
        INC     R9
        LBR     RR1
RRLF:   GLO     R7
        LBNZ    RRL2
        GHI     R8              ; a blank line: dropped
        PHI     R9
        GLO     R8
        PLO     R9
        GLO     R9              ; the contact's end, if it has a line (blank lines before one: passed)
        LBNZ    RREND
        GHI     R9
        XRI     HIGH(RECB)
        LBNZ    RREND
        LBR     RR1
RRL2:   LDI     0AH
        STR     R9
        INC     R9
        GHI     R9
        PHI     R8
        GLO     R9
        PLO     R8
        LDI     0
        PLO     R7
        LBR     RR1
RRFILL: GLO     R7              ; the next sector (FREAD uses R7-RF)
        STXD
        GHI     R7
        STXD
        GLO     R8
        STXD
        GHI     R8
        STXD
        GLO     R9
        STXD
        GHI     R9
        STXD
        SEP     R4
        DW      KS_FREAD
        IRX
        LDXA
        PHI     R9
        LDXA
        PLO     R9
        LDXA
        PHI     R8
        LDXA
        PLO     R8
        LDXA
        PHI     R7
        LDX
        PLO     R7
        LBDF    RREOF
        LOAD    RA, KS_DATBUF
        LBR     RR1
RREOF:  LDI     0
        PHI     RC
        PLO     RC
        LOAD    RD, HAVE
        LDI     0
        STR     RD
        GLO     R7
        LBNZ    RRE2
        GHI     R8              ; (a last line of spaces: dropped)
        PHI     R9
        GLO     R8
        PLO     R9
        LBR     RRE3
RRE2:   LDI     0AH
        STR     R9
        INC     R9
RRE3:   GLO     R9
        LBNZ    RREND
        GHI     R9
        XRI     HIGH(RECB)
        LBNZ    RREND
RRNONE: LDI     1
        SHR
        SEP     R5
RRBIG:  LOAD    RD, BIG
        GLO     RB
        STR     RD
RREND:  LDI     0
        STR     R9
        SEP     R4
        DW      STSRC
        LDI     0
        SHR
        SEP     R5
LDSRC:  LOAD    RD, SPTR        ; RA = SPTR, RC = SREM
        LDA     RD
        PHI     RA
        LDA     RD
        PLO     RA
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R5
STSRC:  LOAD    RD, SPTR
        GHI     RA
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R5

; RESTREC: the rest of a contact too big for RECB - out (CR LF line ends, a blank line after) if WOUT, else
;          only passed
RESTREC: SEP    R4
        DW      LDOUT
        LOAD    RD, BIG
        LDN     RD
        SEP     R4
        DW      PUTW
        SEP     R4
        DW      LDSRC
        LDI     1
        PLO     R7
RS1:    GLO     RC
        LBNZ    RS2
        GHI     RC
        LBZ     RSFILL
RS2:    DEC     RC
        LDA     RA
        PLO     RB
        XRI     0AH
        LBZ     RSLF
        GLO     RB
        SMI     20H
        LBNF    RS1
        GLO     RB
        SEP     R4
        DW      PUTW
        LDI     1
        PLO     R7
        LBR     RS1
RSLF:   GLO     R7
        LBZ     RSEND
        SEP     R4
        DW      PUTWNL
        LDI     0
        PLO     R7
        LBR     RS1
RSFILL: GLO     R7
        STXD
        GLO     RF
        STXD
        GHI     RF
        STXD
        SEP     R4
        DW      KS_FREAD
        IRX
        LDXA
        PHI     RF
        LDXA
        PLO     RF
        LDX
        PLO     R7
        LBDF    RSEOF
        LOAD    RA, KS_DATBUF
        LBR     RS1
RSEOF:  LDI     0
        PHI     RC
        PLO     RC
        LOAD    RD, HAVE
        LDI     0
        STR     RD
        GLO     R7
        LBZ     RSEND
        SEP     R4
        DW      PUTWNL
RSEND:  SEP     R4
        DW      PUTWNL
        SEP     R4
        DW      STSRC
        LBR     STOUT
PUTWNL: LDI     0DH
        SEP     R4
        DW      PUTW
        LDI     0AH
; PUTW: D out (PUTD) if WOUT
PUTW:   STXD
        LOAD    RD, WOUT
        IRX
        LDN     RD
        LBZ     PW9
        LDX
        LBR     PUTD
PW9:    SEP     R5

; ==== matching
; MATCH: DF = 1 if the contact in RECB has every word (in a value; with -f, in that field's). R7 = the word's
;        first character in upper and lower case; RA the word, RB the line, RC where in it
MATCH:  LOAD    RA, WORDS
MW1:    LDN     RA
        LBZ     MYES
        PHI     R7
        PLO     R7
        SMI     'A'
        LBNF    MW2
        SMI     26
        LBDF    MW2
        GLO     R7
        ADI     20H
        PLO     R7
MW2:    LOAD    RB, RECB
ML1:    LDN     RB
        LBZ     MNO
        GHI     RB              ; its field: up to the ':'
        PHI     RC
        GLO     RB
        PLO     RC
ML2:    LDN     RC
        XRI     0AH
        LBZ     MLNC
        LDA     RC
        XRI     ':'
        LBNZ    ML2
        LOAD    RD, FIELD       ; -f: the field's name starts so?
        LDN     RD
        LBZ     MS1
        GHI     RB
        PHI     R9
        GLO     RB
        PLO     R9
MLF:    LDN     RD
        LBZ     MS1
        LDA     R9
        SEP     R4
        DW      UPC
        STR     R2
        LDA     RD
        XOR
        LBNZ    MLNX
        LBR     MLF
MLNC:   LOAD    RD, FIELD       ; no ':' - all of it is the value (not with -f)
        LDN     RD
        LBNZ    MLNX
        GHI     RB
        PHI     RC
        GLO     RB
        PLO     RC
MS1:    LDA     RC              ; the word's first character, from RC to the LF
        STR     R2
        XRI     0AH
        LBZ     MLNX2
        GHI     R7
        XOR
        LBZ     MS3
        GLO     R7
        XOR
        LBNZ    MS1
MS3:    GHI     RC              ; the rest of it
        PHI     R9
        GLO     RC
        PLO     R9
        GHI     RA
        PHI     RD
        GLO     RA
        PLO     RD
        INC     RD
MS4:    LDN     RD
        LBZ     MFOUND
        LDA     R9
        PLO     R8
        SMI     'a'
        LBNF    MS5
        SMI     26
        LBDF    MS5
        GLO     R8
        SMI     20H
        PLO     R8
MS5:    GLO     R8
        STR     R2
        LDA     RD
        XOR
        LBZ     MS4
        LBR     MS1
MLNX:   LDA     RB              ; the next line
        XRI     0AH
        LBNZ    MLNX
        LBR     ML1
MLNX2:  GHI     RC
        PHI     RB
        GLO     RC
        PLO     RB
        LBR     ML1
MFOUND: LDA     RA              ; the next word
        LBNZ    MFOUND
        LBR     MW1
MYES:   LDI     1
        SHR
        SEP     R5
MNO:    LDI     0
        SHR
        SEP     R5

; LBLEQ: RD -> a line, RA -> a field's name (upper case, 0 after): DF = 1 if the line is that field ("name:",
;        any case) and RD -> its value (past the spaces). RA moved.
LBLEQ:  LDN     RA
        LBZ     LQ5
        LDA     RD
        SEP     R4
        DW      UPC
        STR     R2
        LDA     RA
        XOR
        LBZ     LBLEQ
LQNO:   LDI     0
        SHR
        SEP     R5
LQ5:    LDA     RD
        XRI     ':'
        LBNZ    LQNO
LQ6:    LDN     RD
        XRI     ' '
        LBNZ    LQ7
        INC     RD
        LBR     LQ6
LQ7:    LDI     1
        SHR
        SEP     R5

; UPC: D in upper case
UPC:    STR     R2
        SMI     'a'
        LBNF    UPC9
        SMI     26
        LBDF    UPC9
        LDN     R2
        SMI     20H
        SEP     R5
UPC9:   LDN     R2
        SEP     R5

; ==== showing
; SHOWREC: the contact in RECB: its lines but the empty fields ("CITY:"), a blank line after. To the output
;          (EMIT: the screen with TTYF). K_OUT keeps only RD and RF.
SHOWREC: LOAD   RF, RECB
SH1:    LDN     RF
        LBZ     SH9
        GHI     RF              ; an empty field?
        PHI     RD
        GLO     RF
        PLO     RD
SH2:    LDN     RD
        XRI     0AH
        LBZ     SH6
        LDA     RD
        XRI     ':'
        LBNZ    SH2
SH3:    LDA     RD
        XRI     ' '
        LBZ     SH3
        DEC     RD
        LDN     RD
        XRI     0AH
        LBNZ    SH6
        INC     RD              ; empty: passed
        GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
        LBR     SH1
SH6:    LDA     RF
        XRI     0AH
        LBZ     SH7
        DEC     RF
        LDA     RF
        SEP     R4
        DW      EMIT
        LBR     SH6
SH7:    SEP     R4
        DW      ENL
        LBR     SH1
SH9:    LBR     ENL
; SHOWNM: the contact's NAME (its first line, if none)
SHOWNM: LOAD    RF, RECB
SN1:    LDN     RF
        LBZ     SN4
        GHI     RF
        PHI     RD
        GLO     RF
        PLO     RD
        LOAD    RA, FLDS        ; (NAME, the first)
        SEP     R4
        DW      LBLEQ
        LBDF    SN6
SN2:    LDA     RF
        XRI     0AH
        LBNZ    SN2
        LBR     SN1
SN4:    LOAD    RD, RECB
SN6:    GHI     RD
        PHI     RF
        GLO     RD
        PLO     RF
SN7:    LDA     RF
        XRI     0AH
        LBZ     ENL
        DEC     RF
        LDA     RF
        SEP     R4
        DW      EMIT
        LBR     SN7
; EMIT: D to the output (the screen with TTYF)
EMIT:   STXD
        LOAD    R7, TTYF
        IRX
        LDN     R7
        LBNZ    EM2
        LDX
        LBR     K_OUT
EM2:    LDX
        LBR     K_TTY
; ENL: a new line (EMIT); on the screen a page at a time (22 lines; Q stops). Keeps RF.
ENL:    LDI     0DH
        SEP     R4
        DW      EMIT
        LDI     0AH
        SEP     R4
        DW      EMIT
        LOAD    R7, TTYF
        LDN     R7
        LBNZ    EN9
        LOAD    R7, K_RDIR
        LDN     R7
        LBNZ    EN9
        LOAD    R7, LINES
        LDN     R7
        ADI     1
        STR     R7
        XRI     22
        LBNZ    EN9
        STR     R7
        SEP     R4
        DW      TPIN
        DB      '-- more: a key goes on, Q stops --',0
        SEP     R4
        DW      KS_GETK
        PLO     RB
        SEP     R4
        DW      TPIN
        DB      0DH,'                                  ',0DH,0
        GLO     RB
        ANI     0DFH
        XRI     'Q'
        LBZ     K_MAIN
        GLO     RB
        XRI     03H
        LBZ     K_MAIN
        GLO     RB
        XRI     1BH
        LBZ     K_MAIN
EN9:    SEP     R5

; ==== the screen (K_TTY: never into a file)
; TPIN: the text after the call
TPIN:   LDA     R6
        LBZ     TP9
        SEP     R4
        DW      K_TTY
        LBR     TPIN
TP9:    SEP     R5
TNL:    LDI     0DH
        SEP     R4
        DW      K_TTY
        LDI     0AH
        LBR     K_TTY
; TBOOK: the book's name
TBOOK:  LOAD    RF, BOOK
TB1:    LDA     RF
        LBZ     TP9
        SEP     R4
        DW      K_TTY
        LBR     TB1
; TDEC: RD in decimal
TDEC:   LOAD    RA, DECT
        LDI     0
        PLO     RC              ; 1: a digit shown
TD1:    LDA     RA
        PHI     RB
        LDA     RA
        PLO     RB
        GHI     RB
        LBNZ    TD2
        GLO     RB
        LBZ     TP9
TD2:    LDI     0
        PHI     RC              ; the digit
TD3:    GLO     RB
        STR     R2
        GLO     RD
        SM
        PLO     RF
        GHI     RB
        STR     R2
        GHI     RD
        SMB
        LBNF    TD4
        PHI     RD
        GLO     RF
        PLO     RD
        GHI     RC
        ADI     1
        PHI     RC
        LBR     TD3
TD4:    GHI     RC
        LBNZ    TD5
        GLO     RC
        LBNZ    TD5
        GHI     RB
        LBNZ    TD1
        GLO     RB
        XRI     1
        LBNZ    TD1
TD5:    LDI     1
        PLO     RC
        GHI     RC
        ADI     '0'
        SEP     R4
        DW      K_TTY
        LBR     TD1
DECT:   DW      10000, 1000, 100, 10, 1, 0
; CNT: "n contact" or "n contacts" (RD = n)
CNT:    GHI     RD
        STR     R2
        GLO     RD
        XRI     1
        OR
        STXD                    ; 0: one
        SEP     R4
        DW      TDEC
        SEP     R4
        DW      TPIN
        DB      ' contact',0
        IRX
        LDX
        LBZ     TP9
        LDI     's'
        LBR     K_TTY
; LDNF, LDNR: RD = NFOUND, NREC
LDNF:   LOAD    RF, NFOUND
        LBR     LDN1
LDNR:   LOAD    RF, NREC
LDN1:   LDA     RF
        PHI     RD
        LDN     RF
        PLO     RD
        SEP     R5
; INC16: the 2 bytes at RD (high first) + 1
INC16:  INC     RD
        LDN     RD
        ADI     1
        STR     RD
        DEC     RD
        LDN     RD
        ADCI    0
        STR     RD
        SEP     R5

; ==== the keyboard (the UART itself: no echo)
; ASK: a key: 'Y', 'N' or 'Q' (Q, Esc, Ctrl-C) - shown, and a new line
ASK:    SEP     R4
        DW      KS_GETK
        PLO     RB
        ANI     0DFH
        XRI     'Y'
        LBZ     AK1
        GLO     RB
        ANI     0DFH
        XRI     'N'
        LBZ     AK2
        GLO     RB
        ANI     0DFH
        XRI     'Q'
        LBZ     AK3
        GLO     RB
        XRI     03H
        LBZ     AK3
        GLO     RB
        XRI     1BH
        LBNZ    ASK
        SEP     R4              ; Esc: alone, Q; an arrow's: not a key here
        DW      ESCSEQ
        LBDF    ASK
AK3:    LDI     'Q'
        LSKP
AK1:    LDI     'Y'
        LSKP
AK2:    LDI     'N'
        PLO     RB
        SEP     R4
        DW      K_TTY
        SEP     R4
        DW      TNL
        GLO     RB
        SEP     R5
; ESCSEQ: after an Esc: DF = 1 if more comes at once (a key's sequence - read to its end), DF = 0: an Esc alone
ESCSEQ: LOAD    R9, 2000
ES1:    LDI     15H             ; the UART's status: a key?
        STR     R2
        OUT     SELPORT
        DEC     R2
        INP     DATPORT
        ANI     01H
        LBNZ    ES3
        DEC     R9
        GLO     R9
        LBNZ    ES1
        GHI     R9
        LBNZ    ES1
        LDI     0
        SHR
        SEP     R5
ES3:    SEP     R4
        DW      KS_GETK
        XRI     '['
        LBZ     ES4
        XRI     '[' XOR 'O'
        LBNZ    ES9
ES4:    SEP     R4              ; to its last byte (40H-7EH)
        DW      KS_GETK
        SMI     40H
        LBNF    ES4
ES9:    LDI     1
        SHR
        SEP     R5
; GETLN: a line typed into LBUF after what is there (shown first): Backspace / Delete rub out, Ctrl-U (or
;        Ctrl-X) all of it, Enter ends it (DF = 0); Esc, Ctrl-C: DF = 1. RF the end, RC.0 its length.
GETLN:  LOAD    RF, LBUF
        LDI     0
        PHI     RC
        PLO     RC
GL0:    LDN     RF
        LBZ     GL1
        SEP     R4
        DW      K_TTY
        INC     RF
        INC     RC
        LBR     GL0
GL1:    SEP     R4
        DW      KS_GETK
        PLO     RB
        XRI     0DH
        LBZ     GLCR
        GLO     RB
        XRI     08H
        LBZ     GLBS
        GLO     RB
        XRI     7FH
        LBZ     GLBS
        GLO     RB
        XRI     15H
        LBZ     GLKILL
        GLO     RB
        XRI     18H
        LBZ     GLKILL
        GLO     RB
        XRI     03H
        LBZ     GLCAN
        GLO     RB
        XRI     1BH
        LBZ     GLESC
        GLO     RB              ; other control keys, and over 7EH: not taken
        SMI     20H
        LBNF    GL1
        GLO     RB
        SMI     7FH
        LBDF    GL1
        GLO     RC
        XRI     VMAX
        LBZ     GLFULL
        GLO     RB
        STR     RF
        INC     RF
        INC     RC
        SEP     R4
        DW      K_TTY
        LBR     GL1
GLFULL: LDI     07H
        SEP     R4
        DW      K_TTY
        LBR     GL1
GLBS:   GLO     RC
        LBZ     GL1
        SEP     R4
        DW      RUB
        LBR     GL1
GLKILL: GLO     RC
        LBZ     GL1
        SEP     R4
        DW      RUB
        LBR     GLKILL
GLESC:  SEP     R4
        DW      ESCSEQ
        LBDF    GL1
GLCAN:  SEP     R4
        DW      TNL
        LDI     1
        SHR
        SEP     R5
GLCR:   LDI     0
        STR     RF
        SEP     R4
        DW      TNL
        LDI     0
        SHR
        SEP     R5
RUB:    DEC     RF              ; the last character off
        DEC     RC
        LDI     08H
        SEP     R4
        DW      K_TTY
        LDI     ' '
        SEP     R4
        DW      K_TTY
        LDI     08H
        LBR     K_TTY

; ==== a contact typed
; FORM: each field asked (edit: its value now to change) -> NEWB, "FIELD: value" lines (each field; empty:
;       "FIELD:"); edit: the contact's other lines after. DF = 1: Esc (or adding with no NAME)
FORM:   LOAD    RD, NEWP
        LDI     HIGH(NEWB)
        STR     RD
        INC     RD
        LDI     LOW(NEWB)
        STR     RD
        LOAD    RD, FLDP
        LDI     HIGH(FLDS)
        STR     RD
        INC     RD
        LDI     LOW(FLDS)
        STR     RD
        LOAD    RD, FIDX
        LDI     0
        STR     RD
FO1:    LOAD    RD, FLDP
        LDA     RD
        PHI     RA
        LDN     RD
        PLO     RA
        LDN     RA
        LBZ     FO8
        LOAD    RD, LBUF        ; the value now: none, or (edit) the contact's
        LDI     0
        STR     RD
        LOAD    RD, MODE
        LDN     RD
        XRI     3
        LBNZ    FO2
        SEP     R4
        DW      FINDV
FO2:    LOAD    RD, FLDP        ; "FIELD: " on the screen
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
FO3:    LDA     RF
        LBZ     FO4
        SEP     R4
        DW      K_TTY
        LBR     FO3
FO4:    SEP     R4
        DW      TPIN
        DB      ': ',0
        SEP     R4
        DW      GETLN
        LBDF    FOCAN
        LOAD    RD, FIDX        ; adding with no NAME: nothing
        LDN     RD
        LBNZ    FO5
        LOAD    RD, MODE
        LDN     RD
        XRI     5
        LBNZ    FO5
        LOAD    RD, LBUF
        LDN     RD
        LBZ     FOCAN
FO5:    LOAD    RD, NEWP        ; "FIELD:" [" value"] LF
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RD, FLDP
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
FO6:    LDA     RF
        LBZ     FO7
        STR     RB
        INC     RB
        LBR     FO6
FO7:    LOAD    RD, FLDP        ; (the next field's name)
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LDI     ':'
        STR     RB
        INC     RB
        LOAD    RF, LBUF
        LDN     RF
        LBZ     FO7B
        LDI     ' '
        STR     RB
        INC     RB
FO7A:   LDA     RF
        LBZ     FO7B
        STR     RB
        INC     RB
        LBR     FO7A
FO7B:   LDI     0AH
        STR     RB
        INC     RB
        LDI     0
        STR     RB
        LOAD    RD, NEWP
        GHI     RB
        STR     RD
        INC     RD
        GLO     RB
        STR     RD
        LOAD    RD, FIDX
        LDN     RD
        ADI     1
        STR     RD
        LBR     FO1
FO8:    LOAD    RD, MODE        ; edit: the lines not asked about, after
        LDN     RD
        XRI     3
        LBNZ    FO9
        LOAD    RD, NEWP
        LDA     RD
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RA, RECB
FX1:    LDN     RA
        LBZ     FX8
        LOAD    RD, CONS        ; a line asked about? (CONS: each field's)
        LDI     11
        PLO     RC
FX2:    LDA     RD
        STR     R2
        GHI     RA
        XOR
        LBNZ    FX3
        LDN     RD
        STR     R2
        GLO     RA
        XOR
        LBZ     FXSKIP
FX3:    INC     RD
        DEC     RC
        GLO     RC
        LBNZ    FX2
FX4:    GHI     RB
        XRI     HIGH(NBTOP)
        LBZ     FXBIG
        LDA     RA
        STR     RB
        INC     RB
        XRI     0AH
        LBNZ    FX4
        LBR     FX1
FXSKIP: LDA     RA
        XRI     0AH
        LBNZ    FXSKIP
        LBR     FX1
FX8:    LDI     0
        STR     RB
FO9:    LDI     0
        SHR
        SEP     R5
FXBIG:  SEP     R4
        DW      TPIN
        DB      'Too long to edit here - NANO edits it.',0DH,0AH,0
FOCAN:  LDI     1
        SHR
        SEP     R5
; FINDV: RA -> a field's name: its value in the contact (RECB) -> LBUF (VMAX at most); CONS[FIDX] = its line
;        (0: none)
FINDV:  LOAD    RD, FIDX
        LDN     RD
        SHL
        ADI     LOW(CONS)
        PLO     R9
        LDI     HIGH(CONS)
        ADCI    0
        PHI     R9
        LDI     0
        STR     R9
        INC     R9
        STR     R9
        DEC     R9
        GHI     RA
        PHI     R8
        GLO     RA
        PLO     R8
        LOAD    RB, RECB
FV1:    LDN     RB
        LBZ     FV9
        GHI     RB
        PHI     RD
        GLO     RB
        PLO     RD
        GHI     R8
        PHI     RA
        GLO     R8
        PLO     RA
        SEP     R4
        DW      LBLEQ
        LBDF    FV5
FV2:    LDA     RB
        XRI     0AH
        LBNZ    FV2
        LBR     FV1
FV5:    GHI     RB
        STR     R9
        INC     R9
        GLO     RB
        STR     R9
        LOAD    RF, LBUF
        LDI     VMAX
        PLO     RC
FV6:    LDN     RD
        XRI     0AH
        LBZ     FV8
        LDA     RD
        STR     RF
        INC     RF
        DEC     RC
        GLO     RC
        LBNZ    FV6
FV8:    LDI     0
        STR     RF
FV9:    SEP     R5

; ==== writing the book again
; LDOUT / STOUT: RF = OUTN / OUTN = RF
LDOUT:  LOAD    RD, OUTN
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        SEP     R5
STOUT:  LOAD    RD, OUTN
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        SEP     R5
; PUTREC: the contact at RB (LF lines, a 0 after) out, CR LF line ends
PUTREC: SEP     R4
        DW      LDOUT
PU1:    LDA     RB
        LBZ     STOUT
        XRI     0AH
        LBZ     PU5
        DEC     RB
        LDA     RB
        STR     RF
        INC     RF
        GHI     RF
        XRI     HIGH(OUTB + 200H)
        LBNZ    PU1
        SEP     R4
        DW      FLUSHO
        LBR     PU1
PU5:    LDI     0DH
        SEP     R4
        DW      PUTD
        LDI     0AH
        SEP     R4
        DW      PUTD
        LBR     PU1
; PUTNL: CR LF out (the blank line after a contact)
PUTNL:  SEP     R4
        DW      LDOUT
        LDI     0DH
        SEP     R4
        DW      PUTD
        LDI     0AH
        SEP     R4
        DW      PUTD
        LBR     STOUT
; PUTD: D at RF (in OUTB): a full sector written (FLUSHO). Keeps the other registers.
PUTD:   STR     RF
        INC     RF
        GHI     RF
        XRI     HIGH(OUTB + 200H)
        LBNZ    PD9
        LBR     FLUSHO
PD9:    SEP     R5
; FLUSHO: OUTB written (WRBLK), RF = OUTB again. Keeps R7-RD.
FLUSHO: GLO     R7
        STXD
        GHI     R7
        STXD
        GLO     R8
        STXD
        GHI     R8
        STXD
        GLO     R9
        STXD
        GHI     R9
        STXD
        GLO     RA
        STXD
        GHI     RA
        STXD
        GLO     RB
        STXD
        GHI     RB
        STXD
        GLO     RC
        STXD
        GHI     RC
        STXD
        GLO     RD
        STXD
        GHI     RD
        STXD
        SEP     R4
        DW      WRBLK
        IRX
        LDXA
        PHI     RD
        LDXA
        PLO     RD
        LDXA
        PHI     RC
        LDXA
        PLO     RC
        LDXA
        PHI     RB
        LDXA
        PLO     RB
        LDXA
        PHI     RA
        LDXA
        PLO     RA
        LDXA
        PHI     R9
        LDXA
        PLO     R9
        LDXA
        PHI     R8
        LDXA
        PLO     R8
        LDXA
        PHI     R7
        LDX
        PLO     R7
        LBDF    WFULL
        LOAD    RF, OUTB
        SEP     R5

; WSETUP: the book's directory entry: the old one to switch (its clusters freed after; the book opened to read),
;         or a new slot (no book yet: nothing to read)
WSETUP: SEP     R4
        DW      PARSEBK
        LOAD    RD, FN11
        SEP     R4
        DW      KS_FINDN
        LBDF    WS2
        LOAD    RD, KS_DATTR
        LDN     RD
        ANI     10H
        LBNZ    BADBK
        LOAD    RD, ESEC        ; the entry to rewrite: its sector, where in DIRBUF; its clusters
        LOAD    RC, KS_DSEC
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        INC     RD
        GHI     RF
        STR     RD
        INC     RD
        GLO     RF
        STR     RD
        LOAD    RD, OLDCL
        LOAD    RC, KS_DCLUS
        LDA     RC
        STR     RD
        INC     RD
        LDN     RC
        STR     RD
        LOAD    RD, REPL
        LDI     1
        STR     RD
        SEP     R4
        DW      KS_FOPEN
        LOAD    RD, HAVE
        LDI     1
        STR     RD
        LBR     WS3
WS2:    SEP     R4              ; a new file: a free entry (a folder may grow by a cluster for it)
        DW      KS_DSLOT
        LBNF    WS2A
        SEP     R4
        DW      TPIN
        DB      'CONTACTS: the folder is full.',0DH,0AH,0
        LBR     FAILST
WS2A:   LOAD    RD, ESEC
        LOAD    RC, KS_WDSEC    ; WDSEC, WDPTR
        LDI     4
        PLO     RB
WS2B:   LDA     RC
        STR     RD
        INC     RD
        DEC     RB
        GLO     RB
        LBNZ    WS2B
WS3:    LOAD    RD, OUTN        ; the sector empty
        LDI     HIGH(OUTB)
        STR     RD
        INC     RD
        LDI     LOW(OUTB)
        STR     RD
        SEP     R5
; WRBLK: OUTB's 512 bytes as the file's next sector (a new cluster when this one is full). DF = 1: failed
WRBLK:  LOAD    RD, WSLEFT
        LDN     RD
        LBNZ    WB4
        SEP     R4              ; a cluster for the next part
        DW      KS_FREECL
        LBDF    WBERR
        LOAD    RD, NEWC
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        LOAD    R9, 0FFFFH      ; it ends the chain ...
        SEP     R4
        DW      KS_FATPUT
        LBDF    WBERR
        LOAD    RD, WPREV       ; ... and the last one points at it (or it is the first)
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, NEWC
        LDA     RD
        PHI     R9
        LDN     RD
        PLO     R9
        GHI     RC
        LBNZ    WB2
        GLO     RC
        LBNZ    WB2
        LOAD    RD, WFIRST
        GHI     R9
        STR     RD
        INC     RD
        GLO     R9
        STR     RD
        LBR     WB3
WB2:    SEP     R4
        DW      KS_FATPUT
        LBDF    WBERR
WB3:    LOAD    RD, NEWC        ; WPREV = it; WLBA = its first sector, WSLEFT = its sectors
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        LOAD    RD, WPREV
        GHI     RC
        STR     RD
        INC     RD
        GLO     RC
        STR     RD
        SEP     R4
        DW      KS_CL2LBA
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_ST32
        LOAD    RD, KS_SPC
        LDN     RD
        PLO     RB
        LOAD    RD, WSLEFT
        GLO     RB
        STR     RD
WB4:    LOAD    RD, WLBA        ; the sector
        SEP     R4
        DW      KS_LD32
        LOAD    RF, OUTB
        SEP     R4
        DW      KS_IDEWR
        LBDF    WBERR
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_LD32
        LOAD    RC, 1
        SEP     R4
        DW      KS_ADD16
        LOAD    RD, WLBA
        SEP     R4
        DW      KS_ST32
        LOAD    RD, WSLEFT
        LDN     RD
        SMI     1
        STR     RD
        LOAD    RD, NSECT
        SEP     R4
        DW      INC16
        LDI     0
        SHR
        SEP     R5
WBERR:  LDI     1
        SHR
        SEP     R5
; WFREE: the clusters taken given back
WFREE:  LOAD    RD, WFIRST
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    WF1
        GLO     RC
        LBZ     WF9
WF1:    SEP     R4
        DW      KS_FREECH
        SEP     R4
        DW      KS_FATFLUSH
WF9:    SEP     R5
; WFIN: the last sector, the FAT, the entry (the switch), the old book's clusters
WFIN:   LOAD    RD, OUTN        ; the size: NSECT x 512 + the bytes in OUTB
        LDA     RD
        SMI     HIGH(OUTB)
        PHI     RB
        LDN     RD
        PLO     RB
        LOAD    RD, NSECT
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GLO     RC
        SHL
        PLO     RC
        GHI     RC
        SHLC
        PHI     RC
        LDI     0
        SHLC
        PLO     RA
        LOAD    RD, FSIZE       ; (little-endian, as the entry has it)
        GLO     RB
        STR     RD
        INC     RD
        GHI     RB
        STR     R2
        GLO     RC
        OR
        STR     RD
        INC     RD
        GHI     RC
        STR     RD
        INC     RD
        GLO     RA
        STR     RD
        SEP     R4              ; the last part of a sector: 0s after it, out
        DW      LDOUT
        GLO     RF
        LBNZ    WFI2
        GHI     RF
        XRI     HIGH(OUTB)
        LBZ     WFI3
WFI2:   LDI     0
        STR     RF
        INC     RF
        GHI     RF
        XRI     HIGH(OUTB + 200H)
        LBNZ    WFI2
        SEP     R4
        DW      WRBLK
        LBDF    WFULL
WFI3:   SEP     R4
        DW      KS_FATFLUSH
        LBDF    WFULL
        SEP     R4              ; WDIR = the book's folder again
        DW      PARSEBK
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRRD
        LBDF    WFULL
        SEP     R4
        DW      KS_STAMP
        LOAD    RD, EPTR
        LDA     RD
        PHI     RF
        LDN     RD
        PLO     RF
        LOAD    RD, REPL        ; the book there: its name, attributes and created time kept
        LDN     RD
        LBZ     WF2
        GLO     RF
        ADI     18
        PLO     RF
        GHI     RF
        ADCI    0
        PHI     RF
        LBR     WF5
WF2:    LOAD    RD, FN11        ; 0-10 the name
        LDI     11
        PLO     RB
WF3:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    WF3
        LDI     20H             ; 11 archive; 12, 13
        STR     RF
        INC     RF
        LDI     0
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 14-17 created
        DW      KS_PUTST
WF5:    LOAD    RD, KS_STD      ; 18-19 used
        LDA     RD
        STR     RF
        INC     RF
        LDN     RD
        STR     RF
        INC     RF
        LDI     0               ; 20-21
        STR     RF
        INC     RF
        STR     RF
        INC     RF
        SEP     R4              ; 22-25 written
        DW      KS_PUTST
        LOAD    RD, WFIRST      ; 26-27 the first cluster, 28-31 the size
        LDA     RD
        PHI     RC
        LDN     RD
        STR     RF
        INC     RF
        GHI     RC
        STR     RF
        INC     RF
        LOAD    RD, FSIZE
        LDI     4
        PLO     RB
WF6:    LDA     RD
        STR     RF
        INC     RF
        DEC     RB
        GLO     RB
        LBNZ    WF6
        LOAD    RD, ESEC
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        SEP     R4
        DW      KS_DIRWR
        LBDF    WFULL
        LOAD    RD, REPL        ; the old book's clusters
        LDN     RD
        LBZ     WF8
        LOAD    RD, OLDCL
        LDA     RD
        PHI     RC
        LDN     RD
        PLO     RC
        GHI     RC
        LBNZ    WF7
        GLO     RC
        LBZ     WF8
WF7:    SEP     R4
        DW      KS_FREECH
        SEP     R4
        DW      KS_FATFLUSH
WF8:    SEP     R5

DEFBK:  DB      '/CONTACTS.TXT',0
FLDS:   DB      'NAME',0,'ADDRESS',0,'ADDRESS2',0,'CITY',0,'STATE/CO',0,'POSTCODE',0
        DB      'COUNTRY',0,'TEL',0,'EMAIL',0,'BDAY',0,'NOTE',0,0
PEND:
; ---- the variables (0 at the start)
VARS:
MODE:   DS      1               ; 1 search, 2 delete, 3 edit, 4 names, 5 add
TTYF:   DS      1               ; 1: the contacts shown on the screen (not the output)
NWORDS: DS      1
WEND:   DS      2
LINES:  DS      1
HAVE:   DS      1               ; 1: the book open to read, not at its end
BIG:    DS      1               ; not 0: the contact read is too big - the character that did not fit
WOUT:   DS      1               ; 1: RESTREC writes
QUIET:  DS      1               ; 1: Q - no more questions
NREC:   DS      2
NFOUND: DS      2
NCHG:   DS      2
SPTR:   DS      2               ; SPTR, SREM: in this order (LDSRC)
SREM:   DS      2
NEWP:   DS      2
FLDP:   DS      2
FIDX:   DS      1
CONS:   DS      22              ; edit: the line each field's value came from
OUTN:   DS      2
NSECT:  DS      2
FSIZE:  DS      4
ESEC:   DS      2               ; ESEC, EPTR: in this order
EPTR:   DS      2
OLDCL:  DS      2
REPL:   DS      1
WSLEFT: DS      1
NEWC:   DS      2
WPREV:  DS      2
WFIRST: DS      2
WLBA:   DS      4
FIELD:  DS      16
FN11:   DS      11
BOOK:   DS      64
WORDS:  DS      128
VEND:
        END
