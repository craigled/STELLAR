// PIDIGITS.SC - the digits of pi by the "spigot" method (Rabinowitz and Wagon, 1995): pi is held as
// an array of small numbers in a mixed base, and each pass multiplies it by 10 and carries
// from the right to the left, letting one decimal digit drip out at the left end. Only
// whole numbers and only 16 bits are needed. A digit can still change if a carry comes later
// (a run of 9s turning into 0s), so a digit is printed only once it is certain.
// Every digit takes one pass over the whole array: more digits, a longer array, each slower.

const MAXD = 50;
const MAXN = 167;                               // 10 * MAXD / 3 + 1
u16 a[MAXN];

u16 readnum() {                                 // digits with echo; Backspace rubs one out; Enter ends
    u16 v = 0, len = 0, c;
    while (1) {
        c = getc();
        if (c == 13) break;
        if ((c == 8 || c == 127) && len) { len--; v = v / 10; print("\b \b"); }
        else if (c >= '0' && c <= '9' && len < 3) { putc(c); v = v * 10 + c - '0'; len++; }
    }
    print("\r\n");
    return v;
}

void main() {
    u16 d, n, i, j, k, m, x, q, pre = 10, nines = 0, shown = 0;
    print("\r\nPI BY THE SPIGOT - how many digits (10-50)? ");
    d = readnum();
    if (d < 10) d = 10;
    if (d > MAXD) d = MAXD;
    n = 10 * d / 3 + 1;
    for (i = 0; i < n; i++) a[i] = 2;           // 2 + 1/3 (2 + 2/5 (2 + 3/7 (2 + ...))) is pi
    print("\r\n");
    for (j = 0; j < d; j++) {
        q = 0;
        k = n - 1;                              // times 10, carried from the right
        m = 2 * n - 1;
        for (i = n; i > 0; i--) {               // a[k] (k = i - 1) is a digit in base m = 2i - 1
            x = 10 * a[k] + q * i;
            q = x / m;
            a[k] = x - q * m;                   // (the remainder: one division, not two)
            k--;
            m -= 2;
        }
        a[0] = q % 10;
        q = q / 10;                             // the digit that dripped out (10: carry one)
        if (q == 9) nines++;                    // a 9 waits: a carry may still turn it to 0
        else {
            if (pre != 10) {
                if (q == 10) pre++;
                putc('0' + pre % 10);
                if (shown == 0) putc('.');
                shown++;
            }
            while (nines) {
                if (q == 10) putc('0'); else putc('9');
                nines--;
            }
            if (q == 10) pre = 0; else pre = q;
        }
    }
    putc('0' + pre);
    print("\r\n");
}
