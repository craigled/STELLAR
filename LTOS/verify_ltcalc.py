# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTCALC on the simulated Elf2K, read the way a terminal shows it. A model of the sheet here (whole numbers of
hundredths, in Python) says what every cell must show: hand-picked sums, random sheets of formulas, loops; then the
keys, saving and opening (the file read on the Mac, files made by hand), and how little is sent when one cell changes.

    python3 LTOS/verify_ltcalc.py [-v]
"""
import os, random, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import build
LIM = 2 ** 31
UP, DOWN, RIGHT, LEFT, ESC = b'\x1b[A', b'\x1b[B', b'\x1b[C', b'\x1b[D', b'\x1b'
BAR = '^S save'


class Screen:
    """A VT100, as much of it as LTCALC uses."""
    def __init__(s, data=b''):
        s.c = [[' '] * 80 for _ in range(24)]; s.rev = [[False] * 80 for _ in range(24)]; s.r = s.k = 0; s.inv = False
        s.feed(data)

    def feed(s, d):
        i = 0
        while i < len(d):
            b = d[i]
            if b == 0x1b:
                m = re.compile(rb'\x1b\[([0-9;]*)([A-Za-z])').match(d, i)
                if not m: i += 1; continue
                i = m.end(); a, f = m.group(1).decode(), m.group(2)
                if f == b'H':
                    p = (a.split(';') + ['1', '1'])[:2]; s.r = int(p[0] or 1) - 1; s.k = int(p[1] or 1) - 1
                elif f == b'J':
                    s.c = [[' '] * 80 for _ in range(24)]; s.rev = [[False] * 80 for _ in range(24)]
                elif f == b'K':
                    for x in range(s.k, 80): s.c[s.r][x] = ' '; s.rev[s.r][x] = False
                elif f == b'm': s.inv = a == '7'
                continue
            i += 1
            if b == 8: s.k = max(0, s.k - 1)
            elif b == 13: s.k = 0
            elif b == 10: s.r = min(23, s.r + 1)
            elif s.r < 24 and s.k < 80:
                s.c[s.r][s.k] = chr(b); s.rev[s.r][s.k] = s.inv; s.k += 1

    def row(s, n): return ''.join(s.c[n - 1]).rstrip()
    def cell(s, name):
        c, r = ord(name[0]) - 65, int(name[1:]) - 1
        return ''.join(s.c[3 + r][4 + 9 * c:13 + 9 * c])
    def mark(s):
        return [(chr(65 + c) + str(r + 1)) for r in range(20) for c in range(8) if s.rev[3 + r][4 + 9 * c]]


def show(v):
    """A value's text as the program makes it."""
    a = abs(v); return '%s%d.%02d' % ('-' if v < 0 else '', a // 100, a % 100)


def cellshow(v):
    if v is None: return ' ' * 9
    if v == 'ERR': return '      ERR'
    t = show(v)
    return t.rjust(9) if len(t) <= 9 else '#' * 9


class Err(Exception): pass


class Sheet:
    """The model: {name: text} -> {name: value in hundredths, 'ERR', None, or text}."""
    def __init__(s, cells): s.cells = cells; s.val = {}; s.busy = set()

    def literal(s, t):
        m = re.fullmatch(r'([-+]?)(\d*)(?:\.(\d*))?', t)
        if not m or not (m.group(2) or m.group(3)): return None
        return (m.group(1) == '-', m.group(2) or '0', (m.group(3) or ''))

    def num(s, whole, frac):
        v = int(whole) * 100 + int((frac + '00')[:2])
        if len(frac) > 2 and frac[2] >= '5': v += 1
        if v >= LIM: raise Err()
        return v

    def get(s, n):
        if n in s.val:
            if s.val[n] == 'ERR': raise Err()
            return s.val[n]
        if n in s.busy: raise Err()
        t = s.cells.get(n)
        if t is None: return None
        s.busy.add(n)
        try:
            if t.startswith('='):
                s.p, s.t = 0, t[1:].upper()
                saved = (s.p, s.t)
                v = s.expr()
                s.ws()
                if s.p != len(s.t): raise Err()
            else:
                l = s.literal(t)
                if l is None: s.val[n] = t; s.busy.discard(n); return t
                v = s.num(l[1], l[2]); v = -v if l[0] else v
        except Err:
            s.val[n] = 'ERR'; s.busy.discard(n); raise
        s.val[n] = v; s.busy.discard(n)
        return v

    def ws(s):
        while s.p < len(s.t) and s.t[s.p] == ' ': s.p += 1
    def peek(s):
        s.ws(); return s.t[s.p] if s.p < len(s.t) else ''

    def cv(s, n):
        p, t = s.p, s.t
        v = s.get(n)
        s.p, s.t = p, t
        return v if isinstance(v, int) else (0 if True else None)

    def expr(s):
        v = s.term()
        while s.peek() in ('+', '-'):
            o = s.peek(); s.p += 1; w = s.term(); v = v + w if o == '+' else v - w
            if abs(v) >= LIM: raise Err()
        return v

    def term(s):
        v = s.unary()
        while s.peek() in ('*', '/'):
            o = s.peek(); s.p += 1; w = s.unary()
            if o == '*': q = (abs(v * w) + 50) // 100
            else:
                if w == 0: raise Err()
                q = (2 * abs(v) * 100 + abs(w)) // (2 * abs(w))
            if q >= LIM: raise Err()
            v = -q if (v < 0) != (w < 0) else q
        return v

    def unary(s):
        c = s.peek()
        if c == '-': s.p += 1; return -s.unary()
        if c == '+': s.p += 1; return s.unary()
        if c == '(':
            s.p += 1; v = s.expr()
            if s.peek() != ')': raise Err()
            s.p += 1; return v
        m = re.compile(r'(\d*)(?:\.(\d*))?').match(s.t, s.p)
        if c and (c.isdigit() or c == '.'):
            s.p = m.end(); return s.num(m.group(1) or '0', m.group(2) or '')
        m = re.compile(r'[A-H]\d+').match(s.t, s.p)
        if m and s.valid(m.group()):
            s.p = m.end(); return s.cv(m.group())
        m = re.compile(r'(SUM|AVG|MIN|MAX|COUNT)\(').match(s.t, s.p)
        if not m: raise Err()
        s.p = m.end(); f = m.group(1); vals = []
        while True:
            a = s.ref(); b = a
            if s.peek() == ':': s.p += 1; b = s.ref()
            for r in range(min(a[1], b[1]), max(a[1], b[1]) + 1):
                for k in range(min(a[0], b[0]), max(a[0], b[0]) + 1):
                    p, t = s.p, s.t
                    v = s.get('%s%d' % ('ABCDEFGH'[k], r))
                    s.p, s.t = p, t
                    if isinstance(v, int):
                        vals.append(v)
                        if abs(sum(vals)) >= LIM: raise Err()
            if s.peek() != ',': break
            s.p += 1
        if s.peek() != ')': raise Err()
        s.p += 1
        if f == 'SUM': return sum(vals)
        if f == 'COUNT': return len(vals) * 100
        if f == 'MIN': return min(vals) if vals else 0
        if f == 'MAX': return max(vals) if vals else 0
        if not vals: raise Err()
        t = sum(vals); q = (2 * abs(t) + len(vals)) // (2 * len(vals))
        return -q if t < 0 else q

    def valid(s, n): return 1 <= int(n[1:]) <= 20
    def ref(s):
        s.ws(); m = re.compile(r'[A-H]\d+').match(s.t, s.p)
        if not m or not s.valid(m.group()): raise Err()
        s.p = m.end(); return (ord(m.group()[0]) - 65, int(m.group()[1:]))

    def solve(s):
        for n in s.cells:
            try: s.get(n)
            except Err: pass
        return s.val


def typed(cells):
    """The keys that type a sheet in: the cells in order, going there with the arrows from A1."""
    k, r, c = b'', 0, 0
    for n, t in cells.items():
        c2, r2 = ord(n[0]) - 65, int(n[1:]) - 1
        k += (DOWN * (r2 - r) if r2 > r else UP * (r - r2)) + (RIGHT * (c2 - c) if c2 > c else LEFT * (c - c2))
        k += t.encode() + b'\r'; r, c = r2 + 1, c2
        if r > 19: r = 19
    return k


def chunks(cells):
    """typed(), a cell at a time: each waits until LTCALC is idle (it writes row 1 only then), as fast fingers would."""
    out, r, c = [], 0, 0
    for n, t in (cells.items() if isinstance(cells, dict) else cells):
        c2, r2 = ord(n[0]) - 65, int(n[1:]) - 1
        k = (DOWN * (r2 - r) if r2 > r else UP * (r - r2)) + (RIGHT * (c2 - c) if c2 > c else LEFT * (c - c2)) + t.encode() + b'\r'
        r, c = min(r2 + 1, 19), c2
        out.append((BAR if not out else IDLE, k))
    return out


IDLE = '\x1b[1;1H'


def run(cf, name, steps, cap=2_500_000_000):
    """LTCALC name, then steps: [(text to wait for, keys)], ending at the prompt. -> state, the bytes it sent."""
    later = [('LTOS> ', b'LTCALC %s\r' % name)] + steps + [('LTOS> ', b'MON\r')]
    b = V.Elf2K(cf, keys=b'', later=later)
    st = b.boot_rom(cap)
    d = bytes(b.u.out)
    i = d.find(b'LTCALC %s' % name)
    return st, d[i:], b


def quit_(*saved):
    return [(BAR, ESC)] if not saved else [('Saved.', ESC)]


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + str(x)) for x in e[:12]]; ok &= not e
    only = [a for a in sys.argv[1:] if not a.startswith('-')]
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed_full(mem, n)
    base = V.image(cf, n)
    prg = build.prg('ltcalc')
    def put(m):
        d = os.path.join(m, 'BIN'); os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'LTCALC.PRG'), 'wb').write(prg)
    base, _ = P2.mac(base, put)

    def fresh(files=None):
        img = base
        if files:
            def put(m):
                for k, v in files.items():
                    p = os.path.join(m, k); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'wb').write(v)
            img, _ = P2.mac(base, put)
        P1.load_image(cf, img)

    def sheet_session(cells, tag, e, then=()):
        """Type a sheet in and compare every cell with the model."""
        fresh()
        st, d, b = run(cf, b'', chunks(list(cells.items()) + list(then)) + [(IDLE, b'\x13'), ('Save as: ', b'T\r'), ('Saved.', ESC)])
        if st != 'stop': e.append('%s: %s %r' % (tag, st, d[-200:])); return None
        s = Screen(d[d.find(b'\x1b[2J'):d.rfind(b'\x1b[2J')])
        cells = {**cells, **dict(then)}
        want = Sheet(dict(cells)).solve()
        for r in range(1, 21):
            for c in 'ABCDEFGH':
                nm = '%s%d' % (c, r); v = want.get(nm)
                w = (v + ' ' * 9)[:9] if isinstance(v, str) and v != 'ERR' else cellshow(v)
                if s.cell(nm) != w: e.append('%s %s %r: shows %r, should be %r' % (tag, nm, cells.get(nm), s.cell(nm), w))
        return s, want, b

    # 1. the look of it
    if not only or '1' in only:
        e = []
        fresh()
        st, d, b = run(cf, b'', [(BAR, b'12.5\r' + b'Rent\r' + UP + UP + RIGHT + b'=A1*2\r'), ('25.00', ESC), ('Quit without', b'Y')])
        s = Screen(d[d.find(b'\x1b[2J'):d.rfind(b'\x1b[2J')])
        if st != 'stop': e.append('%s %r' % (st, d[-300:]))
        if s.row(3).split() != list('ABCDEFGH'): e.append('headings: %r' % s.row(3))
        if [s.row(3 + r)[:2].strip() for r in range(1, 21)] != [str(r) for r in range(1, 21)]: e.append('row numbers')
        for k, w in (('A1', '    12.50'), ('A2', 'Rent     '), ('B1', '    25.00')):
            if s.cell(k) != w: e.append('%s: %r' % (k, s.cell(k)))
        if s.mark() != ['B2']: e.append('the mark: %s' % s.mark())
        if '(no name)*' not in s.row(24): e.append('row 24: %r' % s.row(24))
        if '-v' in sys.argv: print('\n'.join(s.row(r) for r in range(1, 25)))
        report('The screen: headings, row numbers, numbers to the right, text to the left, the mark', e)
    def later_file(path):
        got = {}
        def rd(m):
            p = os.path.join(m, path)
            got['b'] = open(p, 'rb').read() if os.path.exists(p) else None
        P2.mac(V.image(cf, n), rd)
        return got['b']

    # 2. the sums, worked by hand
    if not only or '2' in only:
        e = []
        HAND = [('5', '5.00'), ('-3.5', '-3.50'), ('.25', '0.25'), ('1.005', '1.01'), ('1.004', '1.00'), ('0', '0.00'), ('+7', '7.00'),
                ('=1+2*3', '7.00'), ('=(1+2)*3', '9.00'), ('=10/4', '2.50'), ('=1/3', '0.33'), ('=2/3', '0.67'), ('=-2*3', '-6.00'),
                ('=2*-3', '-6.00'), ('=-2*-3', '6.00'), ('=1.5*1.5', '2.25'), ('=0.05*0.1', '0.01'), ('=0.01*0.01', '0.00'), ('=-0.05*0.1', '-0.01'),
                ('=7-10', '-3.00'), ('=100-0.01', '99.99'), ('=1000/3', '333.33'), ('= 1 + 2 ', '3.00'), ('=2*(3+(4-1))', '12.00'), ('=-(1+2)', '-3.00'),
                ('=99999.99', '#########'), ('=999999.99', '999999.99'), ('=-99999.99', '-99999.99'), ('=-999999.99', '#########'), ('=1000000', '#########'),
                ('=100000*100000', 'ERR'), ('=1/0', 'ERR'), ('=21474836.47+0.01', 'ERR'), ('=-21474836.47-0.01', 'ERR'), ('=21474836.48', 'ERR'), ('21474836.48', 'ERR'),
                ('=1+', 'ERR'), ('=(1', 'ERR'), ('=1)', 'ERR'), ('=Z1', 'ERR'), ('=A21', 'ERR'), ('=A0', 'ERR'), ('=', 'ERR'), ('=FOO(A1)', 'ERR'), ('=SUM(A1', 'ERR'), ('=1 2', 'ERR'),
                ('=4634.17*4634.17', 'ERR'), ('=4634*4634', 'ERR'), ('=46.34*46.34', '2147.40'), ('=123456.78/1.5', '82304.52'), ('=1000000/3.33', '300300.30')]
        HAND = [(t, ('#########' if w == '=99999.99' else w)) for t, w in HAND]
        fix = {'=99999.99': '99999.99', '=4634*4634': '21473956.00'.replace('21473956.00', '#########')}
        cols = 'ABCDEFGH'
        for part in range(0, len(HAND), 40):
            cells = {}
            for i, (t, w) in enumerate(HAND[part:part + 40]):
                cells['%s%d' % ('CDEF'[i // 20], i % 20 + 1)] = t
            r = sheet_session(cells, 'hand', e)
            if r:
                for i, (t, w) in enumerate(HAND[part:part + 40]):
                    nm = '%s%d' % ('CDEF'[i // 20], i % 20 + 1)
                    w = fix.get(t, w)
                    if r[0].cell(nm).strip() != w: e.append('%s %r: shows %r, by hand %r' % (nm, t, r[0].cell(nm), w))
        report('%d sums worked by hand: rounding, signs, brackets, too big, bad formulas' % len(HAND), e)

    # 3. functions, references, order, loops
    if not only or '3' in only:
        e = []
        cells = {'A1': '10', 'A2': '20.5', 'A3': 'text', 'A5': '-4', 'B1': '=SUM(A1:A5)', 'B2': '=AVG(A1:A5)', 'B3': '=MIN(A1:A5)', 'B4': '=MAX(A1:A5)',
                 'B5': '=COUNT(A1:A5)', 'B6': '=sum(a5:a1)', 'B7': '=SUM(A1,A2,A5)', 'B8': '=SUM(A1:A2,A5:A5)+1', 'B9': '=AVG(H1:H3)', 'B10': '=MIN(H1:H3)',
                 'B11': '=COUNT(H1:H3)', 'B12': '=SUM(A1:B1)', 'B13': '=A3+1', 'B14': '=H9*2', 'C1': '=D1+1', 'D1': '=E1+1', 'E1': '=F1+1', 'F1': '=G1+1', 'G1': '5',
                 'C2': '=D2', 'D2': '=C2', 'E2': '=D2+1', 'C3': '=C3', 'C4': '=SUM(C3:C5)', 'D3': '=SUM(A1:H1)*0', 'E3': '=SUM(D3:D3)', 'F3': '=SUM(A1:A5)/COUNT(A1:A5)',
                 'C6': '1', 'C7': '=C6+1', 'C8': '=C7+1', 'C9': '=C8+C7', 'C10': '=MAX(C6:C9)*MIN(C6:C9)', 'D6': '=COUNT(A1:H5)'}
        r = sheet_session(cells, 'functions', e)
        if r:
            w = {'B1': '26.50', 'B2': '8.83', 'B3': '-4.00', 'B4': '20.50', 'B5': '3.00', 'B9': 'ERR', 'B10': '0.00', 'B11': '0.00', 'C1': '9.00', 'C2': 'ERR', 'D2': 'ERR', 'E2': 'ERR', 'C3': 'ERR', 'C4': 'ERR'}
            for k, v in w.items():
                if r[0].cell(k).strip() != v: e.append('%s: %r, by hand %s' % (k, r[0].cell(k), v))
        r = sheet_session({'A1': '1', 'A2': '=A1+1', 'A3': '=A2+1', 'A4': '=SUM(A1:A3)', 'B1': '=C1', 'C1': '=B1', 'D1': '=C1+1', 'E1': '=A4', 'F1': '=SUM(A3:A4)', 'G1': '=1/A1'}, 'changes', e,
                          [('A1', '2'), ('C1', '5'), ('A2', '10'), ('A1', '0'), ('A3', '=A4'), ('A3', '3')])
        if r and (r[0].cell('D1').strip() != '6.00' or r[0].cell('B1').strip() != '5.00' or r[0].cell('G1').strip() != 'ERR'): e.append('changes: %r' % r[0].cell('D1'))
        report('SUM AVG MIN MAX COUNT, ranges either way, lists; formulas needing later cells; loops show ERR', e)

    # 4. random sheets against the model
    if not only or '4' in only:
        e = []
        rnd = random.Random(1802)
        names = ['%s%d' % (c, r) for r in range(1, 21) for c in 'ABCDEFGH']
        def num():
            return rnd.choice(['%d' % rnd.randint(0, 9999), '%d.%02d' % (rnd.randint(0, 999), rnd.randint(0, 99)), '%d.%d' % (rnd.randint(0, 99), rnd.randint(0, 9)),
                               '0.0%d' % rnd.randint(1, 9), '%d' % rnd.randint(100000, 9999999)])
        def ex(d, used):
            k = rnd.randint(0, 9 if d else 3)
            if k == 0: return num()
            if k <= 3: return rnd.choice(used)
            if k == 4: return '(' + ex(d - 1, used) + ')'
            if k == 5: return '-' + ex(d - 1, used)
            if k == 6:
                a, b = rnd.choice(names), rnd.choice(names)
                return '%s(%s:%s)' % (rnd.choice(['SUM', 'AVG', 'MIN', 'MAX', 'COUNT']), a, b)
            return ex(d - 1, used) + rnd.choice(['+', '-', '*', '/']) + ex(d - 1, used)
        for seed in range(3):
            pick = rnd.sample(names, 44); cells = {}
            for i, nm in enumerate(sorted(pick, key=names.index)):
                t = rnd.random()
                if t < .35: cells[nm] = rnd.choice(['', '-']) + num()
                elif t < .42: cells[nm] = rnd.choice(['Rent', 'Total', 'a', 'Long text here'])
                else:
                    x = '=' + ex(3, pick)
                    cells[nm] = x if len(x) <= 58 else '=1+1'
            forms = [k for k in cells if cells[k].startswith('=')]
            then = [(k, rnd.choice(['', '-']) + num()) for k in rnd.sample(sorted(cells), 8)] + [(k, '=' + ex(2, pick)) for k in rnd.sample(forms, 4)]
            sheet_session(cells, 'random %d' % seed, e, [(k, v if len(v) <= 58 else '7') for k, v in then])
        report('3 random sheets of 44 cells, 12 cells then changed, the screen against the model in all 160 cells', e)

    # 5. the keys
    if not only or '5' in only:
        e = []
        fresh()
        st, d, b = run(cf, b'', [(BAR, b'11\r22'), ('\x1b[K2', ESC), ('A2 ', b'33' + UP), ('A1 11', RIGHT + b'44\t55' + LEFT),
                                 ('B1 44', LEFT + LEFT + UP + b'\x05'), ('> 11', b'\x7f1\x7f7\r'), ('17.00', UP + b'\x08'),
                                 ('A1 ', DOWN * 30), ('A20 ', RIGHT * 12), ('H20 ', UP * 25), ('H1 ', LEFT * 12),
                                 ('A1 ', b'\t' + b'x' * 70 + b'\r'), ('xxxxxxxxx', UP), ('B1 xxx', b'\x1b[3~'), (IDLE, b'\x1b[5~\x1b[H\x1bx\x03' + ESC), ('Quit without', b'N'),
                                 ('B1 ', ESC), ('Quit without', b'Y')])
        if b'B1 ' + b'x' * 60 + b'\x1b' not in d: e.append('not 60 characters')
        if st != 'stop': e.append('%s %r' % (st, d[-200:]))
        # the screen just before the last Esc
        s = Screen(d[d.find(b'\x1b[2J'):d.rfind(b'\x1b[2J')])
        for k, w in (('A1', '         '), ('A2', '    33.00'), ('B1', '         '), ('C1', '    55.00')):
            if s.cell(k) != w: e.append('%s: %r' % (k, s.cell(k)))
        if s.mark() != ['B1']: e.append('the mark: %s' % s.mark())
        if d.rfind(b'\x1b[2J') < 0: e.append('did not leave')
        report('Enter, Tab, arrows take an entry; Esc drops it; ^E edits; Backspace and Delete empty; the edges stop; 60 characters at most', e)

    # 6. saving and opening
    if not only or '6' in only:
        e = []
        fresh()
        st, d, b = run(cf, b'BUDGET', [(BAR, b'Rent\r12.5\r=A2*2\r' + RIGHT + b'x\r' + b'\x13'), ('Saved.', ESC)])
        f = later_file('BUDGET.CAL')
        if f != b'A1 Rent\nB4 x\nA2 12.5\nA3 =A2*2\n'.replace(b'B4 x\nA2 12.5\nA3 =A2*2\n', b'A2 12.5\nA3 =A2*2\nB4 x\n'): e.append('the file: %r' % f)
        if 'BUDGET.CAL*' in Screen(d[:d.rfind(b'\x1b[2J')]).row(24): e.append('the star after saving')
        st, d, b = run(cf, b'BUDGET.CAL', [(BAR, DOWN * 1 + b'20\r'), ('40.00', b'\x13'), ('Saved.', ESC)])
        s = Screen(d[d.find(b'\x1b[2J'):d.rfind(b'\x1b[2J')])
        if s.cell('A3') != '    40.00' or s.cell('A1') != 'Rent     ' or s.cell('B4') != 'x        ': e.append('opened: %r %r' % (s.cell('A3'), s.cell('A1')))
        f = later_file('BUDGET.CAL')
        if f != b'A1 Rent\nA2 20\nA3 =A2*2\nB4 x\n': e.append('saved again: %r' % f)
        report('A name gets .CAL; the file is plain lines in cell order; opened, changed, saved again', e)

        e = []
        hand = b'c3 =A1+B1\r\nB1 2.5\r\nnot a cell\n\n A1 9\nZ9 8\nA99 7\nA1 5\nH20 =C3*2'
        fresh({'HAND.CAL': hand, 'DATA/S.CAL': b'A1 77\n', 'BIG.CAL': b'A1 1\n' * 1500})
        st, d, b = run(cf, b'HAND.CAL', [(BAR, ESC)])
        s = Screen(d[d.find(b'\x1b[2J'):d.rfind(b'\x1b[2J')])
        for k, w in (('C3', '     7.50'), ('H20', '    15.00'), ('A1', '     5.00')):
            if s.cell(k) != w: e.append('hand %s: %r' % (k, s.cell(k)))
        st, d, b = run(cf, b'HAND.CAL', [(BAR, b'\x13'), ('Saved.', ESC)])
        if later_file('HAND.CAL') != hand + b'\n': e.append('a file by hand saved untouched: %r' % later_file('HAND.CAL'))
        st, d, b = run(cf, b'/DATA/S', [(BAR, b'\r5\r\x13'), ('Saved.', ESC)])
        if later_file('DATA/S.CAL') != b'A1 77\nA2 5\n': e.append('in a folder: %r' % later_file('DATA/S.CAL'))
        if later_file('S.CAL') is not None: e.append('saved in the wrong folder')
        st, d, b = run(cf, b'BIG', [])
        if b'cannot be opened' not in d: e.append('too big: %r' % d[-100:])
        st, d, b = run(cf, b'', [(BAR, b'1\r\x0f'), ('Lose your', b'N'), ('A2 ', b'\x0f'), ('Lose your', b'Y'), ('Open: ', b'NOPE\r'), ('no such file', b'\x0f'), ('Lose your', b'Y'), ('Open: ', b'BIG\r'),
                                 ('cannot be opened', b'\x0f'), ('Lose your', b'Y'), ('Open: ', b'*\r'), ('not a file name', b'x'), ('A2 ', b'\x0f'), ('Lose your', b'Y'), ('Open: ', b'DATA/S\r'), ('S.CAL', b'\x01'),
                                 ('Save as: ', b'/COPY\r'), ('Saved.', b'\x01'), ('Save as: ', b'COPY\r'), ('Replace', b'N'), ('A1', b'\x01'), ('Save as: ', b'COPY.CAL\r'), ('Replace', b'Y'), ('Saved.', ESC)])
        if st != 'stop': e.append('the questions: %s %r' % (st, d[-200:]))
        if later_file('COPY.CAL') != b'A1 77\nA2 5\n': e.append('save as: %r' % later_file('COPY.CAL'))
        st, d, b = run(cf, b'', [(BAR, b'\x13'), ('Save as: ', b'EMPTY\r'), ('Saved.', ESC)])
        if later_file('EMPTY.CAL') != b'': e.append('an empty sheet: %r' % later_file('EMPTY.CAL'))
        st, d, b = run(cf, b'EMPTY', [(BAR, b'3\r'), ('A2', ESC), ('Quit', b'Y')])
        if st != 'stop' or b'EMPTY.CAL' not in d: e.append('an empty file opened: %s' % st)
        code = P2.fsck_free(V.image(cf, n))
        if code and code[0]: e.append('fsck: %r' % (code,))
        report('A file made by hand (any order, CR LF, no last LF, bad lines); folders; too big; every question; an empty sheet; fsck', e)

    # 7. the sheet full, and how much is sent
    if not only or '7' in only:
        e = []
        room = 0x6BFE - build.assemble('ltcalc')[1]['POOL']
        pad = b''.join(b'%s%d %s\n' % (bytes([65 + i % 8]), i // 8 + 1, b'y' * 58) for i in range(room // 64 - 1))
        pad += b'H20 ' + b'y' * (room - len(pad) - 12) + b'\n'
        fresh({'FULL.CAL': pad})
        st, d, b = run(cf, b'FULL', [(BAR, DOWN * 19 + b'hello there\r'), ('sheet is full', UP + b'\x08'), ('^S', b'abc\r'), ('abc', ESC), ('Quit', b'Y')])
        if b'sheet is full' not in d: e.append('no message: %d %r' % (len(pad), d[-200:]))
        fresh()
        cells = {'A%d' % r: str(r) for r in range(1, 21)}
        cells.update({'B%d' % r: '=A%d*1.5' % r for r in range(1, 21)})
        cells.update({'C1': '=SUM(B1:B20)', 'C2': '=AVG(A1:A20)'})
        fresh()
        class T(list):
            def append(s, x): s.at.append(b.c.steps if hasattr(b.c, 'steps') else b.steps); list.append(s, x)
        st_ = [('LTOS> ', b'LTCALC\r')] + chunks(cells) + [(IDLE, b'\x13'), ('Save as: ', b'R\r'), ('Saved.', UP * 3 + LEFT * 2 + b'7Q'), ('\x1b[KQ', b'\x7f\r'), ('324.00', ESC), ('Quit', b'Y'), ('LTOS> ', b'MON\r')]
        b = V.Elf2K(cf, keys=b'', later=st_)
        o = T(); o.at = []; b.u.out = o
        st = b.boot_rom(2_500_000_000)
        dd = bytes(o); i = dd.rfind(b'\x08 \x08') + 3
        j = dd.find(b'Quit', i)
        sent = dd[i:j]
        gap = max(o.at[x + 1] - o.at[x] for x in range(i, j - 1))
        tot = o.at[j - 1] - o.at[i]
        print('    one cell changed, 3 cells follow: %d bytes sent, %.2f s on the Elf2K (the longest quiet %.2f s)' % (len(sent), (tot + 0) / 110000, gap / 110000))
        if gap > 0.6 * 110000: e.append('too slow')
        if len(sent) > 260: e.append('%d bytes sent: %r' % (len(sent), sent))
        s = Screen(dd[dd.find(b'\x1b[2J'):j])
        if s.cell('A1').strip() != '7.00' or s.cell('B1').strip() != '10.50' or s.cell('C1').strip() != '324.00': e.append('after: %r %r %r' % (s.cell('A1'), s.cell('B1'), s.cell('C1')))
        report('A full sheet says so and keeps working; changing one cell sends only what changed', e)
    print('ok' if ok else 'FAILED')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
