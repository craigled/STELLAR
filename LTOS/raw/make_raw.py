#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/raw/make_raw.py - the raw 1802 example programs: each NAME.asm here assembled (a18) into NAME.BIN - its bytes
from $0000, no header - for LTOS's 1802 command (1802 NAME). Also NAME.lst.

    python3 LTOS/raw/make_raw.py
"""
import glob, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import build


def make(src):
    name = os.path.splitext(os.path.basename(src))[0].upper()
    lst, hexf = os.path.join(HERE, name + '.lst'), os.path.join(HERE, name + '.hex')
    r = subprocess.run([build.A18, src, '-l', lst, '-o', hexf], capture_output=True, text=True, cwd=HERE)
    if r.returncode or 'Error' in r.stdout and '0 Errors' not in r.stdout and 'No Errors' not in r.stdout:
        print(r.stdout); raise SystemExit('%s: a18 reported errors' % src)
    mem = {}
    for ln in open(hexf):
        ln = ln.strip()
        if ln.startswith(':') and ln[7:9] == '00':
            n, a = int(ln[1:3], 16), int(ln[3:7], 16)
            for i in range(n): mem[a + i] = int(ln[9 + 2 * i:11 + 2 * i], 16)
    os.remove(hexf)
    data = bytes(mem.get(a, 0) for a in range(max(mem) + 1))
    open(os.path.join(HERE, name + '.BIN'), 'wb').write(data)
    print('%-8s %4d bytes' % (name + '.BIN', len(data)))
    return name, data


if __name__ == '__main__':
    for s in sorted(glob.glob(os.path.join(HERE, '*.asm'))): make(s)
