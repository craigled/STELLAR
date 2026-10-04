u16 x, y, k;

u16 key() {                     // a key: 'U' 'D' 'L' 'R' for the arrows, 0 if none
    if (!keyready()) return 0;
    k = getc();
    if (k != 27) return k;      // not ESC: an ordinary key
    k = getc();
    if (k == '[') k = getc();   // ESC [ A ... - the '[' may have been lost (see below)
    switch (k) {
        case 'A': return 'U';
        case 'B': return 'D';
        case 'C': return 'R';
        case 'D': return 'L';
    }
    return 0;
}

void main() {
    x = 10; y = 5;
    cls(); cursor(0);
    at(1, 1); print("Arrows move the star, q quits");
    while (1) {
        at(y, x); putc('*');
        delay(10);
        k = key();
        if (k == 'q') break;
        if (k == 0) continue;
        at(y, x); putc(' ');
        switch (k) {
            case 'U': if (y > 2) y--; break;
            case 'D': if (y < 23) y++; break;
            case 'L': if (x > 1) x--; break;
            case 'R': if (x < 79) x++; break;
        }
    }
    cursor(1); at(24, 1);
}
