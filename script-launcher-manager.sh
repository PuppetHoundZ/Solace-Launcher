#!/usr/bin/env bash
# ==============================================================================
# script-launcher-manager.sh
# Solace Script Launcher — Folder-Watching GUI Launcher for .sh Scripts
# Version: 1.6.1
# Status: 🟢 GOLD (Production-Ready)
# Last updated: 2026-06-22
#
# Installs a GTK3 touch GUI that scans one folder for *.sh files, lists them
# as tappable cards, and runs the chosen one in a real terminal window.
# chmod +x is applied to a script only at the moment you tap Run — never to
# the whole folder. Nothing is written outside ~/.local / ~/.config.
#
# Usage: bash script-launcher-manager.sh   (do NOT run as root)
# ==============================================================================
#
# AI REFERENCE NOTES
# ──────────────────────────────────────────────────────────────────────────
#
# WHAT THIS SCRIPT DOES:
#   Terminal menu installs/repairs/uninstalls the "Solace Script Launcher"
#   GTK3 Python GUI. The GUI scans a configurable folder for *.sh files,
#   shows each as a card (name + description/version/status parsed from the
#   script's own header comments), and runs the chosen one in a terminal.
#
# KEY PATHS:
#   ~/.local/bin/solace-script-launcher                 # GTK3 GUI script
#   ~/.config/script-launcher/scripts_dir               # saved watched folder
#   ~/.local/share/applications/solace-script-launcher.desktop
#   ~/.local/share/icons/hicolor/scalable/apps/solace-script-launcher.svg
#   ~/.local/share/script-launcher-manager/             # rollback state dir +
#                                                        # permanent self-copy of this .sh
#   Default watched folder: ~/Documents/RasPiSH Projects
#
# SELF-COPY MECHANISM (Manager button):
#   This .sh mirrors its own content into STATE_DIR/script-launcher-manager.sh
#   on every run. The GUI's Manager button always launches that fixed copy,
#   so it works regardless of where the live file is moved to afterward
#   (including inside the watched folder itself). Only goes stale between
#   saving a new version and running it once from the new location.
#
# TERMINAL LAUNCH FALLBACK CHAIN:
#   foot → xfce4-terminal → lxterminal → x-terminal-emulator
#   lxterminal is the Pi OS Trixie default. foot tried first as a courtesy
#   only. Each script runs as: cd <folder> && bash <script>; then pauses
#   on "Press Enter to close" so output is never lost.
#   Ref: https://docs.xfce.org/apps/xfce4-terminal/command-line
#   Ref: https://manpages.debian.org/stretch/xfce4-terminal/x-terminal-emulator.1.en.html
#
# HEADER PARSING:
#   First ~15 lines of each .sh are scanned for # comment lines. Pulls the
#   first meaningful description line plus "# Version:" and "# Status:" if
#   present — matching the header convention used across all manager scripts.
#   Scripts without this convention still list fine with a fallback label.
#
# SORT CONTROLS:
#   Two toggle buttons in the GUI: Name (A→Z / Z→A) and Date (Newest /
#   Oldest). Default on open is Newest first. Sort state is in-session only.
#
# UNINSTALL:
#   Removes GUI script, desktop shortcut, icon. Never touches anything
#   inside the watched scripts folder. python3-gi/gir1.2-gtk-3.0 are kept
#   (shared GTK3 dependency). Folder preference optionally cleared on request.
#
# LEGACY FILE CLEANUP:
#   _migrate_legacy_names() removes pre-v1.4.0 "script-launcher"-named files
#   at the start of every Install/Repair to avoid stale duplicates.
#   uninstall_gui() also checks both old and new names directly.
#
# CRASH RECOVERY / ROLLBACK:
#   install.partial marker + pre-op backups in STATE_DIR. If install/repair
#   dies mid-way, the next run auto-restores from backup. ERR trap captures
#   $BASH_COMMAND and $LINENO so failures always print what failed and where
#   before rolling back. set -Eeuo pipefail (capital E) ensures ERR fires
#   reliably from inside nested helper functions.
#
# VERSION HISTORY:
#   v1.6.1 (2026-06-22) — Default sort changed to Newest first (date_desc).
#   v1.6.0 (2026-06-22) — Added sort controls row: Name (A→Z/Z→A) and Date
#     (Newest/Oldest) toggle buttons. Active button highlighted cyan. Sort
#     applied in _refresh(); mtime added to _scan_scripts() result dicts.
#   v1.5.1 (2026-06-20) — Fixed broken icon: desktop entry Icon= field was
#     still "script-launcher" after v1.4.0 renamed the file to
#     "solace-script-launcher". Run Install/Repair to regenerate shortcut.
#   v1.5.0 (2026-06-20) — Marked GOLD. Confirmed on real Pi 4 / Pi OS Trixie.
#   v1.4.2 (2026-06-20) — Self-copy mechanism for Manager button: mirrors
#     this .sh into STATE_DIR on every run. GUI always launches that fixed
#     copy. Replaced v1.4.1's manager_path pointer-file approach.
#   v1.4.0 (2026-06-20) — Renamed to "Solace Script Launcher". GUI files
#     renamed to solace-script-launcher.*. _migrate_legacy_names() cleans
#     up old script-launcher.* files on Repair. Config/state dir names kept
#     as-is (internal, not user-facing — renaming would risk resetting the
#     saved folder preference).
#   v1.3.0 (2026-06-20) — Default watched folder changed to
#     ~/Documents/RasPiSH Projects. Existing installs with a saved config
#     are unaffected; use option 4 to update an existing folder pointer.
#   v1.2.0 (2026-06-20) — ERR trap now captures $BASH_COMMAND/$LINENO;
#     _rollback_cleanup() prints the failed command before rolling back.
#     draw_menu() fixed: dropped fixed-width box (path overflow), replaced
#     printf %s with echo -e for color codes in status lines.
#   v1.1.0 (2026-06-19) — Run action uses cd <folder> && bash <script> so
#     relative paths in any script resolve against the watched folder, not
#     whatever directory the terminal happened to open in.
#   v1.0.0 (2026-06-19) — Initial release.
#
# REFERENCES:
#   xfce4-terminal flags   : https://docs.xfce.org/apps/xfce4-terminal/command-line
#   x-terminal-emulator    : https://manpages.debian.org/stretch/xfce4-terminal/x-terminal-emulator.1.en.html
#   Desktop Entry spec     : https://specifications.freedesktop.org/desktop-entry-spec/latest/
#   Pi OS software sources : https://www.raspberrypi.com/documentation/computers/software-sources.html
#
# ==============================================================================

