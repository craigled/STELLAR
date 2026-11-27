# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Multitasking (task / shared / chan / wait / atomic): each program is compiled into one .lst for several
VMs, loaded the way Craig loads it (its D-lines, claims included) into the V0061.37 image as flashed, and
run in the simulator with keys typed one at a time. Checked:

  tasks      examples/tasks.sc: keys go VM2 -> queue -> VM1 while VM3 counts; the total grows between keys,
             main() costs no commands while it sleeps, only the shared area and the VM cores change; from
             dirty memory, and again without reloading
  race       three VMs each add 1 to one shared total 1,000 times: exactly 3,000 - and the same program with
             the update split in two (so it is not one step) loses updates, which shows the test can see them
  queue      100 numbers through a 4-deep chan: in order, none lost, the sender waits when it is full
  painter    main() needs two blocks (VM1+2), a task pinned to VM4, another in VM3: wait() on a shared frame
             number, a shared array, and main() ending while a task still waits for a key
  features   shared i16 and u8 arrays with initialisers, fill() on shared data, a native { } block reading
             a shared array by its absolute address, getline() into a shared buffer
  stopstart  stop()/start(): a counter held and let go, a sleeper not woken while stopped, a task that
             stops itself; from dirty memory, and again without reloading
  errors     the mistakes the compiler refuses
  one-VM     every example without a task compiles exactly as its committed .lst

    python3 tasks_verify.py
