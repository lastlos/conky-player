#!/usr/bin/env bash
S=/dev/shm/conky-player.txt
f() { [ -f "$S" ] && cut -f"$1" "$S"; }
marquee() {
  local s="$1" w=$2 L=${#1}
  if (( L <= w )); then echo "$s"; return; fi
  local R=$((L - w)) P=4 c k t pos
  c=$((2 * R + 2 * P))
  t=$(( $(date +%s%N) / 500000000 ))
  k=$((t % c))
  if   (( k < P ));         then pos=0
  elif (( k < P + R ));     then pos=$((k - P))
  elif (( k < 2 * P + R )); then pos=$R
  else                           pos=$((R - (k - 2 * P - R)))
  fi
  echo "${s:pos:w}"
}
case "$1" in
  state)  [ -f "$S" ] && echo on || echo off ;;
  player) f 1 ;;
  icon)   [ "$(f 2)" = Playing ] && echo "▶" || echo "▮▮" ;;
  title)  marquee "$(f 3)" 37 ;;
  artist) marquee "$(f 4)" 46 ;;
  time)   echo "$(f 5) / $(f 6)" ;;
esac
