// Sieve of Eratosthenes: every prime below 2000, ten to a line, then a count.
// Exercises byte arrays (READIDX / WRITEIDX), arguments, && and || and nested calls.

const N = 2000;
u8 composite[N];                     // written -> zeroed in code at every start (rerun-safe)
u8 hello[] = "Sieve of Eratosthenes, primes below ";
u16 count = 0;

u16 max(u16 a, u16 b) { if (a > b) return a; return b; }
u16 square(u16 x) { return x * x; }

void show(u16 p) {
    printu(p);
    count++;
    if (count % 10 == 0) print("\r\n"); else putc(' ');
}

void main() {
    u16 i, j;
    print(hello);
    printu(N);
    print(":\r\n");
    for (i = 2; square(i) < N; i++) {
        if (composite[i] == 0) {
            for (j = square(i); j < N; j += i) composite[j] = 1;
        }
    }
    for (i = 2; i < N; i++) if (!composite[i] && i != 0 || i == 2 && composite[i] == 0) show(i);
    print("\r\n");
    printu(count);
    print(" primes. max(7, 9) + max(max(1, 2), square(3)) = ");
    printu(max(7, 9) + max(max(1, 2), square(3)));
    print("\r\n");
}
