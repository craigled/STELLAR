// CANONBALL v01 (solo) - a Stellar C game for the STELLAR VM (Elf2K, VT100 terminal).
// Raise or lower the big cannon's barrel with the arrow keys, press SPACE to fire,
// and knock down the castle on the far side of the field.
//
// The ball's position is fixed point: x in 1/256 of a column, yy in 1/256 of a row,
// counting DOWN the screen, both with 128 added so that  col = x >> 8  and  row = yy >> 8
// round to the nearest cell (and a >> 8 is one cheap STELLAR command). A terminal row is
// about two columns tall, so the speed across is 2 x sin-table and the speed up 1 x.
// Each step: x += vx; yy -= vy; vy -= GY. Above the screen yy wraps round (row >= 200).
// The castle is ten columns of bricks; a hit knocks bricks off the columns round it and
// the castle falls when three quarters of its bricks are gone.

const GROUND = 24;  const PR = 21;  const PC = 7;   const BLEN = 5;
const CW = 10;      const GY = 6;   const TOTAL = 58; const FALLEN = 15;
const MSG = 2;      const SKY = 3;  const OFF = 200;

u8 sint[] = { 0, 4, 9, 13, 18, 22, 27, 31, 35, 40, 44, 49, 53, 57, 62, 66, 70, 75, 79, 83,
    87, 91, 96, 100, 104, 108, 112, 116, 120, 124, 127, 131, 135, 139, 143, 146, 150, 153,
    157, 160, 164, 167, 171, 174, 177, 180, 183, 186, 190, 192, 195, 198, 201, 204, 206, 209,
    211, 214, 216, 219, 221, 223, 225, 227, 229, 231, 233, 235, 236, 238, 240, 241, 243, 244,
    245, 246, 247, 248, 249, 250, 251, 252, 253, 253, 254, 254, 254, 255, 255, 255, 255 };
u8 tens[] = "0000000000111111111122222222223333333333444444444455555555556666666666777777777788888888889999999999";
u8 ones[] = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789";
u8 h0[] = { 7, 7, 5, 5, 5, 5, 5, 5, 7, 7 };   // the castle's columns, in bricks
u8 h[10];                                     // what is left of them
u8 trr[120];  u8 trc[120];                    // the last shot's trail (a shot is never 120 cells)
u16 ntr, shots, cx, land, row, col;
u8 left;                                      // bricks still standing
u8 ang, bang;                                 // the angle chosen, and the one the barrel shows

// strings the program fills in before printing ('patched': no restore needed on a rerun)
patched u8 ball[] = "\e[rr;ccH.\e[RR;CCHo";    // old cell gets a trail dot, new cell the ball
patched u8 one[]  = "\e[rr;ccHx";               // any single cell
patched u8 angs[] = "\e[01;20Haa";              // the angle in the status line
u8 title[] = "\e[0m\e[2J\e[?25l\e[05;32HC A N O N B A L L\e[08;16HRaise and lower the barrel of your great cannon, then\e[09;16Hfire to knock down the castle across the field.\e[12;26HUp / Down arrows (or W / S): aim\e[13;26HSPACE: fire\e[14;26HQ: quit\e[18;29HPress SPACE to start";
u8 bye[] = "\e[0m\e[2J\e[H\e[?25hThanks for playing CANONBALL.\r\n";

void quit() { print(bye); halt(); }

u16 kwait(u16 n) {                  // the next key within about n x 4 ms, or 0
    while (n != 0) { if (keyready()) return getc(); n--; }
    return 0;
}

u16 key(u16 k) {                    // key k: 'U' 'D' for aim, ' ' fire, 'Q' quit, 0 for anything else
    if (k == 27) {
        k = kwait(8);
        if (k == '[') k = kwait(8);
    }
    if (k == 'A' || k == 'w' || k == 'W') return 'U';   // a lone 'A'/'B' is an arrow that lost its ESC [
    if (k == 'B' || k == 's' || k == 'S') return 'D';
    if (k == 'q' || k == 'Q') return 'Q';
    if (k == ' ') return ' ';
    return 0;
}

void space() {                      // wait for SPACE (Q quits), stirring rand()
    u16 k;
    while (1) {
        while (!keyready()) rand();
        k = key(getc());
        if (k == ' ') return;
        if (k == 'Q') quit();
    }
}

void cell(u16 r, u16 c, u16 ch) {   // one character at row r, column c
    one[2] = tens[r]; one[3] = ones[r];
    one[5] = tens[c]; one[6] = ones[c];
    one[8] = ch;
    print(one);
}

void message(u16 m) {
    at(MSG, 1); eol();
    at(MSG, 30);
    switch (m) {
        case 1: print("Too short!"); break;
        case 2: print("Too long!"); break;
        case 3: print("Over the top!"); break;
        case 4: rev(1); print(" * * *  H I T !  * * * "); rev(0); break;
    }
}

void showang() {
    angs[8] = tens[ang]; angs[9] = ones[ang];
    rev(1); print(angs); rev(0);
}

void status() {
    at(1, 1); rev(1);
    print(" CANONBALL   Angle "); printz(ang, 2);
    print("   Shots "); printw(shots, 2);
    print("   Castle "); printw(left * 100 / TOTAL, 3);
    print("%   Up/Down aim  SPACE fire  Q quit");
    rev(0);
}

