#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/card_layout.py - the card layout template (LTOS/layout.txt): where LTOS's programs, apps, songs and examples
go on a card. Only the names it lists are ever moved - a person's own files never.

    python3 tools/card_layout.py show                     the template
    python3 tools/card_layout.py image CARD.ide [...]     an Emma 02 card image (or any raw LTOS image) arranged to it
                                                          (Emma 02 closed; a copy kept as CARD-before-layout-DATE.ide)
In code:
    moves(files)            {path: ...} of a card -> [(path, the folder it belongs in)]
    arrange_session(say)    on the Elf2K (a session for elf2k_card.py / the simulator): MKDIR, MV
    arrange_dir(top)        a folder tree on the Mac (a mounted card, the web card's files): mkdir, rename
    arrange_image(path)     an image file, its FAT16 changed in Python (no mount)
"""
import datetime, os, shutil, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'LTOS'))
LAYOUT = os.path.join(HERE, '..', 'LTOS', 'layout.txt')


def load(path=LAYOUT):
    """-> ({NAME: folder}, [folders in order])"""
    where, folders, cur = {}, [], None
    for ln in open(path):
        if ln.startswith('#') or not ln.strip(): continue
        if not ln[0].isspace():
            cur, _, rest = ln.partition(':'); cur = cur.strip(); folders.append(cur)
        else: rest = ln
        for n in rest.split(): where[n.upper()] = cur
    return where, folders


def parent_chain(folder):
    """/BIN/GAMES -> ['/BIN', '/BIN/GAMES']"""
    parts = [p for p in folder.split('/') if p]
    return ['/' + '/'.join(parts[:k]) for k in range(1, len(parts) + 1)]


def moves(files, template=None):
    """A card's files ({path: anything}) -> [(path, folder)]: each listed name not in its folder. A name already in its
    folder is left alone everywhere (a second copy elsewhere is the person's business, not a move)."""
    where, _ = template or load()
    have = {}
    for p in files:
        f, n = p.rsplit('/', 1); have.setdefault(n.upper(), []).append(f or '/')
    out = []
    for n, fs in sorted(have.items()):
        w = where.get(n)
        if w is None or w in fs or len(fs) != 1: continue
        out.append(((fs[0].rstrip('/') + '/' + n) if fs[0] != '/' else '/' + n, w))
    return out


def needed_folders(mv):
    out = []
    for p, w in mv:
        for f in parent_chain(w):
            if f not in out: out.append(f)
    return out


# ---- on the Elf2K (session steps, as cardfiles.py / elf2k_card.py)
def arrange_session(say, files=None):
    """-> [problems]. The card's files read (unless given), folders made, files moved with MV."""
    import cardfiles as CF, cardsync as CS
    if files is None:
        files, dirs = yield from CS.Serial(cr=False).walk(say)
    mv = moves(files)
    if not mv: say('  Every program is where the template puts it.'); return []
    have_dirs = {p.rsplit('/', 1)[0] for p in files}
    for f in needed_folders(mv):
        if f not in have_dirs: yield from CF.cmd('MKDIR ' + f)
    probs = []
    for k, (p, w) in enumerate(mv, 1):
        out = yield from CF.cmd('MV %s %s' % (p, w), 20.0)
        body = out.split('\n', 1)[1] if '\n' in out else out
        if any(x in body for x in ('not', 'No ', 'There is', '?', 'Usage')): probs.append('%s: %s' % (p, body.strip()[:80]))
        say('  %3d/%d  %-24s -> %s' % (k, len(mv), p, w))
    return probs


# ---- a folder tree on the Mac
def arrange_dir(top, say=print):
    """Files under top (a mounted card, the web card's tree) moved to the template's folders -> the moves done."""
    files = {}
    for d, ds, fs in os.walk(top):
        rel = '/' + os.path.relpath(d, top).replace(os.sep, '/').strip('./')
        rel = '/' if rel in ('/', '/.') else rel.upper()
        for f in fs:
            if not f.startswith('.'): files[(rel.rstrip('/') + '/' + f.upper()) if rel != '/' else '/' + f.upper()] = os.path.join(d, f)
    mv = moves(files)
    for p, w in mv:
        dst = os.path.join(top, *[x for x in w.split('/') if x])
        os.makedirs(dst, exist_ok=True)
        shutil.move(files[p], os.path.join(dst, p.rsplit('/', 1)[1]))
        say('  moved %s -> %s' % (p, w))
    return mv


# ---- an image file (Emma 02's .ide, the web card), no mount
def arrange_image(path, say=print, check=True):
    """-> the moves done (the image rewritten in one go)."""
    import cardsync as CS
    im = CS.Image(path, check=check)
    if CS.run(im.open(say)) is None: return None
    files, dirs = CS.run(im.walk(say))
    mv = moves(files)
    for f in needed_folders(mv):
        if f not in dirs: im.mkdir(f); dirs.add(f)
    for p, w in mv:
        folder, name = p.rsplit('/', 1)
        o, found = im.entry(folder or '/', name)
        n, taken = im.entry(w, name)
        if not found or taken: say('** %s: not moved (%s)' % (p, 'gone' if not found else 'already in ' + w)); continue
        im.img[n:n + 32] = im.img[o:o + 32]                  # the same entry - name, size, date, clusters - in its new folder
        im.img[o] = 0xE5                                      # and gone from the old one
        say('  moved %s -> %s' % (p, w))
    tmp = path + '.layout-tmp'
    with open(tmp, 'wb') as f: f.write(im.img)
    shutil.copymode(path, tmp); os.replace(tmp, path)
    return mv


def main(argv):
    if argv[:1] == ['show']:
        where, folders = load()
        for f in folders: print('%s: %s' % (f, ' '.join(sorted(n for n, w in where.items() if w == f))))
    elif argv[:1] == ['image'] and len(argv) > 1:
        for p in argv[1:]:
            root, ext = os.path.splitext(p)
            bak = '%s-before-layout-%s%s' % (root, datetime.date.today().isoformat(), ext)
            if not os.path.exists(bak): shutil.copyfile(p, bak)
            mv = arrange_image(p)
            if mv is not None: print('%s: %d moved (a copy before: %s)' % (p, len(mv), os.path.basename(bak)))
    else: raise SystemExit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
