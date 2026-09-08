import Foundation

/// Decodes the vault's actual Executed log. Transaction success alone is insufficient.
public enum ExecutionEvidence {
    // keccak256("Executed(bytes32,bytes32,bytes32,address,uint64,uint8,bytes32,uint64)")
    public static let topic = "0x57fa9f9504f3e681af84bf4c84cdbf24c65a8c8926d481b72ebaf7a4b3cde255"

    public static func validate(address:String, topics:[String], data:String, vault:String,
                                actionHash:String, proofHash:String, spentAfter:UInt64,
                                action:MandateAction? = nil) throws {
        guard address.lowercased()==vault.lowercased(),topics.count==4,
              topics[0].lowercased()==topic,topics[2].lowercased()==actionHash.lowercased() else {
            throw MandateError.invalidAction
        }
        for value in topics{_=try CanonicalBytes.hex(value,count:32)}
        let bytes=try CanonicalBytes.hex(data,count:160)
        func integer(_ index:Int) throws -> UInt64 {
            let word=bytes.subdata(in:index*32..<(index+1)*32)
            guard word.prefix(24).allSatisfy({$0==0}) else{throw MandateError.invalidAction}
            return word.suffix(8).reduce(0){($0<<8)|UInt64($1)}
        }
        guard bytes.prefix(12).allSatisfy({$0==0}),
              bytes.subdata(in:96..<128)==(try CanonicalBytes.hex(proofHash,count:32)),
              try integer(4)==spentAfter else{throw MandateError.invalidAction}
        if let action {
            guard topics[1].lowercased()==action.mandateId.lowercased(),topics[3].lowercased()==action.nonce.lowercased(),
                  bytes.subdata(in:12..<32)==(try CanonicalBytes.hex(action.recipient,count:20)),
                  try integer(1)==UInt64(action.amount),try integer(2)==UInt64(action.service),
                  let previous=UInt64(action.spentBefore),let amount=UInt64(action.amount),
                  amount<=UInt64.max-previous,spentAfter==previous+amount else{throw MandateError.invalidAction}
        }
    }
}
