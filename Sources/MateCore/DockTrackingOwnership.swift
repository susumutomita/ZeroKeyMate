/// Do not switch off system tracking owned by another camera app on launch.
public struct DockTrackingOwnership:Sendable {
    public private(set) var hasRequestedTracking=false
    public init() {}
    public mutating func shouldApply(enabled:Bool)->Bool {
        if enabled{hasRequestedTracking=true}
        return enabled || hasRequestedTracking
    }
}