set -Eeuo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ──────────────────────────────────────────────────────────────────────────────
SCRIPT_VERSION="1.6.1"

CONFIG_DIR="${HOME}/.config/script-launcher"
CONFIG_FILE="${CONFIG_DIR}/scripts_dir"
DEFAULT_SCRIPTS_DIR="${HOME}/Documents/RasPiSH Projects"

GUI_SCRIPT="${HOME}/.local/bin/solace-script-launcher"
GUI_ICON_DIR="${HOME}/.local/share/icons/hicolor/scalable/apps"
GUI_ICON="${GUI_ICON_DIR}/solace-script-launcher.svg"
GUI_DESKTOP_DIR="${HOME}/.local/share/applications"
GUI_DESKTOP="${GUI_DESKTOP_DIR}/solace-script-launcher.desktop"

# Legacy paths from before the v1.4.0 rename to "Solace Script Launcher" —
# only kept around so install/uninstall can clean up old-named leftovers
# from a prior version without orphaning them.
LEGACY_GUI_SCRIPT="${HOME}/.local/bin/script-launcher"
LEGACY_GUI_ICON="${GUI_ICON_DIR}/script-launcher.svg"
LEGACY_GUI_DESKTOP="${GUI_DESKTOP_DIR}/script-launcher.desktop"

# ── Rollback / crash-recovery state (same pattern as cava-manager.sh) ────────
STATE_DIR="${HOME}/.local/share/script-launcher-manager"
PARTIAL_MARKER="${STATE_DIR}/install.partial"
BACKUP_GUI_SCRIPT="${STATE_DIR}/script-launcher.backup"
BACKUP_GUI_ICON="${STATE_DIR}/script-launcher-icon.backup"
BACKUP_GUI_DESKTOP="${STATE_DIR}/script-launcher-desktop.backup"
MANAGER_SELF_COPY="${STATE_DIR}/script-launcher-manager.sh"
mkdir -p "${STATE_DIR}"

# Mirror this .sh file's current content into a fixed, permanent location
# every single run — same idea as the rollback state dir this directory
# already holds. The GUI's "Manager" button always launches THIS copy
# instead of trying to track wherever the live file currently is, so it
# keeps working no matter where you move script-launcher-manager.sh to
# afterward (including right inside your watched scripts folder). The copy
# only goes stale between the moment you save an updated version and the
# next time you actually run it from its new location — same as any other
# script here.
_SELF_REAL_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"
if [[ "${_SELF_REAL_PATH}" != "${MANAGER_SELF_COPY}" ]]; then
    cp -f "${_SELF_REAL_PATH}" "${MANAGER_SELF_COPY}" 2>/dev/null || true
fi

_ROLLBACK_OP=""

