# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Bake the Stellar C compiler into the website (web/sc/), for stellarc.html.

The page runs the REAL compiler - these same .py files - in the browser under
Pyodide, so there is one compiler, not a copy to keep in step. This copies it from
the work repo, with the example programs, writes web/sc/manifest.json, and checks
that the copied files compile every example byte-identical to the work repo's .lst.

    python3 web/build/bake_scc.py [path/to/stellar-1802]

It also builds web/downloads/stellar-c.zip - the compiler to run on your own computer: the same
five files, the examples, the guide's examples, GUIDE.md and a README - and checks that the
unzipped copy compiles every example byte-identical too.

Run it whenever the compiler changes; then bump ?v= on every page, as for any asset.
"""
import filecmp, io, json, os, re, shutil, subprocess, sys, tempfile, zipfile

WEB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Projects/stellar-1802')
OUT = os.path.join(WEB, 'sc')

# The compiler and everything it imports. Flat in web/sc/: scc.py's sys.path lines
# point at ../Firmware-Math and ../tools, which do not exist there, and are harmless.
SOURCES = ['SC/scc.py', 'SC/asm1802.py', 'Firmware-Math/mini.py',
           'Firmware-Math/stellar_ops.py', 'tools/stellar_disasm.py']

# The examples, in menu order. input: keys pre-loaded before the program starts.
EXAMPLES = [
    ('hello', 'Hello, terminal (the new built-ins)', 'Craig\r', 'Elf2K',
     'A title bar in reverse video, your name read with getline() (bounded: it stops at 20 '
     'characters, Backspace works), today\'s date and time from the clock chip with rtcget(), '
     'and a table in the three number formats - printz, printw, printh - each column placed '
     'with at(row, col). The input box types "Craig"; empty it to type your own name.'),
    ('types', 'Signed numbers, 16-bit arrays, switch', '', 'flat out',
     'The newest parts of the language, checked line by line against Python: 16-bit arrays (u16 / i16), '
     'every signed comparison between seven values from -32768 to 32767 (each digit is four bits: <, <=, >, >=), '
     'signed / % and >> (C\'s rules: the quotient rounds toward zero), a signed divide inside a bigger '
     'expression, and a switch with fall-through, default, break and continue.'),
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
    ('frontpanel', 'Front panel (Q + hex display)', '', 'Elf2K',
     'Counts $00 to $3F on the Elf2K front panel\'s two-digit display with out(n) while q() blinks '
     'the Q lamp. Watch the panel beside the terminal.'),
    ('tasks', 'Three tasks at once (multitasking)', '', 'Elf2K',
     'One program, three VMs: keyboard() owns the keyboard and queues every key, counter() adds in the '
     'background, and main() prints each key with the running total. Click the terminal and type; q quits. '
     'Shared variables, a chan queue and atomic - see the guide\'s section 16. HW-verified on the Elf2K.'),
    ('stopstart', 'Stop and start a task', '', 'flat out',
     'Four VMs check themselves: main() stops a counting task and sees the count hold still, starts it again; '
     'a stopped task is not woken by the variable it waits for until it is started; a task stops itself and '
     'carries on only when main() starts it. Each line printed is one check passed. HW-verified on the Elf2K.'),
    ('menu', 'A menu (print, getc, switch)', '2x3q', 'Elf2K',
     'A hard-coded menu: the whole menu printed with one print(), a key read with getc(), a small '
     'letter turned into a capital, and switch picking what to do - each choice says which program it '
     'would run. The input box presses 2, x, 3 and q; empty it to choose in the terminal.'),
    ('vmtalk', 'Three VMs talking (chan, shared, wait)', '1922', 'Elf2K',
     'The menu again, now with three VMs: main() runs the menu, worker() waits on a chan for a job and '
     'hands back the sum of 1..N through a shared variable while main() wait()s for it, and ticker() counts '
     'in the background - choice 3 stops and starts it. The input box adds up 1..9 and looks at the '
     'ticker; type 2, 3 or q in the terminal.'),
    ('fact', 'Factorials with every digit', '20\r69\r', 'flat out',
     'A u16 holds 8! at most, so bigger factorials are kept as decimal digits in a byte array and '
     'multiplied as on paper, a digit at a time with a carry - up to 100! (158 digits). The input box asks '
     'for 20! and 69!; type another N (0-100) in the terminal, or Enter to stop.'),
    ('dice', 'Dice (rand and rand(n))', 'aasq', 'Elf2K',
     'rand() is STELLAR\'s RAND opcode, a number 0 to 65535; rand(n) is 0 to n - 1, so rand(6) + 1 is a die. '
     'It stirs rand() while waiting for a key. The input box rolls twice, then S rolls 600 times to show the '
     'spread, and q quits; click the terminal to roll your own.'),
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
    bad += build_zip()
    sys.exit(1 if bad else 0)


README = """STELLAR C - the compiler, to run on your own computer
=====================================================

