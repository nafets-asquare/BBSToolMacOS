import AppKit
import BafangProtocol
import SwiftUI

/// Owns the model so that profiles opened from Finder (possibly before the window exists) and
/// the quit check can reach it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func application(_ application: NSApplication, open urls: [URL]) {
        // Only one profile can be open at a time; take the last one chosen
        guard let url = urls.last(where: { $0.pathExtension.lowercased() == Profile.fileExtension }) else { return }
        model.openProfile(at: url)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.confirmDiscardingChanges() ? .terminateNow : .terminateCancel
    }
}

@main
struct BBSToolApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    private var model: AppModel { appDelegate.model }

    init() {
        // Needed when launched as a bare executable (swift run) rather than from the .app bundle
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("BBSTool", id: "main") {
            ContentView()
                .environment(model)
                .onAppear { NSApplication.shared.activate() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BBSTool") { showAboutPanel() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Profile…") { model.openProfile() }
                    .keyboardShortcut("o")
                Menu("Open Sample Profile") {
                    ForEach(AppModel.sampleProfiles, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            model.openSampleProfile(url)
                        }
                    }
                }
                .disabled(AppModel.sampleProfiles.isEmpty)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Profile") { model.saveProfile() }
                    .keyboardShortcut("s")
                Button("Save Profile As…") { model.saveProfileAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu("Controller") {
                Button("Connect") { model.connect() }
                    .keyboardShortcut("k")
                    .disabled(model.connection != .disconnected || model.selectedPort == nil)
                Button("Disconnect") { model.disconnect() }
                    .disabled(!model.isConnected || model.isBusy)
                Divider()
                Button("Read All") { model.readAll() }
                    .keyboardShortcut("r")
                    .disabled(!model.canTransfer)
                Button("Write All…") { model.requestWriteAll() }
                    .disabled(!model.canTransfer)
            }
            CommandGroup(replacing: .help) {
                Button("Programming Guide") { model.selectedTab = .guide }
                    .keyboardShortcut("?")
                Button("Hacker's Guide to Programming the BBS02 & BBSHD (Online)") {
                    NSWorkspace.shared.open(Guide.sourceURL)
                }
            }
        }
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: """
                Configuration tool for Bafang BBS01, BBS02 and BBSHD mid-drive controllers.

                macOS port of the Bafang Configuration Tool V2.0, originally developed by Bafang \
                (www.szbaf.com) and reworked by Stefan Penov (penoff.wordpress.com, \
                penoff.me/2016/01/13/e-bike-conversion-software).
                """,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: "BBSTool", .credits: credits])
    }
}
