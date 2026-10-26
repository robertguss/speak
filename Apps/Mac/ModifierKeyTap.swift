import CoreGraphics
import DictationCore
import Foundation
import os

/// Watches one modifier key system-wide with a session event tap (KTD2).
/// It never swallows events, and it re-enables itself when macOS disables it.
/// Creating the tap needs the Accessibility permission.
final class ModifierKeyTap: @unchecked Sendable {
    private let hotkey = OSAllocatedUnfairLock(initialState: MacHotkey.rightOption)
    private let isDown = OSAllocatedUnfairLock(initialState: false)
    private let onEvent: @Sendable (HotkeyStateMachine.Event) -> Void
    private var tap: CFMachPort?

    /// `onEvent` is called on the tap's own thread.
    init(onEvent: @escaping @Sendable (HotkeyStateMachine.Event) -> Void) {
        self.onEvent = onEvent
    }

    var isRunning: Bool { tap != nil }

    func setHotkey(_ key: MacHotkey) {
        hotkey.withLock { $0 = key }
        isDown.withLock { $0 = false }
    }

    /// Returns false when the tap can't be created, which means Accessibility isn't granted yet.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                Unmanaged<ModifierKeyTap>.fromOpaque(info!).takeUnretainedValue().handle(type, event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "ModifierKeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let down = Self.isPressed(hotkey.withLock { $0 }, event)
            let changed = isDown.withLock { state in
                defer { state = down }
                return state != down
            }
            guard changed else { return }
            let time = TimeInterval(event.timestamp) / 1_000_000_000
            onEvent(down ? .keyDown(at: time) : .keyUp(at: time))
        case .keyDown, .otherMouseDown:
            if isDown.withLock({ $0 }) { onEvent(.otherKey) }
        default:
            break
        }
    }

    /// Fn uses its own flag; the right-side modifiers use device-specific flag bits,
    /// so the left-side key of the same kind doesn't trigger dictation.
    private static func isPressed(_ key: MacHotkey, _ event: CGEvent) -> Bool {
        let flags = event.flags
        switch key {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .rightOption: return flags.rawValue & 0x40 != 0     // NX_DEVICERALTKEYMASK, keycode 61
        case .rightCommand: return flags.rawValue & 0x10 != 0    // NX_DEVICERCMDKEYMASK, keycode 54
        case .rightControl: return flags.rawValue & 0x2000 != 0  // NX_DEVICERCTLKEYMASK, keycode 62
        }
    }
}
