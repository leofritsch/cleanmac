import Foundation

/// One full overview scan, kept so later scans can show what grew.
struct Snapshot: Codable, Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let used: Int64
    let total: Int64
    let layers: [String: Int64]
    /// Measured folder path → bytes.
    let folders: [String: Int64]
}

enum HistoryStore {
    private static var url: URL {
        let dir = Paths.lib("Application Support/Clean Mac")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    static func load() -> [Snapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Snapshot].self, from: data)) ?? []
    }

    /// Scans within an hour replace each other so a busy afternoon doesn't drown the history.
    static func record(_ snap: Snapshot, into history: [Snapshot]) -> [Snapshot] {
        var list = history
        if let last = list.last, snap.date.timeIntervalSince(last.date) < 3600 {
            list.removeLast()
        }
        list.append(snap)
        if list.count > 120 { list.removeFirst(list.count - 120) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) { try? data.write(to: url, options: .atomic) }
        return list
    }

    /// The most recent snapshot at least a day older than `date`, else the oldest one.
    static func baseline(in history: [Snapshot], before date: Date) -> Snapshot? {
        let older = history.filter { $0.date < date.addingTimeInterval(-3600) }
        return older.last(where: { date.timeIntervalSince($0.date) >= 86_400 }) ?? older.first
    }
}
