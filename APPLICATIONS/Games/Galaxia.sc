// STELLAR GALAXIA - a Galaxian-style shooter for the STELLAR VM (Elf2K, VT100). Increment 1.
// The swarm hangs at the top in five rows and sways from side to side; your ship moves along the
// bottom row and fires one shot at a time. Clear the swarm and the next wave sways faster.
//
// Drawing (9600 baud: every byte counts, ~1 ms each): each formation row is ONE patched string in
// FORM - "ESC[rr;ccH", a lead space, then ten 5-column slots (a 3-column alien or spaces, and a
// 2-column gap) - printed whole when the swarm sways (only its column digits change); a hit just
// blanks three bytes of it and prints three spaces at that alien. The ship's string clears row 23
// first, so a move of any size leaves nothing behind. The shot moves 2 rows a frame on odd rows, so it lands on every
// formation row (3 5 7 9 11).
//
// The per-frame work - the shot, the divers, the bombs and their drawing - is native 1802 (tick(), generated
// by build_galaxia.py: Stellar C alone managed ~5 frames a second). G[] carries the state between them.
//
// Increment 2: divers. Every so often an alien leaves its slot (its bytes in FORM go blank),
// swoops out sideways for three rows, then homes in on the ship a row at a time (every other
// frame), dropping bombs. Past the bottom it reappears at the top and flies back down into its
// slot. A bomb or a diver reaching the ship costs a life; three ships.

const LEN = 60;    const NR = 5;     const FX0 = 17;   const SWAY = 4;     // a row's string; rows; the swarm's centre; its reach
const SROW = 23;   const SHOT0 = 21; const TOP = 3;
const XMIN = 3;    const XMAX = 76;                                       // the ship's '/' column
const ND = 3;      const NB = 4;                                          // divers and bombs at once

u8 TPL[] = {
    27, 91, 48, 51, 59, 49, 54, 72, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 61,
    87, 61, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 61, 87, 61, 32, 32, 32, 32, 32, 32, 32, 32,
    32, 32, 32, 32, 32, 32, 32, 32, 32, 0, 27, 91, 48, 53, 59, 49, 54, 72, 32, 32, 32, 32, 32, 32, 32,
    32, 32, 32, 32, 125, 64, 123, 32, 32, 125, 64, 123, 32, 32, 125, 64, 123, 32, 32, 125, 64, 123, 32,
    32, 125, 64, 123, 32, 32, 125, 64, 123, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 0, 27, 91,
    48, 55, 59, 49, 54, 72, 32, 32, 32, 32, 32, 32, 60, 79, 62, 32, 32, 60, 79, 62, 32, 32, 60, 79, 62,
    32, 32, 60, 79, 62, 32, 32, 60, 79, 62, 32, 32, 60, 79, 62, 32, 32, 60, 79, 62, 32, 32, 60, 79, 62,
    32, 32, 32, 32, 32, 32, 32, 0, 27, 91, 48, 57, 59, 49, 54, 72, 32, 47, 86, 92, 32, 32, 47, 86, 92,
    32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92,
    32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 0, 27, 91, 49, 49, 59, 49, 54,
    72, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92,
    32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92, 32, 32, 47, 86, 92,
    32, 32, 0 };
u8 FORM[300];                                  // the live swarm: TPL, then the hits blanked
u8 RVAL[] = { 60, 50, 40, 30, 30 };            // points: flagship, red, purple, blue, blue
u8 tens[] = "0000000000111111111122222222223333333333444444444455555555556666666666777777777788888888889999999999";
u8 ones[] = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789";

