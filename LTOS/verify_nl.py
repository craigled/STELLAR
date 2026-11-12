# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""NL.PRG against the Mac's own nl: each set of options run on the card with > to a file, the file read back by the
Mac and compared byte for byte with nl's output for the same text (CR LF and LF lines, an empty line, a line of
spaces, a file over a sector, no LF at the end, an empty file, numbers past 9999 and 65535's edge). Then the
usage for no name and for bad options, and a file that is not there.

    python3 LTOS/verify_nl.py [-v]
"""
import os, re, shlex, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

T = (b'alpha\r\n\r\n  \r\nbeta\ngamma\r\n' + b''.join(b'line %03d of a file longer than one sector\r\n' % i for i in range(1, 31))
     + b'\r\n\r\nthe last line, with no LF')
TWO = b'\n\n'
CASES = ['', '-b a', '-b n', '-bt', '-n ln', '-n rz', '-nrn', '-w 3', '-w4', '-w 1 -v 98', '-s :', "-s ' -> '",
         '-s ". "', '-v 5 -i 10', '-ba -nrz -w4', '-b a -n ln -w 2 -s |', '-v 9995 -i 2 -b a', '-v 65530 -i 1 -n rz -w 7',
         '-B A -N RZ', '-w 40']
FILES = [('T.TXT', T)] * len(CASES) + [('EMPTY.TXT', b''), ('TWO.TXT', TWO), ('TWO.TXT', TWO)]
OPTS = CASES + ['', '', '-b a']


def mac_nl(opts, data):
    p = subprocess.run(['nl'] + shlex.split(opts.lower() if opts.startswith('-B') else opts), input=data.replace(b'\r', b''),
                       capture_output=True)
    out = p.stdout
    return out if out.endswith(b'\n') or not out else out + b'\n'        # NL ends its last line, as LTOS's tools do


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed_full(mem, n)
    def put(m):
        for name, data in set(FILES): open(os.path.join(m, name), 'wb').write(data)
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)
    c = lambda x: ('LTOS> ', x.encode() + b'\r')
    cmds = ['NL %s %s > O%02d.TXT' % (o, f, k) for k, (o, (f, _)) in enumerate(zip(OPTS, FILES))]
    b = V.Elf2K(cf, keys=b'', later=[c(x) for x in cmds] + [c('NL'), c('NL -b x T.TXT'), c('NL -w 0 T.TXT'), c('NL -q T.TXT'),
                                                           c('NL NOPE.TXT'), c('NL -s'), c('NL -b a TWO.TXT'), c('MON')])
    b.rtc = P3.clock()
    s = b.boot_rom(6_000_000_000)
    t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
    if v: print(t[-1500:])
    got = {}
    def read(m):
        for k in range(len(cmds)):
            p = os.path.join(m, 'O%02d.TXT' % k)
            got[k] = open(p, 'rb').read() if os.path.exists(p) else None
    P2.mac(V.image(cf, n), read)
    e = []
    if s != 'stop': e.append('the end: %s %r' % (s, t[-300:]))
    for k, (o, (f, data)) in enumerate(zip(OPTS, FILES)):
        want = mac_nl(o, data)
        if got[k] != want:
            g = got[k] or b''
            i = next((j for j in range(min(len(g), len(want))) if g[j] != want[j]), min(len(g), len(want)))
            e.append('NL %s %s: differs at byte %d: NL %r, nl %r' % (o, f, i, g[max(0, i - 20):i + 30], want[max(0, i - 20):i + 30]))
    report('NL against the Mac\'s nl: %d option sets, CR LF and LF, empty and space lines, past a sector, no last LF, '
           'an empty file, numbers past 9999 and to 65535' % len(cmds), e)

    e = []
    parts = dict((p.split('\n', 1)[0], p.split('\n', 1)[1] if '\n' in p else '') for p in re.split(r'(?m)^LTOS> ', t))
    for cmd in ('NL', 'NL -b x T.TXT', 'NL -w 0 T.TXT', 'NL -q T.TXT', 'NL -s'):
        if 'NL [-b a|t|n]' not in parts.get(cmd, ''): e.append('%s: %r' % (cmd, parts.get(cmd)))
    if 'NOPE' not in parts.get('NL NOPE.TXT', '') and 'not' not in parts.get('NL NOPE.TXT', '').lower():
        e.append('NL NOPE.TXT: %r' % parts.get('NL NOPE.TXT'))
    scr = parts.get('NL -b a TWO.TXT', '')
    if scr != '     1\t\n     2\t\n': e.append('on the screen: %r' % scr)
    rc, _ = P2.fsck_free(V.image(cf, n))
    if rc: e.append('fsck_msdos: %d' % rc)
    report('usage for no name and bad options, a file not there, the screen, fsck clean', e)
    print('\nNL: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
