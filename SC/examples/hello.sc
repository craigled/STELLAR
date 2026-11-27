// Hello, with the terminal built-ins: a title bar, your name (a bounded getline),
// the date and time from the RTC, and the three number formats.
u8 name[21];
u8 t[8];
u16 n, i;

void main() {
    cls(); cursor(0);
    at(1, 1); rev(1); print("  STELLAR C  -  hello, terminal                                                "); rev(0);
    at(4, 10); print("What is your name? "); cursor(1);
    n = getline(name);
    cursor(0);
    if (n == 0) { at(6, 10); print("No name? Then hello, stranger."); }
    else { at(6, 10); print("Hello, "); rev(1); print(name); rev(0); print("! That is "); printu(n); print(" letters."); }
    rtcget(t);
    at(8, 10); print("It is ");
    printu((t[6] << 8) + t[7]); putc('-'); printz(t[5], 2); putc('-'); printz(t[4], 2);
    print(" at "); printz(t[2], 2); putc(':'); printz(t[1], 2); putc(':'); printz(t[0], 2);
    at(10, 10); print("Numbers   printu  printz(e,5)  printw(e,5)  printh(e)");
    i = 0;
    while (i < 4) {
        at(11 + i, 10); print("          ");
        n = 7 + i * 1234;
        printu(n); at(11 + i, 28); printz(n, 5); at(11 + i, 41); printw(n, 5); at(11 + i, 54); printh(n);
        i++;
    }
    at(16, 10); cursor(1);
}
