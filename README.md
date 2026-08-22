# STELLAR

A cooperative multitasking virtual machine for the RCA COSMAC CDP1802 microprocessor, written entirely in hand-assembled machine code.

## What Is This?

STELLAR is a bytecode interpreter and VM engine that runs up to **4 concurrent virtual machines** on bare CDP1802 hardware. Each VM executes a custom instruction set (160+ opcodes) dispatched through a jump table, with full context switching between VMs via round-robin cooperative multitasking.

There is no assembler, no compiler, no toolchain. Every byte of machine code is hand-assembled and entered as hex.

## Features

- **Cooperative multitasking** — Round-robin scheduling with configurable timeslice across up to 4 VMs
- **Custom instruction set** — 160+ VM opcodes covering math, logic, flow control, I/O, and testing
- **Per-VM state** — Each VM has its own virtual registers (16), accumulators (Acc, Math Acc, Decimal Acc), stack, program counter, and flags
- **Math subsystem** — Add, subtract, multiply, divide with carry/overflow tracking and decimal conversion
- **Debug/trace system** — 8 verbosity levels (0-7) with configurable trace output
- **Error handling** — 20+ error codes with per-VM error state
- **I/O abstraction** — Virtual ports mapped to hardware ports 1-7
- **Label/subroutine system** — 256-entry label array for VM program flow control

## Architecture

### Memory Map

| Region | Address Range | Purpose |
|--------|--------------|---------|
| System Code | `$0000-$09FF` | Core engine, SCRT, utilities |
| Command Table | `$0800-$09FF` | Jump table for VM opcodes (2 bytes/entry) |
| VM Opcode Handlers | `$0A00-$2DFF` | Implementation of each VM instruction |
| CIDP | `$2F00-$2FFF` | Common Interchange Data Page (VM settings & system state) |
| Active VM Core | `$3000-$307F` | Currently executing VM's registers/accumulators/flags |
| MPL Call Stack | `$3100-$317F` | VM-level subroutine stack |
| 1802 Hardware Stack | `$3180-$31FF` | Native 1802 stack |
| Label Array | `$3200-$33FF` | VM program labels (0-255) |
| VM Program Memory | `$4000-$7FFF` | 4 VMs x 4K each (`$4000`, `$5000`, `$6000`, `$7000`) |

### 1802 Register Usage

| Register | Role |
|----------|------|
| R2 | 1802 stack pointer |
| R3 | Main program counter (SCRT) |
| R4/R5 | CALL/RETURN (SCRT) |
| R8 | VM program counter (fetches bytecodes) |
| R9 | VM stack pointer |
| RC | Core register pointer (`$30XX`) |

### VM Instruction Categories

| Opcode Range | Category |
|-------------|----------|
| `$01-$1F` | Data movement, register loads, I/O |
| `$20-$3F` | Stack operations, memory access |
| `$40-$5F` | Arithmetic (add, subtract, multiply, divide) |
| `$60-$7F` | Logic, shift, bit operations |
| `$80-$9F` | Test/compare operations |
| `$A0-$BF` | Flow control (branches, jumps, calls) |
| `$C0-$DF` | System, debug, VM management |

## File Guide

| File | Description |
|------|-------------|
| `STELLAR Full Code.rtf` | Master source — two-column RTF with design notes and hex machine code |
| `STELLAR_full_code.txt` | Plain text extraction of the source (for searching/diffing) |
| `STELLER CORE V0061.docx` | Definitive core memory layout reference |
| `STELLAR_HANDOFF.md` | Session-by-session development log and bug fix history |
| `STELLAR_ONBOARDING.md` | Technical reference for the architecture and code format |

## Applications

Programs written in the STELLAR VM instruction set, hand-assembled as D-line hex. All load at `$4000` (VM1) and run over the terminal. Found in [`APPLICATIONS/`](APPLICATIONS/).

| App | Description |
|-----|-------------|
| `Simple-Calc.lst` | Terminal four-function calculator with chained operations |
| `Prime-Gen.lst` | Prime-number generator over a user-supplied range |
| `Tic-Tac-Toe.lst` | Tic-Tac-Toe against a heuristic computer opponent; board drawn with a 1–9 position legend |
| `Lite-Writer.lst` | Minimal terminal text-entry editor |
| `STAR-Writer.lst` | Basic terminal text-entry app |
| `ELIZA.lst` | ELIZA-style conversational chatbot (keyword matching + pronoun swap) |
| `Banner.lst` | Big-letter ASCII banner printer, 5x5 pre-rendered font |
| `Mandelbrot.lst` | ASCII Mandelbrot set, Q8.8 sign-magnitude fixed point |
| `Game-of-Life.lst` | Conway's Game of Life, animated on a 40x20 grid |
| `Starship.lst` | The COSMAC ELF logo as a static picture; any key quits |
| `Bouncing-Ball.lst` | Two 3x3 reverse-video balls bouncing off the walls and each other |
| `Invaders.lst` | Space Invaders: two rows of six, arrow-key gun, aliens drop bombs |

## Code Format

The source uses D-line notation for machine code:

```
D 0150 F8 08 BB BD
```

- `D` — line prefix (not an opcode)
- `0150` — absolute memory address
- `F8 08 BB BD` — hex bytes: `LDI $08`, `PHI RB`, `PHI RD`

The left column of the RTF contains design notes, pseudocode, and register usage documentation. The right column contains the hex machine code.

## About the CDP1802

The RCA COSMAC CDP1802 is an 8-bit CMOS microprocessor introduced in 1976. Notable for its radiation hardness and low power consumption, it was used in the Galileo spacecraft, COSMAC VIP/ELF hobby computers, and various military/space applications. It features 16 general-purpose 16-bit registers, a single 8-bit accumulator (D), and a unique register-as-program-counter architecture where any register can serve as the PC.

## Status

Active development. Current version: V0061 core layout.

## License

All rights reserved. Copyright Craig Ledbetter.
