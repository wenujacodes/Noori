/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Defaults
import Foundation
import SQLite3

/// A message read from the Messages database. Lives in memory only.
struct MessagesDatabaseRow: Sendable {
    let rowID: Int
    let text: String
    let date: Date?
    let handle: String
    let service: String
    let chatGUID: String?
    let chatDisplayName: String?
    let isGroupChat: Bool
}

/// Reads new incoming messages from `~/Library/Messages/chat.db`, read-only.
/// Needs Full Disk Access. Never logs message contents.
/// All calls must come from the same serial queue.
final class MessagesDatabaseReader {
    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
    }

    enum ReadError: Error {
        case cannotOpen
        case queryFailed
    }

    /// Opens the database, runs `body`, closes it again. Opening per read keeps no
    /// lock on Messages' file and always sees the newest WAL contents.
    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(Self.databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw ReadError.cannotOpen
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        return try body(db)
    }

    /// True when the database can be opened and read (Full Disk Access granted).
    func canRead() -> Bool {
        (try? withDatabase { db in
            try Self.scalarInt(db, "SELECT COUNT(*) FROM (SELECT ROWID FROM message LIMIT 1)")
        }) != nil
    }

    func maxRowID() throws -> Int {
        try withDatabase { db in
            try Self.scalarInt(db, "SELECT IFNULL(MAX(ROWID), 0) FROM message")
        }
    }

    /// Incoming messages (not from me, not reactions or system items) after `rowID`.
    func incomingMessages(after rowID: Int) throws -> [MessagesDatabaseRow] {
        try withDatabase { db in
            if let rows = try? Self.query(db, after: rowID, sql: Self.fullQuery) {
                return rows
            }
            // Older schemas without the reaction/item columns.
            return try Self.query(db, after: rowID, sql: Self.basicQuery)
        }
    }

    private static let attachmentKindColumn = """
        (SELECT a.mime_type FROM message_attachment_join maj
           JOIN attachment a ON a.ROWID = maj.attachment_id
          WHERE maj.message_id = m.ROWID LIMIT 1)
        """

    private static var fullQuery: String {
        """
        SELECT m.ROWID, m.text, m.attributedBody, m.date, h.id, IFNULL(m.service, h.service),
               c.guid, c.display_name, c.style, m.cache_has_attachments, \(attachmentKindColumn)
          FROM message m
          LEFT JOIN handle h ON h.ROWID = m.handle_id
          LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
          LEFT JOIN chat c ON c.ROWID = cmj.chat_id
         WHERE m.ROWID > ?1 AND m.is_from_me = 0
           AND IFNULL(m.item_type, 0) = 0
           AND IFNULL(m.associated_message_type, 0) = 0
         ORDER BY m.ROWID ASC
         LIMIT 50
        """
    }

    private static var basicQuery: String {
        """
        SELECT m.ROWID, m.text, m.attributedBody, m.date, h.id, h.service,
               c.guid, c.display_name, c.style, 0, NULL
          FROM message m
          LEFT JOIN handle h ON h.ROWID = m.handle_id
          LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
          LEFT JOIN chat c ON c.ROWID = cmj.chat_id
         WHERE m.ROWID > ?1 AND m.is_from_me = 0
         ORDER BY m.ROWID ASC
         LIMIT 50
        """
    }

    private static func scalarInt(_ db: OpaquePointer, _ sql: String) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ReadError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw ReadError.queryFailed }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func query(_ db: OpaquePointer, after rowID: Int, sql: String) throws -> [MessagesDatabaseRow] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ReadError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(rowID))

        var rows: [MessagesDatabaseRow] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw ReadError.queryFailed }

            let id = Int(sqlite3_column_int64(stmt, 0))
            var text = string(stmt, 1) ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let blob = data(stmt, 2) {
                text = MessagesAttributedBodyDecoder.text(from: blob) ?? ""
            }
            // U+FFFC stands in for inline attachments.
            text = text.replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                let hasAttachment = sqlite3_column_int(stmt, 9) != 0 || string(stmt, 10) != nil
                guard hasAttachment else { continue }
                text = attachmentLabel(mimeType: string(stmt, 10))
            }

            let rawDate = sqlite3_column_int64(stmt, 3)
            rows.append(MessagesDatabaseRow(
                rowID: id,
                text: text,
                date: appleDate(rawDate),
                handle: string(stmt, 4) ?? "",
                service: string(stmt, 5) ?? "iMessage",
                chatGUID: string(stmt, 6),
                chatDisplayName: string(stmt, 7),
                // chat.style 43 = group chat, 45 = one-to-one.
                isGroupChat: sqlite3_column_int(stmt, 8) == 43
            ))
        }
        return rows
    }

    private static func attachmentLabel(mimeType: String?) -> String {
        let type = mimeType ?? ""
        if type.hasPrefix("image/") { return String(localized: "Photo") }
        if type.hasPrefix("video/") { return String(localized: "Video") }
        if type.hasPrefix("audio/") { return String(localized: "Audio message") }
        return String(localized: "Attachment")
    }

    /// chat.db dates are nanoseconds (seconds on very old macOS) since 2001-01-01.
    private static func appleDate(_ raw: Int64) -> Date? {
        guard raw > 0 else { return nil }
        let seconds = raw > 100_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func string(_ stmt: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, column) else { return nil }
        let value = String(cString: cString)
        return value.isEmpty ? nil : value
    }

    private static func data(_ stmt: OpaquePointer, _ column: Int32) -> Data? {
        guard sqlite3_column_type(stmt, column) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(stmt, column) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, column))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }
}

