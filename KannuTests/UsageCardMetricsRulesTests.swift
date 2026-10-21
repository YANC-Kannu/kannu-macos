/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import XCTest

/// The view is not in the logic target, so this reads its source: every size in the Usage tab's
/// cards comes from `UsageCardMetrics` (so the budget test means something), the shapes are the
/// timer's continuous ones, and the controls at the notch's top edge put their tooltips below.
final class UsageCardMetricsRulesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let viewPath = "Kannu/components/Notch/NotchLLMUsageView.swift"

    func testTheCardsAreSizedByTheMetrics() throws {
        let source = try String(contentsOf: Self.root.appendingPathComponent(Self.viewPath), encoding: .utf8)
        XCTAssertGreaterThan(source.count, 10_000, "the view's source was read")
        XCTAssertEqual(Self.problems(in: source), [])
    }

    func testTheScannerCatchesPlantedOffenders() {
        XCTAssertEqual(Self.problems(in: Self.clean), [])
        let plants: [(String, String)] = [
            (".padding(M.cardPadding)", ".padding(10)"),
            ("cornerRadius: M.cardCornerRadius, style: .continuous", "cornerRadius: 12, style: .continuous"),
            ("cornerRadius: M.cardCornerRadius, style: .continuous", "cornerRadius: M.cardCornerRadius"),
            (".frame(height: M.barHeight)", ".frame(height: 6)"),
            ("Self.font(M.textFontSize, .medium)", ".system(size: 11, weight: .medium)"),
            ("Self.font(M.textFontSize, .medium)", ".font(.caption2)"),
            ("opacity(M.barTrackOpacity)", "opacity(0.15)"),
            (".hoverTooltip(String(localized: \"Fetch latest usage\"), edge: .below)", ".hoverTooltip(String(localized: \"Fetch latest usage\"))"),
            ("M.maxWeeklyBars(statusRow: hasStatus)", "3"),
        ]
        for (good, bad) in plants {
            let planted = Self.clean.replacingOccurrences(of: good, with: bad)
            XCTAssertNotEqual(planted, Self.clean, "the plant changed nothing: \(bad)")
            XCTAssertFalse(Self.problems(in: planted).isEmpty, "not caught: \(bad)")
        }
    }

    /// A miniature of the view with every rule obeyed.
    private static let clean = """
        Image(systemName: "arrow.clockwise")
        .padding(M.cardPadding)
        RoundedRectangle(cornerRadius: M.cardCornerRadius, style: .continuous)
        .frame(height: M.barHeight)
        .frame(height: M.barRowHeight)
        .frame(height: M.statusRowHeight)
        .frame(width: M.headerRowHeight, height: M.headerRowHeight)
        Self.font(M.textFontSize, .medium)
        Capsule().fill(Color.white.opacity(M.barTrackOpacity))
        .hoverTooltip(String(localized: "Fetch latest usage"), edge: .below)
        let limit = M.maxWeeklyBars(statusRow: hasStatus)
        M.columns(innerWidth: innerWidth)
        M.minimumMinorColumnWidth
        """

    private static func problems(in source: String) -> [String] {
        let code = stripped(source)
        var problems: [String] = []
        // The refresh button is the one `arrow.clockwise`; its tooltip call follows its label. Found
        // in the raw source: `stripped` blanks every string, the symbol's name included.
        if let button = source.range(of: "arrow.clockwise") {
            let after = String(source[button.upperBound...].prefix(2_000))
            if let tooltip = matches(#"\.hoverTooltip\([^\n]*"#, in: after).first, !tooltip.contains("edge: .below") {
                problems.append("the refresh button's tooltip must open below: \(tooltip)")
            }
        }
        let literal = #"(\.padding\((\.\w+,\s*)?\d|cornerRadius:\s*\d|\.system\(size:\s*\d|\.frame\((width|height):\s*\d|opacity\(0\.\d|\.font\(\.(caption|caption2|headline|body|footnote|title\w*))"#
        for match in matches(literal, in: code) {
            problems.append("literal size or text style: \(match)")
        }
        for match in matches(#"RoundedRectangle\([^)]*\)"#, in: code) where !match.contains(".continuous") {
            problems.append("a rounded rectangle that is not continuous: \(match)")
        }
        for needle in ["M.headerRowHeight", "M.barHeight", "M.barRowHeight", "M.cardPadding", "M.statusRowHeight",
                       "M.maxWeeklyBars(statusRow:", "M.columns(innerWidth:", "M.cardCornerRadius", "M.barTrackOpacity"]
        where !code.contains(needle) {
            problems.append("the view does not use \(needle)")
        }
        return problems
    }

    /// Comments and string literals out, so a size named in prose is not an offender.
    private static func stripped(_ source: String) -> String {
        var out = source.replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"/\*.*?\*/"#, with: "", options: [.regularExpression])
        out = out.replacingOccurrences(of: #""(?:[^"\\]|\\.)*""#, with: "\"\"", options: .regularExpression)
        return out
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
