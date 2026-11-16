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

/// Hours expected on each weekday (Monday first) from `from` on, until the next schedule starts.
/// Schedules are sorted by date; the first one has no start date and also covers everything before.
struct WorkSchedule: Codable, Equatable {
  var from: PlainDate?
  var hours: [Double]

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(from, forKey: .from)
    try container.encode(hours, forKey: .hours)
  }
}

enum OvertimeReport {
  static let defaultWorkSchedules = [WorkSchedule(from: nil, hours: [8, 8, 8, 8, 8, 0, 0])]

  static func expectedHours(on day: PlainDate, schedules: [WorkSchedule]) -> Double {
    let schedule = schedules.last { $0.from.map { $0 <= day } ?? true } ?? schedules.first
    let weekday = PlainDates.weekdayFromMonday(day)
    guard let hours = schedule?.hours, hours.indices.contains(weekday) else { return 0 }
    return hours[weekday]
  }

  /// Compares worked hours to the hours expected on each day by the schedule that applies then.
  /// Days without any time entry count neither as worked nor as expected.
  static func build(
    secondsPerDay: [PlainDate: Double], startDate: PlainDate, endDate: PlainDate,
    schedules: [WorkSchedule]
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
        let expectedHours = expectedHours(on: day, schedules: schedules)
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
