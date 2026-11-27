#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/cardsync.py - a folder on the Mac kept as a mirror of every file and folder on an LTOS card: the CF card in
the Elf2K (over the serial port, with XFER), or with --emma the card image Emma 02 uses.

    python3 tools/cardsync.py [pull] [MIRROR]        card -> Mac: what changed on the card is copied, what went from
                                                     the card is set aside (default MIRROR ~/Elf2K-mirror)
    python3 tools/cardsync.py push [MIRROR]          Mac -> card: files new or edited in the mirror are sent to the card
    python3 tools/cardsync.py status [MIRROR]        what a pull and a push would do; nothing copied
    On a Windows PC:  py tools\\cardsync.py ...  (needs pyserial for the Elf2K:  py -m pip install pyserial)
    options:
      --port PORT   the Elf2K's serial port (a Mac: /dev/cu.usbserial-300005D8; a PC: the one USB serial port
                    there is, or COM3 and such)
      --emma [launcher|home|IMAGE]   Emma 02's card instead of the Elf2K (default launcher: the LTOS-Emma02 launcher's
                                     copy; home: ~/Emma 02/Elf2K/ltos-card.ide). Default MIRROR ~/Elf2K-mirror-emma
                                     (-emma-home for home). Close Emma 02 first. On a PC: --emma PATH.
      -n          say what would be done, do nothing
      --yes       push without asking
      --full      pull every file again, changed or not
      --force     use a mirror made from another card

The card is the master. A pull makes the mirror match it: a file is copied when its size or date on the card is not
what the last sync saw (so a rerun with nothing changed copies nothing); a file gone from the card is moved out of the
mirror to MIRROR/.cardsync/set-aside/<when>/, never deleted. A file edited on the Mac is kept as it is until the card's
copy changes: then the card's wins and the Mac's goes to set-aside. A push sends only files new or edited on the Mac
(and makes new folders); one changed on both sides is left for you. Deleting on the Mac deletes nothing on the card
(the next pull brings the file back): DELETE it on the Elf2K. LTOS cannot set a file's date, so a pushed file gets
the Elf2K's date; the push reads it back so the next pull does not copy the file again.
Hidden files are mirrored as plain files; .cardsync/state.json says which are hidden. The Mac's own files (.DS_Store, ._*)
and Windows's (Thumbs.db, desktop.ini) are ignored. Dates on the card are to the minute: a file rewritten in the same minute at the same size is not seen
(--full copies everything).
"""
import datetime, json, os, re, shutil, struct, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'LTOS'))
import cardfiles as CF

STATE = '.cardsync'
EMMA = {'launcher': os.path.expanduser('~/Library/Application Support/LTOS-Emma02/Emma 02/Elf2K/ltos-card.ide'),
        'home': os.path.expanduser('~/Emma 02/Elf2K/ltos-card.ide')}
NAME83 = re.compile(r'[A-Z0-9_~$!#%&\'()@^`{}-]{1,8}(\.[A-Z0-9_~$!#%&\'()@^`{}-]{1,3})?')
JUNK_DIRS = ('FSEVE~', 'SPOTL~', 'TRASH~', 'TEMPO~')    # the Mac's own folders, as 8.3 names


def junk(name):
    n = name.upper()
    return name.startswith('.') or any(n.startswith(j) for j in JUNK_DIRS)


def stamp(date):
    """'YYYY-MM-DD HH:MM' (a card date) -> seconds (local time), for the Mac copy's date."""
    try: return int(time.mktime(time.strptime(date, '%Y-%m-%d %H:%M')))
    except (ValueError, OverflowError): return None


def run(gen):
    """A session that never waits on a port (Emma's card): run it to its result."""
    try:
        while True: next(gen)
    except StopIteration as e: return e.value


