# Overlays and the secret boundary

An image is world-readable the moment it is served. A shared secret inside
one is a shared secret in every node that boots it, and in anything else
that can reach the image server. So no secret is ever in an image, and no
secret is ever in git.

## Where each kind of material comes from

| Material | Source | Tracked |
| --- | --- | --- |
| Packages, kernel, drivers | image build | yes, as definitions |
| Configuration identical on every node | `overlays/generic/` | yes |
| Hostname, addresses, node-specific config | `overlays/runtime/*.ww` | yes, as templates |
| SSH host keys | generated per node, delivered at boot | **never** |
| Munge key | generated once per cluster, delivered at boot | **never** |
| TLS certificates and keys | generated on the lab host, delivered at boot | **never** |

## Template, not value

```text
overlays/runtime/etc/munge/munge.key.ww     tracked. a template.
overlays/runtime/etc/munge/munge.key        NEVER. that is the secret.
```

Warewulf renders the template per node at boot and writes the result into
the node's runtime overlay. The secret itself lives on the lab host,
outside both repositories, with restrictive permissions.

## Two gates, by content and by shape

`gitleaks` catches secrets by content: it reads the working tree and the
full git history on every push, so a key committed and then removed still
fails the build.

`scripts/check-no-tracked-secrets.sh` catches them by shape: a tracked file
named `munge.key`, `ssh_host_rsa_key` or `*.pem` is a finding whatever it
contains. An empty placeholder passes a content scan and fails this one,
which matters because the commit that fills it in is the one nobody reviews
carefully.

Both run in CI. Neither is a substitute for the other.

## Rotation

Because no secret is in an image or in git, rotating one is a lab-host
operation and a node reboot. Nothing is rebuilt and nothing is
re-committed. That property is the point of the boundary, not a side
effect of it.
