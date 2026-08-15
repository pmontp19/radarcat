import Foundation

/// The page could not be read as an SMP payload at all: no
/// `Meteocat.avisosSMP(` call, or no top-level `avisos` key in it. A page
/// with no warning open is not this error (see `MeteocatAvisosParser`).
struct MeteocatParseError: Error, CustomStringConvertible {
    let description: String
}

/// Extraction of the inline SMP payload `meteo.cat` embeds in its own pages.
///
/// Swift port of `ha-avisoscat`'s `parser.py`, scoped to what v1 needs: only
/// the top-level `avisos` array is read (`episodisPreavisos` is out of scope,
/// docs/plans/avisos-meteocat.md). The core trick is unchanged and just as
/// necessary here: **no greedy regular expression**. The payload's
/// `comentari` text can itself contain `[`, `]` and `{`
/// ("ratxes de vent [rafegues]" is real Meteocat prose), so the end of the
/// `avisos` array is found with a bracket counter that knows when it is
/// inside a quoted string, never by matching the first `]` a regex happens to
/// see.
///
/// Scanned as UTF-8 bytes rather than `Character`s: none of the ASCII
/// delimiters this parser looks for (`[`, `]`, `{`, `}`, `(`, `)`, quotes,
/// backslash, `:`) can appear as a continuation byte of a multi-byte UTF-8
/// sequence, so byte-level scanning of Catalan text (which this payload is
/// full of) never misreads an accented character as a delimiter.
enum MeteocatAvisosParser {
    private static let callMarker = Array("Meteocat.avisosSMP(".utf8)
    private static let openers: Set<UInt8> = Set("[{(".utf8)
    private static let closers: Set<UInt8> = Set("]})".utf8)
    private static let quoteBytes: Set<UInt8> = Set("\"'`".utf8)
    private static let backslash = UInt8(ascii: "\\")
    private static let colon = UInt8(ascii: ":")
    private static let openBracket = UInt8(ascii: "[")

    // Depth of a key sitting directly inside the call's argument object,
    // counted from the `(` of the call: the `(` itself opens depth 1 and the
    // `{` of the argument object opens depth 2. Anything deeper belongs to a
    // nested object such as `opcions`.
    private static let argumentDepth = 2

    /// Extract the richest `avisos` array out of every
    /// `Meteocat.avisosSMP(...)` call in the page, decoded as JSON.
    ///
    /// A page can render the call more than once (the homepage renders a
    /// 1-day visor and a 3-day widget), so every candidate is decoded and the
    /// one carrying the most entries wins, ties going to the first
    /// (`docs/captures/smp-page-choice-2026-08-06.md` in `ha-avisoscat`).
    static func extractAvisos(fromHTML html: String) throws -> [Any] {
        let bytes = Array(html.utf8)
        guard findRange(of: callMarker, in: bytes, from: 0) != nil else {
            throw MeteocatParseError(
                description: "No Meteocat.avisosSMP( call in the page: the meteo.cat markup changed"
            )
        }

        var candidates: [[Any]] = []
        var foundKey = false
        for (start, end) in callSpans(bytes) {
            let (arrays, found) = decodeAvisosArrays(bytes, start: start, end: end)
            candidates.append(contentsOf: arrays)
            foundKey = foundKey || found
        }

        guard foundKey else {
            throw MeteocatParseError(
                description: "The Meteocat.avisosSMP( call carries no top-level avisos key: "
                    + "the meteo.cat payload shape changed"
            )
        }
        guard !candidates.isEmpty else {
            throw MeteocatParseError(
                description: "The avisos key of the Meteocat.avisosSMP( call could not be decoded as JSON"
            )
        }
        return pickRichest(candidates)
    }

