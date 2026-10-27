import SwiftUI
import DictationCore

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
