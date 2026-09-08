/// User intent survives individual silent recognition turns, but never an explicit stop.
public struct CompanionListeningSession: Sendable {
    public private(set) var isActive=false
    public private(set) var revision:UInt64=0
    public init() {}
    public mutating func begin() {revision &+= 1;isActive=true}
    public mutating func stop() {revision &+= 1;isActive=false}
    public func permitsResume(ticket:UInt64,foreground:Bool,resting:Bool,busy:Bool,screenAllowsListening:Bool) -> Bool {
        isActive && ticket==revision && foreground && !resting && !busy && screenAllowsListening
    }
}
