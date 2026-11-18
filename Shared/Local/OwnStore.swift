import CryptoKit
import Foundation

struct OwnEntry: Identifiable, Sendable {
    let id: Int64
    let date: Date
    let original, text, context, preference, lesson: String
}

struct DailyLesson: Identifiable, Sendable {
    let id, lesson: String
    let count: Int
    let original, corrected: String
}

struct OwnStore {
    private let directory: URL?
    private let clock: () -> Date
    private let schedulesReminders: Bool

    init() {
        directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.io.nitinkhanna.ownphrase")?
            .appendingPathComponent("WritingMemory", isDirectory: true)
        clock = Date.init
        schedulesReminders = true
    }

    // Also allows deterministic tests across dates and independent database connections.
    init(directory: URL, clock: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.clock = clock
        schedulesReminders = false
    }

    private func connect() throws -> LocalDatabase {
        guard var directory else { throw LocalStoreError.unavailable }
        let manager = FileManager.default
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try directory.setResourceValues(resources)
        return try LocalDatabase(at: directory.appendingPathComponent("writing.sqlite"))
    }

    func record(original: String, accepted: RewriteOption) throws {
        let date = clock()
        let db = try connect()
        let context = Self.context(accepted.context)
        let lesson = accepted.lesson.trimmingCharacters(in: .whitespacesAndNewlines)
        let preference = Self.normalized(accepted.preference)
        try db.transaction {
            try db.run("""
                INSERT INTO entries (created,original,accepted,context,preference,lesson,topic) VALUES (?,?,?,?,?,?,?)
                """, [.date(date), .text(original), .text(accepted.text), .text(context), .text(preference), .text(lesson), .text(Self.topic(lesson))])
            if !preference.isEmpty {
                let evidence = Data(SHA256.hash(data: Data(original.utf8))).base64EncodedString()
                try db.run("""
                    INSERT INTO preferences(context,preference,evidence,updated) VALUES (?,?,?,?)
                    ON CONFLICT(context,preference,evidence) DO UPDATE SET updated=excluded.updated
                    """, [.text(context), .text(preference), .text(evidence), .date(date)])
            }
        }
        refreshReminderIfNeeded(at: date, lessonPossible: !lesson.isEmpty)
    }

    func observe(_ draft: String) throws {
        guard let observation = Observation(draft) else { return }
        let db = try connect()
        let date = clock()
        let day = Self.dayNumber(date)
        let didObserve = try db.transaction {
            guard try value("observe", in: db) != 0 else { return false }
            for (feature, count) in observation.counts {
                try db.run("""
                    INSERT INTO observations(day,context,feature,total) VALUES (?,?,?,?)
                    ON CONFLICT(day,context,feature) DO UPDATE SET total=total+excluded.total
                    """, [.int(day), .text(observation.context), .text(feature), .int(Int64(count))])
            }
            return true
        }
        let hasLesson = observation.counts.keys.contains { Observation.guidance[$0] != nil || Observation.grammarGuidance[$0] != nil }
        refreshReminderIfNeeded(at: date, lessonPossible: didObserve && hasLesson)
    }

    func history() throws -> [OwnEntry] {
        try connect().rows("""
            SELECT id,created,original,accepted,context,preference,lesson FROM entries ORDER BY created DESC,id DESC
            """) { OwnEntry(id: $0.int(0), date: $0.date(1), original: $0.text(2), text: $0.text(3), context: $0.text(4), preference: $0.text(5), lesson: $0.text(6)) }
    }

