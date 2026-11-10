# An example session

Claude using the Elf2K through `mcp/server.mjs`. Every block below is what the server sent back, unedited.
Made by `node mcp/example_session.mjs`, which starts the server, sends these 19 tool calls over stdin/stdout
and writes down the results. The calls and the notes above them are Claude's. Run it again and you get the
same file, to the machine cycle.

## 1. boot {}

Power on.

```
[+1.691 s of Elf2K time (634112 cycles), 1.691 s since power-on | waiting for a key | cursor row 5 col 7]
---- screen ----

LTOS: loading the kernel .....................done.

LTOS 0.5 - LiteOS for the Elf2K.  Type HELP for the commands.
LTOS>
```

## 2. command {"line":"VER"}

What is this?

```
[+1.535 s of Elf2K time (575793 cycles), 3.226 s since power-on | waiting for a key | cursor row 14 col 7]
---- screen ----

LTOS: loading the kernel .....................done.

LTOS 0.5 - LiteOS for the Elf2K.  Type HELP for the commands.
LTOS> VER
LTOS 0.5 - LiteOS for the Elf2K
Free software, GPL-3.0-or-later: HELP LICENSE
Kernel:     $0300-$2C98 (10649 bytes)
Programs:   $3000-$6BFF
Booted:     the boot sector started with R3
Card:       LTOS web card
Size:       8 MB
STELLAR:    STELLAR.BIN at sector $0100 - in RAM at boot: MON puts it back
LTOS>
```

## 3. command {"line":"NANO VMS.TXT"}

A file to work on. STELLAR has four VMs, each with a core and a program block; I will type them into NANO out of order.

```
[+4.637 s of Elf2K time (1738778 cycles), 7.863 s since power-on | waiting for a key | cursor row 1 col 1]
---- screen ----























 NANO 1.1   VMS.TXT  Line 1  Col 1   ^G Help
```

## 4. type {"text":"VM3 core 3800 program 6000\nVM1 core 3000 program 4000\nVM4 core 3C00 program 7000\nVM2 core 3400 program 5000\n"}

A newline in the text is the Enter key. NANO redraws as it goes, so 108 keys take a few seconds of the Elf2K's time.

```
[+7.145 s of Elf2K time (2679250 cycles), 15.008 s since power-on | waiting for a key | cursor row 5 col 1]
---- screen ----
VM3 core 3800 program 6000
VM1 core 3000 program 4000
VM4 core 3C00 program 7000
VM2 core 3400 program 5000



















 NANO 1.1   VMS.TXT  Line 5  Col 1  Modified   ^G Help
```

## 5. press {"keys":["Ctrl-O","Ctrl-X"]}

Ctrl-O writes the file, Ctrl-X leaves.

```
[+0.534 s of Elf2K time (200066 cycles), 15.541 s since power-on | waiting for a key | cursor row 1 col 7]
---- screen ----
LTOS>
```

## 6. command {"line":"SORT VMS.TXT"}

The 1802 sorts it.

```
[+1.778 s of Elf2K time (666604 cycles), 17.319 s since power-on | waiting for a key | cursor row 6 col 7]
---- screen ----
LTOS> SORT VMS.TXT
VM1 core 3000 program 4000
VM2 core 3400 program 5000
VM3 core 3800 program 6000
VM4 core 3C00 program 7000
LTOS>
```

## 7. command {"line":"GREP -n 6000 VMS.TXT"}

Which VM has the block at $6000?

```
[+1.995 s of Elf2K time (748114 cycles), 19.314 s since power-on | waiting for a key | cursor row 8 col 7]
---- screen ----
LTOS> SORT VMS.TXT
VM1 core 3000 program 4000
VM2 core 3400 program 5000
VM3 core 3800 program 6000
VM4 core 3C00 program 7000
LTOS> GREP -n 6000 VMS.TXT
1:VM3 core 3800 program 6000
LTOS>
```

## 8. command {"line":"RAWK '{ print $1, $5 }' VMS.TXT"}

awk, in 1802 code: the first and last word of each line.

