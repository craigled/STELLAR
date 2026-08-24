# Running the STELLAR web pages

**Serve it from the repository root, and check which directory your shell is in
first.** `--directory web` is relative to wherever you are, so running the command from
somewhere else quietly serves the wrong tree — you get a directory listing, a 404, or
an old copy of the site, all of which look like "the web project is broken".

```
cd ~/Projects/STELLAR
python3 -m http.server 8787 --directory web
```

then open <http://localhost:8787/simulator.html>. If the page does not appear at all,
`pwd` before blaming the code.

The pages also **must be served over http rather than opened from Finder**: they fetch
their sample programs, and a browser blocks those fetches on a `file://` URL, leaving
the dropdown empty and nothing able to run.

## After pulling a change

Asset URLs carry a `?v=` number so browsers pick up new files. The **page HTML itself**
is not versioned, so the first load after a pull needs a forced reload — **Cmd-Shift-R**
— to fetch HTML that points at the new `?v=`. Ordinary reloads are fine after that.

## Running the full-screen programs

Starfield, Bouncing Ball, Invaders, Starship and Game of Life drive the terminal with
VT100 escape sequences.

* Pick one of the `(VT100)` entries in the dropdown and press **Load**.
* **Set the speed slider to `turbo`.** The default is `4x`, which is one STELLAR opcode
  every 120 ms — a full-screen program looks like it is doing nothing at all.
* Press **Run**.
* For **Invaders**, click the terminal first so it takes keys, then steer with the left
  and right arrows and fire with the space bar.
* **Starship** is the quickest check that everything works: it paints the COSMAC ELF
  logo and stops. If you see that, the emulator, the firmware and the VT100 are all fine.
