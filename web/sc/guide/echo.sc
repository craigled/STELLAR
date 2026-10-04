u16 k, count;

void main() {
    print("Type, and press Enter: ");
    count = 0;
    while (1) {
        k = getc();
        if (k == '\r') break;
        if (k >= 'a' && k <= 'z') k = k - 'a' + 'A';
        putc(k);
        count++;
    }
    print("\r\n"); printu(count); print(" characters\r\n");
}
