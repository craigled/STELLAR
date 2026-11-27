// Front panel: drives the Elf2K's Q lamp and two-digit hex display from Stellar C.
//   out(n)  the low byte of n to the output port - the hex display (port 4 unless outport())
//   q(on)   the Q lamp: 0 off, 1 on (any other value: on if it is not zero)

void main() {
    u16 n;
    print("Counting $00 to $3F on the front panel's display; Q blinks.\r\n");
    for (n = 0; n < 64; n++) {
        out(n);
        q(n & 1);
        delay(64);                 // about 8 counts a second at Elf2K speed
    }
    q(0);
    print("Done.\r\n");
}
