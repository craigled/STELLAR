#!/usr/bin/env python3
"""
Generate web/js/opcodes.js — the data behind the opcode-reference page and the
disassembler side panel.

Reuses the authoritative length/name tables from the STELLAR disassembler
(tools/stellar_disasm.py in the stellar-1802 work repo) and merges in a group,
operand template, and human description for each opcode (from the STELLAR v0.61
reference). Run from anywhere:

    python3 web/build/gen_opcodes.py

Emits: web/js/opcodes.js  (window.STELLAR_OPCODES = [...])
"""
import os, sys, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
# tools/stellar_disasm.py lives in the sibling work repo
DISASM = os.path.expanduser('~/Projects/stellar-1802/tools/stellar_disasm.py')
FMATH  = os.path.expanduser('~/Projects/stellar-1802/Firmware-Math')
DOCX   = 'STELLAR MAIN V0061.36.docx'

def load_disasm():
    spec = importlib.util.spec_from_file_location('stellar_disasm', DISASM)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

# opcode -> (group, operand-template, description)
DESC = {
0x00: ('io', '', 'End the program. Inside a VM, terminates that VM.'),
0x01: ('io', '0Z', 'Define the OUTPUT port (Z=0-7, default 4).'),
0x02: ('io', '0Z', 'Define the INPUT port (Z=9-F, default C). Any other Z is refused with error $08 (since V0061.30).'),
0x03: ('io', 'DZ', 'Define the EF source for GIPA, GIPX and WIP 00: D=EF line (1-4, default 4), Z=0 normal / 1 inverted (active low).'),
0x04: ('io', 'NN', 'Output an immediate byte on the defined output port.'),
0x05: ('io', 'DZ', 'Output one byte of accumulator D (0=Acc, 1=MA, 2=DA). Z counts up from the low end of the remainder: for the MA, Z=0-1 are the remainder and Z=2-5 the number, low byte first; for the DA the number starts at Z=3.'),
0x06: ('io', 'ZX', 'Output register X (Z=0: low byte, else high byte).'),
0x07: ('io', 'FX', 'RTC - the DS12887 real-time clock. F=0 RTCGET: the date and time, plain, into the 8 bytes at M(RX): sec min hour weekday(0=Sun) day month year(2 bytes). F=1 RTCSET from M(RX): every field checked, written in the chip\'s own mode; Test = 1 written, 0 refused (nothing written). F=2 Acc = chip register X; F=3 chip register X = Acc low.'),
0x08: ('io', '0X', 'Output the byte in memory pointed to by register X.'),
0x09: ('io', '', 'Scan all four EF lines into the Accumulator as a mask: bit 0 = EF1 ... bit 3 = EF4, high byte 0.'),
0x0A: ('io', '0Z', 'Set Q (0=Off, 1=On, 2=On-then-Off, 3=On,On then Off,Off).'),
0x0C: ('io', '0Z', 'Scan input-port value into Acc byte Z (0=low, 1=high).'),
0x0D: ('io', '0Z', 'Wait for the EF source (DEFEF) to go active then inactive, then read the input port into Acc byte Z (0=low, 1=high).'),
0x0E: ('io', 'ZX', 'Wait for the EF source (DEFEF) to go active then inactive, then read the input port into register X (Z=0: low, else high).'),
0x0F: ('io', '0Z', 'Wait until EF line Z (1-4) goes high then low; Z=0: the EF source set by DEFEF, normal or inverted. Other VMs keep running while it waits.'),

0x10: ('reg', 'NN NN', 'Load two immediate bytes into the Accumulator.'),
0x11: ('reg', 'ZX NN NN', 'Load two immediate bytes into register X (Z=0: all, 1: low, 2: high; any other Z loads both).'),
0x12: ('reg', 'ZD NN...', 'Load Z bytes into accumulator D (0=Acc,1=MA,2=DA); Z=0 defaults to 2. Bytes fill from the low end, so a short load into the MA or DA lands in the remainder: give all 7 to set the number.'),
0x13: ('reg', '', 'Copy the Acc low byte into its high byte.'),
0x14: ('reg', '0X', 'Copy register X low byte into its high byte.'),
0x15: ('reg', '', 'Swap the Acc high and low bytes.'),
0x16: ('reg', '0X', 'Swap register X high and low bytes.'),
0x17: ('reg', '0Z', 'Shift MA bytes (0=Left, 1=Ring Left, 2=Right, 3=Ring Right).'),
0x18: ('reg', 'NN', 'Set the bit(s) in the mask in the Acc low byte.'),
0x19: ('reg', 'NN', 'Reset the bit(s) in the mask in the Acc low byte.'),
0x1A: ('reg', 'NN', 'Test whether EVERY bit of the mask NN is set in the Acc low byte: true when (Acc.lo AND NN) = NN. Single-bit and multi-bit masks (since V0061.29; before that only single bits, and a false result left the flag unchanged).'),

0x20: ('move', '0Z', 'Set memory mode (0=Absolute, 1=Relative; default Relative). In absolute mode a branch target is absolute too - switch back before branching.'),
0x21: ('move', 'ZX', 'Copy accumulator Z (0=Acc,1=MA,2=DA) to register X.'),
0x22: ('move', 'ZX', 'Copy register X to accumulator Z.'),
0x23: ('move', '0Z XY', 'Copy register X to register Y (Z=0: all, 1: low, 2: high).'),
0x24: ('move', '', 'Copy Acc to the lowest two bytes of MA.'),
0x25: ('move', '', 'Copy the lowest two bytes of MA to Acc.'),
0x27: ('move', '', 'Copy the MA Remainder to Acc.'),
0x28: ('move', '0Z', 'Copy the Command Counter to accumulator Z (0=Acc, 1=MA).'),
0x29: ('move', '', 'Copy the I/O register to the Acc low byte.'),
0x2A: ('move', '', 'Copy the Acc low byte to the I/O register.'),
0x2B: ('move', '', 'Copy the MA high word ($3068/$3069) into the Acc, mirroring COPYMAA.'),
0x2E: ('move', '0X MM MM', 'READIDX — Acc = M(MMMM + RX), zero-extended; RX preserved. Honours MEMMODE absolute since V0061.34 (before, it always added the VM base).'),
0x2F: ('move', '0X MM MM', 'WRITEIDX — M(MMMM + RX) = Acc.low. One-op array store. Honours MEMMODE absolute since V0061.34.'),
0x31: ('move', '0X NN', 'Copy immediate byte NN to memory at register X.'),
0x32: ('move', '0X NN NN', 'Copy two immediate bytes to memory at register X.'),
0x33: ('move', 'ZX', 'Copy memory at RX to accumulator Z (0=Acc:2B, 1=MA:5B, 2=DA:7B).'),
0x34: ('move', 'ZX', 'Copy accumulator Z to memory at register X.'),
0x35: ('move', '0D ZX', 'Copy D bytes (1-4) from M(RX) to accumulator Z; zero-extends the rest. For the MA (Z=1) since V0061.31 - before that it used the old $22-$24 MA location and D=4 was refused.'),
0x36: ('move', '0D ZX', 'Copy D bytes (1-4) of accumulator Z to M(RX). For the MA (Z=1) since V0061.31.'),
0x37: ('move', 'DE ZX', 'Copy D bytes starting at byte E of accumulator Z from M(RX).'),
0x38: ('move', 'DE ZX', 'Copy D bytes of accumulator Z starting at byte E to M(RX).'),
0x39: ('move', '0D XY', 'Copy D bytes (1,2) from M(RX) to register Y. Works in MEMMODE absolute since V0061.34 - before, a dead range check stopped the VM.'),
0x3A: ('move', '0D XY', 'Copy D bytes (1,2) from register X to M(RY).'),
0x3B: ('move', 'XY NN', 'Copy NN bytes from M(RX) to M(RY).'),
0x3C: ('move', 'XY 0Z', 'Copy a memory block from RX to RY until RZ is reached.'),
0x3D: ('move', 'ZX', 'Compare accumulator Z with memory at register X.'),

0x40: ('math', '', 'Increment the Accumulator.'),
0x41: ('math', '', 'Decrement the Accumulator.'),
0x42: ('math', 'ZX', 'Increment register X (Z=0: hex, Z=1: decimal-adjust).'),
0x43: ('math', 'ZX', 'Decrement register X (Z=0: hex, Z=1: decimal-adjust).'),
0x44: ('math', 'XY', 'Add RX + RY into MA.'),
0x45: ('math', 'XY', 'Subtract RX - RY into MA.'),
0x46: ('math', '0X', 'Add Acc + RX into MA.'),
0x47: ('math', '0X', 'Subtract Acc - RX into MA.'),
0x48: ('math', '0X', 'Subtract RX - Acc into MA.'),
0x49: ('math', '0X', 'Multiply RX * Acc into MA.'),
0x4A: ('math', 'XY', 'Multiply RX * RY into MA.'),
0x4B: ('math', '0X', 'Divide Acc / RX into MA + Remainder.'),
0x4C: ('math', '0X', 'Divide RX / Acc into MA + Remainder.'),
0x4D: ('math', 'XY', 'Divide RX / RY into MA + Remainder.'),
0x4E: ('math', 'NN NN', 'Add an immediate value to the Accumulator.'),
0x4F: ('math', 'NN NN', 'Subtract an immediate value from the Accumulator.'),
0x50: ('math', 'XY 0Z', 'Add RX + RY into register Z; Carry set when the sum passes $FFFF (since V0061.31 - before that a wrap also added 1 to the register before RZ).'),
0x51: ('math', 'XY 0Z', 'Subtract RX - RY into register Z.'),
0x52: ('math', '0X NN NN', 'Add an immediate value to register X.'),
0x53: ('math', '0X NN NN', 'Subtract an immediate value from register X.'),
0x54: ('math', 'DZ XY', 'Add D bytes (1-4) at M(RX)+M(RY) into MA (Z: 0=destructive, 1=accumulative). D=4 keeps the top byte since V0061.31.'),
0x55: ('math', 'DZ XY', 'Subtract D bytes (1-4) M(RX)-M(RY) into MA (Z: 0=destructive, 1=accumulative). D=4 keeps the top byte since V0061.31.'),
0x56: ('math', 'ZX', 'Add Acc + Z bytes (Z = 1 or 2) at M(RX) into MA. Any other Z does nothing.'),
0x57: ('math', 'ZX', 'Subtract Acc - Z bytes (Z = 1 or 2) at M(RX) into MA. Any other Z does nothing.'),
0x58: ('math', '0X', 'Multiply Acc * two bytes at M(RX) into MA.'),
0x59: ('math', '0X', 'Divide Acc / two bytes at M(RX) into MA.'),
0x5A: ('math', 'XY', 'Multiply M(RX) * M(RY) into MA.'),
0x5B: ('math', 'XY', 'Divide M(RX) / M(RY) into MA.'),
0x5C: ('math', '0X', 'DIVMAX — native 32/16 divide of the MA by RX (divide-the-MA).'),
0x60: ('math', 'DZ', 'Shift Acc bits. Z = 0 left, 1 ring left, 2 right, 3 ring right. '
        'D = 0 both bytes, 1 low byte, 2 high byte.'),
0x61: ('math', 'XZ', 'Shift register X bits (Z: 0=Left,1=RingL,2=Right,3=RingR), 1 bit/op.'),
0x62: ('math', '0Z', 'Shift MA bits (0=Left, 1=Ring Left, 2=Right, 3=Ring Right).'),
0x63: ('math', 'ZX (NN NN)', 'OR RX with Z (0=Acc, 1=Immediate) into MA.'),
0x64: ('math', 'ZX (NN NN)', 'XOR RX with Z (0=Acc, 1=Immediate) into MA.'),
0x65: ('math', 'ZX (NN NN)', 'AND RX with Z (0=Acc, 1=Immediate) into MA.'),
0x6A: ('math', '0Z', 'Clear accumulator Z (0=Acc, 1=MA, 2=DA).'),
0x6B: ('math', 'ZX', 'Convert to decimal into DA (Z: 0=Acc, 1=MA, 2=RX).'),
0x6C: ('math', '', 'Convert DA to hex into MA.'),
0x6D: ('math', '0Z', 'Set hex/decimal mode (0=Hex, 1=Auto decimal conversion).'),
0x6E: ('math', '', 'OUTDEC — output the DA as decimal ASCII to the UART, leading-zero suppressed (custom; pair with CVT2DEC).'),

0x70: ('stack', '0Z', 'Push the complete contents of accumulator Z (0=Acc, 1=MA, 2=DA).'),
0x71: ('stack', '0Z', 'Pop the complete contents of accumulator Z (0=Acc, 1=MA, 2=DA).'),
0x72: ('stack', '0X', 'Push register X onto the stack (two bytes).'),
0x73: ('stack', '0X', 'Pop the stack into register X (two bytes).'),
0x74: ('stack', 'ZX', 'Push Z bytes of memory onto the stack, starting at M(RX) and walking DOWN (RX, RX-1, ...) (Z=0: 16 bytes). Pair with POPMX from the start of the block to copy it in order.'),
0x75: ('stack', 'ZX', 'Pop Z bytes from the stack into memory, starting at M(RX) and walking UP (RX, RX+1, ...) (Z=0: 16 bytes).'),
0x76: ('stack', '0Z', 'Push one special byte: Z = 0 IO, 1 EF, 2 MEMMODE, 3 DATADIR, 4 HEXFLAG, 6 ERROR, 8 ExitCode. Z = 5 and 7 are unassigned and do nothing.'),
0x77: ('stack', '0Z', 'Pop one special byte back off the stack, Z as for PUSHS.'),
0x78: ('stack', '', 'Push the Q output state onto the stack.'),
0x79: ('stack', '', 'Pop the Q state back off the stack and set Q accordingly.'),

0x80: ('test', 'ZX', 'Test Acc = RX (Z=0: all, 1: low, 2: high).'),
0x81: ('test', 'NN NN', 'Test Acc = immediate.'),
0x82: ('test', '0Z', 'Test whether the Acc equals two bytes of the MA: Z=0 the low two, Z=1 the high two. '
        'The MA remainder is tested with $27 COPYREMA.'),
0x83: ('test', '', 'Test I/O byte = Acc low.'),
0x84: ('test', 'NN', 'Test I/O byte = immediate.'),
0x85: ('test', '0Z', 'Test whether the Acc equals two bytes of the DA: Z=0 the low two, Z=1 the high two.'),
0x86: ('test', 'ZX NN NN', 'Test RX = immediate (Z=0: both, 1: low, 2: high).'),
0x87: ('test', 'XY', 'Test RX = RY.'),
0x88: ('test', 'XY', 'Test RX >= RY. Swap the nibbles (88 YX) to test RX <= RY.'),
0x89: ('test', 'XY', 'Test RX < RY, strictly. Swap the nibbles (89 YX) to test RX > RY.'),
0x8A: ('test', '0X', 'Test DA > RX. DA holds packed BCD and is compared against RX as raw bytes.'),
0x8B: ('test', '0X', 'Test Command Counter > RX.'),
0x8C: ('test', 'ZX', 'Test RX = $0000 (Z=0: both, 1: low, 2: high).'),
0x8D: ('test', '0D', 'Test accumulator D = zero (0=Acc, 1=MA, 2=DA).'),
0x8E: ('test', '', 'Test MA Remainder = zero.'),
0x8F: ('test', '', 'Test DA Remainder = zero.'),
0x90: ('test', 'XY', 'Test whether Acc is within the range RX to RY.'),
0x91: ('test', '', 'Test whether the MA sign is positive ($00).'),
0x92: ('test', '', 'Test whether Q is set.'),
0x93: ('test', '', 'Test whether the Carry flag is set (Carry=1 means borrow/overflow).'),
0x94: ('test', '0Z', 'Test a special flag nonzero (0=Overflow,1=Interrupt,2=Decimal,3=Macro).'),
0x96: ('test', 'NN', 'Test ExitCode = NN.'),
0x97: ('test', 'NN', 'Test Interrupt State = NN.'),
0x98: ('test', '', 'Test whether the Error register is nonzero.'),
0x99: ('test', 'DZ', 'Test EF D (1-4) = Z (0 or 1). Works since V0061.33 - before that it could never report true and overwrote part of R0.'),
0x9A: ('test', '0Z', 'Test whether accumulator Z low byte is even (0=Acc, 1=MA).'),
0x9B: ('test', 'DZ', 'Test whether byte D (from LSB) of accumulator Z is zero (low-byte-safe null test).'),
0x9C: ('test', 'DD XY', 'Compare D bytes at M(RX) with M(RY) into the Test Flag.'),
0x9D: ('test', 'ZX NN...', 'Test the Z bytes at M(RX) = the Z immediate bytes that follow (Z = 1-15; Z = 0 is refused with error $0C). Before V0061.29 it always compared exactly 2 bytes.'),
0x9E: ('test', 'NN', 'Test System Status = NN.'),
0x9F: ('test', '0Z NN', 'Test the value on input port Z (9-F; Z=0: the defined port) = NN. Reads the port for this test only; the VM\'s defined input port is unchanged (since V0061.30).'),

0xA0: ('branch', 'MM MM', 'If Test=True, go to an absolute address.'),
0xA1: ('branch', 'MM MM', 'If Test=False, go to an absolute address.'),
0xA2: ('branch', 'LL', 'If Test=True, go to label LL.'),
0xA3: ('branch', 'LL', 'If Test=False, go to label LL.'),
0xA4: ('branch', '0Z MM', 'If Test=True, jump MM bytes (Z=0: forward, counted from the next command; 1: back, counted from this jump).'),
0xA5: ('branch', '0Z MM', 'If Test=False, jump MM bytes (Z=0: forward, counted from the next command; 1: back, counted from this jump).'),
0xA6: ('branch', 'ZX', 'If Test=True, go to RX (Z=0: direct, Z=1: indirect).'),
0xA7: ('branch', 'ZX', 'If Test=False, go to RX (Z=0: direct, Z=1: indirect).'),
0xB0: ('branch', 'MM MM', 'Go to an absolute address.'),
0xB1: ('branch', 'ZX', 'Go to the address in RX (Z=0: direct, Z=1: indirect).'),
0xB2: ('branch', 'LL', 'Call a labelled location (return with RETURNL).'),
0xB3: ('branch', 'LL', 'Define label LL at this location. The first pass stops at the first F0 00 00, so labels after one are not defined: use F0 C4 for a break in mid-program.'),
0xB4: ('branch', 'LL', 'Go to label LL.'),
0xB5: ('branch', 'XY MM MM', 'Loop to an address until RX >= RY.'),
0xB6: ('branch', 'XY LL', 'Loop to a label until RX >= RY.'),
0xB7: ('branch', '0X MM MM', 'Loop to an address until RX = $0000.'),
0xB8: ('branch', '0X LL', 'Loop to a label until RX = $0000.'),
0xB9: ('branch', '0Z MM', 'Jump MM bytes (Z=0: forward, counted from the next command; Z=1: back, counted from this jump).'),
0xBA: ('branch', 'LL MM MM', 'Define subroutine LL at an address.'),
0xBB: ('branch', 'LL', 'Start of subroutine LL (not executed until called).'),
0xBC: ('branch', '00', 'Marks the end of a subroutine for the first pass (must include the $00 parameter). It does not return: end with RETURN.'),
0xBD: ('branch', 'MM MM', 'Standard call to an address (return with RETURN).'),
0xBE: ('branch', '0Z', 'Return (Z=0: from standard call; else from last location).'),
0xBF: ('branch', '', 'Return from a label (one level deep).'),

0xC0: ('misc', 'NN', 'Delay NN before the next operation.'),
0xC1: ('misc', '0X', 'PRINTSTR — output the whole null-terminated string at M(RX) in one op (custom).'),
0xF1: ('misc', 'MM MM', 'RUNMC — jump to native 1802 machine code at $MMMM. The code is NOT '
        'inline: only the 2-byte address follows the opcode. It must return with SEP R5 (D5). '
        'No VM time-sharing happens while it runs. Moved here from $C2 in V0061.24.'),
0xF2: ('misc', '0Z', 'SETSIZE — raise this VM\'s Max Size to Z whole 4KB blocks '
        '(Z = 1, 2 or 3, giving $10, $20 or $30 pages). The Z-1 VM entries ABOVE this one '
        'are consumed: their CIDP prog page is zeroed so VM_SCANNER skips them entirely. '
        'The new size is written to the CIDP entry and to core+$5D, so the sandbox bound '
        'follows it. REFUSED with error $22, changing nothing, if Z is out of range, if '
        'there is no VM above to take, or if one of them is still running (custom).'),
0xC2: ('io', 'XY', 'GETSTR — read a line from the UART into the buffer at RX, echoing as it '
        'goes. X = cursor register (advances), Y = buffer-start register (the floor backspace '
        'cannot pass). CR ends the line and stores $00; $08/$7F backspace. Handles one '
        'character per execution and yields between them, so other VMs keep running (custom).'),
0xC3: ('misc', '', 'Generate a pseudo-random two-byte number into Acc. Each VM gets its own sequence.'),
0xC4: ('misc', '', 'No operation.'),
0xC5: ('misc', '', 'Enable external interrupt.'),
0xC6: ('misc', '', 'Disable external interrupt (default: disabled).'),
0xC7: ('misc', '0Z', 'Set the Multitasking-Allowed byte (C7 00 = off, C7 01 = on).'),
0xC8: ('misc', 'NN', 'Set the counter-interrupt count (default $03).'),
0xC9: ('misc', '', 'Output the Acc low byte to the UART (blocks until transmitter empty).'),
0xCA: ('misc', 'NN', 'Output the immediate byte NN to the UART.'),
0xCB: ('misc', '', 'Cooperatively wait for a UART byte into Acc low (yields to scheduler).'),
0xCC: ('misc', '', 'Poll the UART once; Test Flag = 1 if a byte is waiting (non-blocking).'),
0xCD: ('misc', '', 'START — required first byte of every STELLAR program (runs the label pre-pass).'),
0xCE: ('misc', 'VZ', 'Pause/Resume VM V (Z=0: pause, Z=1: resume).'),
0xCF: ('misc', 'V0', 'Kill VM V.'),

0xD0: ('vm', 'ZD', 'Enable/disable sharing (Z=0: off, 1: on; D=1: RO, 2: RW).'),
0xD1: ('vm', 'VD', 'Test whether VM V is available for access D (1=Read, 2=RW).'),
0xD2: ('vm', 'VZ', 'Z=0: load VM(V) Acc into local; Z=1: save local to VM(V) Acc.'),
0xD3: ('vm', 'VZ XY', 'Z=0: load VM(V) RX into local RY; Z=1: save local RY to VM(V) RX. X is always VM(V)\'s register, Y always ours.'),
0xD4: ('vm', 'V0 XY', 'Copy two bytes from VM(V) M(RX) into local RY.'),
0xD5: ('vm', 'V0 XY', 'Copy two bytes from local RX to VM(V) M(RY).'),
0xD6: ('vm', 'VX VY', 'Copy one byte from VM(V) M(RX) to VM(V) M(RY).'),
0xD7: ('vm', 'VX VY', 'Copy two bytes from VM(V) RX to VM(V) RY.'),
0xD8: ('vm', 'V0', 'Increment VM(V) Accumulator.'),
0xD9: ('vm', 'V0', 'Decrement VM(V) Accumulator.'),
0xDA: ('vm', 'VX', 'Increment VM(V) register X.'),
0xDB: ('vm', 'VX', 'Decrement VM(V) register X.'),
0xDC: ('vm', 'VX VY DD', 'Copy DD bytes from VM(V) M(RX) to VM(V) M(RY). Both VMs must be shared.'),
0xDD: ('vm', 'V0', 'Test VM status into the Error register / VMstatus.'),
0xDE: ('vm', 'V0 XY', 'Test VM(V) RX = local RY.'),
0xDF: ('vm', 'VZ NN', 'Test VM(V) special register Z = NN.'),

0xF0: ('debug', '', 'BRK — break/exit, show registers. A final BRK followed by 00 00 is the pre-pass end marker.'),
0xF6: ('debug', 'XY', 'Checksum bytes from RX to RY into MA.'),
0xFA: ('debug', '0Z', 'Reset flag Z (0=Carry,1=Overflow,2=Macro,3=Error,4=Test,5=MASign,6=Interrupt,7=Debug).'),
0xFB: ('debug', 'XY NN', 'Fill memory from RX to RY with byte NN.'),
0xFC: ('debug', 'ZD XY', 'One sort pass over array RX-RY (Z=0: asc, 1: desc; D=cell size).'),
0xFD: ('debug', '0V', 'Clear program memory of machine V (0=all, 1-4=one machine).'),
0xFF: ('debug', 'NN', 'Set debug mode (0 normal, 1 step+delay, 2 break-each, 5 TRACE, ...; FF 00 stops).'),
}

