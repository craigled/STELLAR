// STELLAR SNAKE in Stellar C - the same game as APPLICATIONS/Snake/Snake.lst (build_snake.py):
// steer the snake to the food; it grows; don't hit the wall or yourself.
// The grid holds, for each body cell, the direction the snake LEFT it by - the tail
// follows those, so there is no list of segments. Walls are tested by line / column.

const TOPW = 2;  const BOTW = 24;  const LEFTW = 1;  const RIGHTW = 79;
const W = 80;    const FOOD = 9;   const G0 = 240;       // grid index of line 3, column 0
const UP = 1;    const DOWN = 2;   const LEFT = 3;   const RIGHT = 4;
const GROW = 3;  const LEN0 = 4;  const ROW0 = 13;  const COL0 = 40;  const LVLSTEP = 4;

// where the numbers go in the strings
const MOVE_y = 2; const MOVE_x = 5; const MOVE_Y = 11; const MOVE_X = 14;
const TAIL_t = 2; const TAIL_u = 5; const FOOD_f = 2; const FOOD_g = 5;
const DEAD_d = 2; const DEAD_e = 5; const SIDE_r = 2; const SIDE_R = 11;
const STAT_s = 30; const STAT_b = 41;

u16 hl, hc, hi;           // the head: line, column, grid index (line x 80 + column)
u16 tl, tc, ti;           // the tail
u16 dir, grow, score, best;
u8 next, next2, lvl;      // queued turns and the level: bytes in memory

u8 grid[1680];            // lines 3-23 x 80 columns
u8 tens[] = "0000000000111111111122222222223333333333444444444455555555556666666666777777777788888888889999999999";
u8 ones[] = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789";
u8 rev[] = { 0, DOWN, UP, RIGHT, LEFT };               // the opposite direction
u8 waith[] = { 19, 16, 14, 12, 10, 8, 7, 6, 5, 4 };       // the wait after a step across, per level
u8 waitv[] = { 40, 35, 32, 29, 25, 22, 21, 19, 17, 16 };       // ... and up or down (a cell is taller than wide)

// 'patched': the program fills in these strings' blanks before it prints them,
// so they need no restoring when the game is rerun
patched u8 status[] = "\e[01;01HSTELLAR SNAKE   SCORE sss   BEST bbb     arrows/wasd  P pause  ESC quit\e[K";
u8 paused[] = "\e[01;01H   * * *   PAUSED  -  press any key   * * *\e[K";
u8 init[]   = "\e[0m\e[2J\e[?25l";
u8 walls[]  = "\e[02;01H###############################################################################\e[24;01H###############################################################################";
patched u8 side[]   = "\e[rr;01H#\e[RR;79H#";
u8 snake0[] = "\e[13;37HOOO@";
patched u8 move[]   = "\e[yy;xxHO\e[YY;XXH@";
patched u8 tail[]   = "\e[tt;uuH ";
patched u8 foods[]  = "\e[ff;ggH*";
patched u8 dead[]   = "\e[dd;eeHX";
u8 over[]   = "\e[10;29H                     \e[11;29H   *** GAME OVER ***   \e[12;29H                     ";
u8 newb[]   = "\e[12;29H     NEW BEST!       ";
u8 again[]  = "\e[14;21H SPACE: play again        ESC: quit ";
u8 title[]  = "\e[0m\e[2J\e[?25l\e[06;34HSTELLAR SNAKE\e[08;34H  O O O O @  *\e[11;18HEat the food  *  to grow.  Don't hit the wall\e[12;18Hor yourself.  The more you eat, the faster it goes.\e[14;18H  arrow keys (or w a s d): steer     P: pause\e[16;28HSPACE: start       ESC: quit";
u8 bye[]    = "\e[0m\e[2J\e[H\e[?25hThanks for playing STELLAR SNAKE.\r\n";

void quit() { print(bye); halt(); }

u16 kwait() {                      // the next key within ~30 ms, or 0
    u16 n = 8;
    while (n != 0) { if (keyready()) return getc(); n--; }
    return 0;
}

void space() {                     // wait for SPACE, spinning RAND; a lone ESC quits
    u16 k;
    while (1) {
        while (!keyready()) rand();
        k = getc();
        if (k == ' ') return;
        if (k == 27) { if (kwait() == 0) quit(); }
    }
}

void put3(u16 v, u16 p) {          // three digits of v into the status line at p
    status[p + 2] = v % 10 + '0';  v = v / 10;
    status[p + 1] = v % 10 + '0';
    status[p] = v / 10 + '0';
}

void showstatus() { put3(score, STAT_s); put3(best, STAT_b); print(status); }

