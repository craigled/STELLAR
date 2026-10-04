u16 gcd(u16 a, u16 b) {
    u16 t;
    while (b != 0) {
        t = a % b;
        a = b;
        b = t;
    }
    return a;
}

u16 isprime(u16 n) {
    u16 d;
    if (n < 2) return 0;
    for (d = 2; d * d <= n; d++)
        if (n % d == 0) return 0;
    return 1;
}

void main() {
    u16 n;
    print("gcd(1071, 462) = "); printu(gcd(1071, 462)); print("\r\n");
    print("primes below 40:");
    for (n = 1; n < 40; n++)
        if (isprime(n)) { print(" "); printu(n); }
    print("\r\n");
}
