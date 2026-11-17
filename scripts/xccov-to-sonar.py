#!/usr/bin/env python3
#
# Kannu (കണ്ണ്) — Copyright (C) 2024-2026 Kannu Contributors — GPL-3.0-or-later.
#
# Converts the line coverage in an Xcode result bundle into SonarQube's generic coverage XML, which
# `sonar.coverageReportPaths` reads. The SonarCloud workflow runs KannuTests with
# -enableCodeCoverage YES and then this script; without it Sonar sees no coverage at all and the
# gate's new-code coverage condition fails on every PR that adds Swift.
#
# One `xccov --archive --json` call reads every file at once, instead of one xccov process per file.
# Only files under `Kannu/` are written: the test sources and anything xcodebuild generates into
# derivedData are not Sonar sources. A line with any hits counts as covered, the same rule
# SonarSource's own xccov sample script applies.
#
# Usage, from the repository root after the test step: python3 -I scripts/xccov-to-sonar.py
# It takes no arguments on purpose. The paths are the workflow's own, so nothing a caller passes
# reaches xcrun or the file it writes.
import json
import os
import subprocess
import sys
from xml.sax.saxutils import quoteattr

XCRESULT = "TestResults.xcresult"
OUTPUT = "sonar-coverage.xml"
SOURCE_PREFIX = "Kannu/"


def load_archive():
    out = subprocess.run(
        ["xcrun", "xccov", "view", "--archive", "--json", XCRESULT],
        check=True,
        capture_output=True,
    ).stdout
    return json.loads(out)


def relative_source(path, root):
    """The repo-relative path Sonar indexes, or None for a file outside the sources."""
    rel = os.path.relpath(os.path.realpath(path), root)
    if rel.startswith(".."):
        return None
    rel = rel.replace(os.sep, "/")
    return rel if rel.startswith(SOURCE_PREFIX) else None


def to_generic_xml(archive, root):
    lines = ['<coverage version="1">']
    files = 0
    for path in sorted(archive):
        rel = relative_source(path, root)
        if rel is None:
            continue
        executable = [entry for entry in archive[path] if entry.get("isExecutable")]
        if not executable:
            continue
        files += 1
        lines.append(f"  <file path={quoteattr(rel)}>")
        for entry in executable:
            covered = "true" if entry.get("executionCount", 0) > 0 else "false"
            lines.append(f'    <lineToCover lineNumber="{entry["line"]}" covered="{covered}"/>')
        lines.append("  </file>")
    lines.append("</coverage>")
    return "\n".join(lines) + "\n", files


def main():
    if len(sys.argv) > 1:
        sys.exit("usage: scripts/xccov-to-sonar.py (no arguments; run from the repository root)")
    xml, files = to_generic_xml(load_archive(), os.path.realpath(os.getcwd()))
    if files == 0:
        # An empty report would upload as "0% coverage" and look like a real number.
        sys.exit(f"error: no coverage for any file under {SOURCE_PREFIX} in {XCRESULT}")
    with open(OUTPUT, "w", encoding="utf-8") as handle:
        handle.write(xml)
    print(f"Wrote coverage for {files} files to {OUTPUT}")


if __name__ == "__main__":
    main()
