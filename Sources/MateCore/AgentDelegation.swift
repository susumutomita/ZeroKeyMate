import Foundation

/// Additional local disclosure/merchant consent, never a replacement for the signed policy.
public struct AgentDelegation: Codable, Equatable, Sendable {
    public let chainID: UInt64
    public let vault: String
    public let mandateID: String
    public let providerID: String
    public let recipient: String
    public let service: UInt8
    public let maximumAmount: UInt64
    public let validUntil: UInt64

    public init(chainID:UInt64,vault:String,mandateID:String,providerID:String,recipient:String,
                service:UInt8,maximumAmount:UInt64,validUntil:UInt64) {
        self.chainID=chainID;self.vault=vault;self.mandateID=mandateID;self.providerID=providerID
        self.recipient=recipient;self.service=service;self.maximumAmount=maximumAmount;self.validUntil=validUntil
    }

    public func permits(chainID:UInt64,vault:String,mandateID:String,providerID:String,recipient:String,
                        service:UInt8,amount:UInt64,now:UInt64) -> Bool {
        guard maximumAmount>0,amount>0,amount<=maximumAmount,validUntil>now,
              self.chainID==chainID,self.vault.lowercased()==vault.lowercased(),
              self.mandateID.lowercased()==mandateID.lowercased(),self.providerID==providerID,
              self.recipient.lowercased()==recipient.lowercased(),self.service==service,service<=1,
              !providerID.isEmpty,
              (try? CanonicalBytes.hex(vault,count:20)) != nil,
              (try? CanonicalBytes.hex(recipient,count:20)) != nil,
              (try? CanonicalBytes.hex(mandateID,count:32)) != nil else{return false}
        return true
    }
}
