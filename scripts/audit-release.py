#!/usr/bin/env python3
"""Scan staged release trees for secrets, private paths, and accidental build output."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


EXCLUDED_NAMES = {".git", "build", "install", "log", "__pycache__", ".pytest_cache"}
SECRET_PATTERNS = {
    "GitHub token": re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}"),
    "private key": re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    "AWS access key": re.compile(r"AKIA[0-9A-Z]{16}"),
}
PRIVATE_PATHS = (
    re.compile(r"[A-Za-z]:\\Users\\[^\\\s]+", re.IGNORECASE),
    re.compile(r"/home/[^/\s]+"),
)
TEXT_SUFFIXES = {
    ".bash", ".c", ".cfg", ".cmake", ".cpp", ".h", ".hpp", ".json",
    ".md", ".py", ".ps1", ".repos", ".sh", ".srv", ".txt", ".xml",
    ".yaml", ".yml",
}


def scan(root: Path, max_bytes: int) -> list[str]:
    findings: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file() or any(part in EXCLUDED_NAMES for part in path.parts):
            continue
        if path.resolve() == Path(__file__).resolve():
            continue
        relative = path.relative_to(root)
        size = path.stat().st_size
        if size > max_bytes and path.suffix.lower() not in {".bin", ".hex", ".a"}:
            findings.append(f"large file ({size} bytes): {relative}")
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {
            "Dockerfile", "LICENSE", "Makefile", ".gitignore", ".dockerignore"
        }:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(text):
                findings.append(f"{label}: {relative}")
        for pattern in PRIVATE_PATHS:
            if pattern.search(text):
                findings.append(f"private absolute path: {relative}")
                break
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("roots", nargs="+", type=Path)
    parser.add_argument("--max-mib", type=int, default=20)
    args = parser.parse_args()
    findings: list[str] = []
    for root in args.roots:
        findings.extend(f"{root}: {item}" for item in scan(root.resolve(), args.max_mib * 1024 * 1024))
    if findings:
        print("\n".join(findings), file=sys.stderr)
        return 1
    print(f"Release audit passed for {len(args.roots)} root(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
