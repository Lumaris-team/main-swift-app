import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        // Re-read the App Group snapshot every 30 min; the app refreshes the
        // data itself whenever it runs.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

// MARK: - Shared UI

private let widgetBG = Color(red: 0.031, green: 0.035, blue: 0.071) // #080912
private let accent = Color(red: 0.435, green: 0.831, blue: 0.949)  // #6fd4f2
private let violet = Color(red: 0.486, green: 0.302, blue: 1.0)    // #7c4dff

struct WidgetCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2.weight(.bold)).foregroundStyle(accent)
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BigStat: View {
    let value: String
    let label: String
    var color: Color = accent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

struct ItemRow: View {
    let item: WidgetSnapshot.Item
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
            if !item.sub.isEmpty {
                Text(item.sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
    }
}

func freshnessText(_ snap: WidgetSnapshot?) -> String {
    guard let d = snap?.updatedAt, d > .distantPast else { return "Ouvrez Lumaris pour synchroniser" }
    let mins = Int(Date().timeIntervalSince(d) / 60)
    if mins < 1 { return "À l'instant" }
    if mins < 60 { return "Il y a \(mins) min" }
    return "Il y a \(mins / 60) h"
}

// MARK: - 1. Aujourd'hui (medium)

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(widgetBG, for: .widget)
        }
        .configurationDisplayName("Aujourd'hui")
        .description("Tâches du jour, prochain test et cartes dues en un coup d'œil.")
        .supportedFamilies([.systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    var snap: WidgetSnapshot? { entry.snapshot }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AUJOURD'HUI").font(.caption2.weight(.bold)).foregroundStyle(accent)
                    Spacer()
                    Text(freshnessText(snap)).font(.caption2).foregroundStyle(.tertiary)
                }
                HStack(alignment: .top, spacing: 16) {
                    BigStat(value: "\(snap?.tasksDueToday ?? 0)", label: "tâche\( (snap?.tasksDueToday ?? 0) > 1 ? "s" : "") aujourd'hui")
                    BigStat(value: "\(snap?.cardsDue ?? 0)", label: "carte\( (snap?.cardsDue ?? 0) > 1 ? "s" : "") à réviser", color: violet)
                    if let avg = snap?.average {
                        BigStat(value: String(format: "%.1f", avg), label: "moyenne", color: .green)
                    }
                }
                Spacer(minLength: 0)
                if let next = snap?.nextTestTitle, !next.isEmpty {
                    Label("Test \(snap?.nextTestDays ?? 0 > 0 ? "J+\(snap!.nextTestDays)" : "aujourd'hui") : \(next)",
                          systemImage: "calendar.badge.clock")
                        .font(.caption2).foregroundStyle(.orange).lineLimit(1)
                }
            }
        }
        .padding(14)
    }
}

// MARK: - 2. Tâches restantes

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TasksWidget", provider: SnapshotProvider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(widgetBG, for: .widget)
        }
        .configurationDisplayName("Tâches restantes")
        .description("Compteur et prochaines tâches à faire.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TasksWidgetView: View {
    let entry: SnapshotEntry
    var snap: WidgetSnapshot? { entry.snapshot }
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Tâches", systemImage: "checklist").font(.caption2.weight(.semibold)).foregroundStyle(accent)
                Spacer()
                Text(freshnessText(snap)).font(.caption2).foregroundStyle(.tertiary)
            }
            BigStat(value: "\(snap?.tasksRemaining ?? 0)", label: "restante\( (snap?.tasksRemaining ?? 0) > 1 ? "s" : "")")
            if family == .systemMedium {
                if let items = snap?.taskItems, !items.isEmpty {
                    ForEach(items.prefix(3), id: \.title) { ItemRow(item: $0) }
                } else {
                    EmptyHint(text: "Aucune tâche en cours — bravo.")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - 3. Notes & moyenne

struct GradesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GradesWidget", provider: SnapshotProvider()) { entry in
            GradesWidgetView(entry: entry)
                .containerBackground(widgetBG, for: .widget)
        }
        .configurationDisplayName("Notes & moyenne")
        .description("Dernière note et moyenne générale ÉcoleDirecte.")
        .supportedFamilies([.systemMedium])
    }
}

