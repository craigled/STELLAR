# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS + Lite-Writer 3 in the simulator: a document longer than memory, a part at a time.

  * LTWRITER BIG.TXT (20 KB from the Mac: ATTACH copies it into its run of sectors): ^N ^N ^P ^T ^B - each part's
    first / last line numbered from the document's top on the status bar; ^X: the file as it was;
  * ^F across the parts (found further on; not there: back where it was);
  * long lines (a Mac's paragraphs) shown wrapped, the file written back as it was;
  * edits in three parts (one grows: the rest moves up the card; one shrinks: it moves down), ^W: the Mac
    reads exactly the model's text, fsck clean;
  * typing past a part's room: it is written back and a part starts at the cursor's line - nothing lost;
  * LTWRITER alone: a new document, named at ^W.

    python3 LTOS/verify_lw3.py [-v]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_phase4 as P4
import verify_phase5 as P5
import build
import build_litewriter3 as LW3

LST = os.path.join(HERE, '..', 'APPLICATIONS', 'Lite-Writer-3', 'Lite-Writer-3.lst')


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    lw3 = build.stl_of(open(LST, encoding='latin1').read())
    A = LW3.build()[2]
    RLIM = A['RLIM']
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    def clean(t): return re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', ' ', t)

    raw_text = ['']
    def session(files, cmd, later, mb=16, cap=6_000_000_000):
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        def put(m):
            os.makedirs(os.path.join(m, 'BIN'), exist_ok=True)
            open(os.path.join(m, 'BIN', 'LTWRITER.STL'), 'wb').write(lw3)
            for nm, d in files.items(): open(os.path.join(m, nm), 'wb').write(d)
        img, _ = P2.mac(V.image(cf, n), put)
        P1.load_image(cf, img)
        b = V.Elf2K(cf, keys=cmd, later=later); b.rtc = P3.clock(); c = b.c
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        st = P4.run_to_back(b, cap)
        img = V.image(cf, n)
        rc, _ = P2.fsck_free(img)
        _, fl = P2.mac(img, P5.walk)
        raw_text[0] = b.text()
        return st, clean(b.text()), rc, fl

    lines = [b'Line %04d of the long document.\n' % i for i in range(1, 641)]
    BIG = b''.join(lines)                                   # 640 lines of 32 bytes: 20,480
    assert len(lines[0]) == 32

    def cut1(d, start):
        """A part's end, as Lite-Writer 3 cuts it: after the last LF within RLIM bytes (or the end)."""
        if len(d) - start <= RLIM: return len(d)
        return d.rindex(b'\n', start, start + RLIM) + 1
    def last_start(d):
        """The last part's start: after the first LF from len - RLIM on."""
        s = max(0, len(d) - RLIM)
        if s == 0: return 0
        i = d.index(b'\n', s)
        return i + 1 if i + 1 < len(d) else s

    # ---- moving around, no edits
    c1 = cut1(BIG, 0); c2 = cut1(BIG, c1)
    ln = lambda off: BIG[:off].count(b'\n') + 1               # the line an offset is on
    ls = last_start(BIG)
    st, t, rc, fl = session({'BIG.TXT': BIG}, b'LTWRITER BIG.TXT\r', [
        ('press any key', b' '), ('^W writes it back', b'\x0e'),
        ('Line %d ' % ln(c1), b'\x0e'), ('Line %d ' % ln(c2), b'\x10'),
        ('Line %d ' % ln(c2), b'\x14'), ('Line 1 ', b'\x02'),
        ('Line %d ' % (len(lines) + 1), b'\x18')])
    e = []
    if st != 'stop': e.append('the end: %s %r' % (st, t[-400:]))
    if rc: e.append('fsck %d' % rc)
    if fl.get('BIG.TXT') != BIG: e.append('BIG.TXT changed: %r' % (fl.get('BIG.TXT') or b'')[:80])
    if '-v' in sys.argv: print(t[-3000:])
    report('LTWRITER BIG.TXT (20,480 bytes, parts of up to %d): ^N line %d, ^N line %d, ^P its end (line %d), ^T line 1, '
           '^B the end (line %d); ^X: the file as it was, fsck clean' % (RLIM, ln(c1), ln(c2), ln(c2),
                                                                          len(lines) + 1), e)

    # ---- ^F across the parts: found two parts on; a text that is nowhere: back where it was; the next line
    st, t, rc, fl = session({'BIG.TXT': BIG}, b'LTWRITER BIG.TXT\r', [
        ('press any key', b' '), ('^W writes it back', b'\x06line 0500\r'),
        ('Line 500 ', b'\x06nowhere\r'), ('Not found', b'\x06line 0501\r'), ('Line 501 ', b'\x18')])
    e = []
    if st != 'stop': e.append('the end: %s %r' % (st, t[-400:]))
    if rc: e.append('fsck %d' % rc)
    if fl.get('BIG.TXT') != BIG: e.append('BIG.TXT changed')
    report('^F "line 0500" from the top: found in a later part (line 500); ^F "nowhere": Not found, back in line '
           '500\'s part; ^F "line 0501": the next line; ^X: the file as it was, fsck clean', e)

    # ---- long lines (a Mac's paragraphs): shown wrapped at column 72, the file kept as it was
    PARA = b''.join((b'Paragraph %03d. ' % i) + b'The quick brown fox jumps over the lazy dog and keeps on running. ' * 4
                    + b'\n' for i in range(1, 41))
    def rows(d):
        n = col = sc = 0
        for ch in d:
            if ch == 10: n += 1; col = sc = 0; continue
            if ch == 13: continue
            col += 1
            if ch == 32: sc = col
            if col > LW3.WRAPCOL and sc: n += 1; col -= sc; sc = 0
        return n
    q1 = cut1(PARA, 0)
    want = b'X' + PARA
    st, t, rc, fl = session({'PARA.TXT': PARA}, b'LTWRITER PARA.TXT\r', [
        ('press any key', b' '), ('^W writes it back', b'X\x0e'), ('Line %d ' % (rows(PARA[:q1]) + 1), b'\x17'),
        ('bytes to PARA.TXT', b'\x18')])
    e = []
    if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
    if fl.get('PARA.TXT') != want: e.append('PARA.TXT: %d bytes, want %d' % (len(fl.get('PARA.TXT') or b''), len(want)))
    sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
    import litewriter2_verify as LW
    vt = LW.VT100(); vt.feed(raw_text[0].split('LTWRITER PARA.TXT')[-1])
    if any('80' in x for x in vt.bad): e.append('a row written past column 80')
    report('PARA.TXT (40 paragraphs of 285 characters on one line each): shown wrapped at column 72, nothing past '
           'column 80; X at the top, ^N (line %d: the rows wrapped before it counted), ^W: the Mac reads the '
           'paragraphs exactly as they were, with the X' % (rows(PARA[:q1]) + 1), e)

    # ---- edits in three parts: part 1 grows (AAA), part 2 shrinks (two lines cut, one typed), the last gets ZZZ
    d = b'AAA' + BIG                                          # the model
    p2 = c1 + 3                                               # part 2 starts where part 1 ended (it grew by 3)
    nl = d.index(b'\n', p2) + 1; nl = d.index(b'\n', nl) + 1
    d = d[:p2] + b'BBB\n' + d[nl:]
    want = d + b'ZZZ'
    st, t, rc, fl = session({'BIG.TXT': BIG}, b'LTWRITER BIG.TXT\r', [
        ('press any key', b' '), ('^W writes it back', b'AAA\x0e'),
        ('Line %d ' % ln(c1), b'\x0b\x0bBBB\r\x02'),
        ('Line %d ' % (want.count(b'\n') + 1), b'ZZZ\x17'), ('bytes to BIG.TXT', b'\x18')])
    e = []
    if st != 'stop': e.append('the end: %s %r' % (st, t[-400:]))
    if rc: e.append('fsck %d' % rc)
    got = fl.get('BIG.TXT')
    if got != want:
        i = next((k for k in range(min(len(got or b''), len(want))) if got[k] != want[k]), None)
        e.append('BIG.TXT: %d bytes, want %d; first difference at %s: %r / %r'
                 % (len(got or b''), len(want), i, (got or b'')[i - 20:i + 40] if i else got[-60:],
                    want[i - 20:i + 40] if i else want[-60:]))
    if '-v' in sys.argv: print(t[-3000:])
    report('edits in three parts: part 1 grows (the rest moves up the card), part 2 shrinks (moves down), the last '
           'gets ZZZ at its end; ^W, ^X: the Mac reads the model\'s %d bytes, fsck clean' % len(want), e)

    # ---- typing past a part's room: written back, a part from the cursor's line - nothing lost
    typed = b''.join(b'%-40s\r' % (b'typed line %02d' % i) for i in range(28))     # 28 x 41: 1,148 > the room
    # (a line at a time, as typed: the status bar's next line number before the next - a key queue of 128)
    want = typed.replace(b'\r', b'\n') + BIG
    st, t, rc, fl = session({'BIG.TXT': BIG}, b'LTWRITER BIG.TXT\r', [
        ('press any key', b' ')] + [(('^W writes it back', 'Line %d ' % (i + 1))[i > 0], typed[41 * i:41 * i + 41])
                                    for i in range(28)] + [('Line 29 ', b'\x17'), ('bytes to BIG.TXT', b'\x18')])
    e = []
    if st != 'stop': e.append('the end: %s %r' % (st, t[-400:]))
    if rc: e.append('fsck %d' % rc)
    got = fl.get('BIG.TXT')
    if got != want:
        i = next((k for k in range(min(len(got or b''), len(want))) if got[k] != want[k]), None)
        e.append('BIG.TXT: %d bytes, want %d; first difference at %s: %r / %r'
                 % (len(got or b''), len(want), i, (got or b'')[max(0, (i or 0) - 300):(i or 0) + 100],
                    want[max(0, (i or 0) - 20):(i or 0) + 40]))
    if 'Line 29 ' not in t: e.append('the status bar never said Line 29 (after 28 typed lines)')
    if '-v' in sys.argv: print(t[-3000:])
    report('28 lines typed at the top of a full part (1,148 bytes, room for %d): it is written back and a part '
           'starts at the cursor\'s line; ^W: the Mac reads them all, then the document; fsck clean'
           % (A['CAP'] - c1), e)

    # ---- 59,000 bytes: an edit at part 2's top moves 56 KB up the card; ^B, END at the end
    HUGE = b''.join(b'%05d the quick brown fox jumps over it\n' % i for i in range(1, 3000))[:59000]
    h1 = cut1(HUGE, 0)
    want = HUGE[:h1] + b'X' + HUGE[h1:] + b'END'
    st, t, rc, fl = session({'HUGE.TXT': HUGE}, b'LTWRITER HUGE.TXT\r', [
        ('press any key', b' '), ('^W writes it back', b'\x0e'), ('Line %d ' % (HUGE[:h1].count(b'\n') + 1), b'X\x02'),
        ('Line %d ' % (want.count(b'\n') + 1), b'END\x17'), ('bytes to HUGE.TXT', b'\x18')], cap=30_000_000_000)
    e = []
    if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
    got = fl.get('HUGE.TXT')
    if got != want: e.append('HUGE.TXT: %d bytes, want %d' % (len(got or b''), len(want)))
    report('LTWRITER HUGE.TXT (59,000 bytes): ^N, X at part 2\'s top (56 KB move up the card), ^B, END, ^W: the Mac reads '
           'the model\'s %d bytes, fsck clean' % len(want), e)

    # ---- LTWRITER alone: a new document, named at ^W
    st, t, rc, fl = session({}, b'LTWRITER\r', [
        ('press any key', b' '), ('^W asks for a name', b'Hello there\x17'), ('Save as', b'note\r'),
        ('bytes to NOTE.TXT', b'\x18')])
    e = []
    if st != 'stop' or rc: e.append('the end %s, fsck %d: %r' % (st, rc, t[-300:]))
    if fl.get('NOTE.TXT') != b'Hello there': e.append('NOTE.TXT %r (files %r)' % (fl.get('NOTE.TXT'), sorted(fl)))
    report('LTWRITER alone: "Hello there", ^W, Save as note: NOTE.TXT; fsck clean', e)

    print('\nLTOS + Lite-Writer 3: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
