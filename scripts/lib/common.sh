#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for the image build harness.
#
# Deliberately the same shape as the platform repository's
# scripts/lib/common.sh: the same env-file layering, the same `ok` and
# `changed` accounting, and the same timing format, so timings from both
# repositories land in one stream and the 1-to-N curve is one picture.

set -euo pipefail

# Needs bash 4 (mapfile, associative arrays). Say so plainly: a gate that dies
# with "mapfile: command not found" looks broken rather than unsupported.
# macOS ships bash 3.2; use `brew install bash`.
if (( BASH_VERSINFO[0] < 4 )); then
  echo "error: bash 4 or newer required, found $BASH_VERSION" >&2
  exit 2
fi

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export REPO_ROOT

LAB_ENV_EXAMPLE="$REPO_ROOT/lab/local.env.example"
LAB_ENV_FILE="${LAB_ENV_FILE:-$REPO_ROOT/lab/local.env}"

_C_RED=''; _C_GRN=''; _C_YLW=''; _C_BLU=''; _C_RST=''
if [[ -t 1 ]]; then
  _C_RED=$'\033[31m'; _C_GRN=$'\033[32m'; _C_YLW=$'\033[33m'
  _C_BLU=$'\033[36m'; _C_RST=$'\033[0m'
fi

log()  { printf '%s[%s]%s %s\n' "$_C_BLU" "${LAB_SCRIPT_NAME:-images}" "$_C_RST" "$*"; }
warn() { printf '%swarn%s %s\n' "$_C_YLW" "$_C_RST" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$_C_RED" "$_C_RST" "$*" >&2; exit 1; }

lab_load_env() {
  [[ -f "$LAB_ENV_EXAMPLE" ]] || die "missing $LAB_ENV_EXAMPLE"
  set -a
  # shellcheck disable=SC1090
  source <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$LAB_ENV_EXAMPLE")
  if [[ -f "$LAB_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$LAB_ENV_FILE")
  fi
  set +a

  LAB_STATE_DIR="${LAB_STATE_DIR:-/var/lib/cluster-lab}"
  export LAB_STATE_DIR
  export LAB_TIMING_DIR="$LAB_STATE_DIR/timings"
  export LAB_RUN_DIR="$LAB_STATE_DIR/run"

  lab_bootstrap_state
}

# Same bootstrap as the platform repository, and for the same reason: the
# change counter and the timing log are written before anything else gets a
# chance to create their directories. Both repositories write into one
# timing stream, so they must agree on who owns it.
lab_bootstrap_state() {
  local owner="${LAB_WSL_USER:-$USER}" d
  for d in "$LAB_STATE_DIR" "$LAB_RUN_DIR" "$LAB_TIMING_DIR"; do
    [[ -d "$d" ]] || sudo mkdir -p "$d"
  done
  for d in "$LAB_RUN_DIR" "$LAB_TIMING_DIR"; do
    [[ -w "$d" ]] || sudo chown "$owner" "$d"
  done
}

# Every image definition under images/. Discovered, never listed by hand.
lab_image_names() {
  local d
  for d in "$REPO_ROOT"/images/*/; do
    [[ -f "${d}Containerfile" ]] || continue
    basename "$d"
  done
}

# --- change accounting -----------------------------------------------------

_counter_file() { printf '%s' "${LAB_COUNTER_FILE:-$LAB_RUN_DIR/image-changes}"; }

counters_init() {
  mkdir -p "$(dirname "$(_counter_file)")" 2>/dev/null \
    || sudo mkdir -p "$(dirname "$(_counter_file)")"
  printf '0 0\n' > "$(_counter_file)"
}

_bump() {
  local f; f="$(_counter_file)"
  [[ -f "$f" ]] || counters_init
  local c o; read -r c o < "$f"
  case "$1" in changed) c=$((c + 1));; ok) o=$((o + 1));; esac
  printf '%s %s\n' "$c" "$o" > "$f"
}

changed() { _bump changed; printf '%schanged%s %s\n' "$_C_YLW" "$_C_RST" "$*"; }
ok()      { _bump ok;      printf '%sok%s      %s\n' "$_C_GRN" "$_C_RST" "$*"; }

counters_changed() { local c o; read -r c o < "$(_counter_file)"; printf '%s' "$c"; }

counters_report() {
  local c o; read -r c o < "$(_counter_file)"
  printf '\nRESULT: changed=%s ok=%s\n' "$c" "$o"
}
