#!/usr/bin/env python3
"""
Generate web/build/fixtures.json — golden serial output for each sample program,
produced by the REAL firmware simulator in Firmware-Math, over the SAME image the
browser gets (extract_firmware.build_image = V0061.24 as flashed). The Node parity
test (test_parity.mjs) asserts the JS engine reproduces these byte-for-byte.

    python3 web/build/gen_fixtures.py
"""
import os, sys, json

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.abspath(os.path.join(HERE, '..', 'samples'))
FMATH = os.path.expanduser('~/Projects/stellar-1802/Firmware-Math')
sys.path.insert(0, FMATH)
os.chdir(FMATH)

sys.path.insert(0, HERE)                        # extract_firmware lives beside this file
from extract_firmware import build_image        # noqa: E402  (single source of truth)
from cpu1802 import CPU                          # noqa: E402
from calc_interactive import UART               # noqa: E402

CORE = 0x3000

def run(lst_path, inp, max_steps):
    mem = bytearray(build_image())      # V0061.24 exactly as flashed
    for ln in open(lst_path):
        import re
        m = re.match(r'D\s+([0-9A-Fa-f]{4})\s+(.+)', ln.strip())
        if not m or ln.strip().startswith(';'):
            continue
        a = int(m.group(1), 16)
        for tok in m.group(2).split():
            if re.fullmatch(r'[0-9A-Fa-f]{2}', tok):
                mem[a] = int(tok, 16); a += 1
            else:
                break
    c = CPU(mem)
    mem[CORE + 0x3B] = 1; mem[CORE + 0x5B] = 0x40; mem[CORE + 0x5C] = 0
    c.io_out[2] = []; c.io_in[3] = UART(inp, c.io_out)
    c.R[4] = 0x0340; c.R[5] = 0x0360; c.R[2] = 0x2FF0; c.R[6] = 0
    c.R[12] = 0x3000; c.R[8] = 0x4000; c.R[3] = 0x0100; c.P = 3; c.X = 2
    halted = False
    n = 0
    for n in range(max_steps):
        if not c.step():
            halted = True; break
    return bytes(c.io_out.get(3, [])), halted, n

def main():
    manifest = json.load(open(os.path.join(SAMPLES, 'manifest.json')))
    out = {}
    for s in manifest:
        path = os.path.join(SAMPLES, s['file'])
        data, halted, n = run(path, s['input'], s['maxSteps'])
        out[s['file']] = {'input': s['input'], 'outHex': data.hex(),
                          'halted': halted, 'steps': n, 'bytes': len(data)}
        flag = 'halt' if halted else 'CAP!'
        print(f"{s['file']:22} {flag} steps={n:>10,} bytes={len(data):5}")
    dst = os.path.join(HERE, 'fixtures.json')
    json.dump(out, open(dst, 'w'), indent=1)
    print('Wrote', dst)

if __name__ == '__main__':
    main()
