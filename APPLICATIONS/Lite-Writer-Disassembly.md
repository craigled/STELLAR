# Lite-Writer — Full Annotated Disassembly

STELLAR text-entry terminal for the 1802 (Elf2K). Loads at **$4000** (VM1 program
block), runs in **relative** addressing mode (the default), so every `M(Rx)` access
resolves to `Rx + $4000` in real memory.

This document walks the image **instruction by instruction**. For the loop/function
logic and the "why", see the companion `Lite-Writer-Architecture.md`.

---

## Conventions

- `ADDR  bytes            MNEMONIC operands        ; note`
- `Lxx` = a STELLAR label (entry in the 256-slot label array), referenced by number.
- `Rn` = vCPU register n. `Acc` = 16-bit accumulator. `MA` = math accumulator.
- **Relative mode:** `M(Rx)` reads/writes real address `Rx + $4000`.
  So `R2 = $1000` points at real **$5000** (the text buffer);
  `R7 = $2000` points at real **$6000** (save bank 1).

### The three custom terminal opcodes (this build's names vs. the firmware spec)

| This listing | Firmware opcode | Meaning |
|---|---|---|
| `INCH`  ($CB)     | `SERIN`   | Cooperatively wait for a UART byte → Acc low byte |
| `OUTCH` ($C9)     | `SEROUT`  | Send Acc low byte to the UART as ASCII |
| `OUTL NN` ($CA)   | `SEROUTI` | Send the literal byte NN to the UART |

The header names (`INCH`/`OUTCH`/`OUTL`) are just friendlier aliases; the bytes are
the standard v0061 serial ops.

### Byte-read gotcha this code guards against

`35 01 0X` (COPYIMXA, read **1** byte → Acc) loads only **Acc low**. On older
firmware it left Acc high dirty, so the code frequently reloads `10 00 00`
(`LOADAI $0000`) before a read and always tests with a full-word `81 00 00`
(`TESTAI $0000`). Firmware v0061.1D+ zero-extends `$35`, making those guards
redundant-but-harmless; they're kept as written.

---

## Register allocation (whole program)

| Reg | Role |
|---|---|
| **R1** | Write pointer (cursor into the text buffer) |
| **R2** | Buffer start, rel `$1000` (real $5000) |
| **R3** | Buffer end **+1**, rel `$1800` (real $5800) |
| **R4** | Scratch iterator (view / end / replay scans) |
| **R5** | Buffer last byte, rel `$17FF` — used by ^U fill |
| **R6 / R7** | Copy source / destination (save, load, ^W, and the ^K "peek") |
| **R8** | Hex-compare constant `$000A` (used by ^W digit decode) |
| **R9** | Warn threshold, rel `$17E0` |
| **RA** | String pointer for all print loops |
| **RB** | Scratch — holds a decoded hex nibble during ^W |

---

# CODE SEGMENT  ($4000 – $4336)

## Startup / initialisation  ($4000 – $401D)

```
4000  CD             START               ; required first byte of every STELLAR program
4001  C7 00          SETMULTI $00         ; multitasking OFF — claim $5000-$7EFF for this VM alone
4003  11 01 10 00    LOADXI R1,$1000      ; write pointer := buffer start
4007  11 02 10 00    LOADXI R2,$1000      ; R2 = buffer start   (rel $1000 = real $5000)
400B  11 03 18 00    LOADXI R3,$1800      ; R3 = buffer end+1   (rel $1800 = real $5800)
400F  11 05 17 FF    LOADXI R5,$17FF      ; R5 = buffer last    (used by ^U FILLMEMXY)
4013  11 09 17 E0    LOADXI R9,$17E0      ; R9 = "nearing limit" warn threshold
4017  10 00 00       LOADAI $0000         ; Acc := 0
401A  11 0A 07 00    LOADXI RA,$0700      ; RA -> banner string (rel $0700 = real $4700)
```

`C7 00` is the key move: it writes `$2F55 := 0` (Multitasking-Allowed = No) so the
scheduler never leaves VM1, giving Lite-Writer exclusive use of the VM2/3/4 RAM
(`$5000-$7EFF`) for its buffer and save banks.

## Banner print loop — L80  ($401E – $402B)

