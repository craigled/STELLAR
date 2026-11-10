# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build LTOS: assemble with a18, finish the boot sector, write INSTALL.HEX.      python3 LTOS/build.py

  boot.asm    -> boot.bin   (LBA 0, 512 bytes; its checksum byte set so the Elf2K BIOS accepts it)
  monstub.asm -> MON's last step (runs at $3000), into MON.PRG and STELLAR.PRG as out/monstub.inc
  kernel.asm  -> out/kernel.bin, loaded to $0300 by the boot sector
  install.asm -> the installer at $3000; with boot.bin at $4200, the kernel at $4400, the sample files at $6000
              -> INSTALL.HEX (Intel HEX, 16 bytes a record: paste it into the monitor, then CALL 3000)
"""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
A18 = os.path.join(HERE, '..', 'Firmware-Math', 'scratchpad', 'a18')
OUT = os.path.join(HERE, 'out')


def assemble(name):
    """a18 name.asm -> {address: byte}, {symbol: value}."""
    os.makedirs(OUT, exist_ok=True)
    src = os.path.join(HERE, name + '.asm')
    lst, hexf = os.path.join(OUT, name + '.lst'), os.path.join(OUT, name + '.a18.hex')
    r = subprocess.run([A18, src, '-l', lst, '-o', hexf], capture_output=True, text=True, cwd=HERE)
    errs = re.findall(r'^.*Error.*$|^\S.*\b[A-Z] Error\b.*$', r.stdout, re.M)
    listing = open(lst).read()
    bad = [l for l in listing.split('\n') if re.match(r'^[A-Z]  ', l) or re.match(r'^[A-Z] \d', l)]
    if r.returncode or bad or 'Errors' in r.stdout and not re.search(r'\b0 Errors?\b|No Errors', r.stdout, re.I):
        print(r.stdout); print('\n'.join(bad[:20])); raise SystemExit('%s: a18 reported errors' % name)
    mem = {}
    for ln in open(hexf):
        ln = ln.strip()
        if not ln.startswith(':') or ln[7:9] != '00': continue
        n, a = int(ln[1:3], 16), int(ln[3:7], 16)
        for i in range(n): mem[a + i] = int(ln[9 + 2 * i:11 + 2 * i], 16)
    syms = {}                                   # a18's symbol table lines: "0140  CKSUM         0003  DATPORT ..."
    for ln in listing.split('\n'):
        if re.fullmatch(r'(\s*[0-9a-fA-F]{4}  [A-Z_][A-Z0-9_]*)+\s*', ln):
            for v, n in re.findall(r'([0-9a-fA-F]{4})  ([A-Z_][A-Z0-9_]*)', ln): syms[n] = int(v, 16)
    return mem, syms


def btcheck(sector):
    """The Elf2K BIOS's boot check (bios.asm btcheck, 1.0.6 and later), instruction by instruction:
    GLO RD / ADD / IRX / SHL / SHR / SHLC / PLO RD over $0100-$0140; it must end as $60."""
    d = 0
    for b in sector[:0x41]:
        s = d + b; d, df = s & 0xFF, s >> 8          # ADD
        df, d = d >> 7, (d << 1) & 0xFF               # SHL
        df, d = d & 1, d >> 1                         # SHR
        d = ((d << 1) | df) & 0xFF                    # SHLC
    return d


def boot_sector():
    mem, syms = assemble('boot')
    sec = bytearray(512)
    for a, b in mem.items():
        assert 0x100 <= a < 0x300, 'boot.asm put a byte at $%04X' % a
        sec[a - 0x100] = b
    end = syms.get('BOOTEND')
    assert end is not None and end <= 0x2BE, 'the boot code ends at $%04X, past the partition table at $02BE' % (end or 0)
    ck = syms['CKSUM'] - 0x100
    for v in range(256):
        sec[ck] = v
        if btcheck(sec) == 0x60: break
    else: raise SystemExit('no checksum byte makes the boot check come out $60')
    assert sec[0x1FE:0x200] == b'\x55\xAA'
    return bytes(sec), end, v


def intel_hex(mem):
    out, addrs = [], sorted(mem)
    i = 0
    while i < len(addrs):
        a = addrs[i]; run = [mem[a]]
        while i + len(run) < len(addrs) and addrs[i + len(run)] == a + len(run) and len(run) < 16: run.append(mem[a + len(run)])
        rec = [len(run), a >> 8, a & 0xFF, 0] + run
        out.append(':' + ''.join('%02X' % x for x in rec) + '%02X' % (-sum(rec) & 0xFF))
        i += len(run)
    return '\n'.join(out + [':00000001FF']) + '\n'


def help_records():
    """help.txt -> [('h', heading)] / [('c', [names], summary, [page lines])], in order."""
    recs = []
    for ln in open(os.path.join(HERE, 'help.txt')).read().split('\n'):
        if ln.startswith(';'): continue
        assert len(ln) < 78 and all(32 <= ord(ch) < 127 for ch in ln), 'help.txt: %r' % ln
        if ln.startswith('#'): recs.append(('h', ln[1:].strip()))
        elif ln.startswith('@'):
            nm, _, summ = ln[1:].partition(' ')
            recs.append(('c', nm.upper().split(','), summ.strip(), []))
        elif recs and recs[-1][0] == 'c': recs[-1][3].append(ln.rstrip())
    for r in recs:
        if r[0] == 'c':
            while r[3] and not r[3][-1]: r[3].pop()
    return recs


def help_list():
    """HELP alone: the title, then each group's commands - as HELP.PRG prints it (LF line ends)."""
    t = 'LTOS 0.5 - the commands.  HELP name tells more about one.\n'
    for r in help_records():
        if r[0] == 'h': t += '\n' + r[1] + '\n'
        else: t += '  ' + ' '.join(r[1]).ljust(12) + r[2] + '\n'
    return t