void place() {                     // food in a random empty cell
    u16 l, c, i;
    while (1) {
        l = rand() % 21 + 3;
        c = rand() % 77 + 2;
        i = l * W + c;
        if (grid[i - G0] == 0) break;
    }
    grid[i - G0] = FOOD;
    foods[FOOD_f] = tens[l]; foods[FOOD_f + 1] = ones[l];
    foods[FOOD_g] = tens[c]; foods[FOOD_g + 1] = ones[c];
    print(foods);
}

void pause() {
    print(paused);
    while (!keyready()) { }
    getc();
    showstatus();
}

void keys() {                      // a key is waiting: queue a turn, pause, or quit
    u16 k, d;
    k = getc();
    if (k == 27) {
        k = kwait();               // ESC: is an arrow following?
        if (k == 0) quit();
        if (k == '[') k = kwait();
    }
    if (k == 'A' || k == 'w') d = UP;
    else if (k == 'B' || k == 's') d = DOWN;
    else if (k == 'D' || k == 'a') d = LEFT;
    else if (k == 'C' || k == 'd') d = RIGHT;
    else { if (k == 'p' || k == 'P') pause(); return; }
    if (next == 0) {               // queue it unless it is no change or straight back
        if (d != dir && rev[d] != dir) next = d;
    } else if (next2 == 0) {
        if (d != next && rev[d] != next) next2 = d;
    }
}

void play() {                      // one game; returns when the snake dies
    u16 i, w;
    print(init);
    fill(&grid[0], 0, 1680);
    next = 0; next2 = 0; lvl = 0;
    score = 0; grow = 0; dir = RIGHT;
    hl = ROW0; hc = COL0; hi = ROW0 * W + COL0;
    tl = ROW0; tc = COL0 - LEN0 + 1; ti = ROW0 * W + COL0 - LEN0 + 1;
    for (i = ti; i != hi; i++) grid[i - G0] = RIGHT;
    grid[hi - G0] = RIGHT;
    move[MOVE_Y] = tens[hl]; move[MOVE_Y + 1] = ones[hl];
    move[MOVE_X] = tens[hc]; move[MOVE_X + 1] = ones[hc];
    print(walls);
    for (i = TOPW + 1; i != BOTW; i++) {
        side[SIDE_r] = tens[i]; side[SIDE_r + 1] = ones[i];
        side[SIDE_R] = tens[i]; side[SIDE_R + 1] = ones[i];
        print(side);
    }
    print(snake0);
    showstatus();
    place();
    while (1) {
        if (next != 0) { dir = next; next = next2; next2 = 0; }
        if (grow != 0) grow--;
        else {                                      // the tail moves on
            w = grid[ti - G0];
            grid[ti - G0] = 0;
            tail[TAIL_t] = tens[tl]; tail[TAIL_t + 1] = ones[tl];
            tail[TAIL_u] = tens[tc]; tail[TAIL_u + 1] = ones[tc];
            print(tail);
            if (w == UP) { tl--; ti -= W; }
            else if (w == DOWN) { tl++; ti += W; }
            else if (w == LEFT) { tc--; ti--; }
            else { tc++; ti++; }
        }
        copy(&move[MOVE_y], &move[MOVE_Y], 5);     // last step's '@' cell gets the 'O'
        grid[hi - G0] = dir;
        if (dir == UP) { hl--; hi -= W; }
        else if (dir == DOWN) { hl++; hi += W; }
        else if (dir == LEFT) { hc--; hi--; }
        else { hc++; hi++; }
        if (hl == TOPW || hl == BOTW || hc == LEFTW || hc == RIGHTW) return;
        w = grid[hi - G0];
        if (w != 0) {
            if (w != FOOD) return;                  // the body
            score++; grow += GROW;
            w = score / LVLSTEP;
            if (w > 9) w = 9;
            lvl = w;
            grid[hi - G0] = dir;                    // before the food is placed
            place();
            showstatus();
        }
        grid[hi - G0] = dir;
        move[MOVE_Y] = tens[hl]; move[MOVE_Y + 1] = ones[hl];
        move[MOVE_X] = tens[hc]; move[MOVE_X + 1] = ones[hc];
        print(move);
        if (dir >= LEFT) w = waith[lvl]; else w = waitv[lvl];
        while (w != 0) {                            // the wait, reading keys all through it
            if (keyready()) keys();
            delay(1);
            w--;
        }
    }
}

void gameover() {
    u16 n;
    dead[DEAD_d] = tens[hl]; dead[DEAD_d + 1] = ones[hl];
    dead[DEAD_e] = tens[hc]; dead[DEAD_e + 1] = ones[hc];
    print(dead);
    print(over);
    if (score > best) { best = score; print(newb); showstatus(); }
    print(again);
    for (n = 40; n != 0; n--) {                     // swallow keys for ~1 s
        if (keyready()) getc();
        delay(12);
    }
}

void main() {
    best = 0;
    print(title);
    space();
    while (1) { play(); gameover(); space(); }
}
