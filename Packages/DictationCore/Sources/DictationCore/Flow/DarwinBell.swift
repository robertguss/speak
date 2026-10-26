import Foundation

/// A payload-free, cross-process doorbell between the iOS app and its keyboard (KTD6).
/// Darwin notifications can be lost, so receivers always re-read the shared files.
public final class DarwinBell: @unchecked Sendable {
    public static let toApp = "com.robertguss.speak.toApp"
    public static let toKeyboard = "com.robertguss.speak.toKeyboard"

    private static var center: CFNotificationCenter { CFNotificationCenterGetDarwinNotifyCenter() }

    public static func ring(_ name: String) {
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    }

    private let name: String
    private let handler: @Sendable () -> Void

    /// Calls `handler` on the main thread each time `name` rings, until this object is released.
    public init(name: String, handler: @escaping @Sendable () -> Void) {
        self.name = name
        self.handler = handler
        CFNotificationCenterAddObserver(
            Self.center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<DarwinBell>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(Self.center, Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(name as CFString), nil)
    }
}
