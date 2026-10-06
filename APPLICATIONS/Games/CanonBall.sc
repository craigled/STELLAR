// CANONBALL v02 - you against the computer. A Stellar C game for the STELLAR VM (Elf2K, VT100).
// Each side has a castle and a great cannon at its own end of the field. Take turns: raise or
// lower your barrel with the arrow keys and press SPACE to fire; then the computer fires back.
// The first castle knocked down (three quarters of its bricks gone) loses. The wind - shown
// in the status line - changes every game and pushes every ball the same way.
//
// The ball's position is fixed point: x in 1/256 of a column, yy in 1/256 of a row counting
// DOWN the screen, both with 128 added so that  col = x >> 8  and  row = yy >> 8  round to the
// nearest cell. A terminal row is about two columns tall, so the speed across is 2 x the sin
// table and the speed up 1 x. Each step: x += vx (+ the wind); yy -= vy; vy -= GY.
// Above the screen yy wraps round (row >= 200); off either side x >> 8 is 0 or > 80.
//
// The computer aims like a person: it watches where its last ball came down and corrects by
// part of a degree for each column it missed by, plus a wobble: easy 1/5 +-5, normal 1/3 +-3,
// hard 1/2 +-1 (tuned so a decent player beats it about 65% / 45% / 30% of the time).

const GROUND = 24;  const PR = 21;  const BLEN = 5;  const GY = 6;   const OFF = 200;
const CW = 10;      const TOTAL = 58; const FALLEN = 15; const MSG = 2; const SKY = 3;
const CXA = 2;      const PCA = 16;                   // your castle (columns 2-11) and cannon
const CXB = 69;     const PCB = 64;                   // the computer's (69-78, cannon at 64)
const TGA = 7;      const TGB = 73;                   // the middle of each castle: what is aimed at

u8 sint[] = { 0, 4, 9, 13, 18, 22, 27, 31, 35, 40, 44, 49, 53, 57, 62, 66, 70, 75, 79, 83,
    87, 91, 96, 100, 104, 108, 112, 116, 120, 124, 127, 131, 135, 139, 143, 146, 150, 153,
    157, 160, 164, 167, 171, 174, 177, 180, 183, 186, 190, 192, 195, 198, 201, 204, 206, 209,
    211, 214, 216, 219, 221, 223, 225, 227, 229, 231, 233, 235, 236, 238, 240, 241, 243, 244,
    245, 246, 247, 248, 249, 250, 251, 252, 253, 253, 254, 254, 254, 255, 255, 255, 255 };
u8 tens[] = "0000000000111111111122222222223333333333444444444455555555556666666666777777777788888888889999999999";
u8 ones[] = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789";
u8 h0[] = { 7, 7, 5, 5, 5, 5, 5, 5, 7, 7, 7, 7, 5, 5, 5, 5, 5, 5, 7, 7 };
u8 h[20];                                     // the two castles' columns: 0-9 yours, 10-19 the computer's
u8 trr[120];  u8 trc[120];                    // the last shot's trail (a shot is never 120 cells)
u8 ang[2];    u8 bang[2];                     // each side's angle, and the angle its barrel shows
u8 left[2];                                   // bricks still standing in each castle
u8 lvl;                                       // 1 easy, 2 normal, 3 hard
u16 ntr, land, row, col, wins, losses;
i16 wind;                                     // added to the ball's x every step

patched u8 ball[] = "\e[rr;ccH.\e[RR;CCHo";    // old cell gets a trail dot, new cell the ball
patched u8 one[]  = "\e[rr;ccHx";               // any single cell
patched u8 angs[] = "\e[01;30Haa";              // your angle in the status line
u8 title[] = "\e[0m\e[2J\e[?25l\e[04;32HC A N O N B A L L\e[07;14HYour castle stands on the left of the field, the computer's on\e[08;14Hthe right. Take turns firing your great cannons - the first\e[09;14Hcastle knocked down loses. Mind the wind!\e[12;24HUp / Down arrows (or W / S): aim\e[13;24HSPACE: fire        Q: quit\e[16;24HChoose:  1 Easy   2 Normal   3 Hard";
u8 bye[] = "\e[0m\e[2J\e[H\e[?25hThanks for playing CANONBALL.\r\n";