void barrel(u16 ch) {               // draw the barrel at angle bang (ch = ' ' rubs it out)
    u16 r, dc, dr, cs, sn, a;
    if (ch != ' ') {
        if (bang < 23) ch = '-'; else if (bang < 68) ch = '/'; else ch = '|';
    }
    one[8] = ch;
    a = bang; cs = sint[90 - a]; sn = sint[a];
    dc = PC * 256 + 128; dr = PR * 512 + 256;
    for (r = 0; r < BLEN; r++) {
        dc += cs; dr -= sn;         // r x cos (in 1/256 col) and r x sin (in 1/512 row), rounded
        a = dr >> 9;
        one[2] = tens[a]; one[3] = ones[a];
        a = dc >> 8;
        one[5] = tens[a]; one[6] = ones[a];
        print(one);
    }
}

void cannon() {                     // the cannon, its barrel at the angle chosen
    at(PR + 1, PC - 3); print("/###\\");
    at(PR + 2, PC - 3); print("(O)(O)");
    barrel(' '); bang = ang; barrel('#');
}

void castle() {
    u16 r, c;
    for (r = GROUND - 7; r < GROUND; r++) {
        at(r, cx);
        for (c = 0; c < CW; c++) {
            if (h[c] >= GROUND - r) { if (c & 1) putc(']'); else putc('['); }
            else putc(' ');
        }
    }
}

void scene() {
    u16 c;
    cls(); cursor(0);
    at(GROUND, 1);
    for (c = 0; c < 80; c++) putc('=');
    cannon();
    castle();
    status();
}

void blast(u16 hitc) {              // knock bricks off the columns round hitc: 3 2 1
    u16 k, a, d;
    for (k = 0; k < CW; k++) {
        if (k + 2 >= hitc && k <= hitc + 2) {
            if (k > hitc) d = k - hitc; else d = hitc - k;
            a = 3 - d;
            if (h[k] < a) a = h[k];
            h[k] -= a;
            left -= a;
        }
    }
}

void erasetrail() {
    u16 i;
    for (i = 0; i < ntr; i++) cell(trr[i], trc[i], ' ');
    ntr = 0;
}

u16 fly() {                         // fire one ball: 1 short, 2 long, 3 over the top, 4 + column: a hit
    u16 t, x, yy, r, c, or, oc, m, n;  // or/oc = the cell the ball is drawn in (or = 0: not on screen)
    i16 vx, vy;
    t = ang; vx = sint[90 - t]; vy = sint[t];
    t = (BLEN + 1) * vx;
    x = t + (PC * 256 + 128);
    t = (BLEN + 1) * vy;
    t = t >> 1;
    yy = (PR * 256 + 128) - t;
    vx = vx + vx;
    or = 0; oc = 0; m = 0; n = 0;
    while (1) {
        x += vx; yy -= vy; vy -= GY;
        c = x >> 8; r = yy >> 8;
        if (c > 80) { m = 3; c = 81; break; }
        if (r < OFF) {
            if (r >= GROUND) {                      // down on the field
                m = 2;
                if (c < cx) m = 1;
                break;
            }
            if (c >= cx) {                          // the castle: this column and the one passed
                t = c - cx;
                if (t < CW) { if (r + h[t] >= GROUND) { m = t + 4; break; } }
                if (t != 0 && t <= CW) {
                    t--;
                    if (r + h[t] >= GROUND) { m = t + 4; break; }
                }
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
    return m;
}

void shot() {
    u16 m;
    message(0);
    erasetrail();
    cannon();
    shots++;
    m = fly();
    if (m >= 4) {
        cell(row, col, '*'); cell(row - 1, col, '*');
        cell(row, col - 1, '*'); cell(row, col + 1, '*');
        delay(60);
        cell(row, col, ' '); cell(row - 1, col, ' '); cell(row, col - 1, ' '); cell(row, col + 1, ' ');
        blast(m - 4);
        castle();
        m = 4;
    } else if (m != 3) {
        cell(GROUND - 1, land, '*'); delay(30); cell(GROUND - 1, land, ' ');
    }
    message(m);
    cannon();
    status();
}

void play() {
    u16 k;
    copy(&h[0], &h0[0], CW);
    left = TOTAL; shots = 0; ang = 45; bang = 45; ntr = 0;
    cx = 48 + rand() % 21;              // the castle stands somewhere in columns 48-77
    scene();
    while (left > FALLEN) {
        k = kwait(25);                  // the barrel catches up once the keys stop
        if (k == 0) {
            if (bang != ang) cannon();
            while (!keyready()) rand();
            continue;
        }
        k = key(k);
        if (k == 'Q') quit();
        if (k == 'U' && ang < 90) { ang++; showang(); }
        if (k == 'D' && ang > 0)  { ang--; showang(); }
        if (k == ' ') { if (bang != ang) cannon(); shot(); }
    }
    at(MSG, 1); eol();
    at(MSG, 18); rev(1); print("  THE CASTLE HAS FALLEN!  "); rev(0);
    print("  in "); printu(shots); print(" shots");
    at(MSG + 1, 26); print("SPACE: play again    Q: quit");
    for (k = 40; k != 0; k--) { if (keyready()) getc(); delay(12); }
    space();
    at(MSG + 1, 1); eol();
}

void main() {
    print(title);
    space();
    while (1) play();
}
