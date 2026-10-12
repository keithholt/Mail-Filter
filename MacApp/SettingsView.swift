import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    private var page: String { model.page }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Label("Mail-Filter", systemImage: "envelope.fill").font(.headline)
                VStack(spacing: 6) {
                    navigation("Filtering", symbol: "line.3.horizontal.decrease.circle")
                    navigation("Activity", symbol: "clock")
                    navigation("Setup & help", symbol: "questionmark.circle")
                }
                Spacer()
                Text("On-device filtering\nAnalysis stays on this Mac.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(20).frame(width: 175).frame(maxHeight: .infinity).background(.quaternary.opacity(0.4))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(page).font(.largeTitle.bold())
                            Text(subtitle).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.saved {
                            VStack(alignment: .trailing, spacing: 5) {
                                Toggle("Enable filtering", isOn: Binding(get: { !model.paused }, set: model.setFilteringEnabled))
                                    .toggleStyle(.switch).fixedSize()
                                    .help("On enables filtering. Off pauses it immediately. Keep the Mail extension enabled.")
                                Text(model.paused ? "Filtering is off." : "Filtering is on.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange).padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    switch page {
                    case "Activity": activity
                    case "Setup & help": help
                    default: filtering
                    }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 850, minHeight: 690)
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in model.reloadStatus() }
    }

    private var subtitle: String {
        switch page {
        case "Activity": return "Recent decisions from the Mail extension."
        case "Setup & help": return "Set up once. Keep Mail open. Close this window anytime."
        default: return "Move verified political solicitations to Junk."
        }
    }

    private func navigation(_ title: String, symbol: String) -> some View {
        Button { model.page = title } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).padding(.horizontal, 10)
                .background(page == title ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private var filtering: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 20) {
                status("Apple Intelligence", value: model.modelStatus, ready: model.modelStatus == "Ready")
                status("Mail", value: model.mailRunning ? "Running" : "Open Mail to filter incoming messages", ready: model.mailRunning)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Accounts to filter").font(.headline)
                    Spacer()
                    Button(model.accounts.isEmpty ? "Read Mail Accounts" : "Refresh Accounts", action: model.readAccounts).disabled(model.busy)
                }
                if model.accounts.isEmpty {
                    Text("Read your account settings from Mail, then select which inboxes to filter. Mail-Filter does not read messages during setup.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(model.accounts) { account in
                        Toggle(isOn: Binding(get: { model.selection.contains(account.id) }, set: { value in
                            if value { model.selection.insert(account.id) } else { model.selection.remove(account.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name)
                                Text(account.addresses.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox)
                    }
                }
                Text("Mail from any of your configured addresses is protected, including accounts you leave unchecked.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            Toggle(isOn: $model.preview) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preview without moving messages")
                    Text("When off, verified political messages move to Junk. Save changes below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch)
            DisclosureGroup("Filtering instructions", isExpanded: $model.advanced) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Change the instructions used for future messages. The political evidence safeguard still applies.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.rules).font(.body).frame(height: 200).padding(8)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    Text("Political evidence terms").font(.subheadline.bold())
                    TextEditor(text: $model.evidenceText).font(.body).frame(height: 100).padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }.padding(.top, 10)
            }
            HStack {
                Button("Save Settings", action: model.save).buttonStyle(.borderedProminent).disabled(model.accounts.isEmpty || model.selection.isEmpty)
                Spacer()
                Button("Import Previous Setup…", action: model.importPrototype)
            }
            Text(model.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.saved {
                Label("After saving, enable Mail-Filter in Mail → Settings → Extensions.", systemImage: "checkmark.circle")
                    .font(.callout)
            }
        }
    }

    private func status(_ title: String, value: String, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Label(value, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.callout).foregroundStyle(ready ? .green : .secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 40) {
                metric("Incoming callbacks", count: model.activity.receivedCallbacks ?? 0)
                metric("Classified", count: model.activity.processed)
                metric("Junk actions requested", count: model.activity.junkRequested)
                Spacer()
                Button("Refresh", action: model.reloadStatus)
            }
            Text("Mail handles the move after an action is requested. Check the Junk mailbox to confirm. Counts persist between launches.")
                .font(.callout).foregroundStyle(.secondary)
            if let date = model.activity.lastCallback {
                Text("Last incoming callback: \(date.formatted(date: .abbreviated, time: .standard))").font(.caption)
            }
            GroupBox("Selected email analysis") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(model.analyzingSelectedMessage ? "Analyzing selected email…" : "Analyze selected email", action: model.analyzeSelectedMessage)
                            .disabled(model.analyzingSelectedMessage || model.exportingSelectedMessage)
                        Button(model.exportingSelectedMessage ? "Exporting…" : "Export selected email report…", action: model.exportSelectedEmailReport)
                            .disabled(model.exportingSelectedMessage || model.analyzingSelectedMessage)
                    }
                    Text("Select one message in Mail, then analyze it here. No messages are moved. Results may include quotes or the analyzed body excerpt.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let result = model.selectedAnalysis {
                        ScrollView {
                            Text(result).font(.callout).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }.frame(height: 240)
                        Button("Copy analysis result", action: model.copySelectedAnalysis)
                    }
                    if let note = model.analysisCopyMessage { Text(note).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Divider()
            GroupBox("Application diagnostics") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("App status, processing history and extension logs. This report excludes the selected email's analysis and content.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(model.collectingDiagnostics ? "Collecting logs…" : "Copy diagnostic report", action: model.copyDiagnostics)
                        .disabled(model.collectingDiagnostics)
                    if let note = model.diagnosticMessage { Text(note).font(.caption).foregroundStyle(.secondary) }
                    if let report = model.diagnosticReport {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Diagnostic report").font(.headline)
                                Spacer()
                                Button("Copy displayed report", action: model.copyDisplayedDiagnostics)
                            }
                            ScrollView {
                                Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            }.frame(height: 260).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Divider()
            if model.activity.recent.isEmpty {
                ContentUnavailableView("Waiting for new mail", systemImage: "envelope", description: Text("Enable the extension in Mail. New callbacks will appear here; this app does not scan existing Inbox messages."))
            } else {
                ForEach(model.activity.recent) { event in
                    HStack(alignment: .top) {
                        Image(systemName: event.outcome == "junkRequested" ? "tray.full" : "circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activityTitle(event.outcome))
                            if !event.category.isEmpty { Text(categoryDescription(event.category)).font(.caption).foregroundStyle(.secondary) }
                            if let attempt = event.attempt { Text("Classification attempt \(attempt) of 3").font(.caption).foregroundStyle(.secondary) }
                            if let domain = event.failureDomain, let code = event.failureCode {
                                Text("Error: \(domain) (\(code))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        Spacer()
                        Text(event.date, style: .time).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            Text("Activity contains decisions and error categories, not subjects, addresses or message bodies.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(count.formatted()).font(.system(size: 32, weight: .semibold, design: .rounded))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func activityTitle(_ outcome: String) -> String {
        switch outcome {
        case "junkRequested": return "Political — Junk move requested"
        case "previewPolitical": return "Political — preview only"
        case "notPolitical": return "Not political — kept"
        case "protected": return "Protected — kept"
        case "settingsChanged": return "Settings changed during classification — kept"
        case "review": return "Processing failed — kept"
        case "skipped": return "Skipped — kept"
        case "callbackReceived": return "Mail delivered a callback"
        case "queued": return "Waiting for analysis"
        case "analysisStarted": return "Analysis started"
        case "analysisSection": return "Analyzing a section of the email"
        case "retryScheduled": return "Classification failed — retry scheduled"
        case "modelPolitical": return "Model classified the message as political"
        case "modelNotPolitical": return "Model classified the message as not political"
        default: return "Mail callback received"
        }
    }

    private func categoryDescription(_ category: String) -> String {
        switch category {
        case "selfMail": return "Sender matches one of your own addresses."
        case "emptyBody": return "No readable message body."
        case "recipientNotSelected": return "Recipient doesn't match a selected account."
        case "missingIdentity": return "Stable message identity unavailable."
        case "oversizedHeaders": return "Message headers exceed processing limits."
        case "restoredOrPreviouslySelectedForJunk": return "This message was previously selected for Junk."
        case "paused": return "Filtering is paused."
        case "setupRequired": return "Save settings to begin filtering."
        case "modelUnavailable": return "Apple Intelligence is unavailable."
        case "modelGeneration": return "The on-device model couldn't complete analysis."
        case "modelTimedOut": return "The model reached a time limit. Retries share a 60-second total limit; after that the message stays in Inbox."
        case "modelDecodingFailure": return "Apple's model couldn't decode its generated content."
        case "modelConcurrentRequests": return "Apple's model rejected an overlapping request."
        case "modelUnsupportedLanguage": return "Apple's model reported an unsupported language or locale."
        case "modelUnsupportedGuide": return "Apple's model reported an unsupported generation guide."
        case "modelUnsupportedCapability": return "Apple's model reported an unsupported capability."
        case "modelUnsupportedInput": return "Apple's model reported unsupported input content."
        case "modelSessionMutation": return "The model session changed while generating its response."
        case "modelContextLimit": return "The model context was exceeded. A retry uses smaller email sections."
        case "promptContextLimit": return "Saved filtering instructions leave too little room in the model. Shorten them."
        case "emailSectionContextLimit", "emailSectionLimit": return "Email sections could not fit within the analysis limits."
        case "modelRefusal": return "The model refused to classify the message."
        case "modelRateLimited": return "Apple's model service limited the request."
        case "analysisCancelled": return "Analysis was cancelled."
        case "privateSettings": return "The extension couldn't access filtering settings."
        case "bodyReady": return "Mail supplied the message body."
        case "bodyRequested": return "Waiting for Mail to supply the body."
        case "waitingForAnalysis": return "A previous message is still being analyzed."
        case "onDeviceModel": return "The message reached Apple's on-device model."
        case "duplicateCallback": return "This callback was already processed or queued."
        case "invalidClassificationOrEvidence": return "A political decision couldn't be verified."
        case "invalidModelResponse": return "The model did not return a valid classification."
        case "evidenceRejected": return "The model said political, but its evidence could not be verified."
        case "queueFull": return "Too many messages arrived at once."
        case "protectionState", "protectionWriteOrSettingsChanged": return "Recovery records couldn't be used, or settings changed."
        case "bodyUnavailable": return "Mail did not supply the message body."
        default: return category.hasPrefix("section") ? category : "Message could not be processed safely."
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 18) {
            helpItem("1. Choose accounts and save", "Read Mail accounts on the Filtering page. Allow access to Mail account settings when macOS asks. Select inboxes and save.")
            helpItem("2. Enable the Mail extension", "Open Mail → Settings → Extensions, then check Mail-Filter.")
            Button("Open Mail", action: model.openMail)
            helpItem("3. Keep Mail running", "Mail-Filter's settings window can be closed, and this app can quit. Incoming mail is handled by the extension while Mail is running and your Mac is awake.")
            helpItem("Pause filtering", "Turn the Enable filtering switch off to leave new messages in place. Turn it on to resume. This switch is saved immediately; it does not require Save Settings. Keep Mail-Filter enabled in Mail's Extensions settings.")
            helpItem("Recover a false positive", "Move it from Junk back to Inbox. Its saved identity prevents another Junk move, including after restarts and settings changes. Junk moves already requested cannot be recalled by turning filtering off.")
            helpItem("Update or uninstall", "Install a newer version over this one. Settings and restored-message protection are kept outside the app. Use Uninstall Mail-Filter to remove the app, with an option to erase its private data.")
            HStack {
                Button("Import Protection File…", action: model.importProtectionFile)
                Button("Open Uninstaller…", action: model.openUninstaller)
            }
            Link("Mail extension help from Apple", destination: URL(string: "https://support.apple.com/guide/mail/use-mail-extensions-mlhla9a93cd5/mac")!)
                .font(.callout)
        }
    }

    private func helpItem(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
