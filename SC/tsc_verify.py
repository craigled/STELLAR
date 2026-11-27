# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""tsc (Tiny Stellar C, SC.PRG's reference) against scc: each program in TESTS compiled by both, run on V0061.37 in
the simulator (keys typed where a program reads them); the output must be the same, and what the test says.
Then each mistake in BAD must be refused with its line.
    python3 SC/tsc_verify.py [-v]
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import tsc, scc
import opcode_sweep as S

TESTS = {
'arith': ('''
const TEN = 10;
u16 a, b = 7, c;
void main() {
    a = 1000; c = a * 3 + b - TEN / 2;
    printu(c); putc(32); printu(a / 7); putc(32); printu(a % 7); putc(32);
    printu(65535 + 1); putc(32); printu(0 - 1); putc(32); printu(-5 + 6); putc(32);
    printu(0x1F & 0x0C); putc(32); printu(5 | 8); putc(32); printu(6 ^ 3); putc(32); printu(~0 - 65530);
    putc(32); printu(1 << 10); putc(32); printu(40000 >> 3); putc(32); printu(2 + 3 * 4 - (2 + 3) * 4 + 20);
    print("\\r\\n");
}''', b'', '3002 142 6 0 65535 1 12 13 5 5 1024 5000 14\r\n'),
'compare': ('''
u16 x, y;
void main() {
    for (x = 0; x < 4; x++) {
        for (y = 0; y < 4; y++) {
            putc('0' + (x < y) + 2 * (x <= y) + 4 * (x > y));
            putc('a' + (x == y) + 2 * (x != y) + 4 * (x >= y));
        }
        putc(' ');
    }
    if (!(x == 3)) print("not3 "); else print("three? ");
    if (!x) print("zero"); else print("nonzero");
    if (1 && 2 && x == 4) print(" and"); if (0 || x == 9 || 7) print(" or");
    if (x == 4 && (y == 9 || y == 4)) print(" mix");
    printu(3 < 4 && 5); printu(0 || 0); printu(!7); printu(!0);
    print("\\r\\n");
}''', b'', None),
'loops': ('''
u16 i, n, total;
void main() {
    total = 0; i = 0;
    while (1) { i++; if (i > 20) break; if (i % 2 == 1) continue; total += i; }
    printu(total); putc(32);
    for (n = 10; n; n--) { if (n == 3) continue; if (n == 1) break; printu(n); }
    putc(32);
    for (;;) { i--; if (i < 15) break; }
    printu(i);
    i = 5; while (i) i--; printu(i);
    print("\\r\\n");
}''', b'', '110 109876542 140\r\n'),
'funcs': ('''
u16 g;
u16 sq(u16 v) { return v * v; }
u16 add3(u16 x, u16 y, u16 z) { u16 t; t = x + y; t += z; return t; }
u16 gcd(u16 a, u16 b) { u16 t; while (b != 0) { t = a % b; a = b; b = t; } return a; }
void show(u16 v) { printu(v); putc(32); g++; }
u16 isprime(u16 n) { u16 d; if (n < 2) return 0; for (d = 2; d * d <= n; d++) if (n % d == 0) return 0; return 1; }
void main() {
    u16 n;
    g = 0;
    show(sq(12)); show(add3(1, 2, 3)); show(1 + add3(sq(2), sq(3), 10 * sq(1)) * 2);
    show(gcd(1071, 462)); show(sq(3) + sq(4) + sq(add3(1, 1, 1)));
    for (n = 1; n < 30; n++) if (isprime(n)) { printu(n); putc(','); }
    putc(32); printu(g);
    print("\\r\\n");
}''', b'', '144 6 47 21 34 2,3,5,7,11,13,17,19,23,29, 5\r\n'),
'arrays': ('''
const N = 10;
u16 t[N], i, s, sq[5];
void main() {
    for (i = 0; i < N; i++) t[i] = i * i + 1;
    t[3] += 100; t[4]++; t[5]--; t[6] *= 2;
    s = 0; for (i = 0; i < N; i++) s += t[i];
    printu(s); putc(32); printu(t[3]); putc(32); printu(t[t[1]]);
    for (i = 0; i < 5; i++) sq[i] = t[i] - 1;
    putc(32); printu(sq[4] + sq[3]);
    print("\\r\\n");
}''', b'', None),
'chars': ('''
u16 c, n;
void main() {
    print("type: ");
    n = 0;
    while (1) {
        c = getc();
        if (c == '\\r') break;
        if (c >= 'a' && c <= 'z') c = c - 32;
        putc(c); n++;
    }
    print(" = "); printu(n); print(" keys\\r\\n");
    print("tab\\there \\\\ \\'q\\' \\"d\\"\\r\\n");
    halt();
    print("not this");
}''', b'Hello, 1802!\r', 'type: HELLO, 1802! = 12 keys\r\ntab\there \\ \'q\' "d"\r\n'),
'shadow': ('''
u16 v = 5;
void f() { u16 v; v = 9; printu(v); }
void main() { f(); printu(v); if (v == 5) { u16 w = v + 1; printu(w); } print("\\r\\n"); }''', b'', '956\r\n'),
'hwio': ('''
const ON = 1;
void main() {
    u16 t, y;
    q(ON); q(0); q(2);
    printu(ef(1)); printu(ef(4)); if (ef(2) || ef(3)) print("!");
    if (rtc(7)) { t = rtc(0) + rtc(1) + rtc(2) + rtc(3) + rtc(4) + rtc(5); y = rtc(6); printu(t); putc(' '); printu(y); }
    else waitef(4);
    rtc(5); ef(3);
    print("\\r\\n");
}''', b'', None),
}

