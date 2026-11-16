# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""CONTACTS.PRG on the simulated Elf2K. A card made on the Mac with BIG.TXT (a book of 300 contacts, ~45 KB - more
than the Elf2K's memory - and one contact of 5 KB, too big to keep in memory). One boot: CONTACTS adds two
(Backspace used; one with only a NAME), Esc adds nothing, a search over all fields, -f CITY, -f NAME (none: $? 1),
-l, -e (CITY changed, the rest kept with Enter), -d (asked, Y), then on BIG.TXT:
a search for the last contact, -d of one in the middle, -d with Q (nothing changed), a search for a word in the
contact too big (not searched). Then the Mac reads /CONTACTS.TXT and BIG.TXT and checks every byte, and fsck.

    python3 LTOS/verify_contacts.py [-v]
"""
import os, re, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2
import build

FIELDS = ['NAME', 'ADDRESS', 'ADDRESS2', 'CITY', 'STATE/CO', 'POSTCODE', 'COUNTRY', 'TEL', 'EMAIL', 'BDAY', 'NOTE']
ADA = ['Ada Lovelace', '12 St James Square', '', 'London', 'Middlesex', 'SW1Y 4LE', 'England', '555 0100', 'ada@example.com',
       '10 December', 'the first programmer']
BOB = ['Bob Smith'] + [''] * 10


def rec(vals, extra=b''):
    return b''.join((f + ':' + (' ' + v if v else '')).encode() + b'\r\n' for f, v in zip(FIELDS, vals)) + extra + b'\r\n'


def bigbook():
    out = []
    for i in range(300):
        v = ['Person %03d' % i, '%d High Street' % i, '', 'Town%d' % (i % 7), '', 'D%02d' % (i % 24), 'Ireland', '01 %06d' % i,
             'p%03d@example.com' % i, '', 'number %d' % i]
        out.append(rec(v))
        if i == 100:                                    # a contact too big for memory (5 KB of notes)
            out.append(b'NAME: Huge Contact\r\n' + b''.join(b'NOTE: zebra line %03d ...........................\r\n' % k
                                                             for k in range(100)) + b'\r\n')
    return out


def main():
    v = '-v' in sys.argv
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e
    _, syms = build.assemble('contacts')
    report('CONTACTS.PRG fits ($3000-$%04X; OUTB at $5000)' % syms['VEND'],
           [] if syms['VEND'] <= 0x5000 else ['the variables end at $%04X' % syms['VEND']])

    kimg, _ = build.kernel()
    mem, _, _ = build.build(kimg)
    n = 16384
    cf, e2k, st = P1.installed(mem, n)
    big = bigbook()
    def put(m):
        b = os.path.join(m, 'BIN')
        if not os.path.isdir(b): os.mkdir(b)
        open(os.path.join(b, 'CONTACTS.PRG'), 'wb').write(build.prg('contacts'))
        open(os.path.join(m, 'BIG.TXT'), 'wb').write(b''.join(big))
    img, _ = P2.mac(V.image(cf, n), put)
    P1.load_image(cf, img)

    P = 'LTOS> '
    def typed(vals):                                    # each field's prompt, then what is typed
        return [(f + ': ', x) for f, x in zip(FIELDS, vals)]
    ada_keys = [x.encode() + b'\r' for x in ADA]
    ada_keys[3] = b'Lx\x08ondon\r'                       # Backspace
    later = [(P, b'CONTACTS\r')] + typed(ada_keys)
    later += [(P, b'CONTACTS -a\r')] + typed([b'Bob Smith\r'] + [b'\r'] * 10)
    later += [(P, b'CONTACTS\r'), ('NAME: ', b'Carl\r'), ('ADDRESS: ', b'1 Road\r'), ('ADDRESS2: ', b'\x1b')]
    later += [(P, b'CONTACTS -b X.TXT -a\r'), ('NAME: ', b'\r')]
    cmds = ['CONTACTS london', 'CONTACTS -f CITY lONdon', 'CONTACTS -f NAME london', 'CONTACTS -l',
            'CONTACTS "ada love" first', 'CONTACTS -f POSTCODE sw1y', 'CONTACTS -e smith']
    for c in cmds[:-1]: later.append((P, c.encode() + b'\r'))
    later += [(P, b'CONTACTS -e smith\r'), ('(Y/N, Q: no more) ', b'y')]
    later += [('NAME: Bob Smith', b'\r'), ('ADDRESS: ', b'\r'), ('ADDRESS2: ', b'\r'), ('CITY: ', b'Paris\r')]
    later += [(f + ': ', b'\r') for f in FIELDS[4:]]
    later += [(P, b'CONTACTS -d ada\r'), ('(Y/N, Q: no more) ', b'Y')]
    later += [(P, b'CONTACTS -b BIG.TXT 299\r'), (P, b'CONTACTS -b BIG.TXT -d "person 150"\r'),
              ('(Y/N, Q: no more) ', b'y'), (P, b'CONTACTS -b BIG.TXT -d town3\r'), ('(Y/N, Q: no more) ', b'q'),
              (P, b'CONTACTS -b BIG.TXT zebra\r'), (P, b'CONTACTS -b NOPE.TXT x\r'), (P, b'CONTACTS -z\r'),
              (P, b'MON\r')]
    b = V.Elf2K(cf, keys=b'', later=later)
    stat = []
    f0 = b.u.feed
    def feed():
        k = len(b.u.later)
        if k and b.u.later[0][0] == P:
            f0()
            if len(b.u.later) < k: stat.append(b.c.M[0x033F])
        else: f0()
    b.u.feed = feed
    t0 = time.time()
    s = b.boot_rom(40_000_000_000)
    t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', b.text().replace('\r', ''))
    if v: print(t[-9000:])
    parts = re.split(r'(?m)^LTOS> ', t)[1:]
    res = []
    for k, p in enumerate(parts):
        c, _, body = p.partition('\n')
        res.append((c, body, stat[k + 1] if k + 1 < len(stat) else None))
    def seg(cmd, i=0):
        m = [r for r in res if r[0] == cmd]
        return m[i] if len(m) > i else ('', '', None)
    print('(%.0f s on the Mac)' % (time.time() - t0))
    e = [] if s == 'stop' else ['the end: %s' % s]

    c, body, rc = seg('CONTACTS')
    if 'Added: /CONTACTS.TXT has 1 contact.' not in body or rc != 0: e.append('add Ada: %r %r' % (body[-300:], rc))
    c, body, rc = seg('CONTACTS -a')
    if 'has 2 contacts.' not in body: e.append('add Bob: %r' % body[-300:])
    c, body, rc = seg('CONTACTS', 1)
    if 'Nothing added.' not in body or rc != 1: e.append('Esc: %r %r' % (body[-300:], rc))
    c, body, rc = seg('CONTACTS -b X.TXT -a')
    if 'Nothing added.' not in body or rc != 1: e.append('no NAME: %r %r' % (body[-300:], rc))
    report('add: two contacts (Backspace; Enter leaves a field empty), Esc and no NAME add nothing ($? 1)', e)

    e = []
    shown = ''.join((f + ': ' + x + '\n') for f, x in zip(FIELDS, ADA) if x) + '\n'
    for cmd in ('CONTACTS london', 'CONTACTS -f CITY lONdon', 'CONTACTS "ada love" first', 'CONTACTS -f POSTCODE sw1y'):
        c, body, rc = seg(cmd)
        if body != shown + '1 contact found.\n' or rc != 0: e.append('%s: %r %r' % (cmd, body, rc))
    c, body, rc = seg('CONTACTS -f NAME london')
    if body != 'No contact found.\n' or rc != 1: e.append('-f NAME: %r %r' % (body, rc))
    c, body, rc = seg('CONTACTS -l')
    if body != 'Ada Lovelace\nBob Smith\n2 contacts found.\n': e.append('-l: %r' % body)
    report('search: all fields (any case), "two words", -f CITY, -f POSTCODE, -f NAME (none, $? 1), -l', e)

    e = []
    c, body, rc = seg('CONTACTS -e smith')
    if 'Changed 1 contact.' not in body or rc != 0: e.append('-e: %r %r' % (body[-400:], rc))
    c, body, rc = seg('CONTACTS -d ada')
    if 'Deleted 1 contact.' not in body or rc != 0: e.append('-d: %r %r' % (body[-400:], rc))
    c, body, rc = seg('CONTACTS -b BIG.TXT 299')
    want = 'NAME: Person 299\nADDRESS: 299 High Street\nCITY: Town5\nPOSTCODE: D11\nCOUNTRY: Ireland\nTEL: 01 000299\n' \
           'EMAIL: p299@example.com\nNOTE: number 299\n\n1 contact found.\n'
    if body != want: e.append('BIG 299: %r' % body)
    c, body, rc = seg('CONTACTS -b BIG.TXT -d "person 150"')
    if 'Deleted 1 contact.' not in body: e.append('BIG -d: %r' % body[-300:])
    c, body, rc = seg('CONTACTS -b BIG.TXT -d town3')
    if 'Nothing changed.' not in body: e.append('BIG -d Q: %r' % body[-300:])
    c, body, rc = seg('CONTACTS -b BIG.TXT zebra')
    if body != 'No contact found.\n': e.append('zebra: %r' % body)
    c, body, rc = seg('CONTACTS -b NOPE.TXT x')
    if 'There is no NOPE.TXT yet' not in body or rc != 1: e.append('NOPE: %r %r' % (body, rc))
    c, body, rc = seg('CONTACTS -z')
    if 'Usage:' not in body or rc != 1: e.append('usage: %r %r' % (body, rc))

    got = {}
    def rd(m):
        for x in ('CONTACTS.TXT', 'BIG.TXT', 'X.TXT'):
            p = os.path.join(m, x)
            got[x] = open(p, 'rb').read() if os.path.exists(p) else None
    P2.mac(V.image(cf, n), rd)
    bob = BOB[:]; bob[3] = 'Paris'
    if got['CONTACTS.TXT'] != rec(bob): e.append('/CONTACTS.TXT: %r' % got['CONTACTS.TXT'])
    if got['X.TXT'] is not None: e.append('X.TXT made')
    wantbig = b''.join(x for x in big if not x.startswith(b'NAME: Person 150\r'))
    if got['BIG.TXT'] != wantbig:
        g = got['BIG.TXT'] or b''
        i = next((k for k in range(min(len(g), len(wantbig))) if g[k] != wantbig[k]), min(len(g), len(wantbig)))
        e.append('BIG.TXT: %d bytes, want %d; first difference at %d: %r' % (len(g), len(wantbig), i, g[i - 40:i + 40]))
    report('edit (CITY changed, Enter keeps), delete (Y); BIG.TXT (%d bytes): search, delete in the middle, Q '
           'changes nothing, the 5 KB contact kept as it is; no book, usage ($? 1); the files byte for byte'
           % len(b''.join(big)), e)
    rc, _ = P2.fsck_free(V.image(cf, n))
    report('fsck_msdos: the card clean', ['fsck_msdos: %d' % rc] if rc else [])
    print('\nCONTACTS: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
