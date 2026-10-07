// LIFE LAB - Conway's Game of Life that you seed yourself. A Stellar C program for STELLAR
// (Elf2K, VT100 terminal).
//
// EDIT: move the cursor with the arrow keys (or W A S D), SPACE turns a cell on or off,
// 1-9 stamp a classic pattern at the cursor, C clears the board, R fills it at random,
// T steps one generation. ENTER runs it.
// RUN: the generations go by; SPACE or ENTER stops and goes back to EDIT (the board and the
// generation count are kept), + and - change the speed. Q quits; ? shows the help again.
//
// The board is 78 x 20 and wraps round (a torus): what leaves one side comes back on the
// other. A[] holds it with a one-cell border, 80 bytes a row; the border is filled with the
// opposite edge before each generation, so every cell has eight neighbours and no cell is
// a special case. The generation is raw 1802 code (native, run by RUNMC): running column
// sums, so a cell costs one new 3-cell column sum. The new board goes to B[]; then, row by
// row, more native code compares B with A, copies it across, counts the population, and
// builds the escape sequence that redraws only the changed part of the row.

const W = 78;  const H = 20;  const S = 80;          // board width, height, row stride
const CELLS = 1760;                                  // (H + 2) x S
const TOP = 3; const LEFT = 2;                       // screen row / column of cell (0, 0)
const HELPROW = 24;

u8 A[1760];                                          // the board (with its border)
patched u8 B[1760];                                  // the next generation (written before read)
patched u8 rowbuf[100];                              // one row's redraw: escape + cells + 0
u8 tens[] = "0000000000111111111122222222223333333333444444444455555555556666666666777777777788888888889999999999";
u8 ones[] = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789";
u8 pat[] = { 0, 1, 1, 2, 2, 0, 2, 1, 2, 2, 255, 0, 1, 0, 4, 1, 0, 2, 0, 2, 4, 3, 0, 3, 1, 3, 2, 3, 3, 255,
    0, 1, 0, 2, 1, 0, 1, 1, 2, 1, 255, 0, 1, 1, 3, 2, 0, 2, 1, 2, 4, 2, 5, 2, 6, 255,
    0, 24, 1, 22, 1, 24, 2, 12, 2, 13, 2, 20, 2, 21, 2, 34, 2, 35, 3, 11, 3, 15, 3, 20, 3, 21, 3, 34, 3, 35,
    4, 0, 4, 1, 4, 10, 4, 16, 4, 20, 4, 21, 5, 0, 5, 1, 5, 10, 5, 14, 5, 16, 5, 17, 5, 22, 5, 24, 6, 10,
    6, 16, 6, 24, 7, 11, 7, 15, 8, 12, 8, 13, 255,
    0, 2, 0, 3, 0, 4, 0, 8, 0, 9, 0, 10, 2, 0, 2, 5, 2, 7, 2, 12, 3, 0, 3, 5, 3, 7, 3, 12, 4, 0, 4, 5, 4, 7,
    4, 12, 5, 2, 5, 3, 5, 4, 5, 8, 5, 9, 5, 10, 7, 2, 7, 3, 7, 4, 7, 8, 7, 9, 7, 10, 8, 0, 8, 5, 8, 7, 8, 12,
    9, 0, 9, 5, 9, 7, 9, 12, 10, 0, 10, 5, 10, 7, 10, 12, 12, 2, 12, 3, 12, 4, 12, 8, 12, 9, 12, 10, 255,
    0, 6, 1, 0, 1, 1, 2, 1, 2, 5, 2, 6, 2, 7, 255,
    0, 0, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 8, 0, 9, 255,
    0, 0, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 9, 0, 10, 0, 11, 0, 12, 0, 13, 0, 17, 0, 18, 0, 19,
    0, 26, 0, 27, 0, 28, 0, 29, 0, 30, 0, 31, 0, 32, 0, 34, 0, 35, 0, 36, 0, 37, 0, 38, 255 };
u16 patidx[] = { 0, 11, 30, 41, 56, 129, 226, 241, 262 };
u8 waits[] = { 250, 150, 90, 60, 40, 25, 15, 8, 3, 0 };     // the pause after a generation, per speed

