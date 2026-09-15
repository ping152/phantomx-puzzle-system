#!/usr/bin/env python3
"""Fail-closed platform checks shared by the deployment scripts."""

from __future__ import annotations

import argparse
import json
import platform
import re
from pathlib import Path


ARCHITECTURES = {
    "amd64": "amd64",
    "x86_64": "amd64",
    "arm64": "arm64",
    "aarch64": "arm64",
}

DIGEST_IMAGE_RE = re.compile(r"^[^\s@:]+(?:/[^\s@:]+)+@sha256:[0-9a-f]{64}$")


def normalize_architecture(value: str) -> str:
    architecture = ARCHITECTURES.get(str(value).strip().lower())
    if architecture is None:
        raise ValueError(f"unsupported architecture: {value}")
    return architecture


def validate_hardware_owner(owner: str | None, expected: str) -> str:
    normalized_owner = str(owner or "").strip().lower()
    normalized_expected = str(expected).strip().lower()
    if normalized_expected not in ("windows", "jetson"):
        raise ValueError(f"unsupported hardware platform: {expected}")
    if normalized_owner != normalized_expected:
        raise ValueError(
            f"HARDWARE_OWNER must be '{normalized_expected}' for this command"
        )
    return normalized_owner


def validate_jetson(machine: str, tegra_release: str) -> str:
    architecture = normalize_architecture(machine)
    if architecture != "arm64":
        raise ValueError("Jetson deployment requires ARM64/AArch64")
    if not str(tegra_release).strip():
        raise ValueError("JetPack/L4T release was not detected")
    return architecture


def validate_release_image(image: str) -> str:
    normalized = str(image or "").strip().lower()
    if not DIGEST_IMAGE_RE.fullmatch(normalized):
        raise ValueError("release image must be pinned by sha256 digest")
    return normalized


def inspect_host(tegra_path: Path = Path("/etc/nv_tegra_release")) -> dict:
    machine = platform.machine()
    result = {
        "machine": machine,
        "architecture": normalize_architecture(machine),
        "tegra_release": "",
    }
    if tegra_path.exists():
        result["tegra_release"] = tegra_path.read_text(
            encoding="utf-8", errors="replace"
        ).strip()
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect-owner", choices=("windows", "jetson"))
    parser.add_argument("--owner")
    parser.add_argument("--require-jetson", action="store_true")
    parser.add_argument("--release-image", action="append", default=[])
    args = parser.parse_args()

    host = inspect_host()
    if args.expect_owner:
        validate_hardware_owner(args.owner, args.expect_owner)
    if args.require_jetson:
        validate_jetson(host["machine"], host["tegra_release"])
    for image in args.release_image:
        validate_release_image(image)
    print(json.dumps(host, ensure_ascii=True))


if __name__ == "__main__":
    main()