patched u8 ship[] = "\e[23;01H\e[K\e[23;ccH/^\\";    // the row cleared (ESC[K from column 1), then the ship
patched u8 cell[] = "\e[rr;ccHx";               // one character anywhere
patched u8 gone[] = "\e[rr;ccH   ";             // a hit alien
patched u8 era[] = "\e[rr;ccHxxx";              // three cells put back as they were
patched u8 dv[] = "\e[rr;ccHxxx";               // a diver
u8 GLY[] = "=W=}@{<O>/V\\/V\\";               // each formation row's alien
u8 dact[3]; u8 drow[3]; u8 dcol[3]; u8 dslot[3]; u8 dn[3];           // the divers (dslot: row x 16 + column; dn: rows flown)
u8 G[12];                                                            // shared with tick(): see build_galaxia.py
u8 OB[320];                                                          // tick()'s output
u8 RB5[] = { 0, 60, 120, 180, 240 };                                 // each formation row's start in FORM
u8 brow[4]; u8 bcol[4];                                              // the bombs (row 0: none)
u8 title[] = "\e[0m\e[2J\e[?25l\e[03;30HS T E L L A R\e[05;30HG  A  L  A  X  I  A\e[08;14HThe swarm hangs above you, swaying from side to side. Shoot it\e[09;14Hdown before it shoots you. Each wave comes back faster.\e[11;24H=W=  flagship   60\e[12;24H}@{  red        50\e[13;24H<O>  purple     40\e[14;24H/V\\  blue       30\e[17;24HLeft / Right arrows (or A / D): move\e[18;24HSPACE: fire     P: pause\e[19;24HR: restart      Q: quit\e[22;28HPress any key to start";
u8 frame[] = "\e[0m\e[2J\e[?25l\e[01;01H\e[7m STELLAR GALAXIA                                                                \e[0m\e[24;01H Arrows or A D: move   SPACE: fire   P: pause   R: restart   Q: quit";
u8 bye[] = "\e[0m\e[2J\e[H\e[?25hThanks for playing STELLAR GALAXIA.\r\n";

u16 fx, fdir, ft, sway, sx, score, high, wave, left, k, moved, fire, fdel, lives, dt, dper, over;

void quit() { print(bye); halt(); }

u16 kwait(u16 n) {                  // the next key within about n x 4 ms, or 0
    while (n != 0) { if (keyready()) return getc(); n--; }
    return 0;
}

u16 key(u16 k) {                    // arrows / A D -> 'L' 'R'; letters upper-cased
    if (k == 27) {
        k = kwait(8);
        if (k == '[') k = kwait(8);
        if (k == 'C') return 'R';
        if (k == 'D') return 'L';
        return 0;
    }
    if (k >= 'a' && k <= 'z') k = k - 32;
    if (k == 'A') return 'L';
    if (k == 'D') return 'R';
    if (k == 'R') return 'N';       // R = restart: 'N' inside ('R' is right)
    return k;
}

void dig(u16 a, u16 v) { FORM[a] = tens[v]; FORM[a + 1] = ones[v]; }   // two digits into FORM

void swarm() {                      // every row at the swarm's column fx
    u16 r;
    for (r = 0; r < NR; r++) { dig(r * LEN + 5, fx - 1); print(&FORM[r * LEN]); }
}

void drawship() { ship[16] = tens[sx]; ship[17] = ones[sx]; print(ship); }

void put(u16 r, u16 c, u16 ch) {     // one character at row r, column c
    cell[2] = tens[r]; cell[3] = ones[r]; cell[5] = tens[c]; cell[6] = ones[c]; cell[8] = ch;
    print(cell);
}

u16 under(u16 r, u16 c) {           // what belongs at (r, c) without the shot: the swarm's byte, or a space
    u16 i;
    if (r < TOP || r > TOP + 2 * NR - 2 || (r & 1) == 0 || c + 1 < fx || c > fx + 49) return ' ';
    i = r - TOP; i = i >> 1; i = i * LEN; i = i + 9 + c; i = i - fx;
    return FORM[i];
}

void status() {
    at(1, 22); rev(1); print("SCORE "); printz(score, 5); print("   HIGH "); printz(high, 5);
    print("   WAVE "); printw(wave, 2); print("   SHIPS "); printu(lives); rev(0);
}

void erase3(u16 r, u16 c) {         // three cells at (r, c) back to what the swarm has there (or spaces)
    era[2] = tens[r]; era[3] = ones[r]; era[5] = tens[c]; era[6] = ones[c];
    era[8] = under(r, c); era[9] = under(r, c + 1); era[10] = under(r, c + 2);
    print(era);
}


u16 slotat(u16 sl) {                // FORM's index of slot sl's alien (row sl >> 4, column sl & 15)
    u16 i, c;
    i = sl >> 4; c = sl & 15; c = c * 5; i = i * LEN; i = i + 9; return i + c;
}

void rejoin(u16 i) {                // diver i back in its slot
    u16 j, g;
    j = slotat(dslot[i]); g = dslot[i] >> 4; g = g * 3;
    FORM[j] = GLY[g]; FORM[j + 1] = GLY[g + 1]; FORM[j + 2] = GLY[g + 2];
    dact[i] = 0;
}

