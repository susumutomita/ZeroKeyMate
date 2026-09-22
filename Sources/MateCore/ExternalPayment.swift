import Foundation

public enum ExternalPaymentError: Error, Equatable, Sendable {
    case invalidService, invalidChallenge, unsupportedPayment, expired, invalidAuthorization, invalidReceipt, unresolvedPayment
}

/// An application-reviewed endpoint, not a URL supplied by the model or a 402.
/// This initial profile supports Arc Testnet USDC, exact EIP-3009, GET only.
public struct PaymentService: Codable, Equatable, Sendable {
    public let resource: String
    public let recipient: String
    public let maximumAmount: UInt64
    public init(resource: String, recipient: String, maximumAmount: UInt64) throws {
        self.resource=resource;self.recipient=recipient;self.maximumAmount=maximumAmount
        _ = try validate()
    }
    public func validate() throws -> URL {
        let url = try Self.validateResource(resource)
        guard maximumAmount>0,maximumAmount<=500_000,
              (try? CanonicalBytes.hex(recipient,count:20).contains(where:{$0 != 0}))==true
        else {throw ExternalPaymentError.invalidService}
        return url
    }
    /// Validates only the URL shape. Registration still needs explicit user
    /// review; this is not a promise of DNS-level private-network isolation.
    public static func validateResource(_ resource:String) throws -> URL {
        guard resource.utf8.count<=2048,resource.unicodeScalars.allSatisfy({$0.isASCII}),
              let url=URL(string:resource),url.absoluteString==resource,url.scheme=="https",
              let host=url.host,host==host.lowercased(),host.contains("."),
              !host.hasSuffix(".local"),!host.hasSuffix(".localhost"),
              !host.hasSuffix(".internal"),!host.hasSuffix(".test"),
              host.split(separator:".").contains(where:{$0.contains(where:{$0.isLetter})}),
              !host.split(separator:".").allSatisfy({label in
                  label.allSatisfy(\.isNumber) || (label.hasPrefix("0x") && label.dropFirst(2).allSatisfy(\.isHexDigit))
              }),
              host.split(separator:".",omittingEmptySubsequences:false).allSatisfy({label in
                  !label.isEmpty && label.count<=63 && label.first != "-" && label.last != "-"
                    && label.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")})
              }),url.user==nil,url.password==nil,url.port==nil,url.query==nil,url.fragment==nil,
              !url.path.isEmpty,!resource.contains("%"),!resource.contains("\\"),
              !url.pathComponents.contains(".."),!url.pathComponents.contains(".")
        else {throw ExternalPaymentError.invalidService}
        return url
    }
}

public struct PaymentRequirements: Codable, Equatable, Sendable {
    public let scheme:String,network:String,amount:String,asset:String,payTo:String
    public let maxTimeoutSeconds:Int
    public let extra:[String:String]
    func validate(service:PaymentService) throws {
        _ = try service.validate()
        guard scheme=="exact",network==AgeShopProtocol.network,
              asset.lowercased()==AgeShopProtocol.token,payTo.lowercased()==service.recipient.lowercased(),
              let value=UInt64(amount),String(value)==amount,value>0,value<=service.maximumAmount,
              (30...300).contains(maxTimeoutSeconds),extra["name"]=="USDC",extra["version"]=="2",
              extra["assetTransferMethod"]==nil || extra["assetTransferMethod"]=="eip3009",
              extra["paymentFlow"]==nil || extra["paymentFlow"]=="authorization",
              Set(extra.keys).isSubset(of:["name","version","assetTransferMethod","paymentFlow"])
        else {throw ExternalPaymentError.unsupportedPayment}
    }
}

private struct EmptyExtensions: Decodable {
    private struct Key: CodingKey {let stringValue:String;let intValue:Int?=nil;init?(stringValue:String){self.stringValue=stringValue};init?(intValue:Int){return nil}}
    init(from decoder:Decoder) throws {
        guard try decoder.container(keyedBy:Key.self).allKeys.isEmpty else{throw ExternalPaymentError.unsupportedPayment}
    }
}

