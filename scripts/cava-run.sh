#!/usr/bin/env bash
cava -p "$HOME/.config/conky-player/scripts/cava.conf" | while IFS= read -r l; do
  printf '%s\n' "$l" > /dev/shm/cava.txt
done
