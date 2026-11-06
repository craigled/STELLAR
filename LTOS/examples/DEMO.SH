# DEMO.SH - a tour of the LTOS 0.5 shell
# Try:  DEMO Craig      or, to see each line run:  SH -x DEMO Craig

WHO=$1
[ -z "$WHO" ] && WHO=friend
echo "Hello, $WHO - this is SH running on an RCA 1802"
echo "The time is $(TIME)"

line() { echo "----------------------------------------"; }

# a function that leaves its answer in R, and one that returns a status
fact() {
  R=1; I=$1
  while [ $I -gt 1 ]; do R=$((R * I)); I=$((I - 1)); done
}
even() { return $(( $1 % 2 )); }

line
echo "Factorials, 16-bit whole numbers:"
for N in 1 2 3 4 5 6 7; do
  fact $N
  if even $N; then K=even; else K=odd; fi
  echo "  $N! = $R    ($N is $K)"
done

line
echo "Sorting the files in the root by their type:"
S=0; T=0; P=0; O=0
for F in /*.*; do
  case $F in
    *.SH) S=$((S + 1)) ;;
    *.TXT|*.HLP|*.LOG) T=$((T + 1)) ;;
    *.PRG|*.STL) P=$((P + 1)) ;;
    *) O=$((O + 1)) ;;
  esac
done
echo "  $S scripts, $T text files, $P programs, $O others"
[ -d /BIN ] && echo "  and /BIN holds the system programs" || echo "  (no /BIN folder)"

line
echo "$WHO ran the demo" >> /DEMO.LOG
RUNS=$(RAWK 'END {print NR}' /DEMO.LOG)
echo "DEMO.LOG says this demo has run $RUNS time(s)"

line
read -p "Count down from (1-9)? " X
case $X in
  1|2|3|4|5|6|7|8|9) ;;
  *) echo "$X? Let's use 5."; X=5 ;;
esac
while [ $X -gt 0 ]; do
  echo -n "$X... "
  sleep 1
  X=$((X - 1))
done
echo "liftoff!"
echo "Goodbye, $WHO."
