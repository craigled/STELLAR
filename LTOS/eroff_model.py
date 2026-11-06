# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""eroff_model.py - what EROFF.PRG does, in Python: the reference verify_eroff.py holds the 1802 program to.

A small nroff. Text is filled into lines of LL characters and justified; lines that start with '.' are
requests (two letters, case does not matter; an unknown one is ignored):

  .br          break: the words so far go out as a line
  .sp N        break, then N blank lines (1)          .bp      break, then a new page
  .ne N        break; a new page unless N lines still fit on this one
  .fi / .nf    fill (the default) / no fill: each line as it is      .ad / .na   justify / ragged right
  .ce N        break; the next N text lines centred (1)
  .in N        break; indent N (+N / -N: from the indent now)        .ti N   break; the next line only
  .ll N        line length (+N / -N), 10-132 (65)     .pl N    page length (0: no pages), 7-255 (60)
  .pp          a paragraph: break, a blank line, the next line indented 5
  .he 'l'c'r'  the header: left, centred, right; % is the page number (any first character delimits)
  .fo 'l'c'r'  the footer                              .\"      a comment
\& is nothing (a line can start "\&." to begin with a dot). Fonts: \fB bold, \fI italic, \fR roman, \fP the one before - in text (not in requests). .B text / .I text / .R text:
that text in the font, then the one before; .B / .I / .R alone: the font from here on. A font change takes no
room: lines are filled and justified on what shows. Into a file the changes go as \fB \fI \fR (elfprint
makes them real bold and italic); to the screen they are left out.
More, after -ms:
  .lp          a paragraph, its first line not indented
  .ip T N      an indented paragraph: the text N in (5), the tag T (a word, or "words") hanging in the margin;
               a tag that does not fit goes on a line of its own. .pp .lp .sh .nh end it
  .sh text     a heading, bold          .nh L text   a numbered heading (1., 1.1., ... - L the level, 1-5)
  .tl 'l'c'r'  a 3-part title line here (% the page)
  .ds [L|I|C] ... .de   a display: no fill, indented 5 (I), left (L) or centred (C), kept on one page (60
               lines or 3000 bytes at most: more goes out in parts, each kept together)
  .sp N[u]     u: i inches (6 lines), c cm, p points (12 a line), v lines; one decimal, 99.9 at most
A blank line: break and a blank line. A line that starts with spaces: break, and it starts that far in.
Spaces between words are kept as typed; the end of an input line counts as one space.

A page (PL lines): the header, 2 blank lines, PL - 6 lines of text, 2 blank lines, the footer, then a
form feed (not after the last page; into a file only - EROFF sends none to the screen, as the Elf2K's
BIOS stops printing after one). No-space at the top of a page: blank lines there are dropped.

    python3 LTOS/eroff_model.py FILE     # the output, as EROFF would give it
