#!/usr/bin/env python3
"""Run OmniCCG, with its bundled NiCad 6.2, on every commit of a local Git repository.

    ./run.sh <repo-dir> [--out DIR] [--fixed-leaps N | --from-commit SHA] [--first N | --last N] [--first-parent] [--java-only]

Writes ccg_data.xml and ccg_metrics.xml to <repo-dir>/clone-results/, or to --out DIR.
Your repository is never changed: OmniCCG works on a fresh clone of it.
"""
import argparse
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
    omniccg.core.safe_rmtree(dest)
    if dest.exists():
        raise RuntimeError(
            f"Could not remove stale OmniCCG clone directory: {dest}\n"
            "Close any process using it and run the command again."
        )
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "clone", "--quiet", str(repo), str(dest)], check=True)
    return dest


def configure_history(first, last, first_parent=False, java_only=False) -> None:
    """Filter the commit list written by OmniCCG before it prepares sources."""
    if not first and not last and not first_parent and not java_only:
        return
    original = omniccg.core.PrepareGitHistory

    def limited(ctx):
        # The custom options need to be applied before fixed-leap and size limits.
        # OmniCCG otherwise generates --all history, mixing merge branches.
        if first_parent or java_only:
            s, p = ctx.settings, ctx.paths
            rev = "HEAD"
            if s.specific_commit:
                rev = f"{s.specific_commit}..HEAD"

            command = ["git", "-C", p.repo_dir, "log", "--date=short", "--pretty=format:%H%x09%ad%x09%an%x09%s"]
            if first_parent:
                command.append("--first-parent")
            command.append(rev)
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            commits = [line for line in result.stdout.splitlines() if line.strip()]

            if java_only:
                filtered = []
                for line in commits:
                    sha = line.split("\t", 1)[0]
                    changed = subprocess.run(
                        ["git", "-C", p.repo_dir, "diff-tree", "--root", "-m",
                         "--no-commit-id", "--name-only", "-r", sha],
                        check=True, capture_output=True, text=True,
                    ).stdout
                    if any(path.strip().lower().endswith(".java") for path in changed.splitlines()):
                        filtered.append(line)
                commits = filtered

            if s.use_leaps and int(s.commit_leaps or 0) > 1:
                step = int(s.commit_leaps)
                commits = [line for i, line in enumerate(commits) if i % step == 0]

            lines = []
            for line in commits:
                sha, date, author, *summary = line.split("\t")
                lines.append(f"{sha[:7]} {date} {author} {' '.join(summary)}")
            Path(p.hist_file).write_text("\n".join(lines), encoding="utf-8")
            print(f"Wrote {len(lines)} commit(s) to {p.hist_file}")
        else:
            original(ctx)

        hist = Path(ctx.paths.hist_file)
        lines = [line for line in hist.read_text(encoding="utf-8").splitlines() if line.strip()]
        hist.write_text(
            "\n".join(lines[-first:] if first else lines[:last]),
            encoding="utf-8",
        )

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
    parser.add_argument("--first-parent", action="store_true",  help="follow only the first-parent/mainline history")
    parser.add_argument("--java-only", action="store_true", help="skip commits that do not change any Java file")
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

    configure_history(args.first, args.last, args.first_parent, args.java_only)
    for old in ("ccg_data.xml", "ccg_metrics.xml"):  # don't leave a previous run's result behind
        (out / old).unlink(missing_ok=True)
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
