# STELLAR Project Notes — Session 15 Interrupt Redesign

## Status: All 13 implementation steps designed and verified. Ready to enter into Emma 02.

---

## Architecture Quickref

- **CPU:** RCA COSMAC CDP1802/1805/1806, hand-assembled hex
- **SCRT:** R3=PC, R4=CALL($0340), R5=RETURN($0360), R6=link, R2=HW stack
- **VMs:** Up to 4 cooperative VMs; program mem $4000/$5000/$6000/$7000; cores $3000/$3400/$3800/$3C00
- **CIDP VM array** ($2F00–$2F3F): 4 entries × 16 bytes
  - Byte[00]=VM#, [01]=Core page, [02]=ProgLoc, [03]=MaxSize, [04]=Count, [05]=State, [06-09]=#Cmds, [0A]=Mode, [0B]=Status
- **CIDP State values:** $00=Done, $01=Active, $02=Completed This Cycle (Repeat), $05=Killed

## CIDP System Registers ($2F50–$2F5F)

| Addr | Name | Default | Notes |
|------|------|---------|-------|
| $2F50 | System Interrupt State | $00 | $00=Single $01=Counter $02=HW Int $03=1805 Ctr $0E=Error |
| $2F51 | VM Error Register | $00 | $00=None $01=No VMs $02=Aborted |
| $2F52 | Current VM# | $00 | Updated by Do_Next_Task at $00D7–$00DA (already exists) |
| $2F53 | MAX VMs | $04 | Fixed |
| $2F54 | Total VMs Present | $04 | Decremented when VM ends |
| $2F55 | Multitasking Permitted | $01 | $00=No $01=Yes |
| $2F56 | VM Operation | $01 | $00=Sequential $01=Simultaneous |
| $2F57 | VM Repeat | $00 | $00=Run to End $01=Repeat |
| $2F5F | HW Interrupt Flip-flop | $00 | Set by R1 handler for modes $02/$03 |

## Key Function Addresses

| Function | Address | Notes |
|----------|---------|-------|
| Main loop | $0050 | Entry point each tick |
| Do_Next_Task | $0080 | Scans CIDP for State=$01 VMs |
| End_Last_VM | $00E5 | Fires when no State=$01 VM found → redirect to $2D98 |
| CALL routine | $0340 | SCRT call |
| RETURN routine | $0360 | SCRT return |
| End_Current_VM | $0B90 | State setter at $0BA8 → redirect to $2DF3 |
| CHECK_CORE_MEM | $0B70 | RAM integrity test (AA/55), NOT program validity |
| CREATE_CIDP | $0C00 | D5 (RETURN) at $0C6C → redirect to $2E09 |
| VALIDATE_VM | $0C70 | Separate function, immediately after CREATE_CIDP |
| SETSTATE ($C7) | $2560 | Rewritten in Step 1 |
| EINT ($C5) | $2570 | Unchanged; `18 C0 00 50` at $2577 reused by SETSTATE |
| KILLVM ($CF V0) | $2690 | Zeroes M(ProgLoc) at $26AB AND sets State=$05 |
| BRK ($F0) | $26D0 | Explicit end-of-program; 1-byte fix at $26E1 |

## Free Space Used (Session 15)

| Range | Content |
|-------|---------|
| $1D40–$1D76 | R1 interrupt handler (55 bytes) |
| $2D40–$2D4D | SETSTATE mode $03 — 1805 counter setup (14 bytes) |
| $2D60–$2D87 | Counter check handler (40 bytes) |
| $2D88–$2D97 | $2F5F flip-flop handler (16 bytes) |
| $2D98–$2DF2 | End_Last_VM handler (91 bytes) |
| $2DF3–$2E08 | End_Current_VM state setter (22 bytes) |
| $2E09–$2E42 | CREATE_CIDP init stub (58 bytes) |

---

## Complete D-Lines — All 13 Steps

