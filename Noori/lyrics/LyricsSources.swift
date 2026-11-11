/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * The LRCLIB, NetEase Cloud Music and QQ Music requests follow the ones in
 * Lyrimuse's lyrics engine (https://github.com/Yudaotor/lyrimuse), GPL-3.0.
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// The song to find lyrics for.
struct LyricsQuery: Hashable {
    let title: String
    let artist: String
    let album: String
    /// Seconds; 0 when unknown.
    let duration: Double
}

/// Lyrics found for a song.
struct LyricsResult {
    let lines: [LyricsLine]
    let source: String

    var isWordTimed: Bool { lines.contains { $0.words != nil } }
}

// MARK: - Matching

enum LyricsMatching {
    private static let bracketRegex = try! NSRegularExpression(pattern: #"[\(\[（【「『][^\)\]）】」』]*[\)\]）】」』]"#)
    private static let featRegex = try! NSRegularExpression(pattern: #"\s+(feat\.?|ft\.?|featuring|with)\s+.*$"#, options: [.caseInsensitive])
    private static let versionSuffixRegex = try! NSRegularExpression(pattern: #"\s+-\s+.*(remaster|version|edit|mix|live|mono|stereo|from|radio).*$"#, options: [.caseInsensitive])

    /// Lowercased, accents and width folded, traditional Chinese turned simplified,
    /// letters and digits only.
    static func normalize(_ value: String) -> String {
        var s = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        s = s.applyingTransform(StringTransform(rawValue: "Traditional-Simplified"), reverse: false) ?? s
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The title without "(feat. …)", "[Remastered]", " - 2011 Remaster" and similar.
    static func baseTitle(_ title: String) -> String {
        var s = title
        for regex in [bracketRegex, featRegex, versionSuffixRegex] {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? title : s
    }

    /// The artist without "(Romanized Name)" and with only the first credited artist.
    static func primaryArtist(_ artist: String) -> String {
        let withoutBrackets = bracketRegex.stringByReplacingMatches(in: artist, range: NSRange(location: 0, length: (artist as NSString).length), withTemplate: "")
        return artistParts(withoutBrackets).first ?? artist
    }

    static func artistParts(_ artist: String) -> [String] {
        artist
            .replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring|with|x|and|&|vs\.?)\s+"#, with: "|", options: [.regularExpression, .caseInsensitive])
            .split(whereSeparator: { ",，、/&;|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func titleMatches(_ candidate: String, _ query: String) -> Bool {
        let a = normalize(baseTitle(candidate)), b = normalize(baseTitle(query))
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        // "Song" vs "Song (Remix)" style leftovers: allow containment when it's most of the title.
        let shorter = min(a.count, b.count), longer = max(a.count, b.count)
        return shorter >= 4 && Double(shorter) / Double(longer) >= 0.7 && (a.contains(b) || b.contains(a))
    }

    static func artistMatches(_ candidates: [String], _ query: String) -> Bool {
        let queryParts = artistParts(query).map(normalize).filter { $0.count >= 2 }
        let candidateParts = candidates.flatMap(artistParts).map(normalize).filter { $0.count >= 2 }
        guard !queryParts.isEmpty, !candidateParts.isEmpty else { return false }
        return candidateParts.contains { c in queryParts.contains { q in c == q || c.contains(q) || q.contains(c) } }
    }

    /// Within 4 seconds, or true when either length is unknown.
    static func durationMatches(_ candidate: Double, _ query: Double) -> Bool {
        guard candidate > 0, query > 0 else { return true }
        return abs(candidate - query) <= 4
    }

    /// The candidate whose title, artist and length match: an exact title wins
    /// over "(feat. …)" and other variants, then the closest length (another
    /// version of the song, with a longer intro say, is timed seconds off), then
    /// the source's own order, which puts official releases first.
    static func best<T>(_ items: [T], query: LyricsQuery, title: (T) -> String, artists: (T) -> [String], duration: (T) -> Double) -> T? {
        let matches = items.filter {
            titleMatches(title($0), query.title) && artistMatches(artists($0), query.artist) && durationMatches(duration($0), query.duration)
        }
        let exactTitle = normalize(query.title)
        func lengthGap(_ item: T) -> Double {
            let d = duration(item)
            guard d > 0, query.duration > 0 else { return 2 }  // unknown: between close and far
            return abs(d - query.duration)
        }
        // `min` keeps the first of equals, so the source's order breaks ties.
        return matches.enumerated().min { a, b in
            let aExact = normalize(title(a.element)) == exactTitle
            let bExact = normalize(title(b.element)) == exactTitle
            if aExact != bExact { return aExact }
            let gapA = lengthGap(a.element), gapB = lengthGap(b.element)
            if abs(gapA - gapB) >= 0.5 { return gapA < gapB }
            return a.offset < b.offset
        }?.element
    }
}

// MARK: - Sources

enum LyricsSources {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"

    private static func get(_ url: URL, headers: [String: String]) async -> Data? {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }

    private static func url(_ base: String, _ items: [String: String]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    /// The outcome of one source.
    enum Outcome {
        case lyrics(LyricsResult)
        /// The source knows the song and says it has no vocals.
        case instrumental
        case none
    }

    // MARK: LRCLIB

    private struct LRCLIBTrack: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
    }

    private static var lrclibUserAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Noori/\(version) (https://github.com/wenujacodes/Noori)"
    }

    /// LRCLIB: free and open, line timing.
    static func lrclib(_ query: LyricsQuery) async -> Outcome {
        let headers = ["User-Agent": lrclibUserAgent]
        // Exact lookup first (needs the length), then a search.
        if query.duration > 0, let exactURL = url("https://lrclib.net/api/get", [
            "track_name": query.title,
            "artist_name": query.artist,
            "album_name": query.album,
            "duration": String(Int(query.duration.rounded())),
        ]), let data = await get(exactURL, headers: headers),
           let track = try? JSONDecoder().decode(LRCLIBTrack.self, from: data) {
            if track.instrumental == true { return .instrumental }
            if let synced = track.syncedLyrics, !synced.isEmpty {
                return .lyrics(LyricsResult(lines: LyricsParsing.parseLRC(synced), source: "LRCLIB"))
            }
        }

        guard let searchURL = url("https://lrclib.net/api/search", [
            "track_name": LyricsMatching.baseTitle(query.title),
            "artist_name": LyricsMatching.primaryArtist(query.artist),
        ]), let data = await get(searchURL, headers: headers),
              let tracks = try? JSONDecoder().decode([LRCLIBTrack].self, from: data) else { return .none }

        let synced = tracks.filter { !($0.syncedLyrics ?? "").isEmpty }
        if let match = LyricsMatching.best(synced, query: query, title: { $0.trackName ?? "" }, artists: { [$0.artistName ?? ""] }, duration: { $0.duration ?? 0 }),
           let text = match.syncedLyrics {
            return .lyrics(LyricsResult(lines: LyricsParsing.parseLRC(text), source: "LRCLIB"))
        }
        return .none
    }

    // MARK: NetEase Cloud Music

    private struct NetEaseSearch: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            struct Artist: Decodable { let name: String? }
            let id: Int64
            let name: String?
            let artists: [Artist]?
            let duration: Double?
        }
        let code: Int?
        let result: Result?
    }

    private struct NetEaseLyric: Decodable {
        struct Body: Decodable { let lyric: String? }
        let lrc: Body?
        let yrc: Body?
        let tlyric: Body?
        let romalrc: Body?
        let pureMusic: Bool?
    }

    private static let netEaseHeaders = ["Referer": "https://music.163.com/", "User-Agent": "Mozilla/5.0"]

    /// NetEase Cloud Music: word timing for many songs. Returns the word-timed and the
    /// line-timed lyrics separately.
    static func netEase(_ query: LyricsQuery) async -> (word: Outcome, line: Outcome) {
        let title = LyricsMatching.baseTitle(query.title)
        let artist = LyricsMatching.primaryArtist(query.artist)
        var song: NetEaseSearch.Song?
        searching: for terms in ["\(artist) \(title)", "\(title) \(artist)"] {
            for endpoint in ["https://music.163.com/api/search/get", "https://music.163.com/api/search/get/web"] {
                guard let searchURL = url(endpoint, ["type": "1", "limit": "20", "s": terms]),
                      let data = await get(searchURL, headers: netEaseHeaders),
                      let response = try? JSONDecoder().decode(NetEaseSearch.self, from: data),
                      response.code == nil || response.code == 200 else { continue }
                song = LyricsMatching.best(
                    response.result?.songs ?? [],
                    query: query,
                    title: { $0.name ?? "" },
                    artists: { $0.artists?.compactMap(\.name) ?? [] },
                    duration: { ($0.duration ?? 0) / 1000 }
                )
                if song != nil { break searching }
                break // The endpoint answered; try the other word order instead.
            }
        }
        guard let song,
              let lyricURL = url("https://music.163.com/api/song/lyric/v1", ["id": String(song.id), "lv": "-1", "tv": "-1", "rv": "-1", "yv": "-1"]),
              let data = await get(lyricURL, headers: netEaseHeaders),
              let lyric = try? JSONDecoder().decode(NetEaseLyric.self, from: data) else { return (.none, .none) }
        if lyric.pureMusic == true { return (.instrumental, .instrumental) }

        func unescape(_ text: String?) -> String { (text ?? "").replacingOccurrences(of: "\\'", with: "'") }
        // NetEase also has a Chinese translation and, for some songs, a romanization.
        let translations = LyricsParsing.parseLRC(unescape(lyric.tlyric?.lyric))
        let romanizations = LyricsParsing.parseLRC(unescape(lyric.romalrc?.lyric))
        func withExtras(_ lines: [LyricsLine]) -> [LyricsLine] {
            let translated = LyricsParsing.attach(translations, to: lines, as: \.translation)
            return LyricsParsing.attach(romanizations, to: translated, as: \.pronunciation)
        }
        let wordLines = withExtras(LyricsParsing.parseYRC(unescape(lyric.yrc?.lyric)))
        let lineLines = withExtras(LyricsParsing.parseLRC(unescape(lyric.lrc?.lyric)))
        let word: Outcome = wordLines.isEmpty ? .none : .lyrics(LyricsResult(lines: wordLines, source: "NetEase"))
        let line: Outcome = lineLines.isEmpty ? .none : .lyrics(LyricsResult(lines: lineLines, source: "NetEase"))
        return (word, line)
    }

    // MARK: QQ Music

    private struct QQSearch: Decodable {
        struct DataBody: Decodable {
            struct SongBody: Decodable { let list: [Song]? }
            let song: SongBody?
        }
        struct Song: Decodable {
            struct Singer: Decodable { let name: String? }
            let mid: String?
            let title: String?
            let interval: Double?
            let singer: [Singer]?
        }
        let code: Int?
        let data: DataBody?
    }

    private struct QQLyric: Decodable {
        let lyric: String?
        let code: Int?
        let retcode: Int?
    }

    private static let qqHeaders = ["Referer": "https://y.qq.com/", "User-Agent": browserUserAgent]

    /// QQ Music: line timing, strong for Chinese songs.
    static func qq(_ query: LyricsQuery) async -> Outcome {
        let terms = "\(LyricsMatching.primaryArtist(query.artist)) \(LyricsMatching.baseTitle(query.title))"
        var song: QQSearch.Song?
        for host in ["c.y.qq.com", "shc.y.qq.com"] {
            guard let searchURL = url("https://\(host)/soso/fcgi-bin/client_search_cp", [
                "format": "json", "new_json": "1", "t": "0", "aggr": "1", "cr": "1", "p": "1", "n": "20", "w": terms,
            ]), let data = await get(searchURL, headers: qqHeaders),
                  let response = try? JSONDecoder().decode(QQSearch.self, from: data),
                  response.code == 0 else { continue }
            song = LyricsMatching.best(
                response.data?.song?.list ?? [],
                query: query,
                title: { $0.title ?? "" },
                artists: { $0.singer?.compactMap(\.name) ?? [] },
                duration: { $0.interval ?? 0 }
            )
            break
        }
        guard let mid = song?.mid,
              let lyricURL = url("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg", ["format": "json", "nobase64": "1", "g_tk": "5381", "songmid": mid]),
              let data = await get(lyricURL, headers: qqHeaders),
              var body = String(data: data, encoding: .utf8) else { return .none }
        // Sometimes wrapped as MusicJsonCallback({...}).
        if let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}"), open < close {
            body = String(body[open...close])
        }
        guard let lyric = try? JSONDecoder().decode(QQLyric.self, from: Data(body.utf8)),
              let text = lyric.lyric, !text.isEmpty else { return .none }
        let lines = LyricsParsing.parseLRC(LyricsParsing.decodeHTMLEntities(text))
        return lines.isEmpty ? .none : .lyrics(LyricsResult(lines: lines, source: "QQ Music"))
    }
}
