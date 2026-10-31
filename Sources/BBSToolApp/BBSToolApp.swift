import AppKit
import SwiftUI

@main
struct BBSToolApp: App {
    @State private var model = AppModel()

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
            CommandGroup(replacing: .newItem) {}
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
                Button("BBSTool Help") { openHelp() }
                    .keyboardShortcut("?")
            }
        }
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: """
                Configuration tool for Bafang BBS01, BBS02 and BBSHD mid-drive controllers.

                macOS port of the Bafang Configuration Tool V2.0, originally developed by Bafang \
                (www.szbaf.com) and reworked by Stefan Penov (penoff.wordpress.com).
                """,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: "BBSTool", .credits: credits])
    }

    private func openHelp() {
        if let url = Bundle.main.url(forResource: "Help", withExtension: "pdf") {
            NSWorkspace.shared.open(url)
        } else {
            model.alert = AlertInfo(title: "Help not available", message: "The help file is included only in the BBSTool app bundle.")
        }
    }
}
