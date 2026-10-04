u16 i, total;

void main() {
    total = 0;
    i = 0;
    while (1) {
        i++;
        if (i > 20) break;
        if (i % 2 == 1) continue;
        total += i;
    }
    print("2 + 4 + ... + 20 = "); printu(total); print("\r\n");
}
