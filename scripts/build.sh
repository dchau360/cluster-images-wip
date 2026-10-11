#!/usr/bin/env bash
#
# `make build` — build every image definition, or one with IMAGE=<name>.
#
# Timed from the first build, because `image-build` is a phase in the
# project's 1-to-N curve and retrofitting instrumentation into a build is
# how measurements end up missing.
#
# Image content is owned by the image task. What is here is the harness:
# discovery, timing, change accounting, and the output contract.

export LAB_SCRIPT_NAME=build
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/timing.sh
source "$HERE/lib/timing.sh"
lab_load_env
counters_init
timing_init

command -v "$IMAGE_ENGINE" >/dev/null 2>&1 \
  || die "container engine '$IMAGE_ENGINE' not found — set IMAGE_ENGINE in lab/local.env"

mapfile -t TARGETS < <(if [[ -n "${IMAGE:-}" ]]; then printf '%s\n' "$IMAGE"; else lab_image_names; fi)
(( ${#TARGETS[@]} > 0 )) || die "no image definition found under images/"

mkdir -p "$IMAGE_BUILD_DIR" 2>/dev/null || sudo mkdir -p "$IMAGE_BUILD_DIR"

log "building ${#TARGETS[@]} image(s) with $IMAGE_ENGINE"

for name in "${TARGETS[@]}"; do
  dir="$REPO_ROOT/images/$name"
  [[ -f "$dir/Containerfile" ]] || die "no images/$name/Containerfile"
  tag="$IMAGE_PREFIX/$name:latest"

  phase_begin image-build "$name"
  if "$IMAGE_ENGINE" build \
       --build-arg "IMAGE_BASE=$IMAGE_BASE" \
       -t "$tag" \
       -f "$dir/Containerfile" \
       "$dir"; then
    phase_end image-build "$name" ok
    changed "image $tag built"
  else
    phase_end image-build "$name" fail
    die "build failed for $name"
  fi
done

counters_report
timing_report "$LAB_TIMING_DIR/$LAB_RUN_ID.ndjson"
