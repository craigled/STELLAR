# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""DIR's flags in the simulator: -a -e -s -t (folders first), -r, -w, -p, -h, a bad flag, flags after the path.

    python3 LTOS/verify_dir.py [-v]
"""
import os, re, sys, time, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build


def names(o):
    """The NAME.EXT of every long-format line, in order."""
    res = []
    for ln in o.split('\r\n'):
        m = re.match(r'^(\S{1,8}) +(\S{0,3}) +(<DIR>|\d+)  \d{4}-', ln)
        if m: res.append(m.group(1) + ('.' + m.group(2) if m.group(2) else '') + ('/' if m.group(3) == '<DIR>' else ''))
    return res


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    cf, e2k, st = P1.installed_full(mem, 16384)
    files = {'B.TXT': (300, (2024, 1, 5)), 'A.DAT': (50, (2025, 6, 1)), 'C.BAS': (9000, (2023, 3, 3)),
             'D.TXT': (10, (2026, 2, 2))}
    def put(m):
        os.makedirs(os.path.join(m, 'T', 'SUB'))
        for n, (size, ymd) in files.items():
            p = os.path.join(m, 'T', n)
            open(p, 'wb').write(b'x' * size)
            t = time.mktime(ymd + (12, 0, 0, 0, 0, -1)); os.utime(p, (t, t))
        open(os.path.join(m, 'T', 'H.TXT'), 'wb').write(b'hidden')
        subprocess.run(['chflags', 'hidden', os.path.join(m, 'T', 'H.TXT')], check=True)
        os.makedirs(os.path.join(m, 'M'))
        for i in range(30): open(os.path.join(m, 'M', 'F%02d.TXT' % i), 'wb').write(b'%d' % i)
    img, _ = P2.mac(V.image(cf, 16384), put)
    P1.load_image(cf, img)
    cmds = ['DIR T', 'DIR -a T', 'DIR -e T', 'DIR -s T', 'DIR -t T', 'DIR -a -r T', 'DIR T -ar', 'DIR -W T',
            'DIR -h -a T', 'DIR -x', 'DIR -a -s T', 'DIR -ap M', 'DIR -a T/*.TXT']
    keys = b''.join(c.encode() + b'\r' + (b' ' if c == 'DIR -ap M' else b'') for c in cmds) + b'MON\r'
    b, st, t = P3.session(cf, keys, rtc=P3.clock())
    if '-v' in sys.argv: print(t)
    out = {c: P2.session_out(t, c + '\r') for c in cmds}
    e = []
    srt = ['SUB/', 'A.DAT', 'B.TXT', 'C.BAS', 'D.TXT']
    if sorted(names(out['DIR T'])) != sorted(srt): e.append('DIR T: %r' % names(out['DIR T']))
    if '   4 files, 9360 bytes' not in out['DIR T']: e.append('DIR T totals: %r' % out['DIR T'][-40:])
    for c, want in (('DIR -a T', srt),
                    ('DIR -e T', ['SUB/', 'C.BAS', 'A.DAT', 'B.TXT', 'D.TXT']),
                    ('DIR -s T', ['SUB/', 'C.BAS', 'B.TXT', 'A.DAT', 'D.TXT']),
                    ('DIR -t T', ['SUB/', 'D.TXT', 'A.DAT', 'B.TXT', 'C.BAS']),
                    ('DIR -a -r T', srt[::-1]), ('DIR T -ar', srt[::-1]),
                    ('DIR -h -a T', ['SUB/', 'A.DAT', 'B.TXT', 'C.BAS', 'D.TXT', 'H.TXT']),
                    ('DIR -a -s T', ['SUB/', 'C.BAS', 'B.TXT', 'A.DAT', 'D.TXT']),
                    ('DIR -a T/*.TXT', ['B.TXT', 'D.TXT'])):
        got = [n for n in names(out[c]) if not n.startswith('_')] if '-h' in c else names(out[c])  # (-h: the Mac's ._ files too)
        if got != want: e.append('%s: %r (want %r)' % (c, names(out[c]), want))
    w = out['DIR -W T'].split('\r\n')
    if not any(re.match(r'^\S+ +\S+ +\S+ +\S+ +\S+ *$', ln) and 'SUB/' in ln and 'A.DAT' in ln for ln in w) or \
            '   4 files, 9360 bytes' not in out['DIR -W T']:
        e.append('DIR -W T: %r' % out['DIR -W T'])
    if 'DIR [-a -e -s -t -r -w -p -h] [path]' not in out['DIR -x']: e.append('DIR -x: %r' % out['DIR -x'])
    m = names(out['DIR -ap M'])
    if m != ['F%02d.TXT' % i for i in range(30)] or t.count('-- more: a key goes on') != 1:
        e.append('DIR -ap M: %r, %d pauses' % (m, t.count('-- more: a key goes on')))
    if st != 'stop': e.append('MON: %s' % st)
    report('DIR: card order; -a -e -s -t (folders first); -r and -ar after the path; -W wide; -h hidden; '
           '-x shows the flags; -a -s: the last wins; -ap pauses once in 30; -a with a pattern', e)

    print('DIR flags: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
