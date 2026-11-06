# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS + NANO (a small nano, in 1802 code) in the simulator: a document longer than memory, a part at a time.

  * NANO BIG.TXT (20 KB from the Mac: ATTACH copies it into its run of sectors): ^C, ^B, ^T, ^_ 300, ^V ^Y -
    each place checked by ^C's "Line n col c, bytes a-b of f"; ^X: the file as it was, fsck clean;
  * edits in three parts (AAA at the top, two lines cut and one typed in part 2, ZZZ at the end), ^O, ^X: the
    Mac reads exactly the model's text, fsck clean;
  * typing past a part's room: it is written and a part starts at the cursor's line - nothing lost;
  * ^W across the parts, and a text that is not there;
  * HUGE.TXT (59,000 bytes): an X at part 2's top moves 52 KB up the card;
  * NANO alone: the name asked for; ^X with a change: N leaves it as it was;
  * a long line shown whole (wrapped), Down by screen rows, the mark: Shift + arrows, ^^ / Alt-A, ^K, Alt-6, ^U.

    python3 LTOS/verify_enano.py [-v] [scenario numbers, 1-7]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_phase5 as P5
import build


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    E = build.assemble('enano')[1]
    RLIM = E['TEND'] - E['TS'] - 1536
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    only = [int(a) for a in sys.argv[1:] if a.isdigit()]       # scenario numbers: just those
    def chosen(k): return not only or k in only
    def clean(t): return re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', ' ', t)

    def session(files, steps, mb=16, cap=8_000_000_000):
        """The card with these files in the root; steps: [(text to wait for, keys)], from the LTOS> prompt; then
        MON. -> the end, the screen's text, fsck's code, the files the Mac reads."""
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        def put(m):
            for nm, d in files.items(): open(os.path.join(m, nm), 'wb').write(d)
        img, _ = P2.mac(V.image(cf, n), put)
        P1.load_image(cf, img)
        b = V.Elf2K(cf, keys=b'', later=list(steps) + [('LTOS> ', b'MON\r')]); b.rtc = P3.clock()
        st = b.boot_rom(cap)
        img = V.image(cf, n)
        rc, _ = P2.fsck_free(img)
        _, fl = P2.mac(img, P5.walk)
        if '-v' in sys.argv: print(clean(b.text())[-3000:])
        return st, clean(b.text()), rc, fl

    def where(line, col, a, b, f): return 'Line %d col %d, bytes %d-%d of %d ]' % (line, col, a, b, f)
    def cut1(d, start):
        """A part's end, as NANO cuts it: after the last LF within RLIM bytes (or the end)."""
        if len(d) - start <= RLIM: return len(d)
        return d.rindex(b'\n', start, start + RLIM) + 1
    def last_start(d):
        s = max(0, len(d) - RLIM)
        if s == 0: return 0
        i = d.index(b'\n', s)
        return i + 1 if i + 1 < len(d) else s
    def diff(got, want):
        got = got or b''
        i = next((k for k in range(min(len(got), len(want))) if got[k] != want[k]), min(len(got), len(want)))
        return '%d bytes, want %d; first difference at %d: %r / %r' % (len(got), len(want), i, got[max(0, i - 30):i + 30],
                                                                      want[max(0, i - 30):i + 30])

    lines = [b'Line %04d of the long document.\n' % i for i in range(1, 641)]
    BIG = b''.join(lines)                                   # 640 lines of 32: 20,480
    N = len(BIG)
    ln = lambda d, off: d[:off].count(b'\n') + 1
    c1 = cut1(BIG, 0); c2 = cut1(BIG, c1); ls = last_start(BIG)
    p300 = 299 * 32; s300 = next(s for s in (0, c1, c2, cut1(BIG, c2)) if s <= p300 < cut1(BIG, s))

    if chosen(1):
        # ---- moving around, no edits
        st, t, rc, fl = session({'BIG.TXT': BIG}, [
            ('LTOS> ', b'NANO BIG.TXT\r'), ('NANO 1.1', b'\x03'),
            (where(1, 1, 0, c1, N), b'\x02\x03'),
            (where(641, 1, ls, N, N), b'\x14\x03'),
            (where(1, 1, 0, c1, N), b'\x1f300\r\x03'),
            (where(300, 1, s300, cut1(BIG, s300), N), b'\x1b[B\x1b[B\x1b[C\x03'),
            (where(302, 2, s300, cut1(BIG, s300), N), b'\x18')])
        e = []
        if st != 'stop': e.append('the end: %s %r' % (st, t[-400:]))
        if rc: e.append('fsck %d' % rc)
        if fl.get('BIG.TXT') != BIG: e.append('BIG.TXT changed: ' + diff(fl.get('BIG.TXT'), BIG))
        report('NANO BIG.TXT (20,480 bytes, parts of up to %d): ^C line 1, ^B line 641 (the last part), ^T line 1, '
               '^_ 300, Down Down Right: line 302 col 2 - each with its part\'s bytes; ^X: the file as it was, '
               'fsck clean' % RLIM, e)

    if chosen(2):
        # ---- edits in three parts: AAA at the top; at line 300 two lines cut, BBB typed; ZZZ at the end; ^O
        d = b'AAA' + BIG
        at = d.index(b'Line 0300')
        nl = d.index(b'\n', at) + 1; nl = d.index(b'\n', nl) + 1
        d = d[:at] + b'BBB\n' + d[nl:]
        want = d + b'ZZZ'
        st, t, rc, fl = session({'BIG.TXT': BIG}, [
            ('LTOS> ', b'NANO BIG.TXT\r'), ('NANO 1.1', b'AAA\x03'),
            ('Line 1 col 4,', b'\x1f300\r\x03'),
            ('Line 300 col 1,', b'\x0b\x0bBBB\r\x03'),
            ('Line 301 col 1,', b'\x02ZZZ\x03'),
            ('col 4, bytes', b'\x0f'), ('bytes to BIG.TXT', b'\x18')])
        e = []
        if st != 'stop': e.append('the end: %s %r' % (st, t[-400:]))
        if rc: e.append('fsck %d' % rc)
        if fl.get('BIG.TXT') != want: e.append('BIG.TXT: ' + diff(fl.get('BIG.TXT'), want))
        report('edits in three parts: AAA at the top (part 1 grows: the rest moves up the card), two lines cut and BBB '
               'at line 300 (shrinks: moves down), ZZZ at the end; ^O, ^X: the Mac reads the model\'s %d bytes, fsck '
               'clean' % len(want), e)

    if chosen(3):
        # ---- typing past a part's room: written, a part from the cursor's line - nothing lost
        typed = b''.join(b'%-40s\r' % (b'typed line %02d' % i) for i in range(40))     # 40 x 41: 1,640 > 1,536
        want = typed.replace(b'\r', b'\n') + BIG
        steps = [('LTOS> ', b'NANO BIG.TXT\r'), ('NANO 1.1', b'\x03')]
        prev = where(1, 1, 0, c1, N)
        for i in range(40):
            steps.append((prev, typed[41 * i:41 * i + 41] + b'\x03')); prev = 'Line %d col 1,' % (i + 2)
        steps += [(prev, b'\x0f'), ('bytes to BIG.TXT', b'\x18')]
        st, t, rc, fl = session({'BIG.TXT': BIG}, steps)
        e = []
        if st != 'stop': e.append('the end: %s %r' % (st, t[-400:]))
        if rc: e.append('fsck %d' % rc)
        if fl.get('BIG.TXT') != want: e.append('BIG.TXT: ' + diff(fl.get('BIG.TXT'), want))
        report('40 lines typed at the top of a full part (1,640 bytes, room for 1,536): it is written and a part starts '
               'at the cursor\'s line; ^O: the Mac reads them all, then the document; fsck clean', e)

    if chosen(4):
        # ---- ^W: across the parts; then a text that is nowhere (the cursor goes back)
        st, t, rc, fl = session({'BIG.TXT': BIG}, [
            ('LTOS> ', b'NANO BIG.TXT\r'), ('NANO 1.1', b'\x17line 0500\r\x03'),
            ('Line 500 col 1,', b'\x17nowhere\r'), ('Not found', b'\x03'),
            ('Line 500 col 1,', b'\x17of the\r\x03'), ('Line 500 col 11,', b'\x18')])
        e = []
        if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
        if fl.get('BIG.TXT') != BIG: e.append('BIG.TXT changed')
        report('^W "line 0500" from the top: found in a later part (line 500); ^W "nowhere": Not found, the cursor where '
               'it was; ^W "of the": the next on the same line', e)

    if chosen(5):
        # ---- 59,000 bytes: an X at part 2's top moves the rest up the card; ^B, END, ^O
        HUGE = b''.join(b'%05d the quick brown fox jumps over it\n' % i for i in range(1, 3000))[:59000]
        h1 = cut1(HUGE, 0)
        want = HUGE[:h1] + b'X' + HUGE[h1:] + b'END'
        l2 = ln(HUGE, h1)
        st, t, rc, fl = session({'HUGE.TXT': HUGE}, [
            ('LTOS> ', b'NANO HUGE.TXT\r'), ('NANO 1.1', b'\x1f%d\r\x03' % l2),
            ('Line %d col 1,' % l2, b'X\x02END\x03'), ('col 4, bytes', b'\x0f'), ('bytes to HUGE.TXT', b'\x18')],
            cap=30_000_000_000)
        e = []
        if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
        if fl.get('HUGE.TXT') != want: e.append('HUGE.TXT: ' + diff(fl.get('HUGE.TXT'), want))
        report('HUGE.TXT (59,000 bytes): ^_ to part 2\'s first line, X there (the rest moves up the card), ^B, END, ^O: '
               'the Mac reads the model\'s %d bytes, fsck clean' % len(want), e)

    if chosen(6):
        # ---- NANO alone: the name asked for; CR LF read as LF; ^X N leaves a file as it was
        st, t, rc, fl = session({'CRLF.TXT': b'one\r\ntwo\r\n'}, [
            ('LTOS> ', b'NANO\r'), ('File name: ', b'note.txt\r'), ('NANO 1.1', b'Hello there\x0f'),
            ('bytes to NOTE.TXT', b'\x18'),
            ('LTOS> ', b'NANO CRLF.TXT\r'), ('NANO 1.1', b'\x1b[B\x05!\x03'), ('Line 2 col 5,', b'\x0f'),
            ('bytes to CRLF.TXT', b'\x18'),
            ('LTOS> ', b'NANO NOTE.TXT\r'), ('NANO 1.1', b'more\x18'), ('Save the changes?', b'n')])
        e = []
        if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
        if fl.get('NOTE.TXT') != b'Hello there': e.append('NOTE.TXT %r (files %r)' % (fl.get('NOTE.TXT'), sorted(fl)))
        if fl.get('CRLF.TXT') != b'one\ntwo!\n': e.append('CRLF.TXT %r' % fl.get('CRLF.TXT'))
        report('NANO alone: "File name:" note.txt, "Hello there", ^O: NOTE.TXT; CRLF.TXT (CR LF) Down End "!" ^O: '
               'LF line ends; NANO NOTE.TXT, a change, ^X N: as it was; fsck clean', e)

    if chosen(7):
        # ---- a long line shown whole (wrapped on the screen), Down by screen rows, the mark: cut, paste, copy
        LONGL = b''.join(b'w%03d ' % i for i in range(1, 41))        # 200 characters: rows of 75 (15 words) each
        DOC = b'abcdefghij\n' + LONGL + b'\nend\n'
        want = b'defghijabc\n' + LONGL + b'\nend\nend'
        st, t, rc, fl = session({'LONG.TXT': DOC}, [
            ('LTOS> ', b'NANO LONG.TXT\r'), ('NANO 1.1', b'\x07'), ('Press a key.', b'x\x1b[B\x1b[B\x03'),
            ('Line 2 col 76,', b'\x14\x1e\x1b[1;2C\x1b[1;2C\x1b[1;2C\x0b\x05\x15\x03'),
            ('Line 1 col 11,', b'\x02\x1b[A\x1ba\x1b[C\x1b[C\x1b[C\x1b6\x02\x15\x0f'),
            ('bytes to LONG.TXT', b'\x18')])
        e = []
        if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
        if 'w040' not in t or 'w016' not in t: e.append('the long line not all on the screen')
        if 'every key' not in t or 'Shift+arrow mark and move' not in t: e.append('no key chart at ^G')
        if fl.get('LONG.TXT') != want: e.append('LONG.TXT %r' % fl.get('LONG.TXT'))
        report('^G: the key chart; a 200-character line shown whole (wrapped); Down Down: its second row (col 76); ^^ Shift-Right x3 ^K: '
               '"abc" cut, ^E ^U: pasted at the line\'s end; ^B Up Alt-A Right x3 Alt-6: "end" copied, ^B ^U, ^O: the '
               'Mac reads the model\'s text, fsck clean', e)

    print('\nLTOS + NANO: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
