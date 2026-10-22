// stop(t) / start(t) (Stellar C multitasking): four VMs check themselves and print what they saw.
//   counter()  VM2  counts; main() stops it, sees the count hold still, starts it again
//   sleeper()  VM3  waits for go; stopped, a write to go does not wake it - started, it wakes
//   self()     VM4  prints A, stops itself, prints B only when main() starts it
// Expected: A / runs / stopped / runs again / no wake while stopped / woke / started / B
shared u16 adds;
shared u8 go;
task counter() { while (1) adds++; }
task sleeper() { while (1) { wait(go != 0); go = 0; print("woke\r\n"); } }
task self() { print("A\r\n"); stop(self); print("B\r\n"); }
void spin() { u16 i; i = 0; while (i < 300) i++; }
void main() {
    u16 a;
    spin();
    a = adds; spin(); if (adds != a) print("runs\r\n");
    stop(counter); spin();
    a = adds; spin(); if (adds == a) print("stopped\r\n");
    start(counter); spin();
    if (adds != a) print("runs again\r\n");
    stop(sleeper); go = 1; spin(); spin();
    if (go == 1) print("no wake while stopped\r\n");
    start(sleeper); spin(); spin();
    if (go == 0) print("started\r\n");
    start(self); spin();
}
