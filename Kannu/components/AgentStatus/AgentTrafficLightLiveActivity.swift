import Defaults
import SwiftUI

/// The three-dot (or single-dot) traffic light itself, independent of any live state.
///
/// Shared by the notch indicator and by the Settings / onboarding pickers so a preview can
/// never drift from what the notch actually draws.
struct AgentTrafficLightDots: View {
    let style: AgentTrafficLightStyle
    let state: AgentTrafficLightState
    /// Whether the lit dot should breathe. Previews pass false; the live indicator decides
    /// per-state (red only inside its completion window, yellow/green for as long as they're lit).
    var isPulsing: Bool = false
    /// The live notch indicator draws its dots with Core Animation (`TrafficLightDot`), so the
    /// breath costs the main thread nothing; previews keep plain SwiftUI circles.
    var live: Bool = false
    var dotSize: CGFloat = 10
    var spacing: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Default(.agentActiveColor) private var activeColor
    @Default(.agentAwaitingInputColor) private var awaitingColor
    @Default(.agentStoppedColor) private var stoppedColor

    /// The one colour the current state lights up, or nil when nothing is lit (`.inactive`).
    /// The three `shows…TrafficLight` booleans are mutually exclusive by construction.
    private var litColor: Color? {
        state.litPalette(active: activeColor, awaiting: awaitingColor, stopped: stoppedColor)?.color
    }

    var body: some View {
        HStack(spacing: spacing) {
            switch style {
            case .classic:
                dot(stoppedColor.color, isActive: state.showsRedTrafficLight)
                dot(awaitingColor.color, isActive: state.showsYellowTrafficLight)
                dot(activeColor.color, isActive: state.showsGreenTrafficLight)
            case .minimal:
                // Nothing is lit when inactive, and the indicator is hidden in that case
                // anyway — draw nothing rather than inventing a colour.
                if let litColor {
                    dot(litColor, isActive: true)
                }
            }
        }
    }

    @ViewBuilder
    private func dot(_ color: Color, isActive: Bool) -> some View {
        let tint = color.opacity(isActive ? 1.0 : 0.2)
        if live {
            // The inner frame leaves room for the breath (1.3×); the outer keeps the layout slot.
            TrafficLightDot(color: tint, diameter: dotSize, pulsing: isActive && isPulsing && !reduceMotion)
                .frame(width: dotSize * TrafficLightPulseSpec.scale, height: dotSize * TrafficLightPulseSpec.scale)
                .frame(width: dotSize, height: dotSize)
        } else {
            Circle()
                .fill(tint)
                .frame(width: dotSize, height: dotSize)
        }
    }
}

/// The closed-notch cue for an unacknowledged high-severity security finding. Deliberately
/// monochrome: white on the notch, never one of the three light colours, so it cannot be read
/// as an agent state and cannot collide with a custom palette. The *shape* carries the meaning.
struct SecurityShieldGlyph: View {
    @Environment(\.notchForeground) private var notchForeground
    var size: CGFloat = 9

    var body: some View {
        Image(systemName: "exclamationmark.shield.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(notchForeground.opacity(0.9))
            .accessibilityLabel(String(localized: "Unacknowledged high-severity security finding"))
    }
}

extension AgentTrafficLightStyle {
    /// How many dots the style draws in the sideways pill's left wing: Classic three, Minimal the lit one.
    var pillDotCount: Int {
        switch self {
        case .classic: return 3
        case .minimal: return 1
        }
    }
}

/// The agent's app icon in the sideways pill's right wing, and in the lock-screen pill's. It never scales,
/// pulses or animates: on 2026-08-19 the provider logo left the closed notch because it pulsed 1.0→1.3 and
/// read as the notch blinking (CHANGELOG), so it came back still, and all motion stays on the dot.
struct AgentPillIcon: View {
    /// Nil draws nothing (a security cue with no agent): the wing keeps its width.
    let source: AgentProviderIconSource?
    let size: CGFloat
    /// Boards, onboarding and Brain's preview: an SF Symbol stand-in, never another company's logo.
    var symbolsOnly = false

