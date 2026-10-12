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
# Usage:  scripts/check-no-identity-in-image.sh <image-ref> [<image-ref> ...]
# Exit:   0 clean, 1 findings.

set -euo pipefail

(( $# > 0 )) || {
  echo "usage: $0 <image-ref> [<image-ref> ...]" >&2
  exit 2
}

FINDINGS=0
finding() { FINDINGS=$((FINDINGS + 1)); printf 'FAIL %s\n' "$*"; }
pass()    { printf 'ok   %s\n' "$*"; }

# Paths inside a layer tarball, anchored. The second arm covers the whole
# `ssh_host_*` family, including a `.pub` or a stray `.bak`.
IDENTITY_PATTERN='(^|/)etc/munge/munge\.key$|(^|/)etc/ssh/ssh_host_[^/]*$'

check_image() {
  local image="$1" work layers layer matches
  echo "== $image"
  work="$(mktemp -d)"
  # RETURN fires when this function returns, so the (large) saved tar does not
  # outlive the image it belongs to.
  trap 'rm -rf "$work"' RETURN

  docker save -o "$work/image.tar" "$image"
  tar -xf "$work/image.tar" -C "$work"

  layers=0
  while IFS= read -r layer; do
    layers=$((layers + 1))
    matches="$(tar -tf "$layer" 2>/dev/null | grep -E "$IDENTITY_PATTERN" || true)"
    if [[ -n "$matches" ]]; then
      finding "$image layer $(basename "$(dirname "$layer")") contains: $(printf '%s' "$matches" | tr '\n' ' ')"
    fi
  done < <(find "$work" \( -name 'layer.tar' -o -path '*/blobs/sha256/*' \) -type f | sort)

  (( layers > 0 )) || { finding "$image: no layers found — cannot prove absence"; return 0; }

  # Cross-check the flattened result as well. A layer check could miss an
  # image format this script does not parse; the running filesystem cannot.
  if docker run --rm --entrypoint /bin/sh "$image" -c \
       'test ! -e /etc/munge/munge.key && ! ls /etc/ssh/ssh_host_*_key 2>/dev/null'; then
    pass "$image: no identity material in $layers layer(s) or the flattened image"
  else
    finding "$image: identity material present in the flattened image"
  fi
}

for image in "$@"; do
  check_image "$image"
done

if (( FINDINGS > 0 )); then
  echo "RESULT: $FINDINGS finding(s). Identity material is delivered by a Warewulf runtime overlay at boot; it must never enter an image layer."
  exit 1
fi
echo "RESULT: no identity material in any image layer"
