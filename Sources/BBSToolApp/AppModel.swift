import AppKit
import BafangProtocol
import BafangSerial
import Observation

enum SettingsTab: Hashable, CaseIterable {
    case basic, pedalAssist, throttle

    init(_ block: Block) {
        switch block {
        case .pedalAssist: self = .pedalAssist
        case .throttle: self = .throttle
        default: self = .basic
        }
    }
}

/// A payload byte of a settings block, used to point at the field the controller rejected.
struct FieldID: Hashable {
    var block: Block
    var index: Int
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// A write waiting for the user's confirmation.
struct PendingWrite: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var perform: @MainActor () -> Void
}

/// The controller's values as last read or written; nil for blocks not read yet.
struct KnownSettings: Equatable {
    var basic: BasicSettings?
    var pedalAssist: PedalAssistSettings?
    var throttle: ThrottleSettings?
}

@MainActor
@Observable
final class AppModel {
    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected(GeneralInfo)
    }

    // Port selection
    private(set) var ports: [String] = []
    var selectedPort: String?

    // Connection and progress
    private(set) var connection = Connection.disconnected
    /// Description of the running operation; nil when idle.
    private(set) var activity: String?
    var status = "Not connected"

    // Settings being edited, and what the controller holds
    var settings = ControllerSettings.initial
    private(set) var known = KnownSettings()

    // Open profile. `profileURL` is nil for a sample (which cannot be saved over) or none.
    var profileName: String?
    var profileURL: URL?
    /// Settings as last opened or saved, to tell whether the profile has been edited.
    var savedSettings = ControllerSettings.initial

    // Presentation
    var selectedTab = SettingsTab.basic
    var highlightedField: FieldID?
    var alert: AlertInfo?
    var pendingWrite: PendingWrite?

    private var session: ControllerSession?
    private var portWatcher: Task<Void, Never>?

    init(watchPorts: Bool = true) {
        refreshPorts()
        if watchPorts {
            portWatcher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    self?.refreshPorts()
                }
            }
        }
    }

    var info: GeneralInfo? {
        if case .connected(let info) = connection { info } else { nil }
    }

    var isConnected: Bool { info != nil }
    var isBusy: Bool { activity != nil }
    var canTransfer: Bool { isConnected && !isBusy }

    // MARK: Ports

    /// Rescans ports, keeps the selection if it still exists, and otherwise selects the
    /// only USB adapter present. Disconnects if the connected port has gone away.
    func refreshPorts() {
        let available = PortScanner.availablePorts()
        guard available != ports else { return }
        ports = available

        if let selectedPort, !available.contains(selectedPort) {
            if isConnected {
                lostConnection("The cable was disconnected.")
            }
            self.selectedPort = nil
        }
        if selectedPort == nil {
            let adapters = PortScanner.likelyAdapters()
            selectedPort = adapters.count == 1 ? adapters[0] : nil
        }
    }

    // MARK: Connection

    func connect() {
        guard let selectedPort, connection == .disconnected else { return }
        let session = ControllerSession(path: selectedPort)
        self.session = session
        connection = .connecting
        run("Connecting…") { [weak self] in
            let info = try await session.connect()
            self?.connection = .connected(info)
            self?.status = "Connected to \(info.manufacturer) \(info.model). Read the settings to see the controller's values."
        }
    }

    func disconnect() {
        guard let session else { return }
        self.session = nil
        connection = .disconnected
        known = KnownSettings()
        status = "Disconnected"
        Task { await session.disconnect() }
    }

    private func lostConnection(_ message: String) {
        disconnect()
        status = "Connection lost"
        alert = AlertInfo(title: "Connection lost", message: message)
    }

    // MARK: Reading

    func read(_ tab: SettingsTab) {
        guard let session else { return }
        switch tab {
        case .basic:
            run("Reading Basic…") { [weak self] in
                let basic = try await session.read(BasicSettings.self)
                self?.settings.basic = basic
                self?.known.basic = basic
                self?.status = "Basic read from the controller."
            }
        case .pedalAssist:
            run("Reading Pedal Assist…") { [weak self] in
                let pedalAssist = try await session.read(PedalAssistSettings.self)
                self?.settings.pedalAssist = pedalAssist
                self?.known.pedalAssist = pedalAssist
                self?.status = "Pedal Assist read from the controller."
            }
        case .throttle:
            run("Reading Throttle Handle…") { [weak self] in
                let throttle = try await session.read(ThrottleSettings.self)
                self?.settings.throttle = throttle
                self?.known.throttle = throttle
                self?.status = "Throttle Handle read from the controller."
            }
        }
    }

    func readAll() {
        guard let session else { return }
        run("Reading all settings…") { [weak self] in
            let all = try await session.readAll()
            self?.settings = all
            self?.known = KnownSettings(basic: all.basic, pedalAssist: all.pedalAssist, throttle: all.throttle)
            self?.status = "All settings read from the controller."
        }
    }

    // MARK: Writing

    /// Asks for confirmation, listing what will change, then writes one block.
    func requestWrite(_ tab: SettingsTab) {
        switch tab {
        case .basic: requestWrite(settings.basic, known: known.basic) { $0.known.basic = $1 }
        case .pedalAssist: requestWrite(settings.pedalAssist, known: known.pedalAssist) { $0.known.pedalAssist = $1 }
        case .throttle: requestWrite(settings.throttle, known: known.throttle) { $0.known.throttle = $1 }
        }
    }

    private func requestWrite<S: DisplayableSettings>(
        _ settings: S,
        known: S?,
        remember: @escaping @MainActor (AppModel, S) -> Void
    ) {
        guard let session else { return }
        let title = S.block.title
        pendingWrite = PendingWrite(
            title: "Write \(title) to the controller?",
            message: changeSummary(settings, known: known)
        ) { [weak self] in
            self?.run("Writing \(title)…") { [weak self] in
                try await session.write(settings)
                guard let self else { return }
                remember(self, settings)
                self.status = "\(title) written and verified."
            }
        }
    }

    func requestWriteAll() {
        guard let session else { return }
        let settings = settings
        let sections = [
            section(settings.basic, known: known.basic),
            section(settings.pedalAssist, known: known.pedalAssist),
            section(settings.throttle, known: known.throttle),
        ]
        pendingWrite = PendingWrite(
            title: "Write all settings to the controller?",
            message: sections.joined(separator: "\n\n")
        ) { [weak self] in
            self?.run("Writing all settings…") { [weak self] in
                try await session.writeAll(settings)
                self?.known = KnownSettings(basic: settings.basic, pedalAssist: settings.pedalAssist, throttle: settings.throttle)
                self?.status = "All settings written and verified."
            }
        }
    }

    private func section<S: DisplayableSettings>(_ settings: S, known: S?) -> String {
        S.block.title + ":\n" + changeSummary(settings, known: known)
    }

    /// True if the block differs from what the controller is known to hold.
    func isModified(_ tab: SettingsTab) -> Bool {
        switch tab {
        case .basic: known.basic.map { $0 != settings.basic } ?? false
        case .pedalAssist: known.pedalAssist.map { $0 != settings.pedalAssist } ?? false
        case .throttle: known.throttle.map { $0 != settings.throttle } ?? false
        }
    }

    // MARK: Running operations

    /// Runs one controller operation at a time, showing progress and turning errors into alerts.
    private func run(_ description: String, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        activity = description
        highlightedField = nil
        Task {
            do {
                try await operation()
            } catch {
                handle(error)
            }
            activity = nil
        }
    }

    func handle(_ error: Error) {
        if connection == .connecting {
            session = nil
            connection = .disconnected
        }
        switch error {
        case SessionError.rejected(let block, let index, let name):
            selectedTab = SettingsTab(block)
            highlightedField = FieldID(block: block, index: index)
            status = "\(block.title) was not written."
            alert = AlertInfo(
                title: "The controller rejected \(block.title)",
                message: "\(name) is out of range. Nothing in \(block.title) was changed."
            )
        case is SerialError:
            lostConnection("\(error)")
        case LinkError.timeout(.data(.general), _):
            status = "Not connected"
            alert = AlertInfo(
                title: "The controller did not answer",
                message: "Check that the programming cable is connected to the controller and the battery is switched on."
            )
        default:
            status = "Failed"
            alert = AlertInfo(title: "Communication failed", message: "\(error)")
        }
    }
}

/// Lists the fields that differ from the controller's known values.
func changeSummary<S: DisplayableSettings>(_ settings: S, known: S?) -> String {
    guard let known else {
        return "The controller's current values have not been read, so the changes cannot be listed."
    }
    let changes = zip(S.fieldNames, zip(known.displayValues, settings.displayValues))
        .filter { $1.0 != $1.1 }
        .map { "\($0): \($1.0) → \($1.1)" }
    return changes.isEmpty ? "No changes from the controller's current values." : changes.joined(separator: "\n")
}
