u8  line[6];
u16 secret, guess, tries, n, i, ok;

u16 number() {                  // the digits typed, as a number (65535 if there are none)
    n = 0; ok = 0;
    for (i = 0; line[i] != 0; i++)
        if (line[i] >= '0' && line[i] <= '9') { n = n * 10 + line[i] - '0'; ok = 1; }
    if (!ok) return 65535;
    return n;
}

void main() {
    while (1) {
        secret = rand() % 100 + 1;
        tries = 0;
        print("\r\nI have a number from 1 to 100.\r\n");
        while (1) {
            print("Your guess? ");
            getline(line);
            guess = number();
            if (guess == 65535) continue;
            tries++;
            if (guess < secret) print("  higher\r\n");
            else if (guess > secret) print("  lower\r\n");
            else break;
        }
        print("Yes! "); printu(secret); print(" in "); printu(tries); print(" tries.\r\n");
        print("Again (y/n)? ");
        getline(line);
        switch (line[0]) {
            case 'y': case 'Y': continue;
        }
        print("Bye.\r\n");
        return;
    }
}