void quit() { print(bye); halt(); }

u16 kwait(u16 n) {                  // the next key within about n x 4 ms, or 0
    while (n != 0) { if (keyready()) return getc(); n--; }
    return 0;
}

u16 key(u16 k) {                    // key k: 'U' 'D' for aim, ' ' fire, 'Q' quit, else k itself
    if (k == 27) {
        k = kwait(8);
        if (k == '[') k = kwait(8);
    }
    if (k == 'A' || k == 'w' || k == 'W') return 'U';   // a lone 'A'/'B' is an arrow that lost its ESC [
    if (k == 'B' || k == 's' || k == 'S') return 'D';
    if (k == 'q') return 'Q';
    return k;
}

u16 anykey() {                      // wait for a key, stirring rand(); Q quits
    u16 k;
    while (!keyready()) rand();
    k = key(getc());
    if (k == 'Q') quit();
    return k;
}

void cell(u16 r, u16 c, u16 ch) {   // one character at row r, column c
    one[2] = tens[r]; one[3] = ones[r];
    one[5] = tens[c]; one[6] = ones[c];
    one[8] = ch;
    print(one);
}

void say(u16 s, u16 m) {            // what a shot did: side s, result m
    at(MSG, 1); eol();
    if (m == 0) return;
    at(MSG, 22);
    if (s) print("The computer's shot: "); else print("Your shot: ");
    switch (m) {
        case 1: print("too short."); break;
        case 2: print("too long."); break;
        case 3: print("right off the field!"); break;
        case 4: rev(1); print(" H I T ! "); rev(0); break;
        case 5: if (s) print("oops - its own castle!"); else print("oops - your own castle!"); break;
    }
}

void showang() {
    u16 a;
    a = ang[0];
    angs[8] = tens[a]; angs[9] = ones[a];
    rev(1); print(angs); rev(0);
}

void status() {
    u16 w, a, k;
    at(1, 1); rev(1);
    print(" CANONBALL   You "); printw(left[0] * 100 / TOTAL, 3);
    print("%  Angle "); printz(ang[0], 2);
    print("   Wind ");
    if (wind == 0) print("calm");
    else {
        if (wind < 0) { w = -wind; a = '<'; } else { w = wind; a = '>'; }
        w = w / 8;
        for (k = 0; k < 4; k++) { if (k < w) putc(a); else putc(' '); }
    }
    print("     Computer "); printw(left[1] * 100 / TOTAL, 3);
    print("%        Q quit ");
    rev(0);
}

void barrel(u16 s, u16 ch) {        // side s's barrel at angle bang[s] (ch = ' ' rubs it out)
    u16 r, dc, dr, cs, sn, a;
    a = bang[s];
    if (ch != ' ') {
        if (a < 23) ch = '-';
        else if (a >= 68) ch = '|';
        else if (s) ch = '\\'; else ch = '/';
    }
    one[8] = ch;
    cs = sint[90 - a]; sn = sint[a];
    dc = 128; dr = PR * 512 + 256;
    for (r = 0; r < BLEN; r++) {
        dc += cs; dr -= sn;         // r x cos (in 1/256 col) and r x sin (in 1/512 row), rounded
        a = dr >> 9;
        one[2] = tens[a]; one[3] = ones[a];
        a = dc >> 8;
        if (s) a = PCB - a; else a = PCA + a;
        one[5] = tens[a]; one[6] = ones[a];
        print(one);
    }
}

void cannon(u16 s) {                // side s's cannon, its barrel where it was last drawn
    u16 c;
    if (s) c = PCB - 1; else c = PCA - 3;
    at(PR + 1, c); print("/###\\");
    at(PR + 2, c); print("(O)(O)");
    barrel(s, '#');
}

void aim(u16 s) {                   // move side s's barrel to its chosen angle
    barrel(s, ' '); bang[s] = ang[s]; barrel(s, '#');
}

