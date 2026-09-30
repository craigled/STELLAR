// Front panel: drives the Elf2K's Q lamp and two-digit hex display from Stellar C.
// Stellar C has no built-in for either yet, so each is one line of asm { }:
//   OUTX 0{n}   the low byte of n to the output port - the hex display
//   SETQ 01/00  the Q lamp on / off

void main() {
    u16 n;
    print("Counting $00 to $3F on the front panel's display; Q blinks.\r\n");
    for (n = 0; n < 64; n++) {
        asm {
            OUTX 0{n}
        }
        if (n & 1) {
            asm {
                SETQ 01
            }
        } else {
            asm {
                SETQ 00
            }
        }
        delay(64);                 // about 8 counts a second at Elf2K speed
    }
    asm {
        SETQ 00
    }
    print("Done.\r\n");
}
