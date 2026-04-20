import CoreAudio
import Foundation

struct AudioInputDevice: Equatable, Identifiable {
    let id: String
    let name: String
    let uid: String
}

@MainActor
final class AudioInputDeviceManager: ObservableObject {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var selectedDeviceUID: String?
    @Published private(set) var systemDefaultDeviceUID: String?
    @Published private(set) var selectionWarning: String?

    private let defaults: UserDefaults
    private let selectedDeviceDefaultsKey = "selectedMicrophoneUID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedDeviceUID = defaults.string(forKey: selectedDeviceDefaultsKey)
        refreshDevices()
    }

    var recordingDeviceUID: String? {
        guard let selectedDeviceUID else { return nil }
        return devices.contains(where: { $0.uid == selectedDeviceUID }) ? selectedDeviceUID : nil
    }

    var currentSystemDefaultName: String? {
        guard let systemDefaultDeviceUID else { return nil }
        return devices.first(where: { $0.uid == systemDefaultDeviceUID })?.name
    }

    var menuSignature: String {
        let deviceSummary = devices.map { "\($0.uid):\($0.name)" }.joined(separator: "|")
        return [
            selectedDeviceUID ?? "system-default", systemDefaultDeviceUID ?? "no-default",
            selectionWarning ?? "no-warning", deviceSummary,
        ]
        .joined(separator: "::")
    }

    func refreshDevices() {
        let availableDevices = CoreAudioInputDevices.inputDevices()
        devices = availableDevices
        systemDefaultDeviceUID = CoreAudioInputDevices.defaultInputDeviceUID()

        guard let selectedDeviceUID else {
            selectionWarning = nil
            return
        }

        guard availableDevices.contains(where: { $0.uid == selectedDeviceUID }) else {
            self.selectedDeviceUID = nil
            defaults.removeObject(forKey: selectedDeviceDefaultsKey)
            selectionWarning = "Selected microphone unavailable. Using system default."
            return
        }

        selectionWarning = nil
    }

    func selectSystemDefault() {
        selectedDeviceUID = nil
        selectionWarning = nil
        defaults.removeObject(forKey: selectedDeviceDefaultsKey)
        refreshDevices()
    }

    func selectDevice(uid: String) {
        guard devices.contains(where: { $0.uid == uid }) else {
            refreshDevices()
            return
        }

        selectedDeviceUID = uid
        selectionWarning = nil
        defaults.set(uid, forKey: selectedDeviceDefaultsKey)
        refreshDevices()
    }
}

enum CoreAudioInputDevices {
    static func defaultInputDeviceUID() -> String? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard
            let deviceID = readAudioDeviceIDProperty(
                objectID: AudioObjectID(kAudioObjectSystemObject),
                address: address
            )
        else {
            return nil
        }

        return deviceUID(for: deviceID)
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first(where: { $0.uid == uid }).flatMap { _ in
            deviceIDs().first(where: { deviceUID(for: $0) == uid })
        }
    }

    static func inputDevices() -> [AudioInputDevice] {
        let defaultUID = defaultInputDeviceUID()
        return deviceIDs()
            .compactMap { deviceID -> AudioInputDevice? in
                guard inputChannelCount(for: deviceID) > 0,
                    let name = deviceName(for: deviceID),
                    let uid = deviceUID(for: deviceID)
                else {
                    return nil
                }

                return AudioInputDevice(id: uid, name: name, uid: uid)
            }
            .sorted { lhs, rhs in
                if lhs.uid == defaultUID { return true }
                if rhs.uid == defaultUID { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return readPropertyArray(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: address
        ) ?? []
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return readStringProperty(objectID: deviceID, address: address)
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return readStringProperty(objectID: deviceID, address: address)
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        guard sizeStatus == noErr, propertySize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return 0
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferListPointer)
        guard status == noErr else {
            return 0
        }

        let audioBufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return buffers.reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }

    private static func readStringProperty(objectID: AudioObjectID, address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var value: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &propertySize, $0)
        }
        guard status == noErr else {
            return nil
        }

        return value?.takeUnretainedValue() as String?
    }

    private static func readAudioDeviceIDProperty(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) -> AudioDeviceID? {
        var address = address
        var value = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &propertySize, $0)
        }
        guard status == noErr else {
            return nil
        }

        return value
    }

    private static func readPropertyArray<T>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) -> [T]? {
        var address = address
        var propertySize: UInt32 = 0

        let sizeStatus = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &propertySize)
        guard sizeStatus == noErr else {
            return nil
        }

        let itemCount = Int(propertySize) / MemoryLayout<T>.stride
        var values = [T](unsafeUninitializedCapacity: itemCount) { buffer, initializedCount in
            initializedCount = itemCount
        }

        let status = values.withUnsafeMutableBytes {
            guard let baseAddress = $0.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }

            return AudioObjectGetPropertyData(objectID, &address, 0, nil, &propertySize, baseAddress)
        }
        guard status == noErr else {
            return nil
        }

        return values
    }
}