struct GradesWidgetView: View {
    let entry: SnapshotEntry
    var snap: WidgetSnapshot? { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Notes", systemImage: "chart.bar.fill").font(.caption2.weight(.semibold)).foregroundStyle(accent)
                Spacer()
                Text(freshnessText(snap)).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(alignment: .top, spacing: 16) {
                if let avg = snap?.average {
                    BigStat(value: String(format: "%.2f", avg), label: snap?.averageLabel.isEmpty == false ? snap!.averageLabel : "Moyenne", color: .green)
                } else {
                    BigStat(value: "—", label: "Moyenne")
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let v = snap?.lastGradeValue, !v.isEmpty {
                        Text(v).font(.title3.weight(.bold).monospacedDigit())
                        Text("\(snap?.lastGradeSubject ?? "") — \(snap?.lastGradeTitle ?? "")")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        Text(snap?.lastGradeDate ?? "").font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        EmptyHint(text: "Aucune note synchronisée")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - 4. Flashcards dues

struct FlashcardsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlashcardsWidget", provider: SnapshotProvider()) { entry in
            FlashcardsWidgetView(entry: entry)
                .containerBackground(widgetBG, for: .widget)
        }
        .configurationDisplayName("Flashcards dues")
        .description("Cartes SM-2 à réviser aujourd'hui.")
        .supportedFamilies([.systemSmall])
    }
}

struct FlashcardsWidgetView: View {
    let entry: SnapshotEntry
    var snap: WidgetSnapshot? { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Flashcards", systemImage: "rectangle.on.rectangle.angled").font(.caption2.weight(.semibold)).foregroundStyle(violet)
            BigStat(value: "\(snap?.cardsDue ?? 0)", label: "à réviser", color: violet)
            Text("\(snap?.cardsTotal ?? 0) cartes au total")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(freshnessText(snap)).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
    }
}

// MARK: - 5. Devoirs ÉcoleDirecte

struct HomeworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomeworkWidget", provider: SnapshotProvider()) { entry in
            HomeworkWidgetView(entry: entry)
                .containerBackground(widgetBG, for: .widget)
        }
        .configurationDisplayName("Devoirs à rendre")
        .description("Devoirs ÉcoleDirecte non faits et prochaine échéance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeworkWidgetView: View {
    let entry: SnapshotEntry
    var snap: WidgetSnapshot? { entry.snapshot }
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Devoirs", systemImage: "book.fill").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                Spacer()
                Text(freshnessText(snap)).font(.caption2).foregroundStyle(.tertiary)
            }
            BigStat(value: "\(snap?.homeworkOpen ?? 0)", label: "à rendre", color: .orange)
            if family == .systemMedium {
                if let items = snap?.homeworkItems, !items.isEmpty {
                    ForEach(items, id: \.title) { ItemRow(item: $0) }
                } else {
                    EmptyHint(text: "Aucun devoir en attente.")
                }
            } else if let first = snap?.homeworkItems.first {
                ItemRow(item: first)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - 6. Prochain test

struct NextTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTestWidget", provider: SnapshotProvider()) { entry in
            NextTestWidgetView(entry: entry)
                .containerBackground(widgetBG, for: .widget)
        }
        .configurationDisplayName("Prochain test")
        .description("Le chapitre dont le prochain contrôle arrive le plus tôt.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextTestWidgetView: View {
    let entry: SnapshotEntry
    var snap: WidgetSnapshot? { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Prochain test", systemImage: "flag.checkered").font(.caption2.weight(.semibold)).foregroundStyle(.pink)
            if let title = snap?.nextTestTitle, !title.isEmpty {
                Text(title).font(.headline).lineLimit(3)
                Text(snap?.nextTestSubject ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                HStack {
                    Text(snap?.nextTestDate ?? "").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    if (snap?.nextTestDays ?? -1) >= 0 {
                        Text("J+\(snap!.nextTestDays)").font(.caption.weight(.bold)).foregroundStyle(.pink)
                    }
                }
            } else {
                EmptyHint(text: "Aucun test planifié")
                Spacer(minLength: 0)
            }
            Text(freshnessText(snap)).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
    }
}

// MARK: - Bundle

@main
struct LumarisWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        TasksWidget()
        GradesWidget()
        FlashcardsWidget()
        HomeworkWidget()
        NextTestWidget()
    }
}
