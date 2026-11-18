/// Where the server gets reference rates from. All rates are relative to EUR,
/// exactly as the ECB publishes them.
protocol UpstreamRatesSource: Sendable {
    /// ISO 4217 code → English currency name.
    func currencies() async throws -> [String: String]

    /// Rates for every publication day in `start...end`, oldest first.
    /// Returns an empty array when nothing has been published in that range yet.
    func rates(from start: RateDate, to end: RateDate) async throws -> [DailyRates]
}
