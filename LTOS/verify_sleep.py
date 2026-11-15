# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""SLEEP.PRG in the simulator, with a DS12887 whose periodic flag ticks (register C bit 6, every PER instructions
once register A's rate bits say 64 Hz): each SLEEP must wait exactly seconds x 64 flags (the decimals to the
nearest 1/64), and put register A back. Esc and Ctrl-C stop it early (exit status 1 in K_STAT); a clock whose
flag never comes, and no clock at all, are reported; usage for bad numbers.

    python3 LTOS/verify_sleep.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import build

PER = 1500
CASES = [('2', 128), ('0.5', 32), ('1.01', 65), ('0', 0), ('0.99', 63), ('3.5', 224), ('00001.25', 80), ('1.', 64), ('.5', 32)]
BAD = ['SLEEP', 'SLEEP x', 'SLEEP 1.234', 'SLEEP 70000', 'SLEEP -1', 'SLEEP 1 2', 'SLEEP 1.x', 'SLEEP 123456']


class Clock:
    """A DS12887: A, B, C - the periodic flag every PER instructions while RS = 1010 (64 Hz)."""
    def __init__(s, b, flag=True, present=True):
        s.b, s.flag, s.present = b, flag, present
        s.A, s.last, s.n, s.writes, s.stop_at, s.stop_key = 0x20, 0, 0, [], None, None
    def rd(s, r):
        if not s.present: return 0xFF
        if r == 0x0A: return s.A
        if r == 0x0B: return 0x02
        if r == 0x0C:
            if s.flag and s.A & 0x0F == 0x0A and s.b.steps - s.last >= PER:
                s.last = s.b.steps; s.n += 1
                if s.stop_at is not None and s.n == s.stop_at: s.b.u.q.append(s.stop_key)
                return 0xC0
            return 0
        return 0
    def wr(s, r, v):
        if r == 0x0A:
            s.writes.append(v)
            if s.A & 0x0F != 0x0A and v & 0x0F == 0x0A: s.last = s.b.steps
            s.A = v


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
    img, _ = P2.mac(V.image(cf, n), lambda m: [open(os.path.join(m, k + '.PRG'), 'wb').write(build.prg(k.lower())) for k in ('SLEEP',)])
    P1.load_image(cf, img)
    base = V.image(cf, n)

    def session(cmds, stop=None, **kw):
        """Each command alone on a fresh boot: (screen text, flags taken, A's writes, K_STAT)."""
        out = []
        for cmd in cmds:
            P1.load_image(cf, base)
            b = V.Elf2K(cf, keys=b'', later=[('LTOS> ', cmd.encode() + b'\r'), ('LTOS> ', b'MON\r')])
            st = {}
            feed0 = b.u.feed
            def feed():                                 # K_STAT just as MON is typed (MON's STELLAR covers it)
                if len(b.u.later) == 1 and 'k' not in st and bytes(b.u.out).find(b'LTOS> ', b.u.seen) >= 0:
                    st['k'] = b.c.M[0x033F]
                feed0()
            b.u.feed = feed
            ck = Clock(b, **kw)
            if stop: ck.stop_at, ck.stop_key = stop
            b.rtc = ck.rd; b.rtcw = ck.wr
            s = b.boot_rom(400_000_000)
            t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
            parts = dict((p.split('\n', 1)[0], p.split('\n', 1)[1] if '\n' in p else '') for p in re.split(r'(?m)^LTOS> ', t))
            rc = str(st.get('k'))
            if v: print(cmd, s, ck.n, ck.writes, repr(parts.get(cmd)), rc)
            out.append((s, parts.get(cmd, ''), ck.n, ck.writes, rc))
        return out

    e = []
    for (arg, want), (s, scr, got, w, rc) in zip(CASES, session(['SLEEP ' + a for a, _ in CASES])):
        if s != 'stop' or scr or got != want or w[-1:] != [0x20] or (w and w[0] != 0x2A) or rc != '0':
            e.append('SLEEP %s: %d flags (want %d), A written %s, %r, $? %r, %s' % (arg, got, want, w, scr, rc, s))
    report('SLEEP n: exactly n x 64 periodic flags (the decimals to the nearest 1/64), register A at 64 Hz and put back '
           'as it was; nothing printed; $? 0', e)

    e = []
    for key, name in ((0x1B, 'Esc'), (0x03, 'Ctrl-C')):
        (s, scr, got, w, rc), = session(['SLEEP 100'], stop=(10, key))
        if got != 10 or w[-1:] != [0x20] or rc != '1' or scr: e.append('%s: %d flags, A %s, %r, $? %r' % (name, got, w, scr, rc))
    (s, scr, got, w, rc), = session(['SLEEP 5'], flag=False)
    if 'periodic flag does not come' not in scr or w[-1:] != [0x20] or rc != '1': e.append('no flag: %r %s $? %r' % (scr, w, rc))
    (s, scr, got, w, rc), = session(['SLEEP 5'], present=False)
    if 'SLEEP needs the clock' not in scr or w or rc != '1': e.append('no clock: %r %s $? %r' % (scr, w, rc))
    for (s, scr, got, w, rc), cmd in zip(session(BAD), BAD):
        if 'Usage: SLEEP' not in scr or w or rc != '1': e.append('%s: %r %s $? %r' % (cmd, scr, w, rc))
    report('Esc / Ctrl-C stop it at once ($? 1, A put back); a flag that never comes and no clock reported; usage for '
           'bad numbers', e)
    print('\nSLEEP: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
