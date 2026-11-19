/// A wall-clock time like `16:15`, interpreted in some time zone by the caller.
struct TimeOfDay: Hashable, Sendable, CustomStringConvertible {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        precondition((0..<24).contains(hour) && (0..<60).contains(minute), "Invalid time \(hour):\(minute)")
        self.hour = hour
        self.minute = minute
    }

    /// Parses `HH:mm`.
    init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    var description: String {
        let paddedMinute = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(hour):\(paddedMinute)"
    }
}
