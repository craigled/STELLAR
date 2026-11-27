# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check Stellar C's Elf2K I/O built-ins ($01-$0F) in the simulator on V0061.37 (as flashed).

Each input port p reads $pp; the test drives the EF lines itself and records every
byte written to each output port and every change of Q.

    python3 io_verify.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import opcode_sweep as S
import scc

IMG = bytes(S.image('37'))

def run(src, ef_line=None, ef_period=3000, cap=3_000_000):
    """ef_line: which EF (1-4) the test pulses (all others held low); None = never."""
    r = scc.compile_text(src, 'iotest')
    if 'error' in r: raise SystemExit(r['error'])
    c = S.boot(IMG, S.parse_dlines(r['lst'].split('\n')), keys=b'')
    for p in (1, 4, 5, 6, 7): c.io_in[p] = S.Port(0x11 * p)
    qs, done = [c.Q], False
    for n in range(cap):
        v = (n // ef_period) & 1 if ef_line else 0
        c.EF = [v if i + 1 == ef_line else 0 for i in range(4)]
        if not c.step(): done = True; break
        if c.Q != qs[-1]: qs.append(c.Q)
    out = {p: list(v) for p, v in c.io_out.items() if p not in (2, 3) and v}
    err = c.M[0x304F]
    return dict(done=done, serial=bytes(c.io_out.get(3, [])).decode('latin1'), out=out, q=qs, err=err)

ok = True
def check(name, got, want):
    global ok
    good = got == want
    ok &= good
    print('%-44s %s' % (name, 'OK' if good else 'FAIL\n   got  %r\n   want %r' % (got, want)))

# ---- output: OUTI, OUTX (low and high), OUTA via the Acc, OUTMX, DEFOUT, SETQ
r = run('''
u8 a[] = { 7, 8, 9 };
void main() {
    u16 n, i;
    out(0x42);            // OUTI, default port 4
    outport(5);
    n = 0x1234;
    out(n);               // OUTX low
    out(n >> 8);          // OUTX high
    out(n + 1);           // via the Acc: OUTA
    i = 2;
    out(a[i]);            // READIDX + OUTA
    outmem(&a[1]);        // OUTMX
    i = 0;
    outmem(&a[i]);        // OUTMX through a computed address
    outport(7);
    out(300);             // a constant keeps its low byte
    q(1); q(0); q(2); q(3);
    n = 5; q(n);  n = 0; q(n);
}''')
check('outputs: ports and bytes', r['out'], {4: [0x42], 5: [0x34, 0x12, 0x35, 9, 8, 7], 7: [300 & 255]})
check('outputs: Q sequence (1,0, blink, 2 blinks, 1,0)', r['q'], [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0])
check('outputs: ran to the end, no error', (r['done'], r['err']), (True, 0))

# ---- input: SIPA (now), GIPX/GIPA (wait for the EF line), DEFIN, DEFEF, GETEFA, WIP
src_in = '''
void main() {
    u16 x;
    x = scanin();          printu(x); putc(' ');      // default port 4: $44
    inport(6);
    printu(scanin());      putc(' ');                 // through the Acc: $66
    if (scanin() == 0x66) print("eq ");               // TESTAI path
    x = getin();           printu(x); putc(' ');      // waits for EF4, then port 6
    efsource(%d);
    printu(getin());       putc(' ');                 // waits for the new EF line
    waitef();
    print("done");
}'''
r = run(src_in % 2, ef_line=None, cap=400_000)
check('input: scanin() does not wait; getin() does', (r['serial'], r['done']), ('68 102 eq ', False))
r4 = run(src_in % 4, ef_line=4)
check('input: EF4 pulsing, efsource(4)', (r4['serial'], r4['done'], r4['err']), ('68 102 eq 102 102 done', True, 0))
r2 = run(src_in % 2, ef_line=2, cap=600_000)
check('input: EF2 pulsing: getin() waits on EF4 first', (r2['serial'], r2['done']), ('68 102 eq ', False))

# efsource(2): the second getin() then waits on EF2 (and only EF2)
src_ef = '''
void main() {
    efsource(2);
    printu(getin());
    print(" ok");
}'''
check('efsource(2): getin() completes on EF2', run(src_ef, ef_line=2)['serial'], '68 ok')
check('efsource(2): ... and not on EF4', run(src_ef, ef_line=4, cap=400_000)['done'], False)

# efsource(n, 1): inverted - the line rests high and a press pulls it low. getin() waits for
# low, then high again, so it reads when the pulse ENDS; read as normal it would read when
# the pulse starts (its first high -> low edge).
def rests_high(line):
    def run_inv(src, cap=400_000):
        r = scc.compile_text(src, 'iotest')
        c = S.boot(IMG, S.parse_dlines(r['lst'].split('\n')), keys=b'')
        for p in (1, 4, 5, 6, 7): c.io_in[p] = S.Port(0x11 * p)
        for n in range(cap):
            c.EF = [0 if (i + 1 == line and 60_000 <= n < 90_000) else 1 for i in range(4)]
            if not c.step(): return n
        return None
    return run_inv
for inv, lo, hi in ((1, 90_000, 400_000), (0, 60_000, 90_000)):
    n = rests_high(3)('void main() { efsource(3, %d); printu(getin()); }' % inv)
    check('efsource(3, %d): reads at the pulse %s' % (inv, 'END' if inv else 'START'), n is not None and lo <= n < hi, True)

# waitef() follows efsource() too (the WIP patch), and not the output port
src_w = '''
void main() {
    outport(5);
    efsource(2);
    waitef();
    print("w");
}'''
check('waitef() after efsource(2): completes on EF2', run(src_w, ef_line=2)['serial'], 'w')
check('waitef() after efsource(2): ... and not on EF4', run(src_w, ef_line=4, cap=400_000)['done'], False)

# waitef(n): that EF line, whatever efsource() says (the WIP Z patch)
src_wn = '''
void main() {
    efsource(2);
    waitef(3);
    print("n");
}'''
check('waitef(3) after efsource(2): completes on EF3', run(src_wn, ef_line=3)['serial'], 'n')
check('waitef(3) after efsource(2): ... and not on EF2', run(src_wn, ef_line=2, cap=400_000)['done'], False)

# GETEFA: the highest EF line that is on
src_g = '''
void main() {
    printu(ef());
    if (ef() == 0) print(" none");
}'''
check('ef() with no EF line on', run(src_g)['serial'], '0 none')

# GETEFA as a mask (the GETEFA mask patch): EF lines held on by the test
def held(src, lines):
    r = scc.compile_text(src, 'iotest')
    c = S.boot(IMG, S.parse_dlines(r['lst'].split('\n')), keys=b'')
    c.EF = [1 if i + 1 in lines else 0 for i in range(4)]
    return S.run(c, cap=400_000, ef_period=0)['serial']
src_m = '''
void main() {
    u16 x;
    printu(ef());
    putc(' ');
    x = ef(3);
    printu(x);
    printu(ef(4));
    if (ef(1)) putc('Y'); else putc('N');
}'''
check('ef(), ef(n) with EF3 + EF4 on', held(src_m, (3, 4)), '12 11N')
check('ef(), ef(n) with EF1 on', held(src_m, (1,)), '1 00Y')

# ---- compile-time checks
for bad, msg in (('void main() { outport(3); }', 'serial chip'), ('void main() { outport(8); }', 'must be 1-7'),
                 ('void main() { inport(2); }', 'serial chip'), ('void main() { efsource(0); }', 'must be 1-4'),
                 ('void main() { u16 p; p = 4; outport(p); }', 'needs a constant'), ('void main() { q(4); }', 'two blinks'),
                 ('void main() { out(); }', 'takes 1 argument'), ('void main() { u16 x; x = getin(1); }', 'takes 0 arguments'),
                 ('void main() { efsource(2, 2); }', 'must be 0 or 1'), ('void main() { efsource(1, 0, 1); }', 'takes 1 or 2'),
                 ('void main() { waitef(5); }', 'must be 1-4'), ('void main() { u16 x; x = ef(0); }', 'must be 1-4')):
    e = scc.compile_text(bad).get('error', '')
    check('refused: %s' % bad[14:44], msg in e, True)

print('ALL OK' if ok else 'FAILURES')
sys.exit(0 if ok else 1)
