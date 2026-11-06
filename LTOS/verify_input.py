# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""GETSTR, FETCH, POS and FREE's used line in the simulator: a script that reads a line and a key into variables
and files (what is typed shows on the screen, and only the answer goes into the variable or file), Backspace,
Ctrl-C (status 1), POS's codes, and FREE's sums (used = size - free).

    python3 LTOS/verify_input.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import build

SCRIPT = b'''N=$(GETSTR -p "Name? ")
echo "got [$N]"
K=$(FETCH -p "Key? ")
echo "key [$K]"
E=$(FETCH -p "Enter? ")
echo "enter [$E]"
GETSTR -p 'Line? ' OUT.TXT
TYPE OUT.TXT
FETCH -p "One? " K.TXT
TYPE K.TXT
GETSTR -p "Stop? "
echo "status $?"
POS 5 3
echo
'''


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        open(os.path.join(m, 'T.SH'), 'wb').write(SCRIPT)
    img, _ = P2.mac(V.image(cf, 16384), put)
    P1.load_image(cf, img)
    later = [('LTOS> ', b'T\r'), ('Name? ', b'Crai\x08aig x\x08\x08\r'), ('Key? ', b'q'), ('Enter? ', b'\r'),
             ('Line? ', b'hello world\r'), ('One? ', b'Z'), ('Stop? ', b'abc\x03'),
             ('LTOS> ', b'GETSTR -p "Here? "\r'), ('Here? ', b'typed\r'),
             ('LTOS> ', b'FREE\r'), ('LTOS> ', b'POS 0 3\r'), ('LTOS> ', b'POS 2\r'), ('LTOS> ', b'MON\r')]
    b = V.Elf2K(cf, keys=b'', later=later)
    b.boot_rom(cap=1)
    r = None
    while True:
        r = b.run(2_000_000, stop=0x8003)
        if r != 'cap' or b.steps > 600_000_000: break
    t = b.text()
    if '-v' in sys.argv: print(t)
    s = t.replace('\r\n', '\n').replace('\r', '')

    e = []
    for want in ('got [Craaig]\n', 'Key? q\nkey [q]\n', 'Enter? \nenter []\n',
                 'Line? hello world\nhello world\n', 'One? Z\nZ\n', 'status 1\n', '\x1b[3;5H'):
        if want not in s: e.append('missing %r' % want)
    report('GETSTR / FETCH in a script: Backspace, into variables (shown once, on the screen) and files, '
           'Enter, Ctrl-C (status 1); POS 5 3', e)

    e = []
    i = s.find('Here? ')
    if s[i:i + 40].count('typed') != 1: e.append('GETSTR at the prompt: %r' % s[i:i + 40])
    report('GETSTR at the prompt: the line shown once', e)

    e = []
    m = re.search(r'(\d+) KB free of (\d+) KB \((\d+) of (\d+) clusters of (\d+) bytes\)\n(\d+) KB used \((\d+) clusters\)', s)
    if not m: e.append('FREE: %r' % s[s.find('FREE'):s.find('FREE') + 160])
    else:
        fkb, tkb, fc, tc, cb, ukb, uc = map(int, m.groups())
        if uc != tc - fc: e.append('used clusters %d, not %d - %d' % (uc, tc, fc))
        if ukb != uc * cb // 1024: e.append('used KB %d, not %d clusters x %d bytes' % (ukb, uc, cb))
    report('FREE: used = the size less what is free', e)

    e = []
    for c in ('POS 0 3', 'POS 2'):
        o = P2.session_out(t, c + '\r')
        if 'POS x y - the cursor to column x, row y (1 1: the top left)' not in o: e.append('%s: %r' % (c, o))
    report('POS: 0, or y missing: how to use it', e)
    if r != 'stop': report('MON at the end', ['%s: %r' % (r, t[-300:])])
    print('LTOS INPUT: ' + ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
