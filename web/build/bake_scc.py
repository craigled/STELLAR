"""Bake the Stellar C compiler into the website (web/sc/), for stellarc.html.

The page runs the REAL compiler - these same .py files - in the browser under
Pyodide, so there is one compiler, not a copy to keep in step. This copies it from
the work repo, with the example programs, writes web/sc/manifest.json, and checks
that the copied files compile every example byte-identical to the work repo's .lst.

    python3 web/build/bake_scc.py [path/to/stellar-1802]

Run it whenever the compiler changes; then bump ?v= on every page, as for any asset.
"""
import filecmp, json, os, shutil, subprocess, sys

WEB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Projects/stellar-1802')
OUT = os.path.join(WEB, 'sc')

# The compiler and everything it imports. Flat in web/sc/: scc.py's sys.path lines
# point at ../Firmware-Math and ../tools, which do not exist there, and are harmless.
SOURCES = ['SC/scc.py', 'SC/asm1802.py', 'Firmware-Math/mini.py',
           'Firmware-Math/stellar_ops.py', 'tools/stellar_disasm.py']

# The examples, in menu order. input: keys pre-loaded before the program starts.
EXAMPLES = [
    ('primes', 'Prime generator', '3\r60\r', 'Elf2K',
     'Asks for a low and a high limit and prints the primes between them - the same program as '
     'the hand-written Prime-Gen v07, and 35% smaller. The input box answers 3 and 60; '
     'empty it to type your own limits in the terminal.'),
    ('sieve', 'Sieve of Eratosthenes', '', 'flat out',
     'Every prime below 2000, ten to a line, then a count. Byte arrays, arguments, && and ||, '
     'nested calls.'),
    ('snake', 'Snake', '', 'Elf2K',
     'The full arrow-key game: steer to the food, grow, avoid the walls and yourself. Click the '
     'terminal, press Space to start and steer with the arrow keys; P pauses, Esc quits. '
     'Within a few percent of the hand-written version.'),
    ('asmdemo', 'Inline STELLAR: asm { }', 'abc', 'flat out',
     'Hand-written STELLAR opcodes inside a C function: MULTXY on register variables, an array '
     'address, @break out of a loop, a hand-made CALL, and a SERST poll loop that counts the keys '
     'waiting (the three pre-loaded in the input box).'),
    ('nativedemo', 'Native 1802: native { }', '', 'flat out',
     'Raw 1802 machine code run by $F1 RUNMC: sums a 200-byte array (71x faster than the compiled '
     'loop), formats the total as hex, and copies a string kept inside the native block.'),
]


def main():
    os.makedirs(os.path.join(OUT, 'examples'), exist_ok=True)
    for rel in SOURCES:
        shutil.copy(os.path.join(WORK, rel), os.path.join(OUT, os.path.basename(rel)))
    manifest = []
    for name, title, inp, speed, blurb in EXAMPLES:
        shutil.copy(os.path.join(WORK, 'SC', 'examples', name + '.sc'), os.path.join(OUT, 'examples'))
        manifest.append({'name': title, 'file': name + '.sc', 'input': inp, 'speed': speed, 'blurb': blurb})
    json.dump({'files': [os.path.basename(r) for r in SOURCES], 'examples': manifest},
              open(os.path.join(OUT, 'manifest.json'), 'w'), indent=1)

    # the baked copy must compile each example exactly as the work repo does
    check = ('import sys; sys.path.insert(0, %r); import scc, json\n'
             'out = {}\n'
             'for n in %r:\n'
             '    r = scc.compile_text(open(%r + "/examples/" + n + ".sc").read(), n)\n'
             '    out[n] = r.get("lst") or r.get("error")\n'
             'print(json.dumps(out))') % (OUT, [e[0] for e in EXAMPLES], OUT)
    got = json.loads(subprocess.run([sys.executable, '-c', check], capture_output=True, text=True,
                                    cwd='/', check=True).stdout)
    bad = [n for n in got if got[n] != open(os.path.join(WORK, 'SC', 'examples', n + '.lst')).read()]
    print('baked %d compiler files + %d examples into web/sc/; byte-identical to the work repo: %s'
          % (len(SOURCES), len(EXAMPLES), 'ALL' if not bad else 'NO - ' + ', '.join(bad)))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
