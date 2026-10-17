import AppKit
import Carbon

/// System-wide shortcuts that work while the app is hidden during a screen recording.
/// Option-Command-R starts and stops; Option-Command-P pauses, and is held only while recording so it
/// never takes the key from other apps the rest of the time. Carbon hot keys need no permission and
/// work in the App Store sandbox.
@MainActor
final class GlobalHotkeyManager {
    private enum Hotkey: UInt32 {
        case record = 1
        case pause = 2
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    init() {}

    func start() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotkeyID = EventHotKeyID()
            let error = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID
            )
            guard error == noErr else { return error }
            let id = hotkeyID.id
            Task { @MainActor in GlobalHotkeyManager.handle(id: id) }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        if status != noErr {
            AppLogger.recording.error("Hot keys: could not install handler (\(status))")
        }
        register(.record, keyCode: UInt32(kVK_ANSI_R))
    }

    /// Option-Command-P is held only while a recording runs.
    func setRecording(_ isRecording: Bool) {
        if isRecording {
            register(.pause, keyCode: UInt32(kVK_ANSI_P))
        } else {
            unregister(.pause)
        }
    }

    private static func handle(id: UInt32) {
        let appState = ServiceContainer.shared.appState
        switch Hotkey(rawValue: id) {
        case .record: appState.toggleRecording()
        case .pause: appState.togglePause()
        case nil: break
        }
    }

    private func register(_ hotkey: Hotkey, keyCode: UInt32) {
        guard refs[hotkey.rawValue] == nil else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5356), id: hotkey.rawValue)
        let status = RegisterEventHotKey(keyCode, UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[hotkey.rawValue] = ref
        } else {
            AppLogger.recording.error("Hot keys: \(String(describing: hotkey)) is taken by another app (\(status))")
        }
    }

    private func unregister(_ hotkey: Hotkey) {
        guard let ref = refs.removeValue(forKey: hotkey.rawValue) else { return }
        UnregisterEventHotKey(ref)
    }
}