/// A displayed quote expires locally; x402's challenge itself is not signed.
/// An EIP-3009 signature binds the transfer, not this HTTP URL or any SKU.
public struct PaymentRequest: Codable, Equatable, Sendable {
    public let service:PaymentService
    public let accepted:PaymentRequirements
    public let quotedAt:UInt64
    public let expiresAt:UInt64
    private init(service:PaymentService,accepted:PaymentRequirements,now:UInt64) {
        self.service=service;self.accepted=accepted;quotedAt=now
        expiresAt=now+UInt64(min(180,accepted.maxTimeoutSeconds))
    }
    public static func parse(header:String,service:PaymentService,now:UInt64) throws -> PaymentRequest {
        struct Resource:Decodable{let url:String}
        struct Challenge:Decodable {let x402Version:Int,resource:Resource,accepts:[PaymentRequirements];let extensions:EmptyExtensions?}
        _ = try service.validate()
        guard now>0,now<=UInt64.max-300,header.utf8.count<=16_384,
              let data=Data(base64Encoded:header) else{throw ExternalPaymentError.invalidChallenge}
        let challenge=try JSONDecoder().decode(Challenge.self,from:data)
        guard challenge.x402Version==2,challenge.resource.url==service.resource,
              (1...8).contains(challenge.accepts.count) else{throw ExternalPaymentError.invalidChallenge}
        let accepted=challenge.accepts.filter{(try? $0.validate(service:service)) != nil}
        guard accepted.count==1 else{throw ExternalPaymentError.unsupportedPayment}
        return PaymentRequest(service:service,accepted:accepted[0],now:now)
    }
    /// A quote for the registration review screen, not an authorized service.
    /// The owner must accept the returned recipient and ceiling before storing it.
    public static func discover(header:String,resource:String,maximumAmount:UInt64,now:UInt64) throws -> PaymentRequest {
        struct Challenge:Decodable {let accepts:[PaymentRequirements]}
        _ = try PaymentService.validateResource(resource)
        guard header.utf8.count<=16_384,let data=Data(base64Encoded:header) else {
            throw ExternalPaymentError.invalidChallenge
        }
        let candidates=try JSONDecoder().decode(Challenge.self,from:data)
        guard (1...8).contains(candidates.accepts.count) else{throw ExternalPaymentError.invalidChallenge}
        let services=candidates.accepts.compactMap{offer -> PaymentService? in
            guard let service=try? PaymentService(resource:resource,recipient:offer.payTo,maximumAmount:maximumAmount),
                  (try? offer.validate(service:service)) != nil else{return nil}
            return service
        }
        guard services.count==1,let service=services.first else{throw ExternalPaymentError.unsupportedPayment}
        return try parse(header:header,service:service,now:now)
    }
    public func validate(now:UInt64,allowExpired:Bool=false) throws {
        try accepted.validate(service:service)
        guard quotedAt>0,quotedAt<=UInt64.max-300,quotedAt<=now,
              expiresAt==quotedAt+UInt64(min(180,accepted.maxTimeoutSeconds)) else{throw ExternalPaymentError.invalidChallenge}
        if !allowExpired && now>=expiresAt{throw ExternalPaymentError.expired}
    }
}

public struct PaymentAuthorization: Codable, Equatable, Sendable {
    public let from:String,to:String,value:String,validAfter:String,validBefore:String,nonce:String
    public init(request:PaymentRequest,payer:String,nonce:String,now:UInt64) throws {
        try request.validate(now:now)
        guard now<=UInt64.max-300 else{throw ExternalPaymentError.invalidAuthorization}
        from=payer;to=request.accepted.payTo;value=request.accepted.amount
        // Match the reference EIP-3009 client. Quote freshness limits when an
        // approval can be made, not the server's subsequent settlement window.
        validAfter="0";validBefore=String(now+UInt64(request.accepted.maxTimeoutSeconds));self.nonce=nonce
        try validate(request:request)
    }
    public func validate(request:PaymentRequest) throws {
        try request.validate(now:request.quotedAt,allowExpired:true)
        guard (try? CanonicalBytes.hex(from,count:20).contains(where:{$0 != 0}))==true,
              to==request.accepted.payTo,value==request.accepted.amount,
              validAfter=="0",let end=UInt64(validBefore),String(end)==validBefore,
              end>UInt64(request.accepted.maxTimeoutSeconds),
              end-UInt64(request.accepted.maxTimeoutSeconds)>=request.quotedAt,
              end-UInt64(request.accepted.maxTimeoutSeconds)<request.expiresAt,
              (try? CanonicalBytes.hex(nonce,count:32).contains(where:{$0 != 0}))==true
        else{throw ExternalPaymentError.invalidAuthorization}
    }
}

