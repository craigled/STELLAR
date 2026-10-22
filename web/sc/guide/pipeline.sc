chan raw[8];                // keys, from keyboard() to upper()
chan done[8];               // capital letters, from upper() to main()
shared u16 letters;         // how many letters upper() changed

task keyboard() {           // VM2: owns the keyboard
    u16 k;
    while (1) {
        k = getc();
        send(raw, k);
        if (k == '\r') return;
    }
}

task upper() {              // VM3: does the work
    u16 k;
    while (1) {
        k = recv(raw);
        if (k >= 'a' && k <= 'z') { k = k - 32; letters++; }
        send(done, k);
        if (k == '\r') return;
    }
}

void main() {               // VM1: shows the result
    u16 k;
    print("type a line: ");
    while (1) {
        k = recv(done);
        if (k == '\r') break;
        putc(k);
    }
    print("\r\n"); printu(letters); print(" letters changed\r\n");
}