### Step 1 — SETSTATE rewrite ($2560–$256F, 16 bytes)
```
D 2560 F8 2F BF    ; PHI RF → RF.hi=$2F
D 2563 F8 50 AF    ; PLO RF → RF=$2F50
D 2566 18 08 5F    ; INC R8; LDN R8; STR RF → M($2F50)=mode
D 2569 FB 03       ; XRI $03
D 256B C2 2D 40    ; LBZ $2D40 → mode $03: 1805 setup
D 256E 30 77       ; BR $2577 → reuse EINT's INC R8; LBR $0050
```

### Step 2 — SETSTATE mode $03 ($2D40–$2D4D, 14 bytes)
```
D 2D40 18 08       ; INC R8; LDN R8 → D=NN
D 2D42 68 00       ; STPC
D 2D44 68 06       ; LDC
D 2D46 68 07       ; STM
D 2D48 68 0C       ; CIE
D 2D4A 18          ; INC R8
D 2D4B C0 00 50    ; LBR $0050
```

### Step 3 — Main loop Sequential gate (1 byte)
```
D 005F F8 56 AA    ; was F8 50 AA
```

### Step 4 — Main loop mode dispatch ($0066–$007B, 22 bytes)
```
D 0066 F8 50 AA    ; RA=$2F50
D 0069 0A          ; LDN RA
D 006A C2 01 00    ; LBZ $0100 → mode $00: Run Program
D 006D FB 01       ; XRI $01
D 006F C2 2D 60    ; LBZ $2D60 → mode $01: counter handler
D 0072 C0 2D 88    ; LBR $2D88 → modes $02/$03/$0E: flip-flop handler
D 0075 C4 C4 C4 C4 C4 C4 C4
```

### Step 5 — Counter check handler ($2D60–$2D87, 40 bytes)
```
D 2D60 F8 2F BF
D 2D63 F8 54 AF    ; RF=$2F54
D 2D66 0F FB 01    ; LDN RF; XRI $01
D 2D69 C2 01 00    ; LBZ $0100 → 1 VM: skip
D 2D6C F8 56 AF    ; RF=$2F56
D 2D6F 0F
D 2D70 C2 01 00    ; LBZ $0100 → Sequential: skip
D 2D73 9C BB       ; GHI RC; PHI RB
D 2D75 F8 5F AB    ; RB=$305F
D 2D78 EB          ; SEX RB
D 2D79 F8 5E AC    ; RC=$305E
D 2D7C 0C F5       ; LDN RC; SD
D 2D7E C7 00 80    ; LBNF $0080 → Do_Next_Task
D 2D81 0C FC 01 5C ; LDN RC; ADI $01; STR RC
D 2D85 C0 01 00    ; LBR $0100
```

### Step 6 — $2F5F flip-flop handler ($2D88–$2D97, 16 bytes)
```
D 2D88 F8 2F BF
D 2D8B F8 5F AF    ; RF=$2F5F
D 2D8E 0F
D 2D8F C2 01 00    ; LBZ $0100 → no interrupt
D 2D92 F8 00 5F    ; clear flip-flop
D 2D95 C0 00 80    ; LBR $0080
```

### Step 7 — R1 handler ($1D40–$1D76, 55 bytes)
```
D 1D40 78 22
D 1D42 9F 73       ; save RF.hi
D 1D44 8F 73       ; save RF.lo
D 1D46 F8 2F BF
D 1D49 F8 55 AF    ; RF=$2F55
D 1D4C 0F
D 1D4D C2 1D 6E    ; LBZ $1D6E → check $304C
D 1D50 F8 50 AF    ; RF=$2F50
D 1D53 0F
D 1D54 FB 02       ; XRI $02
D 1D56 C2 1D 60    ; LBZ $1D60
D 1D59 FB 01       ; XRI $01
D 1D5B C2 1D 60    ; LBZ $1D60
D 1D5E 30 66       ; BR $1D66
D 1D60 F8 5F AF    ; RF=$2F5F
D 1D63 F8 01 5F    ; M($2F5F)=$01
D 1D66 12
D 1D67 72 AF       ; restore RF.lo
D 1D69 72 BF       ; restore RF.hi
D 1D6B 22 78
D 1D6D 71          ; DIS
D 1D6E F8 4C AF    ; RF=$304C
D 1D71 0F
D 1D72 C2 1D 66    ; LBZ $1D66
D 1D75 30 60       ; BR $1D60
```

