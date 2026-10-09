"""Run the install helper with controlled OS commands; never touch a live host."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "templates/install-rke2.sh"
VERSION = "v1.37.1+rke2r1"


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        self.calls = self.root / "calls"
        self.command("modprobe", 'exit "${MISSING_KERNEL:-0}"')
        self.command("dnf", 'echo "dnf $*" >> "$CALLS"')
        self.command("curl", 'echo "curl $*" >> "$CALLS"; cat "$ONLINE_INSTALLER"')
        self.command("rke2", 'echo "rke2 version ${ACTUAL_VERSION:-v1.37.1+rke2r1} (fixture)"')
        self.installer = self.artifacts / "install.sh"
        self.installer.write_text(
            '#!/bin/sh\n'
            'printf "install %s %s %s\\n" "$INSTALL_RKE2_TYPE" "$INSTALL_RKE2_VERSION" "${INSTALL_RKE2_ARTIFACT_PATH:-online}" >> "$CALLS"\n'
        )

    def command(self, name, body):
        p = self.bin / name
        p.write_text("#!/bin/sh\n" + body + "\n")
        p.chmod(0o755)

    def run_install(self, role="server", offline=True, **extra):
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                   ROLE=role, RKE2_VERSION=VERSION, INSTALL_URL="https://install.example/rke2",
                   INSTALL_ARTIFACT_PATH=str(self.artifacts) if offline else "",
                   CALLS=str(self.calls), ONLINE_INSTALLER=str(self.installer), **extra)
        result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
        calls = self.calls.read_text() if self.calls.exists() else ""
        return result, calls

    def test_local_install_for_server_and_agent_never_uses_network(self):
        for role in ("server", "agent"):
            with self.subTest(role=role):
                result, calls = self.run_install(role)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"install {role} {VERSION} {self.artifacts}", calls)
                self.assertNotIn("curl ", calls)
                self.assertNotIn("dnf ", calls)

    def test_missing_local_installer_fails_without_network_fallback(self):
        self.installer.unlink()
        result, calls = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("install.sh", result.stderr)
        self.assertEqual(calls, "")

    def test_missing_kernel_dependency_fails_offline_without_dnf(self):
        result, calls = self.run_install(MISSING_KERNEL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("kernel", result.stderr.lower())
        self.assertEqual(calls, "")

    def test_wrong_baked_version_fails_before_service_start(self):
        result, _ = self.run_install(ACTUAL_VERSION="v1.36.5+rke2r1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("version", result.stderr.lower())

    def test_online_install_preserves_mirror_and_running_kernel_package(self):
        result, calls = self.run_install(offline=False, MISSING_KERNEL="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dnf install -y kernel-modules-extra-", calls)
        self.assertIn("curl -sfL https://install.example/rke2", calls)
        self.assertIn(f"install server {VERSION} online", calls)


if __name__ == "__main__":
    unittest.main()
