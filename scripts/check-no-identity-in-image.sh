#!/usr/bin/env bash
#
# Prove no identity material is baked into any layer of a built node image.
#
# The identity criterion is "absent from every image layer", not "absent from
# the running container". A secret that only exists in a lower layer is still
# in the published image, still pullable by anyone, and still on the node after
# a pivot. So this walks the layer tarballs in `docker save` output rather than
# the flattened filesystem.
#
# It checks the same shapes the git gates check: the Munge key and any SSH
# host key. The image installs neither; the lab host generates them and a
# Warewulf per-node overlay delivers them at boot.
#
# The layer list comes from the saved manifest, not from a `find`, and every
# declared layer must be present and readable. A containerd-backed `docker
# save` can write an OCI index whose layer blobs are not in the archive at
# all; a `find` would then count zero layers and the check would pass on an
# image it never read. That is the one outcome this gate exists to prevent.
#
# Usage:  scripts/check-no-identity-in-image.sh <image-ref> [<image-ref> ...]
# Exit:   0 clean, 1 findings.

set -euo pipefail

(( $# > 0 )) || {
  echo "usage: $0 <image-ref> [<image-ref> ...]" >&2
  exit 2
}

command -v python3 >/dev/null 2>&1 || {
  echo "error: python3 is required to read the image manifest" >&2
  exit 2
}

FINDINGS=0
finding() { FINDINGS=$((FINDINGS + 1)); printf 'FAIL %s\n' "$*"; }
pass()    { printf 'ok   %s\n' "$*"; }

# Paths inside a layer tarball, anchored. The second arm covers the whole
# `ssh_host_*` family, including a `.pub` or a stray `.bak`.
IDENTITY_PATTERN='(^|/)etc/munge/munge\.key$|(^|/)etc/ssh/ssh_host_[^/]*$'

# Print the layer paths a saved image declares, one per line. Docker's classic
# format lists them under `Layers` in manifest.json; an OCI layout lists their
# digests in the manifest blob that index.json points at.
image_layer_paths() {
  python3 - "$1" <<'PY'
import json
import os
import sys

root = sys.argv[1]
paths = []

manifest = os.path.join(root, "manifest.json")
if os.path.exists(manifest):
    with open(manifest, encoding="utf-8") as fh:
        entries = json.load(fh)
    paths = entries[0].get("Layers", [])
else:
    with open(os.path.join(root, "index.json"), encoding="utf-8") as fh:
        index = json.load(fh)
    for entry in index.get("manifests", []):
        digest = entry.get("digest", "").split(":")[-1]
        blob = os.path.join(root, "blobs", "sha256", digest)
        if not os.path.exists(blob):
            continue
        with open(blob, encoding="utf-8") as fh:
            manifest_doc = json.load(fh)
        paths = [
            os.path.join("blobs", "sha256", layer["digest"].split(":")[-1])
            for layer in manifest_doc.get("layers", [])
        ]
        break

print("\n".join(paths))
PY
}

# List a layer's entries. OCI layers are gzipped; classic layer.tar is not.
list_layer() {
  tar -tzf "$1" 2>/dev/null && return 0
  tar -tf "$1" 2>/dev/null
}

check_image() {
  local image="$1" work layer listing matches paths
  local declared=0 layers=0
  echo "== $image"

  work="$(mktemp -d)"
  docker save -o "$work/image.tar" "$image"
  tar -xf "$work/image.tar" -C "$work"

  mapfile -t paths < <(image_layer_paths "$work")

  if (( ${#paths[@]} == 0 )); then
    finding "$image: the saved manifest declares no layers — cannot prove absence"
  else
    for layer in "${paths[@]}"; do
      declared=$((declared + 1))
      if [[ ! -f "$work/$layer" ]]; then
        finding "$image: declared layer $layer is missing from the archive"
        continue
      fi
      if ! listing="$(list_layer "$work/$layer")"; then
        finding "$image: layer $layer is not a readable tar"
        continue
      fi
      layers=$((layers + 1))
      matches="$(printf '%s\n' "$listing" | grep -E "$IDENTITY_PATTERN" || true)"
      if [[ -n "$matches" ]]; then
        finding "$image layer $layer contains: $(printf '%s' "$matches" | tr '\n' ' ')"
      fi
    done

    if (( layers == declared )); then
      # Cross-check the flattened result as well. A layer check could miss an
      # image format this script does not parse; the running filesystem cannot.
      if docker run --rm --entrypoint /bin/sh "$image" -c \
           'test ! -e /etc/munge/munge.key && ! ls /etc/ssh/ssh_host_*_key 2>/dev/null'; then
        pass "$image: no identity material in $layers layer(s) or the flattened image"
      else
        finding "$image: identity material present in the flattened image"
      fi
    else
      finding "$image: read $layers of $declared declared layer(s)"
    fi
  fi

  rm -rf "$work"
  return 0
}

for image in "$@"; do
  check_image "$image"
done

if (( FINDINGS > 0 )); then
  echo "RESULT: $FINDINGS finding(s). Identity material is delivered by a Warewulf runtime overlay at boot; it must never enter an image layer."
  exit 1
fi
echo "RESULT: no identity material in any image layer"
