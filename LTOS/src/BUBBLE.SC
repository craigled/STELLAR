// BUBBLE.SC - watch a bubble sort put a column of bars in order, one swap at a time.
// Each pass walks down the bars and swaps any two neighbours that are the wrong way round,
// so the longest bar left "bubbles" to the bottom. Only the two bars that swap are drawn
// again - the screen is the slow part. The shuffle comes from a small random-number
// generator (as GUESS.SC's), stirred by the keys you type before it starts.

const N = 16;                                   // bars
const TOP = 3;                                  // the first bar's row
u16 h[N];                                       // the bars' lengths, 1 .. N
u16 seed = 1802;

u16 rnd() { seed = seed * 75 + 74; return seed; }

void at(u16 row, u16 col) { print("\e["); printu(row); putc(';'); printu(col); putc('H'); }

void bar(u16 i) {                               // bar i: its length, then the rest of the row cleared
    u16 k;
    at(TOP + i, 8);
    printu(h[i]); putc(' ');
    if (h[i] < 10) putc(' ');
    for (k = 0; k < h[i]; k++) print("###");
    print("\e[K");
}

void main() {
    u16 i, j, t, k, swaps = 0, pass = 0;
    print("\e[2J\e[H");
    print("BUBBLE SORT - type a few keys to stir the shuffle, then Enter: ");
    while (1) { k = getc(); if (k == 13) break; seed += k; rnd(); }
    for (i = 0; i < N; i++) h[i] = i + 1;
    for (i = N - 1; i > 0; i--) {               // shuffle: swap each bar with one at or before it
        j = rnd() % (i + 1);
        t = h[i]; h[i] = h[j]; h[j] = t;
    }
    print("\e[2J\e[H BUBBLE SORT");
    for (i = 0; i < N; i++) bar(i);
    for (i = N - 1; i > 0; i--) {               // after each pass one more bar is in its place
        pass++;
        at(TOP + N + 1, 8); print("Pass "); printu(pass); print(", "); printu(swaps); print(" swaps so far");
        k = 0;
        for (j = 0; j < i; j++)
            if (h[j] > h[j + 1]) {
                t = h[j]; h[j] = h[j + 1]; h[j + 1] = t;
                swaps++; k++;
                bar(j); bar(j + 1);
            }
        if (k == 0) break;                      // a pass with no swap: all in order
    }
    at(TOP + N + 1, 8); print("Sorted: "); printu(pass); print(" passes, "); printu(swaps); print(" swaps.\e[K");
    at(TOP + N + 3, 8); print("Press a key.");
    getc();
    print("\e[2J\e[H");
}
