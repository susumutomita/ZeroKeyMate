import Foundation

/// The application and store independently enforce this small, versioned
/// catalogue. Model output and remote descriptions cannot set prices or age.
public enum ShopProduct: String, Codable, CaseIterable, Sendable {
    case lager = "mate-lager"
    case sparklingWater = "mate-sparkling-water"

    public var name: String { self == .lager ? "Mate Lager" : "Mate Sparkling Water" }
    public var unitAmount: UInt64 { self == .lager ? 100_000 : 50_000 }
    public var minimumAge: Int { self == .lager ? 20 : 0 }
    public var size: String { self == .lager ? "330 ml" : "500 ml" }
}

public struct ShopSelection: Codable, Equatable, Sendable {
    public let product: ShopProduct
    public let quantity: Int
    public static let maximumQuantity = 5
    public static let lager = try! ShopSelection(product: .lager, quantity: 1)

    public init(product: ShopProduct, quantity: Int) throws {
        guard (1...Self.maximumQuantity).contains(quantity) else { throw AgeShopError.invalidOrder }
        self.product = product; self.quantity = quantity
    }
    public var amount: UInt64 { product.unitAmount * UInt64(quantity) }
    public var displayAmount: String { TokenAmount(units: amount).display }
    public var requiresAgeProof: Bool { product.minimumAge > 0 }

    /// Reconstruct from trusted product rules, not a server-supplied age flag.
    public init(order: AgeShopOrder) throws {
        guard let product = ShopProduct(rawValue: order.productId) else { throw AgeShopError.invalidOrder }
        try self.init(product: product, quantity: order.quantity)
        guard order.amount == String(amount), order.minimumAge == product.minimumAge else { throw AgeShopError.invalidOrder }
    }

    // Decoding must not bypass the quantity bound before computing an amount.
    enum CodingKeys: String, CodingKey { case product, quantity }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(product: values.decode(ShopProduct.self, forKey: .product),
                      quantity: values.decode(Int.self, forKey: .quantity))
    }
}
