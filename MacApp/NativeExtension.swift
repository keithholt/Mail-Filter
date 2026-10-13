import Foundation
import MailKit
import OSLog

@MainActor
@objc(MailFilterExtension)
final class MailFilterExtension: NSObject, MEExtension {
    override init() {
        super.init()
        Logger(subsystem: "org.mail-filter.app", category: "Lifecycle").notice("Mail-Filter extension initialized (build 12)")
    }
    func handlerForMessageActions() -> any MEMessageActionHandler { NativeMessageHandler() }
}

final class NativeMessageHandler: NSObject, MEMessageActionHandler {
    private let tracker = BodyRequestTracker()
    private let logger = Logger(subsystem: "org.mail-filter.app", category: "MailKit")
    var requiredHeaders: [String] { ["message-id", "delivered-to", "x-original-to"] }

    func decideAction(for message: MEMessage, completionHandler: @escaping (MEMessageActionDecision?) -> Void) {
        guard message.state == .received else { completionHandler(nil); return }
        logger.notice("Mail received-message callback")
        let messageID = message.headers?.first { $0.key.lowercased() == "message-id" }?.value.first
        let hasBody = message.rawData != nil
        Task { @MainActor in NativeClassifier.shared.callbackReceived(messageID: messageID, hasBody: hasBody) }
        if tracker.shouldRequestBody(messageID: messageID, hasRawData: message.rawData != nil) {
            completionHandler(.invokeAgainWithBody)
            return
        }
        guard let raw = message.rawData else {
            Task { @MainActor in NativeClassifier.shared.callbackFailure("bodyUnavailable", messageID: messageID) }
            completionHandler(nil); return
        }
        do {
            let body = try MIMEBodyDecoder.decode(raw)
            // Preserve the display name, matching selected-email diagnostics.
            let sender = message.fromAddress.rawString
            let subject = message.subject
            let deliveries = (message.headers ?? [:]).filter { ["delivered-to", "x-original-to"].contains($0.key.lowercased()) }.flatMap(\.value)
            let recipients = deliveries.isEmpty ? message.allRecipientAddresses.compactMap(\.addressString)
                : deliveries.compactMap { MEEmailAddress(rawString: $0).addressString }
            Task { @MainActor in
                let request = await NativeClassifier.shared.inspect(messageID: messageID, sender: sender, subject: subject, recipients: recipients, body: body)
                completionHandler(request ? .action(.moveToJunk) : nil)
            }
        } catch {
            let category = (error as? MIMEBodyError)?.rawValue ?? "bodyDecoder"
            Task { @MainActor in NativeClassifier.shared.callbackFailure(category, messageID: messageID) }
            completionHandler(nil)
        }
    }
}
