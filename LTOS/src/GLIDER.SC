// GLIDER.SC - Conway's Game of Life on a 16 x 8 world whose edges wrap round. A cell with 3
// live neighbours is born; one with 2 or 3 lives on; every other cell is empty next time.
// Only the live cells are visited - every one adds 1 to the eight cells round it - and only
// the cells that may change are looked at again, so the work grows with the live cells, not
// with the size of the world (a loop step costs the 1802 a few thousand instructions).
// Space: the next generation; R: run 20; Q quits.

const W = 16;
const H = 8;
const L = 40;                                   // at most this many live cells
const C = 120;                                  // and cells that may change
u16 n[128];                                     // each cell (W * H): 16 if alive, + its live neighbours
u16 live[L];                                    // where the live cells are
u16 cand[C];                                    // the cells that may change this generation
u16 nlive = 0, ncand = 0, gen = 0;

void at(u16 row, u16 col) { print("\e["); printu(row); putc(';'); printu(col); putc('H'); }

void draw(u16 i, u16 ch) { at(3 + i / W, 30 + i % W); putc(ch); }

void set(u16 r, u16 c) { n[r * W + c] = 16; live[nlive] = r * W + c; nlive++; draw(r * W + c, 'O'); }

void bump(u16 x) {                              // one more live neighbour for cell x
    if (n[x] == 0) { if (ncand == C) return; cand[ncand] = x; ncand++; }
    n[x]++;
}

void step() {
    u16 k, x, r, c, up, mid, dn, l, rt, v, a;
    ncand = 0;
    for (k = 0; k < nlive; k++) { cand[ncand] = live[k]; ncand++; }   // a live cell may die
    for (k = 0; k < nlive; k++) {
        x = live[k];
        r = x / W; c = x - r * W;
        mid = r * W;                            // where its row, the one above and the one below
        if (r == 0) up = (H - 1) * W; else up = mid - W;   //  start (the edges wrap round)
        if (r == H - 1) dn = 0; else dn = mid + W;
        if (c == 0) l = W - 1; else l = c - 1;
        if (c == W - 1) rt = 0; else rt = c + 1;
        bump(up + l); bump(up + c); bump(up + rt); bump(mid + l);
        bump(mid + rt); bump(dn + l); bump(dn + c); bump(dn + rt);
    }
    nlive = 0;
    for (k = 0; k < ncand; k++) {
        x = cand[k];
        a = n[x] >= 16;                         // alive now
        v = n[x] & 15;                          // its live neighbours
        v = v == 3 || (v == 2 && a);            // alive next
        if (v != a) { if (v) draw(x, 'O'); else draw(x, '.'); }
        if (v && nlive < L) { n[x] = 16; live[nlive] = x; nlive++; }
        else n[x] = 0;
    }
    gen++;
}

void main() {
    u16 r, c, k, run = 0;
    print("\e[2J");
    at(1, 32); print("THE GAME OF LIFE");
    for (r = 0; r < H; r++) { at(3 + r, 30); for (c = 0; c < W; c++) putc('.'); }
    set(1, 2); set(1, 3); set(1, 4);            // a blinker
    set(3, 9); set(4, 10); set(5, 8); set(5, 9); set(5, 10);   // a glider, heading down and right
    at(16, 16); print("Space: next generation   R: run 20   Q: quit");
    while (1) {
        at(14, 30); print("Generation "); printu(gen); print(", "); printu(nlive); print(" alive  ");
        if (run) run--;
        else {
            k = getc();
            if (k == 'q' || k == 'Q') break;
            if (k == 'r' || k == 'R') run = 20;
        }
        step();
    }
    print("\e[2J\e[H");
}