GROUPS = [
    ('io',     'Input / Output',        '$01-$0F'),
    ('reg',    'Register & Accumulator','$10-$1A'),
    ('move',   'Data Move',             '$20-$3F'),
    ('math',   'Math',                  '$40-$6D'),
    ('stack',  'Stack',                 '$70-$79'),
    ('test',   'Test',                  '$80-$9F'),
    ('branch', 'Labels & Branches',     '$A0-$BF'),
    ('misc',   'Misc / Control',        '$C0-$CF'),
    ('vm',     'VM Inter-Communication','$D0-$DF'),
    ('debug',  'Debug',                 '$F0-$FF'),
]

def live_opcodes():
    """Opcodes that actually dispatch somewhere in the flashed firmware.

    The reference page once published seven opcodes that dispatch straight to the
    illegal-opcode vector ($26, $30, $95, $A8-$AB), because nothing here ever
    checked the firmware. Derive liveness from the dispatch table at $0800 so that
    cannot silently come back.
    """
    sys.path.insert(0, FMATH)
    cwd = os.getcwd()
    os.chdir(FMATH)                      # load_firmware uses relative paths
    try:
        from load_firmware import load
        mem, _ = load(os.path.join('..', DOCX))
    finally:
        os.chdir(cwd)
    UNIMPLEMENTED = 0x0170
    return {op for op in range(256)
            if ((mem[0x0800 + 2*op] << 8) | mem[0x0801 + 2*op]) != UNIMPLEMENTED}


