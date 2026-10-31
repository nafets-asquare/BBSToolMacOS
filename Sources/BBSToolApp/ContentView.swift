import BafangProtocol
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ConnectionPanel()
                ControllerInfoPanel()
            }
            .padding()

            TabView(selection: $model.selectedTab) {
                BasicTab()
                    .tabItem { Text(tabTitle("Basic", .basic)) }
                    .tag(SettingsTab.basic)
                PedalAssistTab()
                    .tabItem { Text(tabTitle("Pedal Assist", .pedalAssist)) }
                    .tag(SettingsTab.pedalAssist)
                ThrottleTab()
                    .tabItem { Text(tabTitle("Throttle Handle", .throttle)) }
                    .tag(SettingsTab.throttle)
            }
            .padding(.horizontal)

            StatusBar()
        }
        .frame(minWidth: 780, minHeight: 640)
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .alert(
            model.pendingWrite?.title ?? "",
            isPresented: Binding(get: { model.pendingWrite != nil }, set: { if !$0 { model.pendingWrite = nil } }),
            presenting: model.pendingWrite
        ) { pending in
            Button("Write") { pending.perform() }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    /// Marks tabs whose values differ from what the controller holds.
    private func tabTitle(_ title: String, _ tab: SettingsTab) -> String {
        model.isModified(tab) ? title + " •" : title
    }
}

private struct ConnectionPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Port", selection: $model.selectedPort) {
                        if model.selectedPort == nil {
                            Text("Choose a port").tag(String?.none)
                        }
                        ForEach(model.ports, id: \.self) { port in
                            Text(port.replacingOccurrences(of: "/dev/cu.", with: "")).tag(String?.some(port))
                        }
                    }
                    .frame(maxWidth: 260)
                    .disabled(model.connection != .disconnected)

                    Button {
                        model.refreshPorts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Rescan ports")
                    .disabled(model.connection != .disconnected)
                }

                HStack {
                    if model.connection == .disconnected {
                        Button("Connect") { model.connect() }
                            .keyboardShortcut("k")
                            .disabled(model.selectedPort == nil)
                    } else {
                        Button("Disconnect") { model.disconnect() }
                            .disabled(model.isBusy)
                    }
                    Spacer()
                    Button("Read All") { model.readAll() }
                        .disabled(!model.canTransfer)
                    Button("Write All…") { model.requestWriteAll() }
                        .disabled(!model.canTransfer)
                }
            }
            .padding(6)
        }
        .frame(minWidth: 380)
    }
}

private struct ControllerInfoPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GroupBox("Controller") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Manufacturer", model.info?.manufacturer)
                row("Model", model.info?.model)
                row("Hardware", model.info.map { "V" + $0.hardwareVersion })
                row("Firmware", model.info.map { "V" + $0.firmwareVersion })
                row("Voltage", model.info?.nominalVoltage.label)
                row("Max current", model.info.map { "\($0.maxCurrent) A" })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value ?? "—").textSelection(.enabled)
        }
    }
}

private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if let activity = model.activity {
                ProgressView().controlSize(.small)
                Text(activity)
            } else {
                Text(model.status)
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
