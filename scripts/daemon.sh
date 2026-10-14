#!/usr/bin/env bash
D="$HOME/.config/conky-player"
S=/dev/shm/conky-player.txt
OFF=/dev/shm/conky-viz-off
CX=230; CY=$(( ${VIZ_Y:-150} + 30 ))   # centre of the visualizer window
declare -A prev
cur=""; lasturl=""

covered() {
  local desk id d x y w h cls props
  desk=$(wmctrl -d | awk '$2=="*"{print $1}')
  while read -r id d x y w h cls _; do
    [ "$d" = "$desk" ] || continue
    case "${cls,,}" in *hidamari*|*nemo-desktop*|*conky*) continue ;; esac
    (( CX >= x && CX < x + w && CY >= y && CY < y + h )) || continue
    props=$(xprop -id "$id" _NET_WM_STATE _NET_WM_WINDOW_TYPE 2>/dev/null)
    [[ $props == *HIDDEN* ]] && continue
    [[ $props == *TYPE_NORMAL* || $props == *TYPE_DIALOG* ]] || continue
    return 0
  done < <(wmctrl -lGx)
  return 1
}
stop_cava() {
  pkill -f "$D/scripts/cava-run.sh"; pkill -f "cava -p $D/scripts/cava.conf"
  rm -f /dev/shm/cava.txt
}

while true; do
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
    printf '%s\t%s\n' "${cur%%.*}" "$line" > "$S.tmp" && mv "$S.tmp" "$S"

    url=$(cut -f9 "$S")
    if [ "$url" != "$lasturl" ]; then
      lasturl=$url
      case "$url" in
        file://*) cp "$(python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1][7:]))' "$url")" /tmp/conky-cover 2>/dev/null ;;
        http*)    curl -sL "$url" -o /tmp/conky-cover ;;
        *)        rm -f /tmp/conky-cover ;;
      esac
    fi

    if [ "${now[$cur]}" = Playing ] && ! covered; then
      rm -f "$OFF"
      pgrep -f "cava -p $D/scripts/cava.conf" >/dev/null || setsid -f "$D/scripts/cava-run.sh" >/dev/null 2>&1
    elif covered; then
      touch "$OFF"; stop_cava
    else
      rm -f "$OFF"; stop_cava
    fi
  else
    rm -f "$S"; touch "$OFF"; stop_cava; lasturl=""
  fi
  sleep 1
done
