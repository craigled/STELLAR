# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""The raw 1802 examples (LTOS/raw/*.BIN, made by raw/make_raw.py), on the simulated 1802 from a reset, timed for a
3 MHz Elf2K (375,000 machine cycles a second; every instruction they use takes 2):

  * COUNTUP: the LEDs (OUT 4) 00, 01 ... FF, then FF stays; about 20 ms a step
  * COUNTDN: FF ... 00, then 00 stays
  * UPDOWN:  00 ... FF ... 00 ... FF, round and round
  * SINE:    Q on for the share of each step the sine table says (delta-sigma), 32 steps a wave, 390 Hz, ~0.96 s,
             then Q off; every step the same 30 machine cycles
  * through LTOS's 1802 command, by their place on the card: 1802 /BIN/RAW/COUNTUP and 1802 /BIN/RAW/SINE 1802 COUNTUP counts on the LEDs, 1802 SINE sounds on Q.

    python3 LTOS/verify_raw.py [-v]
"""
import math, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'raw'))
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
from cpu1802 import CPU
import make_raw
import glob

CPS = 375000                                        # machine cycles a second, 3 MHz


def labels(name):
    out = {}
    for ln in open(os.path.join(HERE, 'raw', name + '.lst')):
        m = re.match(r'\s*([0-9a-fA-F]{4})\s+(?:[0-9a-fA-F]{2}\s+)*([A-Z][A-Z0-9]*):', ln)
        if m: out[m.group(2)] = int(m.group(1), 16)
    return out


def reset(data):
    m = bytearray(0x10000); m[:len(data)] = data
    c = CPU(m); c.P = 0; c.X = 0; c.R[0] = 0; c.Q = 0
    return c


def leds(data, want):
    """-> ([the bytes sent to port 4], [steps between them])"""
    c = reset(data); got, at, gaps, last = [], [], [], 0
    for k in range(60_000_000):
        c.step()
        o = c.io_out.get(4, [])
        if len(o) > len(got):
            got.append(o[-1]); gaps.append(c.steps - last); last = c.steps
            if len(got) >= want: break
    return got, gaps, c


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    bins = dict(make_raw.make(s) for s in sorted(glob.glob(os.path.join(HERE, 'raw', '*.asm'))))
    ms = lambda steps: steps * 2 * 1000 / CPS

    got, gaps, c = leds(bins['COUNTUP'], 256)
    e = []
    if got != list(range(256)): e.append('the LEDs: %s' % got[:8])
    step = sum(gaps[1:]) / len(gaps[1:])
    if not 18 <= ms(step) <= 23: e.append('%.1f ms a step' % ms(step))
    L = labels('COUNTUP'); [c.step() for _ in range(20000)]          # (past the last wait)
    if c.io_out[4][-1] != 0xFF or len(c.io_out[4]) != 256 or c.R[c.P] != L['DONE']: e.append('it does not stay at FF')
    report('COUNTUP: the LEDs 00 to FF, %.1f ms a step (%.1f s), then FF stays' % (ms(step), ms(step) * 256 / 1000), e)

    got, gaps, c = leds(bins['COUNTDN'], 256)
    e = []
    if got != list(range(255, -1, -1)): e.append('the LEDs: %s' % got[:8])
    [c.step() for _ in range(1000)]
    if len(c.io_out[4]) != 256: e.append('it does not stay at 00')
    report('COUNTDN: the LEDs FF to 00, %.1f ms a step, then 00 stays' % ms(sum(gaps[1:]) / len(gaps[1:])), e)

    got, gaps, c = leds(bins['UPDOWN'], 256 + 255 + 255 + 20)
    want = list(range(256)) + list(range(254, -1, -1)) + list(range(1, 256)) + list(range(254, 234, -1))
    e = []
    if got != want[:len(got)]: k = next(i for i, (a, b) in enumerate(zip(got, want)) if a != b); e.append('at %d: %s, not %s' % (k, got[k:k + 4], want[k:k + 4]))
    if max(gaps[1:]) - min(gaps[1:]) > 4: e.append('the steps are uneven: %d-%d' % (min(gaps[1:]), max(gaps[1:])))
    report('UPDOWN: 00 to FF, back to 00, up again (%.1f s a round), every step the same' % (ms(sum(gaps[1:511]) ) / 1000), e)

    # ---- SINE: Q at the end of each step (NX), its share at each of the 32 places in the wave
    L = labels('SINE'); c = reset(bins['SINE'])
    tab = [round(128 + 127 * math.sin(2 * math.pi * k / 32)) for k in range(32)]
    bits, at, last, per = [], [], None, set()
    for k in range(5_000_000):
        if c.R[c.P] == L['NX']:
            bits.append(c.Q)
            if last is not None: per.add(c.steps - last)
            last = c.steps
        if c.R[c.P] == L['DONE']: break
        c.step()
    e = []
    n = len(bits)
    def part(h):                    # the bits' share at h x 390 Hz (h = 1: the tone; 2, 3, ...: its harmonics)
        sc = sum(x * math.sin(2 * math.pi * h * i / 32) for i, x in enumerate(bits)) / n
        cc = sum(x * math.cos(2 * math.pi * h * i / 32) for i, x in enumerate(bits)) / n
        return 2 * math.hypot(sc, cc)
    ideal = 127 / 256                                                # a sine of the table's height
    # A 1-bit line at this speed always carries about as much buzz as tone (measured: every variant - lower,
    # quieter, 2nd-order - is no better on the 1802); first-order puts it mostly at 2.7 kHz and up (the 7th
    # harmonic on), where a small speaker is weak. So: the tone right, the strongest part, the low harmonics small.
    low = max(part(h) for h in range(2, 7))                         # (a square wave: 1/3 of the tone at h = 3)
    worst = max(part(h) for h in range(2, 17))
    if abs(part(1) - ideal) > 0.02: e.append('the 390 Hz part is %.3f, not %.3f' % (part(1), ideal))
    if worst >= part(1): e.append('a harmonic (%.3f) as strong as the tone' % worst)
    if low > 0.1: e.append('2nd-6th harmonics up to %.3f' % low)
    if abs(sum(bits) / n - 0.5) > 0.01: e.append('Q on %.3f of the time, not half' % (sum(bits) / n))
    if per != {15}: e.append('steps of %s instructions, not all 15' % sorted(per))
    secs = n * 30 / CPS; hz = CPS / 30 / 32
    if not 0.9 <= secs <= 1.0: e.append('%.2f s' % secs)
    if c.Q: e.append('Q is left on')
    report('SINE: every step 15 instructions: %.0f Hz for %.2f s; the tone %.3f (a pure sine: %.3f), 2nd-6th harmonics '
           'at most %.3f, the buzz above at most %.3f; then Q off' % (hz, secs, part(1), ideal, low, worst), e)

    # ---- through LTOS: 1802 COUNTUP, 1802 SINE from the card
    import verify_phase0 as V, verify_phase1 as P1, verify_phase2 as P2, verify_phase3 as P3, build
    kimg, _ = build.kernel(); mem, _, _ = build.build(kimg)
    cf, e2k, st = P1.installed_full(mem, 16384)
    def put(m):                                     # in /BIN/RAW, as the card layout template puts them
        os.makedirs(os.path.join(m, 'BIN', 'RAW'), exist_ok=True)
        for n, d in bins.items(): open(os.path.join(m, 'BIN', 'RAW', n + '.BIN'), 'wb').write(d)
    img, _ = P2.mac(V.image(cf, 16384), put)
    for keys, check in ((b'1802 /BIN/RAW/COUNTUP\r', 'leds'), (b'1802 /BIN/RAW/SINE\r', 'q')):
        P1.load_image(cf, img)
        b = V.Elf2K(cf, keys=keys); b.rtc = P3.clock(); c = b.c
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        st = b.run(900_000_000, stop=0x0000)
        e = []
        if st != 'stop' or 'Starting ' not in b.text(): e.append('not started: %s %r' % (st, b.text()[-200:]))
        if check == 'leds':
            c.io_out[4] = []
            for _ in range(200_000): c.step()
            if c.io_out[4][:5] != [0, 1, 2, 3, 4]: e.append('the LEDs: %s' % c.io_out[4][:8])
            what = 'the LEDs count 00, 01, 02 ...'
        else:
            flips = 0; q = c.Q
            for _ in range(200_000):
                c.step()
                if c.Q != q: flips += 1; q = c.Q
            if flips < 1000: e.append('Q changed only %d times' % flips)
            what = 'Q sounds (%d changes in 200,000 instructions)' % flips
        if '-v' in sys.argv: print(b.text()[-300:])
        report('%s from the card through LTOS\'s 1802 command: %s' % (keys.decode().strip(), what), e)
    print('RAW: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
