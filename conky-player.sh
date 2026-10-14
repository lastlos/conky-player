#!/usr/bin/env bash
# Start, stop or restart the conky-player widget.
D="$HOME/.config/conky-player"

stop() {
  pkill -f "conky -c $D/conky/" 2>/dev/null
  pkill -f "$D/scripts/daemon.sh" 2>/dev/null
  pkill -f "$D/scripts/cava-run.sh" 2>/dev/null
  pkill -f "cava -p $D/scripts/cava.conf" 2>/dev/null
  rm -f /dev/shm/cava.txt /dev/shm/conky-viz-off /dev/shm/conky-player.*
}

start() {
  stop
  export VIZ_Y=150
  setsid -f "$D/scripts/daemon.sh" >/dev/null 2>&1
  conky -c "$D/conky/panel.conf" -d
  conky -c "$D/conky/visualizer.conf" -d
}

case "$1" in
  start|restart) start ;;
  stop)          stop ;;
  *)             echo "usage: ${0##*/} start|stop|restart" >&2; exit 2 ;;
esac
