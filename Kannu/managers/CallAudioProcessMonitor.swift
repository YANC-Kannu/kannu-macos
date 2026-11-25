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

import CoreAudio
import Foundation

/// Reads which of the catalog's apps (`CallAppCatalog`) are capturing and playing audio, and on
/// which devices, from CoreAudio's process list. It needs no permission and raises no prompt: it
/// reads who holds the microphone, never the audio.
///
/// Everything here runs on one private serial queue, never on the main thread. `onChange` is
/// called on that queue, and only when the reading differs from the last one handed over.
///
/// **What wakes it.** Three listeners, each a block on the queue:
/// - the default input device's "running somewhere" flag, the event macOS sends when any app
///   starts or stops using the microphone;
/// - a change of default input device, which moves that listener to the new device;
/// - a change of the process list.
///
/// **The one timer.** On macOS 27.2 a process that *starts* capturing sends no per-process event
/// (measured: 12 starts, no event), so while the microphone is in use, and only then, the reading
/// is taken again every `rereadInterval` seconds. While a catalog app is itself capturing it is
/// taken every `callRereadInterval` seconds: an app that stops capturing sends no event either
/// (measured: the device-level event came 2 s after WhatsApp stopped), and the re-read is the
/// only thing that ends a call's clock. The timer is made when the microphone comes into use and
/// cancelled the moment it is free. With the microphone free, nothing here runs.
///
/// **Teardown.** `stop()` removes every listener and cancels the timer
/// (docs/REGRESSIONS.md entry 19). `deinit` is not that path.
final class CallAudioProcessMonitor: @unchecked Sendable {
    /// How often the reading is retaken while the microphone is in use.
    static let rereadInterval: TimeInterval = 2
    /// How often it is retaken while a catalog app is capturing: what a call's end waits on.
    static let callRereadInterval: TimeInterval = 1

    private let queue = DispatchQueue(label: "com.kannu.app.call-audio-process-monitor", qos: .utility)
    private let onChange: ([CallAudioProcess]) -> Void

    // Everything below is touched only on `queue`.
    private var isRunning = false
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var listenedDevice = AudioObjectID(kAudioObjectUnknown)
    private var rereadTimer: DispatchSourceTimer?
    /// The interval `rereadTimer` was scheduled with.
    private var rereadEvery: TimeInterval = 0
    private var lastReading: [CallAudioProcess] = []
    /// A process object's bundle ID does not change while the object lives, so it is read once.
    /// Pruned to the current list on every reading.
    private var bundleIDs: [AudioObjectID: String] = [:]

