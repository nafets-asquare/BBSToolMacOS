import BafangProtocol
import SwiftUI

struct BasicTab: View {
    @Environment(AppModel.self) private var model

    private func field(_ index: Int) -> FieldID {
        FieldID(block: .basic, index: index)
    }

    var body: some View {
        @Bindable var model = model
        let basic = $model.settings.basic

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("Power") {
                        FieldRow("Low battery protection", field: field(0)) {
                            BytePicker(
                                value: basic.lowBatteryProtection,
                                choices: Choices.lowBattery(for: model.info, current: basic.wrappedValue.lowBatteryProtection),
                                unit: " V"
                            )
                        }
                        FieldRow("Current limit", field: field(1)) {
                            NumberField(value: basic.currentLimit, range: 1...Int(model.info?.maxCurrent ?? 255), unit: "A")
                        }
                    }
                    Section("Speed sensing") {
                        FieldRow("Wheel diameter", field: field(22)) {
                            Picker("", selection: basic.wheelDiameter) {
                                ForEach(Choices.wheelDiameters(current: basic.wrappedValue.wheelDiameter), id: \.self) {
                                    Text($0.label).tag($0)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        FieldRow("Speed meter type", field: field(23)) {
                            Picker("", selection: basic.speedMeterType) {
                                ForEach(SpeedMeterType.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        FieldRow("Speed meter signals", field: field(23)) {
                            NumberField(value: basic.speedMeterSignals, range: 1...63)
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 330)

                Form {
                    Section("Assist levels") {
                        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Level").gridColumnAlignment(.leading)
                                Text("Current limit")
                                Text("Speed limit")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            ForEach(0..<BasicSettings.assistLevelCount, id: \.self) { level in
                                GridRow {
                                    levelLabel(level)
                                    NumberField(value: basic.assistCurrentLimit[level], range: 0...100, unit: "%")
                                    NumberField(value: basic.assistSpeedLimit[level], range: 0...100, unit: "%")
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
            BlockButtons(tab: .basic)
        }
    }

    private func levelLabel(_ level: Int) -> some View {
        let highlighted = [field(2 + level), field(12 + level)].contains(model.highlightedField)
        return Label {
            Text("Assist \(level)")
        } icon: {
            if highlighted {
                Image(systemName: "exclamationmark.triangle.fill")
            }
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(highlighted ? .red : .primary)
    }
}

struct PedalAssistTab: View {
    @Environment(AppModel.self) private var model

    private func field(_ index: Int) -> FieldID {
        FieldID(block: .pedalAssist, index: index)
    }

    var body: some View {
        @Bindable var model = model
        let pas = $model.settings.pedalAssist

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("Sensor and limits") {
                        FieldRow("Pedal sensor type", field: field(0)) {
                            Picker("", selection: pas.pedalSensorType) {
                                ForEach(PedalSensorType.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        FieldRow("Designated assist level", field: field(1)) {
                            OptionalPicker(value: pas.designatedAssistLevel, noneLabel: "By display", choices: Choices.assistLevels)
                        }
                        FieldRow("Speed limit", field: field(2)) {
                            OptionalPicker(value: pas.speedLimit, noneLabel: "By display", choices: Choices.speedLimits, unit: " km/h")
                        }
                        FieldRow("Work mode", field: field(6)) {
                            OptionalPicker(value: pas.workMode, noneLabel: "Undetermined", choices: Choices.workModes)
                        }
                    }
                    Section("Start") {
                        FieldRow("Start current", field: field(3)) {
                            NumberField(value: pas.startCurrent, range: 1...100, unit: "%")
                        }
                        FieldRow("Slow-start mode", field: field(4)) {
                            BytePicker(value: pas.slowStartMode, choices: Choices.slowStartModes)
                        }
                        FieldRow("Start degree (signals)", field: field(5)) {
                            NumberField(value: pas.startDegree, range: 1...100)
                        }
                    }
                }
                .formStyle(.grouped)

                Form {
                    Section("Stop and decay") {
                        FieldRow("Stop delay", field: field(7)) {
                            NumberField(value: pas.stopDelay, range: 0...255, unit: "× 10 ms")
                        }
                        FieldRow("Current decay", field: field(8)) {
                            NumberField(value: pas.currentDecay, range: 1...8)
                        }
                        FieldRow("Stop decay", field: field(9)) {
                            NumberField(value: pas.stopDecay, range: 0...255, unit: "× 10 ms")
                        }
                        FieldRow("Keep current", field: field(10)) {
                            NumberField(value: pas.keepCurrent, range: 1...100, unit: "%")
                        }
                    }
                }
                .formStyle(.grouped)
            }
            BlockButtons(tab: .pedalAssist)
        }
    }
}

struct ThrottleTab: View {
    @Environment(AppModel.self) private var model

    private func field(_ index: Int) -> FieldID {
        FieldID(block: .throttle, index: index)
    }

    var body: some View {
        @Bindable var model = model
        let throttle = $model.settings.throttle

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("Throttle signal") {
                        FieldRow("Start voltage", field: field(0)) {
                            TenthsField(value: throttle.startVoltage, range: 0...50, unit: "V")
                        }
                        FieldRow("End voltage", field: field(1)) {
                            TenthsField(value: throttle.endVoltage, range: 0...50, unit: "V")
                        }
                        FieldRow("Mode", field: field(2)) {
                            Picker("", selection: throttle.mode) {
                                ForEach(ThrottleMode.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                    }
                }
                .formStyle(.grouped)

                Form {
                    Section("Assist") {
                        FieldRow("Designated assist level", field: field(3)) {
                            OptionalPicker(value: throttle.designatedAssistLevel, noneLabel: "By display", choices: Choices.assistLevels)
                        }
                        FieldRow("Speed limit", field: field(4)) {
                            OptionalPicker(value: throttle.speedLimit, noneLabel: "By display", choices: Choices.speedLimits, unit: " km/h")
                        }
                        FieldRow("Start current", field: field(5)) {
                            NumberField(value: throttle.startCurrent, range: 1...100, unit: "%")
                        }
                    }
                }
                .formStyle(.grouped)
            }
            Spacer(minLength: 0)
            BlockButtons(tab: .throttle)
        }
    }
}