/// Pulls the plain text out of `message.attributedBody`, an NSAttributedString
/// archived as a typedstream (macOS 13+ often leaves `message.text` empty).
/// Scans the bytes instead of using `NSUnarchiver`, which raises uncatchable
/// Objective-C exceptions on data it doesn't like.
enum MessagesAttributedBodyDecoder {
    static func text(from blob: Data) -> String? {
        let bytes = [UInt8](blob)
        let marker = Array("NSString".utf8)
        guard let markerIndex = firstIndex(of: marker, in: bytes) else { return nil }

        // After the class name comes a few bytes of class info, then '+' (0x2B,
        // the C-string type tag), then the length and the UTF-8 bytes.
        var index = markerIndex + marker.count
        let searchEnd = min(bytes.count, index + 16)
        while index < searchEnd, bytes[index] != 0x2B { index += 1 }
        guard index < searchEnd else { return nil }
        index += 1

        guard index < bytes.count else { return nil }
        let lengthTag = bytes[index]
        index += 1
        let length: Int
        switch lengthTag {
        case 0x81: // 2-byte little-endian length follows
            guard index + 2 <= bytes.count else { return nil }
            length = Int(bytes[index]) | Int(bytes[index + 1]) << 8
            index += 2
        case 0x82: // 4-byte little-endian length follows
            guard index + 4 <= bytes.count else { return nil }
            length = Int(bytes[index]) | Int(bytes[index + 1]) << 8
                | Int(bytes[index + 2]) << 16 | Int(bytes[index + 3]) << 24
            index += 4
        default:
            length = Int(lengthTag)
        }

        guard length > 0, index + length <= bytes.count else { return nil }
        return String(bytes: bytes[index..<(index + length)], encoding: .utf8)
    }

    private static func firstIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= pattern.count else { return nil }
        for start in 0...(bytes.count - pattern.count) where bytes[start] == pattern[0] {
            if Array(bytes[start..<(start + pattern.count)]) == pattern { return start }
        }
        return nil
    }
}

/// Watches the Messages database files for writes with DispatchSource (no polling)
/// and calls `onChange` (debounced) on `queue`.
final class MessagesDatabaseWatcher {
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingWork: DispatchWorkItem?

    init(queue: DispatchQueue, onChange: @escaping () -> Void) {
        self.queue = queue
        self.onChange = onChange
    }

    deinit { stop() }

    /// Starts (or restarts) watching. Returns false if nothing could be watched.
    @discardableResult
    func start() -> Bool {
        stop()
        let dbURL = MessagesDatabaseReader.databaseURL
        let paths = [
            dbURL.path,
            dbURL.path + "-wal",
            dbURL.deletingLastPathComponent().path, // catches the WAL being recreated
        ]
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .delete, .rename],
                queue: queue
            )
            source.setEventHandler { [weak self, weak source] in
                guard let self, let source else { return }
                let event = source.data
                if event.contains(.delete) || event.contains(.rename) {
                    // The file was replaced: watch the new one.
                    self.queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.start()
                        self?.scheduleChange()
                    }
                    return
                }
                self.scheduleChange()
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
        return !sources.isEmpty
    }

    func stop() {
        pendingWork?.cancel()
        pendingWork = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func scheduleChange() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

/// Owns the reader and the watcher on one background queue and reports new
/// incoming messages. Only the last seen ROWID is stored (in Defaults).
final class MessagesDatabaseMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.wenujacodes.Noori.messages", qos: .utility)
    private let reader = MessagesDatabaseReader()
    private var watcher: MessagesDatabaseWatcher?
    private let lastSeenKey: Defaults.Key<Int>
    /// Messages older than this when found (e.g. an iCloud sync after wake) are skipped.
    private let maximumMessageAge: TimeInterval = 120
    private let onNewMessage: @Sendable (MessagesDatabaseRow) -> Void

    init(lastSeenKey: Defaults.Key<Int>, onNewMessage: @escaping @Sendable (MessagesDatabaseRow) -> Void) {
        self.lastSeenKey = lastSeenKey
        self.onNewMessage = onNewMessage
    }

    func checkAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [reader] in completion(reader.canRead()) }
    }

    /// Starts watching. Reports whether the database is readable and watched.
    func start(_ completion: @escaping @Sendable (_ readable: Bool, _ watching: Bool) -> Void) {
        queue.async { [self] in
            guard reader.canRead() else {
                completion(false, false)
                return
            }
            if let maxID = try? reader.maxRowID() {
                let lastSeen = Defaults[lastSeenKey]
                // First run, or the database was reset: start from the newest message.
                if lastSeen == 0 || maxID < lastSeen {
                    Defaults[lastSeenKey] = maxID
                }
            }
            if watcher == nil {
                watcher = MessagesDatabaseWatcher(queue: queue) { [weak self] in
                    self?.checkForNewMessages()
                }
            }
            completion(true, watcher?.start() ?? false)
        }
    }

    func stop() {
        queue.async { [self] in
            watcher?.stop()
            watcher = nil
        }
    }

    private func checkForNewMessages() {
        let lastSeen = Defaults[lastSeenKey]
        guard let rows = try? reader.incomingMessages(after: lastSeen) else { return }
        // Move past everything written so far, sent messages included.
        let newest = max(rows.last?.rowID ?? 0, (try? reader.maxRowID()) ?? 0)
        if newest > lastSeen {
            Defaults[lastSeenKey] = newest
        }
        let now = Date()
        if let latest = rows.last(where: { row in
            guard let date = row.date else { return true }
            return now.timeIntervalSince(date) < maximumMessageAge
        }) {
            onNewMessage(latest)
        }
    }
}
