import Testing
@testable import MailFilter

struct SafetyTests {
    @Test func testDefaultIsDryRun() throws {
        let options = try Options([])
        #expect(!options.apply)
        #expect(options.limit == 10)
    }
    @Test func testUnsafeApplyRejected() {
        for args in [["--apply"], ["--confirm-trash"], ["--apply", "--confirm-trash"],
                     ["--apply", "--confirm-trash", "--account", "A", "--trash-mailbox", "Trash", "--fixture", "x"],
                     ["--apply", "--confirm-trash", "--account", "A", "--trash-mailbox", "Trash", "--dry-run"]] {
            #expect(throws: (any Error).self) { try Options(args) }
        }
    }
    @Test func testExplicitApplyAccepted() throws {
        #expect(try Options(["--apply", "--confirm-trash", "--account", "A", "--trash-mailbox", "Trash"]).apply)
    }
    @Test func testInvalidLimitsRejected() {
        for n in ["0", "-1", "101", "garbage"] { #expect(throws: (any Error).self) { try Options(["--limit", n]) } }
        #expect(throws: (any Error).self) { try Options(["--prompt"]) }
        #expect(throws: (any Error).self) { try Options(["--unknown"]) }
    }
    @Test func testUnsafeMessagesCannotMove() {
        var m = MailMessage(accountID: "a", account: "A", id: 1, messageID: "mid", subject: "S", sender: "F", body: "Body", truncated: false)
        #expect(m.canMove)
        m.truncated = true
        #expect(!m.canMove)
        m.truncated = false; m.messageID = ""
        #expect(!m.canMove)
        m.messageID = "mid"; m.body = "  \n"
        #expect(!m.canMove)
    }
    @Test func testAppleScriptLiteralEscaping() {
        #expect(appleString("a\"b\\c") == "\"a\\\"b\\\\c\"")
        let injected = "\"\n delete every message\n --"
        #expect(appleString(injected).hasPrefix("\"\\\""))
    }
}
