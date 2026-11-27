// native { } in Stellar C: raw 1802 machine code, run in place by $F1 RUNMC.
// Prints "19900 = 19900", then "4DBC", then "native!" - see native_verify.py.

const N = 200;
u8 data[N];
u8 hex[5];                         // written by the native code only
u8 buf[12];

void main() {
    u16 i, n, total, check;

    for (i = 0; i < N; i++) data[i] = i;
    n = N;

    native {                       // total = the sum of data[0..n-1]
        LDI hi(&data)
        PHI R7
        LDI lo(&data)
        PLO R7                     ; R7 -> data
        LDI hi({n})
        PHI R9
        LDI lo({n})
        PLO R9                     ; R9 -> n's VM register (high byte first)
        LDA R9
        PHI R8
        LDN R9
        PLO R8                     ; R8 = n
        LDI 0
        PHI RD
        PLO RD                     ; RD = the sum
        SEX R2
    loop:
        LDA R7
        STR R2                     ; the next byte, where ADD can see it
        GLO RD
        ADD
        PLO RD
        GHI RD
        ADCI 0
        PHI RD
        DEC R8
        GLO R8
        BNZ loop
        GHI R8
        BNZ loop
        LDI hi({total})
        PHI R9
        LDI lo({total})
        PLO R9
        GHI RD
        STR R9
        INC R9
        GLO RD
        STR R9                     ; total = RD
    }

    check = 0;
    for (i = 0; i < N; i++) check += data[i];
    printu(total);
    if (total == check) print(" = "); else print(" != ");
    printu(check);
    print("\r\n");

    native {                       // hex[] = total as four hex digits
        LDI hi(&hex)
        PHI R7
        LDI lo(&hex)
        PLO R7
        LDI hi({total})
        PHI R8
        LDI lo({total})
        PLO R8
        LDI 4
        PLO R9
    digit:
        GLO R9
        ANI 1
        BNZ low
        LDN R8                     ; digits 4 and 2: the high nibble
        SHR
        SHR
        SHR
        SHR
        BR conv
    low:
        LDA R8                     ; digits 3 and 1: the low nibble, then the next byte
        ANI $0F
    conv:
        PLO RE
        SMI 10                     ; DF = 1 when the nibble is 10 or more
        GLO RE
        BNF num
        ADI 'A'-'0'-10
    num:
        ADI '0'
        STR R7
        INC R7
        DEC R9
        GLO R9
        BNZ digit
        STR R7                     ; D = 0 here: the terminator
    }
    print(hex);
    print("\r\n");

    native {                       // buf[] = a string kept inside the native block
        LBR copy
    text:
        DB "native!", 0
    copy:
        LDI hi(text)
        PHI R7
        LDI lo(text)
        PLO R7
        LDI hi(&buf)
        PHI R8
        LDI lo(&buf)
        PLO R8
    more:
        LDA R7
        STR R8
        INC R8
        LBNZ more
    }
    print(buf);
    print("\r\n");
}
