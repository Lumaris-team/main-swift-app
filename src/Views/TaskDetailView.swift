import SwiftUI

// MARK: - Detail (read view with quick actions)

struct TaskDetailView: View {
    @ObservedObject var store: WorkspaceStore
    let table: String
    let row: [String: Any]
    let onClose: () -> Void
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(J.str(row, "title").isEmpty ? "Sans titre" : J.str(row, "title"))
                            .font(.title3.weight(.semibold))
                        Spacer()
                        if J.bool(row, "is_done") {
                            Label("Fait", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }

                Section("Échéance") {
                    LabeledContent("Date", value: J.fmtDateTime(J.date(row, "remind_date")))
                    if !J.str(row, "frequency").isEmpty {
                        LabeledContent("Fréquence", value: freqLabel(J.str(row, "frequency")))
                    }
                }

                Section("Liens") {
                    if J.int(row, "subject_id") > 0 {
                        LabeledContent("Matière", value: store.subjectName(J.int(row, "subject_id")))
                    }
                    if J.int(row, "chapter_id") > 0 {
                        LabeledContent("Chapitre", value: store.chapterName(J.int(row, "chapter_id")))
                    }
                    if !J.str(row, "linked_action").isEmpty {
                        LabeledContent("Action", value: J.str(row, "linked_action"))
                    }
                }

                if !J.str(row, "text_body").isEmpty {
                    Section("Détails") {
                        Text(J.str(row, "text_body"))
                            .font(.callout)
                    }
                }
                if !J.str(row, "comments").isEmpty {
                    Section("Commentaires") {
                        Text(J.str(row, "comments"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Tâche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            Task { await store.toggleDone(table: table, taskId: J.int(row, "task_id")) }
                        } label: {
                            Image(systemName: J.bool(row, "is_done") ? "circle" : "checkmark.circle")
                        }
                        Button("Modifier") { editing = true }
                    }
                }
            }
            .sheet(isPresented: $editing) {
                TaskEditorView(store: store, table: table, row: row) {
                    editing = false
                    onClose()
                }
            }
        }
    }

    private func freqLabel(_ f: String) -> String {
        ["daily": "Quotidien", "weekly": "Hebdomadaire", "monthly": "Mensuel", "yearly": "Annuel", "custom": "Personnalisé"][f] ?? f
    }
}

// MARK: - Editor (create / edit)

/// Native form covering the main task columns — every field maps to a D1
/// column; nothing JSON is shown to the user.
struct TaskEditorView: View {
    @ObservedObject var store: WorkspaceStore
    let table: String
    let row: [String: Any]?
    let onDone: () -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var comments = ""
    @State private var hasDate = false
    @State private var remindDate = Date()
    @State private var remind = false
    @State private var isHomework = false
    @State private var pushTasks = false
    @State private var isDone = false
    @State private var subjectId = 0
    @State private var chapterId = 0
    @State private var methodId = 0
    @State private var priorityId = 0
    @State private var attentionId = 0
    @State private var flagId = 0
    @State private var labelId = 0
    @State private var linkedAction = ""
    @State private var frequency = ""
    @State private var busy = false
    @State private var error: String?

    private let freqOptions: [(String, String)] = [
        ("", "Aucune"), ("daily", "Quotidien"), ("weekly", "Hebdomadaire"),
        ("monthly", "Mensuel"), ("yearly", "Annuel"), ("custom", "Personnalisé"),
    ]
    private let actions: [(String, String)] = [
        ("", "—"), ("import", "Importer une leçon"), ("course", "Générer le cours"),
        ("flashcards", "Flashcards"), ("activities", "Activités / tests"),
        ("review", "Révision"), ("examplan", "Planifier le contrôle"),
        ("ask", "Poser une question IA"), ("edit", "Modifier le cours"), ("eval", "Évaluation"),
    ]

    private var isNew: Bool { row == nil }
    private var taskTable: String {
        if isNew {
            switch table {
            case "events", "repeat_events": return table
            default: return "tasks"
            }
        }
        return table
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tâche") {
                    TextField("Titre", text: $title)
                    TextField("Détails", text: $bodyText, axis: .vertical)
                        .lineLimit(3...6)
                    Toggle("Terminée", isOn: $isDone)
                    Toggle("Devoir", isOn: $isHomework)
                    Toggle("Notifications push", isOn: $pushTasks)
                }

                Section("Planification") {
                    Toggle("Date d'échéance", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Échéance", selection: $remindDate)
                    }
                    Toggle("Rappel actif", isOn: $remind)
                    Picker("Fréquence", selection: $frequency) {
                        ForEach(freqOptions, id: \.0) { Text($1).tag($0) }
                    }
                }

