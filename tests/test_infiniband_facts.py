#!/usr/bin/env python3
"""Tests for the discovery image's InfiniBand GUID reader.

The lab has no InfiniBand hardware, so the sysfs tree here is synthetic: the
same files an IB-enabled kernel would expose, under a temporary directory.
The GUIDs are synthetic too. Nothing in this file has ever touched an HCA,
which is exactly the point — the reader is real, the hardware is not.

The script is loaded by path because it is shipped without a `.py` suffix.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "images" / "discovery" / "files" / "cluster-discovery"

_loader = importlib.machinery.SourceFileLoader("cluster_discovery", str(SCRIPT))
_spec = importlib.util.spec_from_loader("cluster_discovery", _loader)
cluster_discovery = importlib.util.module_from_spec(_spec)
_loader.exec_module(cluster_discovery)

GID0 = "fe800000000000000200004200000002"


class InfinibandFactsTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)

    def _port(self, device, port, gid, node, state="4: ACTIVE",
              rate="100 Gb/sec (4X EDR)", netdev=None):
        base = self.root / device
        (base / "ports" / port / "gids").mkdir(parents=True, exist_ok=True)
        (base / "node_guid").write_text(node + "\n")
        (base / "ports" / port / "gids" / "0").write_text(gid + "\n")
        (base / "ports" / port / "state").write_text(state + "\n")
        (base / "ports" / port / "rate").write_text(rate + "\n")
        if netdev:
            ndevs = base / "ports" / port / "gid_attrs" / "ndevs"
            ndevs.mkdir(parents=True, exist_ok=True)
            (ndevs / "0").write_text(netdev + "\n")

    def test_reads_every_port_with_its_guids(self):
        self._port("mlx5_0", "1", GID0, "0200004200000001", netdev="ib0")
        self._port("mlx5_1", "1", "00000000000000000000000000000000",
                   "0000000000000000", state="1: DOWN", rate="")
        ports = cluster_discovery.infiniband_facts(str(self.root))
        self.assertEqual([p["device"] for p in ports], ["mlx5_0", "mlx5_1"])
        first = ports[0]
        self.assertEqual(first["port"], "1")
        self.assertEqual(first["node_guid"], "0200:0042:0000:0001")
        self.assertEqual(first["port_guid"], "0200:0042:0000:0002")
        self.assertEqual(first["netdev"], "ib0")
        self.assertIn("EDR", first["rate"])

    def test_all_zero_gid_has_no_port_guid(self):
        self._port("mlx5_1", "1", "00000000000000000000000000000000",
                   "0000000000000000")
        port = cluster_discovery.infiniband_facts(str(self.root))[0]
        self.assertEqual(port["port_guid"], "")
        self.assertEqual(port["node_guid"], "")

    def test_missing_root_is_empty_not_an_error(self):
        self.assertEqual(
            cluster_discovery.infiniband_facts(str(self.root / "absent")), [])


if __name__ == "__main__":
    unittest.main()
