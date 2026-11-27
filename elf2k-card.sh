#!/bin/sh
# Copyright (C) 2026 Craig Ledbetter
# SPDX-License-Identifier: GPL-3.0-or-later
# The Elf2K card tool on Linux (or a Mac from a terminal):  ./elf2k-card.sh  [--port /dev/ttyUSB0]
# Your user must be allowed to use the serial port (on most Linux: the dialout group).
cd "$(dirname "$0")" || exit 1
exec python3 tools/elf2k_card.py "$@"
