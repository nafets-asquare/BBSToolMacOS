import AppKit
import BafangProtocol
import UniformTypeIdentifiers

extension AppModel {
    var isProfileEdited: Bool {
        profileName != nil && settings != savedSettings
    }

    /// True if quitting or opening another profile would lose edits. With a profile open, that is
    /// any change since it was opened or saved. Without one, edits are safe once the controller
    /// holds exactly these values.
    var hasUnsavedChanges: Bool {
        guard settings != savedSettings else { return false }
        if profileName != nil { return true }
        return known != KnownSettings(basic: settings.basic, pedalAssist: settings.pedalAssist, throttle: settings.throttle)
    }

    /// Offers to save unsaved changes. Returns false if the user cancels (or cancels saving).
    func confirmDiscardingChanges() -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = profileName.map { "Do you want to save the changes to “\($0)”?" }
            ?? "Do you want to save your changes as a profile?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: profileURL == nil ? "Save…" : "Save")
        alert.addButton(withTitle: "Cancel")
        let dontSave = alert.addButton(withTitle: "Don't Save")
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveProfile()
            return !hasUnsavedChanges
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    /// Profiles shipped with the original tool, bundled with the app.
    static var sampleProfiles: [URL] {
        (Bundle.main.urls(forResourcesWithExtension: Profile.fileExtension, subdirectory: "Profiles") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func openProfile() {
        guard confirmDiscardingChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.profileType]
        panel.directoryURL = profileURL?.deletingLastPathComponent() ?? Self.profilesDirectory(create: false)
        panel.message = "Choose a BBSTool profile (.el)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProfile(from: url, isSample: false)
    }

    /// Opens a profile chosen outside the app, e.g. double-clicked in Finder.
    func openProfile(at url: URL) {
        guard url != profileURL || isProfileEdited else { return }
        guard confirmDiscardingChanges() else { return }
        loadProfile(from: url, isSample: false)
    }

    func openSampleProfile(_ url: URL) {
        guard confirmDiscardingChanges() else { return }
        loadProfile(from: url, isSample: true)
    }

    func loadProfile(from url: URL, isSample: Bool) {
        do {
            let loaded = try Profile.decode(Data(contentsOf: url))
            settings = loaded
            savedSettings = loaded
            highlightedField = nil
            let name = url.deletingPathExtension().lastPathComponent
            profileName = isSample ? "\(name) (sample)" : name
            profileURL = isSample ? nil : url
            status = "Opened \(name). Tabs marked • differ from the controller."
        } catch {
            alert = AlertInfo(title: "The profile could not be opened", message: "\(url.lastPathComponent): \(error)")
        }
    }

    /// Saves over the open profile, or asks for a file if there is none (or it is a sample).
    func saveProfile() {
        if let profileURL {
            writeProfile(to: profileURL)
        } else {
            saveProfileAs()
        }
    }

    func saveProfileAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.profileType]
        panel.directoryURL = profileURL?.deletingLastPathComponent() ?? Self.profilesDirectory(create: true)
        panel.nameFieldStringValue = suggestedProfileName + "." + Profile.fileExtension
        panel.message = "Profiles can also be opened by the Windows Bafang Configuration Tool."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeProfile(to: url)
    }

    private func writeProfile(to url: URL) {
        do {
            try Data(Profile.encode(settings).utf8).write(to: url, options: .atomic)
            profileURL = url
            profileName = url.deletingPathExtension().lastPathComponent
            savedSettings = settings
            status = "Saved \(url.lastPathComponent)."
        } catch {
            alert = AlertInfo(title: "The profile could not be saved", message: error.localizedDescription)
        }
    }

    private var suggestedProfileName: String {
        if let profileName, profileURL != nil {
            return profileName
        }
        let date = Date().formatted(.iso8601.year().month().day())
        return info.map { "\($0.model) \(date)" } ?? "Profile \(date)"
    }

    /// Declared in the app's Info.plist (see scripts/build-app.sh) so Finder opens profiles in
    /// BBSTool; falls back to the bare extension when running outside the bundle.
    static let profileType = UTType(profileTypeIdentifier)
        ?? UTType(filenameExtension: Profile.fileExtension)
        ?? .data

    static let profileTypeIdentifier = "io.github.nafets-asquare.bbstool.profile"

    /// ~/Documents/BBSTool Profiles, created when saving if needed; Documents when it does not
    /// exist (opening) or cannot be created (saving).
    static func profilesDirectory(create: Bool) -> URL {
        let documents = URL.documentsDirectory
        let directory = documents.appendingPathComponent("BBSTool Profiles", isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return FileManager.default.fileExists(atPath: directory.path) ? directory : documents
    }
}
