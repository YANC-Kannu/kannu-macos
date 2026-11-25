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

/// A call in another app on the closed notch. The pill's place is one branch of `ContentView`'s
/// closed-notch chain, in which the first match wins, and its detection is CoreAudio listeners and
/// one timer: neither has a unit surface, so both are pinned by reading the source, each rule
/// against a planted offender.
///
/// What David decided (2026-11-24): the call is drawn above music only, so a running timer and a
/// screen recording keep the notch but for the call's first 5 s; the notch never opens by itself;
/// and the calling app's own window and notification are left alone.
final class ClosedCallPillRulesTests: XCTestCase {
    private static let contentViewPath = "Kannu/ContentView.swift"
    private static let coordinatorPath = "Kannu/KannuViewCoordinator.swift"
    private static let monitorPath = "Kannu/managers/CallAudioProcessMonitor.swift"
    private static let managerPath = "Kannu/managers/CallActivityManager.swift"
    private static let appPath = "Kannu/KannuApp.swift"

    // MARK: - The branch: where it sits, and when it holds

    func testTheCallSitsBetweenTheAgentPillAndMusic() throws {
        XCTAssertEqual(Self.chainProblems(in: try Self.read(Self.contentViewPath)), [])
    }

    func testACallBelowMusicIsCaught() {
        let planted = """
                      } else if isPhysicalNotchScreen && agentLightDeadline != nil && !vm.hideOnClosed {
                          sidewaysAgentPill()
                      } else if canShowMusicDuringExpansion && musicPairingEligible {
                          MusicLiveActivity(secondary: musicSecondary)
                      } else if callOwnsClosedNotch, let call = currentCall {
                          closedCallPill(call)
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .timer) && timerOwnsClosedNotch {
                          TimerLiveActivity(
            """
        XCTAssertEqual(Self.chainProblems(in: planted), ["the call is not drawn ahead of the music pill"])
    }

    func testACallAheadOfTheAgentPillIsCaught() {
        let planted = """
                      } else if callOwnsClosedNotch, let call = currentCall {
                          closedCallPill(call)
                      } else if isPhysicalNotchScreen && agentLightDeadline != nil && !vm.hideOnClosed {
                          sidewaysAgentPill()
                      } else if canShowMusicDuringExpansion && musicPairingEligible {
                          MusicLiveActivity(secondary: musicSecondary)
            """
        XCTAssertEqual(Self.chainProblems(in: planted), ["an agent's switch no longer takes its 7 s ahead of the call"])
    }

    func testABranchWithItsOwnConditionIsCaught() {
        let planted = """
                          sidewaysAgentPill()
                      } else if vm.notchState == .closed, let call = currentCall {
                          closedCallPill(call)
                      } else if canShowMusicDuringExpansion && musicPairingEligible {
                          MusicLiveActivity(secondary: musicSecondary)
            """
        XCTAssertEqual(Self.chainProblems(in: planted), ["the call's branch is not callOwnsClosedNotch"])
        XCTAssertEqual(Self.chainProblems(in: "MusicLiveActivity(secondary: musicSecondary)"), ["the call pill is not in the chain"])
    }

    func testATimerOrARecordingKeepsTheNotchButForTheTakeover() throws {
        XCTAssertEqual(Self.ownershipProblems(in: try Self.read(Self.contentViewPath)), [])
    }

