import SwiftUI

/// Emploi du temps tab — ED timetable via /api/ed/timetable.
/// iPhone layout: week picker → day chips → course cards.
/// When ED demands the 2FA questionnaire, a sheet relays it to the user.
struct TimetableView: View {
    let api: APIClient

    @State private var data: [String: Any]?
    @State private var loading = false
    @State private var error: String?
    @State private var qcm: (question: String, propositions: [String])?
    @State private var week = 0 // 0 = cette semaine, 1 = semaine suivante
    @State private var dayIndex = -1 // -1 = aujourd'hui si possible

    private let days = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    private let dayLabels = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]
    private let weekKeys = ["semaineA", "semaineB"]

    private var weekData: [String: Any]? {
        J.dict(data?[weekKeys[week]])
    }

    private var selectedDay: Int {
        if dayIndex >= 0 && dayIndex < days.count { return dayIndex }
        // default: today for the current week, Monday otherwise
        if week == 0 {
            let wd = Calendar.current.component(.weekday, from: Date()) // 1 = dimanche
            return [2: 0, 3: 1, 4: 2, 5: 3, 6: 4, 7: 5][wd] ?? 0
        }
        return 0
    }

    private var courses: [[String: Any]] {
        guard let wd = weekData else { return [] }
        return J.array(wd[days[selectedDay]])
            .sorted { J.str($0, "horaireDebut") < J.str($1, "horaireDebut") }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Semaine", selection: $week) {
                    Text("Cette semaine").tag(0)
                    Text("Semaine suivante").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days.indices, id: \.self) { i in
                            Button {
                                dayIndex = i
                            } label: {
                                Text(dayLabels[i])
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(i == selectedDay ? Color.cyan.opacity(0.25) : Color(.secondarySystemFill))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 10)
                }

                if loading {
                    ProgressView("Connexion à ÉcoleDirecte…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView("ÉcoleDirecte indisponible", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else {
                    List(courses, id: \.self.courseId) { c in
                        CourseCard(course: c)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .overlay {
                        if courses.isEmpty {
                            ContentUnavailableView("Aucun cours", systemImage: "calendar",
                                                   description: Text("Pas de cours ce jour-là."))
                        }
                    }
                }
            }
            .navigationTitle("Emploi du temps")
            .refreshable { await load() }
            .task { if data == nil { await load() } }
            .sheet(item: Binding(
                get: { qcm.map { QCMItem(id: UUID(), question: $0.question, propositions: $0.propositions) } },
                set: { if $0 == nil { qcm = nil } }
            )) { item in
                QCMSheet(question: item.question, propositions: item.propositions) { choice in
                    qcm = nil
                    Task { await answerQCM(choice) }
                }
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            var resp = try await api.ed("timetable", headers: ["filter": "true"])
            if J.bool(resp, "qcm_required") {
                let props = (resp["propositions"] as? [String]) ?? []
                qcm = (J.str(resp, "question"), props)
                return
            }
            if let tt = J.dict(resp["timetable"]), tt["json"] != nil || tt["ok"] as? Bool == false {
                throw APIClient.APIError.workerError(J.str(resp, "error"))
            }
            data = resp
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func answerQCM(_ choice: Int) async {
        do {
            _ = try await api.edPost("qcm", ["choice": choice])
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct QCMItem: Identifiable {
    let id: UUID
    let question: String
    let propositions: [String]
}

private struct CourseCard: View {
    let course: [String: Any]
    private var cancelled: Bool { J.bool(course, "isAnnule") }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(J.str(course, "horaireDebut")) – \(J.str(course, "horaireFin"))")
                    .font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                Text(J.str(course, "matiereEnseignee").isEmpty ? J.str(course, "libelle") : J.str(course, "matiereEnseignee"))
                    .font(.body.weight(.medium))
                if !J.str(course, "enseignant").isEmpty {
                    Text(J.str(course, "enseignant")).font(.caption).foregroundStyle(.secondary)
                }
                if !J.str(course, "salle").isEmpty {
                    Label(J.str(course, "salle"), systemImage: "mappin")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if cancelled {
                Text("Annulé").font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .opacity(cancelled ? 0.5 : 1)
    }
}

private extension Dictionary where Key == String, Value == Any {
    var courseId: Int { J.int(self, "id") }
}

// MARK: - QCM sheet

private struct QCMSheet: View {
    let question: String
    let propositions: [String]
    let onAnswer: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("ÉcoleDirecte demande une vérification.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(question)
                    .font(.headline)
                ForEach(propositions.indices, id: \.self) { i in
                    Button {
                        busy = true
                        onAnswer(i)
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(UnicodeScalar(65 + i)!))
                                .font(.caption.weight(.bold))
                                .frame(width: 26, height: 26)
                                .background(.cyan.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(propositions[i])
                                .font(.body)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Vérification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
