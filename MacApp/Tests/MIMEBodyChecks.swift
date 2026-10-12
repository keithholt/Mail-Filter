import Foundation

struct CheckFailure: Error { let name: String }

@main
struct DecoderChecks {
    static func require(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        if try !condition() { throw CheckFailure(name: name) }
    }
    static func message(_ headers: String, _ body: String) -> Data {
        Data((headers + "\r\n\r\n" + body).utf8)
    }
    static func message(_ body: String) -> Data {
        message("Content-Type: text/plain; charset=utf-8", body)
    }
    static func rejects(_ input: Data, _ expected: MIMEBodyError) throws {
        do { _ = try MIMEBodyDecoder.decode(input) }
        catch let error as MIMEBodyError {
            try require(error == expected, "expected rejection category")
            return
        }
        throw CheckFailure(name: "malformed input must fail extraction")
    }
    static func main() throws {
        let plain = try MIMEBodyDecoder.decode(message("Hello — dinner Saturday?"))
        try require(plain.text == "Hello — dinner Saturday?", "UTF-8 plain text")
        let qp = try MIMEBodyDecoder.decode(message("Content-Type: text/plain;\r\n charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable", "Donate=20to=20our=20elec=\r\ntion=20campaign.=0AThank=20you."))
        try require(qp.text == "Donate to our election campaign.\nThank you.", "folded headers and quoted-printable soft breaks")
        let b64 = Data("Meeting at café".utf8).base64EncodedString()
        let base64 = try MIMEBodyDecoder.decode(message("Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64", b64))
        try require(base64.text == "Meeting at café", "base64 text")
        let legacy = try MIMEBodyDecoder.decode(message("Content-Type: text/plain; charset=windows-1252\r\nContent-Transfer-Encoding: quoted-printable", "=93Thanks=94 =80"))
        try require(legacy.text == "“Thanks” €", "declared legacy charset")

        let html = "<html><head><title>Omit title</title></head><body><!-- Omit comment --><style>Omit style</style><script>Omit script</script><p>Donate &amp; vote &#x2014; now.</p><a href='https://invalid.example/never-fetch' title='hidden > attribute'>Read more</a><img src='https://invalid.example/never-load'></body></html>"
        let extractedHTML = try MIMEBodyDecoder.decode(message("Content-Type: text/html; charset=utf-8", html))
        try require(extractedHTML.text.contains("Donate & vote — now.") && extractedHTML.text.contains("Read more"), "HTML visible text and entities")
        try require(!extractedHTML.text.contains("Omit") && !extractedHTML.text.contains("invalid.example") && !extractedHTML.text.contains("attribute"), "HTML scripts, styles, comments and attributes omitted")
        let alternatives = "--body\r\nContent-Type: text/plain\r\n\r\nDinner Saturday?\r\n--body\r\nContent-Type: text/html\r\n\r\n<p>Other representation</p>\r\n--body--\r\n"
        let alternative = try MIMEBodyDecoder.decode(message("Content-Type: multipart/alternative; boundary=\"body\"", alternatives))
        try require(alternative.text == "Dinner Saturday?", "prefer plain alternative without duplicates")
        let htmlOnly = "--b\nContent-Type: text/plain\n\n \n--b\nContent-Type: text/html\n\n<p>Hello HTML</p>\n--b--"
        try require(try MIMEBodyDecoder.decode(message("Content-Type: multipart/alternative; boundary=b", htmlOnly)).text == "Hello HTML", "empty plain alternative falls back to HTML")
        let brokenHTML = "--b\nContent-Type: text/plain\n\nSupport the election campaign\n--b\nContent-Type: text/html\n\n<p title='broken>\n--b--"
        try require(try MIMEBodyDecoder.decode(message("Content-Type: multipart/alternative; boundary=b", brokenHTML)).text == "Support the election campaign", "malformed HTML does not discard valid plain alternative")
        let brokenPlain = "--b\nContent-Type: text/plain\nContent-Transfer-Encoding: base64\n\nnot@base64\n--b\nContent-Type: text/html\n\n<p>Campaign for the Second Amendment</p>\n--b--"
        try require(try MIMEBodyDecoder.decode(message("Content-Type: multipart/alternative; boundary=b", brokenPlain)).text == "Campaign for the Second Amendment", "malformed plain alternative falls back to valid HTML")
        let allBroken = brokenPlain.replacingOccurrences(of: "<p>Campaign for the Second Amendment</p>", with: "<p title='broken>")
        try rejects(message("Content-Type: multipart/alternative; boundary=b", allBroken), .malformedEncoding)
        let mixed = "--outer\nContent-Type: multipart/alternative; boundary=body\n\n" + alternatives + "\n--outer\nContent-Type: text/plain; name=policy.txt\nContent-Disposition: attachment; filename=policy.txt\n\nPolitical attachment must be omitted\n--outer\nContent-Type: application/pdf\n\nPolitical PDF must be omitted\n--outer--"
        try require(try MIMEBodyDecoder.decode(message("Content-Type: multipart/mixed; boundary=outer", mixed)).text == "Dinner Saturday?", "nested body with attachments excluded")
        let related = "--r\nContent-Type: text/plain\nContent-ID: <resource>\n\nUnrelated resource text\n--r\nContent-Type: text/html\nContent-ID: <root>\n\n<p>Root document</p>\n--r--"
        try require(try MIMEBodyDecoder.decode(message("Content-Type: multipart/related; boundary=r; start=\"<root>\"", related)).text == "Root document", "related root selected by Content-ID")
        let embedded = try MIMEBodyDecoder.decode(message("Content-Type: message/rfc822", "From: external@example.com\r\n\r\nPolitical attachment"))
        try require(embedded.text.isEmpty, "embedded email attachment excluded")
        let empty = try MIMEBodyDecoder.decode(message(" \r\n\t"))
        try require(empty.text.isEmpty && !empty.truncated, "empty body")
        let long = try MIMEBodyDecoder.decode(message(String(repeating: "a", count: 8_000)))
        try require(long.characterCount == 8_000 && long.text.count == 6_000 && long.truncated, "first 6000 character excerpt")

        try rejects(message("Content-Transfer-Encoding: quoted-printable", "Bad =GZ"), .malformedEncoding)
        try rejects(message("Content-Transfer-Encoding: base64", "not@base64"), .malformedEncoding)
        try rejects(message("Content-Type: text/plain; charset=unrecognized-example", "Hello"), .unsupportedCharset)
        try rejects(message("Content-Type: text/plain\r\nContent-Type: text/html", "Hello"), .malformedHeaders)
        try rejects(message("Content-Type: multipart/mixed; boundary=x", "--x\nContent-Type: text/plain\n\nMissing closing boundary"), .malformedMultipart)
        try rejects(message("Content-Type: multipart/encrypted; boundary=x", "ignored"), .unsupportedMultipart)
        try rejects(message("Content-Type: text/html", "<a title='unterminated> text"), .malformedHTML)
        try rejects(Data(repeating: 65, count: 2 * 1_024 * 1_024 + 1), .oversizedMessage)
        try rejects(message(String(repeating: "a", count: 256 * 1_024 + 1)), .oversizedText)
        var nested = "Content-Type: text/plain\n\nHello"
        for n in 0..<8 { nested = "Content-Type: multipart/mixed; boundary=b\(n)\n\n--b\(n)\n" + nested + "\n--b\(n)--" }
        try rejects(Data(nested.utf8), .nestingLimit)
        let tooMany = (0..<129).map { _ in "--x\nContent-Type: text/plain\n\nHello\n" }.joined() + "--x--"
        try rejects(message("Content-Type: multipart/mixed; boundary=x", tooMany), .partLimit)
        let request = BodyRequestTracker(capacity: 1)
        try require(!request.shouldRequestBody(messageID: nil, hasRawData: false), "missing identity does not request body")
        try require(request.shouldRequestBody(messageID: "<sample@example.com>", hasRawData: false), "initial body request")
        try require(!request.shouldRequestBody(messageID: "<sample@example.com>", hasRawData: false), "no repeated body request")
        try require(request.shouldRequestBody(messageID: "<other@example.com>", hasRawData: false), "body tracker continues past capacity")
        try require(!request.shouldRequestBody(messageID: "<other@example.com>", hasRawData: false), "newest retry identity stays protected")
        try require(request.shouldRequestBody(messageID: "<sample@example.com>", hasRawData: false), "oldest request evicted within memory bound")
        print("Passed 33 MIME extraction and body-request checks (synthetic messages only)")
    }
}
