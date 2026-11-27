import SwiftUI
import WidgetKit

// Widgets d'EDP : ils affichent le résumé que l'appli enregistre à chaque synchro (WidgetStore).
// ponytail: pas de réseau dans les widgets ; ils se mettent à jour quand tu ouvres EDP (et à chaque changement de cours).

struct Entry: TimelineEntry { let date: Date; let snap: WidgetSnapshot? }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snap: WidgetStore.load() ?? (context.isPreview ? .sample : nil)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = WidgetStore.load(), now = Date()
        // une entrée à chaque début / fin de cours pour que « prochain cours » avance tout seul
        var dates = [now]
        for l in snap?.lessons ?? [] { for d in [l.s, l.e] where d > now { dates.append(d) } }
        dates = Array(Set(dates)).sorted().prefix(40).map { $0 }
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now)!
        completion(Timeline(entries: dates.map { Entry(date: $0, snap: snap) }, policy: .after(min(dates.dropFirst().first ?? next, next))))
    }
}

// MARK: - Données utiles

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(at: .now, name: "Robin",
        lessons: [.init(t: "Mathématiques", s: .now.addingTimeInterval(1800), e: .now.addingTimeInterval(5400), room: "B12", c: "#3b82f6", x: false),
                  .init(t: "Anglais", s: .now.addingTimeInterval(5400), e: .now.addingTimeInterval(9000), room: "A04", c: "#f59e0b", x: false)],
        hw: [.init(t: "Exercices 12 à 15 p. 84", subj: "Mathématiques", d: "", c: "#3b82f6"), .init(t: "Réviser le chapitre 3", subj: "Histoire", d: "", c: "#ef4444")],
        hwCount: 2, avg: 15.4, avgClass: 12.1, last: .init(v: "17", on: "20", subj: "Physique-chimie"),
        bus: .init(line: "A", dep: .now.addingTimeInterval(3600), wake: .now.addingTimeInterval(1200), first: "Mathématiques"),
        unread: 1, unreadTop: "Sortie au théâtre", outfitLabel: "Habits de demain", outfit: "jean, sweat gris")

    func lessons(at d: Date) -> (current: Lesson?, next: Lesson?, rest: [Lesson]) {
        let live = lessons.filter { $0.x != true }.sorted { $0.s < $1.s }
        let cur = live.first { $0.s <= d && d < $0.e }
        let upcoming = live.filter { $0.s > d }
        return (cur, upcoming.first, upcoming)
    }
}

