# cluster-images-wip

**The root filesystems a diskless HPC node boots over the network.** Three OCI
images, built in GitHub Actions, published as **public** GHCR packages with one
immutable tag per commit, imported by Warewulf and served to UEFI nodes over an
isolated provisioning segment.

The cluster that boots them —  the network, the provisioning services, the
automation and the 1-to-N measurements — is
[`cluster-platform-wip`](https://github.com/dchau360/cluster-platform-wip).
**Start there** if you want the project; this repository is one half of it.

> This repository is **public**. Every commit is world-readable forever.
> Read [Repository rules](#repository-rules) before your first commit.

## What it builds

```text
  IMAGE_BASE (a pinned upstream tag, never a moving one)
        |
        v
  compute-base       kernel, dracut with the wwinit module, init, network,
        |            management, inventory, stress tools, the RDMA userspace.
        |            Shared by every node, so it is built once.
        |
        +--> compute-slurm   slurmd and Munge, and nothing else.
        |
        +--> discovery       pynetbox and the self-registration payload.
```

| Image | What boots it | Where |
| --- | --- | --- |
| `compute-base` | nothing on its own; it is the shared layer | [`images/compute-base/`](images/compute-base/) |
| `compute-slurm` | every provisioned compute node | [`images/compute-slurm/`](images/compute-slurm/) |
| `discovery` | a machine with no identity yet, for one boot | [`images/discovery/`](images/discovery/) |

The two node images are **layers** on `compute-base`, not separate builds.
That is not tidiness: `image-build` is a phase in the platform's measured
1-to-N curve, and if a Slurm change rebuilt the kernel, dracut and the
initramfs, the number would be measuring the wrong thing. See
[`docs/image-design.md`](docs/image-design.md).

The package set is a file — `images/*/packages.txt` — and not a `RUN` line, so
a reviewer can see what is in an image without reading shell.

## The image must boot, not just run

This is the thing that makes a Warewulf node image different from a container
image, and it cost two days to find.

A Warewulf node boots in two stages with the `dracut` method: iPXE loads
`/boot/initramfs-<kver>.img` first, and **that initramfs must contain
Warewulf's `wwinit` dracut module**. The upstream distro image has neither a
kernel nor the module, so `compute-base` installs the kernel and rebuilds the
initramfs with `--add wwinit`. Without it the node stops at dracut's
`Failed to mount /sysroot` and nothing explains why.

The build now asserts it with `lsinitrd ... | grep wwinit`, so the next person
gets a **build** failure instead of a **boot** failure.

`imgextract` is *not* used: it is a Warewulf patch to iPXE that the Ubuntu
`ipxe` package does not ship. The two-stage method needs no patched iPXE.

## How images are versioned in GHCR

```text
ghcr.io/dchau360/cluster-images-wip/compute-base:sha-<commit>     immutable
ghcr.io/dchau360/cluster-images-wip/compute-slurm:sha-<commit>    immutable
ghcr.io/dchau360/cluster-images-wip/discovery:sha-<commit>        immutable
ghcr.io/dchau360/cluster-images-wip/<image>:latest                moving
```

- **One tag per commit.** `.github/workflows/images.yml` derives the tag as
  `sha-<short commit>`, so an image traces back to the commit and the Actions
  run that built it, and **the previous tag stays importable**. `latest` is
  pushed too, and it is a convenience only: it names whatever was published
  most recently, so anything that has to name *one* build — a rollback, a
  rolling update, a measurement — uses the `sha-` tag.
- **Every run records provenance.** The workflow writes a job summary with the
  image, the tag and the registry digest, and uploads a `provenance.json` with
  the tag, the commit and the run URL.
- **The packages are public on purpose, not by accident.** A provisioned node
  must be able to fetch its image with no credential anywhere on it, and
  `wwctl image import docker://ghcr.io/...` is the one command that has to work
  on a bare server. A private package would force a registry token onto the
  provisioning host *and* onto every node, which is the thing this design
  refuses. The workflow sets the package visibility to public explicitly and
  warns loudly if it could not, because a private package surfaces as an
  import that mysteriously needs a credential.
- **A public image is only safe because of the secret boundary below.** No
  Munge key, no SSH host key, no TLS material is in any layer, and the build
  proves it before the images are reported as published —
  `scripts/check-no-identity-in-image.sh` runs over every built image, in CI,
  on the flattened filesystem as well as the layers.

## How rollback works

Rollback is a **tag change on the server**, not a rebuild. Nothing in this
repository is reverted, and nothing is pushed again:

```sh
# in cluster-platform-wip, on the lab host
make rollback TAG=sha-<previous>
```

That re-imports `docker://ghcr.io/dchau360/cluster-images-wip/compute-slurm:<tag>`
under a tag-specific Warewulf name, rebuilds the node's runtime overlays so the
node can report the tag it was provisioned from, restarts `warewulfd`, reboots
the node, and then **reads the tag back off the node's own serial console**
rather than trusting the server's view.

The tag must be pinned rather than moving, and that is the whole reason the
immutable `sha-` tag exists: `latest` names whatever was pushed most recently,
which is exactly what a rollback must not do.

Measured, with the console output, in
[the platform's drills](https://github.com/dchau360/cluster-platform-wip/blob/main/docs/acceptance-drills.md#image-rollback).

The same mechanism runs forward, one node at a time, with automatic rollback
under failure — `make rolling-update TAG=sha-<new>`. A rollout to an image with
no `slurmd` in it was tested: the first node's pull reported `failed`, the
harness put it back on the image it had, verified it, resumed it, and stopped
the rollout, while every job on the cluster completed. Recorded in
[the platform's evidence table](https://github.com/dchau360/cluster-platform-wip/blob/main/docs/node-self-configuration.md#evidence).

## Quick start

```sh
cp lab/local.env.example lab/local.env   # fill in the host-specific values
make build                               # build every image definition
make build IMAGE=compute-base            # build one
make import                              # import built images into Warewulf
make lint                                # the same gates CI runs
```

`make help` lists everything. Builds are local and tagged `latest` by default:
nothing from a developer's machine is pushed anywhere public. CI is what
publishes.

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
boot. Three gates enforce it and none of them substitutes for another:
`gitleaks` by content over the worktree *and the full history*, so a key
committed and then removed still fails; `check-no-tracked-secrets.sh` by
shape, so an empty `munge.key` placeholder fails too; and
`check-no-identity-in-image.sh` inside every built image.

Because no secret is in an image or in git, **rotating one is a lab-host
operation and a node reboot** — nothing is rebuilt and nothing is
re-committed. That property is the point of the boundary, not a side effect of
it. See [`docs/overlays.md`](docs/overlays.md).

## Structure

```text
Makefile                      build / import / lint
lab/
  local.env.example           every host-specific variable, named and documented
  local.env                   the real values. UNTRACKED.
images/
  compute-base/               the common node image
    Containerfile             kernel, dracut with wwinit, and why
    packages.txt              the package set, as a reviewable file
    files/node_exporter.service
    README.md
  compute-slurm/              Slurm client layered on the base
    Containerfile             Slurm built from the pinned upstream tarball
    packages.txt
    README.md
  discovery/                  live discovery boot, registers the node in NetBox
    Containerfile
    files/cluster-discovery   the scrape-and-register payload
    files/cluster-discovery.service
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
  check-no-identity-in-image.sh   no key material in any image layer
tests/
  test_infiniband_facts.py    the IB fact parsing, against synthetic GUIDs
docs/
  image-design.md             layering, what belongs in an image
  overlays.md                 the secret boundary
.github/workflows/
  ci.yml                      gitleaks, host values, yamllint, hadolint, shellcheck
  images.yml                  build, publish to GHCR, prove no identity, record provenance
```

## Why Slurm is built from source here

Configless `slurmd` fetches its configuration from the controller over Slurm's
own RPC, and that RPC works across at most three major releases. The head
node's controller is Ubuntu's 25.11; EPEL 9 ships 22.05. Taking the distro
package is therefore not a slower path to the same place — it is a path to a
node that cannot talk to the controller at all. `compute-slurm` builds the
pinned SchedMD release (`SLURM_VERSION`, `SLURM_SHA256` in the Containerfile),
and bumping the controller means bumping that version in the same change.

The image carries **no Slurm configuration file at all**: `slurm.conf` never
exists on a compute node. See the platform's
[`docs/node-self-configuration.md`](https://github.com/dchau360/cluster-platform-wip/blob/main/docs/node-self-configuration.md).

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

MIT — see [LICENSE](LICENSE).
