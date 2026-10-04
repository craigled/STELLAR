u8  counts[6];
u16 scores[] = { 300, 1200, 50, 700, 950 };
u16 i, j, t;

void main() {
    // a histogram of 600 dice rolls
    for (i = 0; i < 600; i++) counts[rand() % 6]++;
    t = 0;
    for (i = 0; i < 6; i++) t += counts[i];
    print("rolls counted: "); printu(t); print("\r\n");
    // sort the scores, smallest first (a bubble sort)
    for (i = 0; i < 5; i++)
        for (j = 0; j + 1 < 5 - i; j++)
            if (scores[j] > scores[j + 1]) {
                t = scores[j]; scores[j] = scores[j + 1]; scores[j + 1] = t;
            }
    for (i = 0; i < 5; i++) { printu(scores[i]); print(" "); }
    print("\r\n");
}
