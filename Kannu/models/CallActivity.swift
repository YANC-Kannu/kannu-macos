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

import Foundation

/// An app whose calls the notch shows. Pure, in the logic target.
struct CallApp: Equatable, Identifiable {
    /// A stable key of Kannu's own, never shown.
    let id: String
    /// The app's name as its maker writes it. A brand, so it is not translated.
    let name: String
    /// The app's own bundle ID: where its icon comes from.
    let bundleID: String
    /// The bundle IDs its audio may run under. A process matches when its bundle ID is one of
    /// these or starts with one followed by a dot, which is how a helper is named
    /// (`com.example.app.helper` for `com.example.app`).
    let processPrefixes: [String]
    /// Whether a real call was measured on a Mac. An unverified app is matched by its public
    /// bundle ID only, and docs/SETTINGS.md lists it as such.
    let isVerified: Bool
    /// Whether this app's calls were measured to capture from a device they also play to, and
    /// its recordings not to (`CallAudioProcess.capturesFromOutputDevice`). Then only such a
    /// capture starts a call. False keeps the plain rule, capturing and playing, for an app where
    /// the difference was not measured.
    var callsCaptureFromOutput = false

    func matches(processBundleID: String) -> Bool {
        let candidate = processBundleID.lowercased()
        return processPrefixes.contains { prefix in
            let prefix = prefix.lowercased()
            return candidate == prefix || candidate.hasPrefix(prefix + ".")
        }
    }
}

/// The apps Kannu recognises a call in. Browsers are left out on purpose: a browser holding the
/// microphone is not necessarily a call.
enum CallAppCatalog {
    static let apps: [CallApp] = [
        // Measured: a call captures from the microphone and the speakers (echo cancellation),
        // a voice note from the microphone alone, and both capture and play throughout.
        CallApp(id: "whatsapp", name: "WhatsApp", bundleID: "net.whatsapp.WhatsApp",
                processPrefixes: ["net.whatsapp.WhatsApp"], isVerified: true, callsCaptureFromOutput: true),
        // A huddle's audio runs in a helper, `com.tinyspeck.slackmacgap.helper` (measured).
        CallApp(id: "slack", name: "Slack", bundleID: "com.tinyspeck.slackmacgap",
                processPrefixes: ["com.tinyspeck.slackmacgap"], isVerified: true),
        CallApp(id: "zoom", name: "Zoom", bundleID: "us.zoom.xos",
                processPrefixes: ["us.zoom.xos"], isVerified: false),
        CallApp(id: "teams", name: "Microsoft Teams", bundleID: "com.microsoft.teams2",
                processPrefixes: ["com.microsoft.teams2", "com.microsoft.teams"], isVerified: false),
        CallApp(id: "discord", name: "Discord", bundleID: "com.hnc.Discord",
                processPrefixes: ["com.hnc.Discord"], isVerified: false),
        CallApp(id: "telegram", name: "Telegram", bundleID: "ru.keepcoder.Telegram",
                processPrefixes: ["ru.keepcoder.Telegram", "com.tdesktop.Telegram"], isVerified: false),
        CallApp(id: "signal", name: "Signal", bundleID: "org.whispersystems.signal-desktop",
                processPrefixes: ["org.whispersystems.signal-desktop"], isVerified: false),
    ]

    /// The catalog app a process belongs to, by its bundle ID or a helper's.
    static func app(forProcessBundleID bundleID: String) -> CallApp? {
        apps.first { $0.matches(processBundleID: bundleID) }
    }
}

/// One catalog app's process as CoreAudio reports it: whether it is capturing (input running) and
/// whether it is playing (output running). What `CallAudioProcessMonitor` hands over.
struct CallAudioProcess: Equatable {
    let bundleID: String
    let isCapturing: Bool
    let isPlaying: Bool
    /// One of the devices it captures from is one it also plays to. That is echo cancellation
    /// taking the output as its reference (measured on a WhatsApp call: it captured from the
    /// microphone and the speakers), or a single device that is both microphone and speaker, a
    /// headset. A plain recording on a separate microphone and speaker shares none (measured on a
    /// WhatsApp voice note, which captured from the microphone alone while it also played).
    let capturesFromOutputDevice: Bool

