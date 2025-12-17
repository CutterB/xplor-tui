# xplor-tui

A pure Bash TUI file explorer designed to run in ultra-minimal Linux environments.

## Features
- Scrollable TUI
- Folders-first sorting
- Icons (📁 folders, 📄 files, 🚀 executables)
- File sizes, permissions, modified time
- Folder item counts (pure Bash)
- Per-directory cursor memory
- Wraparound navigation
- Search filter (/)
- Works without: wc, sort, awk, tput, seq, basename

## Usage

```bash
chmod +x xplor.sh
cd "$(./xplor.sh)"

## Running

```sh
./xplor

xplor will automatically select:

bash TUI mode on modern systems

ksh88 (Harris-compatible) mode when ksh is detected

Force a mode:

XPLOR_MODE=tui ./xplor
XPLOR_MODE=harris ./xplor
