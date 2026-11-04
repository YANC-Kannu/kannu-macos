/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Kannu (കണ്ണ്)
 * See NOTICE for details.
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

struct StatsSettings: View {
    @ObservedObject var statsManager = StatsManager.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.statsStopWhenNotchCloses) var statsStopWhenNotchCloses
    @Default(.statsUpdateInterval) var statsUpdateInterval
    @Default(.showCpuGraph) var showCpuGraph
    @Default(.showMemoryGraph) var showMemoryGraph
    @Default(.showGpuGraph) var showGpuGraph
    @Default(.showNetworkGraph) var showNetworkGraph
    @Default(.showDiskGraph) var showDiskGraph
    @Default(.cpuTemperatureUnit) var cpuTemperatureUnit

    private func highlightID(_ title: String) -> String {
        SettingsTab.stats.highlightID(for: title)
    }

    var enabledGraphsCount: Int {
        [showCpuGraph, showMemoryGraph, showGpuGraph, showNetworkGraph, showDiskGraph].filter { $0 }.count
    }

    private var formattedUpdateInterval: String {
        let seconds = Int(statsUpdateInterval.rounded())
        if seconds >= 60 {
            return "60 s (1 min)"
        } else if seconds == 1 {
            return "1 s"
        } else {
            return "\(seconds) s"
        }
    }

    private var shouldShowStatsBatteryWarning: Bool {
        !statsStopWhenNotchCloses && statsUpdateInterval <= 5
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableStatsFeature) {
                    Text("Enable system stats monitoring")
                }
                .settingsHighlight(id: highlightID("Enable system stats monitoring"))
                .onChange(of: enableStatsFeature) { _, newValue in
                    if !newValue {
                        statsManager.stopMonitoring()
                    }
                    // Note: Smart monitoring will handle starting when switching to stats tab
                }

            } header: {
                SettingsSectionHeader("General")
            } footer: {
                SettingsFooter("When enabled, the Stats tab will display real-time system performance graphs. This feature requires system permissions and may use additional battery.")
            }

            if enableStatsFeature {
                Section {
                    SettingsRow("Stop monitoring after closing the notch", description: "When enabled, stats monitoring stops a few seconds after the notch closes.") {
                        Defaults.Toggle(key: .statsStopWhenNotchCloses) {
                            Text("Stop monitoring after closing the notch")
                        }
                    }
                    .settingsHighlight(id: highlightID("Stop monitoring after closing the notch"))

                    SettingsSliderRow("Update interval",
                                      description: "Controls how often system metrics refresh while monitoring is active.",
                                      value: $statsUpdateInterval, in: 1...60, step: 1,
                                      valueText: Text(formattedUpdateInterval))

                    if shouldShowStatsBatteryWarning {
                        Label {
                            Text("High-frequency updates without a timeout can increase battery usage.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                    }
                } header: {
                    SettingsSectionHeader("Monitoring Behavior")
                } footer: {
                    SettingsFooter("Sampling can continue while the notch is closed when the timeout is disabled.")
                }

                Section {
                    Defaults.Toggle(key: .showCpuGraph) {
                        Text("CPU Usage")
                    }
                    .settingsHighlight(id: highlightID("CPU Usage"))

                    if showCpuGraph {
                        Picker("Temperature unit", selection: $cpuTemperatureUnit) {
                            ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .settingsHighlight(id: highlightID("Temperature unit"))
                    }
                    Defaults.Toggle(key: .showMemoryGraph) {
                        Text("Memory Usage")
                    }
                    .settingsHighlight(id: highlightID("Memory Usage"))
                    Defaults.Toggle(key: .showGpuGraph) {
                        Text("GPU Usage")
                    }
                    .settingsHighlight(id: highlightID("GPU Usage"))
                    Defaults.Toggle(key: .showNetworkGraph) {
                        Text("Network Activity")
                    }
                    .settingsHighlight(id: highlightID("Network Activity"))
                    Defaults.Toggle(key: .showDiskGraph) {
                        Text("Disk I/O")
                    }
                    .settingsHighlight(id: highlightID("Disk I/O"))
                } header: {
                    SettingsSectionHeader("Graph Visibility")
                } footer: {
                    if enabledGraphsCount >= 4 {
                        SettingsFooter("With \(enabledGraphsCount) graphs enabled, the Dynamic Island will expand horizontally to accommodate all graphs in a single row.")
                    } else {
                        SettingsFooter("Each graph can be individually enabled or disabled. Network activity shows download/upload speeds, and disk I/O shows read/write speeds.")
                    }
                }

                Section {
                    HStack {
                        Text("Monitoring Status")
                            .textSelection(.enabled)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statsManager.isMonitoring ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(statsManager.isMonitoring ? "Active" : "Stopped")
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    if statsManager.isMonitoring {
                        if showCpuGraph {
                            HStack {
                                Text("CPU Usage")
                                    .textSelection(.enabled)
                                Spacer()
                                Text(statsManager.cpuUsageString)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if showMemoryGraph {
                            HStack {
                                Text("Memory Usage")
                                    .textSelection(.enabled)
                                Spacer()
                                Text(statsManager.memoryUsageString)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if showGpuGraph {
                            HStack {
                                Text("GPU Usage")
                                    .textSelection(.enabled)
                                Spacer()
                                Text(statsManager.gpuUsageString)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if showNetworkGraph {
                            HStack {
                                Text("Network Download")
                                    .textSelection(.enabled)
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.networkDownload))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            HStack {
                                Text("Network Upload")
                                    .textSelection(.enabled)
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.networkUpload))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if showDiskGraph {
                            HStack {
                                Text("Disk Read")
                                    .textSelection(.enabled)
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.diskRead))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            HStack {
                                Text("Disk Write")
                                    .textSelection(.enabled)
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.diskWrite))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        HStack {
                            Text("Last Updated")
                                .textSelection(.enabled)
                            Spacer()
                            Text(statsManager.lastUpdated, style: .relative)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    SettingsSectionHeader("Live Performance Data")
                }

                Section {
                    SettingsActionRow {
                        Button("Clear Data") {
                            statsManager.clearHistory()
                        }
                        .disabled(statsManager.isMonitoring)

                        Button(statsManager.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                            if statsManager.isMonitoring {
                                statsManager.stopMonitoring()
                            } else {
                                statsManager.startMonitoring()
                            }
                        }
                    }
                } header: {
                    SettingsSectionHeader("Controls")
                }
            }
        }
        .navigationTitle("Stats")
    }
}
