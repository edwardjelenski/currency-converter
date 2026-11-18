import Fluent

/// A currency we have rates for. Primary key is the ISO 4217 code.
final class CurrencyModel: Model, @unchecked Sendable {
    static let schema = "currencies"

    @ID(custom: "code", generatedBy: .user)
    var id: String?

    @Field(key: "name")
    var name: String

    init() {}

    init(code: String, name: String) {
        self.id = code
        self.name = name
    }
}
