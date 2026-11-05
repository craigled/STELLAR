# STELLAR TEST PROGRAMS V0.61.36: what the review found

Every table in `STELLAR TEST PROGRAMS V0.61.36.docx` was read, then run on the V0061.36 firmware in the website's emulator. The document itself has not been changed. The Opcodes page now holds %COUNT% worked examples, covering all 198 opcodes, and each one has been seen to give the result shown. None of this was run on the Elf2K itself.

## How the firmware behaves, and may surprise you

These came up in the review. The examples show what the firmware does today. Nothing in the firmware was changed. The first two may be leftovers from when the MA grew from 3 bytes to 4, so you may want to decide whether they should change.

1. **`$17 SHIFTMA` rings only the low 3 bytes of the MA.** The top byte stays out of the ring.
2. **`$34 COPYAMX` with Z=1 saves 5 bytes:** the low 3 of the number and the 2 of the remainder. The number's top byte is not saved.
3. **`$12 LOADZAI` fills the MA and DA from the low end.** The MA is 7 bytes (4 number, 2 remainder, 1 sign) and the DA 7 (4 number, 3 remainder). A short load lands in the remainder first: `12 31 12 34 56` puts 1234 in the remainder. To set the number you must give all seven. The page's description of `$12` does not say this yet.
4. **`$05 OUTA` counts Z up from the low end of the remainder.** For the MA, Z=0 and 1 are the remainder and Z=2 to 5 the number, low byte first. For the DA the number's low byte is Z=3. Several programs in the document used the wrong Z and showed 00.
5. **`$A7` and `$B1` with Z=1 (indirect) read the pointer as an actual address, even in relative mode.** `R1 = 00F0` means 40F0 for most commands, but here the register must hold 40F0. The address found there is then relative. `$A6` shares the description but was not tried in this form.
6. **Jumps count differently forward and back.** A forward jump counts from the next command, a back jump from the jump itself. This applies to `$A4`, `$A5` and `$B9`.
7. **The label pre-pass stops at the first `F0 00 00`.** A BRK in the middle of a program followed by a gap of zeros is an end marker, so labels after it are never defined, and the program stops with error 01 (T202). Use `F0 C4`.
8. **`$BC ENDSUB` does not return.** It only marks the end for the first pass. A subroutine reached by GTL must end with RETURN 01.
9. **`$DC` needs both VMs shared.** With VM2 not shared, the copy into it did nothing.
10. **`$11 LOADXI` with Z=4 loads both bytes.** The document said it would load nothing.

## Out of date in the document as a whole

- The STACK headings still give the old numbers: PUSHA is `$70`, POPA `$71`, PUSHX `$72`, POPX `$73`, PUSHMX `$74`, POPMX `$75`, PUSHS `$76`, POPS `$77`, PUSHQ `$78`, POPQ `$79`.
- Opcodes that no longer exist: `$26` COPYAREM, `$70` PUSHI, `$71` PUSH2I, `$7E` POPLAST, `$7F` RESETSP, `$95` SETEXIT (never implemented), `$A8` (a copy of the IFTRUEI heading), `$F8` EXTOP.
- `$C2` is GETSTR now; RUNMC moved to `$F1`. `$C7` is SETMULTI, not SETSTATE.
- `$5A` and `$5B` take one operand byte (XY), not DZ XY.
- `$82` TESTAMA and `$85` TESTADA now take an operand.
- `$FA` RESETFLAG's flag numbers have changed.
- The TESTERROR heading says `$9A`; it is `$98`. The TESTABZ heading says TESTAZ.
- Addresses in many explanations still say 3xxx: programs are at 4xxx.
- The first page says "RS-23": it should be RS-232.
