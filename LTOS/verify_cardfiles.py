# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""cardfiles.py's backup and restore sessions, run against the simulated Elf2K (the real ROM, the CF card model,
19200 baud, a UART that holds ONE byte): a 32 MB card with folders, a folder in a folder, a hidden file, an empty
file, a binary file and a STELLAR app is backed up - every file byte for byte, its size, hidden or not - then restored
onto a fresh 8 MB LTOS card: the Mac reads that card and finds the same files, the hidden one hidden, the card's own
LTOS left as it was (and replaced with --all), fsck clean. A restore over the same files again replaces them.

    python3 LTOS/verify_cardfiles.py [-v]
"""
import os, random, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import verify_phase3 as P3
import verify_xfer as VX
import build, cardfiles as CF

SPS = VX.SPS


class SessionUART(V.UART):
    """The Mac at the serial port from power-on: the generator gen runs the whole session."""
    def __init__(s, gen):
        super().__init__(b'', []); s.out = VX.Out(s)
        s.gen = gen; s.req = next(gen); s.done = False; s.result = None
        s.inq = []; s.rxp = 0; s.outp = 0; s.got = b''; s.since = 0; s.board = None
    def tick(s):
        if s.board is not None: s.now = max(s.now, s.board.steps)
        while s.outp < len(s.out): s.got += bytes([s.out[s.outp]]); s.outp += 1; s.since = s.now
        if s.done: return
        while True:
            r = s.req; val = None
            if r[0] == 'send':
                t0 = max([s.now] + [t for t, _ in s.inq[-1:]])
                s.inq += [(t0 + (k + 1) * s.PER, x) for k, x in enumerate(r[1])]
            else:
                n, q = r[1], r[2]
                if len(s.got) >= n: val, s.got = s.got[:n], s.got[n:]
                elif s.now - s.since > q * SPS: val, s.got = s.got, b''
                else: return
            try: s.req = s.gen.send(val)
            except StopIteration as e: s.result = e.value; s.done = True; return
            s.since = max(s.now, s.inq[-1][0] if s.inq else 0)
    def feed_timed(s):
        s.tick()
        if s.rxp < len(s.inq) or not s.done: s.timed = 1; return True
        s.timed = None; return False
    def ready(s):
        s.tick(); return any(t <= s.now for t, _ in s.inq[s.rxp:s.rxp + 600])
    def read(s):
        s.tick(); k = s.rxp
        while k < len(s.inq) and s.inq[k][0] <= s.now: k += 1
        if k == s.rxp: return 0
        s.lost += k - 1 - s.rxp; s.rxp = k
        return s.inq[k - 1][1]


def session(cf, gen, cap=4_000_000_000):
    def whole():
        r = yield from gen
        yield from CF.typed('MON')                 # (the simulator stops at the monitor)
        return r
    b = V.Elf2K(cf, keys=b'', later=[]); b.rtc = P3.clock()
    b.u = SessionUART(whole()); b.u.board = b
    st = b.boot_rom(cap=cap)
    return b.u, st, b.text()


def set_hidden(img, path):
    """The hidden bit on a root file's entry (as HIDE does)."""
    ps = struct.unpack_from('<I', img, 0x1C6)[0]; v = ps * 512
    res, nf, fsz, nroot = struct.unpack_from('<H', img, v + 14)[0], img[v + 16], struct.unpack_from('<H', img, v + 22)[0], struct.unpack_from('<H', img, v + 17)[0]
    root = (ps + res + nf * fsz) * 512
    n, x = (path.strip('/').split('.') + [''])[:2]
    want = (n.ljust(8) + x.ljust(3)).encode()
    for o in range(root, root + nroot * 32, 32):
        if bytes(img[o:o + 11]) == want: img[o + 11] |= 2; return
    raise SystemExit('no ' + path)


