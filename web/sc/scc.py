# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
# Its output: see COPYING.EXCEPTION.
"""scc - the Stellar C compiler (prototype).

Stellar C is a small C-like language shaped to what STELLAR does in one opcode:

    const N = 10;                 compile-time constants
    u16 score = 0;                16-bit unsigned scalars -> VM registers
    u8  grid[800];                byte arrays -> memory, READIDX / WRITEIDX
    u8  msg[] = "hello";          initialised byte arrays (a string is one)
    patched u8 pos[] = "\e[rr;ccH";   an array whose written bytes are always set before
                                  they are read: it is not restored at start
    u16 f(u16 a, u16 b) { ... }   functions; parameters and locals are registers
    void g() { ... }

    statements  if / else, while, for, break, continue, return, x = e,
                x += e (-= *= /= %= &= |= ^=), x++, x--, a[i] = e, calls
    conditions  == != < <= > >= && || !   (all unsigned)
    expressions + - * / % & | ^ << >> (by a constant), unary -, a[i], calls
    builtins    putc(e)  print("text")  printu(e)  getc()  keyready()
                rand()   rand(n)        delay(k)       halt()
    Elf2K I/O   out(e) outmem(a) outport(p) q(e) scanin() getin() inport(p)
                efsource(n) ef() waitef()      ($01-$0F, see ARITY below)
    asm { }     inline STELLAR, one command per line (see ASM below)
    native { }  raw 1802, run by $F1 RUNMC (see NATIVE below)
    tasks       task f() { }  shared u16 x;  chan c[n];  send recv ready wait turns  atomic { }
                - one program in several VMs (see MULTITASKING below; compile_program)

WHAT IT BUYS OVER HAND-ASSEMBLY: every hard-won STELLAR rule is in the compiler, not in
the programmer's head - address branches only (no label machinery),
relative addressing, $89 TESTLXY is strictly <, the F0 00 00 end marker, every array a
program writes is (re)initialised in code at start (rerun without reloading), SETSIZE
and the VM claims when the program outgrows 4 KB, and the .lst house format with the
source line on every opcode.

THE MODEL: no recursion and no stack frames - STELLAR has 15 fast registers and no
indexed stack, so every variable gets a REGISTER for the whole run, and two functions
that are never active at the same time share registers (the call graph decides).
Recursion is refused at compile time. RD-RF are expression temporaries and RD also
carries return values; R0-RC hold variables (RC is 0 when the program needs a zero).

    python3 scc.py prog.sc [-o prog.lst]
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
from mini import assemble, claim_vms_text
from stellar_ops import *


class Error(Exception): pass

# ====================================================================== lexer
TOK = re.compile(r'''
    (?P<ws>\s+|//[^\n]*|/\*.*?\*/)
  | (?P<num>0[xX][0-9a-fA-F]+|\d+)
  | (?P<chr>'(?:\\.|[^\\'])')
  | (?P<str>"(?:\\.|[^\\"])*")
  | (?P<id>[A-Za-z_]\w*)
  | (?P<op><<=|>>=|==|!=|<=|>=|&&|\|\||\+\+|--|\+=|-=|\*=|/=|%=|&=|\|=|\^=|<<|>>|[-+*/%&|^!<>=(){}\[\];,~:])
''', re.S | re.X)
ESCAPES = {'n': 10, 'r': 13, 't': 9, 'b': 8, 'e': 27, '0': 0, '\\': 92, "'": 39, '"': 34}

def unescape(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == '\\':
            if s[i + 1] == 'x': out.append(int(s[i + 2:i + 4], 16)); i += 4; continue
            out.append(ESCAPES[s[i + 1]]); i += 2
        else: out.append(ord(s[i])); i += 1
    return out

ASM = re.compile(r'(asm|native)\s*\{')

def lex(src):
    toks, pos, line = [], 0, 1
    while pos < len(src):
        m = ASM.match(src, pos)
        if m and (pos == 0 or not (src[pos - 1].isalnum() or src[pos - 1] == '_')):
            depth, j = 1, m.end()                   # the body is kept raw: {x} nests
            while depth:
                if j == len(src): raise Error('line %d: asm { is never closed' % line)
                depth += {'{': 1, '}': -1}.get(src[j], 0); j += 1
            first = line + src[pos:m.end()].count('\n')
            toks.append(('asm', (m.group(1), first, src[m.end():j - 1]), line))
            line += src[pos:j].count('\n'); pos = j; continue
        m = TOK.match(src, pos)
        if not m: raise Error('line %d: cannot read %r' % (line, src[pos:pos + 10]))
        k, v = m.lastgroup, m.group()
        if k == 'num': toks.append(('num', int(v, 0), line))
        elif k == 'chr': toks.append(('num', unescape(v[1:-1])[0], line))
        elif k == 'str': toks.append(('str', unescape(v[1:-1]), line))
        elif k != 'ws': toks.append((k, v, line))
        line += v.count('\n'); pos = m.end()
    toks.append(('eof', None, line))
    return toks

# ====================================================================== asm { }
# One STELLAR command per line, written as the mnemonic (or its opcode byte) and then its
# operand bytes in hex. Inside an operand:
#     {x}      the register variable x lives in, as one hex digit:  COPYXY 00 {a}{b}
#     {f.x}    function f's variable x (to set up a CALL @f by hand)
#     #e       two bytes: a constant, &array or &array+k             LOADXI 0{p} #&buf
#     %e       one byte: a constant                                  SEROUTI %'*'
#     'c'      one byte: a character
#     @name    a label: one in this function's asm, a function, or break / continue / return
#     name:    defines a label
# Comments start with // or ;. Each command's length is checked against the opcode table.
# The asm may use RD, RE and RF freely; it must leave RC as it found it.
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
from stellar_disasm import OPLEN, NAMES, vlen
OPCODE = {v: k for k, v in NAMES.items()}
ATOK = re.compile(r"'(?:\\.|[^\\'])'|\S+")

def asm_parse(first, text):
    """-> (lines, refs): lines are (line, label, words); refs are ('var', x) and
    ('call', f, []) nodes, so the liveness, allocation and call-graph passes see them."""
    lines, refs = [], []
    for i, raw in enumerate(text.split('\n')):
        body = re.split(r'//|;', raw, 1)[0]
        m = re.match(r'\s*([A-Za-z_]\w*):', body)
        label = m.group(1) if m else None
        words = ATOK.findall(body[m.end():] if m else body)
        if label or words: lines.append((first + i, label, words))
        for w in words[1:]:
            refs += [('var', v) for v in re.findall(r'\{(\w+)\}', w)]
            if w.startswith('@'): refs.append(('call', w[1:], []))
    return lines, refs

# ====================================================================== native { }
# Raw 1802, run in place by $F1 RUNMC. The compiler puts the code after the program's
# data, where the STELLAR pre-pass never looks, and emits RUNMC <its absolute address>
# where the block stands. Operands are expressions:
#     {x}      the ABSOLUTE address of variable x's VM register (high byte; {x}+1 is the
#              low byte): VM1's registers live in its core at $3000 + 2n
#     &a, a    the absolute address of array a (&a+k, &a[k])
#     hi(e) lo(e)   the two halves of an address
#     $41 0x41 65 'A'   numbers; const names; labels (local to the block)
# The block ends with SEX R2 / RETN (label exit:), so BR exit or falling off the end
# goes home. Free registers: R7 R8 R9 RB RD RE RF (the RUNMC handler saves them), and R2
# as the stack. R3 is the PC, R6 the way home, RA's low byte is not restored by
# V0061.34 - writing any register but those is refused. X is unknown on entry: SEX
# before any STR, OUT or ALU-with-memory. RUNMC does not yield: other VMs wait.
from asm1802 import assemble as assemble1802, register, AsmError
NATIVE_FREE = {7, 8, 9, 0xB, 0xD, 0xE, 0xF}
# Where the program runs: VM1 by default; scc --vm N builds it for VM N's block (program at
# $4000 + (N-1) x $1000, registers at $3000 + (N-1) x $400) - the absolute addresses (D-lines,
# native code, RUNMC, {var}) move, the bytecode itself is relative anyway.
ORG = 0x4000
REGS = 0x3000
VM = 1
TOP = 0x7F00          # programs end below this: the Elf2K's $7Fxx page is not available
STOPPED = 0x03        # a VM's CIDP state after stop(): the scheduler skips it, and wake-ups (only of 4) pass it by


def set_vm(n):
    global ORG, REGS, VM
    if n not in (1, 2, 3, 4): raise Error('--vm must be 1-4')
    VM, ORG, REGS = n, 0x4000 + (n - 1) * 0x1000, 0x3000 + (n - 1) * 0x400

def strip_comment(line):
    q = None
    for i, ch in enumerate(line):
        if q:
            if ch == q and line[i - 1] != '\\': q = None
        elif ch in '"\'': q = ch
        elif ch == ';' or line.startswith('//', i): return line[:i]
    return line

def native_parse(first, text):
    lines, refs = [], []
    for i, raw in enumerate(text.split('\n')):
        body = strip_comment(raw)
        m = re.match(r'\s*([A-Za-z_]\w*):', body)
        label = m.group(1) if m else None
        rest = (body[m.end():] if m else body).strip()
        mn, _, arg = rest.partition(' ') if ' ' in rest else rest.partition('\t')
        if label or mn: lines.append((first + i, label, mn.upper() or None, arg.strip()))
        refs += [('var', v) for v in re.findall(r'\{(\w+)\}', arg)]
    return lines, refs

# ====================================================================== parser
# expressions: ('num', v) ('var', name) ('idx', name, e) ('call', name, [args])
#              ('bin', op, a, b) ('neg', e) ('not', e) ('addr', name, e) ('str', bytes)
# statements carry their source line: (kind, line, ...)
PREC = [('||',), ('&&',), ('==', '!='), ('<', '<=', '>', '>='), ('|',), ('^',), ('&',),
        ('<<', '>>'), ('+', '-'), ('*', '/', '%')]

TYPES = ('u16', 'u8', 'i16')

class Parser:
    def __init__(s, toks): s.t = toks; s.i = 0; s.signed = set(); s.cur = None
    def peek(s, k=0): return s.t[s.i + k]
    def line(s): return s.t[s.i][2]
    def take(s, v=None, kind=None):
        t = s.t[s.i]
        if (v is not None and t[1] != v) or (kind and t[0] != kind):
            raise Error('line %d: expected %s, found %r' % (t[2], v or kind, t[1]))
        s.i += 1; return t
    def accept(s, v):
        if s.t[s.i][1] == v and s.t[s.i][0] == 'op': s.i += 1; return True
        return False

    def program(s):
        items = []
        while s.peek()[0] != 'eof':
            ln = s.line()
            if s.peek()[1] == 'const':
                s.take(); n = s.take(kind='id')[1]; s.take('='); e = s.expr(); s.take(';')
                items.append(('const', ln, n, e)); continue
            if s.peek()[1] == 'task' and s.peek(1)[0] in ('id', 'op'):      # task [(vm)] [void] name() { }
                s.take(); pin = None
                if s.accept('('): pin = s.expr(); s.take(')')
                if s.peek()[1] == 'void': s.take()
                name = s.take(kind='id')[1]; s.take('(')
                if not s.accept(')'): raise Error('line %d: a task takes no parameters' % ln)
                s.cur = name; body = s.block(); s.cur = None
                items.append(('task', ln, name, pin, body)); continue
            if s.peek()[1] == 'chan' and s.peek(1)[0] == 'id':                # chan name[n];
                s.take(); n = s.take(kind='id')[1]; s.take('['); size = s.expr(); s.take(']'); s.take(';')
                items.append(('chan', ln, n, size)); continue
            if s.peek()[1] == 'shared' and s.peek(1)[1] in TYPES:            # shared u16 x;  shared u8 a[n];
                s.take(); ty = s.take(kind='id')[1]; name = s.take(kind='id')[1]
                d = s.decl_rest(ty, name, ln, top=True)
                items += d; items.append(('shared', ln, [x[2] for x in d])); continue
            patched = s.peek()[1] == 'patched' and s.take()
            ty = s.take(kind='id')[1]
            if ty not in TYPES + ('void',): raise Error('line %d: unknown type %r' % (ln, ty))
            name = s.take(kind='id')[1]
            if patched:
                d = s.decl_rest(ty, name, ln, top=True)
                items += [x + ('patched',) for x in d]; continue
            if s.accept('('):
                params = []; s.cur = name
                while not s.accept(')'):
                    pty = s.take(kind='id')[1]
                    if pty not in TYPES: raise Error('line %d: unknown type %r' % (ln, pty))
                    params.append(s.take(kind='id')[1]); s.accept(',')
                    if pty == 'i16': s.signed.add((name, params[-1]))
                items.append(('func', ln, ty, name, params, s.block())); s.cur = None; continue
            items += s.decl_rest(ty, name, ln, top=True)
        items.append(('signed', ln, s.signed))
        return items

    def decl_rest(s, ty, name, ln, top=False):
        out = []
        while True:
            if s.accept('['):
                size = None if s.peek()[1] == ']' else s.expr()
                s.take(']')
                init = None
                if s.accept('='):
                    if s.peek()[0] == 'str': init = s.take()[1] + [0]
                    else:
                        s.take('{'); init = []
                        while not s.accept('}'): init.append(s.expr()); s.accept(',')
                if ty == 'i16': s.signed.add((None, name))
                out.append(('array', ln, name, size, init, ty))
            else:
                init = s.expr() if s.accept('=') else None
                if ty == 'i16': s.signed.add((s.cur if not top else None, name))
                out.append(('scalar', ln, name, init, 'u16' if ty == 'i16' else ty))
            if s.accept(';'): return out
            s.take(','); name = s.take(kind='id')[1]

    def block(s):
        s.take('{'); body = []
        while not s.accept('}'): body.append(s.stmt())
        return ('block', body)

    def stmt(s):
        ln = s.line(); t = s.peek()
        if t[1] == '{': return s.block()
        if t[0] == 'id' and t[1] in TYPES:
            s.take(); name = s.take(kind='id')[1]
            decls = s.decl_rest(t[1], name, ln)
            if any(d[0] == 'array' for d in decls): raise Error('line %d: arrays are declared outside functions' % ln)
            return ('block', [('local', d[1], d[2], d[3]) for d in decls])
        if t[1] == 'switch':
            s.take(); s.take('('); e = s.expr(); s.take(')'); s.take('{'); items = []
            while not s.accept('}'):
                if s.peek()[1] == 'case':
                    cl = s.line(); s.take(); v = s.expr(); s.take(':'); items.append(('case', cl, v))
                elif s.peek()[1] == 'default':
                    cl = s.line(); s.take(); s.take(':'); items.append(('default', cl))
                else: items.append(s.stmt())
            return ('switch', ln, e, items)
        if t[1] == 'if':
            s.take(); s.take('('); c = s.expr(); s.take(')'); a = s.stmt()
            b = s.stmt() if s.peek()[1] == 'else' and s.take() else None
            return ('if', ln, c, a, b)
        if t[1] == 'while':
            s.take(); s.take('('); c = s.expr(); s.take(')'); return ('while', ln, c, s.stmt(), None)
        if t[1] == 'for':
            s.take(); s.take('(')
            init = None if s.peek()[1] == ';' else s.simple()
            s.take(';'); c = ('num', 1) if s.peek()[1] == ';' else s.expr(); s.take(';')
            step = None if s.peek()[1] == ')' else s.simple()
            s.take(')')
            return ('block', ([init] if init else []) + [('while', ln, c, s.stmt(), step)])
        if t[1] in ('break', 'continue'): s.take(); s.take(';'); return (t[1], ln)
        if t[1] == 'atomic' and s.peek(1)[1] == '{':
            s.take(); return ('atomic', ln, s.block())
        if t[0] == 'asm':
            s.take(); kind, first, text = t[1]
            return (kind, ln) + (asm_parse if kind == 'asm' else native_parse)(first, text)
        if t[1] == 'return':
            s.take(); e = None if s.peek()[1] == ';' else s.expr(); s.take(';'); return ('return', ln, e)
        st = s.simple(); s.take(';')
        if st[0] == 'expr' and st[2][1] == 'wait':                 # wait(condition): sleep until it is true
            if len(st[2][2]) != 1: raise Error('line %d: wait(condition) takes one argument' % ln)
            return ('wait', ln, st[2][2][0])
        if st[0] == 'expr' and st[2][1] in ('stop', 'start') and st[2][0] == 'call':   # stop(task) / start(task)
            a = st[2][2]
            if len(a) != 1 or a[0][0] != 'var':
                raise Error('line %d: %s(task) takes the name of a task' % (ln, st[2][1]))
            return (st[2][1], ln, a[0][1])
        inner = []
        _walk(st, lambda x: inner.append(x[1]) if x[0] == 'call' and x[1] in ('stop', 'start') else None)
        if inner: raise Error('line %d: %s(task) is a statement of its own, not a value' % (ln, inner[0]))
        return st

    def simple(s):
        ln = s.line(); target = s.unary()
        t = s.peek()[1]
        if t in ('=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>='):
            s.take(); e = s.expr()
            if t != '=': e = ('bin', t[:-1], target, e)
            return ('assign', ln, target, e)
        if t in ('++', '--'): s.take(); return ('assign', ln, target, ('bin', t[0], target, ('num', 1)))
        if target[0] != 'call': raise Error('line %d: a statement must assign or call' % ln)
        return ('expr', ln, target)

    def expr(s, lvl=0):
        if lvl == len(PREC): return s.unary()
        a = s.expr(lvl + 1)
        while s.peek()[0] == 'op' and s.peek()[1] in PREC[lvl]:
            op = s.take()[1]; a = ('bin', op, a, s.expr(lvl + 1))
        return a

    def unary(s):
        if s.accept('-'): return ('neg', s.unary())
        if s.accept('!'): return ('not', s.unary())
        if s.accept('~'): return ('bin', '^', s.unary(), ('num', 0xFFFF))
        if s.accept('&'):                                   # &a[i] or &a: an address
            n = s.take(kind='id')[1]
            if s.accept('['): e = s.expr(); s.take(']'); return ('addr', n, e)
            return ('addr', n, ('num', 0))
        if s.accept('('): e = s.expr(); s.take(')'); return e
        t = s.take()
        if t[0] == 'num': return ('num', t[1] & 0xFFFF)
        if t[0] == 'str': return ('str', t[1])
        if t[0] != 'id': raise Error('line %d: unexpected %r' % (t[2], t[1]))
        if s.accept('('):
            args = []
            while not s.accept(')'): args.append(s.expr()); s.accept(',')
            if t[1] == 'rand' and args:                     # rand(n): 0 .. n - 1, as rand() % n
                if len(args) > 1: raise Error('line %d: rand() or rand(n)' % t[2])
                return ('bin', '%', ('call', 'rand', []), args[0])
            return ('call', t[1], args)
        if s.accept('['): e = s.expr(); s.take(']'); return ('idx', t[1], e)
        return ('var', t[1])

# ====================================================================== compiler
TEMPS = [0xF, 0xE, 0xD]           # expression temporaries
RV = 0xD                          # return values
ZERO = 0xC                        # holds 0 when the program needs it: a[k], u8 variables
BUILTINS = {'turns', 'putc', 'print', 'printu', 'getc', 'keyready', 'rand', 'delay', 'halt', 'fill', 'copy',
            'out', 'outmem', 'outport', 'inport', 'getin', 'scanin', 'ef', 'efsource', 'waitef', 'q',
            'cls', 'eol', 'rev', 'cursor', 'at', 'printz', 'printw', 'printh', 'getline',
            'rtcget', 'rtcset', 'peek', 'poke', 'peekw', 'pokew', 'printi'}
#   printi(e)       e as a SIGNED number: a '-' and its size if negative
# Terminal, number formatting, line input, the RTC and absolute memory (2026-10-04):
#   cls() eol() rev(on) cursor(on)   VT100: clear + home, erase to end of line, reverse video,
#                                    show/hide the cursor - each one PRINTSTR of a constant string
#   at(row, col)    cursor to row, col (1-based): constants -> one string; else LIB_AT (decimal)
#   printz(e, n)    e as exactly n digits, zero-padded (n 1-5; a larger e shows its low n digits)
#   printw(e, n)    e right-aligned in n columns, space-padded (same rule)
#   printh(e[, n])  e as n hex digits (1-4, default 4)
#   getline(buf[, max])  a line of at most max characters (default: the array's size - 1) into the
#                   u8 array buf, NUL-terminated, echoed, Backspace works, Enter echoes CR LF;
#                   returns its length. Bounded - unlike $C2 GETSTR, which has no limit.
#   rtcget(t) / rtcset(t)  $07 RTCGET / RTCSET with the 8-byte u8 array t: sec min hour weekday(0=Sun)
#                   day month year-hi year-lo. rtcset returns 1 if the firmware wrote it, 0 if refused.
#                   Needs firmware V0061.35 or later (the $07 RTC opcode).
#   peek(a) poke(a, v) peekw(a) pokew(a, v)   a byte / 16-bit word at the ABSOLUTE address a
#                   (MEMMODE 00 for those few opcodes, no branch while absolute)
LIBS = {}   # library routines a program uses: emitted once, after its functions
# The Elf2K I/O group, $01-$0F, on V0061.34 + the DEFEF DZ, WIP and WIP Z patches (HW-verified 2026-09-30):
#   outport(p)  $01 DEFOUT 0p   output port 1-7; 2 and 3 are the serial chip, so refused
#   inport(p)   $02 DEFIN 0Z    input port 1-7 (Z = p + 8)
#   efsource(n) $03 DEFEF n0    the EF line getin() and waitef() wait on, 1-4 (default 4, INPUT);
#   efsource(n, 1)  DEFEF n1    ... inverted (active low). Needs the DEFEF DZ patch: unpatched
#                               V0061.34 read n from the low nibble and stopped with error $0E
#   out(e)      $04 OUTI / $06 OUTX / $05 OUTA 00   a byte to the output port (the hex display)
#   outmem(a)   $08 OUTMX       the byte at address a to the output port
#   ef()        $09 GETEFA      all four EF lines as a mask: bit 0 = EF1 ... bit 3 = EF4 (GETEFA mask patch)
#   ef(n)       GETEFA + $1A TESTBITI   1 if EF line n (1-4) is on, else 0
#   q(e)        $0A SETQ        0 off, 1 on (any non-constant: on if non-zero), 2 one blink, 3 two
#   scanin()    $0C SIPA        read the input port now
#   getin()     $0D GIPA / $0E GIPX   wait for the EF line (the INPUT button) to go high then low,
#                               then read the input port
#   waitef()    $0F WIP 00      wait for the efsource() line to go active then inactive, yielding
#                               to the other VMs meanwhile (unpatched: the output port's number!)
#   waitef(n)   $0F WIP 0n      ... on EF line n, 1-4, normal, whatever efsource() says
ARITY = {'out': 1, 'outmem': 1, 'outport': 1, 'inport': 1, 'getin': 0, 'scanin': 0, 'ef': (0, 1),
         'efsource': (1, 2), 'waitef': (0, 1), 'q': 1}
# ops after which a DIVXY's quotient/remainder are still in the MA
KEEPS_MA = {'COPYAX', 'TESTREMZ', 'IFTRUEI', 'IFFALSEI', 'TESTXY', 'TESTXI', 'TESTXZ',
            'TESTLXY', 'TESTGXY', 'COPYXY', 'LOADXI'}
WRITES_REG = re.compile(r'-> R(\d+)$|^(?:LOADXI|INCX|DECX|ADDXI|SUBXI) R(\d+)')
EXPRS = ('num', 'var', 'idx', 'call', 'bin', 'neg', 'not', 'addr', 'str')


class Compiler:
    def __init__(s, items, name, entry='main', mt=None):
        s.name = name
        s.entry = entry                  # the function the program starts with: main(), or a task's own
        s.mt = mt                        # a part of a multitasking program (see compile_program), else None
        s.shared = set()
        s.atomic = 0                     # inside atomic { }: SETMULTI 00 is on
        s.consts, s.globals, s.arrays, s.funcs, s.bytevars = {}, {}, {}, {}, {}
        for it in items:
            if it[0] == 'const': s.consts[it[2]] = s.const(it[3], it[1])
            elif it[0] == 'scalar' and it[4] == 'u8':           # a u8 variable: one byte of memory
                s.bytevars[it[2]] = it; s.arrays[it[2]] = ('array', it[1], it[2], ('num', 1), None)
            elif it[0] == 'scalar': s.globals[it[2]] = it
            elif it[0] == 'array': s.arrays[it[2]] = it
            elif it[0] == 'func': s.funcs[it[3]] = it
            elif it[0] == 'signed': s.signed = it[2]
            elif it[0] == 'shared': s.shared.update(it[2])
        if not hasattr(s, 'signed'): s.signed = set()
        if entry not in s.funcs: raise Error('no main()')
        for n, fn in list(s.funcs.items()):                     # u8 variable x  ->  x[0]
            s.funcs[n] = fn[:5] + (s.desugar(fn[5]),)
        s.written = set()
        s.scan_writes()
        if mt and mt['role'] == 'main': s.written |= {a for a in s.shared if a in s.arrays}   # set up every run
        s.patched = {n for n, it in s.arrays.items() if it[-1] == 'patched'}
        s.need_zero = bool(s.bytevars) or s.uses_const_index()
        s.setsize = 1
        s.allocate()

    def desugar(s, node):
        if isinstance(node, list): return [s.desugar(x) for x in node]
        if not isinstance(node, tuple): return node
        if node[0] == 'var' and node[1] in s.bytevars and node[1] not in s.arrays_wide(): return ('idx', node[1], ('num', 0))
        return tuple(s.desugar(x) if isinstance(x, (tuple, list)) else x for x in node)

    def const(s, e, ln):
        if e[0] == 'num': return e[1]
        if e[0] == 'flip': return (s.const(e[1], ln) + 0x8000) & 0xFFFF
        if e[0] == 'var' and e[1] in getattr(s, 'consts', {}): return s.consts[e[1]]
        if e[0] == 'neg': return (-s.const(e[1], ln)) & 0xFFFF
        if e[0] == 'bin' and e[1] in ('/', '%', '>>') and (s.has_neg(e[2]) or s.has_neg(e[3])):
            # a constant with a minus sign in it is folded the way C does: signed
            sg = lambda v: v - 0x10000 if v & 0x8000 else v
            a, b = sg(s.const(e[2], ln)), sg(s.const(e[3], ln))
            if e[1] == '>>': return (a >> b) & 0xFFFF
            if b == 0: raise Error('line %d: division by zero' % ln)
            q = abs(a) // abs(b) * (1 if (a < 0) == (b < 0) else -1)
            return (q if e[1] == '/' else a - b * q) & 0xFFFF
        if e[0] == 'bin' and e[1] in '+-*/%&|^<<>>':
            a, b = s.const(e[2], ln), s.const(e[3], ln)
            return {'+': a + b, '-': a - b, '*': a * b, '/': a // max(b, 1), '%': a % max(b, 1),
                    '&': a & b, '|': a | b, '^': a ^ b, '<<': a << b, '>>': a >> b}[e[1]] & 0xFFFF
        raise Error('line %d: not a constant' % ln)

    def has_neg(s, e):
        if not isinstance(e, tuple): return False
        if e[0] == 'neg': return True
        return any(s.has_neg(x) for x in e[1:] if isinstance(x, tuple))

    def isconst(s, e):
        try: s.const(e, 0); return True
        except (Error, KeyError, TypeError, IndexError): return False

    def arrays_wide(s):
        return {n for n, it in s.arrays.items() if len(it) > 5 and it[5] in ('u16', 'i16')}
    def wide(s, name): return name in s.arrays and len(s.arrays[name]) > 5 and s.arrays[name][5] in ('u16', 'i16')

    def is_signed(s, e):
        """Does e have a signed (i16) value? Then <, <=, >, >=, /, %, >> and printing treat it as signed."""
        k = e[0]
        if k == 'var':
            if e[1] in s.consts or e[1] in s.arrays: return False
            if s.fn is not None and (s.fn, e[1]) in s.signed: return True
            if s.fn is not None and e[1] in s.fvars_of(s.fn): return False
            return (None, e[1]) in s.signed
        if k == 'idx': return (None, e[1]) in s.signed
        if k == 'call': return e[1] in s.funcs and s.funcs[e[1]][2] == 'i16'
        if k == 'neg': return s.is_signed(e[1])
        if k == 'bin' and e[1] in ('+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>'):
            return s.is_signed(e[2]) or s.is_signed(e[3])
        return False

    # ---------------------------------------------------------- analysis
    def walk(s, node, fn):
        if isinstance(node, tuple):
            fn(node)
            for x in node[1:]:
                if isinstance(x, (tuple, list)): s.walk(x, fn)
        elif isinstance(node, list):
            for x in node: s.walk(x, fn)

    def scan_writes(s):
        def f(n):
            if n[0] == 'assign' and n[2][0] == 'idx': s.written.add(n[2][1])
            if n[0] == 'call' and n[1] in ('fill', 'copy') and n[2] and n[2][0][0] == 'addr':
                s.written.add(n[2][0][1])
            if n[0] == 'call' and n[1] in ('getline', 'rtcget') and n[2] and n[2][0][0] == 'var':
                s.written.add(n[2][0][1])
        for fn in s.funcs.values(): s.walk(fn[5], f)

    def uses_const_index(s):
        found = []
        def f(n):
            if n[0] == 'idx' and s.isconst(n[2]): found.append(n)
        for fn in s.funcs.values(): s.walk(fn[5], f)
        return bool(found)

    def vars_in(s, e):
        """The u16 variables an expression reads."""
        out = set()
        def f(x):
            if x[0] == 'var' and x[1] not in s.consts and x[1] not in s.arrays: out.add(x[1])
        s.walk(e, f)
        return out

    def usage(s, n, fn):
        """For one function: each variable's weight (uses x 10 per loop level), and whether
        its value is LIVE across a call to another function (then it cannot share a register
        with anything that function might use). Liveness is the usual backward dataflow over
        the statements, loops iterated to a fixed point."""
        weight, loops = {}, [0]
        def count(e):
            for v in s.vars_in(e): weight[v] = weight.get(v, 0) + 10 ** min(loops[0], 3)
        def cnt(st):
            k = st[0]
            if k == 'block':
                for x in st[1]: cnt(x)
            elif k == 'while':
                loops[0] += 1; count(st[2]); cnt(st[3])
                if st[4]: cnt(st[4])
                loops[0] -= 1
            elif k == 'if':
                count(st[2]); cnt(st[3])
                if st[4]: cnt(st[4])
            elif k == 'switch':
                count(st[2])
                for x in st[3]:
                    if x[0] not in ('case', 'default'): cnt(x)
            elif k == 'local':
                weight[st[2]] = weight.get(st[2], 0) + 10 ** min(loops[0], 3)
                if st[3]: count(st[3])
            elif k in ('assign', 'expr', 'return'):
                for x in st[2:]:
                    if isinstance(x, tuple): count(x)
            elif k in ('asm', 'native'):                # these name registers: keep them there
                for v in s.vars_in(st[3]): weight[v] = weight.get(v, 0) + 10 ** 6
            elif k == 'atomic': cnt(st[2])
            elif k == 'wait':
                loops[0] += 1; count(st[2]); loops[0] -= 1
        for p in fn[4]: weight[p] = weight.get(p, 0) + 1
        cnt(fn[5])

        across = {}                                     # var -> the functions it must survive
        def mark(vs, e):
            gs = set()
            s.walk(e, lambda x: gs.add(x[1]) if x[0] == 'call' and x[1] in s.funcs else None)
            for g in list(gs): gs |= s.desc[g]
            for v in vs: across.setdefault(v, set()).update(gs)
        def has_call(e):
            found = []
            s.walk(e, lambda x: found.append(1) if x[0] == 'call' and x[1] in s.funcs else None)
            return bool(found)
        def live(st, out, ctx):
            k = st[0]
            if k == 'block':
                for x in reversed(st[1]): out = live(x, out, ctx)
                return out
            if k in ('assign', 'local'):
                tgt, e = (st[2], st[3]) if k == 'assign' else (('var', st[2]), st[3])
                if e is None: return out - {st[2]}
                kill = {tgt[1]} if tgt[0] == 'var' else set()
                use = s.vars_in(e) | (s.vars_in(tgt[2]) if tgt[0] == 'idx' else set())
                if has_call(e):
                    rest = s.vars_in(e[2]) if e[0] == 'call' and e[1] in s.funcs else set()
                    # the call's own arguments are used up before it runs - unless they are
                    # still live after it (then they must survive it like anything else)
                    mark((out - kill) | (use - rest) if e[0] == 'call' else (out - kill) | use, e)
                return (out - kill) | use
            if k == 'expr':
                if st[2][1] in s.funcs: mark(out, st[2])
                elif has_call(st[2]): mark(out | s.vars_in(st[2]), st[2])
                if st[2][1] == 'halt': return set()
                return out | s.vars_in(st[2])
            if k in ('asm', 'native'):                  # reads (and may write) what it names
                if has_call(st[3]): mark(out | s.vars_in(st[3]), st[3])
                return out | s.vars_in(st[3])
            if k == 'return':
                if st[2] is not None and has_call(st[2]): mark(s.vars_in(st[2]), st[2])
                return s.vars_in(st[2]) if st[2] is not None else set()
            if k == 'if':
                i = live(st[3], out, ctx) | (live(st[4], out, ctx) if st[4] else out)
                if has_call(st[2]): mark(i | out, st[2])
                return s.vars_in(st[2]) | i
            if k == 'while':
                head = set(out)
                for _ in range(50):
                    cond_in = s.vars_in(st[2]) | head | out
                    step_in = live(st[4], cond_in, ctx) if st[4] else cond_in
                    body_in = live(st[3], step_in, ctx + [(out, step_in)])
                    new = s.vars_in(st[2]) | body_in | out
                    if has_call(st[2]): mark(new, st[2])
                    if new == head: break
                    head = new
                return head
            if k == 'switch':
                items = st[3]
                body = [x for x in items if x[0] not in ('case', 'default')]
                ctx2 = ctx + [(out, ctx[-1][1] if ctx else out)]           # break: past the switch
                acc = set() if any(x[0] == 'default' for x in items) else set(out)
                for i, x in enumerate(items):
                    if x[0] in ('case', 'default'):
                        rest = [y for y in items[i + 1:] if y[0] not in ('case', 'default')]
                        acc |= live(('block', rest), out, ctx2)
                if has_call(st[2]): mark(acc | out, st[2])
                return s.vars_in(st[2]) | acc
            if k == 'break': return set(ctx[-1][0]) if ctx else out
            if k == 'continue': return set(ctx[-1][1]) if ctx else out
            if k == 'atomic': return live(st[2], out, ctx)
            if k == 'wait': return s.vars_in(st[2]) | out
            return out
        live(fn[5], set(), [])
        return {v: (w, across.get(v, set())) for v, w in weight.items()}

    def allocate(s):
        """Every u16 variable gets a register if one is free of conflicts, else two bytes of
        memory. Most-used first. Two variables conflict when both could hold a live value
        at once: globals with everything; a function's own variables with each other; and a
        variable that must survive a call with everything the called functions use."""
        calls = {n: set() for n in s.funcs}
        for n, fn in s.funcs.items():
            def f(x, n=n):
                if x[0] == 'call' and x[1] in s.funcs: calls[n].add(x[1])
            s.walk(fn[5], f)
        def reach(n, path, seen):
            for m in calls[n]:
                if m in path: raise Error('%s() is recursive: Stellar C has no stack frames' % m)
                if m not in seen: seen.add(m); reach(m, path | {m}, seen)
            return seen
        s.desc = {n: reach(n, {n}, set()) for n in s.funcs}
        items = {}                                   # (fn, var) -> [weight, functions it must survive]                                   # (fn, var) -> [weight, crossing]
        for n, fn in s.funcs.items():
            info = s.usage(n, fn)
            for v, (w, cross) in info.items():
                if v not in s.globals and v not in s.fvars_of(n) and not v.startswith('.'):
                    raise Error('%s(): %r is not declared' % (n, v))   # (it used to become a silent local)
                if v in s.globals and (n, v) not in items and v not in s.fvars_of(n):
                    g = items.setdefault((None, v), [0, None]); g[0] += w
                else: items[(n, v)] = [w, cross]
            for i in range(s.nested(fn)): items[(n, '.h%d' % i)] = [10 ** 4, set(s.desc[n])]
        for g in s.globals: items.setdefault((None, g), [0, None])
        # A call stores its arguments into the callee's parameters one by one: a variable that argument
        # j reads must not share a register with parameters 0 .. j-1 (stored before it is read) - e.g.
        # put(r) calling dig2(&cell[2], r) with dig2.a in put.r's register passed the address as v.
        pairs = set()
        for n, fn in s.funcs.items():
            fv = s.fvars_of(n)
            def f(x, n=n, fv=fv):
                if x[0] == 'call' and x[1] in s.funcs:
                    params = s.funcs[x[1]][4]
                    for j, a in enumerate(x[2]):
                        for v in s.vars_in(a):
                            for p in params[:j]:
                                pairs.add(((n if v in fv else None, v), (x[1], p)))
            s.walk(fn[5], f)
        regs = [r for r in range(0, 0xD) if not (s.need_zero and r == ZERO)]   # R0 works (V0061.34)
        def conflict(a, b):
            if (a, b) in pairs or (b, a) in pairs: return True
            if a[0] is None or b[0] is None or a[0] == b[0]: return True
            (fa, _), (fb, _) = a, b
            return fb in items[a][1] or fa in items[b][1]
        s.loc = {}
        order = sorted(items, key=lambda k: (-items[k][0], str(k)))
        for k in order:
            if k[0] is None and k[1] in s.shared:          # one copy for every task: memory, never a register
                s.loc[k] = ('m', '.v__%s' % k[1]); continue
            taken = {s.loc[o][1] for o in s.loc if s.loc[o][0] == 'r' and conflict(k, o)}
            r = next((r for r in regs if r not in taken), None)
            s.loc[k] = ('r', r) if r is not None else ('m', '.v_%s_%s' % (k[0] or '', k[1]))
        s.hidden = {n: 0 for n in s.funcs}

    def fvars_of(s, n):
        fn = s.funcs[n]; names = set(fn[4])
        def f(x):
            if x[0] == 'local': names.add(x[2])
        s.walk(fn[5], f)
        return names

    def nested(s, fn):
        """How many hidden registers a function needs: calls inside expressions."""
        most = [0]
        def count(e, top, logic=False):
            if not isinstance(e, tuple): return 0
            n = 1 if e[0] == 'call' and e[1] in s.funcs and not top else 0
            if e[0] == 'call': return n + sum(count(a, False) for a in e[2])
            if s.lazy(e):                          # a && f() as a value: one more, for its 0 or 1 (see hoist)
                return (0 if logic else 1) + count(e[2], False, True) + count(e[3], False, True)
            if e[0] == 'not': return count(e[1], False, logic)
            if e[0] == 'bin' and e[1] in ('&&', '||'): return count(e[2], False, logic) + count(e[3], False, logic)
            return n + sum(count(x, False) for x in e[1:] if isinstance(x, tuple))
        def f(st):
            if st[0] in ('assign', 'expr', 'return', 'local', 'if', 'while', 'switch'):
                for x in st[2:]:
                    if isinstance(x, tuple) and x[0] in EXPRS:
                        most[0] = max(most[0], count(x, st[0] not in ('if', 'while', 'switch'), st[0] in ('if', 'while')))
        s.walk(fn[5], f)
        return most[0]

    def where(s, name, fn=None):
        fn = s.fn if fn is None else fn
        if (fn, name) in s.loc: return s.loc[(fn, name)]
        if (None, name) in s.loc: return s.loc[(None, name)]
        raise Error('line %d: unknown variable %r' % (s.ln, name))
    def maddr(s, loc): return s.layout.get(loc[1], 0)

    # ---------------------------------------------------------- emitting
    def new(s, tag='L'): s.n += 1; return '%s%d' % (tag, s.n)
    def emit(s, row):
        if isinstance(row[0], str) and row[0].startswith('11 '):           # LOADXI of a known value
            b = [int(x, 16) for x in row[0].split()]
            if s.kreg.get(b[1] & 15) == (b[2] << 8 | b[3]): return
        mn0 = row[1].split()[0] if row[1] else ''
        if mn0 == 'READIDX' and s.acc == row[0]: return                  # the Acc holds that byte already
        s.acc = row[0] if mn0 == 'READIDX' else s.acc if mn0 in ('TESTAI', 'IFTRUEI', 'IFFALSEI', 'WRITEIDX',
                                                                   'COPYAX') else None
        note = s.src_note()
        row = (row[0], row[1], (note + '   ' + row[2]).strip() if row[2] else note)
        s.rows.append(row)
        mn = row[1].split()[0] if row[1] else ''
        if mn not in KEEPS_MA: s.ma = None
        if mn in ('CALL', 'RETURN'): s.kreg = {}
        m = WRITES_REG.search(row[1])
        if m:
            r = int(m.group(1) or m.group(2))
            if s.ma and r in s.ma: s.ma = None
            if s.acc and int(s.acc.split()[1], 16) & 15 == r: s.acc = None
            if mn == 'LOADXI': b = [int(x, 16) for x in row[0].split()]; s.kreg[r] = b[2] << 8 | b[3]
            else: s.kreg.pop(r, None)
    def label(s, name): s.rows.append(lbl(name)); s.ma = None; s.kreg = {}; s.acc = None
    def src_note(s):
        if s.ln != s.noted: s.noted = s.ln; return s.lines[s.ln - 1].strip()[:60]
        return ''

    def temp(s):
        for t in TEMPS:
            if t not in s.tbusy: s.tbusy.add(t); return t
        raise Error('line %d: expression too deep (3 temporaries)' % s.ln)
    def untemp(s, r):
        if r in TEMPS: s.tbusy.discard(r)

    # ---------------------------------------------------------- variables
    def load(s, name, d):
        loc = s.where(name)
        if loc[0] == 'r':
            if loc[1] != d: s.emit(cpxy(loc[1], d))
        else: s.emit(ldx(d, s.maddr(loc), name)); s.emit(mxy2(d, d))

    def store_reg(s, name, r, fn=None):
        """Variable <- register r."""
        loc = s.where(name, fn)
        if loc[0] == 'r':
            if loc[1] != r: s.emit(cpxy(r, loc[1]))
        else:
            p = s.temp(); s.emit(ldx(p, s.maddr(loc), name)); s.emit(xmy2(r, p)); s.untemp(p)

    def store(s, name, e, fn=None):
        """Variable <- expression."""
        loc = s.where(name, fn)
        if loc[0] == 'r': return s.value(e, loc[1])
        if e[0] == 'var' and e[1] not in s.consts and s.where(e[1])[0] == 'r':
            return s.store_reg(name, s.where(e[1])[1], fn)
        t = s.temp(); s.value(e, t); s.store_reg(name, t, fn); s.untemp(t)

    # ---------------------------------------------------------- expressions
    def lazy(s, e):
        """a && b or a || b where b calls a function: b must not run unless it is needed."""
        if e[0] != 'bin' or e[1] not in ('&&', '||'): return False
        found = []
        s.walk(e[3], lambda x: found.append(x) if x[0] == 'call' and x[1] in s.funcs else None)
        return bool(found)

    def hidden_var(s):
        k = s.hidden[s.fn]; s.hidden[s.fn] += 1
        h = '.h%d' % k
        if (s.fn, h) not in s.loc: raise Error('line %d: too many calls in one expression' % s.ln)
        return h

    def hoist(s, e, top=True, logic=False):
        """Calls inside an expression are made first, each into a hidden variable.
        logic: e is a condition (if, while), so cond() makes the right side of a lazy && or || itself,
        only when it is needed; elsewhere the whole && or || is worked out first, into a hidden variable."""
        if e[0] == 'call' and not top and e[1] not in BUILTINS:
            h = s.hidden_var(); s.store(h, e)
            return ('var', h)
        if s.lazy(e):
            l = ('bin', e[1], s.hoist(e[2], False, True), ('lazy', e[3]))
            if logic: return l
            h = s.hidden_var(); s.store(h, l)
            return ('var', h)
        if e[0] == 'bin':
            l = logic and e[1] in ('&&', '||')
            return ('bin', e[1], s.hoist(e[2], False, l), s.hoist(e[3], False, l))
        if e[0] == 'not': return ('not', s.hoist(e[1], False, logic))
        if e[0] == 'neg': return (e[0], s.hoist(e[1], False))
        if e[0] in ('idx', 'addr'): return (e[0], e[1], s.hoist(e[2], False))
        if e[0] == 'call': return ('call', e[1], [s.hoist(a, False) for a in e[2]])
        return e

    def reg(s, e):
        """A register holding e: the variable's own, or a temporary (free it with untemp)."""
        if e[0] == 'rreg': return e[1]
        if e[0] == 'var' and e[1] not in s.consts and e[1] not in s.arrays:
            loc = s.where(e[1])
            if loc[0] == 'r': return loc[1]
        if s.isconst(e):
            v = s.const(e, s.ln)
            if v == 0 and s.need_zero: return ZERO
            for t in TEMPS:
                if t not in s.tbusy and s.kreg.get(t) == v: s.tbusy.add(t); return t
        t = s.temp(); s.value(e, t); return t

    def index(s, name, e):
        """(index register, base) for a[e]: a constant offset goes into the base."""
        base = s.addr(name)
        if s.isconst(e): return ZERO, (base + s.const(e, s.ln)) & 0xFFFF
        if e[0] == 'bin' and e[1] in ('+', '-') and s.isconst(e[3]):
            k = s.const(e[3], s.ln)
            return s.reg(e[2]), (base + (k if e[1] == '+' else -k)) & 0xFFFF
        if e[0] == 'bin' and e[1] == '+' and s.isconst(e[2]):
            return s.reg(e[3]), (base + s.const(e[2], s.ln)) & 0xFFFF
        return s.reg(e), base

    def value(s, e, d):
        """Code that leaves e in register d."""
        if s.isconst(e): return s.emit(ldx(d, s.const(e, s.ln)))
        k = e[0]
        if k == 'var': return s.load(e[1], d)
        if k == 'rreg':                                # a value already in register e[1]
            return s.emit(cpxy(e[1], d)) if e[1] != d else None
        if k == 'flip':                                # e + $8000: a signed value, for an unsigned compare
            s.value(e[1], d); return s.emit(addxi(d, 0x8000, 'signed: + $8000'))
        if k == 'idx' and s.wide(e[1]):                # the pointer in d itself, then d = the word it points at
            s.wptr(e[1], e[2], d); return s.emit(mxy2(d, d))
        if k == 'idx':
            ri, base = s.index(e[1], e[2]); s.emit(rdidx(ri, base)); s.untemp(ri); return s.emit(acc2x(d))
        if k == 'addr':
            w = 2 if s.wide(e[1]) else 1
            if s.isconst(e[2]): return s.emit(ldx(d, (s.addr(e[1]) + w * s.const(e[2], s.ln)) & 0xFFFF, '&' + e[1]))
            s.value(e[2], d)
            if w == 2: s.emit(addxyz(d, d, d))
            return s.emit(addxi(d, s.addr(e[1])))
        if k == 'call': return s.call(e, d)
        if k == 'neg':
            r = s.reg(e[1]); t = s.temp(); s.emit(ldx(t, 0)); s.emit(subxyz(t, r, d)); s.untemp(t); s.untemp(r); return
        if k == 'not' or (k == 'bin' and e[1] in ('==', '!=', '<', '<=', '>', '>=', '&&', '||')):
            yes, end = s.new(), s.new()
            s.cond(e, yes, True); s.emit(ldx(d, 0)); s.emit(gal(end)); s.label(yes); s.emit(ldx(d, 1)); s.label(end)
            return
        op, a, b = e[1], e[2], e[3]
        if op in ('+', '*', '&', '|', '^') and s.isconst(a) and not s.isconst(b): a, b = b, a
        if op in ('+', '-') and s.isconst(b):
            v = s.const(b, s.ln)
            if s.uses(a, d) and not (a[0] == 'var' and s.where(a[1]) == ('r', d)):
                t = s.temp(); s.value(a, t); a2 = t
            else: s.value(a, d); a2 = None
            if a2 is not None:
                s.emit(cpxy(a2, d)); s.untemp(a2)
            if v == 0: return
            if v == 1: return s.emit(incx(d) if op == '+' else decx(d))
            return s.emit(addxi(d, v) if op == '+' else subxi(d, v))
        if op in ('<<',) and s.isconst(b) or (op == '*' and s.isconst(b) and s.const(b, s.ln) in (2, 4)):
            n = s.const(b, s.ln) if op == '<<' else {2: 1, 4: 2}[s.const(b, s.ln)]
            s.value(a, d)
            for _ in range(n): s.emit(addxyz(d, d, d))
            return
        if op == '>>' and s.isconst(b) and s.is_signed(a): return s.sshift(a, s.const(b, s.ln), d)
        if op in ('/', '%') and (s.is_signed(a) or s.is_signed(b)): return s.sdiv(a, b, d, op)
        if op == '>>' and s.isconst(b): op, b = '/', ('num', 1 << s.const(b, s.ln))
        if op in ('&', '|', '^'):
            code = {'|': '63', '^': '64', '&': '65'}[op]; name = {'|': 'OR', '^': 'XOR', '&': 'AND'}[op]
            ra = s.reg(a)
            if s.isconst(b):
                v = s.const(b, s.ln)
                s.emit(('%s 1%X %02X %02X' % (code, ra, v >> 8, v & 255), '%s R%d %04X' % (name, ra, v), ''))
            else:
                rb = s.reg(b); s.emit(x2acc(rb)); s.untemp(rb)
                s.emit(('%s 0%X' % (code, ra), '%s R%d Acc' % (name, ra), ''))
            s.untemp(ra); return s.emit(ma2x(d))
        if d in TEMPS and not s.uses(b, d) and a[0] not in ('var', 'num') and not s.isconst(a):
            # a is worked out in d itself (the result goes there anyway): one temporary fewer
            s.value(a, d); ra = d
        else: ra = s.reg(a)
        rb = s.reg(b)
        if op == '+': s.emit(addxyz(ra, rb, d))
        elif op == '-': s.emit(subxyz(ra, rb, d))
        elif op == '*': s.emit(multxy(ra, rb)); s.emit(ma2x(d))
        elif op in ('/', '%'):
            s.divide(ra, rb)
            if op == '/': s.emit(ma2x(d))
            else: s.emit(rema()); s.emit(acc2x(d))
        else: raise Error('line %d: operator %s' % (s.ln, op))
        if ra != d: s.untemp(ra)                          # d is the caller's: still in use
        s.untemp(rb)

    def side_effects(s, e):
        """Does evaluating e do something (a call to a function, rand(), getc(), an input)?"""
        found = []
        s.walk(e, lambda x: found.append(x) if x[0] == 'call' and (x[1] in s.funcs or
               x[1] in ('rand', 'getc', 'getin', 'scanin', 'getline', 'peek', 'peekw', 'rtcset')) else None)
        return bool(found)

    def wptr(s, name, ie, t=None):
        """A register (t, else a new temporary) pointing at a 16-bit array element (base + 2 x index)."""
        if t is None: t = s.temp()
        if s.isconst(ie): s.emit(ldx(t, (s.addr(name) + 2 * s.const(ie, s.ln)) & 0xFFFF, '&%s[%d]' % (name, s.const(ie, s.ln))))
        else:
            s.value(ie, t); s.emit(addxyz(t, t, t, 'x 2: two bytes an element')); s.emit(addxi(t, s.addr(name)))
        return t

    def sshift(s, a, k, d):
        """Signed >> k: arithmetic (rounds down): a negative a is ~(~a >> k)."""
        s.value(a, d); t = s.temp(); pos, end = s.new(), s.new()
        s.emit(ldx(t, 0x8000)); s.emit(testlt(d, t)); s.emit(ift(pos, 'not negative'))
        s.emit(ldx(t, 0xFFFF)); s.emit(subxyz(t, d, d, '~a'))
        s.emit(ldx(t, 1 << k)); s.emit(divxy(d, t)); s.emit(ma2x(d))
        s.emit(ldx(t, 0xFFFF)); s.emit(subxyz(t, d, d, '~ again')); s.emit(gal(end))
        s.label(pos); s.emit(ldx(t, 1 << k)); s.emit(divxy(d, t)); s.emit(ma2x(d))
        s.label(end); s.untemp(t); s.ma = None

    def sdiv(s, a, b, d, op):
        """Signed / and % (C: the quotient rounds toward zero, the remainder takes a's sign), by LIB_SDIV
        (RF / RE -> RF quotient, RE remainder). Any temporaries in use are kept on the VM stack."""
        keep = [t for t in TEMPS if t in s.tbusy and t != d]
        for t in keep: s.emit(('72 0%X' % t, 'PUSHX R%d' % t, 'kept across the signed divide'))
        for x, what in ((a, 'the dividend'), (b, 'the divisor')):   # each onto the stack as soon as it is made
            r = s.reg(x); s.emit(('72 0%X' % r, 'PUSHX R%d' % r, what)); s.untemp(r)
        s.emit(('73 0E', 'POPX R14', 'the divisor')); s.emit(('73 0F', 'POPX R15', 'the dividend'))
        s.libs.add('LIB_SDIV'); s.emit(call('LIB_SDIV', 'signed ' + op))
        r = 0xF if op == '/' else 0xE
        s.emit(('72 0%X' % r, 'PUSHX R%d' % r, '')); s.emit(('73 0%X' % d, 'POPX R%d' % d, ''))
        for t in reversed(keep): s.emit(('73 0%X' % t, 'POPX R%d' % t, ''))
        s.ma = None; s.kreg = {}; s.acc = None

    def uses(s, e, r):
        """Does evaluating e read register r (so r must not be written first)?"""
        found = []
        def f(x):
            if x[0] == 'var' and x[1] not in s.consts and x[1] not in s.arrays and s.where(x[1]) == ('r', r): found.append(x)
        s.walk(e, f)
        return bool(found)

    def divide(s, ra, rb):
        if s.ma == (ra, rb): return                  # the MA already holds ra / rb
        s.emit(divxy(ra, rb)); s.ma = (ra, rb)

    def to_acc(s, e):
        """Code that leaves e in the Acc (for WRITEIDX, SEROUT, printu, TESTAI)."""
        if s.isconst(e): return s.emit(ldai(s.const(e, s.ln)))
        if e[0] == 'var' and s.where(e[1])[0] == 'r': return s.emit(x2acc(s.where(e[1])[1]))
        if e[0] == 'idx' and not s.wide(e[1]):
            ri, base = s.index(e[1], e[2]); s.emit(rdidx(ri, base)); s.untemp(ri); return
        if e[0] == 'call' and e[1] == 'getc': return s.emit(('CB', 'SERIN', ''))
        if e[0] == 'call' and e[1] == 'rand': return s.emit(('C3', 'RAND', ''))
        if e[0] == 'call' and e[1] in ('scanin', 'getin'):          # the port byte, high byte 0
            s.emit(ldai(0)); return s.emit(('0C 00', 'SIPA', 'scan the input port') if e[1] == 'scanin'
                                           else ('0D 00', 'GIPA', 'wait for EF, then read the input port'))
        if e[0] == 'call' and e[1] == 'ef' and not e[2]: return s.emit(('09', 'GETEFA', 'EF1-4 as a mask'))
        if e[0] == 'bin' and e[1] in ('%', '/') and not s.is_signed(e):
            ra, rb = s.reg(e[2]), s.reg(e[3]); s.divide(ra, rb)
            s.emit(rema() if e[1] == '%' else maa()); s.untemp(ra); s.untemp(rb); return
        if e[0] == 'bin' and e[1] in ('+', '-') and s.isconst(e[3]):
            s.to_acc(e[2]); v = s.const(e[3], s.ln)
            return s.emit(addai(v if e[1] == '+' else (-v) & 0xFFFF))
        t = s.temp(); s.value(e, t); s.emit(x2acc(t)); s.untemp(t)

    def call(s, e, d=None):
        name, args = e[1], e[2]
        if name in BUILTINS: return s.builtin(name, args, d)
        if name not in s.funcs: raise Error('line %d: no function %s()' % (s.ln, name))
        params = s.funcs[name][4]
        if len(args) != len(params): raise Error('line %d: %s() takes %d arguments' % (s.ln, name, len(params)))
        for a, p in zip(args, params): s.store(p, a, name)
        s.emit(call('F_' + name))
        if d is not None and d != RV: s.emit(cpxy(RV, d))

    def address(s, e):
        """A constant address from &a[k], a, or a string literal (else None)."""
        if e[0] == 'addr' and s.isconst(e[2]): return (s.addr(e[1]) + s.const(e[2], s.ln)) & 0xFFFF
        if e[0] == 'var' and e[1] in s.arrays: return s.addr(e[1])
        if e[0] == 'str': return s.layout.get(s.string(e), 0)
        return None

    def builtin(s, name, args, d):
        if name == 'putc':
            if s.isconst(args[0]): return s.emit(serouti(s.const(args[0], s.ln)))
            s.to_acc(args[0]); return s.emit(serout())
        if name == 'print':
            t = s.temp(); a = s.address(args[0])
            note = '"%s"' % bytes(args[0][1]).decode('latin1').encode('unicode_escape').decode()[:40] \
                if args[0][0] == 'str' else ''
            if a is None: s.value(args[0], t)
            else: s.emit(ldx(t, a, note))
            s.emit(printstr(t)); s.untemp(t); return
        if name == 'printu':
            s.to_acc(args[0]); s.emit(('24', 'COPYAMA', '')); s.emit(('6B 00', 'CVT2DEC Acc', ''))
            return s.emit(('6E', 'OUTDEC', ''))
        if name == 'printi':
            t = s.temp(); s.value(args[0], t); c = s.temp(); pos = s.new()
            s.emit(ldx(c, 0x8000)); s.emit(testlt(t, c)); s.emit(ift(pos, 'not negative'))
            s.emit(serouti('-')); s.emit(ldx(c, 0)); s.emit(subxyz(c, t, t, 'its size'))
            s.label(pos); s.emit(x2acc(t)); s.emit(('24', 'COPYAMA', '')); s.emit(('6B 00', 'CVT2DEC Acc', ''))
            s.emit(('6E', 'OUTDEC', '')); s.untemp(c); s.untemp(t); return
        if name == 'turns':                          # turns(n): $C8 SETCIN - commands this VM runs a turn
            s.nargs(name, args, 1)
            if not s.isconst(args[0]) or not 1 <= s.const(args[0], s.ln) <= 255:
                raise Error('line %d: turns(n): n must be a constant, 1-255' % s.ln)
            v = s.const(args[0], s.ln)
            return s.emit(('C8 %02X' % v, 'SETCIN %02X' % v, 'this VM runs %d commands a turn' % v))
        if name == 'delay': return s.emit(('C0 %02X' % s.const(args[0], s.ln), 'DLYI %02X' % s.const(args[0], s.ln), ''))
        if name == 'halt': return s.emit(gal('QUIT'))
        if name in ARITY: return s.io(name, args, d)
        if name in ('getc', 'rand'):
            s.emit(('CB', 'SERIN', '') if name == 'getc' else ('C3', 'RAND', ''))
            if d is not None: s.emit(acc2x(d))
            return
        if name == 'keyready':
            if d is None: return
            return s.value(('bin', '!=', ('call', 'keyready', []), ('num', 0)), d)
        if name == 'fill':                           # fill(&a[k], value, count)
            n, v = s.const(args[2], s.ln), s.const(args[1], s.ln)
            x, y = s.temp(), s.temp()
            s.value(args[0], x); s.value(args[0], y) if s.address(args[0]) is None else \
                s.emit(ldx(y, (s.address(args[0]) + n - 1) & 0xFFFF))
            if s.address(args[0]) is None: s.emit(addxi(y, n - 1))
            s.emit(('FB %X%X %02X' % (x, y, v), 'FILLMEMXY R%d..R%d %02X' % (x, y, v), ''))
            s.untemp(x); s.untemp(y); return
        if name == 'copy':                           # copy(&dst, &src, count): COPYMXMY
            n = s.const(args[2], s.ln)
            if not 0 < n < 256: raise Error('line %d: copy() of 1-255 bytes' % s.ln)
            x, y = s.temp(), s.temp()
            s.value(args[1], x); s.value(args[0], y)
            s.emit(('3B %X%X %02X' % (x, y, n), 'COPYMXMY R%d -> R%d %d' % (x, y, n), ''))
            s.untemp(x); s.untemp(y); return
        if name in ('cls', 'eol', 'rev', 'cursor', 'at', 'printz', 'printw', 'printh', 'getline',
                    'rtcget', 'rtcset', 'peek', 'poke', 'peekw', 'pokew'):
            return s.builtin2(name, args, d)
        raise Error(name)

    # ---------------------------------------------------------- terminal, numbers, input, RTC, memory
    def nargs(s, name, args, *ok):
        if len(args) not in ok:
            raise Error('line %d: %s() takes %s argument%s' % (s.ln, name, ' or '.join(map(str, ok)),
                                                                '' if ok == (1,) else 's'))
    def conststr(s, text, note=''):
        t = s.temp(); s.emit(ldx(t, s.layout.get(s.string(('str', list(text.encode('latin1')))), 0), note))
        s.emit(printstr(t)); s.untemp(t)
    def free_for_lib(s, name):
        if s.tbusy: raise Error('line %d: %s() can only be a statement of its own' % (s.ln, name))
    def into(s, e, r):
        """e into temporary r, which then stays reserved (the next argument cannot use it)."""
        s.tbusy.add(r); s.value(e, r)
    def lib_call(s, name, note=''):
        s.libs.add(name); s.emit(call(name, note)); s.tbusy.clear(); s.kreg = {}; s.ma = None; s.acc = None

    def builtin2(s, name, args, d):
        E = '\x1b'
        if name in ('cls', 'eol'):
            s.nargs(name, args, 0)
            return s.conststr(E + '[0m' + E + '[2J' + E + '[H' if name == 'cls' else E + '[K', name + '()')
        if name in ('rev', 'cursor'):
            s.nargs(name, args, 1)
            on, off = (E + '[7m', E + '[0m') if name == 'rev' else (E + '[?25h', E + '[?25l')
            if s.isconst(args[0]): return s.conststr(on if s.const(args[0], s.ln) else off, '%s(%d)' % (name, s.const(args[0], s.ln)))
            no, end = s.new(), s.new()
            s.cond(s.hoist(args[0], False, True), no, False); s.conststr(on); s.emit(gal(end))
            s.label(no); s.conststr(off); s.label(end); return
        if name == 'at':
            s.nargs(name, args, 2)
            if s.isconst(args[0]) and s.isconst(args[1]):
                r, c = s.const(args[0], s.ln), s.const(args[1], s.ln)
                return s.conststr(E + '[%d;%dH' % (r, c), 'at(%d, %d)' % (r, c))
            s.free_for_lib(name); s.into(args[0], 0xF); s.into(args[1], 0xE)
            return s.lib_call('LIB_AT', 'ESC [ row ; col H')
        if name in ('printz', 'printw', 'printh'):
            s.nargs(name, args, *((1, 2) if name == 'printh' else (2,)))
            n = s.const(args[1], s.ln) if len(args) == 2 else 4
            if not s.isconst(args[1]) if len(args) == 2 else False:
                raise Error('line %d: %s(e, n): n must be a constant' % (s.ln, name))
            top = 4 if name == 'printh' else 5
            if not 1 <= n <= top: raise Error('line %d: %s(e, %d): n must be 1-%d' % (s.ln, name, n, top))
            s.free_for_lib(name); s.into(args[0], 0xF)
            if name == 'printh':
                if n < 4:
                    s.emit(ldx(0xE, 16 ** n)); s.emit(divxy(0xF, 0xE)); s.emit(rema()); s.emit(acc2x(0xF, 'its low %d hex digits' % n))
                s.emit(ldx(0xE, 16 ** (n - 1)))
                return s.lib_call('LIB_HEX', '%d hex digits' % n)
            if n < 5:
                s.emit(ldx(0xE, 10 ** n)); s.emit(divxy(0xF, 0xE)); s.emit(rema()); s.emit(acc2x(0xF, 'its low %d digits' % n))
            s.emit(ldx(0xE, 10 ** (n - 1)))
            return s.lib_call('LIB_PRZ' if name == 'printz' else 'LIB_PRW', '%d digits' % n)
        if name == 'getline':
            s.nargs(name, args, 1, 2)
            if args[0][0] != 'var' or args[0][1] not in s.arrays or args[0][1] in s.bytevars or s.wide(args[0][1]):
                raise Error('line %d: getline(buf): buf must be a u8 array' % s.ln)
            size = len(s.array_bytes(s.arrays[args[0][1]]))
            mx = s.const(args[1], s.ln) if len(args) == 2 else size - 1
            if len(args) == 2 and not s.isconst(args[1]): raise Error('line %d: getline(buf, max): max must be a constant' % s.ln)
            if not 1 <= mx <= size - 1: raise Error('line %d: getline(): max must be 1-%d (the array\'s size - 1, for the NUL)' % (s.ln, size - 1))
            base = s.addr(args[0][1])
            free = [t for t in TEMPS if t not in s.tbusy and t != d]
            cnt = d if d in TEMPS else free.pop()
            ch, cmp_ = free.pop(), free.pop()
            loop, bs, end = s.new(), s.new(), s.new()
            s.emit(ldx(cnt, 0, 'getline(): at most %d characters' % mx))
            s.label(loop); s.emit(('CB', 'SERIN', '')); s.emit(acc2x(ch))
            s.emit(testxi(ch, 13)); s.emit(ift(end)); s.emit(testxi(ch, 8)); s.emit(ift(bs))
            s.emit(testxi(ch, 0x7F)); s.emit(ift(bs))
            s.emit(ldx(cmp_, 0x20)); s.emit(testlt(ch, cmp_)); s.emit(ift(loop))
            s.emit(ldx(cmp_, mx)); s.emit(testlt(cnt, cmp_)); s.emit(iff(loop, 'full: ignored'))
            s.emit(x2acc(ch)); s.emit(wridx(cnt, base)); s.emit(serout('echo')); s.emit(incx(cnt)); s.emit(gal(loop))
            s.label(bs); s.emit(testxz(cnt)); s.emit(ift(loop)); s.emit(decx(cnt))
            s.emit(serouti(8)); s.emit(serouti(' ')); s.emit(serouti(8)); s.emit(gal(loop))
            s.label(end); s.emit(ldai(0)); s.emit(wridx(cnt, base, 'NUL')); s.emit(serouti(13)); s.emit(serouti(10))
            if d is not None and d != cnt: s.emit(cpxy(cnt, d))
            return
        if name in ('rtcget', 'rtcset'):
            s.nargs(name, args, 1)
            if args[0][0] != 'var' or args[0][1] not in s.arrays or s.wide(args[0][1]) or len(s.array_bytes(s.arrays[args[0][1]])) < 8:
                raise Error('line %d: %s(t): t must be a u8 array of 8 bytes' % (s.ln, name))
            t = s.temp(); s.emit(ldx(t, s.addr(args[0][1])))
            s.emit(('07 %X%X' % (0 if name == 'rtcget' else 1, t), '%s R%d' % (name.upper(), t),
                    'sec min hour wday day month yearhi yearlo'))
            s.untemp(t)
            if name == 'rtcset' and d is not None:
                no = s.new(); s.emit(ldx(d, 0)); s.emit(iff(no, 'refused: nothing written')); s.emit(ldx(d, 1)); s.label(no)
            return
        if name in ('peek', 'peekw'):
            s.nargs(name, args, 1)
            t = s.temp(); s.value(args[0], t)
            s.emit(('20 00', 'MEMMODE 00', 'absolute - no branch'))
            if name == 'peek': s.emit(rdidx(t, 0)); s.emit(('20 01', 'MEMMODE 01', 'relative again'))
            else:
                s.emit(mxy2(t, t)); s.emit(('20 01', 'MEMMODE 01', 'relative again'))
            if d is not None: s.emit(acc2x(d) if name == 'peek' else cpxy(t, d))
            s.untemp(t); s.acc = None; s.kreg = {}; return
        if name in ('poke', 'pokew'):
            s.nargs(name, args, 2)
            t = s.temp(); s.value(args[0], t)
            if name == 'poke':
                s.to_acc(args[1])
                s.emit(('20 00', 'MEMMODE 00', 'absolute - no branch')); s.emit(wridx(t, 0))
            else:
                v = s.temp(); s.value(args[1], v)
                s.emit(('20 00', 'MEMMODE 00', 'absolute - no branch')); s.emit(xmy2(v, t)); s.untemp(v)
            s.emit(('20 01', 'MEMMODE 01', 'relative again')); s.untemp(t); s.acc = None; return
        raise Error(name)

    def lib_rows(s, name):
        """A library routine (arguments in RF, RE; RD scratch; R0 borrowed through the VM stack)."""
        push, pop = ('72 00', 'PUSHX R0', 'borrow R0'), ('73 00', 'POPX R0', 'give R0 back')
        if name == 'LIB_AT':
            return [lbl(name, 'ESC [ RF ; RE H'), serouti(0x1B), serouti('['), x2acc(0xF), ('24', 'COPYAMA', ''),
                    ('6B 00', 'CVT2DEC Acc', ''), ('6E', 'OUTDEC', ''), serouti(';'), x2acc(0xE), ('24', 'COPYAMA', ''),
                    ('6B 00', 'CVT2DEC Acc', ''), ('6E', 'OUTDEC', ''), serouti('H'), ret()]
        if name in ('LIB_PRZ', 'LIB_PRW'):
            # RF = the value, RE = the place of its first digit (10^(n-1)); R0 = 1 once a digit is shown
            L, DG, NX = name + '_L', name + '_D', name + '_N'
            return [lbl(name, 'RF in decimal from place RE, ' + ('zero' if name == 'LIB_PRZ' else 'space') + '-padded'),
                    push, ldx(0, 1 if name == 'LIB_PRZ' else 0),
                    lbl(L), divxy(0xF, 0xE), maa(), acc2x(0xD, 'this digit'), rema(), acc2x(0xF, 'the rest'),
                    testxz(0xD), iff(DG), testxz(0), iff(DG), testxi(0xE, 1), ift(DG, 'the last digit always shows'),
                    serouti(' '), gal(NX),
                    lbl(DG), ldx(0, 1), x2acc(0xD), addai(0x30), serout(),
                    lbl(NX), ldx(0xD, 10), divxy(0xE, 0xD), maa(), acc2x(0xE), testxz(0xE), iff(L), pop, ret()]
        if name == 'LIB_SDIV':
            # RF / RE signed -> RF quotient (toward zero), RE remainder (a's sign). R0: 1 = a < 0, +2 = b < 0
            A1, A2, Q, R, RM, DONE = [name + x for x in ('_A1', '_A2', '_Q', '_R', '_RM', '_D')]
            return [lbl(name, 'signed RF / RE'), push, ldx(0, 0),
                    ldx(0xD, 0x8000), testlt(0xF, 0xD), ift(A1), ldx(0xD, 0), subxyz(0xD, 0xF, 0xF, '|a|'), incx(0),
                    lbl(A1), ldx(0xD, 0x8000), testlt(0xE, 0xD), ift(A2), ldx(0xD, 0), subxyz(0xD, 0xE, 0xE, '|b|'), addxi(0, 2),
                    lbl(A2), divxy(0xF, 0xE), ma2x(0xF), rema(), acc2x(0xE),
                    testxi(0, 1), ift(Q), testxi(0, 2), iff(R),
                    lbl(Q), ldx(0xD, 0), subxyz(0xD, 0xF, 0xF, 'the quotient is negative'),
                    lbl(R), testxi(0, 1), ift(RM), testxi(0, 3), iff(DONE),
                    lbl(RM), ldx(0xD, 0), subxyz(0xD, 0xE, 0xE, 'the remainder takes a\'s sign'),
                    lbl(DONE), pop, ret()]
        if name == 'LIB_HEX':
            L = name + '_L'; hx = s.layout.get(s.string(('str', list(b'0123456789ABCDEF'))), 0)
            return [lbl(name, 'RF in hex from place RE'),
                    lbl(L), divxy(0xF, 0xE), maa(), acc2x(0xD), rema(), acc2x(0xF),
                    rdidx(0xD, hx, '0-9 A-F'), serout(),
                    ldx(0xD, 16), divxy(0xE, 0xD), maa(), acc2x(0xE), testxz(0xE), iff(L), ret()]
        raise Error(name)

    def io(s, name, args, d):
        """The Elf2K I/O group, $01-$0F (see ARITY above)."""
        want = ARITY[name] if isinstance(ARITY[name], tuple) else (ARITY[name],)
        if len(args) not in want:
            n = ' or '.join(str(k) for k in want)
            raise Error('line %d: %s() takes %s argument%s' % (s.ln, name, n, '' if n == '1' else 's'))
        def const(lo, hi, what):
            if not s.isconst(args[0]): raise Error('line %d: %s() needs a constant %s' % (s.ln, name, what))
            v = s.const(args[0], s.ln)
            if not lo <= v <= hi: raise Error('line %d: %s(%d): %s must be %d-%d' % (s.ln, name, v, what, lo, hi))
            return v
        if name == 'outport':
            p = const(1, 7, 'port')
            if p in (2, 3): raise Error('line %d: outport(%d): ports 2 and 3 are the serial chip' % (s.ln, p))
            return s.emit(('01 0%X' % p, 'DEFOUT %d' % p, 'output port %d' % p))
        if name == 'inport':
            p = const(1, 7, 'port')
            if p in (2, 3): raise Error('line %d: inport(%d): ports 2 and 3 are the serial chip' % (s.ln, p))
            return s.emit(('02 0%X' % (p + 8), 'DEFIN %X' % (p + 8), 'input port %d' % p))
        if name == 'efsource':
            n = const(1, 4, 'EF line')
            inv = 0
            if len(args) == 2:
                if not s.isconst(args[1]) or s.const(args[1], s.ln) > 1:
                    raise Error('line %d: efsource(n, inverted): inverted must be 0 or 1' % s.ln)
                inv = s.const(args[1], s.ln)
            return s.emit(('03 %X%X' % (n, inv), 'DEFEF %X%X' % (n, inv),
                           'getin() waits on EF%d%s' % (n, ', inverted' if inv else '')))
        if name == 'waitef':
            if not args: return s.emit(('0F 00', 'WIP 00', 'wait for the EF line: active, then inactive'))
            n = const(1, 4, 'EF line')
            return s.emit(('0F 0%X' % n, 'WIP 0%X' % n, 'wait for EF%d: high, then low' % n))
        if name == 'q':
            e = args[0]
            if s.isconst(e):
                v = s.const(e, s.ln)
                if v > 3: raise Error('line %d: q(%d): 0 off, 1 on, 2 one blink, 3 two blinks' % (s.ln, v))
                return s.emit(('0A 0%X' % v, 'SETQ %d' % v, ''))
            off, end = s.new(), s.new()                          # on if non-zero
            s.cond(s.hoist(e, False, True), off, False)
            s.emit(('0A 01', 'SETQ 1', '')); s.emit(gal(end))
            s.label(off); s.emit(('0A 00', 'SETQ 0', '')); s.label(end); return
        if name == 'out':
            e = args[0]
            if s.isconst(e): return s.emit(('04 %02X' % (s.const(e, s.ln) & 255), 'OUTI %02X' % (s.const(e, s.ln) & 255), ''))
            if e[0] == 'var' and e[1] not in s.consts and e[1] not in s.arrays and s.where(e[1])[0] == 'r':
                r = s.where(e[1])[1]; return s.emit(('06 0%X' % r, 'OUTX R%d' % r, 'its low byte'))
            if (e[0] == 'bin' and e[1] == '>>' and s.isconst(e[3]) and s.const(e[3], s.ln) == 8 and e[2][0] == 'var'
                    and e[2][1] not in s.consts and e[2][1] not in s.arrays and s.where(e[2][1])[0] == 'r'):
                r = s.where(e[2][1])[1]; return s.emit(('06 1%X' % r, 'OUTX R%d high' % r, 'its high byte'))
            s.to_acc(e); return s.emit(('05 00', 'OUTA Acc', 'the Acc\'s low byte'))
        if name == 'outmem':
            a = s.address(args[0])
            t = s.temp()
            if a is None: s.value(args[0], t)
            else: s.emit(ldx(t, a))
            s.emit(('08 0%X' % t, 'OUTMX R%d' % t, 'the byte it points at')); s.untemp(t); return
        if name == 'ef':
            if args:                                          # ef(n): 0 / 1
                n = const(1, 4, 'EF line')
                s.emit(('09', 'GETEFA', 'EF1-4 as a mask'))
                s.emit(('1A %02X' % (1 << (n - 1)), 'TESTBITI %02X' % (1 << (n - 1)), 'EF%d on?' % n))
                if d is None: return
                off = s.new()
                s.emit(ldx(d, 0)); s.emit(iff(off)); s.emit(ldx(d, 1)); s.label(off)
                return
            s.emit(('09', 'GETEFA', 'EF1-4 as a mask'))
            if d is not None: s.emit(acc2x(d))
            return
        if name in ('scanin', 'getin'):
            if name == 'getin' and d is not None:                 # straight into the register
                s.emit(ldx(d, 0)); return s.emit(('0E 0%X' % d, 'GIPX -> R%d' % d, 'wait for EF, then read the input port'))
            s.to_acc(('call', name, []))
            if d is not None: s.emit(acc2x(d))
            return
        raise Error(name)

    def string(s, e):
        if e[0] != 'str': raise Error('line %d: a string is needed' % s.ln)
        b = bytes(e[1]) + b'\0'
        if b not in s.strings: s.strings[b] = 'S%d' % len(s.strings)
        return s.strings[b]

    def addr(s, name):
        if name not in s.arrays: raise Error('line %d: %s is not an array' % (s.ln, name))
        return s.layout.get(name, 0)

    # ---------------------------------------------------------- conditions
    def cond(s, c, target, sense):
        """Branch to target when c is `sense` (True/False); fall through otherwise."""
        br = lambda: s.emit(ift(target) if sense else iff(target))
        if s.isconst(c):
            if bool(s.const(c, s.ln)) == sense: s.emit(gal(target))
            return
        k = c[0]
        if k == 'lazy': return s.cond(s.hoist(c[1], False, True), target, sense)   # only now: see hoist
        if k == 'not': return s.cond(c[1], target, not sense)
        if k == 'call' and c[1] == 'keyready': s.emit(('CC', 'SERST', '')); return br()
        if k == 'call' and c[1] == 'ef' and len(c[2]) == 1 and s.isconst(c[2][0]) and 1 <= s.const(c[2][0], s.ln) <= 4:
            n = s.const(c[2][0], s.ln)                       # if (ef(n)): one test, one branch
            s.emit(('09', 'GETEFA', 'EF1-4 as a mask'))
            s.emit(('1A %02X' % (1 << (n - 1)), 'TESTBITI %02X' % (1 << (n - 1)), 'EF%d on?' % n)); return br()
        if k == 'bin' and c[1] == '&&':
            if sense:
                skip = s.new(); s.cond(c[2], skip, False); s.cond(c[3], target, True); s.label(skip)
            else: s.cond(c[2], target, False); s.cond(c[3], target, False)
            return
        if k == 'bin' and c[1] == '||':
            if sense: s.cond(c[2], target, True); s.cond(c[3], target, True)
            else:
                skip = s.new(); s.cond(c[2], skip, True); s.cond(c[3], target, False); s.label(skip)
            return
        if k != 'bin' or c[1] not in ('==', '!=', '<', '<=', '>', '>='):
            return s.cond(('bin', '!=', c, ('num', 0)), target, sense)
        op, a, b = c[1], c[2], c[3]
        if s.isconst(a) and not s.isconst(b):
            a, b = b, a; op = {'<': '>', '>': '<', '<=': '>=', '>=': '<='}.get(op, op)
        if op in ('==', '!='):
            if op == '!=': sense = not sense
            br = lambda: s.emit(ift(target) if sense else iff(target))
            if a[0] == 'bin' and a[1] == '%' and s.isconst(b) and s.const(b, s.ln) == 0 and not s.is_signed(a):
                ra, rb = s.reg(a[2]), s.reg(a[3]); s.divide(ra, rb); s.untemp(ra); s.untemp(rb)
                s.emit(('8E', 'TESTREMZ', '')); return br()
            if s.isconst(b) and ((a[0] == 'idx' and not s.wide(a[1])) or (a[0] == 'call' and a[1] in ('getc', 'rand', 'ef', 'scanin', 'getin'))):
                s.to_acc(a); s.emit(testai(s.const(b, s.ln))); return br()
            ra = s.reg(a)
            if s.isconst(b):
                v = s.const(b, s.ln)
                s.emit(testxz(ra) if v == 0 else testxi(ra, v))
            else:
                rb = s.reg(b); s.emit(testxy(ra, rb)); s.untemp(rb)
            s.untemp(ra); return br()
        if s.is_signed(a) or s.is_signed(b): a, b = ('flip', a), ('flip', b)   # signed: compare a+$8000, b+$8000
        ra, rb = s.reg(a), s.reg(b)
        # $88 TESTGXY: RX >= RY.  $89 TESTLXY: RX < RY (strictly - the COMMANDS row says <=)
        s.emit({'<': testlt(ra, rb), '>=': testge(ra, rb), '>': testlt(rb, ra), '<=': testge(rb, ra)}[op])
        s.untemp(ra); s.untemp(rb); br()

    # ---------------------------------------------------------- statements
    def stmt(s, st):
        k = st[0]
        if k == 'block':
            for x in st[1]: s.stmt(x)
            return
        s.ln = st[1]; s.tbusy = set(); s.hidden[s.fn] = 0
        if k == 'local':
            if st[3] is not None: s.store(st[2], s.hoist(st[3]))
            return
        if k == 'assign':
            w = s.shared_written(st)
            atom = w and not s.atomic and (s.shared_in(st[3]) or (st[2][0] == 'idx' and s.shared_in(st[2][2])))
            if atom:                               # read-modify-write of shared data: one step for the others
                bad = s.unsafe(st[3], True)
                if bad: raise Error('line %d: %s in an update of shared data: work it out first' % (st[1], bad))
                s.setmulti(0, 'a shared update: no other task cuts in')
            s.assign(st[2], st[3])
            if atom: s.setmulti(1)
            return s.wakes(w)
        if k == 'expr': s.call(s.hoist(st[2])); return s.wakes(s.shared_written(st))
        if k == 'wait': return s.wait(st)
        if k in ('stop', 'start'): return s.stopstart(st)
        if k == 'atomic':
            if not s.atomic:
                bad = s.unsafe(st[2])
                if bad: raise Error('line %d: %s inside atomic { }: every other task would stop with it' % (st[1], bad))
                s.setmulti(0, 'atomic {: no other task runs'); s.atomic_loops = len(s.loops)
            s.atomic += 1; s.stmt(st[2]); s.atomic -= 1
            if not s.atomic: s.ln = st[1]; s.setmulti(1, '} atomic')
            return
        if k == 'asm': return s.asm(st[2])
        if k == 'native': return s.native(st[2])
        if k == 'if':
            _, _, c, a, b = st
            one = a[1][0] if a[0] == 'block' and len(a[1]) == 1 else a
            if b is None and one[0] in ('break', 'continue', 'return'): s.leaving(one[0])
            if b is None and one[0] in ('break', 'continue') and s.loops:
                # if (c) break;  ->  one conditional branch straight out of the loop
                return s.cond(s.hoist(c, False, True), s.loops[-1][0 if one[0] == 'break' else 1], True)
            if b is None and one[0] == 'return' and one[2] is None:
                return s.cond(s.hoist(c, False, True), 'R_' + s.fn, True)    # if (c) return;
            els, end = s.new(), s.new()
            s.cond(s.hoist(c, False, True), els if b else end, False)
            s.stmt(a)
            if b:
                if not (s.rows and s.rows[-1][1].split()[:1] in (['GAL'], ['RETURN'])): s.emit(gal(end))
                s.label(els); s.stmt(b)
            s.label(end); return
        if k == 'while':
            _, ln, c, body, step = st
            top, test, end, cont = s.new(), s.new(), s.new(), s.new()
            forever = s.isconst(c) and s.const(c, ln)
            if not forever: s.emit(gal(test))
            s.label(top)
            s.loops.append((end, cont))
            s.stmt(body)
            s.loops.pop()
            s.label(cont)
            if step: s.stmt(step)
            s.ln = ln; s.tbusy = set()
            if forever: s.emit(gal(top))
            else: s.label(test); s.hidden[s.fn] = 0; s.cond(s.hoist(c, False, True), top, True)
            s.label(end); return
        if k == 'switch': return s.switch(st)
        if k in ('break', 'continue', 'return'): s.leaving(k)
        if k in ('break', 'continue'):
            if not s.loops or s.loops[-1][0 if k == 'break' else 1] is None:
                raise Error('line %d: %s outside a loop' % (st[1], k))
            return s.emit(gal(s.loops[-1][0 if k == 'break' else 1]))
        if k == 'return':
            if st[2] is not None: s.value(s.hoist(st[2]), RV)
            return s.emit(ret())
        raise Error('line %d: %s' % (st[1], k))

    # ---------------------------------------------------------- multitasking (see compile_program)
    def wrap(s, a): return (a - ORG) & 0xFFFF          # an absolute address, as this block's relative one
    def state(s, vm): return s.wrap(0x2F05 + 0x10 * (vm - 1))   # VM vm's CIDP state byte: 1 run, 4 paused
    def setmulti(s, on, note=''): s.emit(('C7 0%d' % on, 'SETMULTI 0%d' % on, note))
    def setstate(s, vm, v, note):
        r = s.temp(); s.emit(ldx(r, s.state(vm), 'VM%d state' % vm))
        s.emit(('31 0%X %02X' % (r, v), 'COPYMXI R%d %02X' % (r, v), note)); s.untemp(r)

    def shared_in(s, e):
        """The shared variables and arrays e reads or names."""
        out = set()
        s.walk(e, lambda x: out.add(x[1]) if x[0] in ('var', 'idx', 'addr') and isinstance(x[1], str)
               and x[1] in s.shared else None)
        return out

    def shared_written(s, st):
        """The shared names a statement writes: its target, or the array fill/copy/getline/rtcget fills."""
        w = set()
        if st[0] == 'assign' and st[2][0] in ('var', 'idx') and st[2][1] in s.shared: w.add(st[2][1])
        def f(x):
            if x[0] == 'call' and x[1] in ('fill', 'copy', 'getline', 'rtcget') and x[2] and \
                    x[2][0][0] in ('addr', 'var') and x[2][0][1] in s.shared:
                w.add(x[2][0][1])
        s.walk(st, f)
        return w

    def wakes(s, names):
        """After a write to shared data: wake every other task whose wait() looks at it (if it sleeps).
        A task that stop() can reach is woken with multitasking off, so a stop() cannot fall between the
        look and the wake and be undone."""
        if not s.mt or not names: return
        for vm in sorted({v for n in names for v in s.mt['watch'].get(n, ())} - {VM}):
            guard = vm in s.mt.get('stoppable', ()) and not s.atomic
            if guard: s.setmulti(0, 'wake with no other task running: a stop() cannot cut in')
            r = s.temp(); skip = s.new()
            s.emit(ldx(r, s.state(vm), 'VM%d state' % vm))
            s.emit(('9D 1%X 04' % r, 'TESTMXI R%d 04' % r, 'is VM%d asleep in wait()?' % vm))
            s.emit(iff(skip)); s.emit(('31 0%X 01' % r, 'COPYMXI R%d 01' % r, 'wake VM%d' % vm))
            s.untemp(r); s.label(skip)
            if guard: s.setmulti(1)

    def stopstart(s, st):
        """stop(t): t's VM state = STOPPED - the scheduler gives it no turns, and wake-ups (which only wake
        a VM asleep in wait(), state 4) leave it alone. start(t): a STOPPED task runs again (state 1);
        one asleep in wait() looks at its condition again. stop() of the task itself waits to be started."""
        k, ln, name = st
        if not s.mt: raise Error('line %d: %s(%s): %s is not a task' % (ln, k, name, name))
        if name == 'main':
            raise Error('line %d: %s(main): main() cannot be stopped or started - when it ends, the program ends'
                        % (ln, k))
        vm = s.mt['vms'].get(name)
        if vm is None: raise Error('line %d: %s(%s): %s is not a task' % (ln, k, name, name))
        r = s.temp()
        if k == 'stop' and vm == VM:
            if s.atomic: raise Error('line %d: stop(%s) inside atomic { }: nothing else could run to start it' % (ln, name))
            again = s.new()
            s.emit(ldx(r, s.state(vm), 'my VM state'))
            s.emit(('31 0%X %02X' % (r, STOPPED), 'COPYMXI R%d %02X' % (r, STOPPED), 'stop(%s): no more turns' % name))
            s.label(again); s.emit(('9D 1%X %02X' % (r, STOPPED), 'TESTMXI R%d %02X' % (r, STOPPED), 'still stopped?'))
            s.emit(ift(again))
        elif k == 'stop':
            s.emit(ldx(r, s.state(vm), 'VM%d state' % vm))
            s.emit(('31 0%X %02X' % (r, STOPPED), 'COPYMXI R%d %02X' % (r, STOPPED), 'stop(%s): no more turns' % name))
        else:
            skip = s.new()
            if not s.atomic: s.setmulti(0, 'start(%s): look and start with no other task running' % name)
            s.emit(ldx(r, s.state(vm), 'VM%d state' % vm))
            s.emit(('9D 1%X %02X' % (r, STOPPED), 'TESTMXI R%d %02X' % (r, STOPPED), 'stopped?'))
            s.emit(iff(skip)); s.emit(('31 0%X 01' % r, 'COPYMXI R%d 01' % r, 'start(%s): it runs again' % name))
            s.label(skip)
            if not s.atomic: s.setmulti(1)
        s.untemp(r)

    def unsafe(s, node, top_updates=False):
        """Why node cannot run with multitasking off (inside atomic { } or a shared update), or None:
        a wait, a nested atomic, a key or EF wait, or a function that does one - or that updates
        shared data itself (its own SETMULTI 01 would end ours early)."""
        seen, found = set(), []
        def f(x, inner):
            if x[0] == 'wait': found.append('wait()')
            elif x[0] == 'atomic': found.append('atomic { }')
            elif x[0] == 'call' and x[1] in ('getc', 'getline', 'getin', 'waitef'): found.append(x[1] + '()')
            elif x[0] == 'call' and x[1] in s.funcs and x[1] not in seen:
                seen.add(x[1]); s.walk(s.funcs[x[1]][5], lambda y: f(y, True))
            elif x[0] == 'assign' and (inner or top_updates) and s.shared_written(x) and s.shared_in(x[3]):
                found.append('a shared update')
        s.walk(node, lambda x: f(x, False))
        if top_updates:
            s.walk(node, lambda x: found.append('%s()' % x[1]) if x[0] == 'call' and x[1] in s.funcs else None)
        return found[0] if found else None

    def leaving(s, k):
        if not s.atomic: return
        if k == 'return' or len(s.loops) <= s.atomic_loops:
            raise Error('line %d: %s out of atomic { }: multitasking would stay off' % (s.ln, k))

    def wait(s, st):
        """wait(c): with multitasking off, look at c; if false, mark this VM paused, multitasking on, and
        spin until a wake-up sets the state back to 1 (the scheduler stops giving us turns meanwhile).
        Looking and pausing with no other task running means a wake-up cannot fall between them."""
        ln, c = st[1], st[2]
        if not s.mt: raise Error('line %d: wait() needs a task to wake it: see task' % ln)
        if s.atomic: raise Error('line %d: wait() inside atomic { }: nothing could wake it' % ln)
        if s.calls_in(c):
            raise Error('line %d: wait(condition): the condition cannot call a function' % ln)
        if not s.shared_in(c):
            raise Error('line %d: wait(): the condition reads no shared variable, so nothing would wake it' % ln)
        top, spin, done = s.new(), s.new(), s.new()
        s.label(top); s.setmulti(0, 'wait(): look with no other task running')
        s.cond(c, done, True)
        r = s.temp(); s.emit(ldx(r, s.state(VM), 'my VM state'))
        s.emit(('31 0%X 04' % r, 'COPYMXI R%d 04' % r, 'asleep: no more turns until a wake-up'))
        s.setmulti(1)
        s.label(spin); s.emit(('9D 1%X 04' % r, 'TESTMXI R%d 04' % r, 'still asleep?')); s.emit(ift(spin))
        s.emit(gal(top, 'woken: look again')); s.untemp(r)
        s.label(done); s.setmulti(1)

    def calls_in(s, e):
        found = []
        s.walk(e, lambda x: found.append(x) if x[0] == 'call' else None)
        return found

    def switch(s, st):
        """switch (e) { case k: ... default: ... }: the tests first (TESTXI each case), then the bodies in
        order - C's fall-through; break leaves the switch, continue goes to the enclosing loop."""
        _, ln, e, items = st
        e = s.hoist(e, False)
        r = s.reg(e)
        end, dflt, seen = s.new(), None, {}
        labels = []
        for it in items:
            if it[0] == 'case':
                s.ln = it[1]
                if not s.isconst(it[2]): raise Error('line %d: case needs a constant' % it[1])
                v = s.const(it[2], it[1])
                if v in seen: raise Error('line %d: case %d twice (line %d)' % (it[1], v, seen[v]))
                seen[v] = it[1]; L = s.new(); labels.append(L)
                s.emit(testxz(r) if v == 0 else testxi(r, v)); s.emit(ift(L, 'case %d' % v))
            elif it[0] == 'default':
                if dflt: raise Error('line %d: two defaults' % it[1])
                dflt = s.new(); labels.append(dflt)
        s.untemp(r)
        s.emit(gal(dflt or end, 'default' if dflt else 'no case: past the switch'))
        s.loops.append((end, s.loops[-1][1] if s.loops else None))
        i = 0
        for it in items:
            if it[0] in ('case', 'default'): s.label(labels[i]); i += 1
            else: s.stmt(it)
        s.loops.pop()
        s.label(end)

    def asm_value(s, e, n):
        """#e / %e: a constant or an array address, as n bytes."""
        try: x = Parser(lex(e)).expr()
        except Error: raise Error('line %d: cannot read %r' % (s.ln, e))
        v = s.address(x) if x[0] in ('addr', 'str') else s.const(x, s.ln) if s.isconst(x) else None
        if v is None: raise Error('line %d: %r is not a constant or an address' % (s.ln, e))
        if n == 1 and v > 255: raise Error('line %d: %%%s is %d: more than a byte' % (s.ln, e, v))
        return [v >> 8, v & 255] if n == 2 else [v]

    def asm_reg(s, m):
        name = m.group(1)
        fn, name = name.split('.', 1) if '.' in name else (s.fn, name)
        if fn not in s.funcs: raise Error('line %d: no function %s()' % (s.ln, fn))
        if name in s.arrays:
            raise Error('line %d: %s is in memory, not a register: use #&%s' % (s.ln, name, name))
        if name not in s.fvars_of(fn) and name not in s.globals:
            raise Error('line %d: unknown variable %r' % (s.ln, m.group(1)))
        loc = s.where(name, fn)
        if loc[0] != 'r': raise Error('line %d: {%s} did not get a register' % (s.ln, m.group(1)))
        return '%X' % loc[1]

    def asm_label(s, name):
        if name in ('break', 'continue'):
            if not s.loops: raise Error('line %d: @%s outside a loop' % (s.ln, name))
            return s.loops[-1][0 if name == 'break' else 1]
        if name == 'return': return 'R_' + s.fn
        if name in s.funcs and name not in s.asm_defs: return 'F_' + name
        s.asm_used.setdefault(name, s.ln)
        return 'A_%s_%s' % (s.fn, name)

    def asm(s, lines):
        """Inline STELLAR, emitted as written: none of the peephole caches look inside."""
        for ln, label, words in lines:
            s.ln = ln
            if label:
                if label in s.funcs: raise Error('line %d: label %s: is also a function' % (ln, label))
                if label in s.asm_defs: raise Error('line %d: label %s: defined twice' % (ln, label))
                s.asm_defs.add(label); s.rows.append(lbl('A_%s_%s' % (s.fn, label)))
            if not words: continue
            op = words[0].upper()
            if op in OPCODE: op = OPCODE[op]
            elif re.fullmatch(r'[0-9A-F]{2}', op): op = int(op, 16)
            else: raise Error('line %d: unknown command %r' % (ln, words[0]))
            bs, target, text = [op], None, []
            for w in words[1:]:
                if w.startswith('@'):
                    if target or len(words) != 2:
                        raise Error('line %d: a label must be the only operand' % ln)
                    target = s.asm_label(w[1:]); text.append(w[1:]); continue
                if w.startswith('#'): b = s.asm_value(w[1:], 2)
                elif w.startswith('%'): b = s.asm_value(w[1:], 1)
                elif w.startswith("'"): b = unescape(w[1:-1])[:1]
                else:
                    h = re.sub(r'\{([\w.]+)\}', s.asm_reg, w.lstrip('$'))
                    if not re.fullmatch(r'([0-9A-Fa-f]{2})+', h):
                        raise Error('line %d: %r is not whole hex bytes' % (ln, w))
                    b = list(bytes.fromhex(h))
                bs += b; text.append(' '.join('%02X' % x for x in b))
            name = NAMES.get(op, '%02X' % op)
            if target:
                if OPLEN.get(op) != 2: raise Error('line %d: %s does not take an address' % (ln, name))
                row = (('%02X' % op, target), '%s %s' % (name, text[0]), '')
            else:
                want = OPLEN.get(op)
                if want is None: raise Error('line %d: opcode %02X is not a STELLAR command' % (ln, op))
                want = vlen(dict(enumerate(bs)), 0) if want == 0xFF else want + 1
                if len(bs) != want:
                    raise Error('line %d: %s is %d bytes long, not %d' % (ln, name, want, len(bs)))
                row = (' '.join('%02X' % x for x in bs), ' '.join([name] + text), '')
            s.rows.append((row[0], row[1], s.src_note()))
        s.ma = None; s.kreg = {}; s.acc = None                  # the asm may have changed anything

    def native_value(s, text, labels):
        """An operand of a native block, as a number (0 for a label on the sizing pass)."""
        t = re.sub(r'\{([\w.]+)\}', lambda m: str(REGS + 2 * int(s.asm_reg(m), 16)), text)
        t = re.sub(r'\$([0-9A-Fa-f]+)', r'0x\1', t)
        try:
            p = Parser(lex(t)); e = p.expr()
            if p.peek()[0] != 'eof': raise Error('')
        except Error: raise Error('line %d: cannot read %r' % (s.ln, text))
        def ev(e):
            k = e[0]
            if k == 'num': return e[1]
            if k == 'var':
                if labels is not None and e[1] in labels:
                    if e[1] in s.consts:                          # (KEY was both: &W+KEY took the label)
                        raise Error('line %d: %r is both a label in the block and a const' % (s.ln, e[1]))
                    return labels[e[1]]
                if e[1] in s.consts: return s.consts[e[1]]
                if e[1] in s.arrays: return (ORG + s.addr(e[1])) & 0xFFFF
                if labels is None: return 0
                raise Error('line %d: unknown name %r' % (s.ln, e[1]))
            if k == 'addr': return ((ORG + s.addr(e[1])) & 0xFFFF) + (2 if s.wide(e[1]) else 1) * ev(e[2])
            if k == 'idx' and e[1] in s.arrays: return ((ORG + s.addr(e[1])) & 0xFFFF) + (2 if s.wide(e[1]) else 1) * ev(e[2])
            if k == 'call' and e[1] in ('hi', 'lo') and len(e[2]) == 1:
                v = ev(e[2][0]); return (v >> 8) & 255 if e[1] == 'hi' else v & 255
            if k == 'neg': return -ev(e[1])
            if k == 'bin' and e[1] in ('+', '-', '*', '/', '&', '|', '^', '<<', '>>'):
                a, b = ev(e[2]), ev(e[3])
                return {'+': a + b, '-': a - b, '*': a * b, '/': a // max(b, 1), '&': a & b,
                        '|': a | b, '^': a ^ b, '<<': a << b, '>>': a >> b}[e[1]]
            raise Error('line %d: %r is not a native operand' % (s.ln, text))
        return ev(e)

    def native(s, lines):
        """Assemble the block for its place after the data; RUNMC it from here."""
        for ln, label, mn, arg in lines:
            s.ln = ln
            if mn == 'SEP': raise Error('line %d: use CALL addr / RETN, not SEP' % ln)
            if mn in ('PLO', 'PHI', 'INC', 'DEC', 'LDA'):
                try: r = register(arg, ln)
                except AsmError as e: raise Error(str(e))
                ok = r in NATIVE_FREE or (r == 2 and mn in ('INC', 'DEC', 'LDA'))
                # LDA R6: inline parameters - inside a routine reached by CALL, R6 is the SCRT return link
                # (the call saved the outer one); at the block's top level it is the way home: don't
                ok = ok or (r == 6 and mn == 'LDA')
                if not ok:
                    why = {3: 'R3 is the PC', 6: 'R6 is the way home', 2: 'R2 is the stack',
                           0xA: "RA's low byte is not restored by the RUNMC handler"}.get(r, 'the RUNMC handler does not save it')
                    raise Error('line %d: %s R%X: %s (free: R7 R8 R9 RB RD RE RF)' % (ln, mn, r, why))
        end = lines[-1][0] if lines else s.ln
        body = list(lines) + [(end, 'exit', 'SEX', 'R2'), (end, None, 'RETN', '')]
        key = '.native_%d' % len(s.natives)
        base = ORG + s.layout.get(key, 0)
        try: bs, listing, _, shorts = assemble1802(body, base, lambda t, l: s.native_value(t, l))
        except AsmError as e: raise Error(str(e))
        s.natives[key] = (bs, listing, shorts)
        s.ln = lines[0][0] if lines else s.ln
        s.emit(runmc(base, 'native block, %d bytes' % len(bs)))
        s.ma = None; s.kreg = {}; s.acc = None                  # it may have changed anything

    def assign(s, target, e):
        e = s.hoist(e)
        if target[0] == 'var':
            loc = s.where(target[1])
            if loc[0] == 'r':
                d = loc[1]
                if e[0] == 'bin' and e[2] == target and e[1] in ('+', '-') and not s.isconst(e[3]):
                    rb = s.reg(e[3])
                    s.emit(addxyz(d, rb, d) if e[1] == '+' else subxyz(d, rb, d)); s.untemp(rb); return
            return s.store(target[1], e)
        if (target[0] == 'idx' and e[0] == 'bin' and len(e) > 2 and e[2] == target
                and s.side_effects(target[2])):
            # a[f()] += k  (and a[rand() % 6]++): the index is worked out ONCE, as in C - not once
            # to read and again to write
            t = s.temp(); s.value(target[2], t); v = s.temp()
            if s.wide(target[1]):
                s.emit(addxyz(t, t, t)); s.emit(addxi(t, s.addr(target[1]))); s.emit(mxy2(t, v))
                s.value(('bin', e[1], ('rreg', v), e[3]), v); s.emit(xmy2(v, t))
            else:
                s.emit(rdidx(t, s.addr(target[1]))); s.emit(acc2x(v))
                s.value(('bin', e[1], ('rreg', v), e[3]), v); s.emit(x2acc(v)); s.emit(wridx(t, s.addr(target[1])))
            s.untemp(v); s.untemp(t); s.acc = None; return
        if target[0] == 'idx' and s.wide(target[1]):
            v = s.reg(e); p = s.wptr(target[1], target[2])
            s.emit(xmy2(v, p)); s.untemp(p); s.untemp(v); return
        if target[0] == 'idx':
            ri, base = s.index(target[1], target[2])
            s.to_acc(e)
            s.emit(wridx(ri, base)); s.untemp(ri); return
        raise Error('line %d: cannot assign to that' % s.ln)

    # ---------------------------------------------------------- the program
    def compile(s, src):
        s.lines = src.split('\n')
        if not hasattr(s, 'layout'): s.layout = {}              # pass 1: addresses are placeholders
        s.rows = []; s.n = 0; s.strings = {}; s.ma = None; s.kreg = {}; s.acc = None; s.loops = []
        s.natives = {}; s.libs = set()
        s.ln = 1; s.noted = 0; s.fn = None; s.tbusy = set()
        s.rows.append(start('Stellar C: ' + s.name))
        if s.setsize > 1: s.rows.append(('F2 %02X' % s.setsize, 'SETSIZE %02X' % s.setsize, 'the program needs %d KB' % (4 * s.setsize)))
        role = s.mt['role'] if s.mt else None
        if role: s.noted = s.ln                    # (no source line on the start-up code)
        if role == 'main':                         # before any task has run a command: they wait for us
            s.setmulti(0, 'no other VM runs until the shared data is set up')
            for vm in s.mt['tasks']: s.setstate(vm, 4, 'VM%d waits' % vm)
        if s.need_zero: s.emit(ldx(ZERO, 0, 'RC = 0: the index for a[k] and the u8 variables'))
        for a, it in s.arrays.items():             # arrays the program writes are set up again every run
            if a in s.shared and role != 'main': continue          # main() sets up the shared data
            if (a not in s.written and a not in s.shared) or a in s.patched: continue
            s.ln = it[1]; s.noted = 0
            if a in s.bytevars:
                if s.bytevars[a][3] is not None:
                    s.emit(ldai(s.const(s.bytevars[a][3], it[1]))); s.emit(wridx(ZERO, s.addr(a)))
                elif a in s.shared: s.emit(ldai(0)); s.emit(wridx(ZERO, s.addr(a), 'shared: 0 at the start'))
                continue
            size = len(s.array_bytes(it))
            if it[4] is None:
                s.emit(ldx(0xE, s.addr(a))); s.emit(ldx(0xF, s.addr(a) + size - 1))
                s.emit(('FB EF 00', 'FILLMEMXY RE..RF 00', ''))
            else:
                for off in range(0, size, 255):
                    n = min(255, size - off)
                    s.emit(ldx(0xE, s.layout.get('.init_' + a, 0) + off)); s.emit(ldx(0xF, s.addr(a) + off))
                    s.emit(('3B EF %02X' % n, 'COPYMXMY RE -> RF %d' % n, 'from its pristine copy'))
        for g, it in s.globals.items():
            if g in s.shared and role != 'main': continue
            init = it[3] if it[3] is not None or g not in s.shared else ('num', 0)
            if init is not None: s.ln = it[1]; s.noted = 0; s.fn = None; s.tbusy = set(); s.store(g, init)
        s.tbusy = set()
        if role == 'main':
            for vm in s.mt['tasks']: s.setstate(vm, 1, 'start VM%d' % vm)
            s.setmulti(1, 'the tasks run from here')
        s.rows.append(call('F_' + s.entry, 'run %s()' % s.entry))
        s.rows.append(lbl('QUIT'))
        if role == 'main':                         # main() is over: so is the program
            s.setmulti(0); s.kreg = {}
            for vm in s.mt['tasks']: s.setstate(vm, 4, 'stop VM%d' % vm)
            s.setmulti(1); s.rows.append(('00', 'HALT', 'no VM is left running: the program ends'))
        elif role == 'task':                       # a task that is over parks itself: paused for good
            s.setmulti(1, 'in case it stopped inside atomic { }'); s.kreg = {}
            r = s.temp(); s.emit(ldx(r, s.state(VM), 'my VM state')); s.label('PARK')
            s.emit(('31 0%X 04' % r, 'COPYMXI R%d 04' % r, 'paused - a stray wake-up only brings us back here'))
            s.emit(gal('PARK')); s.untemp(r)
        else: s.rows.append(('00', 'HALT', ''))
        for n, fn in s.funcs.items():
            s.fn = n; s.ln = fn[1]; s.noted = 0; s.kreg = {}; s.ma = None; s.acc = None
            s.asm_defs, s.asm_used = set(), {}
            s.rows.append(lbl('F_' + n, '%s()' % n))
            s.stmt(fn[5])
            for name, ln in s.asm_used.items():
                if name not in s.asm_defs: raise Error('line %d: no label %s: in %s()' % (ln, name, n))
            if s.rows[-1][1].startswith('RETURN') and not s.rows[-1][2].startswith('~'):
                s.rows.insert(len(s.rows) - 1, lbl('R_' + n))     # the body's own last RETURN
            else: s.rows.append(lbl('R_' + n)); s.rows.append(ret())
        for name in sorted(s.libs): s.rows += s.lib_rows(name)
        s.rows.append(brk('end marker: the pre-pass stops here'))
        return s.rows

    def array_bytes(s, it):
        size = s.const(it[3], it[1]) if it[3] is not None else len(it[4])
        init = it[4] or []
        vals = [x if isinstance(x, int) else s.const(x, it[1]) for x in init]
        if len(vals) > size: raise Error('line %d: too many initialisers' % it[1])
        if len(it) > 5 and it[5] in ('u16', 'i16'):          # two bytes an element, high byte first
            return b''.join(bytes([(v >> 8) & 255, v & 255]) for v in vals) + bytes(2 * (size - len(vals)))
        return bytes(v & 255 for v in vals) + bytes(size - len(vals))


