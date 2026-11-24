import Foundation

/// Timer changes saved on this Mac first and sent to the server in order, so the timer works
/// offline. Mirrors the outbox of the web page in `src/web/offline.ts`.
final class TimerOutbox {
  enum Change: Codable, Equatable {
    case put(TrackedEntry)
    case delete(id: String)

    var entryID: String {
      switch self {
      case .put(let entry): entry.id
      case .delete(let id): id
      }
    }
  }

  private let file: URL
  private(set) var changes: [Change]
  private var flushing: Task<[String], Error>?

  init(file: URL) {
    self.file = file
    changes = (try? JSONDecoder().decode([Change].self, from: Data(contentsOf: file))) ?? []
  }

  var isEmpty: Bool { changes.isEmpty }

  func add(_ change: Change) {
    // A newer version of an entry replaces its unsent one, keeping its place in line.
    if case .put = change,
      let index = changes.firstIndex(where: {
        if case .put = $0 { $0.entryID == change.entryID } else { false }
      })
    {
      changes[index] = change
    } else {
      changes.append(change)
    }
    save()
  }

  func clear() {
    changes = []
    save()
  }

  /// Sends the changes in order and returns why the server refused any of them; those are
  /// dropped, as the server's version wins. Stops, keeping the rest, while the server is unreachable.
  func flush(to server: TrackingServer) async throws -> [String] {
    if let flushing { return try await flushing.value }
    let task = Task { try await send(to: server) }
    flushing = task
    defer { flushing = nil }
    return try await task.value
  }

  private func send(to server: TrackingServer) async throws -> [String] {
    var refused: [String] = []
    while let change = changes.first {
      do {
        switch change {
        case .put(let entry): _ = try await server.put(entry)
        case .delete(let id): try await server.delete(id: id)
        }
      } catch let error as ClockifyError {
        // Deleting an entry that is already gone is fine.
        if case .put = change { refused.append(error.localizedDescription) }
      }
      // Unless a newer version replaced it meanwhile; that one is sent next.
      if changes.first == change { changes.removeFirst() }
      save()
    }
    return refused
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(changes).write(to: file, options: .atomic)
    } catch {
      print("Saving the timer outbox failed:", error.localizedDescription)
    }
  }
}
