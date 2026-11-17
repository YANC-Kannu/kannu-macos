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
# Only files under the source prefix (default `Kannu/`) are written: the test sources and anything
# xcodebuild generates into derivedData are not Sonar sources. A line with any hits counts as
# covered, the same rule SonarSource's own xccov sample script applies.
#
# Usage: xccov-to-sonar.py <TestResults.xcresult> <output.xml> [--root DIR] [--prefix Kannu/]
import argparse
import json
import os
import subprocess
import sys
from xml.sax.saxutils import quoteattr


def load_archive(xcresult):
    out = subprocess.run(
        ["xcrun", "xccov", "view", "--archive", "--json", xcresult],
        check=True,
        capture_output=True,
    ).stdout
    return json.loads(out)


def relative_source(path, root, prefix):
    """The repo-relative path Sonar indexes, or None for a file outside the sources."""
    rel = os.path.relpath(os.path.realpath(path), root)
    if rel.startswith(".."):
        return None
    rel = rel.replace(os.sep, "/")
    return rel if rel.startswith(prefix) else None


def to_generic_xml(archive, root, prefix):
    lines = ['<coverage version="1">']
    files = 0
    for path in sorted(archive):
        rel = relative_source(path, root, prefix)
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
    parser = argparse.ArgumentParser(description="Xcode result bundle coverage to Sonar generic XML")
    parser.add_argument("xcresult")
    parser.add_argument("output")
    parser.add_argument("--root", default=os.getcwd(), help="repository root (default: cwd)")
    parser.add_argument("--prefix", default="Kannu/", help="source prefix to keep (default: Kannu/)")
    args = parser.parse_args()

    root = os.path.realpath(args.root)
    xml, files = to_generic_xml(load_archive(args.xcresult), root, args.prefix)
    if files == 0:
        # An empty report would upload as "0% coverage" and look like a real number.
        sys.exit(f"error: no coverage for any file under {args.prefix} in {args.xcresult}")
    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(xml)
    print(f"Wrote coverage for {files} files to {args.output}")


if __name__ == "__main__":
    main()
