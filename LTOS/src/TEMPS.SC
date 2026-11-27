// TEMPS.SC - whole-number arithmetic: a Fahrenheit to Celsius table. The numbers here are
// 0 to 65535 (no minus), so below 32 F the sum is done the other way round and a - printed.
// Dividing last keeps the most accuracy: (f - 32) x 5 / 9.

void main() {
    u16 f;
    print("   F      C\r\n");
    for (f = 0; f <= 220; f += 10) {
        if (f < 100) putc(' ');
        if (f < 10) putc(' ');
        printu(f);
        print("    ");
        if (f < 32) {
            putc('-');
            printu((32 - f) * 5 / 9);
        } else {
            printu((f - 32) * 5 / 9);
        }
        print("\r\n");
    }
    print("Water boils at 212 F = 100 C.\r\n");
}
