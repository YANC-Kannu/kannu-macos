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

/// A beta never reaches every user. The release workflow runs on every `v*` tag, and its last step
/// commits the appcast to `main`, which every installed Kannu reads: before pre-release tags were
/// handled, `v1.4.0-beta.1` would have been offered to everyone by Sparkle and published as the
/// Latest release. A tag with a hyphen is a pre-release now; these pins keep it one. The workflow
/// is YAML that only runs on a tag, so its text is read.
final class ReleaseWorkflowRulesTests: XCTestCase {
    private static let workflowPath = ".github/workflows/release.yml"

    func testAPreReleaseTagNeverReachesTheAppcast() throws {
        XCTAssertEqual(Self.problems(in: try Self.read(Self.workflowPath)), [])
    }

    func testTheScannerCatchesTheOldWorkflow() throws {
        let workflow = try Self.read(Self.workflowPath)
        let unguarded = workflow.replacingOccurrences(of: "        if: env.RELEASE_PRERELEASE != 'true'\n", with: "")
        XCTAssertEqual(Self.problems(in: unguarded), [
            "Export Sparkle Update Assets runs for a pre-release",
            "Upload Sparkle Artifact runs for a pre-release",
            "Attach appcast to the release runs for a pre-release",
        ])
        let unflagged = workflow
            .replacingOccurrences(of: "          prerelease: ${{ env.RELEASE_PRERELEASE == 'true' }}\n", with: "")
            .replacingOccurrences(of: "if [[ \"${VERSION}\" == *-* ]]; then", with: "if false; then")
        XCTAssertEqual(Self.problems(in: unflagged), [
            "a tag with a hyphen is not marked a pre-release",
            "the GitHub release is not published as a pre-release",
        ])
    }

    /// No build strips the `com.apple.security.mach-services` entitlement. The release workflow, CI
    /// and both local build scripts each ran `plutil -remove com.apple.security.mach-services`, which
    /// reads the dots in the key as a key path, answered "No value to remove at key path" and never
    /// removed it: every build those four made, ad-hoc ones included, carried the key. The reason the
    /// strip gave, that amfid kills an ad-hoc app carrying it, does not hold on macOS 26 (an ad-hoc
    /// signed app with hardened runtime and this entitlement launches), and neither does
    /// `ExtensionXPCServiceHost`'s note that its listener crashes the app without it (a Kannu Dev
    /// build without the key started the listener and ran for hours). A strip that worked would
    /// only change what gets signed, for no reason anyone has shown.
    func testNoBuildStripsTheMachServicesEntitlement() throws {
        for path in Self.buildFiles {
            XCTAssertEqual(Self.machServicesProblems(in: try Self.read(path), path: path), [], path)
        }
        let plutilStrip = "if ! plutil_out=$(plutil -remove com.apple.security.mach-services Kannu/Kannu.entitlements 2>&1); then"
        XCTAssertEqual(Self.machServicesProblems(in: plutilStrip, path: "ci.yml"),
                       ["ci.yml strips the mach-services entitlement"])
        let plistBuddyStrip = "/usr/libexec/PlistBuddy -c \"Delete :com.apple.security.mach-services\" \"$ENTITLEMENTS\""
        XCTAssertEqual(Self.machServicesProblems(in: plistBuddyStrip, path: "release.yml"),
                       ["release.yml strips the mach-services entitlement"])
        let quotedStrip = "plutil -remove \"com.apple.security.mach-services\" \"$TEMP_ENTITLEMENTS\""
        XCTAssertEqual(Self.machServicesProblems(in: quotedStrip, path: "build-dmg.sh"),
                       ["build-dmg.sh strips the mach-services entitlement"])
    }

    private static let buildFiles = [
        workflowPath, ".github/workflows/ci.yml", "scripts/build-dmg.sh", "scripts/build-launch-app.sh",
    ]

    static func machServicesProblems(in text: String, path: String) -> [String] {
        strips("com.apple.security.mach-services", in: text) ? ["\(path) strips the mach-services entitlement"] : []
    }

    /// A `plutil -remove` or PlistBuddy `Delete` of `key`, however the shell quotes it.
    private static func strips(_ key: String, in text: String) -> Bool {
        let unquoted = text.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
        return unquoted.contains("plutil -remove \(key)") || unquoted.contains("Delete :\(key)")
    }