```
[+3.423 s of Elf2K time (1283702 cycles), 22.737 s since power-on | waiting for a key | cursor row 13 col 7]
---- screen ----
LTOS> SORT VMS.TXT
VM1 core 3000 program 4000
VM2 core 3400 program 5000
VM3 core 3800 program 6000
VM4 core 3C00 program 7000
LTOS> GREP -n 6000 VMS.TXT
1:VM3 core 3800 program 6000
LTOS> RAWK '{ print $1, $5 }' VMS.TXT
VM3 6000
VM1 4000
VM4 7000
VM2 5000
LTOS>
```

## 9. command {"line":"SORT -r VMS.TXT > DOWN.TXT"}

Sorted the other way, into a new file.

```
[+2.147 s of Elf2K time (805255 cycles), 24.884 s since power-on | waiting for a key | cursor row 14 col 7]
---- screen ----
LTOS> SORT VMS.TXT
VM1 core 3000 program 4000
VM2 core 3400 program 5000
VM3 core 3800 program 6000
VM4 core 3C00 program 7000
LTOS> GREP -n 6000 VMS.TXT
1:VM3 core 3800 program 6000
LTOS> RAWK '{ print $1, $5 }' VMS.TXT
VM3 6000
VM1 4000
VM4 7000
VM2 5000
LTOS> SORT -r VMS.TXT > DOWN.TXT
LTOS>
```

## 10. read_file {"path":"/DOWN.TXT"}

That file, read from the card image itself and not through LTOS. No Elf2K time passes.

```
VM4 core 3C00 program 7000
VM3 core 3800 program 6000
VM2 core 3400 program 5000
VM1 core 3000 program 4000
```

## 11. launch_app {"name":"GALAXIA"}

A game. LTOS loads the STELLAR firmware and the app.

```
[+4.984 s of Elf2K time (1868855 cycles), 29.868 s since power-on | waiting for a key | cursor row 22 col 50 (hidden)]
---- screen ----


                             S T E L L A R

                             G  A  L  A  X  I  A


             The swarm hangs above you, swaying from side to side. Shoot it
             down before it shoots you. Each wave comes back faster.

                       =W=  flagship   60
                       }@{  red        50
                       <O>  purple     40
                       /V\  blue       30


                       Left / Right arrows (or Z / X): move
                       SPACE: fire     P: pause
                       R: restart    Esc: quit


                           Press any key to start
```

## 12. press {"keys":["Space"],"max_seconds":1}

Any key starts it. One second of the Elf2K's time, then stop and look.

```
[+1.000 s of Elf2K time (375016 cycles), 30.868 s since power-on | time ran out (still busy or still drawing) | cursor row 23 col 42 (hidden)]
---- screen ----
 STELLAR GALAXIA     SCORE 00000   HIGH 00000   WAVE  1   SHIPS 3

                               =W=            =W=

                          }@{  }@{  }@{  }@{  }@{  }@{

                     <O>  <O>  <O>  <O>  <O>  <O>  <O>  <O>

                /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\

                /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\











                                      /^\
 Arrows or Z X: move   SPACE: fire   P: pause   R: restart   Esc: quit
```

## 13. press {"keys":["Left","Left","Left","Space"],"max_seconds":1.5}

Three steps left, fire, and a second and a half for the shot to get there.

```
[+1.500 s of Elf2K time (562525 cycles), 32.368 s since power-on | time ran out (still busy or still drawing) | cursor row 11 col 69 (hidden)]
---- screen ----
 STELLAR GALAXIA     SCORE 00030   HIGH 00030   WAVE  1   SHIPS 3

                                 =W=            =W=

                            }@{  }@{  }@{  }@{  }@{  }@{

                       <O>  <O>  <O>  <O>  <O>  <O>  <O>  <O>

                  /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\  /V\

                  /V\  /V\  /V\       /V\  /V\  /V\  /V\  /V\  /V\











                                /^\
 Arrows or Z X: move   SPACE: fire   P: pause   R: restart   Esc: quit
```

## 14. vm_core {"vm":1}

The game is a STELLAR program in VM1. Its core should be where VMS.TXT says: $3000, with the program at $4000.

```
VM1: active, core at $3000, program block $4000 (the VM running now)
registers  R0=0F2A R1=0005 R2=0000 R3=0000 R4=0000 R5=0021 R6=0000 R7=0000
           R8=0013 R9=0003 RA=001E RB=0017 RC=0000 RD=0000 RE=1382 RF=1370
ACC=0000  MA=00000000 rem 0000 sign 00  DA=00000003
PL=4A23 (the command at it: $39)  commands run: 3462
flags  test=0 carry=0 overflow=0 hexdec=0  memmode=1
```