Stellar C is a small C-like language that compiles to STELLAR bytecode for the RCA 1802
(STELLAR-1802 on a COSMAC Elf 2000). This is the same compiler the Stellar C page at
https://stellar-1802.dev/stellarc runs in the browser.

WHAT YOU NEED
  Python 3.8 or newer. Nothing else - no packages to install.

COMPILE A PROGRAM
  cd stellar-c
  python3 scc.py examples/hello.sc

  This writes examples/hello.lst (the program, ready to load) and examples/hello.sym.json
  (where each function and variable ended up). To name the output yourself:

  python3 scc.py myprog.sc -o myprog.lst

  If the program has a mistake, the compiler prints the line number and what is wrong, and
  writes nothing.

RUN IT
  On an Elf2K: the .lst starts with a commented disassembly (every line begins with ';', so
  the loader skips it), then the block of 'D aaaa bb bb ...' lines. Send the whole file to the
  Elf2K's monitor from your terminal program, the same way as any other STELLAR .lst, and
  start STELLAR. STELLAR firmware V0061.35 or later is needed (rtcget/rtcset use its $07
  clock opcode).

  In a browser: open https://stellar-1802.dev/simulator and use "Open .lst", or paste the
  source into https://stellar-1802.dev/stellarc and press Compile, then Run.

LEARN THE LANGUAGE
  GUIDE.md is the language, step by step, from the first program to a finished game. Every
  example in it is in guide-examples/ and was checked by compiling and running it. The same
  guide, with Try-it links, is at https://stellar-1802.dev/stellarc-guide

FILES
  scc.py              the compiler (run this one)
  asm1802.py          its 1802 assembler, for native { } blocks
  mini.py             its STELLAR assembler
  stellar_ops.py      the STELLAR commands it emits
  stellar_disasm.py   STELLAR command lengths and names
  examples/           the example programs from the Stellar C page
  guide-examples/     every runnable example from GUIDE.md
  GUIDE.md            the guide

Stellar C is a prototype and the language is still growing; the newest version is always on
the Stellar C page.
"""


def guide_examples():
    """[(name, source)] for every runnable example in the work repo's SC/GUIDE.md."""
    text = open(os.path.join(WORK, 'SC', 'GUIDE.md')).read()
    return re.findall(r'^```c example=(\S+)[^\n]*\n(.*?)\n```', text, re.S | re.M)


def build_zip():
    """web/downloads/stellar-c.zip; returns the examples the unzipped copy compiles differently."""
    out = os.path.join(WEB, 'downloads', 'stellar-c.zip')
    files = [('README.txt', README.encode())]
    files += [(os.path.basename(r), open(os.path.join(WORK, r), 'rb').read()) for r in SOURCES]
    files += [('GUIDE.md', open(os.path.join(WORK, 'SC', 'GUIDE.md'), 'rb').read())]
    files += [('examples/%s.sc' % e[0], open(os.path.join(WORK, 'SC', 'examples', e[0] + '.sc'), 'rb').read())
              for e in EXAMPLES]
    guide = guide_examples()
    files += [('guide-examples/%s.sc' % n, (src + '\n').encode()) for n, src in guide]
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in files:                       # fixed dates: the same files make the same zip
            info = zipfile.ZipInfo('stellar-c/' + name, date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    open(out, 'wb').write(buf.getvalue())

    # the unzipped copy, run as a user would run it, must compile each example as the work repo does
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        zipfile.ZipFile(out).extractall(tmp)
        d = os.path.join(tmp, 'stellar-c')
        for e in EXAMPLES:
            r = subprocess.run([sys.executable, 'scc.py', 'examples/%s.sc' % e[0]], cwd=d, capture_output=True, text=True)
            want = open(os.path.join(WORK, 'SC', 'examples', e[0] + '.lst')).read()
            got = open(os.path.join(d, 'examples', e[0] + '.lst')).read() if r.returncode == 0 else r.stderr
            if got != want: bad.append('zip:' + e[0])
        for n, _ in guide:
            r = subprocess.run([sys.executable, 'scc.py', 'guide-examples/%s.sc' % n], cwd=d, capture_output=True, text=True)
            if r.returncode or not os.path.exists(os.path.join(d, 'guide-examples', n + '.lst')): bad.append('zip-guide:' + n)
    print('wrote web/downloads/stellar-c.zip (%d files, %.0f KB); unzipped, it compiles every example as the work repo: %s'
          % (len(files), os.path.getsize(out) / 1024, 'ALL' if not bad else 'NO - ' + ', '.join(bad)))
    return bad


if __name__ == '__main__':
    main()
