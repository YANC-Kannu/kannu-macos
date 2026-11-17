/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 * Copyright (C) 2024-2026 Atoll Contributors
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

final class LockScreenLiveActivityOverlayModel: ObservableObject {
	@Published var scale: CGFloat = 0.6
	@Published var opacity: Double = 0
	/// The attention alert presented this pill for its flash (`flashForAttentionAlert`): it carries the
	/// sideways pill's dot and icon for as long as it shows. Reset by the next lock or unlock.
	@Published var showsAgentForAlert = false
}

/// A pinned sideways reveal on the lock-screen pill, for snapshot boards.
struct AgentLockPillPreview: Equatable {
	let state: AgentTrafficLightState
	let iconSource: AgentProviderIconSource?
}

struct LockScreenLiveActivityOverlay: View {
	@ObservedObject var model: LockScreenLiveActivityOverlayModel
	@ObservedObject var animator: LockIconAnimator
	let notchSize: CGSize
	var isDynamicIslandMode: Bool = false
	/// Snapshot boards only: a pinned attention flash instead of the live one.
	var attentionPreview: AttentionAlertPreview? = nil
	/// Snapshot boards only: a pinned agent reveal instead of the live one.
	var agentPreview: AgentLockPillPreview? = nil

	/// The light's mirror, never the monitor (docs/REGRESSIONS.md entry 10): only a state switch is read here,
	/// and `AgentTrafficLightIndicator` draws the dot and icon.
	@ObservedObject private var agentLight = CursorAgentStatusMonitor.shared.projection
	@Default(.agentPillLayout) private var agentPillLayout
	@Default(.enableAgentStatusFeature) private var enableAgentStatusFeature
	/// The sideways reveal on this pill: set by a state switch while locked, cleared by one sleep.
	@State private var agentRevealDeadline: Date?

	private var indicatorSize: CGFloat {
		max(0, notchSize.height - 12)
	}

	private var horizontalPadding: CGFloat {
		isDynamicIslandMode ? 8 : cornerRadiusInsets.closed.bottom
	}

	private var totalWidth: CGFloat {
		notchSize.width + (indicatorSize * 2) + (horizontalPadding * 2)
	}

	private var collapsedScale: CGFloat {
		Self.collapsedScale(for: notchSize)
	}

	private var topOffset: CGFloat {
		isDynamicIslandMode ? dynamicIslandTopOffset : 0
	}

    @State private var isHovering: Bool = false

	/// The sideways pill on the lock screen: during a reveal (a state switch while locked, or the attention
	/// alert's flash), the dot stands where the lock icon was and the agent's app icon fills the other wing;
	/// then the lock icon returns. Only while the lock icon is fully locked, so unlocking still animates it.
	/// Below the notch (`AgentPillLayout.belowNotch`) leaves this pill as it was.
	private var showsAgent: Bool {
		if agentPreview != nil { return true }
		guard agentPillLayout == .sideways, enableAgentStatusFeature, agentLight.shouldShowTrafficLight,
			  animator.progress >= 0.999 else { return false }
		return agentRevealDeadline != nil || model.showsAgentForAlert
	}

	var body: some View {
		ZStack {
			if showsAgent {
				agentRow
					.transition(.opacity)
			} else {
				lockRow
					.transition(.opacity)
			}
		}
		.animation(.easeInOut(duration: 0.2), value: showsAgent)
		.frame(width: notchSize.width + (indicatorSize * 2), height: notchSize.height)
		.padding(.horizontal, horizontalPadding)
		.background(Color.black)
		// While locked the notch windows are hidden and this pill is the only Kannu window on
		// screen, so the attention alert draws here too.
		.overlay { AttentionAlertOverlay(preview: attentionPreview) }
		.clipShape(
			isDynamicIslandMode
				? AnyShape(DynamicIslandPillShape(
					cornerRadius: max(notchSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed)
				  ))
				: AnyShape(NotchShape(
					topCornerRadius: cornerRadiusInsets.closed.top,
					bottomCornerRadius: cornerRadiusInsets.closed.bottom
				  ))
		)
		.padding(.top, topOffset)
		.frame(width: totalWidth, height: notchSize.height + topOffset)
		.scaleEffect(x: max(model.scale, collapsedScale) * (isHovering ? 1.03 : 1.0), 
                     y: 1 * (isHovering ? 1.03 : 1.0), 
                     anchor: .center)
		.opacity(model.opacity)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovering = hovering
            }
            if hovering {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
        }
		.onChange(of: agentLight.trafficLightState) { _, _ in armAgentReveal() }
		.onChange(of: agentLight.shouldShowTrafficLight) { _, _ in armAgentReveal() }
		// One sleep per reveal, never a timer: the dot hands back to the lock icon by itself.
		.task(id: agentRevealDeadline) {
			guard let deadline = agentRevealDeadline else { return }
			try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
			if !Task.isCancelled { agentRevealDeadline = nil }
		}
	}

	private var lockRow: some View {
		HStack(spacing: 0) {
			Color.clear
				.overlay(alignment: .leading) {
					LockIconProgressView(progress: animator.progress)
						.frame(width: indicatorSize, height: indicatorSize)
				}
				.frame(width: indicatorSize, height: notchSize.height)

			Rectangle()
				.fill(.clear)
				.frame(width: notchSize.width, height: notchSize.height)

			Color.clear
				.frame(width: indicatorSize, height: notchSize.height)
		}
	}

	@ViewBuilder
	private var agentRow: some View {
		if let agentPreview {
			AgentLockPillRow(wingWidth: indicatorSize, housingWidth: notchSize.width, height: notchSize.height,
							 iconSource: agentPreview.iconSource, symbolsOnly: true, accessibilityLabel: "") {
				AgentTrafficLightDots(style: .minimal, state: agentPreview.state)
			}
		} else {
			AgentTrafficLightIndicator(placement: .lockPill(wingWidth: indicatorSize, housingWidth: notchSize.width,
															height: notchSize.height))
		}
	}

	/// A switch of the published light while locked starts the same 7 s reveal the notch uses.
	private func armAgentReveal() {
		guard agentPillLayout == .sideways, enableAgentStatusFeature, agentLight.shouldShowTrafficLight,
			  LockScreenManager.shared.isLocked else { return }
		agentRevealDeadline = Date().addingTimeInterval(notchRevealHoldSeconds)
	}
}

extension LockScreenLiveActivityOverlay {
	static func collapsedScale(for notchSize: CGSize, isDynamicIslandMode: Bool = false) -> CGFloat {
		let indicatorSize = max(0, notchSize.height - 12)
		let horizontalPadding = isDynamicIslandMode ? 8.0 : cornerRadiusInsets.closed.bottom
		let totalWidth = notchSize.width + (indicatorSize * 2) + (horizontalPadding * 2)
		guard totalWidth > 0 else { return 1 }
		return notchSize.width / totalWidth
	}
}
