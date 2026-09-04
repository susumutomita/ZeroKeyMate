/// User intent only: this is not evidence that a camera has started or stopped.
/// Hardware status must come from the capture service, not this value.
public struct CaptureIntent: Equatable, Sendable {
    public private(set) var isForeground = false
    public private(set) var isRequested = false

    public init() {}

    public var shouldCapture: Bool { isForeground && isRequested }

    public mutating func setForeground(_ foreground: Bool) {
        isForeground = foreground
        if !foreground {
            // Returning to the foreground must never resume capture implicitly.
            isRequested = false
        }
    }

    public mutating func requestStart() {
        // Ignore stale button actions delivered after the app backgrounds.
        isRequested = isForeground
    }

    public mutating func requestStop() {
        isRequested = false
    }
}
