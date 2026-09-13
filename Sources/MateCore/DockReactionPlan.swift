/// Bounded absolute positions around a freshly observed stationary position.
public struct DockReactionPlan:Sendable {
    public let positions:[Double]
    public let permittedRange:Range<Double>
    public let maximumSpeed:Double
    public let stepSeconds=0.8
    public init?(center:Double,range:Range<Double>,maximumSpeed:Double) {
        guard center.isFinite,range.lowerBound.isFinite,range.upperBound.isFinite,
              maximumSpeed.isFinite,maximumSpeed>0,range.contains(center) else{return nil}
        let amplitude=min(0.03,center-range.lowerBound-0.002,range.upperBound-center-0.002)
        guard amplitude>=0.005 else{return nil}
        let speed=min(maximumSpeed,0.1)
        guard 2*amplitude/speed<=0.8 else{return nil}
        self.maximumSpeed=speed
        positions=[center+amplitude,center-amplitude,center]
        permittedRange=(center-amplitude-0.001)..<(center+amplitude+0.001)
    }
}

/// At most one pending/current reaction. Stop invalidates it even after re-enable.
public struct DockReactionGate:Sendable {
    public struct Request:Sendable { public let outcome:CompanionOutcome; public let ticket:UInt64 }
    private var pending:CompanionOutcome?
    private var active:UInt64?
    private var revision:UInt64=0
    private var nextAllowed:Double=0
    public init() {}
    public mutating func update(allowed:Bool) {
        if !allowed{pending=nil;revision &+= 1}
    }
    public mutating func request(_ outcome:CompanionOutcome,allowed:Bool,now:Double)->Bool {
        guard allowed,now.isFinite,now>=nextAllowed,pending == nil,active == nil else{return false}
        pending=outcome;nextAllowed=now+4;return true
    }
    public mutating func begin(allowed:Bool)->Request? {
        guard allowed,active == nil,let outcome=pending else{return nil}
        pending=nil;revision &+= 1;active=revision;return Request(outcome:outcome,ticket:revision)
    }
    public func permits(_ ticket:UInt64,allowed:Bool)->Bool {allowed && active == ticket && revision == ticket}
    public mutating func finish(_ ticket:UInt64) {if active == ticket{active=nil}}
}
