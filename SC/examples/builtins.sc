// Every terminal / number / input / RTC / memory built-in, once - checked by builtins_verify.py.
u8 name[11];
u8 t[8];
u16 n, r, c;

void main() {
    cls();
    at(2, 5); rev(1); print("Stellar C built-ins"); rev(0); eol();
    r = 4; c = 7;
    at(r, c); print("at(4, 7)");
    at(6, 1); printz(42, 5); putc(' '); printz(7, 2); putc(' '); printz(123, 2);
    at(7, 1); putc('['); printw(42, 5); putc(']'); putc('['); printw(0, 3); putc(']');
    at(8, 1); printh(48879); putc(' '); printh(10, 2); putc(' '); printh(255, 1);
    at(9, 1); print("Name? "); n = getline(name, 10);
    at(10, 1); print("Hello, "); print(name); print("! "); printu(n); print(" letters");
    rtcget(t);
    at(11, 1); printu((t[6] << 8) + t[7]); putc('-'); printz(t[5], 2); putc('-'); printz(t[4], 2);
    putc(' '); printz(t[2], 2); putc(':'); printz(t[1], 2); putc(':'); printz(t[0], 2);
    t[0] = 0; t[1] = 30; t[2] = 9; t[4] = 25; t[5] = 12; t[6] = 7; t[7] = 234;     // 2026-12-25 09:30:00
    n = rtcset(t);
    at(12, 1); print("set "); printu(n);
    t[4] = 31; t[5] = 2;                                                            // 31 February: refused
    n = rtcset(t);
    print(" bad "); printu(n);
    poke(26368, 171); pokew(26370, 4660);                                           // $6700 = $AB, $6702 = $1234
    at(13, 1); printh(peek(26368), 2); putc(' '); printh(peekw(26370));
    cursor(0); cursor(1);
    at(14, 1);
}