def help_dats(most=12000):
    """HELP.HLP, HELP2.HLP (and HELP3.HLP): the records split where one starts, each ending with a 0 - so each fits in
    one part of LTOS-SYSTEM, and in memory: HELP.PRG holds one at a time (the next once it reaches one's end)."""
    b = help_dat()[:-1]
    starts = [i for i in range(len(b)) if b[i] in (1, 2) and (i == 0 or b[i - 1] == 0)] + [len(b)]
    parts, at = [], 0
    while at < len(b):
        cut = max(i for i in starts if i <= at + most - 1)
        assert cut > at, 'a help record is too big'
        parts.append(b[at:cut] + b'\0'); at = cut
    assert len(parts) <= 3, 'the help needs a HELP4.HLP (HELP.PRG reads 3 parts at most)'
    return [((b'HELP%-4sHLP' % (b'' if k == 0 else str(k + 1).encode())), p) for k, p in enumerate(parts)]


def help_dat():
    """help.txt -> HELP.DAT's bytes (HELP.PRG loads them: 1 heading 0 / 2 names 0 summary 0 page 0 / 0)."""
    b = bytearray()
    for r in help_records():
        if r[0] == 'h': b += b'\x01' + r[1].encode() + b'\0'
        else: b += (b'\x02' + ','.join(r[1]).encode() + b'\0' + r[2].encode() + b'\0' +
                    ''.join(l + '\n' for l in r[3]).encode() + b'\0')
    b += b'\0'
    return bytes(b)



