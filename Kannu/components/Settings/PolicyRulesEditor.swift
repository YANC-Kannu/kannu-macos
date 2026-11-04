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

import SwiftUI

/// The "Edit rules" sheet: the agent policy as rows, no JSON. Save stays off while the draft would
/// not be a policy, and says why in the parser's words, so nothing here can disagree with the hook.
/// All reading and writing goes through `SecurityFindingsStore`, off the main actor.
struct PolicyRulesEditor: View {
    @State var draft: AgentPolicyDraft
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var showConflict = false
    @State private var saveError: String?

    var body: some View {
        SettingsSheet("Edit rules",
                      subtitle: Text("Commands and tools your agents may not use. A command rule matches the command's first word; a tool rule matches the tool's exact name."),
                      width: SettingsTheme.sheetWidthWide) {
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
                    if draft.rows.isEmpty {
                        Text("No rules yet. Add one below.")
                            .settingsDescriptionStyle()
                    }
                    ForEach($draft.rows) { $row in
                        ruleRow($row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 360)

            Button {
                draft.addRow()
            } label: {
                Label("Add rule", systemImage: "plus")
            }

            if let problem = saveError ?? draft.problem {
                SettingsErrorText(problem)
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save(replacingChanges: false) }
                .buttonStyle(SettingsButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(saving || draft.problem != nil)
        }
        .alert("The rules changed while you were editing", isPresented: $showConflict) {
            Button("Replace with mine") { save(replacingChanges: true) }
            Button("Reload") { reload() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Someone saved the policy after you opened it. Replace their version with yours, or reload and lose your edits.")
        }
    }

    private func ruleRow(_ row: Binding<AgentPolicyDraft.Row>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.rowContent) {
            SettingsSelect("Kind", selection: row.kind,
                           choices: [.command: String(localized: "Command"), .tool: String(localized: "Tool")])
            TextField(row.wrappedValue.kind == .command ? "ssh" : "WebFetch", text: row.text,
                      prompt: Text(verbatim: row.wrappedValue.kind == .command ? "ssh" : "WebFetch"))
                .font(SettingsTheme.mono)
                .frame(width: 170)
                .settingsField()
            TextField("Reason (optional)", text: row.reason, prompt: Text("Reason (optional)"))
                .settingsField()
            Button {
                draft.removeRow(row.wrappedValue.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove rule")
            .accessibilityLabel("Remove rule")
        }
    }

    private func save(replacingChanges: Bool) {
        saving = true
        saveError = nil
        SecurityFindingsStore.shared.saveAgentPolicy(draft, replacingChanges: replacingChanges) { outcome in
            saving = false
            switch outcome {
            case .saved:
                dismiss()
            case .changedOnDisk:
                showConflict = true
            case .failed(let error):
                saveError = error.message
            }
        }
    }

    private func reload() {
        SecurityFindingsStore.shared.openAgentPolicyDraft { fresh in
            if let fresh {
                saveError = nil
                draft = fresh
            } else {
                // The file on disk is no longer a policy; the row behind the sheet says why.
                dismiss()
            }
        }
    }
}
