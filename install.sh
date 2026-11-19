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
LDCONFIG="$(command -v ldconfig || true)"
[[ -z "$LDCONFIG" && -x /sbin/ldconfig ]] && LDCONFIG=/sbin/ldconfig      # Debian keeps it off the user PATH
[[ -z "$LDCONFIG" && -x /usr/sbin/ldconfig ]] && LDCONFIG=/usr/sbin/ldconfig
LIBS="$([[ -n "$LDCONFIG" ]] && "$LDCONFIG" -p 2>/dev/null || true)"
missing=()
if [[ -n "$LIBS" ]]; then  # can't tell? don't guess
  for lib in libxcb-cursor.so.0 libxkbcommon-x11.so.0 libEGL.so.1 libfontconfig.so.1 libdbus-1.so.3; do
    [[ "$LIBS" == *"$lib"* ]] || missing+=("$lib")
  done
fi
if (( ${#missing[@]} )); then
  if command -v apt >/dev/null; then LIBCMD="sudo apt install -y libxcb-cursor0 libxkbcommon-x11-0 libegl1 libfontconfig1 libdbus-1-3"
  elif command -v dnf >/dev/null; then LIBCMD="sudo dnf install -y xcb-util-cursor libxkbcommon-x11 mesa-libEGL fontconfig dbus-libs"
  elif command -v pacman >/dev/null; then LIBCMD="sudo pacman -S --needed --noconfirm xcb-util-cursor libxkbcommon-x11 libglvnd fontconfig dbus"
  elif command -v zypper >/dev/null; then LIBCMD="sudo zypper install -y libxcb-cursor0 libxkbcommon-x11-0 libEGL1 fontconfig libdbus-1-3"
  else LIBCMD=""
  fi
  warn "Saarthi's window needs a few system libraries that are missing: ${missing[*]}"
  answer="n"
  if [[ -n "$LIBCMD" && -r /dev/tty ]]; then
    printf '    Install them now with:  %s\n    [Y/n] ' "$LIBCMD"
    read -r answer < /dev/tty || answer="n"
    answer="${answer:-y}"
  fi
  if [[ "$answer" =~ ^[Yy] ]]; then
    $LIBCMD || warn "Couldn't install them. Run this yourself:  $LIBCMD"
  elif [[ -n "$LIBCMD" ]]; then
    warn "Run this, then start Saarthi from the app menu:  $LIBCMD"
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

# ---------- make the `saarthi` command work in new terminals ----------
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      if [[ -f "$rc" ]] && ! grep -q 'saarthi: ~/.local/bin' "$rc"; then
        printf '\n# saarthi: ~/.local/bin on PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
      fi
    done
    warn "Open a new terminal to use the 'saarthi' command (or run: export PATH=\"\$HOME/.local/bin:\$PATH\")" ;;
esac

# ---------- start it, and make sure it really started ----------
"$APP_DIR/saarthi" --quit >/dev/null 2>&1 || true
LOG="$DATA/saarthi/last-start.log"
say "Starting Saarthi 🎉  (double-click it for reminders & notes, right-click for the menu)"
nohup "$APP_DIR/saarthi" >"$LOG" 2>&1 &
sleep 5
if pgrep -f "$APP_DIR/saarthi" >/dev/null 2>&1; then
  say "Saarthi is running. Look at the bottom-right of your screen."
else
  warn "Saarthi didn't stay open. Last messages:"
  grep -v '^qt.qpa.theme\|portal' "$LOG" | tail -5 | sed 's/^/    /'
  if grep -q 'xcb' "$LOG"; then
    warn "This is the missing-library problem above. Install them, then open Saarthi from the app menu."
  fi
fi
