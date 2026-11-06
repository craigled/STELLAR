# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""HELP.PRG in the simulator: HELP (the list, paged), ?, HELP name (any case, other names), no such command.

    python3 LTOS/verify_help.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    cf, e2k, st = P1.installed_full(mem, 16384)
    cmds = ['HELP', '?', 'HELP dir', 'help DEL', 'HELP PATHS', 'HELP NOSUCH', 'MKDIR X', 'CD X', 'HELP CD']
    pauses = build.help_list().count('\n') // 22            # (a pause after every 22 lines, the last too)
    keys = b''.join(c.encode() + b'\r' + (b' ' * pauses if c in ('HELP', '?') else b'') for c in cmds) + b'MON\r'
    b, st, t = P3.session(cf, keys, rtc=P3.clock())
    if '-v' in sys.argv: print(t)
    def out(c):
        m = re.search(r'LTOS(?: /X)?> ' + re.escape(c) + r'\r\r\n(.*?)LTOS(?: /X)?> ', t, re.S)
        return re.sub(r'-- more: a key goes on, Q stops --.\r {34}\r', '', m.group(1), flags=re.S) if m else None
    e = []
    want = build.help_list().replace('\n', '\r\n')
    for c in ('HELP', '?'):
        if out(c) != want: e.append('%s: %r' % (c, (out(c) or '')[:300]))
    if t.count('-- more: a key goes on') != 2 * pauses: e.append('pauses: %d (want %d in each list)' % (t.count('-- more: a key goes on'), pauses))
    recs = {n: r for r in build.help_records() if r[0] == 'c' for n in r[1]}
    for c, nm in (('HELP dir', 'DIR'), ('help DEL', 'RM'), ('HELP PATHS', 'PATHS'), ('HELP CD', 'CD')):
        r = recs[nm]
        w = ', '.join(r[1]) + ' - ' + r[2] + '\r\n' + ('\r\n' + ''.join(l + '\r\n' for l in r[3]) if r[3] else '')
        if out(c) != w: e.append('%s: %r (want %r)' % (c, (out(c) or '')[:200], w[:200]))
    if out('HELP NOSUCH') != 'There is no help for NOSUCH. HELP alone lists the commands.\r\n':
        e.append('HELP NOSUCH: %r' % out('HELP NOSUCH'))
    if st != 'stop': e.append('MON: %s' % st)
    report('HELP and ? list every command (a pause each screen); HELP dir / help DEL (the other name) / HELP PATHS / '
           'HELP CD from a folder show that page; HELP NOSUCH says so', e)
    print('HELP: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
