# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The web BIOS (webbios.asm) against the real Elf2K ROM: the same LTOS sessions, the same screens and cards.

LTOS on the web cannot use Spare Time Gizmos' ROM, so webbios.asm stands in for it: our own code for the BIOS
calls LTOS uses (F_BOOT F_TYPE F_READ F_MSG F_INPUTL F_IDEREAD F_INITCALL) at the ROM's addresses. Each session
below runs twice - once on the real ROM, once on the web BIOS - from the same card, and must give exactly the
same text on the terminal, the same card afterwards, and the same ending:

  * commands and their output: VER, DIR, HELP (its '-- more' answered), TYPE, ECHO > a file, scripts with
    functions / case / $( ) / RAWK, line editing at the prompt (Backspace, Ctrl-C), TIME, DATE
  * a STELLAR app (STELLAR.PRG loads the firmware, the app prints and halts; STELLAR's way back is F_BOOT, which
    loads the kernel again) and the prompt after it
  * MON: the ROM's monitor at $8003 (the web BIOS has none - both stop there)

    python3 LTOS/verify_webbios.py [-v]
"""
import os, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'SC'))
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase3 as P3
import verify_redir as R
import verify_sh4 as SH4
import build

HELLO_SC = b'void main() { print("Hello from a STELLAR app.\\r\\n"); }\n'


def webbios():
    m, s = build.assemble('webbios')
    img = bytearray(b'\xFF' * 0x8000)
    for a, b in m.items(): img[a - 0x8000] = b
    return bytes(img)


class WebElf2K(V.Elf2K):
    """The simulator's Elf2K with the web BIOS where the ROM was."""
    BIOS = None
    def __init__(s, cf, keys=b'', later=()):
        super().__init__(cf, keys=keys, later=later)
        s.c.M[0x8000:0x10000] = WebElf2K.BIOS


def hello_stl():
    import scc
    d = tempfile.mkdtemp()
    p = os.path.join(d, 'hello.sc'); open(p, 'wb').write(HELLO_SC)
    c, em, labels, data = scc.compile_file(p)
    scc.write_lst(p, p.replace('.sc', '.lst'), c, em, labels, data)
    return build.stl_of(open(p.replace('.sc', '.lst')).read())


def run(cls, img, later, stop=0x8003):
    cf = V.CV.CF(sectors=16384); P1.load_image(cf, img)
    b = cls(cf, later=later); b.rtc = P3.clock()
    c = b.c
    c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
    st = b.run(900_000_000, stop=stop)
    return st, b.text(), V.image(cf, 16384)


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    WebElf2K.BIOS = webbios()
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    R.TEXTS.update(SH4.FILES)
    R.TEXTS['T.SH'] = b'echo "Testing the batch feature"\necho 1\necho 2\nexit\n'
    R.TEXTS['HI.STL'] = hello_stl()
    cf = R.card(mem)
    img = V.image(cf, 16384)

    P = 'LTOS> '
    cmds = ['VER', 'DIR', 'DIR -t /', 'TYPE LIST.TXT', 'ECHO hi there > X.TXT', 'TYPE X.TXT', 'T', 'F4 one two',
            'C one two', 'ECHO abcd\b\b\bxyz', 'nonsense\x03', 'TIME', 'DATE', 'HELP SCRIPTS', 'HI', 'VER']
    later = []
    for k in cmds:
        later.append((P, (k + ('' if k.endswith('\x03') else '\r')).encode('latin1')))
        if k == 'HI': P = 'Hello from a STELLAR app.'      # (then the kernel again, and its prompt)
        else: P = 'LTOS> '
    later.insert(3, ('LTOS> ', b'HELP\r')); later.insert(4, ('-- more', b'q'))
    later.append(('LTOS> ', b'MON\r'))
    rom = run(V.Elf2K, img, list(later))
    web = run(WebElf2K, img, list(later))
    e = []
    if rom[0] != 'stop': e.append('the real ROM: %s, %r' % (rom[0], rom[1][-300:]))
    if web[0] != rom[0]: e.append('the web BIOS: %s, %r' % (web[0], web[1][-300:]))
    if web[1] != rom[1]:
        i = next((i for i in range(min(len(web[1]), len(rom[1]))) if web[1][i] != rom[1][i]), min(len(web[1]), len(rom[1])))
        e.append('the screens part at character %d: ROM %r, web %r' % (i, rom[1][max(0, i - 80):i + 80], web[1][max(0, i - 80):i + 80]))
    if web[2] != rom[2]: e.append('the cards differ afterwards')
    for w in ('Testing the batch feature', 'hello world args 1', 'Hello from a STELLAR app.', 'gamma', 'xyz'):
        if w not in rom[1]: e.append('the session never showed %r' % w)
    if '-v' in sys.argv: print(web[1])
    report('%d commands (HELP paged, a script, functions, RAWK, Backspace, Ctrl-C, a STELLAR app and back, '
           'MON): the web BIOS gives the real ROM\'s screen (%d characters) and card' % (len(cmds) + 2, len(rom[1])), e)

    # the web BIOS's own monitor stand-in at $8003: says so, a key boots LTOS again
    cf2 = V.CV.CF(sectors=16384); P1.load_image(cf2, img)
    b = WebElf2K(cf2, later=[('LTOS> ', b'MON\r'), ('start LTOS again', b'x'), ('LTOS> ', b'VER\r')]); b.rtc = P3.clock()
    c = b.c; c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
    b.run(300_000_000)
    t = b.text(); e = []
    if 'ROM monitor is not part of the web version' not in t or t.count('LTOS> ') < 2 or 'Kernel:' not in t.split('start LTOS again')[-1]:
        e.append(repr(t[-400:]))
    report('MON on the web: no monitor, a key boots LTOS again (VER after it)', e)

    print('\nWEB BIOS: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
