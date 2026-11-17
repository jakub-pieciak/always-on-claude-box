# shellcheck shell=bash
# Shared helpers for install.sh and the modules.

c_blue=$'\033[1;34m'; c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_off=$'\033[0m'

step() { printf '\n%s==> %s%s\n' "$c_blue" "$*" "$c_off"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '%s    ✓ %s%s\n' "$c_green" "$*" "$c_off"; }
warn() { printf '%s    ! %s%s\n' "$c_yellow" "$*" "$c_off" >&2; }
die()  { printf '%sERROR: %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }

# run CMD...      run a command, or only print it in --dry-run mode
run() {
  if [[ "${DRY_RUN:-false}" == true ]]; then printf '    + %s\n' "$*"; else "$@"; fi
}

# put FILE MODE [root]   write stdin to FILE (as root when the 3rd arg is "root")
put() {
  local file=$1 mode=$2 who=${3:-user} tmp
  tmp="$(mktemp)"; cat > "$tmp"
  if [[ "${DRY_RUN:-false}" == true ]]; then
    printf '    + write %s (%s, %s, %s lines)\n' "$file" "$mode" "$who" "$(wc -l < "$tmp")"
  elif [[ "$who" == root ]]; then
    sudo install -D -m "$mode" "$tmp" "$file"
  else
    install -D -m "$mode" "$tmp" "$file"
  fi
  rm -f "$tmp"
}

# ask VAR "Question" "default"
ask() {
  local __var=$1 __q=$2 __def=${3:-} __a
  read -rp "    $__q${__def:+ [$__def]}: " __a
  printf -v "$__var" '%s' "${__a:-$__def}"
}

# ask_yn VAR "Question" y|n
ask_yn() {
  local __var=$1 __q=$2 __def=$3 __a __hint
  [[ "$__def" == y ]] && __hint="Y/n" || __hint="y/N"
  while true; do
    read -rp "    $__q [$__hint]: " __a; __a="${__a:-$__def}"
    case "${__a,,}" in
      y|yes|t|tak) printf -v "$__var" true; return ;;
      n|no|nie)    printf -v "$__var" false; return ;;
    esac
  done
}

# ask_secret VAR "Question" MINLEN   (typed twice, never echoed)
ask_secret() {
  local __var=$1 __q=$2 __min=${3:-1} __a __b
  while true; do
    read -rsp "    $__q: " __a; echo
    read -rsp "    Repeat: " __b; echo
    if [[ "$__a" != "$__b" ]]; then warn "They do not match, try again."; continue; fi
    if (( ${#__a} < __min )); then warn "At least $__min characters, try again."; continue; fi
    printf -v "$__var" '%s' "$__a"; return
  done
}

installed() { dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'; }
