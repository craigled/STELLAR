# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""run_tests.py - every verifier at once: build once (build.prebuild), then each verify_NAME.py in its own process
with LTOS_PREBUILT=1, as many at a time as there are cores, each stopped after --limit minutes. A summary at the
end; each one's output in out/tests/NAME.txt.

    python3 LTOS/run_tests.py                    all of them
    python3 LTOS/run_tests.py redir tools        just these
    python3 LTOS/run_tests.py --limit 10 ...     (minutes each; 30 if not said)
"""
import os, sys, time, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ALL = ['diskinfo', 'phase1', 'phase2', 'phase3', 'phase4', 'phase5', 'lw2io', 'lw3', 'enano', 'dir', 'help', 'hex', 'cfprogs', 'tools', 'rawk', 'eroff', 'uniqsort',
       'update', 'recv', 'xfer', 'edit', 'redir', 'cards', 'sh', 'sh3', 'sh4', 'input', 'trash', 'running', 'memverse', 'hide', 'ltcalc', 'sed', 'sysrx']
OWNBUILD = ('update',)


def main():
    args = sys.argv[1:]
    limit = 30
    if '--limit' in args:
        i = args.index('--limit'); limit = float(args[i + 1]); del args[i:i + 2]
    names = args or ALL
    t0 = time.time()
    r = subprocess.run([sys.executable, '-c', 'import build, sys; bad = build.lint_load_d(); '
                        'assert not bad, bad; build.prebuild()'], cwd=HERE, capture_output=True, text=True)
    if r.returncode:
        print(r.stdout + r.stderr); print('the build failed'); return False
    print(r.stdout.strip())
    od = os.path.join(HERE, 'out', 'tests'); os.makedirs(od, exist_ok=True)
    env = dict(os.environ, LTOS_PREBUILT='1')
    todo = list(names); run = {}; res = {}
    cores = os.cpu_count() or 4
    while todo or run:
        while todo and len(run) < cores:
            n = todo.pop(0)
            f = open(os.path.join(od, n + '.txt'), 'w')
            ev = env if n not in OWNBUILD else os.environ        # (update builds kernels of its own, in copies)
            run[n] = (subprocess.Popen([sys.executable, 'verify_%s.py' % n], cwd=HERE, env=ev, stdout=f,
                                       stderr=subprocess.STDOUT), f, time.time())
        time.sleep(2)
        for n, (p, f, ts) in list(run.items()):
            if p.poll() is None and time.time() - ts > limit * 60:
                p.kill(); p.wait(); res[n] = 'TIMED OUT (%g min)' % limit
            if p.poll() is not None:
                f.close(); del run[n]
                res.setdefault(n, 'ALL PASS' if p.returncode == 0 else 'FAIL')
                print('%-8s %-22s %4.0f s' % (n, res[n], time.time() - ts), flush=True)
    print()
    for n in names:
        if res[n] != 'ALL PASS':
            lines = open(os.path.join(od, n + '.txt')).read().splitlines()
            bad = [l for l in lines if 'FAIL' in l or 'Error' in l or 'Traceback' in l or l.startswith('    ')]
            print('-- %s: %s' % (n, res[n])); [print('   ' + l[:160]) for l in bad[:8]]
    ok = all(v == 'ALL PASS' for v in res.values())
    print('\n%d of %d pass, %.0f minutes' % (sum(v == 'ALL PASS' for v in res.values()), len(names), (time.time() - t0) / 60))
    return ok


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
