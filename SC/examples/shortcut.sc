// && and || stop early: the right side - here a call to f() - runs only when it is needed.
// Each test prints its result and how many times f() ran. Checked by shortcut_verify.py.
u16 n, r, x, i, z, o;
u16 pat[] = { 0, 3 };

u16 f(u16 v) { n++; return v; }
void g() { if (o || f(1)) return; n = n + 100; }
u16 h() { return z && f(1); }

void show() { printu(r); putc(','); printu(n); putc(' '); n = 0; }

void main() {
    z = 0; o = 1; n = 0;
    r = 0; if (z && f(1)) r = 1; show();                   // 0,0
    r = 0; if (o && f(1)) r = 1; show();                   // 1,1
    r = 0; if (o || f(1)) r = 1; show();                   // 1,0
    r = 0; if (z || f(0)) r = 1; show();                   // 0,1
    r = z && f(1); show();                                 // 0,0
    r = o || f(0); show();                                 // 1,0
    r = o && f(5); show();                                 // 1,1
    r = 0; if ((z && f(1)) || f(1)) r = 1; show();         // 1,1
    r = 0; if (!(z && f(1))) r = 1; show();                // 1,0
    i = 0; while (i < 3 && f(1)) i++; r = i; show();       // 3,3
    r = 0; if (f(0) && f(1)) r = 1; show();                // 0,1
    r = 0; while (1) { if (o || f(1)) break; r++; } show(); // 0,0
    g(); r = 0; show();                                    // 0,0
    r = h(); show();                                       // 0,0
    r = (z && f(1)) + 2; show();                           // 2,0
    r = f(o && f(7)); show();                              // 1,2
    i = 0; r = 0; if (pat[i] && !f(pat[i])) r = 1; show(); // 0,0  (SAWK's rules())
    i = 1; r = 0; if (pat[i] && !f(pat[i])) r = 1; show(); // 0,1
    r = 0; if (z && f(1) || o && f(1)) r = 1; show();      // 1,1
    r = 0; if (o && (z || f(0)) && f(1)) r = 1; show();    // 0,1
    q(z && f(1)); q(0); r = 0; show();                     // 0,0
    print("\r\n");
}
