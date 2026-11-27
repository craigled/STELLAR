#!/usr/bin/env python3
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""SC/mk_dotbot.py - examples/dotbot.sc made from examples/dotbot.sc.in with the maze of LTOS/dotbot_gen.py put in
(the same maze as the native DOTBOT, checked there), then compiled: examples/dotbot.lst.

    python3 SC/mk_dotbot.py
"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'LTOS'))
import dotbot_gen

m = dotbot_gen.maze()
probs = dotbot_gen.check(m)
if probs: raise SystemExit('the maze: ' + '; '.join(probs))
src = open(os.path.join(HERE, 'examples', 'dotbot.sc.in')).read().replace('@MAZE@', ''.join(m))
open(os.path.join(HERE, 'examples', 'dotbot.sc'), 'w').write(src)
r = subprocess.run([sys.executable, os.path.join(HERE, 'scc.py'), os.path.join(HERE, 'examples', 'dotbot.sc')],
                   capture_output=True, text=True)
print(r.stdout + r.stderr, end='')
sys.exit(r.returncode)