    /// No build strips `com.apple.security.cs.disable-library-validation` either. `build-dmg.sh` and
    /// `build-launch-app.sh` ran `plutil -remove` on it, which never removed it, for the same key-path
    /// reason. A strip that worked would break both: their builds are ad-hoc signed, an ad-hoc
    /// signature has no Team ID, and with library validation on, dyld refuses the embedded Lottie
    /// and Sparkle frameworks ("mapping process and mapped file (non-platform) have different Team
    /// IDs"), so the app never starts. An ad-hoc probe app with hardened runtime and an embedded
    /// ad-hoc framework shows exactly that on macOS 26, and runs once the entitlement is back.
    func testNoBuildStripsLibraryValidation() throws {
        for path in Self.buildFiles {
            XCTAssertEqual(Self.libraryValidationProblems(in: try Self.read(path), path: path), [], path)
        }
        let plutilStrip = "if ! plutil_out=$(plutil -remove com.apple.security.cs.disable-library-validation \"$TEMP_ENTITLEMENTS\" 2>&1); then"
        XCTAssertEqual(Self.libraryValidationProblems(in: plutilStrip, path: "build-dmg.sh"),
                       ["build-dmg.sh strips disable-library-validation"])
        let plistBuddyStrip = "/usr/libexec/PlistBuddy -c \"Delete :com.apple.security.cs.disable-library-validation\" \"$TEMP_ENTITLEMENTS\""
        XCTAssertEqual(Self.libraryValidationProblems(in: plistBuddyStrip, path: "build-launch-app.sh"),
                       ["build-launch-app.sh strips disable-library-validation"])
        let quotedStrip = "plutil -remove 'com.apple.security.cs.disable-library-validation' \"$TEMP_ENTITLEMENTS\""
        XCTAssertEqual(Self.libraryValidationProblems(in: quotedStrip, path: "ci.yml"),
                       ["ci.yml strips disable-library-validation"])
    }

    static func libraryValidationProblems(in text: String, path: String) -> [String] {
        strips("com.apple.security.cs.disable-library-validation", in: text)
            ? ["\(path) strips disable-library-validation"] : []
    }

    /// A dropped connection while stapling failed the 1.4.0 beta 2 release after Apple had accepted
    /// the DMG ("The network connection was lost", stapler error 68). The release's Notarize step
    /// runs `scripts/notarize-dmg.sh`, which now retries the staple before giving up.
    func testTheStapleIsRetried() throws {
        let script = try Self.read("scripts/notarize-dmg.sh")
        XCTAssertEqual(Self.stapleProblems(workflow: try Self.read(Self.workflowPath), script: script), [])
        let singleShot = script.replacingOccurrences(
            of: "for attempt in $(seq 1 \"$staple_attempts\"); do\n  if xcrun stapler staple \"$DMG_PATH\"; then",
            with: "xcrun stapler staple \"$DMG_PATH\"\nfor attempt in 1; do\n  if true; then"
        )
        XCTAssertNotEqual(singleShot, script, "the plant did not take")
        XCTAssertEqual(Self.stapleProblems(workflow: try Self.read(Self.workflowPath), script: singleShot),
                       ["the staple is not retried"])
        // The loop kept, but given one attempt: one try is no retry.
        let oneAttempt = script.replacingOccurrences(of: "staple_attempts=5\n", with: "staple_attempts=1\n")
        XCTAssertNotEqual(oneAttempt, script, "the plant did not take")
        XCTAssertEqual(Self.stapleProblems(workflow: try Self.read(Self.workflowPath), script: oneAttempt),
                       ["the staple is not retried"])
        XCTAssertEqual(Self.stapleProblems(workflow: "run: xcrun notarytool submit build/Kannu.dmg --wait", script: script),
                       ["the Notarize step does not run scripts/notarize-dmg.sh"])
    }

    static func stapleProblems(workflow: String, script: String) -> [String] {
        var problems: [String] = []
        if !workflow.contains("./scripts/notarize-dmg.sh \"build/${RELEASE_DMG}\"") {
            problems.append("the Notarize step does not run scripts/notarize-dmg.sh")
        }
        let loop = script.range(of: "for attempt in $(seq 1 \"$staple_attempts\"); do").map { String(script[$0.upperBound...]) } ?? ""
        let loopBody = loop.components(separatedBy: "\ndone").first ?? ""
        let staples = script.components(separatedBy: "xcrun stapler staple").count - 1
        // The loop's count, as the script sets it: at least two tries, or it is no retry.
        let attempts = script.split(separator: "\n").first { $0.hasPrefix("staple_attempts=") }
            .flatMap { Int($0.dropFirst("staple_attempts=".count)) } ?? 0
        if staples != 1 || !loopBody.contains("xcrun stapler staple") || !loopBody.contains("sleep") || attempts < 2 {
            problems.append("the staple is not retried")
        }
        return problems
    }

