# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""kmove.py - move a block of kernel.asm out into a system program (NAME.PRG at PRGORG, $2C00): the block's references
to kernel symbols become KS_name (out/ksyms.inc), LBR MAIN becomes SEP R5 (back to the kernel), and the program
checks the kernel's stamp first. Used for VER, FREE (phase 4) and DIR, TYPE, DUMP, SAVE (phase 5).
    python3 kmove.py  (run once per move; edits kernel.asm, writes the .asm files)"""
import re

HDR = '''        CPU     1802
        INCL    "ltos.inc"
        INCL    "kapi.inc"
        INCL    "out/ksyms.inc"

        ORG     PRGORG - 6
        DW      START, PEND - START, START
        ORG     PRGORG
START:  LOAD    RD, 032DH       ; built for this kernel? (it uses the kernel's routines directly)
        LDA     RD
        XRI     HIGH(KS_STAMPV)
        LBNZ    OLD
        LDN     RD
        XRI     LOW(KS_STAMPV)
        LBNZ    OLD
'''
TAIL = '''OLD:    SEP     R4
        DW      K_PIN
        DB      'Not for this kernel - install LTOS again.',0DH,0AH,0
        SEP     R5
'''


def conv(blk, ks, inc):
    REGS = {'R%X' % i for i in range(16)} | {'LOW', 'HIGH'}
    local = set(re.findall(r'^([A-Z][A-Z0-9_]*):', blk, re.M))
    out = []
    for line in blk.splitlines():
        code, sep, com = line.partition(';')
        if "'" in code: out.append(line); continue
        if re.search(r'\bLBR\s+MAIN\b', code): code = code.replace('LBR     MAIN', 'SEP     R5     ')
        def rep(m):
            w = m.group(0)
            if w in local or w in REGS or w in inc: return w
            return 'KS_' + w if w in ks else w
        m = re.match(r'(\s*(?:[A-Z][A-Z0-9_]*:)?\s*\S+)(.*)', code)
        if m and m.group(2): code = m.group(1) + re.sub(r'\b[A-Z][A-Z0-9_]*\b', rep, m.group(2))
        out.append(code + sep + com)
    return '\n'.join(out)
