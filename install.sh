#!/usr/bin/env bash
# Installs conky-player into ${XDG_CONFIG_HOME:-~/.config}/conky-player,
# checks dependencies and optionally adds an autostart entry.
# Never uses sudo: missing packages are only reported.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
DEST=$CONFIG/conky-player
AUTOSTART_FILE=$CONFIG/autostart/conky-player.desktop
autostart=ask
answer=""

usage() {
  cat <<EOF
usage: ${0##*/} [--autostart | --no-autostart]

Copies conky-player to $DEST and checks dependencies.
An existing settings.conf is kept.

  --autostart     create $AUTOSTART_FILE
  --no-autostart  do not create it and do not ask
EOF
}

for arg in "$@"; do
  case "$arg" in
    --autostart)    autostart=yes ;;
    --no-autostart) autostart=no ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage >&2; exit 2 ;;
  esac
done

# --- Dependencies -------------------------------------------------------

missing_pkgs=()
missing_other=()
need_pkg() { [[ " ${missing_pkgs[*]} " == *" $1 "* ]] || missing_pkgs+=("$1"); }

if ! command -v conky >/dev/null; then
  need_pkg conky-all
elif ! conky -v 2>/dev/null | grep -A5 'Lua bindings' | grep -q Cairo ||
     ! conky -v 2>/dev/null | grep -A5 'Lua bindings' | grep -q Imlib2; then
  echo "conky is installed but lacks Lua cairo/imlib2 bindings (conky-std is not enough)."
  need_pkg conky-all
fi

for cmd in playerctl:playerctl cava:cava wmctrl:wmctrl xprop:x11-utils \
           xwininfo:x11-utils curl:curl python3:python3; do
  command -v "${cmd%%:*}" >/dev/null || need_pkg "${cmd#*:}"
done

# Pango renders titles in every script; without it they fall back to plain
# text with no shaping or font fallback.
if command -v python3 >/dev/null && ! python3 -c "import cairo, gi
gi.require_version('PangoCairo', '1.0')
from gi.repository import PangoCairo" 2>/dev/null; then
  need_pkg python3-gi; need_pkg python3-gi-cairo; need_pkg gir1.2-pango-1.0
fi

# Check the fonts named in the settings that will be used.
settings_file=$DEST/settings.conf
[ -f "$settings_file" ] || settings_file=$SRC/settings.conf
DIR=${settings_file%/settings.conf}
. "$SRC/scripts/settings.sh"
for key in font:Inter font_mono:'JetBrains Mono' font_symbol:'DejaVu Sans' font_cjk:'Noto Sans CJK JP'; do
  family=$(setting "${key%%:*}" "${key#*:}")
  fc-list ":family=$family" 2>/dev/null | grep -q . && continue
  case "$family" in
    Inter)              need_pkg fonts-inter ;;
    'JetBrains Mono')   need_pkg fonts-jetbrains-mono ;;
    'DejaVu Sans')      need_pkg fonts-dejavu-core ;;
    'Noto Sans CJK'*)   need_pkg fonts-noto-cjk ;;
    *)                  missing_other+=("font \"$family\"") ;;
  esac
done

if [ ${#missing_pkgs[@]} -gt 0 ] || [ ${#missing_other[@]} -gt 0 ]; then
  echo "Missing dependencies:"
  [ ${#missing_pkgs[@]} -gt 0 ] && echo "  sudo apt install ${missing_pkgs[*]}"
  for m in "${missing_other[@]}"; do echo "  $m (install it or change settings.conf)"; done
  echo "Installing anyway; install these for the widget to work fully."
  echo
else
  echo "All dependencies found."
fi

# Titles in other scripts need a font that has them; Noto covers most.
if ! fc-list :lang=ar 2>/dev/null | grep -q . || ! fc-list :lang=hi 2>/dev/null | grep -q .; then
  echo "Optional: for Arabic, Hebrew, Devanagari and other scripts install"
  echo "  sudo apt install fonts-noto-core"
  echo
fi

if [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
  echo "Warning: this is a Wayland session. conky-player needs X11 (wmctrl, xprop and"
  echo "Conky's own_window do not work on Wayland)."
  echo
fi

# --- Files --------------------------------------------------------------

if [ "$SRC" = "$DEST" ]; then
  echo "Already running from $DEST, not copying."
else
  mkdir -p "$DEST/conky" "$DEST/scripts"
  install -m 755 "$SRC/conky-player.sh" "$DEST/"
  install -m 644 "$SRC"/conky/*.lua "$SRC"/conky/*.conf "$DEST/conky/"
  install -m 755 "$SRC/scripts/daemon.sh" "$SRC/scripts/cava-run.sh" \
    "$SRC/scripts/render-text.py" "$DEST/scripts/"
  install -m 644 "$SRC/scripts/settings.sh" "$DEST/scripts/"
  if [ -f "$DEST/settings.conf" ]; then
    echo "Kept existing $DEST/settings.conf (defaults are in $SRC/settings.conf)."
  else
    install -m 644 "$SRC/settings.conf" "$DEST/"
  fi
  echo "Installed to $DEST"
fi

# --- Autostart ----------------------------------------------------------

if [ "$autostart" = ask ]; then
  autostart=no
  if [ -t 0 ]; then
    read -rp "Start conky-player automatically on login? [y/N] " answer
    [[ $answer == [yY]* ]] && autostart=yes
  fi
fi

if [ "$autostart" = yes ]; then
  mkdir -p "${AUTOSTART_FILE%/*}"
  cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=conky-player
Comment=Media player widget for Conky
Exec=sh -c 'sleep 5 && exec "$DEST/conky-player.sh" start'
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
  echo "Created $AUTOSTART_FILE"
fi

echo
echo "Start it with: $DEST/conky-player.sh start"
