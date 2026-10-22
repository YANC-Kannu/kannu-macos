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

/// Every privacy-protected resource Kannu uses has its usage description and its entitlement, and
/// nothing it does not use has either:
/// - Screen Assistant records audio, with no microphone description and audio input turned off;
/// - LocalSend joins a multicast group and listens on the local network, with no description;
/// - the camera entitlement was on, but nothing captures video (`CameraMonitor` only enumerates
///   devices and reads CoreMediaIO's "running somewhere", which a hardened-runtime probe does
///   without it);
/// - the Desktop description was declared for screenshots Kannu never saves there.
final class PrivacyUsageDescriptionRulesTests: XCTestCase {
    func testUsageDescriptionsMatchWhatKannuUses() throws {
        let project = try Self.read("Kannu.xcodeproj/project.pbxproj")
        let entitlements = try Self.read("Kannu/Kannu.entitlements")
        let assistant = try Self.read("Kannu/managers/ScreenAssistantManager.swift")
        XCTAssertEqual(Self.problems(project: project, entitlements: entitlements, assistant: assistant), [])

        let old = project
            .replacingOccurrences(of: "ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES;", with: "ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = NO;")
            .replacingOccurrences(of: "ENABLE_RESOURCE_ACCESS_CAMERA = NO;", with: "ENABLE_RESOURCE_ACCESS_CAMERA = YES;")
            .replacingOccurrences(of: "INFOPLIST_KEY_NSMicrophoneUsageDescription", with: "INFOPLIST_KEY_NSDesktopFolderUsageDescription")
        XCTAssertEqual(Self.problems(project: old, entitlements: entitlements, assistant: assistant), [
            "no microphone usage description in every configuration",
            "a Desktop folder description, for a folder Kannu never touches",
            "audio input is off",
            "the camera entitlement is on, with nothing that captures video",
        ])

        let unasked = assistant.replacingOccurrences(of: "switch AVCaptureDevice.authorizationStatus(for: .audio) {",
                                                     with: "switch AVAuthorizationStatus.authorized {")
        XCTAssertNotEqual(unasked, assistant, "the plant did not take")
        XCTAssertEqual(Self.problems(project: project, entitlements: entitlements, assistant: unasked),
                       ["Screen Assistant records without asking for the microphone"])
    }

    static func problems(project: String, entitlements: String, assistant: String) -> [String] {
        var problems: [String] = []
        func everyConfiguration(_ text: String) -> Bool { project.components(separatedBy: text).count - 1 == 2 }
        if !everyConfiguration("INFOPLIST_KEY_NSMicrophoneUsageDescription = ") {
            problems.append("no microphone usage description in every configuration")
        }
        if !everyConfiguration("INFOPLIST_KEY_NSLocalNetworkUsageDescription = ") {
            problems.append("no local network usage description in every configuration")
        }
        if project.contains("NSDesktopFolderUsageDescription") {
            problems.append("a Desktop folder description, for a folder Kannu never touches")
        }
        if !everyConfiguration("ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES;")
            || !entitlements.contains("<key>com.apple.security.device.audio-input</key>") {
            problems.append("audio input is off")
        }
        if !everyConfiguration("ENABLE_RESOURCE_ACCESS_CAMERA = NO;") || entitlements.contains("com.apple.security.device.camera") {
            problems.append("the camera entitlement is on, with nothing that captures video")
        }
        let recording = assistant.components(separatedBy: "private func startRecording() {").dropFirst().first ?? ""
        let beforeRecorder = recording.components(separatedBy: "AVAudioRecorder(url:").first ?? ""
        if !beforeRecorder.contains("switch AVCaptureDevice.authorizationStatus(for: .audio) {")
            || !beforeRecorder.contains("AVCaptureDevice.requestAccess(for: .audio)") {
            problems.append("Screen Assistant records without asking for the microphone")
        }
        return problems
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