def main():
    d = load_disasm()
    live = live_opcodes()
    named = set(d.NAMES)

    phantom = sorted(named - live)
    if phantom:
        print('  SKIPPED - named but dead in the firmware: '
              + ' '.join('$%02X' % o for o in phantom))
    undocumented = sorted(live - named)
    if undocumented:
        print('  WARNING - live in the firmware but unnamed, so NOT published: '
              + ' '.join('$%02X' % o for o in undocumented))

    entries = []
    for op in sorted(named & live):
        name = d.NAMES[op]
        length = d.OPLEN.get(op, 1)
        group, operands, desc = DESC.get(op, ('misc', '', ''))
        entries.append(dict(op=op, name=name,
                            length=(length if length != 0xFF else -1),
                            group=group, operands=operands, desc=desc))
    out = os.path.join(HERE, '..', 'js', 'opcodes.js')
    out = os.path.abspath(out)
    with open(out, 'w') as f:
        f.write('// AUTO-GENERATED by web/build/gen_opcodes.py — do not edit by hand.\n')
        f.write('// length: operand bytes after the opcode (-1 = variable).\n')
        f.write('(function(){\n')
        f.write('var GROUPS = ' + _js(GROUPS) + ';\n')
        f.write('var OPS = [\n')
        for e in entries:
            f.write('  {op:0x%02X, name:%s, length:%d, group:%s, operands:%s, desc:%s},\n' % (
                e['op'], _s(e['name']), e['length'], _s(e['group']),
                _s(e['operands']), _s(e['desc'])))
        f.write('];\n')
        f.write('if (typeof module !== "undefined" && module.exports) module.exports = {groups:GROUPS, opcodes:OPS};\n')
        f.write('if (typeof window !== "undefined") { window.STELLAR_OPCODE_GROUPS = GROUPS; window.STELLAR_OPCODES = OPS; }\n')
        f.write('})();\n')
    print(f'Wrote {out}  ({len(entries)} opcodes)')

def _s(t):
    return '"' + t.replace('\\', '\\\\').replace('"', '\\"') + '"'

def _js(groups):
    return '[' + ','.join('[%s,%s,%s]' % (_s(a), _s(b), _s(c)) for a, b, c in groups) + ']'

if __name__ == '__main__':
    main()