# ──────────────────────────────────────────────────────────────────────────────
# COLOURS & LOGGING
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() {
    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $*${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
}

press_enter() { echo ""; read -rp "  Press [Enter] to continue…"; }

confirm() {
    local prompt="${1:-Are you sure?} [y/N] "
    local response=""
    read -r -p "$prompt" response
    [[ "$response" =~ ^[Yy]$ ]]
}

refuse_root() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "\n${RED}[ERROR]${NC} Do not run this script as root."
        echo -e "        Run it as your normal user:  ${BOLD}bash $0${NC}\n"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# ROLLBACK / CRASH RECOVERY (mirrors cava-manager.sh's proven pattern)
# ──────────────────────────────────────────────────────────────────────────────
_rollback_cleanup() {
    local exit_code="${1:-0}"
    local op="$_ROLLBACK_OP"

    if [[ -f "$PARTIAL_MARKER" && "$exit_code" -ne 0 ]]; then
        echo ""
        log_error "Failed command (exit $exit_code), line ${_FAILED_LINE:-?}: ${_FAILED_COMMAND:-unknown}"
        log_warn "Operation '${op}' did not complete — rolling back changes…"

        if [[ -f "$BACKUP_GUI_SCRIPT" ]]; then
            cp -f "$BACKUP_GUI_SCRIPT" "$GUI_SCRIPT"
            log_info "Restored: $GUI_SCRIPT"
            rm -f "$BACKUP_GUI_SCRIPT"
        elif [[ "$op" == "install" && -f "$GUI_SCRIPT" ]]; then
            rm -f "$GUI_SCRIPT"
            log_info "Removed partial GUI script."
        fi

        if [[ -f "$BACKUP_GUI_ICON" ]]; then
            cp -f "$BACKUP_GUI_ICON" "$GUI_ICON"
            log_info "Restored: $GUI_ICON"
            rm -f "$BACKUP_GUI_ICON"
        elif [[ "$op" == "install" && -f "$GUI_ICON" ]]; then
            rm -f "$GUI_ICON"
            log_info "Removed partial icon."
        fi

        if [[ -f "$BACKUP_GUI_DESKTOP" ]]; then
            cp -f "$BACKUP_GUI_DESKTOP" "$GUI_DESKTOP"
            log_info "Restored: $GUI_DESKTOP"
            rm -f "$BACKUP_GUI_DESKTOP"
        elif [[ "$op" == "install" && -f "$GUI_DESKTOP" ]]; then
            rm -f "$GUI_DESKTOP"
            log_info "Removed partial desktop shortcut."
        fi

        rm -f "$PARTIAL_MARKER"
        echo ""
        log_warn "Rollback complete. Your system is back to its previous state."
        log_warn "Fix the issue above, then run Install / Repair again."
    elif [[ -f "$PARTIAL_MARKER" && "$exit_code" -eq 0 ]]; then
        rm -f "$PARTIAL_MARKER" "$BACKUP_GUI_SCRIPT" "$BACKUP_GUI_ICON" "$BACKUP_GUI_DESKTOP"
    fi
}

_EXIT_CODE=0
_FAILED_COMMAND=""
_FAILED_LINE=""
trap '_EXIT_CODE=$?; _FAILED_COMMAND="$BASH_COMMAND"; _FAILED_LINE="$LINENO"' ERR
trap '_rollback_cleanup "$_EXIT_CODE"' EXIT
trap 'echo ""; log_warn "Interrupted."; exit 130' INT TERM HUP

_rollback_begin() {
    _ROLLBACK_OP="$1"
    echo "$1" > "$PARTIAL_MARKER"
    # NOTE: written as if/fi, not `[[ -f X ]] && cp ...`. The && form being
    # the LAST statement in a function is a real set -e trap: when the guard
    # is false (the normal case on a fresh install, since none of these
    # files exist yet) the function itself returns non-zero, and that
    # propagates out as a genuine failure even though nothing actually went
    # wrong. This is exactly what caused install to abort instantly on a
    # clean Pi with no prior install. if/fi always returns 0 when its
    # condition is false, so it can safely be the last thing a function does.
    if [[ -f "$GUI_SCRIPT" ]]; then
        cp -f "$GUI_SCRIPT" "$BACKUP_GUI_SCRIPT"
    fi
    if [[ -f "$GUI_ICON" ]]; then
        cp -f "$GUI_ICON" "$BACKUP_GUI_ICON"
    fi
    if [[ -f "$GUI_DESKTOP" ]]; then
        cp -f "$GUI_DESKTOP" "$BACKUP_GUI_DESKTOP"
    fi
}

_rollback_end() {
    _ROLLBACK_OP=""
    rm -f "$PARTIAL_MARKER" "$BACKUP_GUI_SCRIPT" "$BACKUP_GUI_ICON" "$BACKUP_GUI_DESKTOP"
}

_check_partial_state() {
    [[ -f "$PARTIAL_MARKER" ]] || return 0
    local op
    op="$(cat "$PARTIAL_MARKER")"
    echo ""
    log_warn "Previous '${op}' did not complete (power loss or crash?) — auto-restoring…"

    if [[ -f "$BACKUP_GUI_SCRIPT" ]]; then
        cp -f "$BACKUP_GUI_SCRIPT" "$GUI_SCRIPT" && log_info "Restored: $GUI_SCRIPT"
        rm -f "$BACKUP_GUI_SCRIPT"
    else
        [[ -f "$GUI_SCRIPT" ]] && rm -f "$GUI_SCRIPT" && log_info "Removed incomplete GUI script."
    fi
    if [[ -f "$BACKUP_GUI_ICON" ]]; then
        cp -f "$BACKUP_GUI_ICON" "$GUI_ICON" && log_info "Restored: $GUI_ICON"
        rm -f "$BACKUP_GUI_ICON"
    else
        [[ -f "$GUI_ICON" ]] && rm -f "$GUI_ICON" && log_info "Removed incomplete icon."
    fi
    if [[ -f "$BACKUP_GUI_DESKTOP" ]]; then
        cp -f "$BACKUP_GUI_DESKTOP" "$GUI_DESKTOP" && log_info "Restored: $GUI_DESKTOP"
        rm -f "$BACKUP_GUI_DESKTOP"
    else
        [[ -f "$GUI_DESKTOP" ]] && rm -f "$GUI_DESKTOP" && log_info "Removed incomplete desktop shortcut."
    fi

    rm -f "$PARTIAL_MARKER"
    echo ""
    log_ok "Auto-restore complete."
    press_enter
}

# ──────────────────────────────────────────────────────────────────────────────
# CONFIG (watched scripts folder)
# ──────────────────────────────────────────────────────────────────────────────
get_scripts_dir() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local saved=""
        saved="$(cat "$CONFIG_FILE")"
        if [[ -n "$saved" ]]; then
            echo "$saved"
            return 0
        fi
    fi
    echo "$DEFAULT_SCRIPTS_DIR"
}

set_scripts_dir() {
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$1" > "$CONFIG_FILE"
}

