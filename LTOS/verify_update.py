# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS in the simulator: RECV SYSTEM as the first command after U puts a new kernel on the card.

  The card's RECV.PRG was built for the kernel it had. U puts a new kernel there whose internal addresses (the
  KS_ symbols in out/ksyms.inc) have all moved - here, 16 bytes more ahead of them. That old RECV.PRG then runs
  RECV SYSTEM with the new kernel's LTOS-SYSTEM.HEX (and LTOS-SYSTEM2.HEX): every .PRG and .STL must land in
  /BIN, replacing the ones there, none in the root (the root is searched first - a copy there would hide the new
  one in /BIN), and HELP.TXT in the root. (On the Elf2K on 2026-10-19, 16 programs went into the root instead.)

  Both kernels and their programs are built in copies of LTOS in a temporary folder: out/ is not touched.

    python3 LTOS/verify_update.py [-v] [--card-recv FILE]   (FILE: a recvcore.asm for the card's RECV.PRG)
"""
import os, sys, shutil, tempfile, glob
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_phase5 as P5
import build

N = 16384                                           # an 8 MB card


def copy_of_ltos(edit=None):
    """A copy of LTOS's sources in a temporary folder; edit(folder) changes it. -> the folder."""
    d = tempfile.mkdtemp(prefix='ltos-')
    for f in glob.glob(os.path.join(HERE, '*.asm')) + glob.glob(os.path.join(HERE, '*.inc')) + [os.path.join(HERE, 'help.txt')]:
        shutil.copy(f, d)
    shutil.copytree(os.path.join(HERE, 'out'), os.path.join(d, 'out'))
    if edit: edit(d)
    return d


def built(d):
    """build.py's kernel and installer, in the copy d. -> (installer memory, kernel symbols, the files)."""
    build.HERE, build.OUT = d, os.path.join(d, 'out')
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    files = {n[:8].decode().strip() + '.' + n[8:].decode().strip(): data for n, data in build.samples()}
    return mem, ksyms, files


def pad_kernel(d):
    """8 bytes ahead of COLD (never run - $0300 jumps over them): every kernel routine and variable moves.
    (8, not 16: the kernel has only a few bytes to spare.)"""
    p = os.path.join(d, 'kernel.asm'); s = open(p).read()
    s = s.replace('\nCOLD:', '\n        DB      0,0,0,0,0,0,0,0\nCOLD:', 1)
    s = s.replace('ORG     2D00H', 'ORG     2D08H', 1)         # (the variables are at a fixed place: moved too)
    open(p, 'w').write(s)


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    card_recv = sys.argv[sys.argv.index('--card-recv') + 1] if '--card-recv' in sys.argv else None
    old_here, old_out = build.HERE, build.OUT
    try:
        a = copy_of_ltos((lambda d: shutil.copy(card_recv, os.path.join(d, 'recvcore.asm'))) if card_recv else None)
        mem1, ks1, files1 = built(a)                # the kernel the card has, and its programs
        b = copy_of_ltos(pad_kernel)
        mem2, ks2, files2 = built(b)                # the new one U puts there, and its programs

        e = []
        for s in ('WDIR', 'TOBIN', 'FINDN', 'ARGP', 'FNAME', 'RUNIT', 'KSTAMP'):
            if ks1[s] == ks2[s] and s != 'KSTAMP': e.append('KS_%s did not move ($%04X)' % (s, ks1[s]))
        if files1['RECV.PRG'] == files2['RECV.PRG']: e.append('the two RECV.PRGs are the same')
        report('the new kernel: KS_WDIR $%04X -> $%04X, KS_TOBIN $%04X -> $%04X ...; RECV.PRG differs'
               % (ks1['WDIR'], ks2['WDIR'], ks1['TOBIN'], ks2['TOBIN']), e)

        build.HERE, build.OUT = a, os.path.join(a, 'out')
        cf, e2k, st = P1.installed_full(mem1, N)    # F, RECV SYSTEM: the old kernel and every program for it
        progs = sorted(k for k in files1 if k.endswith(('.PRG', '.STL')))
        def binned(m):                              # Craig's card: every program in /BIN, HELP.TXT in the root
            os.makedirs(os.path.join(m, 'BIN')); os.makedirs(os.path.join(m, 'DOCS'))
            for n in progs: os.rename(os.path.join(m, n), os.path.join(m, 'BIN', n))
        img, _ = P2.mac(V.image(cf, N), binned)
        P1.load_image(cf, img)

        e2k = V.Elf2K(cf, keys=b'U')                # U: the new kernel
        for ad, v in mem2.items(): e2k.c.M[ad] = v
        e2k.call(0x3000, cap=300_000_000); t = e2k.text()
        _, fl = P2.mac(V.image(cf, N), P5.walk)
        e = []
        if 'LTOS is updated; the files on the card are as they were.' not in t: e.append('U: %r' % t[-300:])
        if fl.get('BIN/RECV.PRG') != files1['RECV.PRG']: e.append('BIN/RECV.PRG is not the old kernel\'s')
        report('U puts the new kernel on a card whose /BIN has the old kernel\'s programs', e)

        # CD is a program now (2026-10-20): right after U, the card's CD.PRG is the old kernel's - it says so (no
        # hang), and RECV SYSTEM, the next step, is run from the root
        build.HERE, build.OUT = b, os.path.join(b, 'out')
        cf2 = type(cf)(sectors=N); P1.load_image(cf2, V.image(cf, N))
        bx, st, t = P3.session(cf2, b'CD DOCS\rMON\r', rtc=P3.clock(), cap=300_000_000)
        e = [] if ('Not for this kernel' in t and st == 'stop') else ['%s: %r' % (st, t[-300:])]
        report('right after U, the old CD.PRG refuses ("Not for this kernel") and LTOS goes on', e)
        for folder in ('',):                        # RECV SYSTEM, the first command, from the root
            build.HERE, build.OUT = b, os.path.join(b, 'out')
            cf2 = type(cf)(sectors=N); P1.load_image(cf2, V.image(cf, N))
            prompt = 'LTOS /%s> ' % folder if folder else 'LTOS> '
            later = []
            for nm in build.sysparts():
                fp = os.path.join(build.OUT, nm)
                if not os.path.exists(fp): continue
                if later: later.append((prompt, b'RECV SYSTEM\r'))
                later.append(('Ctrl-C stops.', open(fp).read().replace('\n', '\r\n').encode()))
            later.append((prompt, b'MON\r'))
            keys = (b'CD %s\r' % folder.encode() if folder else b'') + b'RECV SYSTEM\r'
            bx, st, t = P3.session(cf2, keys, rtc=P3.clock(), cap=1_800_000_000, later=later)
            _, fl = P2.mac(V.image(cf2, N), P5.walk)
            e = []
            if st != 'stop' or t.count(' saved') < len(files2): e.append('%s: %r' % (st, t[-500:]))
            for n in sorted(k for k in files2 if k.endswith(('.PRG', '.STL'))):
                if fl.get('BIN/' + n) != files2[n]:
                    e.append('BIN/%s: %s' % (n, 'missing' if 'BIN/' + n not in fl else 'not the new one'))
                if n in fl: e.append('%s in the root' % n)
                if 'DOCS/' + n in fl: e.append('%s in /DOCS' % n)
            if fl.get('HELP.TXT') != files2['HELP.TXT']: e.append('HELP.TXT: not the new one in the root')
            if 'BIN/HELP.TXT' in fl: e.append('HELP.TXT in /BIN')
            if '-v' in sys.argv: print(t[-3000:])
            report('RECV SYSTEM from %s with the old RECV.PRG: every program into /BIN, none in the root; '
                   'HELP.TXT into the root' % ('/' + folder if folder else 'the root'), e)
    finally:
        build.HERE, build.OUT = old_here, old_out

    print('LTOS update: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
