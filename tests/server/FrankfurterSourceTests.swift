import Foundation
import Testing
@testable import App

struct FrankfurterSourceTests {
    @Test func decodesTimeseriesWithExactDecimals() throws {
        let json = Data("""
        {"amount":1.0,"base":"EUR","start_date":"2026-11-17","end_date":"2026-11-18",
         "rates":{"2026-11-18":{"JPY":174.85,"USD":1.0968},"2026-11-17":{"JPY":175.1,"USD":1.0981}}}
        """.utf8)

        let days = try FrankfurterSource.decodeTimeseries(json)

        #expect(days.map(\.date) == [date("2026-11-17"), date("2026-11-18")])
        #expect(days[1].rates["USD"] == Decimal(string: "1.0968"))
        #expect(days[1].rates["JPY"]?.description == "174.85")
    }

    @Test func rejectsInvalidDates() {
        let json = Data(#"{"rates":{"2026-13-01":{"USD":1.1}}}"#.utf8)
        #expect(throws: FrankfurterSource.SourceError.self) { try FrankfurterSource.decodeTimeseries(json) }
    }
}
