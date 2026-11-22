import Foundation
import RecipeCore

/// ISO 8601 durations in full: "PT1H30M", "P0DT1H", fractional and
/// compound forms. Negative durations are invalid; zero is allowed.
public enum ISODuration {
    /// Parses an ISO 8601 duration into seconds. Nil when malformed.
    public static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.hasPrefix("P") else { return nil }
        var rest = trimmed.dropFirst()
        var total = 0
        var componentCount = 0
        // The "T" separator: date designators before it are calendar
        // values, time designators after it are clock values. A "T"
        // with nothing before it ("PT30M") is legal.
        var inTimePart = false
        var seenT = false
        // Each component: a number and a designator (Y M W D H M S).
        // "M" means months before "T" and minutes after it.
        while !rest.isEmpty {
            if rest.first == "T" {
                guard !seenT else { return nil }
                seenT = true
                inTimePart = true
                rest = rest.dropFirst()
                continue
            }
            let number = rest.prefix { $0.isNumber || $0 == "." }
            guard !number.isEmpty else { return nil }
            rest = rest.dropFirst(number.count)
            guard let designator = rest.first else { return nil }
            rest = rest.dropFirst()
            guard
                let value = Decimal(
                    string: String(number), locale: Locale(identifier: "en_US_POSIX"))
            else { return nil }
            let seconds: Decimal
            switch designator {
            case "Y", "M", "W", "D", "H", "S":
                break
            default:
                return nil
            }
            switch designator {
            case "Y": seconds = value * 31_556_952  // the Gregorian year
            case "M" where !inTimePart: seconds = value * 2_629_746  // the month
            case "W": seconds = value * 604_800
            case "D": seconds = value * 86_400
            case "H": seconds = value * 3_600
            case "M": seconds = value * 60
            case "S": seconds = value
            default: return nil
            }
            var rounded = Decimal()
            var source = seconds
            NSDecimalRound(&rounded, &source, 0, .plain)
            total += (rounded as NSDecimalNumber).intValue
            componentCount += 1
        }
        guard componentCount > 0 else { return nil }
        guard seenT || hasDateComponent(trimmed) else { return nil }
        return total
    }

    /// Renders seconds as the shortest ISO 8601 duration ("PT1H30M").
    public static func render(seconds: Int) -> String {
        guard seconds > 0 else { return "PT0S" }
        var rest = seconds
        var parts: [String] = []
        let days = rest / 86_400
        rest %= 86_400
        let hours = rest / 3_600
        rest %= 3_600
        let minutes = rest / 60
        let secs = rest % 60
        var time = ""
        if hours > 0 { time += "\(hours)H" }
        if minutes > 0 { time += "\(minutes)M" }
        if secs > 0 { time += "\(secs)S" }
        if days > 0 { parts.append("\(days)D") }
        // A time part only appears when there is time: "P1D", "PT30M".
        if !time.isEmpty { parts.append("T" + time) }
        if parts.isEmpty { parts.append("T0S") }
        return "P" + parts.joined()
    }

    private static func hasDateComponent(_ text: String) -> Bool {
        // "P1D" and friends: any date designator before a "T".
        guard let tIndex = text.firstIndex(of: "T") else {
            return text.contains(where: { "YWD".contains($0) })
        }
        return text[..<tIndex].contains(where: { "YWD".contains($0) })
    }
}

/// Renders a duration the way the app shows it ("1 hr 30 min").
public func durationDisplay(seconds: Int) -> String {
    guard seconds > 0 else { return "" }
    var rest = seconds
    var parts: [String] = []
    let days = rest / 86_400
    rest %= 86_400
    let hours = rest / 3_600
    rest %= 3_600
    let minutes = rest / 60
    if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
    if hours > 0 { parts.append(hours == 1 ? "1 hr" : "\(hours) hrs") }
    if minutes > 0 { parts.append(minutes == 1 ? "1 min" : "\(minutes) mins") }
    if parts.isEmpty && seconds > 0 { parts.append("\(seconds) secs") }
    return parts.joined(separator: " ")
}
