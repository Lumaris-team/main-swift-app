import SwiftUI

/// Matières tab — subject cards → chapter list → chapter detail/editor.
struct SubjectsView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var selectedSubject: [String: Any]?
    @State private var selectedChapter: [String: Any]?
    @State private var newSubject = false

    var body: some View {
        NavigationStack {
            List(store.subjects, id: \.self.subjectRowId) { s in
                Button {
                    selectedSubject = s
                } label: {
                    HStack(spacing: 12) {
                        Text(String(J.str(s, "subject_name").prefix(1)).uppercased())
                            .font(.title3.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(store.theme.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(J.str(s, "subject_name")).font(.body.weight(.medium))
                            let chs = store.chaptersOf(J.int(s, "subject_id"))
                            Text("\(chs.count) chapitre\(chs.count > 1 ? "s" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if store.subjects.isEmpty && !store.isLoading {
                    ContentUnavailableView("Aucune matière", systemImage: "book.closed",
                                           description: Text("Créez votre première matière avec +."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(store.theme.background)
            .navigationTitle("Matières")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newSubject = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await store.loadAll() }
            .sheet(item: Binding(
                get: { selectedSubject.map { IdentifiedSubject(id: String(J.int($0, "subject_id")), row: $0) } },
                set: { if $0 == nil { selectedSubject = nil } }
            )) { item in
                SubjectDetailView(store: store, subject: item.row) { sel in
                    selectedSubject = nil
                    selectedChapter = sel
                }
            }
            .sheet(item: Binding(
                get: { selectedChapter.map { IdentifiedChapter(id: String(J.int($0, "lesson_id")), row: $0) } },
                set: { if $0 == nil { selectedChapter = nil } }
            )) { item in
                ChapterDetailView(store: store, chapter: item.row) { selectedChapter = nil }
            }
            .sheet(isPresented: $newSubject) {
                SubjectEditorView(store: store) { newSubject = false }
            }
        }
    }
}

private struct IdentifiedSubject: Identifiable { let id: String; let row: [String: Any] }
private struct IdentifiedChapter: Identifiable { let id: String; let row: [String: Any] }

private extension Dictionary where Key == String, Value == Any {
    var subjectRowId: Int { J.int(self, "subject_id") }
}

// MARK: - Subject detail

struct SubjectDetailView: View {
    @ObservedObject var store: WorkspaceStore
    let subject: [String: Any]
    let onPickChapter: ([String: Any]?) -> Void
    @State private var editing = false
    @State private var newChapter = false
    @State private var confirmDelete = false

    private var chapters: [[String: Any]] {
        store.chaptersOf(J.int(subject, "subject_id"))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Nom", value: J.str(subject, "subject_name"))
                    if !J.str(subject, "ed_subject_code").isEmpty {
                        LabeledContent("Code ED", value: J.str(subject, "ed_subject_code"))
                    }
                }

                Section {
                    ForEach(chapters, id: \.self.lessonRowId) { c in
                        Button {
                            onPickChapter(c)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(J.str(c, "lesson_name")).foregroundStyle(.primary)
                                    if J.bool(c, "awaiting_evaluation") {
                                        Text("En attente d'évaluation")
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if let d = J.date(c, "tests_date") {
                                    Text("Test : \(J.fmtDate(d))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Button { newChapter = true } label: {
                        Label("Ajouter un chapitre", systemImage: "plus")
                    }
                } header: {
                    Text("Chapitres (\(chapters.count))")
                }
            }
            .scrollContentBackground(.hidden)
            .background(store.theme.background)
            .navigationTitle(J.str(subject, "subject_name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { onPickChapter(nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Modifier") { editing = true }
                        Button("Supprimer", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("Supprimer la matière et ses chapitres ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        await store.deleteSubject(subjectId: J.int(subject, "subject_id"))
                        onPickChapter(nil)
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
            .sheet(isPresented: $editing) {
                SubjectEditorView(store: store, subject: subject) { editing = false }
            }
            .sheet(isPresented: $newChapter) {
                ChapterEditorView(store: store, chapter: nil, subjectId: J.int(subject, "subject_id")) { newChapter = false }
            }
        }
    }
}

// MARK: - Chapter detail

struct ChapterDetailView: View {
    @ObservedObject var store: WorkspaceStore
    let chapter: [String: Any]
    let onClose: () -> Void
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(J.str(chapter, "lesson_name")).font(.title3.weight(.semibold))
                        Spacer()
                        if J.bool(chapter, "awaiting_evaluation") {
                            Text("Évaluation attendue").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }

                Section("Infos") {
                    LabeledContent("Matière", value: store.subjectName(J.int(chapter, "subject_id")))
                    if let d = J.date(chapter, "session_date") {
                        LabeledContent("Séance", value: J.fmtDate(d))
                    }
                    if let d = J.date(chapter, "tests_date") {
                        LabeledContent("Prochain test", value: J.fmtDate(d))
                    }
                }

                if !J.str(chapter, "teacher_notes").isEmpty {
                    Section("Notes de la prof") {
                        Text(J.str(chapter, "teacher_notes")).font(.callout)
                    }
                }

                if !J.str(chapter, "body").isEmpty {
                    Section("Cours") {
                        Text(J.str(chapter, "body"))
                            .font(.callout)
                            .lineLimit(20)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(store.theme.background)
            .navigationTitle("Chapitre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { onClose() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Modifier") { editing = true }
                        Button("Supprimer", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("Supprimer ce chapitre ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        await store.deleteChapter(lessonId: J.int(chapter, "lesson_id"))
                        onClose()
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
            .sheet(isPresented: $editing) {
                ChapterEditorView(store: store, chapter: chapter) { editing = false }
            }
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    var lessonRowId: Int { J.int(self, "lesson_id") }
}

// MARK: - Subject editor

struct SubjectEditorView: View {
    @ObservedObject var store: WorkspaceStore
    var subject: [String: Any]? = nil
    let onDone: () -> Void

    @State private var name = ""
    @State private var edCode = ""
    @State private var edName = ""
    @State private var comments = ""
    @State private var teacherNotes = ""
    @State private var busy = false
    @State private var error: String?

    private var isNew: Bool { subject == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Matière") {
                    TextField("Nom", text: $name)
                    TextField("Code ED", text: $edCode)
                    TextField("Nom ED", text: $edName)
                }
                Section("Notes") {
                    TextField("Commentaires", text: $comments, axis: .vertical).lineLimit(2...4)
                    TextField("Notes de la prof — attentes & style de test", text: $teacherNotes, axis: .vertical).lineLimit(3...6)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(isNew ? "Nouvelle matière" : "Modifier la matière")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "…" : "Enregistrer") { Task { await save() } }
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let s = subject else { return }
                name = J.str(s, "subject_name")
                edCode = J.str(s, "ed_subject_code")
                edName = J.str(s, "ed_subject_name")
                comments = J.str(s, "comments")
                teacherNotes = J.str(s, "teacher_notes")
            }
        }
    }

    private func save() async {
        busy = true; error = nil
        defer { busy = false }
        let fields: [String: Any] = [
            "subject_name": name.trimmingCharacters(in: .whitespaces),
            "ed_subject_code": edCode,
            "ed_subject_name": edName,
            "comments": comments,
            "teacher_notes": teacherNotes,
        ]
        do {
            if isNew { try await store.createSubject(fields: fields) }
            else if let s = subject { try await store.updateSubject(subjectId: J.int(s, "subject_id"), fields: fields) }
            onDone()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Chapter editor

struct ChapterEditorView: View {
    @ObservedObject var store: WorkspaceStore
    var chapter: [String: Any]? = nil
    var subjectId: Int = 0
    let onDone: () -> Void

    @State private var name = ""
    @State private var subject = 0
    @State private var desc = ""
    @State private var teacherNotes = ""
    @State private var bodyText = ""
    @State private var hasTest = false
    @State private var testDate = Date()
    @State private var hasSession = false
    @State private var sessionDate = Date()
    @State private var awaitingEval = false
    @State private var isYearly = false
    @State private var busy = false
    @State private var error: String?

    private var isNew: Bool { chapter == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chapitre") {
                    TextField("Nom", text: $name)
                    Picker("Matière", selection: $subject) {
                        Text("—").tag(0)
                        ForEach(store.subjects, id: \.self.subjectRowId) { s in
                            Text(J.str(s, "subject_name")).tag(J.int(s, "subject_id"))
                        }
                    }
                    TextField("Description", text: $desc, axis: .vertical).lineLimit(2...4)
                }
                Section("Dates") {
                    Toggle("Date de séance", isOn: $hasSession)
                    if hasSession { DatePicker("Séance", selection: $sessionDate, displayedComponents: .date) }
                    Toggle("Prochain test", isOn: $hasTest)
                    if hasTest { DatePicker("Test", selection: $testDate, displayedComponents: .date) }
                    Toggle("En attente d'évaluation", isOn: $awaitingEval)
                    Toggle("Annuel", isOn: $isYearly)
                }
                Section("Notes") {
                    TextField("Notes de la prof — attentes & style de test", text: $teacherNotes, axis: .vertical).lineLimit(3...6)
                }
                Section("Cours") {
                    TextField("Corps du cours", text: $bodyText, axis: .vertical).lineLimit(5...12)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(isNew ? "Nouveau chapitre" : "Modifier le chapitre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "…" : "Enregistrer") { Task { await save() } }
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || subject == 0)
                }
            }
            .onAppear {
                if let c = chapter {
                    name = J.str(c, "lesson_name")
                    subject = J.int(c, "subject_id")
                    desc = J.str(c, "lesson_description")
                    teacherNotes = J.str(c, "teacher_notes")
                    bodyText = J.str(c, "body")
                    awaitingEval = J.bool(c, "awaiting_evaluation")
                    isYearly = J.bool(c, "is_yearly")
                    if let d = J.date(c, "tests_date") { hasTest = true; testDate = d }
                    if let d = J.date(c, "session_date") { hasSession = true; sessionDate = d }
                } else {
                    subject = subjectId
                }
            }
        }
    }

    private func save() async {
        busy = true; error = nil
        defer { busy = false }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        var fields: [String: Any] = [
            "lesson_name": name.trimmingCharacters(in: .whitespaces),
            "subject_id": subject,
            "lesson_description": desc,
            "teacher_notes": teacherNotes,
            "body": bodyText,
            "awaiting_evaluation": awaitingEval ? 1 : 0,
            "is_yearly": isYearly ? 1 : 0,
            "tests_date": hasTest ? day.string(from: testDate) : "",
            "session_date": hasSession ? day.string(from: sessionDate) : "",
        ]
        do {
            if isNew { try await store.createChapter(fields: fields) }
            else if let c = chapter { try await store.updateChapter(lessonId: J.int(c, "lesson_id"), fields: fields) }
            onDone()
        } catch { self.error = error.localizedDescription }
    }
}
