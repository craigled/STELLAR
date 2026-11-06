# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The LTOS> command line, edited (GETLN): arrows, Home / End, Backspace and Delete in the middle, the up arrow
(the last line again), Ctrl-C, a key sequence it does not know (Ctrl + arrow). Each line is checked twice: what
LTOS ran, and what the screen shows (a small terminal: characters, Backspace, ESC [ K).

    python3 LTOS/verify_edit.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase1 as P1
import verify_phase3 as P3
import build

L, R, HOME, END, UP, DEL = b'\x1b[D', b'\x1b[C', b'\x1b[H', b'\x1b[F', b'\x1b[A', b'\x1b[3~'


def screen_line(echo):
    """What a terminal shows for the echo of one line: characters overwrite, BS goes left, ESC [ K erases."""
    line, x, i = [], 0, 0
    while i < len(echo):
        ch = echo[i]
        if ch == '\x1b':
            m = re.match(r'\x1b\[([0-9;]*)([A-Za-z])', echo[i:])
            if m.group(2) == 'K': del line[x:]
            i += m.end(); continue
        if ch == '\x08': x = max(0, x - 1)
        else:
            if x < len(line): line[x] = ch
            else: line.append(ch)
            x += 1
        i += 1
    return ''.join(line).rstrip()


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e

    cases = [(b'ABD' + L + b'C', 'ABCD', 'left, then typing in the middle'),
             (b'BC' + HOME + b'A' + END + b'D', 'ABCD', 'Home and End (ESC [ H / F)'),
             (b'BC\x1b[1~A\x1b[4~D', 'ABCD', 'Home and End (ESC [ 1 ~ / 4 ~)'),
             (b'AXBCD' + HOME + R + DEL, 'ABCD', 'right, then Delete'),
             (b'ABXCD' + L + L + b'\x08', 'ABCD', 'Backspace in the middle'),
             (b'ABCDE\x7f', 'ABCD', 'DEL (7F) is Backspace too'),
             (b'AB\x1b[1;5CCD', 'ABCD', 'Ctrl + right (ESC [ 1 ; 5 C): ignored'),
             (b'ZZZZZZ' + UP, 'ABCD', 'the up arrow: the last line instead'),
             (L + L + b'Q' + HOME + DEL, '', 'arrows on an empty line do nothing; Q, Home, Delete: empty again')]
    cf, e2k, st = P1.installed_full(mem, 16384)
    keys = b''.join(k + b'\r' for k, _, _ in cases) + b'xyz\x03' + UP + b'\rMON\r'
    b, st, t = P3.session(cf, keys, rtc=P3.clock())
    if '-v' in sys.argv: print(repr(t))
    # each line: from the prompt "LTOS> " to its CR LF; then what LTOS answered
    parts = re.findall(r'LTOS> (.*?)\r\n(.*?)(?=LTOS> )', t, re.S)
    e = []
    for (k, want, label), (echo, ans) in zip(cases, parts):
        shown = screen_line(echo.rstrip('\r'))     # (Enter is echoed, as the BIOS did)
        if shown != want: e.append('%s: the screen shows %r (want %r)' % (label, shown, want))
        if (want and 'Unknown command: %s ' % want not in ans) or (not want and ans.strip()): e.append('%s: LTOS ran %r' % (label, ans.strip()))
        if '\x1b' in echo: e.append('%s: an ESC sent (the BIOS\'s F_TYPE drops it on the Elf2K): %r' % (label, echo))
    rest = parts[len(cases):]
    if len(rest) < 2 or not rest[0][0].endswith('^C'): e.append('Ctrl-C: %r' % (rest[:1],))
    elif 'Unknown command: ABCD ' not in rest[1][1]: e.append('the up arrow after Ctrl-C: %r' % (rest[1],))
    if st != 'stop': e.append('MON: %s' % st)
    report('the command line: ' + '; '.join(l for _, _, l in cases) + '; Ctrl-C; the up arrow after it', e)
    # a line pasted at full speed (19200 baud: a character every ~58 instructions; the UART holds ONE)
    cf, e2k, st = P1.installed_full(mem, 16384)
    paste = b'THE-QUICK-BROWN-FOX-JUMPS-OVER-THE-LAZY-DOG'
    b, st, t = P3.session(cf, b'', rtc=P3.clock(), later=[('LTOS> ', paste + b'\r', 'timed'), ('LTOS> ', b'MON\r')]) \
        if 'later' in P3.session.__code__.co_varnames else (None, None, None)
    if b is None:
        import verify_phase0 as V
        b = V.Elf2K(cf, keys=b'', later=[('LTOS> ', paste + b'\r', 'timed'), ('LTOS> ', b'MON\r')]); b.rtc = P3.clock(); c = b.c
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        st = b.run(400_000_000, stop=0x8003); t = b.text()
    e = [] if 'Unknown command: %s ' % paste.decode() in t and b.u.lost == 0 else \
        ['lost %d; %r' % (b.u.lost, t[-200:])]
    report('a line pasted at full speed (19200 baud) arrives whole', e)
    print('Line editing: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
