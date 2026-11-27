import Foundation

/// Résumé envoyé par le site EDP pour les widgets, partagé entre l'appli et ses widgets.
struct WidgetSnapshot: Codable {
    struct Lesson: Codable { var t: String; var s: Date; var e: Date; var room: String?; var c: String?; var x: Bool? }
    struct Homework: Codable { var t: String; var subj: String?; var d: String; var c: String? }
    struct Grade: Codable { var v: String; var on: String?; var subj: String? }
    struct Bus: Codable { var line: String?; var dep: Date?; var wake: Date?; var first: String? }
    var at: Date
    var name: String?
    var lessons: [Lesson] = []
    var hw: [Homework] = []
    var hwCount: Int = 0
    var avg: Double?
    var avgClass: Double?
    var last: Grade?
    var bus: Bus?
    var unread: Int = 0
    var unreadTop: String?
    var outfitLabel: String?
    var outfit: String?
}

/// Fichier partagé (groupe d'applis). AltStore peut renommer le groupe avec ton identifiant d'équipe :
/// on essaie donc le nom déduit de l'identifiant de l'appli, puis le nom d'origine.
enum WidgetStore {
    static var folder: URL? {
        var base = Bundle.main.bundleIdentifier ?? "fr.bizzari.edp"
        if Bundle.main.bundleURL.pathExtension == "appex" { base = base.components(separatedBy: ".").dropLast().joined(separator: ".") }
        for g in ["group.\(base)", "group.fr.bizzari.edp"] {
            if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) { return u }
        }
        return nil
    }
    static var file: URL? { folder?.appendingPathComponent("widgets.json") }

    static func save(_ json: Data) -> Bool {
        guard let f = file else { return false }
        return (try? json.write(to: f, options: .atomic)) != nil
    }

    static func load() -> WidgetSnapshot? {
        guard let f = file, let d = try? Data(contentsOf: f) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WidgetSnapshot.self, from: d)
    }
}
