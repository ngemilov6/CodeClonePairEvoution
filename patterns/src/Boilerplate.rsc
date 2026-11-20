module Boilerplate

// Boiler-plating due to language in-expressiveness (Kapser and Godfrey,
// "Cloning Considered Harmful" Considered Harmful, 2006): copies that are
// "closely located in the software system, either in the same file or in the
// same subsystem" and "will be expected to evolve very closely". Their code
// differs a little, for example only in a data type.
//
// From OmniCCG's genealogy alone: all copies, at every version, are in the
// same directory; at the latest version they are not identical; and they
// changed together at least once and never some of them alone. (Similar method names, the paper's other sign,
// are not in OmniCCG's output.)

import List;
import Set;
import Genealogy;

bool isBoilerplate(Lineage lineage) {
    versions = perCommit(lineage);
    changes = [change(versions[i - 1], versions[i]) | i <- [1..size(versions)]];
    return size({directory(c.file) | v <- versions, c <- v.copies}) == 1
        && size(hashes(versions[-1])) > 1
        && "Consistent" in changes
        && "Inconsistent" notin changes;
}

// The number of commits where every copy changed.
int changedTogether(Lineage lineage) {
    versions = perCommit(lineage);
    return size([i | i <- [1..size(versions)], change(versions[i - 1], versions[i]) == "Consistent"]);
}
