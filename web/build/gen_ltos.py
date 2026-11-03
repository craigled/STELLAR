"""Bake LTOS for the web: the web BIOS (js/webbios.js) and the demo CF card (ltos/ltos-card.bin).

    python3 web/build/gen_ltos.py [path/to/stellar-1802]

Run on the Mac (the card is made the way the LTOS tests make theirs: the installer's F run in the Python Elf2K,
then the files added through a mounted copy of the image).

The card: LTOS 0.5 installed (kernel, boot sector, STELLAR.BIN), every system program in /BIN with HELP.HLP,
STELLAR apps in /BIN as NAME.STL, scripts in the root (TEST.SH, DEMO.SH), documents in /DOCS.
"""
import os, sys, json, shutil, struct
WORK = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Projects/stellar-1802')
LTOS = os.path.join(WORK, 'LTOS')
WEB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, LTOS)
os.chdir(LTOS)
import build
import verify_phase0 as V
import verify_phase1 as P1
import verify_phase2 as P2

SECTORS = 16384                                  # an 8 MB card
SAMPLES = os.path.join(WEB, 'samples')
APPS = [                                         # (NAME on the card, the .lst)
    ('GALAXIA', os.path.join(WORK, 'APPLICATIONS', 'Galaxia', 'Galaxia.lst')),
    ('LW2', os.path.join(WORK, 'APPLICATIONS', 'Lite-Writer-2', 'Lite-Writer-2.lst')),
    ('LW3', os.path.join(WORK, 'APPLICATIONS', 'Lite-Writer-3', 'Lite-Writer-3.lst')),
    ('TETRIS', 'Tetris.lst'), ('BREAKOUT', 'Breakout.lst'), ('SNAKE', 'Snake.lst'),
    ('LANDER', 'Lunar-Lander.lst'), ('RACER', 'Racer.lst'), ('PONG', 'Pong.lst'), ('INVADERS', 'Invaders.lst'),
    ('TICTAC', 'Tic-Tac-Toe.lst'), ('MOONBASE', 'Moonbase.lst'), ('WARMER', 'Getting-Warmer.lst'),
    ('MANDEL', 'Mandelbrot.lst'), ('STARS', 'Starfield.lst'), ('BALL', 'Bouncing-Ball.lst'),
    ('STARSHIP', 'Starship.lst'), ('LIFELAB', 'Life-Lab.lst'), ('LIFE', 'Game-of-Life.lst'),
    ('SORTS', 'Sort-Visualiser.lst'), ('ELIZA', 'ELIZA.lst'), ('BANNER', 'Banner.lst'), ('PI', 'Pi-Spigot.lst'),
    ('PRIMES', 'Prime-Gen-v07.lst'), ('CALC', 'Simple-Calc-8.lst'), ('BATTLE', 'Battleship.lst'),
    ('CANNON', 'CanonBall-Solo.lst'), ('CLOCK', 'Big-Clock-v3.lst'),
    ('ORBIT', os.path.join(WEB, 'downloads', 'Stellar-Orbit.lst')), ('MAZE', os.path.join(WEB, 'downloads', 'Maze.lst')),
    ('MAZERACE', os.path.join(WEB, 'downloads', 'MazeRace.lst')),
    ('DICE', os.path.join(WORK, 'SC', 'examples', 'dice.lst')),
]

TEST_SH = b'''echo "Testing the batch feature"
echo "1"
echo "2"
echo "3"
exit
'''

README = b'''LTOS 0.5 - LiteOS for the Elf2K, running in your browser.

The real kernel, shell and programs, on an emulated RCA 1802 with a CF card.
Some things to try:

  HELP              every command          HELP SCRIPTS   what a script can do
  DIR /BIN          the programs           TYPE DEMO.SH   a shell script
  DEMO you          run DEMO.SH            SH -x TEST     each line shown as it runs
  LW2 DOCS/LETTER.TXT                      the Lite-Writer 2 editor (^X: menu)
  LW3 DOCS/BOOK.TXT   Lite-Writer 3: a 20 KB file, a part at a time (^N ^P ^T ^B)
  ENANO DOCS/BOOK.TXT   ENANO: a small nano; Shift+arrow selects (^G: every key)
  GALAXIA           a game (arrows, SPACE; Esc quits back to LTOS)
  ORBIT             STELLAR ORBIT: fly Apollo 7 on three VMs (SPACE starts the count)
  EROFF EROFF.RF    a small nroff: plain text made into pages (> EROFF.TXT keeps it)
  SORT -n -r DOCS/SALES.TXT    SORT, UNIQ, PWD, WC, GREP ... - HELP has them all
  RAWK '{ s += $2 } END { print s }' DOCS/SALES.TXT
  ECHO hello > HI.TXT ; TYPE HI.TXT ; FSCK

Changes you make stay in this browser. "Restore the card" puts every file back.
'''