void launch() {                     // an alien leaves the swarm, if a diver is free and it is there
    u16 i, sl, j, c;
    for (i = 0; i < ND; i++) if (!dact[i]) break;
    if (i == ND) return;
    sl = rand() % 50; c = sl / 10; j = c * 6; sl = sl + j;     // row x 16 + column
    j = slotat(sl);
    if (FORM[j] == ' ') return;
    FORM[j] = ' '; FORM[j + 1] = ' '; FORM[j + 2] = ' ';
    c = sl >> 4; dact[i] = 1; dslot[i] = sl; j = c * 2; drow[i] = TOP + j; dn[i] = 0;
    c = sl & 15; c = c * 5; dcol[i] = fx + c;
}


void shiphit() {                    // a bomb or a diver got the ship
    u16 i;
    at(SROW, sx); print("*#*"); delay(250); delay(250);
    for (i = 0; i < ND; i++) if (dact[i]) { erase3(drow[i], dcol[i]); rejoin(i); }
    for (i = 0; i < NB; i++) if (brow[i]) { put(brow[i], bcol[i], under(brow[i], bcol[i])); brow[i] = 0; }
    if (G[0]) { put(G[0], G[1], under(G[0], G[1])); G[0] = 0; }
    lives--; status(); swarm();
    if (lives == 0) {
        at(13, 34); rev(1); print(" GAME OVER "); rev(0);
        delay(250); delay(250); delay(250); while (keyready()) getc();
        while (!keyready()) rand();
        getc(); over = 1; return;
    }
    delay(250); delay(250); drawship();
}




void newwave() {
    u16 i;
    copy(&FORM[0], &TPL[0], 150); copy(&FORM[150], &TPL[150], 150);
    for (i = 0; i < ND; i++) dact[i] = 0;
    for (i = 0; i < NB; i++) { if (brow[i]) put(brow[i], bcol[i], ' '); brow[i] = 0; }
    left = 36; sway = 10;
    i = wave * 4; dper = 44 - i; if (wave > 8) dper = 12;
    dt = 0; swarm(); status();
}


