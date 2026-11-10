# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""tomus.py: ABC, RTTTL, MIDI and BASIC made into .MUS - what each reader makes is checked against the notes worked
out by hand (pitches, lengths, repeats, endings, ties, triplets, broken rhythm, key and bar accidentals, chords, the
skyline of a MIDI file, BASIC's octave), then each .MUS is played by PLAY.PRG in the cycle-counting 1802
(verify_play.Run): every note's pitch and every start, against the same list.

    python3 LTOS/verify_tomus.py [-v]
"""
import math, os, struct, sys, tempfile
from fractions import Fraction as F
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build, tomus, verify_play as VP

ABC = r'''%abc
X:1
T:A Test Jig
C:trad.
M:6/8
L:1/8
Q:3/8=100
K:G
|:GAB c2d|e>dB {g}A3|1 (3BcB A2 z:|2 [GBd]2- d f=f^f||
w: some words here that are not notes
'''
# G major (F#), 6/8, quarter = 150 a minute; lengths in quarters
A1 = [(67, F(1, 2)), (69, F(1, 2)), (71, F(1, 2)), (72, 1), (74, F(1, 2)),
      (76, F(3, 4)), (74, F(1, 4)), (71, F(1, 2)), (69, F(3, 2))]
ABC_WANT = A1 + [(71, F(1, 3)), (72, F(1, 3)), (71, F(1, 3)), (69, 1), (None, F(1, 2))] + A1 + \
    [(74, F(3, 2)), (78, F(1, 2)), (77, F(1, 2)), (78, F(1, 2))]

RTTTL = 'Test Tone:d=4,o=5,b=100:8e6,8p,c#,2a4.,16b'
RTTTL_WANT = [(88, F(1, 2)), (None, F(1, 2)), (73, 1), (69, 3), (83, F(1, 4))]

FAST = 'Fast:d=8,o=5,b=400:c,d,e,f,4g'                # T400: written as T200, lengths doubled
FAST_WANT = [(72, F(1, 2)), (74, F(1, 2)), (76, F(1, 2)), (77, F(1, 2)), (79, 1)]

BASIC = '''10 REM a tune
20 PLAY "T120 O3 L4 C D E8E8"
30 A$ = "P4 O4 G2"
40 PLAY A$ : PRINT "done"
50 PLAY "MB N37 MS >C"
'''
# GW-BASIC's O3 = middle C (60); O4 G = 79; N37 = middle C; MS: staccato; >C after O4: O5 C = 84
BASIC_WANT = [(60, 1), (62, 1), (64, F(1, 2)), (64, F(1, 2)), (None, 1), (79, 2), (60, 1), (84, 1)]


def midi_file():
    """Type 1, 480 a quarter: a tempo track (120, then 100 at beat 4), a melody with a chord on beat 3 and a held
    note crossed by a higher one, a bass part, and drums (left out)."""
    def vl(n):
        out = [n & 0x7F]; n >>= 7
        while n: out.insert(0, (n & 0x7F) | 0x80); n >>= 7
        return bytes(out)
    def track(evs):
        b, t = b'', 0
        for tick, data in sorted(evs, key=lambda e: e[0]):
            b += vl(tick - t) + data; t = tick
        b += vl(0) + b'\xFF\x2F\x00'
        return b'MTrk' + struct.pack('>I', len(b)) + b
    Q = 480
    t0 = [(0, b'\xFF\x03\x09Midi Test'), (0, b'\xFF\x51\x03' + (500000).to_bytes(3, 'big')),
          (4 * Q, b'\xFF\x51\x03' + (600000).to_bytes(3, 'big'))]
    def n(ch, s, e, p): return [(s, bytes([0x90 | ch, p, 90])), (e, bytes([0x80 | ch, p, 0]))]
    mel = n(0, 0, Q, 60) + n(0, Q, 2 * Q, 64) + n(0, 2 * Q, 3 * Q, 67) + n(0, 2 * Q, 3 * Q, 72) + \
        n(0, 4 * Q, 6 * Q, 69) + n(0, 5 * Q, 6 * Q, 74) + n(0, 6 * Q + 3, 7 * Q - 2, 71)      # (nearly on the grid)
    bass = n(1, 0, 4 * Q, 36) + n(1, 4 * Q, 8 * Q, 43)
    drums = n(9, 0, Q // 2, 38) + n(9, Q, Q + Q // 2, 38)
    return b'MThd' + struct.pack('>IHHH', 6, 1, 4, Q) + track(t0) + track(mel) + track(bass) + track(drums)
# the melody track: C4 E4, then the chord's top (C5), a rest, A4 cut by D5 halfway, then B4; tempo 120, 100 from beat 4
MIDI_WANT = [(60, 1), (64, 1), (72, 1), (None, 1), (69, 1), (74, 1), (71, 1)]
MIDI_SECS = [0.5, 0.5, 0.5, 0.5, 0.6, 0.6, 0.6]


def events(song):
    return [(e[1], e[2]) if e[0] == 'n' else (None, e[1]) for e in song.ev if e[0] in ('n', 'r')]


def main():
    v = '-v' in sys.argv
    import play_gen; play_gen.main()
    prg = build.prg('play')
    ok = True
    def report(label, e):
        nonlocal ok
        print('%s: %s' % (label, 'OK' if not e else 'FAIL')); [print('    ' + x) for x in e[:12]]; ok &= not e

    def played(song, want, secs, label, e):
        """The .MUS through PLAY: each note's pitch, and each start at the time the list says."""
        text, shift = tomus.write_mus(song)
        if v: print(text)
        r = VP.Run(prg, 'T', {'T.MUS': text.encode()}, max_s=120)
        ns = r.notes()
        heard = [n for n in want if n[0] is not None]
        if r.end != 'returned' or len(ns) != len(heard):
            e.append('%s: %d notes heard, want %d (%s) %r' % (label, len(ns), len(heard), r.end, r.out[-80:])); return
        for (t, d, hz), (m, q) in zip(ns, heard):
            f = 440 * 2 ** ((m + shift - 69) / 12)
            if abs(1200 * math.log2(hz / f)) > 3: e.append('%s: %.1f Hz, want %.1f (MIDI %d)' % (label, hz, f, m))
        starts, t = [], 0.0
        for (m, q), s in zip(want, secs):
            if m is not None: starts.append(t)
            t += s
        got = [n[0] - ns[0][0] for n in ns]
        for k, (a, b) in enumerate(zip(got, starts)):
            if abs(a - b) > 0.006 + 0.002 * k:        # (PLAY's own time between notes varies ~1 ms)
                e.append('%s: note %d starts at %.3f s, want %.3f' % (label, k + 1, a, b)); break

    # ---- ABC
    e = []
    s = tomus.read_abc(ABC)
    if s.title != 'A Test Jig' or getattr(s, 'composer', '') != 'trad.': e.append('title %r composer %r' % (s.title, getattr(s, 'composer', '')))
    if events(s) != ABC_WANT: e.append('read: %r' % events(s))
    if [x[1] for x in s.ev if x[0] == 't'] != [150]: e.append('tempo: %r' % [x for x in s.ev if x[0] == 't'])
    played(s, ABC_WANT, [float(q) * 60 / 150 for m, q in ABC_WANT], 'ABC', e)
    two = ABC + 'X:2\nT:Second\nM:4/4\nL:1/4\nK:Bb\nB c d e|\n'
    s2 = tomus.read_abc(two, tune=2)
    if s2.title != 'Second' or events(s2) != [(70, 1), (72, 1), (74, 1), (75, 1)]: e.append('X:2 in B flat: %r' % events(s2))
    if [x[1] for x in s2.ev if x[0] == 't'] != [120]: e.append('X:2 tempo with no Q: %r' % s2.ev[:2])
    s3 = tomus.read_abc('X:1\nT:R\nM:4/4\nL:1/8\nK:D\n|:A2B2:|:c2d2:|\n')
    if [m for m, q in events(s3)] != [69, 71, 69, 71, 73, 74, 73, 74]: e.append('|: :|: :| %r' % events(s3))
    s4 = tomus.read_abc('X:1\nT:Dor\nM:4/4\nL:1/4\nK:Edor\nF C C, _B\n')
    if [m for m, q in events(s4)] != [66, 61, 49, 70]: e.append('E dorian (F# C#), C, lower octave, flat: %r' % events(s4))
    report('ABC: key, lengths, > , triplet, tie, chord top, accidentals in a bar, repeat and endings, words left out', e)

    # ---- RTTTL
    e = []
    s = tomus.read_rtttl(RTTTL)
    if s.title != 'Test Tone' or events(s) != RTTTL_WANT: e.append('read: %r %r' % (s.title, events(s)))
    played(s, RTTTL_WANT, [float(q) * 0.6 for m, q in RTTTL_WANT], 'RTTTL', e)
    s = tomus.read_rtttl(FAST)
    text, _ = tomus.write_mus(s)
    if 'T200' not in text: e.append('b=400: %r' % text)
    played(s, FAST_WANT, [float(q) * 60 / 400 for m, q in FAST_WANT], 'RTTTL b=400', e)
    report('RTTTL: lengths, dots, rest, sharps, octaves (A4 = 440); b=400 written as T200 with lengths doubled', e)

    # ---- MIDI
    e = []
    s = tomus.read_midi(midi_file(), 'x')
    if s.title != 'Midi Test' or events(s) != MIDI_WANT: e.append('read: %r %r' % (s.title, events(s)))
    if [x[1] for x in s.ev if x[0] == 't'] != [120, 100]: e.append('tempos: %r' % [x for x in s.ev if x[0] == 't'])
    played(s, MIDI_WANT, MIDI_SECS, 'MIDI', e)
    b2 = tomus.read_midi(midi_file(), 'x', track=3)
    if events(b2) != [(36, 4), (43, 4)]: e.append('--track 3 (the bass): %r' % events(b2))
    text, shift = tomus.write_mus(b2)
    if shift != 0 or 'O2' not in text: e.append('bass C2: %r shift %d' % (text, shift))
    low = tomus.Song('low'); low.tempo(120); low.note(12, 1); low.note(24, 1)
    text, shift = tomus.write_mus(low)
    if shift != 12: e.append('below C1: moved %d' % shift)
    report('MIDI: the melody track, chord top, a higher note cutting in, a rest, tempo change, the grid; --track; moved into range', e)

    # ---- BASIC
    e = []
    s = tomus.read_basic(BASIC, 'B')
    if events(s) != BASIC_WANT: e.append('read: %r' % events(s))
    if [x[1] for x in s.ev if x[0] == 'a'] != ['S']: e.append('MS: %r' % [x for x in s.ev if x[0] == 'a'])
    played(s, BASIC_WANT, [float(q) * 0.5 for m, q in BASIC_WANT], 'BASIC', e)
    report('BASIC: PLAY literals and A$, O3 = middle C, P, N, MB left out, MS', e)

    # ---- writing
    e = []
    long = tomus.Song('long'); long.tempo(120); long.note(60, F(5)); long.note(62, F(9, 4)); long.rest(F(5))
    text, _ = tomus.write_mus(long)
    if 'ML' not in text or 'R1' not in text: e.append('a 5-quarter note, a 5-quarter rest: %r' % text)
    played(long, [(60, 4), (60, 1), (62, 2), (62, F(1, 4)), (None, 5)], [2, 0.5, 1, 0.125, 2.5], 'long notes (each piece sounds)', e)
    if tomus.name83('Amazing Grace (v. 2)', 'x.abc') != 'AMAZINGG.MUS' or tomus.name83('', 'my-tune.mid') != 'MYTUNE.MUS':
        e.append('names: %s %s' % (tomus.name83('Amazing Grace (v. 2)', 'x.abc'), tomus.name83('', 'my-tune.mid')))
    with tempfile.TemporaryDirectory() as d:
        for nm, data in (('a.abc', ABC.encode()), ('r.txt', RTTTL.encode()), ('m.mid', midi_file()), ('p.bas', BASIC.encode())):
            p = os.path.join(d, nm); open(p, 'wb').write(data)
            out = os.path.join(d, nm + '.MUS')
            tomus.main([p, '-o', out])
            if not os.path.getsize(out): e.append('%s: nothing written' % nm)
    report('writing: notes longer than one length joined legato, long rests, 8.3 names, each format from a file', e)
    print('\nTOMUS: %s' % ('ALL PASS' if ok else 'FAIL'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
