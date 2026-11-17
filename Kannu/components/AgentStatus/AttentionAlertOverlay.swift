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

import Defaults
import SwiftUI

/// The attention alert drawn over a notch's body: the notch's fill (`ContentView.notchBodyFill`) and the
/// lock-screen pill (`LockScreenLiveActivityOverlay`), each of which clips it to its own shape. A leaf:
/// it observes only `AttentionAlertManager`, which publishes twice per alert, and draws nothing between
/// alerts. `ContentView` also subscribes to the flash's id, without observing, to reveal a hidden island.
struct AttentionAlertOverlay: View {
    /// Snapshot boards only: draw this flash, pinned, instead of following the manager.
    var preview: AttentionAlertPreview? = nil

    @ObservedObject private var manager = AttentionAlertManager.shared
    @Default(.agentAwaitingInputColor) private var awaitingColor

    var body: some View {
        ZStack {
            if let preview {
                AttentionAlertFlashView(visual: preview.visual, tint: awaitingColor.neonColor, pinnedPhase: preview.phase)
            } else if let flash = manager.flash {
                AttentionAlertFlashView(visual: flash.visual, tint: awaitingColor.neonColor)
                    .id(flash.id)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A flash frozen at one point of its sweep, for snapshot boards.
struct AttentionAlertPreview: Equatable {
    let visual: AttentionAlertVisual
    let phase: CGFloat
}

/// One flash. The shimmer is two sweeps of a bright band in the awaiting-input colour, then it stops:
/// a finite `repeatCount`, never `repeatForever` and never a `TimelineView`, so nothing keeps ticking if
/// the window is hidden (docs/REGRESSIONS.md entry 22). The glow is still: the colour's wash and a
/// soft rim, for Reduce Motion.
struct AttentionAlertFlashView: View {
    static let sweepDuration: TimeInterval = 1.0
    static let sweeps = 2

    let visual: AttentionAlertVisual
    let tint: Color
    /// Pins the sweep at one point, for snapshot boards; nil animates.
    var pinnedPhase: CGFloat? = nil

    @State private var phase: CGFloat = 0

    var body: some View {
        switch visual {
        case .shimmer: shimmer
        case .glow: glow
        }
    }

    private var shimmer: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let band = max(height * 2.5, width * 0.3)
            let progress = pinnedPhase ?? phase
            LinearGradient(
                colors: [
                    .clear,
                    tint.opacity(0.25),
                    tint.opacity(0.7),
                    Color.white.opacity(0.85),
                    tint.opacity(0.7),
                    tint.opacity(0.25),
                    .clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band, height: height * 2.2)
            .rotationEffect(.degrees(18))
            .offset(x: progress * (width + band) - band, y: -height * 0.6)
            .blur(radius: 2)
        }
        .onAppear {
            guard pinnedPhase == nil else { return }
            withAnimation(.easeInOut(duration: Self.sweepDuration).repeatCount(Self.sweeps, autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var glow: some View {
        GeometryReader { proxy in
            let rim = max(2, proxy.size.height * 0.08)
            ZStack {
                tint.opacity(0.22)
                Rectangle()
                    .strokeBorder(tint.opacity(0.95), lineWidth: rim)
                    .blur(radius: rim)
            }
        }
    }
}
