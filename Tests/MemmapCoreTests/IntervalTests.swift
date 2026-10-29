import Foundation
import MemmapCore
import Testing

private let us = Locale(identifier: "en_US")

@Test func acceptsIntervalsInRange() {
  #expect(parseRefreshInterval("7", locale: us) == 7)
  #expect(parseRefreshInterval(" 0.5 ", locale: us) == 0.5)
  #expect(parseRefreshInterval("3600", locale: us) == 3600)
  #expect(parseRefreshInterval("1,5", locale: Locale(identifier: "de_DE")) == 1.5)
}

@Test func rejectsIntervalsOutOfRangeOrUnparsable() {
  #expect(parseRefreshInterval("0.4", locale: us) == nil)
  #expect(parseRefreshInterval("3601", locale: us) == nil)
  #expect(parseRefreshInterval("", locale: us) == nil)
  #expect(parseRefreshInterval("abc", locale: us) == nil)
}

@Test func formatsIntervalsWithoutGrouping() {
  #expect(formatRefreshInterval(2, locale: us) == "2")
  #expect(formatRefreshInterval(0.5, locale: us) == "0.5")
  #expect(formatRefreshInterval(3600, locale: us) == "3600")
}