```
401E  B3 80          LBL  L80
4020  35 01 0A       COPYIMXA Acc <- M(RA) [1b]   ; read next banner byte
4023  81 00 00       TESTAI $0000                 ; null terminator?
4026  A2 81          IFTRUEL  L81                  ; yes -> done printing banner
4028  C9             OUTCH                         ; else send the char
4029  42 0A          INCX RA                       ; advance string pointer
402B  B4 80          GTL  L80                      ; loop
```

This is the **canonical print-string loop** reused eight times in the program
(L80, L82, L84, L86, L88, L71/L78, and the view/replay loops are variants).

## "Text is Present?" check — L81 / L82 / L83  ($402D – $404A)

```
402D  B3 81          LBL  L81
402F  35 01 02       COPYIMXA Acc <- M(R2) [1b]   ; read first byte of the text buffer
4032  81 00 00       TESTAI $0000
4035  A2 01          IFTRUEL  L01                 ; buffer empty -> straight to main loop
4037  11 0A 07 28    LOADXI RA,$0728              ; else RA -> "Text is Present" (real $4728)

403B  B3 82          LBL  L82                     ; print "Text is Present"
403D  35 01 0A       COPYIMXA Acc <- M(RA) [1b]
4040  81 00 00       TESTAI $0000
4043  A2 83          IFTRUEL  L83
4045  C9             OUTCH
4046  42 0A          INCX RA
4048  B4 82          GTL  L82

404A  B3 83          LBL  L83                     ; (empty) falls through into L01
```

On entry the buffer usually starts as `$00` (freshly cleared), so this line is
mostly for the case where `^X` exited earlier and text is still resident in RAM.

---

## L01 — MAIN INPUT LOOP + key dispatch  ($404C – $409F)

```
404C  B3 01          LBL  L01
404E  CB             INCH                 ; block (cooperatively) for one keystroke -> Acc low
```

A ladder of `TESTAI imm / IFTRUEL Lxx` pairs classifies the key. Order matters only
in that each test is independent; the first match wins because its branch is taken.

```
404F  81 00 18       TESTAI $0018   A2 FE  IFTRUEL LFE   ; ^X  $18  exit
4054  81 00 16       TESTAI $0016   A2 10  IFTRUEL L10   ; ^V  $16  view buffer
4059  81 00 13       TESTAI $0013   A2 65  IFTRUEL L65   ; ^S  $13  save to bank 1
405E  81 00 17       TESTAI $0017   A2 70  IFTRUEL L70   ; ^W  $17  write to address
4063  81 00 0C       TESTAI $000C   A2 66  IFTRUEL L66   ; ^L  $0C  load bank 1
4068  81 00 0B       TESTAI $000B   A2 55  IFTRUEL L55   ; ^K  $0B  kill line
406D  81 00 05       TESTAI $0005   A2 60  IFTRUEL L60   ; ^E  $05  jump to end
4072  81 00 04       TESTAI $0004   A2 30  IFTRUEL L30   ; ^D  $04  delete char (no echo)
4077  81 00 7F       TESTAI $007F   A2 20  IFTRUEL L20   ; DEL $7F  backspace
407C  81 00 07       TESTAI $0007   A2 67  IFTRUEL L67   ; ^G  $07  help
4081  81 00 08       TESTAI $0008   A2 20  IFTRUEL L20   ; BS  $08  backspace (Ctrl-H) -> same as DEL
4086  81 00 0D       TESTAI $000D   A2 40  IFTRUEL L40   ; CR  $0D  enter
408B  81 00 15       TESTAI $0015   A2 50  IFTRUEL L50   ; ^U  $15  clear buffer
```

Both `$7F` (DEL) and `$08` (Ctrl-H) route to **L20**, so the Backspace key works
whatever byte the terminal sends.

If none matched, the byte is treated as a **printable character** and stored:

```
4090  89 13          TESTLXY R1<=R3       ; is write ptr still within the buffer?
4092  A3 01          IFFALSEL L01         ; buffer full -> ignore key, back to loop
4094  C9             OUTCH                ; echo the character
4095  36 01 01       COPYIAMX M(R1) <- Acc [1b]   ; store it at the cursor
4098  42 01          INCX R1              ; advance cursor
409A  87 19          TESTXY R1==R9        ; reached the warn threshold ($17E0)?
409C  A2 04          IFTRUEL  L04         ; yes -> show "nearing size limit" once
409E  B4 01          GTL  L01             ; loop for next key
```

