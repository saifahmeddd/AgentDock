import SwiftUI
import UniformTypeIdentifiers

struct AgentDockPanel: View {
    @EnvironmentObject private var store: AgentDockStore
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()

            ScrollView {
                VStack(spacing: 14) {
                    DropZoneView(isTargeted: isDropTargeted)
                        .onDrop(
                            of: [
                                UTType.fileURL.identifier,
                                UTType.url.identifier,
                                UTType.text.identifier,
                                UTType.plainText.identifier
                            ],
                            isTargeted: $isDropTargeted,
                            perform: handleDrop
                        )

                    ComposerView()

                    if let analysis = store.selectedAnalysis {
                        AnalysisDetailView(analysis: analysis)
                    } else {
                        EmptyStateView()
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 430, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = urlFromProviderItem(item)
                    Task { @MainActor in
                        if let url {
                            store.ingestFiles([url])
                        }
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    let text = object as? String
                    Task { @MainActor in
                        if let text {
                            store.ingestDroppedText(text)
                        }
                    }
                }
            }
        }

        return handled
    }

    private func urlFromProviderItem(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var store: AgentDockStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white, .teal)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.teal.gradient)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("AgentDock")
                    .font(.headline)
                Text("Drop work. Agents handle it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.clearAll()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear")
            .disabled(store.analyses.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

private struct ComposerView: View {
    @EnvironmentObject private var store: AgentDockStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("Source", selection: $store.selectedSource) {
                    ForEach(IntakeSourceKind.allCases.filter { $0 != .unknown }) { source in
                        Label(source.rawValue, systemImage: source.symbolName)
                            .tag(source)
                    }
                }
                .labelsHidden()
                .frame(width: 156)

                Button {
                    store.ingestDraftText()
                } label: {
                    Label("Analyze", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: $store.draftText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 86, maxHeight: 112)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.teal)
            Text("Agents standing by")
                .font(.headline)
            Text("Slack, WhatsApp, Gmail, Teams, PDFs, screenshots, browser pages, and copied text.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

private struct DropZoneView: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isTargeted ? .white : .teal)

            Text(isTargeted ? "Release to analyze" : "Drop work here")
                .font(.headline)

            Text("Text, files, screenshots, PDFs, links")
                .font(.caption)
                .foregroundStyle(isTargeted ? .white.opacity(0.85) : .secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.teal : Color(nsColor: .controlBackgroundColor))
                .strokeBorder(
                    isTargeted ? Color.teal : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [7, 5])
                )
        )
        .animation(.easeOut(duration: 0.16), value: isTargeted)
    }
}
