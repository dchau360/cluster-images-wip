# compute-slurm

`compute-base` with the Slurm client layered on. Stub; the Slurm task owns
the content.

Built as a layer, not as a second full image, so the common parts are built
once. That keeps the measured `image-build` phase honest about what is
actually being rebuilt when only the Slurm layer changes.

The Munge key is not in this image. It is generated once per cluster and
delivered per node by a Warewulf runtime overlay at boot.
