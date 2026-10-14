#!/usr/bin/env bash
# Runs cava with a config generated from settings.conf and keeps the latest
# frame (semicolon-separated bar heights, 0-100) in $CONKY_PLAYER_RUN/cava.
DIR=${CONKY_PLAYER_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
RUN=${CONKY_PLAYER_RUN:-${XDG_RUNTIME_DIR:-/dev/shm/$USER}/conky-player}
. "$DIR/scripts/settings.sh"
mkdir -p "$RUN"

cat > "$RUN/cava.conf" <<CONF
[general]
bars = $(setting viz_bars 32)
framerate = $(setting viz_fps 60)
[input]
method = $(setting cava_input pulse)
source = auto
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
bar_delimiter = 59
frame_delimiter = 10
CONF

cava -p "$RUN/cava.conf" | while IFS= read -r l; do
  printf '%s\n' "$l" > "$RUN/cava"
done
