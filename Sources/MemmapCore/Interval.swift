import Foundation

public let refreshIntervalRange = 0.5...3600.0

public func parseRefreshInterval(_ text: String, locale: Locale = .current) -> Double? {
  let trimmed = text.trimmingCharacters(in: .whitespaces)
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.locale = locale
  guard let value = Double(trimmed) ?? formatter.number(from: trimmed)?.doubleValue,
    refreshIntervalRange.contains(value)
  else { return nil }
  return value
}

public func formatRefreshInterval(_ value: Double, locale: Locale = .current) -> String {
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.locale = locale
  formatter.maximumFractionDigits = 3
  formatter.usesGroupingSeparator = false
  return formatter.string(from: NSNumber(value: value)) ?? String(value)
}