u16 r, full, pop, gen, cr, cc, speed, seed;

patched u8 cell[] = "\e[rr;ccHx\b";              // one cell, cursor left on it
patched u8 curs[] = "\e[rr;ccH";                 // the cursor to a cell
u8 frame[] = "\e[0m\e[2J\e[02;01H+------------------------------------------------------------------------------+";
patched u8 side[] = "\e[rr;01H|\e[rr;80H|";
u8 bottom[] = "\e[23;01H+------------------------------------------------------------------------------+";
u8 hedit[] = "\e[24;01H\e[K Arrows SPACE=cell 1-9=pattern C=clear R=random T=step ENTER=run ?=help Q=quit\e[?25h";
u8 hrun[]  = "\e[24;01H\e[K\e[?25l  RUNNING      SPACE or ENTER: stop and edit      + / -: speed      Q: quit";
u8 title[] = "\e[0m\e[2J\e[?25l\e[02;33HL I F E   L A B\e[04;05HConway's Game of Life: every cell lives or dies by its eight neighbours.\e[05;05HA live cell with 2 or 3 live neighbours lives on; an empty cell with exactly\e[06;05H3 is born. Draw your own life forms, then run them and watch them evolve.\e[08;05HEDIT  arrows (or W A S D) move    SPACE cell on/off    C clear    R random\e[09;05H      T one generation    ENTER run    ? this help    Q quit\e[10;05HRUN   SPACE or ENTER stop (back to edit)    + / -  faster / slower\e[12;05HPatterns, stamped at the cursor:\e[13;07H1 glider          2 spaceship        3 R-pentomino (chaos)\e[14;07H4 acorn           5 glider gun       6 pulsar (blinks forever)\e[15;07H7 diehard (dies)  8 ten in a row     9 infinite growth\e[17;05HThe board wraps round: what leaves one edge comes back on the other.\e[20;28HPress any key to start";
u8 bye[] = "\e[0m\e[2J\e[H\e[?25hThanks for playing LIFE LAB.\r\n";

void quit() { print(bye); halt(); }

u16 kwait(u16 n) {                  // the next key within about n x 4 ms, or 0
    while (n != 0) { if (keyready()) return getc(); n--; }
    return 0;
}

u16 key(u16 k) {                    // arrows -> 'U' 'D' 'L' 'R'; letters upper-cased
    if (k == 27) {
        k = kwait(8);
        if (k == '[') k = kwait(8);
        if (k == 'A') return 'U';
        if (k == 'B') return 'D';
        if (k == 'C') return 'R';
        if (k == 'D') return 'L';
        return 0;
    }
    if (k >= 'a' && k <= 'z') k = k - 32;
    if (k == 'W') return 'U';
    if (k == 'S') return 'D';
    if (k == 'A') return 'L';
    if (k == 'D') return 'R';
    if (k == 'R') return 'N';       // R = random: 'N' inside the program ('R' is right)
    return k;
}

void status(u16 mode) {             // mode 0 edit, 1 run
    at(1, 1); rev(1);
    print(" LIFE LAB   ");
    if (mode) print("RUNNING"); else print("EDITING");
    print("   Generation "); printz(gen, 5);
    print("   Population "); printz(pop, 4);
    print("   Speed "); printu(speed);
    print("              ");
    rev(0);
}

void putcursor() {
    u16 a;
    a = cr + TOP; curs[2] = tens[a]; curs[3] = ones[a];
    a = cc + LEFT; curs[5] = tens[a]; curs[6] = ones[a];
    print(curs);
}

void putcell(u16 rr, u16 c, u16 alive) {
    u16 a;
    a = rr + TOP; cell[2] = tens[a]; cell[3] = ones[a];
    a = c + LEFT; cell[5] = tens[a]; cell[6] = ones[a];
    if (alive) cell[8] = 'O'; else cell[8] = ' ';
    print(cell);
}

u16 at_(u16 rr, u16 c) {            // A[] index of cell (rr, c)
    u16 i;
    i = rr + 1;
    i = i * S;
    return i + c + 1;
}

