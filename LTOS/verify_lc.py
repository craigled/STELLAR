# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LC (LC.PRG, the LTOS Commander) phase 1 in the simulator, on the real ROM's UART (19200 baud, a UART that holds
ONE byte): a card with folders, a folder of 200 files, a deep folder with a long path, a hidden file and a read-only
one. Keys are typed as a terminal sends them (arrows and PgDn as their Esc sequences), and after every key the
whole screen - every character and which are reversed - is compared with what a model of LC in Python says it
should be, the model's folders read from the very same card image:

  * both panes (folders first, then by name as the card has it: NAME    EXT), sizes, dates; a hidden file not
    shown; the cursor reversed in the active pane only; the frame's path (a long one: ... and its end), the counts
  * Up Down PgUp PgDn Home End, scrolling; Enter into a folder, '..' and Backspace up (the cursor back on the
    folder left); a folder of more than 170: the first 169 and "(more)"
  * Tab; Space tags (the tagged count and bytes), '*' every file, '-' none; the line about the file under the
    cursor (size, full date, read-only); a key not yet done: its message, gone at the next key; Ctrl-R; F1 Help
  * Esc: the screen cleared, the cursor shown, LTOS> again; no byte lost at the UART all along

    python3 LTOS/verify_lc.py [-v]
"""
import os, re, struct, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import verify_phase0 as V
import verify_phase1 as P1
import verify_cardfiles as VC
import cardsync as CS
import cardfiles as CFm
import build
import verify_phase2 as P2

ROWS, PMAX, POOLN, VPMAX = 18, 160, (0x6A00 - 0x5A00) // 22, 128
VERB = '-v' in sys.argv
UARTS = []                                              # the session's UART (its board: where the 1802 is)
_ui = VC.SessionUART.__init__
def _ni(self, gen): UARTS.append(self); _ui(self, gen)
VC.SessionUART.__init__ = _ni
_LCSY = {}
def lc_waiting():
    """True while LC sits in KEY's inline loop - waiting for a key, nothing more to do or say."""
    if not _LCSY: _LCSY.update(build.assemble('lc')[1])
    if not UARTS or getattr(UARTS[-1], 'board', None) is None: return False
    u = UARTS[-1]; c = u.board.c
    if u.rxp < len(u.inq): return False                 # (a key sent and not read yet)
    return _LCSY['KW1'] <= c.R[c.P] < _LCSY['KW3']
def settle(quiet, cap=12000):
    """What comes, until LC waits for a key again (seen at once - no fixed wait), or quiet seconds of nothing"""
    got, idle = b'', 0.0
    while len(got) < cap:
        d = yield ('recv', 1, 0.02)
        if d: got += d; idle = 0.0; continue
        idle += 0.02
        if lc_waiting() or idle >= quiet: break
    return got
KEYBAR = ' 1Help 2Info 3View 4Ren 5Copy 6Move 7MkDir 8Del 9Run EEdit  Tab pane  Esc quit'
NOTYET = ' Not in this LC yet.'  # (9: Run)
VFOOT = ' Space next page   b back   Home  End   H hex or text   Esc back to the panes'
KINDS = {'PRG': 'a program', 'OVL': 'the rest of a program (its overlay)', 'STL': 'a STELLAR app', 'MUS': 'music for PLAY',
         'SH': 'a script for SH', 'SC': 'Stellar C (SC makes it a .STL)', 'BIN': 'raw bytes',
         'HLP': 'a page of HELP', 'CLC': 'a sheet for LTCALC', 'TXT': 'text'}
TEXTCTL = {9, 10, 12, 13, 0x1A, 0x1B}
pl = lambda n: '' if n == 1 else 's'


def is_text(d): return all(b < 0x80 and (b >= 0x20 or b in TEXTCTL) for b in d[:512])


def vtrow(d, st):
    """VTROW: one text row (up to 80) from st['pos']; st['flag']: 1 a CR ended the last line, 2 the last row was full."""
    out, eof = '', False
    while True:
        if st['pos'] >= len(d): return out, True
        b = d[st['pos']]; st['pos'] += 1
        f = st['flag']; st['flag'] = 0
        if f:
            if b == 10: continue
            if f & 2 and b == 13: st['flag'] = 1; continue
        if b == 10: return out, False
        if b == 13: st['flag'] = 1; return out, False
        if b == 9:
            out += ' '
            while len(out) % 8: out += ' '
        elif b < 32 or b >= 127: out += '.'
        else: out += chr(b)
        if len(out) == 80: st['flag'] = 2; return out, False


def view_pages(d, hexmode):
    """[(22 rows, the last page?)] as View draws them."""
    pages, st = [], {'pos': 0, 'flag': 0}
    while True:
        rows, eof = [], False
        for r in range(22):
            if hexmode:
                b = d[st['pos']:st['pos'] + 16]; o = st['pos']; st['pos'] += len(b); eof |= len(b) < 16
                rows.append('' if not b else '%06X ' % o + ''.join(' ' + ('%02X' % b[i] if i < len(b) else '  ') + (' ' if i == 7 else '')
                            for i in range(16)) + '  ' + ''.join(chr(c) if 32 <= c < 127 else '.' for c in b))
            else:
                t, e2 = vtrow(d, st); rows.append(t); eof |= e2
        last = eof or st['pos'] >= len(d)
        pages.append((rows, last))
        if last or len(pages) == VPMAX: return pages


def lines_of(d):
    if len(d) > 16384: return 'over 16 KB (lines not counted)'
    n = d.count(10) or d.count(13)
    if d and d[-1] not in (10, 13): n += 1
    return '%d line%s' % (n, pl(n))


def kind(name, d):
    if name == 'STELLAR.BIN': return 'the STELLAR firmware (FW loads it)'
    ext = name.partition('.')[2]
    if ext in KINDS:
        k = KINDS[ext]
        if ext == 'PRG':
            if d[6:10] == b'VER:': k += ' ' + d[10:].split(b'\0')[0][:8].decode()
            k += ': load $%02X%02X, start $%02X%02X' % (d[0], d[1], d[4], d[5])
        elif ext == 'STL' and len(d) > 128 and d[128]: k += ' ' + d[128:].split(b'\0')[0][:8].decode()
        elif ext in ('SH', 'SC', 'TXT'): k += ', ' + lines_of(d)
        return k
    return 'text, ' + lines_of(d) if is_text(d) else 'data (not text)'
