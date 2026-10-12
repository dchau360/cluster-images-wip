# Discovery image

An ephemeral boot whose only job is to make a machine describe itself.

A node that PXE-boots this image has no identity yet: no NetBox device, no
address in the source of truth. `cluster-discovery` measures the machine —
DMI serial, CPU, memory, every NIC MAC, every disk, GPU presence — writes it
to NetBox with `pynetbox`, creates one interface per real NIC, claims the
address the node actually holds as an IPAM address record, and sets it as the
device's primary IPv4 address.

The image is `compute-base` plus `pynetbox` plus one systemd unit. It is a
layer for the same reason `compute-slurm` is: the kernel, dracut and the
Warewulf `wwinit` initramfs are the expensive, shared parts, and a discovery
change must not rebuild them.

## What it is not

* It does not hold a credential. The NetBox endpoint and token arrive at
  boot in a Warewulf runtime overlay, exactly like the Munge key and the SSH
  host keys. There is no NetBox token in this image and none in git.
* It does not touch the installed disk. Discovery is a live boot; the
  provisioned image is a later boot.
* It does not decide the node's final hostname. It reads the name the
  provisioning system already gave it, and falls back to the DMI serial for
  a machine that is defined nowhere.

## Configuration

`cluster-discovery.service` reads `/etc/cluster-discovery/netbox.env`:

```sh
NETBOX_URL=http://<provisioning-gateway>:8001
NETBOX_TOKEN=<delivered by the cluster-discovery overlay>
```

It writes these custom fields on the device (all text, so the same script
works against any NetBox version):

| Field | Contents |
| --- | --- |
| `discovery_status` | `discovering` while running, `complete` when done |
| `discovered_at` | UTC timestamp of the scrape |
| `discovered_manufacturer` | DMI system vendor |
| `discovered_product` | DMI product name |
| `discovered_serial` | DMI product serial |
| `discovered_uuid` | DMI product UUID |
| `discovered_bios` | BIOS version |
| `discovered_address` | the address the node holds |
| `discovered_cpu_model` | CPU model name |
| `discovered_cpu_count` | logical processor count |
| `discovered_memory_mib` | installed memory, MiB |
| `discovered_disk_count` | number of block devices |
| `discovered_disk_total_gb` | total block-device capacity |
| `discovered_gpu_count` | number of display-class PCI devices |
| `discovered_gpu_models` | their vendor and device strings |
| `discovered_nic_macs` | every non-loopback MAC |

## Build and test

```sh
make build IMAGE=discovery           # build
make check-image-identity IMAGE_REF=<ref>   # no identity material in a layer
```

The images workflow builds and publishes it with every other image, and the
layer check runs over it before it is reported as published.
