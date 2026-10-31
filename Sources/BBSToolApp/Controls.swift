import BafangProtocol
import SwiftUI

/// A form row whose label is marked when the controller rejected this field.
struct FieldRow<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    let field: FieldID?
    @ViewBuilder let content: Content

    init(_ title: String, field: FieldID? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.field = field
        self.content = content()
    }

    private var isHighlighted: Bool {
        field != nil && model.highlightedField == field
    }

    var body: some View {
        LabeledContent {
            content
        } label: {
            Label {
                Text(title)
            } icon: {
                if isHighlighted {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isHighlighted ? .red : .primary)
            .help(isHighlighted ? "The controller rejected this value" : "")
        }
    }
}

/// Integer entry with a stepper, clamped to `range`.
struct NumberField: View {
    @Binding var value: UInt8
    let range: ClosedRange<Int>
    var unit: String?

    private var number: Binding<Int> {
        Binding(
            get: { Int(value) },
            set: { value = UInt8(min(max($0, range.lowerBound), range.upperBound)) }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: number, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Stepper("", value: number, in: range)
                .labelsHidden()
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .leading)
            }
        }
        .help("\(range.lowerBound)–\(range.upperBound)")
    }
}

/// Entry for a value stored in tenths, shown with one decimal (e.g. throttle voltage).
struct TenthsField: View {
    @Binding var value: UInt8
    let range: ClosedRange<Int>
    let unit: String

    private var number: Binding<Double> {
        Binding(
            get: { Double(value) / 10 },
            set: { value = UInt8(min(max(Int(($0 * 10).rounded()), range.lowerBound), range.upperBound)) }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: number, format: .number.precision(.fractionLength(1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Stepper("", value: number, in: Double(range.lowerBound) / 10...Double(range.upperBound) / 10, step: 0.1)
                .labelsHidden()
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
        }
    }
}

/// Picker for a value where nil means "set by the display" (or another sentinel meaning).
struct OptionalPicker: View {
    @Binding var value: UInt8?
    let noneLabel: String
    let choices: [UInt8]
    var unit = ""

    var body: some View {
        Picker("", selection: $value) {
            Text(noneLabel).tag(UInt8?.none)
            Divider()
            ForEach(Choices.including(value, in: choices), id: \.self) { choice in
                Text("\(choice)\(unit)").tag(UInt8?.some(choice))
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// Picker over plain byte values.
struct BytePicker: View {
    @Binding var value: UInt8
    let choices: [UInt8]
    var unit = ""

    var body: some View {
        Picker("", selection: $value) {
            ForEach(Choices.including(value, in: choices), id: \.self) { choice in
                Text("\(choice)\(unit)").tag(choice)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// Read and Write buttons for one block.
struct BlockButtons: View {
    @Environment(AppModel.self) private var model
    let tab: SettingsTab

    var body: some View {
        HStack {
            Spacer()
            Button("Read") { model.read(tab) }
            Button("Write…") { model.requestWrite(tab) }
        }
        .disabled(!model.canTransfer)
        .padding([.horizontal, .bottom])
    }
}
