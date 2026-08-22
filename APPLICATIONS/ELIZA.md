# ELIZA for STELLAR — Design Doc

A STELLAR (1802 vCPU) port of the classic ELIZA "conversation" program — a
terminal chatbot that fakes a Rogerian therapist with pattern-matching, no AI.

Status: **design / not yet built.** Target file: `APPLICATIONS/ELIZA.lst`.

---

## 1. Background (so the design is grounded)

- Weizenbaum's original ELIZA (1966) was MAD-SLIP on an IBM 7094. The famous
  "type it in from the magazine" version is **Jeff Shrager's BASIC port (1973,
  Creative Computing 1977)** — that's the model here.
- The BASIC version is small and data-driven: **36 keywords, 112 response
  strings, 6 pronoun-swap pairs.** No intelligence — just keyword lookup +
  canned replies + pronoun flipping.

## 2. Scope — two phases

- **Phase 1 — "Lite-ELIZA"** (build first): ~12 keywords, ~30 responses, 3
  pronoun swaps, fallback replies, quit word. Proves the engine end to end.
- **Phase 2 — full ELIZA**: grow the data toward 36 keywords / 112 responses.
  **The engine does not change — only the data tables grow.** That's the whole
  point of the data-driven design.

## 3. How ELIZA works (the loop we're implementing)

```
greet
repeat:
    print "> "
    read a line into INPUT           (echo, handle backspace, stop on CR)
    normalize: uppercase; pad with one leading + trailing space
    scan keyword table in priority order for a substring match in INPUT
    if a keyword matched:
        pick response = block[rot]; rot = (rot+1) mod N     (per-keyword rotate)
        copy response -> OUTPUT
        if response ends with the APPEND marker:
            fragment = INPUT text AFTER the matched keyword
            pronoun-swap the fragment (YOU<->I, MY<->YOUR, ARE<->AM, ...)
            append swapped fragment -> OUTPUT
    else:
        use a rotating FALLBACK reply ("PLEASE GO ON.", "TELL ME MORE.", ...)
    print OUTPUT + CRLF
until INPUT is a quit word (BYE / QUIT)
```

Example: input `I AM SAD` → keyword `I AM`, fragment `SAD`, response
`"HOW LONG HAVE YOU BEEN \*"` → output `HOW LONG HAVE YOU BEEN SAD?`

## 4. Memory map (uses the Lite-Writer block technique)

`C7 00` (SETMULTI off) at startup claims the VM2/3/4 RAM, so one VM owns
`$5000-$7EFF`. Data is flashed to `$6000+` via D-lines alongside the code.

```
$4000-$4FFF   ELIZA engine (code)                     [VM1 program block]
$5000-$50FF   INPUT line buffer   (rel $1000)
$5100-$51FF   OUTPUT assembly buffer (rel $1100)
$5200-$52FF   scratch: fragment ptr, rot temp, flags (rel $1200)
$6000-$7EFF   DATA: keyword records + response pool + swap table (rel $2000+)
```

Phase 1 note: Lite-ELIZA's data may be small enough (~1.5 KB) to sit inside
`$4000-$4FFF` with the code; but design for `$6000` data from the start so
Phase 2 growth needs no restructuring.

## 5. Data formats

### Keyword records (interleaved, linear scan) — at `$6000`
Records back to back; scan walks them in order (first match wins = priority).
```
  <keyword text>, $00        ; ASCII, uppercase, e.g. "I AM"
  <resp_ptr_lo> <resp_ptr_hi>; rel pointer to this keyword's response block
  <N>                        ; number of responses in the block
  <rot>                      ; rotation counter (starts $00, mutated in RAM)
  ... next record ...
  $00                        ; lone null = end of keyword table
```
Scan step: match keyword string against INPUT; if no match, advance past its
null then +4 (ptr+N+rot) to the next record.

### Response pool — at e.g. `$6800`
Null-terminated strings, N per block, blocks back to back. A response may end
with an **APPEND marker byte `$01`** (just before its `$00`) meaning "append the
pronoun-swapped fragment here."

