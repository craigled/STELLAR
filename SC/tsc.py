# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""tsc - Tiny Stellar C: the reference for SC.PRG, the compiler that runs on LTOS (LTOS/sc.asm). The same
algorithm, step for step, so SC.PRG's .STL must be this one's byte for byte (LTOS/verify_sc.py).

The language is a part of Stellar C (SC/GUIDE.md), so a program compiles with scc.py too:
    const NAME = 5;                    a constant (a number, a character, -n or another constant)
    u16 a, b = 7, t[10];               16-bit unsigned variables and arrays (globals: = a constant; arrays
                                       outside functions only, as scc)
    u16 f(u16 x, u16 y) { ... }        functions (u16 or void), defined before they are called; no recursion
    void main() { ... }                where it starts
    statements  { } u16 x = e; if / else, while, for, break, continue, return [e];
                x = e, x op= e (+ - * / % & | ^), x++, x--, a[i] = e (op=, ++, --), f(...);
    expressions || && == != < <= > >= | ^ & << >> (by a constant) + - * / % - ~ ! a[i] f(...) ( )
                numbers 123 0x1F 'c' (escapes \\n \\r \\t \\b \\e \\0 \\\\ \\' \\")
    builtins    print("text")  printu(e)  putc(e)  getc()  halt()
                (n below: a constant)
                q(n)       the Q line (the speaker, the Q lamp): 0 off, 1 on, 2 one blink, 3 two
                ef(n)      1 if EF line n (1-4; 4 is the INPUT switch) is on, else 0
                waitef(n)  wait for EF line n to go on, then off (one press of INPUT for 4)
                rtc(n)     the clock chip (DS12887): 0 second, 1 minute, 2 hour,
                           3 weekday (0 = Sunday), 4 day, 5 month, 6 the year (2026); 7: 1 if the
                           Elf2K has a clock chip, 0 if not (then 0-6 mean nothing)
    comments    // ... and /* ... */

The code: one pass, as it is read. $4000: CD (START), BD (CALL main), 00 (HALT: halt() goes there), then each
function as it comes, then F0 00 00 (the pre-pass end marker). Variables, arrays and strings take room from the
top of the 3 KB block down (addresses known at once; SC.PRG on LTOS has room for no more); the code grows up to meet them. An expression is worked
out in R1-R11 as a stack (RF holds an address, RE a 0, RD a function's value); a comparison leaves its answer
in STELLAR's Test flag until something needs it as a number. Variables live in memory (static: no stack
frames - as STELLAR has none), so a call keeps the caller's working registers with PUSHX / POPX.

    python3 SC/tsc.py prog.sc            -> prog.STL beside it (and a listing of the bytes with -l)
"""
import sys, os

TOP = 0x0C00                                    # the 3 KB block (relative addresses: 0 = $4000)
NTEMP = 11
BUILTINS = ('print', 'printu', 'putc', 'getc', 'halt', 'q', 'ef', 'waitef', 'rtc')
KEYW = ('u16', 'void', 'const', 'if', 'else', 'while', 'for', 'break', 'continue', 'return')
OPS2 = ('==', '!=', '<=', '>=', '&&', '||', '++', '--', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>')
ESC = {'n': 10, 'r': 13, 't': 9, 'b': 8, 'e': 27, '0': 0, '\\': 92, "'": 39, '"': 34}


class Error(Exception):
    def __init__(s, line, msg): super().__init__('line %d: %s' % (line, msg)); s.line = line; s.msg = msg


class Lexer:
    def __init__(s, src):
        s.src = src.replace('\r\n', '\n').replace('\r', '\n'); s.i = 0; s.line = 1; s.next()

    def err(s, msg): raise Error(s.line, msg)

    def ch(s, k=0):
        j = s.i + k
        return s.src[j] if j < len(s.src) else ''

    def escape(s):
        c = s.ch(); s.i += 1
        if c != '\\': return ord(c)
        e = s.ch(); s.i += 1
        if e not in ESC: s.err('not an escape: \\%s' % e)
        return ESC[e]

    def next(s):
        """The next token -> s.kind ('num' 'id' 'str' 'op' 'eof'), s.val."""
        while True:
            c = s.ch()
            if c == '': break
            if c == '\n': s.line += 1; s.i += 1
            elif c in ' \t': s.i += 1
            elif c == '/' and s.ch(1) == '/':
                while s.ch() not in ('\n', ''): s.i += 1
            elif c == '/' and s.ch(1) == '*':
                s.i += 2
                while not (s.ch() == '*' and s.ch(1) == '/'):
                    if s.ch() == '': s.err('a /* with no */')
                    if s.ch() == '\n': s.line += 1
                    s.i += 1
                s.i += 2
            else: break
        c = s.ch()
        if c == '': s.kind, s.val = 'eof', ''; return
        if c.isdigit():
            j = s.i
            if c == '0' and s.ch(1) in 'xX':
                s.i += 2; j = s.i
                while s.ch() and s.ch() in '0123456789abcdefABCDEF': s.i += 1
                if s.i == j: s.err('0x with no digits')
                v = int(s.src[j:s.i], 16)
            else:
                while s.ch().isdigit(): s.i += 1
                v = int(s.src[j:s.i])
            if v > 0xFFFF: s.err('a number over 65535')
            s.kind, s.val = 'num', v; return
        if c == "'":
            s.i += 1
            if s.ch() in ("'", '\n', ''): s.err('not a character')
            v = s.escape()
            if s.ch() != "'": s.err("no closing '")
            s.i += 1; s.kind, s.val = 'num', v; return
        if c == '"':
            s.i += 1; b = []
            while s.ch() != '"':
                if s.ch() in ('\n', ''): s.err('no closing "')
                b.append(s.escape())
            s.i += 1; s.kind, s.val = 'str', bytes(b); return
        if c.isalpha() or c == '_':
            j = s.i
            while s.ch() and (s.ch().isalnum() or s.ch() == '_'): s.i += 1
            if s.i - j > 15: s.err('a name over 15 letters')
            s.kind, s.val = 'id', s.src[j:s.i]; return
        if s.src[s.i:s.i + 2] in OPS2: s.kind, s.val = 'op', s.src[s.i:s.i + 2]; s.i += 2; return
        if c in '+-*/%&|^~!<>=(){}[];,': s.kind, s.val = 'op', c; s.i += 1; return
        s.err('not a character of Stellar C: %r' % c)

    def is_(s, v): return s.kind in ('op', 'id') and s.val == v

    def take(s, v):
        if s.is_(v): s.next(); return True
        return False

    def need(s, v):
        if not s.take(v): s.err('%s expected' % v)

    def name(s):
        if s.kind != 'id' or s.val in KEYW: s.err('a name expected')
        n = s.val; s.next(); return n


class Compiler:
    def __init__(s, src):
        s.lx = Lexer(src)
        s.img = bytearray(TOP)                  # the 4 KB block
        s.pc = 0; s.dtop = TOP; s.rtcbuf = None
        s.syms = []                             # [name, kind, value, extra] - kind: c(onst) v(ar) a(rray) f(unc)
        s.nglob = 0                             # globals end here (a function's locals after)
        s.k = 0                                 # working registers in use (R1..Rk)
        s.flag = None                           # None: the value is in Rk; 1 / 0: in the Test flag (true when Test = it)
        s.loops = []                            # [break chain, continue target]
        s.fn = None
        s.mainfix = 2                           # where CALL main's address goes

    def err(s, msg): raise Error(s.lx.line, msg)

    # ---- code
    def emit(s, *bs):
        for b in bs:
            if s.pc >= s.dtop: s.err('the program is over 3 KB')
            s.img[s.pc] = b & 0xFF; s.pc += 1

    def word(s, v): s.emit(v >> 8, v)

    def patch(s, at, v): s.img[at] = (v >> 8) & 0xFF; s.img[at + 1] = v & 0xFF

    def data(s, n):
        s.dtop -= n
        if s.dtop < s.pc: s.err('the program is over 3 KB')
        return s.dtop

    # ---- names
    def find(s, n):
        for e in reversed(s.syms):
            if e[0] == n: return e
        return None

    def add(s, n, kind, val, extra=0):
        lo = s.nglob if s.fn else 0
        for e in s.syms[lo:]:
            if e[0] == n: s.err('%s defined twice' % n)
        s.syms.append([n, kind, val, extra]); return s.syms[-1]

    def cexpr(s):
        """A constant: [-] a number, a character or a constant's name."""
        neg = s.lx.take('-')
        if s.lx.kind == 'num': v = s.lx.val; s.lx.next()
        elif s.lx.kind == 'id':
            e = s.find(s.lx.val)
            if not e or e[1] != 'c': s.err('%s is not a constant' % s.lx.val)
            v = e[2]; s.lx.next()
        else: s.err('a constant expected')
        return (-v if neg else v) & 0xFFFF

    # ---- registers
    def push(s):
        if s.k >= NTEMP: s.err('the expression is too deep')
        s.k += 1; return s.k

    def value(s):
        """Make the Test flag's answer a number in Rk (1 true, 0 false)."""
        if s.flag is None: return
        k = s.k; yes = s.pc + 10
        s.emit(0xA0 if s.flag else 0xA1); s.word(yes)
        s.emit(0x11, k, 0, 0); s.emit(0xB0); s.word(yes + 4)
        s.emit(0x11, k, 0, 1); s.flag = None

    def tojump(s):
        """A jump if the condition (Rk, or the Test flag) is false: its address's place, to patch; Rk freed."""
        if s.flag is None: s.emit(0x8C, s.k); op = 0xA0
        else: op = 0xA1 if s.flag else 0xA0
        s.flag = None; s.k -= 1
        s.emit(op); at = s.pc; s.word(0); return at

    def ld(s, addr, r): s.emit(0x11, 0x0F); s.word(addr); s.emit(0x39, 0x02, 0xF0 | r)
    def st(s, r, addr): s.emit(0x11, 0x0F); s.word(addr); s.emit(0x3A, 0x02, (r << 4) | 0x0F)

    # ---- expressions (each leaves one more register in use, or the Test flag)
    PREC = [('||',), ('&&',), ('==', '!='), ('<', '<=', '>', '>='), ('|',), ('^',), ('&',), ('<<', '>>'),
            ('+', '-'), ('*', '/', '%')]

    def expr(s, lvl=0):
        if lvl == len(s.PREC): return s.unary()
        if lvl <= 1: return s.logic(lvl)
        s.expr(lvl + 1)
        while s.lx.kind == 'op' and s.lx.val in s.PREC[lvl]:
            op = s.lx.val; s.lx.next(); s.value()
            if op in ('<<', '>>'):
                n = s.cexpr()
                if n > 15: s.err('a shift over 15')
                a = s.k
                if op == '<<':
                    for _ in range(n): s.emit(0x50, a * 17, a)
                else:
                    b = s.push(); s.emit(0x11, b); s.word(1 << n); s.emit(0x4D, a * 16 + b, 0x21, 0x10 | a); s.k -= 1
                continue
            s.expr(lvl + 1); s.value()
            b = s.k; a = b - 1; s.k = a
            if op == '+': s.emit(0x50, a * 16 + b, a)
            elif op == '-': s.emit(0x51, a * 16 + b, a)
            elif op == '*': s.emit(0x4A, a * 16 + b, 0x21, 0x10 | a)
            elif op == '/': s.emit(0x4D, a * 16 + b, 0x21, 0x10 | a)
            elif op == '%': s.emit(0x4D, a * 16 + b, 0x27, 0x21, a)
            elif op in ('&', '|', '^'):
                s.emit(0x22, b, {'|': 0x63, '^': 0x64, '&': 0x65}[op], a, 0x21, 0x10 | a)
            elif op == '==': s.emit(0x87, a * 16 + b); s.flag = 1
            elif op == '!=': s.emit(0x87, a * 16 + b); s.flag = 0
            elif op == '<': s.emit(0x89, a * 16 + b); s.flag = 1
            elif op == '>=': s.emit(0x89, a * 16 + b); s.flag = 0
            elif op == '>': s.emit(0x89, b * 16 + a); s.flag = 1
            elif op == '<=': s.emit(0x89, b * 16 + a); s.flag = 0

    def logic(s, lvl):
        """|| (lvl 0) and && (1), short: the answer as a number, 0 or 1."""
        s.expr(lvl + 1)
        op = ('||', '&&')[lvl]
        if not s.lx.is_(op): return
        jumps = []
        while s.lx.take(op):
            jumps.append(s.cond_jump(lvl == 0))
            s.expr(lvl + 1)
        jumps.append(s.cond_jump(lvl == 0))
        k = s.push()                                    # (the operand's register, again)
        s.emit(0x11, k, 0, 0 if lvl == 0 else 1); s.emit(0xB0); end = s.pc; s.word(0)
        for at in jumps: s.patch(at, s.pc)
        s.emit(0x11, k, 0, 1 if lvl == 0 else 0); s.patch(end, s.pc)

    def cond_jump(s, when):
        """A jump (address to patch) taken when the operand is true (when=True) or false; its register freed."""
        if s.flag is None: s.emit(0x8C, s.k); f = 0                 # Test = 1: the value is 0 (false)
        else: f = s.flag
        s.flag = None; s.k -= 1
        s.emit(0xA0 if f == when else 0xA1); at = s.pc; s.word(0); return at

    def unary(s):
        if s.lx.take('-'):
            s.unary(); s.value(); k = s.k; s.emit(0x11, 0x0E, 0, 0, 0x51, 0xE0 | k, k); return
        if s.lx.take('~'):
            s.unary(); s.value(); k = s.k; s.emit(0x64, 0x10 | k, 0xFF, 0xFF, 0x21, 0x10 | k); return
        if s.lx.take('!'):
            s.unary()
            if s.flag is None: s.emit(0x8C, s.k); s.flag = 1
            else: s.flag ^= 1
            return
        s.primary()

    def primary(s):
        lx = s.lx
        if lx.take('('): s.expr(); lx.need(')'); return
        if lx.kind == 'num': k = s.push(); s.emit(0x11, k); s.word(lx.val); lx.next(); return
        if lx.kind != 'id': s.err('a value expected')
        n = lx.name()
        if lx.is_('('): return s.call(n, True)
        e = s.find(n)
        if not e: s.err('%s not defined' % n)
        if e[1] == 'c': k = s.push(); s.emit(0x11, k); s.word(e[2]); return
        if e[1] == 'v': k = s.push(); s.ld(e[2], k); return
        if e[1] == 'a':
            lx.need('['); s.expr(); s.value(); lx.need(']')
            k = s.k; s.emit(0x50, k * 17, k, 0x52, k); s.word(e[2]); s.emit(0x39, 0x02, k * 17); return
        s.err('%s is a function: ( expected' % n)

    def call(s, n, want):
        lx = s.lx; lx.need('(')
        if n in BUILTINS: return s.builtin(n, want)
        e = s.find(n)
        if not e or e[1] != 'f': s.err('no function %s() (defined before this?)' % n)
        if e is s.fn: s.err('%s() calls itself: no recursion' % n)
        if want and not e[3][1]: s.err('%s() gives no value' % n)
        k0 = s.k; nargs, _, pbase = e[3]
        for j in range(nargs):
            if j: lx.need(',')
            s.expr(); s.value()
        lx.need(')')
        if s.k - k0 != nargs: s.err('%s() takes %d values' % (n, nargs))
        for j in range(nargs): s.st(k0 + 1 + j, pbase + 2 * j)
        s.k = k0
        for r in range(1, k0 + 1): s.emit(0x72, r)
        s.emit(0xBD); s.word(e[2])
        for r in range(k0, 0, -1): s.emit(0x73, r)
        if want: k = s.push(); s.emit(0x23, 0x00, 0xD0 | k)

    def builtin(s, n, want):
        lx = s.lx
        if n == 'print':
            if want: s.err('print() gives no value')
            if lx.kind != 'str': s.err('print("text") expected')
            a = s.data(len(lx.val) + 1); s.img[a:a + len(lx.val)] = lx.val; lx.next(); lx.need(')')
            s.emit(0x11, 0x0F); s.word(a); s.emit(0xC1, 0x0F); return
        if n in ('printu', 'putc'):
            if want: s.err('%s() gives no value' % n)
            s.expr(); s.value(); lx.need(')'); k = s.k; s.k -= 1
            if n == 'printu': s.emit(0x22, k, 0x24, 0x6B, 0x00, 0x6E)
            else: s.emit(0x22, k, 0xC9)
            return
        if n in ('q', 'ef', 'waitef', 'rtc'):           # a constant: the line, or what to read
            if want and n in ('q', 'waitef'): s.err('%s() gives no value' % n)
            v = s.cexpr(); lx.need(')')
            lo, hi = {'q': (0, 3), 'ef': (1, 4), 'waitef': (1, 4), 'rtc': (0, 7)}[n]
            if v < lo or v > hi: s.err('n out of range: q 0-3, ef 1-4, rtc 0-7')
            if n == 'q': s.emit(0x0A, v); return                                # SETQ
            if n == 'waitef': s.emit(0x0F, v); return                           # WIP: on, then off
            k = s.push()
            if n == 'ef': s.emit(0x09, 0x1A, 1 << (v - 1)); s.flag = 1         # GETEFA, TESTBITI: on?
            elif v == 7: s.emit(0x07, 0x2B, 0x21, k, 0x86, k, 0x00, 0xFF); s.flag = 0   # register B $FF: none
            else:
                if s.rtcbuf is None: s.rtcbuf = s.data(8)
                s.emit(0x11, 0x0F); s.word(s.rtcbuf); s.emit(0x07, 0x0F)          # RTCGET: 8 bytes
                if v == 6: s.emit(0x11, 0x0F); s.word(s.rtcbuf + 6); s.emit(0x39, 0x02, 0xF0 | k)   # the year
                else: s.emit(0x11, 0x0E, 0, 0, 0x2E, 0x0E); s.word(s.rtcbuf + v); s.emit(0x21, k)
            if not want:
                s.flag = None; s.k -= 1
            return
        lx.need(')')
        if n == 'getc':
            k = s.push(); s.emit(0xCB, 0x21, k)
            if not want: s.k -= 1
            return
        if want: s.err('halt() gives no value')
        s.emit(0xB0, 0x00, 0x04)

    # ---- statements
    def stmt(s):
        lx = s.lx; s.k = 0; s.flag = None
        if lx.take('{'):
            while not lx.take('}'):
                if lx.kind == 'eof': s.err('} expected')
                s.stmt()
            return
        if lx.take(';'): return
        if lx.take('u16'):
            while True:
                n = lx.name()
                if lx.is_('['): s.err('arrays are declared outside functions')
                a = s.data(2); s.add(n, 'v', a)
                if lx.take('='): s.k = 0; s.expr(); s.value(); s.st(1, a); s.k = 0
                if not lx.take(','): break
            lx.need(';'); return
        if lx.take('if'):
            lx.need('('); s.expr(); lx.need(')'); at = s.tojump()
            s.stmt()
            if lx.take('else'):
                s.emit(0xB0); end = s.pc; s.word(0); s.patch(at, s.pc); s.stmt(); s.patch(end, s.pc)
            else: s.patch(at, s.pc)
            return
        if lx.take('while'):
            top = s.pc; lx.need('('); s.expr(); lx.need(')'); at = s.tojump()
            s.loops.append([[at], top]); s.stmt()
            s.emit(0xB0); s.word(top); s.endloop(); return
        if lx.take('for'):
            lx.need('(')
            if not lx.is_(';'): s.simple()
            lx.need(';'); top = s.pc; ends = []
            if not lx.is_(';'): s.k = 0; s.expr(); ends.append(s.tojump())
            lx.need(';')
            s.emit(0xB0); body = s.pc; s.word(0)
            step = s.pc
            if not lx.is_(')'): s.simple()
            lx.need(')'); s.emit(0xB0); s.word(top); s.patch(body, s.pc)
            s.loops.append([ends, step]); s.stmt()
            s.emit(0xB0); s.word(step); s.endloop(); return
        if lx.take('break'):
            if not s.loops: s.err('break outside a loop')
            lx.need(';'); s.emit(0xB0); s.loops[-1][0].append(s.pc); s.word(0); return
        if lx.take('continue'):
            if not s.loops: s.err('continue outside a loop')
            lx.need(';'); s.emit(0xB0); s.word(s.loops[-1][1]); return
        if lx.take('return'):
            if not lx.is_(';'):
                if not s.fn[3][1]: s.err('a void function returns no value')
                s.expr(); s.value(); s.emit(0x23, 0x00, 0x10 * s.k + 0xD)
            elif s.fn[3][1]: s.err('return: a value expected')
            lx.need(';'); s.emit(0xBE, 0x00); return
        s.simple(); lx.need(';')

    def endloop(s):
        for at in s.loops.pop()[0]: s.patch(at, s.pc)

    def simple(s):
        """x = e, x op= e, x++, x--, a[i] ..., f(...)"""
        lx = s.lx; s.k = 0; s.flag = None
        n = lx.name()
        if lx.is_('('): return s.call(n, False)
        e = s.find(n)
        if not e or e[1] not in ('v', 'a'): s.err('%s is not a variable' % n)
        if e[1] == 'a':
            lx.need('['); s.expr(); s.value(); lx.need(']')
            s.emit(0x50, 0x11, 0x01, 0x52, 0x01); s.word(e[2])                 # R1 = the element's address
            ld = lambda: s.emit(0x39, 0x02, 0x12)                             # R2 = it
            sv = lambda: s.emit(0x3A, 0x02, 0x21)
        else:
            ld = lambda: s.ld(e[2], s.k)
            sv = lambda: s.st(1, e[2])
        if lx.take('='): s.expr(); s.value(); return sv()
        op = lx.val if lx.kind == 'op' else ''
        if op not in ('++', '--', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^='): s.err('= expected')
        lx.next()
        k = s.push(); ld()
        if op in ('++', '--'): s.emit(0x42 if op == '++' else 0x43, k); return sv()
        s.expr(); s.value(); b = s.k; a = k; s.k = a
        o = op[0]
        if o == '+': s.emit(0x50, a * 16 + b, a)
        elif o == '-': s.emit(0x51, a * 16 + b, a)
        elif o == '*': s.emit(0x4A, a * 16 + b, 0x21, 0x10 | a)
        elif o == '/': s.emit(0x4D, a * 16 + b, 0x21, 0x10 | a)
        elif o == '%': s.emit(0x4D, a * 16 + b, 0x27, 0x21, a)
        else: s.emit(0x22, b, {'|': 0x63, '^': 0x64, '&': 0x65}[o], a, 0x21, 0x10 | a)
        sv()

    # ---- the program
    def program(s):
        lx = s.lx
        s.emit(0xCD, 0xBD, 0, 0, 0x00)
        while lx.kind != 'eof':
            if lx.take('const'):
                n = lx.name(); lx.need('='); s.add(n, 'c', s.cexpr()); lx.need(';'); continue
            if lx.take('void'): s.function(lx.name(), False); continue
            if not lx.take('u16'): s.err('u16, void or const expected')
            n = lx.name()
            if lx.is_('('): s.function(n, True); continue
            while True:
                if lx.take('['):
                    sz = s.cexpr(); lx.need(']')
                    if not 1 <= sz <= 2000: s.err('an array of 1-2000 expected')
                    s.add(n, 'a', s.data(2 * sz))
                else:
                    a = s.data(2); s.add(n, 'v', a)
                    if lx.take('='): v = s.cexpr(); s.img[a] = v >> 8; s.img[a + 1] = v & 0xFF
                if not lx.take(','): break
                n = lx.name()
            lx.need(';')
        m = s.find('main')
        if not m or m[1] != 'f': raise Error(lx.line, 'no main()')
        s.emit(0xF0, 0x00, 0x00)
        return s.stl()

    def function(s, n, val):
        lx = s.lx; lx.need('(')
        params = []
        if not lx.is_(')'):
            while True:
                lx.need('u16'); params.append(lx.name())
                if not lx.take(','): break
        lx.need(')')
        pbase = s.data(2 * len(params)) if params else s.dtop
        e = s.add(n, 'f', s.pc, (len(params), val, pbase))
        if n == 'main': s.patch(s.mainfix, s.pc)
        s.nglob = len(s.syms); s.fn = e
        for j, p in enumerate(params): s.add(p, 'v', pbase + 2 * j)
        if not lx.is_('{'): s.err('{ expected')
        s.stmt()
        s.emit(0xBE, 0x00)
        del s.syms[s.nglob:]; s.fn = None

    def stl(s):
        """'STL1', 9 blocks: $4000-$4BFF (6) and a 0 at $5000 $6000 $7000 (no other VM runs)."""
        blocks = [0x40, 0x42, 0x44, 0x46, 0x48, 0x4A, 0x50, 0x60, 0x70]
        head = b'STL1' + bytes([len(blocks)]) + b''.join(bytes([b, 0]) for b in blocks)
        return head.ljust(512, b'\0') + bytes(s.img) + bytes(3 * 512)


def compile_text(src):
    return Compiler(src).program()


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('-')]
    if not a: print(__doc__); return 1
    src = open(a[0], encoding='latin-1').read()
    try: stl = compile_text(src)
    except Error as e: print('%s %s' % (a[0], e)); return 1
    out = os.path.splitext(a[0])[0] + '.STL'
    open(out, 'wb').write(stl); print('%s -> %s' % (a[0], out)); return 0


if __name__ == '__main__':
    sys.exit(main())