    func testACallThatOutranksTheTimerIsCaught() {
        let planted = """
            private var isCallTakeoverShowing: Bool {
                isSneakPeekVisibleOnCurrentScreen && coordinator.sneakPeek.type == .call
            }
            private var callOwnsClosedNotch: Bool {
                guard currentCall != nil else { return false }
                guard vm.notchState == .closed, !vm.hideOnClosed, !lockScreenManager.isLocked else { return false }
                if isCallTakeoverShowing { return true }
                return !isCurrentScreenExpansionVisible && !recordingHoldsClosedNotch
            }
            private var isClosedNotchEmptyState: Bool {
                if callOwnsClosedNotch { return false }
                return true
            }
            """
        XCTAssertEqual(Self.ownershipProblems(in: planted), ["a call takes the notch from a running timer for good"])
        let noRecording = planted.replacingOccurrences(of: "!recordingHoldsClosedNotch", with: "!timerOwnsClosedNotch")
        XCTAssertEqual(Self.ownershipProblems(in: noRecording), ["a call takes the notch from a screen recording for good"])
        let noTakeover = planted
            .replacingOccurrences(of: "!recordingHoldsClosedNotch", with: "!timerOwnsClosedNotch && !recordingHoldsClosedNotch")
            .replacingOccurrences(of: "    if isCallTakeoverShowing { return true }\n", with: "")
        XCTAssertEqual(Self.ownershipProblems(in: noTakeover), ["the call's 5 s takeover is not asked ahead of the timer and the recording"])
        let shownWhileLocked = planted
            .replacingOccurrences(of: "!recordingHoldsClosedNotch", with: "!timerOwnsClosedNotch && !recordingHoldsClosedNotch")
            .replacingOccurrences(of: ", !lockScreenManager.isLocked", with: "")
        XCTAssertEqual(Self.ownershipProblems(in: shownWhileLocked), ["the call shows while the screen is locked or the notch hides"])
        let paintedEmpty = planted
            .replacingOccurrences(of: "!recordingHoldsClosedNotch", with: "!timerOwnsClosedNotch && !recordingHoldsClosedNotch")
            .replacingOccurrences(of: "    if callOwnsClosedNotch { return false }\n", with: "")
        XCTAssertEqual(Self.ownershipProblems(in: paintedEmpty), ["a notch that holds a call still counts as empty"])
    }

    // MARK: - The takeover: `.call` and its pair in the hand-written ==

    func testTheTakeoverMatches() throws {
        XCTAssertEqual(Self.takeoverProblems(coordinator: try Self.read(Self.coordinatorPath),
                                             content: try Self.read(Self.contentViewPath)), [])
    }

    /// The trap: `SneakContentType` writes its own `==`, whose `default` answers false. A case
    /// with no pair there never equals itself, so `sneakPeek.type == .call` is never true and
    /// the takeover silently never shows.
    func testACaseWithoutItsPairIsCaught() {
        let coordinator = """
            enum SneakContentType: Equatable {
                case capsLock
                case call
            }
            extension SneakContentType {
                static func == (lhs: SneakContentType, rhs: SneakContentType) -> Bool {
                    switch (lhs, rhs) {
                    case (.capsLock, .capsLock):
                        return true
                    default:
                        return false
                    }
                }
            }
                    let bypassedTypes: [SneakContentType] = [.music, .timer, .bluetoothAudio, .call]
            """
        let content = """
            private var isCallTakeoverShowing: Bool {
                isSneakPeekVisibleOnCurrentScreen && coordinator.sneakPeek.type == .call
            }
                      } else if isSneakPeekVisibleOnCurrentScreen && (coordinator.sneakPeek.type != .call) {
                          InlineHUD(type: $coordinator.sneakPeek.type)
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .call) {
                              SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type)
            private func shouldFixSizeForSneakPeek() -> Bool {
                let isOtherSneak = coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .call
            }
            private func noteCallStarted() {
                coordinator.toggleSneakPeek(status: true, type: .call, duration: CallActivityManager.takeoverDuration)
            }
            """
        XCTAssertEqual(Self.takeoverProblems(coordinator: coordinator, content: content),
                       [".call has no pair in SneakContentType's hand-written =="])
        let paired = coordinator.replacingOccurrences(of: "case (.capsLock, .capsLock):", with: "case (.capsLock, .capsLock),\n     (.call, .call):")
        XCTAssertEqual(Self.takeoverProblems(coordinator: paired, content: content), [])
        // Switched off with the system HUDs: the takeover is not one of them.
        XCTAssertEqual(Self.takeoverProblems(coordinator: paired.replacingOccurrences(of: ", .call]", with: "]"), content: content),
                       ["the takeover is dropped when the system HUDs are off"])
        // Drawn as a HUD: the takeover is the pill, not a volume-style indicator.
        XCTAssertEqual(Self.takeoverProblems(coordinator: paired,
                                             content: content.replacingOccurrences(of: " && (coordinator.sneakPeek.type != .call) {\n              InlineHUD", with: " {\n              InlineHUD")),
                       ["the takeover is also drawn as an inline HUD"])
        XCTAssertEqual(Self.takeoverProblems(coordinator: paired,
                                             content: content.replacingOccurrences(of: " && (coordinator.sneakPeek.type != .call) {\n                  SystemEventIndicatorModifier", with: " {\n                  SystemEventIndicatorModifier")),
                       ["the takeover is also drawn as a system HUD"])
        XCTAssertEqual(Self.takeoverProblems(coordinator: paired,
                                             content: content.replacingOccurrences(of: " && coordinator.sneakPeek.type != .call\n", with: "\n")),
                       ["the takeover sizes the notch like a HUD"])
    }