# ---------------------------------------------------------------------------------------------------- the serial port
class Port:
    """The Elf2K's serial port, 19200 8N1: on a Mac termios, as elfser.py (no pyserial needed); on a PC pyserial
    (COM3 and such). Linux: termios, /dev/ttyUSB0 with --port."""
    def __init__(s, name=None):
        s.ser = s.fd = None
        if CF.E.termios is not None and not (name or '').upper().startswith('COM'):
            if name: CF.E.DEV = name
            s.name = CF.E.DEV; s.fd = CF.E.open_port()
            return
        try: import serial
        except ImportError:
            raise SystemExit('The serial port needs pyserial on this computer:  py -m pip install pyserial')
        s.name = name or s.find()
        s.ser = serial.Serial(s.name, 19200, bytesize=8, parity='N', stopbits=1, timeout=0.02, write_timeout=10,
                              xonxoff=False, rtscts=False, dsrdtr=False)

    @staticmethod
    def find():
        """The one USB serial port there is (more than one, or none: --port)."""
        import serial.tools.list_ports as lp
        usb = [p for p in lp.comports() if p.vid is not None]
        if len(usb) == 1: return usb[0].device
        have = ', '.join('%s (%s)' % (p.device, p.description) for p in lp.comports()) or 'none'
        raise SystemExit('Which serial port is the Elf2K on? Give --port COMn   (ports here: %s)' % have)

    def write(s, data):
        if s.ser: s.ser.write(data); s.ser.flush()
        else: CF.E.writeall(s.fd, data)

    def read(s, n):
        """Up to n bytes, waiting about 20 ms at most."""
        if s.ser: return s.ser.read(n)
        r, _, _ = CF.E.select.select([s.fd], [], [], 0.02)
        if not r: return b''
        try: return os.read(s.fd, n)
        except BlockingIOError: return b''

    def quiet(s, q=0.3, most=1.0):
        t0 = last = time.time()
        while time.time() - t0 < most:
            if s.read(4096): last = time.time()
            elif time.time() - last > q: break

    def run(s, gen):
        """A session (('send', bytes) / ('recv', n, quiet seconds) steps, as elfser.py's xrun) -> its result."""
        req = next(gen)
        while True:
            val = None
            if req[0] == 'send': s.write(req[1])
            else:
                n, q = req[1], req[2]; val = b''; last = time.time()
                while len(val) < n and time.time() - last < q:
                    d = s.read(n - len(val))
                    if d: val += d; last = time.time()
            try: req = gen.send(val)
            except StopIteration as e: return e.value

    def close(s):
        if s.ser: s.ser.close()
        else: os.close(s.fd)


def run_port(gen, name=None):
    port = Port(name); port.quiet()
    try: return port.run(gen)
    finally: port.close()


def emma_running():
    """Emma 02 open? (pgrep on a Mac or Linux, tasklist on Windows)"""
    try:
        if os.name == 'nt':
            r = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True, text=True)
            return any(ln.split(',')[0].strip('"').lower().startswith('emma') for ln in r.stdout.splitlines())
        if sys.platform == 'darwin':
            return subprocess.run(['pgrep', '-f', 'Emma 02.app/Contents/MacOS'], capture_output=True).returncode == 0
        return subprocess.run(['pgrep', '-i', 'emma'], capture_output=True).returncode == 0    # (the name, not -f:
                                                                   #  this very command may have "Emma 02" in it)
    except OSError: return False


# ---------------------------------------------------------------------------------------------------- the Elf2K
class Serial:
    """The Elf2K's card over the serial port. Every method is a generator of elfser.py's ('send'|'recv', ...) steps."""
    what = 'the Elf2K'
    def __init__(s, cr=True): s.cr = cr

    def open(s, say):
        if not (yield from CF.start(s.cr, say)): return None
        return CF.card_name((yield from CF.cmd('DISKINFO -Q', 20.0)))

    def walk(s, say, top='/'):
        """-> ({path: (size, date, hidden)}, {folder paths})"""
        files, dirs, todo = {}, set(), [top]
        while todo:
            folder = todo.pop(0)
            for n, sz, d, h in (yield from CF.listing(folder, say)):
                p = CF.join(folder, n)
                if junk(n): continue
                if sz is None: dirs.add(p); todo.append(p)
                else: files[p] = (sz, d, h)
        return files, dirs

    def get(s, path, say): return (yield from CF.pull(path, say))

    def write(s, mkdirs, puts, say):
        """Folders made, files sent -> the paths not sent."""
        for d in mkdirs: yield from CF.cmd('MKDIR ' + d)
        bad = []
        for k, (p, data) in enumerate(puts, 1):
            ok = yield from CF.put(p, data, say)
            say('  %3d/%d  -> %-28s %7d bytes%s' % (k, len(puts), p, len(data), '' if ok else '  ** NOT SENT'))
            if not ok: bad.append(p)
        return bad

    def close(s):
        if False: yield


