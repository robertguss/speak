import SwiftUI
import UniformTypeIdentifiers
import DictationCore

struct DictionarySection: View {
    let model: DictionaryModel
    let prefs: AppPreferences
    @State private var showingDictionary = false

    var body: some View {
        Section {
            #if os(macOS)
            Button("Edit Dictionary…") { showingDictionary = true }
                .sheet(isPresented: $showingDictionary) {
                    NavigationStack {
                        DictionaryView(model: model, prefs: prefs)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDictionary = false } }
                            }
                    }
                    .frame(minWidth: 480, minHeight: 520)
                }
            #else
            NavigationLink("Edit Dictionary") { DictionaryView(model: model, prefs: prefs) }
            #endif
            Text(hintSummary).font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("Dictionary")
        } footer: {
            Text(footer)
        }
    }

    private var hintSummary: String {
        let hints = model.hints(prefs)
        guard !model.entries.isEmpty else { return "Add names, acronyms, and jargon so they're spelled right." }
        guard hints.supported else { return "This model doesn't take spelling hints; replacements still apply." }
        return "\(model.entries.count) entries. \(hints.terms.count) of \(hints.candidateCount) sent as hints to \(prefs.transcriptionProvider.displayName)."
    }

    private var footer: String {
        var text = "Dictionary words go to your transcription provider with the audio and, when cleanup is on, to the cleanup endpoint with the transcript."
        if prefs.transcriptionProvider == .elevenLabs {
            text += " ElevenLabs charges 20% more when hints are sent."
        }
        return text
    }
}

struct DictionaryView: View {
    let model: DictionaryModel
    let prefs: AppPreferences
    @State private var search = ""
    @State private var editing: EntryEditor.Target?
    @State private var importingCSV = false

    var body: some View {
        let sent = Set(model.hints(prefs).terms.map { $0.lowercased() })
        List {
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
            if model.entries.isEmpty && model.error == nil {
                Text("No entries yet. Add a word, or import your list from Wispr Flow or a CSV file.")
                    .foregroundStyle(.secondary)
            }
            ForEach(filtered) { entry in
                EntryRow(entry: entry, sent: sent.contains(entry.text.lowercased())) { model.toggleStar(entry) }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = .existing(entry) }
                    .contextMenu {
                        Button("Edit") { editing = .existing(entry) }
                        Button(entry.starred ? "Unstar" : "Star") { model.toggleStar(entry) }
                        Button("Delete", role: .destructive) { model.delete(entry) }
                    }
                    #if os(iOS)
                    .swipeActions { Button("Delete", role: .destructive) { model.delete(entry) } }
                    #endif
            }
        }
        .searchable(text: $search)
        .navigationTitle("Dictionary")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Import CSV…") { importingCSV = true }
                    #if os(macOS)
                    Button("Import from Wispr Flow") { model.importWispr() }
                    #endif
                } label: {
                    if model.importing { ProgressView().controlSize(.small) } else { Label("Import", systemImage: "square.and.arrow.down") }
                }
                .disabled(model.importing)
            }
            ToolbarItem {
                Button { editing = .new } label: { Label("Add", systemImage: "plus") }
            }
        }
        .fileImporter(isPresented: $importingCSV, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if case .success(let url) = result { model.importCSV(url) }
        }
        .alert(item: Binding(get: { model.importResult }, set: { model.importResult = $0 })) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .sheet(item: $editing) { target in
            EntryEditor(target: target, model: model)
        }
        .onAppear { model.reload() }
    }

    private var filtered: [DictionaryEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.entries }
        return model.entries.filter { $0.text.localizedCaseInsensitiveContains(query) || ($0.heardAs ?? "").localizedCaseInsensitiveContains(query) }
    }
}

private struct EntryRow: View {
    let entry: DictionaryEntry
    let sent: Bool
    let toggleStar: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                if let heardAs = entry.heardAs {
                    Text("Heard as “\(heardAs)”").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !sent {
                Text("Not sent").font(.caption).foregroundStyle(.secondary)
            }
            Button(action: toggleStar) {
                Image(systemName: entry.starred ? "star.fill" : "star")
                    .foregroundStyle(entry.starred ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(entry.starred ? "Unstar" : "Star")
        }
    }
}
