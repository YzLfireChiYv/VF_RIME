# SPDX-License-Identifier: MIT
# Copyright (c) 2026 YzLfireChiYv
"""Opt-in source acquisition. Does not build, install or publish an input method."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

PACKAGE = Path(__file__).resolve().parents[1]

def run(*args):
    return subprocess.check_output(list(args), text=True, encoding="utf-8").strip()

def acquire(item, destination):
    if destination.exists() and any(destination.iterdir()):
        raise RuntimeError("Refusing to modify an existing directory: " + str(destination))
    destination.mkdir(parents=True, exist_ok=True)
    run("git", "init", str(destination))
    run("git", "-C", str(destination), "remote", "add", "origin", item["upstream"])
    run("git", "-C", str(destination), "fetch", "--depth", "1", "origin", item["base_commit"])
    run("git", "-C", str(destination), "checkout", "--detach", "FETCH_HEAD")
    if item.get("patch"):
        patch = PACKAGE / item["patch"]
        if hashlib.sha256(patch.read_bytes()).hexdigest() != item["patch_sha256"]:
            raise RuntimeError("Patch checksum mismatch: " + item["id"])
        run("git", "-C", str(destination), "apply", "--check", "--index", str(patch))
        run("git", "-C", str(destination), "apply", "--index", str(patch))
        tree = run("git", "-C", str(destination), "write-tree")
        if tree != item["patched_tree"]:
            raise RuntimeError("Patched tree differs: " + item["id"])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="explicitly allow Git downloads")
    parser.add_argument("--destination", type=Path, default=Path("source-preview"))
    parser.add_argument("--with-deps", action="store_true", help="fetch pinned upstream submodules too")
    args = parser.parse_args()
    lock = json.loads((PACKAGE / "SOURCE-LOCK.json").read_text("utf-8"))
    if not args.fetch:
        print("No downloads or writes. Add --fetch and choose a NEW destination.")
        for item in lock["repositories"]:
            print(item["id"], item["upstream"], item["base_commit"])
        return
    destination = args.destination.resolve()
    if destination.exists():
        raise RuntimeError("Destination must not already exist")
    destination.mkdir(parents=True)
    for item in lock["repositories"]:
        acquire(item, destination / item["checkout_path"])
    if args.with_deps:
        # Never recursively update Weasel's old librime gitlink over the patched core.
        run("git", "-C", str(destination / "weasel"), "submodule", "update", "--init", "--", "plum")
        run("git", "-C", str(destination / "weasel/librime"), "submodule", "update", "--init", "--recursive")
    print("Sources prepared only. Follow BUILDING.md; nothing was installed.")

if __name__ == "__main__":
    main()
