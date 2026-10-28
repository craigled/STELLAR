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

## The LTOS page

`ltos.html` boots LTOS 0.5 from a CF card image (`ltos/ltos-card.bin`) on an emulated Elf2K (`js/elf2k.js`),
with a stand-in BIOS of our own (`js/webbios.js`, from `LTOS/webbios.asm` in stellar-1802) instead of the
Elf2K ROM. Changes to the card are kept in the browser (IndexedDB); **Restore the card** puts every file back.

After a change to LTOS, an app or the demo files, on the Mac:

```
python3 web/build/gen_ltos.py      # the card and webbios.js (about a minute)
python3 web/build/ltos_ref.py      # the reference session from that card
node web/build/test_ltos.mjs       # the page's machine must print exactly the same
```

Bump `V` in `js/ltos-page.js` with the `?v=` so browsers fetch the new card. Changes saved in a browser are kept under the card's fingerprint, so a new card starts clean.