LETTER = b'''Dear reader,

This letter lives on an emulated CompactFlash card, in a FAT16 folder called
DOCS. LTOS reads and writes it a 512-byte sector at a time, exactly as it does
on Craig's Elf2K.

Lite-Writer 2 is a STELLAR program: STELLAR.PRG loads the STELLAR firmware,
which runs the editor in its virtual machine. Ctrl-X shows the menu; save, and
the letter goes back onto the card.

Best wishes,
The 1802
'''

BOOK = b''.join(b'Line %04d of a long document: LW3 holds one part at a time.\n' % i for i in range(1, 341))

SALES = b'''north 120
south 75
east 210
west 95
north 60
east 40
'''


def add_files(m):
    os.makedirs(os.path.join(m, 'BIN'), exist_ok=True)
    os.makedirs(os.path.join(m, 'DOCS'), exist_ok=True)
    for n in os.listdir(m):                                         # every program into /BIN, as RECV SYSTEM puts them
        if n.upper().endswith('.PRG'):
            os.rename(os.path.join(m, n), os.path.join(m, 'BIN', n))
    for name, lst in APPS:
        p = lst if os.path.isabs(lst) else os.path.join(SAMPLES, lst)
        open(os.path.join(m, 'BIN', name + '.STL'), 'wb').write(build.stl_of(open(p, encoding='latin1').read()))
    open(os.path.join(m, 'TEST.SH'), 'wb').write(TEST_SH)
    open(os.path.join(m, 'DEMO.SH'), 'wb').write(open(os.path.join(LTOS, 'examples', 'DEMO.SH'), 'rb').read())
    open(os.path.join(m, 'EROFF.RF'), 'wb').write(open(os.path.join(LTOS, 'examples', 'EROFF.RF'), 'rb').read())
    open(os.path.join(m, 'README.TXT'), 'wb').write(README)
    open(os.path.join(m, 'DOCS', 'LETTER.TXT'), 'wb').write(LETTER)
    open(os.path.join(m, 'DOCS', 'SALES.TXT'), 'wb').write(SALES)
    open(os.path.join(m, 'DOCS', 'BOOK.TXT'), 'wb').write(BOOK)
    for junk in ('.fseventsd', '.Spotlight-V100', '.Trashes'):        # what the Mac leaves on a volume
        shutil.rmtree(os.path.join(m, junk), ignore_errors=True)
    for d, ds, fs in os.walk(m):
        for f in fs:
            if f.startswith('._'): os.remove(os.path.join(d, f))


def main():
    kimg, ksyms = build.kernel()
    mem, syms, boot = build.build(kimg)
    cf, e2k, st = P1.installed_full(mem, SECTORS)
    img, _ = P2.mac(V.image(cf, SECTORS), add_files)
    rc, _ = P2.fsck_free(img)
    assert rc == 0, 'fsck_msdos: %d' % rc
    used = [(l, img[l * 512:(l + 1) * 512]) for l in range(SECTORS) if any(img[l * 512:(l + 1) * 512])]
    out = bytearray(b'LTCD' + struct.pack('<II', SECTORS, len(used)))
    for l, s in used: out += struct.pack('<I', l) + s
    os.makedirs(os.path.join(WEB, 'ltos'), exist_ok=True)
    open(os.path.join(WEB, 'ltos', 'ltos-card.bin'), 'wb').write(out)
    m, s = build.assemble('webbios')
    bios = bytearray(b'\xFF' * 0x8000)
    for a, b in m.items(): bios[a - 0x8000] = b
    js = ('// webbios.js - written by build/gen_ltos.py from LTOS/webbios.asm: our own stand-in for the Elf2K ROM\n'
          '// ($8000-$FFFF), base64. Not the Spare Time Gizmos ROM.\n'
          'window.LTOS_WEBBIOS = "%s";\n' % __import__('base64').b64encode(bytes(bios)).decode())
    open(os.path.join(WEB, 'js', 'webbios.js'), 'w').write(js)
    print('ltos-card.bin: %d sectors used of %d, %d bytes; webbios.js: %d bytes of code'
          % (len(used), SECTORS, len(out), len(m)))


if __name__ == '__main__':
    main()
