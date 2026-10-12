# compute-base

The common node image. Everything every compute node needs, and nothing it
does not.

Stub. The image task owns the content; the build harness around it works
today:

```sh
make build IMAGE=compute-base
```

## What belongs here

- Kernel, init, dracut, and whatever is needed to boot from a Warewulf
  image.
- Network and management basics: SSH server, time sync, rsync.
- Anything shared by every node, so it is built once and served N times.
- The RDMA userspace (`rdma-core`, `libibverbs-utils`, `perftest`). The
  kernel module for Soft-RoCE (`rdma_rxe`) comes with the kernel; the
  libraries and the benchmark did not, and a node cannot install them for
  itself without a package mirror on the isolated segment.

## What does not

- Slurm. That is a layer, in `compute-slurm`.
- Any secret. SSH host keys, the Munge key and TLS material arrive from a
  Warewulf per-node overlay at boot. See `../../docs/overlays.md`.
- Anything node-specific. Hostname and addresses come from the overlay too.