void tick() {                       // the frame's native work (build_galaxia.py), then its output
    native {
            SEX R2
            LDI hi(&OB)
            PHI R8
            LDI lo(&OB)
            PLO R8                          ; R8 -> the output, all frame
            LDI hi(&G[4])
            PHI R9
            LDI lo(&G[4])
            PLO R9
            LDN R9
            LBZ sh1                         ; no fire
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            LDN R9
            LBNZ sh1                        ; (a shot already flies)
            LDI 21
            STR R9
            LDI hi(&G[2])
            PHI R9
            LDI lo(&G[2])
            PLO R9
            LDN R9
            ADI 1
            PLO RF
            LDI hi(&G[1])
            PHI R9
            LDI lo(&G[1])
            PLO R9
            GLO RF
            STR R9
            LBR sh3
    sh1:
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            LDA R9
            LBZ sh9                         ; no shot
            PHI RD
            LDN R9
            PLO RD
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            LDI 0
            STR R9                          ; (no shot while its cell is put back)
            CALL CUR                        ; the shot's cell back to what it was
            CALL OCC
            GLO RE
            STR R8
            INC R8
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            GHI RD
            SMI 2
            STR R9
            SMI 3
            LBDF sh3                        ; still on the screen
            LDI 0
            STR R9
            LBR sh9
    sh3:
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            LDA R9
            PHI RD
            LDN R9
            PLO RD
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            LDI 0
            STR R9                          ; (no shot while a hit puts cells back)
            CALL FHIT
            GHI RE
            LBNZ sh8
            CALL DHIT
            GHI RE
            LBNZ sh8
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            GHI RD
            STR R9                          ; it flies on
            CALL CUR
            LDI '|'
            STR R8
            INC R8
            LBR sh9
    sh8:
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            LDI 0
            STR R9
    sh9:
            LDI hi(&G[5])
            PHI R9
            LDI lo(&G[5])
            PLO R9
            LDN R9
            LBZ tb
            CALL DIVERS
            LBR tz
    tb:     CALL BOMBS
    tz:     LDI 0
            STR R8
            LBR exit

    ; CUR: ESC [ rr ; cc H for RD = row, column (kept)
    CUR:
            LDI 27
            STR R8
            INC R8
            LDI '['
            STR R8
            INC R8
            GHI RD
            PLO RF
            CALL DIG2
            LDI ';'
            STR R8
            INC R8
            GLO RD
            PLO RF
            CALL DIG2
            LDI 'H'
            STR R8
            INC R8
            RETN
    ; DIG2: RF.0 (0-99) as two digits
    DIG2:   GLO RF
            ADI lo(&tens)
            PLO R9
            LDI hi(&tens)
            ADCI 0
            PHI R9
            LDN R9
            STR R8
            INC R8
            GLO RF
            ADI lo(&ones)
            PLO R9
            LDI hi(&ones)
            ADCI 0
            PHI R9
            LDN R9
            STR R8
            INC R8
            RETN

    ; ROWA: R9 -> FORM's byte for a formation row RD.1 (odd, 3-11) at string offset RF.0 (0-58): FORM + 60 (r-3)/2 + RF.0
    ROWA:   GHI RD
            SMI 3
            SHR
            ADI lo(&RB5)
            PLO R9
            LDI hi(&RB5)
            ADCI 0
            PHI R9
            LDN R9
            STR R2
            GLO RF
            ADD
            PLO RF
            LDI 0
            ADCI 0
            PHI RF
            GLO RF
            ADI lo(&FORM)
            PLO R9
            GHI RF
            ADCI hi(&FORM)
            PHI R9
            RETN

    ; UNDER: RE.0 = what belongs at RD (row, column) without the moving things: the swarm's byte, or a space
    UNDER:  LDI ' '
            PLO RE
            GHI RD
            SMI 3
            LBNF un9
            GHI RD
            SMI 12
            LBDF un9
            GHI RD
            ANI 1
            LBZ un9
            LDI hi(&G[3])
            PHI R9
            LDI lo(&G[3])
            PLO R9
            LDN R9
            SMI 1
            STR R2                          ; fx - 1: where a row's string starts
            GLO RD
            SM
            LBNF un9
            PLO RF
            SMI 51
            LBDF un9
            GLO RF
            ADI 8                           ; past ESC [ rr ; cc H
            PLO RF
            CALL ROWA
            LDN R9
            PLO RE
    un9:    RETN

    ; OCC: RE.0 = what shows at RD (row, column): the shot, a bomb, a diver's glyph, else UNDER. (RF, R9, RE.1)
    OCC:
            LDI hi(&G[0])
            PHI R9
            LDI lo(&G[0])
            PLO R9
            LDA R9
            STR R2
            GHI RD
            XOR
            LBNZ oc1
            LDN R9
            STR R2
            GLO RD
            XOR
            LBNZ oc1
            LDI '|'
            PLO RE
            RETN
    oc1:    LDI 0
            PHI RF
    ob1:    GHI RF
            ADI lo(&brow)
            PLO R9
            LDI hi(&brow)
            ADCI 0
            PHI R9
            LDN R9
            STR R2
            GHI RD
            XOR
            LBNZ ob2
            GHI RF
            ADI lo(&bcol)
            PLO R9
            LDI hi(&bcol)
            ADCI 0
            PHI R9
            LDN R9
            STR R2
            GLO RD
            XOR
            LBNZ ob2
            LDI '!'
            PLO RE
            RETN
    ob2:    GHI RF
            ADI 1
            PHI RF
            XRI 4
            LBNZ ob1
            LDI 0
            PHI RF
    od1:    GHI RF
            ADI lo(&dact)
            PLO R9
            LDI hi(&dact)
            ADCI 0
            PHI R9
            LDN R9
            LBZ od2
            GHI RF
            ADI lo(&drow)
            PLO R9
            LDI hi(&drow)
            ADCI 0
            PHI R9
            LDN R9
            STR R2
            GHI RD
            XOR
            LBNZ od2
            GHI RF
            ADI lo(&dcol)
            PLO R9
            LDI hi(&dcol)
            ADCI 0
            PHI R9
            LDN R9
            STR R2
            GLO RD
            SM
            LBNF od2                        ; left of it
            PHI RE                          ; (the column in the glyph)
            SMI 3
            LBDF od2                        ; right of it
            GHI RF
            ADI lo(&dslot)
            PLO R9
            LDI hi(&dslot)
            ADCI 0
            PHI R9
            LDN R9
            SHR
            SHR
            SHR
            SHR
            PLO RE
            SHL
            STR R2
            GLO RE
            ADD
            STR R2
            GHI RE
            ADD
            ADI lo(&GLY)
            PLO R9
            LDI hi(&GLY)
            ADCI 0
            PHI R9
            LDN R9
            PLO RE
            RETN
    od2:    GHI RF
            ADI 1
            PHI RF
            XRI 3
            LBNZ od1
            LBR UNDER

    ; ERASE3: the three cells at RD back as they were (RD kept)
    ERASE3: CALL CUR
            CALL OCC
            GLO RE
            STR R8
            INC R8
            INC RD
            CALL OCC
            GLO RE
            STR R8
            INC R8
            INC RD
            CALL OCC
            GLO RE
            STR R8
            INC R8
            DEC RD
            DEC RD
            RETN

    ; FHIT: the shot at RD (row, column) hits the swarm? RE.1 = 1, the alien blanked in FORM and on the screen,
    ;       G6 += its points, G7 += 1.  RD kept.
    FHIT:   LDI 0
            PHI RE
            GHI RD
            SMI 3
            LBNF fh9
            GHI RD
            SMI 12
            LBDF fh9
            GHI RD
            ANI 1
            LBZ fh9
            LDI hi(&G[3])
            PHI R9
            LDI lo(&G[3])
            PLO R9
            LDN R9
            STR R2
            GLO RD
            SM
            LBNF fh9                        ; left of the swarm
            PLO RF
            SMI 48
            LBDF fh9                        ; right of it
            LDI 0
            PHI RF                          ; RF.1 = the slot, RF.0 = the column in it
    fh1:    GLO RF
            SMI 5
            LBNF fh2
            PLO RF
            GHI RF
            ADI 1
            PHI RF
            LBR fh1
    fh2:    GLO RF
            SMI 3
            LBDF fh9                        ; a gap
            GHI RF
            SHL
            SHL
            STR R2
            GHI RF
            ADD
            PLO R7                          ; R7.0 = 5 x the slot
            ADI 9
            PLO RF
            CALL ROWA
            LDN R9
            XRI ' '
            LBZ fh9                         ; nobody there
            LDI ' '
            STR R9
            INC R9
            STR R9
            INC R9
            STR R9
            GLO RD
            PLO RB                          ; (the shot's column, kept)
            LDI hi(&G[3])
            PHI R9
            LDI lo(&G[3])
            PLO R9
            LDN R9
            STR R2
            GLO R7
            ADD
            PLO RD                          ; the alien's first column
            CALL CUR
            LDI ' '
            STR R8
            INC R8
            LDI ' '
            STR R8
            INC R8
            LDI ' '
            STR R8
            INC R8
            GLO RB
            PLO RD
            GHI RD
            SMI 3
            SHR
            ADI lo(&RVAL)
            PLO R9
            LDI hi(&RVAL)
            ADCI 0
            PHI R9
            LDN R9
            PLO RF                          ; its points
            CALL SCORE
            LDI 1
            PHI RE
    fh9:    RETN

    ; SCORE: G6 += RF.0, G7 += 1
    SCORE:
            LDI hi(&G[6])
            PHI R9
            LDI lo(&G[6])
            PLO R9
            LDN R9
            STR R2
            GLO RF
            ADD
            STR R9
            INC R9
            LDN R9
            ADI 1
            STR R9
            RETN

    ; DHIT: the shot at RD hits a diver (on row r or r + 1: both move)? RE.1 = 1, the diver gone, double points.
    DHIT:   LDI 0
            PHI RE
            PLO R7
    dh1:
            GLO R7
            ADI lo(&dact)
            PLO R9
            LDI hi(&dact)
            ADCI 0
            PHI R9
            LDN R9
            LBZ dh8
            GLO R7
            ADI lo(&drow)
            PLO R9
            LDI hi(&drow)
            ADCI 0
            PHI R9
            LDN R9
            STR R2
            GHI RD
            SD                              ; its row - the shot's: 0-2 (the shot's two rows, or it stepped in)
            LBNF dh8
            SMI 3
            LBDF dh8
            GLO R7
            ADI lo(&dcol)
            PLO R9
            LDI hi(&dcol)
            ADCI 0
            PHI R9
            LDN R9
            STR R2
            GLO RD
            SM
            LBNF dh8                        ; left of it
            SMI 3
            LBDF dh8                        ; right of it
            GLO RD
            PLO RB
            GHI RD
            PHI RB                          ; (the shot, kept)
            GLO R7
            ADI lo(&dact)
            PLO R9
            LDI hi(&dact)
            ADCI 0
            PHI R9
            LDI 0
            STR R9                          ; gone (before its cells are put back)
            GLO R7
            ADI lo(&drow)
            PLO R9
            LDI hi(&drow)
            ADCI 0
            PHI R9
            LDN R9
            PHI RD
            GLO R7
            ADI lo(&dcol)
            PLO R9
            LDI hi(&dcol)
            ADCI 0
            PHI R9
            LDN R9
            PLO RD
            CALL ERASE3
            GLO RB
            PLO RD
            GHI RB
            PHI RD
            GLO R7
            ADI lo(&dslot)
            PLO R9
            LDI hi(&dslot)
            ADCI 0
            PHI R9
            LDN R9
            SHR
            SHR
            SHR
            SHR
            ADI lo(&RVAL)
            PLO R9
            LDI hi(&RVAL)
            ADCI 0
            PHI R9
            LDN R9
            SHL
            PLO RF                          ; double
            CALL SCORE
            LDI 1
            PHI RE
            RETN
    dh8:    INC R7
            GLO R7
            XRI 3
            LBNZ dh1
            RETN

    ; RND: RF.0 = the next byte of a 16-bit Galois LFSR (G9-10)
    RND:
            LDI hi(&G[9])
            PHI R9
            LDI lo(&G[9])
            PLO R9
            LDA R9
            PHI RF
            LDN R9
            PLO RF
            GHI RF
            SHR
            PHI RF
            GLO RF
            SHRC
            PLO RF
            LBNF rn1
            GHI RF
            XRI $B4
            PHI RF
    rn1:
            LDI hi(&G[9])
            PHI R9
            LDI lo(&G[9])
            PLO R9
            GHI RF
            STR R9
            INC R9
            GLO RF
            STR R9
            RETN

    ; DIVERS: each diver one row - the swoop out, the attack (homing, bombs), past the bottom round to the top, home
    DIVERS: LDI 0
            PLO R7
    dv1:
            GLO R7
            ADI lo(&dact)
            PLO R9
            LDI hi(&dact)
            ADCI 0
            PHI R9
            LDN R9
            LBZ dvn
            GLO R7
            ADI lo(&drow)
            PLO R9
            LDI hi(&drow)
            ADCI 0
            PHI R9
            LDN R9
            PHI RD
            GLO R7
            ADI lo(&dcol)
            PLO R9
            LDI hi(&dcol)
            ADCI 0
            PHI R9
            LDN R9
            PLO RD
            GLO R7
            ADI lo(&dact)
            PLO R9
            LDI hi(&dact)
            ADCI 0
            PHI R9
            LDI 0
            STR R9
            CALL ERASE3
            GLO R7
            ADI lo(&dact)
            PLO R9
            LDI hi(&dact)
            ADCI 0
            PHI R9
            LDI 1
            STR R9
            GHI RD
            ADI 1
            PHI RD
            GLO R7
            ADI lo(&dn)
            PLO R9
            LDI hi(&dn)
            ADCI 0
            PHI R9
            LDN R9
            SMI 3
            LBDF dv3
            GLO RD                          ; the swoop: two columns away from the middle
            SMI 38
            LBDF dv2
            GLO RD
            SMI 4
            LBNF dv6
            GLO RD
            SMI 2
            PLO RD
            LBR dv6
    dv2:    GLO RD
            SMI 74
            LBDF dv6
            GLO RD
            ADI 2
            PLO RD
            LBR dv6
    dv3:
            GLO R7
            ADI lo(&dn)
            PLO R9
            LDI hi(&dn)
            ADCI 0
            PHI R9
            LDN R9
            SMI 200
            LBDF dv5
            LDI hi(&G[2])
            PHI R9
            LDI lo(&G[2])
            PLO R9
            LDN R9                          ; the attack: two columns toward the ship
            STR R2
            GLO RD
            ADI 1
            SM
            LBDF dv3a
            GLO RD
            ADI 2
            PLO RD
            LBR dv3b
    dv3a:
            LDI hi(&G[2])
            PHI R9
            LDI lo(&G[2])
            PLO R9
            LDN R9
            ADI 1
            STR R2
            GLO RD
            SD
            LBDF dv3b
            GLO RD
            SMI 2
            PLO RD
    dv3b:   GHI RD
            SMI 18
            LBDF dv4
            CALL RND
            GLO RF
            ANI 7
            LBNZ dv4
            CALL BOMB
    dv4:    GHI RD
            SMI 23
            LBNF dv6
            LDI hi(&G[2])
            PHI R9
            LDI lo(&G[2])
            PLO R9
            LDN R9                          ; down to the ship's row: does it hit the ship?
            STR R2
            GLO RD
            ADI 2
            SM
            LBNF dv4a
            LDI hi(&G[2])
            PHI R9
            LDI lo(&G[2])
            PLO R9
            LDN R9
            ADI 2
            STR R2
            GLO RD
            SD
            LBNF dv4a
            GLO R7
            ADI lo(&drow)
            PLO R9
            LDI hi(&drow)
            ADCI 0
            PHI R9
            GHI RD
            STR R9
            GLO R7
            ADI lo(&dcol)
            PLO R9
            LDI hi(&dcol)
            ADCI 0
            PHI R9
            GLO RD
            STR R9
            LDI hi(&G[8])
            PHI R9
            LDI lo(&G[8])
            PLO R9
            LDI 1
            STR R9
            RETN
    dv4a:   LDI 2                           ; missed: round to the top, then home
            PHI RD
            GLO R7
            ADI lo(&dn)
            PLO R9
            LDI hi(&dn)
            ADCI 0
            PHI R9
            LDI 200
            STR R9
    dv5:
            GLO R7
            ADI lo(&dslot)
            PLO R9
            LDI hi(&dslot)
            ADCI 0
            PHI R9
            LDN R9                          ; home: above its slot (following the sway), down to its row
            ANI 15
            PLO RF
            SHL
            SHL
            STR R2
            GLO RF
            ADD
            STR R2
            LDI hi(&G[3])
            PHI R9
            LDI lo(&G[3])
            PLO R9
            LDN R9
            ADD
            PLO RD
            GLO R7
            ADI lo(&dslot)
            PLO R9
            LDI hi(&dslot)
            ADCI 0
            PHI R9
            LDN R9
            SHR
            SHR
            SHR
            SHR
            SHL
            ADI 3
            STR R2
            GHI RD
            SM
            LBNF dv6
            CALL REJOIN
            CALL DRAWD                      ; (home: seen in its slot at once)
            GLO R7
            ADI lo(&drow)
            PLO R9
            LDI hi(&drow)
            ADCI 0
            PHI R9
            GHI RD
            STR R9
            LBR dvn
    dv6:
            GLO R7
            ADI lo(&dn)
            PLO R9
            LDI hi(&dn)
            ADCI 0
            PHI R9
            LDN R9
            ADI 1
            STR R9
            GLO R7
            ADI lo(&drow)
            PLO R9
            LDI hi(&drow)
            ADCI 0
            PHI R9
            GHI RD
            STR R9
            GLO R7
            ADI lo(&dcol)
            PLO R9
            LDI hi(&dcol)
            ADCI 0
            PHI R9
            GLO RD
            STR R9
            CALL DRAWD
    dvn:    INC R7
            GLO R7
            XRI 3
            LBNZ dv1
            RETN

    ; DRAWD: diver R7.0 at RD
    DRAWD:  CALL CUR
            GLO R7
            ADI lo(&dslot)
            PLO R9
            LDI hi(&dslot)
            ADCI 0
            PHI R9
            LDN R9
            SHR
            SHR
            SHR
            SHR
            PLO RF
            SHL
            STR R2
            GLO RF
            ADD                             ; 3 x its row
            ADI lo(&GLY)
            PLO R9
            LDI hi(&GLY)
            ADCI 0
            PHI R9
            LDA R9
            STR R8
            INC R8
            LDA R9
            STR R8
            INC R8
            LDN R9
            STR R8
            INC R8
            RETN

    ; REJOIN: diver R7.0 back in its slot: its glyph into FORM; not diving
    REJOIN:
            GLO R7
            ADI lo(&dslot)
            PLO R9
            LDI hi(&dslot)
            ADCI 0
            PHI R9
            LDN R9
            PLO RB                          ; (the slot)
            ANI 15
            PLO RF
            SHL
            SHL
            STR R2
            GLO RF
            ADD
            ADI 9
            PLO RF                          ; 9 + 5 x the column: its offset in the row's string
            GHI RD
            PLO RE                          ; (keep RD)
            GLO RB
            SHR
            SHR
            SHR
            SHR
            SHL
            ADI 3
            PHI RD                          ; its row on the screen
            CALL ROWA
            GLO RE
            PHI RD
            GLO RB
            SHR
            SHR
            SHR
            SHR
            PLO RF
            SHL
            STR R2
            GLO RF
            ADD
            ADI lo(&GLY)
            PLO RB
            LDI hi(&GLY)
            ADCI 0
            PHI RB
            LDA RB
            STR R9
            INC R9
            LDA RB
            STR R9
            INC R9
            LDN RB
            STR R9
            GLO R7
            ADI lo(&dact)
            PLO R9
            LDI hi(&dact)
            ADCI 0
            PHI R9
            LDI 0
            STR R9
            RETN

    ; BOMB: a bomb from below the diver at RD, if one of the four is free
    BOMB:   LDI 0
            PLO RF
    bo1:    GLO RF
            ADI lo(&brow)
            PLO R9
            LDI hi(&brow)
            ADCI 0
            PHI R9
            LDN R9
            LBZ bo2
            INC RF
            GLO RF
            XRI 4
            LBNZ bo1
            RETN
    bo2:    GHI RD
            ADI 1
            STR R9
            GLO RF
            ADI lo(&bcol)
            PLO R9
            LDI hi(&bcol)
            ADCI 0
            PHI R9
            GLO RD
            ADI 1
            STR R9
            INC RD
            GHI RD
            ADI 1
            PHI RD
            CALL CUR
            LDI '!'
            STR R8
            INC R8
            DEC RD
            GHI RD
            SMI 1
            PHI RD
            RETN

    ; BOMBS: each bomb one row down; at the ship's row: a hit, or gone
    BOMBS:  LDI 0
            PLO R7
    bb1:
            GLO R7
            ADI lo(&brow)
            PLO R9
            LDI hi(&brow)
            ADCI 0
            PHI R9
            LDN R9
            LBZ bbn
            PHI RD
            LDI 0
            STR R9                          ; (no bomb while its cell is put back)
            GLO R7
            ADI lo(&bcol)
            PLO R9
            LDI hi(&bcol)
            ADCI 0
            PHI R9
            LDN R9
            PLO RD
            CALL CUR
            CALL OCC
            GLO RE
            STR R8
            INC R8
            GHI RD
            ADI 1
            PHI RD
            SMI 23
            LBNF bb3
            GLO R7
            ADI lo(&brow)
            PLO R9
            LDI hi(&brow)
            ADCI 0
            PHI R9
            LDI 0
            STR R9
            LDI hi(&G[2])
            PHI R9
            LDI lo(&G[2])
            PLO R9
            LDN R9
            STR R2
            GLO RD
            SM
            LBNF bbn                        ; left of the ship
            SMI 3
            LBDF bbn                        ; right of it
            LDI hi(&G[8])
            PHI R9
            LDI lo(&G[8])
            PLO R9
            LDI 1
            STR R9
            RETN
    bb3:
            GLO R7
            ADI lo(&brow)
            PLO R9
            LDI hi(&brow)
            ADCI 0
            PHI R9
            GHI RD
            STR R9
            CALL CUR
            LDI '!'
            STR R8
            INC R8
    bbn:    INC R7
            GLO R7
            XRI 4
            LBNZ bb1
            RETN
    }
    print(OB);
}

void game() {
    print(frame);
    score = 0; wave = 1; fx = FX0; fdir = 1; ft = 0; sx = 39; lives = 3; over = 0;
    for (k = 0; k < NB; k++) brow[k] = 0;
    G[0] = 0; G[9] = rand(); G[10] = rand() | 1;
    newwave(); drawship();
    while (!over) {
        moved = 0; fire = 0;
        while (keyready()) {
            k = key(getc());
            if (k == 'L' && sx > XMIN) { sx = sx - 2; if (sx < XMIN) sx = XMIN; moved = 1; }
            else if (k == 'R' && sx < XMAX) { sx = sx + 2; if (sx > XMAX) sx = XMAX; moved = 1; }
            else if (k == ' ') fire = 1;
            else if (k == 'Q') quit();
            else if (k == 'N') return;
            else if (k == 'P') { at(1, 2); rev(1); print("PAUSED"); rev(0); while (!keyready()) rand(); getc(); at(1, 2); rev(1); print(" STELL"); rev(0); }
        }
        if (moved) drawship();
        G[2] = sx; G[3] = fx; G[4] = fire; G[5] = ft & 1; G[6] = 0; G[7] = 0; G[8] = 0;
        tick();
        if (G[6]) { score = score + G[6]; left = left - G[7]; if (score > high) high = score; status(); }
        if (G[8]) shiphit();
        if (over) return;
        dt++;
        if (dt >= dper) { dt = 0; launch(); }
        if (left == 0) { wave++; newwave(); }
        ft++;
        if (ft >= sway) {                               // the swarm sways one column
            ft = 0; fx = fx + fdir;
            if (fx >= FX0 + SWAY || fx <= FX0 - SWAY) fdir = 0 - fdir;
            swarm();
        }
    }
}

void main() {
    high = 0;
    while (1) {
        print(title);
        while (!keyready()) rand();
        getc();
        game();
    }
}
