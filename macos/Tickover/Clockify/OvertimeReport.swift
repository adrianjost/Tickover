import Foundation

struct OvertimeData: Encodable {
  struct Day: Encodable {
    let date: PlainDate
    let actualHours: Double
    let expectedHours: Double
    let cumulativeOvertimeHours: Double
  }

  let totalOvertimeHours: Int
  let totalOvertimeMinutes: Int
  let dailyData: [Day]

  var totalOvertimeSeconds: Int { (totalOvertimeHours * 60 + totalOvertimeMinutes) * 60 }
}

enum OvertimeReport {
  static let defaultWorkHours: [Double] = [8, 8, 8, 8, 8, 0, 0]

  /// Compares worked hours to the hours expected on each weekday (`workHours`, Monday first).
  /// Days without any time entry count neither as worked nor as expected.
  static func build(
    secondsPerDay: [PlainDate: Double], startDate: PlainDate, endDate: PlainDate,
    workHours: [Double]
  ) throws -> OvertimeData {
    guard PlainDates.parse(startDate) != nil, PlainDates.parse(endDate) != nil else {
      throw ClockifyError(message: "Invalid date format, expected YYYY-MM-DD")
    }

    var dailyData: [OvertimeData.Day] = []
    var expected: Double = 0
    var actual: Double = 0

    var day = startDate
    while day <= endDate {
      if let worked = secondsPerDay[day] {
        let weekday = PlainDates.weekdayFromMonday(day)
        let expectedHours = workHours.indices.contains(weekday) ? workHours[weekday] : 0
        expected += expectedHours * 3600
        actual += worked
        dailyData.append(
          .init(
            date: day,
            actualHours: hoursTruncatedToMinutes(worked),
            expectedHours: expectedHours,
            cumulativeOvertimeHours: hoursTruncatedToMinutes(actual - expected)
          ))
      } else if (day == startDate && dailyData.isEmpty) || day == endDate {
        // Anchor entries for start/end date so the chart spans the full range.
        dailyData.append(
          .init(
            date: day,
            actualHours: 0,
            expectedHours: 0,
            cumulativeOvertimeHours: hoursTruncatedToMinutes(actual - expected)
          ))
      }
      day = PlainDates.addDays(day, 1)
    }

    let totalMinutes = Int((actual - expected) / 60)
    return OvertimeData(
      totalOvertimeHours: totalMinutes / 60,
      totalOvertimeMinutes: totalMinutes % 60,
      dailyData: dailyData
    )
  }

  private static func hoursTruncatedToMinutes(_ seconds: Double) -> Double {
    (seconds / 60).rounded(.towardZero) / 60
  }
}
