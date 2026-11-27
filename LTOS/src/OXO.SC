// OXO.SC - Tic-Tac-Toe: you are X, the computer is O. Type 1-9 for a square (laid out as
// on a phone: 1 2 3 on top). The computer's plan, in order: win if it can, block you if it
// must, else the centre, then a corner, then a side. Arrays can't be filled where they are
// declared in Tiny Stellar C, so lines() fills the table of the eight lines when it starts.

u16 b[9];                                       // the board: 0 empty, 1 X (you), 2 O (the computer)
u16 ln[24];                                     // the eight lines, three squares each
u16 nl = 0;
u16 wins = 0, losses = 0, draws = 0;

void add(u16 x, u16 y, u16 z) { ln[nl] = x; ln[nl + 1] = y; ln[nl + 2] = z; nl += 3; }

void lines() {
    add(0, 1, 2); add(3, 4, 5); add(6, 7, 8);   // rows
    add(0, 3, 6); add(1, 4, 7); add(2, 5, 8);   // columns
    add(0, 4, 8); add(2, 4, 6);                 // diagonals
}

void at(u16 row, u16 col) { print("\e["); printu(row); putc(';'); printu(col); putc('H'); }

void show() {                                   // the board, an empty square shows its number
    u16 r, c, s;
    for (r = 0; r < 3; r++) {
        at(4 + r * 2, 30);
        for (c = 0; c < 3; c++) {
            s = r * 3 + c;
            putc(' ');
            if (b[s] == 1) putc('X');
            else if (b[s] == 2) putc('O');
            else putc('1' + s);
            putc(' ');
            if (c < 2) putc('|');
        }
        if (r < 2) { at(5 + r * 2, 30); print("---+---+---"); }
    }
}

u16 winner() {                                  // 1 or 2 if someone has a line, else 0
    u16 k;
    for (k = 0; k < 24; k += 3)
        if (b[ln[k]] != 0 && b[ln[k]] == b[ln[k + 1]] && b[ln[k]] == b[ln[k + 2]]) return b[ln[k]];
    return 0;
}

u16 full() {
    u16 s;
    for (s = 0; s < 9; s++) if (b[s] == 0) return 0;
    return 1;
}

u16 two(u16 who) {                              // a square that finishes a line for who: 1-9, 0 none
    u16 k, i, mine, gap;
    for (k = 0; k < 24; k += 3) {
        mine = 0; gap = 9;
        for (i = k; i < k + 3; i++) {
            if (b[ln[i]] == who) mine++;
            else if (b[ln[i]] == 0) gap = ln[i];
        }
        if (mine == 2 && gap != 9) return gap + 1;
    }
    return 0;
}

u16 pick() {                                    // the computer's square
    u16 s;
    s = two(2); if (s) return s - 1;            // win
    s = two(1); if (s) return s - 1;            // block
    if (b[4] == 0) return 4;                    // the centre
    if (b[0] == 0) return 0;                    // a corner
    if (b[2] == 0) return 2;
    if (b[6] == 0) return 6;
    if (b[8] == 0) return 8;
    for (s = 1; s < 9; s += 2) if (b[s] == 0) return s;   // a side
    return 9;
}

void say(u16 row) { at(row, 20); print("\e[K"); }

void main() {
    u16 s, k, turn, first = 1, w;
    lines();
    while (1) {
        for (s = 0; s < 9; s++) b[s] = 0;
        print("\e[2J");
        at(1, 27); print("TIC-TAC-TOE: you are X");
        at(12, 20); print("Won "); printu(wins); print("  lost "); printu(losses); print("  drawn "); printu(draws);
        turn = first;
        while (1) {
            show();
            w = winner();
            if (w || full()) break;
            if (turn == 1) {
                say(14); print("Your square, 1-9 (Q quits): ");
                k = getc();
                if (k == 'q' || k == 'Q') { print("\e[2J\e[H"); halt(); }
                if (k < '1' || k > '9' || b[k - '1'] != 0) continue;
                b[k - '1'] = 1;
            } else b[pick()] = 2;
            turn = 3 - turn;
        }
        say(14);
        if (w == 1) { print("You win!"); wins++; }
        else if (w == 2) { print("I win."); losses++; }
        else { print("A draw."); draws++; }
        print("  Again? (Y/N) ");
        k = getc();
        if (k != 'y' && k != 'Y') break;
        first = 3 - first;                      // take turns to start
    }
    print("\e[2J\e[H");
}