                Section("Organisation") {
                    Picker("Matière", selection: $subjectId) {
                        Text("—").tag(0)
                        ForEach(store.subjects, id: \.self.subjectId) { s in
                            Text(J.str(s, "subject_name")).tag(J.int(s, "subject_id"))
                        }
                    }
                    Picker("Chapitre", selection: $chapterId) {
                        Text("—").tag(0)
                        ForEach(store.chapters.filter { subjectId == 0 || J.int($0, "subject_id") == subjectId }, id: \.self.lessonId) { c in
                            Text(J.str(c, "lesson_name")).tag(J.int(c, "lesson_id"))
                        }
                    }
                    Picker("Méthode", selection: $methodId) {
                        Text("—").tag(0)
                        ForEach(store.methodOptions(), id: \.id) { Text($0.name).tag($0.id) }
                    }
                    Picker("Priorité", selection: $priorityId) {
                        Text("—").tag(0)
                        ForEach(store.lookupOptions("priorities", idKey: "priority_id"), id: \.id) { o in
                            Text(o.name.isEmpty ? "Priorité \(o.id)" : o.name).tag(o.id)
                        }
                    }
                    Picker("Attention", selection: $attentionId) {
                        Text("—").tag(0)
                        ForEach(store.lookupOptions("attention", idKey: "attention_level_id"), id: \.id) { o in
                            Text(o.name.isEmpty ? "Attention \(o.id)" : o.name).tag(o.id)
                        }
                    }
                    Picker("Drapeau", selection: $flagId) {
                        Text("—").tag(0)
                        ForEach(store.lookupOptions("flags", idKey: "flag_id"), id: \.id) { o in
                            Text(o.name.isEmpty ? "Drapeau \(o.id)" : o.name).tag(o.id)
                        }
                    }
                    Picker("Étiquette", selection: $labelId) {
                        Text("—").tag(0)
                        ForEach(store.lookupOptions("labels", idKey: "label_id"), id: \.id) { o in
                            Text(o.name.isEmpty ? "Étiquette \(o.id)" : o.name).tag(o.id)
                        }
                    }
                    Picker("Action liée", selection: $linkedAction) {
                        ForEach(actions, id: \.0) { Text($1).tag($0) }
                    }
                }

                Section("Notes") {
                    TextField("Commentaires", text: $comments, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(isNew ? "Nouvelle tâche" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "…" : "Enregistrer") { Task { await save() } }
                        .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let row else { return }
        title = J.str(row, "title")
        bodyText = J.str(row, "text_body")
        comments = J.str(row, "comments")
        isDone = J.bool(row, "is_done")
        isHomework = J.bool(row, "is_homework")
        pushTasks = J.bool(row, "push_tasks")
        remind = J.bool(row, "remind")
        subjectId = J.int(row, "subject_id")
        chapterId = J.int(row, "chapter_id")
        methodId = J.int(row, "methods_id")
        priorityId = J.int(row, "priority_id")
        attentionId = J.int(row, "attention_level_id")
        flagId = J.int(row, "flags_id")
        labelId = J.int(row, "labels_id")
        linkedAction = J.str(row, "linked_action")
        frequency = J.str(row, "frequency")
        if let d = J.date(row, "remind_date") {
            hasDate = true
            remindDate = d
        }
    }

    private func fields() -> [String: Any] {
        var f: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespaces),
            "text_body": bodyText,
            "comments": comments,
            "is_done": isDone ? 1 : 0,
            "is_homework": isHomework ? 1 : 0,
            "push_tasks": pushTasks ? 1 : 0,
            "remind": remind ? 1 : 0,
            "subject_id": subjectId,
            "chapter_id": chapterId,
            "methods_id": methodId,
            "priority_id": priorityId,
            "attention_level_id": attentionId,
            "flags_id": flagId,
            "labels_id": labelId,
            "linked_action": linkedAction,
            "frequency": frequency,
        ]
        if hasDate {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            f["remind_date"] = iso.string(from: remindDate)
        } else {
            f["remind_date"] = ""
        }
        return f
    }

    private func save() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if isNew {
                try await store.createTask(table: taskTable, fields: fields())
            } else if let row {
                try await store.updateTask(table: table, taskId: J.int(row, "task_id"), fields: fields())
            }
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    var subjectId: Int { J.int(self, "subject_id") }
    var lessonId: Int { J.int(self, "lesson_id") }
}
