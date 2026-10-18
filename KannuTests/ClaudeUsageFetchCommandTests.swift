import XCTest

/// Guards the two shipped regressions where a "harmless" addition to the usage spawn silently broke
/// the fetch. Both looked healthy at runtime — session started, spinner ran, nothing fetched — so
/// only a pinned test catches them. See docs/REGRESSIONS.md.
final class ClaudeUsageFetchCommandTests: XCTestCase {

    // MARK: - Regression 1: print-only flags kill the interactive session

    func testNoAttemptUsesAPrintOnlyFlag() {
        for arguments in ClaudeUsageFetchCommand.attempts {
            XCTAssertTrue(
                ClaudeUsageFetchCommand.isValidForInteractiveSession(arguments: arguments),
                "Attempt \(arguments) carries a print-only flag. /usage needs an interactive session, "
                + "and the CLI exits immediately on these — the session dies before /usage is typed."
            )
        }
    }

    func testNoSessionPersistenceIsRejected() {
        // The exact flag that shipped broken: "can only be used with --print mode".
        XCTAssertFalse(ClaudeUsageFetchCommand.isValidForInteractiveSession(
            arguments: ["--no-session-persistence"]))
        XCTAssertFalse(ClaudeUsageFetchCommand.isValidForInteractiveSession(
            arguments: ["--settings", "{}", "--no-session-persistence"]))
    }

