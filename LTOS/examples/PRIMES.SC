// PRIMES.SC - the prime numbers below 500, in Tiny Stellar C.
// On LTOS:  SC PRIMES  (makes PRIMES.STL), then  PRIMES  runs it.
const TOP = 500;
u16 n, d, count;

u16 isprime(u16 x) {
    if (x < 2) return 0;
    for (d = 2; d * d <= x; d++)
        if (x % d == 0) return 0;
    return 1;
}

void main() {
    count = 0;
    for (n = 2; n < TOP; n++) {
        if (isprime(n)) {
            printu(n); putc(' ');
            count++;
            if (count % 10 == 0) print("\r\n");
        }
    }
    print("\r\n"); printu(count); print(" primes below "); printu(TOP); print("\r\n");
}