DEEP = '/AAAAAAAA/BBBBBBBB/CCCCCCCC/DDDDDDDD'


def vt100(t):
    """The screen as the VT100 shows it: 24 rows of 80 characters, and which are reversed (row strings of 0 / 1)."""
    g = [[' '] * 81 for _ in range(25)]; a = [['0'] * 81 for _ in range(25)]; r = c = 1; rev = False; shown = True
    for m in re.finditer(r'\x1b\[([0-9;?]*)([A-Za-z])|(.)', t, re.S):
        if m.group(3) is not None:
            ch = m.group(3)
            if ch == '\r': c = 1
            elif ch == '\n': r = min(24, r + 1)
            elif ch == '\b': c = max(1, c - 1)
            else:
                if 1 <= r <= 24 and 1 <= c <= 80: g[r][c] = ch; a[r][c] = '1' if rev else '0'
                c += 1
        else:
            p, k = m.group(1), m.group(2)
            if k == 'H':
                q = p.split(';') if p else ['1', '1']; r, c = int(q[0]), int(q[1] if len(q) > 1 and q[1] else 1)
            elif k == 'J': g = [[' '] * 81 for _ in range(25)]; a = [['0'] * 81 for _ in range(25)]
            elif k == 'K':
                for x in range(c, 81): g[r][x] = ' '; a[r][x] = '0'
            elif k == 'm': rev = p == '7'
            elif k in 'hl' and p == '?25': shown = k == 'h'
    return [''.join(row[1:]) for row in g[1:]], [''.join(row[1:]) for row in a[1:]], shown


def fat11(n):
    base, _, ext = n.partition('.'); return base.ljust(8) + ext.ljust(3)


class Card:
    """The folders as the card has them: path -> [(name, attr, size, date, cluster)] (LC's order, '..' first)."""
    def __init__(s, img, data):
        s.im = img; s.dirs = {'/': 0}; s.data = data
        todo = ['/']
        while todo:
            p = todo.pop()
            for n, at, sz, d, fc in img.entries(s.dirs[p]):
                if at & 0x10: q = (p.rstrip('/') + '/' + n); s.dirs[q] = fc; todo.append(q)
    def listing(s, path, lim=PMAX):
        es = [e for e in s.im.entries(s.dirs[path]) if not e[1] & 0x0E]     # (hidden, system, the label: not shown)
        es.sort(key=lambda e: (not e[1] & 0x10, fat11(e[0])))
        if path != '/': es = [('..', 0x10, 0, None, 0)] + es
        more = len(es) > lim; es = es[:lim]
        return es, more


class Pane:
    def __init__(s, card, col):
        s.card, s.col = card, col; s.path = '/'; s.ents = []; s.more = False; s.top = s.cur = 0; s.tags = set()
    def go(s, path, lim):
        s.path = path; s.ents, s.more = s.card.listing(path, lim); s.top = s.cur = 0; s.tags = set()
    @property
    def up(s): return s.path != '/'


def date14(d, full=False):
    if d is None or d.startswith('1980-00-00'): return ' ' * 14
    return d if full else d[2:]


def line(e, tagged):
    n, at, sz, d, _ = e
    if n == '..': return ' ' + '..'.ljust(12) + '      <UP>' + ' ' + ' ' * 14
    mid = '     <DIR>' if at & 0x10 else '%10d' % sz
    return ('>' if tagged else ' ') + n.ljust(12) + mid + ' ' + date14(d)