void castle(u16 s) {
    u16 r, c, k, b;
    if (s) { b = CW; c = CXB; } else { b = 0; c = CXA; }
    for (r = GROUND - 7; r < GROUND; r++) {
        at(r, c);
        for (k = 0; k < CW; k++) {
            if (h[b + k] >= GROUND - r) { if (k & 1) putc(']'); else putc('['); }
            else putc(' ');
        }
    }
}

void scene() {
    u16 c;
    cls(); cursor(0);
    at(GROUND, 1);
    for (c = 0; c < 80; c++) putc('=');
    cannon(0); cannon(1);
    castle(0); castle(1);
    status();
}

void blast(u16 hc) {                // knock bricks off the columns round h[hc]: 3 2 1, in its castle
    u16 k, a, d, b, s;
    if (hc >= CW) s = 1; else s = 0;
    b = s * CW;
    for (k = b; k < b + CW; k++) {
        if (k + 2 >= hc && k <= hc + 2) {
            if (k > hc) d = k - hc; else d = hc - k;
            a = 3 - d;
            if (h[k] < a) a = h[k];
            h[k] -= a;
            left[s] -= a;
        }
    }
}

void erasetrail() {
    u16 i;
    for (i = 0; i < ntr; i++) cell(trr[i], trc[i], ' ');
    ntr = 0;
}

u16 hidx(u16 c) {                   // the h[] index of castle column c, or 99 if c is not in a castle
    if (c >= CXA && c < CXA + CW) return c - CXA;
    if (c >= CXB && c < CXB + CW) return c - (CXB - CW);
    return 99;
}

u16 fly(u16 s) {                    // side s fires: returns 1 short, 2 long, 3 off the field, 10 + h[] index: a hit
    u16 t, x, yy, r, c, or, oc, m, n;
    i16 vx, vy;
    t = ang[s]; vx = sint[90 - t]; vy = sint[t];
    t = (BLEN + 1) * vx;
    if (s) { x = (PCB * 256 + 128) - t; vx = -vx; }
    else   x = t + (PCA * 256 + 128);
    t = (BLEN + 1) * vy;
    t = t >> 1;
    yy = (PR * 256 + 128) - t;
    vx = vx + vx + wind;
    or = 0; oc = 0; m = 0; n = 0;
    while (1) {
        x += vx; yy -= vy; vy -= GY;
        c = x >> 8; r = yy >> 8;
        if (c == 0 || c > 80) { m = 3; break; }
        if (r < OFF) {
            if (r >= GROUND) {                      // down on the field: short or long of the target
                m = 1;
                if (s) { if (c < TGA) m = 2; } else { if (c > TGB) m = 2; }
                break;
            }
            if (c < CXA + CW + 1 || c + 1 >= CXB) {  // near a castle: this column and the one passed
                t = hidx(c);
                if (t != 99) { if (r + h[t] >= GROUND) { m = t + 10; break; } }
                if (vx > 0) t = hidx(c - 1); else t = hidx(c + 1);
                if (t != 99) { if (r + h[t] >= GROUND) { m = t + 10; break; } }
            }
            if (r >= SKY) {
                if (r != or || c != oc) {
                    ball[11] = tens[r]; ball[12] = ones[r];
                    ball[14] = tens[c]; ball[15] = ones[c];
                    if (or == 0) copy(&ball[2], &ball[11], 5);
                    print(ball);
                    copy(&ball[2], &ball[11], 5);
                    trr[n] = r; trc[n] = c; n++;
                    or = r; oc = c;
                }
                continue;
            }
        }
        if (or != 0) { cell(or, oc, '.'); or = 0; }  // gone off the top
    }
    if (or != 0) cell(or, oc, '.');                  // the ball's last cell joins the trail
    row = r; col = c; land = c; ntr = n;
    if (m == 3) { if (c == 0 || c >= OFF) land = 0; else land = 81; }
    return m;
}

