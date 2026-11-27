#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/elf2k_card.py - the Elf2K's CF card looked after from the Mac's Terminal: a menu.

    python3 tools/elf2k_card.py              (or double-click "Elf2K Card.command")

  1  Format the card and install LTOS + STELLAR - asks first, louder if the card already holds LTOS (and offers a
     backup); then the installer's F, INSTALL2, the whole system (SYSRX), the starter files (the STELLAR apps, README,
     licence, ... as on the Emma 02 kit's card) and a FSCK
  2  Update LTOS + STELLAR, if needed - the kernel (its stamp at $032D, read with DUMP), every system file (its size)
     and STELLAR.BIN (byte for byte) compared with this build; only what differs is put right (U, SYSRX, STELLAR.BIN)
  3  Back up the card to the Mac - every file and folder, into ~/Elf2K-backups/<card name> <date and time>
  4  Check the card - FSCK in full, DISKINFO's space and bad-cluster count; the slow every-sector read if wanted
  5  Name this card - a name of your own, kept in ~/Elf2K-backups/cards.json by the card's serial number
  6  Arrange the programs as the card layout template (LTOS/layout.txt: /BIN, /BIN/GAMES, /BIN/OFFICE,
     /BIN/SYSTEM ...) - Format does it to a new card, Update offers it; your own files are never moved
  7  List every file on the card - a tree (in each folder its folders, then its files, alphabetically), with
     sizes and dates, as LTOS's own TREE -f shows it on the Elf2K; it can be saved in Downloads
  8  Get a file from the card into Downloads - a full path, or a name looked for in every folder
  9  Put a file from Downloads on the card - picked from the newest, given an 8.3 name, into a folder (the
     template's for a program, made if missing); a file already there is replaced only if you say so
  10 Restore a backup (from 3) onto the card - any LTOS card, another size too; LTOS's own programs and help are
     left as the card has them unless you say; sizes and FSCK checked after
  11 Delete a file (to /TRASH by default, or for good) or a folder and all in it (for good, after asking)
  12 Run a raw 1802 program: one in /BIN/RAW, or a .BIN from Downloads put there first - 1802 /BIN/RAW/NAME
  R  Read the card again (after changing cards)

The serial port must be free (no terminal program on it). Built on LTOS/elfser.py (XFER, SYSRX, the port),
LTOS/cardfiles.py (the backup) and tools/cardsync.py (the port on a PC, the Emma card image). Every step is a session
generator yielding ('send', bytes) / ('recv', n, quiet seconds) / ('ask', question, default), so
tools/verify_elf2k_card.py runs the very same steps against the simulated Elf2K.

More functions are meant to come: each is a line in MENU and a session function.
"""
import datetime, json, os, re, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.abspath(os.path.join(HERE, '..'))
LT = os.path.join(TOP, 'LTOS')
sys.path.insert(0, LT); sys.path.insert(0, HERE)
import elfser as E
import cardfiles as CF
import cardsync as CS
import card_layout as CL

OUT = os.path.join(LT, 'out')
PAK = os.path.join(OUT, 'LTOS-ALL.PAK')
INSTALL, INSTALL2 = os.path.join(OUT, 'INSTALL.HEX'), os.path.join(OUT, 'INSTALL2.HEX')
CARDCHK = os.path.join(OUT, 'CARDCHK.HEX')   # what is on the card, asked from the monitor (cardchk.asm)
FIRMWARE = os.path.join(TOP, 'stellar v6137.hex')
KSYMS = os.path.join(OUT, 'ksyms.inc')
STARTER = os.path.join(TOP, 'EMMA02', 'card-share.img')      # the Emma 02 kit's card: what a fresh card is given
HOME = os.path.expanduser('~/Elf2K-backups')
NAMES = os.path.join(HOME, 'cards.json')
PROMPT, MON = CF.PROMPT, b'>>>'
STLSIZE = 0x2F00                                              # STELLAR.BIN: RAM $0000-$2EFF


# ---------------------------------------------------------------------------------------------------- this build
def hex_image(path):
    """Intel HEX -> {address: byte}."""
    mem = {}
    for ln in open(path):
        ln = ln.strip()
        if not ln.startswith(':'): continue
        r = bytes.fromhex(ln[1:])
        if r[3] == 0:
            a = (r[1] << 8) | r[2]
            for i, x in enumerate(r[4:4 + r[0]]): mem[a + i] = x
    return mem


def pak_files(pak):
    """LTOS-ALL.PAK -> {'NAME.EXT': bytes} (block 0: the plan; then each LPAK part)."""
    out, at = {}, 512
    for k in range(pak[4]):
        p = pak[at:at + pak[5 + k] * 512]; at += pak[5 + k] * 512
        for i in range(p[4]):
            e = p[5 + 15 * i: 20 + 15 * i]
            n, x = e[:8].decode('latin1').strip(), e[8:11].decode('latin1').strip()
            o = (e[11] << 8) | e[12]
            out[n + ('.' + x if x else '')] = bytes(p[o:o + ((e[13] << 8) | e[14])])
    return out


class Build:
    """What this Mac would put on a card."""
    def __init__(s):
        for f in (PAK, INSTALL, INSTALL2, FIRMWARE, KSYMS):
            if not os.path.exists(f): raise SystemExit('Missing %s - build LTOS first (python3 LTOS/build.py).' % f)
        s.pak = open(PAK, 'rb').read()
        s.files = pak_files(s.pak)
        m = re.search(r'KS_STAMPV\s+EQU\s+0?([0-9A-F]{4})H', open(KSYMS).read())
        s.stamp = int(m.group(1), 16)
        fw = hex_image(FIRMWARE)
        s.fw_have = fw                                          # the bytes the firmware HEX gives
        s.fw = bytes(fw.get(a, 0) for a in range(STLSIZE))
        s.fw_version = '%02X.%02X' % (fw.get(3, 0), fw.get(4, 0))     # 61.37: STELLAR V0061.37
        s.install, s.install2, s.cardchk = INSTALL, INSTALL2, CARDCHK

    def starter(self, say):
        """The starter files from the Emma kit's card: everything on it that is not the system -> [(path, bytes)]."""
        if not os.path.exists(STARTER):
            say('  (no %s - the starter files are left out; make it with EMMA02/clean_card.py)' % STARTER); return []
        im = CS.Image(STARTER, check=False)
        CS.run(im.open(say)); files, dirs = CS.run(im.walk(say))
        out = []
        for p in sorted(files):
            n = p.rsplit('/', 1)[1]
            if n in self.files or p.upper() == '/STELLAR.BIN': continue
            out.append((p, CS.run(im.get(p, say))))
        return out


# ---------------------------------------------------------------------------------------------------- the card's names
def names():
    try: return json.load(open(NAMES))
    except (OSError, ValueError): return {}


def set_name(serial, name):
    os.makedirs(HOME, exist_ok=True)
    n = names(); n[serial] = name
    json.dump(n, open(NAMES, 'w'), indent=1)


def safe(name): return re.sub(r'[^A-Za-z0-9 ._-]+', '', name).strip() or 'card'


# ---------------------------------------------------------------------------------------------------- steps
def ask(question, default=''):
    """The person at the Mac answers (the runner asks; a test answers from its script)."""
    return (yield ('ask', question, default))


def yes(question, default=False):
    a = yield from ask(question + (' (Y/n) ' if default else ' (y/N) '), 'y' if default else 'n')
    a = (a or '').strip().lower()
    return default if not a else a.startswith('y')


def until(pats, quiet, most=3600.0):
    return (yield from CF.until(pats, quiet, most))


CR = True        # an Enter first to see where the Elf2K is (the simulator, booting by itself, sets it False)


def where(cr=None):
    """-> 'ltos' (LTOS's prompt), 'monitor' (the ROM's >>>) or None (no answer)."""
    cr = CR if cr is None else cr
    if cr: yield ('send', b'\r')
    got = yield from until([PROMPT, MON, MON + b' '], 6.0 if cr else 90.0)
    if got.endswith(PROMPT): return 'ltos'
    if got.rstrip().endswith(MON): return 'monitor'
    return None


def boot(say):
    """At the monitor: BOOT -> True once LTOS's prompt is there."""
    yield from CF.typed('BOOT')
    got = yield from until([PROMPT], 45.0, 120.0)
    if got.endswith(PROMPT): return True
    say('** The card did not start LTOS (%r).' % got.decode('latin1')[-60:])
    return False


def to_monitor(say):
    """From LTOS: MON (it puts STELLAR.BIN back in RAM, if the card has one) -> True at >>>."""
    yield from CF.typed('MON')
    got = yield from until([MON, MON + b' '], 20.0)
    if got.rstrip().endswith(MON): return True
    say('** MON did not reach the monitor (%r)' % got.decode('latin1')[-60:]); return False


def mon_line(line):
    """A line typed at the monitor, each character as its echo comes back; then the monitor's >>> again."""
    for ch in (line + '\r').encode():
        yield ('send', bytes([ch])); yield ('recv', 1, 0.5)


def paste_hex(path, what, say):
    """An Intel HEX file pasted into the monitor, line by line (each waits for the monitor's >>>) -> True."""
    lines = [l.strip() for l in open(path) if l.strip()]
    say('  %s: %d lines into the Elf2K\'s memory ...' % (what, len(lines)))
    t0 = time.time()
    for k, ln in enumerate(lines, 1):
        yield from mon_line(ln)
        got = yield from until([MON, MON + b' '], 3.0, 10.0)
        if b'?' in got:
            say('** the monitor did not take line %d of %s (%r)' % (k, what, got.decode('latin1')[-40:])); return False
        if k % 200 == 0: say('    %d of %d lines, %d s' % (k, len(lines), time.time() - t0))
    say('    done, %d s' % (time.time() - t0))
    return True


def installer(choice, b, say):
    """INSTALL.HEX pasted, CALL 3000, answered F or U. -> 'done', 'firmware' (F: STELLAR is not the right one in RAM -
    nothing written) or None (it failed: its words are shown)."""
    if not (yield from paste_hex(b.install, 'INSTALL.HEX', say)): return None
    yield from mon_line('CALL 3000')
    got = (yield from until([b'Which? ', MON, MON + b' '], 60.0)).decode('latin1')
    if not got.endswith('Which? '):
        say('** the installer stopped:\n' + got.replace('\r', '')[-400:]); return None
    m = re.search(r'STELLAR V00([0-9A-F]{2})\.([0-9A-F]{2}) is in RAM', got)
    if choice == 'F' and (not m or '%s.%s' % m.groups() != b.fw_version):
        yield ('send', b'X')                                  # (anything else = stop: nothing written)
        yield from until([MON, MON + b' '], 10.0)
        return 'firmware'
    yield ('send', choice.encode())
    say('  The installer is at work (%s) - a minute or more; the card is quiet while it clears ...'
        % ('formatting' if choice == 'F' else 'the kernel and the boot sector'))
    got = (yield from until([MON, MON + b' '], 600.0, 7200.0)).decode('latin1').replace('\r', '')
    bad = [w for w in ('FAILED', 'Nothing written', 'did not load right', 'not bootable', 'has no LTOS') if w in got]
    if bad:
        say('** the installer said:\n' + got[-500:]); return None
    say('  ' + '\n  '.join(l for l in got.split('\n') if l.strip() and not l.startswith(' ' * 4))[-600:])
    return 'done'


def put_file(path, data, say):
    return (yield from CF.put(path, data, say))


def send_system(b, say, rx_sent=False):
    """The whole system with SYSRX (elfser.py system's steps). This build's SYSRX goes first, as /SYSRX.PRG, unless
    rx_sent (already there): a card's older SYSRX would not know where newer kinds of file go. -> True"""
    yield from CF.cmd('CD /')
    yield from CF.cmd('MKDIR /BIN')
    yield from CF.cmd('MKDIR /MUSIC')
    yield from CF.cmd('MKDIR /SRC')
    if not rx_sent:
        if not (yield from put_file('/SYSRX.PRG', b.files['SYSRX.PRG'], lambda *a: None)):
            say('  (this card\'s XFER could not take the new SYSRX first: the card\'s own SYSRX does it)')
    yield from CF.typed('SYSRX')
    got = yield from until([b'Ctrl-C stops.\r\n', PROMPT], 30.0)
    if not got.endswith(b'Ctrl-C stops.\r\n'):
        say('** SYSRX did not start (%r)' % got.decode('latin1')[-80:]); return False
    say('  Sending the system: %d files, about 5 minutes ...' % len(b.files))
    E.xsys.t0 = time.time()
    ok = yield from E.xsys(b.pak, say)
    yield from until([PROMPT], 20.0)
    if not ok: say('** the system did not all arrive'); return False
    for n in ('RECV', 'MON', 'MKDIR', 'SYSRX'):            # (a fresh card's first copies: /BIN has them now)
        yield from CF.cmd('RM /%s.PRG' % n)
    return True


def card_id(say):
    """DISKINFO -Q -> {'model', 'serial', 'size', 'text'}."""
    t = yield from CF.cmd('DISKINFO -Q', 30.0)
    def f(label):
        m = re.search(label + r':\s*(.+)', t); return m.group(1).strip() if m else '?'
    return {'model': f('Model'), 'serial': f('Serial number'), 'size': f('Size').split(' =')[0], 'text': t}


def label(card):
    n = names().get(card['serial'])
    return ('"%s" (%s, %s)' % (n, card['model'], card['size'])) if n else '%s, %s, serial %s' % (card['model'], card['size'], card['serial'])


def kernel_stamp():
    """The running kernel's stamp, at $032D (KSTAMP) - every system program carries the one it was built for."""
    t = yield from CF.cmd('DUMP 320 10', 10.0)
    m = re.search(r'0320[ :]+((?:[0-9A-F]{2} +){13,16})', t)
    if not m: return None
    b = m.group(1).split()
    return (int(b[13], 16) << 8) | int(b[14], 16)


def walk(say):
    """Every file on the card -> {path: size}."""
    files, dirs = yield from CS.Serial(cr=False).walk(say)
    return {p: sz for p, (sz, d, h) in files.items()}


def compare(b, say):
    """-> (kernel differs, [system files that differ or are missing], STELLAR.BIN differs, the card's files)"""
    st = yield from kernel_stamp()
    say('  kernel: %s' % ('the same as this build' if st == b.stamp else
                          'stamp $%04X, this build $%04X - it needs updating' % (st or 0, b.stamp)))
    say('  reading every folder ...')
    have = yield from walk(say)
    byname = {}
    for p, sz in have.items():
        byname.setdefault(p.rsplit('/', 1)[1], []).append((p, sz))
    def right_place(n, p):                                   # where SYSRX puts each kind (a /BIN folder counts)
        if n.endswith('.MUS'): return p == '/MUSIC/' + n
        if n.endswith('.SC'): return p == '/SRC/' + n
        if n.endswith(('.PRG', '.OVL')): return p.startswith('/BIN/')
        return p == '/' + n
    diff = []
    for n, data in sorted(b.files.items()):
        found = [(p, sz) for p, sz in byname.get(n, []) if right_place(n, p)]
        if not found: diff.append('%s: not on the card' % n)
        elif all(sz != len(data) for p, sz in found):
            diff.append('%s: %d bytes on the card, %d in this build' % (found[0][0], found[0][1], len(data)))
    say('  system files: %s' % ('all %d the same size as this build' % len(b.files) if not diff else '%d differ' % len(diff)))
    for d in diff[:12]: say('    ' + d)
    if len(diff) > 12: say('    ... and %d more' % (len(diff) - 12))
    if '/STELLAR.BIN' not in have:
        say('  STELLAR.BIN: not on the card'); stl = True
    else:
        data = yield from CF.pull('/STELLAR.BIN', say)
        stl = data is None or any(data[a] != v for a, v in b.fw_have.items() if a < len(data)) or len(data) != STLSIZE
        say('  STELLAR.BIN: %s' % ('V00%s, as this build' % b.fw_version if not stl else 'not V00%s - it needs updating' % b.fw_version))
    return st != b.stamp, diff, stl, have


# ---------------------------------------------------------------------------------------------------- the menu's jobs
LASTCARD = [None]   # start()'s look at the card: 'ltos', 'blank', 'other', 'none' (CARDCHK), or None


def probe(say):
    """At the monitor: CARDCHK.HEX pasted and run (CALL 3000) - sector 0 read, nothing booted or written ->
    'ltos' (an LTOS card), 'blank' (never formatted), 'other' (formatted elsewhere), 'none' (no card), None (no answer)."""
    say('Looking at the card (from the monitor - not booting it) ...')
    if not (yield from paste_hex(CARDCHK, 'CARDCHK.HEX', say)): return None
    yield from mon_line('CALL 3000')
    got = yield from until([MON, MON + b' '], 10.0, 30.0)
    m = re.search(rb'CARD:(LTOS|BLANK|OTHER|NONE)', got)
    return m.group(1).decode().lower() if m else None


def start(say, cr=None):
    """To LTOS's prompt, whatever the Elf2K is doing -> True. At the monitor: the card looked at first (probe) - an
    LTOS card is booted; a blank card is not (BOOT would run its zeros and stop the Elf2K until Reset)."""
    LASTCARD[0] = None
    w = yield from where(cr)
    if w == 'ltos': LASTCARD[0] = 'ltos'; return True
    if w == 'monitor':
        say('The Elf2K is at its monitor (>>>).')
        c = yield from probe(say)
        LASTCARD[0] = c
        if c == 'ltos':
            say('An LTOS card: BOOT ...')
            if (yield from boot(say)): return True
            say('The card did not start LTOS.')
            return False
        if c == 'blank': say('The card is BLANK - it has never been formatted. (Menu 1 formats it and installs LTOS.)')
        elif c == 'other': say('The card is formatted, but not with LTOS. (Menu 1 formats it for LTOS - erasing it.)')
        elif c == 'none': say('** No card answered: is one in the Elf2K\'s reader?')
        else: say('** The card check did not answer (see above).')
        return False
    say('** The Elf2K is not answering. Is it on, and the serial cable in? If a blank card was booted it is stuck:')
    say('   press RESET on the Elf2K, then R here. (Nothing done.)')
    return False


def job_format(b, say):
    """1: format + LTOS + STELLAR + the system + the starter files + FSCK."""
    w = yield from where()
    blank = False
    if w == 'monitor':
        c = yield from probe(say)                       # (always looked at again: the card may have been changed)
        if c == 'ltos':
            say('An LTOS card: BOOT, to see what is on it ...')
            if not (yield from boot(say)): say('** It did not start - nothing done.'); return
            w = 'ltos'
        elif c in ('blank', 'other'):
            say('The card is %s.' % ('blank (never formatted)' if c == 'blank' else 'formatted for something else'))
            blank = True
        else: say('** The card could not be looked at - nothing done.'); return
    elif w is None:
        say('** The Elf2K is not answering - nothing done.'); return
    if w == 'ltos':
        card = yield from card_id(say)
        say('On the Elf2K: an LTOS card - %s' % label(card))
        say('Formatting ERASES EVERYTHING on it.')
        if (yield from yes('Back it up to this computer first?', True)):
            yield from job_backup(b, say, card)
        if not (yield from yes('Reformat this card - erase everything and install LTOS fresh?')):
            say('Nothing done.'); return
        if not (yield from to_monitor(say)): return
    else:
        if not (yield from yes('Format this card - ERASE everything on it - and install LTOS?')):
            say('Nothing done.'); return
    t0 = time.time()
    r = yield from installer('F', b, say)
    if r == 'firmware':
        say('  STELLAR V00%s is not in the Elf2K\'s memory: putting it there first (it is saved as STELLAR.BIN) ...' % b.fw_version)
        if not (yield from paste_hex(FIRMWARE, 'the STELLAR firmware', say)): return
        r = yield from installer('F', b, say)
    if r != 'done': say('** Formatting did not finish - see above.'); return
    if not (yield from paste_hex(b.install2, 'INSTALL2.HEX', say)): return
    yield from mon_line('CALL 3003')
    got = (yield from until([MON, MON + b' '], 120.0)).decode('latin1')
    if 'Then elfser.py system' not in got:
        say('** INSTALL2 did not finish:\n' + got.replace('\r', '')[-300:]); return
    if not (yield from boot(say)): return
    if not (yield from send_system(b, say, rx_sent=True)): return
    st = b.starter(say)
    if st:
        say('  The starter files (as on the Emma 02 kit\'s card): %d files ...' % len(st))
        for d in sorted({p.rsplit('/', 1)[0] for p, _ in st if p.count('/') > 1}, key=lambda d: d.count('/')):
            yield from CF.cmd('MKDIR ' + d)
        bad = []
        for k, (p, data) in enumerate(st, 1):
            ok = yield from put_file(p, data, say)
            if not ok: bad.append(p)
            if k % 10 == 0 or k == len(st): say('    %d of %d' % (k, len(st)))
        if bad: say('  ** not sent: ' + ', '.join(bad))
    say('  Laying the card out as the template (LTOS/layout.txt) ...')
    probs = yield from CL.arrange_session(say)
    for p in probs: say('  ** ' + p)
    say('The new card, checked:')
    yield from job_check(b, say, scan=False)
    say('Formatted and installed in %d minutes.' % ((time.time() - t0 + 59) // 60))


def job_update(b, say):
    """2: the card compared with this build; only what differs is put right."""
    if not (yield from start(say)): return
    card = yield from card_id(say)
    say('Comparing %s with this build ...' % label(card))
    kern, diff, stl, have = yield from compare(b, say)
    anyway = False
    if not kern and not diff and not stl:
        say('LTOS and STELLAR on this card are up to date.')
        say('(Sizes are compared: a change that kept a file\'s size would not show - the system can be sent anyway.)')
        if not (yield from yes('Send the whole system anyway?')):
            yield from offer_layout(say, have); return
        anyway = True
    elif not (yield from yes('Update this card now?', True)):
        say('Nothing done.'); return
    t0 = time.time()
    rx = False
    if kern:
        # the new SYSRX first, while the card's own kernel and XFER still work together: SYSRX checks no stamp, so it
        # runs after U, when the old XFER would say "Not for this kernel"
        rx = yield from put_file('/SYSRX.PRG', b.files['SYSRX.PRG'], say)
        if not (yield from to_monitor(say)): return
        r = yield from installer('U', b, say)
        if r != 'done': say('** The kernel was not updated - see above.'); return
        if not (yield from boot(say)): return
    if kern or diff or anyway:
        if not (yield from send_system(b, say, rx_sent=rx)): return
    if stl:
        say('  STELLAR.BIN: V00%s onto the card ...' % b.fw_version)
        if not (yield from put_file('/STELLAR.BIN', b.fw, say)): say('** STELLAR.BIN was not sent'); return
    say('Checking again ...')
    kern, diff, stl, have = yield from compare(b, say)
    say(('Updated: LTOS and STELLAR are as this build (%d s).' if not (kern or diff or stl) else
         '** Still different after the update - see above (%d s).') % (time.time() - t0))
    yield from offer_layout(say, have)


def offer_layout(say, have):
    """Programs not where the template (LTOS/layout.txt) puts them: listed, and moved if the person says so."""
    mv = CL.moves(have)
    if not mv: say('Every program is where the card layout template puts it.'); return
    say('%d programs are not where the card layout template (LTOS/layout.txt) puts them:' % len(mv))
    for p, w in mv[:15]: say('    %-24s -> %s' % (p, w))
    if len(mv) > 15: say('    ... and %d more' % (len(mv) - 15))
    if not (yield from yes('Move them there now?', True)): return
    probs = yield from CL.arrange_session(say, files=have)
    say('Moved.' if not probs else '** Not all moved:\n  ' + '\n  '.join(probs))


def job_backup(b, say, card=None):
    """3: every file and folder into ~/Elf2K-backups/<name> <date time>."""
    if card is None:
        if not (yield from start(say)): return None
        card = yield from card_id(say)
    name = names().get(card['serial'])
    if not name:
        name = (yield from ask('This card has no name yet - one for its backups (e.g. Main 8MB): ', '')).strip()
        if name: set_name(card['serial'], name)
        else: name = '%s %s' % (card['model'], card['serial'][-6:])
    folder = os.path.join(HOME, '%s %s' % (safe(name), datetime.datetime.now().strftime('%Y-%m-%d %H%M')))
    say('Backing up %s to %s ...' % (label(card), folder))
    t0 = time.time()
    man, datas = yield from CF.backup_session(say, cr=True)        # (an Enter: LTOS is already at its prompt)
    if man is None: return None
    man['card'] = {'name': name, 'model': card['model'], 'serial': card['serial'], 'size': card['size']}
    CF.save_backup(folder, man, datas)
    say('Backed up: %d files, %d bytes, in %d s -> %s%s' % (len(datas), sum(map(len, datas.values())), time.time() - t0,
        folder, ('\n** NOT read: ' + ', '.join(man['not_read'])) if man['not_read'] else ''))
    return folder


def job_check(b, say, scan=None):
    """4: FSCK in full; DISKINFO's space and bad clusters; the every-sector read if wanted."""
    if scan is None:
        if not (yield from start(say)): return
    say('  FSCK: every folder, every file\'s clusters, both FATs - a few minutes on a big card ...')
    t = yield from CF.cmd('FSCK', 180.0)
    t = term(t)
    m = re.search(r'Checked: (\d+) files, (\d+) folders', t)
    ok = 'No problems found' in t
    probs = [l.strip() for l in t.split('\n') if l.strip() and not re.match(r'^[.\\|/ -]*$', l.strip())
             and not l.startswith(('FSCK', 'Checking', 'Checked', 'No problems')) and 'LTOS>' not in l]
    say('  DISKINFO: the space and the bad clusters ...')
    d = term((yield from CF.cmd('DISKINFO', 600.0)))
    def f(lbl):
        x = re.search(r'\n  ' + lbl + r':\s+(.*)', d); return x.group(1).strip() if x else '?'
    say('')
    say('  The card:      %s, %s' % (f('Model'), f('Size')))
    say('  Files:         %s in %s' % (m.group(1), (m.group(2) + ' folders')) if m else '  Files:         ? (FSCK did not finish)')
    say('  Space:         %s' % f('Bytes'))
    say('  Clusters:      %s' % f('Clusters'))
    say('  Marked bad:    %s' % f('In the FAT'))
    say('  FSCK:          %s' % ('no problems found' if ok else 'PROBLEMS:'))
    if not ok:
        for l in probs[:20]: say('    ' + l)
    say('')
    if scan is None:
        mb = re.match(r'(\d+)', f('Size'))
        mins = int(mb.group(1)) if mb else 0
        if (yield from yes('Also read every sector to look for unreadable ones (DISKINFO -S, about %s)?'
                           % ('%d minutes' % mins if mins < 120 else '%d hours' % (mins // 60)))):
            say('  Reading every sector - press Ctrl-C here to stop it ...')
            t = term((yield from CF.cmd('DISKINFO -S', 3600.0)))
            x = re.search(r'Unreadable:\s+(.*)', t)
            say('  Unreadable:    %s' % (x.group(1).strip() if x else '? (it did not finish)'))


def term(t):
    """As the terminal shows it: a backspace steps back (DISKINFO's turning \\|/-)."""
    out = []
    for c in t:
        if c == '\x08':
            if out and out[-1] != '\n': out.pop()
        else: out.append(c)
    return ''.join(out)


def job_arrange(b, say):
    """6: the card's programs moved to where the template (LTOS/layout.txt) puts them; your own files stay."""
    if not (yield from start(say)): return
    card = yield from card_id(say)
    say('Reading every folder of %s ...' % label(card))
    files = yield from walk(say)
    yield from offer_layout(say, files)


DOWNLOADS = os.path.expanduser('~/Downloads')
SHORT_OK = set('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&\'()-@^_`{}~')


def short_name(name):
    """A Mac file name -> an LTOS (8.3, upper case) one: NAME.EXT, or None if it already is one (then: itself)."""
    base, dot, ext = name.upper().rpartition('.')
    if not dot: base, ext = name.upper(), ''
    clean = lambda t, n: ''.join(c for c in t if c in SHORT_OK)[:n]
    b2, e2 = clean(base, 8) or 'FILE', clean(ext, 3)
    return b2 + ('.' + e2 if e2 else '')


def is_short(name):
    base, dot, ext = name.rpartition('.')
    if not dot: base, ext = name, ''
    return (name == name.upper() and 1 <= len(base) <= 8 and len(ext) <= 3 and
            all(c in SHORT_OK for c in base + ext))


def walk_all(say):
    """-> ({path: (size, date, hidden)}, {folders}) - every folder of the card read."""
    return (yield from CS.Serial(cr=False).walk(say))


def tree_lines(files, dirs):
    """The card as a tree: in each folder its folders first, then its files - each by name as the card has it
    (NAME    EXT). Line for line what LTOS's TREE -f prints on the Elf2K."""
    kids = {}
    for d in dirs: kids.setdefault(d.rsplit('/', 1)[0] or '/', []).append((d, None))
    for p, v in files.items(): kids.setdefault(p.rsplit('/', 1)[0] or '/', []).append((p, v))
    out = ['/']
    def fat11(n):                   # the card's own form of a name (NAME    EXT): LTOS's TREE -f sorts by it too
        base, _, ext = n.partition('.'); return base.ljust(8) + ext.ljust(3)
    def show(folder, pre):
        items = sorted(kids.get(folder, []), key=lambda x: (x[1] is not None, fat11(x[0].rsplit('/', 1)[1])))
        for k, (p, v) in enumerate(items):
            last = k == len(items) - 1
            n = p.rsplit('/', 1)[1]
            branch = pre + ('`-- ' if last else '|-- ')
            if v is None:
                out.append('%s%s/' % (branch, n))
                show(p, pre + ('    ' if last else '|   '))
            else:
                sz, dt, h = v
                out.append('%s%-12s%8d  %s%s' % (branch, n, sz, dt, '  (hidden)' if h else ''))
    show('/', '')
    return out


def job_tree(b, say):
    """7: every folder and file on the card as a tree, alphabetically, with sizes and dates."""
    if not (yield from start(say)): return
    card = yield from card_id(say)
    say('Reading every folder of %s ...' % label(card))
    files, dirs = yield from walk_all(say)
    lines = tree_lines(files, dirs)
    say('')
    for l in lines: say(l)
    say('')
    say('%d files in %d folders, %d bytes' % (len(files), len(dirs), sum(v[0] for v in files.values())))
    if (yield from yes('Save this list in Downloads?')):
        n = names().get(card['serial']) or card['model']
        path = os.path.join(DOWNLOADS, '%s tree %s.txt' % (safe(n), datetime.datetime.now().strftime('%Y-%m-%d %H%M')))
        open(path, 'w').write('\n'.join([label(card), ''] + lines) + '\n')
        say('Saved: ' + path)


def pick(say, options, what):
    """A numbered choice -> the option, or None."""
    for k, o in enumerate(options, 1): say('  %2d  %s' % (k, o))
    a = (yield from ask('Which %s (1-%d, Enter = none)? ' % (what, len(options)), '')).strip()
    return options[int(a) - 1] if a.isdigit() and 1 <= int(a) <= len(options) else None


def job_get(b, say):
    """8: a file from the card into Downloads (a full path, or a name looked for everywhere on the card)."""
    if not (yield from start(say)): return
    want = (yield from ask('Which file on the card? (a path like /BIN/GAMES/RACER.STL, or a name to look for): ', '')).strip().upper()
    if not want: return
    if '/' in want: path = want if want.startswith('/') else '/' + want
    else:
        say('Looking for %s in every folder ...' % want)
        files, dirs = yield from walk_all(say)
        hits = sorted(p for p in files if p.rsplit('/', 1)[1] == want or p.rsplit('/', 1)[1].split('.')[0] == want)
        if not hits: say('There is no %s on the card.' % want); return
        path = hits[0] if len(hits) == 1 else (yield from pick(say, hits, 'one'))
        if not path: return
    say('Reading %s ...' % path)
    data = yield from CF.pull(path, say)
    if data is None: say('** %s was not read (is the name right?)' % path); return
    name = path.rsplit('/', 1)[1]
    dest = os.path.join(DOWNLOADS, name); base, ext = os.path.splitext(dest); k = 1
    while os.path.exists(dest): dest = '%s-%d%s' % (base, k, ext); k += 1     # (never over one already there)
    open(dest, 'wb').write(data)
    say('%s -> %s (%d bytes)' % (path, dest, len(data)))


def job_put(b, say):
    """9: a file from Downloads to a folder on the card."""
    try: ls = [f for f in os.listdir(DOWNLOADS) if not f.startswith('.') and os.path.isfile(os.path.join(DOWNLOADS, f))]
    except OSError: ls = []
    if not ls: say('Nothing in %s to send.' % DOWNLOADS); return
    ls.sort(key=lambda f: os.path.getmtime(os.path.join(DOWNLOADS, f)), reverse=True)
    say('The newest files in Downloads:')
    f = yield from pick(say, ls[:20], 'file')
    if not f:
        f = (yield from ask('Or type its name in Downloads (Enter = stop): ', '')).strip()
        if not f or not os.path.isfile(os.path.join(DOWNLOADS, f)): say('Nothing sent.'); return
    data = open(os.path.join(DOWNLOADS, f), 'rb').read()
    if len(data) > 32 * 1024 * 1024: say('** %s is over 32 MB - too big for XFER.' % f); return
    name = f.upper() if is_short(f.upper()) else short_name(f)
    if f.upper() != name or not is_short(f.upper()):
        n2 = (yield from ask('LTOS names are 8.3 - %s on the card as [%s]: ' % (f, name), name)).strip().upper()
        if n2: name = n2
        if not is_short(name): say('** %s is not an 8.3 name - nothing sent.' % name); return
    guess = CL.load()[0].get(name, '/')
    folder = (yield from ask('Into which folder on the card? [%s]: ' % guess, guess)).strip().upper() or guess
    folder = '/' + folder.strip('/') if folder.strip('/') else '/'
    if not (yield from start(say)): return
    files, dirs = yield from walk_all(say)
    if folder != '/' and folder not in dirs:
        if not (yield from yes('There is no %s on the card. Make it?' % folder, True)): say('Nothing sent.'); return
        for d in CL.parent_chain(folder):
            if d not in dirs: yield from CF.cmd('MKDIR ' + d)
    path = (folder.rstrip('/') + '/' + name) if folder != '/' else '/' + name
    if path in files and not (yield from yes('%s is on the card already (%d bytes). Replace it?' % (path, files[path][0]))):
        say('Nothing sent.'); return
    say('Sending %s (%d bytes) to %s ...' % (f, len(data), path))
    ok = yield from CF.put(path, data, say)
    if not ok: say('** It was not sent.'); return
    out = yield from CF.cmd('DIR ' + path, 10.0)
    m = re.search(r'\s(\d+)\s+\d{4}-\d\d-\d\d', out)
    say('On the card: %s, %s bytes%s' % (path, m.group(1) if m else '?',
        '' if m and int(m.group(1)) == len(data) else '  ** not the size sent (%d)' % len(data)))


def job_restore(b, say):
    """10: a backup made by 3 put back on the card in the Elf2K (any LTOS card: another size too)."""
    try: bks = sorted((d for d in os.listdir(HOME) if os.path.exists(os.path.join(HOME, d, 'MANIFEST.json'))),
                      key=lambda d: os.path.getmtime(os.path.join(HOME, d, 'MANIFEST.json')), reverse=True)
    except OSError: bks = []
    if not bks: say('There are no backups in %s yet (menu 3 makes them).' % HOME); return
    say('Your backups, newest first:')
    d = yield from pick(say, bks[:20], 'backup')
    if not d: return
    man, datas = CF.load_backup(os.path.join(HOME, d))
    sysf = [f for f in man['files'] if CF.is_system(f['path'])]
    say('%s: %d folders, %d files, %d bytes (%d of them LTOS\'s own programs and help)' % (d, len(man['folders']),
        len(man['files']), sum(f['size'] for f in man['files']), len(sysf)))
    if not (yield from start(say)): return
    card = yield from card_id(say)
    everything = (yield from yes('Put back LTOS\'s own programs and help too? (No keeps the ones that match this card\'s '
                                 'kernel - usually right)'))
    n = len([f for f in man['files'] if everything or not CF.is_system(f['path'])])
    if not (yield from yes('Write %d files onto %s, replacing any of the same name?' % (n, label(card)))):
        say('Nothing written.'); return
    t0 = time.time()
    probs = yield from CF.restore_session(man, datas, say, everything, cr=True)
    say(('Restored, every size checked, FSCK clean (%d s).' if not probs else
         '** Restored with problems (%d s):\n  ' + '\n  '.join(probs)) % (time.time() - t0))


def find_on_card(say, want):
    """A path, or a name looked for in every folder -> (path, files, dirs) or (None, ...)."""
    files, dirs = yield from walk_all(say)
    if '/' in want: return (want if want.startswith('/') else '/' + want), files, dirs
    hits = sorted([p for p in files if p.rsplit('/', 1)[1] in (want,) or p.rsplit('/', 1)[1].split('.')[0] == want] +
                  [p for p in dirs if p.rsplit('/', 1)[1] == want])
    if not hits: say('There is no %s on the card.' % want); return None, files, dirs
    return (hits[0] if len(hits) == 1 else (yield from pick(say, hits, 'one'))), files, dirs


def job_delete(b, say):
    """11: a file to /TRASH (or for good), or a folder and all in it (for good)."""
    if not (yield from start(say)): return
    want = (yield from ask('Delete what on the card? (a path, or a name to look for): ', '')).strip().upper()
    if not want: return
    path, files, dirs = yield from find_on_card(say, want)
    if not path: return
    path = path.rstrip('/') or '/'
    if path == '/': say('** Not the whole card - Format (1) does that.'); return
    if path in files:
        n = path.rsplit('/', 1)[1]
        if n in b.files or path.upper() == '/STELLAR.BIN' or CL.load()[0].get(n):
            say('(%s is part of LTOS: Update - menu 2 - puts it back.)' % path)
        how = (yield from ask('%s (%d bytes): T = move it to /TRASH (it can be got back), D = delete it for good, '
                              'Enter = keep it [T]: ' % (path, files[path][0]), 'T')).strip().upper()[:1] or 'T'
        if how == 'T':
            out = yield from CF.cmd('DELETE ' + path, 20.0)
            say('Moved to /TRASH (MV /TRASH/%s %s gets it back; EMPTY deletes the trash for good).' % (n, path.rsplit('/', 1)[0] or '/'))
        elif how == 'D':
            if not (yield from yes('Delete %s for good? It cannot be undone.' % path)): say('Kept.'); return
            out = yield from CF.cmd('RM ' + path, 20.0)
            say('Deleted.')
        else: say('Kept.'); return
    elif path in dirs:
        inside = sorted(p for p in files if p.startswith(path + '/'))
        subs = sorted((d for d in dirs if d.startswith(path + '/')), key=lambda d: -d.count('/'))
        say('%s holds %d files in %d folders.' % (path, len(inside), len(subs)))
        for p in inside[:12]: say('    ' + p)
        if len(inside) > 12: say('    ... and %d more' % (len(inside) - 12))
        if any(p.rsplit('/', 1)[1] in b.files for p in inside): say('(Some are part of LTOS: Update - menu 2 - puts them back.)')
        if not (yield from yes('Delete %s and everything in it for good? It cannot be undone.' % path)): say('Kept.'); return
        for p in inside: yield from CF.cmd('RM ' + p, 20.0)
        for d in subs + [path]: yield from CF.cmd('RMDIR ' + d, 20.0)
        say('Deleted %s (%d files, %d folders).' % (path, len(inside), len(subs) + 1))
    else: say('There is no %s on the card.' % path); return
    files2, dirs2 = yield from walk_all(say)
    if path in files2 or path in dirs2: say('** %s is still there.' % path)


def job_runbin(b, say):
    """12: a raw 1802 program (.BIN) run on the Elf2K with LTOS's 1802 command - one in /BIN/RAW, or one from
    Downloads put there first."""
    if not (yield from start(say)): return
    files, dirs = yield from walk_all(say)
    raw = sorted(p for p in files if p.startswith('/BIN/RAW/') and p.endswith('.BIN'))
    try: dl = sorted((f for f in os.listdir(DOWNLOADS) if f.upper().endswith('.BIN') and not f.startswith('.')),
                     key=lambda f: os.path.getmtime(os.path.join(DOWNLOADS, f)), reverse=True)
    except OSError: dl = []
    opts = raw + ['Downloads: ' + f for f in dl[:10]]
    if not opts: say('No .BIN in /BIN/RAW on the card, nor in Downloads.'); return
    say('Which raw program? (those in /BIN/RAW, then .BIN files in Downloads)')
    c = yield from pick(say, opts, 'program')
    if not c: return
    if c.startswith('Downloads: '):
        f = c[len('Downloads: '):]; data = open(os.path.join(DOWNLOADS, f), 'rb').read()
        name = f.upper() if is_short(f.upper()) else short_name(f)
        if '/BIN/RAW' not in dirs:
            for d in CL.parent_chain('/BIN/RAW'):
                if d not in dirs: yield from CF.cmd('MKDIR ' + d)
        path = '/BIN/RAW/' + name
        if path in files and not (yield from yes('%s is on the card already. Replace it?' % path, True)): pass
        else:
            say('Sending %s to %s ...' % (f, path))
            if not (yield from CF.put(path, data, say)): say('** It was not sent.'); return
        c = path
    load = (yield from ask('Load address (hex, Enter = 0000): ', '')).strip().upper()
    start_a = (yield from ask('Start address (hex, Enter = the load address): ', '')).strip().upper() if load else ''
    if any(ch not in '0123456789ABCDEF' for ch in load + start_a): say('** Addresses are hex (like 0100) - nothing run.'); return
    z = yield from yes('Clear RAM to 00 first (-Z)?')
    cmd = '1802 %s%s%s%s' % ('-Z ' if z else '', c[:-4], (' ' + load) if load else '', (' ' + start_a) if start_a else '')
    say('LTOS> ' + cmd)
    yield from CF.typed(cmd)
    got = (yield from until([b'oading ... done.\r\n', PROMPT], 20.0)).decode('latin1').replace('\r', '')
    say(got.strip())
    if 'done.' in got:
        say('The Elf2K is the program\'s now. Press RESET when you are done, then R here brings LTOS back.')


def job_name(b, say):
    """5: a name for the card in the Elf2K."""
    if not (yield from start(say)): return
    card = yield from card_id(say)
    old = names().get(card['serial'], '')
    n = (yield from ask('A name for %s%s: ' % (label(card), (' [%s]' % old) if old else ''), old)).strip()
    if n: set_name(card['serial'], n); say('This card is now "%s".' % n)


def job_look(b, say):
    """R: what is in the Elf2K now. A blank card (or another system's): offered a format and LTOS there and then."""
    if not (yield from start(say)):
        if LASTCARD[0] in ('blank', 'other'):
            q = ('Format this card and install LTOS + STELLAR now?' if LASTCARD[0] == 'blank' else
                 'Format this card for LTOS now - ERASING what is on it - and install LTOS + STELLAR?')
            if (yield from yes(q)): yield from job_format(b, say)
        return
    card = yield from card_id(say)
    v = yield from CF.cmd('VER', 10.0)
    k = re.search(r'Kernel:\s+(.*)', v); bt = re.search(r'Built:\s+(.*)', v)
    st = yield from kernel_stamp()
    say('In the Elf2K: %s' % label(card))
    say('  LTOS kernel %s, built %s - %s' % (k.group(1).strip() if k else '?', bt.group(1).strip() if bt else '?',
        'the same as this build' if st == b.stamp else 'NOT this build\'s (menu 2 updates it)'))


MENU = [('1', 'Format the card and install LTOS + STELLAR', job_format),
        ('2', 'Update LTOS + STELLAR on the card (if needed)', job_update),
        ('3', 'Back up the card to this computer', job_backup),
        ('4', 'Check the card (FSCK, space, bad sectors)', job_check),
        ('5', 'Name this card', job_name),
        ('6', 'Arrange the programs as the card layout template', job_arrange),
        ('7', 'List every file on the card (a tree, alphabetically)', job_tree),
        ('8', 'Get a file from the card into Downloads', job_get),
        ('9', 'Put a file from Downloads on the card', job_put),
        ('10', 'Restore a backup onto the card', job_restore),
        ('11', 'Delete a file or folder on the card', job_delete),
        ('12', 'Run a raw 1802 program (.BIN)', job_runbin),
        ('R', 'Read the card again (after changing cards)', job_look)]


# ---------------------------------------------------------------------------------------------------- running
def answering(gen, answer):
    """A job's ('ask', ...) steps answered here (by the person, or a test's script); the rest go to the port."""
    req = next(gen)
    while True:
        if req[0] == 'ask': val = answer(req[1], req[2])
        else: val = yield req
        try: req = gen.send(val)
        except StopIteration as e: return e.value


def main():
    say = lambda s='': print(s, flush=True)
    b = Build()
    port_name = sys.argv[sys.argv.index('--port') + 1] if '--port' in sys.argv else None
    def run(job):
        try: port = CS.Port(port_name)
        except OSError as e:
            say('** The serial port %s will not open (%s). Is a terminal program using it? Close it and try again.'
                % (port_name or E.DEV, e)); return
        port.quiet()
        try: port.run(answering(job(b, say), lambda q, d: input(q)))
        except KeyboardInterrupt: say('\n(stopped)')
        finally: port.close()
    say('Elf2K card tool - this build: LTOS kernel stamp $%04X, %d system files, STELLAR V00%s'
        % (b.stamp, len(b.files), b.fw_version))
    run(job_look)
    while True:
        say('')
        for k, t, f in MENU: say('  %-2s %s' % (k, t))
        say('  Q  Quit')
        try: c = input('Which? ').strip().upper()
        except EOFError: c = 'Q'
        if c == 'Q': break
        job = {k: f for k, t, f in MENU}.get(c)
        if job: say(''); run(job)


if __name__ == '__main__':
    main()