### Step 8 — BRK fix (1 byte)
```
D 26E1 F8 55 AA    ; was F8 50 AA
```

### Step 9 — End_Current_VM redirect ($0BA8–$0BAB)
```
D 0BA8 C0 2D F3    ; LBR $2DF3
D 0BAB C4
```

### Step 10 — End_Current_VM state setter ($2DF3–$2E08, 22 bytes)
```
D 2DF3 F8 2F BF
D 2DF6 F8 57 AF    ; RF=$2F57
D 2DF9 0F
D 2DFA C2 2E 02    ; LBZ $2E02
D 2DFD F8 02 5A    ; State=$02 (Repeat)
D 2E00 30 05       ; BR $2E05
D 2E02 F8 00 5A    ; State=$00 (non-Repeat)
D 2E05 1A          ; INC RA
D 2E06 C0 0B AC    ; LBR $0BAC
```

### Step 11 — End_Last_VM redirect ($00E5)
```
D 00E5 C0 2D 98
D 00E8 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4
```

### Step 12 — End_Last_VM handler ($2D98–$2DF2, 91 bytes)
```
D 2D98 F8 2F BF
D 2D9B F8 57 AF    ; RF=$2F57
D 2D9E 0F
D 2D9F CA 2D B1    ; LBNZ $2DB1 → Repeat path
D 2DA2 F8 52 AF    ; RF=$2F52
D 2DA5 F8 00 5F
D 2DA8 F8 50 AF    ; RF=$2F50
D 2DAB F8 00 5F
D 2DAE C0 26 00    ; LBR $2600 (halt)
D 2DB1 F8 2F BA    ; RA.hi=$2F
D 2DB4 F8 05 AA    ; VM1: RA=$2F05
D 2DB7 0A FB 02
D 2DBA C2 2D C0    ; LBZ $2DC0
D 2DBD 30 C3       ; BR $2DC3
D 2DC0 F8 01 5A    ; State=$01
D 2DC3 F8 15 AA    ; VM2: RA=$2F15
D 2DC6 0A FB 02
D 2DC9 C2 2D CF    ; LBZ $2DCF
D 2DCC 30 D2       ; BR $2DD2
D 2DCF F8 01 5A
D 2DD2 F8 25 AA    ; VM3: RA=$2F25
D 2DD5 0A FB 02
D 2DD8 C2 2D DE    ; LBZ $2DDE
D 2DDB 30 E1       ; BR $2DE1
D 2DDE F8 01 5A
D 2DE1 F8 35 AA    ; VM4: RA=$2F35
D 2DE4 0A FB 02
D 2DE7 C2 2D ED    ; LBZ $2DED
D 2DEA 30 F0       ; BR $2DF0
D 2DED F8 01 5A
D 2DF0 C0 00 80    ; LBR $0080
```

### Step 13 — CREATE_CIDP init (two changes)

**13a — $0C6C (3 bytes, uses dead space $0C6C–$0C6E):**
```
D 0C6C C0 2E 09    ; LBR $2E09 (was D5; VALIDATE_VM is at $0C70)
```

**13b — Init stub ($2E09–$2E42, 58 bytes):**
```
D 2E09 F8 2F BA    ; RA.hi=$2F
D 2E0C F8 50 AA
D 2E0F F8 00 5A    ; $2F50=$00 Single
D 2E12 F8 51 AA
D 2E15 F8 00 5A    ; $2F51=$00 no errors
D 2E18 F8 52 AA
D 2E1B F8 00 5A    ; $2F52=$00
D 2E1E F8 53 AA
D 2E21 F8 04 5A    ; $2F53=$04 MAX VMs
D 2E24 F8 54 AA
D 2E27 F8 04 5A    ; $2F54=$04 total VMs
D 2E2A F8 55 AA
D 2E2D F8 01 5A    ; $2F55=$01 multitasking permitted
D 2E30 F8 56 AA
D 2E33 F8 01 5A    ; $2F56=$01 Simultaneous
D 2E36 F8 57 AA
D 2E39 F8 00 5A    ; $2F57=$00 Run to End
D 2E3C F8 5F AA
D 2E3F F8 00 5A    ; $2F5F=$00 flip-flop clear
D 2E42 D5          ; RETURN (from CREATE_CIDP)
```