def compile_file(path):
    return compile_source(open(path).read(), os.path.splitext(os.path.basename(path))[0])


def compile_source(src, name):
    """A one-VM program -> (compiler, emitted rows, labels, data). compile_program takes either kind."""
    items = Parser(lex(src)).program()
    if any(it[0] in MULTI for it in items):
        raise Error('the program has tasks or shared data: compile it with compile_program()')
    return compile_items(items, src, name)


def compile_items(items, src, name, entry='main', mt=None, fixed=None):
    """One block's program. fixed: layout entries decided elsewhere (a task's shared data, which lives
    in main()'s block) - not placed again here."""
    fixed = fixed or {}
    c = Compiler(items, name, entry, mt)
    c.layout = dict(fixed)
    for _ in range(4):
        # pass 1 sizes the code; pass 2 places the data after it
        c.compile(src)
        em, _ = assemble(c.rows, base=ORG)
        code_len = em[-1][0] + len(em[-1][1]) - ORG
        data, a = {}, (code_len + 15) & ~15
        for b, lab in c.strings.items(): c.layout[lab] = a; data[a] = b; a += len(b)
        for n, it in c.arrays.items():
            if n in fixed: continue
            byts = c.array_bytes(it)
            c.layout[n] = a; data[a] = byts if it[4] else b''; a += len(byts)
            if n in c.written and it[4] and n not in c.patched: c.layout['.init_' + n] = a; data[a] = byts; a += len(byts)
        for k, loc in c.loc.items():
            if loc[0] == 'm' and loc[1] not in fixed: c.layout[loc[1]] = a; a += 2
        for key, (bs, _, shorts) in c.natives.items():           # raw 1802 for RUNMC
            if shorts and (a & 255) + len(bs) > 256: a = (a + 255) & ~255   # short branches: one page
            c.layout[key] = a; data[a] = bytes(bs); a += len(bs)
        c.data_end = a
        blocks = (a + 0xFFF) // 0x1000
        if blocks > 3: raise Error('the program needs %d KB: more than SETSIZE 3 gives' % (4 * blocks))
        if blocks > 5 - VM: raise Error('the program needs %d KB: VM%d has only %d KB above it' % (4 * blocks, VM, 4 * (5 - VM)))
        if blocks > c.setsize: c.setsize = blocks; continue
        c.compile(src)
        em, labels = assemble(c.rows, base=ORG)
        if em[-1][0] + len(em[-1][1]) - ORG == code_len:
            for key, (bs, _, shorts) in c.natives.items():       # as assembled for the final layout
                assert len(bs) == len(data[c.layout[key]])
                data[c.layout[key]] = bytes(bs)
                for op, t, ln in shorts:
                    if op >> 8 != t >> 8:
                        raise Error('line %d: short branch at $%04X to $%04X leaves its page: '
                                    'use the long form (LBR, LBZ, ...)' % (ln, op - 1, t))
            if ORG + c.data_end > TOP:          # Craig's Elf2K: $7F00-$7FFF is not free RAM
                raise Error('the program ends at $%04X: past $%04X ($7F00-$7FFF is not available - %d bytes too many)'
                            % (ORG + c.data_end - 1, TOP - 1, ORG + c.data_end - TOP))
            return c, em, labels, {k: v for k, v in data.items() if v}
    raise Error('the layout did not settle')


