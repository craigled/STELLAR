#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""
STELLAR bytecode disassembler.

Reads a STELLAR program (Elf2K ".lst" D-line format) and writes an annotated
disassembly to a ".dis" file.

    python3 stellar_disasm.py <program.lst> [output.dis]

If no output path is given, writes <program>.dis next to the input.

What it does:
  * Rebuilds the memory image from all `D <addr> <bytes>` lines.
  * Disassembles the code segment from the program entry, decoding operands
    into readable form (registers, $immediates, label numbers, CALL targets).
  * Stops decoding code at the `F0 00 00` pre-pass end marker, then dumps
    anything after it — and any later D-line block (e.g. the $4700 string
    table) — as a hex + ASCII data dump.
  * Cross-references labels: every `LBL n` is anchored, and every branch/call
    to a label or address is annotated with its target.

Self-contained: opcode lengths and names are baked in (validated against the
firmware $2E00 length table and the shipped apps). No firmware docx required.

Opcode set: STELLAR v0.61 (191+ opcodes). Unknown bytes are shown as `?`.
"""
import re, sys, os

# ---------------------------------------------------------------------------
# Opcode length table: bytes of OPERANDS that follow the opcode byte.
# 0xFF => variable length, resolved by vlen() below.
# ---------------------------------------------------------------------------
OPLEN = {
0x00:0,0x01:1,0x02:1,0x03:1,0x04:1,0x05:1,0x06:1,0x07:1,0x08:1,0x09:0,0x0A:1,
0x0C:1,0x0D:1,0x0E:1,0x0F:1,
0x10:2,0x11:3,0x12:0xFF,0x13:0,0x14:1,0x15:0,0x16:1,0x17:1,0x18:1,0x19:1,0x1A:1,
0x20:1,0x21:1,0x22:1,0x23:2,0x24:0,0x25:0,0x26:0,0x27:0,0x28:1,0x29:0,0x2A:0,
0x2B:0,0x2E:3,0x2F:3,0x30:1,0x31:2,0x32:3,0x33:1,0x34:1,0x35:2,0x36:2,0x37:2,0x38:2,
0x39:2,0x3A:2,0x3B:2,0x3C:2,0x3D:1,
0x40:0,0x41:0,0x42:1,0x43:1,0x44:1,0x45:1,0x46:1,0x47:1,0x48:1,0x49:1,0x4A:1,
0x4B:1,0x4C:1,0x4D:1,0x4E:2,0x4F:2,0x50:2,0x51:2,0x52:3,0x53:3,0x54:2,0x55:2,
0x56:1,0x57:1,0x58:1,0x59:1,0x5A:1,0x5B:1,0x5C:1,
0x60:1,0x61:1,0x62:1,0x63:0xFF,0x64:0xFF,0x65:0xFF,0x6A:1,0x6B:1,0x6C:0,0x6D:1,0x6E:0,
0x70:1,0x71:1,0x72:1,0x73:1,0x74:1,0x75:1,0x76:1,0x77:1,0x78:0,0x79:0,
0x80:1,0x81:2,0x82:1,0x83:0,0x84:1,0x85:1,0x86:3,0x87:1,0x88:1,0x89:1,0x8A:1,0x8B:1,
0x8C:1,0x8D:1,0x8E:0,0x8F:0,0x90:1,0x91:0,0x92:0,0x93:0,0x94:1,0x95:1,0x96:1,0x97:1,
0x98:0,0x99:1,0x9A:1,0x9B:1,0x9C:2,0x9D:0xFF,0x9E:1,0x9F:2,
0xA0:2,0xA1:2,0xA2:1,0xA3:1,0xA4:2,0xA5:2,0xA6:1,0xA7:1,0xA8:2,0xA9:2,0xAA:1,0xAB:1,
0xB0:2,0xB1:1,0xB2:1,0xB3:1,0xB4:1,0xB5:3,0xB6:2,0xB7:3,0xB8:2,0xB9:2,0xBA:3,0xBB:1,0xBC:1,0xBD:2,0xBE:1,0xBF:0,
0xC0:1,0xC1:1,0xC2:1,0xC3:0,0xC4:0,0xC5:0,0xC6:0,0xC7:1,0xC8:1,0xC9:0,0xCA:1,0xCB:0,0xCC:0,0xCD:0,0xCE:1,0xCF:1,
0xD0:1,0xD1:1,0xD2:1,0xD3:2,0xD4:2,0xD5:2,0xD6:2,0xD7:2,0xD8:1,0xD9:1,0xDA:1,0xDB:1,0xDC:3,0xDD:1,0xDE:2,0xDF:2,
0xF0:0,0xF1:2,0xF2:1,0xF6:1,0xFA:1,0xFB:2,0xFC:2,0xFD:1,0xFF:1,
}

NAMES = {
0x00:'HALT',0x01:'DEFOUT',0x02:'DEFIN',0x03:'DEFEF',0x04:'OUTI',0x05:'OUTA',0x06:'OUTX',0x07:'RTC',
0x08:'OUTMX',0x09:'GETEFA',0x0A:'SETQ',0x0C:'SIPA',0x0D:'GIPA',0x0E:'GIPX',0x0F:'WIP',
0x10:'LOADAI',0x11:'LOADXI',0x12:'LOADZAI',0x13:'COPYALH',0x14:'COPYXLH',0x15:'SWAPA',0x16:'SWAPX',
0x17:'SHIFTMA',0x18:'SETBITI',0x19:'RESETBITI',0x1A:'TESTBITI',
0x20:'MEMMODE',0x21:'COPYAX',0x22:'COPYXA',0x23:'COPYXY',0x24:'COPYAMA',0x25:'COPYMAA',
0x27:'COPYREMA',0x28:'COPYCCA',0x29:'COPYIOA',0x2A:'COPYAIO',0x2B:'COPYMAH',0x2E:'READIDX',0x2F:'WRITEIDX',
0x31:'COPYMXI',0x32:'COPYMX2I',0x33:'COPYMXA',0x34:'COPYAMX',0x35:'COPYIMXA',0x36:'COPYIAMX',
0x37:'COPYDEMXA',0x38:'COPYDEAMX',0x39:'COPYMXY',0x3A:'COPYXMY',0x3B:'COPYMXMY',0x3C:'COPYMXYZ',0x3D:'COMPAMX',
0x40:'INCA',0x41:'DECA',0x42:'INCX',0x43:'DECX',0x44:'ADDXY',0x45:'SUBXY',0x46:'ADDAX',0x47:'SUBAX',
0x48:'SUBXA',0x49:'MULTXA',0x4A:'MULTXY',0x4B:'DIVAX',0x4C:'DIVXA',0x4D:'DIVXY',0x4E:'ADDAI',0x4F:'SUBAI',
0x50:'ADDXYZ',0x51:'SUBXYZ',0x52:'ADDXI',0x53:'SUBXI',0x54:'ADDMXMY',0x55:'SUBMXMY',0x56:'ADDAMX',0x57:'SUBAMX',
0x58:'MULTAMX',0x59:'DIVAMX',0x5A:'MULTMXMY',0x5B:'DIVMXMY',0x5C:'DIVMAX',
0x60:'SHIFTBA',0x61:'SHIFTBX',0x62:'SHIFTBMA',0x63:'OR',0x64:'XOR',0x65:'AND',0x6A:'CLEARA',
0x6B:'CVT2DEC',0x6C:'CVT2HEX',0x6D:'SETHEXDEC',0x6E:'OUTDEC',
0x70:'PUSHA',0x71:'POPA',0x72:'PUSHX',0x73:'POPX',0x74:'PUSHMX',0x75:'POPMX',
0x76:'PUSHS',0x77:'POPS',0x78:'PUSHQ',0x79:'POPQ',
0x80:'TESTAX',0x81:'TESTAI',0x82:'TESTAMA',0x83:'TESTIO',0x84:'TESTIOI',0x85:'TESTADA',0x86:'TESTXI',
0x87:'TESTXY',0x88:'TESTGXY',0x89:'TESTLXY',0x8A:'TESTDAGX',0x8B:'TESTCCGX',0x8C:'TESTXZ',0x8D:'TESTAZ',
0x8E:'TESTREMZ',0x8F:'TESTDAREMZ',0x90:'TESTRANGEXY',0x91:'TESTSIGN',0x92:'TESTQ',0x93:'TESTCF',
0x94:'TESTSPEC',0x96:'TESTEXIT',0x97:'TESTIS',0x98:'TESTERROR',0x99:'TESTEFI',
0x9A:'TESTEVEN',0x9B:'TESTABZ',0x9C:'COMPMXMY',0x9D:'TESTMXI',0x9E:'TESTSYSTAT',0x9F:'TESTINP',
0xA0:'IFTRUEI',0xA1:'IFFALSEI',0xA2:'IFTRUEL',0xA3:'IFFALSEL',0xA4:'IFTRUEJI',0xA5:'IFFALSEJI',
0xA6:'IFTRUEX',0xA7:'IFFALSEX',
0xB0:'GAL',0xB1:'GTX',0xB2:'CALLL',0xB3:'LBL',0xB4:'GTL',0xB5:'LOOPI',0xB6:'LOOPL',0xB7:'LOOPXI',
0xB8:'LOOPXL',0xB9:'JUMPI',0xBA:'DEFSUB',0xBB:'STARTSUB',0xBC:'ENDSUB',0xBD:'CALL',0xBE:'RETURN',0xBF:'RETURNL',
0xC0:'DLYI',0xC1:'PRINTSTR',0xC2:'GETSTR',0xC3:'RAND',0xC4:'NOP',0xC5:'EINT',0xC6:'DINT',0xC7:'SETMULTI',0xC8:'SETCIN',
0xC9:'SEROUT',0xCA:'SEROUTI',0xCB:'SERIN',0xCC:'SERST',0xCD:'START',0xCE:'PAUSEVM',0xCF:'KILLVM',
0xD0:'SHAREVM',0xD1:'TESTVM',0xD2:'COPYVA',0xD3:'COPYVXY',0xD4:'COPYVMXY',0xD5:'COPYXVMY',0xD6:'COPYVMXVMY',
0xD7:'COPYVXVY',0xD8:'INCVA',0xD9:'DECVA',0xDA:'INCVX',0xDB:'DECVX',0xDC:'COPYBVMXVMY',0xDD:'TESTVSTAT',0xF1:'RUNMC',
0xDE:'TESTVXY',0xDF:'TESTVSR',
0xF0:'BRK',0xF2:'SETSIZE',0xF6:'CKSUMXY',0xFA:'RESETFLAG',0xFB:'FILLMEMXY',0xFC:'PULSESORTXY',0xFD:'CLEARPROG',0xFF:'DEBUG',
}

# opcodes whose single operand byte is a label number (for cross-referencing)
LABEL_REF = {0xA2,0xA3,0xA6,0xA7,0xB2,0xB4}
# opcodes whose operand is (XY LL) with the label in the 2nd byte
LABEL_REF2 = {0xB6,0xB8}         # LOOPL XY LL / LOOPXL 0X LL
# opcodes taking an absolute (relative-to-base) 16-bit address as first 2 operand bytes
ADDR_REF = {0xA0,0xA1,0xB0,0xBD}   # IFTRUEI/IFFALSEI/GAL/CALL


def vlen(mem, a):
    """Total instruction length for variable-length opcodes (incl. opcode byte)."""
    op = mem.get(a, 0)
    nxt = mem.get(a + 1, 0)
    if op == 0x12:                       # LOADZAI ZD NN...  (Z bytes of immediate)
        return 2 + ((nxt >> 4) or 2)
    if op in (0x63, 0x64, 0x65):         # OR/XOR/AND ZX (+NN NN when Z==1 immediate)
        return 2 if (nxt >> 4) != 1 else 4
    if op == 0x9D:                       # TESTMXI ZX NN... (Z bytes)
        return 2 + (nxt >> 4)
    return 1


# ---------------------------------------------------------------------------
# Operand rendering
# ---------------------------------------------------------------------------
def hi(b): return (b >> 4) & 0xF
def lo(b): return b & 0xF
def w(b0, b1): return (b0 << 8) | b1

def render(op, ops, base, labels):
    """Return (operand_text, comment_text) for one instruction."""
    n = len(ops)
    c = ''
    # ----- register / accumulator moves -----
    if op == 0x11 and n == 3:                              # LOADXI ZX NN NN
        z = hi(ops[0]); part = {0:'',1:'.lo',2:'.hi'}.get(z, '?')
        return f'R{lo(ops[0]):X}{part} = ${w(ops[1],ops[2]):04X}', c
    if op in (0x10,) and n == 2:                           # LOADAI NN NN
        return f'Acc = ${w(ops[0],ops[1]):04X}', c
    if op in (0x4E,0x4F,0x81) and n == 2:                  # ADDAI/SUBAI/TESTAI NN NN
        return f'${w(ops[0],ops[1]):04X}', c
    if op in (0x52,0x53) and n == 3:                       # ADDXI/SUBXI 0X NN NN
        v = w(ops[1],ops[2]); sv = v-0x10000 if v>=0x8000 else v
        c = f'(={sv})' if sv<0 else ''
        return f'R{lo(ops[0]):X} {"+=" if op==0x52 else "-="} ${v:04X}', c
    if op == 0x86 and n == 3:                              # TESTXI ZX NN NN
        z = hi(ops[0]); part={0:'',1:'.lo',2:'.hi'}.get(z,'?')
        return f'R{lo(ops[0]):X}{part} == ${w(ops[1],ops[2]):04X}', c
    if op == 0x23 and n == 2:                              # COPYXY 0Z XY
        z = lo(ops[0]); part={0:'',1:'.lo',2:'.hi'}.get(z,'?')
        return f'R{hi(ops[1]):X} -> R{lo(ops[1]):X}{part}', c
    if op in (0x21,0x22) and n == 1:                       # COPYAX ZX / COPYXA ZX
        acc={0:'Acc',1:'MA',2:'DA'}.get(hi(ops[0]),'?')
        return (f'{acc} -> R{lo(ops[0]):X}' if op==0x21
                else f'R{lo(ops[0]):X} -> {acc}'), c
    if op in (0x42,0x43) and n == 1:                       # INCX/DECX ZX
        return f'R{lo(ops[0]):X}' + (' (dec-adj)' if hi(ops[0])==1 else ''), c
    if op in (0x44,0x45,0x87,0x88,0x89) and n == 1:        # XY reg pair
        sep={0x44:'+',0x45:'-',0x87:'==',0x88:'>=',0x89:'<='}[op]
        return f'R{hi(ops[0]):X} {sep} R{lo(ops[0]):X}', c
    if op in (0x46,0x47,0x48,0x49,0x4A,0x4B,0x4C,0x4D) and n == 1:  # math X/Y or 0X
        return f'R{hi(ops[0]):X},R{lo(ops[0]):X}' if op in (0x4A,0x4D) else f'R{lo(ops[0]):X}', c
    if op in (0x50,0x51) and n == 2:                       # ADDXYZ/SUBXYZ XY 0Z
        return f'R{hi(ops[0]):X},R{lo(ops[0]):X} -> R{lo(ops[1]):X}', c
    if op in (0x8C,0x80) and n == 1:                       # TESTXZ ZX / TESTAX ZX
        z=hi(ops[0]); part={0:'',1:'.lo',2:'.hi'}.get(z,'?')
        return (f'R{lo(ops[0]):X}{part} == 0' if op==0x8C else f'Acc == R{lo(ops[0]):X}{part}'), c
    if op in (0x35,0x36) and n == 2:                       # COPYIMXA/COPYIAMX 0D ZX
        d=lo(ops[0]); acc={0:'Acc',1:'MA',2:'DA'}.get(hi(ops[1]),'?')
        arrow = f'M(R{lo(ops[1]):X}) -> {acc}' if op==0x35 else f'{acc} -> M(R{lo(ops[1]):X})'
        return f'{d} byte(s), {arrow}', c
    if op in (0x33,0x34) and n == 1:                       # COPYMXA/COPYAMX ZX
        acc={0:'Acc',1:'MA',2:'DA'}.get(hi(ops[0]),'?')
        return (f'M(R{lo(ops[0]):X}) -> {acc}' if op==0x33 else f'{acc} -> M(R{lo(ops[0]):X})'), c
    # ----- labels / branches -----
    if op == 0xB3 and n == 1:
        return f'L{ops[0]:02X}', c
    if op in LABEL_REF and n == 1:
        tgt = labels.get(ops[0])
        c = f'-> ${tgt:04X}' if tgt is not None else '(label undefined)'
        return f'L{ops[0]:02X}', c
    if op in LABEL_REF2 and n == 2:
        tgt = labels.get(ops[1])
        c = f'-> ${tgt:04X}' if tgt is not None else '(label undefined)'
        cond = f'R{hi(ops[0]):X}>=R{lo(ops[0]):X}' if op==0xB6 else f'R{lo(ops[0]):X}==0'
        return f'L{ops[1]:02X}  [{cond}]', c
    if op in ADDR_REF and n >= 2:
        rel = w(ops[0],ops[1])
        c = f'-> ${base+rel:04X}'
        return f'${rel:04X}', c
    if op == 0xBE and n == 1:
        return ('(from call)' if ops[0]==0 else '(from last loc)'), c
    # ----- serial / misc small ones -----
    if op == 0xCA and n == 1:
        ch = chr(ops[0]) if 32<=ops[0]<127 else ''
        c = f"'{ch}'" if ch else ''
        return f'${ops[0]:02X}', c
    if op == 0xC1 and n == 1:                              # PRINTSTR 0X (custom, R X -> string)
        return f'M(R{lo(ops[0]):X}) (null-term string)', c
    if op == 0xC2 and n == 1:                              # GETSTR XY (cursor reg, floor reg)
        return f'cursor R{hi(ops[0]):X}, floor R{lo(ops[0]):X}', c
    if op == 0xF1 and n == 2:                              # RUNMC MM MM (jump to machine code)
        return f'machine code at ${ops[0]:02X}{ops[1]:02X}', c
    if op in (0x04,) and n == 1:
        return f'${ops[0]:02X}', c
    # ----- generic fallback: raw operand bytes -----
    return (' '.join(f'{b:02X}' for b in ops), c)


# ---------------------------------------------------------------------------
# .lst parsing
# ---------------------------------------------------------------------------
def read_lst(path):
    img = {}
    for ln in open(path):
        s = ln.strip()
        if s.startswith(';'):
            continue
        m = re.match(r'D\s+([0-9A-Fa-f]{4})\s+(.+)', s)
        if not m:
            continue
        a = int(m.group(1), 16)
        for t in m.group(2).split():
            if re.fullmatch(r'[0-9A-Fa-f]{2}', t):
                img[a] = int(t, 16); a += 1
            else:
                break
    return img


def segments(img):
    """Group the sparse image into contiguous [start,end] runs."""
    addrs = sorted(img)
    segs = []
    s = p = addrs[0]
    for a in addrs[1:]:
        if a == p + 1:
            p = a
        else:
            segs.append((s, p)); s = p = a
    segs.append((s, p))
    return segs


def collect_labels(img, lo_a, hi_a, base):
    """Pass 1: map label number -> address (the byte AFTER the LBL opcode)."""
    labels = {}
    a = lo_a
    while a <= hi_a:
        op = img.get(a, 0)
        L = OPLEN.get(op, 1)
        if L == 0xFF: L = vlen(img, a)
        L = (L + 1) if L != 0xFF else 1
        if op == 0xB3:
            labels[img.get(a + 1, 0)] = a          # anchor at the LBL itself
        if op == 0xF0 and img.get(a+1)==0 and img.get(a+2)==0:
            break
        a += L
    return labels


def data_dump(img, lo_a, hi_a, out):
    a = lo_a
    while a <= hi_a:
        row = [img.get(a + i) for i in range(16) if (a + i) <= hi_a]
        hexs = ' '.join(f'{b:02X}' for b in row)
        asc = ''.join(chr(b) if 32 <= b < 127 else '.' for b in row)
        out.append(f'{a:04X}  {hexs:<47}  |{asc}|')
        a += 16


def disassemble(path):
    img = read_lst(path)
    if not img:
        raise SystemExit(f'No D-lines found in {path}')
    segs = segments(img)
    entry = segs[0][0]
    base = entry & 0xF000                    # relative-address base (program block page)
    code_lo, code_hi = segs[0]

    labels = collect_labels(img, code_lo, code_hi, base)
    # reverse map addr->list of label numbers anchored there
    anchor = {}
    for num, ad in labels.items():
        anchor.setdefault(ad, []).append(num)

    out = []
    out.append(f'; STELLAR disassembly of {os.path.basename(path)}')
    out.append(f'; entry ${entry:04X}   relative base ${base:04X}   '
               f'{len(labels)} labels')
    out.append(';' + '-' * 68)

    a = code_lo
    ended = False
    while a <= code_hi:
        op = img.get(a, 0)
        L = OPLEN.get(op)
        if L is None:
            out.append(f'{a:04X}  {op:02X}                 ???  (unknown opcode)')
            a += 1; continue
        if L == 0xFF:
            total = vlen(img, a); nops = total - 1
        else:
            nops = L; total = L + 1
        ops = [img.get(a + 1 + i, 0) for i in range(nops)]
        raw = ' '.join(f'{b:02X}' for b in [op] + ops)
        name = NAMES.get(op, f'op{op:02X}')
        operand, comment = render(op, ops, base, labels)

        # end marker F0 00 00
        endmark = (op == 0xF0 and img.get(a+1)==0 and img.get(a+2)==0)
        if endmark:
            name = 'BRK'; operand = ''; comment = '<< pre-pass end marker (F0 00 00)'
            total = 3

        line = f'{a:04X}  {raw:<17} {name:<11} {operand}'
        if comment:
            line = f'{line:<52}; {comment}'
        out.append(line)
        a += total
        if endmark:
            ended = True
            data_start = a
            break

    # anything left in the code segment after the end marker = data
    if ended and data_start <= code_hi:
        out.append('')
        out.append(f'; --- trailing data in code segment (${data_start:04X}-${code_hi:04X}) ---')
        data_dump(img, data_start, code_hi, out)

    # later segments (string tables etc.) = data
    for (s, e) in segs[1:]:
        out.append('')
        out.append(f'; --- data segment ${s:04X}-${e:04X} ---')
        data_dump(img, s, e, out)

    # insert label anchor comments inline by re-emitting? simpler: footer index
    out.append('')
    out.append('; label index (number -> address):')
    for num in sorted(labels):
        out.append(f';   L{num:02X} = ${labels[num]:04X}')
    return '\n'.join(out) + '\n'


def main():
    if len(sys.argv) < 2:
        print(__doc__); raise SystemExit(2)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + '.dis'
    text = disassemble(src)
    open(dst, 'w').write(text)
    print(f'Disassembled {src} -> {dst} ({text.count(chr(10))} lines)')


if __name__ == '__main__':
    main()
