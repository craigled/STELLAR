#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/tomus.py - music from the internet made into PLAY's .MUS files (a tune file for LTOS's PLAY.PRG).

    python3 LTOS/tomus.py SONG.abc                 -> TITLE.MUS beside it (8.3 name from the title)
    python3 LTOS/tomus.py SONG.mid -o HYMN.MUS     a MIDI file: the melody (the top note of the busiest part)
    python3 LTOS/tomus.py SONG.mid --list          its tracks, to pick one with --track N
    python3 LTOS/tomus.py TUNES.abc --tune 3       ABC with several tunes: X:3 (default: the first)
    python3 LTOS/tomus.py RING.txt                 an RTTTL ringtone   name:d=4,o=5,b=100:8e,8p,c#6 ...
    python3 LTOS/tomus.py OLD.BAS                  a BASIC program's PLAY "..." strings (GW-BASIC, QBasic)

  --transpose N   semitones up (or down: -12 an octave); out of PLAY's O1-O7 it moves by octaves on its own
  --tempo N       quarter notes a minute, in place of the file's
  --grid N        MIDI only: notes snapped to 1/N of a whole note (default 16; 12 or 24 keeps triplets)
  --title TEXT    the title PLAY prints (default: the file's)

Formats: ABC (abcnotation.com, thesession.org: one melody line - notes, accidentals, the key, lengths, broken rhythm
> <, triplets, ties, chords (the top note), repeats and 1st/2nd endings; grace notes, decorations and chord names
are left out), RTTTL (A4 = 440 is octave 4, as PLAY's), Standard MIDI files (type 0 and 1; tempo changes kept;
the drum channel left out), and BASIC (middle C is O3 there, O4 in PLAY: shifted; N, P, MB/MF handled).
"""
import os, re, sys, struct
from fractions import Fraction as F
from collections import Counter

NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
SEMI = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
LOW, HIGH = 24, 107                    # PLAY's C1 .. B7 (MIDI numbers; middle C = 60 = O4 C)
MAXFILE = 12000                        # PLAY loads a file into about 12 KB


class Song:
    """What every reader makes: events in order - ('n', midi, quarters), ('r', quarters), ('t', quarters a minute),
    ('a', 'N' | 'L' | 'S'), ('bar',) - and a title."""
    def __init__(self, title=''):
        self.title, self.ev, self.notes = title, [], []

    def note(self, m, q): self.ev.append(('n', m, F(q)))
    def rest(self, q): self.ev.append(('r', F(q)))
    def tempo(self, t): self.ev.append(('t', t))
    def art(self, a): self.ev.append(('a', a))
    def bar(self): self.ev.append(('bar',))


# ---------------------------------------------------------------------------------------------------- ABC
KEYS = {'C': 0, 'G': 1, 'D': 2, 'A': 3, 'E': 4, 'B': 5, 'F': -1}
MODES = {'': 0, 'maj': 0, 'ion': 0, 'm': -3, 'min': -3, 'aeo': -3, 'mix': -1, 'dor': -2, 'phr': -4, 'lyd': 1, 'loc': -5}


def abc_key(v):
    """K: value -> {letter: +1 / -1} for the key signature."""
    m = re.match(r'\s*([A-G])([#b]?)\s*([A-Za-z]*)', v or '')
    if not m: return {}
    n = KEYS[m.group(1)] + (7 if m.group(2) == '#' else -7 if m.group(2) == 'b' else 0)
    mode = m.group(3).lower()
    n += MODES.get(mode[:3], MODES.get(mode, 0)) if mode not in ('m', 'min') else -3
    acc = {}
    for c in 'FCGDAEB'[:max(0, n)]: acc[c] = 1
    for c in 'BEADGCF'[:max(0, -n)]: acc[c] = -1
    return acc


def abc_meter(v):
    v = (v or '').strip()
    if v == 'C': return F(4, 4)
    if v == 'C|': return F(2, 2)
    m = re.match(r'(\d+)\s*/\s*(\d+)', v)
    return F(int(m.group(1)), int(m.group(2))) if m else None


def abc_len(s, i):
    """A length at s[i]: '2', '/', '//', '3/2', '/4' -> (multiplier, next i)."""
    m = re.compile(r'(\d*)(/*)(\d*)').match(s, i)
    num = int(m.group(1)) if m.group(1) else 1
    if m.group(2):
        den = int(m.group(3)) if m.group(3) else 2 ** len(m.group(2))
    else:
        den = 1
    return F(num, den), m.end()


def read_abc(text, tune=None):
    tunes, cur = [], None
    for line in text.replace('\r', '\n').split('\n'):
        mx = re.match(r'X:\s*(\d+)', line)
        if mx: cur = [int(mx.group(1)), []]; tunes.append(cur)
        elif cur is not None: cur[1].append(line)
    if not tunes: tunes = [[1, text.replace('\r', '\n').split('\n')]]
    pick = [t for t in tunes if tune is None or t[0] == tune]
    if not pick: raise SystemExit('no tune X:%s in the file (there are: %s)' % (tune, ', '.join(str(t[0]) for t in tunes)))
    lines = pick[0][1]
    st = {'L': None, 'M': F(4, 4), 'K': {}, 'Q': None, 'voice': None, 'first_voice': None}
    title, composer, body, inbody = [], [], [], False
    items = []                                     # ('n', midi, q, tied) ('r', q) ('t', bpm) and bar items
    # ---- the music, line by line
    bar_acc = {}
    tup = [0, F(1)]                                # notes left in a tuplet, its factor
    broken = None                                  # ('>' or '<', count) waiting for the next note

    def unit():
        if st['L']: return st['L']
        return F(1, 16) if st['M'] is not None and st['M'] < F(3, 4) else F(1, 8)

    def field(k, v):
        v = v.strip()
        if k == 'T': title.append(v)
        elif k == 'C': composer.append(v)
        elif k == 'L':
            m = re.match(r'(\d+)\s*/\s*(\d+)', v)
            if m: st['L'] = F(int(m.group(1)), int(m.group(2)))
        elif k == 'M': st['M'] = abc_meter(v)
        elif k == 'K':
            st['K'] = abc_key(v)
            return True
        elif k == 'Q':
            m = re.search(r'(\d+)\s*/\s*(\d+)\s*=\s*(\d+)', v)
            if m: bpm = int(m.group(3)) * F(int(m.group(1)), int(m.group(2))) * 4
            else:
                m = re.search(r'(?:^|=)\s*(\d+)\s*$', v)
                bpm = int(m.group(1)) * unit() * 4 if m else None
            if bpm:
                st['Q'] = bpm
                if inbody: items.append(('t', bpm))
        elif k == 'V':
            vid = v.split()[0] if v.split() else ''
            if st['first_voice'] is None: st['first_voice'] = vid
            st['voice'] = vid
        return False

    def put_note(m, q, tied):
        nonlocal broken
        q = q * unit() * 4                          # whole notes -> quarters
        if tup[0]:
            q *= tup[1]; tup[0] -= 1
        if broken:
            d, n = broken
            prev = next((k for k in range(len(items) - 1, -1, -1) if items[k][0] in ('n', 'r')), None)
            a, b = 2 - F(1, 2 ** n), F(1, 2 ** n)
            if d == '<': a, b = b, a
            if prev is not None:
                it = list(items[prev]); it[2 if it[0] == 'n' else 1] *= a; items[prev] = tuple(it)
            q *= b; broken = None
        items.append(('n', m, q, tied) if m is not None else ('r', q))

    for raw in lines:
        line = raw.split('%')[0] if not raw.startswith('%%') else ''
        if not line.strip(): continue
        mf = re.match(r'([A-Za-z]):(.*)$', line)
        if mf:
            if mf.group(1) in 'wW': continue       # the words
            if field(mf.group(1), mf.group(2)) and not inbody:
                inbody = True
                if st['Q']: items.append(('t', st['Q']))
            continue
        if not inbody: continue
        if st['first_voice'] is not None and st['voice'] != st['first_voice']: continue
        s, i = line, 0
        while i < len(s):
            c = s[i]
            if c in ' \t`y$\\': i += 1
            elif c == '"':
                j = s.find('"', i + 1); i = len(s) if j < 0 else j + 1
            elif c == '!':
                j = s.find('!', i + 1); i = len(s) if j < 0 else j + 1
            elif c == '+' and s.find('+', i + 1) > 0:
                i = s.find('+', i + 1) + 1
            elif c == '{':
                j = s.find('}', i + 1); i = len(s) if j < 0 else j + 1
            elif c == '[' and re.match(r'\[[A-Za-z]:', s[i:]):
                j = s.find(']', i)
                k = s[i + 1]; field(k, s[i + 3:j if j > 0 else len(s)])
                i = len(s) if j < 0 else j + 1
            elif c == '[' and i + 1 < len(s) and s[i + 1].isdigit():
                items.append(('volta', int(s[i + 1]))); i += 2
                while i < len(s) and (s[i].isdigit() or s[i] in ',-'): i += 1
            elif c == '[' and s[i + 1:i + 2] == '|':
                items.append(('bar', '[|')); bar_acc = {}; i += 2
            elif c == '[':                         # a chord: its top note
                j = s.find(']', i)
                if j < 0: i += 1; continue
                best, first_len, k = None, None, i + 1
                while k < j:
                    m2 = re.compile(r"([_^=]*)([A-Ga-g])([',]*)").match(s, k)
                    if not m2: k += 1; continue
                    p = pitch(m2, st, bar_acc)
                    ln, k = abc_len(s, m2.end())
                    if first_len is None: first_len = ln
                    if best is None or p > best: best = p
                    while k < j and s[k] == '-': k += 1
                mul, i = abc_len(s, j + 1)
                tied = i < len(s) and s[i] == '-'
                if tied: i += 1
                if best is not None: put_note(best, (first_len or 1) * mul, tied)
            elif c in '|:':                        # bar lines and repeats
                m3 = re.compile(r'(:*)(\|+|\[\|)?(\])?(:*)').match(s, i)
                txt = m3.group(0) or c
                i = m3.end() if m3.end() > i else i + 1
                pre, post = len(m3.group(1)), len(m3.group(4))
                if (pre and post) or (pre >= 2 and not m3.group(2)): items.append(('bar', '::'))
                elif pre: items.append(('bar', ':|'))
                elif post: items.append(('bar', '|:'))
                elif m3.group(3) or (m3.group(2) and len(m3.group(2)) > 1): items.append(('bar', '||'))
                else: items.append(('bar', '|'))
                bar_acc = {}
                if i < len(s) and s[i].isdigit():
                    items.append(('volta', int(s[i]))); i += 1
                    while i < len(s) and (s[i].isdigit() or s[i] in ',-'): i += 1
            elif c == '(':
                m4 = re.compile(r'\((\d)(?::(\d*))?(?::(\d*))?').match(s, i)
                if m4:
                    p = int(m4.group(1))
                    comp = st['M'] is not None and st['M'].numerator % 3 == 0 and st['M'].numerator > 3
                    q = int(m4.group(2)) if m4.group(2) else {2: 3, 3: 2, 4: 3, 6: 2, 8: 3}.get(p, 3 if comp else 2)
                    r = int(m4.group(3)) if m4.group(3) else p
                    tup[0], tup[1] = r, F(q, p); i = m4.end()
                else: i += 1                       # a slur
            elif c in '<>':
                n = 0
                while i < len(s) and s[i] == c: n += 1; i += 1
                broken = (c, n)
            elif c == '-':
                for k in range(len(items) - 1, -1, -1):
                    if items[k][0] == 'n': items[k] = items[k][:3] + (True,); break
                i += 1
            elif c in 'zx':
                ln, i = abc_len(s, i + 1); put_note(None, ln, False)
            elif c == 'Z':
                n, i = abc_len(s, i + 1)
                bar = (st['M'] or F(4, 4)) * 4
                items.append(('r', bar * n))
            elif c in '_^=' or c in 'ABCDEFGabcdefg':
                m2 = re.compile(r"([_^=]*)([A-Ga-g])([',]*)").match(s, i)
                if not m2: i += 1; continue
                p = pitch(m2, st, bar_acc)
                ln, i = abc_len(s, m2.end())
                tied = i < len(s) and s[i] == '-'
                if tied: i += 1
                put_note(p, ln, tied)
            else:
                i += 1                             # decorations (~ . H L M O P S T u v), ), stray characters
    song = Song(' / '.join(title[:1]) or '')
    if composer: song.composer = composer[0]
    if not any(it[0] == 't' for it in items):      # no Q: a usual pace for the meter
        m = st['M']
        song.tempo(150 if m is not None and m.numerator % 3 == 0 and m.numerator > 3 else 120)
    for it in expand(items):
        if it[0] == 'n': song.ev.append(('n', it[1], it[2], it[3]))
        elif it[0] == 'r': song.rest(it[1])
        elif it[0] == 't': song.tempo(it[1])
        elif it[0] == 'bar': song.bar()
    song.ev = tie(song.ev)
    return song


def pitch(m, st, bar_acc):
    acc, letter, octs = m.group(1), m.group(2), m.group(3)
    n = 60 + SEMI[letter.upper()] + (12 if letter.islower() else 0) + 12 * octs.count("'") - 12 * octs.count(',')
    key = (letter.upper(), n // 12)
    if acc:
        a = acc.count('^') - acc.count('_')
        bar_acc[key] = a
    else:
        a = bar_acc.get(key, st['K'].get(letter.upper(), 0))
    return n + a


def expand(items):
    """Repeats played out: |: ... :| twice; [1 the first time round, [2 the second."""
    out, i, start, passn, skipping, guard = [], 0, 0, 1, False, 0
    while i < len(items):
        guard += 1
        if guard > 200000: break
        it = items[i]
        if it[0] == 'volta':
            skipping = it[1] != passn; i += 1; continue
        if it[0] == 'bar' and it[1] in (':|', '::'):
            if passn == 1 and not skipping:         # the first time: back to the start of the section
                passn = 2; out.append(('bar', '|')); i = start; continue
            if skipping: skipping = False           # the end of a 1st ending, the second time: on to the 2nd
            else: passn = 1                         # the end of the second time
            start = i + 1
            if it[1] == '::': passn = 1
            out.append(('bar', '|')); i += 1; continue
        if it[0] == 'bar' and it[1] == '|:':
            start = i + 1; passn = 1; skipping = False
            out.append(('bar', '|')); i += 1; continue
        if it[0] == 'bar' and it[1] in ('||', '[|'):
            skipping = False; passn = 1; start = i + 1
        if not skipping: out.append(it)
        i += 1
    return out


def tie(ev):
    """Tied notes of the same pitch made one (across bar lines)."""
    out = []
    for e in ev:
        if e[0] == 'n':
            if out:
                k = len(out) - 1
                while k >= 0 and out[k][0] == 'bar': k -= 1
                if k >= 0 and out[k][0] == 'n' and len(out[k]) > 3 and out[k][3] and out[k][1] == e[1]:
                    out[k] = ('n', e[1], out[k][2] + e[2], len(e) > 3 and e[3]); continue
            out.append(e)
        else:
            out.append(e)
    return [e[:3] if e[0] == 'n' else e for e in out]


# ---------------------------------------------------------------------------------------------------- RTTTL
def read_rtttl(text):
    text = ' '.join(text.split())
    parts = text.split(':')
    if len(parts) < 3: raise SystemExit('not RTTTL: name:d=4,o=5,b=100:notes')
    name, defs, notes = parts[0].strip(), parts[1], ':'.join(parts[2:])
    d, o, b = 4, 6, 63
    for kv in defs.split(','):
        k, _, v = kv.strip().partition('=')
        if k.lower() == 'd' and v.strip().isdigit(): d = int(v)
        if k.lower() == 'o' and v.strip().isdigit(): o = int(v)
        if k.lower() == 'b' and v.strip().isdigit(): b = int(v)
    song = Song(name)
    song.tempo(b)
    for tok in notes.split(','):
        tok = tok.strip().lower()
        if not tok: continue
        m = re.match(r'(\d*)([a-gp])(#?)(\.?)(\d?)(\.?)$', tok)
        if not m: raise SystemExit('RTTTL: what is %r?' % tok)
        q = F(4, int(m.group(1)) if m.group(1) else d)
        if m.group(4) or m.group(6): q *= F(3, 2)
        if m.group(2) == 'p': song.rest(q); continue
        octave = int(m.group(5)) if m.group(5) else o
        song.note(12 * (octave + 1) + SEMI[m.group(2).upper()] + (1 if m.group(3) else 0), q)
    return song


# ---------------------------------------------------------------------------------------------------- BASIC
def read_basic(text, name):
    """The strings every PLAY statement plays (literals, and string variables set to literals), in order."""
    vars_, out = {}, []
    for line in text.replace('\r', '\n').split('\n'):
        line = re.sub(r'(?i)^\s*\d*\s*REM\b.*', '', line)
        for stmt in re.split(r':(?=(?:[^"]*"[^"]*")*[^"]*$)', line):
            m = re.match(r'\s*(?:\d+\s+)?(?:LET\s+)?([A-Za-z]\w*\$)\s*=\s*(.*)$', stmt, re.I)
            if m:
                vars_[m.group(1).upper()] = basic_expr(m.group(2), vars_); continue
            m = re.search(r'\bPLAY\s+(.*)$', stmt, re.I)
            if m and not re.match(r'\s*(ON|OFF|STOP)\b', m.group(1), re.I):
                out.append(basic_expr(m.group(1), vars_))
    if not out: raise SystemExit('no PLAY statements found')
    return read_mml(' '.join(out), name, basic=True)


def basic_expr(e, vars_):
    s = ''
    for lit, var in re.findall(r'"([^"]*)"?|([A-Za-z]\w*\$)', e):
        s += lit if lit or not var else vars_.get(var.upper(), '')
    return s


def read_mml(s, name, basic=False):
    """BASIC's music language. O0-O6 there, middle C = O3: one octave up here."""
    song = Song(name)
    o, L, i, s = 4, 4, 0, s.upper()
    song.tempo(120)
    def num(i):
        m = re.compile(r'\s*(\d+)').match(s, i)
        return (int(m.group(1)), m.end()) if m else (None, i)
    def dots(i, q):
        add = q / 2
        while i < len(s) and s[i] == '.': q += add; add /= 2; i += 1
        return q, i
    while i < len(s):
        c = s[i]; i += 1
        if c in 'ABCDEFG':
            n = 12 * (o + 2) + SEMI[c]
            if i < len(s) and s[i] in '#+': n += 1; i += 1
            elif i < len(s) and s[i] == '-': n -= 1; i += 1
            v, i = num(i)
            q, i = dots(i, F(4, v if v else L))
            song.note(n, q)
        elif c in 'PR':
            v, i = num(i)
            q, i = dots(i, F(4, v if v else L))
            song.rest(q)
        elif c == 'N':
            v, i = num(i)
            q, i = dots(i, F(4, L))
            if v: song.note(v + 23, q)
            else: song.rest(q)
        elif c == 'O':
            v, i = num(i)
            if v is not None: o = max(0, min(6, v))
        elif c == '>': o = min(6, o + 1)
        elif c == '<': o = max(0, o - 1)
        elif c == 'L':
            v, i = num(i)
            if v: L = v
        elif c == 'T':
            v, i = num(i)
            if v: song.tempo(v)
        elif c == 'M' and i < len(s):
            k = s[i]; i += 1
            if k in 'NLS': song.art(k)
        elif c == 'X':
            print('warning: X (play another string) is not followed', file=sys.stderr)
            while i < len(s) and s[i] != ';': i += 1
    return song


# ---------------------------------------------------------------------------------------------------- MIDI
def varlen(b, i):
    v = 0
    while True:
        c = b[i]; i += 1; v = (v << 7) | (c & 0x7F)
        if not c & 0x80: return v, i


def read_midi_tracks(b):
    if b[:4] != b'MThd': raise SystemExit('not a MIDI file')
    hl = struct.unpack('>I', b[4:8])[0]
    fmt, ntr, div = struct.unpack('>HHH', b[8:14])
    if div & 0x8000: raise SystemExit('MIDI with SMPTE time is not handled')
    p, tracks, tempos, sigs = 8 + hl, [], [], []
    for t in range(ntr):
        while b[p:p + 4] != b'MTrk':
            if p >= len(b): break
            p += 8 + struct.unpack('>I', b[p + 4:p + 8])[0]
        if p >= len(b): break
        ln = struct.unpack('>I', b[p + 4:p + 8])[0]
        i, end, tick, run = p + 8, p + 8 + ln, 0, 0
        tr = {'name': '', 'notes': [], 'chans': Counter()}
        on = {}
        while i < end:
            dt, i = varlen(b, i); tick += dt
            st = b[i]
            if st == 0xFF:
                typ = b[i + 1]; l, j = varlen(b, i + 2); data = b[j:j + l]; i = j + l
                if typ == 0x51: tempos.append((tick, int.from_bytes(data, 'big')))
                elif typ == 0x58 and l >= 2: sigs.append((tick, data[0], 2 ** data[1]))
                elif typ in (0x03,) and not tr['name']: tr['name'] = data.decode('latin1').strip()
                elif typ == 0x2F: break
                continue
            if st in (0xF0, 0xF7):
                l, j = varlen(b, i + 1); i = j + l; continue
            if st & 0x80: run = st; i += 1
            hi, ch = run >> 4, run & 15
            if hi in (0xC, 0xD): i += 1; continue
            d1, d2 = b[i], b[i + 1]; i += 2
            if hi == 9 and d2 > 0:
                on.setdefault((ch, d1), []).append(tick)
            elif hi == 8 or (hi == 9 and d2 == 0):
                if on.get((ch, d1)):
                    s0 = on[(ch, d1)].pop(0)
                    tr['notes'].append((s0, tick, d1, ch)); tr['chans'][ch] += 1
        tracks.append(tr)
        p = end
    return div, tracks, sorted(tempos), sigs


def read_midi(b, name, track=None, grid=16):
    div, tracks, tempos, sigs = read_midi_tracks(b)
    usable = [(k, t) for k, t in enumerate(tracks) if [n for n in t['notes'] if n[3] != 9]]
    if not usable: raise SystemExit('no notes (other than drums) in this MIDI file')
    if track is not None:
        if not (1 <= track <= len(tracks)): raise SystemExit('--track: 1 to %d' % len(tracks))
        pick = [tracks[track - 1]]
    else:                                          # the melody: the highest-pitched of the busier tracks
        def mel(t): return [n for n in t['notes'] if n[3] != 9]
        most = max(len(mel(t)) for k, t in usable)
        pick = [max((t for k, t in usable if len(mel(t)) >= most * 0.3),
                    key=lambda t: sum(n[2] for n in mel(t)) / len(mel(t)))]
    notes = [n for t in pick for n in t['notes'] if n[3] != 9]
    chans = Counter(n[3] for n in notes)
    if len(chans) > 1 and track is None:          # several instruments in the track: the busiest
        ch = chans.most_common(1)[0][0]; notes = [n for n in notes if n[3] == ch]
    q = F(4, grid)                                 # the grid in quarters
    def snap(t): return F(round(F(t, div) / q)) * q
    notes = sorted(((snap(s), snap(e), p) for s, e, p, c in notes), key=lambda n: (n[0], -n[2]))
    mel = []                                       # the top line: a higher note cuts the one sounding
    for s, e, p in notes:
        if e <= s: continue
        if mel and s < mel[-1][1]:
            if p > mel[-1][2] and s > mel[-1][0]: mel[-1] = (mel[-1][0], s, mel[-1][2]); mel.append((s, e, p))
            continue
        mel.append((s, e, p))
    title = name
    for t in tracks:
        if t['name']: title = t['name']; break
    song = Song(title)
    tq = [(F(t, div), 60000000 / us) for t, us in tempos] or [(F(0), 120.0)]
    ti = 0
    pos = mel[0][0] if mel else F(0)
    bar = F(sigs[0][1] * 4, sigs[0][2]) if sigs else F(4)
    cur_t = None
    while ti + 1 < len(tq) and tq[ti + 1][0] <= pos: ti += 1
    if round(tq[ti][1]) != cur_t: cur_t = round(tq[ti][1]); song.tempo(cur_t)
    for s, e, p in mel:
        while ti + 1 < len(tq) and tq[ti + 1][0] <= s:     # a tempo change: from where it is (a rest split there)
            ti += 1
            at = max(pos, tq[ti][0])
            if at > pos: song.rest(at - pos); pos = at
            if round(tq[ti][1]) != cur_t: cur_t = round(tq[ti][1]); song.tempo(cur_t)
        if s > pos: song.rest(s - pos)
        if s % bar == 0 and song.ev and song.ev[-1][0] != 'bar': song.bar()
        song.note(p, e - s); pos = e
    return song


def list_midi(b):
    div, tracks, tempos, sigs = read_midi_tracks(b)
    print('%d tracks, %d ticks a quarter note' % (len(tracks), div))
    for k, t in enumerate(tracks, 1):
        ns = t['notes']
        if not ns: print('  %2d  %-24s no notes' % (k, t['name'][:24])); continue
        lo, hi = min(n[2] for n in ns), max(n[2] for n in ns)
        print('  %2d  %-24s %5d notes  %s - %s  channels %s%s' % (k, t['name'][:24], len(ns), NAMES[lo % 12] + str(lo // 12 - 1),
              NAMES[hi % 12] + str(hi // 12 - 1), ' '.join(str(c + 1) for c in sorted(t['chans'])), '  (drums)' if 9 in t['chans'] else ''))


# ---------------------------------------------------------------------------------------------------- .MUS out
PIECES = sorted({F(4, L) for L in range(1, 65)} | {F(6, L) for L in range(1, 65)} | {F(7, L) for L in range(1, 65)}, reverse=True)


def spell(q):
    """quarters -> (L, dots), or None if PLAY cannot write it as one note."""
    for dots, num in ((0, 4), (1, 6), (2, 7)):
        L = F(num) / q
        if L.denominator == 1 and 1 <= L <= 64: return int(L), dots
    return None


def split(q):
    """quarters -> lengths PLAY can write, adding up to it (what is below a 64th is dropped)."""
    out = []
    while q > 0:
        if spell(q): out.append(q); break
        p = next((p for p in PIECES if p <= q), None)
        if p is None: break
        out.append(p); q -= p
    return out


def write_mus(song, transpose=0, tempo=None):
    notes = [e[1] for e in song.ev if e[0] == 'n']
    if not notes: raise SystemExit('no notes')
    shift = transpose
    while max(notes) + shift > HIGH and min(notes) + shift - 12 >= LOW: shift -= 12
    while min(notes) + shift < LOW and max(notes) + shift + 12 <= HIGH: shift += 12
    toks, art, oct_, scale, T = [], 'N', None, F(1), None
    lens = Counter()
    ev = []                                        # tempo scaling first: T has to be 32-255
    for e in song.ev:
        if e[0] == 't':
            bpm = tempo if tempo else e[1]
            scale = F(1)
            while bpm / scale > 255: scale *= 2
            while bpm / scale < 32: scale /= 2
            ev.append(('t', max(32, min(255, round(bpm / scale)))))
        elif e[0] == 'n': ev.append(('n', e[1] + shift, e[2] / scale))
        elif e[0] == 'r': ev.append(('r', e[1] / scale))
        else: ev.append(e)
    for e in ev:
        if e[0] == 'n' and spell(e[2]) and spell(e[2])[1] == 0: lens[spell(e[2])[0]] += 1
    L = lens.most_common(1)[0][0] if lens else 4
    out = ['L%d' % L]
    def length(q):
        L2, d = spell(q)
        return ('' if (L2, d) == (L, 0) else str(L2)) + '.' * d
    for e in ev:
        if e[0] == 't':
            if e[1] != T: out.append('T%d' % e[1]); T = e[1]
        elif e[0] == 'a':
            if e[1] != art: out.append('M' + e[1]); art = e[1]
        elif e[0] == 'bar':
            if out and out[-1] != '|': out.append('|')
        elif e[0] == 'r':
            for p in split(e[1]): out.append('R' + length(p))
        elif e[0] == 'n':
            m = max(LOW, min(HIGH, e[1])); o = m // 12 - 1
            if oct_ is None or abs(o - oct_) > 1: out.append('O%d' % o)
            elif o == oct_ + 1: out.append('>')
            elif o == oct_ - 1: out.append('<')
            oct_ = o
            parts = split(e[2])
            if len(parts) > 1 and art != 'L':      # longer than one note can say: the pieces joined, legato
                out.append('ML')
                for p in parts[:-1]: out.append(NAMES[m % 12] + length(p))
                out.append('M' + art); out.append(NAMES[m % 12] + length(parts[-1]))
            else:
                for p in parts: out.append(NAMES[m % 12] + length(p))
    while out and out[-1] == '|': out.pop()
    lines, cur = [], ''
    for t in out:
        if len(cur) + len(t) + 1 > 72 and cur:
            lines.append(cur.rstrip()); cur = ''
        cur += t + ' '
    if cur.strip(): lines.append(cur.rstrip())
    head = []
    if song.title: head.append('; ' + song.title[:70])
    if getattr(song, 'composer', ''): head.append('; ' + song.composer[:70])
    text = '\n'.join(head + lines) + '\n'
    return text, shift


def name83(title, src):
    base = re.sub(r'[^A-Z0-9]', '', (title or '').upper())[:8] or re.sub(r'[^A-Z0-9]', '', os.path.splitext(os.path.basename(src))[0].upper())[:8] or 'SONG'
    return base + '.MUS'


def read(path, tune=None, track=None, grid=16):
    b = open(path, 'rb').read()
    ext = os.path.splitext(path)[1].lower()
    stem = os.path.splitext(os.path.basename(path))[0]
    if b[:4] == b'MThd' or ext in ('.mid', '.midi', '.kar'): return read_midi(b, stem, track, grid)
    t = b.decode('latin1')
    if ext == '.abc' or re.search(r'^X:\s*\d', t, re.M) or re.search(r'^K:', t, re.M): return read_abc(t, tune)
    if ext == '.bas' or re.search(r'\bPLAY\s*"', t, re.I) or re.search(r'\bPLAY\s+[A-Za-z]\w*\$', t, re.I): return read_basic(t, stem)
    if re.match(r'\s*[^:\n]*:\s*[dob]\s*=', t, re.I) or ext in ('.rtttl', '.rtx', '.txt'): return read_rtttl(t)
    raise SystemExit('which format is %s? (.abc, .mid, .bas, or an RTTTL line)' % path)


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(description='Music from the internet made into PLAY .MUS files for LTOS.')
    ap.add_argument('file'); ap.add_argument('-o', '--out')
    ap.add_argument('--tune', type=int); ap.add_argument('--track', type=int)
    ap.add_argument('--transpose', type=int, default=0); ap.add_argument('--tempo', type=int)
    ap.add_argument('--grid', type=int, default=16); ap.add_argument('--title'); ap.add_argument('--list', action='store_true')
    a = ap.parse_args(argv)
    if a.list:
        list_midi(open(a.file, 'rb').read()); return
    song = read(a.file, a.tune, a.track, a.grid)
    if a.title: song.title = a.title
    text, shift = write_mus(song, a.transpose, a.tempo)
    out = a.out or os.path.join(os.path.dirname(os.path.abspath(a.file)), name83(song.title, a.file))
    open(out, 'w', newline='\n').write(text)
    notes = [e for e in song.ev if e[0] == 'n']
    lo, hi = min(e[1] for e in notes) + shift, max(e[1] for e in notes) + shift
    print('%s: %d notes, %s to %s%s, %d bytes' % (os.path.basename(out), len(notes), NAMES[lo % 12] + str(lo // 12 - 1),
          NAMES[hi % 12] + str(hi // 12 - 1), (', moved %+d semitones' % shift) if shift else '', len(text.encode())))
    if len(text.encode()) > MAXFILE: print('warning: over %d bytes - too big for PLAY to load' % MAXFILE)


if __name__ == '__main__':
    main(sys.argv[1:])