    var body: some View {
        Group {
            if let source {
                AgentProviderIconView(source: source, size: size, symbolsOnly: symbolsOnly)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The sideways pill as laid out by `ClosedAgentPillLayout`: the lights (and the shield) centred in the left
/// wing, the housing's width left clear, the icon centred in the right wing. Drawn by the live indicator and,
/// with fixtures, by the boards, onboarding and Brain's preview, so none of them can drift from the notch.
struct AgentSidewaysPillRow<Lights: View>: View {
    let layout: ClosedAgentPillLayout
    let iconSource: AgentProviderIconSource?
    var symbolsOnly = false
    let accessibilityLabel: String
    @ViewBuilder let lights: () -> Lights

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: ClosedAgentPillLayout.shieldSpacing) {
                lights()
                if layout.showsShield {
                    SecurityShieldGlyph()
                        .frame(width: ClosedAgentPillLayout.shieldWidth)
                }
            }
            .frame(width: layout.wingWidth, height: layout.closedHeight)

            Color.clear
                .frame(width: layout.housingWidth, height: layout.closedHeight)

            AgentPillIcon(source: iconSource, size: layout.iconSize, symbolsOnly: symbolsOnly)
                .frame(width: layout.wingWidth, height: layout.closedHeight)
        }
        .frame(width: layout.width, height: layout.closedHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The lock-screen pill during a reveal: the lit dot in the lock icon's wing, the housing clear, the app
/// icon in the other wing. The pill's wings are its own (`closed height − 12`), so its window never
/// changes size (docs/REGRESSIONS.md entry 17); one dot is what fits a wing that size.
struct AgentLockPillRow<Light: View>: View {
    let wingWidth: CGFloat
    let housingWidth: CGFloat
    let height: CGFloat
    let iconSource: AgentProviderIconSource?
    var symbolsOnly = false
    let accessibilityLabel: String
    @ViewBuilder let light: () -> Light

    var body: some View {
        HStack(spacing: 0) {
            light()
                .frame(width: wingWidth, height: height)
            Color.clear
                .frame(width: housingWidth, height: height)
            AgentPillIcon(source: iconSource, size: wingWidth, symbolsOnly: symbolsOnly)
                .frame(width: wingWidth, height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The closed notch with the light where the chosen layout puts it, drawn still: plain dots (never the live
/// breathing ones) and a symbol stand-in for the app icon, so nothing here repeats while Brain is closed
/// (docs/REGRESSIONS.md entry 22) and no other company's logo shows. Brain's Traffic light preview and
/// onboarding's style cards draw it; it lives with the notch's views because it paints the notch's black.
struct AgentPillLayoutPreview: View {
    let style: AgentTrafficLightStyle
    let layout: AgentPillLayout
    var state: AgentTrafficLightState = .executing

    private static let closedHeight: CGFloat = 24
    private static let housingWidth: CGFloat = 40

    var body: some View {
        Group {
            switch layout {
            case .sideways:
                AgentSidewaysPillRow(
                    layout: ClosedAgentPillLayout(closedHeight: Self.closedHeight, housingWidth: Self.housingWidth,
                                                  dotCount: style.pillDotCount, showsShield: false),
                    iconSource: .claude,
                    symbolsOnly: true,
                    accessibilityLabel: ""
                ) {
                    AgentTrafficLightDots(style: style, state: state)
                }
                .background(NotchShape(topCornerRadius: 4, bottomCornerRadius: 8).fill(Color.black))
            case .belowNotch:
                VStack(spacing: 0) {
                    Color.clear.frame(height: Self.closedHeight)
                    AgentTrafficLightDots(style: style, state: state)
                        .frame(height: 18, alignment: .top)
                }
                .frame(width: Self.housingWidth + 72)
                .background(NotchShape(topCornerRadius: 4, bottomCornerRadius: 10).fill(Color.black))
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Agent status: working, Claude Code": what VoiceOver reads for a pill that shows the app's icon.
enum AgentPillAccessibility {
    static func label(state: String, appName: String?) -> String {
        guard let appName, !appName.isEmpty else { return state }
        return String(localized: "\(state), \(appName)")
    }
}

struct AgentTrafficLightIndicator: View {
    /// Where the indicator draws. Every placement is drawn here, by the one view that observes the monitor
    /// (`ClosedNotchObservationTests`), so the icon and the dots always follow the same session.
    enum Placement: Equatable {
        /// The dots, and the shield beside them: the band below the notch, the music and timer centres,
        /// and every display without a notch.
        case centred
        /// The sideways pill on a notched MacBook: the dots in a left wing, the housing, the agent's app
        /// icon in a right wing, at the closed height (`ClosedAgentPillLayout`).
        case beside(housingWidth: CGFloat, closedHeight: CGFloat)
        /// The lock-screen pill during a reveal: the lit dot where the lock icon was, the icon opposite.
        case lockPill(wingWidth: CGFloat, housingWidth: CGFloat, height: CGFloat)
    }

    @ObservedObject var agentStatusMonitor = CursorAgentStatusMonitor.shared
    @ObservedObject private var findingsStore = SecurityFindingsStore.shared
    @Default(.showAgentStoppedIndicator) private var showAgentStoppedIndicator
    @Default(.agentTrafficLightStyle) private var trafficLightStyle
    @Default(.adrHighAlertMode) private var highAlertMode

    var placement: Placement = .centred

    /// True while `SecurityAlertPill` is on screen beside these dots: the pill carries its own
    /// shield, and two rendered side by side until this existed.
    var suppressSecurityGlyph = false

    /// A pending high finding shows a shield beside the dots in every mode but Off. It rides
    /// along wherever the dots are drawn (standalone, or inside the music pill).
    private var showsSecurityGlyph: Bool {
        !suppressSecurityGlyph && highAlertMode.showsGlyph && findingsStore.groupRanking.pendingHighCount > 0
    }
    /// Keyed by session ID — records when a session first became non-active (stopped/inactive),
    /// so a just-finished run can pulse red briefly before settling.
    @State private var completionTimestamps: [String: Date] = [:]
    /// Bumped once when the red pulse window ends, so the body re-evaluates at that moment. (A
    /// 1 Hz `TimelineView` used to redraw this view every second for the whole run just for that.)
    @State private var attentionWake = Date.distantPast

    /// When the primary session finished, if it did (the red pulse window starts there).
    private var primaryCompletion: Date? {
        primarySession.flatMap { completionTimestamps[$0.id] }
    }

    /// Spoken description of the aggregate state. `displayName` is a raw literal used for
    /// on-screen text, so it is not reused here — VoiceOver output is localized.
    private var accessibilityStateDescription: String {
        switch activeState {
        case .executing, .thinking:
            return String(localized: "Agent status: working")
        case .awaitingInput:
            return String(localized: "Agent status: needs your input")
        case .stopped:
            return String(localized: "Agent status: stopped")
        case .inactive:
            return String(localized: "Agent status: no agents running")
        }
    }

    private var activeState: AgentTrafficLightState {
        if agentStatusMonitor.trafficLightState == .inactive && showAgentStoppedIndicator {
            return .stopped
        }
        return agentStatusMonitor.trafficLightState
    }

    private var primarySession: AgentSessionStatus? {
        let visible = agentStatusMonitor.sessions.filter { $0.isVisible && !AgentTrafficLightMapper.isSimulationSession($0) }
        return AgentTrafficLightMapper.primarySession(from: visible)
    }

    /// The app the pill's icon stands for: the session the light is showing.
    private var primaryIconSource: AgentProviderIconSource? {
        primarySession.map { AgentProviderIconSource(rawProvider: $0.provider) }
    }

    private var pillAccessibilityLabel: String {
        AgentPillAccessibility.label(state: accessibilityStateDescription, appName: primarySession?.providerLabel)
    }

    /// All non-simulation visible sessions, newest-first.
    private var visibleSessions: [AgentSessionStatus] {
        agentStatusMonitor.sessions
            .filter { $0.isVisible && !AgentTrafficLightMapper.isSimulationSession($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        // The notch shows exactly ONE light regardless of how many agents are running: the
        // highest-priority state across all of them (stopped > awaiting input > executing >
        // thinking), with the most recently updated chat breaking ties. There is deliberately
        // no per-agent row — the earlier one rendered provider logos instead of lights, and
        // pulsed those logos, which read as the notch blinking at you.
        //
        // Since 2.0 the sideways pill (`Placement.beside`, the default on a notched MacBook) shows
        // ONE app icon again: the primary session's, beside the light, never instead of it. It is
        // still — no scale, no pulse, no animation of its own (`AgentPillIcon`); the dot keeps all
        // the motion. `ClosedAgentPillRulesTests` pins that.
        //
        // The red pulse window is re-evaluated by one wake at its end (`.task(id:)` below), not by
        // a periodic timer.
        let now = Date()
        let _ = attentionWake
        placed(at: now)
        .task(id: AgentTrafficLightAttention.pulseChange(red: activeState.showsRedTrafficLight, completedAt: primaryCompletion, now: now)) {
            guard let end = AgentTrafficLightAttention.pulseChange(red: activeState.showsRedTrafficLight,
                                                                   completedAt: primaryCompletion, now: Date()) else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 0.05))
            if !Task.isCancelled { attentionWake = Date() }
        }
        // Track when sessions leave an active run so the completion pulse has a start time.
        .onChange(of: visibleSessions) { _, newSessions in
            let now = Date()
            // Drop timestamps for sessions that have left the visible list entirely.
            let newIDs = Set(newSessions.map(\.id))
            completionTimestamps = completionTimestamps.filter { newIDs.contains($0.key) }
            for session in newSessions {
                if session.displayState.isActiveRun {
                    // Back to active — clear any stale completion stamp.
                    completionTimestamps.removeValue(forKey: session.id)
                } else if completionTimestamps[session.id] == nil {
                    completionTimestamps[session.id] = now
                }
            }
        }
    }

    @ViewBuilder
    private func placed(at now: Date) -> some View {
        switch placement {
        case .centred:
            HStack(spacing: 6) {
                lights(at: now, style: trafficLightStyle)
                    // The dots carry the aggregate state in colour alone, and it is rendered as text
                    // nowhere — the panel shows per-session state, and only on hover.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityStateDescription)
                if showsSecurityGlyph {
                    SecurityShieldGlyph()
                }
            }
        case let .beside(housingWidth, closedHeight):
            AgentSidewaysPillRow(
                layout: ClosedAgentPillLayout(closedHeight: closedHeight, housingWidth: housingWidth,
                                              dotCount: trafficLightStyle.pillDotCount,
                                              showsShield: showsSecurityGlyph),
                iconSource: primaryIconSource,
                accessibilityLabel: pillAccessibilityLabel
            ) {
                lights(at: now, style: trafficLightStyle)
            }
        case let .lockPill(wingWidth, housingWidth, height):
            AgentLockPillRow(wingWidth: wingWidth, housingWidth: housingWidth, height: height,
                             iconSource: primaryIconSource, accessibilityLabel: pillAccessibilityLabel) {
                lights(at: now, style: .minimal)
            }
        }
    }

    /// The live dots. The breath is the only motion any placement has.
    private func lights(at now: Date, style: AgentTrafficLightStyle) -> AgentTrafficLightDots {
        AgentTrafficLightDots(
            style: style,
            state: activeState,
            isPulsing: shouldPulse(at: now),
            live: true
        )
    }

    /// Yellow and green breathe for as long as they are lit — they mean "something is happening".
    /// Red means finished, so it pulses only for `attentionWindow` after the run actually ends
    /// and then holds steady; otherwise a finished agent would blink indefinitely.
    private func shouldPulse(at now: Date) -> Bool {
        AgentTrafficLightAttention.pulses(
            yellowOrGreen: activeState.showsYellowTrafficLight || activeState.showsGreenTrafficLight,
            red: activeState.showsRedTrafficLight,
            completedAt: primaryCompletion,
            now: now
        )
    }
}

struct AgentTrafficLightLiveActivity: View {
    @EnvironmentObject var vm: KannuViewModel
    @ObservedObject private var findingsStore = SecurityFindingsStore.shared
    @ObservedObject private var doNotDisturb = DoNotDisturbManager.shared
    @Default(.adrHighAlertMode) private var highAlertMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isHovering: Bool
    let gestureProgress: CGFloat

    /// Only supplied when rendering on a display with a physical notch.
    /// Non-notch displays receive nil and retain their existing sizing.
    var physicalNotchExpandedHeight: CGFloat? = nil

    /// Must remain zero on non-notch displays.
    var trafficLightVerticalOffset: CGFloat = 0

    /// Clicking the security pill opens the panel on the agent tab, where the pinned card is.
    var onTapSecurityPill: (() -> Void)? = nil

    var onHoverAgentCenter: ((Bool) -> Void)? = nil

    /// The sideways pill (`AgentPillLayout.sideways` on a notched MacBook): the light beside the housing at
    /// the closed height, no band, and the high finding as a shield in the left wing; `SecurityAlertPill`
    /// stays with the band. False keeps the band exactly as it was.
    var sideways = false

    private var notchContentHeight: CGFloat {
        let normalHeight = max(
            0,
            vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
        )

        guard let physicalNotchExpandedHeight else {
            return normalHeight
        }

        return max(normalHeight, physicalNotchExpandedHeight)
    }

    private var outerHeight: CGFloat {
        let normalHeight = max(
            0,
            vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)
        )

        guard let physicalNotchExpandedHeight else {
            return normalHeight
        }

        return max(
            normalHeight,
            physicalNotchExpandedHeight + (isHovering ? 8 : 0)
        )
    }

    private var contentWidth: CGFloat {
        max(
            0,
            vm.closedNotchSize.width + (isHovering ? 8 : 0)
        )
    }

    /// The pill is not a sneak peek: sneak peeks are timed HUDs that auto-hide. It lives here,
    /// beside the light, and stays until the user acts (default) — or for five seconds in that
    /// mode. Deferred to glyph-only while Focus is on, so a Do Not Disturb session is not
    /// interrupted; it appears when Focus ends.
    private func pillIsVisible(at now: Date, pinned: AgentSecurityFinding) -> Bool {
        guard highAlertMode.showsPill, !doNotDisturb.isDoNotDisturbActive else { return false }
        return AgentTrafficLightAttention.pillVisible(fiveSecondMode: highAlertMode == .fiveSeconds,
                                                      firstSeen: pinned.firstSeen, now: now)
    }

    /// Bumped once when a five-second pill's time is up; the store's own snooze wake covers the
    /// rest. (A 1 Hz `TimelineView` used to re-rank every second instead.)
    @State private var pillWake = Date.distantPast

    var body: some View {
        if sideways {
            sidewaysBody
        } else {
            bandBody
        }
    }

    /// The pill beside the housing. Only the indicator observes the monitor, so it draws all three parts.
    private var sidewaysBody: some View {
        AgentTrafficLightIndicator(placement: .beside(housingWidth: contentWidth,
                                                      closedHeight: vm.effectiveClosedNotchHeight))
            .frame(height: outerHeight)
            .contentShape(Rectangle())
            .onHover { hovering in
                onHoverAgentCenter?(hovering)
            }
    }

    @ViewBuilder
    private var bandBody: some View {
        let now = Date()
        let _ = pillWake
        let groups = findingsStore.groupRanking
        let pillEnd = groups.pinnedFinding.flatMap {
            AgentTrafficLightAttention.pillChange(fiveSecondMode: highAlertMode == .fiveSeconds, firstSeen: $0.firstSeen, now: now)
        }
        let pinnedPill = groups.pinnedFinding.flatMap { pillIsVisible(at: now, pinned: $0) ? $0 : nil }
        HStack(spacing: 8) {
            AgentTrafficLightIndicator(suppressSecurityGlyph: pinnedPill != nil)
            if let pinned = pinnedPill {
                SecurityAlertPill(
                    finding: pinned,
                    extraCount: max(0, groups.pendingHighCount - 1),
                    maxWidth: min(contentWidth * 0.62, 190)
                )
                .onTapGesture { onTapSecurityPill?() }
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .task(id: pillEnd) {
            guard let pillEnd else { return }
            try? await Task.sleep(for: .seconds(max(0, pillEnd.timeIntervalSinceNow) + 0.05))
            if !Task.isCancelled { pillWake = Date() }
        }
        .offset(y: trafficLightVerticalOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: contentWidth, height: notchContentHeight)
        .frame(height: outerHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            onHoverAgentCenter?(hovering)
        }
    }
}

/// "⚠ Running MCP server nobody declared  +2" — the one high finding that owns the closed
/// notch, and how many more are waiting. Monochrome on purpose (see `SecurityShieldGlyph`).
struct SecurityAlertPill: View {
    @Environment(\.notchForeground) private var notchForeground
    let finding: AgentSecurityFinding
    let extraCount: Int
    let maxWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            SecurityShieldGlyph(size: 9)
            Text(finding.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(notchForeground.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
            if extraCount > 0 {
                Text("+\(extraCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(notchForeground.opacity(0.7))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(notchForeground.opacity(0.14)))
        .frame(maxWidth: maxWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Security finding, high: \(finding.title). Click to open."))
    }
}
