# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Cards that are slow or keep data wrong (the two 32 MB SanDisk SDCFB-32s, 2026-10-26), in the simulator.

  * SLOW RESET: after the soft reset ends, the card shows "ready" from before for a while and takes commands as
    nothing (so SET FEATURES 8-bit is lost and it stays 16-bit), then is busy, then ready. The driver waits
    ~16 ms, then for ready, then checks 8-bit mode took (IDE8CHK): F installs, the card boots to the prompt.
    (The driver before this - LTOS/ has the same fix now - failed it as the hardware did: "no LBA".)
  * A card whose RESET is slower than that wait: the first try's IDENTIFY is lost; IDERST tries again.
  * KEPT WRONG: the card's buffer holds what was written - so reading the same sector straight back is right -
    but what it keeps has the byte after a "7C 00" moved early ("7C A8 00 A8 ..."), as sectors 73 and 75 were.
    The old installer said "Every sector read back right" and the boot failed its sum; the new one reads
    another sector first, sees it, writes it twice more, and stops (VERIFY FAILED) - it never says ready.

    python3 LTOS/verify_cards.py [-v]
"""
import os, sys, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import cftest_verify as CV
import build

N = 16384


class SlowResetCF(CV.CF):
    """After the soft reset ends: STALE steps showing ready (commands taken as nothing), then BUSY steps busy."""
    def __init__(s, stale, busy, slow_first=0, quick=0, **kw):
        super().__init__(**kw); s.stale, s.busyn, s.first, s.quick = stale, busy, slow_first, quick
        s.rst = None; s.srst = False; s.nres = 0; s.clock = lambda: 0; s.ignored = 0
    def write(s, r, v):
        if r == 14:
            was, s.srst = s.srst, bool(v & 0x04)
            if was and not s.srst: s.rst = s.clock(); s.nres += 1
        return super().write(r, v)
    def phase(s):
        if s.rst is None or s.nres <= s.quick: return 'ok'
        t = s.clock() - s.rst; st = s.stale + (s.first if s.nres == s.quick + 1 else 0)
        return 'stale' if t < st else 'busy' if t < st + s.busyn else 'ok'
    def read(s, r):
        ph = s.phase()
        if r in (7, 14) and ph == 'busy': return 0x80
        if r in (7, 14) and ph == 'stale': return 0x50
        return super().read(r)
    def command(s, v):
        if s.phase() != 'ok': s.ignored += 1; return
        return super().command(v)


class KeptWrongCF(CV.CF):
    """Keeps "7C 00 A8" as "7C A8 00 A8" (the rest moved up one); its buffer gives back the last sector written
    right, until another sector is read."""
    PAT = b'\x7C\x00\xA8'
    def __init__(s, **kw):
        super().__init__(**kw); s.cache = None
    def write(s, r, v):
        before = s.log[-1] if s.log else None
        super().write(r, v)
        if s.log and s.log[-1] is not before and s.log[-1][0] == 'write':
            lba = s.log[-1][1]; d = s.disk[lba]; s.cache = (lba, d)
            i = d.find(s.PAT)
            if i >= 0: s.disk[lba] = (d[:i + 1] + d[i + 2:i + 3] + d[i + 1:])[:512]
    def command(s, v):
        if v == 0x20 and s.cache and s.lba() != s.cache[0]: s.cache = None
        r = super().command(v)
        if v == 0x20 and s.cache and s.lba() == s.cache[0]: s.buf = s.cache[1]
        return r


def install(mem, cf, two=True):
    e = V.Elf2K(cf, keys=b'F'); cf.clock = lambda: e.steps
    for a, b in mem.items(): e.c.M[a] = b
    st = e.call(0x3000, cap=300_000_000)
    if two and 'CALL 3003' in e.text(): P1.second_paste(e)
    return e.text()


def boots(cf):
    """BOOT: the ROM's own reset quick (it is the ROM's, and on the Elf2K it read these cards' boot sector), LTOS's
    kernel's (IDERST at its start) slow."""
    cf.nres = 0; cf.quick = 1
    b = V.Elf2K(cf, keys=b'VER\r'); cf.clock = lambda: b.steps
    st = b.boot_rom(cap=60_000_000)
    return b.text()


def main():
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)

    # 1. a slow reset: 600 steps showing ready (~6 ms), then 4,000 busy
    e = []
    cf = SlowResetCF(600, 4000, sectors=N); t = install(mem, cf)
    if 'The card is ready. Type BOOT.' not in t or 'SanDisk SDCFB-128' not in t: e.append('install: %r' % t[-400:])
    else:
        t = boots(cf)
        if 'LTOS> VER' not in t: e.append('the boot: %r' % t[-300:])
    if '-v' in sys.argv: print(t)
    report('a card slow out of its reset (before: SET FEATURES lost, IDENTIFY read 16-bit - "no LBA"): the driver '
           'waits and checks 8-bit mode - F installs, it boots', e)

    # 2. a reset slower than the wait, the first time only: the first try's commands are lost; tried again
    e = []
    cf = SlowResetCF(600, 4000, slow_first=3000, sectors=N); t = install(mem, cf)
    if 'The card is ready. Type BOOT.' not in t or cf.nres < 2: e.append('resets %d: %r' % (cf.nres, t[-300:]))
    report('a reset slower than the wait the first time: IDERST tries again (%d resets), F installs' % cf.nres, e)

    # 3. kept wrong
    e = []
    cf = KeptWrongCF(sectors=N); t = install(mem, cf)
    if 'VERIFY FAILED' not in t or 'The card is ready' in t: e.append('install: %r' % t[-400:])
    if '-v' in sys.argv: print(t)
    report('a card that keeps "7C 00 A8" wrong but gives its buffer back (before: "read back right", then the boot '
           'failed its sum): the installer reads another sector first - VERIFY FAILED, not ready', e)

    print('\nCards: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