---

## Key Discoveries / Corrections vs Original Plan

1. **$2F52 already written** at $00D7–$00DA in existing Do_Next_Task — no new code needed
2. **Step 13 inline insertion impossible** — VALIDATE_VM ($0C70) immediately follows CREATE_CIDP's D5 ($0C6C), only 3 dead bytes between them. Solution: LBR from $0C6C to stub at $2E09.
3. **SETSTATE fits in 16 bytes** (not 18) by using `BR $2577` to reuse EINT's existing `18 C0 00 50`
4. **BNF short branch** on page $2D would target $2D80 not $0080 — use LBNF ($C7) instead
5. **End_Current_VM** does NOT zero byte[00] — only KILLVM does. Repeat mode safe.
6. **CHECK_CORE_MEM ($0B70)** tests core RAM ($30xx) with AA/55, NOT program byte[00]

## SETQM Opcode ($0DBB–$0DFD) — Desktop version (Mar 1)

Plays Q-pin tone sequence from address MM:MM (absolute or relative).
- $0DBB–$0DC0: absolute/relative check; RC=$303B, LDN RC; BZ→absolute path; else RC=$305B/SEX RC
- $0DC1–$0DC8: INC R8; LDA R8; ADD (relative: +M($305B) offset); PHI RD → RD.hi set
- $0DCA: AD = PLO RD; $0DCB: LDN RD (main loop)
- Pattern byte: high nibble=H (frequency), low nibble=L (repeat count); $FF=pause, $00=end
- RE.lo=L (repeat), RF=H:H (half-period); Q=0 loop then Q=1 loop, then DEC RE; repeat L times
- BNZ goes back to $0DDD (Q=0 loop start), not $0DCA (avoids resetting RE/RF)
- Bug fixes (3): $0DC0 BZ target C9→C4; PLO RD restored at $0DCA; BNZ target CA→DD

## Break_Out_Of_Stellar ($02C0–$02D2)
- Bug at $02CD: `01` (LDN R1) should be `0A` (LDN RA) — reads M($2F5E)=$4D for R1.lo
- Fix: `D 02CD 0A`
- Exit: E2 79 D1 (SEX R2; SAV; SEP R1) — currently unreliable, needs revisiting

## Pending
- **FIX REG_DUMP short branch targets** (priority, see Session 17) — 2 bytes
- **Enter all 13 Session 15 steps into Emma 02**
- **Fix Break_Out_Of_Stellar: `D 02CD 0A`**
- **STELLAR exit mechanism** (E2 79 D1 unreliable) — revisit with new ideas
- Update `<cpu>1802</cpu>` → `<cpu>1805</cpu>` when using mode $03
- Test full Session 15 implementation

## Working File Location
- **Active:** `~/Desktop/Stellar_Code_Work/STELLAR Full Code.rtf`
- **Repo:** `~/Projects/stellar-1802/STELLAR Full Code.rtf`
- Last commit: Session 17 (see below)

---

## Session 16 — 2-VM Multitasking Crash

### Symptom
STELLAR crashes when two programs loaded ($4000 and $5000). Single VM works fine.

### Root Cause: Register Save Format Mismatch

**VM_SCANNER** ($0A30): saves 8 register pairs via STXD starting at **core:$FD**:
`RE.hi, RE.lo, RD.hi, RD.lo, RC.hi, RC.lo, RB.hi, RB.lo, RA.hi, RA.lo, R9.hi, R9.lo, R8.hi, R8.lo, R7.hi, R7.lo`
→ R8.hi lands at **core:$F0**, R8.lo at **core:$F1**

**REG_DUMP** ($0510): saves 9 register pairs via STXD starting at **core:$FF**:
`RF.hi, RF.lo, RE.hi, RE.lo, RD.hi, RD.lo, RB.hi, RB.lo, RA.hi, RA.lo, R9.hi, R9.lo, R8.hi, R8.lo, R7.hi, R7.lo, R2.hi, R2.lo`
→ R8.hi lands at **core:$F2**, R8.lo at **core:$F3**

