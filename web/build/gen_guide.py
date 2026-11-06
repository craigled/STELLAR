# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build web/stellarc-guide.html from the work repo's SC/GUIDE.md - the Stellar C guide - and put its
examples in web/sc/guide/ (NAME.sc + manifest.json) so each "Try it" link opens one in stellarc.html
(stellarc.html#guide=NAME).

The examples are checked first: SC/guide_check.py compiles and runs every one against the output the
guide shows, and the page is not written if any fails.

    python3 web/build/gen_guide.py [path/to/stellar-1802]
"""
import html, json, os, re, subprocess, sys

WEB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Projects/stellar-1802')
SRC = os.path.join(WORK, 'SC', 'GUIDE.md')
OUT = os.path.join(WEB, 'stellarc-guide.html')
EXDIR = os.path.join(WEB, 'sc', 'guide')


def version():
    m = re.search(r'\?v=(\d+)', open(os.path.join(WEB, 'stellarc.html')).read())
    return m.group(1)


def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r'`([^`]+)`', lambda m: '<code>%s</code>' % m.group(1), t)
    t = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', t)
    t = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', t)
    return t


def slug(t): return re.sub(r'[^a-z0-9]+', '-', re.sub(r'`', '', t.lower())).strip('-')


def render(md):
    out, toc, lines, i = [], [], md.split('\n'), 0
    def para(buf):
        if buf: out.append('<p>%s</p>' % inline(' '.join(x.strip() for x in buf)))
    buf = []
    while i < len(lines):
        l = lines[i]
        if l.startswith('```'):
            para(buf); buf = []
            info = l[3:].strip(); body = []
            i += 1
            while not lines[i].startswith('```'): body.append(lines[i]); i += 1
            code = html.escape('\n'.join(body))
            m = re.match(r'c\s+(example|error)=(\S+)', info)
            if m and m.group(1) == 'example':
                out.append('<div class="g-ex"><div class="g-exh"><span class="mono">%s.sc</span>'
                           '<a class="g-try" href="stellarc.html#guide=%s">Try it &rarr;</a></div><pre><code>%s</code></pre></div>'
                           % (m.group(2), m.group(2), code))
            elif m:
                out.append('<div class="g-ex"><div class="g-exh"><span class="mono">%s.sc</span>'
                           '<span class="g-lbl">does not compile</span></div><pre><code>%s</code></pre></div>' % (m.group(2), code))
            elif info in ('output', 'screen', 'error'):
                lbl = {'output': 'Output', 'screen': 'The screen', 'error': 'The compiler says'}[info]
                out.append('<div class="g-out g-%s"><div class="g-lbl">%s</div><pre>%s</pre></div>' % (info, lbl, code))
            else:
                out.append('<pre><code>%s</code></pre>' % code)
            i += 1; continue
        if l.startswith('#'):
            para(buf); buf = []
            n = len(l) - len(l.lstrip('#')); text = l[n:].strip()
            if n == 1: out.append('<h1>%s</h1>' % inline(text))
            else:
                sid = slug(text)
                if n == 2: toc.append((sid, text))
                out.append('<h%d id="%s">%s</h%d>' % (n, sid, inline(text), n))
            i += 1; continue
        if l.strip() == '---':
            para(buf); buf = []; out.append('<hr>'); i += 1; continue
        if l.startswith('|'):
            para(buf); buf = []
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not all(re.match(r'^-+$', c) for c in cells): rows.append(cells)
                i += 1
            t = '<div class="g-table"><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>' % (
                ''.join('<th>%s</th>' % inline(c) for c in rows[0]),
                ''.join('<tr>%s</tr>' % ''.join('<td>%s</td>' % inline(c) for c in r) for r in rows[1:]))
            out.append(t); continue
        m = re.match(r'^(\*|\d+\.)\s+(.*)$', l)
        if m:
            para(buf); buf = []
            tag = 'ol' if m.group(1)[0].isdigit() else 'ul'
            items = []
            while i < len(lines):
                m = re.match(r'^(\*|\d+\.)\s+(.*)$', lines[i])
                if m: items.append([m.group(2)]); i += 1; continue
                if lines[i].startswith('  ') and lines[i].strip() and items: items[-1].append(lines[i].strip()); i += 1; continue
                break
            out.append('<%s>%s</%s>' % (tag, ''.join('<li>%s</li>' % inline(' '.join(it)) for it in items), tag))
            continue
        if not l.strip(): para(buf); buf = []; i += 1; continue
        buf.append(l); i += 1
    para(buf)
    return '\n'.join(out), toc


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Stellar C guide</title>
<meta name="description" content="Programming in Stellar C: the language taught step by step, from the first line to a finished game - every example checked by compiling and running it.">
<link rel="stylesheet" href="css/site.css?v={V}">
<style>
.guide{{max-width:82ch}}
.guide h2{{margin-top:2.2em; border-top:1px solid var(--line); padding-top:.9em}}
.guide hr{{display:none}}
.guide pre{{margin:.4em 0 1em; padding:12px 14px; overflow-x:auto; font-size:13px; line-height:1.45}}
.guide li{{margin:.25em 0}}
.g-ex .g-exh{{display:flex; justify-content:space-between; align-items:baseline; font-size:12.5px; color:var(--ink-soft); margin-top:1.2em}}
.g-ex pre{{margin-top:.25em}}
.g-try{{font-family:var(--mono); font-size:12.5px}}
.g-out .g-lbl,.g-exh .g-lbl{{font-family:var(--mono); font-size:11px; letter-spacing:.12em; text-transform:uppercase; color:var(--accent)}}
.g-out pre{{background:var(--bg-sunk); color:var(--ink); border:1px solid var(--line)}}
.g-screen pre{{background:var(--code-bg); color:var(--code-ink)}}
.g-table{{overflow-x:auto}}
.g-table table{{border-collapse:collapse; font-size:14px; margin:.6em 0 1.2em}}
.g-table th,.g-table td{{border:1px solid var(--line); padding:5px 9px; text-align:left; vertical-align:top}}
.g-toc{{columns:2; font-size:14.5px; margin:1em 0 2em; padding-left:1.2em}}
@media(max-width:700px){{.g-toc{{columns:1}}}}
</style>
</head>
<body>
<main class="wrap guide">
  <div class="tag" style="font-family:var(--mono);color:var(--accent);letter-spacing:.18em;font-size:12px;text-transform:uppercase">Language &middot; guide</div>
  {BODY_H1}
  <p class="muted">The compiler and its examples are on the <a href="stellarc.html">Stellar C page</a>; each <b>Try it</b> link below opens an example there, ready to compile and run.</p>
  <ol class="g-toc">{TOC}</ol>
  {BODY}
</main>
<footer class="foot">STELLAR for the RCA COSMAC 1802 &middot; <a href="stellarc.html">Stellar C</a> &middot; <a href="index.html">home</a></footer>
<script src="js/nav.js?v={V}"></script>
</body>
</html>
"""


def main():
    r = subprocess.run([sys.executable, '-W', 'ignore', os.path.join(WORK, 'SC', 'guide_check.py'), '--write', EXDIR],
                       capture_output=True, text=True, cwd=os.path.join(WORK, 'SC'))
    last = r.stdout.strip().split('\n')[-1]
    if 'ALL OK' not in last: raise SystemExit('guide examples FAIL - not writing the page:\n' + r.stdout[-2000:])
    body, toc = render(open(SRC).read())
    h1 = re.search(r'<h1>.*?</h1>', body).group(0)
    body = body.replace(h1, '', 1)
    tocs = ''.join('<li><a href="#%s">%s</a></li>' % (sid, inline(re.sub(r'^\d+\.\s*', '', t))) for sid, t in toc
                   if not t.lower().startswith('quick'))
    v = version()
    open(OUT, 'w').write(PAGE.format(V=v, BODY_H1=h1, TOC=tocs, BODY=body))
    n = len(json.load(open(os.path.join(EXDIR, 'manifest.json'))))
    print('wrote %s (%d sections) and %d examples in web/sc/guide/ - %s' % (OUT, len(toc), n, last))


if __name__ == '__main__':
    main()