    init(bundleID: String, isCapturing: Bool, isPlaying: Bool, capturesFromOutputDevice: Bool = false) {
        self.bundleID = bundleID
        self.isCapturing = isCapturing
        self.isPlaying = isPlaying
        self.capturesFromOutputDevice = capturesFromOutputDevice
    }
}

/// A call the notch shows: which app, and whether it rings or has been running since a moment.
struct CallActivity: Equatable {
    enum Phase: Equatable {
        case ringing
        case ongoing(since: Date)
    }

    let app: CallApp
    let phase: Phase

    var isRinging: Bool { phase == .ringing }

    /// When the call connected; nil while it rings.
    var startedAt: Date? {
        if case let .ongoing(since) = phase { return since }
        return nil
    }
}

/// Turns "which catalog apps capture and play" into no call, a ring, or a call running since a
/// moment.
///
/// - **A call starts** when an app both captures and plays. A ringtone is output with no input,
///   so it starts none. A recording made in the app can do both (measured: a WhatsApp voice note
///   captures and plays for its whole length), so for an app whose calls were measured to
///   capture from their output device (`CallApp.callsCaptureFromOutput`) a call also needs that,
///   which the recording lacks. On a headset that is microphone and speaker in one, the two
///   cannot be told apart, and a recording there reads as a call.
/// - **A call goes on** while its app still captures. Its output may come and go.
/// - **A call ends** `dropGrace` seconds after its app was first seen not capturing. The grace
///   covers a change of microphone, which stops and restarts the app's capture, so the pill and
///   its clock do not restart.
/// - **A ring** is handed in by whoever saw it (the ring observer); a call that connects, or one
///   already running, outranks it.
///
/// A value type with no clock of its own: every call passes `now`.
struct CallActivityResolver: Equatable {
    /// How long a call outlives its app's capture.
    static let dropGrace: TimeInterval = 2

    private(set) var activity: CallActivity?
    /// The first reading that showed the running call's app no longer capturing. The grace runs
    /// from here, not from the last reading that showed the capture: readings are up to 2 s apart
    /// while the microphone is in use, and that gap must not eat the grace.
    private var droppedAt: Date?

    /// When the running call ends unless its app captures again: `dropGrace` after `droppedAt`.
    /// Nil with no call, while it rings, and while its app is capturing. Whoever owns the resolver
    /// calls `update` again at this moment, because nothing else will: once the microphone is
    /// free, no event and no re-read arrives.
    private(set) var dropDeadline: Date?

    /// Takes one reading and returns the call to show.
    @discardableResult
    mutating func update(processes: [CallAudioProcess], ringing: CallApp? = nil, now: Date) -> CallActivity? {
        let capturing = Self.apps(in: processes) { _, usage in usage.isCapturing }
        let connected = Self.apps(in: processes) { app, usage in
            usage.isCapturing && usage.isPlaying && (!app.callsCaptureFromOutput || usage.capturesFromOutputDevice)
        }

        if let current = activity, case .ongoing = current.phase {
            if capturing.contains(current.app) {
                droppedAt = nil
                dropDeadline = nil
                return activity
            }
            let dropped = droppedAt ?? now
            let deadline = dropped.addingTimeInterval(Self.dropGrace)
            if now < deadline {
                droppedAt = dropped
                dropDeadline = deadline
                return activity
            }
        }

        // No call was running, or the one that was has ended.
        droppedAt = nil
        dropDeadline = nil
        if let app = connected.first {
            activity = CallActivity(app: app, phase: .ongoing(since: now))
        } else if let ringing {
            activity = CallActivity(app: ringing, phase: .ringing)
        } else {
            activity = nil
        }
        return activity
    }

    /// The catalog apps whose processes, read as one, pass `test`, in the catalog's order.
    private static func apps(in processes: [CallAudioProcess], where test: (CallApp, CallAudioProcess) -> Bool) -> [CallApp] {
        CallAppCatalog.apps.filter { app in
            // An app's capture and its playback may sit in different helpers, so the test reads
            // the app's processes as one.
            let own = processes.filter { app.matches(processBundleID: $0.bundleID) }
            guard !own.isEmpty else { return false }
            return test(app, CallAudioProcess(bundleID: app.bundleID,
                                              isCapturing: own.contains { $0.isCapturing },
                                              isPlaying: own.contains { $0.isPlaying },
                                              capturesFromOutputDevice: own.contains { $0.capturesFromOutputDevice }))
        }
    }
}
