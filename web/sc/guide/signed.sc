i16 t[] = { -12, 5, -3, 20, -8, 0, 15 };
i16 low, high, sum, x;
u16 i;

void main() {
    low = t[0]; high = t[0]; sum = 0;
    for (i = 0; i < 7; i++) {
        if (t[i] < low) low = t[i];
        if (t[i] > high) high = t[i];
        sum += t[i];
    }
    print("lowest "); printi(low); print(", highest "); printi(high);
    print(", average "); printi(sum / 7); print(" remainder "); printi(sum % 7); print("\r\n");
    x = -7;
    print("x / 2 = "); printi(x / 2); print(", x % 2 = "); printi(x % 2);
    print(", x >> 1 = "); printi(x >> 1); print(", -7 / 2 = "); printi(-7 / 2); print("\r\n");
}
