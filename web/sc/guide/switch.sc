u16 k, a, b;

void main() {
    a = 20; b = 4;
    while (1) {
        k = getc();
        switch (k) {
            case '+': printu(a + b); break;
            case '-': printu(a - b); break;
            case '*': printu(a * b); break;
            case '/': printu(a / b); break;
            case 'q': case 'x': print("bye"); return;
            default: print("?");
        }
        print(" ");
    }
}
