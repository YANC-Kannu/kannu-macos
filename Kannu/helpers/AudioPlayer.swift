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

import Foundation
import AppKit

class AudioPlayer {
    /// Plays a bundled file once. Returns the sound so a caller can stop it; nil when the file is missing.
    @discardableResult
    func play(fileName: String, fileExtension: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension),
              let sound = NSSound(contentsOf: url, byReference: false) else { return nil }
        sound.play()
        return sound
    }
}
