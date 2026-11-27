// FIRST.SC - the smallest Tiny Stellar C program: print() for words, printu() for a number.
//
// On the Elf2K:   CD /SRC        go to the examples
//                 SC FIRST       compile FIRST.SC into FIRST.STL (a STELLAR app)
//                 FIRST          run it
// HELP SCLANG shows the whole language. To change an example, copy it first
// (COPY FIRST.SC MYFIRST.SC): an LTOS update puts the examples back as they were.

void main() {
    print("Hello from Tiny Stellar C on the COSMAC 1802!\r\n");
    print("2 + 3 * 4 = ");
    printu(2 + 3 * 4);
    print("\r\n");
}
