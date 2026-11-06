# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
# elfcmpram.py FILE - the Elf2K at the monitor: E 0000 2EFF, compared byte for byte with FILE (a firmware image).
import os
import os, re, sys
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'elfser.py')).read().replace('main()\n',''))
want = open(sys.argv[1], 'rb').read()
fd = open_port(); read_until_quiet(fd, 0.3, 1); got = b''
for ch in b'E 0000 2EFF\r':
    os.write(fd, bytes([ch])); got += echo1(fd)
got += read_until_quiet(fd, 3, 180); os.close(fd)
mem = {}
for m in re.finditer(rb'^([0-9A-F]{4})>  ((?:[0-9A-F]{2} ){15}[0-9A-F]{2})', got, re.M):
    a = int(m.group(1), 16)
    for k, x in enumerate(m.group(2).split()): mem[a + k] = int(x, 16)
bad = [i for i in range(len(want)) if mem.get(i) != want[i]]
print('RAM $0000-$2EFF vs %s: %d bytes read, %d differ %s' % (sys.argv[1], len(mem), len(bad), [hex(x) for x in bad[:5]]))
