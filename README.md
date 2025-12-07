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

