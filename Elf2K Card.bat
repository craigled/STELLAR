@echo off
rem Copyright (C) 2026 Craig Ledbetter
rem SPDX-License-Identifier: GPL-3.0-or-later
rem Double-click: the Elf2K card tool (format, install, update, back up, check the CF card in the Elf2K).
rem Needs Python 3 (python.org) and pyserial (py -m pip install pyserial). Another serial port: add --port COM4
cd /d "%~dp0"
set PY=py -3
where py >nul 2>nul || set PY=python
%PY% -c "import serial" 2>nul || (
  echo The serial port needs pyserial. Installing it now ...
  %PY% -m pip install --user pyserial
)
%PY% tools\elf2k_card.py %*
echo.
pause
