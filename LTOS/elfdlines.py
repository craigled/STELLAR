# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
# elfdlines.py FILE - the Elf2K at the monitor: each D-line of FILE typed, re-typed if the monitor rejects it.
import os, sys
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'elfser.py')).read().replace('main()\n',''))
lines = [l.strip() for l in open(sys.argv[1]).read().split('\n') if l.strip()]
fd = open_port(); read_until_quiet(fd, 0.3, 1); bad = 0
for ln in lines:
    for attempt in range(4):
        got = b''
        for ch in (ln + '\r').encode():
            os.write(fd, bytes([ch])); got += echo1(fd); time.sleep(0.003)
        got += read_until_quiet(fd, 0.05, 2.0, until=b'>>>')
        if b'?' not in got: break
        print('rejected, again:', ln)
    else: bad += 1
os.close(fd); print(len(lines), 'D-lines,', bad, 'never accepted')
