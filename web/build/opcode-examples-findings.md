# STELLAR TEST PROGRAMS V0.61.36: what the review found

Every table in `STELLAR TEST PROGRAMS V0.61.36.docx` was read, then run in the website's emulator, on V0061.36 at first and now on V0061.37. The Opcodes page now holds %COUNT% worked examples, covering all 198 opcodes, and each one has been seen to give the result shown. None of this was run on the Elf2K itself.

## Firmware faults: fixed in V0061.37 (on the Elf2K 2026-11-05)

The patch is in `STELLAR V0061.37 PATCH D-LINES.txt`, built by `tools/fw_patchset_v37.py`. Each fix has a `TESTS/PATCH-*` program, and all six print K on the Elf2K. The examples on the page show V0061.37.

1. **`$17 SHIFTMA` left out the MA's top byte in all four modes**, not only the ring modes as this report first said. It now moves all 4 bytes.
2. **`$33 COPYMXA` and `$34 COPYAMX` with Z=1 moved 5 bytes and lost the top byte.** They now move 6: the 4 of the number and the 2 of the remainder. This also repairs `$3D COMPAMX`, which already compared 6 bytes, so a value saved with `$34` never matched itself.
3. **`$A6`, `$A7` and `$B1` with Z=1 read the pointer as an actual address, even in relative mode.** It now counts from the program, like every other register address. In absolute mode nothing changes.

More of the same kind turned up while fixing those, by running the MA opcodes with a value in the top byte. They were not in the first version of this report:

4. **`$70 PUSHA` and `$71 POPA` with Z=1 lost the top byte.** They now push 7 bytes, not 6.
5. **`$8D TESTAZ` with Z=1 ignored the top byte**, so 01000000 tested as zero.
6. **`$28 COPYCCA` with Z=1 copied 3 of the 4 counter bytes** and left the MA's top byte as it was.

7. **`$6B CVT2DEC` with Z=1 converted only the low 16 bits**, so 65536 gave 0 with no error. It now converts all 32 bits. The DA holds 8 digits: from 100,000,000 up it keeps the low 8 digits and sets Overflow, which stays set until cleared. Automatic decimal mode (`$6D`) uses the same code, so math results over 65535 now show correctly there too.

8. **`$6C CVT2HEX` handled only about 5 digits:** 99999999 gave 869F, and 65536 gave FF00. It now converts all 8 digits, so a number up to 99,999,999 goes to decimal and back unchanged. As before, the DA remainder is not converted: the MA remainder comes back as 0.

## How the firmware behaves, and stays that way

These are not faults. Changing them would break working programs or go against the firmware document, so they are now written on the Opcodes page.

1. **`$12 LOADZAI` fills the MA and DA from the low end,** as the firmware document says ("All of the accumulators fill to the lowest byte"). The MA is 7 bytes (4 number, 2 remainder, 1 sign) and the DA 7 (4 number, 3 remainder). A short load lands in the remainder first: `12 31 12 34 56` puts 1234 in the remainder. To set the number you must give all seven.
2. **`$05 OUTA` counts Z up from the low end of the remainder.** For the MA, Z=0 and 1 are the remainder and Z=2 to 5 the number, low byte first. For the DA the number's low byte is Z=3. Several programs in the document used the wrong Z and showed 00.
3. **Jumps count differently forward and back.** A forward jump counts from the next command, a back jump from the jump itself. This applies to `$A4`, `$A5` and `$B9`.
4. **The label pre-pass stops at the first `F0 00 00`.** A BRK in the middle of a program followed by a gap of zeros is an end marker, so labels after it are never defined, and the program stops with error 01 (T202). Use `F0 C4`.
5. **`$BC ENDSUB` does not return.** It only marks the end for the first pass. A subroutine reached by GTL must end with RETURN 01.
6. **`$DC` needs both VMs shared.** With VM2 not shared, the copy into it did nothing.
7. **`$11 LOADXI` with any Z other than 1 or 2 loads both bytes.** The document said Z=4 would load nothing.

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
