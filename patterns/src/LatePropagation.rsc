module LatePropagation

// Late propagation: a change reaches some copies of a clone class but not the
// others, and the copies left behind are changed later.

import List;
import Genealogy;

data Finding = finding(int diverged, int propagated);  // indices into the lineage's versions

// At an Inconsistent version some copies changed (the leading ones, with new
// code) and the others kept their code (the lagging ones). Late propagation:
// at the first later version where a lagging copy's code changes, the leading
// copies keep theirs, so only the copies left behind were changed.
list[Finding] latePropagation(Lineage versions) {
    versions = perCommit(versions);
    findings = [];
    for (i <- [1..size(versions)], versions[i].change == "Inconsistent") {
        leading = hashes(versions[i]) - hashes(versions[i - 1]);
        lagging = hashes(versions[i]) & hashes(versions[i - 1]);
        for (j <- [i + 1..size(versions)], !(lagging <= hashes(versions[j]))) {
            if (versions[j].evolution != "Subtract" && leading <= hashes(versions[j])) {
                findings += finding(i, j);
            }
            break;
        }
    }
    return findings;
}
