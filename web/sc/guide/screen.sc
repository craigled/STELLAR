u16 r, n;

void main() {
    cls();
    at(1, 1); rev(1); print(" REPORT "); rev(0);
    at(3, 3); print("row   value   padded   hex");
    for (r = 0; r < 4; r++) {
        n = r * 1234 + 5;
        at(4 + r, 3); printu(r);
        at(4 + r, 9); printw(n, 5);
        at(4 + r, 17); printz(n, 5);
        at(4 + r, 26); printh(n);
    }
    at(9, 1);
}