# ====================================================================== MULTITASKING: one program, several VMs
# task name() { }  runs in a VM of its own beside main() (VM1); shared variables and arrays live in main()'s
# block and every part reaches them by absolute address, written as the wrapped relative address (STELLAR adds
# the block's page with no clamp: VM2's $EF00 is $3F00). chan name[n] is a queue of bytes: a shared ring plus
# three shared counters, with send / recv / ready rewritten below into wait() and atomic { }.
MULTI = ('task', 'chan', 'shared')


class Part:
    def __init__(s, title, vm, c, em, labels, data):
        s.title, s.vm, s.c, s.em, s.labels, s.data = title, vm, c, em, labels, data
        s.org = 0x4000 + (vm - 1) * 0x1000
        s.code = em[-1][0] + len(em[-1][1]) - s.org


class Program:
    """A compiled program: one Part per VM it uses (a one-VM program has one, built for VM N by --vm N)."""
    def __init__(s, name, parts, single, shared=None, warnings=()):
        s.name, s.parts, s.single, s.shared, s.warnings = name, parts, single, shared or {}, list(warnings)

    def lst(s, path):
        """The .lst: every part's disassembly, then one block of D-lines for all of them."""
        old = VM
        try:
            if s.single:
                p = s.parts[0]; set_vm(p.vm)
                return render_lst(path, p.c, p.em, p.labels, p.data)
            heads, code = [], []
            for p in s.parts:
                set_vm(p.vm)
                text = render_lst(path, p.c, p.em, p.labels, p.data, claims=False)
                h, _, d = text.partition('; CODE  -  download this block\n')
                heads.append(h.rstrip('\n')); code.append(d.strip('\n'))
        finally: set_vm(old)
        n = sum(len(p.em) for p in s.parts)
        top = ['; ' + '=' * 74,
               '; %s  -  a MULTITASKING program compiled from %s by scc (Stellar C): %d VMs, ONE file'
               % (s.name, os.path.basename(path), len(s.parts)),
               '; ' + '=' * 74,
               '; %d STELLAR commands in all.' % n]
        for p in s.parts:
            top.append(';   VM%d $%04X-$%04X  %-14s %4d commands, %5d bytes of code, %5d in all'
                       % (p.vm, p.org, min(p.org + 0x1000 * p.c.setsize, TOP) - 1, p.title + '()', len(p.em), p.code, p.c.data_end))
        if s.shared:
            top.append('; shared (absolute): ' + ', '.join('%s $%04X' % (k, v) for k, v in s.shared.items()
                                                          if '__' not in k))
        top += ['; Load this one file, then cold boot: every VM starts at once, and main() holds the tasks',
                '; until the shared data is set up. When main() ends, the whole program ends.']
        top += ['; warning: ' + w for w in s.warnings]
        text = '\n'.join(top + [';'] + heads + ['', '; CODE  -  download this block', ''] +
                         ['\n\n'.join(code)]) + '\n'
        return claim_vms_text(text)[0]

    def pokes(s, path='program.sc'):
        """(address, byte) for every D-line, as Craig loads it."""
        out = []
        for ln in s.lst(path).split('\n'):
            m = re.match(r'D ([0-9A-F]{4}) (.*)$', ln)
            if m:
                a = int(m.group(1), 16)
                out += [(a + i, int(b, 16)) for i, b in enumerate(m.group(2).split())]
        return out

    def symbols(s):
        if s.single: return symbols(s.parts[0].c, s.parts[0].labels)
        old = VM
        try:
            out = {'shared': s.shared, 'vms': {}}
            for p in s.parts:
                set_vm(p.vm); out['vms'][p.vm] = dict(symbols(p.c, p.labels), part=p.title)
            return out
        finally: set_vm(old)

    def summary(s):
        if s.single:
            p = s.parts[0]; return '%d commands, %d bytes of code, %d in all' % (len(p.em), p.code, p.c.data_end)
        return '; '.join('VM%d %s(): %d commands, %d in all' % (p.vm, p.title, len(p.em), p.c.data_end) for p in s.parts)