# ---------------------------------------------------------------------------------------------------- Emma 02
class Image:
    """An Emma 02 card image (a raw IDE disk: MBR, one FAT16 partition). Read straight from the file; written by
    changing its FAT16 in Python (no mount, so on a PC too). The methods are generators too, that never wait."""
    def __init__(s, path, check=True):
        s.path = path; s.check = check; s.what = 'the Emma 02 card ' + path

    def open(s, say):
        if False: yield
        if not os.path.exists(s.path): say('** No card image at %s' % s.path); return None
        if s.check and emma_running():
            say('** Close Emma 02 first (LTOS keeps the FAT in memory: the card image is not settled while it runs).')
            return None
        s.img = bytearray(open(s.path, 'rb').read())
        ps = struct.unpack_from('<I', s.img, 0x1C6)[0] * 512; b = s.img[ps:ps + 512]
        s.bps, s.spc, res, s.nf, s.nroot = struct.unpack_from('<H', b, 11)[0], b[13], struct.unpack_from('<H', b, 14)[0], b[16], struct.unpack_from('<H', b, 17)[0]
        s.fsz = struct.unpack_from('<H', b, 22)[0]
        s.fat = ps + res * s.bps; s.root = s.fat + s.nf * s.fsz * s.bps; s.data = s.root + s.nroot * 32
        tot = struct.unpack_from('<H', b, 19)[0] or struct.unpack_from('<I', b, 32)[0]
        s.nclus = min((ps + tot * s.bps - s.data) // (s.spc * s.bps) + 2, s.fsz * s.bps // 2, 0xFFF7)
        return 'image, %d MB' % (tot * s.bps // 1048576)

    def chain(s, c):
        out = []
        while 2 <= c < 0xFFF8 and len(out) < 65536:
            out.append(c); c = struct.unpack_from('<H', s.img, s.fat + 2 * c)[0]
        return out

    def clus(s, c): return s.data + (c - 2) * s.spc * s.bps

    def entries(s, first):
        """A folder's entries (first cluster; 0 = the root) -> [(name, attr, size, date, cluster)]."""
        if first == 0: raw = s.img[s.root:s.root + s.nroot * 32]
        else: raw = b''.join(s.img[s.clus(c):s.clus(c) + s.spc * s.bps] for c in s.chain(first))
        out, lfn = [], ''
        for o in range(0, len(raw), 32):
            e = raw[o:o + 32]
            if e[0] == 0: break
            if e[0] == 0xE5: lfn = ''; continue
            if e[11] == 0x0F:                       # a long name's piece (the Mac's ._ files have them)
                part = (e[1:11] + e[14:26] + e[28:32]).decode('utf-16-le', 'replace').split('\0')[0]
                lfn = part + lfn if not e[0] & 0x40 else part; continue
            long_, lfn = lfn, ''
            if e[11] & 0x08: continue               # the volume label
            n, x = e[:8].decode('latin1').rstrip(), e[8:11].decode('latin1').rstrip()
            if n[:1] == '\x05': n = '\xe5' + n[1:]
            name = n + ('.' + x if x else '')
            if name in ('.', '..') or long_.startswith('.'): continue
            t, d = struct.unpack_from('<HH', e, 22)
            date = '%04d-%02d-%02d %02d:%02d' % (1980 + (d >> 9), (d >> 5) & 15, d & 31, t >> 11, (t >> 5) & 63)
            out.append((name, e[11], struct.unpack_from('<I', e, 28)[0], date, struct.unpack_from('<H', e, 26)[0]))
        return out

    def walk(s, say, top='/'):
        if False: yield
        files, dirs, todo = {}, set(), [('/', 0)]
        s.where = {}
        while todo:
            folder, c = todo.pop(0)
            for n, a, sz, d, fc in s.entries(c):
                p = CF.join(folder, n)
                if junk(n): continue
                if a & 0x10: dirs.add(p); todo.append((p, fc))
                else: files[p] = (sz, d, bool(a & 0x02)); s.where[p] = (fc, sz)
        return files, dirs

    def get(s, path, say):
        if False: yield
        fc, sz = s.where[path]
        return b''.join(s.img[s.clus(c):s.clus(c) + s.spc * s.bps] for c in s.chain(fc))[:sz]

    # ---- writing: the FAT16 changed in memory, then the image file replaced in one go (no mount: on any computer)
    def setfat(s, c, v):
        for k in range(s.nf): struct.pack_into('<H', s.img, s.fat + k * s.fsz * s.bps + 2 * c, v)

    def alloc(s, n):
        """n free clusters, chained and zeroed -> the first (0 for none)."""
        got = []
        for c in range(2, s.nclus):
            if len(got) == n: break
            if struct.unpack_from('<H', s.img, s.fat + 2 * c)[0] == 0: got.append(c)
        if len(got) < n: raise OSError('the card is full')
        for a, b in zip(got, got[1:] + [0xFFFF]): s.setfat(a, b)
        for c in got: s.img[s.clus(c):s.clus(c) + s.spc * s.bps] = bytes(s.spc * s.bps)
        return got[0] if got else 0

    def lookup(s, path):
        """A folder's path -> its first cluster (0: the root)."""
        c = 0
        for part in [x for x in path.strip('/').split('/') if x]:
            hit = [e for e in s.entries(c) if e[0].upper() == part.upper() and e[1] & 0x10]
            if not hit: raise OSError('no folder ' + path)
            c = hit[0][4]
        return c

    def slots(s, c):
        """Where a folder's 32-byte entries are in the image."""
        if c == 0: return list(range(s.root, s.root + s.nroot * 32, 32))
        return [s.clus(x) + o for x in s.chain(c) for o in range(0, s.spc * s.bps, 32)]

    @staticmethod
    def short(name):
        if name in ('.', '..'): return name.ljust(11).encode()
        n, x = (name.upper().split('.') + [''])[:2]
        return (n.ljust(8) + x.ljust(3)).encode('latin1')

    def entry(s, folder, name):
        """-> (offset of name's entry, True) or (a free entry's, False); a full subfolder grows a cluster."""
        c = s.lookup(folder); want = s.short(name); free = None
        for o in s.slots(c):
            e = s.img[o]
            if e == 0:
                if free is None: free = o
                break
            if e == 0xE5:
                if free is None: free = o
                continue
            if bytes(s.img[o:o + 11]) == want and s.img[o + 11] != 0x0F: return o, True
        if free is not None: return free, False
        if c == 0: raise OSError('the root folder is full')
        last = s.chain(c)[-1]; n = s.alloc(1); s.setfat(last, n)
        return s.clus(n), False

    def put_entry(s, o, name, attr, clus, size):
        t = time.localtime()
        tm = (t.tm_hour << 11) | (t.tm_min << 5) | (t.tm_sec // 2)
        dt = ((max(t.tm_year, 1980) - 1980) << 9) | (t.tm_mon << 5) | t.tm_mday
        s.img[o:o + 32] = s.short(name) + bytes([attr, 0, 0]) + struct.pack('<HHHHHHHI', tm, dt, dt, 0, tm, dt, clus, size)

    def mkdir(s, path):
        folder, name = path.rsplit('/', 1); folder = folder or '/'
        o, found = s.entry(folder, name)
        if found: return
        parent = s.lookup(folder); c = s.alloc(1)
        s.put_entry(o, name, 0x10, c, 0)
        s.put_entry(s.clus(c), '.', 0x10, c, 0)
        s.put_entry(s.clus(c) + 32, '..', 0x10, parent, 0)

    def write_file(s, path, data):
        folder, name = path.rsplit('/', 1)
        o, found = s.entry(folder or '/', name)
        attr, old = 0x20, []
        if found:                                   # replaced: its clusters freed, hidden kept
            attr = (s.img[o + 11] & 0x07) | 0x20
            old = s.chain(struct.unpack_from('<H', s.img, o + 26)[0])
            for x in old: s.setfat(x, 0)
        cs = s.spc * s.bps
        try: c = s.alloc((len(data) + cs - 1) // cs)
        except OSError:                             # (too big: the old file left as it was)
            for a, b in zip(old, old[1:] + [0xFFFF]): s.setfat(a, b)
            raise
        for k, x in enumerate(s.chain(c) if c else []):
            s.img[s.clus(x):s.clus(x) + cs] = data[k * cs:(k + 1) * cs].ljust(cs, b'\0')
        s.put_entry(o, name, attr, c, len(data))

    def write(s, mkdirs, puts, say):
        if False: yield
        if s.check and emma_running():
            say('** Close Emma 02 first.'); return [p for p, _ in puts]
        bad = []
        try:
            for d in mkdirs: s.mkdir(d)
        except OSError as e: say('** %s' % e); return [p for p, _ in puts]
        for k, (p, data) in enumerate(puts, 1):
            try:
                s.write_file(p, data)
                say('  %3d/%d  -> %-28s %7d bytes' % (k, len(puts), p, len(data)))
            except OSError as e: bad.append(p); say('** %s: %s' % (p, e))
        tmp = s.path + '.cardsync-tmp'
        with open(tmp, 'wb') as f: f.write(s.img)
        shutil.copymode(s.path, tmp); os.replace(tmp, s.path)
        return bad

    def close(s):
        if False: yield


# ---------------------------------------------------------------------------------------------------- the mirror
class Mirror:
    def __init__(s, root):
        s.root = os.path.abspath(os.path.expanduser(root)); s.sf = os.path.join(s.root, STATE, 'state.json')
        s.st = json.load(open(s.sf)) if os.path.exists(s.sf) else {'files': {}, 'folders': []}
        s.when = datetime.datetime.now().strftime('%Y-%m-%d-%H%M%S')

    def mac(s, p): return os.path.join(s.root, *p.strip('/').split('/'))

    def macstat(s, p):
        try: x = os.stat(s.mac(p)); return (x.st_size, int(x.st_mtime))
        except OSError: return None

    def mac_changed(s, p):
        """The Mac's copy is not what the last sync wrote (None: there is no Mac copy)."""
        m = s.macstat(p); f = s.st['files'].get(p)
        if m is None: return None
        return f is None or m != (f['msize'], f['mtime'])

    def mac_files(s):
        """The files and folders in the mirror (card-style paths), the Mac's own files left out."""
        files, dirs = set(), set()
        for d, ds, fs in os.walk(s.root):
            ds[:] = [x for x in ds if not x.startswith('.')]
            rel = os.path.relpath(d, s.root)
            base = '' if rel == '.' else '/' + rel.replace(os.sep, '/')
            for x in ds: dirs.add(base + '/' + x)
            for x in fs:
                if not x.startswith('.') and x not in ('Icon\r', 'Thumbs.db', 'desktop.ini') and not x.endswith('.cardsync-tmp'):
                    files.add(base + '/' + x)
        return files, dirs

    def set_aside(s, p, say, why):
        src = s.mac(p)
        if not os.path.exists(src): return
        dst = os.path.join(s.root, STATE, 'set-aside', s.when, *p.strip('/').split('/'))
        os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.move(src, dst)
        say('  set aside  %-28s (%s)' % (p, why))

    def store(s, p, data, size, date, hidden):
        q = s.mac(p); os.makedirs(os.path.dirname(q), exist_ok=True)
        tmp = q + '.cardsync-tmp'
        with open(tmp, 'wb') as f: f.write(data)
        os.replace(tmp, q)
        t = stamp(date)
        if t: os.utime(q, (t, t))
        s.record(p, size, date, hidden)

    def record(s, p, size, date, hidden):
        m = s.macstat(p) or (None, None)
        s.st['files'][p] = {'size': size, 'date': date, 'hidden': hidden, 'msize': m[0], 'mtime': m[1]}

    def save(s, card, source):
        s.st.update(card=card, source=source, synced=datetime.datetime.now().isoformat(timespec='seconds'))
        os.makedirs(os.path.dirname(s.sf), exist_ok=True)
        tmp = s.sf + '.tmp'; json.dump(s.st, open(tmp, 'w'), indent=1, sort_keys=True); os.replace(tmp, s.sf)


def pull_plan(m, files, dirs, full=False):
    """-> (to copy [(path, why)], gone from the card [paths], Mac-edited and kept [paths])."""
    copy, gone, kept = [], [], []
    for p, (sz, d, h) in sorted(files.items()):
        f = m.st['files'].get(p); mc = m.mac_changed(p)
        if full: copy.append((p, 'all'))
        elif mc is None: copy.append((p, 'new' if f is None else 'missing on the Mac'))
        elif f is None or (f['size'], f['date']) != (sz, d): copy.append((p, 'changed' if f else 'new'))
        elif mc: kept.append(p)
    for p in sorted(m.st['files']):
        if p not in files: gone.append(p)
    return copy, gone, kept


def push_plan(m, files, dirs):
    """-> (folders to make, files to send [path], left: [(path, why)])."""
    mfiles, mdirs = m.mac_files()
    send, left = [], []
    for p in sorted(mfiles):
        if p.startswith('/' + STATE): continue
        f = m.st['files'].get(p)
        up = p.upper()
        if not all(NAME83.fullmatch(x) for x in up.strip('/').split('/')):
            left.append((p, 'not an 8.3 name')); continue
        if f is not None and not m.mac_changed(p): continue          # as the last sync left it
        if f is None and up in files and p != up: continue           # (the card's own, with the Mac's case)
        if f is None and up in files: left.append((p, 'on the card already, never synced: pull first')); continue
        if f is not None and up in files and (f['size'], f['date']) != files[up][:2]:
            left.append((p, 'changed on the card too: pull sets the Mac copy aside')); continue
        send.append(p)
    want = {x.upper() for p in send for x in ['/'.join(p.split('/')[:k]) for k in range(2, p.count('/') + 1)]}
    mk = sorted((want | {d.upper() for d in mdirs if not d.startswith('/' + STATE)}) - dirs, key=lambda x: x.count('/'))
    return mk, send, left


# ---------------------------------------------------------------------------------------------------- the sessions
def session(card, m, mode, say, full=False, dry=False, force=False, ask=None, source=''):
    """The whole sync (a generator, as elfser.py's sessions are): -> a summary dict, or None (nothing done)."""
    name = yield from card.open(say)
    if name is None: return None
    say('The card: %s' % name)
    if m.st.get('card') and m.st['card'] != name and not force:
        say('** This mirror was made from another card (%s). --force to use it anyway.' % m.st['card']); return None
    t0 = time.time()
    files, dirs = yield from card.walk(say)
    say('%d folders, %d files, %d bytes on the card (%.0f s to list)' % (len(dirs), len(files), sum(f[0] for f in files.values()), time.time() - t0))
    out = {'copied': [], 'gone': [], 'kept': [], 'sent': [], 'left': [], 'failed': []}

    if mode in ('pull', 'status'):
        copy, gone, kept = pull_plan(m, files, dirs, full)
        out.update(gone=gone, kept=kept)
        for p in kept: say('  kept       %-28s (edited on the Mac; push sends it)' % p)
        if mode == 'status' or dry:
            for p, why in copy: say('  would copy %-28s %7d bytes (%s)' % (p, files[p][0], why))
            for p in gone: say('  would set aside %s (gone from the card)' % p)
            out['copied'] = [p for p, _ in copy]
        else:
            for d in sorted(dirs): os.makedirs(m.mac(d), exist_ok=True)
            for p in gone:
                m.set_aside(p, say, 'gone from the card'); del m.st['files'][p]
            for k, (p, why) in enumerate(copy, 1):
                sz, d, h = files[p]
                if m.mac_changed(p): m.set_aside(p, say, 'edited on the Mac, changed on the card too: the card\'s wins')
                data = yield from card.get(p, say)
                if data is None or len(data) != sz:
                    out['failed'].append(p); say('** %s: %s' % (p, 'not read' if data is None else '%d bytes, not %d' % (len(data), sz)))
                    continue
                m.store(p, data, sz, d, h); out['copied'].append(p)
                say('  %3d/%d  <- %-28s %7d bytes  (%s)%s' % (k, len(copy), p, sz, why, '  hidden' if h else ''))
            for p, (sz, d, h) in files.items():                    # hidden or shown since: noted
                f = m.st['files'].get(p)
                if f and f['hidden'] != h: f['hidden'] = h
            for d in sorted(set(m.st['folders']) - dirs, key=len, reverse=True):     # folders gone from the card
                q = m.mac(d)
                if os.path.isdir(q) and not [x for x in os.listdir(q) if x != '.DS_Store']:
                    shutil.rmtree(q, ignore_errors=True)
                elif os.path.isdir(q): say('  folder %s is gone from the card; the Mac\'s files in it are kept' % d)
            m.st['folders'] = sorted(dirs)
            m.save(name, source)

    if mode in ('push', 'status'):
        mk, send, left = push_plan(m, files, dirs)
        out['left'] = left
        for p, why in left: say('  not sent   %-28s (%s)' % (p, why))
        if mode == 'status' or dry or not (send or mk):
            for d in mk: say('  would make folder %s' % d)
            for p in send: say('  would send %-28s %7d bytes' % (p, m.macstat(p)[0]))
            out['sent'] = send
        elif ask is None or ask(len(send), len(mk)):
            for p in send:
                if p != p.upper():                                  # the card's name, on the Mac too
                    tmp = m.mac(p) + '.cardsync-case'; os.rename(m.mac(p), tmp); os.rename(tmp, m.mac(p.upper()))
            send = [p.upper() for p in send]
            bad = yield from card.write(mk, [(p, open(m.mac(p), 'rb').read()) for p in send], say)
            out['failed'] += bad; out['sent'] = [p for p in send if p not in bad]
            # the card's own size and date for what was sent, so a pull does not copy it back
            touched = sorted({p.rsplit('/', 1)[0] or '/' for p in out['sent']})
            now = {}
            if isinstance(card, Serial):
                for folder in touched:
                    for n, sz, d, h in (yield from CF.listing(folder, say)): now[CF.join(folder, n)] = (sz, d, h)
            else:
                now, _ = yield from card.walk(say)
            for p in out['sent']:
                if p in now and now[p][0] == m.macstat(p)[0]:
                    m.record(p, now[p][0], now[p][1], now[p][2])
                else: out['failed'].append(p); say('** %s: the card has %s' % (p, now.get(p)))
            m.st['folders'] = sorted(set(m.st['folders']) | set(mk))
            m.save(name, source)
        else: say('Nothing sent.'); out['sent'] = []
    yield from card.close()
    return out


def main(argv):
    a = list(argv)
    flags = {f for f in ('-n', '--yes', '--full', '--force') if f in a}
    a = [x for x in a if x not in flags]
    emma = None
    if '--emma' in a:
        i = a.index('--emma'); del a[i]
        emma = 'launcher'
        if i < len(a) and (a[i] in EMMA or a[i].endswith('.ide')): emma = a.pop(i)
    port = None
    if '--port' in a:
        i = a.index('--port'); port = a[i + 1]; del a[i:i + 2]
    if any(x.startswith('-') for x in a): raise SystemExit(__doc__)
    mode = a.pop(0) if a and a[0] in ('pull', 'push', 'status') else 'pull'
    if len(a) > 1: raise SystemExit(__doc__)
    default = '~/Elf2K-mirror' if emma is None else '~/Elf2K-mirror-emma' + ('' if emma == 'launcher' else '-home' if emma == 'home' else '-' + os.path.splitext(os.path.basename(emma))[0])
    m = Mirror(a[0] if a else default)
    say = lambda s: print(s, flush=True)
    if emma:
        if emma in EMMA and sys.platform != 'darwin':
            raise SystemExit('Where is Emma 02\'s card here? Give it:  --emma PATH\\TO\\ltos-card.ide')
        img = os.path.abspath(os.path.expanduser(EMMA.get(emma, emma)))
        card, source = Image(img), 'emma:' + img
    else:
        card, source = Serial(), 'elf2k'
    if m.st.get('source') and m.st['source'] != source and not flags & {'--force'}:
        raise SystemExit('This mirror is synced with %s, not %s. --force to use it anyway.' % (m.st['source'], source))
    say('%s %s  <->  %s' % (mode, card.what, m.root))

    def ask(n, k):
        if '--yes' in flags: return True
        return input('Send %d file%s%s to %s? (y/N) ' % (n, 's' * (n != 1), ' and make %d folder%s' % (k, 's' * (k != 1)) if k else '', card.what)).strip().lower() == 'y'
    t0 = time.time()
    gen = session(card, m, mode, say, full='--full' in flags, dry='-n' in flags, force='--force' in flags, ask=ask, source=source)
    out = run_port(gen, port) if isinstance(card, Serial) else run(gen)
    if out is None: raise SystemExit(1)
    verb = 'would be ' if mode == 'status' or '-n' in flags else ''
    parts = []
    if mode != 'push': parts += ['%d copied to the Mac' % len(out['copied']), '%d set aside' % len(out['gone'])]
    if mode != 'pull': parts += ['%d sent to the card' % len(out['sent'])]
    if out['kept']: parts.append('%d edited on the Mac' % len(out['kept']))
    if out['left']: parts.append('%d not sent' % len(out['left']))
    say('%s: %s%s (%.0f s)%s' % ('Status' if mode == 'status' else 'Done', verb, ', '.join(parts), time.time() - t0,
                                ('\n** FAILED: ' + ', '.join(out['failed'])) if out['failed'] else ''))
    if out['failed']: raise SystemExit(1)


if __name__ == '__main__':
    main(sys.argv[1:])
