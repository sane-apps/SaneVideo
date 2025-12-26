//
//  GlobalHotkeyManager.swift
//  SaneVideo
//
import AppKit
import Carbon

class GlobalHotkeyManager {

    private var eventHandlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    
    // CRITICAL FIX: Store the retained pointer so we can release it in deinit
    // Using passUnretained was causing potential use-after-free crashes
    private var retainedSelf: Unmanaged<GlobalHotkeyManager>?

    init() {}

    func start() {
        setupHotkeys()
    }

    func handleEvent(id: UInt32) {
        eventHandlers[id]?()
    }

    private func setupHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        // CRITICAL FIX: Use passRetained to ensure the object stays alive
        // while the event handler is registered. We'll release in deinit.
        retainedSelf = Unmanaged.passRetained(self)
        let selfPointer = retainedSelf!.toOpaque()

        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            var hotkeyID = EventHotKeyID()
            let error = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )

            if error == noErr {
                if let userData = userData {
                    // Use takeUnretainedValue since we're not transferring ownership here
                    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    manager.handleEvent(id: hotkeyID.id)
                }
            } else {
                NSLog("❌ GlobalHotkeyManager: Failed to get event parameter: \(error)")
            }

            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)

        if status != noErr {
            NSLog("❌ GlobalHotkeyManager: Failed to install event handler: \(status)")
        } else {
            NSLog("✅ GlobalHotkeyManager: Event handler installed")
        }

        // Register hotkeys
        registerHotkey(id: 1, keyCode: 15, modifiers: UInt32(cmdKey | optionKey)) { // ⌥⌘R
            DispatchQueue.main.async {
                NSLog("⌨️ Global Hotkey: Toggle Recording")
                ServiceContainer.shared.appState.toggleRecording()
            }
        }

        registerHotkey(id: 2, keyCode: 35, modifiers: UInt32(cmdKey | shiftKey)) { // ⌘⇧P
            DispatchQueue.main.async {
                ServiceContainer.shared.appState.togglePause()
            }
        }

        registerHotkey(id: 3, keyCode: 1, modifiers: UInt32(cmdKey | shiftKey)) { // ⌘⇧S
            DispatchQueue.main.async {
                ServiceContainer.shared.appState.toggleScreenShare()
            }
        }

        registerHotkey(id: 4, keyCode: 4, modifiers: UInt32(cmdKey | shiftKey)) { // ⌘⇧H
            DispatchQueue.main.async {
                ServiceContainer.shared.appState.togglePiPVisibility()
            }
        }
    }

    private func registerHotkey(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        let hotkeyID = EventHotKeyID(signature: OSType(0x5356), id: id) // 'SV'
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            NSLog("❌ GlobalHotkeyManager: Failed to register hotkey id \(id): \(status)")
        }

        eventHandlers[id] = handler
    }

    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}
