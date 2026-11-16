# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""ASM.PRG (the 1802 assembler on LTOS) on the simulated Elf2K, against a18 on the Mac.
A card with LTOS's own .inc files in /SRC (and out/ksyms.inc in /SRC/OUT), some of LTOS's programs' sources, a file
of every kind of line (asm_feat.src: IF / ELSE nesting, SET, FILL, TEXT, PAGE, CALL / RETN, every operator and
number, string escapes, lower case, Tabs, ::) and a file for each kind of mistake. ASM makes each .PRG on the card;
it must be a18's, byte for byte. Then: -l (each line's address and first bytes as a18's listing has them),
-o, a path, the .ASM taken as read, a .PRG replaced, $? 0 / 1, each mistake said with its line (nothing saved),
fsck clean.

    python3 LTOS/verify_asm.py [-v] [--all]       (--all: every program of LTOS that fits, not a few)
"""
import os, re, sys, glob, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

FEW = ['hello', 'touch', 'cal', 'deroff', 'sleep']
ALL = ['apps', 'cat', 'cls', 'copy', 'date', 'delete', 'deroff', 'dir', 'diskinfo', 'eartest', 'empty', 'fetch',
       'find', 'free', 'fsck', 'getstr', 'grep', 'help', 'hexd', 'hide', 'memverse', 'mkdir', 'mv', 'nl', 'play', 'pos',
       'recv', 'ren', 'rm', 'rmdir', 'running', 'send', 'sort', 'squeeze', 'sysrx', 'tail', 'time', 'tree', 'type',
       'uniq', 'ver', 'wc', 'xfer', 'hello', 'touch', 'pwd', 'cd', 'echo', 'head', 'sleep', 'cal', 'morse', 'stellar']
FEAT = os.path.join(HERE, 'asm_feat.src')
# each: the file, its text, what ASM says (line: words) - a18 must call each a mistake too
BAD = [('B1', '        ORG 3000H\n        LDI 300\n        END\n', '2: a value out of range'),
       ('B2', '        ORG 30FFH\n        BR  3000H\n        END\n', '2: a short branch out of this page'),
       ('B3', '        ORG 3000H\n        LDI NOPE\n        END\n', '2: a name not defined'),
       ('B4', '        ORG 3000H\n        FOO 1\n        END\n', '2: not an opcode'),
       ('B5', '        ORG 3000H\n        LDN 0\n        END\n', '2: not a register (0-15) or port (1-7)'),
       ('B6', '        ORG 3000H\nA       LDI 1\nA       LDI 2\n        END\n', '3: defined twice, with two values'),
       ('B7', '        ORG 3000H\n        DB  "abc\n        END\n', '2: no closing quote'),
       ('B8', '        ORG 3000H\n        LDI 12G\n        END\n', '2: not a number in its base'),
       ('B9', '        ORG 3000H\n        LDI (1 + 2\n        END\n', '2: ( and ) do not match'),
       ('B10', '        ORG 3000H\n        ORG LATER\nLATER   LDI 1\n        END\n', '2: a name defined only further on'),
       ('B11', '        ORG 3000H\n        ENDI\n        END\n', '2: IF / ELSE / ENDI out of order'),
       ('B12', '        ORG 3000H\n        INCL "NONE.INC"\n        END\n', '2: no such INCL file'),
       ('B13', '        ORG 3000H\n        LDI 1\n', '2: no END at the end'),
       ('B14', '        ORG 3000H\n        DB  \'x\' + 1\n        END\n', '2: more on the line than there should be'),
       ('B15', '        ORG 3000H\n        LDI 1 +\n        END\n', '2: not a good expression'),
       ('B16', '        ORG 3010H\n        LDI 1\n        ORG 3000H\n        LDI 2\n        END\n',
        '4: code at an address already made (an ORG back)'),
       ('B17', '        ORG 3000H\nHIGH    LDI 1\n        END\n', '2: not a label'),
       ('B18', '        ORG 3000H\n        DB  "a\\qb"\n        END\n', '2: not a \\ escape')]


def a18(path):
    """a18 on the Mac -> (the bytes from the lowest address to the highest, errors)."""
    d = tempfile.mkdtemp()
    hexf, lst = os.path.join(d, 'o.hex'), os.path.join(d, 'o.lst')
    r = subprocess.run([build.A18, path, '-l', lst, '-o', hexf], capture_output=True, text=True, cwd=os.path.dirname(path))
    errs = int(m.group(1)) if (m := re.search(r'(\d+) Error', r.stdout)) else 0
    mem = {}
    if os.path.exists(hexf):
        for ln in open(hexf):
            ln = ln.strip()
            if ln.startswith(':') and ln[7:9] == '00':
                n, a = int(ln[1:3], 16), int(ln[3:7], 16)
                for i in range(n): mem[a + i] = int(ln[9 + 2 * i:11 + 2 * i], 16)
    data = bytes(mem.get(a, 0) for a in range(min(mem), max(mem) + 1)) if mem else b''
    return data, errs, open(lst, encoding='latin1').read() if os.path.exists(lst) else ''


def main():
    v = '-v' in sys.argv
    progs = ALL if '--all' in sys.argv else FEW
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:15]]; ok &= not e
    _, syms = build.assemble('asm')
    e = []
    if syms['VEND'] > syms['SYMT']: e.append('the code and its variables end at $%04X, past the names at $%04X' % (syms['VEND'], syms['SYMT']))
    if syms['SYMT'] + syms['NSLOT'] * 6 > 0x6C00: e.append('the names run past $6BFF')
    report('ASM.PRG fits: $3000-$%04X, %d names $%04X-$%04X' % (syms['VEND'], syms['NSLOT'], syms['SYMT'], syms['SYMT'] + syms['NSLOT'] * 6 - 1), e)

    # a18 must call each BAD file a mistake, and take the feature file
    e = []
    tmp = tempfile.mkdtemp()
    for name, text, _ in BAD:
        p = os.path.join(tmp, name + '.ASM'); open(p, 'w').write(text)
        if a18(p)[1] == 0 and name != 'B16': e.append('a18 takes %s' % name)     # (B16: a18's hex may go back)
    feat, ferr, flst = a18(FEAT)
    if ferr: e.append('a18: asm_feat.src has %d errors' % ferr)
    report('a18 itself: each mistake file a mistake, asm_feat.src clean', e)

    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 32768
    cf, e2k, st = P1.installed(mem, n)
    def put(m):
        b = os.path.join(m, 'BIN'); os.makedirs(b, exist_ok=True)
        for p in ('ASM', 'CD', 'TYPE'): open(os.path.join(b, p + '.PRG'), 'wb').write(build.prg(p.lower()))
        d = os.path.join(m, 'SRC'); os.mkdir(d); os.mkdir(os.path.join(d, 'OUT')); os.mkdir(os.path.join(d, 'SUB'))
        for f in glob.glob(os.path.join(HERE, '*.inc')): open(os.path.join(d, os.path.basename(f).upper()), 'wb').write(open(f, 'rb').read())
        for f in glob.glob(os.path.join(HERE, 'out', '*.inc')):
            open(os.path.join(d, 'OUT', os.path.basename(f).upper()), 'wb').write(open(f, 'rb').read())
        for p in progs: open(os.path.join(d, p.upper() + '.ASM'), 'wb').write(open(os.path.join(HERE, p + '.asm'), 'rb').read())
        open(os.path.join(d, 'FEAT.ASM'), 'wb').write(open(FEAT, 'rb').read())
        open(os.path.join(d, 'SUB', 'HI.S'), 'wb').write(open(os.path.join(HERE, 'hello.asm'), 'rb').read())   # (INCL: from this folder, as a18's)
        for name, text, _ in BAD: open(os.path.join(d, name + '.ASM'), 'w').write(text)
        open(os.path.join(d, 'B1.PRG'), 'wb').write(b'old')                     # (a mistake: the old one stays)
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)

    cmds = ['ASM %s' % p.upper() for p in progs] + ['ASM FEAT.ASM', 'ASM -l FEAT > FEAT.LST', 'ASM -o OTHER.PRG HELLO',
            'ASM SUB/HI.S', 'ASM HELLO'] + ['ASM ' + x for x, _, _ in BAD] + ['ASM', 'ASM -x HELLO', 'ASM NOSUCH']
    later = [('LTOS> ', b'CD SRC\r')] + [('/SRC> ', x.encode() + b'\r') for x in cmds + ['MON']]
    b = V.Elf2K(cf, keys=b'', later=later)
    b.rtc = P3.clock()
    stat = []
    f0 = b.u.feed
    def feed():
        k = len(b.u.later)
        f0()
        if len(b.u.later) < k: stat.append(b.c.M[0x033F])
    b.u.feed = feed
    s = b.boot_rom(3_000_000_000_000)
    t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
    if v: print(t[-6000:])
    parts = re.split(r'(?m)^LTOS /SRC> ', t)[1:]
    out = [(p.partition('\n')[0], p.partition('\n')[2], stat[k + 2] if k + 2 < len(stat) else None) for k, p in enumerate(parts[:len(cmds)])]
    res = dict(zip(cmds, out))
    got = {}
    def rd(m):
        for f in [p.upper() + '.PRG' for p in progs] + ['FEAT.PRG', 'FEAT.LST', 'OTHER.PRG', 'SUB/HI.PRG', 'HELLO.PRG', 'B1.PRG'] + \
                 [x + '.PRG' for x, _, _ in BAD[1:]]:
            p = os.path.join(m, 'SRC', f)
            got[f] = open(p, 'rb').read() if os.path.exists(p) else None
    P2.mac(V.image(cf, n), rd)
    secs = b.steps / 112000                                 # (1.79 MHz: 16 clocks an instruction)

    e = []
    if s != 'stop': e.append('the end: %s' % s)
    for p in progs:
        want, g = build.prg(p), got[p.upper() + '.PRG']
        c, body, rc = res['ASM %s' % p.upper()]
        if g != want or rc != 0 or 'Saved %s.PRG: %d bytes' % (p.upper(), len(want)) not in body:
            i = next((j for j in range(min(len(g or b''), len(want))) if g[j] != want[j]), None)
            e.append('%s: %s (%s bytes, a18 %d; first difference at %s) $? %r %r' % (p, 'same' if g == want else 'NOT a18\'s', len(g) if g else None, len(want), i, rc, body[-200:]))
    report('ASM makes LTOS\'s own programs exactly as a18 does: %s' % ', '.join(progs), e)

    e = []
    if got['FEAT.PRG'] != feat:
        g = got['FEAT.PRG'] or b''
        i = next((j for j in range(min(len(g), len(feat))) if g[j] != feat[j]), min(len(g), len(feat)))
        e.append('FEAT.PRG: %d bytes, a18 %d; first difference at %d: %s / %s' % (len(g), len(feat), i, g[i:i + 8].hex(), feat[i:i + 8].hex()))
    if res['ASM FEAT.ASM'][2] != 0: e.append('$? %r: %r' % (res['ASM FEAT.ASM'][2], res['ASM FEAT.ASM'][1]))
    report('asm_feat.src (IF / ELSE, SET, FILL, TEXT, PAGE, CALL, every operator, number and escape): a18\'s bytes', e)

    e = []                                                  # the listing: each line's bytes are the .PRG's
    lst = (got['FEAT.LST'] or b'').decode('latin1').split('\n')
    lines = [l for l in lst if l.strip()]
    lo = 0x3000
    n_ok = 0
    for l in lines:
        m = re.match(r'^([0-9A-F]{4}) ([0-9A-F]{2,8}) ', l)
        if not m: continue
        a, bs = int(m.group(1), 16), bytes.fromhex(m.group(2))
        if feat[a - lo:a - lo + len(bs)] != bs: e.append('listed %s, the .PRG has %s' % (l[:40], feat[a - lo:a - lo + len(bs)].hex()))
        else: n_ok += 1
    if n_ok < 35: e.append('only %d listed lines with bytes' % n_ok)
    if not any(l.startswith('               ') and 'DB      3' in l for l in lines):
        e.append('IF 0\'s lines not shown without an address')
    if not any(l.startswith('3000 F834') for l in lines): e.append('the first line: %r' % [l for l in lines if l.startswith('3000')][:2])
    report('ASM -l: the listing (address, bytes, the line; a skipped line without an address), > FEAT.LST', e)

    e = []
    hello = build.prg('hello')
    if got['OTHER.PRG'] != hello: e.append('-o OTHER.PRG: %r' % (got['OTHER.PRG'] or b'')[:20])
    if got['SUB/HI.PRG'] != hello: e.append('SUB/HI.S (a path, an extension of its own) -> SUB/HI.PRG: %r' % (got['SUB/HI.PRG'] or b'')[:20])
    if got['HELLO.PRG'] != hello: e.append('HELLO.PRG made again: %r' % (got['HELLO.PRG'] or b'')[:20])
    for c in ('ASM', 'ASM -x HELLO'):
        if 'Usage: ASM' not in res[c][1] or res[c][2] != 1: e.append('%s: %r $? %r' % (c, res[c][1], res[c][2]))
    if 'there is no NOSUCH.ASM' not in res['ASM NOSUCH'][1] or res['ASM NOSUCH'][2] != 1: e.append('ASM NOSUCH: %r' % (res['ASM NOSUCH'],))
    report('-o name, a path (SUB/HI.S -> SUB/HI.PRG, INCL "../ltos.inc"), a .PRG made again, usage, no such file', e)

    e = []
    for name, text, want in BAD:
        c, body, rc = res['ASM ' + name]
        if ('%s.ASM %s' % (name, want)) not in body or 'nothing saved' not in body or rc != 1:
            e.append('%s: %r $? %r (want "%s.ASM %s")' % (name, body[-160:], rc, name, want))
        if name != 'B1' and got.get(name + '.PRG') is not None: e.append('%s.PRG made all the same' % name)
    if got['B1.PRG'] != b'old': e.append('B1.PRG (there before): %r' % got['B1.PRG'])
    report('each mistake said with its file and line, $? 1, nothing saved (an old .PRG left as it was)', e)

    rc, _ = P2.fsck_free(V.image(cf, n))
    report('fsck_msdos: the card clean (all those .PRGs, replaced ones, ones not saved)', ['fsck_msdos: %d' % rc] if rc else [])
    print("(a 1.79 MHz Elf2K's time for all of it: %.0f s)" % secs)
    print('\nASM: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
