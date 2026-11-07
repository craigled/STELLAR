# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""LTOS/elfser.py - drive the Elf2K over its USB serial port (install and test LTOS on the hardware).
Talk to the Elf2K over /dev/cu.usbserial-300005D8 at 19200 8N1 (no pyserial: termios).
   python3 elf.py send 'TEXT'      - send (\\r for Enter), print what comes back until quiet
   python3 elf.py hex FILE         - paste an Intel HEX file line by line, waiting for each echo
   python3 elf.py get NAME [FILE]  - SEND NAME on the Elf2K (LTOS): the file saved here (backups)
   python3 elf.py put FILE [NAME]  - XFER -R NAME on the Elf2K: FILE onto the card, any size (--yes: replace)
   python3 elf.py putstl LST [NAME] - a STELLAR app's .lst made into NAME.STL here (as RECV NAME.STL would),
                                     then put: for apps too big for RECV (over 15 KB, e.g. ORBIT's 31 blocks)
   python3 elf.py pull NAME [FILE] - XFER -S NAME on the Elf2K: the file from the card, any size
   python3 elf.py system [FILE]   - every LTOS program, in one go (SYSRX on the Elf2K, out/LTOS-ALL.PAK here)
   options: --wait S (quiet time to stop reading, default 1.0), --max S (longest to read)"""
import os, sys, termios, time, select, tty, binascii
DEV = '/dev/cu.usbserial-300005D8'
def open_port():
    fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = 0; a[1] = 0
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL       # 8N1, no modem control, no HUPCL
    a[3] = 0
    a[4] = a[5] = termios.B19200
    a[6][termios.VMIN] = 0; a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    return fd
def read_until_quiet(fd, quiet=1.0, most=30.0, until=None):
    out = b''; t0 = time.time(); last = time.time()
    while time.time() - t0 < most:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 4096)
            except BlockingIOError: d = b''
            if d: out += d; last = time.time()
            if until and until in out: break
        elif time.time() - last > quiet: break
    return out
def writeall(fd, data):
    while data:
        try: n = os.write(fd, data); data = data[n:]
        except BlockingIOError: time.sleep(0.01)
def echo1(fd):
    t0 = time.time()
    while time.time() - t0 < 0.3:
        r, _, _ = select.select([fd], [], [], 0.01)
        if r:
            d = os.read(fd, 64)
            if d: return d
    return b''
# ---- XFER (xfer.asm): frames of 516 bytes - the block number (2, low byte first), 512 bytes, the CRC-16 of
#      both (XMODEM's, high byte first) - each answered ACK, NAK (again) or CAN (stopped). Block 0: the size.
#      The protocols are generators: they yield ('send', bytes) or ('recv', n, quiet seconds) - n bytes, or what
#      came before that much quiet - and get the bytes back; verify_xfer.py runs them against the simulator.
ACK, NAK, CAN = b'\x06', b'\x15', b'\x18'
def xframe(n, data):
    body = bytes([n & 0xFF, n >> 8]) + data.ljust(512, b'\0')
    return body + binascii.crc_hqx(body, 0).to_bytes(2, 'big')
def xstart(say):
    for i in range(5):                                  # 'G' until XFER answers
        yield ('send', b'G')
        r = yield ('recv', 1, 2.0)
        if r: return r
    say('** no answer from XFER'); return b''
def xput(data, say=print):
    """Mac to card (XFER -R is waiting): -> True when the Elf2K has said the last block is on the card."""
    nb = (len(data) + 511) // 512
    if nb > 65534: say('** too big: 32 MB at most'); return False
    r = yield from xstart(say)
    if r != ACK: return False
    for blk in range(nb + 1):
        fr = xframe(blk, len(data).to_bytes(4, 'little') if blk == 0 else data[(blk - 1) * 512:blk * 512])
        for tries in range(12):
            yield ('send', fr)
            r = yield ('recv', 1, 45.0)                 # ACK: on the card; NAK, nothing (its ACK lost?): again
            # (45 s: under XFER's ~59 s wait for a block, over the ~30 s finding a free cluster can take on a nearly full card)
            if r in (ACK, CAN): break
        if r != ACK: say('** XFER stopped it' if r == CAN else '** no answer from the Elf2K'); return False
        if blk % 32 == 0 or blk == nb: say('  %d of %d bytes' % (min(blk * 512, len(data)), len(data)))
    return True
def xsys(data, say=print):
    """Mac to card (SYSRX is waiting): LTOS-ALL.PAK, block by block. A part's last block is ACKed once its files are
    on the card, so that wait is long. -> True when the last one is ACKed."""
    r = yield from xstart(say)
    if r != ACK: return False
    nb = len(data) // 512
    ends, at = set(), 0
    for c in data[5:5 + data[4]]: at += c; ends.add(at)
    for blk in range(nb):
        fr = xframe(blk, data[blk * 512:blk * 512 + 512])
        for tries in range(8):
            yield ('send', fr)
            r = yield ('recv', 1, 240.0 if blk in ends else 45.0)
            if r in (ACK, CAN): break
        if r != ACK: say('** SYSRX stopped it' if r == CAN else '** no answer from the Elf2K'); return False
        if blk in ends: say('  %d of %d parts on the card, %d s' % (sorted(ends).index(blk) + 1, len(ends), time.time() - xsys.t0))
    return True
def xpull(say=print):
    """Card to Mac (XFER -S is waiting): -> the file's bytes, or None."""
    yield ('send', b'G')
    want, size, out, quiet = 0, None, bytearray(), 0
    while True:
        fr = yield ('recv', 516, 3.0)
        if len(fr) == 516 and binascii.crc_hqx(fr, 0) == 0:
            quiet = 0; n = fr[0] | (fr[1] << 8)
            if n == want:                               # the next: kept
                if n == 0: size = int.from_bytes(fr[2:6], 'little')
                else: out += fr[2:514]
                want += 1
                yield ('send', ACK)
                if want > (size + 511) // 512: return bytes(out[:size])
                if n % 32 == 0: say('  %d of %d bytes' % (min(n * 512, size), size))
            else: yield ('send', ACK if n == want - 1 else NAK)    # the last one again: its ACK was lost
            continue
        if fr[:1] == CAN: say('** XFER stopped it'); return None
        if not fr:                                      # nothing: XFER sends it again after ~3 s
            quiet += 1
            if quiet > 12: say('** nothing from the Elf2K'); return None
            if want == 0 and quiet % 2 == 0: yield ('send', b'G')
            continue
        yield ('recv', 4096, 0.3)                       # damaged or cut short: the rest of it, then NAK
        yield ('send', NAK)
def xrun(fd, gen):
    """Run an XFER protocol on the serial port -> its result."""
    req = next(gen)
    while True:
        val = None
        if req[0] == 'send': writeall(fd, req[1])
        else:
            n, q = req[1], req[2]; val = b''; last = time.time()
            while len(val) < n and time.time() - last < q:
                r, _, _ = select.select([fd], [], [], 0.02)
                if r:
                    try: d = os.read(fd, n - len(val))
                    except BlockingIOError: d = b''
                    if d: val += d; last = time.time()
        try: req = gen.send(val)
        except StopIteration as e: return e.value
def xcommand(fd, cmd, yes=False):
    """Type an XFER command; answer 'replace it?' (asking here, or Y with --yes) -> True once it is waiting."""
    got = b''
    for ch in (cmd + '\r').encode():
        os.write(fd, bytes([ch])); got += echo1(fd)
    while True:
        got += read_until_quiet(fd, 5.0, 30.0, until=b'Ctrl-C stops.')
        if b'Ctrl-C stops.' in got:
            read_until_quiet(fd, 0.1, 1.0); return True
        if got.endswith(b'(Y/N) '):
            show(got); got = b''
            a = 'Y' if yes else input().strip()[:1].upper() or 'N'
            if yes: print('Y')
            os.write(fd, a.encode()); got += echo1(fd)
            if a != 'Y': show(got + read_until_quiet(fd, 1.0, 5.0)); return False
            continue
        show(got); return False
def show(b): sys.stdout.write(b.decode('latin1').replace('\r\n', '\n').replace('\r', '\n')); sys.stdout.flush()
def stl_of(lst):
    """What RECV NAME.STL makes of a STELLAR .lst (build.py's stl_of): only its 'D aaaa bb ...' lines; sector 0 =
    'STL1', the block count, each 512-byte block's address (in the order its first byte appears); then the blocks."""
    import re
    order, blocks = [], {}
    for line in lst.replace('\r', '\n').split('\n'):
        m = re.match(r'D +([0-9A-F]{4})((?: +[0-9A-F]{2})+) *$', line)
        if not m: continue
        a = int(m.group(1), 16)
        for k, x in enumerate(m.group(2).split()):
            blk = (a + k) >> 9
            if blk not in blocks: blocks[blk] = bytearray(512); order.append(blk)
            blocks[blk][(a + k) & 511] = int(x, 16)
    head = b'STL1' + bytes([len(order)]) + b''.join(bytes([(b << 9) >> 8, 0]) for b in order)
    return head.ljust(512, b'\0') + b''.join(bytes(blocks[b]) for b in order)
def main():
    args = sys.argv[1:]; quiet = 1.0; most = 30.0
    if '--wait' in args: i = args.index('--wait'); quiet = float(args[i + 1]); del args[i:i + 2]
    if '--max' in args: i = args.index('--max'); most = float(args[i + 1]); del args[i:i + 2]
    fd = open_port()
    if args[0] == 'listen':                            # just read: until quiet for --wait seconds
        show(read_until_quiet(fd, quiet, most)); os.close(fd); return
    read_until_quiet(fd, 0.2, 1.0)                     # whatever was waiting
    if args[0] == 'send':
        data = args[1].encode().decode('unicode_escape').encode('latin1')
        for ch in data:                                # a character at a time: the 1802 reads them one by one
            os.write(fd, bytes([ch])); time.sleep(0.002)
        show(read_until_quiet(fd, quiet, most))
    elif args[0] == 'system':                          # system [FILE]: every program, at LTOS's prompt (RECV SYSTEM's job)
        data = open(args[1] if len(args) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out', 'LTOS-ALL.PAK'), 'rb').read()
        def cmd(c, most=30.0):
            for ch in (c + '\r').encode():
                os.write(fd, bytes([ch])); echo1(fd)
            return read_until_quiet(fd, 6.0, most, until=b'LTOS> ')
        os.write(fd, b'\r'); read_until_quiet(fd, 2.0, 6.0)
        cmd('MKDIR /BIN')                              # (a fresh card has none; there already: it only says so)
        xsys.t0 = time.time()
        if not xcommand(fd, 'SYSRX'): os.close(fd); return
        okd = xrun(fd, xsys(data))
        show(read_until_quiet(fd, 6.0, 20.0, until=b'LTOS> '))
        if okd:
            for n in ('RECV', 'MON', 'MKDIR', 'SYSRX'): cmd('RM /%s.PRG' % n)   # (a fresh card's first copies: /BIN has them now)
        print('\ndone in %d s' % (time.time() - xsys.t0) if okd else '\n** it did not finish')
    elif args[0] == 'recv':                            # recv 'RECV NAME' FILE [line-delay-ms]: the file at full speed
        got = b''
        for ch in (args[1] + '\r').encode():          # the command at typing pace (the BIOS echoes it)
            os.write(fd, bytes([ch])); got += echo1(fd)
        got += read_until_quiet(fd, 8.0, 40.0, until=b'Ctrl-C stops.')
        if b'Ctrl-C stops.' not in got:
            show(got); print('\n** RECV did not start - nothing sent'); os.close(fd); return
        got += read_until_quiet(fd, 0.2, 2.0)          # its CR LF, and RECV reading: the UART holds ONE character,
                                                       #  so a ':' sent at once can be lost - then RECV takes text
        data = open(args[2], 'rb').read(); dl = float(args[3]) / 1000 if len(args) > 3 else 0
        if dl:
            for ln in data.split(b'\n'):
                writeall(fd, ln + b'\n'); time.sleep(dl)
        else:                                          # the first line slowly (on the Elf2K a digit of the first
            first, _, rest = data.partition(b'\n')     #  record was once lost: RECV now refuses such a file),
            for ch in first + b'\n':                   #  then the rest at full speed
                os.write(fd, bytes([ch])); time.sleep(0.002)
            writeall(fd, rest)
        termios.tcdrain(fd)                            # (RECV ends ~2.5 s after the last byte, then saves -
        show(got + read_until_quiet(fd, max(quiet, 5.0), max(most, 60.0),     #  or asks "replace it?")
                                    until=b'(Y/N) '))
    elif args[0] == 'get':                             # get NAME [file]: SEND NAME on the Elf2K, its Intel HEX here
        name = args[1]; dest = args[2] if len(args) > 2 else os.path.basename(name.replace('/', os.sep))
        got = b''
        for ch in ('SEND ' + name + '\r').encode():
            os.write(fd, bytes([ch])); got += echo1(fd)
        got += read_until_quiet(fd, 5.0, max(most, 900.0), until=b':00000001FF')
        got += read_until_quiet(fd, 0.5, 3.0)
        if b':00000001FF' not in got:
            show(got[-400:]); print('\n** no end record - nothing saved'); os.close(fd); return
        data, base, bad = {}, 0, 0
        for ln in got.decode('latin1').split('\n'):
            ln = ln.strip()
            if not ln.startswith(':'): continue
            r = bytes.fromhex(ln[1:])
            if sum(r) & 0xFF: bad += 1; continue
            n, a, ty = r[0], (r[1] << 8) | r[2], r[3]
            if ty == 0:
                for i, x in enumerate(r[4:4 + n]): data[base + a + i] = x
            elif ty == 4: base = ((r[4] << 8) | r[5]) << 16
        if bad: print('** %d records with bad checksums - nothing saved' % bad); os.close(fd); return
        out = bytes(data.get(i, 0) for i in range(max(data) + 1)) if data else b''
        open(dest, 'wb').write(out)
        print('%s: %d bytes -> %s' % (name, len(out), dest))
    elif args[0] in ('put', 'putstl'):                 # put FILE [NAME]: XFER -R NAME, FILE sent block by block
        src = args[1]; name = args[2] if len(args) > 2 else os.path.basename(src).upper()
        data = open(src, 'rb').read(); t0 = time.time()
        if args[0] == 'putstl':                        # (putstl: the .lst made into the .STL first)
            data = stl_of(data.decode('latin1'))
            if len(args) <= 2: name = os.path.splitext(name)[0] + '.STL'
            if data[4] == 0: print('** no D-lines in %s - nothing sent' % src); os.close(fd); return
            print('%s: %d blocks, %d bytes' % (name, data[4], len(data)))
        if not xcommand(fd, 'XFER -R ' + name, yes='--yes' in sys.argv): os.close(fd); return
        try: ok = xrun(fd, xput(data))
        except KeyboardInterrupt:                      # stop: block $FFFF
            writeall(fd, xframe(0xFFFF, b'')); ok = False
        show(read_until_quiet(fd, 1.0, 10.0))
        if ok: print('%s -> %s: %d bytes in %.0f s' % (src, name, len(data), time.time() - t0))
    elif args[0] == 'pull':                            # pull NAME [FILE]: XFER -S NAME, saved here
        name = args[1]; dest = args[2] if len(args) > 2 else os.path.basename(name.replace('/', os.sep))
        t0 = time.time()
        if not xcommand(fd, 'XFER -S ' + name): os.close(fd); return
        try: data = xrun(fd, xpull())
        except KeyboardInterrupt:
            writeall(fd, CAN); data = None
        show(read_until_quiet(fd, 1.0, 10.0))
        if data is not None:
            open(dest, 'wb').write(data)
            print('%s -> %s: %d bytes in %.0f s' % (name, dest, len(data), time.time() - t0))
    elif args[0] == 'hex':
        lines = open(args[1]).read().split('\n'); n = 0; got = b''
        for ln in lines:
            ln = ln.strip()
            if not ln: continue
            for ch in (ln + '\r').encode():          # one character, then wait for its echo
                os.write(fd, bytes([ch]))
                got += read_until_quiet(fd, 0.2, 0.5, until=b'') if False else echo1(fd)
            got += read_until_quiet(fd, 0.05, 2.0, until=b'>>>')
            n += 1
            if b'?' in got[-200:] and n < 3: print('rejected:', got[-200:]); break
            if n % 100 == 0: print('  %d lines sent' % n, flush=True)
        got += read_until_quiet(fd, 1.0, 5.0)
        print('%d lines sent; the last thing the Elf2K said:' % n); show(got[-600:])
    os.close(fd)
if __name__ == '__main__':
    main()