## 15. peek {"address":"$3000","length":32}

The first bytes of that core, as they sit in memory.

```
3000  0F 2A 00 05 00 00 00 00 00 00 00 21 00 00 00 00  .*.........!....
3010  00 13 00 03 00 1E 00 17 00 00 00 00 13 82 13 70  ...............p
```

## 16. press {"keys":["Esc"]}

Esc quits every app.

```
[+1.834 s of Elf2K time (687810 cycles), 34.202 s since power-on | waiting for a key | cursor row 6 col 7]
---- screen ----
Thanks for playing STELLAR GALAXIA.

LTOS: loading the kernel .....................done.

LTOS 0.5 - LiteOS for the Elf2K.  Type HELP for the commands.
LTOS>
```

## 17. stellar_load {"programs":[{"sample":"Mandelbrot.lst"}],"max_seconds":60}

Now the bare firmware with no LTOS, and one sample program in VM1.

```
[+60.000 s of Elf2K time (22500002 cycles), 60.000 s since power-on | time ran out (still busy or still drawing) | cursor row 9 col 33]
VM1: Mandelbrot.lst
---- screen ----
STELLAR MANDELBROT
...........:::::---------------:::::::::
..........::::----------==+x+==---::::::
.........:::----------===+c***===--:::::
.........::---------====++a#@a++==---:::
........::---------====+co#@@@o++==---::
........:--------====+@@ax#@@W*aca+=---:
.......:--------==+++cx@@@@@@@@@@@o=---:
.......:------=++++ccxW@@@@@@@@@
```

## 18. run {"seconds":600}

It is still drawing. Let it finish.

```
[+185.775 s of Elf2K time (69665573 cycles), 245.775 s since power-on | the 1802 stopped (IDL) | cursor row 24 col 1]
---- screen ----
..........::::----------==+x+==---::::::
.........:::----------===+c***===--:::::
.........::---------====++a#@a++==---:::
........::---------====+co#@@@o++==---::
........:--------====+@@ax#@@W*aca+=---:
.......:--------==+++cx@@@@@@@@@@@o=---:
.......:------=++++ccxW@@@@@@@@@@@c+=---
.......---===+aao%ooa@@@@@@@@@@@@@%+=---
.......-===++co#@@@#x@@@@@@@@@@@@@*+=---
......-===+++ax@@@@@@@@@@@@@@@@@@@*+=---
......=+=ccoa@@@@@@@@@@@@@@@@@@@@@c+=---
......coax%x@@@@@@@@@@@@@@@@@@@@@*c+==--
......-===cco#&@@@@@@@@@@@@@@@@@@@o+=---
......:====++oaW@@@@W@@@@@@@@@@@@@@+=---
.......--===++a@%@%*x@@@@@@@@@@@@@@+=---
.......-----==occccoo#@@@@@@@@@@@@a+=---
.......:-------=++++co%@@@@@@@@@@@c+----
.......:--------===++cW@#@@@@@@@@%a=---:
........:---------===+ccoa#@@@accc=---::
........::---------====++c&@@@c++==--:::
.........::----------====+c*@o+===--::::
..........:::---------===++%oa==---:::::
..........:::::----------==++=---:::::::
```

## 19. status {}

Where everything stands.

```
Bare STELLAR: VM1 Mandelbrot.lst
245.775 s of Elf2K time since power-on (92165575 machine cycles); the clock says 2026-11-09 12:04:05
The 1802 has stopped (IDL).
1802: P=1 X=3 D=00 DF=0 Q=0  next at FFF1: IDL
      R0=0025 R1=FFF1 R2=2FFE R3=02E3 R4=0340 R5=0360 R6=0000 R7=3200
      R8=4147 R9=317F RA=2F50 RB=3037 RC=3056 RD=0800 RE=3004 RF=0006
Keys typed and not yet read: 0
Card: 7 sectors written since it was baked.
STELLAR VMs (CIDP at $2F00):
  VM1: finished, core $3000, program $4000, 250204 commands run
  VM2: finished, core $3400, program $5000, 0 commands run
  VM3: finished, core $3800, program $6000, 0 commands run
  VM4: finished, core $3C00, program $7000, 0 commands run
```