void showrows() {                   // redraw the changed part of every row; count the population
    pop = 0;
    for (r = 1; r <= H; r++) {
        native {
            LDI hi({r})
            PHI R9
            LDI lo({r})
            PLO R9
            INC R9
            LDN R9
            PLO RE                      ; RE.0 = r
            LDI hi(&A+1)
            PHI R7
            LDI lo(&A+1)
            PLO R7
            LDI hi(&B+1)
            PHI R8
            LDI lo(&B+1)
            PLO R8
        mul:
            GLO R7
            ADI S
            PLO R7
            GHI R7
            ADCI 0
            PHI R7
            GLO R8
            ADI S
            PLO R8
            GHI R8
            ADCI 0
            PHI R8
            DEC RE
            GLO RE
            BNZ mul                     ; R7 = A row r, column 1; R8 = B the same
            LDI 0
            PLO RD                      ; RD.0 = first changed column (0: none)
            PHI RD                      ; RD.1 = last changed column
            PLO RB
            PHI RB                      ; RB = live cells in the row
            LDI 1
            PLO RE                      ; RE.0 = the column, 1-78
            SEX R2
        scan:
            LDN R8                      ; new
            STR R2
            BZ s1
            INC RB
        s1:
            LDN R7                      ; old
            XOR
            BZ same
            GLO RD
            BNZ s2
            GLO RE
            PLO RD
        s2:
            GLO RE
            PHI RD
        same:
            LDN R8
            STR R7                      ; A = B
            INC R7
            INC R8
            INC RE
            GLO RE
            XRI W+1
            BNZ scan
            LDI hi({full})
            PHI R9
            LDI lo({full})
            PLO R9
            INC R9
            LDN R9
            BZ nofull
            LDI 1
            PLO RD
            LDI W
            PHI RD
        nofull:
            LDI hi(&rowbuf)
            PHI R9
            LDI lo(&rowbuf)
            PLO R9
            GLO RD
            LBZ done
            LDI 27
            STR R9
            INC R9
            LDI '['
            STR R9
            INC R9
            LDI hi({r})
            PHI RF
            LDI lo({r})
            PLO RF
            INC RF
            LDN RF
            ADI TOP-1                   ; the screen row
            PLO RF
            LDI '0'
            PHI RF
        t1:
            GLO RF
            SMI 10
            BNF t2
            PLO RF
            GHI RF
            ADI 1
            PHI RF
            BR t1
        t2:
            GHI RF
            STR R9
            INC R9
            GLO RF
            ADI '0'
            STR R9
            INC R9
            LDI ';'
            STR R9
            INC R9
            GLO RD
            ADI LEFT-1                  ; the screen column of the first change
            PLO RF
            LDI '0'
            PHI RF
        t3:
            GLO RF
            SMI 10
            BNF t4
            PLO RF
            GHI RF
            ADI 1
            PHI RF
            BR t3
        t4:
            GHI RF
            STR R9
            INC R9
            GLO RF
            ADI '0'
            STR R9
            INC R9
            LDI 'H'
            STR R9
            INC R9
            GLO R8                      ; R8 = B row + 79: back to column 'first'
            SMI W+1
            PLO R8
            GHI R8
            SMBI 0
            PHI R8
            GLO RD
            STR R2
            GLO R8
            ADD
            PLO R8
            GHI R8
            ADCI 0
            PHI R8
            GHI RD                      ; how many: last - first + 1
            SM
            ADI 1
            PLO RE
        emit:
            LDA R8
            BZ e1
            LDI 'O'
            BR e2
        e1:
            LDI ' '
        e2:
            STR R9
            INC R9
            DEC RE
            GLO RE
            BNZ emit
        done:
            LDI 0
            STR R9                      ; the terminator
            LDI hi({pop}+1)
            PHI R9
            LDI lo({pop}+1)
            PLO R9                      ; pop += RB (big-endian register: low byte first here)
            GLO RB
            STR R2
            LDN R9
            ADD
            STR R9
            DEC R9
            GHI RB
            STR R2
            LDN R9
            ADC
            STR R9
        }
        if (rowbuf[0]) print(rowbuf);
    }
}