`Acc` still holds the keystroke here — `TESTAI` doesn't modify it — so the same
value that was classified is the value stored.

## L04 — size-limit warning  ($40A0 – $40B8)

```
40A0  B3 04          LBL  L04
40A2  11 0A 07 3A    LOADXI RA,$073A      ; RA -> "You are nearing the size limit"
40A6  B3 86          LBL  L86             ; print-string loop
40A8  35 01 0A       COPYIMXA Acc <- M(RA) [1b]
40AB  81 00 00       TESTAI $0000
40AE  A2 87          IFTRUEL  L87
40B0  C9             OUTCH
40B1  42 0A          INCX RA
40B3  B4 86          GTL  L86
40B5  B3 87          LBL  L87
40B7  B4 01          GTL  L01
```

The threshold `$17E0` sits 32 bytes below the buffer end, so the warning fires once
as the user nears the wall; typing still works up to `R3`.

---

## L10 — ^V VIEW buffer  ($40B9 – $40D7)

```
40B9  B3 10          LBL  L10
40BB  CA 0D          OUTL $0D             ; CR
40BD  CA 0A          OUTL $0A             ; LF
40BF  23 00 24       COPYXY R2 -> R4      ; R4 = buffer start (iterator)

40C2  B3 11          LBL  L11
40C4  87 14          TESTXY R1==R4        ; reached the cursor?
40C6  A2 12          IFTRUEL  L12         ; yes -> done
40C8  35 01 04       COPYIMXA Acc <- M(R4) [1b]
40CB  C9             OUTCH                ; print buffer char
40CC  42 04          INCX R4
40CE  B4 11          GTL  L11

40D0  B3 12          LBL  L12
40D2  CA 0D          OUTL $0D
40D4  CA 0A          OUTL $0A
40D6  B4 01          GTL  L01
```

Dumps everything from buffer start up to (not including) the cursor. Because CR/LF
pairs are stored verbatim, the replay reproduces the user's line breaks.

---

## L20 — BACKSPACE ($7F / $08)  ($40D8 – $40F7)

```
40D8  B3 20          LBL  L20
40DA  88 12          TESTGXY R1>=R2       ; anything to delete?
40DC  A3 01          IFFALSEL L01         ; cursor below start -> nothing to do
40DE  43 01          DECX R1              ; step cursor back one
40E0  35 01 01       COPYIMXA Acc <- M(R1) [1b]   ; peek the char we backed onto
40E3  81 00 0A       TESTAI $000A         ; is it the LF of a CR+LF pair?
40E6  A3 22          IFFALSEL L22         ; no -> just do the erase feedback
40E8  88 12          TESTGXY R1>=R2       ; yes: can we step back once more?
40EA  A3 22          IFFALSEL L22
40EC  43 01          DECX R1              ; drop the CR too (a CR+LF counts as one deletion)

40EE  B3 22          LBL  L22
40F0  CA 08          OUTL $08             ; BS  \  visually erase one glyph:
40F2  CA 20          OUTL $20             ; SP   >  backspace, space, backspace
40F4  CA 08          OUTL $08             ; BS  /
40F6  B4 01          GTL  L01
```

The cursor is destructive: deleting simply retreats `R1`; the old bytes are
overwritten on the next keypress or terminated by the next `$00`.

---

## L30 — ^D delete char (no erase echo)  ($40F8 – $410F)

```
40F8  B3 30          LBL  L30
40FA  88 12          TESTGXY R1>=R2
40FC  A3 01          IFFALSEL L01
40FE  43 01          DECX R1
4100  35 01 01       COPYIMXA Acc <- M(R1) [1b]
4103  81 00 0A       TESTAI $000A
4106  A3 01          IFFALSEL L01         ; not LF -> done (dropped 1 byte)
4108  88 12          TESTGXY R1>=R2
410A  A3 01          IFFALSEL L01
410C  43 01          DECX R1              ; LF -> drop the CR too
410E  B4 01          GTL  L01
```

