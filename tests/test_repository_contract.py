import unittest
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RepositoryContractTest(unittest.TestCase):
    def test_required_release_files_exist(self):
        required = [
            ".env.example",
            "compose.yaml",
            "compose.windows-hardware.yaml",
            "compose.jetson-hardware.yaml",
            "docker/motion.Dockerfile",
            "docker/vision.Dockerfile",
            "scripts/setup-windows.ps1",
            "scripts/test-windows-sim.ps1",
            "scripts/start-windows-hardware.ps1",
            "scripts/stop-windows.ps1",
            "scripts/setup-jetson.sh",
            "scripts/test-jetson-sim.sh",
            "scripts/start-jetson-hardware.sh",
            "scripts/stop-jetson.sh",
            "scripts/audit-release.py",
            "docs/DEPLOYMENT_WINDOWS_JETSON.md",
            "repositories.lock.yaml",
        ]
        missing = [path for path in required if not (ROOT / path).is_file()]
        self.assertEqual(missing, [])

    def test_dockerfiles_target_humble_without_latest(self):
        for relative_path in ("docker/motion.Dockerfile", "docker/vision.Dockerfile"):
            with self.subTest(path=relative_path):
                text = (ROOT / relative_path).read_text(encoding="utf-8")
                self.assertIn("ARG ROS_DISTRO=humble", text)
                self.assertIn("FROM ros:${ROS_DISTRO}-ros-base", text)
                self.assertNotIn(":latest", text)

    def test_hardware_scripts_fail_closed_on_owner(self):
        expectations = {
            "scripts/start-windows-hardware.ps1": "--expect-owner windows",
            "scripts/start-jetson-hardware.sh": "--expect-owner jetson",
        }
        for relative_path, marker in expectations.items():
            with self.subTest(path=relative_path):
                text = (ROOT / relative_path).read_text(encoding="utf-8")
                self.assertIn("deployment_guard.py", text)
                self.assertIn(marker, text)

    def test_install_and_simulation_scripts_never_start_hardware(self):
        for relative_path in (
            "scripts/setup-windows.ps1",
            "scripts/test-windows-sim.ps1",
            "scripts/setup-jetson.sh",
            "scripts/test-jetson-sim.sh",
        ):
            with self.subTest(path=relative_path):
                text = (ROOT / relative_path).read_text(encoding="utf-8").lower()
                self.assertNotIn("start-windows-hardware", text)
                self.assertNotIn("start-jetson-hardware", text)
                self.assertNotIn("profile hardware", text)

    def test_stop_scripts_attempt_controller_stop_first(self):
        for relative_path in (
            "scripts/stop-windows.ps1",
            "scripts/stop-jetson.sh",
        ):
            with self.subTest(path=relative_path):
                text = (ROOT / relative_path).read_text(encoding="utf-8")
                stop_index = text.index("STOP")
                down_index = text.index("down")
                self.assertLess(stop_index, down_index)

    def test_phantomx_snapshot_is_content_pinned(self):
        text = (ROOT / "repositories.lock.yaml").read_text(encoding="utf-8")
        match = re.search(r"snapshot_sha256:\s*([0-9a-f]{64})", text)
        self.assertIsNotNone(match)

    def test_multiarch_publish_uses_native_runners(self):
        text = (ROOT / ".github/workflows/publish-images.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("runner: ubuntu-22.04", text)
        self.assertIn("runner: ubuntu-24.04-arm", text)
        self.assertIn("platform: linux/amd64", text)
        self.assertIn("platform: linux/arm64", text)
        self.assertIn("docker buildx imagetools create", text)
        self.assertNotIn("setup-qemu-action", text)


if __name__ == "__main__":
    unittest.main()
