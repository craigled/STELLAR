# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""APPS.PRG in the simulator: the .STL apps (blocks, KB, VMs, version) and APPS -P (the programs in /BIN: KB and
version); RECV NAME.STL keeps a .lst's "; VERSION:  v02" line (= build.stl_of, byte for byte); bad options.

    python3 LTOS/verify_apps.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build

APPS = os.path.join(HERE, '..', 'APPLICATIONS')
TG = open(os.path.join(APPS, 'CLOCK', 'Time-Grab.lst')).read()
MR = open(os.path.join(APPS, 'Maze', 'MazeRace.lst')).read()
# RECV: '; VERSION:' lines - spaces before the word, only the word kept, the last one wins (a shorter one: its 0
#       ends it), cut at 15 characters; ';VERSION:', '; VERSION ' and a lower-case one are not versions
TGV = '; VERSION:   2.0beta  (2026-11-15) - notes\n' + TG + '\n;VERSION: 9\n; VERSION 8\n; version: 7\n; VERSION: 2.1\n'
LONG = '; VERSION:1234567890ABCDEFGHIJ\n' + MR


def kb(n):
    h = (n + 511) // 512
    return '%4s KB' % ('%d.5' % (h // 2) if h & 1 else '%d' % (h // 2))


def prg_ver(d):
    if len(d) < 11 or d[0:2] == d[4:6] or d[6:10] != b'VER:': return ''
    v = d[10:].split(b'\0')[0][:15]
    return ''.join(chr(c) for c in v[:next((i for i, c in enumerate(v) if not 32 <= c < 127), len(v))])


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
    progs = {'APPS': build.prg('apps'), 'RECV': build.prg('recv'), 'STLRX': build.prg('stlrx'), 'ECHO': build.prg('echo'),
             'NL': build.prg('nl')}
    progs['ODD'] = progs['ECHO'][:6] + b'\0' * 1500                     # 1506 bytes: 3 halves - 1.5 KB
    progs['FAKE'] = b'\x30\x00\x00\x10\x30\x00VER:9.9\0' + b'\0' * 8     # VER: but started at its load address: none
    def put(m):
        os.makedirs(os.path.join(m, 'BIN'), exist_ok=True)
        for k, d in progs.items(): open(os.path.join(m, 'BIN', k + '.PRG'), 'wb').write(d)
        open(os.path.join(m, 'TIMEGRAB.STL'), 'wb').write(build.stl_of(TG))
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)
    c = lambda x: ('LTOS> ', x.encode() + b'\r')
    tgx, lgx = TGV.replace('\n', '\r\n').encode(), LONG.replace('\n', '\r\n').encode()
    b = V.Elf2K(cf, keys=b'', later=[c('RECV TGV.STL'), ('Ctrl-C stops.', tgx), c('RECV LONG.STL'), ('Ctrl-C stops.', lgx),
                                     c('APPS'), c('APPS -P'), c('APPS -p'), c('APPS -X'), c('APPS P'), c('MON')])
    b.rtc = P3.clock()
    s = b.boot_rom(3_000_000_000)
    t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
    if v: print(t[-2500:])
    parts = dict((p.split('\n', 1)[0], p.split('\n', 1)[1] if '\n' in p else '') for p in re.split(r'(?m)^LTOS> ', t))
    got = {}
    P2.mac(V.image(cf, n), lambda m: got.update({f: open(os.path.join(m, f), 'rb').read() for f in os.listdir(m) if f.endswith('.STL')}))

    e = []
    if s != 'stop': e.append('the end: %s %r' % (s, t[-300:]))
    for f, l, ver in (('TGV.STL', TGV, '2.1'), ('LONG.STL', LONG, '1234567890ABCDE')):
        if got.get(f) != build.stl_of(l): e.append('%s is not stl_of (%r)' % (f, (got.get(f) or b'')[120:150]))
        if build.stl_version(build.stl_of(l)) != ver: e.append('%s: stl_of keeps %r' % (f, build.stl_version(build.stl_of(l))))
    if build.stl_of(TGV)[128:140] != b'2.1\0eta\0\0\0\0\0': e.append('the shorter one: %r' % build.stl_of(TGV)[128:140])
    report('RECV NAME.STL keeps the word of a "; VERSION:" line at +128 = stl_of: spaces skipped, the last one wins, 15 '
           'characters at most, near misses ignored', e)

    e = []
    want = ('LONG      8 blocks  4 KB  VM 1 2 3  1234567890ABCDE\n'
            'TGV       4 blocks  2 KB  VM 1  2.1\n'
            'TIMEGRAB  4 blocks  2 KB  VM 1\n')
    ao = parts.get('APPS', '')
    if sorted(ao.splitlines()) != sorted(want.splitlines()): e.append('APPS: %r' % ao)
    report('APPS: blocks, KB, the VMs, the version when there is one', e)

    e = []
    want = sorted('%-8s%s%s' % (k, kb(len(d)), ('  ' + prg_ver(d)) if prg_ver(d) else '') for k, d in progs.items())
    for cmd in ('APPS -P', 'APPS -p'):
        if sorted(parts.get(cmd, '').splitlines()) != want: e.append('%s: %r, want %r' % (cmd, parts.get(cmd), want))
    if not any(w.startswith('APPS ') and w.endswith(' KB  1.1') for w in want):
        e.append('APPS.PRG carries no 1.1: %r' % want)
    if not any(w == 'ODD      1.5 KB' for w in want): e.append('ODD: %r' % want)
    for cmd in ('APPS -X', 'APPS P'):
        if 'Usage: APPS [-P]' not in parts.get(cmd, ''): e.append('%s: %r' % (cmd, parts.get(cmd)))
    rc, _ = P2.fsck_free(V.image(cf, n))
    if rc: e.append('fsck_msdos: %d' % rc)
    report('APPS -P: every /BIN program, its KB (to the half) and its VER: tag; usage for bad options; fsck clean', e)
    e = []                                                              # Stellar C: #version 1.2 -> '; VERSION:  1.2'
    sys.path.insert(0, os.path.join(HERE, '..', 'SC'))
    import scc
    src = 'void main() {\n  print("hi");\n}\n'
    r = scc.compile_text('#version 2.0b   // the second\n' + src)
    if build.stl_version(build.stl_of(r.get('lst', ''))) != '2.0b': e.append('#version 2.0b: %r' % r.get('lst', r)[:300])
    if build.stl_version(build.stl_of(scc.compile_text(src)['lst'])) != '': e.append('no #version: a version anyway')
    for bad in ('#version\n', '#version 1 2\n', '#version 1234567890123456\n'):
        if 'line 1: #version' not in scc.compile_text(bad + src).get('error', ''): e.append('%r: %r' % (bad, scc.compile_text(bad + src)))
    r = scc.compile_text('\n#version 3\nvoid main() {\n  print("a") +;\n}\n')
    if 'line 4' not in r.get('error', ''): e.append('line numbers after #version: %r' % r)
    report('Stellar C: #version 2.0b -> the .lst\'s "; VERSION:" line, as stl_of keeps it; bad ones refused; line numbers kept', e)
    print('\nAPPS: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
