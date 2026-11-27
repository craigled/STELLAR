// COUNT.SC - loops: for counts up, while counts down; one loop inside another makes a table.

void main() {
    u16 i, j;
    print("Up:   ");
    for (i = 1; i <= 10; i++) {
        printu(i);
        putc(' ');
    }
    print("\r\nDown: ");
    i = 10;
    while (i > 0) {
        printu(i);
        putc(' ');
        i--;
    }
    print("\r\n\r\nThe times table:\r\n");
    for (i = 1; i <= 9; i++) {
        for (j = 1; j <= 9; j++) {
            if (i * j < 10) putc(' ');          // two places a number, so the columns line up
            putc(' ');
            printu(i * j);
        }
        print("\r\n");
    }
}
