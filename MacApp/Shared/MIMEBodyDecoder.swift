import Foundation
import CoreFoundation

struct DecodedMailBody {
    let text: String
    let characterCount: Int
    let truncated: Bool
}

enum MIMEBodyError: String, Error {
    case oversizedMessage, malformedHeaders, malformedMultipart, malformedEncoding
    case unsupportedCharset, unsupportedMultipart, nestingLimit, partLimit, oversizedText, malformedHTML
}

/// A bounded text extractor for on-device mail classification.
/// It never opens links, loads images, examines attachments, or writes message data.
enum MIMEBodyDecoder {
    static func decode(_ data: Data) throws -> DecodedMailBody {
        guard data.count <= 2 * 1_024 * 1_024 else { throw MIMEBodyError.oversizedMessage }
        // A byte-preserving intermediate representation keeps non-UTF-8 parts intact.
        let source = String(String.UnicodeScalarView(data.map { UnicodeScalar($0) }))
            .replacingOccurrences(of: "\r\n", with: "\n")
        var reader = Reader()
        let text = try reader.entity(source, depth: 0).text.trimmingCharacters(in: .whitespacesAndNewlines)
        return DecodedMailBody(text: String(text.prefix(6_000)), characterCount: text.count, truncated: text.count > 6_000)
    }

    private struct Part {
        var text = ""
        var plain = false
    }

    private struct Reader {
        var partCount = 0
        var decodedBytes = 0

        mutating func entity(_ source: String, depth: Int) throws -> Part {
            guard depth < 8 else { throw MIMEBodyError.nestingLimit }
            partCount += 1
            guard partCount <= 128 else { throw MIMEBodyError.partLimit }
            let (headers, body) = try splitEntity(source)
            let type = try parameterized(headers["content-type"] ?? "text/plain")
            let disposition = try parameterized(headers["content-disposition"] ?? "inline")
            if disposition.name == "attachment" || disposition.parameters.keys.contains(where: { $0.hasPrefix("filename") }) || type.parameters.keys.contains(where: { $0.hasPrefix("name") }) {
                return Part()
            }
            if type.name.hasPrefix("multipart/") {
                guard ["multipart/alternative", "multipart/mixed", "multipart/related", "multipart/signed"].contains(type.name) else {
                    throw MIMEBodyError.unsupportedMultipart
                }
                guard let boundary = type.parameters["boundary"], !boundary.isEmpty, boundary.count <= 70,
                      !boundary.contains("\n"), !boundary.contains("\r") else { throw MIMEBodyError.malformedMultipart }
                let children = try multipart(body, boundary: boundary)
                if type.name == "multipart/related" {
                    // Related parts are resources for one root document, not extra body text.
                    let root: String
                    if let start = type.parameters["start"] {
                        guard let match = try children.first(where: { try splitEntity($0).0["content-id"] == start }) else {
                            throw MIMEBodyError.malformedMultipart
                        }
                        root = match
                    } else { root = children[0] }
                    return try entity(root, depth: depth + 1)
                }
                if type.name == "multipart/signed" { return try entity(children[0], depth: depth + 1) }
                var parts: [Part] = []
                for child in children { parts.append(try entity(child, depth: depth + 1)) }
                if type.name == "multipart/alternative" {
                    return parts.first(where: { $0.plain && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        ?? parts.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? Part()
                }
                return Part(text: parts.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n"))
            }
            // Embedded messages, images, calendar data and all other attachments stay out.
            guard type.name == "text/plain" || type.name == "text/html" else { return Part() }
            let bytes = try transferDecoded(body, encoding: headers["content-transfer-encoding"] ?? "7bit")
            decodedBytes += bytes.count
            guard decodedBytes <= 256 * 1_024 else { throw MIMEBodyError.oversizedText }
            let text = try characters(bytes, charset: type.parameters["charset"])
            return Part(text: type.name == "text/html" ? try htmlText(text) : text, plain: type.name == "text/plain")
        }
    }

    private static func splitEntity(_ source: String) throws -> ([String: String], String) {
        if source.hasPrefix("\n") { return ([:], String(source.dropFirst())) }
        guard let separator = source.range(of: "\n\n"), source[..<separator.lowerBound].utf8.count <= 64 * 1_024 else {
            throw MIMEBodyError.malformedHeaders
        }
        var headers: [String: String] = [:]
        var key: String?
        for line in source[..<separator.lowerBound].components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard let key else { throw MIMEBodyError.malformedHeaders }
                headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { throw MIMEBodyError.malformedHeaders }
            let name = String(line[..<colon]).lowercased()
            guard !name.isEmpty, name.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
                throw MIMEBodyError.malformedHeaders
            }
            if headers[name] != nil && ["content-type", "content-transfer-encoding", "content-disposition", "content-id"].contains(name) {
                throw MIMEBodyError.malformedHeaders
            }
            key = name
            headers[name] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return (headers, String(source[separator.upperBound...]))
    }

    private static func parameterized(_ value: String) throws -> (name: String, parameters: [String: String]) {
        var segments: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        for char in value {
            if escaped { current.append(char); escaped = false; continue }
            if quoted && char == "\\" { escaped = true; continue }
            if char == "\"" { quoted.toggle(); continue }
            if char == ";" && !quoted { segments.append(current); current = "" }
            else { current.append(char) }
        }
        guard !quoted, !escaped else { throw MIMEBodyError.malformedHeaders }
        segments.append(current)
        var parameters: [String: String] = [:]
        for segment in segments.dropFirst() where !segment.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let equals = segment.firstIndex(of: "=") else { throw MIMEBodyError.malformedHeaders }
            let key = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard parameters[key] == nil else { throw MIMEBodyError.malformedHeaders }
            parameters[key] = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        return (segments[0].trimmingCharacters(in: .whitespaces).lowercased(), parameters)
    }

    private static func multipart(_ body: String, boundary: String) throws -> [String] {
        let delimiter = "--" + boundary
        var parts: [String] = []
        var lines: [String]? = nil
        var closed = false
        for line in body.components(separatedBy: "\n") {
            let marker = line.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
            if marker == delimiter || marker == delimiter + "--" {
                if let lines { parts.append(lines.joined(separator: "\n")) }
                if marker == delimiter + "--" { closed = true; break }
                lines = []
                guard parts.count < 128 else { throw MIMEBodyError.partLimit }
            } else if lines != nil { lines!.append(line) }
        }
        guard closed, !parts.isEmpty else { throw MIMEBodyError.malformedMultipart }
        return parts
    }

    private static func transferDecoded(_ body: String, encoding: String) throws -> Data {
        let bytes = body.unicodeScalars.map { UInt8($0.value) }
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "7bit", "8bit", "binary": return Data(bytes)
        case "base64":
            let compact = Data(bytes.filter { ![9, 10, 13, 32].contains($0) })
            guard let data = Data(base64Encoded: compact) else { throw MIMEBodyError.malformedEncoding }
            return data
        case "quoted-printable":
            var result = Data()
            var i = 0
            while i < bytes.count {
                if bytes[i] != 61 { result.append(bytes[i]); i += 1; continue }
                if i + 1 < bytes.count, bytes[i + 1] == 10 { i += 2; continue }
                guard i + 2 < bytes.count,
                      let byte = UInt8(String(bytes: bytes[(i + 1)...(i + 2)], encoding: .ascii) ?? "", radix: 16) else {
                    throw MIMEBodyError.malformedEncoding
                }
                result.append(byte)
                i += 3
            }
            return result
        default: throw MIMEBodyError.malformedEncoding
        }
    }

