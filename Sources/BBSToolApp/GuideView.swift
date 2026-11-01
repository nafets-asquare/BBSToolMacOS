import SwiftUI

/// The programming guide, shown as a tab next to the settings.
struct GuideView: View {
    var body: some View {
        Form {
            ForEach(Guide.sections) { section in
                Section {
                    if let intro = section.intro {
                        Text(markdown(intro))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(section.entries) { entry in
                        GuideEntryView(entry: entry)
                    }
                } header: {
                    Text(section.title)
                }
            }

            Section {
                Text(markdown(
                    "Based on [\(Guide.sourceTitle)](\(Guide.sourceURL.absoluteString)) by Karl Gesslein, ElectricBike-Blog.com, 2015, which collects advice from em3ev, Empowered Cycles and Endless-Sphere forum members. Rewritten for BBSTool; see the original for the full discussion and the example tunes."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            } header: {
                Text("Source")
            }
        }
        .formStyle(.grouped)
    }
}

private struct GuideEntryView: View {
    let entry: GuideEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(.headline)
            Text(markdown(entry.text))
                .fixedSize(horizontal: false, vertical: true)
            if let typical = entry.typical {
                Label {
                    Text(typical)
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if let caution = entry.caution {
                Label {
                    Text(caution)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
        .textSelection(.enabled)
    }
}

/// Renders inline Markdown, keeping line breaks so numbered steps stay on separate lines.
private func markdown(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}