### Pronoun-swap table — small, at e.g. `$6000` top or `$7E00`
Pairs of null-terminated strings `<from>$00<to>$00`, terminated by lone `$00`.
Patterns include their surrounding spaces for word-boundary safety:
```
" YOU "  -> " I "        " I "   -> " YOU "
"YOUR "  -> "MY "        "MY "   -> "YOUR "
" ARE "  -> " AM "       " AM "  -> " ARE "
```
(Phase 2 adds `WERE/WAS`, `IVE/YOUVE`, `IM/YOURE`.)

### Fallback block
A response block with no keyword (reached when the scan falls off the end):
`"PLEASE GO ON."`, `"TELL ME MORE."`, `"I SEE."`, `"CAN YOU ELABORATE?"`,
`"HOW DOES THAT MAKE YOU FEEL?"` — rotated like any block.

## 6. Key subroutines (the real work)

1. **READLINE** — `SERIN` chars into INPUT until CR; echo; handle backspace
   ($08/$7F); null-terminate. (Reuse Lite-Writer's input pattern.)
2. **UPPERCASE + PAD** — walk INPUT: 'a'..'z' → subtract $20; write a leading
   and trailing space so `" YOU "` etc. match at word boundaries.
3. **FINDKEY (substring search)** — the workhorse. For each keyword record:
   nested loop — for each start position p in INPUT, compare keyword bytes to
   INPUT[p..]; all match → hit at p, fragment = p + keyword length. Returns the
   matched record (ptr/N/rot) and the fragment start, or "none".
4. **ROTATE** — from the record: pick response index = rot; walk the block that
   many nulls to reach the chosen string; `rot = (rot+1) mod N`; store back.
5. **EMIT + SWAP** — copy the response to OUTPUT; on APPEND marker, run the
   fragment through a left-to-right pronoun swap (at each word start, test the
   swap-from patterns; emit swap-to on hit, else copy the char) into OUTPUT.
6. **QUITCHK** — compare INPUT to `BYE`/`QUIT`; if so, print sign-off + `HALT`.

Hardest bits: FINDKEY (nested compare) and EMIT+SWAP (length-changing word
substitution). Everything else is copy/compare loops we've already written.

## 7. Opcodes — all already in the build

`SERIN` (CB), `SEROUT` (C9), `SEROUTI` (CA NN), `COPYIMXA` (35), `COPYIAMX`
(36), `TESTAI` (81), `TESTXY` (87), `TESTXI` (86), `TESTGXY`/`TESTLXY` (88/89),
`IFTRUEL`/`IFFALSEL` (A2/A3), `GTL`/`LBL` (B4/B3), `INCX`/`DECX` (42/43),
`COPYXY` (23), `LOADXI` (11), `LOADAI` (10), `SUBAI` (4F, for uppercase),
`C7 00` (SETMULTI off), `00` (HALT). No new firmware required to start.

## 7b. Candidate firmware primitives (string opcodes) — when & what

String work is the bottleneck for text apps (Lite-Writer + ELIZA), and native
firmware runs ~15–40× faster than interpreted bytecode — so a string primitive
is the best-justified firmware addition on the horizon. But do it *after*
proving the exact semantics in bytecode, not before (learn-then-promote, the
way `$C7 SETMULTI` was a confident one-shot because we knew exactly what it
needed).

**Top candidate — `FINDSTR` (substring search).** Collapses ELIZA's entire
`FINDKEY` double loop into one op, and it's reusable (a future Lite-Writer `^R`
find, a shell, any text tool).
- Proposed shape: needle ptr in one reg, haystack ptr in another (both
  null-terminated, VM-relative). Result: match position → a reg, and set the
  Test Flag on found / clear on not-found (so `IFTRUEL`/`IFFALSEL` dispatch it).
  Fragment start for ELIZA = match_pos + needle length.
- Must honor the relative-mode `M(Rx) = R[x] + $4000` translation (route through
  `$0450` like the copy opcodes do), so it reaches the right RAM.

**Second — `CMPN` / string-equals.** Whole-string compare (quit-word check,
swap-pattern match). Smaller win than FINDSTR.

