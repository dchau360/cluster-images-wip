#!/usr/bin/env bash
#
# `make import` — import built images into Warewulf so nodes can boot them.
#
# Stub. The Warewulf task owns the import mechanics. The harness around it
# is here already so that task only has to fill in one command: discovery,
# the `image-import` timing phase, and the idempotency contract are done.

export LAB_SCRIPT_NAME=import
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/timing.sh
source "$HERE/lib/timing.sh"
lab_load_env
counters_init
timing_init

if ! command -v wwctl >/dev/null 2>&1; then
  warn "wwctl not installed — nothing to import.
     The Warewulf task installs it. See the platform repository."
  exit 0
fi

mapfile -t TARGETS < <(if [[ -n "${IMAGE:-}" ]]; then printf '%s\n' "$IMAGE"; else lab_image_names; fi)

for name in "${TARGETS[@]}"; do
  tag="$IMAGE_PREFIX/$name:latest"
  phase_begin image-import "$name"
  if sudo wwctl image list 2>/dev/null | grep -qE "^[[:space:]]*$name\b"; then
    ok "image $name already imported"
  else
    # Owned by the Warewulf task. Left explicit so the gap is visible
    # rather than silently skipped.
    warn "import of $tag not implemented yet — owned by the Warewulf task"
  fi
  phase_end image-import "$name"
done

counters_report
