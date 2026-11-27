# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""DOTBOTC.STL - DOTBOT in Stellar C (SC/examples/dotbot.sc.in): compiled again (SC/mk_dotbot.py), the .lst must be
the one in the project (the one put on the cards and the website), then SC/dotbot_sc_verify.py's checks on the
STELLAR firmware.

    python3 LTOS/verify_dotbotc.py
"""
import os, sys, subprocess, tempfile, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
SC = os.path.join(HERE, '..', 'SC')
sys.path.insert(0, SC)


def main():
    lst = os.path.join(SC, 'examples', 'dotbot.lst')
    before = open(lst, 'rb').read()
    r = subprocess.run([sys.executable, os.path.join(SC, 'mk_dotbot.py')], capture_output=True, text=True)
    ok = r.returncode == 0 and open(lst, 'rb').read() == before
    print('compiled again: %s' % ('the same .lst - OK' if ok else 'FAIL ' + (r.stdout + r.stderr)[-300:]))
    if not ok: open(lst, 'wb').write(before)
    import dotbot_sc_verify
    return dotbot_sc_verify.main() and ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
