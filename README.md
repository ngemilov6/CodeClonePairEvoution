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
| `--first-parent` | follow only the main line, excluding side branches |
| `--java-only` | skip commits that do not change a `.java` file |

`--fixed-leaps` and `--from-commit` choose the commits first, then `--first` or `--last` keeps part of that choice. For example, `--fixed-leaps 10 --last 50` gives the newest 50 of every 10th commit.

Use `--first-parent` to avoid mixing side branches into the genealogy. Use
`--java-only` to skip commits that cannot affect Java clone detection. These
filters can be combined, and can also be combined with fixed leaps or commit
limits.

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
- **Several versions per commit:** OmniCCG sometimes records several versions of a lineage for one commit. The detection and the report use the last one per commit for late propagation and boiler-plating.

## Project map and how to change things

The layout separates the command-line pipeline from the Rascal pattern-analysis
project. Their entry points and metadata stay in their current locations:
`run.sh` and `install.sh` expect files at the project root, while Rascal expects
its sources, manifest, and Maven configuration under `patterns/`. Keeping these
framework-required paths avoids extra configuration and makes the run commands
easy to follow.

```text
CodeClonePairEvoution/
|-- README.md                 Setup, commands, patterns, limitations, and this guide
|-- install.sh                Creates the local runtime and builds NiCad
|-- run.sh                    Runs the Python stage, Rascal stage, and report opener
|-- clone_evo.py              Python entry point for running OmniCCG
|-- .gitignore                Excludes local environments, dependencies, and run output
|-- .vscode/
|   `-- settings.json         Optional editor setting; not needed by the pipeline
|-- vendor/                   Downloaded OmniCCG distribution (ignored by Git)
|   `-- OmniCCG-main/
|       `-- OmniCCG-CLI/      Python package and bundled NiCad used by this project
|-- .venv/                    Generated Python environment; created by install.sh
|-- rascal-shell-stable.jar   Downloaded Rascal runtime; created by install.sh
|-- patterns.html             Standalone report snapshot; not read by the pipeline
`-- patterns/                 Rascal project (keep its project structure)
    |-- pom.xml               Rascal/Maven dependency and build configuration
    |-- META-INF/
    |   `-- RASCAL.MF         Rascal project manifest; points to src/
    |-- report.html           HTML template used for generated reports
    |-- src/
    |   |-- Patterns.rsc      Rascal entry point: runs rules and writes report data
    |   |-- Genealogy.rsc     Parses OmniCCG XML and builds report data
    |   |-- LatePropagation.rsc
    |   |-- Boilerplate.rsc   Pattern detection rules
    `-- target/               Generated Rascal build output; do not edit by hand
```

`.venv/`, `rascal-shell-stable.jar`, and `vendor/` are local setup/runtime
contents, not application source. `install.sh` creates or downloads them. The
`target/` directory is generated build output. The top-level `patterns.html`
is not the report template: new run reports are written as
`<results-folder>/patterns.html` using `patterns/report.html`.

### What happens during a run

1. `run.sh` selects the local Python interpreter and calls `clone_evo.py`.
2. `clone_evo.py` makes a clean clone of the analyzed repository and configures
   OmniCCG's commit history selection.
3. OmniCCG uses the NiCad bundled under `vendor/OmniCCG-main/OmniCCG-CLI/` to
   detect clones at the selected revisions. It writes `ccg_data.xml` and
   `ccg_metrics.xml` to the results folder.
4. `run.sh` launches Rascal from `patterns/`. `Patterns.rsc` reads
   `ccg_data.xml` through `Genealogy.rsc`, then calls the detection rules.
5. `Genealogy.rsc` combines the findings with `patterns/report.html` to create
   `<results-folder>/patterns.html`; `run.sh` opens that report.

### Where to make changes

| If you want to change… | Start here |
|---|---|
| Setup, downloads, or NiCad build steps | `install.sh` |
| Pipeline orchestration or how the report is opened | `run.sh` |
| Repository validation, clone preparation, or commit selection | `clone_evo.py` |
| How OmniCCG XML is parsed or the report data is assembled | `patterns/src/Genealogy.rsc` |
| Late-propagation detection | `patterns/src/LatePropagation.rsc` |
| Boiler-plating detection | `patterns/src/Boilerplate.rsc` |
| Rascal rule invocation and console output | `patterns/src/Patterns.rsc` |
| Report layout and styling | `patterns/report.html` |
| Rascal dependencies or build setup | `patterns/pom.xml` and `patterns/META-INF/RASCAL.MF` |

Avoid editing `vendor/` for ordinary pipeline changes: it contains upstream
OmniCCG code and bundled NiCad. If an upstream fix is needed, document it as a
local patch so it can be reapplied after reinstalling the dependency.

To run only the Rascal stage manually, from this project directory:

```bash
cd patterns
java -jar ../rascal-shell-stable.jar Patterns <results-folder>
```
