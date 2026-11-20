#!/usr/bin/env python3
"""Run OmniCCG, with its bundled NiCad 6.2, on every commit of a local Git repository.

    ./run.sh <repo-dir> [--out DIR] [--fixed-leaps N | --from-commit SHA] [--first N | --last N]

Writes ccg_data.xml and ccg_metrics.xml to <repo-dir>/clone-results/, or to --out DIR.
Your repository is never changed: OmniCCG works on a fresh clone of it.
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

import omniccg.core
from omniccg.cli_operations import write_xml_result
from omniccg.core import execute_omniccg


def clean_clone(repo: Path) -> Path:
    """A fresh clone of repo's committed history inside OmniCCG's workspace.

    Given the user's folder, OmniCCG would copy untracked files too and run
    `checkout -f` in the copy. The clone keeps the repository's name, which
    OmniCCG uses for its workspace.
    """
    dest = Path(omniccg.core.__file__).parent / "cloned_repositories" / repo.name / "source" / repo.name
    shutil.rmtree(dest, ignore_errors=True)
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "clone", "--quiet", str(repo), str(dest)], check=True)
    return dest


def limit_history(first, last) -> None:
    """Keep only the oldest `first` or newest `last` commits OmniCCG selected.

    OmniCCG writes its commit list to a history file (newest first), then reads
    it back. Trimming the file in between keeps OmniCCG's own selection.
    """
    if not first and not last:
        return
    original = omniccg.core.PrepareGitHistory

    def limited(ctx):
        original(ctx)
        hist = Path(ctx.paths.hist_file)
        lines = [line for line in hist.read_text().splitlines() if line.strip()]
        hist.write_text("\n".join(lines[-first:] if first else lines[:last]))

    omniccg.core.PrepareGitHistory = limited


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("repo", type=Path, help="the repository's top folder")
    parser.add_argument("--out", type=Path, help="results folder (default: <repo>/clone-results)")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--fixed-leaps", type=int, metavar="N", help="analyse every Nth commit")
    selection.add_argument("--from-commit", metavar="SHA", help="analyse the commits after SHA")
    limit = parser.add_mutually_exclusive_group()
    limit.add_argument("--first", type=int, metavar="N", help="only the oldest N of those commits")
    limit.add_argument("--last", type=int, metavar="N", help="only the newest N of those commits")
    args = parser.parse_args()

    repo = args.repo.expanduser().resolve()
    if not (repo / ".git").exists():
        parser.error(f"{repo} is not the top folder of a Git repository")
    out = (args.out.expanduser().resolve() if args.out else repo / "clone-results")

    user = {"clone_detector": "nicad"}
    if args.from_commit:
        user["from_a_specific_commit"] = args.from_commit
    else:
        user["from_first_commit"] = True
    if args.fixed_leaps:
        user["fixed_leaps"] = args.fixed_leaps

    limit_history(args.first, args.last)
    source = str(clean_clone(repo))
    # OmniCCG requires git_repository even when it copies from local_path.
    _, lineages, metrics = execute_omniccg(
        {"git_repository": source, "local_path": source, "user_settings": user})
    if lineages is None and metrics is None:
        print("OmniCCG found no clone genealogy.")
        return 0
    out.mkdir(parents=True, exist_ok=True)
    write_xml_result(lineages, metrics, str(out))
    print(f"Done: results in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
