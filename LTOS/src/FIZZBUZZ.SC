// FIZZBUZZ.SC - if / else and the remainder (%): 1 to 100, but Fizz for a multiple of 3,
// Buzz for a multiple of 5, FizzBuzz for both.

void main() {
    u16 n;
    for (n = 1; n <= 100; n++) {
        if (n % 15 == 0) print("FizzBuzz");
        else if (n % 3 == 0) print("Fizz");
        else if (n % 5 == 0) print("Buzz");
        else printu(n);
        if (n % 10 == 0) print("\r\n");         // ten a line
        else putc(' ');
    }
}
