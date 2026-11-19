#!/usr/bin/env bash
# Saarthi installer for Linux (x86_64). No Python or admin rights needed.
#
#   curl -fsSL https://raw.githubusercontent.com/Ashish04Kumar/saarthiDesk-releases/main/install.sh | bash
#
#   ... | bash -s -- --autostart     also start Saarthi with your computer
#   ... | bash -s -- --uninstall     remove it (your notes, reminders and settings are kept)
set -euo pipefail

REPO_RAW="${SAARTHI_BASE_URL:-https://github.com/Ashish04Kumar/saarthiDesk-releases/raw/main}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA/saarthi/app"
BIN_DIR="$HOME/.local/bin"
DESKTOP_FILE="$DATA/applications/saarthi.desktop"
ICON_FILE="$DATA/icons/hicolor/256x256/apps/saarthi.png"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

AUTOSTART=0
for arg in "$@"; do
  case "$arg" in
    --autostart) AUTOSTART=1 ;;
    --uninstall)
      say "Removing Saarthi (your data in ~/.config/saarthi is kept)"
      [[ -x "$APP_DIR/saarthi" ]] && "$APP_DIR/saarthi" --quit >/dev/null 2>&1 || true
      rm -rf "$APP_DIR" "$BIN_DIR/saarthi" "$DESKTOP_FILE" "$ICON_FILE" \
             "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/saarthi.desktop"
      say "Done."
      exit 0 ;;
    *) die "Unknown option: $arg" ;;
  esac
done

# ---------- checks ----------
[[ "$(uname -s)" == "Linux" ]] || die "This installer is for Linux. Windows/macOS builds are coming."
[[ "$(uname -m)" == "x86_64" ]] || die "Only x86_64 (64-bit Intel/AMD) is supported right now."
GLIBC="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || echo 0)"
if [[ "$(printf '%s\n2.34\n' "$GLIBC" | sort -V | head -1)" != "2.34" ]]; then
  die "Your Linux is too old (glibc $GLIBC). Saarthi needs glibc 2.34+: Ubuntu 22.04+, Mint 21+, Debian 12+, Fedora 35+."
fi
command -v curl >/dev/null || die "curl is needed."
command -v tar  >/dev/null || die "tar is needed."

# ---------- download ----------
VERSION="$(curl -fsSL "$REPO_RAW/VERSION" 2>/dev/null || echo latest)"
say "Downloading Saarthi $VERSION (~70 MB)…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fL --progress-bar "$REPO_RAW/saarthi-linux-x86_64.tar.gz" -o "$TMP/saarthi.tar.gz" || die "Download failed."
if curl -fsSL "$REPO_RAW/saarthi-linux-x86_64.tar.gz.sha256" -o "$TMP/sum" 2>/dev/null; then
  ( cd "$TMP" && echo "$(cut -d' ' -f1 sum)  saarthi.tar.gz" | sha256sum -c --quiet - ) || die "Checksum mismatch, download again."
fi

# ---------- install ----------
[[ -x "$APP_DIR/saarthi" ]] && "$APP_DIR/saarthi" --quit >/dev/null 2>&1 || true
say "Installing to $APP_DIR"
rm -rf "$APP_DIR" && mkdir -p "$APP_DIR"
tar -xzf "$TMP/saarthi.tar.gz" -C "$APP_DIR" --strip-components=1
mkdir -p "$BIN_DIR" "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON_FILE")"
ln -sf "$APP_DIR/saarthi" "$BIN_DIR/saarthi"
cp "$APP_DIR/_internal/saarthi/assets/icon.png" "$ICON_FILE" 2>/dev/null || true
cat > "$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Saarthi
Comment=Your animated desktop companion
Exec="$APP_DIR/saarthi"
Icon=saarthi
Terminal=false
Categories=Utility;
StartupWMClass=saarthi
DESKTOP
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$(dirname "$DESKTOP_FILE")" || true
say "Added Saarthi to your app menu"

# ---------- system libraries the window needs ----------
LIBS="$(ldconfig -p 2>/dev/null || true)"
missing=()
for lib in libxcb-cursor.so.0 libxkbcommon-x11.so.0 libEGL.so.1 libfontconfig.so.1 libdbus-1.so.3; do
  [[ "$LIBS" == *"$lib"* ]] || missing+=("$lib")
done
if (( ${#missing[@]} )); then
  warn "A few system libraries are missing: ${missing[*]}. Install them with:"
  if command -v apt >/dev/null; then echo "    sudo apt install -y libxcb-cursor0 libxkbcommon-x11-0 libegl1 libfontconfig1 libdbus-1-3"
  elif command -v dnf >/dev/null; then echo "    sudo dnf install -y xcb-util-cursor libxkbcommon-x11 mesa-libEGL fontconfig dbus-libs"
  elif command -v pacman >/dev/null; then echo "    sudo pacman -S --needed xcb-util-cursor libxkbcommon-x11 libglvnd fontconfig dbus"
  elif command -v zypper >/dev/null; then echo "    sudo zypper install libxcb-cursor0 libxkbcommon-x11-0 libEGL1 fontconfig libdbus-1-3"
  fi
fi

# ---------- typing detection on Wayland ----------
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && ! id -nG | grep -qw input; then
  echo
  warn "You're on Wayland. To let Saarthi see how fast you type (never what you type), run once:"
  echo "    sudo usermod -aG input \$USER"
  warn "then log out and back in. Everything else works without it."
fi

if (( AUTOSTART )); then
  mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
  cp "$DESKTOP_FILE" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/saarthi.desktop"
  say "Saarthi will start with your computer"
fi

case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "Add ~/.local/bin to your PATH to use the 'saarthi' command." ;; esac
say "Starting Saarthi 🎉  (double-click it for reminders & notes, right-click for the menu)"
nohup "$APP_DIR/saarthi" >/dev/null 2>&1 &
