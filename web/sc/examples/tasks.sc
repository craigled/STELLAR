// Three tasks at once (Stellar C multitasking): one file, three VMs.
//   main()      VM1  prints each key with the running total, until q
//   keyboard()  VM2  owns the keyboard: every key goes into the queue
//   counter()   VM3  counts in the background
shared u16 total;            // one copy, seen by every task
shared u16 adds;             // how many times counter() has added
chan keys[8];                // bytes from keyboard() to main()

task keyboard() {
    u16 k;
    while (1) {
        k = getc();          // getc() lets the other VMs run while it waits
        send(keys, k);       // into the queue (waits if it is full)
        if (k == 'q') return;
    }
}

task counter() {
    while (1) {
        total++;             // read-modify-write of shared data: made one step by the compiler
        adds++;
    }
}

void main() {
    u16 k;
    print("type; q quits\r\n");
    while (1) {
        k = recv(keys);      // asleep until a key arrives
        if (k == 'q') break;
        atomic { putc(k); print(" total "); printu(total); print("\r\n"); }
    }
    print("bye\r\n");
}
