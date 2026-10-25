#!/usr/bin/env python3
"""
Generate web/build/fixtures.json — golden serial output for each sample program,
produced by the REAL firmware simulator in Firmware-Math, over the SAME image the
browser gets (extract_firmware.build_image = V0061.36 as flashed). The Node parity
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
    mem = bytearray(build_image())      # V0061.36 exactly as flashed
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
    # COLD BOOT from the reset vector, exactly as the pages run it (StellarVM
    # coldBoot) and as the Elf2K does. The fixtures used to be taken on a
    # hand-built register state (R3=$0100 ...), which only ever worked because the
    # firmware then did SEP R1 with R1=0 and cold-booted anyway - with R1 as the
    # program counter - and its exit landed on $0033, the low byte of CALL $0C00,
    # which happened to be $00. V0061.27 moved CREATE_CIDP and that exit printed a
    # stray byte. R1 = $FFF0 is an address that is always $00 (IDL).
    c.R[0] = 0x0000; c.P = 0; c.X = 0; c.R[1] = 0xFFF0
    # Run the firmware's start-up until a VM is active, then count the step
    # budget - exactly what StellarVM's cold boot does (_bootUntilReady in the
    # constructor, then runToSerial(maxSteps)), so capped samples stop at the
    # same instruction in both engines.
    for _ in range(800000):
        if not c.step(): break
        if mem[0x2F54] >= 1 and any(mem[0x2F00 + v * 0x10 + 5] == 1 for v in range(4)):
            break
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
        if s.get('fixture') is False: continue      # output depends on the time of day (Big Clock)
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
