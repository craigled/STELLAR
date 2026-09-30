// asm { } in Stellar C: inline STELLAR next to the compiled code.
// Prints "42 asm ok" then "5 !42" then "3 keys" - see asm_verify.py.

u8 msg[] = " asm ok\r\n";

u16 twice(u16 a) { return a + a; }

u16 countkeys() {                  // a SERST poll loop written by hand
    u16 k = 0;
    asm {
    poll:
        SERST                      // a key waiting?
        IFFALSEI @done
        SERIN                      // take it
        INCX 0{k}
        GAL @poll
    done:
    }
    return k;
}

void main() {
    u16 n, i, p;

    n = 7; i = 6;
    asm {
        MULTXY {n}{i}              // MA = n * i
        COPYAX 1{n}                // n = MA
    }
    printu(n);

    asm {
        LOADXI 0{p} #&msg          // an array's address
        PRINTSTR 0{p}
    }

    i = 0;
    while (1) {
        i++;
        asm {
            TESTXI 0{i} #5
            IFTRUEI @break         // leaves the while loop
        }
    }
    printu(i);

    asm {
        LOADXI 0{twice.a} #21      // twice()'s parameter, set by hand
        CALL @twice
        COPYXY 00 D{n}             // the return value comes back in RD
        TESTXI 0{n} #42
        IFTRUEI @good
        SEROUTI %'X'
    good:
        SEROUTI ' '
        SEROUTI %0x21              // '!'
    }
    printu(n);
    print("\r\n");

    printu(countkeys());
    print(" keys\r\n");
}