u16 shot(u16 s) {                   // side s fires; returns the result for say()
    u16 m, t;
    say(s, 0);
    erasetrail();
    cannon(0); cannon(1);
    aim(s);
    m = fly(s);
    if (m >= 10) {
        t = m - 10;
        cell(row, col, '*'); cell(row - 1, col, '*');
        cell(row, col - 1, '*'); cell(row, col + 1, '*');
        delay(60);
        cell(row, col, ' '); cell(row - 1, col, ' '); cell(row, col - 1, ' '); cell(row, col + 1, ' ');
        blast(t);
        if (t >= CW) castle(1); else castle(0);
        m = 4;
        if (t >= CW && s) m = 5;                     // its own castle
        if (t < CW && s == 0) m = 5;
    } else if (m != 3) {
        cell(GROUND - 1, land, '*'); delay(30); cell(GROUND - 1, land, ' ');
    }
    say(s, m);
    cannon(0); cannon(1);
    status();
    return m;
}

void player() {                     // your turn: aim, then SPACE
    u16 k;
    at(MSG + 1, 1); eol(); at(MSG + 1, 30); print("Your turn - aim and fire!");
    while (1) {
        k = kwait(25);                  // the barrel catches up once the keys stop
        if (k == 0) {
            if (bang[0] != ang[0]) aim(0);
            k = anykey();
        } else k = key(k);
        if (k == 'Q') quit();
        if (k == 'U' && ang[0] < 90) { ang[0]++; showang(); }
        if (k == 'D' && ang[0] > 0)  { ang[0]--; showang(); }
        if (k == ' ') break;
    }
    at(MSG + 1, 1); eol();
    shot(0);
}

void computer() {                   // the computer's turn
    u16 m;
    i16 a, e, j;
    at(MSG + 1, 1); eol(); at(MSG + 1, 30); print("The computer is aiming...");
    delay(150);
    m = shot(1);
    at(MSG + 1, 1); eol();
    // where did it land, against the middle of your castle? (a ball that came down
    // to the right of the target - nearer the computer - was short: raise the barrel)
    e = land;
    e = e - TGA;
    if (lvl == 1)      { e = e / 5; j = rand() % 11; j = j - 5; }   // easy: a fifth, +-5 wobble
    else if (lvl == 2) { e = e / 3; j = rand() % 7;  j = j - 3; }   // normal: a third, +-3
    else               { e = e / 2; j = rand() % 3;  j = j - 1; }   // hard: a half, +-1
    if (e > 12) e = 12;
    if (e < -12) e = -12;
    a = ang[1];
    a = a + e + j;
    if (a < 5) a = 5;
    if (a > 45) a = 45;
    ang[1] = a;
}

u16 over() {                        // is a castle down? 1 you won, 2 the computer won, 0 not yet
    if (left[1] <= FALLEN) return 1;
    if (left[0] <= FALLEN) return 2;
    return 0;
}

void play() {
    u16 k, w;
    copy(&h[0], &h0[0], 2 * CW);
    left[0] = TOTAL; left[1] = TOTAL; ntr = 0;
    ang[0] = 45; bang[0] = 45;
    k = 15 + rand() % 30;
    ang[1] = k; bang[1] = k;
    w = rand() % 7;
    wind = w; wind = wind - 3; wind = wind * 8;
    scene();
    while (1) {
        player();
        w = over(); if (w) break;
        computer();
        w = over(); if (w) break;
    }
    at(MSG + 1, 1); eol();
    at(MSG, 1); eol(); at(MSG, 20); rev(1);
    if (w == 1) { print("  YOU WIN!  The computer's castle has fallen.  "); wins++; }
    else        { print("  The computer wins - your castle has fallen.  "); losses++; }
    rev(0);
    at(MSG + 1, 22); print("You "); printu(wins); print(" - Computer "); printu(losses);
    print("     SPACE: play again   Q: quit");
    for (k = 40; k != 0; k--) { if (keyready()) getc(); delay(12); }
    while (anykey() != ' ') { }
    at(MSG + 1, 1); eol();
}

void main() {
    u16 k;
    wins = 0; losses = 0;
    print(title);
    while (1) {
        k = anykey();
        if (k >= '1' && k <= '3') break;
    }
    lvl = k - '0';
    while (1) play();
}