**Feasibility:** opcode space is fine — freed slots already trap to `$0170`
(`$F3/$F4/$F5/$F7`, plus deleted `$7E/$7F/$84/$8B/$95`); claim one `$C7`-style.
No new dispatch machinery needed.

**Plan:** write `FINDKEY`/`EMIT+SWAP` in bytecode first (milestones 2–3).
Structure `FINDKEY` as a clean "needle in haystack → position + found-flag"
routine so its interface matches a future `FINDSTR` opcode — then promoting it
is a drop-in swap (bytecode subroutine → one opcode) with no app-logic change.
Only promote if the bytecode scan actually feels slow on hardware.

## 8. Lite-ELIZA starter data (Phase 1)

Keyword order = priority (longer / more specific first). `\*` = APPEND marker.

| Keyword    | Responses (rotated) |
|------------|---------------------|
| `HELLO`    | "HELLO. HOW ARE YOU FEELING TODAY?" |
| `I AM`     | "HOW LONG HAVE YOU BEEN \*?" · "DO YOU ENJOY BEING \*?" · "IS IT NORMAL TO BE \*?" |
| `I FEEL`   | "TELL ME MORE ABOUT SUCH FEELINGS." · "DO YOU OFTEN FEEL \*?" |
| `I WANT`   | "WHY DO YOU WANT \*?" · "WHAT WOULD IT MEAN TO GET \*?" |
| `BECAUSE`  | "IS THAT THE REAL REASON?" · "WHAT OTHER REASONS COME TO MIND?" |
| `SORRY`    | "PLEASE DON'T APOLOGIZE." · "APOLOGIES ARE NOT NEEDED." |
| `DREAM`    | "WHAT DOES THAT DREAM SUGGEST TO YOU?" · "DO YOU DREAM OFTEN?" |
| `MY`       | "WHY DO YOU MENTION YOUR \*?" · "YOUR \*?" |
| `YOU`      | "WE WERE DISCUSSING YOU, NOT ME." · "WHY SAY THAT ABOUT ME?" |
| `COMPUTER` | "DO COMPUTERS WORRY YOU?" · "WHY MENTION COMPUTERS?" |
| `NO`       | "WHY NOT?" · "YOU SEEM NEGATIVE." |
| `YES`      | "YOU SEEM QUITE CERTAIN." · "I SEE." |
| *(fallback)* | "PLEASE GO ON." · "TELL ME MORE." · "I SEE." · "CAN YOU ELABORATE?" · "HOW DOES THAT MAKE YOU FEEL?" |
| `BYE`/`QUIT` | "GOODBYE. IT WAS GOOD TALKING WITH YOU." → HALT |

Swaps (Phase 1): ` YOU `↔` I `, `MY `↔`YOUR `, ` ARE `↔` AM `.

## 9. Milestones

1. **Echo shell** — READLINE + print it back (proves input/output/backspace).
2. **Keyword → canned reply** — FINDKEY + ROTATE, no fragment append yet.
3. **Fragment append + pronoun swap** — EMIT+SWAP (the "HOW LONG HAVE YOU BEEN
   SAD?" behavior).
4. **Fallback + quit** — rotating generic replies; BYE/QUIT sign-off.
5. **Grow data → full 36/112** (Phase 2). Optional `FINDSTR` firmware helper.

Build/verify with the same Python disassembler+label-checker workflow used for
Lite-Writer (validate the D-line stream decodes cleanly and every GTL/IFTRUEL
target has a matching LBL before flashing).

## 10. Open questions

- Uppercase-only, or handle lowercase input? (Uppercasing on input is easiest.)
- Response rotation persistence: counters live in RAM data at `$6000` — fine
  within a session; reset on re-flash.
- Fragment cleanup: trim trailing punctuation / a trailing period on the append?
- Keyword priority/ranking: first-match-in-table-order for Phase 1; add ranking
  later if a fuller ELIZA feel is wanted.
- Line length cap (256-byte INPUT buffer is plenty for a terminal line).
