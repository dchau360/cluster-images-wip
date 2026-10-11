# lab/

Host-specific configuration. One file is tracked, one is not.

| File | Tracked | Contents |
| --- | --- | --- |
| `local.env.example` | yes | every variable, named and documented. Host values blank, lab values at their defaults. |
| `local.env` | **no** | the real values, on the lab host only. |

```sh
cp lab/local.env.example lab/local.env
$EDITOR lab/local.env
```

There is exactly one place a host-specific value may live. That is what
makes the CI leak gate meaningful: a value found anywhere else is a bug by
definition, not a judgement call.

`scripts/check-no-host-values.sh` is the gate, and it is the same script
the platform repository uses. It prints variable **names** only, never a
value, so the log of a failing run is itself safe to read in public.

To give CI the real file for exact matching:

```sh
gh secret set LAB_LOCAL_ENV --repo dchau360/cluster-images-wip < lab/local.env
```

Fork pull requests get no secret. The pattern checks still run, so a leaked
address or a real MAC still fails the build from a fork.
