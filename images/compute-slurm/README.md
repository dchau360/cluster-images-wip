# compute-slurm

`compute-base` with the Slurm client layered on: `slurmd` and Munge.

Slurm is built from the pinned upstream release (`SLURM_VERSION`,
`SLURM_SHA256` in the Containerfile), not taken from EPEL. The node runs
configless — `slurmd --conf-server` fetches its configuration from the head
node's `slurmctld` — and that RPC only works across at most three major
releases. EPEL 9 ships 22.05; the controller runs 25.11. Bumping the
controller means bumping `SLURM_VERSION` here in the same change.

The image carries no Slurm configuration file at all. `slurm.conf` never
exists on a compute node; see `cluster-platform-wip`'s
`docs/node-self-configuration.md`.

Built as a layer, not as a second full image, so the common parts are built
once. That keeps the measured `image-build` phase honest about what is
actually being rebuilt when only the Slurm layer changes.

The Munge key is not in this image. It is generated once per cluster and
delivered per node by a Warewulf runtime overlay at boot.
