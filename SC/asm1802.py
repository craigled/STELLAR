# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""asm1802 - the small RCA 1802 assembler behind Stellar C's native { } blocks.

    assemble(lines, base, value) -> (bytes, listing, labels, shorts)

lines    (line number, label or None, mnemonic or None, operand text) tuples
base     the absolute address the code starts at
value    value(text, labels) -> int, the caller's expression evaluator; labels is
         None on the sizing pass (sizes never depend on values)

It knows the whole 1802 instruction set plus DB / DW data, CALL addr (D4 hi lo, the
firmware's SCRT call) and RETN (D5). Register operands are R0-RF or a hex digit.
shorts lists (operand address, target) for every short branch, so the caller can
enforce the page rule once the final address is known.
"""
import re

REG = {'LDN': 0x00, 'INC': 0x10, 'DEC': 0x20, 'LDA': 0x40, 'STR': 0x50, 'GLO': 0x80,
       'GHI': 0x90, 'PLO': 0xA0, 'PHI': 0xB0, 'SEP': 0xD0, 'SEX': 0xE0}
ONE = {'IDL': 0x00, 'IRX': 0x60, 'RET': 0x70, 'DIS': 0x71, 'LDXA': 0x72, 'STXD': 0x73,
       'ADC': 0x74, 'SDB': 0x75, 'SHRC': 0x76, 'RSHR': 0x76, 'SMB': 0x77, 'SAV': 0x78,
       'MARK': 0x79, 'REQ': 0x7A, 'SEQ': 0x7B, 'SHLC': 0x7E, 'RSHL': 0x7E, 'SKP': 0x38,
       'NOP': 0xC4, 'LSNQ': 0xC5, 'LSNZ': 0xC6, 'LSNF': 0xC7, 'LSKP': 0xC8, 'LSIE': 0xCC,
       'LSQ': 0xCD, 'LSZ': 0xCE, 'LSDF': 0xCF, 'LDX': 0xF0, 'OR': 0xF1, 'AND': 0xF2,
       'XOR': 0xF3, 'ADD': 0xF4, 'SD': 0xF5, 'SHR': 0xF6, 'SM': 0xF7, 'SHL': 0xFE,
       'RETN': 0xD5}
IMM = {'ADCI': 0x7C, 'SDBI': 0x7D, 'SMBI': 0x7F, 'LDI': 0xF8, 'ORI': 0xF9, 'ANI': 0xFA,
       'XRI': 0xFB, 'ADI': 0xFC, 'SDI': 0xFD, 'SMI': 0xFF}
SHORT = {'BR': 0x30, 'BQ': 0x31, 'BZ': 0x32, 'BDF': 0x33, 'BPZ': 0x33, 'BGE': 0x33,
         'B1': 0x34, 'B2': 0x35, 'B3': 0x36, 'B4': 0x37, 'BNQ': 0x39, 'BNZ': 0x3A,
         'BNF': 0x3B, 'BM': 0x3B, 'BL': 0x3B, 'BN1': 0x3C, 'BN2': 0x3D, 'BN3': 0x3E,
         'BN4': 0x3F}
LONG = {'LBR': 0xC0, 'LBQ': 0xC1, 'LBZ': 0xC2, 'LBDF': 0xC3, 'LBNQ': 0xC9, 'LBNZ': 0xCA,
        'LBNF': 0xCB, 'CALL': 0xD4}
PORT = {'OUT': 0x60, 'INP': 0x68}


class AsmError(Exception): pass


def register(t, ln):
    m = re.fullmatch(r'[Rr]?([0-9A-Fa-f])', t.strip())
    if not m: raise AsmError('line %d: %r is not a register' % (ln, t))
    return int(m.group(1), 16)


def split_args(text):
    """DB / DW operands: split on commas outside quotes."""
    out, cur, q = [], '', None
    for ch in text:
        if q:
            cur += ch
            if ch == q and not cur.endswith('\\' + q): q = None
        elif ch in '"\'': q = ch; cur += ch
        elif ch == ',': out.append(cur.strip()); cur = ''
        else: cur += ch
    if cur.strip(): out.append(cur.strip())
    return out


def encode(mn, arg, ln, addr, value, labels):
    """-> (bytes, short-branch target or None)"""
    if mn in ONE:
        if arg: raise AsmError('line %d: %s takes no operand' % (ln, mn))
        return [ONE[mn]], None
    if mn in REG:
        r = register(arg, ln)
        if mn == 'LDN' and r == 0: raise AsmError('line %d: LDN R0 is IDL on the 1802' % ln)
        return [REG[mn] | r], None
    if mn in PORT:
        n = value(arg, labels)
        if not 1 <= n <= 7: raise AsmError('line %d: %s port must be 1-7' % (ln, mn))
        return [PORT[mn] | n], None
    if mn in IMM:
        v = value(arg.lstrip('#'), labels)
        if labels is not None and not -128 <= v <= 255:
            raise AsmError('line %d: %s %s = %d: not a byte' % (ln, mn, arg, v))
        return [IMM[mn], v & 255], None
    if mn in SHORT:
        t = value(arg, labels)
        return [SHORT[mn], t & 255], t
    if mn in LONG:
        t = value(arg, labels)
        return [LONG[mn], (t >> 8) & 255, t & 255], None
    if mn in ('DB', 'DW'):
        out = []
        for a in split_args(arg):
            if a.startswith('"'):
                if mn == 'DW': raise AsmError('line %d: a string in DW' % ln)
                out += list(a[1:-1].encode('latin1').decode('unicode_escape').encode('latin1'))
                continue
            v = value(a, labels)
            out += [v & 255] if mn == 'DB' else [(v >> 8) & 255, v & 255]
        return out, None
    raise AsmError('line %d: unknown 1802 instruction %r' % (ln, mn))


def assemble(lines, base, value):
    labels, addr = {}, base
    for ln, label, mn, arg in lines:                           # pass 1: sizes and labels
        if label:
            if label in labels: raise AsmError('line %d: label %s: defined twice' % (ln, label))
            labels[label] = addr
        if mn: addr += len(encode(mn, arg, ln, addr, value, None)[0])
    out, listing, shorts, addr = [], [], [], base
    for ln, label, mn, arg in lines:                           # pass 2: bytes
        if not mn:
            if label: listing.append((addr, [], label + ':', ln))
            continue
        bs, short = encode(mn, arg, ln, addr, value, labels)
        if short is not None: shorts.append((addr + 1, short, ln))
        listing.append((addr, bs, ('%s:  ' % label if label else '') + ('%s %s' % (mn, arg)).strip(), ln))
        out += bs; addr += len(bs)
    return out, listing, labels, shorts