"""
import sys

MAXLL, MAXLINE, MAXT, MAXB, MAXPFX = 132, 255, 80, 250, 32
KEEPL, KEEPB = 60, 3000                       # a display kept: lines, bytes (each line + 1)
CODE = {'R': '\x01', 'B': '\x02', 'I': '\x03'}          # a font change, inside: one byte that takes no room
FONT = {v: k for k, v in CODE.items()}


def vis(x):                                  # how much of x shows
    return len(x) - sum(ch in FONT for ch in x)


class Roff:
    def __init__(s):
        s.ll, s.ind, s.ti, s.pl = 65, 0, -1, 60
        s.fill, s.adj, s.ce = True, True, 0
        s.he, s.fo = '', ''
        s.words = []                         # the line being filled: (spaces before it, word) each
        s.dirleft = True                     # the justifying spaces go left first, then right (alternating)
        s.page, s.lineno, s.out = 1, 0, []
        s.fcur, s.fprv, s.pfx = 'R', 'R', ''        # the font, the one before, font changes for the next word
        s.pind, s.tag = 0, ''                    # .ip: its indent (on top of IN), its tag (waiting for the line)
        s.nums = [0] * 5                         # .nh's numbers
        s.keeping, s.kept, s.keptb = False, [], 0
        s.dsave = None                           # .ds: the fill, IN and CE to go back to

    def setf(s, f):                          # -> the change's byte; P: the font before
        if f == 'P': f = s.fprv
        s.fprv, s.fcur = s.fcur, f
        return CODE[f]

    def conv(s, t):                          # \fB \fI \fR \fP -> their bytes
        o, i = '', 0
        while i < len(t):
            if t[i] == '\\' and t[i + 1:i + 2] == 'f' and t[i + 2:i + 3] and t[i + 2] in 'BIRP':
                o += s.setf(t[i + 2]); i += 3
            elif t[i] == '\\' and t[i + 1:i + 2] == '&':     # \& : nothing (so a line can start with a dot)
                i += 2
            else:
                o += t[i]; i += 1
        return o

    # ---- pages
    def body(s): return s.pl - 6

    def title(s, t):
        if not t: return ''
        d, parts = t[0], t[1:].split(t[0])
        parts = (parts + ['', '', ''])[:3]
        parts = [p.replace('%', str(s.page)) for p in parts]
        line = [' '] * s.ll
        def put(col, txt):
            for i, ch in enumerate(txt):
                if 0 <= col + i < s.ll: line[col + i] = ch
        put(0, parts[0]); put(max(0, (s.ll - len(parts[1])) // 2), parts[1]); put(s.ll - len(parts[2]), parts[2])
        return ''.join(line)

    def raw(s, t): s.out.append(t.rstrip(' ') + '\n')

    def endpage(s, last):
        while s.lineno < s.body(): s.raw(''); s.lineno += 1
        s.raw(''); s.raw(''); s.raw(s.title(s.fo))
        if not last: s.out.append('\f')
        s.page += 1; s.lineno = 0

    def line(s, t):                          # a body line out - kept, in a display
        if s.keeping:
            if len(s.kept) == KEEPL or s.keptb + len(t) + 1 > KEEPB: s.flush()
            s.kept.append(t); s.keptb += len(t) + 1
            return
        s.out_line(t)

    def flush(s):                            # the display kept: a new page first if it will not fit
        k = s.kept; s.kept, s.keptb = [], 0
        if k and s.pl and s.lineno and s.lineno + len(k) > s.body(): s.endpage(False)
        for t in k: s.out_line(t)

    def out_line(s, t):                      # a body line out (the header first at a page's top)
        if s.pl and s.lineno == 0:
            s.raw(s.title(s.he)); s.raw(''); s.raw('')
        s.raw(t)
        if s.pl:
            s.lineno += 1
            if s.lineno == s.body(): s.endpage(False)

    def space(s, n):
        for _ in range(n):
            if s.pl and s.lineno == 0: return     # no-space at the top of a page
            s.line('')

    # ---- filling
    def indent(s): return s.ti if s.ti >= 0 else min(s.ind + s.pind, s.ll - 1)

    def joined(s, ws):                       # the line as it stands: the first word's spaces are not counted
        return ws[0][1] + ''.join(' ' * g + w for g, w in ws[1:]) if ws else ''

    def emit(s, justify):
        ind = s.indent(); width = s.ll - ind
        w = s.words; text = s.joined(w)
        if justify and len(w) > 1 and vis(text) < width:
            extra, gaps = width - vis(text), len(w) - 1
            base, rem = divmod(extra, gaps)
            sp = [g + base for g, _ in w[1:]]
            for i in range(rem):
                sp[i if s.dirleft else gaps - 1 - i] += 1
            s.dirleft = not s.dirleft
            text = w[0][1] + ''.join(' ' * sp[i] + w[i + 1][1] for i in range(gaps))
        if s.tag:                                # .ip's tag, in the margin at IN
            pad = max(ind - s.ind - vis(s.tag), 1)
            s.line(' ' * s.ind + s.tag + ' ' * pad + text); s.tag = ''
        else:
            s.line(' ' * ind + text)
        s.words = []; s.ti = -1

    def brk(s):
        if s.words: s.emit(False)

    def word(s, gap, w):
        width = s.ll - s.indent()
        if s.words:
            j = s.joined(s.words)
            if vis(j) + gap + vis(w) > width or len(j) + gap + len(w) > MAXB: s.emit(s.adj)
        s.words.append((gap, w))

    def addpfx(s, x): s.pfx = (s.pfx + x)[:MAXPFX]

    # ---- requests
    @staticmethod
    def num(arg, default):
        """-> (sign, value): sign '+', '-' or ''; value default if no digits"""
        a = arg.lstrip(' '); sg = ''
        if a[:1] in '+-' and a: sg, a = a[0], a[1:]
        d = ''
        for ch in a:
            if not ch.isdigit(): break
            d += ch
        return sg, (int(d) & 0xFFFF if d else default)

    def endip(s): s.pind = 0; s.tag = ''

    @staticmethod
    def tagarg(arg):                         # .ip's tag: a word, or "words"; -> (tag, the rest)
        a = arg.lstrip(' ')
        if a[:1] == '"':
            j = a.find('"', 1)
            return (a[1:j], a[j + 1:]) if j >= 0 else (a[1:], '')
        j = a.find(' ')
        return (a, '') if j < 0 else (a[:j], a[j:])

    @staticmethod
    def spunits(arg):                        # .sp: N lines, or N.N with a unit i c p v
        a = arg.lstrip(' ')
        if a[:1] in '+-' and a: a = a[1:]
        d = ''
        while a[:1].isdigit(): d += a[0]; a = a[1:]
        f, hasf = 0, False
        if a[:1] == '.' and a[1:2].isdigit():
            f, hasf = int(a[1]), True; a = a[2:]
            while a[:1].isdigit(): a = a[1:]
        if not d and not hasf: return 1
        u = a[:1].lower()
        n = int(d) & 0xFFFF if d else 0
        if u not in ('i', 'c', 'p', 'v'): return n
        v10 = min(n * 10 + f, 999)
        return {'i': (v10 * 6 + 5) // 10, 'c': (v10 * 59 + 125) // 250, 'p': (v10 + 60) // 120, 'v': (v10 + 5) // 10}[u]

    def rel(s, now, arg, default):
        sg, v = s.num(arg, default)
        return now + v if sg == '+' else now - v if sg == '-' else v

    def request(s, name, arg):
        n = name.lower()
        if n == 'br': s.brk()
        elif n == 'sp': s.brk(); s.space(s.spunits(arg))
        elif n == 'bp':
            s.brk()
            if s.pl and s.lineno: s.endpage(False)
        elif n == 'ne':
            s.brk(); need = s.num(arg, 1)[1]
            if s.pl and s.lineno and s.lineno + need > s.body(): s.endpage(False)
        elif n == 'fi': s.brk(); s.fill = True
        elif n == 'nf': s.brk(); s.fill = False
        elif n == 'ad': s.adj = True
        elif n == 'na': s.adj = False
        elif n == 'ce': s.brk(); s.ce = s.num(arg, 1)[1]
        elif n == 'in': s.brk(); s.ind = min(max(s.rel(s.ind, arg, 0), 0), s.ll - 1)
        elif n == 'ti': s.brk(); s.ti = min(max(s.rel(s.ind, arg, 0), 0), s.ll - 1)
        elif n == 'll':
            s.ll = min(max(s.rel(s.ll, arg, 65), 10), MAXLL)
            s.ind = min(s.ind, s.ll - 1)
        elif n == 'pl':
            v = s.num(arg, 60)[1]
            s.pl = 0 if v == 0 else min(max(v, 7), 255)
            if s.pl and s.lineno >= s.body(): s.endpage(False)
            if not s.pl: s.lineno = 0
        elif n == 'pp': s.brk(); s.endip(); s.space(1); s.ti = min(s.ind + 5, s.ll - 1)
        elif n == 'lp': s.brk(); s.endip(); s.space(1)
        elif n == 'ip':
            s.brk(); s.endip(); s.space(1)
            tag, rest = s.tagarg(arg)
            v = s.num(rest, 5)[1]
            s.pind = min(v, s.ll - 1 - s.ind)
            if tag:
                if vis(tag) < s.pind: s.tag = tag
                else: s.line(' ' * s.ind + tag)
        elif n in ('sh', 'nh'):
            s.brk(); s.endip(); s.space(1)
            if s.pl and s.lineno and s.lineno + 3 > s.body(): s.endpage(False)
            t, label = arg.lstrip(' '), ''
            if n == 'nh':
                lv = 1
                if t[:1].isdigit():
                    d = ''
                    while t[:1].isdigit(): d += t[0]; t = t[1:]
                    lv = min(max(int(d) & 0xFFFF, 1), 5); t = t.lstrip(' ')
                s.nums[lv - 1] = (s.nums[lv - 1] + 1) & 0xFFFF
                for i in range(lv, 5): s.nums[i] = 0
                label = '.'.join(str(x) for x in s.nums[:lv]) + '. '
            t = (label + t)[:MAXLINE]
            if t: s.line(' ' * s.ind + s.setf('B') + t + s.setf('P'))
        elif n == 'tl': s.brk(); s.line(s.title(arg.lstrip(' ')[:MAXT]))
        elif n == 'ds':
            s.brk()
            if s.keeping: s.flush()
            if s.dsave is None: s.dsave = (s.fill, s.ind, s.ce)
            k = arg.lstrip(' ')[:1].upper()
            s.fill = False; s.keeping = True
            if k == 'C': s.ce = 0xFFFF
            elif k != 'L': s.ind = min(s.ind + 5, s.ll - 1)
        elif n == 'de':
            s.brk()
            if s.keeping: s.flush(); s.keeping = False
            if s.dsave is not None: s.fill, s.ind, s.ce = s.dsave; s.dsave = None
        elif n in ('b', 'b ', 'i', 'i ', 'r', 'r '):
            f, a = n[0].upper(), arg.lstrip(' ')
            if a[:1] == '"':                         # "words": the quotes go
                j = a.find('"', 1); a = a[1:j] if j >= 0 else a[1:]
                if not a: return
            if not a: s.addpfx(s.setf(f))
            else: s.text(s.conv(('\\f' + f + a + '\\fP')[:MAXLINE]))
        elif n in ('he', 'fo'):
            t = arg.lstrip(' ')[:MAXT]
            if n == 'he': s.he = t
            else: s.fo = t

    # ---- input
    def text(s, t):
        if s.ce:
            s.brk(); t = t.strip(' ')
            pad = max(0, (s.ll - s.ind - vis(t)) // 2)
            s.line(' ' * (s.ind + pad) + s.pfx + t); s.ce -= 1; s.pfx = ''
        elif not s.fill:
            s.line(' ' * s.indent() + s.pfx + t); s.ti = -1; s.pfx = ''
        else:
            lead = len(t) - len(t.lstrip(' '))
            if lead:
                s.brk(); s.ti = min(s.ind + lead, s.ll - 1)
            t = t.lstrip(' '); gap = 1                # spaces between words are kept (as nroff); a line's
            for w in t.split(' '):                    #  end is one space
                if not w: gap += 1
                elif vis(w) == 0:                     # only font changes: onto the last word (or the next)
                    if s.words and len(s.joined(s.words)) + len(w) <= MAXB:
                        g, lw = s.words[-1]; s.words[-1] = (g, lw + w)
                    else: s.addpfx(w)
                    gap += 1
                else:
                    w = s.pfx + w; s.pfx = ''
                    s.word(gap, w); gap = 1

    def feed(s, t):
        t = t.replace('\t', ' ')[:MAXLINE]
        if t.startswith('.'):
            if t[1:3] == '\\"': return
            s.request(t[1:3], t[3:])
            return
        t = s.conv(t)
        if t.strip(' ') == '':
            s.brk(); s.space(1)
        else:
            s.text(t)

    def run(s, data):
        lines = data.replace('\r', '').split('\n')
        if lines[-1] == '': lines.pop()                  # (a last line with no LF counts; an empty one is none)
        for t in lines:
            s.feed(t)
        s.brk()
        if s.keeping: s.flush()
        if s.pl and s.lineno: s.endpage(True)
        return ''.join(s.out)


def eroff(data, screen=False):
    """The output: into a file (font changes as \\fB \\fI \\fR), or to the screen (none, and no form feeds)"""
    o = Roff().run(data)
    if screen: return ''.join(ch for ch in o if ch not in FONT and ch != '\f')
    return ''.join('\\f' + FONT[ch] if ch in FONT else ch for ch in o)


if __name__ == '__main__':
    sys.stdout.write(eroff(open(sys.argv[1], encoding='latin1').read()))
