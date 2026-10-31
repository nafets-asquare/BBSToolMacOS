import AppKit
import BafangProtocol
import UniformTypeIdentifiers

extension AppModel {
    var isProfileEdited: Bool {
        profileName != nil && settings != savedSettings
    }

    /// Profiles shipped with the original tool, bundled with the app.
    static var sampleProfiles: [URL] {
        (Bundle.main.urls(forResourcesWithExtension: Profile.fileExtension, subdirectory: "Profiles") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func openProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.profileType]
        panel.directoryURL = profileURL?.deletingLastPathComponent() ?? Self.profilesDirectory(create: false)
        panel.message = "Choose a BBSTool profile (.el)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProfile(from: url, isSample: false)
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

    static let profileType = UTType(filenameExtension: Profile.fileExtension) ?? .data

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
