# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS phase 4 in the simulator: STELLAR.BIN found by name.

  * RECV STELLAR.BIN (a whole firmware as Intel HEX, from $0000) replaces it - in other sectors than the
    installer's; MON then puts THAT firmware back, byte for byte; VER shows where it is now;
  * RECV STELLAR.BIN from $2800 is refused (and the old one kept);
  * RM STELLAR.BIN: VER says there is none; MON just leaves;
  * VER.PRG / FREE.PRG refuse to run on another kernel (the build stamp at $032D).

    python3 LTOS/verify_phase4.py [-v]
"""
import os, sys, re
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import opcode_sweep as S
import build

# BACK: STELLAR.PRG puts it at $0180 (the firmware's free bytes) and makes it R1, so a program's end boots LTOS
_SM, _SY = build.assemble('stellar')
BACK = bytes(_SM[_SY['BACK'] + i] for i in range(_SY['BACKN']))
def with_back(fw):
    b = bytearray(fw); b[0x180:0x180 + len(BACK)] = BACK; return bytes(b)
def run_to_back(b, cap):
    """Run to BACK: $0180 with P = 1 (a STELLAR program's end). LTOS's boot sector also runs code at $0180,
    with P = 3 - stepped past."""
    while True:
        st = b.run(cap, stop=0x0180)
        if st != 'stop' or b.c.P == 1: return st
        b.c.step()


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    stl = S.image('37')[0:0x2F00]
    new = bytearray(stl); new[0x2EF0:0x2F00] = b'NEW FIRMWARE!!!!'; new[0x0100] ^= 0xFF; new = bytes(new)
    hx = build.intel_hex({i: b for i, b in enumerate(new)}).replace('\n', '\r\n').encode()
    hx28 = build.intel_hex({0x2800 + i: b for i, b in enumerate(new[:512])}).replace('\n', '\r\n').encode()

    for mb in (8, 32):
        n = mb * 2048
        cf, e2k, st = P1.installed_full(mem, n)
        go = 'Ctrl-C stops.'
        keys = b'SAVE PAD.BIN 2800 2FFF\r' b'RECV STELLAR.BIN\r'           # PAD.BIN: so the new one lands elsewhere
        later = [(go, hx), ('replace it?', b'Y'), ('LTOS> ', b'VER\r'), ('LTOS> ', b'RECV STELLAR.BIN\r'), (go, hx28),
                 ('LTOS> ', b'MON\r')]
        b, st, t = P3.session(cf, keys, rtc=P3.clock(), later=later, cap=900_000_000)
        e = []
        img = V.image(cf, n)
        got, fl = P2.mac(img, lambda m: {f: open(os.path.join(m, f), 'rb').read() for f in os.listdir(m) if f == 'STELLAR.BIN'})
        if fl.get('STELLAR.BIN') != new: e.append('the Mac reads STELLAR.BIN: not the new firmware')
        if 'STELLAR.BIN is not from $0000 - nothing saved.' not in t: e.append('a STELLAR.BIN from $2800 was not refused')
        if bytes(b.c.M[0:0x2F00]) != new: e.append('MON did not put the NEW firmware back (%d bytes differ)' % sum(1 for x, y in zip(b.c.M[0:0x2F00], new) if x != y))
        m = re.search(r'STELLAR.BIN at sector \$([0-9A-F]{4})', P2.session_out(t, 'VER\r'))
        if not m or int(m.group(1), 16) == 0xFC: e.append('VER: %r' % P2.session_out(t, 'VER\r')[-120:])
        if st != 'stop': e.append('MON: %s' % st)
        if '-v' in sys.argv and mb == 8: print(t[-2500:])
        report('%d MB: RECV STELLAR.BIN (a whole firmware, as HEX) replaces it in new sectors; MON puts the new one '
               'back byte for byte; VER shows where; one from $2800 refused' % mb, e)

    cf, e2k, st = P1.installed_full(mem, 16384)
    b, st, t = P3.session(cf, b'RM STELLAR.BIN\rVER\rMON\r', rtc=P3.clock())
    e = []
    if 'no STELLAR.BIN on this card' not in t or 'STELLAR.BIN is not on the card.' not in t or st != 'stop':
        e.append(repr(t[-300:]))
    report('RM STELLAR.BIN: VER says none, MON just leaves', e)
    # a system program built for another kernel: FREE.PRG's stamp changed on the card
    cf, e2k, st = P1.installed_full(mem, 16384)
    img = bytearray(V.image(cf, 16384))
    spc, fat, fsz, nf, root, ents, data = P2.geometry(img)
    en = P3.entry(bytes(img), b'FREE    PRG')
    c = en[26] | en[27] << 8
    o = data + (c - 2) * spc * 512
    assert img[o + 6:o + 12] == bytes([0xF8, 0x03, 0xBD, 0xF8, 0x2D, 0xAD]), img[o:o + 16].hex()
    img[o + 14] ^= 0x55                                       # XRI HIGH(KS_STAMPV): another kernel's
    P1.load_image(cf, bytes(img))
    b, st, t = P3.session(cf, b'FREE\rVER\rMON\r', rtc=P3.clock())
    e = []
    if 'Not for this kernel - install LTOS again.' not in P2.session_out(t, 'FREE\r') or 'LTOS 0.5' not in P2.session_out(t, 'VER\r'):
        e.append(repr(t[-400:]))
    report('a FREE.PRG built for another kernel refuses to run (VER, built for this one, runs)', e)
    # 4b: STELLAR [file] - the firmware loaded through its FAT chain, started as the monitor's RUN does
    used = bytearray(stl); used[0x185] = 0xC4; used = bytes(used)               # a firmware that uses $0185
    for how, keys, r1, fw in (('STELLAR', b'STELLAR\r', 0x0180, with_back(stl)),
                              ('STELLAR S2.BIN', b'COPY STELLAR.BIN S2.BIN\rSTELLAR S2.BIN\r', 0x0180, with_back(stl)),
                              ('STELLAR -M', b'STELLAR -M\r', 0x8F53, stl),
                              ('STELLAR USED.BIN (its $0180 not free)', b'STELLAR USED.BIN\r', 0x8F53, used)):
        cf, e2k, st = P1.installed_full(mem, 16384)
        if 'USED' in how:
            img, _ = P2.mac(V.image(cf, 16384), lambda m: open(os.path.join(m, 'USED.BIN'), 'wb').write(used))
            P1.load_image(cf, img)
        b = V.Elf2K(cf, keys=keys); b.rtc = P3.clock(); c = b.c
        b.c.M[0:0x2F00] = bytes(0x2F00)                        # (RAM without STELLAR: it must come from the card)
        c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
        st = b.run(900_000_000, stop=0x0000)
        e = []
        if st != 'stop' or c.P != 0 or c.X != 0: e.append('%s: not started as RUN would (%s, P=%X X=%X)' % (how, st, c.P, c.X))
        if c.R[1] != r1: e.append('%s: R1 = %04X, not $%04X' % (how, c.R[1], r1))
        if bytes(c.M[0:0x2F00]) != fw: e.append('%s: RAM is not the firmware (with BACK at $0180 if R1 is it)' % how)
        if 'Starting STELLAR ... done.' not in b.text(): e.append('%s: %r' % (how, b.text()[-200:]))
        report('%s: the firmware from the card to $0000-$2EFF, started with R0 = 0, X = P = 0 - as RUN; R1 = BACK at '
               '$0180 (a program\'s end boots LTOS), or with -M or a firmware that uses $0180, the ROM\'s breakpoint '
               'entry' % how, e)
    cf, e2k, st = P1.installed_full(mem, 16384)
    b, st, t = P3.session(cf, b'STELLAR NOPE.BIN\rSTELLAR A.TXT B.TXT\rSTELLAR A*\rSTELLAR NOAPP\rMON\r', rtc=P3.clock())
    e = [] if (t.count('or not STELLAR firmware.') == 1 and t.count('STELLAR [-M] [firmware.BIN] [app ...]') == 2
               and 'NOAPP.STL is not on the card.' in t and st == 'stop') else [repr(t[-500:])]
    report('STELLAR with a missing file, a file that is not a firmware, a wildcard: refused, LTOS goes on', e)

    # $7F00-$7FFF is the Elf2K BIOS's: RECV refuses a line there or one that runs into it; a $7E80 line loads
    # (the stub keeps only the $7E00 block's first half) and the BIOS's page is left as it was
    cf, e2k, st = P1.installed_full(mem, 16384)
    hi = b'D 4000 CD\r\nD 7E80 11 22 33 44\r\nD 7EFE AA BB\r\n'
    b, st, t = P3.session(cf, b'RECV F00.STL\r', rtc=P3.clock(),
                          later=[('Ctrl-C stops.', b'D 4000 CD\r\nD 7F00 01\r\n'), ('LTOS> ', b'RECV RUN.STL\r'),
                                 ('Ctrl-C stops.', b'D 4000 CD\r\nD 7EF8 01 02 03 04 05 06 07 08 09 0A\r\n'),
                                 ('LTOS> ', b'RECV HI.STL\r'), ('Ctrl-C stops.', hi), ('LTOS> ', b'MON\r')], cap=1_500_000_000)
    e = []
    if t.count('An address outside $4000-$7EFF - nothing saved.') != 2: e.append('F00 / RUN not both refused: %r' % t[-600:])
    if 'Saved HI.STL' not in t: e.append('HI.STL not saved: %r' % t[-300:])
    b = V.Elf2K(cf, keys=b'STELLAR HI\r'); b.rtc = P3.clock(); c = b.c
    b.c.M[0:0x2F00] = bytes(0x2F00)
    c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
    st = b.run(900_000_000, stop=0x3000)                     # MON's stub starts: the BIOS's page now ...
    mark = bytes(c.M[0x7F00:0x8000])
    st = b.run(900_000_000, stop=0x0000) if st == 'stop' else st
    if st != 'stop': e.append('STELLAR HI: %s %r' % (st, b.text()[-300:]))
    else:
        if bytes(c.M[0x7F00:0x8000]) != mark: e.append('the stub wrote into $7F00-$7FFF')
        if bytes(c.M[0x7E80:0x7E84]) != bytes([0x11, 0x22, 0x33, 0x44]) or bytes(c.M[0x7EFE:0x7F00]) != bytes([0xAA, 0xBB]):
            e.append('the $7E00 block did not load: %s' % bytes(c.M[0x7E80:0x7E84]).hex())
    report('$7F00-$7FFF (the BIOS\'s): RECV refuses a line at $7F00 and one running into it; a $7E80..$7EFF app '
           'loads through STELLAR', e)

    # 31 blocks (an app in every VM - STELLAR ORBIT, $4000-$7DC0): 16 KB, more than RECV's room ($3000-$6BFF) -
    # said, nothing saved; elfser.py putstl makes the .STL on the Mac (= the reference) and XFER puts it on the card
    olst = open(os.path.join(HERE, '..', '..', 'STELLAR', 'web', 'downloads', 'Stellar-Orbit.lst')).read()
    owant = build.stl_of(olst)
    cf, e2k, st = P1.installed_full(mem, 16384)
    b, st, t = P3.session(cf, b'MKDIR APPS\rCD APPS\rRECV ORBIT.STL\r', rtc=P3.clock(),
                          later=[('Ctrl-C stops.', olst.replace('\n', '\r\n').encode()), ('LTOS /APPS> ', b'MON\r')],
                          cap=3_000_000_000)
    e = []
    if 'Too big for RECV (15 KB): on the PC/Mac/Linux, elfser.py putstl NAME.lst - nothing saved.' not in t: e.append('RECV: %r' % t[-300:])
    import elfser as E, verify_xfer as X
    if E.stl_of(olst) != owant: e.append('putstl\'s .STL is not the reference')
    u, st, t = X.run(cf, b'XFER -R /APPS/ORBIT.STL\r', E.xput(E.stl_of(olst), lambda *a: None), later=[('LTOS> ', b'MON\r')])
    _, fl = P2.mac(V.image(cf, 16384), lambda m: open(os.path.join(m, 'APPS', 'ORBIT.STL'), 'rb').read()
                   if os.path.exists(os.path.join(m, 'APPS', 'ORBIT.STL')) else None)
    if fl != owant: e.append('ORBIT.STL: %s (want %d bytes) %r' % (len(fl) if fl else None, len(owant), t[-300:]))
    report('ORBIT (31 blocks, 16 KB): RECV says it is too big, nothing saved; elfser.py putstl + XFER: /APPS/ORBIT.STL '
           '= the reference', e)

    # a .lst sent at full speed (timed: 19200 baud, the UART holds one byte - as on the Elf2K) whose first D-line
    # comes at once (Prime-Gen: byte 205): STLRX must be reading when it says "Send the .lst" (it zeroed 16 KB
    # first - it used to say it before, and the first lines were lost on the hardware)
    e = []
    for nm, rel in (('PRIMES', ('samples', 'Prime-Gen-v07.lst')),):
        plst = open(os.path.join(HERE, '..', '..', 'STELLAR', 'web', *rel)).read().replace('\n', '\r\n')
        cf, e2k, st = P1.installed_full(mem, 16384)
        b, st, t = P3.session(cf, b'RECV %s.STL\r' % nm.encode(), rtc=P3.clock(), cap=4_000_000_000,
                              later=[('Ctrl-C stops.', plst.encode(), 'timed'), ('LTOS> ', b'MON\r')])
        _, got = P2.mac(V.image(cf, 16384), lambda m, nm=nm: open(os.path.join(m, nm + '.STL'), 'rb').read()
                        if os.path.exists(os.path.join(m, nm + '.STL')) else None)
        if got != build.stl_of(plst): e.append('%s.STL: %s bytes, lost %d characters: %r' % (nm, len(got) if got else None, b.u.lost, t[-200:]))
    report('RECV NAME.STL at full speed (timed UART): Prime-Gen (a D-line at byte 205) arrives whole', e)

    # 4c: apps on the card - RECV NAME.STL from a whole .lst; APPS; STELLAR NAME runs it
    lst = open(os.path.join(HERE, '..', 'APPLICATIONS', 'CLOCK', 'Time-Grab.lst')).read()
    want = build.stl_of(lst)
    lstx = lst.replace('\n', '\r\n').encode()
    mrl = open(os.path.join(HERE, '..', 'APPLICATIONS', 'Maze', 'MazeRace.lst')).read()
    mrx = mrl.replace('\n', '\r\n').encode()
    vm = lambda l: ' '.join(str(v) for v in build.vms_of(build.stl_of(l)))     # VM 1 / VM 1 2 3: the ones that start with $CD
    for mb in (8, 32):
        cf, e2k, st = P1.installed_full(mem, mb * 2048)
        bad = b'D 4000 CD\r\nD 3F00 01 02\r\n'
        b, st, t = P3.session(cf, b'RECV TIMEGRAB.STL\r', rtc=P3.clock(),
                              later=[('Ctrl-C stops.', lstx), ('LTOS> ', b'RECV BAD.STL\r'), ('Ctrl-C stops.', bad),
                                     ('LTOS> ', b'RECV MAZERACE.STL\r'), ('Ctrl-C stops.', mrx),
                                     ('LTOS> ', b'APPS\r'), ('LTOS> ', b'MON\r')], cap=1_500_000_000)
        img = V.image(cf, mb * 2048); e = []
        got, fl = P2.mac(img, lambda m: {f: open(os.path.join(m, f), 'rb').read() for f in os.listdir(m) if f.endswith('.STL')})
        if fl.get('TIMEGRAB.STL') != want: e.append('TIMEGRAB.STL is not what the .lst says (%s bytes)' % len(fl.get('TIMEGRAB.STL', b'')))
        if 'BAD.STL' in fl or 'An address outside $4000-$7EFF - nothing saved.' not in t: e.append('BAD.STL: %r' % t[-300:])
        ao = P2.session_out(t, 'APPS\r')
        if not (re.search(r'TIMEGRAB  4 blocks  VM %s\r?\n' % vm(lst), ao) and re.search(r'MAZERACE  8 blocks  VM %s\r?\n' % vm(mrl), ao)
                and vm(lst) == '1' and vm(mrl) == '1 2 3'): e.append('APPS: %r' % ao)
        if '-v' in sys.argv and mb == 8: print(t[-1500:])
        report('%d MB: RECV TIMEGRAB.STL from the whole Time-Grab.lst (comments and all) = the D-lines exactly; an '
               'address outside $4000-$7EFF refused; APPS lists the VMs each runs in (Time-Grab: VM 1, Maze Race: VM 1 2 3)' % mb, e)
    # STELLAR TIMEGRAB in the simulator: V0061.36 from the card, the app from the card, run to its end
    b = V.Elf2K(cf, keys=b'STELLAR TIMEGRAB\r'); b.rtc = P3.clock(); c = b.c
    c.M[0:0x2F00] = bytes(0x2F00); c.M[0x4000:0x7F00] = bytes(0x3F00)       # nothing left from before
    c.R[2] = 0x7EF0; c.X = 2; c.R[0xE] = 0x0100; c.R[3] = 0xFF00; c.P = 3
    st = b.run(150_000_000, stop=0x0000)
    e = []
    if st != 'stop' or c.R[1] != 0x0180: e.append('not started as RUN would, R1 = BACK (%s, R1 = %04X)' % (st, c.R[1]))
    for k in range(want[4]):
        a = want[5 + 2 * k] << 8
        if bytes(c.M[a:a + 512]) != want[512 * (k + 1):512 * (k + 2)]: e.append('the block at $%04X is not the app' % a)
    if bytes(c.M[0:0x2F00]) != with_back(stl): e.append('RAM is not the firmware')
    st = run_to_back(b, 150_000_000)                       # (BACK: the app has ended - the firmware never runs $0180)
    if st != 'stop': e.append('the app did not end through BACK (%s)' % st)
    st = b.run(150_000_000, stop=0x0106)                   # then LTOS's boot sector, from the BIOS's F_BOOT
    if st != 'stop' or c.P != 3: e.append('BACK did not boot LTOS (%s, P = %X)' % (st, c.P))
    if '2026-10-16 14:30:20' not in b.text(): e.append('Time Grab did not print the time: %r' % b.text()[-300:])
    report('STELLAR TIMEGRAB: the firmware and the app\'s blocks loaded from the card, STELLAR started as RUN does, '
           'and Time Grab ran to its end (printed the clock\'s 2026-10-16 14:30:20) - and LTOS booted again', e)

    # 4d: DATE / TIME - shown, and set in the clock's own form
    class RTC:
        """A DS12887: binary 24-hour with the year from 1972 (the Elf2K BIOS's way), or BCD (12-hour if asked)."""
        def __init__(s, binary=True, h24=True, t=(2026, 10, 17, 14, 30, 20)):
            s.binary, s.h24 = binary, h24
            s.r = {0x0A: 0x20, 0x0B: (0x04 if binary else 0) | (0x02 if h24 else 0) | 0x01}
            y, mo, d, h, mi, se = t
            for reg, v in ((0, se), (2, mi), (7, d), (8, mo), (9, y - 1972 if binary else y - 2000), (6, 6)):
                s.r[reg] = s.enc(v)
            s.r[4] = s.enc(h) if h24 else (s.enc(h % 12 or 12) | (0x80 if h >= 12 else 0))
            s.writes = []
        def enc(s, v): return v if s.binary else int('%d' % v, 16)
        def dec(s, v): return v if s.binary else int('%02x' % v)
        def read(s, reg): return s.r.get(reg, 0)
        def write(s, reg, v): s.r[reg] = v; s.writes.append((reg, v))
    def run_rtc(keys, rtc):
        cf_ = cf4
        b = V.Elf2K(cf_, keys=keys); b.rtc = rtc.read if rtc else (lambda r: 0xFF); b.rtcw = rtc.write if rtc else None
        st = b.boot_rom(cap=200_000_000)
        return st, b.text()
    cf4, e2k, st = P1.installed_full(mem, 16384)
    e = []
    r = RTC()
    st, t = run_rtc(b'DATE\rTIME\rTIME 9:05\rDATE 2027-02-28\rDATE\rTIME\rMON\r', r)
    for w, c in (('Saturday 2026-10-17', 'DATE\r'), ('14:30:20', 'TIME\r'), ('09:05:00', 'TIME 9:05\r'),
                 ('Sunday 2027-02-28', 'DATE 2027-02-28\r')):
        if w not in P2.session_out(t, c): e.append('%r: %r' % (c, P2.session_out(t, c)[:120]))
    if (r.r[4], r.r[2], r.r[0], r.r[7], r.r[8], r.r[9], r.r[6]) != (9, 5, 0, 28, 2, 2027 - 1972, 7):
        e.append('the binary registers: %r' % r.r)
    if r.r[0x0B] != 0x07 or r.r[0x0A] != 0x20 or not any(reg == 0x0B and v & 0x80 for reg, v in r.writes):
        e.append('SET was not used / B not put back: B=%02X A=%02X' % (r.r[0x0B], r.r[0x0A]))
    report('DATE / TIME on a clock kept as the Elf2K BIOS does (binary, 24-hour, from 1972): shown with the '
           'weekday; set (the weekday register too, Sunday = 7) with SET held, B put back', e)
    e = []
    r = RTC()
    st, t = run_rtc(b'DATE 2027-02-29\rDATE 2028-02-29\rDATE 1999-01-01\rDATE 2026-13-01\rDATE 2026-10-17x\r'
                    b'TIME 24:00\rTIME 12:60\rTIME 1:2:3:4\rTIME\rMON\r', r)
    if t.count('DATE shows it; DATE yyyy-mm-dd sets it') != 4: e.append('bad dates: %r' % t[-900:])
    if 'Tuesday 2028-02-29' not in t: e.append('the leap day 2028-02-29')
    if t.count('TIME shows it; TIME hh:mm[:ss] sets it') != 3: e.append('bad times: %r' % t[-600:])
    report('bad dates (2027-02-29, 1999, month 13, trailing junk) and times (24:00, 12:60, 1:2:3:4) refused; '
           'the leap day 2028-02-29 (a Tuesday) taken', e)
    e = []
    r = RTC(binary=False, h24=False, t=(2026, 10, 17, 9, 0, 0))
    st, t = run_rtc(b'TIME\rTIME 13:45:30\rTIME 0:10\rDATE 2026-12-25\rMON\r', r)
    if '09:00:00' not in P2.session_out(t, 'TIME\r'): e.append('BCD 12-hour shown: %r' % P2.session_out(t, 'TIME\r'))
    if '00:10:00' not in P2.session_out(t, 'TIME 0:10\r') or r.r[4] != 0x12: e.append('12 AM: %02X' % r.r[4])
    if not any(reg == 4 and v == 0x81 for reg, v in r.writes): e.append('13:45 as BCD 12-hour (1 PM = $81) not written')
    if (r.r[7], r.r[8], r.r[9], r.r[6]) != (0x25, 0x12, 0x26, 5) or 'Friday 2026-12-25' not in t: e.append('BCD date: %r' % r.r)
    st, t = run_rtc(b'DATE\rTIME\rMON\r', None)
    if t.count('There is no clock') != 2: e.append('no clock: %r' % t[-300:])
    report('a BCD 12-hour clock: shown and set in its own form (1 PM = $81, 12 AM = $12, year from 2000); no clock '
           'said so', e)

    print('\nLTOS phase 4:', 'ALL PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