def _walk(node, fn):
    if isinstance(node, tuple):
        fn(node)
        for x in node[1:]:
            if isinstance(x, (tuple, list)): _walk(x, fn)
    elif isinstance(node, list):
        for x in node: _walk(x, fn)


def _names(node, names):
    """The names from `names` that node refers to: variables, arrays, and words of asm / native text."""
    out = set()
    def f(x):
        if x[0] in ('var', 'idx', 'addr') and isinstance(x[1], str) and x[1] in names: out.add(x[1])
        if x[0] == 'asm':
            out.update(n for _, _, words in x[2] for w in words for n in re.findall(r'[A-Za-z_]\w*', w) if n in names)
        if x[0] == 'native':
            out.update(n for _, _, _, arg in x[2] for n in re.findall(r'[A-Za-z_]\w*', arg) if n in names)
    _walk(node, f)
    return out


def _chans(items, chans):
    """send / recv / ready -> wait() and atomic { } on the queue's shared ring and counters."""
    def parts(ch, ln, what):
        if ch[0] != 'var' or ch[1] not in chans: raise Error('line %d: %s(c): c must be a chan' % (ln, what))
        n = ch[1]; return n, chans[n], n + '__h', n + '__t', n + '__n'
    def inc(v, n, ln):                                  # v = v + 1, back to 0 at n
        return [('assign', ln, ('var', v), ('bin', '+', ('var', v), ('num', 1))),
                ('if', ln, ('bin', '==', ('var', v), ('num', n)), ('assign', ln, ('var', v), ('num', 0)), None)]
    def recv(ch, ln, target):
        buf, n, h, tl, cnt = parts(ch, ln, 'recv')
        body = ([('assign', ln, target, ('idx', buf, ('var', tl)))] if target else []) + inc(tl, n, ln) + \
               [('assign', ln, ('var', cnt), ('bin', '-', ('var', cnt), ('num', 1)))]
        return [('wait', ln, ('bin', '!=', ('var', cnt), ('num', 0))), ('atomic', ln, ('block', body))]
    def ex(e, ln):
        if not isinstance(e, tuple): return e
        if e[0] == 'call' and e[1] == 'ready':
            if len(e[2]) != 1: raise Error('line %d: ready(c) takes one argument' % ln)
            return ('var', parts(e[2][0], ln, 'ready')[4])
        if e[0] == 'call' and e[1] in ('send', 'recv'):
            raise Error('line %d: %s() must be a statement of its own: send(c, v);  x = recv(c);' % (ln, e[1]))
        return tuple(ex(x, ln) if isinstance(x, tuple) else [ex(y, ln) for y in x] if isinstance(x, list) else x
                     for x in e)
    def st(x):
        k = x[0]
        if k == 'block': return ('block', [st(y) for y in x[1]])
        if k in ('case', 'default', 'break', 'continue', 'asm', 'native'): return x
        ln = x[1]
        if k == 'expr' and x[2][1] == 'send':
            if len(x[2][2]) != 2: raise Error('line %d: send(c, v) takes two arguments' % ln)
            buf, n, h, tl, cnt = parts(x[2][2][0], ln, 'send')
            v = ex(x[2][2][1], ln); pre = []
            if not (v[0] == 'num' or (v[0] == 'var' and v[1] not in chans)):
                pre = [('local', ln, '.sv', v)]; v = ('var', '.sv')     # worked out before the queue is locked
            body = [('assign', ln, ('idx', buf, ('var', h)), v)] + inc(h, n, ln) + \
                   [('assign', ln, ('var', cnt), ('bin', '+', ('var', cnt), ('num', 1)))]
            return ('block', pre + [('wait', ln, ('bin', '<', ('var', cnt), ('num', n))), ('atomic', ln, ('block', body))])
        if k == 'expr' and x[2][1] == 'recv':
            return ('block', recv(x[2][2][0] if x[2][2] else ('num', 0), ln, None))
        if k == 'assign' and x[3][0] == 'call' and x[3][1] == 'recv':
            return ('block', recv(x[3][2][0] if x[3][2] else ('num', 0), ln, ex(x[2], ln)))
        if k == 'local' and x[3] and x[3][0] == 'call' and x[3][1] == 'recv':
            return ('block', [('local', ln, x[2], None)] + recv(x[3][2][0] if x[3][2] else ('num', 0), ln, ('var', x[2])))
        if k == 'if': return ('if', ln, ex(x[2], ln), st(x[3]), st(x[4]) if x[4] else None)
        if k == 'while': return ('while', ln, ex(x[2], ln), st(x[3]), st(x[4]) if x[4] else None)
        if k == 'switch': return ('switch', ln, ex(x[2], ln), [st(y) for y in x[3]])
        if k == 'atomic': return ('atomic', ln, st(x[2]))
        return tuple(ex(y, ln) if isinstance(y, tuple) else y for y in x)
    return [it[:5] + (st(it[5]),) if it[0] == 'func' else it for it in items]


