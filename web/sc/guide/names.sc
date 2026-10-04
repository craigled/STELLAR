u8 name[16];
u16 n, i;

void main() {
    print("Your name? ");
    n = getline(name);
    print("Hello, "); print(name); print(" - backwards: ");
    i = n;
    while (i > 0) { i--; putc(name[i]); }
    print("\r\n");
}
