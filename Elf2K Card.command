#!/bin/bash
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
# Double-click: the Elf2K card tool in Terminal (format, install, update, back up, check the CF card in the Elf2K).
# It runs the tool in this project - so it can be copied to the Desktop or kept in the Dock.
DIR="$HOME/Projects/stellar-1802"
[ -f "$(dirname "$0")/tools/elf2k_card.py" ] && DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1
python3 tools/elf2k_card.py "$@"
echo
read -n 1 -s -r -p "Press any key to close this window."
