#!/usr/bin/env python3
"""Select packaging and VM checks for pull requests."""

import argparse
import os
import subprocess
from pathlib import Path

BUILD_DIRECTORIES = {
    ".github",
    "assets",
    "control",
    "integration_test",
    "lib",
    "linux",
    "packaging",
    "telemetry",
    "test",
    "tool",
}
BUILD_FILES = {
    ".metadata",
    "analysis_options.yaml",
    "flake.nix",
    "flake.lock",
    "pubspec.yaml",
    "pubspec.lock",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
}


def needs_build(paths: list[str]) -> bool:
    return any(
        path in BUILD_FILES or path.split("/", 1)[0] in BUILD_DIRECTORIES
        for path in paths
    )


def changed_paths(base: str, head: str) -> list[str]:
    # Show both sides of renames so moving build code into docs still qualifies.
    result = subprocess.run(
        ["git", "diff", "--name-only", "--no-renames", "-z", base, head, "--"],
        check=True,
        stdout=subprocess.PIPE,
    )
    return [os.fsdecode(path) for path in result.stdout.split(b"\0") if path]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="PR base commit; omit to run every check")
    parser.add_argument("--head", default="HEAD")
    args = parser.parse_args()
    required = args.base is None or needs_build(changed_paths(args.base, args.head))
    result = f"build={'true' if required else 'false'}\n"
    print(result, end="")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a") as stream:
            stream.write(result)


if __name__ == "__main__":
    main()