def compile_program(src, name):
    """Any program -> Program. Without a task it is compile_source's, for the VM set_vm() chose."""
    items = Parser(lex(src)).program()
    if not any(it[0] in MULTI for it in items):
        c, em, labels, data = compile_items(items, src, name)
        return Program(name, [Part('main', VM, c, em, labels, data)], True)
    if VM != 1: raise Error('a program with tasks starts in VM1: build it without --vm')
    tasks = [it for it in items if it[0] == 'task']
    if not tasks:
        ln = next(it[1] for it in items if it[0] in MULTI)
        raise Error('line %d: shared data and chan need at least one task' % ln)
    if len(tasks) > 3: raise Error('line %d: at most 3 tasks: VM2-VM4 (main() is VM1)' % tasks[3][1])
    k = Compiler.__new__(Compiler); k.consts = {}          # the constants, for chan sizes and task(N)
    for it in items:
        if it[0] == 'const': k.consts[it[2]] = k.const(it[3], it[1])
    funcs = {it[3] for it in items if it[0] == 'func'}
    chans, out = {}, []
    for it in items:
        if it[0] == 'chan':
            n = k.const(it[3], it[1])
            if not 2 <= n <= 255: raise Error('line %d: chan %s[%d]: the size must be 2-255' % (it[1], it[2], n))
            chans[it[2]] = n
            out += [('array', it[1], it[2], ('num', n), None, 'u8')] + \
                   [('scalar', it[1], it[2] + x, None, 'u8') for x in ('__h', '__t', '__n')] + \
                   [('shared', it[1], [it[2], it[2] + '__h', it[2] + '__t', it[2] + '__n'])]
        elif it[0] == 'task':
            if it[2] in funcs or it[2] == 'main' or any(x[0] == 'task' and x[2] == it[2] for x in out):
                raise Error('line %d: %s is the name of a function or another task' % (it[1], it[2]))
            out.append(('func', it[1], 'void', it[2], [], it[4]))
        else: out.append(it)
    items = _chans(out, chans)
    shared = set().union(*[set(it[2]) for it in items if it[0] == 'shared'])
    fn = {it[3]: it for it in items if it[0] == 'func'}
    entries = ['main'] + [it[2] for it in tasks]
    calls = {n: set() for n in fn}
    for n, it in fn.items():
        def f(x, n=n):
            if x[0] == 'call' and x[1] in fn: calls[n].add(x[1])
        _walk(it[5], f)
    for n in fn:
        for m in calls[n]:
            if m in entries:
                raise Error('%s() calls %s(), which is %s' % (n, m, 'main()' if m == 'main' else
                            'a task: it runs by itself in its own VM, it cannot be called'))
    def reach(e):
        seen, todo = {e}, [e]
        while todo:
            for m in calls[todo.pop()] - seen: seen.add(m); todo.append(m)
        return seen
    reached = [reach(e) for e in entries]
    plain = {it[2] for it in items if it[0] in ('scalar', 'array')} - shared
    users = {}
    for i, fs in enumerate(reached):
        for f in fs:
            for n in _names(fn[f][5], plain): users.setdefault(n, set()).add(i)
    for n, us in users.items():
        if len(us) > 1:
            who = ' and '.join('%s()' % entries[i] for i in sorted(us))
            raise Error('%s is used by %s: make it shared, or keep it in one task' % (n, who))
    watch, keys, natives, stopped = {}, [], False, set()   # what each part's wait()s look at; tasks stop() names
    for i, fs in enumerate(reached):
        reads_keys = False
        def f(x, i=i):
            nonlocal reads_keys, natives
            if x[0] == 'wait':
                for n in _names(x[2], shared): watch.setdefault(n, set()).add(i)
            if x[0] == 'call' and x[1] in ('getc', 'getline', 'keyready'): reads_keys = True
            if x[0] == 'native': natives = True
            if x[0] in ('stop', 'start'):
                if x[2] != 'main' and x[2] not in entries:
                    raise Error('line %d: %s(%s): %s is not a task' % (x[1], x[0], x[2], x[2]))
                if x[0] == 'stop' and x[2] != 'main': stopped.add(x[2])
        for g in fs: _walk(fn[g][5], f)
        if reads_keys: keys.append(entries[i])
    warnings = []
    if len(keys) > 1:
        warnings.append('%s all read the keyboard: whichever asks first gets each key'
                        % ', '.join('%s()' % k for k in keys))
    if natives: warnings.append('native { } stops every VM while it runs (RUNMC does not yield)')
    for it in items:
        if it[0] != 'func': continue
        def f(x):
            if x[0] == 'while' and x[3] == ('block', []) and _names(x[2], shared):
                warnings.append('line %d: a busy wait on shared data takes turns from every other task: '
                                'use wait(...)' % x[1])
        _walk(it[5], f)
    pins = [k.const(it[3], it[1]) if it[3] is not None else None for it in tasks]
    def part_items(i):
        fs = reached[i]; mine = {n for n, us in users.items() if i in us}
        return [it for it in items if it[0] in ('const', 'signed', 'shared') or
                (it[0] in ('scalar', 'array') and (it[2] in shared or it[2] in mine)) or
                (it[0] == 'func' and it[3] in fs)]
    sizes, old = [1] * len(entries), VM
    try:
        for _ in range(8):
            # main() at VM1; pinned tasks where they asked; the rest in the first free VMs, in order
            used = {v: 'main()' for v in range(1, 1 + sizes[0])}
            vms = [1] + [None] * len(tasks)
            def take(i, v):
                for b in range(v, v + sizes[i + 1]): used[b] = tasks[i][2] + '()'
                vms[i + 1] = v
            for i, pin in enumerate(pins):
                if pin is None: continue
                if not 2 <= pin <= 4: raise Error('line %d: task(%d): VM2-VM4' % (tasks[i][1], pin))
                clash = [used[b] for b in range(pin, pin + sizes[i + 1]) if b in used]
                if clash or pin + sizes[i + 1] > 5:
                    raise Error('line %d: task(%d) %s(): %s' % (tasks[i][1], pin, tasks[i][2],
                                'VM%d is taken by %s' % (pin, clash[0]) if clash else 'it needs %d blocks from VM%d'
                                % (sizes[i + 1], pin)))
                take(i, pin)
            for i, pin in enumerate(pins):
                if pin is not None: continue
                v = next((v for v in range(2, 6 - sizes[i + 1]) if all(b not in used for b in range(v, v + sizes[i + 1]))), None)
                if v is None:
                    raise Error('the program needs %d blocks of 4 KB (%s): there are 4' % (sum(sizes),
                                ', '.join('%s() %d' % (e, sz) for e, sz in zip(entries, sizes))))
                take(i, v)
            mt = {'tasks': vms[1:], 'watch': {n: {vms[i] for i in s} for n, s in watch.items()},
                  'vms': dict(zip(entries, vms)), 'stoppable': {vms[entries.index(n)] for n in stopped}}
            set_vm(1)
            c, em, labels, data = compile_items(part_items(0), src, name, 'main', dict(mt, role='main'))
            parts = [Part('main', 1, c, em, labels, data)]
            addr = {n: 0x4000 + c.layout[n] for n in c.arrays if n in shared}
            addr.update({n: 0x4000 + c.layout['.v__' + n] for (f, n), loc in c.loc.items() if f is None and n in shared})
            for i, e in enumerate(entries[1:], 1):
                set_vm(vms[i])
                fixed = {(n if n in c.arrays else '.v__' + n): (a - ORG) & 0xFFFF for n, a in addr.items()}
                ct, emt, lt, dt = compile_items(part_items(i), src, name, e, dict(mt, role='task'), fixed)
                parts.append(Part(e, vms[i], ct, emt, lt, dt))
            new = [p.c.setsize for p in parts]
            if new == sizes:
                return Program(name, parts, False, dict(sorted(addr.items(), key=lambda x: x[1])), warnings)
            sizes = new
        raise Error('the VMs did not settle')
    finally: set_vm(old)


