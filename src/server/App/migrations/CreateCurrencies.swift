import Fluent

struct CreateCurrencies: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(CurrencyModel.schema)
            .field("code", .string, .identifier(auto: false))
            .field("name", .string, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(CurrencyModel.schema).delete()
    }
}
