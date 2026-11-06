# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""EROFF.PRG in the simulator, against eroff_model.py: each document formatted with EROFF X.RF > X.OUT on the card,
the .OUT read back and compared byte for byte with the model (LF line ends, as LTOS's > writes them).

    python3 LTOS/verify_eroff.py [-v] [N]     # N random documents as well (default 6)
"""
import os, re, sys, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import build
import eroff_model as R

EDGE = '''.\\" the edges
.ll 30
.pl 12
.he '%'Edge'%'
.fo 'left only
A very long word: supercalifragilisticexpialidociousandmoreandmoreandmore ends it.
Two  spaces   and three, kept.
.ce 3
   centred, spaces taken off
a line much too long to centre within thirty columns at all
.
.XX an unknown request
.ti +3
temp indent plus three, then the rest of this paragraph back at the left margin again.
.in +4
.ti -2
hanging by two
.in -100
.ll +200
wide now: the line length is kept to 132 columns at most, so this line can run on and on and on and on and on
and on and on until it wraps somewhere near the far right edge of a wide printer page.
.ll 20
.nf
no fill    kept
	a tab
.fi
.sp 0
.sp 3
.ne 50
needs a new page first.
.bp
.bp
.pl 0
no pages from here on.
.sp 2
.he 'never shown
the end'''


FONTS = r'''.ll 40
.pl 0
This has \fBbold words\fR and \fIitalic\fP ones, \fBbold\fP. A \fBlong
bold run that crosses the end of the line\fR and goes on, justified on what shows.
Spaces \fB around \fR codes, \fBnested \fIitalic\fP back to bold\fP and roman.
.B "Bold line"
back to roman.
.I
italic from here
.R
roman. A lone \fX is kept, and \f at the end \
.B
.ce
centred bold
.R
.nf
\fBno fill\fR    kept
.fi
.I a line of italic words long enough to wrap onto the next line, then back
done.
\&.this line starts with a dot; \&a\&b is ab.
.B "quoted words" and the rest left off
.I "unclosed
.B ""
end.
'''


MS = r'''.pl 30
.ll 50
.nh Introduction
.pp
Some text for the first paragraph, long enough to wrap a little here.
.ip * 3
A bulleted item with a star hanging in the margin, wrapping onto a second line.
.ip "(a)" 6
A tagged item.
.ip longtagword 4
Tag too long for the room.
.lp
Back to the left margin, no indent on this first line of the paragraph.
.nh 2 Details
.sh Unnumbered
.nh More
.tl 'left'%'right'
.sp 1i
.ds
display line one
   display line two
.de
.ds C
Centred display
.de
after .sp .5c and .sp 24p:
.sp .5c
.sp 24p
end.
.ip "" 8
no tag, indented 8.
.ip ** 2
star star: too long for 2.
.nh 9 deep level clamps to 5
.nh 3 three
.nh 1 back to one
.sh
.ds L
left display
.ds
nested display: the first flushed
.sp 2
.de
.de
.sp 2.5i
.sp 3c
.sp 7.75v
.sp 120p
.sp 999.9i
.sp .
.sp x
.sp 1.5
.tl
.tl '%'
'''


def rand_doc(rng):
    words = ('the quick brown fox jumps over a lazy dog ELF2K STELLAR 1802 cosmac, roff; page! '
             'formatting justified indented centred x yy zzz \\fBbold \\fIital\\fP \\fR \\fB \\fP').split()
    reqs = ['.br', '.sp', '.sp 2', '.bp', '.ne 5', '.fi', '.nf', '.ad', '.na', '.ce', '.ce 2', '.in 4', '.in +3',
            '.in -2', '.ti 6', '.ti -1', '.ll 40', '.ll +5', '.ll -7', '.pl 15', '.pl 20', '.pl 0', '.pp',
            '.B', '.I', '.R', '.B a bold bit', '.I an italic bit', '.R roman',
            '.lp', '.ip', '.ip *', '.ip (1) 6', '.ip "two words" 3', '.sh A heading', '.nh Numbered', '.nh 2 Sub',
            ".tl 'a'b'c'", '.ds', '.ds L', '.ds C', '.de', '.sp 1i', '.sp .5c', '.sp 6p', '.sp 2v',
            ".he 'L'%'R'", ".fo ''- % -''", '.\\" note', '']
    out = []
    for _ in range(rng.randint(30, 90)):
        if rng.random() < 0.3:
            out.append(rng.choice(reqs))
        else:
            lead = ' ' * rng.choice([0, 0, 0, 0, 2, 5])
            out.append(lead + '  '.join(' '.join(rng.choice(words) for _ in range(rng.randint(1, 8)))
                                         for _ in range(rng.randint(1, 2))))
    return '\n'.join(out) + '\n'


def main():
    ok = True
    n = int(sys.argv[-1]) if sys.argv[-1].isdigit() else 6
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    rng = random.Random(1802)
    longds = '.pl 20\n.ds\n' + ''.join('display line %d\n' % i for i in range(70)) + '.de\nafter.\n'
    docs = {'TOUR': open(os.path.join(HERE, 'examples', 'EROFF.RF')).read(), 'EDGE': EDGE, 'FONTS': FONTS, 'MS': MS,
            'LONGDS': longds,
            'EMPTY': '', 'NOLF': 'no line end at the end'}
    for i in range(n): docs['R%d' % i] = rand_doc(rng)
    docs['CRLF'] = docs['TOUR'].replace('\n', '\r\n')
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):
        for k, d in docs.items(): open(os.path.join(m, k + '.RF'), 'wb').write(d.encode('latin1'))
    img, _ = P2.mac(V.image(cf, 16384), put)
    P1.load_image(cf, img)
    cmds = ''.join('EROFF %s.RF > %s.OUT\r' % (k, k) for k in docs)
    b, st, t = P3.session(cf, cmds.encode() + b'MON\r', rtc=P3.clock(), cap=4_000_000_000)
    if '-v' in sys.argv: print(t[-3000:])
    _, got = P2.mac(V.image(cf, 16384), lambda m: {f[:-4]: open(os.path.join(m, f), 'rb').read()
                                                   for f in os.listdir(m) if f.endswith('.OUT')})
    for k, d in docs.items():
        want = R.eroff(d.replace('\r', '')).encode('latin1')
        g = got.get(k)
        e = []
        if g != want:
            if g is None: e.append('no %s.OUT' % k)
            else:
                gl, wl = g.split(b'\n'), want.split(b'\n')
                i = next((i for i in range(min(len(gl), len(wl))) if gl[i] != wl[i]), min(len(gl), len(wl)))
                e.append('%s: %d bytes, want %d; first difference, line %d:\n      got  %r\n      want %r'
                         % (k, len(g), len(want), i + 1, gl[i] if i < len(gl) else None, wl[i] if i < len(wl) else None))
        print('%-6s %5d bytes in, %5d out, %2d pages: %s' % (k, len(d), len(want), want.count(b'\f') + (1 if want else 0),
                                                           'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]
        ok &= not e
    b, st, t2 = P3.session(cf, b'EROFF\r', rtc=P3.clock(), later=[('LTOS> ', b'EROFF NOPE.RF\r'), ('LTOS> ', b'MON\r')])
    u = P2.session_out(t2, 'EROFF\r')
    e = [] if 'EROFF name' in u else ['EROFF alone: %r' % u]
    u2 = P2.session_out(t2, 'EROFF NOPE.RF\r')
    e += [] if 'NOPE' in u2.upper() or 'not' in u2.lower() else ['EROFF NOPE.RF: %r' % u2]
    print('EROFF alone: the usage; a missing file: the kernel says so: %s' % ('OK' if not e else 'FAIL')); [print('    ' + x) for x in e]
    ok &= not e
    print('\nEROFF: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
