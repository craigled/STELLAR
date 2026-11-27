# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check every example in SC/GUIDE.md: each ```c block marked example=NAME is compiled and run in the
simulator (V0061.37 as flashed - the docx, the DS12887 model set to 2026-10-04 14:23:07 in the
Elf2K BIOS's mode, a strict VT100 screen), and what follows it must match:

    ```output        the serial output, exactly (CR LF shown as line ends)
    ```screen        the screen's rows from row 1, each trailing space dropped (VT100 programs)
    ```error         a compile error, which must contain this text  (block marked error=NAME)

Info-string options:  input="..."  (keys typed, with \\r \\e \\x1b escapes)   gap=N (type them N 1802
instructions apart, not all at once)   steps=N   noexit (a
program that waits for ever: run N steps and compare what is there).

    python3 guide_check.py [--show NAME|all] [--write DIR]   (--write: the examples as .sc files)
"""
import sys, os, re, shlex, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import scc
import opcode_sweep as S
import rtc_verify as V
import litewriter2_verify as LW

LW.TROWS = 26
class VT(LW.VT100):
    def esc(s, e):
        if e in ('\x1b[?25l', '\x1b[?25h'): return
        super().esc(e)

GUIDE = os.path.join(HERE, 'GUIDE.md')
BIOS = {0x00: 7, 0x02: 23, 0x04: 14, 0x06: 7, 0x07: 4, 0x08: 10, 0x09: 54,
        0x0A: 0x20, 0x0B: 0x07, 0x0C: 0x10, 0x0D: 0x80}


def unescape(s):
    return s.encode('latin1').decode('unicode_escape').encode('latin1')   # \r \e \x1b ...


def blocks(text):
    """[(info, body, line)] for every fenced block."""
    out, lines, i = [], text.split('\n'), 0
    while i < len(lines):
        m = re.match(r'^```(.*)$', lines[i])
        if m:
            info, start, body = m.group(1).strip(), i + 1, []
            i += 1
            while not lines[i].startswith('```'): body.append(lines[i]); i += 1
            out.append((info, '\n'.join(body), start))
        i += 1
    return out


def examples(text=None):
    """[(name, kind, opts, source, check-kind, check-body, line)]"""
    bl = blocks(text or open(GUIDE).read())
    out = []
    for k, (info, body, line) in enumerate(bl):
        parts = shlex.split(info) if info else []
        if not parts or parts[0] != 'c': continue
        opts = dict(p.split('=', 1) for p in parts[1:] if '=' in p)
        flags = {p for p in parts[1:] if '=' not in p}
        name = opts.get('example') or opts.get('error')
        if not name: continue
        nxt = bl[k + 1] if k + 1 < len(bl) else ('', '', 0)
        chk = nxt[0] if nxt[0] in ('output', 'screen', 'error') else None
        out.append((name, 'error' if 'error' in opts else 'example', dict(opts, flags=flags), body, chk,
                    nxt[1] if chk else None, line))
    return out


def run(src, name, keys=b'', steps=20_000_000, gap=0):
    prog = scc.compile_program(src, name)
    if prog.single:
        p = prog.parts[0]
        pokes = [(a + i, b) for a, bs, _, _ in p.em for i, b in enumerate(bs)] + \
                [(0x4000 + a + i, b) for a, d in p.data.items() for i, b in enumerate(d)]
    else: pokes = prog.pokes(name + '.sc')        # several VMs: every D-line of the one .lst
    img = bytearray(S.image('37'))
    c = S.boot(bytes(img), pokes, keys=b'')
    rtc = V.DS12887(c)
    for n, v in BIOS.items(): rtc.r[n] = v
    c.io_in[3] = V.Port3In(c.io_in[3], c.io_out[2], rtc)
    c.io_out[3] = V.Port3Out(c.io_out[2], rtc)
    if gap:                                    # typed one at a time, gap 1802 instructions apart
        for k in keys: V.run(c, gap); c.io_in[3].u.q.append(k)
    else: c.io_in[3].u.q.extend(keys)
    r = V.run(c, steps)
    text = bytes(c.io_out[3]).decode('latin1')
    vt = VT(); vt.feed(text)
    return text, vt, r, c


def main():
    show = sys.argv[sys.argv.index('--show') + 1] if '--show' in sys.argv else None
    write = sys.argv[sys.argv.index('--write') + 1] if '--write' in sys.argv else None
    exs = examples()
    names = [e[0] for e in exs]
    dup = {n for n in names if names.count(n) > 1}
    if dup: raise SystemExit('duplicate example names: %s' % dup)
    ok, manifest = True, {}
    for name, kind, opts, src, chk, want, line in exs:
        if kind == 'error':
            try: scc.compile_program(src, name); got = '(it compiled)'
            except scc.Error as e: got = str(e)
            good = want is not None and want.strip() in got
            if show in (name, 'all'): print('--- %s (error)\n%s' % (name, got))
            print('%-24s %-8s %s' % (name, 'error', 'OK' if good else 'FAIL: %r' % got))
            ok &= good; continue
        keys = unescape(opts.get('input', ''))
        steps = int(opts.get('steps', 20_000_000))
        try: text, vt, r, c = run(src, name, keys, steps, int(opts.get('gap', 0)))
        except scc.Error as e:
            print('%-24s %-8s FAIL: does not compile: %s' % (name, chk or '-', e)); ok = False; continue
        err = next((e for e in (c.M[0x3000 + v * 0x400 + 0x4F] for v in range(4)) if e), 0)   # any VM's
        ended = r == 'halt' or 'noexit' in opts['flags']
        if chk == 'output':
            got = text.replace('\r\n', '\n'); good = got.rstrip('\n') == want.rstrip('\n')
        elif chk == 'screen':
            rows = [vt.row(i) for i in range(24)]
            wl = want.split('\n')
            got = '\n'.join(rows[:len(wl)]); good = got == '\n'.join(l.rstrip() for l in wl) and not vt.bad
        else: got, good = text, True
        good = good and ended and not err
        if show in (name, 'all'):
            print('--- %s  (%s, %s)' % (name, r, 'error $%02X' % err if err else 'no error'))
            print(text.replace('\r\n', '\n') if chk != 'screen' else '\n'.join(vt.row(i) for i in range(24)).rstrip('\n'))
        print('%-24s %-8s %s' % (name, chk or 'runs', 'OK' if good else 'FAIL%s%s' % (
            '' if ended else ' (did not finish)', ' (VM error $%02X)' % err if err else '')))
        if not good and chk and show is None:
            for a, b in zip(got.split('\n'), want.split('\n')):
                if a.rstrip() != b.rstrip(): print('     got  %r\n     want %r' % (a, b)); break
        ok &= good
        manifest[name] = {'input': opts.get('input', ''), 'line': line}
        if write:
            os.makedirs(write, exist_ok=True)
            open(os.path.join(write, name + '.sc'), 'w').write(src + '\n')
    if write: json.dump(manifest, open(os.path.join(write, 'manifest.json'), 'w'), indent=1)
    print('%d examples: %s' % (len(exs), 'ALL OK' if ok else 'FAILURES'))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
