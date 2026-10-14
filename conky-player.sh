#!/usr/bin/env bash
# Start, stop or restart the conky-player widget.
# Works from any location: paths are resolved relative to this script.
DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
RUN=${XDG_RUNTIME_DIR:-/dev/shm/$USER}/conky-player
export CONKY_PLAYER_DIR=$DIR CONKY_PLAYER_RUN=$RUN

stop() {
  pkill -f "conky .*-c $DIR/conky/" 2>/dev/null
  pkill -f "$DIR/scripts/daemon.sh" 2>/dev/null
  pkill -f "$DIR/scripts/cava-run.sh" 2>/dev/null
  pkill -f "cava -p $RUN/cava.conf" 2>/dev/null
  rm -f "$RUN"/snapshot "$RUN"/cover "$RUN"/cava "$RUN"/cava.conf "$RUN"/viz-off
  rmdir "$RUN" 2>/dev/null
  return 0
}

start() {
  stop
  mkdir -p "$RUN"
  setsid -f "$DIR/scripts/daemon.sh" >/dev/null 2>&1
  conky -q -c "$DIR/conky/panel.conf" -d
  conky -q -c "$DIR/conky/visualizer.conf" -d
}

status() {
  if pgrep -f "$DIR/scripts/daemon.sh" >/dev/null; then
    echo "running"
    pgrep -af "conky .*-c $DIR/conky/|$DIR/scripts/|cava -p $RUN/"
  else
    echo "stopped"
    return 1
  fi
}

case "${1:-}" in
  start|restart) start ;;
  stop)          stop ;;
  status)        status ;;
  *)             echo "usage: ${0##*/} start|stop|restart|status" >&2; exit 2 ;;
esac