def fat_now():
    import datetime
    t = datetime.datetime.now()
    time = (t.hour << 11) | (t.minute << 5) | (t.second // 2)
    date = ((t.year - 1980) << 9) | (t.month << 5) | t.day
    return time, date


def shstub():
    """shstub.asm (SH's way back after an outside command, at $2E00) -> out/shstub.inc, for sh.asm to copy there."""
    stub, ss = assemble('shstub')
    lo, hi = min(stub), max(stub)
    assert lo == 0x2E00 and hi < 0x2E98, 'SH\'s stub must fit in $2E00-$2E97 (its state is at $2E98)'
    body = bytes(stub.get(a, 0) for a in range(lo, hi + 1))
    with open(os.path.join(OUT, 'shstub.inc'), 'w') as f:
        f.write('SS_SUM  EQU     0%04XH\nSTUBN   EQU     %d\n' % (ss['SSUMIT'], len(body)))
        for i in range(0, len(body), 16):
            f.write('        DB      ' + ', '.join('0%02XH' % b for b in body[i:i + 16]) + '\n')


def prg(name):
    """A program (its 6-byte header just before its load address: $3000, $4000 for STELLAR, $6800 for SAVE, DUMP and MON) -> the
    .PRG file's bytes."""
    if name == 'sh': shstub()
    mem, syms = assemble(name)
    if name == 'sh':                                            # SH: its code $4000-$6BFF, its buffers $7700-$79FF
        assert syms['START'] == 0x4000 and syms['PEND'] <= 0x6C00, 'SH.PRG runs to $%04X - past $6BFF' % syms['PEND']
        assert syms['RAWL'] >= 0x7700 and syms['VEND2'] <= 0x7C00, 'SH.PRG: its buffers not in $7700-$7BFF'

    lo = min(a for a in mem if a >= 0x2FFA) + 6
    if 'RAWKEND' in syms:                                       # RAWK: its buffers end below LTOS's ($6C00)
        assert syms['RAWKEND'] <= 0x6C00, 'RAWK.PRG: its buffers run to $%04X' % syms['RAWKEND']
        assert syms['RUNEND'] <= syms['PEND'], 'RAWK.PRG: the buffers for running ($%04X) pass the compiler ($%04X)' % (syms['RUNEND'], syms['PEND'])
        assert syms['LOOPSE'] <= 0x7C00 and syms['TMPE'] <= 0x7C00, 'RAWK.PRG: past $7BFF'
        assert syms['CEND'] <= syms['STEPB'], 'RAWK.PRG: its variables ($%04X) run into the steps ($%04X)' % (syms['CEND'], syms['STEPB'])
    if 'HXPEND' in syms:                                        # RECV's HEX loop / STLRX's D-line loop: one page
        assert syms['HXPEND'] - 1 < (lo & 0xFF00) + 0x100, '%s: its receive loop crosses a page' % name
    if 'RXPEND' in syms:                                        # XFER's frame loop: one page
        assert syms['RXL'] & 0xFF00 == (syms['RXPEND'] - 1) & 0xFF00, '%s: its receive loop crosses a page' % name
        assert syms['BUF'] + 516 <= 0x6A00, '%s: BUF runs into its CRC tables at $6A00' % name
    if 'FWMSGN' in syms:                                       # FW.PRG: its last line fits over the stub's
        assert syms['FWMSGN'] <= syms['MS_MSOKN'], 'FW.PRG: its message is longer than the stub\'s'
    if name == 'stellar':                                       # at $4000: clear of $3000-$3FFF (MON's stub, the jobs,
        assert lo == 0x4000 and syms['PEND'] <= syms['ATTORG'], 'STELLAR.PRG runs into ATTACH.PRG ($%04X)' % syms['ATTORG']
        assert syms['VEND'] <= 0x6C00, 'STELLAR.PRG: its variables past $6C00'  #  ATTACH's note, the kept slots)
        assert syms['VARS'] >= 0x6B00, 'STELLAR.PRG: its variables below $6B00 (ATTACH.PRG may run to $6AFF)'
    if name == 'attach':                                        # at ATTORG, clear of STELLAR.PRG's variables
        assert lo == syms['ATTORG'] and syms['PEND'] <= 0x6B00, 'ATTACH.PRG runs into STELLAR.PRG\'s variables'
    if name == 'enano':                                         # its code around ATTACH's note, clear of ATTACH.PRG
        assert syms['OVLHD'] == 0x6900 == syms['TEND'] and syms['OVLAE'] <= 0x6E00, 'NANO.OVL\'s first half is not in $6900-$6DFF ($%04X)' % syms['OVLAE']
        assert syms['OVLEND'] <= 0x7C00, 'NANO.OVL\'s second half passes $7BFF ($%04X)' % syms['OVLEND']
        mem = {a: v for a, v in mem.items() if a < 0x6900}      # (NANO.OVL: enano_ovl())
        assert lo == 0x3000 and syms['ENDA'] <= 0x3300, 'NANO.PRG: its first part runs into the note ($%04X)' % syms['ENDA']
        assert syms['CODEB'] == 0x3400 and syms['PEND'] <= syms['ATTORG'], 'NANO.PRG runs into ATTACH.PRG ($%04X)' % syms['PEND']
        assert syms['NOTE'] + syms['V_VEND'] <= syms['NAMEZ'], 'NANO.PRG: its variables run into NAMEZ'
    if name == 'stlrx':                                         # its code in $7700-$7BFF, its variables $7C00 up
        assert lo == 0x7700 and syms['PEND'] <= 0x7C00, 'STLRX.PRG is not in $7700-$7BFF'
        assert 0x7C00 <= syms['NTXT'] and syms['STLVEND'] <= 0x7D00, 'STLRX.PRG\'s variables must sit at $7C00-$7CFF'
    hdr = min(a for a in mem if a >= 0x2FFA)
    end = max(a for a in mem if a >= 0x2FFA) + 1
    return bytes(mem.get(a, 0) for a in range(hdr, end))


def enano_ovl():
    """NANO.OVL: NANO's code that is not in NANO.PRG - $6900-$6DFF (1,280 bytes, padded), then $7700 on. NANO.PRG
    loads it once ATTACH.PRG has run and puts the two halves in place: the screen, the keys, the mark."""
    mem, syms = assemble('enano')
    return bytes(mem.get(a, 0) for a in range(0x6900, 0x6E00)) + bytes(mem.get(a, 0) for a in range(0x7700, syms['OVLEND']))


def sysparts():
    """The system bundle's files, in the order they are sent: LTOS-SYSTEM.HEX, then 2, 3 ... (as many as there are)."""
    return [n for n in ['LTOS-SYSTEM.HEX'] + ['LTOS-SYSTEM%d.HEX' % k for k in range(2, SYSMAX + 1)] if os.path.exists(os.path.join(OUT, n))]


def samples():
    """[(11-byte name, bytes)] - every file LTOS puts on the card besides STELLAR.BIN, most needed first: the
    installer takes as many as fit; LTOS-SYSTEM.HEX (RECV SYSTEM) carries them all."""
    return [(b'RECV    PRG', prg('recv')), (b'MON     PRG', prg('mon')), (b'STLRX   PRG', prg('stlrx')), (b'TYPE    PRG', prg('type')), (b'HELP    TXT', help_list().encode('ascii')),
            (b'DIR     PRG', prg('dir')), (b'SAVE    PRG', prg('save')), (b'LOAD    PRG', prg('load')), (b'DUMP    PRG', prg('dump')), (b'VER     PRG', prg('ver')),
            (b'FREE    PRG', prg('free')), (b'DISKINFOPRG', prg('diskinfo')), (b'COPY    PRG', prg('copy')), (b'HEX     PRG', prg('hexd')),
            (b'HELLO   PRG', prg('hello')), (b'STELLAR PRG', prg('stellar')), (b'APPS    PRG', prg('apps')), (b'FW      PRG', prg('fw')),
            (b'DATE    PRG', prg('date')), (b'TIME    PRG', prg('time')), (b'MKDIR   PRG', prg('mkdir')),
            (b'RMDIR   PRG', prg('rmdir')), (b'MV      PRG', prg('mv')),
            (b'RM      PRG', prg('rm')), (b'DEL     PRG', prg('rm')), (b'REN     PRG', prg('ren')), (b'CLS     PRG', prg('cls')), (b'CD      PRG', prg('cd')),
            (b'WC      PRG', prg('wc')), (b'GREP    PRG', prg('grep')), (b'FIND    PRG', prg('find')), (b'TREE    PRG', prg('tree')), (b'SEND    PRG', prg('send')), (b'FSCK    PRG', prg('fsck')), (b'XFER    PRG', prg('xfer')), (b'RAWK    PRG', prg('rawk')),
            (b'ECHO    PRG', prg('echo')), (b'CAT     PRG', prg('cat')), (b'HEAD    PRG', prg('head')), (b'TAIL    PRG', prg('tail')), (b'TOUCH   PRG', prg('touch')), (b'SH      PRG', prg('sh')), (b'EROFF   PRG', prg('eroff')), (b'PWD     PRG', prg('pwd')), (b'SORT    PRG', prg('sort')), (b'UNIQ    PRG', prg('uniq')),
            (b'ATTACH  PRG', prg('attach')), (b'HELP    PRG', prg('help')), (b'NANO    PRG', prg('enano')), (b'NANO    OVL', enano_ovl()),
            (b'GETSTR  PRG', prg('getstr')), (b'FETCH   PRG', prg('fetch')), (b'POS     PRG', prg('pos')),
            (b'DELETE  PRG', prg('delete')), (b'EMPTY   PRG', prg('empty')), (b'RUNNING PRG', prg('running')), (b'MEMVERSEPRG', prg('memverse')), (b'LTCALC  PRG', prg('ltcalc')), (b'SED     PRG', prg('sed')), (b'SYSRX   PRG', prg('sysrx')), (b'SQUEEZE PRG', prg('squeeze')), (b'HIDE    PRG', prg('hide')), (b'PLAY    PRG', prg('play'))] + help_dats()


def stl_of(lst):
    """What RECV NAME.STL makes of a STELLAR .lst: only its 'D aaaa bb ...' lines; sector 0 = 'STL1', the block
    count, each 512-byte block's address (in the order its first byte appears); then the blocks (undefined bytes 0)."""
    import re
    order, blocks = [], {}
    for line in lst.replace('\r', '\n').split('\n'):
        m = re.match(r'D +([0-9A-F]{4})((?: +[0-9A-F]{2})+) *$', line)
        if not m: continue
        a = int(m.group(1), 16)
        for k, x in enumerate(m.group(2).split()):
            blk = (a + k) >> 9
            if blk not in blocks: blocks[blk] = bytearray(512); order.append(blk)
            blocks[blk][(a + k) & 511] = int(x, 16)
    head = b'STL1' + bytes([len(order)]) + b''.join(bytes([(b << 9) >> 8, 0]) for b in order)
    return head.ljust(512, b'\0') + b''.join(bytes(blocks[b]) for b in order)


def vms_of(stl):
    """The VMs an .STL runs in, as APPS lists them: a VM's block ($4000/$5000/$6000/$7000) that starts with $CD."""
    return [(stl[5 + 2 * i] >> 4) - 3 for i in range(stl[4])
            if stl[5 + 2 * i] in (0x40, 0x50, 0x60, 0x70) and stl[512 * (i + 1)] == 0xCD]


def pak(files):
    """A bundle of files for RECV: 'LPAK', a count, name (11) / offset (2) / length (2) each, then the bytes."""
    head = 5 + 15 * len(files); body = b''; ents = b''
    for name, data in files:
        ents += name + bytes([(head + len(body)) >> 8, (head + len(body)) & 0xFF, len(data) >> 8, len(data) & 0xFF])
        body += data
    return b'LPAK' + bytes([len(files)]) + ents + body


SYSPARTS = []
SYSMAX = 12                                                   # LTOS-SYSTEM's parts at most (each one RECV SYSTEM)


def build(kernel=b''):
    boot, bend, ck = boot_sector()
    open(os.path.join(OUT, 'boot.bin'), 'wb').write(boot)
    mem, syms = assemble('install')
    assert syms['INSTEND'] <= syms['BOOTIMG'], 'the installer runs into the boot image ($%04X)' % syms['INSTEND']
    for i, b in enumerate(boot): mem[syms['BOOTIMG'] + i] = b
    nk = (len(kernel) + 511) // 512
    assert not kernel or (kernel[7] <= 9 and kernel[8] <= 9), 'the installer writes the version as one digit each (LTOSx.y)'
    assert nk <= 31, 'the kernel is %d sectors; there are 31' % nk
    assert syms['KERNIMG'] + nk * 512 <= syms['FTABMAX'], 'the kernel image runs past $%04X' % syms['FTABMAX']
    for i, b in enumerate(kernel.ljust(nk * 512, b'\0')): mem[syms['KERNIMG'] + i] = b
    mem[syms['KSECTS']] = nk
    tm, dt = fat_now()                                         # the files' time and date
    for i, v in enumerate((tm & 0xFF, tm >> 8, dt & 0xFF, dt >> 8)): mem[syms['DATEV'] + i] = v
    files = samples()                                          # FTAB: count, then name size where; bytes after -
    def fits(fl):                                              # the gap biggest-first, the rest after the table
        g = syms['INSTEND']; t = syms['KERNIMG'] + nk * 512 + 1 + 15 * len(fl)
        for d in sorted((d for n, d in fl), key=len, reverse=True):
            if g + len(d) <= syms['BOOTIMG']: g += len(d)
            else: t += len(d)
        return t <= syms['SBUF']
    while not fits(files): files = files[:-1]                  # as many as fit, in the order of samples()
    sysall = samples()                                         # LTOS-SYSTEM.HEX (+ 2.HEX .. 4.HEX): all of them
    rbuf = assemble('recv')[1]['BUF']                          # RECV keeps a HEX file from BUF up to PTOP:
    room = 0x6C00 - rbuf - 1                                   #  as many as fit in the first, the rest in a second
                                                               #  (its last byte below $6BFF: RECV's end check)
    parts = []                                                 # each file into the first part it fits in
    for f in sysall:
        for p in parts:
            if len(pak(p + [f])) <= room: p.append(f); break
        else: parts.append([f])
    assert len(parts) <= SYSMAX and all(len(pak(p)) <= room for p in parts), 'LTOS-SYSTEM does not fit in %d parts' % SYSMAX
    sy = assemble('sysrx')[1]                                  # LTOS-ALL.PAK (SYSRX, elfser.py system): one file, in 512-byte
    assert all(len(pak(p)) + 511 & ~511 <= 0x6C00 - sy['BUF'] for p in parts), 'a part is too big for SYSRX.PRG'
    paks = [pak(p).ljust((len(pak(p)) + 511) // 512 * 512, b'\0') for p in parts]      # blocks: first the plan, then the parts
    plan = sum(map(len, paks)).to_bytes(4, 'little') + bytes([len(paks)]) + bytes(len(x) // 512 for x in paks)
    open(os.path.join(OUT, 'LTOS-ALL.PAK'), 'wb').write(plan.ljust(512, b'\0') + b''.join(paks))
    for k in range(SYSMAX):                                    # LTOS-SYSTEM.HEX, LTOS-SYSTEM2.HEX .. (as many as needed)
        nm = 'LTOS-SYSTEM%s' % ('' if k == 0 else str(k + 1))
        if k < len(parts):
            sp = pak(parts[k])
            open(os.path.join(OUT, nm + '.HEX'), 'w').write(intel_hex({i: b for i, b in enumerate(sp)}))
            open(os.path.join(OUT, nm + '.PAK'), 'wb').write(sp)
        else:
            for ext in ('.HEX', '.PAK'):
                if os.path.exists(os.path.join(OUT, nm + ext)): os.remove(os.path.join(OUT, nm + ext))
    SYSPARTS[:] = [len(p) for p in parts]
    syslen = sum(len(pak(p)) for p in parts)                    # (one pack of them all would pass 64 KB)
    ftab = syms['KERNIMG'] + nk * 512                          #  or in the gap after the installer's variables
    mem[syms['FTABP']], mem[syms['FTABP'] + 1] = ftab >> 8, ftab & 0xFF
    at = ftab + 1 + 15 * len(files)
    gap0 = gat = syms['INSTEND']
    mem[ftab] = len(files)
    clusters = 24
    ingap = set()                                              # the gap: filled biggest-first with what fits
    for k in sorted(range(len(files)), key=lambda k: -len(files[k][1])):
        if gat + len(files[k][1]) <= syms['BOOTIMG']: ingap.add(k); gat += len(files[k][1])
    gat = gap0
    for k, (name, data) in enumerate(files):
        e = ftab + 1 + 15 * k
        if k in ingap: w = gat; gat += len(data)
        else: w = at; at += len(data)
        for i, b in enumerate(name): mem[e + i] = b
        mem[e + 11], mem[e + 12], mem[e + 13], mem[e + 14] = len(data) >> 8, len(data) & 0xFF, w >> 8, w & 0xFF
        for i, b in enumerate(data): mem[w + i] = b
        clusters += (len(data) + 511) // 512
    assert at <= syms['SBUF'], 'the files for the card run to $%04X, into the installer\'s buffers' % at
    assert clusters + 2 < 256, 'the files need more clusters than one FAT sector holds'
    # CHKTAB: the installer checks what it was loaded with, range by range, before it writes anything
    ranges = [(0x3000, syms['CODEEND'] - 0x3000), (syms['BOOTIMG'], 512), (syms['KERNIMG'], nk * 512), (ftab, at - ftab),
              (gap0, gat - gap0)]
    t = syms['CHKTAB']
    for k, (a0, n) in enumerate(ranges):
        missing = [a for a in range(a0, a0 + n) if a not in mem]
        assert not missing, 'CHKTAB range %d has bytes INSTALL.HEX does not load ($%04X...)' % (k, missing[0])
        sm = sum(mem[a] for a in range(a0, a0 + n)) & 0xFFFF
        for i, v in enumerate((a0 >> 8, a0 & 0xFF, n >> 8, n & 0xFF, sm >> 8, sm & 0xFF)): mem[t + 6 * k + i] = v
    ks = sum(kernel.ljust(nk * 512, b'\0')) & 0xFFFF       # the boot sector checks the sum of all nk sectors
    mem[syms['KSUM']], mem[syms['KSUM'] + 1] = ks >> 8, ks & 0xFF
    open(os.path.join(OUT, 'INSTALL.HEX'), 'w').write(intel_hex(mem))
    # INSTALL2.HEX (CALL 3003 after F): the files INSTALL.HEX had no room for, in samples() order, as many as fit at
    # I2AT (the kernel image's place, on the card by then) below SBUF, in the root's first sector and the FAT's
    m2, a2 = {}, syms['I2AT'] + 4
    rest = [f for f in samples()[len(files):] if f[0] in (b'RECV    PRG', b'MON     PRG', b'MKDIR   PRG', b'SYSRX   PRG')]   # (RECV SYSTEM: the rest, into /BIN)
    files2 = []
    for n, d in rest:                                          # 16 entries: the label, STELLAR.BIN, the files
        if (a2 + 1 + 15 * (len(files2) + 1) + sum(len(x) for _, x in files2) + len(d) > syms['SBUF']
                or 2 + len(files) + len(files2) + 1 > 16 or clusters + (len(d) + 511) // 512 + 2 >= 256): break
        files2.append((n, d)); clusters += (len(d) + 511) // 512
    assert files2 and files2[0][0] == b'RECV    PRG' or files and files[0][0] == b'RECV    PRG', 'RECV.PRG is in neither INSTALL file'
    m2[a2] = len(files2)
    at2 = a2 + 1 + 15 * len(files2)
    for k, (name, data) in enumerate(files2):
        e = a2 + 1 + 15 * k
        for i, b in enumerate(name): m2[e + i] = b
        m2[e + 11], m2[e + 12], m2[e + 13], m2[e + 14] = len(data) >> 8, len(data) & 0xFF, at2 >> 8, at2 & 0xFF
        for i, b in enumerate(data): m2[at2 + i] = b
        at2 += len(data)
    n2 = at2 - a2
    s2 = sum(m2[a] for a in range(a2, at2)) & 0xFFFF
    for i, v in enumerate((s2 >> 8, s2 & 0xFF, n2 >> 8, n2 & 0xFF)): m2[syms['I2AT'] + i] = v
    open(os.path.join(OUT, 'INSTALL2.HEX'), 'w').write(intel_hex(m2))
    build.install2_files = [n for n, d in files2]
    print('boot sector: code to $%04X (the table starts at $02BE), checksum byte $%02X -> the BIOS check gives $%02X'
          % (bend, ck, btcheck(boot)))
    print('installer:   $3000-$%04X, %d kernel sectors, %d of the %d files (INSTALL2.HEX: %d more); INSTALL.HEX = %d records; '
          'LTOS-SYSTEM.HEX: %d files, %d bytes' % (syms['INSTEND'] - 1, nk, len(files), len(sysall), len(files2),
          intel_hex(mem).count('\n') - 1, len(sysall), syslen))
    build.installed_files = [n for n, d in files]
    return mem, syms, boot


KSECMAX = 21                                                  # $0300-$2CFF; its variables $2D00-$2DFF; programs at $3000


def kernel():
    """monstub.asm (runs at $3000) -> out/monstub.inc; kernel.asm (at $0300, includes it) -> its bytes."""
    stub, ss = assemble('monstub')
    lo, hi = min(stub), max(stub)
    body = bytes(stub.get(a, 0) for a in range(lo, hi + 1))
    assert lo == 0x3000 and hi < 0x31FF, 'MON\'s stub must end before its job list (MACT, $31FF)'
    with open(os.path.join(OUT, 'monstub.inc'), 'w') as f:
        for i in range(0, len(body), 16):
            f.write('        DB      ' + ', '.join('0%02XH' % b for b in body[i:i + 16]) + '\n')
    with open(os.path.join(OUT, 'monstub_syms.inc'), 'w') as f:    # FW.PRG puts its own last line over MSOK's
        f.write('MS_MSOK EQU     0%04XH\nMS_MSOKN EQU    %d\n' % (ss['MSOK'], ss['MSGO'] - ss['MSOK']))
    mem, syms = assemble('kernel')
    end = syms['KEND']
    assert end <= 0x0300 + KSECMAX * 512, 'the kernel runs to $%04X - more than %d sectors' % (end, KSECMAX)
    assert syms['KV1END'] <= 0x2E00 and syms['KVEND'] <= 0x3000, 'the kernel\'s variables run to $%04X, into $2E00-$2EFF (STLCHK compares it)' % max(syms['KV1END'], syms['KVEND'])
    tm, dt = fat_now()                                         # DATEV: files' date when there is no clock
    for i, v in enumerate((tm & 0xFF, tm >> 8, dt & 0xFF, dt >> 8)): mem[syms['DATEV'] + i] = v
    import zlib                                                # KSTAMP: which kernel the system programs
    kb = bytearray(mem.get(a, 0) for a in range(0x0300, end))    #  (VER.PRG ...) were built against - from its
    for x in list(range(syms['DATEV'], syms['DATEV'] + 4)) + [syms['KSTAMP'], syms['KSTAMP'] + 1]:
        kb[x - 0x0300] = 0                                     #  bytes (not the build's date): the same source,
    stamp = (zlib.crc32(bytes(kb)) & 0xFFFF) or 1              #  the same stamp
    mem[syms['KSTAMP']], mem[syms['KSTAMP'] + 1] = stamp >> 8, stamp & 0xFF
    with open(os.path.join(OUT, 'ksyms.inc'), 'w') as f:       # their include: every kernel symbol, KS_name
        f.write('; ksyms.inc - written by build.py: the kernel\'s symbols, for the system programs on the card\n')
        f.write('KS_STAMPV EQU    0%04XH\n' % stamp)
        for n, v in sorted(syms.items()):
            if n.isidentifier(): f.write('KS_%-12s EQU 0%04XH\n' % (n, v & 0xFFFF))
    img = bytes(mem.get(a, 0) for a in range(0x0300, end))
    assert img[3:7] == b'LTOS'
    open(os.path.join(OUT, 'kernel.bin'), 'wb').write(img)
    print('kernel:      $0300-$%04X, %d bytes = %d sectors (MON\'s stub %d bytes)' % (end - 1, len(img), (len(img) + 511) // 512, len(body)))
    return img, syms


def native_prog(name, load=0x3000):
    """A native program (cftest, cfscan): -> out/NAME.HEX (the code only, for the monitor's CALL) and
    out/NAME.PRG (the LTOS program file: its 6-byte header, then the code)."""
    mem, syms = assemble(name)
    if 'FPEND' in syms:                                         # CFSCAN's short-branch loops: one page
        assert syms['FRD'] >> 8 == (syms['FPEND'] - 1) >> 8, 'FRD..FCMP cross a page'
    end = max(a for a in mem if a >= load) + 1
    code = bytes(mem.get(a, 0) for a in range(load, end))
    hdr = bytes(mem[a] for a in range(load - 6, load))
    assert (hdr[0] << 8 | hdr[1]) == load, '%s: the header does not load at $%04X' % (name, load)
    open(os.path.join(OUT, name.upper() + '.PRG'), 'wb').write(hdr + code)
    open(os.path.join(OUT, name.upper() + '.HEX'), 'w').write(intel_hex({load + i: b for i, b in enumerate(code)}))
    print('%-12s $%04X-$%04X, %d bytes; %s.HEX = %d records' % (name, load, end - 1, len(code), name.upper(),
                                                              (len(code) + 15) // 16))
    return mem, syms


def lint_load_d():
    """LOAD (LDI / PHI / LDI / PLO) leaves D = the address's low byte: a LOAD followed by an instruction that uses
    D, before anything sets it, is a bug (it bit LTOS five times). -> the places, as 'file:line'."""
    import re, glob
    use = {'STR', 'STXD', 'PHI', 'PLO', 'XRI', 'ANI', 'ORI', 'ADI', 'SMI', 'SDI', 'ADCI', 'SMBI', 'XOR', 'OR', 'AND',
           'ADD', 'SM', 'SD', 'LBZ', 'LBNZ', 'BZ', 'BNZ', 'SHR', 'SHL', 'SHLC', 'SHRC'}
    bad = []
    for f in sorted(glob.glob(os.path.join(HERE, '*.asm'))):
        lines = open(f).read().splitlines()
        for i, l in enumerate(lines):
            if not re.match(r'^\w*:?\s+LOAD\s', l): continue
            for l2 in lines[i + 1:i + 6]:
                m = re.match(r'^(\w+:)?\s+([A-Z]+)', l2)
                if not m: continue
                if m.group(2) == 'LOAD': continue
                if m.group(1): break                             # a label: other paths come in there
                if m.group(2) in use: bad.append('%s:%d' % (os.path.basename(f), i + 2))
                break
        for i, l in enumerate(lines):                          # a18: HIGH / LOW bind looser than + and -:
            code = l.split(';')[0]                             #  HIGH(X)+1 is HIGH(X+1) - write HIGH(X+100H)
            if "'" not in code and re.search(r'\b(HIGH|LOW)\s*\([^)]*\)\s*[-+]', code):
                bad.append('%s:%d (HIGH/LOW then + or -)' % (os.path.basename(f), i + 1))
    return bad


def prebuild():
    """Build once and keep the results (out/prebuilt.pkl): with LTOS_PREBUILT=1 the verifiers use them and do not
    assemble again - so several can run at once (run_tests.py) without writing out/ under each other."""
    import pickle
    k = kernel(); b = build(k[0]); sm = samples()
    with open(os.path.join(OUT, 'prebuilt.pkl'), 'wb') as f:
        pickle.dump({'kernel': k, 'build': b, 'samples': sm, 'installed_files': build.installed_files,
                     'install2_files': build.install2_files, 'SYSPARTS': list(SYSPARTS)}, f)


if os.environ.get('LTOS_PREBUILT'):
    import pickle as _pk
    _C = _pk.load(open(os.path.join(OUT, 'prebuilt.pkl'), 'rb'))
    SYSPARTS[:] = _C['SYSPARTS']
    def kernel(): return _C['kernel']
    def build(kernel=b''):
        assert kernel == _C['kernel'][0], 'LTOS_PREBUILT: build() with another kernel'
        return _C['build']
    build.installed_files = _C['installed_files']; build.install2_files = _C['install2_files']
    def samples(): return _C['samples']


if __name__ == '__main__':
    bad = lint_load_d()
    assert not bad, 'D used right after a LOAD (it holds the address\'s low byte): ' + ', '.join(bad)
    build(kernel()[0])
    native_prog('cftest')
    native_prog('cfscan')
    native_prog('cfdiag3')
    native_prog('cfdiag4')
