// MOONLAND.SC - land on the moon, the way the 1969 teletype game played: every turn you choose
// how hard to burn the engine, then ten seconds pass. The moon pulls you 16 m/s faster each
// turn; each unit of fuel burned slows you by 1 m/s. Touch down at 5 m/s or less to land
// safely. Only whole numbers, never below 0: the speed is counted downwards and the engine
// is not strong enough to lift you, so a burn bigger than the speed just stops you.

u16 readnum() {                                 // digits with echo; Backspace rubs one out; Enter ends
    u16 v = 0, len = 0, c;
    while (1) {
        c = getc();
        if (c == 13) break;
        if ((c == 8 || c == 127) && len) { len--; v = v / 10; print("\b \b"); }
        else if (c >= '0' && c <= '9' && len < 3) { putc(c); v = v * 10 + c - '0'; len++; }
    }
    return v;
}

void col(u16 v, u16 w) {                        // v right-aligned in w columns
    u16 d = 1, t = v;
    while (t >= 10) { t = t / 10; d++; }
    while (d < w) { putc(' '); d++; }
    printu(v);
}

void main() {
    u16 alt, v, fuel, t, b, v2, fall, f, k;
    while (1) {
        alt = 6000; v = 60; fuel = 400; t = 0;
        print("\e[2J\e[H");
        print("LUNAR LANDER - you are 6000 m up, falling at 60 m/s, with 400 units of fuel.\r\n");
        print("Each turn: type a burn (0-40) and Enter. Land at 5 m/s or less.\r\n\r\n");
        print(" TIME  HEIGHT   SPEED   FUEL   BURN\r\n");
        while (alt > 0) {
            col(t, 5); col(alt, 8); col(v, 8); col(fuel, 7); print("    ");
            if (fuel == 0) { print("(none left)"); b = 0; }
            else {
                b = readnum();
                if (b > 40) b = 40;
                if (b > fuel) b = fuel;
            }
            print("\r\n");
            fuel -= b;
            v2 = v + 16;                        // the moon's pull
            if (b >= v2) v2 = 0; else v2 -= b;  // the engine (it cannot lift you)
            fall = (v + v2) / 2 * 10;           // ten seconds at the average speed
            if (fall >= alt) {                  // touch down during these ten seconds
                f = alt * 16 / fall;            // how far into the ten seconds, in sixteenths
                if (v2 >= v) v2 = v + (v2 - v) * f / 16;   // the speed at that moment (no number below 0,
                else v2 = v - (v - v2) * f / 16;           //  none over 65535: alt * 16 stays small here)
                alt = 0;
            } else alt -= fall;
            v = v2;
            t += 10;
        }
        print("\r\nTouch down at "); printu(t); print(" s, "); printu(v); print(" m/s: ");
        if (v <= 5) print("a perfect landing. Well done!");
        else if (v <= 15) print("a hard landing - the crew is shaken but safe.");
        else if (v <= 40) print("the lander is wrecked. You will wait a long time for a lift home.");
        else { print("a new crater, "); printu(v / 3); print(" m deep."); }
        print("\r\n\r\nAgain? (Y/N) ");
        k = getc();
        if (k != 'y' && k != 'Y') break;
    }
    print("\r\n");
}