    func profile() throws -> String {
        let db = try connect()
        let preferences = try db.rows("""
            SELECT context,preference,count(*) AS evidence
            FROM preferences GROUP BY context,preference
            ORDER BY evidence DESC,max(updated) DESC,context,preference LIMIT 8
            """) { row in
            let count = row.int(2)
            let evidence = count == 1 ? "one example, tentative" : "\(count) distinct drafts"
            return "\(row.text(0)): \(row.text(1)) (\(evidence))."
        }
        let rows = try db.rows("""
            SELECT context,feature,sum(total) FROM observations GROUP BY context,feature ORDER BY context
            """) { ($0.text(0), $0.text(1), $0.int(2)) }
        var observations: [String] = []
        for (context, group) in Dictionary(grouping: rows, by: { $0.0 }).sorted(by: { $0.key < $1.key }) {
            let counts = Dictionary(uniqueKeysWithValues: group.map { ($0.1, $0.2) })
            let passages = counts["passages", default: 0]
            guard passages >= 3 else { continue }
            var traits = ["about \(counts["words", default: 0] / passages) words per passage"]
            let labels = [("greeting", "greeting openings"), ("questionOpening", "question openings"),
                          ("softRequest", "requests phrased as questions"), ("directOpening", "direct request openings"),
                          ("contractions", "clear contractions"), ("shortPassage", "short passages of ten words or fewer"),
                          ("multiSentence", "multi-sentence passages")]
            for (feature, label) in labels {
                let count = counts[feature, default: 0]
                if count >= 2 { traits.append("\(count) " + label) }
            }
            observations.append("Observed \(context.lowercased()) typing across \(passages) passages: " + traits.joined(separator: ", ") + ".")
        }
        let reflections = try db.rows("""
            SELECT context,trait,count(*) AS samples FROM reflections GROUP BY context,trait
            HAVING samples >= 2 ORDER BY samples DESC,max(updated) DESC,context,trait LIMIT 8
            """) { row in
                "Observed \(row.text(0).lowercased()) voice — \(row.text(1)) (\(row.int(2)) distinct passages)."
            }
        let choices = preferences.map { "Accepted rewrite preference — " + $0 }
        return (observations + reflections + choices).joined(separator: "\n")
    }

    func daily(on date: Date = Date()) throws -> [DailyLesson] {
        let db = try connect()
        let calendar = Calendar.current
        guard let day = calendar.dateInterval(of: .day, for: date) else { return [] }
        let examples = try db.rows("""
            SELECT topic,lesson,original,accepted FROM entries
            WHERE created >= ? AND created < ? AND topic != '' ORDER BY created DESC,id DESC
            """, [.date(day.start), .date(day.end)]) { ($0.text(0), $0.text(1), $0.text(2), $0.text(3)) }
        var seen = [String: Set<String>]()
        var newest = [String: (String,String,String)]()
        for (topic,lesson,original,accepted) in examples {
            seen[topic, default: []].insert(original)
            if newest[topic] == nil { newest[topic] = (lesson,original,accepted) }
        }
        var lessons = newest.map { topic, sample in
            DailyLesson(id: topic, lesson: sample.0, count: seen[topic]?.count ?? 1, original: sample.1, corrected: sample.2)
        }
        let totals = try db.rows("""
            SELECT feature,sum(total) FROM observations WHERE day=? GROUP BY feature
            """, [.int(Self.dayNumber(date))]) { ($0.text(0), Int($0.int(1))) }
        let counts = Dictionary(uniqueKeysWithValues: totals)
        for (word, guidance) in Observation.guidance {
            let total = counts[word, default: 0], passages = counts["passages_" + word, default: 0]
            guard total >= 3, passages >= 2 else { continue }
            lessons.append(DailyLesson(id: "vocabulary/" + word, lesson: "You used “\(word)” \(total) times across \(passages) passages. " + guidance, count: total, original: "", corrected: ""))
        }
        for (key, guidance) in Observation.grammarGuidance {
            let count = counts[key, default: 0]
            if count > 0 {
                lessons.append(DailyLesson(id: key, lesson: guidance, count: count, original: "", corrected: ""))
            }
        }
        return lessons.sorted { lhs,rhs in lhs.count == rhs.count ? lhs.id < rhs.id : lhs.count > rhs.count }
    }