    /// Both 2.0 betas built and signed for half an hour and were then refused at Notarize DMG:
    /// Apple had revised its agreement and the team had not accepted it. The workflow now asks the
    /// notary service first, with a call that uploads nothing, before anything is built.
    func testAppleIsAskedBeforeAnythingIsBuilt() throws {
        let workflow = try Self.read(Self.workflowPath)
        let script = try Self.read("scripts/check-notary-access.sh")
        XCTAssertEqual(Self.notaryCheckProblems(workflow: workflow, script: script), [])
        // The step moved after the build, where a refusal costs the whole build again.
        let step = try XCTUnwrap(workflow.range(of: "      - name: Check Apple notary access\n"))
        let nextStep = try XCTUnwrap(workflow.range(of: "      - name: Download Metal Toolchain\n"))
        let block = String(workflow[step.lowerBound..<nextStep.lowerBound])
        let late = workflow.replacingOccurrences(of: block, with: "")
            .replacingOccurrences(of: "      - name: Notarize DMG\n", with: block + "      - name: Notarize DMG\n")
        XCTAssertNotEqual(late, workflow, "the plant did not take")
        XCTAssertEqual(Self.notaryCheckProblems(workflow: late, script: script),
                       ["Apple is asked only after the build"])
        XCTAssertEqual(Self.notaryCheckProblems(workflow: workflow.replacingOccurrences(of: block, with: ""), script: script),
                       ["the workflow never asks Apple before building"])
        // A check that submits would upload a file; one that never names the agreement hides the cause.
        let submits = script.replacingOccurrences(of: "xcrun notarytool history", with: "xcrun notarytool submit build/Kannu.dmg")
        XCTAssertEqual(Self.notaryCheckProblems(workflow: workflow, script: submits),
                       ["the check does not ask for the history"])
        let silent = script.replacingOccurrences(of: "grep -qi \"agreement\"", with: "false")
        XCTAssertNotEqual(silent, script, "the plant did not take")
        XCTAssertEqual(Self.notaryCheckProblems(workflow: workflow, script: silent),
                       ["a refused agreement is not named"])
    }

    static func notaryCheckProblems(workflow: String, script: String) -> [String] {
        var problems: [String] = []
        let call = "./scripts/check-notary-access.sh"
        if let check = workflow.range(of: call) {
            let build = workflow.range(of: "- name: Archive and export Release app")
            if build.map({ check.lowerBound > $0.lowerBound }) ?? true {
                problems.append("Apple is asked only after the build")
            }
        } else {
            problems.append("the workflow never asks Apple before building")
        }
        if !script.contains("xcrun notarytool history") || script.contains("notarytool submit") {
            problems.append("the check does not ask for the history")
        }
        if !script.contains("grep -qi \"agreement\"") || !script.contains("Account Holder") {
            problems.append("a refused agreement is not named")
        }
        return problems
    }

    // MARK: - Sparkle is proven before the build

