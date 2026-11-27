// GUESS.SC - a game: guess the number from 1 to 100. getc() reads one key; readnum() builds a
// number from the digits typed. The secret number comes from the keys you type first: a
// simple random-number generator (x = x * 75 + 74) is stirred by them.

u16 seed = 1802;

u16 rnd() {
    seed = seed * 75 + 74;                      // (65535 wraps round to 0: the numbers are 16 bits)
    return seed;
}

u16 readnum() {                                 // digits with echo; Backspace rubs one out; Enter ends
    u16 v = 0;
    u16 len = 0;
    u16 c;
    while (1) {
        c = getc();
        if (c == 13) break;
        if (c == 8 || c == 127) {
            if (len != 0) { len--; v = v / 10; print("\b \b"); }
        } else if (c >= '0' && c <= '9' && len < 4) {
            putc(c);
            v = v * 10 + c - '0';
            len++;
        }
    }
    print("\r\n");
    return v;
}

void main() {
    u16 c, secret, guess, tries;
    print("GUESS THE NUMBER\r\n\r\nType your name and press Enter: ");
    while (1) {                                 // each key stirs the generator
        c = getc();
        if (c == 13) break;
        putc(c);
        seed = seed * 31 + c;
    }
    secret = rnd() % 100 + 1;
    print("\r\nI have a number from 1 to 100.\r\n");
    tries = 0;
    while (1) {
        print("Your guess: ");
        guess = readnum();
        tries++;
        if (guess < secret) print("Too low.\r\n");
        else if (guess > secret) print("Too high.\r\n");
        else break;
    }
    print("Right! It was ");
    printu(secret);
    print(" - you took ");
    printu(tries);
    print(" tries.\r\n");
}
