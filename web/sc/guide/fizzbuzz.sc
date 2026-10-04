u16 n;

void main() {
    for (n = 1; n <= 15; n++) {
        if (n % 15 == 0) print("FizzBuzz");
        else if (n % 3 == 0) print("Fizz");
        else if (n % 5 == 0) print("Buzz");
        else printu(n);
        print(" ");
    }
    print("\r\n");
}
