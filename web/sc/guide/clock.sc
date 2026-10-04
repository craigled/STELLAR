u8 t[8];

void main() {
    rtcget(t);
    print("Today is ");
    printu(t[6] * 256 + t[7]); putc('-'); printz(t[5], 2); putc('-'); printz(t[4], 2);
    print(", the time is ");
    printz(t[2], 2); putc(':'); printz(t[1], 2); putc(':'); printz(t[0], 2);
    print("\r\n");
}
