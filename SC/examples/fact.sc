// fact.sc - factorials. A u16 only holds up to 65535, so 8! = 40320 is the biggest that fits.
// For bigger ones we keep the answer as decimal digits in an array and multiply the way you do
// on paper: one digit at a time, carrying into the next.

const MAXD = 160;           // digits kept: enough for 100! (158 digits)
u8 dig[160];                // the answer, units digit first: dig[0] is the last digit printed
u8 line[8];                 // what you type
u16 len;                    // how many digits are in use

u16 small(u16 n) {          // the simple way: fine up to 8!
    u16 f;
    f = 1;
    while (n > 1) { f = f * n; n--; }
    return f;
}

void times(u16 m) {         // dig = dig * m
    u16 i, d, carry;
    carry = 0;
    for (i = 0; i < len; i++) {
        d = dig[i] * m + carry;     // at most 9 * 100 + 99: fits easily in a u16
        dig[i] = d % 10;            // keep the units...
        carry = d / 10;             // ...and carry the rest
    }
    while (carry > 0) {             // the carry makes the number longer
        dig[len] = carry % 10;
        carry = carry / 10;
        len++;
    }
}

void show() {               // print the digits, most important first
    u16 i;
    i = len;
    while (i > 0) { i--; putc('0' + dig[i]); }
}

void main() {
    u16 n, i, k;
    print("\r\nSmall ones, in a u16:\r\n");
    for (n = 0; n <= 8; n++) {
        printu(n); print("! = "); printu(small(n)); print("\r\n");
    }
    while (1) {
        print("\r\nN (0-100, Enter to stop)? ");
        k = getline(line);
        print("\r\n");
        if (k == 0) return;
        n = 0;                              // the typed digits -> a number
        for (i = 0; i < k; i++) {
            if (line[i] < '0' || line[i] > '9') { n = 999; break; }
            n = n * 10 + line[i] - '0';
        }
        if (n > 100) { print("0 to 100, please\r\n"); continue; }
        dig[0] = 1; len = 1;                // start at 1
        for (i = 2; i <= n; i++) times(i);  // then 1 x 2 x 3 x ... x n
        printu(n); print("! = "); show();
        print("\r\n("); printu(len); print(" digits)\r\n");
    }
}
