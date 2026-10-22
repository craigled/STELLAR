shared u16 total;
shared u8 finished;

task helper() {
    u16 i;
    for (i = 0; i < 500; i++) total++;
    finished = 1;
}

void main() {
    u16 i;
    for (i = 0; i < 500; i++) total++;
    wait(finished == 1);
    printu(total); print("\r\n");
}