def attr_hidden(img, path):
    ps = struct.unpack_from('<I', img, 0x1C6)[0]; v = ps * 512
    res, nf, fsz, nroot = struct.unpack_from('<H', img, v + 14)[0], img[v + 16], struct.unpack_from('<H', img, v + 22)[0], struct.unpack_from('<H', img, v + 17)[0]
    root = (ps + res + nf * fsz) * 512
    n, x = (path.strip('/').split('.') + [''])[:2]
    want = (n.ljust(8) + x.ljust(3)).encode()
    for o in range(root, root + nroot * 32, 32):
        if bytes(img[o:o + 11]) == want: return bool(img[o + 11] & 2)
    return None


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:15]]; ok &= not e
    say = print if v else (lambda *a: None)
    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    rnd = random.Random(7)
    user = {'/DOCS/LETTER.TXT': b'Dear reader,\r\nA letter.\r\n', '/DOCS/OLD/NOTES.TXT': b'old notes\n' * 40,
            '/MUSIC/ODE.MUS': open(os.path.join(HERE, 'music', 'ODE.MUS'), 'rb').read(), '/ROOT.TXT': b'in the root\n',
            '/SECRET.TXT': b'hidden\n', '/EMPTY.TXT': b'', '/DATA.BIN': bytes(rnd.getrandbits(8) for _ in range(3000)),
            '/BIN/MYAPP.STL': bytes(rnd.getrandbits(8) for _ in range(1536))}
    # card A: 32 MB, LTOS installed, the user's files on it
    NA, NB = 62720, 16384
    cfa, _, _ = P1.installed_full(mem, NA)
    def put(m):
        for p, d in user.items():
            q = os.path.join(m, *p.strip('/').split('/')); os.makedirs(os.path.dirname(q), exist_ok=True); open(q, 'wb').write(d)
        for dd, ds, fs in os.walk(m):              # (not the Mac's own ._ files: a card written by dd has none)
            for f in fs:
                if f.startswith('._'): os.remove(os.path.join(dd, f))
    imga, _ = P2.mac(V.image(cfa, NA), put)
    imga = bytearray(imga); set_hidden(imga, '/SECRET.TXT')
    P1.load_image(cfa, bytes(imga))
    on_a = VX.files(bytes(imga))

    e = []
    u, st, t = session(cfa, CF.backup_session(say, cr=False))
    man, datas = u.result if u.result else ({'files': [], 'folders': [], 'not_read': []}, {})
    if v: print(t[-600:])
    if st != 'stop': e.append('the session ended: %s %r' % (st, t[-300:]))
    want = {'/' + k.replace(os.sep, '/').upper(): d for k, d in on_a.items()}
    for p, d in want.items():
        if datas.get(p) != d: e.append('%s: %s' % (p, 'missing' if p not in datas else '%d bytes, not the same' % len(datas[p])))
    extra = set(datas) - set(want)
    if extra: e.append('more than the card has: %r' % sorted(extra))
    hid = {f['path'] for f in man['files'] if f['hidden']}
    if hid != {'/SECRET.TXT'}: e.append('hidden: %r' % hid)
    if {d['path'] for d in man['folders']} != {'/BIN', '/DOCS', '/DOCS/OLD', '/MUSIC', '/BIBLE'} - ({'/BIBLE'} if not any(p.startswith('/BIBLE') for p in want) else set()):
        e.append('folders: %r' % sorted(d['path'] for d in man['folders']))
    if 'Model:' not in man.get('diskinfo', ''): e.append('DISKINFO: %r' % man.get('diskinfo', '')[:80])
    if u.lost: e.append('%d characters lost at the UART' % u.lost)
    report('backup of a 32 MB card: every file (%d, %d bytes) byte for byte, folders in folders, the hidden one marked, '
           'DISKINFO kept' % (len(datas), sum(map(len, datas.values()))), e)

    # card B: 8 MB, a fresh LTOS: the backup restored (its own LTOS left alone)
    e = []
    cfb, _, _ = P1.installed_full(mem, NB)
    imgb0 = V.image(cfb, NB); on_b0 = VX.files(imgb0)
    u, st, t = session(cfb, CF.restore_session(man, datas, say, cr=False))
    if v: print(t[-800:])
    if st != 'stop' or u.result is None: e.append('the session ended: %s %r' % (st, t[-300:]))
    elif u.result: e.append('it said: %r' % u.result)
    imgb = V.image(cfb, NB); on_b = VX.files(imgb)
    for p, d in user.items():
        k = p.strip('/').replace('/', os.sep)
        if on_b.get(k) != d: e.append('%s: %s' % (p, 'missing' if k not in on_b else 'not the same'))
    for k, d in on_b0.items():
        if CF.is_system('/' + k.replace(os.sep, '/')) and on_b.get(k) != d: e.append('%s: the card\'s own LTOS changed' % k)
    if not attr_hidden(imgb, '/SECRET.TXT'): e.append('/SECRET.TXT is not hidden')
    rc, _ = P2.fsck_free(imgb)
    if rc: e.append('fsck_msdos: %d' % rc)
    if u.lost: e.append('%d characters lost at the UART' % u.lost)
    report('restore onto a fresh 8 MB card: the files there byte for byte, the hidden one hidden, the card\'s own LTOS '
           'left as it was, DIR sizes and FSCK checked by the session, fsck clean', e)

    # again over the same files, with --all: replaced, and the system ones too
    e = []
    u, st, t = session(cfb, CF.restore_session(man, datas, say, everything=True, cr=False))
    imgb2 = V.image(cfb, NB); on_b2 = VX.files(imgb2)
    if st != 'stop' or u.result: e.append('%s %r' % (st, u.result))
    for p, d in datas.items():
        k = p.strip('/').replace('/', os.sep)
        if on_b2.get(k) != d: e.append('%s: %s' % (p, 'missing' if k not in on_b2 else 'not the same'))
    rc, _ = P2.fsck_free(imgb2)
    if rc: e.append('fsck_msdos: %d' % rc)
    report('restore --all over it again: every file replaced (Y to "replace it?"), the card\'s LTOS files as the backup\'s, '
           'fsck clean', e)
    print('\nCARDFILES: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