    /// Decode every top-level `avisos` array found between `start` and `end`
    /// (one call's argument span), plus whether the key was seen at all -
    /// those are two different failures: an absent key means the markup
    /// changed, a present-but-undecodable one just means this one candidate
    /// is unusable while another copy of the call might still be readable.
    private static func decodeAvisosArrays(_ bytes: [UInt8], start: Int, end: Int) -> ([[Any]], Bool) {
        var arrays: [[Any]] = []
        var found = false
        // One resumable walk per span: occurrences of "avisos" arrive in
        // increasing order, so advancing the same walk answers the depth of
        // all of them in a single pass instead of rescanning from the start
        // every time.
        let walk = BracketWalk(bytes: bytes, start: start)
        var searchPos = start
        while let occurrence = findAvisosOccurrence(bytes, from: searchPos, to: end) {
            searchPos = occurrence + 6   // "avisos".utf8.count, guarantees forward progress
            guard let valueStart = colonValueStart(bytes, afterKeyEnd: occurrence + 6, to: end) else {
                continue
            }
            walk.advance(to: occurrence)
            guard !walk.inString, walk.depth == argumentDepth else {
                // Prose that reads like a key, or a nested `avisos` key (every
                // episode of the payload carries one under its own `avisos`
                // sub-key at a deeper level) - not the one we want.
                continue
            }
            found = true
            guard valueStart < bytes.count, bytes[valueStart] == openBracket else { continue }
            guard let closesAt = scanBalanced(bytes, start: valueStart) else { continue }
            guard let array = try? JSONSerialization.jsonObject(with: Data(bytes[valueStart..<closesAt])) as? [Any]
            else { continue }
            arrays.append(array)
        }
        return (arrays, found)
    }