extension Color {
    init(hex: String?) {
        var v: UInt64 = 0x3B82F6
        if let h = hex?.replacingOccurrences(of: "#", with: ""), h.count == 6, let x = UInt64(h, radix: 16) { v = x }
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

private func hm(_ d: Date) -> String { d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
private func num(_ x: Double) -> String { String(format: x.rounded() == x ? "%.0f" : "%.1f", x).replacingOccurrences(of: ".", with: ",") }

/// Fond adapté iOS 17 (containerBackground) et iOS 16.
extension View {
    @ViewBuilder func edpBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) { containerBackground(.fill.tertiary, for: .widget) }
        else { padding().background(Color(.secondarySystemBackground)) }
    }
}

struct NoData: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EDP").font(.headline)
            Text("Ouvre EDP une fois pour remplir ce widget.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct Header: View {
    let icon: String, title: String, tint: Color
    var body: some View {
        Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(tint).lineLimit(1)
    }
}

// MARK: - Prochain cours

struct NextLessonView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var body: some View {
        if let s = e.snap {
            let (cur, next, rest) = s.lessons(at: e.date)
            switch family {
            case .accessoryRectangular:
                if let l = cur ?? next {
                    VStack(alignment: .leading) {
                        Text(cur != nil ? "En cours" : "Prochain cours").font(.caption2)
                        Text(l.t).font(.headline).lineLimit(1)
                        Text("\(hm(l.s))\(l.room.map { " · \($0)" } ?? "")").font(.caption)
                    }
                } else { Text("Plus de cours").font(.headline) }
            case .accessoryInline:
                if let l = cur ?? next { Text("\(hm(l.s)) \(l.t)") } else { Text("Plus de cours") }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Header(icon: "clock", title: cur != nil ? "En cours" : "Prochain cours", tint: .blue)
                    if let l = cur ?? next {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: l.c)).frame(width: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.t).font(.headline).lineLimit(2)
                                Text("\(hm(l.s)) – \(hm(l.e))").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                if let r = l.room, !r.isEmpty { Text(r).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        if family != .systemSmall, let n = (cur != nil ? next : rest.dropFirst().first) {
                            Text("Ensuite : \(n.t) à \(hm(n.s))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if cur == nil { Text(l.s, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                    } else {
                        Text("Plus de cours prévu").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else { NoData() }
    }
}

// MARK: - Emploi du temps

struct ScheduleView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var body: some View {
        if let s = e.snap {
            let items = s.lessons.filter { $0.e > e.date }.sorted { $0.s < $1.s }
            VStack(alignment: .leading, spacing: 5) {
                Header(icon: "calendar", title: items.first.map { Calendar.current.isDateInToday($0.s) ? "Aujourd’hui" : $0.s.formatted(.dateTime.weekday(.wide)).capitalized } ?? "Emploi du temps", tint: .blue)
                if items.isEmpty { Text("Rien de prévu").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(Array(items.prefix(family == .systemLarge ? 9 : 3).enumerated()), id: \.offset) { _, l in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: l.c)).frame(width: 3, height: 26)
                        Text(hm(l.s)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
                        Text(l.t).font(.subheadline.weight(.medium)).lineLimit(1).strikethrough(l.x == true)
                        Spacer(minLength: 0)
                        if let r = l.room { Text(r).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else { NoData() }
    }
}

// MARK: - Devoirs

struct HomeworkView: View {
    @Environment(\.widgetFamily) var envFamily
    let e: Entry
    var forced: WidgetFamily? = nil
    var family: WidgetFamily { forced ?? envFamily }
    var body: some View {
        if let s = e.snap {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) { Image(systemName: "checklist"); Text("\(s.hwCount)").font(.title3.bold()) }
            case .accessoryInline:
                Text("\(s.hwCount) devoir\(s.hwCount > 1 ? "s" : "") à faire")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text("\(s.hwCount) à faire").font(.headline)
                    ForEach(Array(s.hw.prefix(2).enumerated()), id: \.offset) { _, h in Text(h.t).font(.caption).lineLimit(1) }
                }
            case .systemSmall:
                VStack(alignment: .leading, spacing: 4) {
                    Header(icon: "checklist", title: "À faire", tint: .blue)
                    Text("\(s.hwCount)").font(.system(size: 40, weight: .bold, design: .rounded))
                    if let h = s.hw.first { Text(h.t).font(.caption).lineLimit(2).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Header(icon: "checklist", title: "À faire · \(s.hwCount)", tint: .blue)
                    if s.hw.isEmpty { Text("Rien à faire, profite !").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(Array(s.hw.prefix(family == .systemLarge ? 8 : 3).enumerated()), id: \.offset) { _, h in
                        HStack(alignment: .top, spacing: 7) {
                            Circle().strokeBorder(Color(hex: h.c), lineWidth: 2).frame(width: 14, height: 14).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.t).font(.subheadline).lineLimit(1)
                                Text([h.subj, h.d].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else { NoData() }
    }
}

// MARK: - Moyenne et dernière note

struct AverageView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var body: some View {
        if let s = e.snap {
            switch family {
            case .accessoryCircular:
                if let a = s.avg { Gauge(value: min(max(a, 0), 20), in: 0...20) { Text("Moy.") } currentValueLabel: { Text(num(a)) }.gaugeStyle(.accessoryCircular) }
                else { Text("–") }
            case .accessoryInline:
                Text(s.avg.map { "Moyenne \(num($0))/20" } ?? "Pas de moyenne")
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Header(icon: "chart.bar", title: "Moyenne", tint: .blue)
                    Text(s.avg.map(num) ?? "–").font(.system(size: 40, weight: .bold, design: .rounded)) + Text(" /20").font(.caption).foregroundColor(.secondary)
                    if let c = s.avgClass { Text("Classe : \(num(c))").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else { NoData() }
    }
}

struct LastGradeView: View {
    let e: Entry
    var body: some View {
        if let s = e.snap {
            VStack(alignment: .leading, spacing: 4) {
                Header(icon: "star", title: "Dernière note", tint: .blue)
                if let g = s.last {
                    Text(g.v).font(.system(size: 38, weight: .bold, design: .rounded)) + Text(g.on.map { "/\($0)" } ?? "").font(.caption).foregroundColor(.secondary)
                    if let m = g.subj { Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                } else { Text("Pas encore de note").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else { NoData() }
    }
}

// MARK: - Bus, messages, habits

struct BusView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var body: some View {
        if let s = e.snap, let b = s.bus, let dep = b.dep {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text("Bus \(b.line ?? "")").font(.caption2)
                    Text(hm(dep)).font(.headline.monospacedDigit())
                    if let w = b.wake { Text("Lever \(hm(w))").font(.caption) }
                }
            case .accessoryInline:
                Text("Bus \(b.line ?? "") à \(hm(dep))")
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Header(icon: "bus", title: "Bus \(b.line ?? "")", tint: .blue)
                    Text(hm(dep)).font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    if dep > e.date { Text(dep, style: .relative).font(.caption).foregroundStyle(.secondary) }
                    if let w = b.wake { Text("Lever à \(hm(w))").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if e.snap == nil { NoData() }
        else { VStack(alignment: .leading) { Header(icon: "bus", title: "Bus", tint: .blue); Text("Règle ton bus dans EDP").font(.caption).foregroundStyle(.secondary); Spacer(minLength: 0) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
    }
}

struct MessagesView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var body: some View {
        if let s = e.snap {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) { Image(systemName: "bubble.left"); Text("\(s.unread)").font(.title3.bold()) }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Header(icon: "bubble.left", title: "Messages & infos", tint: .blue)
                    Text("\(s.unread)").font(.system(size: 40, weight: .bold, design: .rounded)) + Text(" non lu\(s.unread > 1 ? "s" : "")").font(.caption).foregroundColor(.secondary)
                    Text(s.unreadTop ?? "Rien de nouveau").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else { NoData() }
    }
}

struct OutfitView: View {
    let e: Entry
    var body: some View {
        if let s = e.snap {
            VStack(alignment: .leading, spacing: 4) {
                Header(icon: "tshirt", title: s.outfitLabel ?? "Habits", tint: .blue)
                Text(s.outfit ?? "Rien de prévu").font(.subheadline.weight(.medium)).lineLimit(4)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else { NoData() }
    }
}

// MARK: - Résumé (grand)

struct DayView: View {
    let e: Entry
    var body: some View {
        if e.snap != nil {
            VStack(spacing: 10) {
                NextLessonView(e: e).frame(maxHeight: .infinity)
                Divider()
                HomeworkView(e: e, forced: .systemMedium).frame(maxHeight: .infinity)
            }
        } else { NoData() }
    }
}

// MARK: - Déclaration des widgets

private func widget<V: View>(_ kind: String, _ name: String, _ desc: String, _ families: [WidgetFamily], @ViewBuilder _ view: @escaping (Entry) -> V) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { e in view(e).edpBackground().widgetURL(URL(string: "edp://open")) }
        .configurationDisplayName(name).description(desc).supportedFamilies(families)
}

@main
struct EDPWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonWidget(); ScheduleWidget(); HomeworkWidget(); AverageWidget(); LastGradeWidget()
        BusWidget(); MessagesWidget(); OutfitWidget(); DayWidget()
    }
}

struct NextLessonWidget: Widget { var body: some WidgetConfiguration { widget("next", "Prochain cours", "Le cours en cours ou le suivant, avec la salle.", [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]) { NextLessonView(e: $0) } } }
struct ScheduleWidget: Widget { var body: some WidgetConfiguration { widget("schedule", "Emploi du temps", "Tes prochains cours de la journée.", [.systemMedium, .systemLarge]) { ScheduleView(e: $0) } } }
struct HomeworkWidget: Widget { var body: some WidgetConfiguration { widget("homework", "Devoirs", "Ce qu’il te reste à faire.", [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]) { HomeworkView(e: $0) } } }
struct AverageWidget: Widget { var body: some WidgetConfiguration { widget("average", "Moyenne", "Ta moyenne générale et celle de la classe.", [.systemSmall, .accessoryCircular, .accessoryInline]) { AverageView(e: $0) } } }
struct LastGradeWidget: Widget { var body: some WidgetConfiguration { widget("lastgrade", "Dernière note", "Ta note la plus récente.", [.systemSmall]) { LastGradeView(e: $0) } } }
struct BusWidget: Widget { var body: some WidgetConfiguration { widget("bus", "Bus du matin", "Le bus à prendre et l’heure du lever.", [.systemSmall, .accessoryRectangular, .accessoryInline]) { BusView(e: $0) } } }
struct MessagesWidget: Widget { var body: some WidgetConfiguration { widget("messages", "Messages & infos", "Messages et annonces Pronote non lus.", [.systemSmall, .accessoryCircular]) { MessagesView(e: $0) } } }
struct OutfitWidget: Widget { var body: some WidgetConfiguration { widget("outfit", "Habits", "Ta tenue du jour ou de demain.", [.systemSmall]) { OutfitView(e: $0) } } }
struct DayWidget: Widget { var body: some WidgetConfiguration { widget("day", "Ma journée", "Prochain cours et devoirs, en grand.", [.systemLarge]) { DayView(e: $0) } } }
