// EAR TEST - watches the Elf2K's EF3 line, where a sound "ear" plugs in
// (PLANS/Elf2K-Ear-EF3.md), and shows live what it hears.
//
// Each "check" is a burst of 1000 fast native samples of EF3 (about 30 ms of the 1802's time,
// some 34,000 samples a second, so even a raw comparator ear following the sound wave is
// caught); a check that sees EF3 on at all counts as sound. The native sampling holds the
// 1802 while it runs, so other VMs slow down while the test runs.
//
//   q quit   c clear the count   i flip the polarity   + / - hold (quiet checks bridged
//   inside one sound: 0 for a clean tone detector, 1-3 for a raw "sound module")

const SAMPLES = 1000;
const BAR = 20;              // the level bar, columns 13-32

u8 hashes[] = "####################";
u8 dots[] = "....................]";

void screen() {
    cls(); cursor(0);
    print("STELLAR EAR TEST - listening on EF3\r\n\r\n");
    print("EF lines   1 .  2 .  3 .  4 .     (* = the line is pulled low: on)\r\n\r\n");
    print("EF3         quiet\r\n\r\n");
    print("Level      [....................]\r\n\r\n");
    print("Sounds     0\r\nHold\r\nPolarity\r\n\r\n");
    print("Nothing plugged in: every line shows '.', EF4 '*' only while INPUT is held.\r\n");
    print("EF3 '*' with nothing plugged in: JP6 is still fitted (RS-232 input owns EF3).\r\n");
    print("A clap or knock: Sounds goes up by one. A steady tone: SOUND stays lit.\r\n");
    print("SOUND lit when it is quiet: the ear's output is the other way up - press i.\r\n");
    print("A raw sound module counting one clap as several: press + (more hold).\r\n\r\n");
    print("q quit   c clear   i invert   + - hold");
}

void main() {
    u16 hits, on, quiet, sounds, hold, inv, lvl, peak, shown, mask, oldmask, k, cnt, seen;

    hold = 2; inv = 0;
    while (1) {
        screen();
        on = 0; quiet = 0; sounds = 0; shown = 0; oldmask = 99; cnt = 0; peak = 0; seen = 0;
        at(10, 12); printu(hold);
        at(11, 12); if (inv) print("inverted"); else print("normal");

        while (1) {
            native {                   // hits = how many of 1000 samples saw EF3 pulled low
                LDI 0
                PHI RD
                PLO RD
                LDI hi(SAMPLES)
                PHI R8
                LDI lo(SAMPLES)
                PLO R8
            loop:
                BN3 off
                INC RD
            off:
                DEC R8
                GLO R8
                BNZ loop
                GHI R8
                BNZ loop
                LDI hi({hits})
                PHI R9
                LDI lo({hits})
                PLO R9
                GHI RD
                STR R9
                INC R9
                GLO RD
                STR R9
            }
            if (hits) seen = 1;                // the line itself (before any inverting)
            if (inv) hits = SAMPLES - hits;
            lvl = hits / 50;                   // 0-1000 -> 0-20
            if (lvl > peak) peak = lvl;

            // one sound = checks with EF3 on, bridging up to `hold` quiet checks
            if (on) {
                if (hits) quiet = 0;
                else {
                    quiet++;
                    if (quiet > hold) { on = 0; print("\e[5;12H quiet "); }
                }
            } else if (hits) {
                on = 1; quiet = 0; sounds++;
                print("\e[5;12H\e[7m SOUND \e[0m\e[9;12H"); printu(sounds);
            }

            cnt++;
            if ((cnt & 3) == 0) {              // every fourth check: the level bar, the EF lines
                if (peak != shown) {
                    at(7, 13); print(&hashes[BAR - peak]); print(&dots[peak]);
                    shown = peak;
                }
                peak = 0;
                // EF1, EF2, EF4 as they are now; EF3 '*' if any sample since the last update saw it
                // (a raw ear flickers far too fast to show the instant value)
                mask = ef() & 11;
                if (seen) mask = mask | 4;
                seen = 0;
                if (mask != oldmask) {
                    oldmask = mask;
                    at(3, 14); if (mask & 1) putc('*'); else putc('.');
                    at(3, 19); if (mask & 2) putc('*'); else putc('.');
                    at(3, 24); if (mask & 4) putc('*'); else putc('.');
                    at(3, 29); if (mask & 8) putc('*'); else putc('.');
                }
            }

            if (keyready()) {
                k = getc();
                if (k == 'q' || k == 'Q') { cls(); cursor(1); halt(); }
                if (k == 'c' || k == 'C') break;
                if (k == 'i' || k == 'I') { inv = inv ^ 1; break; }
                if (k == '+' && hold < 20) { hold++; at(10, 12); printu(hold); eol(); }
                if (k == '-' && hold > 0) { hold--; at(10, 12); printu(hold); eol(); }
            }
        }
    }
}