    /// Apple's refusal stopped both 2.0 betas at Notarize DMG, so no Sparkle step had ever run in this
    /// repository, and a pre-release skips them anyway. Nothing had shown that the signing-key secret
    /// pairs with `SUPublicEDKey` inside the app: the workflow only saw that it was not empty. A wrong
    /// key would first show on the final tag, as every install refusing the update. The key is now
    /// checked on every tag, and before Apple is asked, so a refused agreement cannot hide it.
    func testTheSparkleKeyIsCheckedBeforeAnythingIsBuilt() throws {
        let workflow = try Self.read(Self.workflowPath)
        let script = try Self.read("scripts/check-sparkle-key.sh")
        XCTAssertEqual(Self.sparkleKeyProblems(workflow: workflow, script: script), [])

        let check = try XCTUnwrap(Self.step("Check Sparkle signing key", in: workflow))
        let without = workflow.replacingOccurrences(of: check, with: "")
        XCTAssertEqual(Self.sparkleKeyProblems(workflow: without, script: script), ["the workflow never checks the Sparkle key"])
        // After Apple is asked, a refused agreement ends the run before the key is looked at.
        let metal = "      - name: Download Metal Toolchain\n"
        let late = without.replacingOccurrences(of: metal, with: check + metal)
        XCTAssertNotEqual(late, without, "the plant did not take")
        XCTAssertEqual(Self.sparkleKeyProblems(workflow: late, script: script), ["the Sparkle key is checked only after Apple is asked"])
        let tools = try XCTUnwrap(Self.step("Download Sparkle Tools", in: workflow))
        let apple = "      - name: Check Apple notary access\n"
        let toolsLate = workflow.replacingOccurrences(of: tools, with: "").replacingOccurrences(of: apple, with: tools + apple)
        XCTAssertNotEqual(toolsLate, workflow, "the plant did not take")
        XCTAssertEqual(Self.sparkleKeyProblems(workflow: toolsLate, script: script), ["the Sparkle key is checked before its tools are downloaded"])
        // A beta is the only tag that runs before the final one: skipping it there proves nothing in time.
        let name = "      - name: Check Sparkle signing key\n"
        let finalOnly = workflow.replacingOccurrences(of: name, with: name + "        if: env.RELEASE_PRERELEASE != 'true'\n")
        XCTAssertEqual(Self.sparkleKeyProblems(workflow: finalOnly, script: script), ["a pre-release skips the Sparkle key check"])

        // A key checked against itself always passes; the app's own public key is the one that matters.
        for (target, replacement) in [("Print :SUPublicEDKey", "Print :CFBundleVersion"), ("key.isValidSignature(signature, for: data)", "true")] {
            let planted = script.replacingOccurrences(of: target, with: replacement)
            XCTAssertNotEqual(planted, script, "the plant did not take: \(target)")
            XCTAssertEqual(Self.sparkleKeyProblems(workflow: workflow, script: planted),
                           ["the check does not verify against the app's own public key"])
        }
        for (target, replacement) in [
            ("set -euo pipefail\n", "set -euxo pipefail\n"),
            ("echo \"Checking the Sparkle signing key...\"\n", "echo \"Checking the Sparkle signing key $SPARKLE_EDDSA_PRIVATE_KEY\"\n"),
        ] {
            let planted = script.replacingOccurrences(of: target, with: replacement)
            XCTAssertNotEqual(planted, script, "the plant did not take: \(target)")
            XCTAssertEqual(Self.sparkleKeyProblems(workflow: workflow, script: planted), ["the check could print the private key"])
        }
    }

    static func sparkleKeyProblems(workflow: String, script: String) -> [String] {
        var problems: [String] = []
        if let call = workflow.range(of: "./scripts/check-sparkle-key.sh") {
            let apple = workflow.range(of: "- name: Check Apple notary access")
            if apple.map({ call.lowerBound > $0.lowerBound }) ?? true {
                problems.append("the Sparkle key is checked only after Apple is asked")
            }
            let tools = workflow.range(of: "- name: Download Sparkle Tools")
            if tools.map({ call.lowerBound < $0.lowerBound }) ?? true {
                problems.append("the Sparkle key is checked before its tools are downloaded")
            }
            if step("Check Sparkle signing key", in: workflow)?.contains("        if: ") ?? true {
                problems.append("a pre-release skips the Sparkle key check")
            }
        } else {
            problems.append("the workflow never checks the Sparkle key")
        }
        if !script.contains("Print :SUPublicEDKey") || !script.contains("isValidSignature(") || script.contains("--verify") {
            problems.append("the check does not verify against the app's own public key")
        }
        // The key is named twice: once to see that it is set, once on its way into sign_update's standard input.
        let allowed = [
            "if [ -z \"${SPARKLE_EDDSA_PRIVATE_KEY:-}\" ]; then",
            "printf '%s' \"$SPARKLE_EDDSA_PRIVATE_KEY\" | \"$SPARKLE_BIN_DIR/sign_update\" --ed-key-file - -p",
        ]
        let uses = script.components(separatedBy: "\n")
            .filter { $0.contains("$SPARKLE_EDDSA_PRIVATE_KEY") || $0.contains("${SPARKLE_EDDSA_PRIVATE_KEY") }
        if uses.count != 2 || !uses.allSatisfy({ line in allowed.contains { line.contains($0) } })
            || script.range(of: "set -[a-z]*x", options: .regularExpression) != nil || script.contains("xtrace") {
            problems.append("the check could print the private key")
        }
        return problems
    }

    // MARK: - The appcast reaches main by an admin's hand