    /// `onChange` runs on the monitor's queue.
    init(onChange: @escaping ([CallAudioProcess]) -> Void) {
        self.onChange = onChange
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            addSystemListeners()
            followDefaultInputDevice()
            refresh()
        }
    }

    /// Removes every listener and cancels the timer. Returns once that is done, so nothing of
    /// this monitor runs after it.
    func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            cancelRereadTimer()
            removeDeviceListener()
            removeSystemListeners()
            bundleIDs = [:]
            lastReading = []
        }
    }

    // MARK: - Listeners

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private static let systemSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyProcessObjectList,
        kAudioHardwarePropertyDefaultInputDevice,
    ]

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func addSystemListeners() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Already on `queue`: the block was registered with it.
            guard let self, self.isRunning else { return }
            self.followDefaultInputDevice()
            self.refresh()
        }
        systemListener = block
        for selector in Self.systemSelectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, queue, block)
        }
    }

    private func removeSystemListeners() {
        guard let block = systemListener else { return }
        for selector in Self.systemSelectors {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, queue, block)
        }
        systemListener = nil
    }

    /// Keeps the "running somewhere" listener on whichever device is the default input now.
    private func followDefaultInputDevice() {
        let device: AudioObjectID = Self.read(Self.systemObject, kAudioHardwarePropertyDefaultInputDevice)
            ?? AudioObjectID(kAudioObjectUnknown)
        guard device != listenedDevice else { return }
        removeDeviceListener()
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isRunning else { return }
            self.refresh()
        }
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        guard AudioObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr else { return }
        deviceListener = block
        listenedDevice = device
    }

    private func removeDeviceListener() {
        if let block = deviceListener {
            var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &address, queue, block)
        }
        deviceListener = nil
        listenedDevice = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Reading

    /// Takes one reading, hands it over if it changed, and keeps the re-read timer running
    /// exactly while the microphone is in use.
    private func refresh() {
        let reading = readCatalogProcesses()
        // A catalog app capturing on a microphone that is not the default one is the microphone
        // in use too, and nothing else would report its end.
        let catalogAppCaptures = reading.contains { $0.isCapturing }
        setRereadTimer(running: microphoneIsInUse || catalogAppCaptures,
                       every: catalogAppCaptures ? Self.callRereadInterval : Self.rereadInterval)
        guard reading != lastReading else { return }
        lastReading = reading
        onChange(reading)
    }

    private var microphoneIsInUse: Bool {
        guard listenedDevice != AudioObjectID(kAudioObjectUnknown) else { return false }
        let running: UInt32 = Self.read(listenedDevice, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0
        return running != 0
    }

    /// The catalog apps' processes, with whether each captures and plays. Processes of any other
    /// app are skipped at their bundle ID: nothing more is read about them.
    private func readCatalogProcesses() -> [CallAudioProcess] {
        let objects = Self.processObjects()
        let live = Set(objects)
        bundleIDs = bundleIDs.filter { live.contains($0.key) }
        var reading: [CallAudioProcess] = []
        for object in objects {
            let bundleID: String
            if let known = bundleIDs[object] {
                bundleID = known
            } else {
                bundleID = Self.readString(object, kAudioProcessPropertyBundleID) ?? ""
                bundleIDs[object] = bundleID
            }
            guard !bundleID.isEmpty, CallAppCatalog.app(forProcessBundleID: bundleID) != nil else { continue }
            let input: UInt32 = Self.read(object, kAudioProcessPropertyIsRunningInput) ?? 0
            let output: UInt32 = Self.read(object, kAudioProcessPropertyIsRunningOutput) ?? 0
            // Its devices are read only while it does both: that is when the answer is asked for.
            let shares = input != 0 && output != 0 && Self.capturesFromOutputDevice(object)
            reading.append(CallAudioProcess(bundleID: bundleID, isCapturing: input != 0, isPlaying: output != 0,
                                            capturesFromOutputDevice: shares))
        }
        // The list's order is CoreAudio's own and not stable; sorted, an unchanged reading compares equal.
        func key(_ process: CallAudioProcess) -> (String, Int) {
            (process.bundleID,
             (process.isCapturing ? 4 : 0) + (process.isPlaying ? 2 : 0) + (process.capturesFromOutputDevice ? 1 : 0))
        }
        return reading.sorted { key($0) < key($1) }
    }

    /// Whether one of the devices the process captures from is one it also plays to
    /// (`CallAudioProcess.capturesFromOutputDevice`).
    private static func capturesFromOutputDevice(_ process: AudioObjectID) -> Bool {
        let inputs = Set(objectIDs(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput))
        guard !inputs.isEmpty else { return false }
        return !inputs.isDisjoint(with: objectIDs(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput))
    }

    // MARK: - The re-read, only while the microphone is in use

    private func setRereadTimer(running: Bool, every interval: TimeInterval) {
        guard running else {
            cancelRereadTimer()
            return
        }
        if let timer = rereadTimer {
            // The one timer, rescheduled: never a second one.
            if rereadEvery != interval {
                rereadEvery = interval
                timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
            }
            return
        }
        rereadEvery = interval
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            self.refresh()
        }
        rereadTimer = timer
        timer.resume()
    }

    private func cancelRereadTimer() {
        rereadTimer?.cancel()
        rereadTimer = nil
        rereadEvery = 0
    }

    // MARK: - CoreAudio reads

    private static func processObjects() -> [AudioObjectID] {
        objectIDs(systemObject, kAudioHardwarePropertyProcessObjectList)
    }

    /// A property that is a list of object IDs: the process list, a process's devices.
    private static func objectIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        // The list may have shrunk between the two calls.
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func read<Value: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Value? {
        var address = address(selector)
        var value: Value = 0
        var size = UInt32(MemoryLayout<Value>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }
}
