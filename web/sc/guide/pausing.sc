shared u16 ticks;

task clock() { while (1) ticks++; }       // counts in the background

void a_while() { u16 i; i = 0; while (i < 300) i++; }

void main() {
    u16 t;
    a_while();
    stop(clock);
    t = ticks; a_while();
    if (ticks == t) print("clock stopped\r\n");
    start(clock); a_while();
    if (ticks != t) print("clock running again\r\n");
}
