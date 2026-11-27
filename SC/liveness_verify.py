# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression test: a call's arguments that are still needed AFTER the call must keep their
registers. scc used to leave every argument variable out of 'must survive this call', so the
callee's own variables could share their registers and overwrite them (found in CanonBall v02:
t = incastle(c, r) clobbered fly()'s c and r).

    python3 liveness_verify.py
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import guide_check as GC

SRC = r'''
u16 f(u16 a, u16 b) {        // its own locals are busy: they must not land on c or r
    u16 t, u;
    t = a * 3; u = b + 7;
    if (t > u) return t - u;
    return u - t;
}
void main() {
    u16 c, r, t, n;
    n = 0;
    for (c = 1; c < 6; c++) {
        r = c + 10;
        t = f(c, r);          // c and r are used again below
        n = n + t + c * 100 + r;
    }
    printu(n); print("\r\n");
}
'''

def model():
    n = 0
    for c in range(1, 6):
        r = c + 10; t = abs(c * 3 - (r + 7)); n += t + c * 100 + r
    return n

text, vt, res, cpu = GC.run(SRC, 'liveness', b'', 5_000_000)
want = '%d\r\n' % model()
ok = text == want and res == 'halt'
print('got %r want %r: %s' % (text, want, 'PASS' if ok else 'FAIL'))
sys.exit(0 if ok else 1)
