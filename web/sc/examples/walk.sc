// walk.sc - made by LTOS/walk_gen.py: the man RUNNING draws, as a STELLAR app. Esc stops him.
u8 clear[] = "\e[0m\e[2J\e[?25l\e[23;36HEsc stops";
u8 leave[] = "\e[0m\e[?25h\e[2J\e[H";
u8 first[] = "\e[7m\e[6;38H      \e[7;38H      \e[9;40H  \e[B\b\b  \e[B\b\b  \e[B\b\b  \e[B\b\b    \e[B\e[4D    \e[B\e[4D  \e[B\b\b  \e[B\e[4D    \e[B\e[6D      \e[19;32H      \e[2C  \e[B\e[8D  \e[4C  \e[0m";
u8 f0[] = "\e[7m\e[10;38H  \e[2C  \e[B\e[6D  \e[2C    \e[B\e[8D  \e[6C    \e[13;38H  \e[0m\e[2C  \e[7m\e[B\e[6D  \e[0m\e[2C  \e[7m\e[B\e[6D  \e[B\b\b  \e[0m  \e[7m  \e[B\e[8D  \e[0m\e[2C  \e[7m  \e[0m\e[B\e[6D    \e[7m  \e[0m\e[19;32H    \e[4C  \e[7m  \e[B\e[8D  \e[0m\e[2C  \e[7m  \e[0m";
u8 f1[] = "\e[7m\e[5;38H      \e[0m\e[7;38H      \e[7m\e[8;40H  \e[9;38H  \e[2C  \e[4C  \e[10;36H  \e[0m  \e[2C  \e[7m    \e[11;36H  \e[0m  \e[2C    \e[7m\e[12;36H  \e[0m  \e[6C    \e[7m\e[13;36H  \e[0m\e[B\e[2C  \e[7m  \e[B\e[8D  \e[0m    \e[7m  \e[16;34H    \e[0m  \e[2C  \e[7m  \e[17;34H  \e[0m    \e[2C  \e[7m    \e[18;32H    \e[0m  \e[4C  \e[7m\e[2C  \e[19;30H    \e[0m\e[2C  \e[4C  \e[7m\e[4C    \e[20;32H  \e[0m\e[2C  \e[4C  ";
u8 f2[] = "\e[7m\e[8;48H  \e[9;36H  \e[6C    \e[11;34H  \e[B\b\b  \e[0m  \e[B\b\b  \e[7m\e[4C  \e[B\e[8D  \e[B\e[4D  \e[0m\e[6C  \e[7m  \e[16;28H      \e[0m\e[2C  \e[7m\e[8C  \e[17;26H    \e[0m\e[4C  \e[8C  \e[7m\e[2C  \e[18;28H  \e[0m\e[2C    \e[10C  \e[7m      \e[0m\e[19;30H    \e[14C  \e[20;32H    ";
u8 f3[] = "\e[8;48H  \e[9;36H  \e[6C    \e[11;34H  \e[B\b\b  \e[7m  \e[B\b\b  \e[0m\e[4C  \e[B\e[8D  \e[7m\e[15;26H      \e[0m\e[2C  \e[7m\e[6C  \e[0m  \e[7m\e[16;26H  \e[0m    \e[7m\e[4C  \e[0m\e[8C  \e[17;28H  \e[7m\e[14C  \e[0m\e[2C  \e[18;28H  \e[7m\e[16C  \e[0m      \e[7m\e[B\e[6D  \e[0m";
u8 f4[] = "\e[5;38H      \e[7m\e[7;38H      \e[0m\e[8;40H  \e[9;38H  \e[2C  \e[4C  \e[10;36H  \e[7m  \e[2C  \e[0m    \e[11;36H  \e[7m  \e[2C    \e[0m\e[12;36H  \e[7m  \e[6C    \e[0m\e[13;36H  \e[7m\e[B\e[2C  \e[0m  \e[15;26H      \e[4C  \e[7m    \e[0m  \e[16;26H  \e[7m    \e[0m\e[2C    \e[7m  \e[2C  \e[0m  \e[17;26H  \e[7m  \e[4C      \e[2C  \e[0m    \e[7m\e[18;28H  \e[12C    \e[0m  \e[7m\e[B\e[4D  \e[0m\e[2C    \e[7m\e[B\e[8D      \e[0m";
u8 f5[] = "\e[10;38H  \e[2C  \e[B\e[6D  \e[2C    \e[B\e[8D  \e[6C    \e[13;38H  \e[7m\e[2C  \e[0m\e[B\e[6D  \e[7m\e[2C  \e[0m\e[B\e[6D  \e[16;28H      \e[4C  \e[7m  \e[0m  \e[17;28H  \e[4C    \e[7m\e[2C  \e[0m  \e[18;28H  \e[7m\e[6C      \e[0m    \e[7m\e[19;32H      \e[2C  \e[0m\e[2C  \e[7m\e[20;34H  \e[4C  \e[0m\e[2C      ";

u16 stop() {
    u16 k;
    if (!keyready()) return 0;
    k = getc();
    if (k != 27) return 0;
    delay(3);                        // more straight after it: an arrow key
    if (!keyready()) return 1;
    while (keyready()) { k = getc(); }
    return 0;
}

void main() {
    print(clear);
    print(first);
    while (1) {
        print(f0);
        if (stop()) break;
        print(f1);
        if (stop()) break;
        print(f2);
        if (stop()) break;
        print(f3);
        if (stop()) break;
        print(f4);
        if (stop()) break;
        print(f5);
        if (stop()) break;
    }
    print(leave);
}
