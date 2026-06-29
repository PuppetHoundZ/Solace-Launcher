# Solace Script Launcher — Folder-Watching GUI Launcher for .sh Scripts

Installs a GTK3 touch GUI that scans one folder for `*.sh` files, lists them as tappable cards, and runs the chosen one in a real terminal window. 

`chmod +x` is applied to a script only at the moment you tap Run — never to the whole folder. Nothing is written outside `~/.local` or `~/.config`.

## Features
* Terminal menu installs, repairs, or uninstalls the launcher.
* GTK3 Python GUI shows each script as a card with its name, description, version, and status parsed from the script's own header comments.
* Fallback label handling for scripts without standard headers.
* Built-in single-instance guard (second launch exits silently if already running).
* Dedicated Manager button to open/close the utility via the terminal menu.
* Dual toggle sorting controls: Name (A→Z / Z→A) and Date (Newest / Oldest).
* Crash recovery and rollback protection during installation/repairs.

## Key Paths
* `~/.local/bin/solace-script-launcher` — GTK3 GUI script
* `~/.config/script-launcher/scripts_dir` — Saved watched folder pointer
* `~/.local/share/applications/solace-script-launcher.desktop` — Desktop shortcut
* `~/.local/share/icons/hicolor/scalable/apps/solace-script-launcher.svg` — Application icon
* `~/.local/share/script-launcher-manager/` — Rollback state and backup infrastructure

> **Note:** The default watched folder is `~/Documents/RasPiSH Projects`.

## Terminal Launch Fallback Chain
When executing a script, the launcher searches for available terminal emulators in the following order:
1. `foot`
2. `xfce4-terminal`
3. `lxterminal` (Raspberry Pi OS Trixie default)
4. `x-terminal-emulator`

Each script executes as `cd <folder> && bash <script>` so that relative paths resolve correctly against the watched folder, and pauses on completion so output is not lost.

## Usage

Do **NOT** run this script as root.

```bash
chmod +x script-launcher-manager.sh
./script-launcher-manager.sh
