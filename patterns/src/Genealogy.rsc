module Genealogy

// Reading OmniCCG's clone genealogy (ccg_data.xml) and writing the HTML report.

import IO;
import List;
import String;
import lang::json::IO;
import lang::xml::DOM;

data Copy = copy(str file, int startLine, int endLine, str hash);
data Version = version(int nr, str commit, str evolution, str change, list[Copy] copies);
alias Lineage = list[Version];  // one clone class followed over the commits where it changed

list[Lineage] readLineages(loc xml) {
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

str directory(str file) = /^<d:.*>\/[^\/]*$/ := file ? d : ".";

// The code of the copies in a version, as OmniCCG's hashes of it.
set[str] hashes(Version v) = {c.hash | c <- v.copies};

// OmniCCG can record several versions of a lineage for one commit; keep the last one.
Lineage perCommit(Lineage l) = [l[i] | i <- [0..size(l) - 1], l[i + 1].nr != l[i].nr] + [l[-1]];

// What happened to the copies between two versions, as OmniCCG decides it from
// their hashes: none changed (Same), all changed (Consistent), or some (Inconsistent).
str change(Version before, Version after) {
    kept = hashes(after) & hashes(before);
    return kept == hashes(after) ? "Same" : kept == {} ? "Consistent" : "Inconsistent";
}

str files(Version v) = intercalate(", ", dup([c.file | c <- v.copies]));

// ---- The report: report.html with the patterns as JSON in place of __DATA__

value lineageJson(Lineage l) = [
    ("nr": v.nr, "commit": v.commit, "change": v.change, "copies": [
        ("file": c.file, "start": c.startLine, "end": c.endLine, "hash": c.hash) | c <- v.copies])
    | v <- l];

loc writeReport(loc results, int lineages, list[map[str, value]] patterns) {
    report = ("results": results.path, "lineages": lineages, "patterns": patterns);
    json = replaceAll(asJSON(report), "\</", "\<\\/");  // keep "\</script>" out of the page
    page = results + "patterns.html";
    writeFile(page, replaceFirst(readFile(|cwd:///report.html|), "__DATA__", json));
    return page;
}