    /// The workflow's last step committed the appcast to `main` as `github-actions[bot]`. The ruleset
    /// on `main` lets only an admin update it, so on the first final tag that push would have been
    /// refused: a release on GitHub, and a feed still offering 1.3.4. The job now attaches the signed
    /// appcast to the release, and `scripts/publish-appcast.sh`, run by an admin, commits it.
    func testTheWorkflowNeverPushesTheAppcastItself() throws {
        let workflow = try Self.read(Self.workflowPath)
        let script = try Self.read("scripts/publish-appcast.sh")
        XCTAssertEqual(Self.appcastProblems(workflow: workflow, script: script), [])

        // The old step back in place of the upload.
        let upload = "          gh release upload \"$TAG\" Updates/appcast.xml --clobber --repo \"$GITHUB_REPOSITORY\"\n"
        let pushed = workflow.replacingOccurrences(
            of: upload, with: "          git commit -m \"Update appcast for ${TAG}\"\n          git push origin main\n")
        XCTAssertNotEqual(pushed, workflow, "the plant did not take")
        XCTAssertEqual(Self.appcastProblems(workflow: pushed, script: script), [
            "the workflow pushes to a branch, which the ruleset on main refuses",
            "the signed appcast is not attached to the release",
        ])
        let silent = workflow.replacingOccurrences(of: "./scripts/publish-appcast.sh ${TAG}", with: "the release guide")
        XCTAssertNotEqual(silent, workflow, "the plant did not take")
        XCTAssertEqual(Self.appcastProblems(workflow: silent, script: script), ["the run does not say which step is left"])

        for (target, replacement, problem) in [
            ("if [[ \"$VERSION\" == *-* ]]; then", "if false; then", "the script would publish a pre-release to the feed"),
            ("git clone --quiet", "git checkout \"$BRANCH\" #", "the script works in the caller's own checkout"),
            ("xmllint --noout", "true", "the script publishes an appcast it has not checked"),
            ("sparkle:edSignature=", "sparkle:version", "the script publishes an appcast it has not checked"),
            ("if [ \"$DRY_RUN\" = true ]; then", "if false; then", "a dry run would still push"),
        ] {
            let planted = script.replacingOccurrences(of: target, with: replacement)
            XCTAssertNotEqual(planted, script, "the plant did not take: \(target)")
            XCTAssertEqual(Self.appcastProblems(workflow: workflow, script: planted), [problem], "planted: \(target)")
        }
    }

    static func appcastProblems(workflow: String, script: String) -> [String] {
        var problems: [String] = []
        if workflow.contains("git push") {
            problems.append("the workflow pushes to a branch, which the ruleset on main refuses")
        }
        let attach = step("Attach appcast to the release", in: workflow) ?? ""
        if !attach.contains("gh release upload \"$TAG\" Updates/appcast.xml") {
            problems.append("the signed appcast is not attached to the release")
        }
        if !attach.contains("./scripts/publish-appcast.sh ${TAG}") {
            problems.append("the run does not say which step is left")
        }
        if !script.contains("if [[ \"$VERSION\" == *-* ]]; then") {
            problems.append("the script would publish a pre-release to the feed")
        }
        // A fresh clone in a scratch folder: the caller's checkout and its worktrees keep their branches.
        if !script.contains("git clone ") || script.contains("git checkout") || script.contains("git switch") {
            problems.append("the script works in the caller's own checkout")
        }
        if !script.contains("xmllint --noout") || !script.contains("sparkle:edSignature=")
            || !script.contains("<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>") {
            problems.append("the script publishes an appcast it has not checked")
        }
        if let stop = script.range(of: "if [ \"$DRY_RUN\" = true ]; then"), let push = script.range(of: " push origin "),
           stop.lowerBound < push.lowerBound {
            // The dry run stops before the push.
        } else {
            problems.append("a dry run would still push")
        }
        return problems
    }

    // MARK: - A beta rehearses the Sparkle export

