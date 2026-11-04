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

import AppKit
import SwiftUI

struct SettingsColorPickerRow: View {
    let title: String
    var description: String? = nil
    @Binding var selection: Color
    var supportsOpacity: Bool = false

    var body: some View {
        LabeledContent {
            KannuColorPickerButton(color: selection, accessibilityLabel: title) {
                SettingsColorPickerPopover(selection: $selection, supportsOpacity: supportsOpacity)
            }
        } label: {
            SettingsRowLabel(verbatim: title, description: description)
        }
    }
}

/// Presets + screen sampler, with the gradient picker one click away. The gradient replaced a
/// "Custom…" button that opened `NSColorPanel`: in this accessory app the panel never reliably
/// appeared, so custom colours were unreachable.
private struct SettingsColorPickerPopover: View {
    @Binding var selection: Color
    var supportsOpacity: Bool

    @State private var showsSpectrum = false

    private static let presets: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemMint, .systemTeal,
        .systemCyan, .systemBlue, .systemIndigo, .systemPurple, .systemPink, .systemBrown,
        .systemGray, .black, .white, .darkGray,
    ]

    private var items: [KannuColorSwatchGrid.Item] {
        Self.presets.enumerated().map { index, preset in
            KannuColorSwatchGrid.Item(
                id: "preset-\(index)",
                color: Color(nsColor: preset),
                disabledReason: nil,
                accessibilityLabel: String(localized: "Color swatch")
            )
        }
    }

    private var selectedID: String? {
        items.first { matches($0.color, selection) }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsSpectrum {
                HStack(spacing: 6) {
                    Button {
                        showsSpectrum = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(SettingsButtonStyle(.quiet))
                    .accessibilityLabel(Text("Back"))
                    Text("Custom color")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                }
                .font(.caption)
                // The popover's compact scale: our style sets the buttons' type by their size.
                .controlSize(.small)
                ColorSpectrumPicker(color: $selection, supportsOpacity: supportsOpacity)
                    .frame(width: 220)
            } else {
                KannuColorSwatchGrid(
                    items: items,
                    selectedID: selectedID,
                    columns: 8,
                    swatchSize: 18
                ) { item in
                    selection = item.color
                }
                Divider()
                HStack {
                    Button {
                        ScreenColorSampler.shared.sample { picked in selection = picked }
                    } label: {
                        Label("Pick from screen", systemImage: "eyedropper")
                    }
                    .buttonStyle(SettingsButtonStyle(.quiet))
                    Spacer()
                    Button("Custom…") { showsSpectrum = true }
                        .buttonStyle(SettingsButtonStyle(.quiet))
                }
                .font(.caption)
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private func matches(_ lhs: Color, _ rhs: Color) -> Bool {
        guard let a = NSColor(lhs).usingColorSpace(.sRGB),
              let b = NSColor(rhs).usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}

/// Owns the screen sampler so it outlives the popover — a locally-created `NSColorSampler` can be
/// released before the user finishes picking, silently dropping the result.
private final class ScreenColorSampler {
    static let shared = ScreenColorSampler()
    private var sampler: NSColorSampler?
    private init() {}

    func sample(onPick: @escaping (Color) -> Void) {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] picked in
            self?.sampler = nil
            guard let picked else { return }
            onPick(Color(nsColor: picked))
        }
    }
}
