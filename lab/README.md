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

## Declaring a variable host-specific

Two files, and the gate requires them to agree. `lab/host-specific.vars` is a
tracked list of **names**, never values, and it is the authority.
`local.env.example` carries a matching inline tag so a reader sees the rule
next to the variable:

```sh
LAB_HOST_SSH=          # host-specific
#LAB_WSL_USER=         # host-specific
```

For every name on the list: the example may not assign it a value, and its
value from `local.env` is searched for in every tracked file with **no
exemption of any kind**.

The tag alone cannot be the authority. Typing a real value over a commented
declaration deletes the tag in the same edit, so a gate reading only tags
would fall silent on exactly the mistake it exists to catch. Reading the list,
that edit fails twice.

Full reasoning, and why a listed value should not be a short common word, is in
`lab/README.md` of the platform repository. Short version: `LAB_WSL_USER` is
left unset on the lab host, because `${LAB_WSL_USER:-${USER:-$(id -un)}}`
already gives the right answer there.

## Supplying local.env to CI

**Each repository has its own `lab/local.env` and its own secret.** They are
not interchangeable: this repository's file holds the `IMAGE_*` and
`WAREWULF_*` variables and none of the platform's networking ones, and the
"every variable in `local.env` is declared in the example" check fails if the
wrong file is loaded.

```sh
gh secret set LAB_LOCAL_ENV --repo dchau360/cluster-images-wip < lab/local.env
```

Fork pull requests get no secret. The pattern checks still run, so a leaked
address or a real MAC still fails the build from a fork.
