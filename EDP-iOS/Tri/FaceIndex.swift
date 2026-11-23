import Foundation
import Photos
import UIKit
import Vision
import Accelerate
import Contacts

struct FaceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Reconnaissance des visages, entièrement sur l'iPhone (rien n'est envoyé ailleurs).
///  1. Vision trouve les visages de chaque photo ;
///  2. chaque visage reçoit une « empreinte » (vecteur) calculée par Vision sur le visage recadré ;
///  3. les visages proches sont regroupés (voisins mutuels au-dessus d'un seuil réglable) ;
///  4. les photos de profil des contacts servent à proposer un nom pour chaque groupe.
/// Les empreintes sont gardées dans un fichier de l'appli : une nouvelle analyse ne traite que les nouvelles photos.
final class FaceIndex {
    static let shared = FaceIndex()

    struct Face: Codable {
        let asset: String          // identifiant local de la photo
        let box: [Float]           // x, y, largeur, hauteur (0…1, origine en haut à gauche)
        let q: Data                // empreinte normalisée, quantifiée sur 8 bits
    }
    private struct Store: Codable {
        var version = 1
        var scanned: [String: Double] = [:]   // photo → date de modification déjà analysée
        var faces: [Face] = []
    }

    private let queue = DispatchQueue(label: "tri.faces", qos: .userInitiated)
    private var store = Store()
    private var loaded = false
    private var scanning = false
    private var cancelRequested = false
    // voisins les plus proches (calculés après chaque analyse) : face → [(face, similarité)]
    private var neighbors: [[(Int, Float)]] = []
    private var vectors: [Float] = []
    private var dim = 0
    private var contactPrints: [(id: String, name: String, v: [Float])] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tri", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("faces-v1.plist")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL), let s = try? PropertyListDecoder().decode(Store.self, from: data), s.version == 1 {
            store = s
        }
    }
    private func save() {
        let enc = PropertyListEncoder(); enc.outputFormat = .binary
        if let data = try? enc.encode(store) { try? data.write(to: fileURL, options: .atomic) }
    }

    // MARK: Analyse

    /// Analyse les photos pas encore traitées. `progress(fait, total, visages)` est appelé régulièrement.
    func scan(progress: @escaping (Int, Int, Int) -> Void, done: @escaping (Result<[String: Any], Error>) -> Void) {
        queue.async {
            self.loadIfNeeded()
            if self.scanning { DispatchQueue.main.async { done(.failure(FaceError("Analyse déjà en cours."))) }; return }
            self.scanning = true; self.cancelRequested = false
            defer { self.scanning = false }

            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let fetch = PHAsset.fetchAssets(with: opts)
            var todo: [PHAsset] = []
            var alive = Set<String>()
            fetch.enumerateObjects { a, _, _ in
                alive.insert(a.localIdentifier)
                let m = a.modificationDate?.timeIntervalSince1970 ?? 0
                if self.store.scanned[a.localIdentifier] != m, a.mediaSubtypes.contains(.photoScreenshot) == false { todo.append(a) }
            }
            // photos supprimées entre-temps
            self.store.faces.removeAll { !alive.contains($0.asset) }
            self.store.scanned = self.store.scanned.filter { alive.contains($0.key) }

            let total = todo.count
            var lastSave = Date()
            for (i, asset) in todo.enumerated() {
                if self.cancelRequested { break }
                autoreleasepool {
                    let found = self.facesIn(asset)
                    self.store.faces.removeAll { $0.asset == asset.localIdentifier }
                    self.store.faces.append(contentsOf: found)
                    self.store.scanned[asset.localIdentifier] = asset.modificationDate?.timeIntervalSince1970 ?? 0
                }
                if i % 8 == 0 || i == total - 1 {
                    let n = self.store.faces.count
                    DispatchQueue.main.async { progress(i + 1, total, n) }
                }
                if Date().timeIntervalSince(lastSave) > 15 { self.save(); lastSave = Date() }
            }
            self.save()
            self.buildNeighbors()
            let result: [String: Any] = ["faces": self.store.faces.count, "photos": self.store.scanned.count,
                                         "cancelled": self.cancelRequested, "suggested": Double(self.defaultThreshold())]
            DispatchQueue.main.async { done(.success(result)) }
        }
    }

    func cancel() { cancelRequested = true }

    /// Visages d'une photo : détection, recadrage avec une marge, empreinte.
    private func facesIn(_ asset: PHAsset) -> [Face] {
        guard let image = Self.uprightImage(asset, side: 900) else { return [] }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let detect = VNDetectFaceRectanglesRequest()
        guard (try? handler.perform([detect])) != nil, let faces = detect.results, !faces.isEmpty else { return [] }
        let W = CGFloat(image.width), H = CGFloat(image.height)
        var out: [Face] = []
        for f in faces.prefix(12) {
            let b = f.boundingBox       // origine en bas à gauche
            // visages trop petits : peu fiables
            if b.width * W < 48 || b.height * H < 48 { continue }
            var r = CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H)
            r = r.insetBy(dx: -r.width * 0.18, dy: -r.height * 0.18).intersection(CGRect(x: 0, y: 0, width: W, height: H))
            guard let crop = image.cropping(to: r.integral), let v = Self.featurePrint(crop) else { continue }
            out.append(Face(asset: asset.localIdentifier,
                            box: [Float(r.minX / W), Float(r.minY / H), Float(r.width / W), Float(r.height / H)],
                            q: Self.quantize(v)))
        }
        return out
    }

    // MARK: Regroupement

    private func buildNeighbors() {
        let faces = store.faces
        guard let first = faces.first else { neighbors = []; vectors = []; dim = 0; return }
        dim = first.q.count
        let n = faces.count
        vectors = [Float](repeating: 0, count: n * dim)
        for (i, f) in faces.enumerated() where f.q.count == dim {
            let v = Self.dequantize(f.q)
            vectors.replaceSubrange(i * dim ..< (i + 1) * dim, with: v)
        }
        var assetIndex: [String: Int] = [:]
        let owner = faces.map { f -> Int in if let x = assetIndex[f.asset] { return x }; let x = assetIndex.count; assetIndex[f.asset] = x; return x }
        let k = min(12, n - 1)
        var result = [[(Int, Float)]](repeating: [], count: n)
        guard k > 0 else { neighbors = result; return }
        let block = 256
        var sims = [Float](repeating: 0, count: block * n)
        transposedCache = nil
        let allT = transposedAll()
        var start = 0
        while start < n {
            let rows = min(block, n - start)
            vectors.withUnsafeBufferPointer { all in
                sims.withUnsafeMutableBufferPointer { out in
                    // sims[rows × n] = A[rows × dim] · Allᵀ
                    vDSP_mmul(all.baseAddress! + start * dim, 1, allT, 1, out.baseAddress!, 1,
                              vDSP_Length(rows), vDSP_Length(n), vDSP_Length(dim))
                }
            }
            for r in 0 ..< rows {
                let i = start + r
                var best: [(Int, Float)] = []
                best.reserveCapacity(k + 1)
                for j in 0 ..< n where owner[j] != owner[i] {   // jamais deux visages d'une même photo
                    let s = sims[r * n + j]
                    if best.count < k { best.append((j, s)); if best.count == k { best.sort { $0.1 > $1.1 } } }
                    else if s > best[k - 1].1 {
                        best[k - 1] = (j, s)
                        var x = k - 1
                        while x > 0 && best[x].1 > best[x - 1].1 { best.swapAt(x, x - 1); x -= 1 }
                    }
                }
                if best.count < k { best.sort { $0.1 > $1.1 } }
                result[i] = best
            }
            start += rows
        }
        neighbors = result
        transposedCache = nil
    }

    private var transposedCache: [Float]?
    private func transposedAll() -> [Float] {
        if let t = transposedCache { return t }
        let n = vectors.count / max(dim, 1)
        var t = [Float](repeating: 0, count: vectors.count)
        vDSP_mtrans(vectors, 1, &t, 1, vDSP_Length(dim), vDSP_Length(n))
        transposedCache = t
        return t
    }

    /// Seuil proposé : adapté à la galerie (similarité typique du visage le plus proche).
    func defaultThreshold() -> Float {
        let nn = neighbors.compactMap { $0.first?.1 }.sorted()
        guard nn.count >= 10 else { return 0.8 }
        return max(0.6, min(0.95, nn[Int(Double(nn.count) * 0.35)]))
    }

    /// Groupes de visages pour un seuil donné : voisins mutuels au-dessus du seuil, puis union.
    func clusters(threshold: Float, minSize: Int, done: @escaping ([String: Any]) -> Void) {
        queue.async {
            self.loadIfNeeded()
            if self.neighbors.count != self.store.faces.count { self.buildNeighbors() }
            let n = self.store.faces.count
            var parent = Array(0 ..< n)
            func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
            let sets = self.neighbors.map { Set($0.filter { $0.1 >= threshold }.map { $0.0 }) }
            for i in 0 ..< n { for j in sets[i] where j > i && sets[j].contains(i) { let a = find(i), b = find(j); if a != b { parent[a] = b } } }
            var groups: [Int: [Int]] = [:]
            for i in 0 ..< n { groups[find(i), default: []].append(i) }
            let big = groups.values.filter { $0.count >= minSize }.sorted { $0.count > $1.count }
            var out: [[String: Any]] = []
            for g in big.prefix(300) {
                let centroid = self.centroid(of: g)
                // visage le plus représentatif : le plus proche du centre
                let rep = g.max { self.dot(centroid, $0) < self.dot(centroid, $1) } ?? g[0]
                let faces = g.map { self.faceDict($0) }
                var item: [String: Any] = ["faces": faces, "cover": self.faceDict(rep), "size": g.count]
                if let m = self.bestContact(centroid, threshold: threshold) { item["contact"] = ["id": m.id, "name": m.name, "score": Double(m.score)] }
                out.append(item)
            }
            DispatchQueue.main.async { done(["groups": out, "faces": n, "threshold": Double(threshold), "suggested": Double(self.defaultThreshold())]) }
        }
    }

    /// Ressemblance moyenne entre deux groupes (pour proposer « est-ce la même personne ? »).
    func similarity(_ a: [String], _ b: [String], done: @escaping (Double) -> Void) {
        queue.async {
            let ia = self.indices(a), ib = self.indices(b)
            guard !ia.isEmpty, !ib.isEmpty else { DispatchQueue.main.async { done(0) }; return }
            let ca = self.centroid(of: ia), cb = self.centroid(of: ib)
            var s: Float = 0; vDSP_dotpr(ca, 1, cb, 1, &s, vDSP_Length(self.dim))
            DispatchQueue.main.async { done(Double(s)) }
        }
    }

    private func indices(_ keys: [String]) -> [Int] {
        let wanted = Set(keys)
        return store.faces.indices.filter { wanted.contains(Self.key(store.faces[$0], $0, in: store.faces)) }
    }
    private func faceDict(_ i: Int) -> [String: Any] {
        let f = store.faces[i]
        return ["key": Self.key(f, i, in: store.faces), "asset": f.asset, "box": f.box.map { Double($0) }]
    }
    /// Clé stable d'un visage : photo + position arrondie (ne dépend pas de l'ordre du fichier).
    static func key(_ f: Face, _ i: Int, in all: [Face]) -> String {
        "\(f.asset)#\(Int((f.box[0] * 100).rounded()))-\(Int((f.box[1] * 100).rounded()))"
    }
    private func centroid(of idx: [Int]) -> [Float] {
        var c = [Float](repeating: 0, count: dim)
        vectors.withUnsafeBufferPointer { v in
            for i in idx { vDSP_vadd(c, 1, v.baseAddress! + i * dim, 1, &c, 1, vDSP_Length(dim)) }
        }
        return Self.normalized(c)
    }
    private func dot(_ c: [Float], _ i: Int) -> Float {
        var s: Float = 0
        vectors.withUnsafeBufferPointer { v in vDSP_dotpr(c, 1, v.baseAddress! + i * dim, 1, &s, vDSP_Length(dim)) }
        return s
    }

    // MARK: Contacts

    /// Lit les photos de profil des contacts pour proposer des noms (avec la permission de l'utilisateur).
    func loadContacts(done: @escaping (Result<Int, Error>) -> Void) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else { DispatchQueue.main.async { done(.failure(FaceError("Accès aux contacts refusé : autorise-le dans Réglages › Tri › Contacts."))) }; return }
            self.queue.async {
                let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor,
                                               CNContactNicknameKey as CNKeyDescriptor, CNContactThumbnailImageDataKey as CNKeyDescriptor,
                                               CNContactImageDataAvailableKey as CNKeyDescriptor]
                var prints: [(String, String, [Float])] = []
                let req = CNContactFetchRequest(keysToFetch: keys)
                try? store.enumerateContacts(with: req) { c, _ in
                    guard c.imageDataAvailable, let data = c.thumbnailImageData, let img = UIImage(data: data)?.cgImage else { return }
                    let name = c.nickname.isEmpty ? [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ") : c.nickname
                    guard !name.isEmpty else { return }
                    // recadre sur le visage s'il est trouvé, sinon toute la photo
                    let handler = VNImageRequestHandler(cgImage: img, options: [:])
                    let detect = VNDetectFaceRectanglesRequest()
                    var target = img
                    if (try? handler.perform([detect])) != nil, let f = detect.results?.first {
                        let W = CGFloat(img.width), H = CGFloat(img.height), b = f.boundingBox
                        var r = CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H)
                        r = r.insetBy(dx: -r.width * 0.18, dy: -r.height * 0.18).intersection(CGRect(x: 0, y: 0, width: W, height: H))
                        if let crop = img.cropping(to: r.integral) { target = crop }
                    }
                    if let v = Self.featurePrint(target) { prints.append((c.identifier, name, v)) }
                }
                self.contactPrints = prints.map { (id: $0.0, name: $0.1, v: $0.2) }
                DispatchQueue.main.async { done(.success(prints.count)) }
            }
        }
    }

    private func bestContact(_ centroid: [Float], threshold: Float) -> (id: String, name: String, score: Float)? {
        guard !contactPrints.isEmpty, contactPrints[0].v.count == centroid.count else { return nil }
        var best: (String, String, Float)?
        for c in contactPrints {
            var s: Float = 0; vDSP_dotpr(centroid, 1, c.v, 1, &s, vDSP_Length(centroid.count))
            if s >= threshold - 0.04, s > (best?.2 ?? -1) { best = (c.id, c.name, s) }
        }
        return best.map { (id: $0.0, name: $0.1, score: $0.2) }
    }

    func reset() {
        queue.async {
            self.store = Store(); self.neighbors = []; self.vectors = []; self.transposedCache = nil
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    // MARK: Outils

    /// Image droite (orientation appliquée), au plus `side` pixels de côté.
    static func uprightImage(_ asset: PHAsset, side: CGFloat) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        var result: UIImage?
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options) { img, _ in result = img }
        guard let img = result else { return nil }
        if img.imageOrientation == .up, let cg = img.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: img.size, format: format).image { _ in img.draw(at: .zero) }.cgImage
    }

    static func featurePrint(_ image: CGImage) -> [Float]? {
        let req = VNGenerateImageFeaturePrintRequest()
        req.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([req])) != nil, let obs = req.results?.first else { return nil }
        let n = obs.elementCount
        var v = [Float](repeating: 0, count: n)
        obs.data.withUnsafeBytes { raw in
            switch obs.elementType {
            case .float: for i in 0 ..< n { v[i] = raw.load(fromByteOffset: i * 4, as: Float.self) }
            case .double: for i in 0 ..< n { v[i] = Float(raw.load(fromByteOffset: i * 8, as: Double.self)) }
            default: break
            }
        }
        return normalized(v)
    }

    static func normalized(_ v: [Float]) -> [Float] {
        var norm: Float = 0; vDSP_svesq(v, 1, &norm, vDSP_Length(v.count)); norm = sqrt(norm)
        guard norm > 0 else { return v }
        var out = [Float](repeating: 0, count: v.count); var d = norm
        vDSP_vsdiv(v, 1, &d, &out, 1, vDSP_Length(v.count))
        return out
    }
    static func quantize(_ v: [Float]) -> Data {
        // les composantes d'un vecteur normalisé de grande dimension sont petites : on les étire avant d'arrondir
        Data(v.map { UInt8(bitPattern: Int8(max(-127, min(127, ($0 * 127 * 8).rounded())))) })
    }
    static func dequantize(_ d: Data) -> [Float] { normalized(d.map { Float(Int8(bitPattern: $0)) / (127 * 8) }) }
}
