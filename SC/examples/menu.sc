// menu.sc - a menu: show the menu's text, take a key, pick the program for it.
// The menu's text is built into the program.

u8 menu[] = "\r\n=== ELF2K MENU ===\r\n 1  Lite-Writer\r\n 2  NANO editor\r\n 3  Directory\r\n Q  Quit\r\n\r\nChoice? ";
u16 k;

void main() {
    while (1) {
        print(menu);
        k = getc();
        if (k >= 'a' && k <= 'z') k = k - 'a' + 'A';
        putc(k); print("\r\n");
        switch (k) {
            case '1': print("-> would run: LW2\r\n"); break;
            case '2': print("-> would run: NANO\r\n"); break;
            case '3': print("-> would run: DIR\r\n"); break;
            case 'Q': print("Bye.\r\n"); return;
            default:  print("No such choice.\r\n");
        }
    }
}