Identical retreat logic to L20 but emits **no** `BS SP BS` feedback — it just
silently moves the cursor back.

---

## L55 — ^K KILL LINE  ($4110 – $4174)

Two paths. **Path A** (`L5A`): current line has text → erase back to the previous
CR+LF and keep it. **Path B** (`L5C`/`L5D`): current line is empty (you just pressed
Enter) → roll back through that CR+LF and delete the *previous* line too, then redraw.

```
4110  B3 55          LBL  L55
4112  89 12          TESTLXY R1<=R2       ; buffer empty?
4114  A2 5B          IFTRUEL  L5B         ; -> just write EOF and return
4116  23 00 17       COPYXY R1 -> R7      ; R7 = cursor (peek pointer)
4119  43 07          DECX R7
411B  35 01 07       COPYIMXA Acc <- M(R7) [1b]   ; last stored byte
411E  81 00 0A       TESTAI $000A         ; was it an LF? (=> current line empty)
4121  A2 5C          IFTRUEL  L5C         ; yes -> Path B (kill previous line)

; ----- Path A: erase the current (non-empty) line back to the prior CR+LF -----
4123  B3 5A          LBL  L5A
4125  89 12          TESTLXY R1<=R2       ; hit buffer start?
4127  A2 5B          IFTRUEL  L5B         ; -> done
4129  23 00 17       COPYXY R1 -> R7
412C  43 07          DECX R7
412E  35 01 07       COPYIMXA Acc <- M(R7) [1b]
4131  81 00 0A       TESTAI $000A         ; previous byte is the line's LF?
4134  A2 5B          IFTRUEL  L5B         ; -> stop, keep that CR+LF
4136  43 01          DECX R1              ; erase one char of the current line
4138  CA 08          OUTL $08             ; BS SP BS feedback
413A  CA 20          OUTL $20
413C  CA 08          OUTL $08
413E  B4 5A          GTL  L5A

4140  B3 5B          LBL  L5B             ; write EOF marker + return
4142  10 00 00       LOADAI $0000
4145  36 01 01       COPYIAMX M(R1) <- Acc [1b]   ; $00 at cursor
4148  B4 01          GTL  L01

; ----- Path B: current line empty -> also remove the preceding line -----
414A  B3 5C          LBL  L5C
414C  43 01          DECX R1              ; step back over the LF
414E  89 12          TESTLXY R1<=R2
4150  A2 5E          IFTRUEL  L5E
4152  43 01          DECX R1              ; step back over the CR

4154  B3 5D          LBL  L5D             ; walk backward through the previous line
4156  89 12          TESTLXY R1<=R2
4158  A2 5E          IFTRUEL  L5E
415A  23 00 17       COPYXY R1 -> R7
415D  43 07          DECX R7
415F  35 01 07       COPYIMXA Acc <- M(R7) [1b]
4162  81 00 0A       TESTAI $000A         ; reached the LF ending the line-before?
4165  A2 5E          IFTRUEL  L5E         ; -> stop there
4167  43 01          DECX R1
4169  B4 5D          GTL  L5D

416B  B3 5E          LBL  L5E
416D  10 00 00       LOADAI $0000
4170  36 01 01       COPYIAMX M(R1) <- Acc [1b]   ; $00 at new cursor
4173  B4 10          GTL  L10             ; redraw the whole buffer via the ^V view
```

Path B leaves the screen out of sync with the buffer (a line vanished mid-screen),
so it re-enters **L10** to reprint the corrected text. Path A only removed the tail
of the current line, so its in-place `BS SP BS` feedback is enough — it returns to L01.

---

## L40 — CR (Enter)  ($4175 – $4193)

```
4175  B3 40          LBL  L40
4177  89 13          TESTLXY R1<=R3       ; room to store the CR?
4179  A3 41          IFFALSEL L41         ; no -> just echo CR/LF
417B  36 01 01       COPYIAMX M(R1) <- Acc [1b]   ; store CR ($0D still in Acc)
417E  42 01          INCX R1
4180  89 13          TESTLXY R1<=R3       ; room for the LF too?
4182  A3 41          IFFALSEL L41
4184  10 00 0A       LOADAI $000A         ; LF
4187  36 01 01       COPYIAMX M(R1) <- Acc [1b]   ; store LF
418A  42 01          INCX R1

418C  B3 41          LBL  L41
418E  CA 0D          OUTL $0D             ; echo CR
4190  CA 0A          OUTL $0A             ; echo LF
4192  B4 01          GTL  L01
```

