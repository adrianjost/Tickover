import Foundation

/// A time entry on the self-hosted server. Times are ISO 8601 strings in UTC; `end` is nil
/// while the timer runs.
struct TrackedEntry: Codable, Equatable {
  let id: String
  let start: String
  var end: String?

  var startDate: Date? { ISO8601Instant.parse(start) }
  var endDate: Date? { end.flatMap(ISO8601Instant.parse) }

  /// A running timer counts until now.
  var seconds: Double {
    guard let startDate else { return 0 }
    return max(0, (endDate ?? Date()).timeIntervalSince(startDate))
  }

  // The web view tells a running timer by `end: null`, so the key must not be left out.
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(start, forKey: .start)
    try container.encode(end, forKey: .end)
  }
}

/// Client for the optional self-hosted time tracking server in `server/`.
struct TrackingServer {
  let baseURL: URL
  let token: String

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    return URLSession(configuration: configuration)
  }()

  private struct Timer: Decodable {
    let running: TrackedEntry?
  }

  private struct ErrorBody: Decodable {
    let error: String
  }

  private struct Session: Decodable {
    let token: String
  }

  /// Signs in and returns a session token for this device.
  static func signIn(baseURL: URL, username: String, password: String) async throws -> String {
    let anonymous = TrackingServer(baseURL: baseURL, token: "")
    let session: Session = try await anonymous.request(
      "POST", "api/login", body: ["username": username, "password": password])
    return session.token
  }

  func signOut() async throws {
    _ = try await send("POST", "api/logout")
  }

  func entries(from: Date, to: Date) async throws -> [TrackedEntry] {
    let query = [
      URLQueryItem(name: "from", value: ISO8601Instant.format(from)),
      URLQueryItem(name: "to", value: ISO8601Instant.format(to)),
    ]
    return try await request("GET", "api/entries", query: query)
  }

  func runningTimer() async throws -> TrackedEntry? {
    let timer: Timer = try await request("GET", "api/timer")
    return timer.running
  }

  func create(start: String, end: String?) async throws -> TrackedEntry {
    try await request("POST", "api/entries", body: ["start": start, "end": end])
  }

  /// Creates or replaces the entry under its own ID, so sending it again is harmless.
  func put(_ entry: TrackedEntry) async throws -> TrackedEntry {
    try await request("PUT", "api/entries/\(entry.id)", body: ["start": entry.start, "end": entry.end])
  }

  func update(id: String, start: String, end: String?) async throws -> TrackedEntry {
    try await request("PATCH", "api/entries/\(id)", body: ["start": start, "end": end])
  }

  func delete(id: String) async throws {
    _ = try await send("DELETE", "api/entries/\(id)")
  }

  func workSchedules() async throws -> [WorkSchedule] {
    let response: WorkSchedules = try await request("GET", "api/work-hours")
    return response.schedules
  }

  func setWorkSchedules(_ schedules: [WorkSchedule]) async throws -> [WorkSchedule] {
    let body = schedules.map { ["from": $0.from ?? NSNull() as Any, "hours": $0.hours] }
    let response: WorkSchedules = try await request(
      "PUT", "api/work-hours", body: ["schedules": body])
    return response.schedules
  }

  private struct WorkSchedules: Decodable {
    let schedules: [WorkSchedule]
  }

  /// Seconds worked per local calendar day, attributing each entry to the day it started.
  static func secondsPerDay(_ entries: [TrackedEntry]) -> [PlainDate: Double] {
    var result: [PlainDate: Double] = [:]
    for entry in entries {
      guard let start = entry.startDate else { continue }
      result[PlainDates.formatLocal(start), default: 0] += entry.seconds
    }
    return result
  }

  private func request<Response: Decodable>(
    _ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any?]? = nil
  ) async throws -> Response {
    try JSONDecoder().decode(
      Response.self, from: try await send(method, path, query: query, body: body))
  }

  private func send(
    _ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any?]? = nil
  ) async throws -> Data {
    var components = URLComponents(
      url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    if !query.isEmpty { components.queryItems = query }
    var request = URLRequest(url: components.url!)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(
        withJSONObject: body.mapValues { $0 ?? NSNull() as Any })
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await Self.session.data(for: request)
    } catch {
      throw ServerUnreachableError(reason: error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse else {
      throw ClockifyError(message: "Unexpected response from the time tracking server")
    }
    guard (200..<300).contains(http.statusCode) else {
      let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
      if http.statusCode == 401 && message == "Unauthorized" {
        throw SessionExpiredError()
      }
      throw ClockifyError(message: message ?? "Time tracking server error (HTTP \(http.statusCode))")
    }
    return data
  }
}

struct ServerUnreachableError: LocalizedError {
  let reason: String
  var errorDescription: String? { "Time tracking server unreachable: \(reason)" }
}

/// The server no longer accepts the session, e.g. after a password or username change.
struct SessionExpiredError: LocalizedError {
  var errorDescription: String? {
    "You were signed out of the time tracking server. Sign in again in Settings."
  }
}
