#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/cardfiles.py - the FILES on the Elf2K's CF card backed up to the Mac, and put back on any LTOS card (not an
image: a backup of a 32 MB card goes back on an 8 MB one, and the other way round). Over the serial port, with XFER.

    python3 LTOS/cardfiles.py backup [FOLDER]        every file and folder, hidden ones too, into FOLDER
                                                     (default ~/Elf2K-backups/card-YYYY-MM-DD-HHMM)
    python3 LTOS/cardfiles.py restore FOLDER [--all] [--yes]
                                                     the folders made, the files sent back (replacing any of the
                                                     same name), hidden ones hidden again; then DIR sizes and FSCK
    python3 LTOS/cardfiles.py list FOLDER            what a backup holds

The card must already have LTOS on it (to restore onto a new card: install LTOS, elfser.py system, then restore).
Restore leaves the card's own LTOS alone unless --all: /STELLAR.BIN, the programs in /BIN (.PRG .OVL), the help files
(/*.HLP) and /NANO.OVL - they go with its kernel ("Not for this kernel" otherwise). STELLAR apps (.STL), documents,
songs, scripts are all restored. Files get the date they are written (LTOS cannot set a file's date).
A backup keeps FOLDER/MANIFEST.json (each path, size, date, hidden or not; the card's DISKINFO) and the files in the
card's own folders. About 1.5 KB a second, plus a few seconds a file to start XFER.

Everything is one generator (the session) yielding ('send', bytes) / ('recv', n, quiet seconds) as elfser.py's XFER
code does, so verify_cardfiles.py runs the very same session against the simulated Elf2K.
"""
import datetime, json, os, re, select, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import elfser as E

PROMPT = b'LTOS> '
SKIP_DIRS = ('.', '..')


def is_system(path):
    """The card's own LTOS: left alone by restore unless --all."""
    p = path.upper()
    d, n = p.rsplit('/', 1)
    ext = n.rsplit('.', 1)[1] if '.' in n else ''
    return (p == '/STELLAR.BIN' or p == '/NANO.OVL' or (d == '' and ext == 'HLP') or (d == '/BIN' and ext in ('PRG', 'OVL')))


# ---------------------------------------------------------------------------------------------------- the session
def until(pats, quiet=8.0, most=600.0):
    """What comes, to one of pats (bytes) or quiet seconds of nothing -> the bytes (most: give up after that)."""
    got, t = b'', 0.0
    while True:
        d = yield ('recv', 1, quiet)
        if not d: return got
        got += d
        if any(got.endswith(p) for p in pats): return got


def typed(line):
    """A line typed at the Elf2K's pace: each character as its echo comes back."""
    for ch in (line + '\r').encode():
        yield ('send', bytes([ch]))
        yield ('recv', 1, 0.5)


def cmd(line, quiet=10.0):
    yield from typed(line)
    out = yield from until([PROMPT], quiet)
    return out.decode('latin1').replace('\r', '')


def parse_dir(text):
    """DIR's lines -> [(name, size or None for a folder, date)] (the names as 8.3: NAME or NAME.EXT)."""
    out = []
    for ln in text.split('\n'):
        if len(ln) < 20 or not re.match(r'[A-Z0-9_$~!#%&\'()@^`{}-]', ln[:1]): continue
        m = re.match(r'(.{8}) (.{3})\s+(<DIR>|\d+)\s+(\d{4}-\d\d-\d\d \d\d:\d\d)', ln)
        if not m: continue
        n, x = m.group(1).strip(), m.group(2).strip()
        name = n + ('.' + x if x else '')
        out.append((name, None if m.group(3) == '<DIR>' else int(m.group(3)), m.group(4)))
    return out


def listing(path, say):
    """A folder: [(name, size, date, hidden)]."""
    allx = parse_dir((yield from cmd('DIR -h ' + path)))
    plain = {n for n, s, d in parse_dir((yield from cmd('DIR ' + path)))}
    return [(n, s, d, n not in plain) for n, s, d in allx if n not in SKIP_DIRS]


def join(folder, name): return (folder.rstrip('/') + '/' + name) if folder != '/' else '/' + name


def pull(path, say):
    yield from typed('XFER -S ' + path)
    got = yield from until([b'Ctrl-C stops.\r\n', PROMPT], 20.0)
    if not got.endswith(b'Ctrl-C stops.\r\n'): say('** %s: %r' % (path, got[-80:])); return None
    data = yield from E.xpull(lambda *a: None)
    yield from until([PROMPT], 10.0)
    return data


def put(path, data, say):
    yield from typed('XFER -R ' + path)
    got = yield from until([b'Ctrl-C stops.\r\n', b'(Y/N) ', PROMPT], 20.0)
    if got.endswith(b'(Y/N) '):
        yield ('send', b'Y'); yield ('recv', 1, 0.5)
        got = yield from until([b'Ctrl-C stops.\r\n', PROMPT], 20.0)
    if not got.endswith(b'Ctrl-C stops.\r\n'): say('** %s: %r' % (path, got[-80:])); return False
    ok = yield from E.xput(data, lambda *a: None)
    yield from until([PROMPT], 10.0)
    return ok


def start(cr=True, say=print):
    """To LTOS's prompt -> True; False if LTOS is not there. On the Elf2K an Enter first (in the simulator it is
    coming up by itself). At the ROM monitor (>>>, after a reset or a card swap): BOOT typed, LTOS waited for."""
    if cr: yield ('send', b'\r')
    got = yield from until([PROMPT, b'>>>', b'>>> '], 6.0 if cr else 90.0)
    if got.endswith(PROMPT): return True
    if got.rstrip().endswith(b'>>>'):
        say('The Elf2K is at its monitor (>>>): BOOT, to start LTOS ...')
        yield from typed('BOOT')
        got = yield from until([PROMPT], 40.0)
        if got.endswith(PROMPT): return True
    say('** LTOS is not answering (%r) - nothing done. Start LTOS on the Elf2K (BOOT at >>>) and try again.' % got[-60:])
    return False


def card_name(info):
    m = re.search(r'Model:\s*(.+)', info); s = re.search(r'Size:\s*(.+)', info)
    return '%s, %s' % (m.group(1).strip() if m else '?', s.group(1).strip() if s else '?')


def backup_session(say, cr=True):
    """-> (manifest, {path: bytes}): every folder walked, every file pulled and its size checked."""
    if not (yield from start(cr, say)): return None, None
    info = yield from cmd('DISKINFO -Q', 20.0)
    say('The card: ' + card_name(info))
    dirs, files, todo = [], [], ['/']
    while todo:
        folder = todo.pop(0)
        for n, s, d, h in (yield from listing(folder, say)):
            p = join(folder, n)
            if s is None:
                if n.upper().startswith('FSEVE~'): say('  (left out: %s, the Mac\'s .fseventsd)' % p); continue
                dirs.append({'path': p, 'date': d, 'hidden': h}); todo.append(p)
            else:
                files.append({'path': p, 'size': s, 'date': d, 'hidden': h})
    say('%d folders, %d files, %d bytes' % (len(dirs), len(files), sum(f['size'] for f in files)))
    datas, bad = {}, []
    for k, f in enumerate(files, 1):
        data = yield from pull(f['path'], say)
        if data is None or len(data) != f['size']:
            bad.append(f['path']); say('** %s: %s' % (f['path'], 'not read' if data is None else '%d bytes, not %d' % (len(data), f['size'])))
            continue
        datas[f['path']] = data
        say('  %3d/%d  %-28s %7d bytes%s' % (k, len(files), f['path'], f['size'], '  (hidden)' if f['hidden'] else ''))
    man = {'made': datetime.datetime.now().isoformat(timespec='seconds'), 'diskinfo': info.strip(), 'folders': dirs,
           'files': files, 'not_read': bad}
    return man, datas


def restore_session(man, datas, say, everything=False, cr=True):
    """-> a list of problems ([] = all well): folders made, files sent, hidden ones hidden, DIR sizes checked, FSCK."""
    if not (yield from start(cr, say)): return ['LTOS did not answer - nothing written']
    info = yield from cmd('DISKINFO -Q', 20.0)
    say('Restoring onto: ' + card_name(info))
    probs = []
    for d in sorted(man['folders'], key=lambda d: d['path'].count('/')):
        out = yield from cmd('MKDIR ' + d['path'])
    send = [f for f in man['files'] if f['path'] in datas and (everything or not is_system(f['path']))]
    left = [f['path'] for f in man['files'] if f not in send]
    if left: say('left as they are on this card (its own LTOS; --all sends them): %d files' % len(left))
    for k, f in enumerate(send, 1):
        ok = yield from put(f['path'], datas[f['path']], say)
        if not ok: probs.append('%s: not sent' % f['path']); say('** %s: not sent' % f['path']); continue
        say('  %3d/%d  %-28s %7d bytes' % (k, len(send), f['path'], f['size']))
    for x in send:                                 # (HIDE takes files only: a hidden folder comes back shown)
        if x['hidden']: yield from cmd('HIDE ' + x['path'])
    sizes = {}                                     # the card's own view now
    for folder in ['/'] + [d['path'] for d in man['folders']]:
        for n, s, dt, h in (yield from listing(folder, say)):
            sizes[join(folder, n)] = (s, h)
    for f in send:
        s, h = sizes.get(f['path'], (None, None))
        if s != f['size']: probs.append('%s: %s on the card, %d in the backup' % (f['path'], s, f['size']))
        elif h != f['hidden']: probs.append('%s: hidden %s, the backup %s' % (f['path'], h, f['hidden']))
    fsck = yield from cmd('FSCK', 120.0)
    if 'No problems found' not in fsck: probs.append('FSCK: ' + fsck.strip()[-200:])
    return probs


# ---------------------------------------------------------------------------------------------------- on the Elf2K
def run_serial(gen):
    """A session on the serial port (elfser.py's xrun, which this is)."""
    fd = E.open_port(); E.read_until_quiet(fd, 0.3, 1.0)
    try: return E.xrun(fd, gen)
    finally: os.close(fd)


def save_backup(folder, man, datas):
    os.makedirs(folder, exist_ok=True)
    for p, d in datas.items():
        q = os.path.join(folder, *p.strip('/').split('/'))
        os.makedirs(os.path.dirname(q), exist_ok=True)
        open(q, 'wb').write(d)
    json.dump(man, open(os.path.join(folder, 'MANIFEST.json'), 'w'), indent=1)


def load_backup(folder):
    man = json.load(open(os.path.join(folder, 'MANIFEST.json')))
    datas = {}
    for f in man['files']:
        q = os.path.join(folder, *f['path'].strip('/').split('/'))
        if os.path.exists(q): datas[f['path']] = open(q, 'rb').read()
    return man, datas


def main(argv):
    if not argv or argv[0] not in ('backup', 'restore', 'list'): raise SystemExit(__doc__)
    say = lambda s: print(s, flush=True)
    if argv[0] == 'backup':
        folder = argv[1] if len(argv) > 1 else os.path.expanduser('~/Elf2K-backups/card-' + datetime.datetime.now().strftime('%Y-%m-%d-%H%M'))
        t0 = time.time()
        man, datas = run_serial(backup_session(say))
        if man is None: raise SystemExit(1)
        save_backup(folder, man, datas)
        say('Backed up %d files (%d bytes) to %s in %d s%s' % (len(datas), sum(map(len, datas.values())), folder, time.time() - t0,
            ('; NOT read: ' + ', '.join(man['not_read'])) if man['not_read'] else ''))
    elif argv[0] == 'list':
        man, datas = load_backup(argv[1])
        print(man['made']); print(man['diskinfo'].split('Model:')[-1].split('\n')[0].strip() if 'Model:' in man['diskinfo'] else '')
        for d in man['folders']: print('  %-30s <DIR>%s' % (d['path'], '  hidden' if d['hidden'] else ''))
        for f in man['files']: print('  %-30s %7d  %s%s%s' % (f['path'], f['size'], f['date'], '  hidden' if f['hidden'] else '',
                                                             '  (LTOS: restored with --all)' if is_system(f['path']) else ''))
    else:
        folder = argv[1]; everything = '--all' in argv
        man, datas = load_backup(folder)
        n = len([f for f in man['files'] if everything or not is_system(f['path'])])
        if '--yes' not in argv:
            a = input('Write %d files from %s onto the card in the Elf2K, replacing any of the same name? (y/N) ' % (n, folder))
            if a.strip().lower() != 'y': print('Nothing written.'); return
        t0 = time.time()
        probs = run_serial(restore_session(man, datas, say, everything))
        say(('Restored, checked, FSCK clean' if not probs else 'Restored with problems:\n  ' + '\n  '.join(probs)) + ' (%d s)' % (time.time() - t0))


if __name__ == '__main__':
    main(sys.argv[1:])