A newline is stored as a **two-byte CR+LF pair** — which is exactly what the delete
paths (L20/L30/L55) look for when they special-case `$0A`.

---

## L50 — ^U CLEAR  ($4194 – $41A1)

```
4194  B3 50          LBL  L50
4196  FB 25 00       FILLMEMXY R2..R5 = $00   ; zero the entire buffer (start..last)
4199  23 00 21       COPYXY R2 -> R1          ; cursor back to start
419C  CA 0D          OUTL $0D
419E  CA 0A          OUTL $0A
41A0  B4 01          GTL  L01
```

One `FILLMEMXY` clears all 2048 bytes in a single opcode.

---

## L60 — ^E END (jump to end, replay, keep typing)  ($41A2 – $41D6)

```
41A2  B3 60          LBL  L60
41A4  23 00 24       COPYXY R2 -> R4          ; R4 = buffer start

41A7  B3 61          LBL  L61                 ; scan forward for first $00 (end of text)
41A9  87 43          TESTXY R4==R3            ; hit buffer end+1?
41AB  A2 62          IFTRUEL  L62
41AD  35 01 04       COPYIMXA Acc <- M(R4) [1b]
41B0  81 00 00       TESTAI $0000             ; found the $00 terminator?
41B3  A2 62          IFTRUEL  L62
41B5  42 04          INCX R4
41B7  B4 61          GTL  L61

41B9  B3 62          LBL  L62
41BB  23 00 41       COPYXY R4 -> R1          ; cursor := end of text
41BE  CA 0D          OUTL $0D
41C0  CA 0A          OUTL $0A
41C2  23 00 24       COPYXY R2 -> R4          ; R4 = start again (for replay)

41C5  B3 63          LBL  L63                 ; replay buffer start..cursor
41C7  87 14          TESTXY R1==R4
41C9  A2 64          IFTRUEL  L64
41CB  35 01 04       COPYIMXA Acc <- M(R4) [1b]
41CE  C9             OUTCH
41CF  42 04          INCX R4
41D1  B4 63          GTL  L63

41D3  B3 64          LBL  L64
41D5  B4 01          GTL  L01
```

Finds the text's `$00` terminator, parks the cursor there, then reprints everything
so you can continue appending. Also the **shared tail** for ^L (load), below.

---

## L65 — ^S SAVE to bank 1  ($41D7 – $4218)

```
41D7  B3 65          LBL  L65
41D9  10 00 00       LOADAI $0000
41DC  36 01 01       COPYIAMX M(R1) <- Acc [1b]   ; terminate text with $00 at cursor
41DF  11 06 10 00    LOADXI R6,$1000              ; src = buffer  (rel $1000 = real $5000)
41E3  11 07 20 00    LOADXI R7,$2000              ; dst = bank 1  (rel $2000 = real $6000)

41E7  B3 90          LBL  L90                     ; copy loop
41E9  35 01 06       COPYIMXA Acc <- M(R6) [1b]
41EC  36 01 07       COPYIAMX M(R7) <- Acc [1b]
41EF  42 06          INCX R6
41F1  42 07          INCX R7
41F3  81 00 00       TESTAI $0000                 ; copied byte was the $00 terminator?
41F6  A2 92          IFTRUEL  L92                 ; -> done
41F8  86 06 18 00    TESTXI R6==$1800             ; or reached end of buffer?
41FC  A2 92          IFTRUEL  L92
41FE  B4 90          GTL  L90

4200  B3 92          LBL  L92
4202  11 0A 07 1B    LOADXI RA,$071B              ; RA -> "File Saved"
4206  B3 84          LBL  L84                     ; print-string loop
4208  35 01 0A       COPYIMXA Acc <- M(RA) [1b]
420B  81 00 00       TESTAI $0000
420E  A2 85          IFTRUEL  L85
4210  C9             OUTCH
4211  42 0A          INCX RA
4213  B4 84          GTL  L84
4215  B3 85          LBL  L85
4217  B4 01          GTL  L01
```

