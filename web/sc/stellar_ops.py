"""Row helpers for building STELLAR programs with mini.assemble.

Each helper returns one row (bytes_or_ref, asm_text, note) so a builder reads
like an assembly listing and the .lst disassembly comes out for free:

    ldx(0xF, 10, "Ten")          ->  ("11 0F 00 0A", "LOADXI R15 000A", "Ten")
    iff("LOOP")                  ->  (("A1", "LOOP"), "IFFALSEI LOOP", "")
    lbl("LOOP")                  ->  ((":", "LOOP"), "", "")

Opcode bytes here were each checked against V0061.30 in the simulator before
use (see Firmware-Math/build_simplecalc5.py for the probes that matter).
"""


def _r(h, a, n=""): return (h, a, n)
def _w(v): return "%02X %02X" % ((v >> 8) & 0xFF, v & 0xFF)


def lbl(name, note=""): return ((":", name), "", note)
def ift(name, note=""): return (("A0", name), "IFTRUEI %s" % name, note)
def iff(name, note=""): return (("A1", name), "IFFALSEI %s" % name, note)
def gal(name, note=""): return (("B0", name), "GAL %s" % name, note)
def call(name, note=""): return (("BD", name), "CALL %s" % name, note)
def ret(note=""): return _r("BE 00", "RETURN", note)

def start(note=""): return _r("CD", "START", note)
def brk(note=""): return _r("F0 00 00", "BREAK", note)

def ldx(x, v, note=""):
    # (LOADXI R0 was broken before the $0ED2 fix; it works on V0061.34 - sim-checked 2026-09-29)
    return _r("11 %02X %s" % (x, _w(v)), "LOADXI R%d %04X" % (x, v), note)
def ldai(v, note=""): return _r("10 %s" % _w(v), "LOADAI %04X" % v, note)
def cpxy(x, y, note=""): return _r("23 00 %X%X" % (x, y), "COPYXY R%d -> R%d" % (x, y), note)
def acc2x(x, note=""): return _r("21 0%X" % x, "COPYAX Acc -> R%d" % x, note)
def ma2x(x, note=""): return _r("21 1%X" % x, "COPYAX MA -> R%d" % x, note)
def x2acc(x, note=""): return _r("22 0%X" % x, "COPYXA R%d -> Acc" % x, note)
def maa(note=""): return _r("25", "COPYMAA", note)
def mah(note=""): return _r("2B", "COPYMAH", note)
def rema(note=""): return _r("27", "COPYREMA", note)
def rdidx(x, base, note=""): return _r("2E 0%X %s" % (x, _w(base)), "READIDX R%d %04X" % (x, base), note)
def wridx(x, base, note=""): return _r("2F 0%X %s" % (x, _w(base)), "WRITEIDX R%d %04X" % (x, base), note)
def mx2i(x, v, note=""): return _r("32 0%X %s" % (x, _w(v)), "COPYMX2I R%d %04X" % (x, v), note)
def mxy2(x, y, note=""): return _r("39 02 %X%X" % (x, y), "COPYMXY M(R%d) -> R%d" % (x, y), note)
def xmy2(x, y, note=""): return _r("3A 02 %X%X" % (x, y), "COPYXMY R%d -> M(R%d)" % (x, y), note)
def ld_ma4(x, note=""): return _r("37 40 1%X" % x, "COPYDEMXA MA <- 4 bytes at M(R%d)" % x, note)
def st_ma4(x, note=""): return _r("38 40 1%X" % x, "COPYDEAMX MA -> 4 bytes at M(R%d)" % x, note)
def incx(x, note=""): return _r("42 0%X" % x, "INCX R%d" % x, note)
def decx(x, note=""): return _r("43 0%X" % x, "DECX R%d" % x, note)
def multxy(x, y, note=""): return _r("4A %X%X" % (x, y), "MULTXY R%d * R%d" % (x, y), note)
def divxy(x, y, note=""): return _r("4D %X%X" % (x, y), "DIVXY R%d / R%d" % (x, y), note)
def divmax(x, note=""): return _r("5C 0%X" % x, "DIVMAX MA / R%d" % x, note)
def addai(v, note=""): return _r("4E %s" % _w(v), "ADDAI %04X" % v, note)
def addxyz(x, y, z, note=""):
    return _r("50 %X%X 0%X" % (x, y, z), "ADDXYZ R%d + R%d -> R%d" % (x, y, z), note)
def subxyz(x, y, z, note=""):
    return _r("51 %X%X 0%X" % (x, y, z), "SUBXYZ R%d - R%d -> R%d" % (x, y, z), note)
