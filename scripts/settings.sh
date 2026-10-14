# Sourced by the shell scripts. Expects $DIR to point at the install dir.

# Usage: setting KEY DEFAULT
# Prints the value of KEY from settings.conf, or DEFAULT if it is not set.
setting() {
  local k v
  if [ -f "$DIR/settings.conf" ]; then
    while IFS='=' read -r k v; do
      k=${k//[[:space:]]/}
      [ "$k" = "$1" ] || continue
      v=${v#"${v%%[![:space:]]*}"}
      v=${v%"${v##*[![:space:]]}"}
      printf '%s\n' "$v"
      return
    done < "$DIR/settings.conf"
  fi
  printf '%s\n' "$2"
}