def symbols(c, labels):
    """Where everything went - for a debugger or a test harness."""
    out = {'vars': {}, 'arrays': {k: ORG + c.layout[k] for k in c.arrays},
           'labels': {k: v for k, v in labels.items() if not re.match(r'L\d+$', k)}}
    for (fn, v), loc in c.loc.items():
        key = v if fn is None else '%s.%s' % (fn, v)
        out['vars'][key] = {'reg': loc[1]} if loc[0] == 'r' else {'mem': ORG + c.layout[loc[1]]}
    if c.natives: out['natives'] = [ORG + c.layout[k] for k in c.natives]
    return out


def render_lst(path, c, em, labels, data, extra='', claims=True):
    """The .lst text, VM claims included."""
    lines = ['; ' + '=' * 74,
             '; %s  -  compiled from %s by scc (Stellar C, prototype)   loads at $%04X%s'
             % (c.name, os.path.basename(path), ORG, '-$%X' % (ORG + 0x1000 * c.setsize - 1) if c.setsize > 1 else ''),
             '; ' + '=' * 74,
             '; %d STELLAR commands, %d bytes of code, %d bytes of data.'
             % (len(em), em[-1][0] + len(em[-1][1]) - ORG, sum(len(d) for d in data.values())),
             '; registers: ' + ', '.join('%s R%d' % ((f + '.' if f else '') + v, l[1])
                                          for (f, v), l in sorted(c.loc.items(), key=lambda x: (x[1][0], str(x[1][1])))
                                          if l[0] == 'r' and not v.startswith('.')),
             '; in memory: ' + (', '.join('%s' % ((f + '.' if f else '') + v) for (f, v), l in c.loc.items() if l[0] == 'm') or 'nothing'),
             ]
    if extra: lines += ['; ' + x for x in extra.split('\n')]
    lines += [';', '; DISASSEMBLY  -  commented out; the loader skips it', ';']
    rev = {}
    for k, v in labels.items():
        if not re.match(r'L\d+$', k) and not k.startswith('R_'): rev.setdefault(v, []).append(k)
    for a, bs, asm, note in em:
        for k in rev.get(a, []): lines.append('; %s:' % (k[2:] + '()' if k.startswith('F_') else k))
        lines.append(('; D %04X %-14s %-30s %s' % (a, ' '.join('%02X' % b for b in bs), asm, note)).rstrip())
    for key, (bs, listing, _) in c.natives.items():
        lines += [';', '; NATIVE 1802  -  %d bytes at $%04X, run by RUNMC' % (len(bs), ORG + c.layout[key]), ';']
        for a, b, text, ln in listing:
            if not b: lines.append('; %s' % text); continue
            src = c.lines[ln - 1]
            note = src[len(strip_comment(src)):].lstrip(';/ ').strip()[:44] if text.split()[0] not in ('exit:', 'RETN') else ''
            lines.append(('; N %04X %-10s %-26s %s' % (a, ' '.join('%02X' % x for x in b), text, note)).rstrip())
    lines += ['', '; CODE  -  download this block', '']
    lines += ['D %04X %s' % (a, ' '.join('%02X' % b for b in bs)) for a, bs, _, _ in em]
    for rel, d in sorted(data.items()):
        lines.append('')
        for off in range(0, len(d), 16):
            lines.append('D %04X %s' % (ORG + rel + off, ' '.join('%02X' % b for b in d[off:off + 16])))
    text = '\n'.join(lines) + '\n'
    return claim_vms_text(text)[0] if claims else text


