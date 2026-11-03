// dice.sc - random numbers in Stellar C: rand() is STELLAR's RAND ($C3), a number 0 to 65535;
// rand(n) is 0 to n - 1 (rand() % n), so rand(6) + 1 is a die. A key press stirs it: rand() is
// called while the program waits, so the throws differ with how long you wait.
u16 counts[6];
u16 i;
u16 k;

void main() {
    print("Press a key to roll two dice (Q quits, S: 600 rolls)\r\n");
    while (1) {
        while (!keyready()) { rand(); }          // stir while waiting
        k = getc();
        if (k == 'q' || k == 'Q') { halt(); }
        if (k == 's' || k == 'S') {
            for (i = 0; i < 6; i++) { counts[i] = 0; }
            for (i = 0; i < 600; i++) { counts[rand(6)]++; }
            for (i = 0; i < 6; i++) { printu(i + 1); print(": "); printu(counts[i]); print("  "); }
            print("\r\n");
        } else {
            print("You rolled "); printu(rand(6) + 1); print(" and "); printu(rand(6) + 1); print("\r\n");
        }
    }
}
