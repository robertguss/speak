import SwiftUI
import UniformTypeIdentifiers
import DictationCore

@MainActor
@Observable
final class DictionaryModel {
    private(set) var entries: [DictionaryEntry] = []
    private(set) var error: String?
    private(set) var importing = false
    var importResult: ImportAlert?
    private let store: DictionaryStore

    init(store: DictionaryStore) {
        self.store = store
    }

    func reload() {
        do {
            entries = try store.entries()
            error = nil
        } catch {
            self.error = "Couldn't read the dictionary: \(error)"
        }
    }

    func hints(_ prefs: AppPreferences) -> VocabularyHints {
        let provider = prefs.transcriptionProvider
        return VocabularyHints.select(entries, provider: provider, model: prefs.model(for: provider))
    }

    func save(_ entry: DictionaryEntry, isNew: Bool) -> String? {
        do {
            try isNew ? store.add(entry) : store.update(entry)
        } catch DictionaryStoreError.duplicate {
            return "Already in your dictionary"
        } catch {
            return "Couldn't save the entry: \(error)"
        }
        reload()
        return nil
    }

    func toggleStar(_ entry: DictionaryEntry) {
        var starred = entry
        starred.starred.toggle()
        if let message = save(starred, isNew: false) { error = message }
    }

    func delete(_ entry: DictionaryEntry) {
        do {
            try store.delete(id: entry.id)
            reload()
        } catch {
            self.error = "Couldn't delete the entry: \(error)"
        }
    }

    func importCSV(_ url: URL) {
        runImport {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return WisprCSVParser.parse(data: try Data(contentsOf: url))
        }
    }

    #if os(macOS)
    func importWispr() {
        runImport { try WisprDatabaseReader.read(from: WisprDatabaseReader.defaultURL) }
    }
    #endif

    private func runImport(_ read: @escaping @Sendable () throws -> ImportBatch) {
        importing = true
        let store = store
        Task {
            let outcome = await Task.detached { () -> Result<(MergeSummary, Int), Error> in
                Result {
                    let batch = try read()
                    return (try store.merge(batch.entries), batch.skipped)
                }
            }.value
            importing = false
            switch outcome {
            case .success(let (summary, skipped)):
                importResult = ImportAlert(
                    title: "Import complete",
                    message: "Added \(summary.added). Already in your dictionary: \(summary.alreadyPresent). Skipped: \(skipped)."
                )
            case .failure(let error as WisprImportError):
                importResult = ImportAlert(title: "Import failed", message: error.userMessage)
            case .failure(let error):
                importResult = ImportAlert(title: "Import failed", message: error.localizedDescription)
            }
            reload()
        }
    }
}

struct ImportAlert: Identifiable {
    let title: String
    let message: String
    var id: String { title + message }
}

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

struct EntryEditor: View {
    enum Target: Identifiable {
        case new
        case existing(DictionaryEntry)
        var id: String {
            if case .existing(let entry) = self { return entry.id }
            return "new"
        }
    }

    let target: Target
    let model: DictionaryModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind = .word
    @State private var writeAs = ""
    @State private var heardAs = ""
    @State private var duplicate: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("Word").tag(DictionaryEntry.Kind.word)
                    Text("Replacement").tag(DictionaryEntry.Kind.replacement)
                }
                .pickerStyle(.segmented)
                if kind == .replacement {
                    TextField("Heard as", text: $heardAs, prompt: Text("pee are"))
                }
                TextField("Write as", text: $writeAs, prompt: Text(kind == .word ? "Kubernetes" : "PR"))
                if let duplicate {
                    Text(duplicate).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .navigationTitle(isNew ? "Add Entry" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
        .onAppear {
            guard case .existing(let entry) = target else { return }
            kind = entry.kind
            writeAs = entry.text
            heardAs = entry.heardAs ?? ""
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var trimmedWriteAs: String { writeAs.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedHeardAs: String { heardAs.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedWriteAs.isEmpty && (kind == .word || !trimmedHeardAs.isEmpty)
    }

    private func save() {
        var entry = DictionaryEntry(kind: kind, text: trimmedWriteAs, heardAs: trimmedHeardAs)
        if case .existing(let existing) = target {
            entry = existing
            entry.kind = kind
            entry.text = trimmedWriteAs
            entry.heardAs = kind == .replacement ? trimmedHeardAs : nil
        }
        duplicate = model.save(entry, isNew: isNew)
        if duplicate == nil { dismiss() }
    }
}
