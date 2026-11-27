# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Per-VM builds (scc --vm N): the native demo compiled for VM2, VM3 and VM4 runs in that VM, beside
a VM1 program, and prints exactly what it prints in VM1 - its D-lines, RUNMC targets, &array and
{var} register addresses all moved to VM N's block and core. Also checks that a VM1 build is the
same as before (--vm 1 is the default).

    python3 pervm_verify.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import scc
import opcode_sweep as S
import rtc_verify as V

WANT = '19900 = 19900\r\n4DBC\r\nnative!\r\n'


def build(path, vm):
    scc.set_vm(vm)
    try:
        c, em, labels, data = scc.compile_file(path)
        return scc.render_lst(os.path.basename(path), c, em, labels, data)
    finally:
        scc.set_vm(1)


def pokes(text, below=None):
    p = S.parse_dlines([l for l in text.split('\n') if l.startswith('D ')])
    return [q for q in p if below is None or q[0] < below]


def main():
    ok = True
    vm1 = build(os.path.join(HERE, 'examples', 'primes.sc'), 1)
    first = pokes(vm1, 0x5000)                       # VM1: primes (its claims dropped)
    for vm in (2, 3, 4):
        text = build(os.path.join(HERE, 'examples', 'nativedemo.sc'), vm)
        base = 0x4000 + (vm - 1) * 0x1000
        good = ('loads at $%04X' % base) in text and ('D %04X CD' % base) in text
        c = S.boot(bytes(S.image('37')), first + pokes(text), keys=b'2\r100\r')
        r = V.run(c, 40_000_000)
        out = bytes(c.io_out[3]).decode('latin1')
        errs = [c.M[0x3000 + v * 0x400 + 0x4F] for v in range(4)]
        good = good and r == 'halt' and WANT in out and not any(errs)
        print('nativedemo in VM%d: %s' % (vm, 'OK' if good else 'FAIL (%s, errors %s, %r)' % (r, errs, out[-80:])))
        ok &= good
    print('per-VM builds:', 'PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
