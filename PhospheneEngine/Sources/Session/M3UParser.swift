// M3UParser — Defensive `.m3u` / `.m3u8` playlist parser (LF.5 / D-132).
//
// Reads a playlist file and resolves each non-comment line to a readable
// audio file URL. Tolerates the variants the parser will see in the wild:
//
//   - UTF-8 BOM at the head of the file (Notepad / TextEdit Western locales).
//   - Either Unix (LF) or Windows (CRLF) line endings, including mixed within
//     one file.
//   - `#EXTM3U` header + per-entry `#EXTINF:duration,Artist — Title` lines
//     (treated as comments — LF.5 does not surface duration / artist hints;
//     ID3 extraction at Task 4 covers that).
//   - Absolute paths (`/Users/foo/bar.m4a`), `file://` URLs, and relative
//     paths resolved against the `.m3u` file's parent directory.
//
// Failure model: every parse failure surfaces as `M3UParser.ParseError`.
// Unreadable individual entries are silently skipped (the caller logs
// `STEM_QUEUE_SKIP` per skip via the returned `skippedLines` list); only
// total-failure conditions (unreadable file, malformed UTF-8, zero
// resolved entries) throw.

import Foundation

// MARK: - M3UParser

/// Stateless `.m3u` / `.m3u8` parser.
///
/// Returns the resolved file URLs alongside the lines that failed to
/// resolve (for caller logging). Callers above this layer (typically
/// `LocalFileMenuCommands`) further validate by extension and dispatch to
/// `SessionManager.startLocalFiles(at:origin:)`.
public enum M3UParser {

    // MARK: - Errors

    /// Total-failure conditions. Individual unreadable entries do NOT throw;
    /// they appear in `M3UParseResult.skippedLines`.
    public enum ParseError: Error, Sendable, Equatable {
        /// The `.m3u` file itself could not be opened (missing file, permission
        /// error, broken symlink).
        case fileUnreadable(String)
        /// The file's bytes could not be decoded as UTF-8 after BOM stripping.
        /// Most real-world `.m3u` files are UTF-8; UTF-16 / Latin-1 fall here.
        case malformedUTF8
        /// The parser walked the file but every non-comment line either failed
        /// to resolve or pointed at an unreadable target. The `.m3u` is
        /// effectively empty from Phosphene's perspective.
        case noEntriesResolved
    }

    // MARK: - Result

    public struct ParseResult: Sendable {
        /// Ordered list of resolved + readable audio file URLs.
        public let urls: [URL]
        /// Lines that were non-empty and non-comment but failed to resolve to
        /// a readable file. Callers log `STEM_QUEUE_SKIP` per line; the parser
        /// itself stays side-effect-free.
        public let skippedLines: [String]
    }

    // MARK: - API

    /// Parse the `.m3u` / `.m3u8` file at `fileURL`. Relative paths inside
    /// the file are resolved against the file's parent directory.
    ///
    /// - Throws: `ParseError` on total failure (file unreadable, malformed
    ///   UTF-8, zero resolved entries).
    public static func parse(at fileURL: URL) throws -> ParseResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw ParseError.fileUnreadable(error.localizedDescription)
        }
        let baseDir = fileURL.deletingLastPathComponent()
        return try parse(data: data, relativeTo: baseDir)
    }

    /// Parse raw `.m3u` bytes against an explicit base directory. Used by
    /// `parse(at:)` and by tests that operate on inline UTF-8 strings.
    ///
    /// - Throws: `ParseError.malformedUTF8` on decode failure;
    ///   `ParseError.noEntriesResolved` when every non-comment line failed
    ///   to resolve to a readable file.
    public static func parse(data: Data, relativeTo baseDir: URL) throws -> ParseResult {
        let stripped = stripBOM(data: data)
        guard let text = String(data: stripped, encoding: .utf8) else {
            throw ParseError.malformedUTF8
        }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var urls: [URL] = []
        var skipped: [String] = []

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }                          // EXTM3U / EXTINF / comment

            guard let resolved = resolveURL(line: line, baseDir: baseDir) else {
                skipped.append(line)
                continue
            }
            if FileManager.default.isReadableFile(atPath: resolved.path) {
                urls.append(resolved)
            } else {
                skipped.append(line)
            }
        }

        guard !urls.isEmpty else {
            throw ParseError.noEntriesResolved
        }
        return ParseResult(urls: urls, skippedLines: skipped)
    }

    // MARK: - Helpers

    /// Strip the UTF-8 BOM (`EF BB BF`) if present at the head of `data`.
    /// UTF-16 BOM variants are detected and the data is returned unchanged
    /// so the UTF-8 decode at the call site throws `malformedUTF8` instead
    /// of silently producing garbled output.
    private static func stripBOM(data: Data) -> Data {
        guard data.count >= 3 else { return data }
        let bytes = [data[data.startIndex], data[data.startIndex + 1], data[data.startIndex + 2]]
        if bytes == [0xEF, 0xBB, 0xBF] {                                  // UTF-8 BOM
            return data.suffix(from: data.startIndex + 3)
        }
        return data
    }

    /// Resolve a single playlist entry to a `URL`, handling `file://` form,
    /// absolute filesystem paths, and relative paths. Returns `nil` only
    /// when the input is structurally unresolvable (e.g. empty after trim);
    /// readability checks happen at the call site.
    private static func resolveURL(line: String, baseDir: URL) -> URL? {
        if line.hasPrefix("file://") {
            return URL(string: line)
        }
        if line.hasPrefix("/") {
            return URL(fileURLWithPath: line)
        }
        return URL(fileURLWithPath: line, relativeTo: baseDir)
            .standardizedFileURL
    }
}
