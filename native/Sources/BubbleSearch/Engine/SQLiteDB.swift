import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over the system SQLite. One instance = one connection;
/// callers are responsible for confining use to a single thread/actor.
final class SQLiteDB {
    private var handle: OpaquePointer?
    let path: String

    enum Value {
        case null
        case int(Int64)
        case real(Double)
        case text(String)
        case blob(Data)
    }

    struct Row {
        let values: [Value]

        func int(_ i: Int) -> Int64? { if case .int(let v) = values[i] { return v }; return nil }
        func double(_ i: Int) -> Double? {
            switch values[i] {
            case .real(let v): return v
            case .int(let v): return Double(v)
            default: return nil
            }
        }
        func text(_ i: Int) -> String? { if case .text(let v) = values[i] { return v }; return nil }
        func blob(_ i: Int) -> Data? { if case .blob(let v) = values[i] { return v }; return nil }
    }

    init(path: String, readonly: Bool = false) throws {
        self.path = path
        let flags = readonly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            throw BubbleSearchError("cannot open \(path): \(msg)")
        }
        handle = db
        sqlite3_busy_timeout(handle, 3000)
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw BubbleSearchError("exec failed: \(msg) — \(sql.prefix(120))")
        }
    }

    @discardableResult
    func run(_ sql: String, _ params: [Value] = []) throws -> Int {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw BubbleSearchError("step failed (\(rc)): \(String(cString: sqlite3_errmsg(handle)))")
        }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ params: [Value] = []) throws -> [Row] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rows: [Row] = []
        let colCount = Int(sqlite3_column_count(stmt))
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else {
                throw BubbleSearchError("query step failed (\(rc)): \(String(cString: sqlite3_errmsg(handle)))")
            }
            var values: [Value] = []
            values.reserveCapacity(colCount)
            for i in 0..<colCount {
                switch sqlite3_column_type(stmt, Int32(i)) {
                case SQLITE_INTEGER: values.append(.int(sqlite3_column_int64(stmt, Int32(i))))
                case SQLITE_FLOAT: values.append(.real(sqlite3_column_double(stmt, Int32(i))))
                case SQLITE_TEXT: values.append(.text(String(cString: sqlite3_column_text(stmt, Int32(i)))))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(stmt, Int32(i)) {
                        values.append(.blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, Int32(i))))))
                    } else {
                        values.append(.blob(Data()))
                    }
                default: values.append(.null)
                }
            }
            rows.append(Row(values: values))
        }
        return rows
    }

    private func prepare(_ sql: String, _ params: [Value]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw BubbleSearchError("prepare failed: \(String(cString: sqlite3_errmsg(handle))) — \(sql.prefix(120))")
        }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .real(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                v.withUnsafeBytes { buf in
                    _ = sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            }
        }
        return stmt
    }
}

struct BubbleSearchError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
