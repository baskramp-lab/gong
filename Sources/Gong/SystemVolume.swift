import AudioToolbox
import CoreAudio

/// Makes the default output device audible while the modal is up (unmute + minimum volume) and puts it back afterwards.
final class SystemVolume {
    /// Volume (0…1) the output is raised to when it is muted or quieter than this.
    static let minimum: Float32 = 0.4

    /// What to put back (`muted`, `volume`) and the volume right after Gong's change (`after`): if the user has
    /// moved the volume away from that, they chose a level and nothing is put back.
    private struct Saved { let device: AudioDeviceID; let muted: UInt32?; let volume: Float32?; let after: Float32? }
    /// Volume steps are not exact; within this the volume still counts as "the one Gong set".
    private static let tolerance: Float32 = 0.02
    private var saved: Saved?

    func ensureAudible() {
        guard saved == nil, let device = Self.defaultOutput() else { return }
        let muted: UInt32? = Self.get(device, kAudioDevicePropertyMute)
        let volume: Float32? = Self.get(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        let needsUnmute = muted == 1
        let needsVolume = (volume ?? 1) < Self.minimum
        guard needsUnmute || needsVolume else { return }
        if needsUnmute { Self.set(device, kAudioDevicePropertyMute, UInt32(0)) }
        if needsVolume { Self.set(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Self.minimum) }
        saved = Saved(device: device, muted: needsUnmute ? muted : nil, volume: needsVolume ? volume : nil,
                      after: Self.get(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume))
    }

    /// Restores only what `ensureAudible` changed, on the device it changed (also when the output has moved on,
    /// e.g. to AirPods), and only while the user has not changed it since.
    func restore() {
        guard let s = saved else { return }
        saved = nil
        let now: Float32? = Self.get(s.device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if let now, let after = s.after, abs(now - after) > Self.tolerance { return }   // the user set a volume
        if let v = s.volume { Self.set(s.device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, v) }
        if let m = s.muted, let muted: UInt32 = Self.get(s.device, kAudioDevicePropertyMute), muted == 0 {
            Self.set(s.device, kAudioDevicePropertyMute, m)
        }
    }

    private static func defaultOutput() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return err == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T: Numeric>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> T? {
        var addr = address(selector)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        let err = withUnsafeMutableBytes(of: &value) { AudioObjectGetPropertyData(device, &addr, 0, nil, &size, $0.baseAddress!) }
        return err == noErr ? value : nil
    }

    private static func set<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: T) {
        var addr = address(selector)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return }
        _ = withUnsafeBytes(of: value) { AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32($0.count), $0.baseAddress!) }
    }
}
