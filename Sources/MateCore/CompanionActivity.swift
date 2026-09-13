public enum CompanionOutcome:Equatable,Sendable { case confirmed,rejected }

/// A presentation of observed work, never authorization or evidence of payment.
public enum CompanionActivity:Equatable,Sendable {
    case resting,ready,listening,thinking,speaking,approval,proving,sending,confirming,confirmed,rejected,unknown

    public static func resolve(resting:Bool,operation:Self?,pending:Bool,outcome:CompanionOutcome?,
                               approval:Bool,speaking:Bool,listening:Bool,thinking:Bool)->Self {
        if resting{return .resting}
        if let operation{return operation}
        if pending{return .unknown}
        if let outcome{return outcome == .confirmed ? .confirmed:.rejected}
        if approval{return .approval}
        if speaking{return .speaking}
        if listening{return .listening}
        return thinking ? .thinking:.ready
    }
    public var processing:Bool {
        switch self {case .thinking,.proving,.sending,.confirming:return true;default:return false}
    }
    public var label:String {
        switch self {
        case .resting:return "Taking a rest."
        case .ready:return "I'm here."
        case .listening:return "Listening."
        case .thinking:return "Thinking."
        case .speaking:return "Speaking."
        case .approval:return "Waiting for approval."
        case .proving:return "Generating a proof on this iPhone"
        case .sending:return "Sending the approved request."
        case .confirming:return "Checking confirmation."
        case .confirmed:return "Confirmed."
        case .rejected:return "This request wasn't approved."
        case .unknown:return "The result is not yet confirmed."
        }
    }
}