Copies text (through the `$00`) from real $5000 into real $6000, then confirms
"File Saved".

---

## L66 — ^L LOAD bank 1  ($4219 – $423F)

```
4219  B3 66          LBL  L66
421B  11 06 20 00    LOADXI R6,$2000      ; src = bank 1  (real $6000)
421F  11 07 10 00    LOADXI R7,$1000      ; dst = buffer  (real $5000)

4223  B3 91          LBL  L91             ; copy loop
4225  35 01 06       COPYIMXA Acc <- M(R6) [1b]
4228  36 01 07       COPYIAMX M(R7) <- Acc [1b]
422B  42 06          INCX R6
422D  42 07          INCX R7
422F  81 00 00       TESTAI $0000         ; hit terminator?
4232  A2 93          IFTRUEL  L93
4234  86 06 28 00    TESTXI R6==$2800     ; or end of save bank?
4238  A2 93          IFTRUEL  L93
423A  B4 91          GTL  L91

423C  B3 93          LBL  L93
423E  B4 60          GTL  L60             ; reuse ^E: find end + replay the loaded text
```

After restoring bank 1 into the buffer it jumps into **L60 (^E)** so the cursor is
placed at the end and the loaded text is echoed to the screen.

---

## L67 — ^G HELP  ($4240 – $4258)

```
4240  B3 67          LBL  L67
4242  11 0A 07 5B    LOADXI RA,$075B      ; RA -> help text (real $475B)
4246  B3 88          LBL  L88             ; print-string loop
4248  35 01 0A       COPYIMXA Acc <- M(RA) [1b]
424B  81 00 00       TESTAI $0000
424E  A2 89          IFTRUEL  L89
4250  C9             OUTCH
4251  42 0A          INCX RA
4253  B4 88          GTL  L88
4255  B3 89          LBL  L89
4257  B4 01          GTL  L01
```

---

## L70 — ^W WRITE to a chosen 16-bit address  ($4259 – $4329)

Prompts `Where? `, reads **four hex digits** = a full 16-bit relative address
(`d1 d2` = HIGH byte, `d3 d4` = LOW byte), copies the buffer there, prints `Copied`.

```
4259  B3 70          LBL  L70
425B  CA 0D          OUTL $0D
425D  CA 0A          OUTL $0A
425F  11 0A 07 D0    LOADXI RA,$07D0      ; RA -> "Where? "
4263  B3 71          LBL  L71             ; print the prompt
4265  35 01 0A       COPYIMXA Acc <- M(RA) [1b]
4268  81 00 00       TESTAI $0000
426B  A2 72          IFTRUEL  L72
426D  C9             OUTCH
426E  42 0A          INCX RA
4270  B4 71          GTL  L71

4272  B3 72          LBL  L72
4274  11 08 00 0A    LOADXI R8,$000A      ; R8 = 10  (nibble>=10 means it was a letter A-F)
```

### Digit 1 → high nibble of the HIGH byte

```
4278  10 00 00       LOADAI $0000
427B  CB             INCH                 ; read digit 1
427C  C9             OUTCH                ; echo it
427D  4F 00 30       SUBAI $0030          ; ASCII -> value ('0'..'9' -> 0..9)
4280  21 0B          COPYAX Acc -> RB     ; RB = value
4282  88 B8          TESTGXY RB>=R8       ; value >= 10 ? (i.e. an A-F letter)
4284  A3 73          IFFALSEL L73         ; no -> it's 0-9, skip letter fixup
4286  4F 00 07       SUBAI $0007          ; letter fixup: 'A'($41)-$30-$07 = $0A

4289  B3 73          LBL  L73
428B  60 00          SHIFTBA left         \
428D  60 00          SHIFTBA left          | nibble << 4  (promote to high nibble)
428F  60 00          SHIFTBA left          |
4291  60 00          SHIFTBA left         /
4293  21 07          COPYAX Acc -> R7     ; R7 = d1<<4
```

### Digit 2 → low nibble of the HIGH byte