**REG_RESTORE** ($0565 entry): reads R8.hi from **core:$F2** (REG_DUMP format).
On first switch to VM2, core was written by VM_SCANNER (old format) → REG_RESTORE reads R9.hi as R8.hi → R8 = garbage → Run Program executes from wrong address → crash.

**Second compounding bug**: Do_Next_Task calls `CALL $0565` with RC.lo=$EE left over from REG_DUMP. REG_RESTORE at $0565 uses SEX RC then LDXA — reads from core:$EE area (wrong stack positions).

### Proposed Fix (3 parts)

**Fix A — VM_SCANNER save format** (make it match REG_DUMP: start at $FF, save RF not RC):
```
D 0AD1 F8 FF AC          ; PLO RC=$FF (was F8 FD AC for $FD)
D 0AD5 8F 73 9F 73 8E 73 9E 73 8D 73 9D 73   ; save RF,RE,RD (was RC,RB,RA start)
```

**Fix B — Do_Next_Task CALL target** (call stub not REG_RESTORE directly):
```
D 00DF D4 2E 43          ; CALL $2E43 (was D4 05 65)
```
⚠️ Craig placed the stub at a different address than $2E43 (see below). Fix B must match.

**Fix C — Restore stub** (sets RC=$F0, SEX RC, then jumps into REG_RESTORE):
```
D 2E43 F8 F0 AC EC C0 05 62   ; PLO RC=$F0; SEX RC; LBR $0562
```
Note: $2E43 is the byte immediately after Session 15 CREATE_CIDP stub's D5 at $2E42.

### Status: Still Crashing

Craig entered Fixes A and B as written, but placed the stub (Fix C) **"just above REG_RESTORE"** instead of at $2E43. REG_RESTORE is at $0550/$0562. "Just above" likely means the 7-byte stub is around $0549–$054F.

**Why it still crashes**: Fix B calls $2E43 (empty space), not where Craig placed the stub.

### Resolution Needed

Before next session, determine where Craig placed the stub:
- If stub is at $0549: change Fix B → `D 00DF D4 05 49`
- If stub is at a different address: update accordingly
- OR: delete stub from wherever Craig placed it, and enter Fix C at $2E43 (keeping Fix B as written)

### Additional Key Addresses Decoded (Session 16)

| Address | Content |
|---------|---------|
| $0008 | Default Max Task Count = $03 |
| $0009 | Number of VMs = $04 |
| $000A | MaxSize = $10 |
| $000B | $3F |
| $0050–$007F | Main loop (checks $2F55, $2F50, counter) |
| $0080–$00E4 | Do_Next_Task (scans CIDP, REG_DUMP, REG_RESTORE) |
| $00E5–$00F9 | End_Last_VM old code (Session 15 redirect not yet entered) |
| $0100–$014F | Run Program (opcode dispatch, breakpoint check) |
| $0510–$0544 | REG_DUMP: saves RF,RE,RD,RB,RA,R9,R8,R7,R2; R8.hi@$F2 |
| $0550–$058C | REG_RESTORE: full entry $0550; partial $0562 (R7+); partial $0565; D5 at $058C |
| $0A30–$0B66 | VM_SCANNER: zeros cores, saves registers, sets State, sets M($2F50) |
| $0B70–$0B82 | CHECK_CORE_MEM: AA/55 pattern test |
| $0B90–$0BBA | End_Current_VM |
| $0C00–$0C6C | CREATE_CIDP |

### M($2F50) Auto-Set by VM_SCANNER
- 1 VM active → M($2F50)=$00 → BRK → Break_Out_Of_Stellar (single VM path, no crash)
- 2+ VMs active → M($2F50)=$02 → BRK → Do_Next_Task (multi-VM path, triggers crash)

---

## Session 17 — Multitasking Crash Fix + DLYI Rewrite

### Current Memory Map (updated)

| Address | Function |
|---------|----------|
| $0500–$0534 | REG_DUMP (moved from $0510; D5 RETURN now at $0534) |
| $0535–$053F | Dead space |
| $0540–$0546 | Restore stub (PLO RC=$F0; SEX RC; LBR $0562) |
| $0547–$054F | Dead space |
| $0550–$058C | REG_RESTORE (unchanged) |

