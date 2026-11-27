# Card sync: a copy of the LTOS card on your computer

`tools/cardsync.py` keeps a folder on your Mac (or PC) as a mirror of every file and folder on an LTOS card: the CF
card in the Elf2K, or the card Emma 02 uses. Run it whenever you want the mirror brought up to date. Only what changed
is copied.

## Where the mirrors are

On the Mac (in your home folder: Finder, Go > Home):

| Card | Mirror folder |
|---|---|
| The Elf2K's CF card | `~/Elf2K-mirror` |
| The Emma launcher's card (`~/Library/Application Support/LTOS-Emma02/Emma 02/Elf2K/ltos-card.ide`) | `~/Elf2K-mirror-emma` |
| Your Emma folder's card (`~/Emma 02/Elf2K/ltos-card.ide`) | `~/Elf2K-mirror-emma-home` |

On a PC (in your user folder):

| Card | Mirror folder |
|---|---|
| The Elf2K's CF card | `C:\Users\<you>\Elf2K-mirror` |
| An Emma card given with `--emma PATH\ltos-card.ide` | `C:\Users\<you>\Elf2K-mirror-emma-ltos-card` |

Any other folder can be given at the end of the command instead. Each mirror has a hidden `.cardsync` folder: the
record of each file, and `set-aside`, where files that went from the card are kept (never deleted).

## On the Mac

Bring the Elf2K mirror up to date (the Elf2K on, the serial port free; LTOS is started if it is at `>>>`):

    python3 ~/Projects/stellar-1802/tools/cardsync.py

Bring the Emma mirrors up to date (close Emma 02 first):

    python3 ~/Projects/stellar-1802/tools/cardsync.py --emma
    python3 ~/Projects/stellar-1802/tools/cardsync.py --emma home

Send files you edited or added in a mirror back to the card (it lists them and asks first):

    python3 ~/Projects/stellar-1802/tools/cardsync.py push
    python3 ~/Projects/stellar-1802/tools/cardsync.py push --emma

See what a sync would do, without copying anything:

    python3 ~/Projects/stellar-1802/tools/cardsync.py status

## On a Windows PC

Once: install Python from python.org, copy the `stellar-1802` folder over (or clone it), then

    py -m pip install pyserial

Then, in the `stellar-1802` folder:

    py tools\cardsync.py --port COM3                     the Elf2K (the COM port the USB serial cable is on)
    py tools\cardsync.py --emma C:\path\to\ltos-card.ide  an Emma card (Emma 02 closed)
    py tools\cardsync.py push --port COM3                 your edits back to the Elf2K

Without `--port` it uses the one USB serial port there is; with more than one it lists them.

## Good to know

- The card is the master. A sync copies a file when its size or date on the card has changed.
- A file deleted from the card is moved out of the mirror into `.cardsync/set-aside/<date-time>/`.
- A file you edit in the mirror stays as you left it until you `push` it. If the card's copy changes first, the
  card's copy wins and yours goes to `set-aside`.
- Deleting a file in the mirror does not delete it on the card; the next sync brings it back. Delete it on the
  Elf2K with DELETE.
- Names sent to the card must be 8.3 (e.g. `NOTES.TXT`); lower case is turned into capitals.
- Times: the first Elf2K sync of the 512 MB card took 12 minutes (137 files); a sync with nothing changed takes about
  30 seconds. Emma syncs take under a second.
- Other options: `-n` (say what would happen, do nothing), `--full` (copy every file again), `--yes` (push without
  asking), `--force` (use a mirror made from another card).
