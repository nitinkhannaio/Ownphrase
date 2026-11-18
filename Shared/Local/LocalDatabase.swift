import Foundation
import SQLite3

enum LocalStoreError: LocalizedError {
    case unavailable
    case database(Int32)
    case invalidTime
    case permission

    var errorDescription: String? {
        switch self {
        case .unavailable: "Writing memory is unavailable. Unlock your phone and check keyboard Full Access."
        case .database: "Writing memory could not be accessed. Please try again."
        case .invalidTime: "Choose a valid reminder time."
        case .permission: "Allow notifications in Settings to receive daily lessons."
        }
    }
}

enum SQLValue {
    case text(String), int(Int64), date(Date)
}

struct SQLRow {
    let statement: OpaquePointer
    func text(_ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        let length = Int(sqlite3_column_bytes(statement, index))
        return String(decoding: UnsafeBufferPointer(start: pointer, count: length), as: UTF8.self)
    }
    func int(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }
    func date(_ index: Int32) -> Date { Date(timeIntervalSince1970: sqlite3_column_double(statement, index)) }
}

final class LocalDatabase {
    private let connection: OpaquePointer

    init(at url: URL) throws {
        var db: OpaquePointer?
        var flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        #if os(iOS)
        flags |= SQLITE_OPEN_FILEPROTECTION_COMPLETE
        #endif
        let result = sqlite3_open_v2(url.path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw LocalStoreError.database(result)
        }
        connection = db
        sqlite3_busy_timeout(db, 2500)
        try run("PRAGMA secure_delete = ON")
        let version = try rows("PRAGMA user_version", map: { $0.int(0) }).first ?? 0
        if version < 1 {
            try transaction {
                try run("""
                    CREATE TABLE IF NOT EXISTS entries (
                      id INTEGER PRIMARY KEY, created REAL NOT NULL, original TEXT NOT NULL, accepted TEXT NOT NULL,
                      context TEXT NOT NULL, preference TEXT NOT NULL, lesson TEXT NOT NULL, topic TEXT NOT NULL
                    )
                    """)
                try run("CREATE INDEX IF NOT EXISTS entries_by_date ON entries(created DESC)")
                try run("""
                    CREATE TABLE IF NOT EXISTS preferences (
                      context TEXT NOT NULL, preference TEXT NOT NULL, evidence TEXT NOT NULL, updated REAL NOT NULL,
                      PRIMARY KEY(context, preference, evidence)
                    ) WITHOUT ROWID
                    """)
                try run("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
                try run("""
                    CREATE TABLE IF NOT EXISTS observations (
                      day INTEGER NOT NULL, context TEXT NOT NULL, feature TEXT NOT NULL, total INTEGER NOT NULL,
                      PRIMARY KEY(day, context, feature)
                    ) WITHOUT ROWID
                    """)
                // Set the final schema version after the reflection tables exist.
            }
        }
        if version < 2 {
            try transaction {
                try run("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                try run("""
                    CREATE TABLE IF NOT EXISTS reflections (
                      context TEXT NOT NULL, trait TEXT NOT NULL, evidence TEXT NOT NULL, updated REAL NOT NULL,
                      PRIMARY KEY(context,trait,evidence)
                    ) WITHOUT ROWID
                    """)
                try run("PRAGMA user_version = 2")
            }
        }
    }

    deinit { sqlite3_close(connection) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try run("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try run("COMMIT")
            return result
        } catch {
            try? run("ROLLBACK")
            throw error
        }
    }

    func run(_ sql: String, _ values: [SQLValue] = []) throws {
        _ = try rows(sql, values) { _ in () }
    }

    func rows<T>(_ sql: String, _ values: [SQLValue] = [], map: (SQLRow) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw LocalStoreError.database(result) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .text(let text):
                status = sqlite3_bind_text(statement, index, text, Int32(text.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .date(let date):
                status = sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
            case .int(let number):
                status = sqlite3_bind_int64(statement, index, number)
            }
            guard status == SQLITE_OK else { throw LocalStoreError.database(status) }
        }
        var output: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: output.append(map(SQLRow(statement: statement)))
            case SQLITE_DONE: return output
            case let status: throw LocalStoreError.database(status)
            }
        }
    }
}
