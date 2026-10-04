const DOZEN = 12;
u16 eggs, boxes, left;

void main() {
    eggs = 100;
    boxes = eggs / DOZEN;
    left = eggs % DOZEN;
    printu(eggs); print(" eggs make "); printu(boxes);
    print(" boxes, with "); printu(left); print(" left over.\r\n");
    eggs = 65535;
    eggs = eggs + 1;
    print("65535 + 1 = "); printu(eggs); print("\r\n");
}
