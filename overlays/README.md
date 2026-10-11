# overlays/

Warewulf overlays. This directory is where the secret boundary lives, so
the split is worth reading before adding a file.

| Tree | Applies to | May contain | Tracked |
| --- | --- | --- | --- |
| `generic/` | every node, identically | configuration with no node-specific and no secret content | yes |
| `runtime/` | each node, templated | `*.ww` templates that Warewulf renders per node | templates only |

## The rule

A **template** is tracked. A **rendered value that is a secret** is not,
and never was.

```text
overlays/runtime/etc/munge/munge.key.ww     <- tracked. a template.
overlays/runtime/etc/munge/munge.key        <- NEVER. that is the secret.
```

The secret itself is generated once on the lab host, kept outside both
repositories, and delivered to each node by Warewulf at boot. The same
holds for SSH host keys and TLS material.

`scripts/check-no-tracked-secrets.sh` enforces this: `overlays/runtime`
may track `*.ww` and documentation, nothing else. It runs in CI.

## Why by shape and not only by content

`gitleaks` catches secrets by content. A file named `munge.key` that is
still empty passes a content scan and fails this one, because the next
commit fills it in and the review does not notice. Both gates run.
