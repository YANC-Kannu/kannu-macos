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

import AppKit
import SwiftUI

// The views in this folder take parameters only: none observes a manager, a store or a default,
// and none runs a timer or a repeating animation. `ContentView` and `NotchHomeView` read the one
// published call and hand it in (`HomeCallPageRulesTests`).

/// What stands for the calling app.
enum CallIconSource: Equatable {
    /// The installed app's own icon, by bundle ID.
    case app(bundleID: String)
    /// A symbol on a tile: the snapshot boards, which never show another company's logo and never
    /// read this Mac's apps.
    case standIn(symbol: String, tile: Color)
}

/// A call's elapsed time.
enum CallElapsed: Equatable {
    /// Counting up from the moment the call connected.
    case since(Date)
    /// A fixed reading: the snapshot boards.
    case fixed(String)
}

/// The installed apps' icons, read once each. A call's app is read when its pill or page first
/// draws; `NSWorkspace` needs no permission for it.
@MainActor
enum CallAppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let icon = AppIconAsNSImage(for: bundleID) else { return nil }
        icons[bundleID] = icon
        return icon
    }
}

/// The calling app's icon, filling the square it is given. Still: it never scales, pulses or
/// animates, like the agent pill's icon.
struct CallAppIcon: View {
    let source: CallIconSource

    var body: some View {
        switch source {
        case let .app(bundleID):
            if let icon = CallAppIconCache.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            } else {
                // The app is not where NSWorkspace can find it: a phone on a tile.
                tile(symbol: "phone.fill", color: .green)
            }
        case let .standIn(symbol, color):
            tile(symbol: symbol, color: color)
        }
    }

    private func tile(symbol: String, color: Color) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(color)
                Image(systemName: symbol)
                    .font(.system(size: side * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// The elapsed time as one self-updating text. The system redraws it once a second; nothing here
/// keeps a clock.
struct CallElapsedText: View {
    let elapsed: CallElapsed

    var body: some View {
        switch elapsed {
        case let .since(start):
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        case let .fixed(reading):
            Text(verbatim: reading)
        }
    }
}

/// The phone glyph beside a call's time: a handset while it runs, an incoming handset while it rings.
enum CallGlyph {
    static func symbol(isRinging: Bool) -> String {
        isRinging ? "phone.arrow.down.left.fill" : "phone.fill"
    }
}

/// What VoiceOver reads for a call's pill and page.
enum CallAccessibility {
    static func label(appName: String, isRinging: Bool) -> String {
        isRinging
            ? String(localized: "Incoming call, \(appName)")
            : String(localized: "Call in progress, \(appName)")
    }
}

/// The call pill on the closed notch, as laid out by `ClosedCallPillLayout`: the app's icon
/// centred in the left wing, the housing's width left clear, and in the right wing the phone glyph
/// with the elapsed time (or the ringing glyph alone) and the camera glyph while the camera is on.
struct CallLiveActivity: View {
    @Environment(\.notchForeground) private var notchForeground

    let layout: ClosedCallPillLayout
    let icon: CallIconSource
    /// Nil while it rings.
    let elapsed: CallElapsed?
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 0) {
            CallAppIcon(source: icon)
                .frame(width: layout.iconSize, height: layout.iconSize)
                .frame(width: layout.wingWidth, height: layout.closedHeight)

            Color.clear
                .frame(width: layout.housingWidth, height: layout.closedHeight)

            HStack(spacing: ClosedCallPillLayout.spacing) {
                Image(systemName: CallGlyph.symbol(isRinging: elapsed == nil))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .frame(width: ClosedCallPillLayout.glyphWidth)
                if layout.showsTime, let elapsed {
                    CallElapsedText(elapsed: elapsed)
                        .font(SettingsTheme.font(size: 11, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(notchForeground.opacity(0.9))
                        .frame(width: ClosedCallPillLayout.timeWidth, alignment: .leading)
                }
                if layout.showsCamera {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .frame(width: ClosedCallPillLayout.glyphWidth)
                }
            }
            .frame(width: layout.wingWidth, height: layout.closedHeight)
        }
        .frame(width: layout.width, height: layout.closedHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