### Do_Next_Task Call Targets (current)
- `$0086: D4 05 00` → CALL REG_DUMP at $0500 ✓
- `$00DF: D4 05 40` → CALL stub at $0540 → REG_RESTORE ✓

### VM_SCANNER Fix A (confirmed in file)
Saves RF,RE,RD,RB,RA,R9,R8,R7 from $FF (matches REG_DUMP format).
R7.hi@$F0, R7.lo@$F1, R8.hi@$F2, R8.lo@$F3 (both VM_SCANNER and REG_DUMP now identical). ✓

### REG_DUMP Branch Bug — TWO BYTES STILL NEED FIXING
When Craig moved REG_DUMP from $0510→$0500, the EF1-save short branches were NOT updated.
They still point to the OLD addresses (stub area) instead of the shifted code positions.

**Fix (only 2 D-lines):**
```
D 052B 39 31    ; BN1 $31 → $0531 (EF1=0 path: LDI $01)  was 39 41 (→ $0541 = stub!)
D 052F 30 33    ; BR  $33 → $0533 (STR RC)                was 30 43 (→ $0543 = stub!)
```
Until these are entered, REG_DUMP's EF1 save jumps into the restore stub and crashes.

### Parse Command — Key Discovery
`$0156: 08 = LDN R8` — Parse Command uses LDN (not LDA). **R8 points to the opcode byte
(not the operand) when the handler is entered.** All opcode handlers must INC R8 first
to advance past the opcode before reading operands.

### DLYI (C0 NN) — Complete Rewrite at $1D00
Handler rewritten by Craig to account for LDN dispatch (R8 → C0 at entry).

**Design:**
- INC R8 at start → R8 → NN
- If NN=0: INC R8 (past NN), LBR $0050
- If core:$4D=0 (first call): initialize $4D=$44=NN, fall through to decrement
- Inner busy-wait loop: RF=$0202, DEC RF/GHI RF/BNZ (~259 iterations of physical CPU time)
- SMI $01 (`FF 01`) decrements M(core:$4D)
- If count reaches 0: INC R8 twice (past C0 and NN), LBR $0050
- If still counting: DEC R8 (restore R8→C0), LBNZ $0050

**SMI instruction:** `$FF bb` = SMI bb = D − bb (Subtract Memory Immediate). Valid 1802 opcode.

**RF clobbering:** Inner loop leaves RF=$00FF. Harmless — main loop at $0053 reinitializes
RF.lo=$06 (`F8 06 AF`) before using RF.

**D-lines (as entered, verified correct):**
```
D 0980 1D 00                              ; jump table: C0 → $1D00

D 1D00 18                                 ; INC R8 (C0 → NN)
D 1D01 08 32 25                           ; LDN R8; BZ $1D25 (NN=0 → done)
D 1D04 F8 4D AC                           ; PLO RC=$4D
D 1D07 0C 3A 14                           ; LDN RC; BNZ $1D14 (counting)
D 1D0A 08 5C                              ; LDN R8; STR RC → M($4D)=NN
D 1D0C F8 44 AC                           ; PLO RC=$44
D 1D0F 08 5C                              ; LDN R8; STR RC → M($44)=NN
D 1D11 F8 4D AC                           ; PLO RC=$4D
D 1D14 28                                 ; DEC R8 (NN → C0)
D 1D15 F8 02 BF AF                        ; RF=$0202 (inner loop setup)
D 1D19 2F 9F 3A 19                        ; DEC RF; GHI RF; BNZ $1D19 (~259 iters)
D 1D1D 0C FF 01 5C                        ; LDN RC; SMI $01; STR RC → M($4D)-=1
D 1D21 CA 00 50                           ; LBNZ $0050 (still counting)
D 1D24 18 18                              ; INC R8; INC R8 (past C0 and NN)
D 1D26 C0 00 50                           ; LBR $0050
```

**Note on timing:** Each STELLAR "tick" of DLYI burns ~259 DEC RF iterations (real CPU cycles)
plus the STELLAR command overhead. NN = number of ticks before advancing. Calibrate accordingly.
