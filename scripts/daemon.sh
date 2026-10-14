#!/usr/bin/env bash
# Polls MPRIS players once a second and publishes the active one for the
# Conky windows: a snapshot line, the cover art, cava frames and a flag that
# hides the visualizer while a window covers it.
DIR=${CONKY_PLAYER_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
RUN=${CONKY_PLAYER_RUN:-${XDG_RUNTIME_DIR:-/dev/shm/$USER}/conky-player}
. "$DIR/scripts/settings.sh"
mkdir -p "$RUN"

SNAP=$RUN/snapshot
OFF=$RUN/viz-off
COVER=$RUN/cover
VIZ=$(setting visualizer yes)
read -ra IGNORE <<< "$(setting cover_ignore conky)"

declare -A prev
cur=""; lasturl=""; cx=""; cy=""

# Centre of the visualizer window, looked up once it exists.
viz_center() {
  [ -n "$cx" ] && return 0
  local geo w h x y
  # Match title and class: another window may be titled "conky-player-viz".
  # Tree lines look like: 0x5a00002 "conky-player-viz": ("conky" "conky")  390x74+35+145  +35+145
  geo=$(xwininfo -root -tree 2>/dev/null |
    awk '/"conky-player-viz": \("conky" / {print $(NF-1), $NF; exit}')
  [[ $geo =~ ^([0-9]+)x([0-9]+)[-+0-9]*\ \+(-?[0-9]+)\+(-?[0-9]+)$ ]] || return 1
  w=${BASH_REMATCH[1]} h=${BASH_REMATCH[2]} x=${BASH_REMATCH[3]} y=${BASH_REMATCH[4]}
  cx=$(( x + w / 2 )); cy=$(( y + h / 2 ))
}

# True if a normal or dialog window on the current desktop covers the
# centre of the visualizer.
covered() {
  local desk id d x y w h cls props i
  viz_center || return 1
  desk=$(wmctrl -d | awk '$2 == "*" {print $1}')
  while read -r id d x y w h cls _; do
    [ "$d" = "$desk" ] || [ "$d" = -1 ] || continue
    for i in "${IGNORE[@]}"; do [[ ${cls,,} == *"${i,,}"* ]] && continue 2; done
    (( cx >= x && cx < x + w && cy >= y && cy < y + h )) || continue
    props=$(xprop -id "$id" _NET_WM_STATE _NET_WM_WINDOW_TYPE 2>/dev/null)
    [[ $props == *HIDDEN* ]] && continue
    [[ $props == *TYPE_NORMAL* || $props == *TYPE_DIALOG* ]] || continue
    return 0
  done < <(wmctrl -lGx 2>/dev/null)
  return 1
}

start_cava() {
  pgrep -f "cava -p $RUN/cava.conf" >/dev/null ||
    setsid -f "$DIR/scripts/cava-run.sh" >/dev/null 2>&1
}

stop_cava() {
  pkill -f "$DIR/scripts/cava-run.sh"
  pkill -f "cava -p $RUN/cava.conf"
  rm -f "$RUN/cava"
}

fetch_cover() {
  local url=$1 path
  case "$url" in
    file://*)
      path=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1][7:]))' "$url")
      cp "$path" "$COVER.tmp" 2>/dev/null ;;
    http://*|https://*)
      curl -sfL --max-time 10 "$url" -o "$COVER.tmp" ;;
    *) false ;;
  esac && mv "$COVER.tmp" "$COVER" || rm -f "$COVER" "$COVER.tmp"
}

trap 'stop_cava; rm -f "$SNAP" "$COVER" "$OFF"; exit' INT TERM

while true; do
  # Pick the active player: one that just started playing wins, then any
  # playing one, then the current one if paused, then any paused one.
  declare -A now=()
  new=""
  mapfile -t players < <(playerctl -l 2>/dev/null | grep -v '^playerctld$')
  for p in "${players[@]}"; do
    st=$(playerctl -p "$p" status 2>/dev/null)
    now[$p]=$st
    [ "$st" = Playing ] && [ "${prev[$p]:-}" != Playing ] && new=$p
  done

  if [ -n "$new" ]; then
    cur=$new
  elif [ -z "$cur" ] || [ "${now[$cur]:-}" != Playing ]; then
    pick=""
    for p in "${players[@]}"; do [ "${now[$p]}" = Playing ] && { pick=$p; break; }; done
    if [ -n "$pick" ]; then cur=$pick
    elif [ -n "$cur" ] && [ "${now[$cur]:-}" = Paused ]; then :
    else
      cur=""
      for p in "${players[@]}"; do [ "${now[$p]}" = Paused ] && { cur=$p; break; }; done
    fi
  fi
  prev=(); for k in "${!now[@]}"; do prev[$k]=${now[$k]}; done

  if [ -n "$cur" ]; then
    line=$(playerctl -p "$cur" metadata --format $'{{status}}\t{{title}}\t{{artist}}\t{{duration(position)}}\t{{duration(mpris:length)}}\t{{position}}\t{{mpris:length}}\t{{mpris:artUrl}}' 2>/dev/null)
    # Strip the instance suffix: "chromium.instance1234" -> "chromium".
    printf '%s\t%s\n' "${cur%%.*}" "$line" > "$SNAP.tmp" && mv "$SNAP.tmp" "$SNAP"

    url=$(cut -f9 "$SNAP")
    if [ "$url" != "$lasturl" ]; then
      lasturl=$url
      fetch_cover "$url"
    fi

    if covered; then
      touch "$OFF"; stop_cava
    else
      rm -f "$OFF"
      if [ "${now[$cur]}" = Playing ] && [ "$VIZ" = yes ]; then start_cava; else stop_cava; fi
    fi
  else
    rm -f "$SNAP" "$COVER"; touch "$OFF"; stop_cava; lasturl=""
  fi
  # Backgrounded so the TERM trap runs immediately instead of after sleep.
  sleep 1 & wait $!
done