void step() {                       // one generation: A -> B, then the rows redrawn and B -> A
    native {
        LDI hi(&A+S)                    ; the border: column 0 = column W, column W+1 = column 1
        PHI R7
        LDI lo(&A+S)
        PLO R7
        LDI H
        PLO RE
    wrow:
        GLO R7
        ADI W
        PLO R8
        GHI R7
        ADCI 0
        PHI R8
        LDN R8
        STR R7
        INC R7
        LDN R7
        INC R8
        STR R8
        INC R8
        GHI R8
        PHI R7
        GLO R8
        PLO R7
        DEC RE
        GLO RE
        BNZ wrow
        LDI hi(&A+S)                    ; row H+1 = row 1 (R7 is at row H+1 now)
        PHI R8
        LDI lo(&A+S)
        PLO R8
        LDI S
        PLO RE
    c1:
        LDA R8
        STR R7
        INC R7
        DEC RE
        GLO RE
        BNZ c1
        LDI hi(&A+H*S)                  ; row 0 = row H
        PHI R8
        LDI lo(&A+H*S)
        PLO R8
        LDI hi(&A)
        PHI R7
        LDI lo(&A)
        PLO R7
        LDI S
        PLO RE
    c2:
        LDA R8
        STR R7
        INC R7
        DEC RE
        GLO RE
        BNZ c2
    }
    native {
        LDI hi(&A)                      ; R7 = the row above, R8 = this row, R9 = the row below
        PHI R7
        LDI lo(&A)
        PLO R7
        LDI hi(&A+S)
        PHI R8
        LDI lo(&A+S)
        PLO R8
        LDI hi(&A+2*S)
        PHI R9
        LDI lo(&A+2*S)
        PLO R9
        LDI hi(&B+S+1)
        PHI RB
        LDI lo(&B+S+1)
        PLO RB                          ; RB = where the new cell goes
        LDI H
        PHI RE                          ; RE.1 = rows to go
        SEX R2
    row:
        LDA R7                          ; RD.0 = column sum at column 0, RD.1 at column 1
        STR R2
        LDA R8
        ADD
        STR R2
        LDA R9
        ADD
        PLO RD
        LDA R7
        STR R2
        LDA R8
        ADD
        STR R2
        LDA R9
        ADD
        PHI RD
        LDI W
        PLO RE                          ; RE.0 = cells to go in the row
    cell:
        LDA R7                          ; the column sum one to the right
        STR R2
        LDA R8
        ADD
        STR R2
        LDA R9
        ADD
        PLO RF
        STR R2
        GHI RD
        ADD
        STR R2
        GLO RD
        ADD                             ; the 3 x 3 sum, the cell itself included
        XRI 3
        BZ alive                        ; 3: born, or lives with 2 neighbours
        XRI 7
        BNZ dead                        ; 4: lives on only if it is alive (3 neighbours)
        DEC R8
        DEC R8
        LDN R8
        INC R8
        INC R8
        BR store
    alive:
        LDI 1
        BR store
    dead:
        LDI 0
    store:
        STR RB
        INC RB
        GHI RD
        PLO RD
        GLO RF
        PHI RD
        DEC RE
        GLO RE
        BNZ cell
        INC RB                          ; skip the border to the next row
        INC RB
        GHI RE
        SMI 1
        PHI RE
        BNZ row
    }
    full = 0;
    showrows();
    gen++;
}

void copyab() {                     // B = A, all 1,760 bytes
    native {
        LDI hi(&A)
        PHI R7
        LDI lo(&A)
        PLO R7
        LDI hi(&B)
        PHI R8
        LDI lo(&B)
        PLO R8
        LDI hi(CELLS)
        PHI R9
        LDI lo(CELLS)
        PLO R9
    cp:
        LDA R7
        STR R8
        INC R8
        DEC R9
        GLO R9
        BNZ cp
        GHI R9
        BNZ cp
    }
}

void redraw() {                     // the whole board, from A
    copyab();
    full = 1;
    showrows();
    full = 0;
}