```
4295  10 00 00       LOADAI $0000
4298  CB             INCH                 ; read digit 2
4299  C9             OUTCH
429A  4F 00 30       SUBAI $0030
429D  21 0B          COPYAX Acc -> RB
429F  88 B8          TESTGXY RB>=R8
42A1  A3 74          IFFALSEL L74
42A3  4F 00 07       SUBAI $0007

42A6  B3 74          LBL  L74
42A8  46 07          ADDAX Acc+R7 -> MA   ; d2 + (d1<<4) = HIGH byte
42AA  25             COPYMAA MA -> Acc
42AB  15             SWAPA                ; move HIGH byte into Acc's HIGH position ($00HH -> $HH00)
42AC  21 07          COPYAX Acc -> R7     ; R7 = HIGH<<8
```

### Digit 3 → high nibble of the LOW byte

```
42AE  10 00 00       LOADAI $0000
42B1  CB             INCH                 ; read digit 3
42B2  C9             OUTCH
42B3  4F 00 30       SUBAI $0030
42B6  21 0B          COPYAX Acc -> RB
42B8  88 B8          TESTGXY RB>=R8
42BA  A3 75          IFFALSEL L75
42BC  4F 00 07       SUBAI $0007

42BF  B3 75          LBL  L75
42C1  60 00          SHIFTBA left         \
42C3  60 00          SHIFTBA left          | d3 << 4
42C5  60 00          SHIFTBA left          |
42C7  60 00          SHIFTBA left         /
42C9  46 07          ADDAX Acc+R7 -> MA   ; (d3<<4) + HIGH<<8
42CB  25             COPYMAA MA -> Acc
42CC  21 07          COPYAX Acc -> R7     ; R7 = $HH(d3)0
```

### Digit 4 → low nibble of the LOW byte

```
42CE  10 00 00       LOADAI $0000
42D1  CB             INCH                 ; read digit 4
42D2  C9             OUTCH
42D3  4F 00 30       SUBAI $0030
42D6  21 0B          COPYAX Acc -> RB
42D8  88 B8          TESTGXY RB>=R8
42DA  A3 7B          IFFALSEL L7B
42DC  4F 00 07       SUBAI $0007

42DF  B3 7B          LBL  L7B
42E1  46 07          ADDAX Acc+R7 -> MA   ; d4 + $HH(d3)0 = full 16-bit rel address
42E3  25             COPYMAA MA -> Acc
42E4  21 07          COPYAX Acc -> R7     ; R7 = destination pointer  (d1 d2 d3 d4)
```

### Terminate text, then copy buffer → R7

```
42E6  10 00 00       LOADAI $0000
42E9  36 01 01       COPYIAMX M(R1) <- Acc [1b]   ; $00 terminator at cursor
42EC  11 06 10 00    LOADXI R6,$1000              ; src = buffer start

42F0  B3 76          LBL  L76                     ; copy loop
42F2  35 01 06       COPYIMXA Acc <- M(R6) [1b]
42F5  36 01 07       COPYIAMX M(R7) <- Acc [1b]
42F8  42 06          INCX R6
42FA  42 07          INCX R7
42FC  81 00 00       TESTAI $0000                 ; copied the terminator?
42FF  A2 77          IFTRUEL  L77
4301  86 06 18 00    TESTXI R6==$1800             ; or end of buffer?
4305  A2 77          IFTRUEL  L77
4307  B4 76          GTL  L76

4309  B3 77          LBL  L77
430B  CA 0D          OUTL $0D
430D  CA 0A          OUTL $0A
430F  11 0A 07 D8    LOADXI RA,$07D8              ; RA -> "Copied"
4313  B3 78          LBL  L78                     ; print-string loop
4315  35 01 0A       COPYIMXA Acc <- M(RA) [1b]
4318  81 00 00       TESTAI $0000
431B  A2 79          IFTRUEL  L79
431D  C9             OUTCH
431E  42 0A          INCX RA
4320  B4 78          GTL  L78
4322  B3 79          LBL  L79
4324  CA 0D          OUTL $0D
4326  CA 0A          OUTL $0A
4328  B4 01          GTL  L01
```