def write_lst(path, out, c, em, labels, data, extra=''):
    import json
    open(out, 'w').write(render_lst(path, c, em, labels, data, extra))
    json.dump(symbols(c, labels), open(os.path.splitext(out)[0] + '.sym.json', 'w'), indent=1)


def compile_text(src, name='program'):
    """For the web page: source text -> {'lst', 'summary'} or {'error'}; no files touched."""
    try:
        prog = compile_program(src, name)
    except Error as e:
        return {'error': 'scc: %s' % e}
    except (ValueError, KeyError, IndexError, TypeError, RecursionError) as e:
        return {'error': 'scc: internal error (%s: %s) - please report this program' % (type(e).__name__, e)}
    return {'lst': prog.lst(name + '.sc'), 'summary': prog.summary(), 'warnings': prog.warnings}


if __name__ == '__main__':
    if len(sys.argv) < 2: print(__doc__); sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[sys.argv.index('-o') + 1] if '-o' in sys.argv else os.path.splitext(src)[0] + '.lst'
    try:
        if '--vm' in sys.argv: set_vm(int(sys.argv[sys.argv.index('--vm') + 1]))
        prog = compile_program(open(src).read(), os.path.splitext(os.path.basename(src))[0])
        import json
        open(out, 'w').write(prog.lst(src))
        json.dump(prog.symbols(), open(os.path.splitext(out)[0] + '.sym.json', 'w'), indent=1)
    except Error as e:
        print('scc: %s' % e); sys.exit(1)
    for w in prog.warnings: print('scc: warning: %s' % w)
    print('%s: %s -> %s' % (src, prog.summary(), out))
