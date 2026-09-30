"""Tiny two-pass assembler for STELLAR bytecode test programs.

A program is a list of (bytes_or_ref, asm_text, explanation) rows.
  bytes: hex string, e.g. "11 01 09 00"
  ref:   ("A1", "FAIL")  -> opcode + 2-byte PROGRAM-RELATIVE address of the label
  label: (":", "FAIL")
"""
import re

def assemble(rows, base=0x4000):
    # pass 1: sizes and label addresses
    addr=base; labels={}; sized=[]
    for r in rows:
        item=r[0]
        if isinstance(item,tuple) and item[0]==":":
            # a second definition used to win silently (MOONBASE jumped into INVENTORY)
            if item[1] in labels:
                raise ValueError("label %r defined twice: $%04X and $%04X"
                                 % (item[1], labels[item[1]], addr))
            labels[item[1]]=addr; sized.append((None,r)); continue
        n = 3 if isinstance(item,tuple) else len(item.split())
        sized.append((addr,r)); addr+=n
    # pass 2: emit
    out=[]; addr=base
    for a,r in sized:
        item=r[0]
        if isinstance(item,tuple) and item[0]==":": continue
        if isinstance(item,tuple):
            op,lbl=item; t=labels[lbl]-base
            bs=[int(op,16),(t>>8)&0xFF,t&0xFF]
        else:
            bs=[int(x,16) for x in item.split()]
        out.append((a,bs,r[1],r[2] if len(r)>2 else ""))
        addr+=len(bs)
    return out, labels

def dlines(emitted):
    return "\n".join("D %04X %s"%(a," ".join("%02X"%b for b in bs)) for a,bs,_,_ in emitted)

def code_bytes(emitted):
    out={}
    for a,bs,_,_ in emitted:
        for i,b in enumerate(bs): out[a+i]=b
    return out

def lst(emitted, header):
    body="\n".join("D %04X %s"%(a," ".join("%02X"%b for b in bs)) for a,bs,_,_ in emitted)
    return header.rstrip()+"\n\n"+body+"\n"

# ---------------------------------------------------------------- claiming the VM blocks
# A VM runs at cold boot if its block starts with CD START (VM2 $5000, VM3 $6000,
# VM4 $7000), and loading a .lst only overwrites what it lists - so a program left
# from an earlier load would start again alongside the new one. claim_vms() ends
# a .lst with "D X000 00" for the blocks it claims but does not write:
#
#   * a MAIN file - its first program is VM1's, at $4000 - claims every block
#     above: VM2-4 are cleared, and any companion is loaded after it.
#   * a COMPANION file - its first program is VM2's or above, loaded after the
#     main file - claims only the blocks its SETSIZE takes (F2 0n straight after
#     its CD START), so it never clears another companion.
#
# So: load the VM1 file first, then any companions. Files that are one half of an
# older load-both set are left alone. Re-running is safe: the trailing claim
# block is recomputed.
CLAIM_SKIP = {'Race-VM1.lst', 'VMT-D3-Write.lst'}
_DLINE = re.compile(r'^D ([0-9A-Fa-f]{4})((?: [0-9A-Fa-f]{2})+)\s*$')
_CLAIM = re.compile(r'^D [567]000 00\s*$')

def claim_vms(path):
    import os
    name = os.path.basename(path)
    if name in CLAIM_SKIP or name.startswith('sched-'): return []
    text, add = claim_vms_text(open(path, encoding='latin1').read())
    if add is not None: open(path, 'w', encoding='latin1').write(text)
    return add or []

def claim_vms_text(text):
    """claim_vms on the text of a .lst: -> (new text, blocks added), (text, None) if no D-lines."""
    lines = text.split('\n')
    dl = [i for i, ln in enumerate(lines) if _DLINE.match(ln)]
    if not dl: return text, None
    while dl and _CLAIM.match(lines[dl[-1]]) and len(dl) > 1:      # the old claim block
        del lines[dl[-1]]; dl.pop()
    mem = {}
    for i in dl:
        m = _DLINE.match(lines[i]); a = int(m.group(1), 16)
        for k, b in enumerate(m.group(2).split()): mem[a + k] = int(b, 16)
    progs = [x for x in (4, 5, 6, 7) if mem.get(x << 12) == 0xCD]
    if not progs: add = []
    else:
        first = min(progs)
        if first == 4: want = [5, 6, 7]
        else:
            n = mem.get((first << 12) + 2, 1) if mem.get((first << 12) + 1) == 0xF2 else 1
            want = list(range(first + 1, min(first + n, 8)))
        add = [x for x in want if (x << 12) not in mem]
    lines[dl[-1] + 1:dl[-1] + 1] = ['D %X000 00' % x for x in add]
    return '\n'.join(lines), add