/// Persist before the first paid HTTP request; reuse these exact bytes on retry.
/// The app still needs an explicit owner approval before its provider can sign.
public struct PendingPayment: Codable, Equatable, Sendable {
    public let request:PaymentRequest
    public let authorization:PaymentAuthorization
    public let signature:String
    public init(request:PaymentRequest,authorization:PaymentAuthorization,signature:String,now:UInt64) throws {
        self.request=request;self.authorization=authorization;self.signature=signature
        try request.validate(now:now)
        try validate(now:now)
    }
    public func validate(now:UInt64,allowExpired:Bool=false) throws {
        try request.validate(now:now,allowExpired:true)
        try authorization.validate(request:request)
        guard let end=UInt64(authorization.validBefore),end-UInt64(request.accepted.maxTimeoutSeconds)<=now
        else{throw ExternalPaymentError.invalidAuthorization}
        if !allowExpired && now>=end{throw ExternalPaymentError.expired}
        guard (try? CanonicalBytes.hex(signature,count:65).contains(where:{$0 != 0}))==true else{throw ExternalPaymentError.invalidAuthorization}
    }
    public func header(now:UInt64) throws -> String {
        try validate(now:now)
        struct Resource:Encodable{let url:String}
        struct Payload:Encodable{let signature:String,authorization:PaymentAuthorization}
        struct Envelope:Encodable{let x402Version=2;let resource:Resource,accepted:PaymentRequirements,payload:Payload}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return try encoder.encode(Envelope(resource:Resource(url:request.service.resource),accepted:request.accepted,
            payload:Payload(signature:signature,authorization:authorization))).base64EncodedString()
    }
}

/// This is a server's settlement claim, not a verified purchase or delivery.
public struct PaymentReceipt: Codable, Equatable, Sendable {
    public let success:Bool
    public let transaction:String
    public let network:String
    public let payer:String?
    public let errorReason:String?
    /// An untrusted user-provided transaction locator; never settlement evidence.
    public static func unverifiedLocator(_ transaction:String,pending:PendingPayment,now:UInt64) throws -> PaymentReceipt {
        let value=PaymentReceipt(success:true,transaction:transaction,network:AgeShopProtocol.network,
            payer:pending.authorization.from,errorReason:nil)
        try value.validate(pending:pending,now:now)
        return value
    }
    public static func parse(header:String,pending:PendingPayment,now:UInt64) throws -> PaymentReceipt {
        try pending.validate(now:now,allowExpired:true)
        guard header.utf8.count<=16_384,let data=Data(base64Encoded:header) else{throw ExternalPaymentError.invalidReceipt}
        let receipt=try JSONDecoder().decode(Self.self,from:data)
        try receipt.validate(pending:pending,now:now)
        return receipt
    }
    public func validate(pending:PendingPayment,now:UInt64) throws {
        try pending.validate(now:now,allowExpired:true)
        guard network==AgeShopProtocol.network,
              payer?.lowercased()==pending.authorization.from.lowercased(),
              (try? CanonicalBytes.hex(transaction,count:32).contains(where:{$0 != 0}))==true,
              (success && errorReason==nil) || (!success && errorReason=="settlement_pending")
        else{throw ExternalPaymentError.invalidReceipt}
    }
    /// Call only with logs from a successful, canonical confirmed transaction
    /// at `transaction` on the configured chain, obtained independently of HTTP.
    public func validateTransfer(pending:PendingPayment,logs:[AgeShopReceipt.Log],now:UInt64) throws {
        try validate(pending:pending,now:now)
        guard network==AgeShopProtocol.network,payer?.lowercased()==pending.authorization.from.lowercased(),
              let amount=UInt64(pending.authorization.value) else{throw ExternalPaymentError.invalidReceipt}
        let from=try CanonicalBytes.hexString(Data(repeating:0,count:12)+CanonicalBytes.hex(pending.authorization.from,count:20))
        let to=try CanonicalBytes.hexString(Data(repeating:0,count:12)+CanonicalBytes.hex(pending.authorization.to,count:20))
        let value=CanonicalBytes.hexString(Data(repeating:0,count:24)+CanonicalBytes.u64(amount))
        let own=logs.filter{$0.address.lowercased()==AgeShopProtocol.token}
        let used=["0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5",from,pending.authorization.nonce.lowercased()]
        let canceled=["0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81",from,pending.authorization.nonce.lowercased()]
        let indices=own.indices.filter{own[$0].topics.map{$0.lowercased()}==used && own[$0].data=="0x"}
        // Circle's EIP-3009 consumes the nonce immediately before the transfer.
        // Pair adjacent token events; don't combine unrelated transfers in a batch.
        guard !own.contains(where:{$0.topics.map{$0.lowercased()}==canceled}),
              indices.count==1,let index=indices.first,index+1<own.count,
              own[index+1].topics.map({$0.lowercased()})==["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",from,to],
              own[index+1].data.lowercased()==value
        else{throw ExternalPaymentError.invalidReceipt}
    }
}
