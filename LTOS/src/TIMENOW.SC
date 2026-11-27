// TIMENOW.SC - the Elf2K's own hardware: the clock chip, the Q line and the INPUT switch.
// rtc(n) reads the DS12887 clock (7: is there one?), q(n) sets Q (the Q lamp, a speaker on
// Q clicks), ef(4) is 1 while INPUT is held. The time is shown again each time the second
// changes, with a click on Q; hold INPUT to stop (getc() would wait, ef(4) does not).

void two(u16 v) { if (v < 10) putc('0'); printu(v); }   // 7 -> 07

void main() {
    u16 s, last = 99;
    if (!rtc(7)) { print("There is no clock chip on this Elf2K.\r\n"); halt(); }
    print("\e[2J\e[H THE ELF2K'S CLOCK - hold INPUT to stop\r\n\r\n");
    while (!ef(4)) {
        s = rtc(0);
        if (s != last) {
            last = s;
            print("\r "); printu(rtc(6)); putc('-'); two(rtc(5)); putc('-'); two(rtc(4));
            print("  "); two(rtc(2)); putc(':'); two(rtc(1)); putc(':'); two(s);
            print("  weekday "); printu(rtc(3)); print(" (0 = Sunday)  ");
            q(1); q(0);                         // a click
        }
    }
    print("\r\n\r\nStopped.\r\n");
}
