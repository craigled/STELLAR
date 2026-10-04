u16 n, total;

void main() {
    n = 10; total = 0;
    asm {
    loop:
        ADDXYZ {total}{n} 0{total}     // total = total + n
        DECX 0{n}
        TESTXZ 0{n}
        IFFALSEI @loop
    }
    print("10 + 9 + ... + 1 = "); printu(total); print("\r\n");
}
