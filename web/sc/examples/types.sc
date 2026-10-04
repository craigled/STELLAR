// 16-bit arrays, signed (i16) arithmetic and switch - checked by types_verify.py against Python.
const N = 7;
i16 v[] = { -32768, -1000, -1, 0, 1, 999, 32767 };
u16 big[] = { 1000, 2000, 65535, 0, 12345 };
u16 sq[10];
i16 neg[4];
i16 dv[] = { -7, 3, -1, 32767 };
u16 i, j, total, r;
i16 a, b, x;
u8 txt[] = "ai 09xu2b!e";

u16 kind(u16 k) {
    u16 r;
    r = 0;
    switch (k) {
        case 'a': case 'e': case 'i': case 'o': case 'u': r = 1; break;      // vowels
        case ' ': r = 2; break;
        case '0': case '1': case '2': r = 3;                                  // falls through
        case '9': r = r + 10; break;
        default: r = 9;
    }
    return r;
}

void main() {
    // 16-bit arrays: read, sum, write, &a[i]
    total = 0; i = 0;
    while (i < 5) { total += big[i] / 10; i++; }
    printu(total); putc(' '); printu(big[2]); putc(' '); printu(big[4]);
    i = 0;
    while (i < 10) { sq[i] = i * i * 300; i++; }
    putc(' '); printu(sq[9]); putc(' '); printu(sq[3] + sq[4]);
    neg[0] = -5; neg[3] = -32000; i = 3;
    putc(' '); printi(neg[0]); putc(' '); printi(neg[i]);
    putc(' '); printu(&sq[3] - &sq[0]);
    print("\r\n");
    // signed compares: every pair, four bits each: <  <=  >  >=
    i = 0;
    while (i < N) {
        j = 0;
        while (j < N) {
            a = v[i]; b = v[j];
            r = '0';
            if (a < b) r += 1;
            if (a <= b) r += 2;
            if (a > b) r += 4;
            if (a >= b) r += 8;
            putc(r);
            j++;
        }
        i++;
    }
    print("\r\n");
    // signed / % >> printi
    i = 0;
    while (i < N) {
        a = v[i];
        printi(a / 7); putc(','); printi(a % 7); putc(','); printi(a / -3); putc(','); printi(a % -3); putc(',');
        printi(a >> 1); putc(','); printi(a >> 3); putc(' ');
        i++;
    }
    print("\r\n");
    // a signed divide inside a bigger expression (temporaries kept across the library call), variable divisors
    i = 0;
    while (i < N) {
        j = 0;
        while (j < 4) {
            a = v[i]; b = dv[j];
            x = a % b + (a / b) / 2;
            printi(x); putc(' ');
            j++;
        }
        i++;
    }
    print("\r\n");
    // switch, and break / continue inside one in a loop
    i = 0;
    total = 0;
    while (i < 12) {
        j = txt[i];
        switch (j) {
            case 'x': i++; continue;          // continue: the loop's next turn
            case '!': break;                  // break: out of the switch only
        }
        putc('0' + kind(j));
        i++;
    }
    print("\r\n");
}
