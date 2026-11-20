module LatePropagation

// Finds late propagation in OmniCCG's clone genealogy (ccg_data.xml):
// a change that leaves some copies of a clone class behind, followed later
// by a change to one of those lagging copies. Prints the cases and writes
// late-propagation.html (from report.html) next to ccg_data.xml.
//
//   java -jar rascal-shell-stable.jar LatePropagation <results-folder>   (run from patterns/)

import IO;
import List;
import String;
import lang::json::IO;
import lang::xml::DOM;

data Copy = copy(str file, int startLine, int endLine, str hash);
data Version = version(int nr, str commit, str evolution, str change, list[Copy] copies);
data Finding = finding(int diverged, int propagated);  // indices into the lineage's versions

// ---- Reading ccg_data.xml: one list of versions per lineage

list[list[Version]] readLineages(loc xml) {
    if (document(element(_, "lineages", lineages)) := parseXMLDOMTrim(readFile(xml))) {
        return [[readVersion(kids) | element(_, "version", kids) <- versions]
               | element(_, "lineage", versions) <- lineages];
    }
    throw "<xml> is not a ccg_data.xml from OmniCCG";
}

Version readVersion(list[Node] kids) {
    copies = [copy(relative(attr(s, "file")), toInt(attr(s, "startline")), toInt(attr(s, "endline")), attr(s, "hash"))
             | element(_, "class", cls) <- kids, element(_, "source", s) <- cls];
    return version(toInt(attr(kids, "nr")), attr(kids, "hash"), attr(kids, "evolution"), attr(kids, "change"), copies);
}

str attr(list[Node] kids, str name) = [t | attribute(_, n, t) <- kids, n == name][0];

// OmniCCG writes absolute paths into its workspace: keep the part inside the repository.
str relative(str path) = /cloned_repositories\/[^\/]+\/repo\/<rest:.*>$/ := path ? rest : path;

// ---- The pattern

set[str] hashes(Version v) = {c.hash | c <- v.copies};

// At an Inconsistent version some copies changed (the leading ones, with new
// code) and the others kept their code (the lagging ones). Late propagation:
// at the first later version where a lagging copy's code changes, the leading
// copies keep theirs, so only the copies left behind were changed.
list[Finding] latePropagation(list[Version] versions) {
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

// ---- Output

int main(list[str] args) {
    if (size(args) != 1) {
        println("usage: LatePropagation RESULTS_FOLDER  (the folder with ccg_data.xml)");
        return 2;
    }
    loc results = |file:///| + args[0];
    lineages = readLineages(results + "ccg_data.xml");
    found = [<l, f> | l <- lineages, f <- latePropagation(l)];

    for (<l, f> <- found) {
        d = l[f.diverged];
        p = l[f.propagated];
        println("Late propagation in <intercalate(", ", dup([c.file | c <- p.copies]))>");
        println("  diverged   at commit #<d.nr> (<d.commit>)");
        println("  caught up  at commit #<p.nr> (<p.commit>), <p.nr - d.nr> commit(s) later");
    }
    println("<size(found)> late propagation(s) in <size(lineages)> clone lineages");

    writeReport(results, size(lineages), found);
    return 0;
}

// The page is report.html with the findings as JSON in place of __DATA__.
void writeReport(loc results, int lineages, list[tuple[list[Version], Finding]] found) {
    report = ("results": results.path, "lineages": lineages, "findings": [
        ("diverged": f.diverged, "propagated": f.propagated, "versions": [
            ("nr": v.nr, "commit": v.commit, "copies": [
                ("file": c.file, "start": c.startLine, "end": c.endLine, "hash": c.hash) | c <- v.copies])
            | v <- l])
        | <l, f> <- found]);
    json = replaceAll(asJSON(report), "\</", "\<\\/");  // keep "\</script>" out of the page
    page = results + "late-propagation.html";
    writeFile(page, replaceFirst(readFile(|cwd:///report.html|), "__DATA__", json));
    println("Report: <page.path>");
}
