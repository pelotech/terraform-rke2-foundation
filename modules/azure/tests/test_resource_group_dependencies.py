"""Workload resources must wait for the group that the module creates."""

import os
from pathlib import Path
import re
import subprocess
import unittest


class ResourceGroupDependencies(unittest.TestCase):
    def test_workloads_wait_for_the_node_group(self):
        module = Path(__file__).resolve().parents[1]
        graph = subprocess.check_output(
            [os.environ.get("TERRAFORM_BINARY", "terraform"), "graph"],
            cwd=module,
            text=True,
        )
        edges = {}
        for source, target in re.findall(r'"([^"]+)"\s*->\s*"([^"]+)"', graph):
            edges.setdefault(source, set()).add(target)

        def dependencies(source):
            seen = set()
            pending = [source]
            while pending:
                node = pending.pop()
                if node not in seen:
                    seen.add(node)
                    pending.extend(edges.get(node, ()))
            return seen

        for resource in (
            "azurerm_key_vault.this",
            "azurerm_storage_account.oidc",
            "azurerm_storage_account.blob_csi",
            "azurerm_storage_account.etcd_backup",
            "azurerm_lb.api",
            "azurerm_lb.api_public",
            "azurerm_user_assigned_identity.server",
        ):
            with self.subTest(resource=resource):
                self.assertIn("azurerm_resource_group.nodes", dependencies(resource))


if __name__ == "__main__":
    unittest.main()