    /// A pre-release publishes no appcast, so the export script would first run on the final tag. A
    /// beta now runs it into a scratch folder, after the beta itself is published, and uploads the
    /// result under a name of its own. Nothing reads it but a person.
    func testABetaRehearsesTheSparkleExportAndPublishesNoneOfIt() throws {
        let workflow = try Self.read(Self.workflowPath)
        XCTAssertEqual(Self.rehearsalProblems(in: workflow), [])

        let name = "      - name: Rehearse Sparkle export\n"
        let rehearsal = try XCTUnwrap(Self.step("Rehearse Sparkle export", in: workflow))
        let publish = "      - name: Publish GitHub Release\n"
        let early = workflow.replacingOccurrences(of: rehearsal, with: "").replacingOccurrences(of: publish, with: rehearsal + publish)
        for (planted, problem) in [
            (workflow.replacingOccurrences(of: name + "        if: env.RELEASE_PRERELEASE == 'true'\n", with: name),
             "Rehearse Sparkle export does not run only for a pre-release"),
            (workflow.replacingOccurrences(of: "            \"$REHEARSAL_DIR\" \\\n", with: "            Updates \\\n"),
             "the rehearsal writes the real appcast"),
            (workflow.replacingOccurrences(of: "          name: Kannu-sparkle-rehearsal\n", with: "          name: Kannu-sparkle\n"),
             "the rehearsal's result could be taken for the real appcast"),
            (workflow.replacingOccurrences(of: "            build/${{ env.RELEASE_DMG }}\n          body_path",
                                           with: "            build/${{ env.RELEASE_DMG }}\n            ${{ env.REHEARSAL_DIR }}/appcast.xml\n          body_path"),
             "the rehearsal's result could be taken for the real appcast"),
            (early, "a failed rehearsal would hold back the beta itself"),
        ] {
            XCTAssertNotEqual(planted, workflow, "the plant did not take: \(problem)")
            XCTAssertEqual(Self.rehearsalProblems(in: planted), [problem])
        }
    }

    static func rehearsalProblems(in workflow: String) -> [String] {
        var problems: [String] = []
        for name in ["Rehearse Sparkle export", "Upload Sparkle Rehearsal"] {
            guard let range = workflow.range(of: "- name: \(name)\n") else {
                problems.append("\(name) is gone")
                continue
            }
            if !workflow[range.upperBound...].hasPrefix("        if: env.RELEASE_PRERELEASE == 'true'\n") {
                problems.append("\(name) does not run only for a pre-release")
            }
        }
        let rehearsal = step("Rehearse Sparkle export", in: workflow) ?? ""
        if !rehearsal.contains("REHEARSAL_DIR=\"$RUNNER_TEMP/sparkle-rehearsal\"\n")
            || !rehearsal.contains("            \"$REHEARSAL_DIR\" \\\n") || rehearsal.contains("            Updates \\\n") {
            problems.append("the rehearsal writes the real appcast")
        }
        if step("Publish GitHub Release", in: workflow)?.contains("REHEARSAL") ?? true
            || !(step("Upload Sparkle Rehearsal", in: workflow) ?? "").contains("          name: Kannu-sparkle-rehearsal\n") {
            problems.append("the rehearsal's result could be taken for the real appcast")
        }
        if let rehearse = workflow.range(of: "- name: Rehearse Sparkle export"),
           let publish = workflow.range(of: "- name: Publish GitHub Release"), rehearse.lowerBound < publish.lowerBound {
            problems.append("a failed rehearsal would hold back the beta itself")
        }
        return problems
    }

    /// One step's text: from its `- name:` line to the next step's, or to the end of the file.
    static func step(_ name: String, in workflow: String) -> String? {
        guard let start = workflow.range(of: "      - name: \(name)\n") else { return nil }
        let end = workflow[start.upperBound...].range(of: "      - name: ")?.lowerBound ?? workflow.endIndex
        return String(workflow[start.lowerBound..<end])
    }

    // MARK: - Rules

    static func problems(in workflow: String) -> [String] {
        var problems: [String] = []
        if !workflow.contains("if [[ \"${VERSION}\" == *-* ]]; then\n            echo \"RELEASE_PRERELEASE=true\" >> \"$GITHUB_ENV\"") {
            problems.append("a tag with a hyphen is not marked a pre-release")
        }
        for step in ["Export Sparkle Update Assets", "Upload Sparkle Artifact", "Attach appcast to the release"] {
            guard let range = workflow.range(of: "- name: \(step)\n") else {
                problems.append("\(step) is gone")
                continue
            }
            let next = workflow[range.upperBound...].prefix(80)
            if !next.hasPrefix("        if: env.RELEASE_PRERELEASE != 'true'\n") {
                problems.append("\(step) runs for a pre-release")
            }
        }
        let publish = workflow.range(of: "- name: Publish GitHub Release").map { String(workflow[$0.upperBound...].prefix(700)) } ?? ""
        if !publish.contains("prerelease: ${{ env.RELEASE_PRERELEASE == 'true' }}")
            || !publish.contains("make_latest: ${{ env.RELEASE_PRERELEASE == 'true' && 'false' || 'true' }}") {
            problems.append("the GitHub release is not published as a pre-release")
        }
        return problems
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