Each ASCII digit is converted with `-$30`, and if it's `>= 10` after that (a letter)
an extra `-$07` maps `'A'..'F'` → `10..15`. The four nibbles are assembled purely
with 4-bit shifts and `ADDAX`, plus one `SWAPA` to promote the HIGH byte — no 16-bit
shift is ever needed. In relative mode the VM adds `$4000`, so e.g. `2000` → real
`$6000` (bank 1), `1000` → real `$5000` (the buffer itself).

> **Build note:** the ^W path deliberately zeroes the accumulator with `LOADAI 00 00`
> (`10 00 00`) rather than `CLEARA ($6A)` — this build's `$6A` handler crashed the VM.

---

## LFE — ^X EXIT  ($432A – $4336)

```
432A  B3 FE          LBL  LFE
432C  10 00 00       LOADAI $0000
432F  36 01 01       COPYIAMX M(R1) <- Acc [1b]   ; write $00 sentinel at cursor
4332  CA 0D          OUTL $0D
4334  CA 0A          OUTL $0A
4336  00             HALT                         ; text remains in RAM at $5000
```

Terminates the text and halts the VM. Because the buffer lives in RAM that this VM
owns, the text survives; a later run detects it via the L81 "Text is Present" check.

---

# STRING SEGMENT  ($4700 – $47DE)

All strings are null-terminated. The print loops load `RA` with the **relative**
offset (`$07xx`); the VM adds `$4000` to reach these real addresses.

| Real addr | Rel (RA) | Contents |
|---|---|---|
| $4700 | $0700 | `"Lite-Writer for the 1802\r\n"` — startup banner |
| $471B | $071B | `"File Saved\r\n"` — after ^S |
| $4728 | $0728 | `"Text is Present\r\n"` — startup, if buffer non-empty |
| $473A | $073A | `"You are nearing the size limit\r\n"` — once at $17E0 |
| $475B | $075B | help screen (`^D del char … ^G help`) |
| $47D0 | $07D0 | `"Where? "` — ^W prompt |
| $47D8 | $07D8 | `"Copied"` — after ^W |

---

# Label cross-reference

| Label | Addr | Role |
|---|---|---|
| L80 | $401E | banner print loop |
| L81 | $402D | "Text is Present?" check |
| L82/L83 | $403B/$404A | present-string print loop / exit |
| **L01** | **$404C** | **main input loop + key dispatch** |
| L04 | $40A0 | size-limit warning |
| L86/L87 | $40A6/$40B5 | warning print loop / exit |
| L10 | $40B9 | ^V view |
| L11/L12 | $40C2/$40D0 | view print loop / exit |
| L20 | $40D8 | backspace (DEL/BS) |
| L22 | $40EE | BS-SP-BS feedback |
| L30 | $40F8 | ^D delete (no echo) |
| L55 | $4110 | ^K kill-line entry |
| L5A | $4123 | ^K Path A (erase current line) |
| L5B | $4140 | ^K write EOF + return |
| L5C/L5D | $414A/$4154 | ^K Path B (kill previous line) |
| L5E | $416B | ^K Path B finish → redraw |
| L40/L41 | $4175/$418C | CR store CR+LF / echo |
| L50 | $4194 | ^U clear |
| L60 | $41A2 | ^E end (find end) |
| L61/L62 | $41A7/$41B9 | end-scan loop / found |
| L63/L64 | $41C5/$41D3 | replay loop / exit |
| L65 | $41D7 | ^S save |
| L90/L92 | $41E7/$4200 | save copy loop / done |
| L84/L85 | $4206/$4215 | "File Saved" print loop / exit |
| L66 | $4219 | ^L load |
| L91/L93 | $4223/$423C | load copy loop / done → L60 |
| L67 | $4240 | ^G help |
| L88/L89 | $4246/$4255 | help print loop / exit |
| L70 | $4259 | ^W write |
| L71/L72 | $4263/$4272 | prompt print loop / decode start |
| L73/L74/L75/L7B | $4289/$42A6/$42BF/$42DF | per-digit letter-fixup joins |
| L76/L77 | $42F0/$4309 | ^W copy loop / done |
| L78/L79 | $4313/$4322 | "Copied" print loop / exit |
| LFE | $432A | ^X exit / HALT |

*(51 labels, 81 branch targets — all verified to have a matching `LBL`.)*