class LC:
    """What LC shows, kept as LC keeps it."""
    def __init__(s, card, left='/'):
        s.card = card; s.p = [Pane(card, 1), Pane(card, 41)]; s.act = 0; s.msg = None; s.mode = 'panes'
        s.load(0, left); s.load(1, '/')
    def load(s, k, path):           # the pool: the other pane's records kept; PMAX at most
        s.p[k].go(path, min(PMAX, POOLN - len(s.p[1 - k].ents)))
    def a(s): return s.p[s.act]
    def path_of(s, e):
        p = s.a(); return p.path.rstrip('/') + '/' + e[0]
    def setcur(s, new):
        p = s.a()
        if not p.ents: return
        p.cur = new
        if new < p.top: p.top = new
        elif new >= p.top + ROWS: p.top = new - ROWS + 1
    def key(s, k):
        p = s.a(); n = len(p.ents)
        if s.mode == 'view':
            v = s.v; last = v['pages'][v['pg']][1]
            if k == 'vesc': s.mode = 'panes'
            elif k == 'vnext' and not last and v['pg'] < VPMAX - 1: v['pg'] += 1
            elif k == 'vprev' and v['pg']: v['pg'] -= 1
            elif k == 'vhome': v['pg'] = 0
            elif k == 'vend': v['pg'] = len(v['pages']) - 1
            elif k == 'vhex': v['hex'] ^= 1; v['pg'] = 0; v['pages'] = view_pages(v['data'], v['hex'])
            return
        if s.mode == 'info': s.mode = 'panes'; return
        if s.mode == 'prompt': s.mode = 'panes'; s.msg = None; return
        s.msg = None
        if k == 'up' and p.cur > 0: s.setcur(p.cur - 1)
        elif k == 'down' and p.cur < n - 1: s.setcur(p.cur + 1)
        elif k == 'pgup': s.setcur(max(0, p.cur - ROWS))
        elif k == 'pgdn' and n: s.setcur(min(n - 1, p.cur + ROWS))
        elif k == 'home': s.setcur(0)
        elif k == 'end' and n: s.setcur(n - 1)
        elif k == 'tab': s.act ^= 1
        elif k == 'enter' and n:
            e = p.ents[p.cur]
            if e[0] == '..': s.key('back')
            elif e[1] & 0x10: s.load(s.act, p.path.rstrip('/') + '/' + e[0])
            else: s.key('view')
        elif k == 'back' and p.up:
            left = p.path; s.load(s.act, p.path.rsplit('/', 1)[0] or '/')
            k2 = next(i for i, e in enumerate(p.ents) if e[1] & 0x10 and (p.path.rstrip('/') + '/' + e[0]) == left)
            p.cur = k2; p.top = k2 - ROWS // 2 if k2 >= ROWS else 0
        elif k == 'tag' and n:
            if not (p.up and p.cur == 0): p.tags ^= {p.ents[p.cur][0]}
            if p.cur < n - 1: s.setcur(p.cur + 1)
        elif k == 'tagall': p.tags |= {e[0] for e in p.ents if not e[1] & 0x10}
        elif k == 'untag': p.tags = set()
        elif k == 'reload':
            for j in (0, 1): s.load(j, s.p[j].path)
        elif k == 'notyet': s.msg = NOTYET
        elif k == 'view' and n:
            e = p.ents[p.cur]
            if e[1] & 0x10: s.msg = ' A folder: Enter goes into it. View is for files.'; return
            d = s.card.data[s.path_of(e)]
            s.mode = 'view'; s.v = {'data': d, 'hex': not is_text(d), 'pg': 0, 'path': s.path_of(e), 'size': e[2]}
            s.v['pages'] = view_pages(d, s.v['hex'])
        elif k == 'info' and n:
            e = p.ents[p.cur]
            if e[0] == '..': s.msg = ' .. is the folder this one is in.'; return
            s.mode = 'info'; s.ibox = s.info_lines(e)
    def prompt(s, text):            # row 22 asks (a name, or Y / N)
        s.mode = 'prompt'; s.ptext = text
    def after(s, card, msg, name=None, other=False):
        """A job done: the card as it is now; this pane read again (the cursor on name, or where it was), the other
        too if it shows the same folder or other; tags gone; msg on row 22 (None: the file's line)."""
        s.card = card; s.mode = 'panes'
        for q in s.p: q.card = card
        a, o = s.p[s.act], s.p[1 - s.act]
        same = a.path == o.path
        old = a.cur
        s.load(s.act, a.path)
        if name is not None:
            k = next((i for i, e in enumerate(a.ents) if e[0] == name), None)
            a.cur = k if k is not None else min(len(a.ents), old)   # (not found: past the end, then the last)
        else: a.cur = old
        if a.ents and a.cur > len(a.ents) - 1: a.cur = len(a.ents) - 1
        a.top = a.cur - ROWS // 2 if a.cur >= ROWS else 0
        if other or same: s.load(1 - s.act, o.path)
        s.msg = msg
    def info_lines(s, e):
        n, at, sz, d, fc = e; path = s.path_of(e)
        L = [' ' + path, '']
        if at & 0x10:
            es = [x for x in s.card.im.entries(s.card.dirs[path]) if not x[1] & 0x0E]
            fs = [x for x in es if not x[1] & 0x10]; nd = len(es) - len(fs)
            L.append('   Holds        %d file%s of %d bytes and %d folder%s' % (len(fs), pl(len(fs)), sum(x[2] for x in fs), nd, pl(nd)))
        else:
            secs = (sz + 511) // 512; spc = s.card.im.spc; cl = (secs + spc - 1) // spc
            L.append('   Size         %d bytes, %d sector%s, %d cluster%s' % (sz, secs, pl(secs), cl, pl(cl)))
        L.append('   Written      ' + date14(d, True))
        names = [t for bit, t in ((1, 'read-only '), (2, 'hidden '), (4, 'system '), (0x20, 'archive ')) if at & bit]
        L.append('   Attributes   ' + (''.join(names) if names else 'none'))
        L.append('   First cluster ' + str(fc))
        L.append('   What it is   ' + ('a folder' if at & 0x10 else kind(n, s.card.data.get(path, b''))))
        return (L + [''] * 10)[:10]
    def frame_top(s, p):
        t = p.path if len(p.path) <= 34 else '...' + p.path[-31:]
        return '+- ' + t + ' ' + '-' * (35 - len(t)) + '+'
    def frame_bot(s, p):
        es = p.ents[1:] if p.up else p.ents
        tg = [e for e in es if e[0] in p.tags]
        if tg: t = '%d tagged, %d bytes' % (len(tg), sum(e[2] for e in tg))
        else:
            nf = sum(1 for e in es if not e[1] & 0x10); nd = len(es) - nf
            t = '%d file%s, %d folder%s' % (nf, '' if nf == 1 else 's', nd, '' if nd == 1 else 's')
        if p.more: t += ' (more)'
        t = '+- ' + t + ' '
        return t + '-' * (39 - len(t)) + '+'
    def info(s):
        p = s.a()
        if not p.ents: return ''
        n, at, sz, d, _ = p.ents[p.cur]
        if n == '..': return ' ..   up a folder'
        if at & 0x10: t = ' ' + n + '/   folder'
        else: t = (' ' + n).ljust(14) + '%d bytes ' % sz
        t += ' ' + date14(d, True)
        if at & 1: t += '  read-only'
        return t
    def screen(s):
        g = [[' '] * 80 for _ in range(24)]; a = [['0'] * 80 for _ in range(24)]
        def put(r, c, text, rev=False):
            for i, ch in enumerate(text): g[r - 1][c - 1 + i] = ch; a[r - 1][c - 1 + i] = '1' if rev else '0'
        if s.mode == 'view':
            v = s.v; rows, last = v['pages'][v['pg']]
            h = ' %s  %d bytes  %s   page %d%s' % (v['path'], v['size'], 'hex' if v['hex'] else 'text', v['pg'] + 1, ' (the end)' if last else '')
            put(1, 1, h[:80].ljust(80), True)
            for r, t in enumerate(rows): put(2 + r, 1, t)
            put(24, 1, VFOOT)
            return [''.join(r) for r in g], [''.join(r) for r in a]
        put(1, 1, ' LTOS Commander 0.2'.ljust(80), True)
        for k, p in enumerate(s.p):
            c = p.col; act = k == s.act
            top = s.frame_top(p)
            put(2, c, top)
            if act: put(2, c + 3, top[3:top.index(' ', 3)], True)
            for r in range(ROWS):
                e = p.top + r
                put(3 + r, c, '|'); put(3 + r, c + 39, '|')
                if e < len(p.ents): put(3 + r, c + 1, line(p.ents[e], p.ents[e][0] in p.tags), act and e == p.cur)
                else: put(3 + r, c + 1, ' ' * 38)
            put(21, c, s.frame_bot(p))
        put(22, 1, s.ptext if s.mode == 'prompt' else s.msg if s.msg else s.info())
        put(23, 1, KEYBAR)
        if s.mode == 'info':
            put(6, 8, '+- Info ' + '-' * 57 + '+')
            for r, t in enumerate(s.ibox): put(7 + r, 8, '|' + t[:64].ljust(64) + '|')
            put(17, 8, '+'); put(17, 9, ' a key: back to the panes ', True); put(17, 35, '-' * 38 + '+')
        return [''.join(r) for r in g], [''.join(r) for r in a]


