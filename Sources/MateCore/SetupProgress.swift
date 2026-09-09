import Foundation

/// Recomputed from restored credentials and current service/chain observations.
/// A saved navigation checkpoint is never proof that a registration or payment succeeded.
public enum SetupStage:String,Codable,Sendable,CaseIterable {
    case restoring,recovery,connection,login,wallets,account,funds,rules,request
}
public struct SetupProgress:Equatable,Sendable {
    public let stage:SetupStage
    public init(restored:Bool,pending:Bool,connected:Bool,authenticated:Bool,walletsReady:Bool,
                accountChecked:Bool,balance:UInt64,mandateActive:Bool) {
        if !restored {stage = .restoring}
        else if pending {stage = .recovery}
        else if !connected {stage = .connection}
        else if !authenticated {stage = .login}
        else if !walletsReady {stage = .wallets}
        else if !accountChecked {stage = .account}
        else if balance == 0 {stage = .funds}
        else if !mandateActive {stage = .rules}
        else {stage = .request}
    }
}
