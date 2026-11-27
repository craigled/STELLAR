// FUNCS.SC - functions: each takes numbers and gives one back with return. A function must
// come before the code that calls it.

u16 gcd(u16 a, u16 b) {                         // the greatest common divisor (Euclid)
    u16 t;
    while (b != 0) {
        t = a % b;
        a = b;
        b = t;
    }
    return a;
}

u16 power(u16 base, u16 e) {                    // base to the power e (it must fit in 65535)
    u16 r = 1;
    while (e > 0) {
        r = r * base;
        e--;
    }
    return r;
}

u16 isqrt(u16 n) {                              // the whole square root: the biggest r with r x r <= n
    u16 r = 0;
    while ((r + 1) * (r + 1) <= n && r < 255) r++;
    return r;
}

void show(u16 a, u16 b) {                       // a void function: it gives nothing back
    print("gcd(");
    printu(a);
    print(", ");
    printu(b);
    print(") = ");
    printu(gcd(a, b));
    print("\r\n");
}

void main() {
    u16 i;
    show(1802, 1806);
    show(144, 60);
    show(65535, 255);
    print("Powers of 2: ");
    for (i = 0; i <= 15; i++) {
        printu(power(2, i));
        putc(' ');
    }
    print("\r\nsqrt(1802) = ");
    printu(isqrt(1802));
    print(", sqrt(65535) = ");
    printu(isqrt(65535));
    print("\r\n");
}