KEYS = {'up': b'\x1b[A', 'down': b'\x1b[B', 'pgup': b'\x1b[5~', 'pgdn': b'\x1b[6~', 'home': b'\x1b[H', 'end': b'\x1b[F',
        'tab': b'\t', 'enter': b'\r', 'back': b'\x7f', 'tag': b' ', 'tagall': b'*', 'untag': b'-', 'reload': b'\x12',
        'notyet': b'9', 'f1': b'\x1bOP', 'esc': b'\x1b', 'view': b'3', 'info': b'2', 'vnext': b' ', 'vprev': b'b',
        'vend': b'\x1b[F', 'vhome': b'\x1b[H', 'vhex': b'H', 'vesc': b'\x1b', 'iesc': b'\x1b'}


def make_card():
    kimg, _ = build.kernel(); mem, _, _ = build.build(kimg)
    cf, e, st = P1.installed(mem, 16384)
    path = os.path.join(tempfile.mkdtemp(), 'c.img'); open(path, 'wb').write(V.image(cf, 16384))
    im = CS.Image(path, check=False); CS.run(im.open(lambda *a: None)); CS.run(im.walk(lambda *a: None))
    wrap = (b'A' * 200 + b'\r\n' + b'\tTab\tand\ttabs\r\n' + b'CR only\rthen LF\n' + b'x' * 80 + b'\n' + b'after an 80\n'
            + b'x' * 80 + b'\r\n' + b'end, no line end')
    files = [('/LC%d.OVL' % k, p) for k, p in enumerate(build.lc_ovl())] + [('/LC.PRG', build.prg('lc')),  ('/CD.PRG', build.prg('cd')), ('/WRAP.TXT', wrap),
             ('/EMPTY.TXT', b''), ('/NOTES', b'plain text\nno extension\n'),
             ('/BIG.TXT', b''.join(b'line %d %s\r\n' % (i, b'-' * (i * 7 % 150)) for i in range(460))), ('/A.TXT', b'x' * 10), ('/A-B.TXT', b'y' * 20), ('/ZED', b'zzz'),
             ('/README.TXT', b'hello\n' * 300), ('/SECRET.TXT', b'42'), ('/RO.TXT', b'r' * 77),
             ('/DOCS/NOTE.TXT', bytes(700)), ('/DOCS/OLD/DEEP.TXT', bytes(5)), ('/GAMES/X.STL', bytes(1024)),
             ('/GAMES/B.STL', bytes(512)), ('/GAMES/ZED', b'zz'), (DEEP + '/END.TXT', b'end')]
    files += [('/MANY/F%03d.TXT' % i, bytes(i % 50)) for i in range(200)]
    dirs = ['/DOCS', '/DOCS/OLD', '/GAMES', '/MANY', '/EMPTY'] + ['/'.join(DEEP.split('/')[:k]) for k in range(2, 6)]
    CS.run(im.write(dirs, files, lambda *a: None))
    img = bytearray(open(path, 'rb').read())
    VC.set_hidden(img, '/SECRET.TXT')
    ps = struct.unpack_from('<I', img, 0x1C6)[0]; v = ps * 512                 # RO.TXT read-only (attribute bit 0)
    res, nf, fsz, nroot = struct.unpack_from('<H', img, v + 14)[0], img[v + 16], struct.unpack_from('<H', img, v + 22)[0], struct.unpack_from('<H', img, v + 17)[0]
    root = (ps + res + nf * fsz) * 512
    for o in range(root, root + nroot * 32, 32):
        if bytes(img[o:o + 11]) == b'RO      TXT': img[o + 11] |= 1
    open(path, 'wb').write(img)
    P1.load_image(cf, bytes(img))
    im = CS.Image(path, check=False); CS.run(im.open(lambda *a: None))
    return cf, Card(im, dict(files))


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    m, sy = build.assemble('lc')
    e = []
    if sy['VEND'] > sy['CORETOP']: e.append('LC.PRG runs to $%04X, past $%04X' % (sy['VEND'], sy['CORETOP']))
    for nm in ('lcov0', 'lcov1', 'lcov2', 'lcov3', 'lcov4'):
        m2, s2 = build.assemble(nm)
        if s2['OVEND'] > sy['OVLA'] + sy['OVSECS'] * 512: e.append('%s runs past its room' % nm)
    if not sy['OVLA'] + sy['OVSECS'] * 512 <= sy['IDX0'] < sy['IDX1'] < sy['POOL'] or sy['IDX1'] + 256 > sy['POOL']: e.append('the indexes overlap')
    if sy['POOLE'] > sy['RING'] or sy['LBUF'] + 256 > 0x6C00 or sy['HBUF'] + 16 > sy['LBUF']: e.append('the pool or buffers overlap')
    if sy['VPT'] < 0x7700 or sy['VPT'] + sy['VPMAX'] * 10 > 0x7C00: e.append('View\'s pages are not in $7700-$7BFF')
    report('memory: LC.PRG $3000-$%04X, LC.OVL\'s parts, indexes, records, buffers - none overlapping' % sy['VEND'], e)
    cf, card = make_card()
    lc = LC(card)
    root = lc.p[0].ents
    to = lambda name: [next(i for i, e in enumerate(root) if e[0] == name)]
    # the keys, each followed by a look at the whole screen
    plan = (['down'] * to('MANY')[0] + ['enter', 'pgdn', 'pgdn', 'end', 'pgup', 'up', 'home', 'down', 'back',
             'home', 'enter', 'down', 'enter', 'back', 'back']
            + ['down'] * (to('RO.TXT')[0] - to('DOCS')[0]) + ['down', 'up', 'tag', 'tag', 'tab', 'end', 'tag',
             'tagall', 'untag', 'tagall', 'tab', 'home'] + ['down'] * to('AAAAAAAA')[0]
            + ['enter', 'enter', 'enter', 'enter', 'down', 'reload', 'tab', 'enter'])
    pm, plan3 = LC(card), []                            # View and Info, in a fresh LC (its keys found by a model)
    def goto(name):
        p = pm.a(); i = next(j for j, e in enumerate(p.ents) if e[0] == name)
        ks = ['down'] * (i - p.cur) if i >= p.cur else ['up'] * (p.cur - i)
        for k in ks: pm.key(k)
        plan3.extend(ks)
    for name, ks in (('README.TXT', ['view', 'vnext', 'vprev', 'vend', 'vhome', 'vhex', 'vnext', 'vesc']),
                     ('WRAP.TXT', ['enter', 'vesc']), ('LC.PRG', ['view', 'vnext', 'vesc', 'info', 'iesc']),
                     ('README.TXT', ['info', 'iesc']), ('DOCS', ['info', 'iesc', 'view']), ('RO.TXT', ['info', 'iesc']),
                     ('EMPTY.TXT', ['view', 'vesc', 'info', 'iesc']), ('NOTES', ['info', 'iesc', 'view', 'vesc']),
                     ('LC0.OVL', ['info', 'iesc']), ('STELLAR.BIN', ['info', 'iesc']), ('BIG.TXT', ['info', 'iesc', 'view', 'vnext', 'vend', 'vprev', 'vprev', 'vhex', 'vend', 'vesc']),
                     ('GAMES', ['enter']), ('X.STL', ['info', 'iesc', 'view', 'vend', 'vesc'])):
        goto(name)
        for k in ks: pm.key(k); plan3.append(k)
    e4, st4 = [], {'acc': '', 'm': None, 'n': 0}
    def snap():
        img = V.image(cf, 16384); pth = os.path.join(tempfile.mkdtemp(), 'c.img'); open(pth, 'wb').write(img)
        im = CS.Image(pth, check=False); CS.run(im.open(lambda *a: None)); return Card(im, card.data), img
    def tree(c):
        out = {}
        for d, cl in c.dirs.items():
            for n, at, sz, dt, fc in c.im.entries(cl): out[d.rstrip('/') + '/' + n] = (sz, at & 0x10)
        return out
    def look(label):
        st4['n'] += 1
        got, gr, _ = vt100(st4['acc']); want, wr = st4['m'].screen()
        for r in range(1, 24):
            if got[r] != want[r]: e4.append('%s (key %d), row %d:\n      got  %r\n      want %r' % (label, st4['n'], r + 1, got[r], want[r]))
            elif r < 21 and gr[r] != wr[r]: e4.append('%s (key %d), row %d reversed: %s, want %s' % (label, st4['n'], r + 1, gr[r], wr[r]))
    def k4(b, label, wait=1.5):
        yield ('send', b); o = yield from upto(wait); st4['acc'] += o.decode('latin1')
    def nav(*ks):
        for k in ks: yield from k4(KEYS[k], k, 6.0 if k in ('enter', 'back') else 1.5); st4['m'].key(k); look(k)
    class Stop(Exception): pass
    def goto(name):
        p = st4['m'].a(); i = next((j for j, e in enumerate(p.ents) if e[0] == name), None)
        if i is None: e4.append('%s is not in the pane (%s): stopped there' % (name, p.path)); raise Stop
        yield from nav(*(['down'] * (i - p.cur) if i >= p.cur else ['up'] * (p.cur - i)))
    def typed4(text, label, then=None):                 # typed at a quick typist's pace, then the screen looked at
        for ch in text: yield ('send', bytes([ch])); o = yield from upto(0.15); st4['acc'] += o.decode('latin1')
        if then: st4['m'].prompt(then); look(label)
    def ask(b, label, text):
        yield from k4(b, label); st4['m'].prompt(text); look(label)
    def done(b, label, msg, name=None, other=False, check=None, wait=8.0):
        yield from k4(b, label, wait)
        c, img = snap()
        if check:
            t = tree(c); bad = check(t)
            if bad: e4.append('%s: on the card: %s' % (label, bad))
        st4['m'].after(c, msg, name, other); look(label)
    def said(b, label, msg):
        yield from k4(b, label, 4.0); m = st4['m']; m.mode = 'panes'; m.msg = msg; look(label)
    def session4():
        try: yield from session4b()
        except Stop: pass
        for _ in range(4):                              # (out of a prompt, a view, LC: to LTOS> whatever came)
            yield ('send', KEYS['esc']); got = yield from upto(2.0)
            if got.endswith(CFm.PROMPT): break
        st4['img'] = snap()[1]
    def session4b():
        o = yield from upto(6.0)
        st4['acc'] = o.decode('latin1').split('\x1b[0m\x1b[?25l', 1)[-1]
        st4['m'] = LC(snap()[0]); look('LC')
        m = lambda: st4['m']
        yield from goto('A.TXT')                        # Rename: the name offered; typed over; Enter
        yield from ask(b'4', 'rename', ' Rename to (Esc: no): A.TXT')
        yield from typed4(b'\x08' * 5 + b'b1.txt', 'typed', ' Rename to (Esc: no): B1.TXT')
        yield from done(b'\r', 'renamed', ' Renamed.', 'B1.TXT',
                        check=lambda t: None if t.get('/B1.TXT') == (10, 0) and '/A.TXT' not in t else 'B1.TXT / A.TXT')
        yield from ask(b'4', 'rename', ' Rename to (Esc: no): B1.TXT')
        yield from k4(b'\x1b', 'Esc'); m().key('esc'); look('rename: Esc')
        yield from goto('ZED')
        yield from ask(b'4', 'rename', ' Rename to (Esc: no): ZED')
        yield from typed4(b'\x08' * 3 + b'A-B.TXT', 'typed')
        yield from said(b'\r', 'a name there', ' There is one by that name in this folder already.')
        yield from ask(b'4', 'rename', ' Rename to (Esc: no): ZED')
        yield from typed4(b'\x08' * 3 + b'ABCDEFGHI', 'typed')
        yield from said(b'\r', 'not a name', ' Not a name: 1-8 letters or digits, then . and up to 3 more.')
        yield from ask(b'7', 'mkdir', ' A new folder (Esc: none): ')
        yield from typed4(b'newdir', 'typed', ' A new folder (Esc: none): NEWDIR')
        yield from done(b'\r', 'mkdir', ' Folder made.', 'NEWDIR', check=lambda t: None if t.get('/NEWDIR', (0, 0))[1] else 'no /NEWDIR')
        yield from ask(b'7', 'mkdir', ' A new folder (Esc: none): ')
        yield from typed4(b'NEWDIR', 'typed')
        yield from said(b'\r', 'mkdir again', ' There is one by that name in this folder already.')
        yield from nav('tab'); yield from goto('GAMES'); yield from nav('enter', 'tab')
        yield from goto('B1.TXT'); yield from nav('tag'); yield from goto('A-B.TXT'); yield from nav('tag')
        yield from ask(b'6', 'move 2', ' Move 2 to /GAMES? (Y/N) ')
        yield from done(b'y', 'moved 2', ' 2 moved to /GAMES.', other=True,
                        check=lambda t: None if '/GAMES/B1.TXT' in t and '/GAMES/A-B.TXT' in t and '/B1.TXT' not in t and '/A-B.TXT' not in t else 'not moved')
        yield from goto('NEWDIR')
        yield from ask(b'6', 'move a folder', ' Move NEWDIR to /GAMES? (Y/N) ')
        yield from done(b'y', 'moved a folder', ' 1 moved to /GAMES.', other=True,
                        check=lambda t: None if t.get('/GAMES/NEWDIR', (0, 0))[1] and '/NEWDIR' not in t else 'NEWDIR not moved')
        yield from goto('ZED')
        yield from ask(b'6', 'move: no', ' Move ZED to /GAMES? (Y/N) ')
        yield from k4(b'n', 'n'); m().mode = 'panes'; look('move: n')
        yield from nav('tab'); yield from goto('NEWDIR'); yield from nav('enter', 'tab')
        yield from goto('GAMES')
        yield from ask(b'6', 'into itself', ' Move GAMES to /GAMES/NEWDIR? (Y/N) ')
        yield from done(b'y', 'into itself', ' 0 moved to /GAMES/NEWDIR. 1 not: its name is there, or a folder into itself.', other=True,
                        check=lambda t: None if '/GAMES/NEWDIR' in t else 'GAMES moved')
        yield from nav('tab', 'back', 'back', 'tab')
        yield from said(b'6', 'move: same folder', ' Both panes show this folder: Move moves to the other pane' + "'" + 's.')
        yield from goto('ZED')                          # Delete: a file to /TRASH (made), an empty folder, a full one
        yield from ask(b'8', 'delete', ' Delete ZED? Files go to /TRASH, an empty folder for good. (Y/N) ')
        yield from done(b'y', 'deleted', ' 1 moved to /TRASH. ', other=True,
                        check=lambda t: None if t.get('/TRASH/ZED') == (3, 0) and '/ZED' not in t else 'ZED not in /TRASH')
        yield from goto('EMPTY')
        yield from ask(b'\x1b[3~', 'delete (Del)', ' Delete EMPTY? Files go to /TRASH, an empty folder for good. (Y/N) ')
        yield from done(b'Y', 'deleted a folder', ' 0 moved to /TRASH. 1 folder deleted. ', other=True,
                        check=lambda t: None if '/EMPTY' not in t and '/TRASH/EMPTY' not in t else 'EMPTY still there')
        yield from goto('DOCS')
        yield from ask(b'8', 'delete', ' Delete DOCS? Files go to /TRASH, an empty folder for good. (Y/N) ')
        yield from done(b'y', 'a full folder', ' 0 moved to /TRASH. 1 folder left (not empty, or the current one).', other=True,
                        check=lambda t: None if '/DOCS/NOTE.TXT' in t else 'DOCS touched')
        yield from goto('README.TXT'); yield from nav('tag'); yield from goto('RO.TXT'); yield from nav('tag')
        yield from ask(b'8', 'delete 2', ' Delete 2? Files go to /TRASH, an empty folder for good. (Y/N) ')
        yield from done(b'y', 'deleted 2', ' 2 moved to /TRASH. ', other=True,
                        check=lambda t: None if '/TRASH/README.TXT' in t and '/TRASH/RO.TXT' in t and '/RO.TXT' not in t else 'not in /TRASH')
        yield from goto('GAMES'); yield from nav('enter'); yield from goto('ZED')
        yield from ask(b'8', 'delete ZED again', ' Delete ZED? Files go to /TRASH, an empty folder for good. (Y/N) ')
        yield from done(b'y', 'the older one goes', ' 1 moved to /TRASH. ', other=True,
                        check=lambda t: None if t.get('/TRASH/ZED') == (2, 0) and '/GAMES/ZED' not in t else 'TRASH/ZED: %r' % (t.get('/TRASH/ZED'),))
        yield from nav('back'); yield from goto('TRASH'); yield from nav('enter'); yield from goto('ZED')
        yield from ask(b'8', 'delete in the trash', ' Delete ZED? Files go to /TRASH, an empty folder for good. (Y/N) ')
        yield from said(b'y', 'in the trash', ' These are in /TRASH already: EMPTY deletes them for good.')
        yield from session5()
    def fdata(path):                                    # a file's bytes on the card as it is now
        img = V.image(cf, 16384); pth = os.path.join(tempfile.mkdtemp(), 'c.img'); open(pth, 'wb').write(img)
        im = CS.Image(pth, check=False); CS.run(im.open(lambda *a: None)); CS.run(im.walk(lambda *a: None))
        return CS.run(im.get(path, lambda *a: None)) if path in im.where else None
    def same(a, b):
        def ck(t):
            if fdata(a) != fdata(b): return '%s is not %s, byte for byte' % (b, a)
            da = next((e[3] for e in st4['m'].card.im.entries(st4['m'].card.dirs[a.rsplit('/', 1)[0] or '/']) if e[0] == a.rsplit('/', 1)[1]), None)
            return None
        return ck
    def session5():                                     # Copy: files (any size, replaced or not), folders, Esc
        m = lambda: st4['m']
        yield from nav('back')
        yield from nav('tab'); yield from goto('GAMES'); yield from nav('enter', 'tab')
        yield from goto('BIG.TXT')
        yield from ask(b'5', 'copy', ' Copy BIG.TXT to /GAMES? (Y/N) ')
        yield from done(b'y', 'copied', ' 1 copied to /GAMES.', other=True, check=same('/BIG.TXT', '/GAMES/BIG.TXT'), wait=30.0)
        yield from ask(b'5', 'copy again', ' Copy BIG.TXT to /GAMES? (Y/N) ')
        yield from ask(b'y', 'there already', ' BIG.TXT is there already: replace it? (Y, N, A all of them; Esc stops) ')
        yield from done(b'n', 'not replaced', ' 0 copied to /GAMES. 1 left as they were.', other=True)
        yield from ask(b'5', 'copy again', ' Copy BIG.TXT to /GAMES? (Y/N) ')
        yield from ask(b'y', 'there already', ' BIG.TXT is there already: replace it? (Y, N, A all of them; Esc stops) ')
        yield from done(b'y', 'replaced', ' 1 copied to /GAMES.', other=True, check=same('/BIG.TXT', '/GAMES/BIG.TXT'), wait=30.0)
        yield from goto('DOCS')
        yield from ask(b'5', 'copy a folder', ' Copy DOCS to /GAMES? (Y/N) ')
        yield from done(b'y', 'a folder copied', ' 2 copied to /GAMES. 2 folders made.', other=True, wait=30.0,
                        check=lambda t: (same('/DOCS/NOTE.TXT', '/GAMES/DOCS/NOTE.TXT')(t) or same('/DOCS/OLD/DEEP.TXT', '/GAMES/DOCS/OLD/DEEP.TXT')(t)))
        yield from nav('tab'); yield from goto('DOCS'); yield from nav('enter', 'tab')
        yield from goto('GAMES')
        yield from ask(b'5', 'into itself', ' Copy GAMES to /GAMES/DOCS? (Y/N) ')
        yield from done(b'y', 'not into itself', ' 0 copied to /GAMES/DOCS. 1 left as they were.', other=True,
                        check=lambda t: None if '/GAMES/DOCS/GAMES' not in t else 'a GAMES made inside itself')
        yield from goto('EMPTY.TXT'); yield from nav('tag'); yield from goto('NOTES'); yield from nav('tag')
        yield from goto('LC.PRG'); yield from nav('tag')
        yield from ask(b'5', 'copy 3', ' Copy 3 to /GAMES/DOCS? (Y/N) ')
        yield from done(b'y', '3 copied', ' 3 copied to /GAMES/DOCS.', other=True, wait=20.0,
                        check=lambda t: same('/EMPTY.TXT', '/GAMES/DOCS/EMPTY.TXT')(t) or same('/LC.PRG', '/GAMES/DOCS/LC.PRG')(t) or same('/NOTES', '/GAMES/DOCS/NOTES')(t))
        yield from goto('EMPTY.TXT'); yield from nav('tag'); yield from goto('NOTES'); yield from nav('tag')
        yield from goto('LC.PRG'); yield from nav('tag')
        yield from ask(b'5', 'copy 3 again', ' Copy 3 to /GAMES/DOCS? (Y/N) ')
        yield from ask(b'y', 'there already', ' EMPTY.TXT is there already: replace it? (Y, N, A all of them; Esc stops) ')
        yield from done(b'a', 'all replaced', ' 3 copied to /GAMES/DOCS.', other=True, wait=20.0,
                        check=lambda t: same('/LC.PRG', '/GAMES/DOCS/LC.PRG')(t))
        yield from nav('tab', 'back', 'tab')
        yield from goto('BIG.TXT')
        yield from ask(b'5', 'copy, then Esc', ' Copy BIG.TXT to /GAMES? (Y/N) ')
        yield from ask(b'y', 'there already', ' BIG.TXT is there already: replace it? (Y, N, A all of them; Esc stops) ')
        yield from done(b'\x1b', 'Esc', ' 0 copied to /GAMES. Stopped: Esc.', other=True, check=same('/BIG.TXT', '/GAMES/BIG.TXT'))
    shots = []
    upto = settle
    def gen():
        yield from CFm.start(cr=False, say=lambda *a: None)
        yield from CFm.typed('LC')
        shots.append(('LC', (yield from upto(6.0))))
        for k in plan + ['f1', 'enter']:
            yield ('send', KEYS[k]); shots.append((k, (yield from upto(6.0 if k in ('enter', 'back', 'reload') else 1.0))))
        yield ('send', KEYS['esc']); shots.append(('esc', (yield from CFm.until([CFm.PROMPT], 3.0))))
        yield from CFm.typed('LC')
        shots.append(('lc3', (yield from upto(6.0))))
        for k in plan3:
            yield ('send', KEYS[k]); shots.append(('3' + k, (yield from upto(6.0 if k == 'vend' else 3.0))))
        yield ('send', KEYS['esc']); shots.append(('esc3', (yield from CFm.until([CFm.PROMPT], 3.0))))
        yield from CFm.cmd('CD DOCS')                   # LC from a folder: the left pane there, the right the root
        yield from CFm.typed('LC')
        shots.append(('lc2', (yield from upto(6.0))))
        yield ('send', KEYS['esc']); shots.append(('esc2', (yield from CFm.until([b'LTOS /DOCS> '], 3.0))))
        yield from CFm.cmd('CD /')
        yield from CFm.typed('LC')                      # the jobs that change the card, checked as they go
        yield from session4()
    u, st, text = VC.session(cf, gen(), cap=900_000_000)
    acc, e = '', []
    for i, (k, o) in enumerate(shots):
        acc += o.decode('latin1')
        if k in ('lc3', 'esc3') or k[:1] == '3': break
        if k in ('f1', 'esc', 'lc2', 'esc2'): continue
        if k == 'enter' and i and shots[i - 1][0] == 'f1': k = 'none'
        if k != 'LC' and k != 'none': lc.key(k)
        if os.environ.get('DUMP') == k: print(repr(o[:1500]))
        got, gr, _ = vt100(acc)
        want, wr = lc.screen()
        for r in range(24):
            w, g = want[r], got[r]
            if r == 0:
                if not (g[:74] == w[:74] and re.fullmatch(r'\d\d:\d\d ', g[74:]) and gr[0] == '1' * 80): e.append('after %s, row 1: %r %s' % (k, g, gr[0]))
                continue
            if g != w: e.append('after %s (key %d), row %d:\n      got  %r\n      want %r' % (k, i, r + 1, g, w))
            elif r < 21 and gr[r] != wr[r]: e.append('after %s (key %d), row %d reversed: %s, want %s' % (k, i, r + 1, gr[r], wr[r]))
        if VERB and k in ('LC', 'enter', 'tagall'): print('\n'.join(got))
    report('%d keys: every screen as the model draws it (panes, cursor, frames, counts, the file line)' % (len(plan) + 1), e)
    lc3, e = LC(card), []
    i3 = next(i for i, (k, o) in enumerate(shots) if k == 'lc3')
    acc = shots[i3][1].decode('latin1').split('\x1b[0m\x1b[?25l', 1)[-1]
    for i in range(i3, len(shots)):
        k, o = shots[i]
        if k == 'esc3': break
        if i > i3: acc += o.decode('latin1'); lc3.key(k[1:])
        got, gr, _ = vt100(acc)
        want, wr = lc3.screen()
        for r in range(24):
            w, g = want[r], got[r]
            if r == 0 and lc3.mode != 'view':
                if not (g[:74] == w[:74] and re.fullmatch(r'\d\d:\d\d ', g[74:])): e.append('after %s, row 1: %r' % (k, g))
                continue
            if g != w: e.append('after %s (key %d), row %d:\n      got  %r\n      want %r' % (k[1:], i - i3, r + 1, g, w))
            elif gr[r] != wr[r] and (r < 21 or lc3.mode == 'view'): e.append('after %s (key %d), row %d reversed: %s, want %s' % (k[1:], i - i3, r + 1, gr[r], wr[r]))
        if VERB and k[1:] in ('view', 'info', 'enter', 'vhex'): print('\n'.join(got))
    report('View and Info, %d keys: text pages (wrapped, tabs, CR / LF / CR LF), back, End, Home, hex, a binary file in '
           'hex by itself, an empty file; the box for files, a folder, a program, a STELLAR app' % len(plan3), e)
    report('the jobs, %d keys: Rename (Esc, a name there, not a name), MkDir, Move (2 files, a folder, No, into itself, '
           'both panes the same), Delete (a file to a new /TRASH, Del, an empty folder, a full one, 2 tagged, a name '
           '/TRASH has: the older one goes, in /TRASH itself), Copy (38 KB byte for byte, N, replaced, a folder and '
           'its folder, not into itself, 3 tagged and an empty file, A: all, Esc) - every screen, and the card after each' % st4['n'], e4)
    rc, _ = P2.fsck_free(st4['img']) if 'img' in st4 else (None, None)
    report('the card after the jobs and Copy: fsck_msdos finds nothing wrong (no lost or doubled clusters)', [] if rc == 0 else ['fsck_msdos: %r' % rc])
    hs = next(o for k, o in shots if k == 'f1').decode('latin1')
    hl = vt100(hs)[0]
    if VERB: print('\n'.join(hl))
    e = [] if hl[0].startswith(' LTOS Commander - the keys') and any(l.startswith('  Esc ') for l in hl) else ['%r' % hl[:4]]
    if not hl[-1].strip() == '' or len([l for l in hl if l.strip()]) > 22: e.append('more than a screen')
    lines = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', hs).replace('\r', '\n').split('\n')
    e += ['a line of %d characters: %r' % (len(l), l) for l in lines if len(l) > 79]
    report('F1: the help screen (and a key: the panes again, checked above)', e)
    lc2 = LC(card, '/DOCS')
    g2, r2, _ = vt100(next(o for k, o in shots if k == 'lc2').decode('latin1').split('\x1b[0m\x1b[?25l', 1)[-1])
    w2, wr2 = lc2.screen()
    e = ['row %d:\n      got  %r\n      want %r' % (r + 1, g2[r], w2[r]) for r in range(1, 24) if g2[r] != w2[r] or (r < 21 and r2[r] != wr2[r])]
    report('LC typed in /DOCS: the left pane /DOCS, the right the root', e)
    tail = next(o for k, o in shots if k == 'esc').decode('latin1')
    e = []
    if '\x1b[?25h' not in tail or not tail.endswith('LTOS> '): e.append('the end: %r' % tail[-80:])
    if not next(o for k, o in shots if k == 'esc2').endswith(b'LTOS /DOCS> '): e.append('from /DOCS, the end')
    if u.lost: e.append('%d bytes lost at the UART' % u.lost)
    report('Esc: back to LTOS> with the cursor shown; no byte lost', e)
    print('ALL PASS' if ok else 'SOME FAILED')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
