// vmtalk.sc - three VMs talking: main() runs the menu (VM1), worker() does sums (VM2),
// ticker() counts in the background (VM3).

chan job[4];                // main -> worker: a number to work on (one byte each)
shared u16 answer;          // worker -> main: the result
shared u8 done;             //  and a flag saying it is there
shared u16 ticks;           // ticker -> anyone: how far it has counted
shared u8 paused;           // main's note of whether ticker is stopped

task worker() {             // VM2: waits for a job, works it out, hands back the answer
    u16 n, i, sum;
    while (1) {
        n = recv(job);      // sleeps here until main sends something
        sum = 0;
        for (i = 1; i <= n; i++) sum += i;
        answer = sum;
        done = 1;           // main's wait() wakes up on this
    }
}

task ticker() {             // VM3: just keeps counting
    while (1) ticks++;
}

void main() {               // VM1: the menu, and the only one that uses the keyboard
    u16 k, n;
    while (1) {
        print("\r\n 1  add up 1..N (worker)\r\n 2  how far has ticker got?\r\n");
        print(" 3  pause / resume ticker\r\n Q  quit\r\nChoice? ");
        k = getc();
        if (k >= 'a' && k <= 'z') k = k - 'a' + 'A';
        putc(k); print("\r\n");
        switch (k) {
            case '1':
                print("N (0-9)? ");
                n = getc(); putc(n); print("\r\n"); n = n - '0';
                done = 0;
                send(job, n);       // hand the job over...
                wait(done == 1);    // ...and sleep until worker says it is finished
                print("  sum = "); printu(answer); print("\r\n");
                break;
            case '2':
                print("  ticks = "); printu(ticks); print("\r\n");
                break;
            case '3':
                if (paused) { start(ticker); paused = 0; print("  ticker running\r\n"); }
                else        { stop(ticker);  paused = 1; print("  ticker paused\r\n"); }
                break;
            case 'Q':
                print("Bye.\r\n");
                return;             // main ending ends every task
        }
    }
}
