# STELLAR applications

Every finished STELLAR program, as D-line `.lst` files for the Elf2K monitor. Load the
firmware first (the `.hex` from the [web Simulator](https://stellar-1802.dev/simulator.html#elf2k)),
then an app's `.lst`, then cold-boot STELLAR. Every file here has been run on the Elf2K
(the exceptions are noted). Most run in VM1 at `$4000`; the multitasking files say
which VMs they use and in what order to load them.

The same programs run in the browser: the [Simulator](https://stellar-1802.dev/simulator.html)
has most of them as samples, and its download list is built from the same copies.

## Games

| App | File | What it does |
|---|---|---|
| Battleship | [`Battleship.lst`](Games/Battleship.lst) | You against the computer on two 10 x 10 seas; arrow-key aim or typed squares. VT100. |
| Breakout | [`Breakout.lst`](Games/Breakout.lst) | Knock out the wall of bricks; three balls, faster each wall. VT100, arrow keys. |
| CanonBall | [`CanonBall.lst`](Games/CanonBall.lst) | Your castle and great cannon against the computer's: aim, fire, mind the wind; Easy, Normal, Hard. VT100. Written in Stellar C ([source](Games/CanonBall.sc), [notes](Games/CanonBall.md)). |
| CanonBall Solo | [`CanonBall-Solo.lst`](Games/CanonBall-Solo.lst) | Aim the cannon and knock down the castle in as few shots as you can. VT100. Stellar C ([source](Games/CanonBall-Solo.sc)). |
| Getting Warmer | [`Getting-Warmer.lst`](Games/Getting-Warmer.lst) | Guess the number from 1 to 1000 in ten tries: higher or lower, warmer or colder. Plain text. |
| Invaders | [`Invaders.lst`](Games/Invaders.lst) | Two rows of six invaders and an arrow-key gun. VT100. |
| Lunar Lander | [`Lunar-Lander.lst`](Games/Lunar-Lander.lst) | Land on the pad before the fuel runs out. Easy and Hard. VT100, arrow keys. |
| Maze | [`Maze.lst`](Games/Maze.lst) | VM1 builds a maze, VM2 solves it. Two programs, one file. VT100. |
| MOONBASE | [`Moonbase.lst`](Games/Moonbase.lst) | Text adventure: escape the damaged moon base. Two-word commands, 10 rooms; every game is shuffled. |
| Pong | [`Pong.lst`](Games/Pong.lst) | You on the right against the computer. VT100, arrow keys. |
| Racer | [`Racer.lst`](Games/Racer.lst) | Keep the car on a scrolling, winding road. VT100, arrow keys. |
| Snake | [`Snake.lst`](Games/Snake.lst) | Eat the food, grow, and do not hit the wall or yourself. Ten speed levels. VT100, arrow keys. |
| Tetris | [`Tetris.lst`](Games/Tetris.lst) | Steer the falling pieces and clear the rows; levels speed up. VT100, arrow keys. |
| Tic-Tac-Toe | [`Tic-Tac-Toe.lst`](Games/Tic-Tac-Toe.lst) | You are X against a simple AI. |

## Clock

| App | File | What it does |
|---|---|---|
| Big Clock | [`Big-Clock-v3.lst`](Clock/Big-Clock-v3.lst) | The time in big seven-segment digits, the day and the date, from the DS12887 RTC; a timer, an hourly chime and an alarm with snooze on Q. Needs firmware V0061.35 (the $07 RTC opcode). VT100. |

## Text

| App | File | What it does |
|---|---|---|
| Banner | [`Banner.lst`](Text/Banner.lst) | Prints what you type as big block letters. |
| ELIZA | [`ELIZA.lst`](Text/ELIZA.lst) | The classic 1966 chatbot psychotherapist. |
| GETSTR | [`GETSTR.lst`](Text/GETSTR.lst) | The $C2 line-input opcode: read a line, print it back. |
| Lite-Writer 2 | [`Lite-Writer-2.lst`](Text/Lite-Writer-2.lst) | Full-screen word processor: word wrap, find, cut/paste, 4 save slots. VT100. *(the 2026-10-03 keep-the-slots change is simulator-verified, not yet on hardware)* |
| STAR-Writer | [`STAR-Writer.lst`](Text/STAR-Writer.lst) | The early line-oriented text editor (before Lite-Writer). *(no hardware run on record)* |
| String Store | [`String-Store.lst`](Text/String-Store.lst) | Keep three typed lines in slots and print them back. |

## Morse

| App | File | What it does |
|---|---|---|
| Morse Sender v17 | [`Morse-Sender-v17.lst`](Morse/Morse-Sender-v17.lst) | Type text; it is sent as Morse code on the Q output. |
| Morse Sender v18 | [`Morse-Sender-v18.lst`](Morse/Morse-Sender-v18.lst) | The same, but every dot and dash is a 700 Hz tone on Q (RUNMC) - for a speaker; v17 is for keying real gear. |

## Math

| App | File | What it does |
|---|---|---|
| Pi digits | [`Pi-Spigot.lst`](Math/Pi-Spigot.lst) | The digits of pi, up to 1526, by the spigot; the inner loop is raw 1802 (RUNMC). |
| Pi digits Stellar only | [`Pi-Stellar-Only.lst`](Math/Pi-Stellar-Only.lst) | The same pi spigot in pure STELLAR bytecode, up to 350 digits (18x slower). |
| Prime-Gen v04 | [`Prime-Gen-v04.lst`](Math/Prime-Gen-v04.lst) | An earlier prime generator (multiply-back divide test). |
| Prime-Gen v05 | [`Prime-Gen-v05.lst`](Math/Prime-Gen-v05.lst) | Primes by odd-only trial division. |
| Prime-Gen v07 | [`Prime-Gen-v07.lst`](Math/Prime-Gen-v07.lst) | Primes in a range you choose, using the native OUTDEC print. |
| Simple-Calc-5 | [`Simple-Calc-5.lst`](Math/Simple-Calc-5.lst) | 5-digit calculator, all in STELLAR bytecode. |
| Simple-Calc-8 | [`Simple-Calc-8.lst`](Math/Simple-Calc-8.lst) | 8-digit calculator, math in native 1802 via RUNMC. |

## Graphics

| App | File | What it does |
|---|---|---|
| Bouncing Ball | [`Bouncing-Ball.lst`](Graphics/Bouncing-Ball.lst) | Two balls bouncing around the screen and off each other. VT100. |
| Front panel | [`Front-Panel.lst`](Graphics/Front-Panel.lst) | Lights the Q lamp and counts $00-$1F on the hex display. |
| Game of Life | [`Game-of-Life.lst`](Graphics/Game-of-Life.lst) | Conway's Life on a 40x20 grid: a blinker and a glider. VT100. |
| Mandelbrot | [`Mandelbrot.lst`](Graphics/Mandelbrot.lst) | The Mandelbrot set in ASCII. |
| Sort visualiser | [`Sort-Visualiser.lst`](Graphics/Sort-Visualiser.lst) | Watch a bubble sort as VT100 bars. |
| Starfield | [`Starfield.lst`](Graphics/Starfield.lst) | Stars streaming outward; you pick how many. VT100. |
| Starship | [`Starship.lst`](Graphics/Starship.lst) | The COSMAC ELF starship logo in ASCII. |

## Multitasking

| App | File | What it does |
|---|---|---|
| Life Race | [`Life-Race.lst`](Multitasking/Life-Race.lst) | Game of Life in bytecode against native 1802, side by side. One file. |
| Mandelbrot x 4 | [`Mandelbrot-4VM.lst`](Multitasking/Mandelbrot-4VM.lst) | Four VMs draw a quarter of the Mandelbrot set each. One file. |
| Maze Race | [`MazeRace.lst`](Multitasking/MazeRace.lst) | VM1 builds a maze; VM2 and VM3 race it, right hand against left. One file. |
| Race condition (VM1) | [`Race-VM1.lst`](Multitasking/Race-VM1.lst) | Two VMs share a counter: without a lock, counts go missing. Load this file first. |
| Race condition (VM2) | [`Race-VM2.lst`](Multitasking/Race-VM2.lst) | The second worker for the race-condition demo. Load after VM1. |

## Write-ups

- [Tic-Tac-Toe.md](Games/Tic-Tac-Toe.md)
- [Banner.md](Text/Banner.md)
- [ELIZA.md](Text/ELIZA.md)
- [Mandelbrot.md](Graphics/Mandelbrot.md)

The work repository (`stellar-1802`) keeps every earlier version, the builders and the verifiers.