    /// Whether the byte at `index` could be part of a JavaScript identifier -
    /// what stops "avisos" from matching the tail of "episodisPreavisos",
    /// which does contain that substring.
    private static func isWordByte(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
            || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "$")
    }

    /// Index of the next `avisos` occurrence not preceded by a word
    /// character, searching `[from, to)`. Does not itself check that it is
    /// followed by a colon (see `colonValueStart`) or sitting at the right
    /// depth - the caller decides that.
    private static func findAvisosOccurrence(_ bytes: [UInt8], from: Int, to: Int) -> Int? {
        let needle = Array("avisos".utf8)
        guard needle.count <= to else { return nil }
        var i = max(from, 0)
        while i <= to - needle.count {
            if bytes[i] == needle[0], Array(bytes[i..<(i + needle.count)]) == needle {
                let before = i - 1
                if before < 0 || !isWordByte(bytes[before]) {
                    return i
                }
            }
            i += 1
        }
        return nil
    }

    /// Index right after `key: ` (optional closing quote and whitespace
    /// around the colon accepted), or `nil` if what follows the candidate key
    /// is not actually `: `, i.e. this was not a key occurrence at all.
    private static func colonValueStart(_ bytes: [UInt8], afterKeyEnd: Int, to: Int) -> Int? {
        var j = afterKeyEnd
        if j < to, quoteBytes.contains(bytes[j]) { j += 1 }
        while j < to, isJSWhitespace(bytes[j]) { j += 1 }
        guard j < to, bytes[j] == colon else { return nil }
        j += 1
        while j < to, isJSWhitespace(bytes[j]) { j += 1 }
        return j
    }

    private static func isJSWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
            || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }

    /// Count the entries an array carries, seeing through one level of
    /// nesting: the episodes arrive wrapped one level deeper, one sub-array
    /// per forecast day (`[[day1…], [day2…], [day3…]]`), so `[[]]` is as
    /// empty as `[]` and a 3-day copy of the payload counts as bigger than a
    /// 1-day one.
    private static func contentSize(_ value: [Any]) -> Int {
        value.reduce(0) { total, entry in
            if let list = entry as? [Any] { return total + list.count }
            if entry is NSNull { return total }
            return total + 1
        }
    }

    /// Pick the candidate carrying the most entries; ties go to the first -
    /// matches Python's `max(key=...)` tie-breaking, unlike Swift's own
    /// `max(by:)` which keeps the last.
    private static func pickRichest(_ candidates: [[Any]]) -> [Any] {
        var richest: [Any] = []
        var richestSize = -1
        for candidate in candidates {
            let size = contentSize(candidate)
            if size > richestSize {
                richestSize = size
                richest = candidate
            }
        }
        return richestSize > 0 ? richest : []
    }

    // MARK: - Bracket walking

    /// Locate the argument list of every `Meteocat.avisosSMP(` call in the
    /// page, as byte-offset spans `(openParenIndex, closeIndex)`. Every call
    /// is returned, not just the first (see the type's doc comment).
    private static func callSpans(_ bytes: [UInt8]) -> [(Int, Int)] {
        var spans: [(Int, Int)] = []
        var searchFrom = 0
        while let found = findRange(of: callMarker, in: bytes, from: searchFrom) {
            let openParen = found + callMarker.count - 1
            searchFrom = found + callMarker.count
            if let end = scanBalanced(bytes, start: openParen) {
                spans.append((openParen, end))
            } else if findRange(of: callMarker, in: bytes, from: searchFrom) != nil {
                // Unbalanced with another occurrence still to come: prose
                // naming the call rather than a real one. Skip it so it does
                // not become the depth origin for the rest of the page.
                continue
            } else {
                // A truncated final call is still scanned to the end of the
                // page: the keys we want come early in the argument list, so
                // a cut-off tail often still yields them.
                spans.append((openParen, bytes.count))
            }
        }
        return spans
    }

    /// Index just past the bracket group opening at `start` (which must be an
    /// opener itself), or `nil` if it never closes before the end of the
    /// text.
    private static func scanBalanced(_ bytes: [UInt8], start: Int) -> Int? {
        let walk = BracketWalk(bytes: bytes, start: start)
        return walk.advance(to: bytes.count, stopWhenClosed: true) ? walk.position : nil
    }

    private static func findRange(of needle: [UInt8], in bytes: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, from >= 0, needle.count <= bytes.count else { return nil }
        var i = from
        while i <= bytes.count - needle.count {
            if bytes[i] == needle[0], Array(bytes[i..<(i + needle.count)]) == needle {
                return i
            }
            i += 1
        }
        return nil
    }

    /// A resumable left-to-right walk that counts brackets outside quoted
    /// strings. Characters inside a string are skipped - the whole point: the
    /// `]` in "ratxes de vent [rafegues]" must not close the array. Both
    /// JavaScript quote styles are honoured and a backslash escapes the next
    /// character.
    private final class BracketWalk {
        private let bytes: [UInt8]
        private var quote: UInt8?
        private var escaped = false
        private(set) var depth = 0
        private(set) var position: Int

        var inString: Bool { quote != nil }

        init(bytes: [UInt8], start: Int) {
            self.bytes = bytes
            self.position = start
        }

        /// Walk up to (not including) `end`, keeping the depth reached; may
        /// only move forward. With `stopWhenClosed`, stops just past the byte
        /// that brings the depth back to 0 and returns `true`; `false` then
        /// means the group never closed before `end`.
        @discardableResult
        func advance(to end: Int, stopWhenClosed: Bool = false) -> Bool {
            var closed = false
            while position < end {
                let byte = bytes[position]
                position += 1
                if let currentQuote = quote {
                    if escaped {
                        escaped = false
                    } else if byte == MeteocatAvisosParser.backslash {
                        escaped = true
                    } else if byte == currentQuote {
                        quote = nil
                    }
                    continue
                }
                if MeteocatAvisosParser.quoteBytes.contains(byte) {
                    quote = byte
                } else if MeteocatAvisosParser.openers.contains(byte) {
                    depth += 1
                } else if MeteocatAvisosParser.closers.contains(byte) {
                    depth -= 1
                    if stopWhenClosed, depth == 0 {
                        closed = true
                        break
                    }
                }
            }
            return closed
        }
    }
}
