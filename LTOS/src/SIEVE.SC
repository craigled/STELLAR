// SIEVE.SC - an array: the Sieve of Eratosthenes. Every number starts as a maybe-prime; each
// prime crosses out its multiples. What is left uncrossed is prime.

const N = 600;
u16 crossed[N];                                 // arrays live outside the functions

void main() {
    u16 i, j, count;
    for (i = 2; i * i < N; i++) {
        if (!crossed[i]) {
            for (j = i * i; j < N; j += i) crossed[j] = 1;
        }
    }
    count = 0;
    for (i = 2; i < N; i++) {
        if (!crossed[i]) {
            printu(i);
            count++;
            if (count % 12 == 0) print("\r\n");
            else putc(' ');
        }
    }
    print("\r\n");
    printu(count);
    print(" primes below ");
    printu(N);
    print(".\r\n");
}