BAD = [('u16 a; void main() { a = b; }', 1, 'b not defined'),
       ('void main() {\n  print("x);\n}', 2, 'no closing "'),
       ('void f() { f(); }\nvoid main() { }', 1, 'calls itself'),
       ('void main() { g(); }\nvoid g() { }', 1, 'no function g()'),
       ('u16 a;\nu16 a;\nvoid main() { }', 2, 'a defined twice'),
       ('void main() { u16 x; x = (1 + 2; }', 1, ') expected'),
       ('u16 x;\nvoid main() { x = 1 << x; }', 2, 'not a constant'),
       ('void main() { break; }', 1, 'break outside a loop'),
       ('u16 f() { return 1; }\nvoid main() { u16 x; x = 1; }\nvoid g() { return 5; }', 3, 'returns no value'),
       ('u16 t[3];\nvoid main() {\n  t = 4;\n}', 3, '[ expected'),
       ('void main() { u16 x; x = 99999; }', 1, 'over 65535'),
       ('u16 a;', 1, 'no main()'),
       ('void main() {\n  u16 t[3];\n}', 2, 'arrays are declared outside functions'),
       ('void main() { u16 x; x = ef(5); }', 1, 'n out of range'),
       ('void main() {\n  printu(rtc(8));\n}', 2, 'n out of range'),
       ('void main() { q(4); }', 1, 'n out of range'),
       ('u16 n = 2;\nvoid main() { waitef(n); }', 2, 'not a constant'),
       ('void main() { u16 x; x = waitef(4); }', 1, 'waitef() gives no value')]


def run(img_pokes, keys):
    c = S.boot(bytes(S.image('37')), img_pokes, keys=keys)
    for _ in range(60_000_000):
        if not c.step() or c.R[c.P] == S.EXIT_IDL + 1: break
    return bytes(c.io_out.get(3, [])).decode('latin1'), c.M[0x304F]


def pokes_tsc(stl):
    img = stl[512:512 + 3072]
    return [(0x4000 + i, b) for i, b in enumerate(img)] + [(0x5000, 0), (0x6000, 0), (0x7000, 0)]


def pokes_scc(src):
    c0, em, labels, data = scc.compile_source(src, 'prog')
    return [(a + i, b) for a, bs, _, _ in em for i, b in enumerate(bs)] + \
           [(0x4000 + a + i, b) for a, d in data.items() for i, b in enumerate(d)] + [(0x5000, 0), (0x6000, 0), (0x7000, 0)]


def main():
    v = '-v' in sys.argv
    ok = True
    for name, (src, keys, want) in TESTS.items():
        e = []
        stl = tsc.compile_text(src)
        got, err = run(pokes_tsc(stl), keys)
        ref, err2 = run(pokes_scc(src), keys)
        if got != ref: e.append('tsc %r\n        scc %r' % (got[:300], ref[:300]))
        if want is not None and got != want: e.append('want %r' % want)
        if err: e.append('VM error $%02X' % err)
        if v: print('   ', repr(got))
        print('%-10s %s' % (name, 'OK (%d bytes of code)' % (stl[512:].index(b'\xF0\x00\x00') + 3) if not e else 'FAIL'))
        for x in e: print('    ' + x)
        ok &= not e
    e = []
    for src, line, words in BAD:
        try: tsc.compile_text(src); e.append('taken: %r' % src)
        except tsc.Error as x:
            if x.line != line or words not in x.msg: e.append('%r: line %d: %s (want %d: %s)' % (src[:30], x.line, x.msg, line, words))
    print('%-10s %s' % ('mistakes', 'OK (%d)' % len(BAD) if not e else 'FAIL'))
    for x in e: print('    ' + x)
    ok &= not e
    print('\nTSC: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
