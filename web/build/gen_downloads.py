"""Build web/downloads/: the app catalogue behind the Simulator page's download list.

Programs that are Simulator samples are served from web/samples/ as they are (the
curated copies the Simulator runs). The rest are copied here from the work repo
(~/Projects/stellar-1802/APPLICATIONS) at its COMMITTED version, never a working-tree
edit that has not been run on the hardware.

    python3 web/build/gen_downloads.py
"""
import os, json, subprocess

WEB = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
WORK = os.path.expanduser('~/Projects/stellar-1802')
OUT = os.path.join(WEB, 'downloads')

# (group, name, what, source) - source 'samples/X.lst', or a work-repo path to copy.
# A note of None means HW-verified on the Elf2K.
CATALOG = [
 ('Games', 'MOONBASE', 'Text adventure: escape the damaged moon base. Two-word commands, 10 rooms; every game is shuffled.',
  'APPLICATIONS/MOONBASE/Moonbase.lst', None),
 ('Games', 'Lunar Lander', 'Land on the pad before the fuel runs out. Easy and Hard. VT100, arrow keys.',
  'samples/Lunar-Lander.lst', None),
 ('Games', 'Snake', 'Eat the food, grow, and do not hit the wall or yourself. Ten speed levels. VT100, arrow keys.',
  'samples/Snake.lst', None),
 ('Games', 'Tetris', 'Steer the falling pieces and clear the rows; levels speed up. VT100, arrow keys.',
  'samples/Tetris.lst', None),
 ('Games', 'Breakout', 'Knock out the wall of bricks; three balls, faster each wall. VT100, arrow keys.',
  'samples/Breakout.lst', None),
 ('Games', 'Battleship', 'You against the computer on two 10 x 10 seas; arrow-key aim or typed squares. VT100.',
  'samples/Battleship.lst', None),
 ('Games', 'CanonBall', 'Your castle and cannon against the computer\'s: aim, fire, mind the wind; three levels. VT100. Stellar C.',
  'samples/CanonBall.lst', None),
 ('Games', 'CanonBall Solo', 'Aim the great cannon and knock down the castle in as few shots as you can. VT100. Stellar C.',
  'samples/CanonBall-Solo.lst', None),
 ('Games', 'Getting Warmer', 'Guess the number from 1 to 1000 in ten tries: higher or lower, warmer or colder. Plain text.',
  'samples/Getting-Warmer.lst', None),
 ('Games', 'Pong', 'You on the right against the computer. VT100, arrow keys.', 'samples/Pong.lst', None),
 ('Games', 'Racer', 'Keep the car on a scrolling, winding road. VT100, arrow keys.', 'samples/Racer.lst', None),
 ('Games', 'Invaders', 'Two rows of six invaders and an arrow-key gun. VT100.', 'samples/Invaders.lst', None),
 ('Games', 'Tic-Tac-Toe', 'You are X against a simple AI.', 'samples/Tic-Tac-Toe.lst', None),
 ('Games', 'Maze', 'VM1 builds a maze, VM2 solves it. Two programs, one file. VT100.',
  'APPLICATIONS/Maze/Maze.lst', None),
 ('Text', 'Lite-Writer 2', 'Full-screen word processor: word wrap, find, cut/paste, 4 save slots. VT100.',
  'samples/Lite-Writer-2.lst', 'the 2026-10-03 keep-the-slots change is simulator-verified, not yet on hardware'),
 ('Text', 'ELIZA', 'The classic 1966 chatbot psychotherapist.', 'samples/ELIZA.lst', None),
 ('Text', 'Banner', 'Prints what you type as big block letters.', 'samples/Banner.lst', None),
 ('Text', 'GETSTR', 'The $C2 line-input opcode: read a line, print it back.', 'samples/GETSTR.lst', None),
 ('Text', 'String Store', 'Keep three typed lines in slots and print them back.', 'samples/String-Store.lst', None),
 ('Clock', 'Big Clock v3', 'Big seven-segment time, the day and the date from the RTC ($07); timer, hourly chime and alarm on Q. VT100.',
  'samples/Big-Clock-v3.lst', None),
 ('Morse', 'Morse Sender v17', 'Type text; it is sent as Morse code on the Q output.',
  'APPLICATIONS/MORSE CODE/Morse-Sender-v17.lst', None),
 ('Morse', 'Morse Sender v18', 'The same, but every dot and dash is a 700 Hz tone on Q (RUNMC) - for a speaker; v17 is for keying real gear.',
  'samples/Morse-Sender-v18.lst', None),
 ('Morse', 'Morse Receiver v11', 'Key Morse on the Input switch; it learns your hand, and can put the text in a Lite-Writer 2 slot.',
  'samples/Morse-Receiver-v11.lst', 'simulator-verified, not yet run on hardware'),
 ('Morse', 'Morse Receiver v10', 'Key Morse on the Input switch; it learns your hand and prints the text.',
  'APPLICATIONS/MORSE CODE/Morse-Receiver-v10.lst', 'simulator-verified, not yet run on hardware'),
 ('Math', 'Simple-Calc-5', '5-digit calculator, all in STELLAR bytecode.', 'samples/Simple-Calc-5.lst', None),
 ('Math', 'Simple-Calc-8', '8-digit calculator, math in native 1802 via RUNMC.', 'samples/Simple-Calc-8.lst', None),
 ('Math', 'Pi digits', 'The digits of pi, up to 1526, by the spigot; the inner loop is raw 1802 (RUNMC).',
  'samples/Pi-Spigot.lst', None),
 ('Math', 'Pi digits Stellar only', 'The same pi spigot in pure STELLAR bytecode, up to 350 digits (18x slower).',
  'samples/Pi-Stellar-Only.lst', None),
 ('Math', 'Prime-Gen v07', 'Primes in a range you choose, using the native OUTDEC print.',
  'samples/Prime-Gen-v07.lst', None),
 ('Math', 'Prime-Gen v05', 'Primes by odd-only trial division.', 'samples/Prime-Gen-v05.lst', None),
 ('Math', 'Prime-Gen v04', 'An earlier prime generator (multiply-back divide test).',
  'samples/Prime-Gen-v04.lst', None),
 ('Graphics', 'Mandelbrot', 'The Mandelbrot set in ASCII.', 'samples/Mandelbrot.lst', None),
 ('Graphics', 'Game of Life', "Conway's Life on a 40x20 grid: a blinker and a glider. VT100.", 'samples/Game-of-Life.lst', None),
 ('Graphics', 'Sort visualiser', 'Watch a bubble sort as VT100 bars.', 'samples/Sort-Visualiser.lst', None),
 ('Graphics', 'Starfield', 'Stars streaming outward; you pick how many. VT100.', 'samples/Starfield.lst', None),
 ('Graphics', 'Bouncing Ball', 'Two balls bouncing around the screen and off each other. VT100.',
  'samples/Bouncing-Ball.lst', None),
 ('Graphics', 'Starship', 'The COSMAC ELF starship logo in ASCII.', 'samples/Starship.lst', None),
 ('Graphics', 'Front panel', 'Lights the Q lamp and counts $00-$1F on the hex display.', 'samples/Front-Panel.lst', None),
 ('Multitasking', 'Mandelbrot x 4', 'Four VMs draw a quarter of the Mandelbrot set each. One file.',
  'APPLICATIONS/Mandelbrot-4VM.lst', None),
 ('Multitasking', 'Maze Race', 'VM1 builds a maze; VM2 and VM3 race it, right hand against left. One file.',
  'APPLICATIONS/Maze/MazeRace.lst', None),
 ('Multitasking', 'Life Race', 'Game of Life in bytecode against native 1802, side by side. One file.',
  'APPLICATIONS/Life-Race/Life-Race.lst', None),
 ('Multitasking', 'Race condition (VM1)', 'Two VMs share a counter: without a lock, counts go missing. '
  'Load this file first.', 'APPLICATIONS/Race-Condition/Race-VM1.lst', None),
 ('Multitasking', 'Race condition (VM2)', 'The second worker for the race-condition demo. Load after VM1.',
  'APPLICATIONS/Race-Condition/Race-VM2.lst', None),
 ('Firmware', 'FW-Checksum V0061.34', 'Checks the firmware after loading: prints 15 checksums to compare '
  'with the list in the file.', 'TESTS/FW-Checksum-V0061.34.lst', None),
]


def committed(path):
    return subprocess.run(['git', '-C', WORK, 'show', 'HEAD:' + path], check=True,
                          capture_output=True).stdout


def main():
    os.makedirs(OUT, exist_ok=True)
    keep, out = set(), []
    for group, name, what, src, note in CATALOG:
        if src.startswith('samples/'):
            assert os.path.exists(os.path.join(WEB, src)), src
            href = src
        else:
            fn = os.path.basename(src).replace(' ', '-')
            data = committed(src)
            assert b'\nD 4000 CD' in b'\n' + data or b'\nD ' in data, src
            with open(os.path.join(OUT, fn), 'wb') as f: f.write(data)
            keep.add(fn); href = 'downloads/' + fn
        out.append({'group': group, 'name': name, 'what': what, 'href': href, 'note': note})
    for fn in os.listdir(OUT):
        if fn.endswith('.lst') and fn not in keep: os.remove(os.path.join(OUT, fn))
    with open(os.path.join(OUT, 'catalog.json'), 'w') as f: json.dump(out, f, indent=1)
    print('%d apps (%d copied from the work repo) -> %s' % (len(out), len(keep), OUT))


if __name__ == '__main__':
    main()