void randomfill() {                 // about one cell in four alive
    seed = rand();
    native {
        LDI hi({seed})
        PHI R9
        LDI lo({seed})
        PLO R9
        LDA R9
        PHI RF
        LDN R9
        PLO RF
        GLO RF
        BNZ ok
        GHI RF
        BNZ ok
        LDI 1
        PLO RF                          ; a zero seed would stay zero
    ok:
        LDI hi(&A)
        PHI R7
        LDI lo(&A)
        PLO R7
        LDI hi(CELLS)
        PHI R8
        LDI lo(CELLS)
        PLO R8
        SEX R2
    next:
        GHI RF                          ; a 16-bit Galois LFSR: x >>= 1, and if a 1 fell out, x ^= $B400
        SHR
        PHI RF
        GLO RF
        SHRC
        PLO RF
        BNF nox
        GHI RF
        XRI $B4
        PHI RF
    nox:
        GLO RF
        ANI 3
        BZ live
        LDI 0
        BR put
    live:
        LDI 1
    put:
        STR R7
        INC R7
        DEC R8
        GLO R8
        BNZ next
        GHI R8
        BNZ next
    }
}

void stamp(u16 p) {                 // pattern p (1-9) at the cursor, wrapping round
    u16 i, rr, c, k;
    i = patidx[p - 1];
    while (pat[i] != 255) {
        rr = cr + pat[i];
        rr = rr % H;
        c = cc + pat[i + 1];
        c = c % W;
        k = at_(rr, c);
        A[k] = 1;
        putcell(rr, c, 1);
        i += 2;
    }
}

void board() {                      // the frame, the board, the help line
    u16 i;
    print(frame);
    for (i = TOP; i < TOP + H; i++) {
        side[2] = tens[i]; side[3] = ones[i];
        side[11] = tens[i]; side[12] = ones[i];
        print(side);
    }
    print(bottom);
    redraw();
}

void help() {
    print(title);
    while (!keyready()) rand();
    getc();
    board();
}

void count() {                      // the population, without redrawing
    copyab();
    pop = 0;
    full = 0;
    showrows();
}

void run() {                        // generations until a key says stop
    u16 k, n;
    status(1);
    print(hrun);
    while (1) {
        step();
        status(1);
        n = waits[speed];
        while (n != 0) { if (keyready()) break; delay(1); n--; }
        while (keyready()) {
            k = key(getc());
            if (k == 'Q') quit();
            if (k == ' ' || k == 13) return;
            if (k == '+' || k == '=') { if (speed < 9) speed++; status(1); }
            if (k == '-' || k == '_') { if (speed > 0) speed--; status(1); }
        }
    }
}

void edit() {                       // until ENTER
    u16 k, i;
    status(0);
    print(hedit);
    putcursor();
    while (1) {
        while (!keyready()) rand();
        k = key(getc());
        if (k == 'Q') quit();
        if (k == 13) return;
        if (k == 'U') { if (cr == 0) cr = H - 1; else cr--; }
        else if (k == 'D') { cr++; if (cr == H) cr = 0; }
        else if (k == 'L') { if (cc == 0) cc = W - 1; else cc--; }
        else if (k == 'R') { cc++; if (cc == W) cc = 0; }
        else if (k == ' ') {
            i = at_(cr, cc);
            if (A[i]) { A[i] = 0; pop--; putcell(cr, cc, 0); }
            else { A[i] = 1; pop++; putcell(cr, cc, 1); }
            status(0);
        }
        else if (k >= '1' && k <= '9') { stamp(k - '0'); count(); status(0); }
        else if (k == 'C') { fill(&A[0], 0, CELLS); gen = 0; pop = 0; redraw(); status(0); }
        else if (k == 'N') { randomfill(); gen = 0; redraw(); status(0); }
        else if (k == 'T') { step(); status(0); }
        else if (k == '?') { help(); status(0); print(hedit); }
        putcursor();
    }
}

void main() {
    cr = H / 2; cc = W / 2 - 2;
    gen = 0; pop = 0; full = 0; speed = 7;
    fill(&A[0], 0, CELLS);
    help();
    while (1) { edit(); run(); }
}
