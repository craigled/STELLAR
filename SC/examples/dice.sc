// dice.sc - random numbers in Stellar C: rand() is STELLAR's RAND ($C3), a number 0 to 65535;
// rand(n) is 0 to n - 1 (rand() % n), so rand(6) + 1 is a die. A key press stirs it: rand() is
// called while the program waits, so the throws differ with how long you wait.
// The dice rattle on Q (a speaker or buzzer on it): q(1) then q(0) is one click, and the clicks come
// slower and slower as the dice settle. M turns the rattle off and on.
u16 counts[6];
u16 i;
u16 k;
u16 sound;

void rattle() {                                  // eight clicks, further and further apart
    u16 n, d, j;
    if (!sound) return;
    d = 2;
    for (n = 0; n < 8; n++) {
        q(1); q(0);
        for (j = 0; j < d; j++) { delay(1); }   // (delay takes a constant: d short waits)
        d = d + d / 2 + 1;
    }
}

void main() {
    sound = 1;
    print("Press a key to roll two dice (Q quits, S: 600 rolls, M: sound)\r\n");
    while (1) {
        while (!keyready()) { rand(); }          // stir while waiting
        k = getc();
        if (k == 'q' || k == 'Q') { print("Goodbye\r\n"); halt(); }
        if (k == 'm' || k == 'M') {
            sound = !sound;
            if (sound) print("Sound on\r\n"); else print("Sound off\r\n");
            continue;
        }
        if (k == 's' || k == 'S') {
            for (i = 0; i < 6; i++) { counts[i] = 0; }
            for (i = 0; i < 600; i++) { counts[rand(6)]++; }
            for (i = 0; i < 6; i++) { printu(i + 1); print(": "); printu(counts[i]); print("  "); }
            print("\r\n");
        } else {
            rattle();
            print("You rolled "); printu(rand(6) + 1); print(" and "); printu(rand(6) + 1); print("\r\n");
        }
    }
}
