# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""CAL.PRG against the Mac's own cal: months and whole years written with > to a file, read back by the Mac and
compared line by line with cal's output (its trailing spaces left off): leap years old and new, 1900 / 2000, the
Julian years, September 1752, years 1 and 9999. CAL alone shows the clock's month; on the screen today is in
reverse video, in a file it is not. Then usage for bad arguments.

    python3 LTOS/verify_cal.py [-v]
"""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

MONTHS = ['11 2026', '2 2024', '2 2023', '2 1900', '2 2000', '2 1700', '2 1600', '9 1752', '10 1752', '8 1752', '1 1', '12 9999',
          '1 1753', '3 0400', '6 1066', '2 2015', '7 1776', '12 2099']
YEARS = ['2026', '1752', '1', '9999', '2000', '1900', '42', '1753', '1600', '2100', '0999']
BAD = ['CAL 0 2026', 'CAL 13 2026', 'CAL 1 0', 'CAL 10000', 'CAL 1 2026 3', 'CAL x', 'CAL 12345', 'CAL 1x 2026', 'CAL -3']


def mac_cal(args):
    out = subprocess.run(['cal'] + [str(int(a)) for a in args.split()], capture_output=True, text=True).stdout
    return '\n'.join(l.rstrip() for l in out.split('\n'))


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed(mem, n)
    img, _ = P2.mac(V.image(cf, n), lambda m: open(os.path.join(m, 'CAL.PRG'), 'wb').write(build.prg('cal')))
    P1.load_image(cf, img)
    c = lambda x: ('LTOS> ', x.encode() + b'\r')
    args = MONTHS + YEARS + ['']
    cmds = ['CAL %s > C%02d.TXT' % (a, k) if a else 'CAL > C%02d.TXT' % k for k, a in enumerate(args)]
    b = V.Elf2K(cf, keys=b'', later=[c(x) for x in cmds] + [c('CAL')] + [c(x) for x in BAD] + [c('MON')])
    b.rtc = P3.clock(26, 10, 16)
    s = b.boot_rom(8_000_000_000)
    raw = b.text().replace('\r', '')
    t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', raw)
    if v: print(t[-2500:])
    got = {}
    def read(m):
        for k in range(len(cmds)):
            p = os.path.join(m, 'C%02d.TXT' % k)
            got[k] = open(p, 'rb').read().decode('latin-1') if os.path.exists(p) else None
    P2.mac(V.image(cf, n), read)
    e = []
    if s != 'stop': e.append('the end: %s %r' % (s, t[-300:]))
    for k, a in enumerate(args):
        want = mac_cal(a if a else '10 2026')
        g = got[k]
        if g is None: e.append('CAL %s: no file' % a); continue
        g = g.replace('\r\n', '\n')
        if g != want:
            gl, wl = g.split('\n'), want.split('\n')
            i = next((j for j in range(min(len(gl), len(wl))) if gl[j] != wl[j]), min(len(gl), len(wl)))
            e.append('CAL %s: line %d: CAL %r, cal %r' % (a, i + 1, gl[i] if i < len(gl) else None, wl[i] if i < len(wl) else None))
    report('CAL against the Mac\'s cal: %d months, %d years (leap years, 1752, years 1 and 9999), CAL alone = '
           'October 2026 from the clock, no highlight in a file' % (len(MONTHS), len(YEARS)), e)

    e = []
    parts = dict((p.split('\n', 1)[0], p.split('\n', 1)[1] if '\n' in p else '') for p in re.split(r'(?m)^LTOS> ', raw))
    scr = parts.get('CAL', '')
    if '\x1b[7m16\x1b[0m' not in scr: e.append('CAL on the screen: today not in reverse video: %r' % scr[:400])
    if re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', scr) != mac_cal('10 2026'): e.append('CAL on the screen: %r' % scr)
    for x in BAD:
        if 'Usage: CAL' not in parts.get(x, ''): e.append('%s: %r' % (x, parts.get(x)))
    rc, _ = P2.fsck_free(V.image(cf, n))
    if rc: e.append('fsck_msdos: %d' % rc)
    report('CAL on the screen: today (the 16th) in reverse video; usage for bad arguments; fsck clean', e)
    print('\nCAL: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
