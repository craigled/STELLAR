# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the terminal / number / input / RTC / memory built-ins (examples/builtins.sc) on V0061.36 as
flashed (the docx), with the DS12887 model (Firmware-Math/rtc_verify.py) and a strict VT100
screen: the compiled program is run, a name is typed (with a Backspace, and longer than allowed), and
every row it drew is checked - and the chip and memory afterwards. Then a RERUN without reloading.

    python3 builtins_verify.py
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import scc
import opcode_sweep as S
import rtc_verify as V
import litewriter2_verify as LW

LW.TROWS = 26
class VT(LW.VT100):
    def esc(s, e):
        if e in ('\x1b[?25l', '\x1b[?25h'): s.cursor = e.endswith('h'); s.cursors.append(s.cursor); return
        super().esc(e)

BIOS = {0x00: 7, 0x02: 23, 0x04: 14, 0x06: 7, 0x07: 4, 0x08: 10, 0x09: 54,      # 2026-10-04 14:23:07 (Sunday = 7)
        0x0A: 0x20, 0x0B: 0x07, 0x0C: 0x10, 0x0D: 0x80}


def run(pokes, keys, mem=None, regs=BIOS):
    img = bytearray(S.image('37'))
    c = S.boot(bytes(mem), [], keys=b'') if mem else S.boot(bytes(img), pokes, keys=b'')
    rtc = V.DS12887(c)
    for n, v in regs.items(): rtc.r[n] = v
    c.io_in[3] = V.Port3In(c.io_in[3], c.io_out[2], rtc)
    c.io_out[3] = V.Port3Out(c.io_out[2], rtc)
    c.io_in[3].u.q.extend(keys)
    r = V.run(c, 20_000_000)
    vt = VT(); vt.cursors = []; vt.feed(bytes(c.io_out[3]).decode('latin1'))
    return c, rtc, vt, r


def main():
    src = os.path.join(HERE, 'examples', 'builtins.sc')
    c0, em, labels, data = scc.compile_source(open(src).read(), 'builtins')
    pokes = [(a + i, b) for a, bs, _, _ in em for i, b in enumerate(bs)] + \
            [(0x4000 + a + i, b) for a, d in data.items() for i, b in enumerate(d)]
    ok = True
    keys = b'Craiq\x08g Ledbetter-much-too-long\r'
    c, rtc, vt, r = run(pokes, keys)
    row = lambda n: vt.row(n - 1)
    rev = lambda n, a, b: all(vt.a[n - 1][k] for k in range(a - 1, b))
    checks = [
        ('cls, at(2,5), rev(1)/rev(0), eol', row(2) == '    Stellar C built-ins' and rev(2, 5, 23) and not vt.a[1][23]),
        ('at(r, c) with variables (4, 7)', row(4) == '      at(4, 7)'),
        ('printz: 00042 07 23 (123 -> its low 2 digits)', row(6) == '00042 07 23'),
        ('printw: [   42][  0]', row(7) == '[   42][  0]'),
        ('printh: BEEF 0A F', row(8) == 'BEEF 0A F'),
        ('getline: echo, Backspace, stops at 10', row(9) == 'Name? Craig Ledb'),
        ('   the string and its length', row(10) == 'Hello, Craig Ledb! 10 letters'),
        ('rtcget: 2026-10-04 14:23:07 (or :08 - the clock runs)', row(11) in ('2026-10-04 14:23:07', '2026-10-04 14:23:08')),
        ('rtcset: 1 written, 31 Feb refused (0)', row(12) == 'set 1 bad 0'),
        ('   the chip holds 2026-12-25 09:30:0x (binary, year 54, Friday 5)',
         (rtc.r[2], rtc.r[4], rtc.r[7], rtc.r[8], rtc.r[9], rtc.r[6]) == (30, 9, 25, 12, 54, 5)),
        ('poke/pokew/peek/peekw: AB 1234, at $6700 and $6702', row(13) == 'AB 1234' and
         (c.M[0x6700], c.M[0x6702], c.M[0x6703]) == (0xAB, 0x12, 0x34)),
        ('cursor(0) then cursor(1)', vt.cursors[-2:] == [False, True]),
        ('a clean end: halted, no VM error, VT100 only', r == 'halt' and not c.M[0x304F] and not vt.bad),
    ]
    for label, good in checks:
        print('%-66s %s' % (label, 'OK' if good else 'FAIL'))
        ok &= bool(good)
    if not checks[5][1] or not checks[6][1]: print('   rows 9-10: %r / %r' % (row(9), row(10)))
    # rerun from the memory left: the same screen (the name buffer re-initialised), a new name
    c2, rtc2, vt2, r2 = run(None, b'Al\r', mem=c.M, regs=dict(enumerate(rtc.r)))
    good = vt2.row(8) == 'Name? Al' and vt2.row(9) == 'Hello, Al! 2 letters' and vt2.row(5) == '00042 07 23' and r2 == 'halt'
    print('%-66s %s' % ('RERUN without reloading: "Al", 2 letters', 'OK' if good else 'FAIL %r' % vt2.row(9)))
    ok &= good
    # the web page's demo, examples/hello.sc: a name, and none
    c1, em1, _, data1 = scc.compile_source(open(os.path.join(HERE, 'examples', 'hello.sc')).read(), 'hello')
    pk1 = [(a + i, b) for a, bs, _, _ in em1 for i, b in enumerate(bs)] + \
          [(0x4000 + a + i, b) for a, d in data1.items() for i, b in enumerate(d)]
    for keys, want in ((b'Craig\r', '         Hello, Craig! That is 5 letters.'),
                       (b'\r', '         No name? Then hello, stranger.')):
        c, rtc, vt, r = run(pk1, keys)
        good = vt.row(5) == want and vt.row(7).startswith('         It is 2026-10-04 at 14:23:0') and \
            vt.row(11).split() == ['1241', '01241', '1241', '04D9'] and r == 'halt' and not vt.bad
        print('%-66s %s' % ('hello.sc with %r' % keys, 'OK' if good else 'FAIL %r' % vt.row(5)))
        ok &= good
    print('PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
