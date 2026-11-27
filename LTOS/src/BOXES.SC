// BOXES.SC - the screen: putc() sends one character, and ESC sequences (\e[ ...) move the
// cursor, as the VT100 terminal understands them. Draws a box and a diamond, then waits.

void at(u16 row, u16 col) {                     // the cursor to row, col: ESC [ row ; col H
    print("\e[");
    printu(row);
    putc(';');
    printu(col);
    putc('H');
}

void box(u16 top, u16 left, u16 h, u16 w) {     // corners +, sides | and -
    u16 i;
    at(top, left);
    putc('+');
    for (i = 2; i < w; i++) putc('-');
    putc('+');
    for (i = 1; i < h - 1; i++) {
        at(top + i, left);
        putc('|');
        at(top + i, left + w - 1);
        putc('|');
    }
    at(top + h - 1, left);
    putc('+');
    for (i = 2; i < w; i++) putc('-');
    putc('+');
}

void diamond(u16 row, u16 col, u16 size) {      // rows of stars, wider then narrower
    u16 i, j, n;
    for (i = 0; i < size * 2 - 1; i++) {
        if (i < size) n = i;
        else n = size * 2 - 2 - i;
        at(row + i, col - n);
        for (j = 0; j <= n * 2; j++) putc('*');
    }
}

void main() {
    print("\e[2J");                             // the screen cleared
    box(2, 5, 9, 30);
    at(6, 11);
    print("Tiny Stellar C");
    box(4, 40, 14, 30);
    diamond(5, 55, 6);
    at(20, 5);
    print("Press a key...");
    getc();
    print("\e[2J\e[H");
}
