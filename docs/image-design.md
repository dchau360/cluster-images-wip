# Image design

## Layers, not images

```text
  IMAGE_BASE (pinned upstream)
        |
        v
  compute-base        kernel, init, network, management. shared by every node.
        |
        +--> compute-slurm    the Slurm client, and nothing else.
        |
        +--> discovery        pynetbox + the self-registration payload.
```

The two node images are layers on `compute-base` for the same two reasons.
`compute-slurm` layers the Slurm client; `discovery` layers `pynetbox` and
the `cluster-discovery` payload. Neither rebuilds the kernel, dracut or the
`wwinit` initramfs, so a change to either does not move the `image-build`
phase for the base.

**Honest measurement.** `image-build` is a phase in the project's 1-to-N
curve. If a Slurm change rebuilt the whole node image, the phase would
report the cost of rebuilding everything and the number would mean nothing.

**Readable diffs.** The package set is a file, `packages.txt`, not a `RUN`
line. A reviewer can see what the image contains without reading shell.

## The base is pinned

`IMAGE_BASE` in `lab/local.env.example` names a specific tag. An unpinned
base makes a build unreproducible: two runs a week apart would not be
measuring the same thing, and the curve would be noise.

## What belongs in an image

| Belongs | Does not |
| --- | --- |
| Kernel, dracut, init | Hostname, addresses |
| Packages and drivers | SSH host keys |
| Configuration identical on every node | The Munge key |
| Anything built once and served N times | TLS certificates and keys |

The right-hand column is per-node, per-cluster, or secret. All of it comes
from a Warewulf overlay at boot. See [`overlays.md`](overlays.md).

## Nothing knows the node count

An image is built once and serves N nodes. No build step may depend on N.
That is what makes `N=2` and `N=4` differ only in how many nodes fetch the
same image, which is exactly the thing the curve is measuring.
