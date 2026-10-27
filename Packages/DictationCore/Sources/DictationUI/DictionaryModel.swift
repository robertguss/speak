import Foundation
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
