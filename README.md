# Code clone pair evolution

Finds clone evolution patterns in the history of a Java repository.

1. [OmniCCG](https://doi.org/10.5281/zenodo.18344305), using its bundled NiCad 6.2, goes through the repository's commits and builds a **clone genealogy**: every clone class and how its copies changed from commit to commit.
2. A small Rascal project (`patterns/`) reads that genealogy and detects two patterns: **late propagation** and **boiler-plating**.
3. The results are printed and written to an HTML page, which opens in your browser.

## Setup (once)

Install these first:

| Tool | Notes |
|---|---|
| `python3` (3.9 or newer), `gcc`, `make`, `unzip`, `curl`, `git` | from your package manager |
| Java (11 or newer) | for Rascal |
| OpenTxl 11.3.7 (`txl` on your `PATH`) | for NiCad: https://github.com/CordyJ/OpenTxl/releases/tag/v11.3.7 |

On Windows, also install Git for Windows and Visual Studio Build Tools with the C/C++
command-line tools enabled. OpenTxl's `txlc` compiler requires them to build NiCad.

Then, in this folder:

```bash
./install.sh
```

This sets up everything else inside this folder. It's safe to run again.

- Downloads OmniCCG from Zenodo into `vendor/`. If you already have `OmniCCG-main.zip`, put it in `vendor/` first and it's used instead.
- Installs OmniCCG into a Python virtual environment, `.venv/`.
- Downloads `rascal-shell-stable.jar`.
- Builds OmniCCG's NiCad 6.2, with four small fixes so that it builds with GCC 15 and runs with OpenTxl 11.

## Run

```bash
./run.sh <repo-dir> [options]
```

Give the repository's top folder. It runs OmniCCG, then detects the patterns, prints them, and opens the report. You can also run it from inside the repository you want to analyse:

```bash
cd ~/code/dnsjava
../CodeClonePairEvoution/run.sh . --first 50
```

### Which commits

By default, every commit is analysed. That takes about 2–3 seconds per commit, so for a first try, limit the commits:

| Option | Analyses |
|---|---|
| `--first N` | the oldest N commits |
| `--last N` | the newest N commits |
| `--fixed-leaps N` | every Nth commit |
| `--from-commit SHA` | the commits after SHA |

`--fixed-leaps` and `--from-commit` choose the commits first, then `--first` or `--last` keeps part of that choice. For example, `--fixed-leaps 10 --last 50` gives the newest 50 of every 10th commit.

### Where the results go

They go to `<repo-dir>/clone-results/`, or to `--out DIR`:

| File | Contents |
|---|---|
| `ccg_data.xml` | OmniCCG's clone genealogy, which the patterns are detected from |
| `ccg_metrics.xml` | OmniCCG's metrics, such as clone density and how many lineages are still alive |
| `patterns.html` | the report |

Git will list `clone-results/` in the analysed repository as untracked. Add it to that repository's `.gitignore` if you don't want to see it.

### Rerun only the pattern detection

OmniCCG is the slow part, and its result is saved. To detect the patterns again on that result, for example after changing a rule in `patterns/src/`:

```bash
./run.sh <repo-dir> --patterns-only
./run.sh <repo-dir>/clone-results --patterns-only    # or give the results folder itself
./run.sh <repo-dir> --out DIR --patterns-only        # if the full run used --out
```

This takes a few seconds. A full run deletes the previous `ccg_data.xml` first, so `--patterns-only` never works on a result from an earlier run.

## The patterns

OmniCCG groups cloned code into **clone classes**: sets of copies NiCad finds similar. It follows each class across commits as a **lineage**. Each of its copies has a hash of its code, so a copy whose hash changes has changed.

### Late propagation

A change reaches some copies of a clone class but not the others, and the copies left behind are changed later. Until then the copies behave differently, which is how clones lead to bugs (Aversano et al., CSMR 2007; Thummalapenta et al., EMSE 2010).

It's detected when, at some commit, some copies changed and the others kept their code. At a later commit the copies left behind change, while the ones that changed earlier keep their new code.

### Boiler-plating

These are copies the language can't express once, kept in step by hand: Kapser and Godfrey's "boiler-plating due to language in-expressiveness" (WCRE 2006). Such copies are "closely located … in the same file or in the same subsystem", differ a little (for example only in a data type), and "will be expected to evolve very closely".

It's detected when all of these hold:
- All copies are in the same directory, throughout the lineage.
- At the latest commit, the copies aren't identical.
- They changed together at least once, and never some of them alone.

### Reading the report

The report has one section per pattern and one card per case. Each line on a card is one copy, followed across the commits where its clone class changed:
- A filled dot means the copy's code changed at that commit; a hollow dot means it didn't.
- For late propagation, an amber band runs from the commit where the copies diverged to the one where they caught up, and the copy left behind is dashed.
- For boiler-plating, green bands mark the commits where all copies changed together.

Hover over a dot for the file, lines and commit.

## Limitations

- **What OmniCCG analyses:** only `.java` files. It skips files with "test" in their name, and only committed history counts. It walks every branch (`git log --all`), and it works on a fresh clone, so your repository isn't changed.
- **No method names:** OmniCCG's output has none, so boiler-plating can't check the paper's "very similar names", and "same subsystem" is approximated by "same directory".
- **Copies that become identical:** when a late propagation makes the copy left behind identical to the other copy, OmniCCG records no change, so that case can't be detected.
- **Unproven catch-up:** the genealogy has no code, so it can't be checked that the late change was the *same* change.
- **Several versions per commit:** OmniCCG sometimes records several versions of a lineage for one commit. The detection and the report use the last one per commit.

## Layout

```
install.sh          setup
run.sh              OmniCCG, then the pattern detection, then the report
clone_evo.py        runs OmniCCG on a fresh clone of the repository (--first/--last, --out)
patterns/           the Rascal project
  src/Patterns.rsc        entry point: runs the detections, prints them, writes the report
  src/Genealogy.rsc       reads ccg_data.xml; writes patterns.html from report.html
  src/LatePropagation.rsc the late propagation rule
  src/Boilerplate.rsc     the boiler-plating rule
  report.html             the report's template
```

To run the Rascal part by hand: `cd patterns && java -jar ../rascal-shell-stable.jar Patterns <results-folder>`.
