#!/usr/bin/env bash
#
# The secret boundary, as a gate.
#
# gitleaks catches secrets by content. This catches them by shape, which is
# the other half: a tracked file whose NAME says it holds key material is a
# finding even if the file is empty or still a placeholder, because the next
# commit will fill it in and the review will not notice.
#
# Overlay templates are tracked. Overlay secrets are not, and never were:
# they are generated on the lab host and delivered by Warewulf at boot.

set -euo pipefail

# Needs bash 4 (mapfile, associative arrays). Say so plainly: a gate that dies
# with "mapfile: command not found" looks broken rather than unsupported.
# macOS ships bash 3.2; use `brew install bash`.
if (( BASH_VERSINFO[0] < 4 )); then
  echo "error: bash 4 or newer required, found $BASH_VERSION" >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)"

findings=0
finding() { findings=$((findings + 1)); printf 'FAIL %s\n' "$*"; }
pass()    { printf 'ok   %s\n' "$*"; }

# Names that may never be tracked, whatever they contain.
FORBIDDEN_NAMES=(
  'munge\.key$'
  'ssh_host_.*'
  'id_rsa($|\.)'
  'id_ed25519($|\.)'
  'id_ecdsa($|\.)'
  '\.pem$'
  '\.p12$'
  '\.jks$'
  '\.key$'
  '\.vault$'
  'vault-pass'
)

echo "== check 1: no file whose name says it holds key material"
mapfile -t TRACKED < <(git ls-files)
for pat in "${FORBIDDEN_NAMES[@]}"; do
  for f in "${TRACKED[@]}"; do
    if [[ "$f" =~ $pat ]]; then
      finding "tracked file matches forbidden name pattern /$pat/: $f"
    fi
  done
done
(( findings > 0 )) || pass "no tracked file is named like key material"

echo
echo "== check 2: no image artefact is tracked"
art=0
for f in "${TRACKED[@]}"; do
  case "$f" in
    *.tar|*.tar.gz|*.tar.zst|*.squashfs|*.img|*.qcow2|*.iso|*.cpio|*.cpio.gz|\
    *.initramfs|*.initrd|vmlinuz*|initramfs*|initrd*|*.sif|*.oci)
      finding "tracked image artefact: $f"; art=1 ;;
  esac
done
(( art == 1 )) || pass "no image artefact is tracked"

echo
echo "== check 3: the runtime overlay tree holds templates only"
if [[ -d overlays/runtime ]]; then
  bad=0
  while IFS= read -r f; do
    # A template is the mechanism for delivering a secret. A rendered file
    # in this tree is the secret itself.
    case "$f" in
      *.ww|*.md|*/.gitkeep) ;;
      *) finding "overlays/runtime may hold templates (*.ww) only: $f"; bad=1 ;;
    esac
  done < <(git ls-files overlays/runtime)
  (( bad == 1 )) || pass "overlays/runtime holds templates only"
else
  pass "overlays/runtime does not exist yet"
fi

echo
if (( findings > 0 )); then
  echo "RESULT: $findings finding(s). Key material comes from a Warewulf overlay at boot, never from git."
  exit 1
fi
echo "RESULT: no secret material is tracked"