    func testPlainArgumentsAreValid() {
        XCTAssertTrue(ClaudeUsageFetchCommand.isValidForInteractiveSession(arguments: []))
        XCTAssertTrue(ClaudeUsageFetchCommand.isValidForInteractiveSession(
            arguments: ["--settings", #"{"disableRemoteControl":true}"#]))
    }

    // MARK: - Regression 2: the env var that silenced the fetch

    func testEnvironmentIsPlainInheritanceForANormalLaunch() {
        // nil means "inherit", which is what the version that actually fetched did. Setting
        // CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC suppressed the /api/oauth/usage call itself.
        let launchd = ["HOME": "/Users/someone", "PATH": "/usr/bin:/bin", "TMPDIR": "/var/folders/x",
                       "HTTPS_PROXY": "http://proxy:8080"]
        XCTAssertNil(ClaudeUsageFetchCommand.environment(inheriting: launchd),
                     "The fetch must inherit the environment. Adding variables here broke it once.")
    }

    func testAnAgentSessionsVariablesAreRemovedAndNothingIsAdded() {
        // Measured 2026-10-18: inherited from an agent session, these made the probe fetch for the
        // agent's account and rewrite oauthAccount in ~/.claude.json.
        let agent = ["HOME": "/Users/someone", "PATH": "/usr/bin:/bin", "HTTPS_PROXY": "http://proxy:8080",
                     "ANTHROPIC_BASE_URL": "http://127.0.0.1:1", "CLAUDE_CODE_ACCOUNT_UUID": "a",
                     "CLAUDE_CODE_ORGANIZATION_UUID": "o", "CLAUDE_CODE_OAUTH_SCOPES": "user:inference",
                     "CLAUDECODE": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"]
        let child = ClaudeUsageFetchCommand.environment(inheriting: agent)
        XCTAssertEqual(child, ["HOME": "/Users/someone", "PATH": "/usr/bin:/bin",
                               "HTTPS_PROXY": "http://proxy:8080"])
        XCTAssertTrue(Set((child ?? [:]).keys).isSubset(of: Set(agent.keys)), "Removing only, never adding.")
        XCTAssertNil(child?["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"])
    }

    func testTheBreakingEnvironmentKeyIsRecordedAsForbidden() {
        XCTAssertTrue(ClaudeUsageFetchCommand.forbiddenEnvironmentKeys
            .contains("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"))
    }

    // MARK: - The proven fallback must survive

    func testLastAttemptIsBare() {
        // The bare invocation is the one observed to actually fetch. If a future change "improves"
        // it away, the button silently stops working again.
        XCTAssertEqual(ClaudeUsageFetchCommand.attempts.last, [],
                       "The final attempt must be the bare invocation proven to fetch.")
    }

    func testAttemptsAreOrderedCleanestFirst() {
        XCTAssertEqual(ClaudeUsageFetchCommand.attempts.count, 2)
        XCTAssertTrue(ClaudeUsageFetchCommand.attempts[0].contains("--settings"),
                      "The first attempt should try to suppress the device registration.")
    }

    // MARK: - The print probe

    func testPrintProbeIsPinned() {
        // Entry 8: every flag or variable added to a usage spawn needs a measured fetch to prove it.
        XCTAssertEqual(ClaudeUsageFetchCommand.printProbe, ["-p", "/usage"])
        XCTAssertFalse(ClaudeUsageFetchCommand.attempts.contains(ClaudeUsageFetchCommand.printProbe),
                       "The probe is its own command; the interactive attempts keep their guards.")
    }

    func testSignInIsClaudeCodesOwnClaudeAISignIn() {
        XCTAssertEqual(ClaudeUsageFetchCommand.signInArguments, ["auth", "login", "--claudeai"])
        XCTAssertEqual(ClaudeUsageFetchCommand.authStatusArguments, ["auth", "status"])
    }

    private let signedInOutput = """
    You are currently using your subscription to power your Claude Code usage
    Current session: 78% used · resets 2:40am
    Current week (all models): 41% used · resets Oct 21, 5:30am
    Current week (Fable): 41% used · resets Oct 21, 5:30am
    """

    private let costOnlyOutput = """
    Total cost:            $0.0000
    Total duration (API):  0s
    Total duration (wall): 4s
    Usage:                 0 input, 0 output, 0 cache read, 0 cache write
    """

    func testPlanRowsAreRecognised() {
        XCTAssertTrue(ClaudeUsageFetchCommand.outputHasPlanRows(signedInOutput))
        XCTAssertFalse(ClaudeUsageFetchCommand.outputHasPlanRows(costOnlyOutput))
        // Signed in with claude.ai but the fetch returned nothing: the scope case.
        XCTAssertFalse(ClaudeUsageFetchCommand.outputHasPlanRows(
            "You are currently using your subscription to power your Claude Code usage"))
    }

    func testProbeClassification() {
        typealias C = ClaudeUsageFetchCommand
        // The stamp on disk is the proof, whatever was printed.
        XCTAssertEqual(C.classifyProbe(exitStatus: 0, timedOut: false, fetchStampAdvanced: true, output: ""), .fetched)
        // Rows without an advance: Claude Code's own write throttle kept a cache this recent.
        XCTAssertEqual(C.classifyProbe(exitStatus: 0, timedOut: false, fetchStampAdvanced: false,
                                       output: signedInOutput), .fetched)
        // Measured 2026-10-18 from a clean environment: exit 0, only the cost summary.
        XCTAssertEqual(C.classifyProbe(exitStatus: 0, timedOut: false, fetchStampAdvanced: false,
                                       output: costOnlyOutput), .noPlanData)
        XCTAssertEqual(C.classifyProbe(exitStatus: 1, timedOut: false, fetchStampAdvanced: false,
                                       output: costOnlyOutput), .failed)
        XCTAssertEqual(C.classifyProbe(exitStatus: nil, timedOut: true, fetchStampAdvanced: false,
                                       output: signedInOutput), .failed)
        XCTAssertEqual(C.classifyProbe(exitStatus: nil, timedOut: false, fetchStampAdvanced: false, output: ""), .failed)
    }

    // MARK: - Whether Refresh may start a sign-in

    func testAuthStatusParsesOnlyWhatItNeeds() {
        let signedOut = """
        {
          "loggedIn": false,
          "authMethod": "none",
          "apiProvider": "firstParty",
          "configDirectory": "/Users/someone/.claude"
        }
        """
        XCTAssertEqual(ClaudeUsageFetchCommand.parseAuthStatus(signedOut),
                       .init(loggedIn: false, authMethod: "none", apiProvider: "firstParty"))
        // Terminal escape noise around the JSON is tolerated.
        XCTAssertEqual(ClaudeUsageFetchCommand.parseAuthStatus("\u{1B}[?25l" + signedOut + "\n")?.authMethod, "none")
        XCTAssertNil(ClaudeUsageFetchCommand.parseAuthStatus("Not logged in. Run claude auth login to authenticate."))
        XCTAssertNil(ClaudeUsageFetchCommand.parseAuthStatus(#"{"loggedIn": "yes"}"#))
    }

    func testSignInStartsOnlyWhereItReplacesNothingTheUserChose() {
        typealias C = ClaudeUsageFetchCommand
        XCTAssertEqual(C.signInDecision(for: .init(loggedIn: false, authMethod: "none", apiProvider: "firstParty")),
                       .startSignIn)
        // Signed in with claude.ai but without the scope the fetch needs: signing in again fixes it.
        XCTAssertEqual(C.signInDecision(for: .init(loggedIn: true, authMethod: "claude.ai", apiProvider: "firstParty")),
                       .startSignIn)
        // An API key, a key helper or a cloud provider must never be switched over by a Refresh.
        XCTAssertEqual(C.signInDecision(for: .init(loggedIn: true, authMethod: "api_key", apiProvider: "firstParty")),
                       .otherSignInMethod)
        XCTAssertEqual(C.signInDecision(for: .init(loggedIn: true, authMethod: "api_key_helper", apiProvider: "firstParty")),
                       .otherSignInMethod)
        XCTAssertEqual(C.signInDecision(for: .init(loggedIn: false, authMethod: "none", apiProvider: "gateway")),
                       .otherSignInMethod)
        XCTAssertEqual(C.signInDecision(for: .init(loggedIn: true, authMethod: "none", apiProvider: "bedrock")),
                       .otherSignInMethod)
        XCTAssertEqual(C.signInDecision(for: nil), .unknown)
    }

    func testTerminalScriptQuotesTheBinaryPath() {
        let script = ClaudeUsageFetchCommand.terminalSignInScript(
            binary: URL(fileURLWithPath: "/Users/o'brien/Library/Application Support/Claude/claude"))
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(script.contains(#"'/Users/o'\''brien/Library/Application Support/Claude/claude' auth login --claudeai"#),
                      script)
    }
}

final class ClaudeCodeBinaryTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("kannu-binary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func executable(_ relative: String, executable: Bool = true) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url
    }

    private func terminalInstall(_ version: String) throws {
        let target = try executable(".local/share/claude/versions/\(version)")
        let link = home.appendingPathComponent(".local/bin/claude")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    }

    private let desktop = "Library/Application Support/Claude/claude-code"
    private let app = "claude.app/Contents/MacOS/claude"

    func testTheCurrentDesktopLayoutIsFound() throws {
        // Desktop moved to <version>/<build>/claude.app in October 2026; the old lookup expected
        // <version>/claude.app, found nothing, and Refresh silently re-read disk instead.
        try executable("\(desktop)/2.1.286/f2326db61802/\(app)")
        let newest = try executable("\(desktop)/2.1.295/9d6405864fdc/\(app)")
        XCTAssertEqual(ClaudeCodeBinary.resolve(home: home)?.url.resolvingSymlinksInPath().path, newest.resolvingSymlinksInPath().path)
        XCTAssertEqual(ClaudeCodeBinary.resolve(home: home)?.version, "2.1.295")
    }

    func testTheLegacyFlatLayoutStillCounts() throws {
        try executable("\(desktop)/2.1.295/9d6405864fdc/\(app)")
        let legacy = try executable("\(desktop)/2.1.300/\(app)")
        XCTAssertEqual(ClaudeCodeBinary.resolve(home: home)?.url.resolvingSymlinksInPath().path, legacy.resolvingSymlinksInPath().path)
    }

    func testTheNewestVersionWinsWhereverItLives() throws {
        try executable("\(desktop)/2.1.295/9d6405864fdc/\(app)")
        // The terminal copy only updates when `claude` runs, so it is usually the older one.
        try terminalInstall("2.1.263")
        XCTAssertEqual(ClaudeCodeBinary.resolve(home: home)?.version, "2.1.295")
        try FileManager.default.removeItem(at: home.appendingPathComponent(".local"))
        try terminalInstall("2.2.0")
        XCTAssertEqual(ClaudeCodeBinary.resolve(home: home)?.version, "2.2.0")
    }

    func testVersionsCompareNumerically() {
        let older = ClaudeCodeBinary.Candidate(url: URL(fileURLWithPath: "/a"), version: "2.1.99")
        let newer = ClaudeCodeBinary.Candidate(url: URL(fileURLWithPath: "/b"), version: "2.1.100")
        XCTAssertEqual(ClaudeCodeBinary.newest([newer, older]), newer)
        XCTAssertEqual(ClaudeCodeBinary.newest([older, newer]), newer)
        // A tie keeps the earlier candidate: Desktop's copy is listed first.
        let twin = ClaudeCodeBinary.Candidate(url: URL(fileURLWithPath: "/c"), version: "2.1.100")
        XCTAssertEqual(ClaudeCodeBinary.newest([newer, twin]), newer)
        XCTAssertNil(ClaudeCodeBinary.newest([]))
    }

    func testNonVersionFoldersAndNonExecutablesAreIgnored() throws {
        try executable("\(desktop)/tmp/abc/\(app)")
        try executable("\(desktop)/2.1.400/abc/\(app)", executable: false)
        XCTAssertNil(ClaudeCodeBinary.resolve(home: home))
    }
}
