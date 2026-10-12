# cluster-images-wip

Work in progress. Node images for the cluster built in
[`cluster-platform-wip`](https://github.com/dchau360/cluster-platform-wip).

Images are built as OCI containers, imported into Warewulf, and served to
UEFI nodes over the isolated provisioning segment. Per-node material — SSH
host keys, the Munge key, TLS — is **not** in an image. It arrives from a
Warewulf per-node overlay at boot.

> This repository is **public**. Every commit is world-readable forever.
> Read [Repository rules](#repository-rules) before your first commit.

## Quick start

```sh
cp lab/local.env.example lab/local.env   # fill in the host-specific values
make build                               # build every image definition
make build IMAGE=compute-base            # build one
make import                              # import into Warewulf
make lint                                # the same gates CI runs
```

`make help` lists everything.

## What is here today

| Working now | Where |
| --- | --- |
| `gitleaks` on the working tree and the full history | `.github/workflows/ci.yml` |
| Host-value hygiene, shared with the platform repo | `scripts/check-no-host-values.sh` |
| `yamllint`, `hadolint`, `shellcheck` | `.github/workflows/ci.yml` |
| `.gitignore` covering every image artefact shape | `.gitignore` |
| Build harness with versioned tags, push and timing hooks | `Makefile`, `scripts/build.sh` |
| `compute-base`: kernel, `wwinit` initramfs, management, inventory, stress tools | `images/compute-base/` |
| `compute-slurm`: the Slurm client and Munge, layered on the base | `images/compute-slurm/` |
| Publish to GHCR as public versioned packages, with run provenance | `.github/workflows/images.yml` |

### The image must boot, not just run

A Warewulf node boots in two stages with the `dracut` method: iPXE loads
`/boot/initramfs-<kver>.img` first, and that initramfs must contain
Warewulf's `wwinit` dracut module. The upstream distro image has neither a
kernel nor the module, so `compute-base` installs the kernel and builds the
initramfs with `--add wwinit`. Without it the node stops at
dracut's `Failed to mount /sysroot` — a failure this repository hit and now
verifies in the build with a `lsinitrd ... | grep wwinit` check.

`imgextract` is *not* used: it is a Warewulf patch to iPXE that the Ubuntu
`ipxe` package does not ship. The two-stage method needs no patched iPXE.

## Structure

```text
Makefile                      build / import / lint
lab/
  local.env.example           every host-specific variable, named and documented
  local.env                   the real values. UNTRACKED.
images/
  compute-base/               the common node image
    Containerfile             stubbed
    packages.txt              stubbed
    README.md
  compute-slurm/              compute image, Slurm client layered on
    Containerfile             stubbed
    README.md
overlays/
  generic/                    applies to every node, no secrets
  runtime/                    per-node material, templated by Warewulf
  README.md                   what may and may not go in an overlay
scripts/
  build.sh                    build one or every image, timed
  import.sh                   import built images into Warewulf
  lib/common.sh               config loading and change accounting
  lib/timing.sh               phase_begin / phase_end / timing_report
  check-no-host-values.sh     the leak gate. also runs in CI.
docs/
  image-design.md             layering, what belongs in an image
  overlays.md                 the secret boundary
```

## The secret boundary

This is the rule that matters most in this repository.

| Material | Where it comes from | In git? |
| --- | --- | --- |
| Packages, kernel, drivers, configuration | image build | yes, as definitions |
| Hostname, addresses, node-specific config | Warewulf runtime overlay | yes, as templates |
| SSH host keys | Warewulf runtime overlay, generated per node | **never** |
| Munge key | Warewulf runtime overlay, generated once per cluster | **never** |
| TLS certificates and keys | Warewulf runtime overlay | **never** |

An overlay **template** is tracked. An overlay **value** that is a secret
is not, and never was: it is generated on the lab host and delivered at
boot. `gitleaks` scans the full history on every push, so a key committed
and then removed still fails the build.

## Repository rules

The same non-negotiables as the platform repository. CI enforces all but
the last.

1. **This repository is public.** Every commit is world-readable forever.
2. **No host-specific value in a tracked file.** Not an address on the home
   LAN, not an SSH username, not a real MAC. Those live in `lab/local.env`,
   which is untracked. Example MACs are synthetic, from the
   locally-administered range.
3. **No secret in git.** See [the secret boundary](#the-secret-boundary).
4. **No lab state in git.** No image tarball, no squashfs, no kernel, no
   initramfs, no container layer cache.
5. **Nothing knows the node count.** An image is built once and serves N
   nodes; nothing in a build may depend on N.
6. **Every phase is timed and recorded.** `image-build` is a phase in the
   platform repository's timing stream, and `scripts/build.sh` records into
   the same format.
7. **DHCP and TFTP never run on an interface that can reach the home LAN.**
   Owned by the platform repository, repeated here because an image server
   is one careless bind away from breaking it.

## Licence

Not yet chosen. Treat as all rights reserved until it is.
