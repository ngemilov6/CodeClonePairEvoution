module Patterns

// Detects the clone patterns in OmniCCG's ccg_data.xml, prints them, and writes
// patterns.html next to it.
//
//   java -jar rascal-shell-stable.jar Patterns <results-folder>   (run from patterns/)

import IO;
import List;
import Genealogy;
import LatePropagation;
import Boilerplate;

int main(list[str] args) {
    if (size(args) != 1) {
        println("usage: Patterns RESULTS_FOLDER  (the folder with ccg_data.xml)");
        return 2;
    }
    loc results = |file:///| + args[0];
    lineages = readLineages(results + "ccg_data.xml");

    late = [<l, f> | l <- lineages, f <- latePropagation(l)];
    println("Late propagation: <size(late)>");
    for (<l, f> <- late) {
        println("  <files(l[f.propagated])>");
        println("    diverged at commit #<l[f.diverged].nr> (<l[f.diverged].commit>), " +
                "caught up at #<l[f.propagated].nr> (<l[f.propagated].commit>)");
    }

    boiler = sort([l | l <- lineages, isBoilerplate(l)],
                  bool (Lineage a, Lineage b) { return changedTogether(a) > changedTogether(b); });
    println("Boiler-plating: <size(boiler)>");
    for (l <- boiler) {
        println("  <files(l[-1])>: changed together <changedTogether(l)> time(s)");
    }

    page = writeReport(results, size(lineages), [
        ("id": "late-propagation", "name": "Late propagation", "findings":
            [("versions": lineageJson(l), "diverged": f.diverged, "propagated": f.propagated) | <l, f> <- late]),
        ("id": "boilerplate", "name": "Boiler-plating", "findings":
            [("versions": lineageJson(l)) | l <- boiler])
    ]);
    println("\nIn <size(lineages)> clone lineages. Report: <page.path>");
    return 0;
}