def addxi(x, v, note=""): return _r("52 0%X %s" % (x, _w(v)), "ADDXI R%d %04X" % (x, v), note)
def subxi(x, v, note=""): return _r("53 0%X %s" % (x, _w(v)), "SUBXI R%d %04X" % (x, v), note)
def testai(v, note=""): return _r("81 %s" % _w(v), "TESTAI %04X" % v, note)
def testxi(x, v, note=""): return _r("86 0%X %s" % (x, _w(v)), "TESTXI R%d %04X" % (x, v), note)
def testxy(x, y, note=""): return _r("87 %X%X" % (x, y), "TESTXY R%d = R%d" % (x, y), note)
def testge(x, y, note=""): return _r("88 %X%X" % (x, y), "TESTGXY R%d >= R%d" % (x, y), note)
def testlt(x, y, note=""): return _r("89 %X%X" % (x, y), "TESTLXY R%d < R%d" % (x, y), note)
def testxz(x, note=""): return _r("8C 0%X" % x, "TESTXZ R%d" % x, note)
def serout(note=""): return _r("C9", "SEROUT", note)
def serouti(ch, note=""):
    c = ord(ch) if isinstance(ch, str) else ch
    return _r("CA %02X" % c, "SEROUTI %02X" % c + (" '%s'" % chr(c) if 32 < c < 127 else ""), note)
def printstr(x, note=""): return _r("C1 0%X" % x, "PRINTSTR R%d" % x, note)
def getstr(x, y, note=""): return _r("C2 %X%X" % (x, y), "GETSTR R%d R%d" % (x, y), note)
def runmc(addr, note=""): return _r("F1 %s" % _w(addr), "RUNMC %04X" % addr, note)


# ---- Esc quits every app (2026-10-29). An arrow is ESC [ x back to back; a lone ESC is ESC with nothing
#      after it for ~30 ms. KWAIT: a subroutine, Test = a key arrived within ~30 ms (RX counts down).
def kwait(label, x, note=""):
    return [lbl(label, note or "Test = a key arrives within ~30 ms (R%d counts)" % x), ldx(x, 8),
            lbl(label + "1"), _r("CC", "SERST", ""), ift(label + "2"), decx(x), testxz(x), iff(label + "1"),
            _r("CC", "SERST", "Test false: nothing came"),
            lbl(label + "2"), ret()]

#      KWAITP: the same, but RX is kept (PUSHX / POPX) - for programs with no register to spare.
def kwaitp(label, x, note=""):
    return [lbl(label, note or "Test = a key arrives within ~30 ms (R%d kept)" % x), _r("72 0%X" % x, "PUSHX R%d" % x, ""),
            ldx(x, 8),
            lbl(label + "1"), _r("CC", "SERST", ""), ift(label + "2"), decx(x), testxz(x), iff(label + "1"),
            lbl(label + "2"), _r("73 0%X" % x, "POPX R%d" % x, ""), _r("CC", "SERST", "Test: a key is waiting"), ret()]

#      GETL: GETSTR R<cur> R<start> with ESC: a lone ESC as the line's first key goes to quit (a GAL); an arrow
#      there is thrown away. Anything else is the line, read by GETSTR as before (Enter alone: an empty line,
#      0 at the cursor, as GETSTR leaves it). It uses Acc and the stack; RX for the wait is kept.
def getl(label, cur, start, x, quit, note=""):
    k = label
    return [lbl(k, note or "Read a line (GETSTR R%d R%d); a lone ESC first quits" % (cur, start)),
            lbl(k + "K"), _r("CB", "SERIN", "the first key"),
            testai(0x1B), iff(k + "N"),
            call(k + "W", "ESC: an arrow following?"), iff(quit, "no: ESC on its own quits"),
            _r("CB", "SERIN", "an arrow (ESC [ x): its two bytes are thrown away"), call(k + "W"), iff(k + "K"),
            _r("CB", "SERIN", ""), gal(k + "K"),
            lbl(k + "N"), testai(0x0D), iff(k + "C"),
            ldai(0), _r("36 01 0%X" % cur, "COPYIAMX 1 byte Acc -> M(R%d)" % cur, "Enter alone: the empty line"), ret(),
            lbl(k + "C"), testai(0x08), ift(k + "K", "nothing to rub out yet"), testai(0x7F), ift(k + "K"),
            _r("C9", "SEROUT", "the echo"), _r("36 01 0%X" % cur, "COPYIAMX 1 byte Acc -> M(R%d)" % cur, ""),
            incx(cur), getstr(cur, start, "the rest of the line (Backspace can rub out the first key too)"), ret()] + \
           kwaitp(k + "W", x)