    private static func characters(_ data: Data, charset: String?) throws -> String {
        if charset == nil {
            guard let text = String(data: data, encoding: .utf8) else { throw MIMEBodyError.unsupportedCharset }
            return text
        }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset! as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId,
              let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))) else {
            throw MIMEBodyError.unsupportedCharset
        }
        return text
    }

    private static func htmlText(_ html: String) throws -> String {
        // Do not invoke an HTML renderer: it could load remote resources from mail.
        var source = html.replacingOccurrences(of: "(?is)<!--.*?(?:-->|$)", with: "", options: .regularExpression)
        source = source.replacingOccurrences(of: "(?is)<(script|style|head)\\b[^>]*>.*?(?:</\\1\\s*>|$)", with: "", options: .regularExpression)
        var text = ""
        var index = source.startIndex
        let blocks: Set<String> = ["br", "p", "div", "li", "tr", "td", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "section", "article", "table", "hr", "pre", "ul", "ol"]
        while index < source.endIndex {
            let next = source.index(after: index)
            if source[index] == "<", next < source.endIndex,
               source[next].isLetter || ["/", "!", "?"].contains(source[next]) {
                var end = next
                var quote: Character?
                while end < source.endIndex {
                    let char = source[end]
                    if let active = quote { if char == active { quote = nil } }
                    else if char == "\"" || char == "'" { quote = char }
                    else if char == ">" { break }
                    end = source.index(after: end)
                }
                guard end < source.endIndex else { throw MIMEBodyError.malformedHTML }
                let tag = source[next..<end].lowercased().drop(while: { $0 == "/" || $0.isWhitespace }).prefix(while: { $0.isLetter || $0.isNumber })
                text += blocks.contains(String(tag)) ? "\n" : " "
                index = source.index(after: end)
            } else { text.append(source[index]); index = next }
        }
        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ", "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "hellip": "…", "copy": "©", "reg": "®", "trade": "™", "bull": "•", "euro": "€"]
        let expression = try NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);")
        var decoded = ""
        var cursor = text.startIndex
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange])
            let scalarValue = key.hasPrefix("#x") ? UInt32(key.dropFirst(2), radix: 16) : key.hasPrefix("#") ? UInt32(key.dropFirst()) : nil
            let replacement = entities[key] ?? scalarValue.flatMap(UnicodeScalar.init).map(String.init)
            decoded += text[cursor..<range.lowerBound]
            decoded += replacement ?? String(text[range])
            cursor = range.upperBound
        }
        decoded += text[cursor...]
        text = decoded
        return text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
