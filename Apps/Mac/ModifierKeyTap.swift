import CoreGraphics
import DictationCore
import Foundation
import os

final class ModifierKeyTap: @unchecked Sendable {
    private let hotkey = OSAllocatedUnfairLock(initialState: MacHotkey.rightOption)
    private let isDown = OSAllocatedUnfairLock(initialState: false)
    private let onEvent: @Sendable (HotkeyStateMachine.Event) -> Void
    private var tap: CFMachPort?

    init(onEvent: @escaping @Sendable (HotkeyStateMachine.Event) -> Void) {
        self.onEvent = onEvent
    }

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

    private static let rightOptionMask: UInt64 = 0x40     // NX_DEVICERALTKEYMASK
    private static let rightCommandMask: UInt64 = 0x10    // NX_DEVICERCMDKEYMASK
    private static let rightControlMask: UInt64 = 0x2000  // NX_DEVICERCTLKEYMASK

    private static func isPressed(_ key: MacHotkey, _ event: CGEvent) -> Bool {
        let flags = event.flags
        switch key {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .rightOption: return flags.rawValue & rightOptionMask != 0
        case .rightCommand: return flags.rawValue & rightCommandMask != 0
        case .rightControl: return flags.rawValue & rightControlMask != 0
        }
    }
}