    // MARK: - The notch never opens by itself

    func testACallNeverOpensTheNotch() throws {
        let content = try Self.read(Self.contentViewPath)
        XCTAssertEqual(Self.selfOpenProblems(content: content, manager: try Self.read(Self.managerPath),
                                             monitor: try Self.read(Self.monitorPath)), [])
        let started = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "private func noteCallStarted()", in: content))
        let opened = content.replacingOccurrences(of: started, with: started + "\n        openNotch(focus: .home)\n")
        XCTAssertEqual(Self.selfOpenProblems(content: opened, manager: "", monitor: ""), ["a call's start opens the notch"])
        XCTAssertEqual(Self.selfOpenProblems(content: content, manager: "KannuViewCoordinator.shared.currentView = .home", monitor: ""),
                       ["the call manager or its monitor reaches into the notch"])
    }

    // MARK: - Detection: off the main thread, torn down, one timer only while the microphone is in use

    func testTheMonitorIsTornDownAndRereadsOnlyWhileTheMicrophoneIsInUse() throws {
        XCTAssertEqual(Self.monitorProblems(in: try Self.read(Self.monitorPath)), [])
    }

    func testAMonitorThatLeaksOrPollsIsCaught() throws {
        let real = try Self.read(Self.monitorPath)

        let stop = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "func stop()", in: real))
        XCTAssertEqual(Self.monitorProblems(in: real.replacingOccurrences(of: stop, with: stop.replacingOccurrences(of: "cancelRereadTimer()", with: ""))),
                       ["stop() leaves the re-read timer running"])
        XCTAssertEqual(Self.monitorProblems(in: real.replacingOccurrences(of: stop, with: stop.replacingOccurrences(of: "removeDeviceListener()", with: "")
            .replacingOccurrences(of: "removeSystemListeners()", with: ""))),
                       ["stop() leaves a listener installed"])
        XCTAssertEqual(Self.monitorProblems(in: real.replacingOccurrences(of: "func stop()", with: "func halt()")),
                       ["the monitor has no stop()"])

        // The timer as a plain poll: started with the monitor, whatever the microphone does.
        let alwaysOn = real.replacingOccurrences(of: "setRereadTimer(running: microphoneIsInUse || catalogAppCaptures,",
                                                 with: "setRereadTimer(running: true,")
        XCTAssertEqual(Self.monitorProblems(in: alwaysOn), ["the re-read does not follow the microphone"])
        // One pace for everything: the 2 s gap is what let a call's clock run on after it ended.
        let onePace = real.replacingOccurrences(of: "every: catalogAppCaptures ? Self.callRereadInterval : Self.rereadInterval",
                                                with: "every: Self.rereadInterval")
        XCTAssertEqual(Self.monitorProblems(in: onePace), ["the re-read is no quicker while a listed app captures"])
        // Quick always: a poll every second for as long as anything at all holds the microphone.
        let alwaysQuick = real.replacingOccurrences(of: "static let rereadInterval: TimeInterval = 2",
                                                    with: "static let rereadInterval: TimeInterval = 1")
        XCTAssertEqual(Self.monitorProblems(in: alwaysQuick), ["the re-read is no quicker while a listed app captures"])
        // The device lists for every listed process on every reading, idle ones included.
        let devicesAlways = real.replacingOccurrences(of: "let shares = input != 0 && output != 0 && Self.capturesFromOutputDevice(object)",
                                                      with: "let shares = Self.capturesFromOutputDevice(object)")
        XCTAssertEqual(Self.monitorProblems(in: devicesAlways), ["a process's devices are read while it is not capturing and playing"])
        let neverCancelled = real.replacingOccurrences(of: """
                    guard running else {
                        cancelRereadTimer()
                        return
                    }
            """, with: "")
        XCTAssertEqual(Self.monitorProblems(in: neverCancelled), ["the re-read is not cancelled when the microphone is free"])
        XCTAssertEqual(Self.monitorProblems(in: real + "\n    private let second = DispatchSource.makeTimerSource(queue: .main)\n"),
                       ["the monitor runs more than its one timer"])

        // MicrophoneMonitor's shape: a hop to the main queue to read, and a print.
        XCTAssertEqual(Self.monitorProblems(in: real + "\n    func read() { DispatchQueue.main.async { self.refresh() } }\n"),
                       ["the monitor reads on the main queue"])
        XCTAssertEqual(Self.monitorProblems(in: real + "\n    func note() { print(\"mic\") }\n"), ["the monitor prints"])
        XCTAssertEqual(Self.monitorProblems(in: real + """

                func extra() {
                    var address = Self.address(kAudioHardwarePropertyDevices)
                    AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, queue, { _, _ in })
                }
            """), ["a listener is added that nothing removes"])
    }

    func testTheSwitchStartsAndStopsTheMonitor() throws {
        XCTAssertEqual(Self.lifecycleProblems(app: try Self.read(Self.appPath), manager: try Self.read(Self.managerPath)), [])
    }

    func testAMonitorThatOutlivesItsSwitchIsCaught() throws {
        let app = try Self.read(Self.appPath)
        let manager = try Self.read(Self.managerPath)
        XCTAssertEqual(Self.lifecycleProblems(app: app.replacingOccurrences(of: "CallActivityManager.shared.stopMonitoring()", with: ""), manager: manager),
                       ["switching Calls off does not stop the monitor"])
        XCTAssertEqual(Self.lifecycleProblems(app: app.replacingOccurrences(of: "if Defaults[.enableCallActivity] && !AppRuntimeEnvironment.isUITesting {",
                                                                            with: "if true {"), manager: manager),
                       ["the monitor starts whatever the switch says, or under UI testing"])
        XCTAssertEqual(Self.lifecycleProblems(app: app, manager: manager.replacingOccurrences(of: "monitor?.stop()", with: "")),
                       ["stopMonitoring() does not stop the monitor"])
        // Started from the app delegate's init or before the terms: outside continueLaunch().
        let launch = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "private func continueLaunch()", in: app))
        let early = app.replacingOccurrences(of: launch, with: launch.replacingOccurrences(of: "CallActivityManager.shared.startMonitoring()", with: ""))
        XCTAssertEqual(Self.lifecycleProblems(app: early, manager: manager),
                       ["the monitor is not started in continueLaunch()"])
    }

    // MARK: - Rules

    static func chainProblems(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard let call = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "closedCallPill(call)" }) else {
            return ["the call pill is not in the chain"]
        }
        var problems: [String] = []
        let agent = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "sidewaysAgentPill()" }
        let music = lines.firstIndex { $0.contains("MusicLiveActivity(secondary: musicSecondary)") }
        let timer = lines.firstIndex { $0.contains("TimerLiveActivity(") }
        if let agent, call < agent { problems.append("an agent's switch no longer takes its 7 s ahead of the call") }
        if let music, music < call { problems.append("the call is not drawn ahead of the music pill") }
        if let timer, timer < call { problems.append("the call is not drawn ahead of the timer's branch") }
        let condition = lines[..<call].last { $0.contains("} else if ") }?.trimmingCharacters(in: .whitespaces) ?? ""
        if condition != "} else if callOwnsClosedNotch, let call = currentCall {" {
            problems.append("the call's branch is not callOwnsClosedNotch")
        }
        return problems
    }

    static func ownershipProblems(in text: String) -> [String] {
        var problems: [String] = []
        let owns = ClosedNotchTimerRulesTests.body(after: "private var callOwnsClosedNotch: Bool", in: text) ?? ""
        if !["vm.notchState == .closed", "!vm.hideOnClosed", "!lockScreenManager.isLocked"].allSatisfy(owns.contains) {
            problems.append("the call shows while the screen is locked or the notch hides")
        }
        let takeover = owns.range(of: "if isCallTakeoverShowing { return true }")
        let held = owns.range(of: "return ")
            .flatMap { _ in owns.range(of: "return !", options: .backwards) }
        if takeover == nil || held == nil || takeover!.lowerBound > held!.lowerBound {
            problems.append("the call's 5 s takeover is not asked ahead of the timer and the recording")
        }
        let last = held.map { String(owns[$0.lowerBound...]) } ?? ""
        if !last.contains("!timerOwnsClosedNotch") { problems.append("a call takes the notch from a running timer for good") }
        if !last.contains("!recordingHoldsClosedNotch") { problems.append("a call takes the notch from a screen recording for good") }
        let empty = ClosedNotchTimerRulesTests.body(after: "private var isClosedNotchEmptyState: Bool", in: text) ?? ""
        if !empty.contains("if callOwnsClosedNotch { return false }") {
            problems.append("a notch that holds a call still counts as empty")
        }
        return problems
    }

    static func takeoverProblems(coordinator: String, content: String) -> [String] {
        var problems: [String] = []
        let cases = ClosedNotchTimerRulesTests.body(after: "enum SneakContentType: Equatable", in: coordinator) ?? ""
        if !cases.components(separatedBy: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "case call" }) {
            problems.append("SneakContentType has no .call")
        }
        let equals = ClosedNotchTimerRulesTests.body(after: "static func == (lhs: SneakContentType, rhs: SneakContentType) -> Bool", in: coordinator) ?? ""
        if !equals.contains("(.call, .call)") {
            problems.append(".call has no pair in SneakContentType's hand-written ==")
        }
        let bypassed = coordinator.components(separatedBy: "\n").first { $0.contains("let bypassedTypes: [SneakContentType]") } ?? ""
        if !bypassed.contains(".call") { problems.append("the takeover is dropped when the system HUDs are off") }

        let showing = ClosedNotchTimerRulesTests.body(after: "private var isCallTakeoverShowing: Bool", in: content) ?? ""
        if !showing.contains("isSneakPeekVisibleOnCurrentScreen && coordinator.sneakPeek.type == .call") {
            problems.append("the takeover does not read the .call sneak peek")
        }
        let started = ClosedNotchTimerRulesTests.body(after: "private func noteCallStarted()", in: content) ?? ""
        if !started.contains("type: .call, duration: CallActivityManager.takeoverDuration") {
            problems.append("a call's start asks for no takeover")
        }
        // The three places a sneak peek of any other type is drawn or sized as a HUD.
        let inline = ClosedNotchTimerRulesTests.branchCondition(above: "InlineHUD(type: $coordinator.sneakPeek.type", in: content) ?? ""
        if !inline.contains("coordinator.sneakPeek.type != .call") { problems.append("the takeover is also drawn as an inline HUD") }
        let lines = content.components(separatedBy: "\n")
        let system = lines.firstIndex { $0.contains("SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type") }
            .flatMap { at in lines[..<at].last { $0.trimmingCharacters(in: .whitespaces).hasPrefix("if ") } } ?? ""
        if !system.contains("coordinator.sneakPeek.type != .call") { problems.append("the takeover is also drawn as a system HUD") }
        let fixed = ClosedNotchTimerRulesTests.body(after: "private func shouldFixSizeForSneakPeek() -> Bool", in: content) ?? ""
        let other = fixed.range(of: "let isOtherSneak = ").map { String(fixed[$0.upperBound...].prefix(260)) } ?? ""
        if !other.contains("coordinator.sneakPeek.type != .call") { problems.append("the takeover sizes the notch like a HUD") }
        return problems
    }

    static func selfOpenProblems(content: String, manager: String, monitor: String) -> [String] {
        var problems: [String] = []
        let started = ClosedNotchTimerRulesTests.body(after: "private func noteCallStarted()", in: content) ?? ""
        if ["openNotch(", "vm.open()", "currentView ="].contains(where: started.contains) {
            problems.append("a call's start opens the notch")
        }
        let reaches = ["openNotch(", ".open()", "currentView", "KannuViewModel", "NSWorkspace", "AXUIElement"]
        if [manager, monitor].contains(where: { source in reaches.contains(where: Self.code(source).contains) }) {
            problems.append("the call manager or its monitor reaches into the notch")
        }
        return problems
    }

    static func monitorProblems(in source: String) -> [String] {
        let text = code(source)
        var problems: [String] = []
        if let stop = ClosedNotchTimerRulesTests.body(after: "func stop()", in: text) {
            if !stop.contains("cancelRereadTimer()") { problems.append("stop() leaves the re-read timer running") }
            if !(stop.contains("removeDeviceListener()") && stop.contains("removeSystemListeners()")) {
                problems.append("stop() leaves a listener installed")
            }
        } else {
            problems.append("the monitor has no stop()")
        }
        // Every kind of listener added has its removal: the system object's, and the device's.
        let added = text.components(separatedBy: "AudioObjectAddPropertyListenerBlock(").count - 1
        let removed = text.components(separatedBy: "AudioObjectRemovePropertyListenerBlock(").count - 1
        if added != removed || added == 0 { problems.append("a listener is added that nothing removes") }

        let refresh = ClosedNotchTimerRulesTests.body(after: "private func refresh()", in: text) ?? ""
        if !refresh.contains("setRereadTimer(running: microphoneIsInUse") {
            problems.append("the re-read does not follow the microphone")
        }
        // 1 s while a listed app captures, since nothing announces that its capture stopped; 2 s
        // while only something else holds the microphone.
        if !(refresh.contains("every: catalogAppCaptures ? Self.callRereadInterval : Self.rereadInterval")
             && text.contains("static let rereadInterval: TimeInterval = 2")
             && text.contains("static let callRereadInterval: TimeInterval = 1")) {
            problems.append("the re-read is no quicker while a listed app captures")
        }
        if !text.contains("let shares = input != 0 && output != 0 && Self.capturesFromOutputDevice(object)") {
            problems.append("a process's devices are read while it is not capturing and playing")
        }
        let timer = ClosedNotchTimerRulesTests.body(after: "private func setRereadTimer(running: Bool, every interval: TimeInterval)", in: text) ?? ""
        let cancels = timer.range(of: "guard running else {").flatMap { open in
            timer.range(of: "cancelRereadTimer()", range: open.upperBound..<timer.endIndex)
        }
        let makes = timer.range(of: "makeTimerSource(")
        if cancels == nil || makes == nil || cancels!.lowerBound > makes!.lowerBound {
            problems.append("the re-read is not cancelled when the microphone is free")
        }
        let timers = ["makeTimerSource(", "Timer.scheduledTimer", "Timer.publish", "Timer(timeInterval", "asyncAfter(", "Task.sleep"]
            .reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
        if timers != 1 { problems.append("the monitor runs more than its one timer") }

        if text.contains("DispatchQueue.main") || text.contains("@MainActor") || text.contains("MainActor.run") {
            problems.append("the monitor reads on the main queue")
        }
        if text.contains("print(") || text.contains("NSLog(") { problems.append("the monitor prints") }
        return problems
    }

    static func lifecycleProblems(app: String, manager: String) -> [String] {
        var problems: [String] = []
        let launch = ClosedNotchTimerRulesTests.body(after: "private func continueLaunch()", in: app) ?? ""
        if !launch.contains("CallActivityManager.shared.startMonitoring()") {
            problems.append("the monitor is not started in continueLaunch()")
        } else if !launch.contains("if Defaults[.enableCallActivity] && !AppRuntimeEnvironment.isUITesting {\n            CallActivityManager.shared.startMonitoring()") {
            problems.append("the monitor starts whatever the switch says, or under UI testing")
        }
        let sink = app.range(of: "Defaults.publisher(.enableCallActivity, options: [])").map { String(app[$0.upperBound...].prefix(500)) } ?? ""
        if !sink.contains("CallActivityManager.shared.stopMonitoring()") {
            problems.append("switching Calls off does not stop the monitor")
        }
        let stop = ClosedNotchTimerRulesTests.body(after: "func stopMonitoring()", in: manager) ?? ""
        if !stop.contains("monitor?.stop()") { problems.append("stopMonitoring() does not stop the monitor") }
        return problems
    }

    // MARK: - Source reading

    /// Code only: the comments name what the monitor must not do.
    static func code(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .filter {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return !line.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