    func erase() throws {
        let db = try connect()
        try db.transaction {
            try db.run("DELETE FROM entries")
            try db.run("DELETE FROM observations")
            try db.run("DELETE FROM preferences")
            try db.run("DELETE FROM reflections")
            try db.run("DELETE FROM metadata WHERE key='reflectionGeneration'")
        }
        if schedulesReminders { LessonNotice.cancel() }
    }

    func observationEnabled() throws -> Bool { try value("observe", in: connect()) != 0 }
    func setObservationEnabled(_ enabled: Bool) throws {
        let db = try connect()
        try db.transaction {
            try db.run("INSERT INTO settings(key,value) VALUES ('observe',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                       [.int(enabled ? 1 : 0)])
            if !enabled { try db.run("DELETE FROM metadata WHERE key='reflectionGeneration'") }
        }
    }

    func beginReflection() throws -> String? {
        let db = try connect()
        return try db.transaction {
            guard try value("observe", in: db) != 0 else { return nil }
            if let generation = try reflectionGeneration(in: db) { return generation }
            let generation = UUID().uuidString
            try db.run("INSERT INTO metadata(key,value) VALUES ('reflectionGeneration',?)", [.text(generation)])
            return generation
        }
    }

    func recordReflection(trait: String, context: String, evidence: String, generation: String) throws {
        let label = Self.normalized(trait)
        guard !label.isEmpty, !evidence.isEmpty else { return }
        let db = try connect()
        try db.transaction {
            guard try value("observe", in: db) != 0, try reflectionGeneration(in: db) == generation else { return }
            let digest = Data(SHA256.hash(data: Data(evidence.utf8))).base64EncodedString()
            try db.run("""
                INSERT INTO reflections(context,trait,evidence,updated) VALUES (?,?,?,?)
                ON CONFLICT(context,trait,evidence) DO UPDATE SET updated=excluded.updated
                """, [.text(Self.context(context)), .text(label), .text(digest), .date(clock())])
        }
    }

    private func reflectionGeneration(in db: LocalDatabase) throws -> String? {
        try db.rows("SELECT value FROM metadata WHERE key='reflectionGeneration'") { $0.text(0) }.first
    }

    func reminderTime() throws -> (hour: Int, minute: Int)? {
        guard let minutes = try value("reminder", in: connect()), minutes >= 0 else { return nil }
        return (Int(minutes / 60), Int(minutes % 60))
    }

    func setReminder(hour: Int, minute: Int) throws {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { throw LocalStoreError.invalidTime }
        try set("reminder", value: Int64(hour * 60 + minute))
    }

    func clearReminder() throws { try set("reminder", value: -1) }

    private func refreshReminderIfNeeded(at date: Date, lessonPossible: Bool) {
        guard schedulesReminders, lessonPossible, let time = try? reminderTime(),
              let lessons = try? daily(on: date), !lessons.isEmpty else { return }
        LessonNotice.schedule(for: date, hour: time.hour, minute: time.minute, lessons: lessons)
    }

    private func value(_ key: String, in db: LocalDatabase) throws -> Int64? {
        try db.rows("SELECT value FROM settings WHERE key=?", [.text(key)]) { $0.int(0) }.first
    }

    private func set(_ key: String, value: Int64) throws {
        try connect().run("INSERT INTO settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                          [.text(key), .int(value)])
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200))
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private static func topic(_ lesson: String) -> String {
        let topic = lesson.components(separatedBy: " — ").first ?? lesson
        return normalized(topic)
    }

    private static func context(_ context: String) -> String {
        switch context.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "work", "professional": "Work"
        case "casual", "personal": "Casual"
        case "family": "Family"
        case "friends": "Friends"
        default: "General"
        }
    }

    private static func dayNumber(_ date: Date) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year,.month,.day], from: date)
        let year = Int64(parts.year ?? 0)
        let month = Int64(parts.month ?? 0)
        let day = Int64(parts.day ?? 0)
        return year * 10000 + month * 100 + day
    }
}
