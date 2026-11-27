# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""CRON on the simulated Elf2K, with a clock that runs (85,000 steps a second, as the Elf2K's):
  * no table: CRON says how to start; CRON START makes /CRON.TAB (CRON y + the column names); CRON lists it;
  * CRON lists the jobs numbered, the one it cannot read marked; CRON OFF n / ON n change job n's own y/n;
    CRON PAUSE / START change only the CRON line (a job turned off by hand stays off); a table with no CRON line
    gets one at the top; CRON RUN refuses a paused table; usage and a job that is not there: $? 1;
  * CRON RUN from 07:29:50 on a Tuesday (2026-11-17): each job at its minute, in the table's order - a weekday
    range, a step (*/2), day-or-weekday, a list with a range; not the jobs that are off or for another day; then
    Esc ends cron mode and LTOS> comes back.

    python3 LTOS/verify_cron.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_xfer as X
import build

SPS = 85000                                   # steps a second (the Elf2K at 3 MHz)
N = 16384


class Clock:
    """A DS12887 in BCD, 24-hour, that runs from a start time with the simulated steps; Esc typed at STOP."""
    def __init__(s, b, start, stop=None):
        s.b, s.start, s.stop, s.sent = b, start, stop, False
    def now(s):
        return s.start + s.b.steps // SPS          # seconds since midnight on 2026-11-17 (a Tuesday)
    def rd(s, r):
        t = s.now()
        d, t = divmod(t, 86400)
        if s.stop is not None and t >= s.stop and not s.sent:
            s.sent = True; s.b.u.q.append(0x1B)
        bcd = lambda v: int('%d' % v, 16)
        regs = {0x0A: 0x20, 0x0B: 0x02, 0x0C: 0, 0x0D: 0x80, 0: bcd(t % 60), 2: bcd(t // 60 % 60),
                4: bcd(t // 3600), 6: bcd((2 + d) % 7 or 7), 7: bcd(17 + d), 8: 0x11, 9: 0x26}
        return regs.get(r, 0)


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + str(x)[:200]) for x in e[:12]]; ok &= not e
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    cf, _, _ = P1.installed_full(mem, N)
    base = V.image(cf, N)

    def run(img, cmds, start=7 * 3600, stop=None, cap=600_000_000):
        """Each command typed at a prompt, then MON. -> (screen text, the image after, the K_STAT after each)."""
        P1.load_image(cf, img)
        later = [('LTOS> ', c.encode() + b'\r') for c in cmds] + [('LTOS> ', b'MON\r')]
        b = V.Elf2K(cf, keys=b'', later=later)
        ck = Clock(b, start, stop); b.rtc = ck.rd
        stats = []
        feed0 = b.u.feed
        def feed():                                   # K_STAT as each next prompt comes
            if len(stats) < len(cmds) and len(b.u.later) == len(cmds) - len(stats) and \
                    bytes(b.u.out).count(b'LTOS> ') >= len(stats) + 2:
                stats.append(b.c.M[0x033F])
            feed0()
        b.u.feed = feed
        st = b.boot_rom(cap)
        t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
        if v: print(t[-3000:])
        return t, V.image(cf, N), stats, st

    def files(img): return X.files(img)
    def after(t, cmd, first=False):
        i = (t.find if first else t.rfind)('LTOS> ' + cmd + '\n')
        return t[i + len(cmd) + 7:].split('LTOS> ')[0] if i >= 0 else '(not run)'

    # ---- no table; START makes one; the listing
    e = []
    t, img, stats, st = run(base, ['CRON', 'CRON START', 'CRON'])
    if 'No /CRON.TAB yet' not in after(t, 'CRON', True): e.append('no table: %r' % t[-600:])
    tab = files(img).get('CRON.TAB', b'')
    if not tab.startswith(b'CRON y\r\n# run min hour day month weekday'): e.append('the new table: %r' % tab)
    if 'Cron: on' not in t.split('LTOS> CRON START')[-1] or '(no jobs yet' not in t.split('LTOS> CRON START')[-1]:
        e.append('listing a new table: %r' % t[-400:])
    report('No table: CRON says how; CRON START makes /CRON.TAB (CRON y, the column names); CRON lists it', e)

    # ---- the jobs: listed, ON/OFF, PAUSE/START keep each job's own y/n, a table with no CRON line
    TAB = (b'CRON y\r\n# run min hour day month weekday command\r\n'
           b'y 30 7 * * 1-5 ECHO weekday >> /LOG.TXT\r\n'
           b'n 30 7 * * * ECHO off >> /LOG.TXT\r\n'
           b'y 31 7 * * 0,6 ECHO weekend >> /LOG.TXT\r\n'
           b'y */2 7 * * * ECHO even >> /LOG.TXT\r\n'
           b'y 31 7 17 * 6 ECHO dayor >> /LOG.TXT\r\n'
           b'\r\n'
           b'Y\t0-5,31 7 * 11 *  ECHO list >> /LOG.TXT\n'
           b'y 61 * * * * ECHO bad >> /LOG.TXT\r\n'
           b'y 1 2 3 4\r\n')
    img0, _ = P2.mac(base, lambda m: open(os.path.join(m, 'CRON.TAB'), 'wb').write(TAB))
    e = []
    t, img, stats, st = run(img0, ['CRON', 'CRON OFF 4', 'CRON PAUSE', 'CRON RUN', 'CRON START', 'CRON ON 2',
                                   'CRON ON 99', 'CRON BOGUS'])
    l = after(t, 'CRON')
    for want in ['Now:  07:00  Tuesday 2026-11-17', ' 1  y 30 7 * * 1-5 ECHO weekday', ' 2  n 30 7', ' 6  Y\t0-5,31',
                 ' 7  y 61 * * * * ECHO bad >> /LOG.TXT   <- not understood', ' 8  y 1 2 3 4   <- not understood', 'Cron: on']:
        if want not in l: e.append('listing lacks %r' % want)
    if 'Job 4 is off: n */2 7' not in after(t, 'CRON OFF 4'): e.append('OFF 4: %r' % after(t, 'CRON OFF 4'))
    if 'Cron is paused' not in after(t, 'CRON PAUSE'): e.append('PAUSE: %r' % after(t, 'CRON PAUSE'))
    if 'Cron is paused: CRON START first.' not in after(t, 'CRON RUN'): e.append('RUN paused: %r' % after(t, 'CRON RUN'))
    if 'Job 2 is on:  y 30 7' not in after(t, 'CRON ON 2'): e.append('ON 2: %r' % after(t, 'CRON ON 2'))
    if 'There is no job 99' not in after(t, 'CRON ON 99'): e.append('ON 99: %r' % after(t, 'CRON ON 99'))
    if 'Usage: CRON' not in after(t, 'CRON BOGUS'): e.append('usage: %r' % after(t, 'CRON BOGUS'))
    tab = files(img).get('CRON.TAB', b'')
    want = TAB.replace(b'y */2', b'n */2').replace(b'n 30 7 * * * ECHO off', b'y 30 7 * * * ECHO off')
    if tab != want: e.append('the table after: %r' % tab)
    if stats[:8] != [0, 0, 0, 1, 0, 0, 1, 1]: e.append('$? after each: %r' % stats)
    img2, _ = P2.mac(base, lambda m: open(os.path.join(m, 'CRON.TAB'), 'wb').write(b'y 0 * * * * ECHO x\r\n'))
    t2, img2, _, _ = run(img2, ['CRON PAUSE'])
    if files(img2).get('CRON.TAB') != b'CRON n\r\ny 0 * * * * ECHO x\r\n': e.append('no CRON line: %r' % files(img2).get('CRON.TAB'))
    report('CRON lists the jobs (the ones it cannot read marked); ON/OFF n; PAUSE/START keep each job\'s y/n; RUN '
           'refuses a paused table; a CRON line made when there is none; $?', e)

    # ---- cron mode: 07:29:50 to 07:33, then Esc
    e = []
    img3, _ = P2.mac(base, lambda m: open(os.path.join(m, 'CRON.TAB'), 'wb').write(TAB))
    t, img, stats, st = run(img3, ['CRON RUN'], start=7 * 3600 + 29 * 60 + 50, stop=7 * 3600 + 33 * 60 + 10,
                            cap=3_000_000_000)
    log = files(img).get('LOG.TXT', b'').decode('latin1').split()
    want = ['weekday', 'even', 'dayor', 'list', 'even']
    if log != want: e.append('LOG.TXT: %r (want %r)' % (log, want))
    if st != 'stop': e.append('the end: %s' % st)
    if 'Cron mode: each job at its time. Esc stops it.' not in t: e.append('no start line')
    if 'Cron mode stopped.' not in t: e.append('no stop line: %r' % t[-500:])
    for w in ['07:30  ECHO weekday >> /LOG.TXT', '07:31  ECHO dayor >> /LOG.TXT', '07:32  ECHO even >> /LOG.TXT']:
        if w not in t: e.append('screen lacks %r' % w)
    if not t.rstrip().endswith('LTOS> MON') and 'LTOS> MON' not in t[-300:]: e.append('no prompt after Esc: %r' % t[-300:])
    report('CRON RUN from 07:29:50 (Tuesday): weekday at 07:30, */2 at 07:30 and 07:32, day-or-weekday and a list at '
           '07:31, in the table\'s order; nothing off or for another day; Esc: back to LTOS>', e)
    print('\nCRON: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
