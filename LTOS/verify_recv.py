# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""RECV and damaged Intel HEX: a record that loses a digit (the UART holds one character - one sent too soon is
lost) never reaches its checksum; it must count as bad, and nothing is saved. The same file whole: saved.

    python3 LTOS/verify_recv.py [-v]
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_phase0 as V
import build


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    hexs = open(os.path.join(build.OUT, 'LTOS-SYSTEM.HEX')).read()
    lines = hexs.split('\n')
    lines[0] = lines[0][:9] + lines[0][10:]          # its first data digit lost: the rest shifts half a byte
    bad = '\r\n'.join(lines)
    for how, text, want, nowant in (('one digit lost in the first record', bad, 'bad checksum', 'PRG  saved'),
                                     ('the same file whole', hexs.replace('\n', '\r\n'), 'RECV    PRG  saved', 'bad')):
        cf, e2k, st = P1.installed_full(mem, 16384)
        b, st, t = P3.session(cf, b'RECV SYSTEM\r', rtc=P3.clock(), cap=1_800_000_000,
                              later=[('Ctrl-C stops.', text.encode()), ('LTOS> ', b'DIR SYSTEM\rMON\r')])
        e = []
        if want not in t or nowant in t.split('Ctrl-C stops.')[-1].split('LTOS> ')[0]: e.append(repr(t[-300:]))
        if 'SYSTEM' in P2.session_out(t, 'DIR SYSTEM\r').replace('DIR SYSTEM', ''): e.append('a file SYSTEM was saved')
        if '-v' in sys.argv: print(t[-600:])
        report('RECV SYSTEM, %s' % how, e)
    # RECV NAME.STL hands over to STLRX.PRG - found in /BIN too (Craig's card keeps every program there), and
    # the app is saved in the folder RECV was typed in
    import verify_phase5 as P5
    slst = open(os.path.join(HERE, '..', 'APPLICATIONS', 'Snowflake.lst')).read()
    cf, e2k, st = P1.installed_full(mem, 16384)
    progs = [k for k in (n[:8].decode().strip() + '.' + n[8:].decode().strip() for n, _ in build.samples())
             if k.endswith(('.PRG', '.STL'))]
    def binned(m):
        os.makedirs(os.path.join(m, 'BIN')); os.makedirs(os.path.join(m, 'GAMES'))
        for n in progs: os.rename(os.path.join(m, n), os.path.join(m, 'BIN', n))
    img, _ = P2.mac(V.image(cf, 16384), binned)
    P1.load_image(cf, img)
    b, st, t = P3.session(cf, b'CD GAMES\rRECV SNOWFLAK.STL\r', rtc=P3.clock(), cap=1_800_000_000,
                          later=[('Ctrl-C stops.', slst.replace('\n', '\r\n').encode()), ('LTOS /GAMES> ', b'MON\r')])
    _, fl = P2.mac(V.image(cf, 16384), P5.walk)
    e = [] if fl.get('GAMES/SNOWFLAK.STL') == build.stl_of(slst) else ['%r' % t[-300:]]
    report('RECV SNOWFLAK.STL in /GAMES with every program in /BIN: STLRX.PRG found there, the app saved in /GAMES', e)
    print('RECV: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
