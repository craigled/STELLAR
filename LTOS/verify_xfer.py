# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""XFER.PRG (xfer.asm) against elfser.py's own put / pull code: the Mac's bytes arrive at 19200 baud and the UART
holds ONE (as on the Elf2K) - XFER must lose none. A 120 KB file onto the card and back, byte-identical; small
sizes and a folder; a lost byte, a changed byte, a lost ACK (both ways) recovered; a block always bad refused;
replacing (Y, N, a failed replace keeps the old file); the card filling up; a stop from the Mac. After each: the
Mac reads the card, fsck_msdos is clean, and FREE agrees with fsck.

    python3 LTOS/verify_xfer.py [-v]
"""
import os, re, sys, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import elfser as E
import build

SPS = 19200 // 10 * V.UART.PER                          # simulator steps a second (58 a character)
NSEC = 16384                                            # an 8 MB card


class Out(list):
    def __init__(s, u): super().__init__(); s.u = u
    def append(s, b):
        super().append(b); s.u.tick()


class MacUART(V.UART):
    """The Mac on the other end: once the Elf2K prints "Ctrl-C stops.", the generator gen (elfser.xput / xpull)
    runs - its 'send' bytes arrive one every PER steps, its 'recv' sees what XFER sends. sendf(k, bytes) may
    damage the k-th send; recvf(k, byte) the k-th byte received (None: lost)."""
    def __init__(s, keys, later, gen, sendf=None, recvf=None):
        super().__init__(keys, later); s.out = Out(s)
        s.gen, s.sendf, s.recvf = gen, sendf, recvf
        s.active = s.done = False; s.result = None; s.req = None
        s.inq = []; s.rxp = 0; s.outp = 0; s.got = b''; s.since = 0; s.nsend = s.nrecv = 0; s.board = None
    def tick(s):
        if s.board is not None: s.now = max(s.now, s.board.steps)
        if s.done: return
        if not s.active:
            i = bytes(s.out).find(b'Ctrl-C stops.\r\n', s.seen)
            if i < 0: return
            s.active = True; s.outp = i + 15; s.req = next(s.gen); s.since = s.now
        while s.outp < len(s.out):                      # what XFER sent since
            b = s.out[s.outp]; s.outp += 1
            if s.recvf: b = s.recvf(s.nrecv, b)
            s.nrecv += 1
            if b is not None: s.got += bytes([b]); s.since = s.now
        while True:
            r = s.req; val = None
            if r[0] == 'send':
                d = r[1]
                if s.sendf: d = s.sendf(s.nsend, d)
                s.nsend += 1
                t0 = max([s.now] + [t for t, _ in s.inq[-1:]])
                s.inq += [(t0 + (k + 1) * s.PER, x) for k, x in enumerate(d)]
            else:
                n, q = r[1], r[2]
                if len(s.got) >= n: val, s.got = s.got[:n], s.got[n:]
                elif s.now - s.since > q * SPS: val, s.got = s.got, b''
                else: return
            try: s.req = s.gen.send(val)
            except StopIteration as e:
                s.result = e.value; s.done = True; s.active = False; s.timed = None; s.seen = len(s.out); return
            s.since = max(s.now, s.inq[-1][0] if s.inq else 0)
    def feed_timed(s):
        s.tick()
        if s.done and s.rxp < len(s.inq) and s.now > s.inq[-1][0] + 2 * SPS: s.rxp = len(s.inq)   # never read
        if s.active or s.rxp < len(s.inq): s.timed = 1; return True     # (the last ACK: still on its way)
        s.timed = None; return False
    def ready(s):
        s.tick()
        return any(t <= s.now for t, _ in s.inq[s.rxp:s.rxp + 600])
    def read(s):
        s.tick()
        k = s.rxp
        while k < len(s.inq) and s.inq[k][0] <= s.now: k += 1
        if k == s.rxp: return 0
        s.lost += k - 1 - s.rxp; s.rxp = k
        return s.inq[k - 1][1]


def run(cf, keys, gen, later=(), sendf=None, recvf=None, cap=900_000_000):
    b = V.Elf2K(cf, keys=keys, later=list(later)); b.rtc = P3.clock()
    b.u = MacUART(keys, list(later), gen, sendf, recvf); b.u.board = b
    st = b.boot_rom(cap=cap)
    return b.u, st, b.text()


def files(img):
    def walk(m):
        r = {}
        for d, ds, fs in os.walk(m):
            ds[:] = [x for x in ds if not x.startswith('.')]     # (not the Mac's own .fseventsd and such)
            for f in fs:
                if f.startswith('.'): continue
                p = os.path.join(d, f); r[os.path.relpath(p, m)] = open(p, 'rb').read()
        return r
    return P2.mac(img, walk)[1]


def main():
    ok = True
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e]; ok &= not e
    quiet = lambda *a: None
    rnd = random.Random(1802)
    big = bytes(range(256)) * 4 + bytes(rnd.getrandbits(8) for _ in range(120 * 1024 - 1024 + 77))
    cf0, e2k, st = P1.installed_full(mem, NSEC)
    img0 = V.image(cf0, NSEC)

    def card(img):
        cf = P1.CV.CF(sectors=NSEC); P1.load_image(cf, img); return cf
    def check(img, t, e, want=None, gone=()):
        """the Mac's view: want = {path: bytes}; gone = paths that must not be there; fsck clean; FREE = fsck"""
        fl = files(img)
        for f, d in (want or {}).items():
            if fl.get(f) != d: e.append('%s: %s' % (f, 'missing' if f not in fl else '%d bytes, different' % len(fl[f])))
        for f in gone:
            if f in fl: e.append('%s is on the card' % f)
        rc, fr = P2.fsck_free(img)
        if rc != 0: e.append('fsck_msdos %d' % rc)
        m = re.findall(r'\((\d+) of (\d+) clusters', t)
        if not m or not fr or int(m[-1][0]) != fr[1]: e.append('FREE %s, fsck %s' % (m and m[-1][0], fr))
        return fl, fr
    def put(img, name, data, gen=None, yes=None, **kw):
        later = [('(Y/N) ', yes)] if yes else []
        later += [('LTOS> ', b'FREE\r'), ('LTOS> ', b'MON\r')]
        cf = card(img)
        u, st, t = run(cf, b'XFER -R %s\r' % name.encode(), gen or E.xput(data, quiet), later=later, **kw)
        if '-v' in sys.argv: print(t[-700:])
        return V.image(cf, NSEC), u, st, t
    def pull(img, name, **kw):
        cf = card(img)
        u, st, t = run(cf, b'XFER -S %s\r' % name.encode(), E.xpull(quiet), later=[('LTOS> ', b'MON\r')], **kw)
        if '-v' in sys.argv: print(t[-400:])
        return u, st, t

    # 1. a 120 KB file onto the card, then back
    img1, u, st, t = put(img0, 'BIG.BIN', big)
    e = []
    if u.result is not True: e.append('xput: %r' % u.result)
    if u.lost: e.append('%d characters lost (the UART overran)' % u.lost)
    if 'Saved BIG.BIN, %d bytes.' % len(big) not in t: e.append(repr(t[-300:]))
    _, fr1 = check(img1, t, e, {'BIG.BIN': big})
    report('XFER -R BIG.BIN: %d bytes at full speed, none lost; the Mac reads it exactly, fsck clean, FREE = fsck' % len(big), e)
    u, st, t = pull(img1, 'BIG.BIN')
    e = [] if u.result == big else ['xpull: %s' % (None if u.result is None else '%d bytes, different' % len(u.result))]
    if 'Sent BIG.BIN, %d bytes.' % len(big) not in t: e.append(repr(t[-300:]))
    report('XFER -S BIG.BIN: back on the Mac byte-identical', e)

    # 2. small sizes, and a folder
    img, _ = P2.mac(img1, lambda m: os.mkdir(os.path.join(m, 'DOCS')))
    e = []
    for n in (0, 1, 512, 513):
        d = bytes(rnd.getrandbits(8) for _ in range(n)); nm = 'DOCS/S%d.BIN' % n
        img, u, st, t = put(img, '/' + nm, d)
        if u.result is not True or u.lost: e.append('%d bytes: xput %r, %d lost' % (n, u.result, u.lost))
        check(img, t, e, {nm: d})
        u, st, t = pull(img, '/' + nm)
        if u.result != d: e.append('%d bytes: back as %r' % (n, u.result if u.result is None else len(u.result)))
    report('0, 1, 512 and 513 bytes, into /DOCS and back: exact', e)

    # 3. damage, Mac to card: a byte lost (send 4), a byte changed (send 7), the ACK for a block lost (byte 9)
    def sendf(k, d):
        if k == 4: return d[:100] + d[101:]
        if k == 7: return d[:300] + bytes([d[300] ^ 0x40]) + d[301:]
        return d
    acks = []
    def recvf(k, b):
        if b == 6: acks.append(k)
        return None if b == 6 and len(acks) == 9 else b
    med = big[:40000]
    img3, u, st, t = put(img0, 'MED.BIN', med, sendf=sendf, recvf=recvf)
    e = [] if u.result is True else ['xput: %r' % u.result]
    check(img3, t, e, {'MED.BIN': med})
    report('Mac to card: a lost byte, a changed byte, a lost ACK - each sent again; the file exact', e)

    # 4. damage, card to Mac: a byte changed in frame 3, a byte lost in frame 6, the Mac's ACK for frame 8 lost
    def recvf2(k, b):
        if k == 3 * 516 + 40: return b ^ 1
        if k == 6 * 516 + 200: return None
        return b
    nacks = []
    def sendf2(k, d):
        if d == E.ACK:
            nacks.append(k)
            if len(nacks) == 8: return b''
        return d
    u, st, t = pull(img3, 'MED.BIN', recvf=recvf2, sendf=sendf2)
    e = [] if u.result == med else ['xpull: %r' % (u.result if u.result is None else len(u.result))]
    report('Card to Mac: a changed byte, a lost byte, a lost ACK - each sent again; the file exact', e)

    # 5. a block always bad: refused after 10, nothing saved, the clusters given back
    def always(k, d): return d[:200] + bytes([d[200] ^ 0xFF]) + d[201:] if k >= 5 else d
    img5, u, st, t = put(img1, 'BAD.BIN', med, sendf=always)
    e = [] if u.result is False else ['xput: %r' % u.result]
    if '10 bad blocks in a row. Nothing was saved.' not in t: e.append(repr(t[-300:]))
    _, fr = check(img5, t, e, {'BIG.BIN': big}, gone=['BAD.BIN'])
    if fr != fr1: e.append('free: %s, before %s' % (fr, fr1))
    report('A block always bad: stopped after 10 tries, nothing saved, every cluster given back', e)

    # 6. replace: Y (the old clusters freed), N, and a replace that fails (the old file kept)
    new = bytes(rnd.getrandbits(8) for _ in range(70000))
    img6, u, st, t = put(img1, 'BIG.BIN', new, yes=b'Y')
    e = [] if u.result is True else ['xput: %r' % u.result]
    if 'replace it? (Y/N) Y' not in t: e.append(repr(t[-300:]))
    _, fr = check(img6, t, e, {'BIG.BIN': new})
    cl = fr1[0] * 1024 // fr1[1]                        # the cluster's bytes (fsck: KiB free, clusters free)
    want = fr1[1] + (len(big) + cl - 1) // cl - (len(new) + cl - 1) // cl
    if fr and fr[1] != want: e.append('free clusters %d, want %d' % (fr[1], want))
    report('XFER -R BIG.BIN again, Y: replaced, the old clusters freed', e)
    img, u, st, t = put(img1, 'BIG.BIN', new, yes=b'N')
    e = [] if not u.active and u.result is None else ['the transfer started']
    check(img, t, e, {'BIG.BIN': big})
    report('... N: nothing sent, the old file as it was', e)
    img, u, st, t = put(img1, 'BIG.BIN', new, yes=b'Y', sendf=always)
    e = [] if u.result is False else ['xput: %r' % u.result]
    _, fr = check(img, t, e, {'BIG.BIN': big})
    if fr != fr1: e.append('free: %s, before %s' % (fr, fr1))
    report('... Y, then it fails: the old file as it was, nothing lost', e)

    # 7. the card fills up partway: refused, the files kept, fsck clean
    def fill(m):
        st = os.statvfs(m); room = st.f_bavail * st.f_frsize
        open(os.path.join(m, 'FILL.BIN'), 'wb').write(b'\xAA' * (room - 60 * 1024))
    imgf, _ = P2.mac(img1, fill)
    _, frf = check(imgf, '(%d of 0 clusters' % P2.fsck_free(imgf)[1][1], [])
    img, u, st, t = put(imgf, 'NEW.BIN', big)
    e = [] if u.result is False else ['xput: %r' % u.result]
    if 'The card is full. Nothing was saved.' not in t: e.append(repr(t[-300:]))
    _, fr = check(img, t, e, {'BIG.BIN': big}, gone=['NEW.BIN'])
    if fr != frf: e.append('free: %s, before %s' % (fr, frf))
    img, u, st, t = put(imgf, 'BIG.BIN', big[::-1], yes=b'Y')
    if 'The card is full.' not in t: e.append('replacing: %r' % t[-300:])
    check(img, t, e, {'BIG.BIN': big})
    report('The card full partway (a new file, and replacing): refused, the old file kept, nothing lost', e)

    # 8. a stop from the Mac (block $FFFF, as elfser.py sends at Ctrl-C)
    def stopper():
        r = yield from E.xstart(quiet)
        for blk in range(3):
            yield ('send', E.xframe(blk, len(med).to_bytes(4, 'little') if blk == 0 else med[(blk - 1) * 512:blk * 512]))
            r = yield ('recv', 1, 10.0)
        yield ('send', E.xframe(0xFFFF, b''))
        r = yield ('recv', 1, 2.0)
        return r
    img, u, st, t = put(img1, 'STOP.BIN', med, gen=stopper())
    e = [] if u.result == E.CAN else ['the answer: %r' % u.result]
    if 'Stopped on the PC/Mac/Linux. Nothing was saved.' not in t: e.append(repr(t[-300:]))
    _, fr = check(img, t, e, {'BIG.BIN': big}, gone=['STOP.BIN'])
    if fr != fr1: e.append('free: %s, before %s' % (fr, fr1))
    report('Stopped from the Mac partway: nothing saved, every cluster given back', e)

    # 9. no name, a bad option, no such file
    cf = card(img1)
    b, st, t = P3.session(cf, b'XFER\rXFER -Q A\rXFER -S NOPE.BIN\rMON\r', rtc=P3.clock())
    e = []
    for w, c in (('XFER -R name', 'XFER\r'), ('XFER -R name', 'XFER -Q A\r'), ('There is no file NOPE.BIN', 'XFER -S NOPE.BIN\r')):
        if w not in P3.out(t, c): e.append('%r: %r' % (c, P3.out(t, c)[:120]))
    report('XFER, XFER -Q, XFER -S of a missing file: the usage, or why', e)

    print('XFER: %s' % ('ALL PASS' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
