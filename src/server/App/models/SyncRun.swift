import Fluent
import Foundation

/// One attempt to pull rates from the upstream source. The latest row feeds `/health`.
final class SyncRun: Model, @unchecked Sendable {
    static let schema = "sync_runs"

    enum Trigger: String, Codable, Sendable {
        /// Backfill or catch-up when the server starts.
        case startup
        /// Weekday run after the ECB publication time.
        case scheduled
    }

    enum Status: String, Codable, Sendable {
        case running
        case success
        /// The request succeeded (or wasn't needed) but there were no new days.
        case noNewData = "no_new_data"
        case failed
    }

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "trigger")
    var trigger: Trigger

    @Field(key: "status")
    var status: Status

    @Field(key: "started_at")
    var startedAt: Date

    @OptionalField(key: "finished_at")
    var finishedAt: Date?

    @OptionalField(key: "range_start")
    var rangeStart: String?

    @OptionalField(key: "range_end")
    var rangeEnd: String?

    @Field(key: "dates_added")
    var datesAdded: Int

    @OptionalField(key: "latest_rate_date")
    var latestRateDate: String?

    @OptionalField(key: "error")
    var error: String?

    init() {}

    init(trigger: Trigger, startedAt: Date, range: ClosedRange<RateDate>?) {
        self.trigger = trigger
        self.status = .running
        self.startedAt = startedAt
        self.rangeStart = range?.lowerBound.description
        self.rangeEnd = range?.upperBound.description
        self.datesAdded = 0
    }
}