"""
import os, sys, random, glob, re
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'Firmware-Math'))
import scc
import opcode_sweep as S
import rtc_verify as V

GAP = 300_000            # 1802 instructions between keys (~0.2 s at 3 MHz)


def build(src, name='prog'):
    return scc.compile_program(src, name)


def boot(prog, dirty=None, mem=None):
    m = bytearray(S.image('37') if mem is None else mem)
    if dirty is not None:
        rng = random.Random(dirty)
        for a in range(0x4000, 0x7F00): m[a] = rng.randrange(256)
    return S.boot(bytes(m), prog.pokes() if mem is None else [], keys=b'')


def type_keys(c, keys, gap=GAP, cap=20_000_000):
    for k in keys:
        V.run(c, gap); c.io_in[3].q.append(k)
    r = V.run(c, cap)
    return r, bytes(c.io_out[3]).decode('latin1')


def errors(c): return [c.M[0x3000 + v * 0x400 + 0x4F] for v in range(4)]
def commands(c, vm): b = 0x3033 + 0x400 * (vm - 1); return int.from_bytes(bytes(c.M[b:b + 4]), 'big')


def report(name, good, why=''):
    print('%-10s %s%s' % (name, 'OK' if good else 'FAIL', '' if good else '  ' + why))
    return good


def t_tasks():
    prog = build(open(os.path.join(HERE, 'examples', 'tasks.sc')).read(), 'tasks')
    vms = [(p.title, p.vm) for p in prog.parts]
    ok = vms == [('main', 1), ('keyboard', 2), ('counter', 3)]
    shared = (min(prog.shared.values()), max(prog.shared.values()) + 2)
    for label, dirty in (('clean', None), ('dirty', 1802)):
        c = boot(prog, dirty)
        before = bytes(c.M)
        V.run(c, GAP); a = commands(c, 1); V.run(c, GAP); b = commands(c, 1)
        asleep = a == b and c.M[0x2F05] == 4                     # main() waits in recv(): no turns at all
        r, out = type_keys(c, b'xyzq')
        totals = [int(x) for x in re.findall(r'[xyz] total (\d+)\r\n', out)]
        good = (r == 'halt' and out.startswith('type; q quits\r\n') and out.endswith('bye\r\n') and len(totals) == 3
                and totals[0] > 0 and totals[0] < totals[1] < totals[2] and not any(errors(c)) and asleep)
        changed = [x for x in range(0x10000) if c.M[x] != before[x] and not 0x2F00 <= x < 0x4000
                   and not shared[0] <= x < shared[1]]
        good &= not changed
        c2 = boot(prog, mem=c.M)                                # cold boot again, no reload
        r2, out2 = type_keys(c2, b'xyzq')
        t2 = [int(x) for x in re.findall(r'[xyz] total (\d+)\r\n', out2)]
        good &= r2 == 'halt' and len(t2) == 3 and 0 < t2[0] < t2[1] < t2[2] and not any(errors(c2)) and \
            t2[0] < totals[2]                                   # the total started again from 0
        ok &= good
        print('  %s: %s' % (label, out.replace('\r\n', ' | ')))
        if not good: print('     asleep %s, changed outside %s, rerun %r' % (asleep, ['%04X' % x for x in changed[:8]], out2))
    return report('tasks', ok, '%r' % vms)


RACE = """
shared u16 total;
shared u8 done;
task a() { u16 i; for (i = 0; i < 1000; i++) total++; done++; }
task b() { u16 i; for (i = 0; i < 1000; i++) total += 1; done++; }
void main() { u16 j; for (j = 0; j < 1000; j++) total = total + 1; wait(done == 2); printu(total); print("\\r\\n"); }
"""


def t_race():
    out = {}
    for label, src in (('safe', RACE), ('split', re.sub(r'total(\+\+| \+= 1| = total \+ 1);',
                                                       '{ u16 t; t = total; total = t + 1; }', RACE))):
        c = boot(build(src))
        r, text = type_keys(c, b'', cap=60_000_000)
        out[label] = text.strip()
        if r != 'halt' or any(errors(c)): out[label] += ' (%s, errors %s)' % (r, errors(c))
    print('  three VMs x 1,000: %s; with the update split in two: %s' % (out['safe'], out['split']))
    return report('race', out['safe'] == '3000' and out['split'].isdigit() and int(out['split']) < 3000)


QUEUE = """
chan q[4];
shared u16 waited;
task producer() {
    u16 i;
    for (i = 0; i < 100; i++) {
        if (ready(q) == 4) waited++;
        send(q, i);
    }
}
void main() {
    u16 i, k, bad, sum;
    bad = 0; sum = 0;
    for (i = 0; i < 100; i++) {
        k = recv(q);
        if (k != i) bad++;
        sum += k;
        if (i % 10 == 0) delay(255);           // slow down now and then: the queue fills up
    }
    printu(sum); putc(' '); printu(bad); print("\\r\\n");
    if (waited) print("full\\r\\n");
}
"""


def t_queue():
    c = boot(build(QUEUE))
    r, text = type_keys(c, b'', cap=60_000_000)
    print('  sum, out of order:', text.replace('\r\n', ' | '))
    return report('queue', r == 'halt' and text == '4950 0\r\nfull\r\n' and not any(errors(c)), repr(text))


PAINTER = """
shared u8 board[16];
shared u16 frame;
chan keys[4];
u8 big[5000];                        // main() needs two blocks: VM1 + VM2
task(4) painter() {                  // pinned to VM4
    u16 shown, i, sum;
    shown = 0;
    while (1) {
        wait(frame != shown);
        shown = frame; sum = 0;
        for (i = 0; i < 16; i++) sum += board[i];
        atomic { print("frame "); printu(shown); print(" sum "); printu(sum); print("\\r\\n"); }
    }
}
task kb() { while (1) send(keys, getc()); }   // never returns: main() ends it
void main() {
    u16 k, i;
    big[4999] = 7;
    while (1) {
        k = recv(keys);
        if (k == 'q') break;
        atomic { for (i = 0; i < 16; i++) board[i] = k - 'a' + big[4999]; frame++; }
    }
    print("end\\r\\n");
}
"""


def t_painter():
    prog = build(PAINTER)
    vms = [(p.title, p.vm, p.c.setsize) for p in prog.parts]
    lst = prog.lst('painter.sc')
    c = boot(prog)
    r, text = type_keys(c, b'acbq')
    want = 'frame 1 sum 112\r\nframe 2 sum 144\r\nframe 3 sum 128\r\nend\r\n'
    print('  %s: %s' % (vms, text.replace('\r\n', ' | ')))
    return report('painter', vms == [('main', 1, 2), ('painter', 4, 1), ('kb', 3, 1)] and text == want and
                  r == 'halt' and not any(errors(c)) and 'SETSIZE 02' in lst, repr(text))


FEATURES = r"""
shared i16 temps[] = { -5, 300, -20 };
shared u8 line[20];
shared u8 msg[] = "hi";
shared u16 got, sum, step;
shared u8 ack = 0;
task worker() {                       // VM2: native code reads the shared array by its absolute address
    u16 s;
    wait(step == 1);
    native {
        LDI hi(&line)
        PHI R7
        LDI lo(&line)
        PLO R7
        LDI 0
        PHI RD
        PLO RD
        SEX R2
    loop:
        LDA R7
        BZ done
        STR R2
        GLO RD
        ADD
        PLO RD
        GHI RD
        ADCI 0
        PHI RD
        BR loop
    done:
        LDI hi({s})
        PHI R9
        LDI lo({s})
        PLO R9
        GHI RD
        STR R9
        INC R9
        GLO RD
        STR R9
    }
    sum = s;
    fill(&line[0], '*', 3);
    step = 2;
}
task reader() {                       // VM3: a line into the shared buffer; the shared i16s
    u16 i;
    getline(line);
    got = 1;
    atomic { for (i = 0; i < 3; i++) { printi(temps[i]); putc(' '); } print(msg); print("\r\n"); }
    temps[1] = temps[1] - 400;
    ack = ack + 1;
}
void main() {
    wait(got == 1);
    wait(ack == 1);
    print("line "); print(line); print("\r\n");
    step = 1;
    wait(step == 2);
    print("sum "); printu(sum); print(" now "); print(line); print(" t1 "); printi(temps[1]); print("\r\n");
}
"""


def t_features():
    prog = build(FEATURES)
    want = 'ABC\r\n-5 300 -20 hi\r\nline ABC\r\nsum 198 now *** t1 -100\r\n'
    ok = True
    for label, dirty in (('clean', None), ('dirty', 7)):
        c = boot(prog, dirty)
        r, text = type_keys(c, b'ABC\r', gap=200_000)
        c2 = boot(prog, mem=c.M)
        r2, text2 = type_keys(c2, b'ABC\r', gap=200_000)
        ok &= text == want and text2 == want and r == r2 == 'halt' and not any(errors(c)) and not any(errors(c2))
    print('  ' + text.replace('\r\n', ' | '))
    return report('features', ok and any('native' in w for w in prog.warnings), repr(text))


ERRORS = [
    ('u16 n;\ntask t() { n = 1; }\nvoid main() { n = 2; }', 'make it shared'),
    ('shared u16 x;\nvoid main() { }', 'need at least one task'),
    ('void main() { u16 x; wait(x == 1); }', 'needs a task'),
    ('task t() { }\nvoid main() { u16 x; x = 0; wait(x == 1); }', 'reads no shared variable'),
    ('task t() { }\nchan c[4];\nvoid main() { printu(recv(c) + 1); }', 'statement of its own'),
    ('task t() { }\nvoid main() { atomic { getc(); } }', 'getc() inside atomic'),
    ('task t() { }\nvoid main() { while (1) { atomic { break; } } }', 'break out of atomic'),
    ('task t() { }\nvoid main() { t(); }', 'it cannot be called'),
    ('task a() { }\ntask b() { }\ntask c() { }\ntask d() { }\nvoid main() { }', 'at most 3 tasks'),
    ('task(2) a() { }\ntask(2) b() { }\nvoid main() { }', 'VM2 is taken'),
    ('task t() { }\nshared u16 x;\nu16 f() { return 1; }\nvoid main() { x = x + f(); }', 'work it out first'),
    ('task t() { }\nshared u16 x;\nvoid g() { wait(x == 1); }\nvoid main() { atomic { g(); } }', 'inside atomic'),
    ('u8 a[5000];\nu8 b[5000];\ntask s() { }\ntask t() { b[0] = 1; }\nvoid main() { a[0] = 1; }', 'blocks of 4 KB'),
    ('task t() { }\nvoid main() { stop(main); }', 'main() cannot be stopped'),
    ('task t() { }\nvoid main() { start(nobody); }', 'nobody is not a task'),
    ('void f() { }\ntask t() { }\nvoid main() { stop(f); }', 'f is not a task'),
    ('void main() { stop(x); }', 'x is not a task'),
    ('shared u8 x;\ntask t() { atomic { stop(t); } }\nvoid main() { x = 1; }', 'inside atomic'),
    ('shared u8 x;\ntask t() { }\nvoid main() { x = stop(t); }', 'a statement of its own'),
]


STOPSTART = r"""
shared u16 adds;
shared u8 go;
task counter() { while (1) adds++; }
task sleeper() { while (1) { wait(go != 0); go = 0; print("woke\r\n"); } }
task self() { print("A\r\n"); stop(self); print("B\r\n"); }
void spin() { u16 i; i = 0; while (i < 300) i++; }
void main() {
    u16 a;
    spin();
    a = adds; spin(); if (adds != a) print("runs\r\n");
    stop(counter); spin();
    a = adds; spin(); if (adds == a) print("stopped\r\n");
    start(counter); spin();
    if (adds != a) print("runs again\r\n");
    stop(sleeper); go = 1; spin(); spin();
    if (go == 1) print("no wake while stopped\r\n");
    start(sleeper); spin(); spin();
    if (go == 0) print("started\r\n");
    start(self); spin();
}
"""


def t_stopstart():
    """stop() holds a task still (a counter that counts, a sleeper that a write would wake, a task that stops
    itself), start() lets it carry on; the CIDP states while stopped are 3; from dirty memory and a rerun."""
    prog = build(STOPSTART, 'stopstart')
    want = 'A\r\nruns\r\nstopped\r\nruns again\r\nno wake while stopped\r\nwoke\r\nstarted\r\nB\r\n'
    ok = [(p.title, p.vm) for p in prog.parts] == [('main', 1), ('counter', 2), ('sleeper', 3), ('self', 4)]
    c = boot(prog)
    V.run(c, 400_000)
    ok &= c.M[0x2F35] == scc.STOPPED                          # self() has stopped itself
    r = V.run(c, 30_000_000); out = bytes(c.io_out[3]).decode('latin1')
    ok &= r == 'halt' and out == want and not any(errors(c))
    c2 = boot(prog, dirty=1802); r2 = V.run(c2, 30_000_000)
    ok &= r2 == 'halt' and bytes(c2.io_out[3]).decode('latin1') == want and not any(errors(c2))
    c3 = boot(prog, mem=c.M); r3 = V.run(c3, 30_000_000)  # cold boot again, no reload
    ok &= r3 == 'halt' and bytes(c3.io_out[3]).decode('latin1') == want and not any(errors(c3))
    return report('stopstart', ok, repr(out))


def t_errors():
    ok = True
    for src, want in ERRORS:
        try: scc.compile_program(src, 'e'); got = '(it compiled)'
        except scc.Error as e: got = str(e)
        if want not in got: print('  want %r, got %r' % (want, got)); ok = False
    return report('errors', ok, '')


def t_onevm():
    ok = True
    for f in sorted(glob.glob(os.path.join(HERE, 'examples', '*.sc'))):
        if os.path.basename(f) == 'tasks.sc': continue
        p = scc.compile_program(open(f).read(), os.path.splitext(os.path.basename(f))[0])
        same = p.lst(f) == open(f[:-3] + '.lst').read()
        if not same: print('  %s differs from its .lst' % os.path.basename(f))
        ok &= same
    return report('one-VM', ok, '')


def main():
    ok = True
    for t in (t_tasks, t_race, t_queue, t_painter, t_features, t_stopstart, t_errors, t_onevm): ok &= t()
    print('multitasking:', 'PASS' if ok else 'FAIL')
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
