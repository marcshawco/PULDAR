import Foundation

extension Date {
    /// First instant of the month containing this date.
    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.start ?? self
    }

    /// Last instant of the month containing this date.
    var endOfMonth: Date {
        guard let interval = Calendar.current.dateInterval(of: .month, for: self) else {
            return self
        }
        return interval.end.addingTimeInterval(-1)
    }

    /// Compact relative formatter: "Today", "Yesterday", "Feb 18", etc.
    var shortRelative: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = calendar.isDate(self, equalTo: .now, toGranularity: .year)
            ? "MMM d"
            : "MMM d, yyyy"
        return formatter.string(from: self)
    }
}
