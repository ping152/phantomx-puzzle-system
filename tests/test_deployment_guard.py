import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "deployment_guard.py"
SPEC = importlib.util.spec_from_file_location("deployment_guard", MODULE_PATH)
deployment_guard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = deployment_guard
SPEC.loader.exec_module(deployment_guard)


class DeploymentGuardTest(unittest.TestCase):
    def test_normalizes_supported_architectures(self):
        self.assertEqual(deployment_guard.normalize_architecture("AMD64"), "amd64")
        self.assertEqual(deployment_guard.normalize_architecture("x86_64"), "amd64")
        self.assertEqual(deployment_guard.normalize_architecture("aarch64"), "arm64")
        self.assertEqual(deployment_guard.normalize_architecture("arm64"), "arm64")

    def test_rejects_unknown_architecture(self):
        with self.assertRaisesRegex(ValueError, "unsupported architecture"):
            deployment_guard.normalize_architecture("armv7l")

    def test_hardware_owner_is_mandatory_and_platform_specific(self):
        for owner in (None, "", "jetson"):
            with self.subTest(owner=owner):
                with self.assertRaises(ValueError):
                    deployment_guard.validate_hardware_owner(owner, "windows")
        self.assertEqual(
            deployment_guard.validate_hardware_owner("windows", "windows"),
            "windows",
        )

    def test_jetson_requires_arm64_and_tegra_release(self):
        self.assertEqual(
            deployment_guard.validate_jetson("aarch64", "# R36, REVISION: 4.0"),
            "arm64",
        )
        with self.assertRaisesRegex(ValueError, "ARM64"):
            deployment_guard.validate_jetson("x86_64", "# R36")
        with self.assertRaisesRegex(ValueError, "JetPack"):
            deployment_guard.validate_jetson("aarch64", "")

    def test_release_images_require_immutable_digest(self):
        valid = "ghcr.io/ping152/phantomx-puzzle-motion@sha256:" + "a" * 64
        self.assertEqual(deployment_guard.validate_release_image(valid), valid)
        for image in (
            "ghcr.io/ping152/phantomx-puzzle-motion:latest",
            "ghcr.io/ping152/phantomx-puzzle-motion:v0.1.0-rc1",
            "phantomx-puzzle-motion:dev",
        ):
            with self.subTest(image=image):
                with self.assertRaisesRegex(ValueError, "digest"):
                    deployment_guard.validate_release_image(image)


if __name__ == "__main__":
    unittest.main()