count_scripts() {
    local dir="$1" count=0
    [[ -d "$dir" ]] || { echo 0; return; }
    for f in "$dir"/*.sh; do
        [[ -e "$f" ]] && count=$((count + 1))
    done
    echo "$count"
}

# ──────────────────────────────────────────────────────────────────────────────
# GUI DEPENDENCIES
# ──────────────────────────────────────────────────────────────────────────────
install_gui_deps() {
    log_info "Checking GTK3 Python dependencies…"
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends \
        python3-gi \
        python3-gi-cairo \
        gir1.2-gtk-3.0
    log_ok "GTK3 Python dependencies ready."
}

# ──────────────────────────────────────────────────────────────────────────────
# GUI ICON (SVG)
# ──────────────────────────────────────────────────────────────────────────────
write_gui_icon() {
    mkdir -p "${GUI_ICON_DIR}"
    cat > "${GUI_ICON}" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect width="100" height="100" rx="14" fill="#111118"/>
  <rect x="16" y="24" width="68" height="54" rx="8" fill="#191922" stroke="#1ebdd1" stroke-width="3"/>
  <circle cx="27" cy="34" r="2.6" fill="#fabf2f"/>
  <circle cx="36" cy="34" r="2.6" fill="#1ed760"/>
  <circle cx="45" cy="34" r="2.6" fill="#e35454"/>
  <path d="M33 46 L52 58 L33 70 Z" fill="#1ebdd1"/>
</svg>
SVGEOF
    touch "${GUI_ICON_DIR}"
    gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    log_ok "GUI icon written: ${GUI_ICON}"
}

# ──────────────────────────────────────────────────────────────────────────────
# GUI DESKTOP ENTRY
# ──────────────────────────────────────────────────────────────────────────────
write_gui_desktop() {
    mkdir -p "${GUI_DESKTOP_DIR}"
    cat > "${GUI_DESKTOP}" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Solace Script Launcher
GenericName=Run Scripts
Comment=Browse and run .sh scripts from your chosen folder
Exec=python3 ${GUI_SCRIPT}
Icon=solace-script-launcher
Terminal=false
Categories=Utility;System;
Keywords=scripts;launcher;terminal;bash;shell;
StartupNotify=false
EOF
    chmod 644 "${GUI_DESKTOP}"
    update-desktop-database "${GUI_DESKTOP_DIR}" 2>/dev/null || true
    log_ok "Desktop shortcut written: ${GUI_DESKTOP}"
}

# ──────────────────────────────────────────────────────────────────────────────
# GUI SCRIPT (Python/GTK3 heredoc)
# NOTE: heredoc uses PYEOF delimiter — single-quoted so bash does NOT expand
# variables inside (the generated script itself uses $? and $1-style shell
# syntax in the commands it launches, which must stay literal).
# ──────────────────────────────────────────────────────────────────────────────
write_gui_script() {
    mkdir -p "$(dirname "$GUI_SCRIPT")"
    cat > "$GUI_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
# =============================================================================
# solace-script-launcher — Solace Script Launcher GTK3 GUI
# Generated by script-launcher-manager.sh — re-run Install / Repair to update.
#
# Lists *.sh files in a configurable folder and runs the chosen one in a
# terminal window. chmod +x is applied to a script only at the moment you
# run it. Does not modify the scripts themselves, PipeWire, or system config.
# =============================================================================
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gtk, Gdk, GLib, Pango
import glob
import os
import shlex
import subprocess

CONFIG_FILE = os.path.expanduser("~/.config/script-launcher/scripts_dir")
MANAGER_SELF_COPY = os.path.expanduser(
    "~/.local/share/script-launcher-manager/script-launcher-manager.sh")
DEFAULT_DIR = os.path.expanduser("~/Documents/RasPiSH Projects")

# ── Locate the terminal manager script (for the "Manager" button) ───────────
def _find_manager():
    # The manager .sh mirrors its own current content into this fixed
    # location on every run, so there's always a stable, known-good copy to
    # launch here regardless of where the live file currently sits.
    if os.path.isfile(MANAGER_SELF_COPY):
        return MANAGER_SELF_COPY

    # Fallback candidates, only used if the self-copy is missing for some
    # reason (e.g. the state directory was manually deleted).
    candidates = [
        os.path.expanduser("~/script-launcher-manager.sh"),
        os.path.expanduser("~/.local/bin/script-launcher-manager.sh"),
        "/usr/local/bin/script-launcher-manager.sh",
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None

def _read_scripts_dir():
    try:
        with open(CONFIG_FILE, "r") as f:
            p = f.read().strip()
            if p:
                return p
    except (FileNotFoundError, OSError):
        pass
    return DEFAULT_DIR

def _write_scripts_dir(path):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        f.write(path + "\n")

def _parse_header(path):
    """Best-effort pull of a description/version/status from a script's
    leading '#' comment lines. Falls back gracefully for scripts that don't
    follow the AI REFERENCE NOTES header convention."""
    desc, version, status = "", "", ""
    base = os.path.splitext(os.path.basename(path))[0]
    head_lines = []
    try:
        with open(path, "r", errors="ignore") as f:
            for i, ln in enumerate(f):
                if i >= 15:
                    break
                head_lines.append(ln)
    except OSError:
        pass

    for ln in head_lines:
        s = ln.strip()
        if not s.startswith("#"):
            continue
        body = s.lstrip("#").strip()
        if not body or body == base or body.startswith("="):
            continue
        if body.upper().startswith("AI REFERENCE"):
            continue
        low = body.lower()
        if low.startswith("version") and ":" in body:
            version = body.split(":", 1)[1].strip()
            continue
        if low.startswith("status") and ":" in body:
            status = body.split(":", 1)[1].strip()
            continue
        if not desc:
            desc = body

    return desc or "Custom script — no description header found", version, status

def _scan_scripts(folder):
    results = []
    if not os.path.isdir(folder):
        return results
    for path in glob.glob(os.path.join(folder, "*.sh")):
        name = os.path.basename(path)
        desc, version, status = _parse_header(path)
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            mtime = 0
        results.append({"path": path, "name": name, "desc": desc,
                         "version": version, "status": status, "mtime": mtime})
    return results

# ── Color palette — matches the project's dark Solace-style theme ───────────
CSS = b"""
window {
    background-color: #111118;
}
.card2 {
    background-color: #191922;
    border-radius: 10px;
}
.row-title {
    color: #e0e0f0;
    font-weight: bold;
    font-size: 13px;
}
.row-meta {
    color: #6a6a86;
    font-size: 11px;
}
.header-title {
    color: #e0e0f0;
    font-weight: bold;
    font-size: 17px;
}
.header-sub {
    color: #50506a;
    font-size: 11px;
}
.status-msg {
    color: #1ebdd1;
    font-size: 11px;
}
.btn-primary {
    background: #1ebdd1;
    color: #111118;
    border-radius: 9px;
    border: none;
    padding: 4px 12px;
    font-weight: bold;
    font-size: 12px;
}
.btn-primary:hover {
    background: #38d8ef;
}
.btn-secondary {
    background: #20202a;
    color: #c8c8d8;
    border-radius: 9px;
    border: 1px solid #33334a;
    padding: 4px 10px;
    font-size: 12px;
}
.btn-secondary:hover {
    background: #2a2a38;
}
.btn-close {
    background: #1a1a2a;
    color: #fabf2f;
    border-radius: 9px;
    border: 1px solid #fabf2f;
    padding: 4px 12px;
    font-size: 12px;
}
.btn-close:hover {
    background: #2a2418;
}
.btn-sort-active {
    background: #1a2a2e;
    color: #1ebdd1;
    border-radius: 9px;
    border: 1px solid #1ebdd1;
    padding: 4px 10px;
    font-size: 12px;
    font-weight: bold;
}
.btn-sort-active:hover {
    background: #1e3238;
}
list {
    background-color: transparent;
}
listbox row {
    background-color: transparent;
}
"""

class ScriptLauncherWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Solace Script Launcher")
        self.folder = _read_scripts_dir()
        # Sort mode: "name_asc" | "name_desc" | "date_desc" | "date_asc"
        self._sort_mode = "date_desc"
        self.set_default_size(480, 420)
        self.set_size_request(360, 320)
        self.set_resizable(True)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        main_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        main_vbox.set_margin_top(10)
        main_vbox.set_margin_bottom(10)
        main_vbox.set_margin_start(12)
        main_vbox.set_margin_end(12)
        self.add(main_vbox)

        # ── Top bar: title/folder + folder/refresh buttons ──────────────────
        top_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        title_lbl = Gtk.Label(label="Solace Script Launcher", xalign=0)
        title_lbl.get_style_context().add_class("header-title")
        title_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        title_box.pack_start(title_lbl, False, False, 0)
        self._sub_lbl = Gtk.Label(label=self.folder, xalign=0)
        self._sub_lbl.get_style_context().add_class("header-sub")
        self._sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        title_box.pack_start(self._sub_lbl, False, False, 0)
        top_row.pack_start(title_box, True, True, 0)

        folder_btn = Gtk.Button(label="📂 Folder")
        folder_btn.get_style_context().add_class("btn-secondary")
        folder_btn.set_size_request(0, 44)
        folder_btn.connect("clicked", self._on_choose_folder)
        top_row.pack_start(folder_btn, False, False, 0)

        refresh_btn = Gtk.Button(label="⟳ Refresh")
        refresh_btn.get_style_context().add_class("btn-secondary")
        refresh_btn.set_size_request(0, 44)
        refresh_btn.connect("clicked", self._refresh)
        top_row.pack_start(refresh_btn, False, False, 0)

        main_vbox.pack_start(top_row, False, False, 0)

        # ── Sort row: Name A→Z / Z→A  |  Date Newest / Oldest ───────────────
        sort_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        sort_lbl = Gtk.Label(label="Sort:", xalign=0)
        sort_lbl.get_style_context().add_class("header-sub")
        sort_row.pack_start(sort_lbl, False, False, 0)

        self._btn_name = Gtk.Button(label="🔤 A → Z")
        self._btn_name.set_size_request(0, 44)
        self._btn_name.connect("clicked", self._on_sort_name)
        sort_row.pack_start(self._btn_name, False, False, 0)

        self._btn_date = Gtk.Button(label="📅 Newest")
        self._btn_date.set_size_request(0, 44)
        self._btn_date.connect("clicked", self._on_sort_date)
        sort_row.pack_start(self._btn_date, False, False, 0)

        main_vbox.pack_start(sort_row, False, False, 0)
        self._update_sort_buttons()

        # ── Scrollable list of scripts ───────────────────────────────────────
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        self._listbox = Gtk.ListBox()
        self._listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._listbox.set_activate_on_single_click(True)
        self._listbox.connect("row-activated", self._on_row_activated)
        scroller.add(self._listbox)
        main_vbox.pack_start(scroller, True, True, 0)

        # ── Status message (transient) ──────────────────────────────────────
        self._status_lbl = Gtk.Label(label="", xalign=0)
        self._status_lbl.get_style_context().add_class("status-msg")
        main_vbox.pack_start(self._status_lbl, False, False, 0)

        # ── Bottom bar: count + Manager + Close ─────────────────────────────
        bottom_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self._count_lbl = Gtk.Label(label="", xalign=0)
        self._count_lbl.get_style_context().add_class("header-sub")
        self._count_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        bottom_row.pack_start(self._count_lbl, True, True, 0)

        manager_btn = Gtk.Button(label="🖥 Manager")
        manager_btn.get_style_context().add_class("btn-secondary")
        manager_btn.set_size_request(0, 44)
        manager_btn.connect("clicked", self._on_open_manager)
        bottom_row.pack_start(manager_btn, False, False, 0)

        close_btn = Gtk.Button(label="Close")
        close_btn.get_style_context().add_class("btn-close")
        close_btn.set_size_request(0, 44)
        close_btn.connect("clicked", lambda *_: self.close())
        bottom_row.pack_start(close_btn, False, False, 0)

        main_vbox.pack_start(bottom_row, False, False, 0)

        self._refresh()

    # ── Building the list ────────────────────────────────────────────────────
    def _build_row(self, s):
        row = Gtk.ListBoxRow()
        row.script_path = s["path"]
        row.script_name = s["name"]

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.get_style_context().add_class("card2")
        box.set_margin_top(4)
        box.set_margin_bottom(4)
        box.set_margin_start(2)
        box.set_margin_end(2)

        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        inner.set_margin_top(8)
        inner.set_margin_bottom(8)
        inner.set_margin_start(10)
        inner.set_margin_end(10)
        box.pack_start(inner, True, True, 0)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        name_lbl = Gtk.Label(label=s["name"], xalign=0)
        name_lbl.get_style_context().add_class("row-title")
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        info.pack_start(name_lbl, False, False, 0)

        meta_bits = [s["desc"]]
        if s["version"]:
            meta_bits.append("v" + s["version"])
        if s["status"]:
            meta_bits.append(s["status"])
        meta_lbl = Gtk.Label(label="  ·  ".join(meta_bits), xalign=0)
        meta_lbl.get_style_context().add_class("row-meta")
        meta_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        info.pack_start(meta_lbl, False, False, 0)

        inner.pack_start(info, True, True, 0)

        run_btn = Gtk.Button(label="▶ Run")
        run_btn.get_style_context().add_class("btn-primary")
        run_btn.set_size_request(78, 44)
        run_btn.connect("clicked",
                         lambda b, p=s["path"], n=s["name"]: self._run_script(p, n))
        inner.pack_start(run_btn, False, False, 0)

        row.add(box)
        return row

    def _refresh(self, *_):
        for child in self._listbox.get_children():
            self._listbox.remove(child)

        scripts = _scan_scripts(self.folder)

        # Apply active sort
        if self._sort_mode == "name_asc":
            scripts.sort(key=lambda s: s["name"].lower())
        elif self._sort_mode == "name_desc":
            scripts.sort(key=lambda s: s["name"].lower(), reverse=True)
        elif self._sort_mode == "date_desc":
            scripts.sort(key=lambda s: s["mtime"], reverse=True)
        elif self._sort_mode == "date_asc":
            scripts.sort(key=lambda s: s["mtime"])

        if not scripts:
            row = Gtk.ListBoxRow()
            row.set_selectable(False)
            row.set_activatable(False)
            lbl = Gtk.Label(label="No .sh scripts found in this folder yet.")
            lbl.get_style_context().add_class("row-meta")
            lbl.set_margin_top(24)
            lbl.set_margin_bottom(24)
            row.add(lbl)
            self._listbox.add(row)
        else:
            for s in scripts:
                self._listbox.add(self._build_row(s))

        self._listbox.show_all()
        self._sub_lbl.set_text(self.folder)
        self._count_lbl.set_text(f"{len(scripts)} script(s) found")

    # ── Sort controls ─────────────────────────────────────────────────────────
    def _update_sort_buttons(self):
        """Style the active sort button with the highlight class; the inactive
        one reverts to the plain secondary style."""
        name_active = self._sort_mode in ("name_asc", "name_desc")
        date_active = self._sort_mode in ("date_asc", "date_desc")

        for btn, active in ((self._btn_name, name_active),
                             (self._btn_date, date_active)):
            sc = btn.get_style_context()
            if active:
                sc.remove_class("btn-secondary")
                sc.add_class("btn-sort-active")
            else:
                sc.remove_class("btn-sort-active")
                sc.add_class("btn-secondary")

        # Update button labels to show which direction is currently active
        name_labels = {"name_asc": "🔤 A → Z", "name_desc": "🔤 Z → A"}
        date_labels = {"date_desc": "📅 Newest", "date_asc": "📅 Oldest"}
        if self._sort_mode in name_labels:
            self._btn_name.set_label(name_labels[self._sort_mode])
        if self._sort_mode in date_labels:
            self._btn_date.set_label(date_labels[self._sort_mode])

    def _on_sort_name(self, *_):
        """Tap once: switch to Name sort (A→Z). Tap again: flip to Z→A."""
        if self._sort_mode == "name_asc":
            self._sort_mode = "name_desc"
        else:
            self._sort_mode = "name_asc"
        self._update_sort_buttons()
        self._refresh()

    def _on_sort_date(self, *_):
        """Tap once: switch to Date sort (Newest first). Tap again: flip to Oldest."""
        if self._sort_mode == "date_desc":
            self._sort_mode = "date_asc"
        else:
            self._sort_mode = "date_desc"
        self._update_sort_buttons()
        self._refresh()

    # ── Actions ───────────────────────────────────────────────────────────────
    def _on_row_activated(self, listbox, row):
        if hasattr(row, "script_path"):
            self._run_script(row.script_path, row.script_name)

    def _on_choose_folder(self, *_):
        dialog = Gtk.FileChooserDialog(
            title="Choose your scripts folder",
            parent=self,
            action=Gtk.FileChooserAction.SELECT_FOLDER,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN, Gtk.ResponseType.OK,
        )
        if os.path.isdir(self.folder):
            dialog.set_current_folder(self.folder)
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            new_folder = dialog.get_filename()
            self.folder = new_folder
            _write_scripts_dir(new_folder)
            self._refresh()
            self._show_status(f"Folder set to: {new_folder}")
        dialog.destroy()

    def _run_script(self, path, name):
        try:
            subprocess.run(["chmod", "+x", path], check=False)
        except OSError:
            pass

        # Run from the configured/preset scripts folder by default — not
        # wherever the terminal happens to open. Today the scan is
        # non-recursive (self.folder/*.sh only), so this is always the same
        # directory the script actually lives in; it's written as self.folder
        # explicitly (rather than os.path.dirname(path)) so the "home" folder
        # a script runs from is always the one you configured, even if a
        # future version ever scans subfolders too.
        quoted_dir = shlex.quote(self.folder)
        quoted = shlex.quote(path)
        cmd_str = (
            f'cd {quoted_dir} && bash {quoted}; ec=$?; echo; '
            f'if [ "$ec" -ne 0 ]; then echo "Script exited with error code $ec"; fi; '
            f'read -rp "Press Enter to close this window..."'
        )
        terminals = [
            ["foot", "bash", "-c", cmd_str],
            ["xfce4-terminal", "-x", "bash", "-c", cmd_str],
            ["lxterminal", "-e", "bash", "-c", cmd_str],
            ["x-terminal-emulator", "-e", "bash", "-c", cmd_str],
        ]
        for cmd in terminals:
            try:
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self._show_status(f"Launched: {name}")
                return
            except FileNotFoundError:
                continue
        self._show_status("No terminal emulator found — install lxterminal.")

    def _on_open_manager(self, *_):
        mgr = _find_manager()
        if not mgr:
            self._show_status("Manager script not found — re-run install.")
            return
        quoted = shlex.quote(mgr)
        cmd_str = f'bash {quoted}'
        terminals = [
            ["foot", "bash", "-c", cmd_str],
            ["xfce4-terminal", "-x", "bash", "-c", cmd_str],
            ["lxterminal", "-e", "bash", "-c", cmd_str],
            ["x-terminal-emulator", "-e", "bash", "-c", cmd_str],
        ]
        for cmd in terminals:
            try:
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self._show_status("Opened manager in terminal.")
                return
            except FileNotFoundError:
                continue
        self._show_status("No terminal emulator found — install lxterminal.")

    # ── Helpers ───────────────────────────────────────────────────────────────
    def _show_status(self, msg):
        self._status_lbl.set_text(msg)
        GLib.timeout_add_seconds(3, self._clear_status)

    def _clear_status(self):
        if self.get_realized():
            self._status_lbl.set_text("")
        return False


def main():
    win = ScriptLauncherWindow()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$GUI_SCRIPT"
    log_ok "GUI script written: ${GUI_SCRIPT}"
}

# ──────────────────────────────────────────────────────────────────────────────
# UNINSTALL
# ──────────────────────────────────────────────────────────────────────────────
uninstall_gui() {
    local removed=0
    for f in "${GUI_SCRIPT}" "${GUI_ICON}" "${GUI_DESKTOP}" \
             "${LEGACY_GUI_SCRIPT}" "${LEGACY_GUI_ICON}" "${LEGACY_GUI_DESKTOP}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            log_ok "Removed: $f"
            removed=$((removed + 1))
        fi
    done
    [[ $removed -eq 0 ]] && log_info "GUI files not found — already removed."
    update-desktop-database "${GUI_DESKTOP_DIR}" 2>/dev/null || true
    gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
}

_migrate_legacy_names() {
    # One-time cleanup of files left behind by the pre-v1.4.0 "Script
    # Launcher" name, so a Repair doesn't leave two copies installed side
    # by side under the old and new names.
    local found=0
    for f in "${LEGACY_GUI_SCRIPT}" "${LEGACY_GUI_ICON}" "${LEGACY_GUI_DESKTOP}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            found=$((found + 1))
        fi
    done
    if [[ $found -gt 0 ]]; then
        log_info "Removed $found old-named file(s) from before the Solace Script Launcher rename."
        update-desktop-database "${GUI_DESKTOP_DIR}" 2>/dev/null || true
        gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# OPERATIONS
# ──────────────────────────────────────────────────────────────────────────────
launch_gui() {
    if [[ ! -f "${GUI_SCRIPT}" ]]; then
        log_warn "Solace Script Launcher not installed — run option 1 (Install / Repair) first."
        press_enter
        return
    fi
    log_info "Launching Solace Script Launcher…"
    python3 "${GUI_SCRIPT}" &
    disown
    sleep 1
    log_ok "Solace Script Launcher launched."
    press_enter
}

do_install() {
    log_section "Solace Script Launcher — Install / Repair"
    echo "  This installs a GTK3 touch GUI that lists and runs .sh scripts"
    echo "  from a folder you choose. Nothing system-wide is modified — every"
    echo "  file goes in ~/.local, ~/.config, or ~/.local/share."
    echo ""
    confirm "  Proceed with install?" || { log_info "Cancelled."; press_enter; return; }

    _rollback_begin "install"

    _migrate_legacy_names
    mkdir -p "$CONFIG_DIR"
    local dir
    dir="$(get_scripts_dir)"
    if [[ ! -d "$dir" ]]; then
        echo ""
        echo "  Scripts folder (will be created): $dir"
        read -rp "  Press Enter to use this, or type a different path: " chosen
        [[ -n "$chosen" ]] && dir="${chosen%/}"
        mkdir -p "$dir"
        set_scripts_dir "$dir"
        log_ok "Scripts folder ready: $dir"
    else
        log_info "Using existing scripts folder: $dir"
        set_scripts_dir "$dir"
    fi

    install_gui_deps
    write_gui_script
    write_gui_icon
    write_gui_desktop

    _rollback_end
    echo ""
    log_ok "Solace Script Launcher installed."
    log_info "Drop your .sh scripts into: $dir"
    log_info "Open it from the Start Menu (Solace Script Launcher) or option 3 below."
    press_enter
}

do_uninstall() {
    log_section "Solace Script Launcher — Uninstall"
    confirm "  Remove Solace Script Launcher's GUI, icon, and desktop shortcut?" || \
        { log_info "Cancelled."; press_enter; return; }

    uninstall_gui

    echo ""
    log_info "Your scripts folder and everything in it were NOT touched:"
    log_info "  $(get_scripts_dir)"
    if [[ -f "$CONFIG_FILE" ]]; then
        if confirm "  Also forget the saved folder preference?"; then
            rm -f "$CONFIG_FILE"
            log_ok "Folder preference cleared."
        fi
    fi
    log_info "python3-gi / gir1.2-gtk-3.0 were left installed (shared GTK3 dependency)."
    log_ok "Uninstall complete."
    press_enter
}

do_change_folder() {
    log_section "Change Watched Scripts Folder"
    local current
    current="$(get_scripts_dir)"
    echo "  Current folder: $current"
    echo ""
    read -rp "  New folder path (leave blank to keep current): " new_dir
    if [[ -z "$new_dir" ]]; then
        log_info "Kept current folder."
        press_enter
        return
    fi
    new_dir="${new_dir%/}"
    if [[ ! -d "$new_dir" ]]; then
        if confirm "  Folder does not exist. Create it?"; then
            mkdir -p "$new_dir"
        else
            log_warn "Cancelled — folder not changed."
            press_enter
            return
        fi
    fi
    set_scripts_dir "$new_dir"
    log_ok "Scripts folder set to: $new_dir"
    press_enter
}

do_list_scripts() {
    log_section "Scripts Found"
    local dir
    dir="$(get_scripts_dir)"
    echo "  Folder: $dir"
    echo ""
    if [[ ! -d "$dir" ]]; then
        log_warn "Folder does not exist yet — run Install / Repair or change folder."
        press_enter
        return
    fi
    local found=0
    for f in "$dir"/*.sh; do
        [[ -e "$f" ]] || continue
        found=$((found + 1))
        echo -e "  ${BOLD}$(basename "$f")${NC}"
    done
    [[ $found -eq 0 ]] && log_info "No .sh scripts found in this folder yet."
    echo ""
    log_info "Total: $found script(s)"
    press_enter
}

# ──────────────────────────────────────────────────────────────────────────────
# MENU
# ──────────────────────────────────────────────────────────────────────────────
draw_menu() {
    local dir installed_label installed_color count
    dir="$(get_scripts_dir)"
    count="$(count_scripts "$dir")"
    if [[ -f "$GUI_SCRIPT" ]]; then
        installed_label="installed"
        installed_color="$GREEN"
    else
        installed_label="not installed"
        installed_color="$YELLOW"
    fi

    echo ""
    echo -e "${CYAN}${BOLD}  Script Launcher Manager  v${SCRIPT_VERSION}${NC}"
    echo -e "  GUI     : ${installed_color}${installed_label}${NC}"
    echo -e "  Folder  : ${dir}"
    echo -e "  Scripts : ${count} found"
    echo ""
    echo -e "${CYAN}${BOLD}  ──────────────────────────────────────────${NC}"
    echo -e "    ${BOLD}1)${NC}  Install / Repair Solace Script Launcher"
    echo -e "    ${BOLD}2)${NC}  Uninstall Solace Script Launcher"
    echo -e "    ${BOLD}3)${NC}  Open Solace Script Launcher (touch UI)"
    echo -e "    ${BOLD}4)${NC}  Change watched scripts folder"
    echo -e "    ${BOLD}5)${NC}  List scripts found (quick terminal view)"
    echo -e "    ${BOLD}6)${NC}  Exit"
    echo -e "${CYAN}${BOLD}  ──────────────────────────────────────────${NC}"
    echo ""
}

main() {
    refuse_root
    _check_partial_state

    while true; do
        draw_menu
        local choice=""
        read -rp "  Enter choice [1-6]: " choice
        case "$choice" in
            1) do_install        ;;
            2) do_uninstall      ;;
            3) launch_gui        ;;
            4) do_change_folder  ;;
            5) do_list_scripts   ;;
            6)
                echo ""
                log_info "Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                log_warn "Invalid choice — please enter 1–6."
                sleep 1
                ;;
        esac
    done
}

main
