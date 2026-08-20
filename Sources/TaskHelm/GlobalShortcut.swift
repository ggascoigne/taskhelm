import AppKit
import Carbon.HIToolbox
import SwiftUI

struct GlobalShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    static let defaultQuickCapture = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        keyLabel: "T"
    )

    static let defaultTaskBrowser = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(shiftKey | controlKey | optionKey | cmdKey),
        keyLabel: "T"
    )

    static let legacyDefaultQuickCapture = GlobalShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey),
        keyLabel: "Space"
    )

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    var displayName: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyLabel
    }

    var menuKeyEquivalent: KeyEquivalent {
        switch Int(keyCode) {
        case kVK_Space: .space
        case kVK_Return, kVK_ANSI_KeypadEnter: .return
        case kVK_Tab: .tab
        case kVK_Delete: .delete
        case kVK_ForwardDelete: .deleteForward
        case kVK_LeftArrow: .leftArrow
        case kVK_RightArrow: .rightArrow
        case kVK_UpArrow: .upArrow
        case kVK_DownArrow: .downArrow
        case kVK_Home: .home
        case kVK_End: .end
        case kVK_PageUp: .pageUp
        case kVK_PageDown: .pageDown
        default: KeyEquivalent(keyLabel.lowercased().first ?? " ")
        }
    }

    var menuModifiers: SwiftUI.EventModifiers {
        var value: SwiftUI.EventModifiers = []
        if modifiers & UInt32(controlKey) != 0 { value.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { value.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { value.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { value.insert(.command) }
        return value
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifiers = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }

        if event.keyCode == UInt16(kVK_Space) {
            keyLabel = "Space"
        } else {
            keyLabel = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
    }

    var hasRequiredModifier: Bool {
        modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }
}

@MainActor
final class GlobalHotKeyManager {
    enum RegistrationError: LocalizedError {
        case unavailable(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .unavailable(status):
                "The shortcut could not be registered (error \(status)). It may be used by another app."
            }
        }
    }

    var action: (() -> Void)?

    nonisolated private let identifier: EventHotKeyID
    private var hotKeyRef: EventHotKeyRef?
    private var registeredShortcut: GlobalShortcut?
    private var eventHandlerRef: EventHandlerRef?

    init(identifier: UInt32, action: @escaping () -> Void) {
        self.identifier = EventHotKeyID(signature: OSType(0x54574D43), id: identifier)
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func register(_ shortcut: GlobalShortcut) throws {
        guard shortcut != registeredShortcut else { return }
        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &newReference
        )

        guard status == noErr else { throw RegistrationError.unavailable(status) }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = newReference
        registeredShortcut = shortcut
    }

    nonisolated fileprivate func handles(_ event: EventRef) -> Bool {
        var receivedIdentifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedIdentifier
        )
        guard status == noErr,
              receivedIdentifier.signature == identifier.signature,
              receivedIdentifier.id == identifier.id else { return false }
        return true
    }

    fileprivate func handleEvent() {
        action?()
    }
}

private let globalHotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    guard manager.handles(event) else { return OSStatus(eventNotHandledErr) }
    Task { @MainActor in manager.handleEvent() }
    return OSStatus(noErr)
}
